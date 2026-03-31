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
    
    /// Classifies user input with confidence scoring and explanation
    func classify(
        _ input: String,
        context: ClassificationContext,
        provider: ModelProvider?,
        modelID: String?
    ) async throws -> ClassificationResult? {
        
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
        
        // 1. Check for forced mode prefixes
        if let forced = forcedMode(for: trimmed) {
            return createForcedResult(for: forced, input: trimmed)
        }
        
        // 2. Check for learned patterns from user feedback
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
        
        // 3. Multi-line input analysis
        if trimmed.contains("\n") {
            return classifyMultiline(trimmed, context: context)
        }
        
        // 4. Run heuristic scoring
        let heuristicResult = await classifyWithHeuristics(trimmed, context: context)
        
        // 5. If confidence is high enough, return immediately
        if heuristicResult.confidence >= .high {
            return heuristicResult
        }
        
        // 6. For clear queries (what/why/how), always treat as query even without provider
        // This ensures natural language questions get answered, not sent to shell
        if heuristicResult.mode == .query && heuristicResult.score >= 0.4 {
            return ClassificationResult(
                mode: .query,
                confidence: .medium,
                score: heuristicResult.score,
                explanation: ClassificationExplanation(
                    primaryMode: .query,
                    confidenceScore: heuristicResult.score,
                    reasons: ["Natural language query detected (no AI provider configured, will use basic response)"],
                    contributingFactors: heuristicResult.explanation.contributingFactors,
                    alternativeModes: [.terminal]
                )
            )
        }
        
        // 7. If we have a provider, use LLM for ambiguous cases
        guard let provider, let modelID, !modelID.isEmpty else {
            // No LLM available - use heuristic result or mark as uncertain
            if heuristicResult.confidence >= .medium {
                return heuristicResult
            }
            return nil // Trigger disambiguation
        }
        
        // 7. Check cache before calling LLM
        let cacheKey = "\(trimmed)|\(context.projectType.rawValue)" as NSString
        if let cached = cache.object(forKey: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < 300 { // 5 minute cache
            return cached.result
        }
        
        // 8. LLM fallback for ambiguous cases
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
        
        // Handle /chat prefix - strip it for chat mode
        if trimmed.lowercased().hasPrefix("/chat ") {
            return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.lowercased() == "/chat" {
            return ""
        }
        
        guard let first = trimmed.first, ["!", ">", "$"].contains(first) else { return input }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    
    /// Checks if input should force chat/query mode
    func isChatCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("/chat") && !trimmed.lowercased().hasPrefix("/chat-exit")
    }
    
    /// Checks if input is chat exit command
    func isChatExitCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased() == "/chat-exit"
    }
    
    /// Returns true if input is dangerous (destructive command)
    func isDangerousCommand(_ input: String) -> Bool {
        ShellSyntaxAnalyzer.containsDangerousCommand(input)
    }
    
    // MARK: - Private Classification Methods
    
    private func forcedMode(for input: String) -> InputMode? {
        guard let first = input.first else { return nil }
        switch first {
        case "!": return .query
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
    ) async -> ClassificationResult {
        
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
    
    private func calculateQueryScore(_ input: String, context: ClassificationContext) -> Double {
        let lowercased = input.lowercased()
        var score: Double = 0
        
        // Check query prefixes
        for prefix in queryPrefixes {
            if lowercased.hasPrefix(prefix) {
                score += 0.4
                break
            }
        }
        
        // Check for question mark
        if lowercased.hasSuffix("?") {
            score += 0.3
        }
        
        // Check for explanation-seeking words
        let explanationWords = ["explain", "why", "how does", "what is", "what are", "difference"]
        for word in explanationWords {
            if lowercased.contains(word) {
                score += 0.2
                break
            }
        }
        
        // Negative indicators (shell-like content)
        if ShellSyntaxAnalyzer.analyze(input).shellScore > 0.5 {
            score -= 0.3
        }
        
        return max(0, min(score, 1.0))
    }
    
    private func calculateCommandScore(_ input: String, context: ClassificationContext) -> Double {
        let tokens = shellTokens(input)
        guard let first = tokens.first else { return 0 }
        let lowercased = input.lowercased()
        
        // If first word looks like a command but is commonly used in queries,
        // and the rest looks like a question, reduce the terminal score
        if commandLikeQueryWords.contains(first.lowercased()) {
            // Check if this looks like a natural language query
            let restOfInput = lowercased.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
            // If followed by "is", "are", "does", "do", etc., it's likely a question
            let queryIndicators = ["is", "are", "does", "do", "can", "should", "would", "will"]
            if queryIndicators.contains(where: { restOfInput.hasPrefix($0) }) || restOfInput.count > 3 {
                // This is likely a natural language query, not a command invocation
                Log.debug("classifier", "Detected query pattern with command-like word: \(first)")
                return 0.05 // Very low score - treat as query
            }
        }
        
        var score: Double = 0
        
        // Builtin command
        if commandResolver.isBuiltin(first) {
            score += 0.5
        }
        
        // Executable in PATH
        if commandResolver.isExecutable(first) {
            score += 0.4
        }
        
        // Local executable
        if first.hasPrefix("/") || first.hasPrefix("./") || first.hasPrefix("../") {
            score += 0.45
        }
        
        // File in working directory
        if let workingDirectory = context.workingDirectory,
           FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent(first).path) {
            score += 0.4
        }
        
        return min(score, 1.0)
    }
    
    private func calculateAIToShellScore(_ input: String) -> Double {
        let lowercased = input.lowercased()
        let words = shellTokens(lowercased)
        
        guard let first = words.first else { return 0 }
        
        // Must start with action verb
        guard actionVerbs.contains(first) else { return 0 }
        
        var score: Double = 0.3  // Base score for action verb
        
        // Check for system nouns
        let wordSet = Set(words)
        if !wordSet.isDisjoint(with: systemNouns) {
            score += 0.4
        }
        
        // Negative indicators (question patterns)
        if lowercased.hasSuffix("?") {
            score -= 0.3
        }
        
        // Negative indicators (existing command)
        if calculateCommandScore(input, context: .basic(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")) > 0.3 {
            score -= 0.2
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

private final class CommandResolver {
    private let builtins: Set<String> = [
        "cd", "echo", "export", "source", "alias", "unset", "fg", "bg",
        "jobs", "kill", "exit", "history", "pwd", "pushd", "popd", "type",
        "which", "eval", "return", "shift", "test", "[", "[[",
        "true", "false", "read", "printf", "break", "continue"
    ]
    private var executableCache: [String: Bool] = [:]
    private var cacheQueue = DispatchQueue(label: "com.aterm.commandresolver")
    
    func isBuiltin(_ command: String) -> Bool {
        builtins.contains(command)
    }
    
    func isExecutable(_ command: String) -> Bool {
        // Check cache
        if let cached = cacheQueue.sync(execute: { executableCache[command] }) {
            return cached
        }
        
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        
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
