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

/// Maintains conversation history for multi-turn AI queries per pane
@MainActor
final class ConversationHistory {
    private(set) var messages: [ChatMessage] = []
    private let maxMessages = 20

    func addSystemMessage(_ content: String) {
        // Only keep one system message (the latest)
        messages.removeAll { $0.role == "system" }
        messages.insert(ChatMessage(role: "system", content: content), at: 0)
    }

    func addUserMessage(_ content: String) {
        messages.append(ChatMessage(role: "user", content: content))
        trimIfNeeded()
    }

    func addAssistantMessage(_ content: String) {
        messages.append(ChatMessage(role: "assistant", content: content))
        trimIfNeeded()
    }

    func clear() {
        messages.removeAll()
    }

    private func trimIfNeeded() {
        // Keep system message + last N messages
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
