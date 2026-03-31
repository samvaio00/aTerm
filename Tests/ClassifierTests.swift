import Testing
import Foundation
@testable import aTerm

@MainActor
struct ClassifierTests {
    
    // MARK: - Basic Classification Tests
    
    @Test
    func classifiesShellCommandLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify("ls -la", context: context, provider: nil, modelID: nil)

        #expect(result != nil)
        #expect(result?.mode == .terminal)
        #expect(result?.confidence.rawValue ?? 0 >= ClassificationConfidence.medium.rawValue)
    }
    
    @Test
    func classifiesGitCommand() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify("git status", context: context, provider: nil, modelID: nil)

        #expect(result != nil)
        // git is a valid command, so it should be terminal OR aiToShell depending on context
        #expect(result?.mode == .terminal || result?.mode == .aiToShell)
    }
    
    @Test
    func classifiesCdCommand() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify("cd /tmp", context: context, provider: nil, modelID: nil)

        #expect(result != nil)
        #expect(result?.mode == .terminal)
        #expect(result?.confidence.rawValue ?? 0 >= ClassificationConfidence.high.rawValue)
    }
    
    @Test
    func classifiesComplexShellCommand() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "grep -r 'TODO' . | head -20",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .terminal)
        #expect(result?.confidence.rawValue ?? 0 >= ClassificationConfidence.high.rawValue)
    }

    @Test
    func classifiesQuestionLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(
            workingDirectory: nil,
            lastCommands: ["npm test"],
            lastOutputSnippet: "1 failing"
        )

        let result = try await classifier.classify(
            "what's wrong with that test?",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .query)
    }
    
    @Test
    func classifiesExplanationRequest() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "explain how grep works",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .query)
    }

    @Test
    func respectsForcePrefixTerminal() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "$ find my largest log files",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .terminal)
        #expect(result?.confidence == .certain)
    }
    
    @Test
    func respectsForcePrefixAIToShell() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "> find my largest log files",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .aiToShell)
        #expect(result?.confidence == .certain)
    }
    
    @Test
    func respectsForcePrefixQuery() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "! ls -la",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .query)
        #expect(result?.confidence == .certain)
    }
    
    // MARK: - AI-to-Shell Classification Tests
    
    @Test
    func classifiesNaturalLanguageCommand() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "find all python files modified today",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        // "find" is a real command, so this might be terminal or aiToShell
        #expect(result?.mode == .terminal || result?.mode == .aiToShell)
    }
    
    @Test
    func classifiesFileOperationRequest() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "show me the 10 largest files in this directory",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .aiToShell)
    }
    
    @Test
    func classifiesProcessManagementRequest() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "kill all node processes",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        // "kill" is a real command, so this might be terminal or aiToShell
        #expect(result?.mode == .terminal || result?.mode == .aiToShell)
    }
    
    // MARK: - Confidence Scoring Tests
    
    @Test
    func highConfidenceForClearShellCommand() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "docker ps -a",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .terminal)
        #expect(result?.confidence.rawValue ?? 0 >= ClassificationConfidence.medium.rawValue)
        #expect(result?.score ?? 0 >= 0.5)
    }
    
    @Test
    func highConfidenceForClearQuestion() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "how do I reset git credentials?",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .query)
        #expect(result?.confidence.rawValue ?? 0 >= ClassificationConfidence.medium.rawValue)
    }
    
    @Test
    func providesExplanation() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "ls -la",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(!result!.explanation.reasons.isEmpty)
        #expect(result!.explanation.confidenceScore > 0)
    }
    
    // MARK: - Multi-line Input Tests
    
    @Test
    func classifiesMultilineScript() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let script = """
        #!/bin/bash
        echo "Hello World"
        ls -la
        """

        let result = try await classifier.classify(script, context: context, provider: nil, modelID: nil)

        #expect(result != nil)
        #expect(result?.mode == .terminal)
    }
    
    @Test
    func classifiesMultilineQuestion() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let text = """
        I'm trying to understand how to use grep
        with regular expressions.
        Can you show me some examples?
        """

        let result = try await classifier.classify(text, context: context, provider: nil, modelID: nil)

        #expect(result != nil)
        // Multi-line natural language should be query OR terminal (script detection)
        // depending on whether it looks like a script
        #expect(result?.mode == .query || result?.mode == .terminal)
    }
    
    // MARK: - Shell Syntax Analysis Tests
    
    @Test
    func detectsVariableAssignment() {
        let analysis = ShellSyntaxAnalyzer.analyze("FOO=bar echo $FOO")
        
        #expect(analysis.shellScore > 0.3)
        #expect(analysis.matchedPatterns.contains("Variable assignment"))
    }
    
    @Test
    func detectsPipesAndRedirects() {
        let analysis = ShellSyntaxAnalyzer.analyze("cat file.txt | grep pattern > output.txt")
        
        #expect(analysis.shellScore > 0.5)
        #expect(analysis.matchedPatterns.contains("Pipe operator"))
        #expect(analysis.matchedPatterns.contains("Redirection"))
    }
    
    @Test
    func detectsCommandSubstitution() {
        let analysis = ShellSyntaxAnalyzer.analyze("echo $(date)")
        
        #expect(analysis.shellScore > 0.3)
    }
    
    @Test
    func detectsScriptStructure() {
        let script = """
        if [ -f file.txt ]; then
            echo "exists"
        fi
        """
        
        let analysis = ShellSyntaxAnalyzer.analyze(script)
        
        #expect(analysis.isScript)
        #expect(analysis.matchedPatterns.contains("If statement"))
    }
    
    // MARK: - Edge Cases
    
    @Test
    func classifiesEmptyInput() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify("", context: context, provider: nil, modelID: nil)

        #expect(result != nil)
        #expect(result?.mode == .terminal)
        #expect(result?.confidence == .certain)
    }
    
    @Test
    func classifiesWhitespaceOnlyInput() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify("   \n\t  ", context: context, provider: nil, modelID: nil)

        #expect(result != nil)
        #expect(result?.mode == .terminal)
    }
    
    @Test
    func classifiesCommandWithFlags() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "tar -czvf archive.tar.gz --exclude='node_modules' .",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        #expect(result?.mode == .terminal)
    }
    
    @Test
    func classifiesQuestionWithoutQuestionMark() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext()

        let result = try await classifier.classify(
            "tell me how to use docker compose",
            context: context,
            provider: nil,
            modelID: nil
        )

        #expect(result != nil)
        // This could be query (question) or aiToShell (natural language request)
        #expect(result?.mode == .query || result?.mode == .aiToShell)
    }
    
    // MARK: - Dangerous Command Detection
    
    @Test
    func detectsDangerousRmCommand() {
        let classifier = InputClassifier()
        
        #expect(classifier.isDangerousCommand("rm -rf /"))
        #expect(classifier.isDangerousCommand("rm -rf /system"))
    }
    
    @Test
    func detectsDangerousRedirection() {
        let classifier = InputClassifier()
        
        #expect(classifier.isDangerousCommand("> /etc/passwd"))
    }
    
    @Test
    func safeCommandNotDangerous() {
        let classifier = InputClassifier()
        
        #expect(!classifier.isDangerousCommand("ls -la"))
        #expect(!classifier.isDangerousCommand("rm file.txt"))
        #expect(!classifier.isDangerousCommand("cd /tmp"))
    }
}

// MARK: - Project Context Tests

@MainActor
struct ProjectContextTests {
    
    @Test
    func detectsPythonProject() {
        // This is a basic test - actual detection requires filesystem
        let markerFiles = ProjectType.python.markerFiles
        
        #expect(markerFiles.contains("requirements.txt"))
        #expect(markerFiles.contains("pyproject.toml"))
    }
    
    @Test
    func detectsNodeProject() {
        let markerFiles = ProjectType.node.markerFiles
        
        #expect(markerFiles.contains("package.json"))
    }
    
    @Test
    func pythonTestCommands() {
        let commands = ProjectType.python.testCommands
        
        #expect(commands.contains("pytest"))
        #expect(commands.contains("python -m pytest"))
    }
    
    @Test
    func nodeTestCommands() {
        let commands = ProjectType.node.testCommands
        
        #expect(commands.contains("npm test"))
    }
}

// MARK: - Feedback Store Tests

@MainActor
struct FeedbackStoreTests {
    
    @Test
    func recordsAndRetrievesFeedback() {
        let store = ClassificationFeedbackStore.shared
        let context = ClassificationContext(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            lastCommands: ["ls"],
            lastOutputSnippet: ""
        )
        
        // Clear any existing feedback for clean test
        store.clearAll()
        
        // Record a correction
        store.recordCorrection(
            input: "show me files",
            originalMode: .aiToShell,
            correctedMode: .terminal,
            context: context
        )
        
        // Check that pattern was learned
        let learnedMode = store.learnedMode(for: "show me files")
        #expect(learnedMode == .terminal)
    }
    
    @Test
    func patternMatchingWorks() {
        let store = ClassificationFeedbackStore.shared
        let context = ClassificationContext()
        
        store.clearAll()
        
        // Record feedback
        store.recordCorrection(
            input: "list all files",
            originalMode: .query,
            correctedMode: .aiToShell,
            context: context
        )
        
        // Same pattern should match
        let mode1 = store.learnedMode(for: "list all files")
        #expect(mode1 == .aiToShell)
    }
    
    @Test
    func statisticsCalculated() {
        let store = ClassificationFeedbackStore.shared
        let context = ClassificationContext()
        
        store.clearAll()
        
        // Record multiple feedbacks
        store.recordCorrection(input: "cmd1", originalMode: .terminal, correctedMode: .query, context: context)
        store.recordCorrection(input: "cmd2", originalMode: .terminal, correctedMode: .query, context: context)
        store.recordCorrection(input: "cmd3", originalMode: .query, correctedMode: .terminal, context: context)
        
        let stats = store.statistics()
        
        #expect(stats.totalCorrections == 3)
        #expect(stats.queryPreference > 0)
        #expect(stats.terminalPreference > 0)
    }
}

// MARK: - Classification Confidence Tests

struct ClassificationConfidenceTests {
    
    @Test
    func confidenceFromScore() {
        let certain = ClassificationConfidence.from(score: 0.95)
        let high = ClassificationConfidence.from(score: 0.80)
        let medium = ClassificationConfidence.from(score: 0.65)
        let low = ClassificationConfidence.from(score: 0.45)
        let uncertain = ClassificationConfidence.from(score: 0.10)
        
        #expect(certain == .certain)
        #expect(high == .high)
        #expect(medium == .medium)
        #expect(low == .low)
        #expect(uncertain == .uncertain)
    }
    
    @Test
    func confidenceComparison() {
        #expect(ClassificationConfidence.certain > ClassificationConfidence.high)
        #expect(ClassificationConfidence.high > ClassificationConfidence.medium)
        #expect(ClassificationConfidence.uncertain < ClassificationConfidence.low)
    }
    
    @Test
    func confidenceExecutionBehavior() {
        #expect(ClassificationConfidence.certain.shouldExecuteImmediately)
        #expect(ClassificationConfidence.high.shouldExecuteImmediately)
        #expect(!ClassificationConfidence.medium.shouldExecuteImmediately)
        #expect(ClassificationConfidence.low.shouldShowDisambiguation)
        #expect(ClassificationConfidence.uncertain.shouldShowDisambiguation)
    }
}

// MARK: - Command History Pattern Tests

struct CommandHistoryPatternTests {
    
    @Test
    func detectsRepetitivePattern() {
        let pattern = CommandHistoryPattern.analyze(["ls", "ls", "ls"])
        
        #expect(pattern == .repetitive)
    }
    
    @Test
    func detectsExploratoryPattern() {
        let pattern = CommandHistoryPattern.analyze(["ls", "cd foo", "cat file", "pwd", "git status"])
        
        #expect(pattern == .exploratory)
    }
    
    @Test
    func detectsDebuggingPattern() {
        let pattern = CommandHistoryPattern.analyze(["npm test", "npm test -- --grep foo", "npm test"])
        
        #expect(pattern == .repetitiveWithVariations)
    }
    
    @Test
    func detectsCommandSequence() {
        let pattern = CommandHistoryPattern.analyze(["cd /tmp", "ls"])
        
        #expect(pattern == .commandSequence)
    }
}
