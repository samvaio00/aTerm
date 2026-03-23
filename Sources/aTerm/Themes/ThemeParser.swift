import Foundation

enum ThemeParserError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        "The .itermcolors file could not be parsed."
    }
}

enum ThemeParser {
    static func parseTheme(at url: URL) throws -> TerminalTheme {
        let data = try Data(contentsOf: url)
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ThemeParserError.invalidFormat
        }

        let background = color(named: "Background Color", in: dictionary) ?? ThemeColor(hex: "#000000")
        let foreground = color(named: "Foreground Color", in: dictionary) ?? ThemeColor(hex: "#FFFFFF")
        let selection = color(named: "Selection Color", in: dictionary) ?? foreground.withAlpha(0.25)
        let cursor = color(named: "Cursor Color", in: dictionary) ?? foreground
        let ansi = (0..<16).map { index in
            color(named: "Ansi \(index) Color", in: dictionary) ?? fallbackANSIColor(index: index)
        }

        return TerminalTheme(
            id: "imported-\(url.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-"))",
            name: url.deletingPathExtension().lastPathComponent,
            isBuiltin: false,
            sourcePath: url.path,
            palette: .init(background: background, foreground: foreground, selection: selection, cursor: cursor, ansi: ansi)
        )
    }

    private static func color(named key: String, in dictionary: [String: Any]) -> ThemeColor? {
        guard let components = dictionary[key] as? [String: Any] else { return nil }
        return ThemeColor(
            red: components["Red Component"] as? Double ?? 0,
            green: components["Green Component"] as? Double ?? 0,
            blue: components["Blue Component"] as? Double ?? 0,
            alpha: components["Alpha Component"] as? Double ?? 1
        )
    }

    private static func fallbackANSIColor(index: Int) -> ThemeColor {
        BuiltinThemes.all.last?.palette.ansi[index] ?? ThemeColor(hex: "#FFFFFF")
    }
}
