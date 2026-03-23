import Foundation

struct ChatMessage: Codable, Hashable {
    let role: String
    let content: String
}

struct ProviderTestResult {
    let latencyMS: Int
    let message: String
}

enum ProviderRouterError: LocalizedError {
    case missingCredential(String)
    case invalidEndpoint
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case let .missingCredential(providerName):
            return "No credential stored for \(providerName)."
        case .invalidEndpoint:
            return "The provider endpoint URL is invalid."
        case .unexpectedResponse:
            return "The provider response could not be parsed."
        }
    }
}

struct ProviderRouter {
    private let keychainStore = KeychainStore()

    func testConnection(provider: ModelProvider) async throws -> ProviderTestResult {
        guard let request = try makeTestRequest(provider: provider) else {
            return ProviderTestResult(latencyMS: 0, message: "No authentication required.")
        }

        let start = Date()
        let (data, _) = try await URLSession.shared.data(for: request)
        let latencyMS = Int(Date().timeIntervalSince(start) * 1000)
        let message = try parseResponseMessage(data: data, provider: provider)
        return ProviderTestResult(latencyMS: latencyMS, message: message)
    }

    func streamResponse(provider: ModelProvider, modelID: String, messages: [ChatMessage]) throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeStreamingRequest(provider: provider, modelID: modelID, messages: messages)
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        if let chunk = parseStreamingChunk(String(payload), provider: provider) {
                            continuation.yield(chunk)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func complete(provider: ModelProvider, modelID: String, messages: [ChatMessage]) async throws -> String {
        let request = try makeCompletionRequest(provider: provider, modelID: modelID, messages: messages)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseResponseMessage(data: data, provider: provider)
    }

    private func makeTestRequest(provider: ModelProvider) throws -> URLRequest? {
        let modelID = provider.models.first?.id ?? defaultModelID(for: provider)
        let requestBody = try makeRequestBody(provider: provider, modelID: modelID, messages: [ChatMessage(role: "user", content: "Respond with the single word pong.")], stream: false)
        return try buildRequest(provider: provider, body: requestBody)
    }

    private func makeStreamingRequest(provider: ModelProvider, modelID: String, messages: [ChatMessage]) throws -> URLRequest {
        let body = try makeRequestBody(provider: provider, modelID: modelID, messages: messages, stream: true)
        return try buildRequest(provider: provider, body: body)
    }

    private func makeCompletionRequest(provider: ModelProvider, modelID: String, messages: [ChatMessage]) throws -> URLRequest {
        let body = try makeRequestBody(provider: provider, modelID: modelID, messages: messages, stream: false)
        return try buildRequest(provider: provider, body: body)
    }

    private func buildRequest(provider: ModelProvider, body: Data) throws -> URLRequest {
        guard let url = URL(string: provider.endpoint) else {
            throw ProviderRouterError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in provider.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        try applyAuth(to: &request, provider: provider)
        return request
    }

    private func applyAuth(to request: inout URLRequest, provider: ModelProvider) throws {
        guard provider.authType != .none else { return }
        guard let secret = try keychainStore.readSecret(account: provider.id), !secret.isEmpty else {
            throw ProviderRouterError.missingCredential(provider.name)
        }

        switch provider.authType {
        case .bearer:
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        case .xApiKey:
            request.setValue(secret, forHTTPHeaderField: "x-api-key")
        case .oauthToken:
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        case .none:
            break
        }
    }

    private func makeRequestBody(provider: ModelProvider, modelID: String, messages: [ChatMessage], stream: Bool, tools: [ToolSchema]? = nil) throws -> Data {
        switch provider.apiFormat {
        case .openAICompatible, .custom:
            var body: [String: Any] = [
                "model": modelID,
                "messages": messages.map { ["role": $0.role, "content": $0.content] },
                "stream": stream,
            ]
            if let tools, !tools.isEmpty {
                body["tools"] = tools.map { $0.toOpenAIFormat() }
            }
            return try JSONSerialization.data(withJSONObject: body)
        case .anthropic:
            let system = messages.first(where: { $0.role == "system" })?.content
            let anthropicMessages = messages
                .filter { $0.role != "system" }
                .map { ["role": $0.role == "assistant" ? "assistant" : "user", "content": $0.content] }
            var body: [String: Any] = [
                "model": modelID,
                "max_tokens": 4096,
                "stream": stream,
                "system": system as Any,
                "messages": anthropicMessages,
            ]
            if let tools, !tools.isEmpty {
                body["tools"] = tools.map { $0.toAnthropicFormat() }
            }
            return try JSONSerialization.data(withJSONObject: body)
        case .gemini:
            let prompt = messages.map(\.content).joined(separator: "\n\n")
            return try JSONSerialization.data(withJSONObject: [
                "contents": [
                    ["role": "user", "parts": [["text": prompt]]]
                ]
            ])
        }
    }

    private func parseResponseMessage(data: Data, provider: ModelProvider) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            throw ProviderRouterError.unexpectedResponse
        }

        switch provider.apiFormat {
        case .openAICompatible, .custom:
            if let choices = dictionary["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        case .anthropic:
            if let content = dictionary["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                return text
            }
        case .gemini:
            if let candidates = dictionary["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text
            }
        }

        throw ProviderRouterError.unexpectedResponse
    }

    private func parseStreamingChunk(_ payload: String, provider: ModelProvider) -> String? {
        guard let data = payload.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch provider.apiFormat {
        case .openAICompatible, .custom:
            let choices = dictionary["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            return delta?["content"] as? String
        case .anthropic:
            let type = dictionary["type"] as? String
            if type == "content_block_delta",
               let delta = dictionary["delta"] as? [String: Any] {
                return delta["text"] as? String
            }
            return nil
        case .gemini:
            let candidates = dictionary["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            return parts?.first?["text"] as? String
        }
    }

    private func defaultModelID(for provider: ModelProvider) -> String {
        switch provider.id {
        case "anthropic": return "claude-sonnet-4-5"
        case "openai": return "gpt-5.4-mini"
        case "gemini": return "gemini-2.5-flash"
        default: return provider.models.first?.id ?? ""
        }
    }
}
