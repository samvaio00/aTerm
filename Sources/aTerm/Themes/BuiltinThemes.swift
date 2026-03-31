import Foundation

/// Single modern theme with bright colors and no complexity
enum BuiltinThemes {
    static let all: [TerminalTheme] = [
        // Single modern theme - bright, high contrast
        TerminalTheme(
            id: "modern",
            name: "Modern",
            isBuiltin: true,
            sourcePath: nil,
            palette: .init(
                background: ThemeColor(hex: "#0D0D0D"),      // Near black
                foreground: ThemeColor(hex: "#FFFFFF"),      // Pure white - bright!
                selection: ThemeColor(hex: "#3B82F6", alpha: 0.4),
                cursor: ThemeColor(hex: "#3B82F6"),          // Blue cursor
                ansi: [
                    // Bright ANSI colors for high visibility
                    ThemeColor(hex: "#374151"),  // Black (brightened)
                    ThemeColor(hex: "#FF5252"),  // Red
                    ThemeColor(hex: "#69F0AE"),  // Green
                    ThemeColor(hex: "#FFD740"),  // Yellow
                    ThemeColor(hex: "#448AFF"),  // Blue
                    ThemeColor(hex: "#E040FB"),  // Magenta
                    ThemeColor(hex: "#18FFFF"),  // Cyan
                    ThemeColor(hex: "#FFFFFF"),  // White
                    // Bright variants
                    ThemeColor(hex: "#6B7280"),  // Bright Black
                    ThemeColor(hex: "#FF7B7B"),  // Bright Red
                    ThemeColor(hex: "#9BFFCF"),  // Bright Green
                    ThemeColor(hex: "#FFE97B"),  // Bright Yellow
                    ThemeColor(hex: "#7BAAFF"),  // Bright Blue
                    ThemeColor(hex: "#EA80FC"),  // Bright Magenta
                    ThemeColor(hex: "#64FFFF"),  // Bright Cyan
                    ThemeColor(hex: "#FFFFFF"),  // Bright White
                ]
            )
        )
    ]
}
