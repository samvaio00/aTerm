import Foundation

enum InputMode: String {
    case terminal = "TERMINAL"
    case aiToShell = "AI_TO_SHELL"
    case query = "QUERY"
}

struct ClassificationContext {
    let workingDirectory: URL?
    let lastCommands: [String]
    let lastOutputSnippet: String
}

enum InputClassifierError: LocalizedError {
    case noProvider

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "No configured model is available for classifier fallback."
        }
    }
}

@MainActor
final class InputClassifier {
    private let commandResolver = CommandResolver()
    private let queryPrefixes = [
        "what", "why", "how", "explain", "describe", "tell me", "what's",
        "whats", "what is", "what are", "why is", "why does", "how do",
        "how does", "how can", "can you explain", "could you explain"
    ]
    private let actionVerbs: Set<String> = [
        "find", "show", "list", "kill", "stop", "start", "restart", "move",
        "copy", "delete", "remove", "compress", "extract", "create", "make",
        "open", "check", "monitor", "watch", "tail", "grep", "search",
        "count", "sort", "display", "get", "look", "zip", "unzip", "generate",
        "archive"
    ]
    private let systemNouns: Set<String> = [
        "files", "file", "folder", "directory", "process", "port", "service",
        "logs", "disk", "memory", "cpu", "network", "connection", "socket",
        "permissions", "ownership", "symlink", "archive", "package", "backup",
        "this", "the", "all", "running", "errors"
    ]
    private let cache = NSCache<NSString, NSString>()
    private let providerRouter = ProviderRouter()

    func classify(_ input: String, context: ClassificationContext, provider: ModelProvider?, modelID: String?) async throws -> InputMode? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .terminal }

        if let forced = forcedMode(for: trimmed) {
            return forced
        }

        // Check for query patterns first (before terminal commands)
        // This ensures "what is git?" is classified as query even though "what" is a command
        if looksLikeQuery(trimmed) {
            return .query
        }

        if looksLikeTerminal(trimmed, workingDirectory: context.workingDirectory) {
            return .terminal
        }

        if looksLikeAIShell(trimmed) {
            return .aiToShell
        }

        if let cached = cache.object(forKey: trimmed as NSString) as String?,
           let mode = InputMode(rawValue: cached) {
            return mode
        }

        guard let provider, let modelID, !modelID.isEmpty else {
            return nil
        }

        let prompt = classifierPrompt(for: trimmed, context: context)
        let response = try await providerRouter.complete(
            provider: provider,
            modelID: modelID,
            messages: [
                ChatMessage(role: "system", content: "You are a terminal input classifier. Classify the input as exactly one of: TERMINAL, AI_TO_SHELL, or QUERY. Reply with only the classification word."),
                ChatMessage(role: "user", content: prompt),
            ]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let mode = InputMode(rawValue: response) else { return nil }
        cache.setObject(mode.rawValue as NSString, forKey: trimmed as NSString)
        return mode
    }

    func strippedOverrideInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, ["!", ">", "$"].contains(first) else { return input }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private func forcedMode(for input: String) -> InputMode? {
        guard let first = input.first else { return nil }
        switch first {
        case "!": return .query
        case ">": return .aiToShell
        case "$": return .terminal
        default: return nil
        }
    }

    private func looksLikeTerminal(_ input: String, workingDirectory: URL?) -> Bool {
        let tokens = shellTokens(input)
        guard let first = tokens.first else { return false }

        if commandResolver.isBuiltin(first) || first.hasPrefix("/") || first.hasPrefix("./") || first.hasPrefix("../") {
            return true
        }

        if let workingDirectory,
           FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent(first).path) {
            return true
        }

        return commandResolver.isExecutable(first)
    }

    private func looksLikeQuery(_ input: String) -> Bool {
        let lowercased = input.lowercased()
        return queryPrefixes.contains { lowercased.hasPrefix($0) } || lowercased.hasSuffix("?")
    }

    private func looksLikeAIShell(_ input: String) -> Bool {
        let words = Set(shellTokens(input.lowercased()))
        guard let first = shellTokens(input.lowercased()).first else { return false }
        return actionVerbs.contains(first) && !words.isDisjoint(with: systemNouns)
    }

    private func shellTokens(_ input: String) -> [String] {
        input.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func classifierPrompt(for input: String, context: ClassificationContext) -> String {
        """
        Context:
        cwd=\(context.workingDirectory?.path ?? "")
        last_commands=\(context.lastCommands.joined(separator: " | "))
        last_output_snippet=\(context.lastOutputSnippet)

        Input:
        \(input)
        """
    }
}

private final class CommandResolver {
    private let builtins: Set<String> = [
        "cd", "echo", "export", "source", "alias", "unset", "fg", "bg",
        "jobs", "kill", "exit", "history", "pwd", "pushd", "popd", "type",
        "which", "eval"
    ]
    private var executableCache: [String: Bool] = [:]

    func isBuiltin(_ command: String) -> Bool {
        builtins.contains(command)
    }

    func isExecutable(_ command: String) -> Bool {
        if let cached = executableCache[command] {
            return cached
        }

        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let exists = searchPaths.contains { path in
            FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: path).appendingPathComponent(command).path)
        }
        executableCache[command] = exists
        return exists
    }
}
