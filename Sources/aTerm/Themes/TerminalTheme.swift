import Foundation

struct TerminalTheme: Identifiable, Codable, Hashable {
    struct Palette: Codable, Hashable {
        let background: ThemeColor
        let foreground: ThemeColor
        let selection: ThemeColor
        let cursor: ThemeColor
        let ansi: [ThemeColor]
    }

    let id: String
    let name: String
    let isBuiltin: Bool
    let sourcePath: String?
    let palette: Palette
}
