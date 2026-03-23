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
        var nextRequestID: Int = 1
        var pendingResponses: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
        var readTask: Task<Void, Never>?
        var retryCount: Int = 0
    }

    private var runtimes: [String: Runtime] = [:]
    private static let maxRetries = 5
    private static let retryDelayNS: UInt64 = 2_000_000_000

    func snapshot(for definition: MCPServerDefinition) -> MCPServerSnapshot {
        let runtime = runtimes[definition.id]
        return MCPServerSnapshot(
            status: runtime?.status ?? .stopped,
            toolCount: runtime?.tools.count ?? 0,
            tools: runtime?.tools ?? [],
            recentLogs: runtime?.logs ?? [],
            lastError: runtime?.lastError
        )
    }

    func start(_ definition: MCPServerDefinition, cwd: URL?) {
        stop(definition.id)

        var runtime = Runtime(definition: definition)

        switch definition.transport {
        case .stdio:
            guard let command = definition.command else {
                runtime.status = .error
                runtime.lastError = "Missing stdio command"
                runtimes[definition.id] = runtime
                return
            }
            
            // Check for required environment variables
            if definition.id == "github" {
                let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
                if token == nil || token!.isEmpty {
                    runtime.status = .error
                    runtime.lastError = "GITHUB_TOKEN environment variable not set"
                    runtimes[definition.id] = runtime
                    return
                }
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

            let resolvedURL = resolveExecutable(command)
            if resolvedURL.path == "/usr/bin/env" {
                // env fallback: pass the command name as first arg so env can find it
                process.executableURL = resolvedURL
                process.arguments = [command] + resolvedArgs
            } else {
                process.executableURL = resolvedURL
                process.arguments = resolvedArgs
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.appendLog(line, serverID: definition.id)
                }
            }

            process.terminationHandler = { [weak self] proc in
                Task { @MainActor [weak self] in
                    self?.handleTermination(serverID: definition.id, exitCode: proc.terminationStatus, cwd: cwd)
                }
            }

            // Ensure child process has a rich PATH for finding node/npx etc.
            var env = ProcessInfo.processInfo.environment
            let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.volta/bin"]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
            process.environment = env

            do {
                Log.debug("mcp", "Starting \(definition.name): \(process.executableURL?.path ?? "?") \(process.arguments ?? [])")
                try process.run()
                runtime.process = process
                runtime.stdinPipe = stdinPipe
                runtime.stdoutPipe = stdoutPipe
                runtime.stderrPipe = stderrPipe
                runtime.status = .running
                runtimes[definition.id] = runtime

                startReadLoop(serverID: definition.id)
                Task.detached { [weak self] in
                    await self?.initializeServer(serverID: definition.id)
                }
            } catch {
                runtime.status = .error
                runtime.lastError = error.localizedDescription
                runtimes[definition.id] = runtime
            }

        case .sse:
            runtime.status = URL(string: definition.endpoint ?? "") == nil ? .error : .running
            runtime.lastError = runtime.status == .error ? "Invalid SSE endpoint" : nil
            runtimes[definition.id] = runtime
        }
    }

    func stop(_ serverID: String) {
        guard var runtime = runtimes[serverID] else { return }
        runtime.readTask?.cancel()
        runtime.readTask = nil
        runtime.stderrPipe?.fileHandleForReading.readabilityHandler = nil
        // Cancel all pending continuations
        for (_, continuation) in runtime.pendingResponses {
            continuation.resume(throwing: MCPError.serverStopped)
        }
        runtime.pendingResponses.removeAll()
        runtime.process?.terminate()
        runtime.status = .stopped
        runtime.process = nil
        runtime.stdinPipe = nil
        runtime.stdoutPipe = nil
        runtime.stderrPipe = nil
        runtime.retryCount = 0
        runtimes[serverID] = runtime
    }

    func restart(_ definition: MCPServerDefinition, cwd: URL?) {
        stop(definition.id)
        start(definition, cwd: cwd)
    }

    func toolList() -> [MCPToolDescriptor] {
        runtimes.values.flatMap { $0.tools }
    }

    /// Tool schemas suitable for passing to AI provider APIs
    func toolSchemas() -> [ToolSchema] {
        toolList().map { $0.toToolSchema() }
    }

    /// Call a tool on the appropriate MCP server
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        // Find which server owns this tool
        guard let (serverID, _) = runtimes.first(where: { _, runtime in
            runtime.tools.contains(where: { $0.name == name })
        }) else {
            throw MCPError.toolNotFound(name)
        }

        let params: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]
        let response = try await sendRequest(serverID: serverID, method: "tools/call", params: params)

        if let error = response.error {
            throw MCPError.serverError(error["message"] as? String ?? "Unknown error")
        }

        // Extract text content from result
        if let result = response.result,
           let content = result["content"] as? [[String: Any]] {
            return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }

        return response.result.flatMap { String(describing: $0) } ?? ""
    }

    /// Answer a query using MCP tools if possible
    func localFilesystemAnswer(question: String, cwd: URL?) -> String? {
        // If filesystem server is running and we can call tools, return nil to let AI handle it
        // This is a fallback for when the full tool calling isn't available
        guard let runtime = runtimes["filesystem"], runtime.status == .running, let cwd else { return nil }
        let lowercased = question.lowercased()

        if lowercased.contains("how many") {
            // Try to extract file extension
            let extensions: [(String, String)] = [
                ("js files", "js"), ("javascript files", "js"),
                ("swift files", "swift"),
                ("python files", "py"), ("py files", "py"),
                ("typescript files", "ts"), ("ts files", "ts"),
                ("rust files", "rs"),
                ("go files", "go"),
                ("java files", "java"),
                ("css files", "css"),
                ("html files", "html"),
            ]
            for (pattern, ext) in extensions {
                if lowercased.contains(pattern) {
                    let count = countFiles(withExtensions: [ext], in: cwd)
                    return "Filesystem MCP tool reports \(count) `.\(ext)` files in \(cwd.lastPathComponent)."
                }
            }
        }

        return nil
    }

    // MARK: - JSON-RPC 2.0 Protocol

    private func initializeServer(serverID: String) async {
        do {
            let initParams: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": [String: Any](),
                "clientInfo": ["name": "aTerm", "version": "0.1.0"]
            ]
            let response = try await sendRequest(serverID: serverID, method: "initialize", params: initParams)

            if response.error != nil {
                appendLog("Initialize error: \(response.error ?? [:])", serverID: serverID)
                return
            }

            // Send initialized notification
            sendNotification(serverID: serverID, method: "notifications/initialized", params: nil)

            // Discover tools
            let toolsResponse = try await sendRequest(serverID: serverID, method: "tools/list", params: [:])
            if let result = toolsResponse.result,
               let toolsList = result["tools"] as? [[String: Any]] {
                let tools = toolsList.compactMap { dict -> MCPToolDescriptor? in
                    guard let name = dict["name"] as? String else { return nil }
                    let description = dict["description"] as? String ?? ""
                    let inputSchema = dict["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [String: Any]()]
                    return MCPToolDescriptor(id: "\(serverID).\(name)", serverID: serverID, name: name, toolDescription: description, inputSchema: inputSchema)
                }
                runtimes[serverID]?.tools = tools
                appendLog("Discovered \(tools.count) tools", serverID: serverID)
            }
        } catch {
            appendLog("Initialize failed: \(error.localizedDescription)", serverID: serverID)
        }
    }

    private func sendRequest(serverID: String, method: String, params: [String: Any]) async throws -> JSONRPCResponse {
        guard var runtime = runtimes[serverID], let stdinPipe = runtime.stdinPipe else {
            throw MCPError.serverNotRunning
        }

        let requestID = runtime.nextRequestID
        runtime.nextRequestID += 1
        runtimes[serverID] = runtime

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: message)
        var payload = data
        payload.append(contentsOf: "\n".utf8)

        // Write to stdin on a background queue to avoid blocking the main thread
        let pipe = stdinPipe
        let payloadToSend = payload
        return try await withCheckedThrowingContinuation { continuation in
            runtimes[serverID]?.pendingResponses[requestID] = continuation
            DispatchQueue.global(qos: .userInitiated).async {
                pipe.fileHandleForWriting.write(payloadToSend)
            }

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let cont = self.runtimes[serverID]?.pendingResponses.removeValue(forKey: requestID) {
                    cont.resume(throwing: MCPError.timeout)
                }
            }
        }
    }

    private func sendNotification(serverID: String, method: String, params: [String: Any]?) {
        guard let stdinPipe = runtimes[serverID]?.stdinPipe else { return }

        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let params { message["params"] = params }

        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        var payload = data
        payload.append(contentsOf: "\n".utf8)
        let payloadToSend = payload
        let pipe = stdinPipe
        DispatchQueue.global(qos: .userInitiated).async {
            pipe.fileHandleForWriting.write(payloadToSend)
        }
    }

    private func startReadLoop(serverID: String) {
        guard let stdoutPipe = runtimes[serverID]?.stdoutPipe else { return }

        // MUST use detached task — availableData blocks, and MCPHost is @MainActor
        let task = Task.detached { [weak self] in
            let handle = stdoutPipe.fileHandleForReading
            var lineBuffer = Data()

            while !Task.isCancelled {
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    continue
                }

                lineBuffer.append(chunk)

                while let newlineIndex = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = lineBuffer[lineBuffer.startIndex..<newlineIndex]
                    lineBuffer = Data(lineBuffer[(newlineIndex + 1)...])

                    guard !lineData.isEmpty else { continue }
                    await self?.handleServerMessage(lineData, serverID: serverID)
                }
            }
        }

        runtimes[serverID]?.readTask = task
    }

    private func handleServerMessage(_ data: Data, serverID: String) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Check if this is a response (has "id")
        if let id = json["id"] as? Int {
            let response = JSONRPCResponse(
                id: id,
                result: json["result"] as? [String: Any],
                error: json["error"] as? [String: Any]
            )
            if let continuation = runtimes[serverID]?.pendingResponses.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }
            return
        }

        // It's a notification from the server
        if let method = json["method"] as? String {
            appendLog("Server notification: \(method)", serverID: serverID)
        }
    }

    // MARK: - Reconnection

    private func handleTermination(serverID: String, exitCode: Int32, cwd: URL?) {
        guard var runtime = runtimes[serverID] else { return }

        // Cancel pending requests
        for (_, continuation) in runtime.pendingResponses {
            continuation.resume(throwing: MCPError.serverCrashed)
        }
        runtime.pendingResponses.removeAll()
        runtime.readTask?.cancel()
        runtime.readTask = nil

        if exitCode == 0 {
            runtime.status = .stopped
            runtime.lastError = nil
            runtimes[serverID] = runtime
            return
        }

        runtime.retryCount += 1
        runtime.status = .error
        runtime.lastError = "Exited with code \(exitCode)"
        runtimes[serverID] = runtime

        if runtime.retryCount <= Self.maxRetries {
            let definition = runtime.definition
            let attempt = runtime.retryCount
            appendLog("Server crashed (exit \(exitCode)), reconnecting in 2s (attempt \(attempt)/\(Self.maxRetries))...", serverID: serverID)

            Task {
                try? await Task.sleep(nanoseconds: Self.retryDelayNS)
                guard !Task.isCancelled else { return }
                // Preserve retry count across restart
                let currentRetry = self.runtimes[serverID]?.retryCount ?? 0
                self.start(definition, cwd: cwd)
                self.runtimes[serverID]?.retryCount = currentRetry
                self.appendLog("[\(definition.name) restarted]", serverID: serverID)
            }
        } else {
            appendLog("Server crashed \(Self.maxRetries) times, giving up.", serverID: serverID)
        }
    }

    // MARK: - Helpers

    private func appendLog(_ text: String, serverID: String) {
        guard var runtime = runtimes[serverID] else { return }
        let lines = text.split(separator: "\n").map(String.init)
        runtime.logs.append(contentsOf: lines)
        if runtime.logs.count > 50 {
            runtime.logs.removeFirst(runtime.logs.count - 50)
        }
        runtimes[serverID] = runtime
    }

    private func resolveExecutable(_ command: String) -> URL {
        if command.hasPrefix("/") {
            return URL(fileURLWithPath: command)
        }

        // Search PATH with common additional directories where node/npx live
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin",  // nvm
            "\(NSHomeDirectory())/.volta/bin",                 // volta
            "\(NSHomeDirectory())/.local/bin",
            "/usr/bin",
        ]

        var searchPaths = envPath.split(separator: ":").map(String.init)
        for extra in extraPaths {
            if extra.contains("*") {
                // Glob expansion for nvm-style paths
                let base = (extra as NSString).deletingLastPathComponent
                let suffix = (extra as NSString).lastPathComponent
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: base) {
                    for dir in contents {
                        let candidate = "\(base)/\(dir)/\(suffix)"
                        if !searchPaths.contains(candidate) { searchPaths.append(candidate) }
                    }
                }
            } else if !searchPaths.contains(extra) {
                searchPaths.append(extra)
            }
        }

        for path in searchPaths {
            let fullPath = URL(fileURLWithPath: path).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: fullPath.path) {
                return fullPath
            }
        }

        // Fallback: use /usr/bin/env which will search the shell's PATH
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

// MARK: - Types

struct JSONRPCResponse {
    let id: Int
    let result: [String: Any]?
    let error: [String: Any]?
}

enum MCPError: LocalizedError {
    case serverNotRunning
    case serverStopped
    case serverCrashed
    case timeout
    case toolNotFound(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverNotRunning: return "MCP server is not running."
        case .serverStopped: return "MCP server was stopped."
        case .serverCrashed: return "MCP server crashed."
        case .timeout: return "MCP request timed out."
        case .toolNotFound(let name): return "MCP tool '\(name)' not found on any server."
        case .serverError(let msg): return "MCP server error: \(msg)"
        }
    }
}
