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
        .init(id: "kimi-code", name: "Kimi Code", command: "kimi-code", args: [], authEnvVar: "KIMI_API_KEY", installCheck: "which kimi-code", installHint: "Install Kimi Code and ensure `kimi-code` is on PATH.", protocolType: .interactiveCLI, isBuiltin: true),
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
        Dictionary(uniqueKeysWithValues: definitions.map { definition in
            let path = resolve(command: definition.command)
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

    private func resolve(command: String) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }

        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for path in searchPaths {
            let fullPath = URL(fileURLWithPath: path).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }
}
