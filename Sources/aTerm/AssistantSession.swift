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
