import Foundation

struct TermConfig {
    var profileName: String?
    var aiProvider: String?
    var aiModel: String?
    var classifierModel: String?
    var mcpServers: [String] = []
    var defaultAgent: String?
    var agentAutoStart: Bool = false

    static func load(from directory: URL) -> TermConfig? {
        let url = directory.appendingPathComponent(".termconfig")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    static func parse(_ text: String) -> TermConfig {
        var config = TermConfig()
        var section = ""

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }

            let key = parts[0]
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch (section, key) {
            case ("profile", "name"):
                config.profileName = value
            case ("ai", "provider"):
                config.aiProvider = value
            case ("ai", "model"):
                config.aiModel = value
            case ("ai", "classifier_model"):
                config.classifierModel = value
            case ("mcp", "servers"):
                config.mcpServers = value
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
            case ("agents", "default"):
                config.defaultAgent = value
            case ("agents", "auto_start"):
                config.agentAutoStart = value.lowercased() == "true"
            default:
                break
            }
        }

        return config
    }
}
