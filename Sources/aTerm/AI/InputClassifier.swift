import Foundation

// MARK: - Errors

enum InputClassifierError: LocalizedError {
    case noProvider
    
    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "No configured model is available for classifier fallback."
        }
    }
}

// MARK: - Input Classifier

@MainActor
final class InputClassifier {
    
    // MARK: - Dependencies
    
    private let commandResolver = CommandResolver()
    private let providerRouter = ProviderRouter()
    private let feedbackStore = ClassificationFeedbackStore.shared
    private let projectDetector = ProjectContextDetector.shared
    private let cache = NSCache<NSString, ClassificationResultCacheEntry>()
    
    // MARK: - Configuration
    
    private let queryPrefixes = [
        "what", "why", "how", "explain", "describe", "tell me", "what's",
        "whats", "what is", "what are", "why is", "why does", "how do",
        "how does", "how can", "can you explain", "could you explain",
        "show me how", "help me", "i need help", "assist me", "clarify",
        "what does", "what would", "when should", "where is", "who",
        "compare", "contrast", "difference between", "pros and cons"
    ]
    
    /// Words that look like commands but are commonly used in natural language queries
    private let commandLikeQueryWords: Set<String> = ["what", "which"]
    
    private let actionVerbs: Set<String> = [
        "find", "show", "list", "kill", "stop", "start", "restart", "move",
        "copy", "delete", "remove", "compress", "extract", "create", "make",
        "open", "check", "monitor", "watch", "tail", "grep", "search",
        "count", "sort", "display", "get", "look", "zip", "unzip", "generate",
        "archive", "convert", "resize", "resize", "optimize", "clean",
        "organize", "rename", "backup", "restore", "sync", "fetch", "pull",
        "push", "commit", "checkout", "branch", "merge", "rebase", "diff"
    ]
    
    private let systemNouns: Set<String> = [
        "files", "file", "folder", "directory", "process", "port", "service",
        "logs", "disk", "memory", "cpu", "network", "connection", "socket",
        "permissions", "ownership", "symlink", "archive", "package", "backup",
        "this", "the", "all", "running", "errors", "output", "input",
        "stdout", "stderr", "repo", "repository", "branch", "commit",
        "container", "image", "volume", "pod"
    ]
    
    // MARK: - Classification

    /// Synchronously pre-parses user input to immediately distinguish shell commands from AI requests without any LLM latency.
    /// Returns a `ClassificationResult` when heuristics/syntax/command resolution are decisive, or `nil` when truly ambiguous.
    func fastClassify(
        _ input: String,
        context: ClassificationContext,
        routingMode: AIRoutingMode = .smart
    ) -> ClassificationResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ClassificationResult(
                mode: .terminal,
                confidence: .certain,
                score: 1.0,
                explanation: ClassificationExplanation(
                    primaryMode: .terminal,
                    confidenceScore: 1.0,
                    reasons: ["Empty input defaults to terminal"],
                    contributingFactors: [:],
                    alternativeModes: []
                )
            )
        }

        // 0. Check for /chat command - forces pure AI chat mode
        if isChatCommand(trimmed) {
            return ClassificationResult(
                mode: .query,
                confidence: .certain,
                score: 1.0,
                explanation: ClassificationExplanation(
                    primaryMode: .query,
                    confidenceScore: 1.0,
                    reasons: ["/chat command forces AI chat mode"],
                    contributingFactors: ["chat_command": 1.0],
                    alternativeModes: []
                )
            )
        }

        // 1. Check for forced mode prefixes (?, ??, !, >, $, /ask, /cmd)
        if let forced = forcedMode(for: trimmed) {
            return createForcedResult(for: forced, input: trimmed)
        }

        // 2. In Shell-only routing mode, all unprefixed input goes straight to zsh
        if routingMode == .shell {
            return ClassificationResult(
                mode: .terminal,
                confidence: .certain,
                score: 1.0,
                explanation: ClassificationExplanation(
                    primaryMode: .terminal,
                    confidenceScore: 1.0,
                    reasons: ["Shell-only routing mode active"],
                    contributingFactors: ["routing_mode": 1.0],
                    alternativeModes: []
                )
            )
        }

        // 3. Check for learned patterns from user feedback
        if let learned = feedbackStore.learnedMode(for: trimmed) {
            return ClassificationResult(
                mode: learned,
                confidence: .high,
                score: 0.85,
                explanation: ClassificationExplanation(
                    primaryMode: learned,
                    confidenceScore: 0.85,
                    reasons: ["Based on your previous corrections"],
                    contributingFactors: ["learned_pattern": 0.85],
                    alternativeModes: InputMode.allCases.filter { $0 != learned }
                )
            )
        }

        // 4. Multi-line input analysis
        if trimmed.contains("\n") {
            return classifyMultiline(trimmed, context: context)
        }

        // 5. Run synchronous heuristic scoring (shell syntax + PATH/builtin/alias lookup + NL patterns)
        let heuristicResult = classifyWithHeuristics(trimmed, context: context)

        if heuristicResult.confidence >= .high {
            return heuristicResult
        }

        // 6. Expedite recognized shell commands even at medium confidence
        if heuristicResult.mode == .terminal && heuristicResult.score >= 0.6 {
            return heuristicResult
        }

        // 7. Expedite clear natural-language questions without an extra classification round-trip
        if heuristicResult.mode == .query && heuristicResult.score >= 0.4 {
            return ClassificationResult(
                mode: .query,
                confidence: max(heuristicResult.confidence, .medium),
                score: heuristicResult.score,
                explanation: ClassificationExplanation(
                    primaryMode: .query,
                    confidenceScore: heuristicResult.score,
                    reasons: heuristicResult.explanation.reasons,
                    contributingFactors: heuristicResult.explanation.contributingFactors,
                    alternativeModes: [.terminal]
                )
            )
        }

        // 8. Expedite clear natural-language command generation requests without an extra classification round-trip
        if heuristicResult.mode == .aiToShell && heuristicResult.score >= 0.45 {
            return ClassificationResult(
                mode: .aiToShell,
                confidence: max(heuristicResult.confidence, .medium),
                score: heuristicResult.score,
                explanation: heuristicResult.explanation
            )
        }

        // 9. Multi-word natural language fallback when the first word is NOT a valid shell command/builtin/alias
        let tokens = shellTokens(trimmed)
        if tokens.count >= 2 && calculateCommandScore(trimmed, context: context) == 0 && ShellSyntaxAnalyzer.analyze(trimmed).shellScore < 0.3 {
            let mode: InputMode = trimmed.hasSuffix("?") ? .query : .aiToShell
            return ClassificationResult(
                mode: mode,
                confidence: .medium,
                score: 0.65,
                explanation: ClassificationExplanation(
                    primaryMode: mode,
                    confidenceScore: 0.65,
                    reasons: ["Unrecognized command with multi-word natural language phrasing"],
                    contributingFactors: ["natural_language_fallback": 0.65],
                    alternativeModes: [.terminal]
                )
            )
        }

        return nil
    }

    /// Classifies user input with confidence scoring and explanation
    func classify(
        _ input: String,
        context: ClassificationContext,
        provider: ModelProvider?,
        modelID: String?
    ) async throws -> ClassificationResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fast synchronous pre-parse handles all clear shell commands, prefixes, queries, and NL tasks
        if let fast = fastClassify(trimmed, context: context, routingMode: .smart) {
            return fast
        }

        let heuristicResult = classifyWithHeuristics(trimmed, context: context)

        // If we have a provider, use LLM only for genuinely ambiguous cases
        guard let provider, let modelID, !modelID.isEmpty else {
            if heuristicResult.confidence >= .medium {
                return heuristicResult
            }
            return nil // Trigger disambiguation
        }

        // Check cache before calling LLM
        let cacheKey = "\(trimmed)|\(context.projectType.rawValue)" as NSString
        if let cached = cache.object(forKey: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < 300 { // 5 minute cache
            return cached.result
        }

        // LLM fallback for ambiguous cases
        let llmResult = try await classifyWithLLM(
            trimmed,
            context: context,
            provider: provider,
            modelID: modelID,
            heuristicResult: heuristicResult
        )

        // Cache the result
        cache.setObject(
            ClassificationResultCacheEntry(result: llmResult, timestamp: Date()),
            forKey: cacheKey
        )

        return llmResult
    }
    
    /// Strips override prefixes from input
    func strippedOverrideInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        // Handle /chat, /ask, /cmd prefixes
        if lower.hasPrefix("/chat ") {
            return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        if lower == "/chat" {
            return ""
        }
        if lower.hasPrefix("/ask ") {
            return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        if lower.hasPrefix("/cmd ") {
            return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("??") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        
        guard let first = trimmed.first, ["!", "?", ">", "$"].contains(first) else { return input }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    
    /// Checks if input should force chat/query mode
    func isChatCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (trimmed == "/chat" || trimmed.hasPrefix("/chat ")) && !isChatExitCommand(trimmed)
    }
    
    /// Checks if input is chat exit command
    func isChatExitCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["/chat-exit", "/chatexit", "/chat-eixt", "/exit", "/quit"].contains(trimmed)
    }
    
    /// Returns true if input is dangerous (destructive command)
    func isDangerousCommand(_ input: String) -> Bool {
        ShellSyntaxAnalyzer.containsDangerousCommand(input)
    }
    
    // MARK: - Private Classification Methods
    
    private func forcedMode(for input: String) -> InputMode? {
        let lower = input.lowercased()
        if lower.hasPrefix("/ask ") { return .query }
        if lower.hasPrefix("/cmd ") { return .aiToShell }
        if input.hasPrefix("??") { return .aiToShell }
        guard let first = input.first else { return nil }
        switch first {
        case "!", "?": return .query
        case ">": return .aiToShell
        case "$": return .terminal
        default: return nil
        }
    }
    
    private func createForcedResult(for mode: InputMode, input: String) -> ClassificationResult {
        let prefix: String
        switch mode {
        case .terminal: prefix = "$"
        case .aiToShell: prefix = ">"
        case .query: prefix = "!"
        }
        
        return ClassificationResult(
            mode: mode,
            confidence: .certain,
            score: 1.0,
            explanation: ClassificationExplanation(
                primaryMode: mode,
                confidenceScore: 1.0,
                reasons: ["User forced with '\(prefix)' prefix"],
                contributingFactors: ["forced_prefix": 1.0],
                alternativeModes: []
            )
        )
    }
    
    private func classifyMultiline(_ input: String, context: ClassificationContext) -> ClassificationResult {
        let multiline = MultilineInput(input)
        
        if multiline.isScript {
            return ClassificationResult(
                mode: .terminal,
                confidence: .certain,
                score: 0.95,
                explanation: ClassificationExplanation(
                    primaryMode: .terminal,
                    confidenceScore: 0.95,
                    reasons: ["Multi-line script detected (shebang)"],
                    contributingFactors: ["shebang": 0.5, "multiline": 0.45],
                    alternativeModes: [.query]
                )
            )
        }
        
        // Analyze shell syntax
        let analysis = ShellSyntaxAnalyzer.analyze(input)
        
        if analysis.isScript {
            return ClassificationResult(
                mode: .terminal,
                confidence: .high,
                score: 0.85,
                explanation: ClassificationExplanation(
                    primaryMode: .terminal,
                    confidenceScore: 0.85,
                    reasons: ["Multi-line shell script detected"],
                    contributingFactors: ["shell_syntax": analysis.shellScore],
                    alternativeModes: [.query]
                )
            )
        }
        
        // Default to query for code blocks or natural language
        return ClassificationResult(
            mode: .query,
            confidence: .medium,
            score: 0.65,
            explanation: ClassificationExplanation(
                primaryMode: .query,
                confidenceScore: 0.65,
                reasons: ["Multi-line input"],
                contributingFactors: ["multiline": 0.4],
                alternativeModes: [.terminal, .aiToShell]
            )
        )
    }
    
    private func classifyWithHeuristics(
        _ input: String,
        context: ClassificationContext
    ) -> ClassificationResult {
        
        var scores: [InputMode: Double] = [.terminal: 0, .aiToShell: 0, .query: 0]
        var factors: [String: Double] = [:]
        var reasons: [String] = []
        
        // 1. Query pattern detection
        let queryScore = calculateQueryScore(input, context: context)
        scores[.query]! += queryScore
        if queryScore > 0 {
            factors["query_pattern"] = queryScore
            if queryScore > 0.5 {
                reasons.append("Contains question pattern")
            }
        }
        
        // 2. Shell syntax analysis
        let shellAnalysis = ShellSyntaxAnalyzer.analyze(input)
        scores[.terminal]! += shellAnalysis.shellScore
        factors["shell_syntax"] = shellAnalysis.shellScore
        
        if shellAnalysis.isLikelyShellCommand {
            reasons.append("Shell syntax detected: \(shellAnalysis.matchedPatterns.joined(separator: ", "))")
        }
        
        // 3. Command existence check
        let commandScore = calculateCommandScore(input, context: context)
        scores[.terminal]! += commandScore
        if commandScore > 0 {
            factors["known_command"] = commandScore
            if commandScore > 0.3 {
                reasons.append("Recognized as executable command")
            }
        }
        
        // 4. AI-to-Shell pattern detection
        let aiToShellScore = calculateAIToShellScore(input)
        scores[.aiToShell]! += aiToShellScore
        if aiToShellScore > 0 {
            factors["action_pattern"] = aiToShellScore
            if aiToShellScore > 0.5 {
                reasons.append("Action verb + system noun pattern")
            }
        }
        
        // 5. Project context adjustments
        if context.projectType != .generic {
            // Boost terminal score for project-specific commands
            if isProjectSpecificCommand(input, projectType: context.projectType) {
                scores[.terminal]! += 0.2
                factors["project_context"] = 0.2
                reasons.append("Project-specific command for \(context.projectType.rawValue)")
            }
        }
        
        // 6. Error context adjustment
        if context.lastCommandFailed {
            // If last command failed, user might be asking for help
            if queryScore > 0.3 {
                scores[.query]! += 0.15
                factors["error_context"] = 0.15
                reasons.append("Previous command failed - likely asking for help")
            }
        }
        
        // 7. Command history pattern
        if context.isDebugging {
            // User is debugging - likely shell commands
            scores[.terminal]! += 0.1
            factors["debugging_pattern"] = 0.1
        }
        
        // Determine winner
        let (mode, score) = scores.max(by: { $0.value < $1.value })!
        let confidence = ClassificationConfidence.from(score: score)
        
        // Adjust based on user preference profile
        let adjustedResult = applyUserPreference(
            mode: mode,
            score: score,
            confidence: confidence,
            allScores: scores
        )
        
        // Build alternative modes
        let alternatives = scores
            .filter { $0.key != mode && $0.value > 0.2 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
        
        return ClassificationResult(
            mode: adjustedResult.mode,
            confidence: adjustedResult.confidence,
            score: adjustedResult.score,
            explanation: ClassificationExplanation(
                primaryMode: adjustedResult.mode,
                confidenceScore: adjustedResult.score,
                reasons: reasons.isEmpty ? ["Pattern match"] : reasons,
                contributingFactors: factors,
                alternativeModes: alternatives
            )
        )
    }
    
    private let naturalLanguageIndicators: Set<String> = [
        "all", "my", "the", "me", "every", "any", "files", "folders", "directories",
        "processes", "running", "largest", "smallest", "biggest", "newest", "oldest",
        "modified", "created", "bigger", "smaller", "larger", "than", "where", "that",
        "which", "into", "from", "without", "port", "ports", "disk", "memory", "usage",
        "space", "current", "directory", "folder", "last", "recent", "today", "yesterday",
        "recursively", "containing", "matching", "named", "called"
    ]

    /// Returns true when an input starting with an action verb reads like natural language prose rather than shell arguments.
    private func looksLikeNaturalLanguageAction(_ input: String) -> Bool {
        let tokens = shellTokens(input)
        guard tokens.count >= 3, let first = tokens.first?.lowercased() else { return false }
        guard actionVerbs.contains(first) else { return false }

        let argTokens = Array(tokens.dropFirst())
        // If any argument is a shell flag (-x, --foo) or explicit path (./, /, ~/), it's a real shell command
        let hasShellFlagsOrPaths = argTokens.contains { tok in
            tok.hasPrefix("-") || tok == "." || tok == ".." || tok.hasPrefix("./") || tok.hasPrefix("../") || tok.hasPrefix("/") || tok.hasPrefix("~/")
        }
        if hasShellFlagsOrPaths { return false }

        let lowerArgs = Set(argTokens.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) })
        let indicatorMatches = lowerArgs.intersection(naturalLanguageIndicators).count
        return indicatorMatches >= 1
    }

    private func calculateQueryScore(_ input: String, context: ClassificationContext) -> Double {
        let lowercased = input.lowercased()
        var score: Double = 0
        
        // Check query prefixes (match whole word or phrase prefix)
        for prefix in queryPrefixes {
            if lowercased == prefix || lowercased.hasPrefix(prefix + " ") || lowercased.hasPrefix(prefix + "?") {
                // Ensure `which <single-binary>` is treated as the shell command `which`
                if prefix == "which" {
                    let tokens = shellTokens(lowercased)
                    if tokens.count == 2 && !lowercased.hasSuffix("?") {
                        break
                    }
                }
                score += 0.6
                break
            }
        }
        
        // Check for question mark
        if lowercased.hasSuffix("?") {
            score += 0.35
        }
        
        // Check for explanation-seeking words
        let explanationWords = ["explain", "why", "how does", "how do", "how to", "what is", "what are", "what does", "difference", "mean"]
        for word in explanationWords {
            if lowercased.contains(word) {
                score += 0.25
                break
            }
        }
        
        // Negative indicators (shell-like content)
        if ShellSyntaxAnalyzer.analyze(input).shellScore > 0.5 {
            score -= 0.3
        }
        
        return max(0, min(score, 1.0))
    }
    
    private static let commandWrappers: Set<String> = [
        "sudo", "env", "time", "nohup", "nice", "caffeinate", "arch", "xargs", "command", "builtin", " noglob", "nocorrect"
    ]

    private static let gitSubcommands: Set<String> = [
        "add", "am", "annotate", "apply", "archive", "bisect", "blame", "branch", "bundle",
        "checkout", "cherry", "cherry-pick", "clean", "clone", "commit", "config", "count-objects",
        "describe", "diff", "difftool", "fetch", "format-patch", "fsck", "gc", "grep", "help",
        "init", "instaweb", "log", "ls-files", "ls-remote", "ls-tree", "maintenance", "merge",
        "mergetool", "mv", "notes", "prune", "pull", "push", "range-diff", "rebase", "reflog",
        "remote", "repack", "replace", "request-pull", "reset", "restore", "rev-list", "rev-parse",
        "revert", "rm", "shortlog", "show", "show-branch", "sparse-checkout", "stage", "stash",
        "status", "submodule", "switch", "tag", " verify-commit", "verify-tag", "whatchanged", "worktree"
    ]

    /// Extracts the effective command token after skipping leading `KEY=VALUE` assignments and wrapper commands (`sudo`, `time`, etc.).
    private func effectiveCommandToken(from tokens: [String]) -> (command: String, remainingTokens: [String])? {
        var idx = 0
        while idx < tokens.count {
            let tok = tokens[idx]
            // Skip KEY=VALUE assignments
            if tok.contains("="), !tok.hasPrefix("-"), let eqIdx = tok.firstIndex(of: "="), eqIdx > tok.startIndex {
                idx += 1
                continue
            }
            let lower = tok.lowercased()
            if Self.commandWrappers.contains(lower) {
                idx += 1
                // Skip flags passed to the wrapper itself (e.g. `sudo -u root cmd`)
                while idx < tokens.count && tokens[idx].hasPrefix("-") {
                    idx += 1
                }
                continue
            }
            return (tok, Array(tokens.dropFirst(idx + 1)))
        }
        return nil
    }

    private func calculateCommandScore(_ input: String, context: ClassificationContext) -> Double {
        let tokens = shellTokens(input)
        guard let (first, remainingTokens) = effectiveCommandToken(from: tokens) else { return 0 }
        let lowerFirst = first.lowercased()
        let lowercased = input.lowercased()
        
        // If first word looks like a command but is commonly used in queries,
        // and the rest looks like a question, reduce the terminal score
        if commandLikeQueryWords.contains(lowerFirst) {
            let restOfInput = lowercased.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
            let queryIndicators = ["is", "are", "does", "do", "can", "should", "would", "will"]
            if queryIndicators.contains(where: { restOfInput.hasPrefix($0) }) || tokens.count > 2 || lowercased.hasSuffix("?") {
                Log.debug("classifier", "Detected query pattern with command-like word: \(first)")
                return 0.05
            }
        }

        // If this starts with an overlapping verb (e.g. `find`, `kill`, `open`, `make`, `sort`)
        // but the arguments are clearly natural language prose (e.g. "find my largest log files",
        // "kill all node processes"), let AI-to-Shell win instead of executing raw prose in zsh.
        if looksLikeNaturalLanguageAction(input) {
            return 0.15
        }

        // Special handling for `git`: verify the subcommand or flag is valid shell syntax rather than prose like "git undo my last commit"
        if lowerFirst == "git", let sub = remainingTokens.first?.lowercased() {
            if !sub.hasPrefix("-") && !Self.gitSubcommands.contains(sub) && remainingTokens.count >= 2 {
                let lowerArgs = Set(remainingTokens.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) })
                if !lowerArgs.isDisjoint(with: naturalLanguageIndicators) || !lowerArgs.isDisjoint(with: systemNouns) {
                    return 0.15
                }
            }
        }
        
        var score: Double = 0
        
        // Builtin command or common zsh alias
        if commandResolver.isBuiltin(first) || commandResolver.isCommonAlias(first) {
            score += 0.85
        }
        
        // Executable in PATH
        if commandResolver.isExecutable(first) {
            score += 0.85
        }
        
        // Local executable or path navigation
        if first.hasPrefix("/") || first.hasPrefix("./") || first.hasPrefix("../") || first.hasPrefix("~/") {
            score += 0.85
        }
        
        // File in working directory
        if let workingDirectory = context.workingDirectory,
           FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent(first).path) {
            score += 0.8
        }
        
        return min(score, 1.0)
    }
    
    private func calculateAIToShellScore(_ input: String) -> Double {
        let lowercased = input.lowercased()
        let words = shellTokens(lowercased)
        
        guard let first = words.first, words.count >= 2 else { return 0 }
        
        // Must start with action verb
        guard actionVerbs.contains(first) else { return 0 }

        // If arguments contain explicit shell flags or paths (e.g. `find . -name`, `kill -9 1234`), it's a real shell command
        let argTokens = Array(words.dropFirst())
        let hasShellFlagsOrPaths = argTokens.contains { tok in
            tok.hasPrefix("-") || tok == "." || tok == ".." || tok.hasPrefix("./") || tok.hasPrefix("../") || tok.hasPrefix("/") || tok.hasPrefix("~/")
        }
        if hasShellFlagsOrPaths {
            return 0.05
        }
        // `kill <pid>` with numeric PID is a direct terminal command
        if first == "kill", argTokens.allSatisfy({ $0.allSatisfy(\.isNumber) || $0.hasPrefix("%") }) {
            return 0.05
        }
        
        var score: Double = 0.45  // Base score for action verb
        
        // Check for system nouns or natural language indicators
        let cleanWords = Set(words.map { $0.trimmingCharacters(in: .punctuationCharacters) })
        if !cleanWords.isDisjoint(with: systemNouns) {
            score += 0.4
        }
        if !cleanWords.isDisjoint(with: naturalLanguageIndicators) {
            score += 0.25
        }
        
        // Negative indicators (question patterns)
        if lowercased.hasSuffix("?") {
            score -= 0.3
        }
        
        return max(0, min(score, 1.0))
    }
    
    private func isProjectSpecificCommand(_ input: String, projectType: ProjectType) -> Bool {
        let lowercased = input.lowercased()
        
        // Check test commands
        for testCmd in projectType.testCommands {
            if lowercased.hasPrefix(testCmd.lowercased()) {
                return true
            }
        }
        
        // Check build commands
        for buildCmd in projectType.buildCommands {
            if lowercased.hasPrefix(buildCmd.lowercased()) {
                return true
            }
        }
        
        return false
    }
    
    private func applyUserPreference(
        mode: InputMode,
        score: Double,
        confidence: ClassificationConfidence,
        allScores: [InputMode: Double]
    ) -> (mode: InputMode, score: Double, confidence: ClassificationConfidence) {
        let profile = feedbackStore.preferenceProfile
        
        // If confidence is already high, respect it
        if confidence >= .certain {
            return (mode, score, confidence)
        }
        
        // Adjust based on user profile
        switch profile {
        case .expert:
            // Prefer terminal when uncertain
            if confidence <= .low && allScores[.terminal]! > 0 {
                return (.terminal, max(allScores[.terminal]!, 0.6), .medium)
            }
        case .exploratory:
            // Prefer AI modes when uncertain
            if confidence <= .low {
                if allScores[.aiToShell]! >= allScores[.query]! {
                    return (.aiToShell, max(allScores[.aiToShell]!, 0.6), .medium)
                } else {
                    return (.query, max(allScores[.query]!, 0.6), .medium)
                }
            }
        case .assisted:
            // Keep as-is, show disambiguation when uncertain
            break
        }
        
        return (mode, score, confidence)
    }
    
    private func classifyWithLLM(
        _ input: String,
        context: ClassificationContext,
        provider: ModelProvider,
        modelID: String,
        heuristicResult: ClassificationResult
    ) async throws -> ClassificationResult {
        
        let prompt = buildLLMPrompt(input: input, context: context, heuristicResult: heuristicResult)
        
        let response = try await providerRouter.complete(
            provider: provider,
            modelID: modelID,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    You are a terminal input classifier. Analyze the input and classify it as exactly one of: TERMINAL, AI_TO_SHELL, or QUERY.
                    
                    - TERMINAL: Direct shell commands the user wants to execute immediately
                    - AI_TO_SHELL: Natural language requests that should be converted to shell commands
                    - QUERY: Questions or explanations the user wants help with
                    
                    Respond with ONLY a JSON object: {"mode": "MODE", "confidence": 0.0-1.0, "reason": "brief reason"}
                    """
                ),
                ChatMessage(role: "user", content: prompt),
            ]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse LLM response
        let (mode, confidence) = parseLLMResponse(response, fallback: heuristicResult.mode)
        
        // Build explanation
        let explanation = ClassificationExplanation(
            primaryMode: mode,
            confidenceScore: confidence.rawValue,
            reasons: ["LLM classification", "Heuristic confidence: \(heuristicResult.confidence.description)"],
            contributingFactors: ["llm": confidence.rawValue, "heuristic": heuristicResult.score],
            alternativeModes: InputMode.allCases.filter { $0 != mode }
        )
        
        return ClassificationResult(
            mode: mode,
            confidence: confidence,
            score: confidence.rawValue,
            explanation: explanation
        )
    }
    
    private func buildLLMPrompt(
        input: String,
        context: ClassificationContext,
        heuristicResult: ClassificationResult
    ) -> String {
        var parts: [String] = []
        
        parts.append("Input to classify: \"\(input)\"")
        parts.append("")
        parts.append("Context:")
        parts.append("- Working directory: \(context.workingDirectory?.path ?? "unknown")")
        parts.append("- Project type: \(context.projectType.rawValue)")
        if let branch = context.gitBranch {
            parts.append("- Git branch: \(branch)")
        }
        if !context.lastCommands.isEmpty {
            parts.append("- Recent commands: \(context.lastCommands.joined(separator: " | "))")
        }
        if context.lastCommandFailed {
            parts.append("- Last command: FAILED (exit code \(context.lastExitCode ?? -1))")
        }
        
        parts.append("")
        parts.append("Heuristic analysis:")
        parts.append("- Suggested mode: \(heuristicResult.mode.rawValue)")
        parts.append("- Confidence: \(heuristicResult.confidence.description) (\(heuristicResult.score))")
        parts.append("- Reasons: \(heuristicResult.explanation.reasons.joined(separator: "; "))")
        
        return parts.joined(separator: "\n")
    }
    
    private func parseLLMResponse(_ response: String, fallback: InputMode) -> (mode: InputMode, confidence: ClassificationConfidence) {
        // Try to extract JSON
        if let jsonStart = response.firstIndex(of: "{"),
           let jsonEnd = response.lastIndex(of: "}") {
            let jsonString = String(response[jsonStart...jsonEnd])
            
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let modeString = json["mode"] as? String,
               let mode = InputMode(rawValue: modeString) {
                
                let confidenceValue = json["confidence"] as? Double ?? 0.7
                return (mode, ClassificationConfidence.from(score: confidenceValue))
            }
        }
        
        // Fallback: check for mode in raw text
        let uppercased = response.uppercased()
        if uppercased.contains("TERMINAL") {
            return (.terminal, .medium)
        } else if uppercased.contains("AI_TO_SHELL") || uppercased.contains("AI TO SHELL") {
            return (.aiToShell, .medium)
        } else if uppercased.contains("QUERY") {
            return (.query, .medium)
        }
        
        return (fallback, .low)
    }
    
    private func shellTokens(_ input: String) -> [String] {
        input.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

// MARK: - Cache Entry

private final class ClassificationResultCacheEntry: NSObject {
    let result: ClassificationResult
    let timestamp: Date
    
    init(result: ClassificationResult, timestamp: Date) {
        self.result = result
        self.timestamp = timestamp
    }
}

// MARK: - Command Resolver

private final class CommandResolver: @unchecked Sendable {
    private let builtins: Set<String> = [
        "cd", "echo", "export", "source", ".", ":", "alias", "unalias", "unset", "fg", "bg",
        "jobs", "kill", "exit", "logout", "history", "fc", "pwd", "pushd", "popd", "dirs", "type",
        "which", "where", "whence", "eval", "exec", "return", "shift", "test", "[", "[[",
        "true", "false", "read", "printf", "print", "break", "continue", "clear", "reset",
        "set", "setopt", "unsetopt", "bindkey", "autoload", "ulimit", "umask", "wait", "trap",
        "local", "declare", "typeset", "readonly", "let", "getopts", "hash", "rehash", "disown",
        "suspend", "times", "emulate", "zle", "zmodload", "zstyle", "compdef"
    ]
    private let commonAliases: Set<String> = [
        "ll", "la", "l", "lsa", "md", "rd", "..", "...", "....", ".....", "~", "-",
        "g", "ga", "gaa", "gb", "gba", "gbm", "gbd", "gc", "gca", "gcam", "gcb", "gcm", "gcmsg",
        "gco", "gcp", "gd", "gds", "gf", "gfa", "gl", "glog", "glol", "glola", "gm", "gp", "gpf",
        "gpr", "gpu", "gr", "gra", "grb", "grbi", "grbc", "grba", "grh", "grhh", "grm", "grs",
        "grst", "grv", "gsb", "gsh", "gsi", "gsta", "gstaa", "gstc", "gstd", "gstl", "gstp",
        "gsts", "gst", "gsu", "gsw", "gtl", "gts", "gwch",
        "cls", "dir", "vdir", "py", "py3", "ipy", "k", "tf", "dc", "dcu", "dcd", "dcl"
    ]
    private var executableCache: [String: Bool] = [:]
    private var cacheQueue = DispatchQueue(label: "com.aterm.commandresolver")
    
    func isBuiltin(_ command: String) -> Bool {
        builtins.contains(command)
    }

    func isCommonAlias(_ command: String) -> Bool {
        commonAliases.contains(command)
    }
    
    func isExecutable(_ command: String) -> Bool {
        // Check cache
        if let cached = cacheQueue.sync(execute: { executableCache[command] }) {
            return cached
        }
        
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let standardPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(NSHomeDirectory())/.cargo/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
        var seen = Set<String>()
        let searchPaths = (envPaths + standardPaths).filter { seen.insert($0).inserted }
        
        let exists = searchPaths.contains { path in
            FileManager.default.isExecutableFile(
                atPath: URL(fileURLWithPath: path).appendingPathComponent(command).path
            )
        }
        
        cacheQueue.async {
            self.executableCache[command] = exists
            // Trim cache if too large (remove oldest entries)
            if self.executableCache.count > 1000 {
                let keysToRemove = Array(self.executableCache.keys.prefix(100))
                for key in keysToRemove {
                    self.executableCache.removeValue(forKey: key)
                }
            }
        }
        
        return exists
    }
}
