import AppKit

struct ThemeColor: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: String, alpha: Double = 1.0) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(sanitized, radix: 16) ?? 0
        let divisor = 255.0
        red = Double((value >> 16) & 0xff) / divisor
        green = Double((value >> 8) & 0xff) / divisor
        blue = Double(value & 0xff) / divisor
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlpha(_ alpha: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}
