import Foundation

enum MCPTransport: String, Codable, CaseIterable, Identifiable {
    case stdio
    case sse

    var id: String { rawValue }
}

enum MCPScope: String, Codable, CaseIterable, Identifiable {
    case global
    case perProject

    var id: String { rawValue }
}

struct MCPServerDefinition: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var transport: MCPTransport
    var command: String?
    var args: [String]
    var endpoint: String?
    var autoStart: Bool
    var scope: MCPScope
    var isBuiltin: Bool
}

struct MCPToolDescriptor: Identifiable, Hashable {
    let id: String
    let serverID: String
    let name: String
}

enum MCPServerStatus: String {
    case stopped
    case running
    case error
}

struct MCPServerSnapshot: Hashable {
    var status: MCPServerStatus
    var toolCount: Int
    var tools: [MCPToolDescriptor]
    var recentLogs: [String]
    var lastError: String?
}

enum BuiltinMCPServers {
    static let all: [MCPServerDefinition] = [
        .init(id: "filesystem", name: "filesystem", transport: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "{cwd}"], endpoint: nil, autoStart: true, scope: .perProject, isBuiltin: true),
        .init(id: "git", name: "git", transport: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-git", "--repository", "{cwd}"], endpoint: nil, autoStart: true, scope: .perProject, isBuiltin: true),
        .init(id: "github", name: "github", transport: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-github"], endpoint: nil, autoStart: false, scope: .global, isBuiltin: true),
        .init(id: "sqlite", name: "sqlite", transport: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-sqlite"], endpoint: nil, autoStart: false, scope: .global, isBuiltin: true),
        .init(id: "openclaw-mcp", name: "openclaw", transport: .stdio, command: "openclaw", args: ["serve"], endpoint: nil, autoStart: false, scope: .perProject, isBuiltin: true),
    ]
}

struct MCPStore {
    struct StoredServers: Codable {
        var servers: [MCPServerDefinition]
    }

    private let fileManager = FileManager.default

    func load() -> StoredServers? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(StoredServers.self, from: data)
    }

    func save(_ servers: StoredServers) {
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(servers)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to save MCP servers: \(error)\n", stderr)
        }
    }

    private var storageURL: URL {
        AppSupport.baseURL.appendingPathComponent("mcp-servers.json")
    }
}
