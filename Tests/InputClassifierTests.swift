import Foundation
import Testing
@testable import aTerm

@MainActor
struct InputClassifierTests {
    // MARK: - Terminal Mode Classification
    
    @Test
    func classifiesSimpleCommandLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        let mode = try await classifier.classify("ls", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .terminal)
    }
    
    @Test
    func classifiesCommandWithArgsLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("ls -la", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("cd /tmp", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("echo hello world", context: context, provider: nil, modelID: nil) == .terminal)
    }
    
    @Test
    func classifiesBuiltinCommandsLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        let builtins = ["cd", "echo", "export", "source", "alias", "pwd", "exit", "history"]
        for cmd in builtins {
            let mode = try await classifier.classify("\(cmd) something", context: context, provider: nil, modelID: nil)
            #expect(mode == .terminal, "Expected \(cmd) to be classified as terminal")
        }
    }
    
    @Test
    func classifiesAbsolutePathLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        let mode = try await classifier.classify("/usr/bin/python3", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .terminal)
    }
    
    @Test
    func classifiesRelativePathLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("./script.sh", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("../bin/app", context: context, provider: nil, modelID: nil) == .terminal)
    }
    
    // MARK: - Query Mode Classification (via prefixes or force prefix)
    
    @Test
    func classifiesQuestionPrefixesAsQuery() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        // These should be classified as query based on interrogative prefixes
        #expect(try await classifier.classify("what is git", context: context, provider: nil, modelID: nil) == .query)
        #expect(try await classifier.classify("how do I use docker", context: context, provider: nil, modelID: nil) == .query)
        #expect(try await classifier.classify("why is my build failing", context: context, provider: nil, modelID: nil) == .query)
    }
    
    @Test
    func classifiesExplainAsQuery() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("explain this error", context: context, provider: nil, modelID: nil) == .query)
        #expect(try await classifier.classify("explain the output", context: context, provider: nil, modelID: nil) == .query)
        #expect(try await classifier.classify("can you explain this", context: context, provider: nil, modelID: nil) == .query)
        #expect(try await classifier.classify("could you explain ls", context: context, provider: nil, modelID: nil) == .query)
    }
    
    @Test
    func classifiesDescribeAsQuery() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("describe the process", context: context, provider: nil, modelID: nil) == .query)
    }
    
    @Test
    func classifiesTellMeAsQuery() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("tell me about git", context: context, provider: nil, modelID: nil) == .query)
    }
    
    @Test
    func classifiesQuestionMarkAsQuery() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        // Ends with ? should trigger query mode
        let mode = try await classifier.classify("what is this?", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .query)
    }
    
    // MARK: - AI-to-Shell Classification
    
    @Test
    func classifiesActionVerbWithSystemNoun() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        // Action verb + system noun should trigger AI-to-shell
        // Note: Some verbs like 'find', 'kill', 'list' are actual commands, so they may be classified as terminal
        // We test with phrases that are clearly natural language requests
        #expect(try await classifier.classify("search for log files", context: context, provider: nil, modelID: nil) == .aiToShell)
        #expect(try await classifier.classify("display running processes", context: context, provider: nil, modelID: nil) == .aiToShell)
        #expect(try await classifier.classify("stop process on port 3000", context: context, provider: nil, modelID: nil) == .aiToShell)
        #expect(try await classifier.classify("get all directories", context: context, provider: nil, modelID: nil) == .aiToShell)
    }
    
    @Test
    func classifiesCompressExtractAsAIShell() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        // Note: "compress" is an actual command, so we use "archive" (verb) + "files" instead
        // "archive" + "files" triggers ai-to-shell
        #expect(try await classifier.classify("archive these files", context: context, provider: nil, modelID: nil) == .aiToShell)
        // "extract" + "archive" triggers ai-to-shell
        #expect(try await classifier.classify("extract this archive", context: context, provider: nil, modelID: nil) == .aiToShell)
    }
    
    @Test
    func classifiesCreateMakeAsAIShell() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("create new folder", context: context, provider: nil, modelID: nil) == .aiToShell)
        // Note: "make" is a build command, so "create a backup" is better
        #expect(try await classifier.classify("generate a backup", context: context, provider: nil, modelID: nil) == .aiToShell)
    }
    
    @Test
    func classifiesCheckMonitorAsAIShell() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("check disk usage", context: context, provider: nil, modelID: nil) == .aiToShell)
        #expect(try await classifier.classify("monitor cpu usage", context: context, provider: nil, modelID: nil) == .aiToShell)
    }
    
    @Test
    func classifiesSearchGrepAsAIShell() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        // "search for" + "files" triggers ai-to-shell
        #expect(try await classifier.classify("search for TODO in files", context: context, provider: nil, modelID: nil) == .aiToShell)
        // "search" + "logs" triggers ai-to-shell
        #expect(try await classifier.classify("search logs for errors", context: context, provider: nil, modelID: nil) == .aiToShell)
    }
    
    // MARK: - Force Prefixes
    
    @Test
    func forceTerminalPrefix() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        // "what is" normally query, but $ forces terminal
        let mode = try await classifier.classify("$ what is", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .terminal)
    }
    
    @Test
    func forceQueryPrefix() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        // "ls" normally terminal, but ! forces query
        let mode = try await classifier.classify("! ls", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .query)
    }
    
    @Test
    func forceAIShellPrefix() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        // "ls" normally terminal, but > forces aiToShell
        let mode = try await classifier.classify("> ls", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .aiToShell)
    }
    
    // MARK: - Stripped Input
    
    @Test
    func strippedOverrideInput() {
        let classifier = InputClassifier()
        
        #expect(classifier.strippedOverrideInput("$ ls") == "ls")
        #expect(classifier.strippedOverrideInput("! what") == "what")
        #expect(classifier.strippedOverrideInput("> find") == "find")
        #expect(classifier.strippedOverrideInput("ls") == "ls")
        #expect(classifier.strippedOverrideInput("  $ ls  ") == "ls")
    }
    
    // MARK: - Edge Cases
    
    @Test
    func emptyInputIsTerminal() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        let mode = try await classifier.classify("", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .terminal)
    }
    
    @Test
    func whitespaceOnlyIsTerminal() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        let mode = try await classifier.classify("   ", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .terminal)
    }
    
    @Test
    func chainedCommandsAreTerminal() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("ls && pwd", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("cat file | grep text", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("echo hello; echo world", context: context, provider: nil, modelID: nil) == .terminal)
    }
    
    @Test
    func commandSubstitutionIsTerminal() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        let mode = try await classifier.classify("echo $(date)", context: context, provider: nil, modelID: nil)
        
        #expect(mode == .terminal)
    }
    
    @Test
    func complexGitCommandsAreTerminal() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("git log --oneline -10", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("git status", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("git commit -m 'fix bug'", context: context, provider: nil, modelID: nil) == .terminal)
    }
    
    @Test
    func dockerCommandsAreTerminal() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("docker ps", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("docker-compose up", context: context, provider: nil, modelID: nil) == .terminal)
    }
    
    @Test
    func npmYarnCommandsAreTerminal() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
        
        #expect(try await classifier.classify("npm install", context: context, provider: nil, modelID: nil) == .terminal)
        #expect(try await classifier.classify("npm run build", context: context, provider: nil, modelID: nil) == .terminal)
    }
}
