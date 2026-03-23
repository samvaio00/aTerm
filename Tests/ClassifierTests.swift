import Testing
@testable import aTerm

@MainActor
struct ClassifierTests {
    @Test
    func classifiesShellCommandLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")

        let mode = try await classifier.classify("ls -la", context: context, provider: nil, modelID: nil)

        #expect(mode == .terminal)
    }

    @Test
    func classifiesQuestionLocally() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: ["npm test"], lastOutputSnippet: "1 failing")

        let mode = try await classifier.classify("what's wrong with that test?", context: context, provider: nil, modelID: nil)

        #expect(mode == .query)
    }

    @Test
    func respectsForcePrefix() async throws {
        let classifier = InputClassifier()
        let context = ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")

        let mode = try await classifier.classify("> find my largest log files", context: context, provider: nil, modelID: nil)

        #expect(mode == .aiToShell)
    }
}
