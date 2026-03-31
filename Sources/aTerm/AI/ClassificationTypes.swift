import Foundation

// MARK: - Input Mode

enum InputMode: String, CaseIterable, Codable {
    case terminal = "TERMINAL"
    case aiToShell = "AI_TO_SHELL"
    case query = "QUERY"
}

// MARK: - Classification Confidence

/// Confidence level for a classification decision
enum ClassificationConfidence: Double, Comparable {
    case certain = 0.90
    case high = 0.75
    case medium = 0.60
    case low = 0.40
    case uncertain = 0.20
    
    var description: String {
        switch self {
        case .certain: return "Certain"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .uncertain: return "Uncertain"
        }
    }
    
    var shouldExecuteImmediately: Bool {
        self >= .high
    }
    
    var shouldShowDisambiguation: Bool {
        self <= .low
    }
    
    static func from(score: Double) -> ClassificationConfidence {
        if score >= Self.certain.rawValue { return .certain }
        if score >= Self.high.rawValue { return .high }
        if score >= Self.medium.rawValue { return .medium }
        if score >= Self.low.rawValue { return .low }
        return .uncertain
    }
    
    static func < (lhs: ClassificationConfidence, rhs: ClassificationConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Classification Result

/// Result of classifying user input
struct ClassificationResult {
    let mode: InputMode
    let confidence: ClassificationConfidence
    let score: Double
    let explanation: ClassificationExplanation
    
    static func uncertain(_ candidates: [InputMode] = InputMode.allCases) -> ClassificationResult {
        ClassificationResult(
            mode: .terminal,
            confidence: .uncertain,
            score: 0.0,
            explanation: ClassificationExplanation(
                primaryMode: .terminal,
                confidenceScore: 0.0,
                reasons: ["Unable to determine input type"],
                contributingFactors: [:],
                alternativeModes: candidates
            )
        )
    }
}

// MARK: - Classification Explanation

/// Explains why a classification decision was made
struct ClassificationExplanation {
    let primaryMode: InputMode
    let confidenceScore: Double
    let reasons: [String]
    let contributingFactors: [String: Double]
    let alternativeModes: [InputMode]
    
    var summary: String {
        let topReasons = reasons.prefix(2).joined(separator: "; ")
        return "\(primaryMode.rawValue) (\(confidenceScore.percentage)): \(topReasons)"
    }
    
    var userHint: String? {
        if alternativeModes.contains(.terminal) && primaryMode != .terminal {
            return "⌘↵ to run as command"
        } else if alternativeModes.contains(.query) && primaryMode != .query {
            return "⌥↵ to ask AI"
        }
        return nil
    }
}

// MARK: - Enhanced Context

/// Project type detected from directory contents
enum ProjectType: String, CaseIterable {
    case python = "Python"
    case node = "Node.js"
    case rust = "Rust"
    case go = "Go"
    case ruby = "Ruby"
    case swift = "Swift"
    case docker = "Docker"
    case gitOnly = "Git"
    case generic = "Generic"
    
    /// File patterns that identify this project type
    var markerFiles: [String] {
        switch self {
        case .python:
            return ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile", "poetry.lock"]
        case .node:
            return ["package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml"]
        case .rust:
            return ["Cargo.toml", "Cargo.lock"]
        case .go:
            return ["go.mod", "go.sum"]
        case .ruby:
            return ["Gemfile", "Gemfile.lock", "*.gemspec"]
        case .swift:
            return ["Package.swift", "*.xcodeproj", "*.xcworkspace"]
        case .docker:
            return ["Dockerfile", "docker-compose.yml", "docker-compose.yaml"]
        case .gitOnly:
            return [".git"]
        case .generic:
            return []
        }
    }
    
    /// Common test commands for this project type
    var testCommands: [String] {
        switch self {
        case .python:
            return ["pytest", "python -m pytest", "python -m unittest", "tox"]
        case .node:
            return ["npm test", "yarn test", "pnpm test"]
        case .rust:
            return ["cargo test"]
        case .go:
            return ["go test", "go test ./..."]
        case .ruby:
            return ["rspec", "bundle exec rspec", "rake test"]
        case .swift:
            return ["swift test", "xcodebuild test"]
        case .docker:
            return ["docker build .", "docker-compose up"]
        case .gitOnly, .generic:
            return []
        }
    }
    
    /// Common build commands for this project type
    var buildCommands: [String] {
        switch self {
        case .python:
            return ["python setup.py build", "pip install -e ."]
        case .node:
            return ["npm run build", "yarn build", "tsc"]
        case .rust:
            return ["cargo build", "cargo build --release"]
        case .go:
            return ["go build", "go build ./..."]
        case .ruby:
            return ["bundle install", "gem build"]
        case .swift:
            return ["swift build", "xcodebuild"]
        case .docker:
            return ["docker build ."]
        case .gitOnly, .generic:
            return []
        }
    }
}

/// Enhanced classification context with rich project and session information
struct ClassificationContext {
    let workingDirectory: URL?
    let lastCommands: [String]
    let lastOutputSnippet: String
    let lastExitCode: Int?
    let gitBranch: String?
    let projectType: ProjectType
    let recentFailures: [String]
    let sessionDuration: TimeInterval?
    let commandHistoryPattern: CommandHistoryPattern
    
    init(
        workingDirectory: URL? = nil,
        lastCommands: [String] = [],
        lastOutputSnippet: String = "",
        lastExitCode: Int? = nil,
        gitBranch: String? = nil,
        projectType: ProjectType = .generic,
        recentFailures: [String] = [],
        sessionDuration: TimeInterval? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.lastCommands = lastCommands
        self.lastOutputSnippet = lastOutputSnippet
        self.lastExitCode = lastExitCode
        self.gitBranch = gitBranch
        self.projectType = projectType
        self.recentFailures = recentFailures
        self.sessionDuration = sessionDuration
        self.commandHistoryPattern = CommandHistoryPattern.analyze(lastCommands)
    }
    
    /// Creates a basic context when detailed info isn't available
    static func basic(workingDirectory: URL?, lastCommands: [String], lastOutputSnippet: String) -> ClassificationContext {
        ClassificationContext(
            workingDirectory: workingDirectory,
            lastCommands: lastCommands,
            lastOutputSnippet: lastOutputSnippet
        )
    }
    
    /// Returns true if the last command failed
    var lastCommandFailed: Bool {
        guard let code = lastExitCode else { return false }
        return code != 0
    }
    
    /// Returns true if the user appears to be debugging (repeated similar commands)
    var isDebugging: Bool {
        commandHistoryPattern == .repetitiveWithVariations
    }
}

/// Patterns detected in command history
enum CommandHistoryPattern {
    case none
    case exploratory          // Many different commands
    case repetitive           // Same command repeated
    case repetitiveWithVariations  // Similar commands with small changes (debugging)
    case commandSequence      // Common sequences (cd + ls, git add + git commit)
    
    static func analyze(_ commands: [String]) -> CommandHistoryPattern {
        guard commands.count >= 2 else { return .none }
        
        let normalized = commands.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        // Check for exact repetition
        let uniqueCommands = Set(normalized)
        if uniqueCommands.count == 1 {
            return .repetitive
        }
        
        // Check for variations (same command base, different args)
        let bases = normalized.map { $0.split(separator: " ").first.map(String.init) ?? "" }
        let uniqueBases = Set(bases)
        if uniqueBases.count == 1 && uniqueCommands.count > 1 {
            return .repetitiveWithVariations
        }
        
        // Check for common sequences
        let sequencePatterns: [[String]] = [
            ["cd", "ls"],
            ["git add", "git commit"],
            ["docker build", "docker run"],
        ]
        
        for pattern in sequencePatterns {
            if normalized.count >= pattern.count {
                let recent = Array(normalized.suffix(pattern.count))
                let matches = zip(recent, pattern).allSatisfy { cmd, expected in
                    cmd.hasPrefix(expected)
                }
                if matches {
                    return .commandSequence
                }
            }
        }
        
        return .exploratory
    }
}

// MARK: - User Preference Profile

/// User's preference for AI assistance level
enum UserPreferenceProfile: String, CaseIterable {
    case expert = "Expert"           // Prefers direct terminal, rarely uses AI
    case assisted = "Assisted"       // Balanced, uses disambiguation
    case exploratory = "Exploratory" // Prefers AI suggestions
    
    var defaultWhenUncertain: InputMode {
        switch self {
        case .expert: return .terminal
        case .assisted: return .query
        case .exploratory: return .aiToShell
        }
    }
    
    var confidenceThreshold: Double {
        switch self {
        case .expert: return 0.6      // Lower threshold to prefer terminal
        case .assisted: return 0.75   // Balanced
        case .exploratory: return 0.85 // Higher threshold, more AI involvement
        }
    }
}

// MARK: - Helper Extensions

private extension Double {
    var percentage: String {
        String(format: "%.0f%%", self * 100)
    }
}
