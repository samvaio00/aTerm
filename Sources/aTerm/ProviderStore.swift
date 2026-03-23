import Foundation

struct ProviderStore {
    struct StoredProviders: Codable {
        var providers: [ModelProvider]
        var defaultProviderID: String?
        var defaultModelID: String?
    }

    private let fileManager = FileManager.default

    func load() -> StoredProviders? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(StoredProviders.self, from: data)
    }

    func save(_ providers: StoredProviders) {
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(providers)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to save providers: \(error)\n", stderr)
        }
    }

    private var storageURL: URL {
        AppSupport.baseURL.appendingPathComponent("providers.json")
    }
}
