import Foundation

struct ProviderDraft {
    var id = ""
    var name = ""
    var endpoint = ""
    var authType: AuthType = .bearer
    var apiFormat: APIFormat = .openAICompatible
    var secret = ""
    var modelID = ""
    var modelName = ""
    var models: [ModelDefinition] = []

    mutating func addModel() {
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        models.append(.init(id: trimmedID, name: modelName, contextWindow: 128_000, supportsStreaming: true))
        modelID = ""
        modelName = ""
    }

    func toProvider() -> ModelProvider {
        // Auto-generate ID from name if ID is empty
        let finalID: String
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            finalID = trimmedName.lowercased().replacingOccurrences(of: " ", with: "-")
        } else {
            finalID = trimmedID.lowercased()
        }
        
        return ModelProvider(
            id: finalID.isEmpty ? UUID().uuidString : finalID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            authType: authType,
            apiFormat: apiFormat,
            models: models,
            customHeaders: [:],
            isBuiltin: false
        )
    }
}

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
