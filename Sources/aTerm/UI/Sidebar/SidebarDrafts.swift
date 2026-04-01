import Foundation

struct MCPDraft {
    var id = ""
    var name = ""
    var endpoint = ""
    var autoStart = false
    var scope: MCPScope = .global

    func toDefinition() -> MCPServerDefinition {
        MCPServerDefinition(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            transport: .sse,
            command: nil,
            args: [],
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            autoStart: autoStart,
            scope: scope,
            isBuiltin: false
        )
    }
}
