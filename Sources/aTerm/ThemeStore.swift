import Foundation

struct ThemeStore {
    private let fileManager = FileManager.default

    func loadImportedThemes() -> [TerminalTheme] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        return (try? JSONDecoder().decode([TerminalTheme].self, from: data)) ?? []
    }

    func saveImportedThemes(_ themes: [TerminalTheme]) {
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(themes)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to save themes: \(error)\n", stderr)
        }
    }

    private var storageURL: URL {
        AppSupport.baseURL.appendingPathComponent("imported-themes.json")
    }
}
