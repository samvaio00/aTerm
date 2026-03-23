import Foundation

enum BuiltinThemes {
    static let all: [TerminalTheme] = [
        theme("dracula", "Dracula", background: "#282A36", foreground: "#F8F8F2", cursor: "#F8F8F2", accent: "#BD93F9"),
        theme("nord", "Nord", background: "#2E3440", foreground: "#D8DEE9", cursor: "#88C0D0", accent: "#81A1C1"),
        theme("catppuccin-mocha", "Catppuccin Mocha", background: "#1E1E2E", foreground: "#CDD6F4", cursor: "#F5E0DC", accent: "#89B4FA"),
        theme("tokyo-night", "Tokyo Night", background: "#1A1B26", foreground: "#C0CAF5", cursor: "#7AA2F7", accent: "#BB9AF7"),
        theme("gruvbox-dark", "Gruvbox Dark", background: "#282828", foreground: "#EBDBB2", cursor: "#FE8019", accent: "#D79921"),
        theme("solarized-dark", "Solarized Dark", background: "#002B36", foreground: "#93A1A1", cursor: "#839496", accent: "#268BD2"),
        theme("solarized-light", "Solarized Light", background: "#FDF6E3", foreground: "#657B83", cursor: "#586E75", accent: "#B58900"),
        theme("one-dark", "One Dark", background: "#282C34", foreground: "#ABB2BF", cursor: "#61AFEF", accent: "#98C379"),
        theme("monokai", "Monokai", background: "#272822", foreground: "#F8F8F2", cursor: "#FD971F", accent: "#A6E22E"),
        theme("material-dark", "Material Dark", background: "#212121", foreground: "#EEFFFF", cursor: "#FFCC00", accent: "#82AAFF"),
        theme("rose-pine", "Rose Pine", background: "#191724", foreground: "#E0DEF4", cursor: "#F6C177", accent: "#9CCFD8"),
        theme("custom-default", "aTerm Default", background: "#111417", foreground: "#E8F1F2", cursor: "#7BDFF2", accent: "#F4D35E"),
    ]

    private static func theme(_ id: String, _ name: String, background: String, foreground: String, cursor: String, accent: String) -> TerminalTheme {
        TerminalTheme(
            id: id,
            name: name,
            isBuiltin: true,
            sourcePath: nil,
            palette: .init(
                background: ThemeColor(hex: background),
                foreground: ThemeColor(hex: foreground),
                selection: ThemeColor(hex: accent, alpha: 0.25),
                cursor: ThemeColor(hex: cursor),
                ansi: [
                    ThemeColor(hex: "#1B1F23"),
                    ThemeColor(hex: "#FF6B6B"),
                    ThemeColor(hex: "#98C379"),
                    ThemeColor(hex: "#F4D35E"),
                    ThemeColor(hex: "#61AFEF"),
                    ThemeColor(hex: "#C678DD"),
                    ThemeColor(hex: "#56B6C2"),
                    ThemeColor(hex: "#D7DAE0"),
                    ThemeColor(hex: "#5C6370"),
                    ThemeColor(hex: "#FF8787"),
                    ThemeColor(hex: "#B5E48C"),
                    ThemeColor(hex: "#FFE66D"),
                    ThemeColor(hex: "#74C0FC"),
                    ThemeColor(hex: "#D0A2F7"),
                    ThemeColor(hex: "#66D9E8"),
                    ThemeColor(hex: foreground),
                ]
            )
        )
    }
}
