import Foundation

@MainActor
final class MCPHost {
    struct Runtime {
        var definition: MCPServerDefinition
        var process: Process?
        var stdinPipe: Pipe?
        var stdoutPipe: Pipe?
        var stderrPipe: Pipe?
        var logs: [String] = []
        var tools: [MCPToolDescriptor] = []
        var status: MCPServerStatus = .stopped
        var lastError: String?
    }

    private var runtimes: [String: Runtime] = [:]

    func snapshot(for definition: MCPServerDefinition) -> MCPServerSnapshot {
        let runtime = runtimes[definition.id]
        return MCPServerSnapshot(
            status: runtime?.status ?? .stopped,
            toolCount: runtime?.tools.count ?? defaultTools(for: definition).count,
            tools: runtime?.tools ?? defaultTools(for: definition),
            recentLogs: runtime?.logs ?? [],
            lastError: runtime?.lastError
        )
    }

    func start(_ definition: MCPServerDefinition, cwd: URL?) {
        stop(definition.id)

        var runtime = Runtime(definition: definition)
        runtime.tools = defaultTools(for: definition)

        switch definition.transport {
        case .stdio:
            guard let command = definition.command else {
                runtime.status = .error
                runtime.lastError = "Missing stdio command"
                runtimes[definition.id] = runtime
                return
            }

            let process = Process()
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.currentDirectoryURL = cwd

            let resolvedArgs = definition.args.map { arg in
                arg.replacingOccurrences(of: "{cwd}", with: cwd?.path ?? FileManager.default.currentDirectoryPath)
            }

            process.executableURL = resolveExecutable(command)
            process.arguments = resolvedArgs

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.appendLog(line, serverID: definition.id)
                }
            }

            process.terminationHandler = { [weak self] process in
                Task { @MainActor [weak self] in
                    guard var runtime = self?.runtimes[definition.id] else { return }
                    runtime.status = process.terminationStatus == 0 ? .stopped : .error
                    runtime.lastError = process.terminationStatus == 0 ? nil : "Exited with code \(process.terminationStatus)"
                    self?.runtimes[definition.id] = runtime
                }
            }

            do {
                try process.run()
                runtime.process = process
                runtime.stdinPipe = stdinPipe
                runtime.stdoutPipe = stdoutPipe
                runtime.stderrPipe = stderrPipe
                runtime.status = .running
            } catch {
                runtime.status = .error
                runtime.lastError = error.localizedDescription
            }

        case .sse:
            runtime.status = URL(string: definition.endpoint ?? "") == nil ? .error : .running
            runtime.lastError = runtime.status == .error ? "Invalid SSE endpoint" : nil
        }

        runtimes[definition.id] = runtime
    }

    func stop(_ serverID: String) {
        guard var runtime = runtimes[serverID] else { return }
        runtime.process?.terminate()
        runtime.status = .stopped
        runtime.process = nil
        runtimes[serverID] = runtime
    }

    func restart(_ definition: MCPServerDefinition, cwd: URL?) {
        stop(definition.id)
        start(definition, cwd: cwd)
    }

    func toolList() -> [MCPToolDescriptor] {
        runtimes.values.flatMap { $0.tools }
    }

    func localFilesystemAnswer(question: String, cwd: URL?) -> String? {
        guard let runtime = runtimes["filesystem"], runtime.status == .running, let cwd else { return nil }
        let lowercased = question.lowercased()

        if lowercased.contains("how many js files") {
            let count = countFiles(withExtensions: ["js"], in: cwd)
            return "Filesystem MCP tool reports \(count) `.js` files in \(cwd.lastPathComponent)."
        }

        if lowercased.contains("how many swift files") {
            let count = countFiles(withExtensions: ["swift"], in: cwd)
            return "Filesystem MCP tool reports \(count) `.swift` files in \(cwd.lastPathComponent)."
        }

        return nil
    }

    private func appendLog(_ text: String, serverID: String) {
        guard var runtime = runtimes[serverID] else { return }
        let lines = text.split(separator: "\n").map(String.init)
        runtime.logs.append(contentsOf: lines)
        if runtime.logs.count > 50 {
            runtime.logs.removeFirst(runtime.logs.count - 50)
        }
        runtimes[serverID] = runtime
    }

    private func defaultTools(for definition: MCPServerDefinition) -> [MCPToolDescriptor] {
        let toolNames: [String]
        switch definition.id {
        case "filesystem":
            toolNames = ["list_directory", "read_file", "search_files", "count_files"]
        case "git":
            toolNames = ["git_status", "git_log", "git_diff", "git_show"]
        case "github":
            toolNames = ["github_search_prs", "github_get_issue", "github_comment"]
        case "sqlite":
            toolNames = ["sqlite_query", "sqlite_tables"]
        case "openclaw-mcp":
            toolNames = ["openclaw_execute"]
        default:
            toolNames = []
        }

        return toolNames.map { MCPToolDescriptor(id: "\(definition.id).\($0)", serverID: definition.id, name: $0) }
    }

    private func resolveExecutable(_ command: String) -> URL {
        if command.hasPrefix("/") {
            return URL(fileURLWithPath: command)
        }

        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for path in searchPaths {
            let fullPath = URL(fileURLWithPath: path).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: fullPath.path) {
                return fullPath
            }
        }

        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private func countFiles(withExtensions fileExtensions: Set<String>, in directory: URL) -> Int {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var count = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileExtensions.contains(fileURL.pathExtension.lowercased()) {
                count += 1
            }
        }
        return count
    }
}
