import Foundation

struct QueryCommandSuggestion: Identifiable, Hashable {
    let id = UUID()
    let command: String
}

struct QueryResponseState {
    var text = ""
    var isStreaming = false
    var suggestions: [QueryCommandSuggestion] = []
}

struct AIShellState {
    var originalPrompt = ""
    var generatedCommand = ""
    var isGenerating = false
    var isEditing = false
}

enum InputSubmissionState {
    case idle
    case waitingForDisambiguation(String)
}

// MARK: - Tool Calling Types

/// A tool call parsed from an AI provider response
struct ToolCallRequest: @unchecked Sendable {
    let id: String
    let name: String
    let arguments: [String: Any]  // JSON-safe values only
}

/// Events yielded during streaming with tool support
enum StreamEvent: Sendable {
    case text(String)
    case toolCall(ToolCallRequest)
}

/// A completed tool call with its result, ready to send back to the provider
struct ToolCallResult {
    let toolCallID: String
    let name: String
    let content: String
}

// MARK: - Rich Message for API Requests

/// Richer message type that supports tool call/result content for multi-turn tool use.
/// Used when building API requests; ConversationHistory stores these for proper round-trips.
struct RichMessage {
    let role: String
    /// Text content (may be empty for pure tool-call assistant messages)
    let text: String
    /// Tool calls made by the assistant (non-empty only for role == "assistant")
    var toolCalls: [ToolCallRequest]
    /// Tool results provided back to the model (non-empty only for role == "user" or "tool")
    var toolResults: [ToolCallResult]

    init(role: String, text: String, toolCalls: [ToolCallRequest] = [], toolResults: [ToolCallResult] = []) {
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }

    /// Convert to the dict format used in API request bodies for a given provider format
    func toOpenAIDicts() -> [[String: Any]] {
        if role == "assistant" && !toolCalls.isEmpty {
            var msg: [String: Any] = ["role": "assistant"]
            if !text.isEmpty { msg["content"] = text }
            msg["tool_calls"] = toolCalls.map { call -> [String: Any] in
                let argsJSON = (try? JSONSerialization.data(withJSONObject: call.arguments))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                return [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": argsJSON]
                ]
            }
            // Each tool result is a separate message for OpenAI
            var msgs = [msg]
            for result in toolResults {
                msgs.append(["role": "tool", "tool_call_id": result.toolCallID, "content": result.content])
            }
            return msgs
        }
        return [["role": role, "content": text]]
    }

    func toAnthropicDicts() -> [[String: Any]] {
        if role == "assistant" && !toolCalls.isEmpty {
            var contentBlocks: [[String: Any]] = []
            if !text.isEmpty {
                contentBlocks.append(["type": "text", "text": text])
            }
            for call in toolCalls {
                contentBlocks.append(["type": "tool_use", "id": call.id, "name": call.name, "input": call.arguments])
            }
            var msgs: [[String: Any]] = [["role": "assistant", "content": contentBlocks]]
            // Tool results go in a user message for Anthropic
            if !toolResults.isEmpty {
                let resultBlocks: [[String: Any]] = toolResults.map { result in
                    ["type": "tool_result", "tool_use_id": result.toolCallID, "content": result.content]
                }
                msgs.append(["role": "user", "content": resultBlocks])
            }
            return msgs
        }
        if role == "system" { return [] } // system handled separately for Anthropic
        return [["role": role == "assistant" ? "assistant" : "user", "content": text]]
    }
}

/// Maintains conversation history for multi-turn AI queries per pane
@MainActor
final class ConversationHistory {
    private(set) var messages: [RichMessage] = []
    private let maxMessages = 20

    /// Flat ChatMessage array for simple (non-tool) API calls
    var simplifiedMessages: [ChatMessage] {
        messages.map { ChatMessage(role: $0.role, content: $0.text) }
    }

    func addSystemMessage(_ content: String) {
        messages.removeAll { $0.role == "system" }
        messages.insert(RichMessage(role: "system", text: content), at: 0)
    }

    func addUserMessage(_ content: String) {
        messages.append(RichMessage(role: "user", text: content))
        trimIfNeeded()
    }

    func addAssistantMessage(_ content: String) {
        messages.append(RichMessage(role: "assistant", text: content))
        trimIfNeeded()
    }

    func addAssistantToolCallMessage(text: String, toolCalls: [ToolCallRequest], toolResults: [ToolCallResult]) {
        messages.append(RichMessage(role: "assistant", text: text, toolCalls: toolCalls, toolResults: toolResults))
        trimIfNeeded()
    }

    func clear() {
        messages.removeAll()
    }

    private func trimIfNeeded() {
        let nonSystem = messages.filter { $0.role != "system" }
        if nonSystem.count > maxMessages {
            let system = messages.first { $0.role == "system" }
            let kept = Array(nonSystem.suffix(maxMessages))
            messages = (system.map { [$0] } ?? []) + kept
        }
    }
}

/// Tool schema for AI providers
struct ToolSchema {
    let name: String
    let description: String
    let parameters: [String: Any]  // JSON Schema

    func toOpenAIFormat() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        ]
    }

    func toAnthropicFormat() -> [String: Any] {
        [
            "name": name,
            "description": description,
            "input_schema": parameters
        ]
    }
}
