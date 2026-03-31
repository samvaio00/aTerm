import Foundation

/// Analyzes input for shell syntax patterns
struct ShellSyntaxAnalyzer {
    
    // MARK: - Shell Syntax Patterns
    
    /// Regular expression patterns that indicate shell commands
    private static let patterns: [(pattern: String, weight: Double, description: String)] = [
        // Variable assignment
        ("^[a-zA-Z_][a-zA-Z0-9_]*=", 0.4, "Variable assignment"),
        
        // Pipes and redirects
        ("\\|", 0.35, "Pipe operator"),
        (">|>>|<", 0.35, "Redirection"),
        ("2>&1", 0.4, "File descriptor redirect"),
        
        // Command separators
        (";\\s*$|\\|\\||&&", 0.3, "Command chaining"),
        
        // Variable expansion
        ("\\$\\w+|\\$\\{[^}]+\\}|\\$\\(|\\`[^\\`]+\\`", 0.35, "Variable/command substitution"),
        
        // Wildcards
        ("\\*|\\?|\\[.+\\]", 0.25, "Glob pattern"),
        
        // Background/foreground
        ("&\\s*$|fg\\s|bg\\s", 0.3, "Job control"),
        
        // Shell conditionals and loops
        ("^\\s*if\\s|^\\s*then\\s|^\\s*fi\\s*$|^\\s*else\\s", 0.45, "If statement"),
        ("^\\s*for\\s|^\\s*while\\s|^\\s*do\\s|^\\s*done\\s*$", 0.45, "Loop"),
        ("^\\s*case\\s|^\\s*esac\\s*$", 0.45, "Case statement"),
        ("^\\s*function\\s|^\\s*\\(\\)\\s*\\{", 0.45, "Function definition"),
        
        // Common command flags
        ("\\s-\\w+|\\s--\\w+", 0.2, "Command flags"),
        
        // Path patterns
        ("^/|\\./|\\.\\./|~/", 0.3, "File path"),
        
        // Process substitution
        ("<\\(|>\\(", 0.4, "Process substitution"),
        
        // Heredoc
        ("<<\\w+|<<-\\w+", 0.4, "Heredoc"),
        
        // Common shell builtins with specific syntax
        ("^\\s*export\\s+|^\\s*source\\s+|^\\s*\\.\\s+", 0.35, "Shell builtin"),
        ("^\\s*alias\\s+|^\\s*unalias\\s+", 0.35, "Alias command"),
    ]
    
    // MARK: - Analysis Result
    
    struct SyntaxAnalysis {
        let shellScore: Double
        let matchedPatterns: [String]
        let complexityScore: Double
        let isScript: Bool
        let isMultiline: Bool
        
        var isLikelyShellCommand: Bool {
            shellScore >= 0.6
        }
        
        var confidence: ClassificationConfidence {
            ClassificationConfidence.from(score: shellScore)
        }
    }
    
    // MARK: - Analysis Methods
    
    /// Analyzes input for shell syntax patterns
    static func analyze(_ input: String) -> SyntaxAnalysis {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for multiline
        let isMultiline = trimmed.contains("\n")
        
        // If multiline, analyze complexity
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var totalScore: Double = 0
        var matchedPatterns: [String] = []
        var complexityIndicators = 0
        
        // Analyze each line
        for line in lines {
            for (pattern, weight, description) in patterns {
                if line.range(of: pattern, options: .regularExpression) != nil {
                    totalScore += weight
                    if !matchedPatterns.contains(description) {
                        matchedPatterns.append(description)
                    }
                }
            }
            
            // Count complexity indicators
            complexityIndicators += countComplexityIndicators(in: line)
        }
        
        // Bonus for multiple lines that look like a script
        if lines.count > 1 {
            complexityIndicators += lines.count / 2
        }
        
        // Cap score at 1.0
        let finalScore = min(totalScore, 1.0)
        let complexity = min(Double(complexityIndicators) / 5.0, 1.0)
        
        let isScript = isMultiline && (
            trimmed.hasPrefix("#!/") ||
            finalScore > 0.7 ||
            lines.count > 2
        )
        
        return SyntaxAnalysis(
            shellScore: finalScore,
            matchedPatterns: matchedPatterns,
            complexityScore: complexity,
            isScript: isScript,
            isMultiline: isMultiline
        )
    }
    
    /// Quick check for common command patterns
    static func isSimpleCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        
        guard let first = tokens.first.map(String.init) else {
            return false
        }
        
        // Check if it looks like a simple command: command [args...]
        // No shell syntax, no special characters
        let specialChars = CharacterSet(charactersIn: "|&;<>()$`\"'\\*?[]")
        
        return first.rangeOfCharacter(from: specialChars) == nil &&
               tokens.count <= 5 &&
               !trimmed.contains("\n")
    }
    
    /// Checks if input is likely a script that should be executed
    static func looksLikeScript(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Has shebang
        if trimmed.hasPrefix("#!/") {
            return true
        }
        
        // Multiple lines with shell structure
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard lines.count > 1 else { return false }
        
        // Check for script-like structure
        let analysis = analyze(trimmed)
        return analysis.shellScore > 0.5 && lines.count >= 2
    }
    
    /// Extracts the command name from input (first token)
    static func extractCommandName(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        
        guard let first = tokens.first.map(String.init) else {
            return nil
        }
        
        // Remove any variable assignment prefix
        if let equalsIndex = first.firstIndex(of: "=") {
            return String(first[first.index(after: equalsIndex)...])
        }
        
        return first
    }
    
    /// Checks if input contains dangerous commands
    static func containsDangerousCommand(_ input: String) -> Bool {
        let dangerousPatterns = [
            "rm\\s+-rf\\s+/",
            ">\\s*/\\w+",
            ":(){ :|:& };:",  // Fork bomb
            "dd\\s+if=.*of=/dev/",
            "mkfs\\.",
            "^\\s*shutdown",
            "^\\s*reboot",
        ]
        
        let lowercased = input.lowercased()
        for pattern in dangerousPatterns {
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
    
    // MARK: - Private Helpers
    
    private static func countComplexityIndicators(in line: String) -> Int {
        var count = 0
        
        // Count pipes
        count += line.components(separatedBy: "|").count - 1
        
        // Count redirects
        count += line.components(separatedBy: ">").count - 1
        count += line.components(separatedBy: "<").count - 1
        
        // Count command substitutions
        count += line.components(separatedBy: "$(").count - 1
        count += line.components(separatedBy: "`").count - 1
        
        // Count logical operators
        count += line.components(separatedBy: "&&").count - 1
        count += line.components(separatedBy: "||").count - 1
        
        return count
    }
}

// MARK: - Command Normalization

extension ShellSyntaxAnalyzer {
    /// Normalizes a command for comparison (removes extra spaces, lowercases, etc.)
    static func normalize(_ command: String) -> String {
        command
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    
    /// Extracts the "base" command (removes arguments and options)
    static func baseCommand(_ command: String) -> String {
        let normalized = normalize(command)
        let tokens = normalized.split(separator: " ", omittingEmptySubsequences: true)
        
        guard !tokens.isEmpty else { return "" }
        
        // Skip variable assignments
        var startIndex = 0
        for (i, token) in tokens.enumerated() {
            if token.contains("=") {
                startIndex = i + 1
            } else {
                break
            }
        }
        
        guard startIndex < tokens.count else { return "" }
        return String(tokens[startIndex])
    }
    
    /// Calculates similarity between two commands (0.0 - 1.0)
    static func similarity(between command1: String, and command2: String) -> Double {
        let base1 = baseCommand(command1)
        let base2 = baseCommand(command2)
        
        if base1 == base2 {
            return 1.0
        }
        
        // Check if one is a prefix of the other
        if base1.hasPrefix(base2) || base2.hasPrefix(base1) {
            let longer = max(base1.count, base2.count)
            let shorter = min(base1.count, base2.count)
            return Double(shorter) / Double(longer)
        }
        
        // Simple Levenshtein distance could go here
        // For now, just check if they share the first word
        return 0.0
    }
}

// MARK: - Multi-line Input Handling

struct MultilineInput {
    let lines: [String]
    let isScript: Bool
    let detectedLanguage: String?
    
    init(_ input: String) {
        let rawLines = input.components(separatedBy: .newlines)
        self.lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Detect if it's a script
        self.isScript = lines.first?.hasPrefix("#!/") ?? false
        
        // Detect language from shebang
        if let shebang = lines.first, shebang.hasPrefix("#!/") {
            let interpreter = shebang.components(separatedBy: "/").last ?? ""
            if interpreter.contains("python") {
                self.detectedLanguage = "python"
            } else if interpreter.contains("ruby") {
                self.detectedLanguage = "ruby"
            } else if interpreter.contains("node") || interpreter.contains("bash") || interpreter.contains("sh") {
                self.detectedLanguage = "shell"
            } else {
                self.detectedLanguage = interpreter
            }
        } else {
            self.detectedLanguage = nil
        }
    }
    
    /// Determines the appropriate mode for this multi-line input
    func suggestedMode() -> InputMode {
        if isScript {
            return .terminal  // Execute the script
        }
        
        // If it looks like code to be explained
        let shellAnalysis = ShellSyntaxAnalyzer.analyze(lines.joined(separator: "\n"))
        if shellAnalysis.isScript {
            return .terminal
        }
        
        // Default to query for multi-line natural language or code explanation
        return .query
    }
}
