import Foundation

enum BuiltinThemes {
    static let all: [TerminalTheme] = [
        // Dracula - https://draculatheme.com
        theme("dracula", "Dracula",
              background: "#282A36", foreground: "#F8F8F2", cursor: "#F8F8F2", accent: "#BD93F9",
              ansi: ["#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
                     "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"]),
        
        // Nord - https://www.nordtheme.com
        theme("nord", "Nord",
              background: "#2E3440", foreground: "#D8DEE9", cursor: "#88C0D0", accent: "#81A1C1",
              ansi: ["#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
                     "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4"]),
        
        // Catppuccin Mocha - https://catppuccin.com
        theme("catppuccin-mocha", "Catppuccin Mocha",
              background: "#1E1E2E", foreground: "#CDD6F4", cursor: "#F5E0DC", accent: "#89B4FA",
              ansi: ["#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE",
                     "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#A6ADC8"]),
        
        // Tokyo Night - https://github.com/enkia/tokyo-night-vscode-theme
        theme("tokyo-night", "Tokyo Night",
              background: "#1A1B26", foreground: "#C0CAF5", cursor: "#7AA2F7", accent: "#BB9AF7",
              ansi: ["#15161E", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
                     "#414868", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5"]),
        
        // Gruvbox Dark - https://github.com/morhetz/gruvbox
        theme("gruvbox-dark", "Gruvbox Dark",
              background: "#282828", foreground: "#EBDBB2", cursor: "#FE8019", accent: "#D79921",
              ansi: ["#282828", "#CC241D", "#98971A", "#D79921", "#458588", "#B16286", "#689D6A", "#A89984",
                     "#928374", "#FB4934", "#B8BB26", "#FABD2F", "#83A598", "#D3869B", "#8EC07C", "#EBDBB2"]),
        
        // Solarized Dark - https://ethanschoonover.com/solarized/
        theme("solarized-dark", "Solarized Dark",
              background: "#002B36", foreground: "#93A1A1", cursor: "#839496", accent: "#268BD2",
              ansi: ["#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
                     "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"]),
        
        // Solarized Light
        theme("solarized-light", "Solarized Light",
              background: "#FDF6E3", foreground: "#657B83", cursor: "#586E75", accent: "#268BD2",
              ansi: ["#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
                     "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"]),
        
        // One Dark - https://github.com/atom/atom/tree/master/packages/one-dark-ui
        theme("one-dark", "One Dark",
              background: "#282C34", foreground: "#ABB2BF", cursor: "#61AFEF", accent: "#98C379",
              ansi: ["#282C34", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#ABB2BF",
                     "#545862", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#FFFFFF"]),
        
        // Monokai - https://monokai.pro
        theme("monokai", "Monokai",
              background: "#272822", foreground: "#F8F8F2", cursor: "#FD971F", accent: "#A6E22E",
              ansi: ["#272822", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F8F8F2",
                     "#75715E", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F9F8F5"]),
        
        // Material Dark
        theme("material-dark", "Material Dark",
              background: "#212121", foreground: "#EEFFFF", cursor: "#FFCC00", accent: "#82AAFF",
              ansi: ["#212121", "#F07178", "#C3E88D", "#FFCB6B", "#82AAFF", "#C792EA", "#89DDFF", "#EEFFFF",
                     "#4A4A4A", "#F07178", "#C3E88D", "#FFCB6B", "#82AAFF", "#C792EA", "#89DDFF", "#FFFFFF"]),
        
        // Rosé Pine - https://rosepinetheme.com
        theme("rose-pine", "Rose Pine",
              background: "#191724", foreground: "#E0DEF4", cursor: "#F6C177", accent: "#9CCFD8",
              ansi: ["#26233A", "#EB6F92", "#9CCFD8", "#F6C177", "#31748F", "#C4A7E7", "#EBBCBA", "#E0DEF4",
                     "#6E6A86", "#EB6F92", "#9CCFD8", "#F6C177", "#31748F", "#C4A7E7", "#EBBCBA", "#524F67"]),
        
        // aTerm Default
        theme("custom-default", "aTerm Default",
              background: "#111417", foreground: "#E8F1F2", cursor: "#7BDFF2", accent: "#F4D35E",
              ansi: ["#1B1F23", "#FF6B6B", "#98C379", "#F4D35E", "#61AFEF", "#C678DD", "#56B6C2", "#D7DAE0",
                     "#5C6370", "#FF8787", "#B5E48C", "#FFE66D", "#74C0FC", "#D0A2F7", "#66D9E8", "#E8F1F2"]),
    ]

    private static func theme(_ id: String, _ name: String, background: String, foreground: String, cursor: String, accent: String, ansi: [String]) -> TerminalTheme {
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
                ansi: ansi.map { ThemeColor(hex: $0) }
            )
        )
    }
}
