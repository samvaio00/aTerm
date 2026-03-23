import Foundation

/// Fetches and manages the iterm2colorschemes.com theme catalog
@MainActor
final class ThemeCatalog: ObservableObject {
    struct CatalogEntry: Identifiable, Hashable {
        let id: String
        let name: String
        let downloadURL: URL
        var isDownloaded: Bool
    }

    @Published private(set) var entries: [CatalogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private static let indexURL = URL(string: "https://api.github.com/repos/mbadolato/iTerm2-Color-Schemes/contents/schemes")!
    private static let rawBaseURL = "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/schemes/"

    func fetchIndex(existingThemeIDs: Set<String>) async {
        isLoading = true
        errorMessage = nil

        do {
            let (data, _) = try await URLSession.shared.data(from: Self.indexURL)
            guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                errorMessage = "Unexpected API response format."
                isLoading = false
                return
            }

            entries = items.compactMap { item -> CatalogEntry? in
                guard let name = item["name"] as? String, name.hasSuffix(".itermcolors") else { return nil }
                let displayName = String(name.dropLast(".itermcolors".count))
                let id = "imported-\(displayName.lowercased().replacingOccurrences(of: " ", with: "-"))"
                let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                guard let url = URL(string: Self.rawBaseURL + encodedName) else { return nil }
                return CatalogEntry(
                    id: id,
                    name: displayName,
                    downloadURL: url,
                    isDownloaded: existingThemeIDs.contains(id)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = "Failed to fetch catalog: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func download(_ entry: CatalogEntry) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: entry.downloadURL)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(entry.name).itermcolors")
        try data.write(to: tempURL, options: .atomic)

        // Mark as downloaded
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx].isDownloaded = true
        }

        return tempURL
    }
}
