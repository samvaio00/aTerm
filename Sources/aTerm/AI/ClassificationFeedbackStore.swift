import Foundation

/// Stores user feedback on classification decisions to improve future classifications
@MainActor
final class ClassificationFeedbackStore {
    static let shared = ClassificationFeedbackStore()
    
    private let defaults = UserDefaults.standard
    private let feedbackKey = "classificationFeedback"
    private let patternKey = "classificationPatterns"
    private let aliasKey = "learnedAliases"
    
    private var feedbackCache: [ClassificationFeedback] = []
    private var patternCache: [InputPattern: InputMode] = [:]
    private var aliasCache: [String: String] = [:]
    private var userPreferenceProfile: UserPreferenceProfile = .assisted
    
    private init() {
        loadFromStorage()
    }
    
    // MARK: - Types
    
    /// A specific classification feedback entry
    struct ClassificationFeedback: Codable, Equatable {
        let input: String
        let originalMode: InputMode
        let correctedMode: InputMode
        let timestamp: Date
        let context: FeedbackContext
        
        struct FeedbackContext: Codable, Equatable {
            let projectType: String?
            let wasAmbiguous: Bool
        }
    }
    
    /// Pattern extracted from input for matching similar inputs
    struct InputPattern: Hashable, Codable {
        let firstWord: String
        let wordCount: Int
        let hasQuestionMark: Bool
        let hasShellSyntax: Bool
        
        init(from input: String) {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let words = trimmed.split(separator: " ")
            
            self.firstWord = words.first.map(String.init) ?? ""
            self.wordCount = words.count
            self.hasQuestionMark = trimmed.hasSuffix("?")
            self.hasShellSyntax = ShellSyntaxAnalyzer.analyze(trimmed).shellScore > 0.3
        }
        
        func matches(_ input: String) -> Bool {
            let other = InputPattern(from: input)
            return firstWord == other.firstWord &&
                   wordCount == other.wordCount &&
                   hasQuestionMark == other.hasQuestionMark &&
                   hasShellSyntax == other.hasShellSyntax
        }
    }
    
    // MARK: - Feedback Recording
    
    /// Records that a user corrected a classification
    func recordCorrection(
        input: String,
        originalMode: InputMode,
        correctedMode: InputMode,
        context: ClassificationContext
    ) {
        let feedback = ClassificationFeedback(
            input: input,
            originalMode: originalMode,
            correctedMode: correctedMode,
            timestamp: Date(),
            context: .init(
                projectType: context.projectType.rawValue,
                wasAmbiguous: originalMode != correctedMode
            )
        )
        
        feedbackCache.append(feedback)
        
        // Store pattern for quick matching
        let pattern = InputPattern(from: input)
        patternCache[pattern] = correctedMode
        
        // If this is a correction to terminal mode, store as potential alias
        if correctedMode == .terminal {
            let normalized = ShellSyntaxAnalyzer.normalize(input)
            if let existingCommand = feedbackCache
                .first(where: { $0.correctedMode == .terminal && ShellSyntaxAnalyzer.normalize($0.input) == normalized })
                .map({ $0.input }) {
                // Learn this as an alias pattern
                aliasCache[normalized] = existingCommand
            }
        }
        
        // Trim old feedback (keep last 100)
        if feedbackCache.count > 100 {
            feedbackCache.removeFirst(feedbackCache.count - 100)
        }
        
        // Update user preference profile based on behavior
        updateUserPreferenceProfile()
        
        saveToStorage()
    }
    
    /// Records an explicit choice during disambiguation
    func recordDisambiguationChoice(input: String, chosenMode: InputMode, context: ClassificationContext) {
        recordCorrection(
            input: input,
            originalMode: .terminal, // Assume terminal was default
            correctedMode: chosenMode,
            context: context
        )
    }
    
    // MARK: - Querying Feedback
    
    /// Checks if we have learned a mode for this exact input or pattern
    func learnedMode(for input: String) -> InputMode? {
        // Check exact match first
        let normalized = ShellSyntaxAnalyzer.normalize(input)
        if let exact = feedbackCache.first(where: { 
            ShellSyntaxAnalyzer.normalize($0.input) == normalized 
        }) {
            return exact.correctedMode
        }
        
        // Check pattern match
        let pattern = InputPattern(from: input)
        if let mode = patternCache[pattern] {
            return mode
        }
        
        // Check for similar patterns
        return findSimilarPatternMatch(for: input)
    }
    
    /// Gets the user's preference profile based on their correction history
    var preferenceProfile: UserPreferenceProfile {
        userPreferenceProfile
    }
    
    /// Returns learned aliases (common typos or shortcuts)
    func learnedAliases() -> [String: String] {
        aliasCache
    }
    
    /// Checks if an input is a known alias
    func resolveAlias(_ input: String) -> String? {
        let normalized = ShellSyntaxAnalyzer.normalize(input)
        return aliasCache[normalized]
    }
    
    /// Returns statistics on user behavior
    func statistics() -> FeedbackStatistics {
        let total = feedbackCache.count
        guard total > 0 else {
            return FeedbackStatistics(
                totalCorrections: 0,
                terminalPreference: 0,
                aiToShellPreference: 0,
                queryPreference: 0,
                profile: .assisted
            )
        }
        
        let terminalCount = feedbackCache.filter { $0.correctedMode == .terminal }.count
        let aiToShellCount = feedbackCache.filter { $0.correctedMode == .aiToShell }.count
        let queryCount = feedbackCache.filter { $0.correctedMode == .query }.count
        
        return FeedbackStatistics(
            totalCorrections: total,
            terminalPreference: Double(terminalCount) / Double(total),
            aiToShellPreference: Double(aiToShellCount) / Double(total),
            queryPreference: Double(queryCount) / Double(total),
            profile: userPreferenceProfile
        )
    }
    
    // MARK: - Private Methods
    
    private func findSimilarPatternMatch(for input: String) -> InputMode? {
        let targetPattern = InputPattern(from: input)
        
        // Find patterns with same first word
        let candidates = patternCache.filter { $0.key.firstWord == targetPattern.firstWord }
        
        guard !candidates.isEmpty else { return nil }
        
        // Score candidates by similarity
        var bestMatch: (pattern: InputPattern, mode: InputMode, score: Double)?
        
        for (pattern, mode) in candidates {
            var score = 0.0
            
            if pattern.wordCount == targetPattern.wordCount {
                score += 0.3
            }
            
            if pattern.hasQuestionMark == targetPattern.hasQuestionMark {
                score += 0.2
            }
            
            if pattern.hasShellSyntax == targetPattern.hasShellSyntax {
                score += 0.2
            }
            
            // Word count difference penalty
            score -= Double(abs(pattern.wordCount - targetPattern.wordCount)) * 0.1
            
            if bestMatch == nil || score > bestMatch!.score {
                bestMatch = (pattern, mode, score)
            }
        }
        
        // Only return if confidence is high enough
        if let match = bestMatch, match.score > 0.5 {
            return match.mode
        }
        
        return nil
    }
    
    private func updateUserPreferenceProfile() {
        let stats = statistics()
        
        // Determine profile based on behavior
        if stats.terminalPreference > 0.6 {
            userPreferenceProfile = .expert
        } else if stats.queryPreference > 0.4 {
            userPreferenceProfile = .exploratory
        } else {
            userPreferenceProfile = .assisted
        }
    }
    
    // MARK: - Persistence
    
    private func loadFromStorage() {
        if let data = defaults.data(forKey: feedbackKey),
           let decoded = try? JSONDecoder().decode([ClassificationFeedback].self, from: data) {
            feedbackCache = decoded
        }
        
        if let data = defaults.data(forKey: patternKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            var restored: [InputPattern: InputMode] = [:]
            for (key, value) in decoded {
                guard let keyData = key.data(using: .utf8),
                      let pattern = try? JSONDecoder().decode(InputPattern.self, from: keyData),
                      let mode = InputMode(rawValue: value) else {
                    continue
                }
                restored[pattern] = mode
            }
            patternCache = restored
        }
        
        if let aliases = defaults.dictionary(forKey: aliasKey) as? [String: String] {
            aliasCache = aliases
        }
        
        updateUserPreferenceProfile()
    }
    
    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(feedbackCache) {
            defaults.set(data, forKey: feedbackKey)
        }
        
        let patternDict: [String: String] = patternCache.reduce(into: [:]) { dict, entry in
            if let data = try? JSONEncoder().encode(entry.key),
               let key = String(data: data, encoding: .utf8) {
                dict[key] = entry.value.rawValue
            }
        }
        defaults.set(patternDict, forKey: patternKey)
        
        defaults.set(aliasCache, forKey: aliasKey)
    }
    
    /// Clears all learned feedback (for testing or reset)
    func clearAll() {
        feedbackCache.removeAll()
        patternCache.removeAll()
        aliasCache.removeAll()
        saveToStorage()
    }
}

// MARK: - Statistics

struct FeedbackStatistics {
    let totalCorrections: Int
    let terminalPreference: Double
    let aiToShellPreference: Double
    let queryPreference: Double
    let profile: UserPreferenceProfile
    
    var dominantMode: InputMode {
        if terminalPreference >= max(aiToShellPreference, queryPreference) {
            return .terminal
        } else if aiToShellPreference >= queryPreference {
            return .aiToShell
        } else {
            return .query
        }
    }
}

// MARK: - Helper Extensions

private extension Dictionary {
    func compactMapKeysAndValues<T>(_ transform: (Key, Value) -> T?) -> [Key: T] {
        var result: [Key: T] = [:]
        for (key, value) in self {
            if let transformed = transform(key, value) {
                result[key] = transformed
            }
        }
        return result
    }
}
