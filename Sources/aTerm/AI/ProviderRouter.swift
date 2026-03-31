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
    var oauthManager: OAuthManager?

    func testConnection(provider: ModelProvider) async throws -> ProviderTestResult {
        let modelID = provider.models.first?.id ?? defaultModelID(for: provider)
        let body = try makeRequestBody(provider: provider, modelID: modelID, messages: [ChatMessage(role: "user", content: "Respond with the single word pong.")], stream: false)
        let request = try await buildRequestAsync(provider: provider, body: body)

        let start = Date()
        let (data, _) = try await URLSession.shared.data(for: request)
        let latencyMS = Int(Date().timeIntervalSince(start) * 1000)
        let message = try parseResponseMessage(data: data, provider: provider)
        return ProviderTestResult(latencyMS: latencyMS, message: message)
    }

    // MARK: - Simple streaming (text only, no tools)

    func streamResponse(provider: ModelProvider, modelID: String, messages: [ChatMessage]) throws -> AsyncThrowingStream<String, Error> {
        let body = try makeRequestBody(provider: provider, modelID: modelID, messages: messages, stream: true)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await self.buildRequestAsync(provider: provider, body: body)
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

    // MARK: - Streaming with tool support

    func streamWithTools(
        provider: ModelProvider,
        modelID: String,
        richMessages: [RichMessage],
        tools: [ToolSchema]
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        // Build request body eagerly to avoid capturing non-Sendable types in the Task closure
        let body = try makeRichRequestBody(
            provider: provider, modelID: modelID,
            richMessages: richMessages, tools: tools, stream: true
        )
        let apiFormat = provider.apiFormat

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await self.buildRequestAsync(provider: provider, body: body)
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    // Accumulators for in-progress tool calls
                    var pendingToolCalls: [Int: (id: String, name: String, argsJSON: String)] = [:]
                    // Anthropic-specific accumulators
                    var anthropicCurrentBlockIndex: Int?
                    var anthropicToolID = ""
                    var anthropicToolName = ""
                    var anthropicToolArgs = ""

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        switch apiFormat {
                        case .openAICompatible, .custom:
                            // Parse OpenAI streaming format
                            if let choices = dict["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any] {
                                // Text content
                                if let content = delta["content"] as? String {
                                    continuation.yield(.text(content))
                                }
                                // Tool calls (accumulated across chunks)
                                if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                                    for tc in toolCalls {
                                        let index = tc["index"] as? Int ?? 0
                                        if let id = tc["id"] as? String {
                                            // New tool call starting
                                            let funcDict = tc["function"] as? [String: Any] ?? [:]
                                            let name = funcDict["name"] as? String ?? ""
                                            let args = funcDict["arguments"] as? String ?? ""
                                            pendingToolCalls[index] = (id: id, name: name, argsJSON: args)
                                        } else if let funcDict = tc["function"] as? [String: Any],
                                                  let argChunk = funcDict["arguments"] as? String {
                                            // Continuation of arguments
                                            pendingToolCalls[index]?.argsJSON.append(argChunk)
                                        }
                                    }
                                }
                                // Check finish_reason
                                if let finishReason = choices.first?["finish_reason"] as? String,
                                   finishReason == "tool_calls" || finishReason == "stop" {
                                    // Emit completed tool calls
                                    for (_, tc) in pendingToolCalls.sorted(by: { $0.key < $1.key }) {
                                        let args = parseJSONArguments(tc.argsJSON)
                                        continuation.yield(.toolCall(ToolCallRequest(id: tc.id, name: tc.name, arguments: args)))
                                    }
                                    pendingToolCalls.removeAll()
                                }
                            }

                        case .anthropic:
                            let eventType = dict["type"] as? String ?? ""

                            switch eventType {
                            case "content_block_start":
                                if let block = dict["content_block"] as? [String: Any],
                                   let blockType = block["type"] as? String {
                                    let index = dict["index"] as? Int ?? 0
                                    if blockType == "tool_use" {
                                        anthropicCurrentBlockIndex = index
                                        anthropicToolID = block["id"] as? String ?? ""
                                        anthropicToolName = block["name"] as? String ?? ""
                                        anthropicToolArgs = ""
                                    }
                                }

                            case "content_block_delta":
                                if let delta = dict["delta"] as? [String: Any] {
                                    let deltaType = delta["type"] as? String ?? ""
                                    if deltaType == "text_delta", let text = delta["text"] as? String {
                                        continuation.yield(.text(text))
                                    } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                                        anthropicToolArgs.append(partial)
                                    }
                                }

                            case "content_block_stop":
                                if let index = dict["index"] as? Int, index == anthropicCurrentBlockIndex {
                                    // Tool call block complete
                                    let args = parseJSONArguments(anthropicToolArgs)
                                    continuation.yield(.toolCall(ToolCallRequest(
                                        id: anthropicToolID, name: anthropicToolName, arguments: args
                                    )))
                                    anthropicCurrentBlockIndex = nil
                                }

                            default:
                                break
                            }

                        case .gemini:
                            // Gemini: extract text only (tool calling not supported yet)
                            if let candidates = dict["candidates"] as? [[String: Any]],
                               let content = candidates.first?["content"] as? [String: Any],
                               let parts = content["parts"] as? [[String: Any]],
                               let text = parts.first?["text"] as? String {
                                continuation.yield(.text(text))
                            }
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

    // MARK: - Non-streaming completion

    func complete(provider: ModelProvider, modelID: String, messages: [ChatMessage]) async throws -> String {
        let body = try makeRequestBody(provider: provider, modelID: modelID, messages: messages, stream: false)
        let request = try await buildRequestAsync(provider: provider, body: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseResponseMessage(data: data, provider: provider)
    }

    // MARK: - Request Building

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

        // Anthropic requires a version header
        if provider.apiFormat == .anthropic {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        try applyAuth(to: &request, provider: provider)
        return request
    }

    private func applyAuth(to request: inout URLRequest, provider: ModelProvider) throws {
        guard provider.authType != .none else { return }

        // For OAuth providers, try the cached/refreshed OAuth token first
        if provider.authType == .oauthToken, provider.oauthConfig != nil {
            // OAuth token will be applied asynchronously via applyAuthAsync
            // This path is for non-async callers that already set the token
            if let secret = try keychainStore.readSecret(account: provider.id), !secret.isEmpty {
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                return
            }
            throw ProviderRouterError.missingCredential(provider.name)
        }

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
        case .queryParam:
            if let url = request.url,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                var queryItems = components.queryItems ?? []
                queryItems.append(URLQueryItem(name: "key", value: secret))
                components.queryItems = queryItems
                request.url = components.url
            }
        case .none:
            break
        }
    }

    /// Async version of auth application — refreshes OAuth tokens automatically
    private func applyAuthAsync(to request: inout URLRequest, provider: ModelProvider) async throws {
        guard provider.authType != .none else { return }

        if provider.authType == .oauthToken, let oauthManager, provider.oauthConfig != nil {
            let token = try await oauthManager.validAccessToken(for: provider)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return
        }

        try applyAuth(to: &request, provider: provider)
    }

    /// Build request with async auth (for OAuth token refresh)
    func buildRequestAsync(provider: ModelProvider, body: Data) async throws -> URLRequest {
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

        if provider.apiFormat == .anthropic {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        try await applyAuthAsync(to: &request, provider: provider)
        return request
    }

    /// Simple request body for non-tool calls (ChatMessage based)
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
                "messages": anthropicMessages,
            ]
            // Only include system if it has a value (Anthropic API rejects null)
            if let system, !system.isEmpty {
                body["system"] = system
            }
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

    /// Rich request body that supports tool call/result messages
    func makeRichRequestBody(
        provider: ModelProvider, modelID: String,
        richMessages: [RichMessage], tools: [ToolSchema], stream: Bool
    ) throws -> Data {
        switch provider.apiFormat {
        case .openAICompatible, .custom:
            let msgs: [[String: Any]] = richMessages.flatMap { $0.toOpenAIDicts() }
            var body: [String: Any] = [
                "model": modelID,
                "messages": msgs,
                "stream": stream,
            ]
            if !tools.isEmpty {
                body["tools"] = tools.map { $0.toOpenAIFormat() }
            }
            return try JSONSerialization.data(withJSONObject: body)

        case .anthropic:
            let system = richMessages.first(where: { $0.role == "system" })?.text
            let msgs: [[String: Any]] = richMessages
                .filter { $0.role != "system" }
                .flatMap { $0.toAnthropicDicts() }
            var body: [String: Any] = [
                "model": modelID,
                "max_tokens": 4096,
                "stream": stream,
                "messages": msgs,
            ]
            if let system, !system.isEmpty {
                body["system"] = system
            }
            if !tools.isEmpty {
                body["tools"] = tools.map { $0.toAnthropicFormat() }
            }
            return try JSONSerialization.data(withJSONObject: body)

        case .gemini:
            let prompt = richMessages.map(\.text).joined(separator: "\n\n")
            return try JSONSerialization.data(withJSONObject: [
                "contents": [
                    ["role": "user", "parts": [["text": prompt]]]
                ]
            ])
        }
    }

    // MARK: - Response Parsing

    private func parseResponseMessage(data: Data, provider: ModelProvider) throws -> String {
        // First check if it's valid JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            // Not valid JSON - might be HTML error page
            let raw = String(data: data.prefix(500), encoding: .utf8) ?? "unparseable"
            if raw.contains("<!DOCTYPE") || raw.contains("<html") {
                return "HTTP error (check endpoint URL)"
            }
            return "Invalid response: \(raw.prefix(100))"
        }
        
        guard let dictionary = json as? [String: Any] else {
            // Valid JSON but not a dictionary (e.g., array or primitive)
            let raw = String(data: data.prefix(200), encoding: .utf8) ?? "unparseable"
            return "Unexpected response format: \(raw)"
        }

        // Check for API error responses first
        if let error = dictionary["error"] as? [String: Any],
           let message = error["message"] as? String {
            return "API error: \(message)"
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
            // Anthropic error format
            if let type = dictionary["type"] as? String, type == "error",
               let error = dictionary["error"] as? [String: Any],
               let message = error["message"] as? String {
                return "API error: \(message)"
            }
        case .gemini:
            if let candidates = dictionary["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text
            }
        }

        // Last resort: return raw response for debugging
        let raw = String(data: data.prefix(200), encoding: .utf8) ?? "unparseable"
        return "Unexpected response: \(raw)"
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

    private func parseJSONArguments(_ jsonString: String) -> [String: Any] {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private func defaultModelID(for provider: ModelProvider) -> String {
        switch provider.id {
        case "anthropic": return "claude-sonnet-4-5"
        case "openai": return "gpt-5.4-mini"
        case "gemini": return "gemini-2.5-flash"
        default: return provider.models.first?.id ?? ""
        }
    }

    // MARK: - Fetch Available Models

    /// Fetches available models from an OpenAI-compatible /models endpoint
    func fetchModels(endpoint: String, apiKey: String?) async throws -> [ModelDefinition] {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProviderRouterError.invalidEndpoint
        }
        
        // Construct the models endpoint URL
        let modelsURL: URL
        if endpoint.hasSuffix("/chat/completions") {
            modelsURL = url.deletingLastPathComponent().appendingPathComponent("models")
        } else if endpoint.hasSuffix("/") {
            modelsURL = url.appendingPathComponent("models")
        } else {
            modelsURL = url.appendingPathComponent("models")
        }
        
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProviderRouterError.unexpectedResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["data"] as? [[String: Any]] else {
            throw ProviderRouterError.unexpectedResponse
        }
        
        return modelsArray.compactMap { modelDict -> ModelDefinition? in
            guard let id = modelDict["id"] as? String else { return nil }
            let name = modelDict["name"] as? String ?? id
            return ModelDefinition(
                id: id,
                name: name,
                contextWindow: 128_000,
                supportsStreaming: true
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
