import Foundation

/// Detects project type and git context from working directory
@MainActor
final class ProjectContextDetector {
    static let shared = ProjectContextDetector()
    
    private let cache = NSCache<NSString, ProjectCacheEntry>()
    private let fileManager = FileManager.default
    
    struct ProjectInfo {
        let type: ProjectType
        let gitBranch: String?
        let rootDirectory: URL?
    }
    
    private final class ProjectCacheEntry: NSObject {
        let info: ProjectInfo
        let timestamp: Date
        let directoryModDate: Date?
        
        init(info: ProjectInfo, timestamp: Date, directoryModDate: Date?) {
            self.info = info
            self.timestamp = timestamp
            self.directoryModDate = directoryModDate
        }
    }
    
    /// Detects project information for a given directory
    func detectProjectInfo(for directory: URL?) -> ProjectInfo {
        guard let directory = directory else {
            return ProjectInfo(type: .generic, gitBranch: nil, rootDirectory: nil)
        }
        
        let path = directory.path as NSString
        
        // Check cache first
        if let cached = cache.object(forKey: path) {
            // Validate cache is still fresh (check if directory mod date changed)
            let currentModDate = try? fileManager.attributesOfItem(atPath: directory.path)[.modificationDate] as? Date
            if cached.directoryModDate == currentModDate,
               Date().timeIntervalSince(cached.timestamp) < 300 { // 5 minute cache
                return cached.info
            }
        }
        
        // Detect project type
        let type = detectProjectType(in: directory)
        
        // Detect git branch
        let (gitBranch, gitRoot) = detectGitInfo(in: directory)
        
        let info = ProjectInfo(type: type, gitBranch: gitBranch, rootDirectory: gitRoot)
        
        // Cache result
        let modDate = try? fileManager.attributesOfItem(atPath: directory.path)[.modificationDate] as? Date
        cache.setObject(
            ProjectCacheEntry(info: info, timestamp: Date(), directoryModDate: modDate),
            forKey: path
        )
        
        return info
    }
    
    /// Detects the project type by looking for marker files
    private func detectProjectType(in directory: URL) -> ProjectType {
        // Check current directory first
        if let type = checkDirectoryForProjectType(directory) {
            return type
        }
        
        // Walk up parent directories looking for project markers
        var currentDir = directory
        while currentDir.path != "/" && currentDir.path != NSHomeDirectory() {
            currentDir = currentDir.deletingLastPathComponent()
            if let type = checkDirectoryForProjectType(currentDir), type != .gitOnly {
                return type
            }
        }
        
        // Check if it's at least a git repo
        if isGitRepository(directory) {
            return .gitOnly
        }
        
        return .generic
    }
    
    /// Checks a specific directory for project type markers
    private func checkDirectoryForProjectType(_ directory: URL) -> ProjectType? {
        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: directory.path)
        } catch {
            return nil
        }
        
        // Check each project type (order matters - more specific before generic)
        let orderedTypes: [ProjectType] = [
            .python, .node, .rust, .go, .ruby, .swift, .docker
        ]
        
        for type in orderedTypes {
            for marker in type.markerFiles {
                // Support wildcards
                if marker.hasPrefix("*") {
                    let ext = String(marker.dropFirst())
                    if contents.contains(where: { $0.hasSuffix(ext) }) {
                        return type
                    }
                } else if contents.contains(marker) {
                    return type
                }
            }
        }
        
        // Special case: check for Python files if no markers
        if contents.contains(where: { $0.hasSuffix(".py") }) {
            return .python
        }
        
        // Special case: check for JS/TS files
        if contents.contains(where: { $0.hasSuffix(".js") || $0.hasSuffix(".ts") }) {
            return .node
        }
        
        return nil
    }
    
    /// Detects git branch and root directory
    private func detectGitInfo(in directory: URL) -> (branch: String?, root: URL?) {
        // Use git command to get branch and root
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", directory.path, "rev-parse", "--abbrev-ref", "HEAD"]
        task.environment = ["LANG": "en_US.UTF-8"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Suppress errors
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let branch = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Also get the git root
            let rootTask = Process()
            rootTask.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            rootTask.arguments = ["-C", directory.path, "rev-parse", "--show-toplevel"]
            rootTask.environment = ["LANG": "en_US.UTF-8"]
            
            let rootPipe = Pipe()
            rootTask.standardOutput = rootPipe
            rootTask.standardError = Pipe()
            
            try rootTask.run()
            rootTask.waitUntilExit()
            
            let rootData = rootPipe.fileHandleForReading.readDataToEndOfFile()
            let rootPath = String(data: rootData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let root = rootPath.flatMap { URL(fileURLWithPath: $0) }
            
            // Filter out error states
            if let branch = branch, branch != "HEAD", !branch.isEmpty {
                return (branch, root)
            }
        } catch {
            // Git not available or not a repo
        }
        
        return (nil, nil)
    }
    
    /// Checks if directory is inside a git repository
    private func isGitRepository(_ directory: URL) -> Bool {
        let gitDir = directory.appendingPathComponent(".git")
        return fileManager.fileExists(atPath: gitDir.path)
    }
    
    /// Clears the cache (call when project structure might have changed)
    func invalidateCache(for directory: URL?) {
        guard let directory = directory else {
            cache.removeAllObjects()
            return
        }
        cache.removeObject(forKey: directory.path as NSString)
    }
}

// MARK: - Command Suggestions

extension ProjectContextDetector {
    /// Suggests commands based on project context
    func suggestCommands(for projectType: ProjectType, intent: UserIntent) -> [String] {
        switch intent {
        case .test:
            return projectType.testCommands
        case .build:
            return projectType.buildCommands
        case .installDependencies:
            return dependencyCommands(for: projectType)
        case .run:
            return runCommands(for: projectType)
        }
    }
    
    enum UserIntent {
        case test
        case build
        case installDependencies
        case run
    }
    
    private func dependencyCommands(for type: ProjectType) -> [String] {
        switch type {
        case .python:
            return ["pip install -r requirements.txt", "pip install -e .", "poetry install"]
        case .node:
            return ["npm install", "yarn install", "pnpm install"]
        case .rust:
            return ["cargo build"]
        case .go:
            return ["go mod download", "go mod tidy"]
        case .ruby:
            return ["bundle install", "gem install"]
        case .swift:
            return ["swift package resolve", "swift package update"]
        case .docker:
            return ["docker pull"]
        case .gitOnly, .generic:
            return []
        }
    }
    
    private func runCommands(for type: ProjectType) -> [String] {
        switch type {
        case .python:
            return ["python main.py", "python app.py", "python -m http.server"]
        case .node:
            return ["npm start", "node index.js", "node server.js"]
        case .rust:
            return ["cargo run"]
        case .go:
            return ["go run .", "go run main.go"]
        case .ruby:
            return ["ruby app.rb", "rails server"]
        case .swift:
            return ["swift run"]
        case .docker:
            return ["docker-compose up"]
        case .gitOnly, .generic:
            return []
        }
    }
}
