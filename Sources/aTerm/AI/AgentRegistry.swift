import Foundation

enum AgentProtocol: String, Codable, CaseIterable, Identifiable {
    case interactiveCLI

    var id: String { rawValue }
}

struct AgentDefinition: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var command: String
    var args: [String]
    var authEnvVar: String
    var installCheck: String
    var installHint: String
    var protocolType: AgentProtocol
    var isBuiltin: Bool
}

struct AgentInstallationStatus: Hashable {
    let definitionID: String
    let executablePath: String?
    let isInstalled: Bool
}

enum BuiltinAgents {
    static let all: [AgentDefinition] = [
        .init(id: "claude-code", name: "Claude Code", command: "claude", args: [], authEnvVar: "ANTHROPIC_API_KEY", installCheck: "which claude", installHint: "npm install -g @anthropic-ai/claude-code", protocolType: .interactiveCLI, isBuiltin: true),
        .init(id: "kimi-code", name: "Kimi Code", command: "kimi", args: [], authEnvVar: "KIMI_API_KEY", installCheck: "which kimi", installHint: "Install Kimi Code (`kimi` on PATH; legacy installs may use `kimi-code`).", protocolType: .interactiveCLI, isBuiltin: true),
        .init(id: "openai-codex", name: "OpenAI Codex", command: "codex", args: [], authEnvVar: "OPENAI_API_KEY", installCheck: "which codex", installHint: "Install Codex CLI and ensure `codex` is on PATH.", protocolType: .interactiveCLI, isBuiltin: true),
        .init(id: "openclaw", name: "OpenClaw", command: "openclaw", args: [], authEnvVar: "OPENCLAW_API_KEY", installCheck: "which openclaw", installHint: "Install OpenClaw and ensure `openclaw` is on PATH.", protocolType: .interactiveCLI, isBuiltin: true),
        .init(id: "aider", name: "Aider", command: "aider", args: [], authEnvVar: "OPENAI_API_KEY", installCheck: "which aider", installHint: "pipx install aider-chat", protocolType: .interactiveCLI, isBuiltin: true),
    ]
}

struct AgentStore {
    struct StoredAgents: Codable {
        var agents: [AgentDefinition]
        var defaultAgentID: String?
    }

    private let fileManager = FileManager.default

    func load() -> StoredAgents? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(StoredAgents.self, from: data)
    }

    func save(_ agents: StoredAgents) {
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(agents)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to save agents: \(error)\n", stderr)
        }
    }

    private var storageURL: URL {
        AppSupport.baseURL.appendingPathComponent("agents.json")
    }
}

struct AgentDetector {
    func detect(_ definitions: [AgentDefinition]) -> [String: AgentInstallationStatus] {
        let searchPaths = Self.searchPathComponents()
        return Dictionary(uniqueKeysWithValues: definitions.map { definition in
            let path = Self.resolve(definition: definition, searchPaths: searchPaths)
            return (
                definition.id,
                AgentInstallationStatus(
                    definitionID: definition.id,
                    executablePath: path,
                    isInstalled: path != nil
                )
            )
        })
    }

    /// PATH entries for finding user-installed CLIs when aTerm runs as a GUI app (launchd supplies a minimal PATH).
    private static func searchPathComponents() -> [String] {
        var components: [String] = []
        if let helper = pathHelperPATH() {
            components.append(contentsOf: helper.split(separator: ":").map(String.init))
        }
        let home = NSHomeDirectory()
        let extras = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
            "\(home)/bin",
            "\(home)/.kimi/bin",
            "\(home)/.cargo/bin",
        ]
        components.append(contentsOf: extras)
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        components.append(contentsOf: envPath.split(separator: ":").map(String.init))

        var seen = Set<String>()
        var ordered: [String] = []
        for raw in components {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func pathHelperPATH() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/path_helper")
        process.arguments = ["-s"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8),
              let marker = out.range(of: "PATH=\"") else { return nil }
        let after = out[marker.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        return String(after[..<end])
    }

    private static func executableNames(for definition: AgentDefinition) -> [String] {
        switch definition.id {
        case "kimi-code":
            return ["kimi", "kimi-code"]
        default:
            return [definition.command]
        }
    }

    private static func resolve(definition: AgentDefinition, searchPaths: [String]) -> String? {
        for name in executableNames(for: definition) {
            if let path = resolveExecutable(named: name, searchPaths: searchPaths) {
                return path
            }
        }
        return nil
    }

    private static func resolveExecutable(named command: String, searchPaths: [String]) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }

        for path in searchPaths {
            let fullPath = URL(fileURLWithPath: path).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }
}
