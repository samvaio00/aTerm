import Foundation

struct SessionStore {
    struct StoredPane: Codable {
        let id: UUID
        let title: String
        let workingDirectoryPath: String?
        let profileID: UUID?
        let agentDefinitionID: String?

        var workingDirectoryURL: URL? {
            guard let workingDirectoryPath else { return nil }
            return URL(fileURLWithPath: workingDirectoryPath)
        }
    }

    struct StoredTab: Codable {
        let id: UUID
        let title: String
        let workingDirectoryPath: String?
        let profileID: UUID?
        let agentDefinitionID: String?
        let activePaneID: UUID?
        let splitOrientation: String?
        let panes: [StoredPane]?

        var workingDirectoryURL: URL? {
            guard let workingDirectoryPath else { return nil }
            return URL(fileURLWithPath: workingDirectoryPath)
        }

        var resolvedSplitOrientation: PaneSplitOrientation? {
            guard let splitOrientation else { return nil }
            return PaneSplitOrientation(rawValue: splitOrientation)
        }
    }

    private let fileManager = FileManager.default

    func loadTabs() -> [StoredTab] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        return (try? JSONDecoder().decode([StoredTab].self, from: data)) ?? []
    }

    func saveTabs(_ tabs: [StoredTab]) {
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tabs)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to persist tabs: \(error)\n", stderr)
        }
    }

    private var storageURL: URL {
        AppSupport.baseURL.appendingPathComponent("session-tabs.json")
    }
}
