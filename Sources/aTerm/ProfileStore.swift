import Foundation

struct ProfileStore {
    struct StoredProfiles: Codable {
        var defaultProfileID: UUID?
        var profiles: [Profile]
    }

    private let fileManager = FileManager.default

    func load() -> StoredProfiles? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(StoredProfiles.self, from: data)
    }

    func save(_ profiles: StoredProfiles) {
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to save profiles: \(error)\n", stderr)
        }
    }

    private var storageURL: URL {
        AppSupport.baseURL.appendingPathComponent("profiles.json")
    }
}
