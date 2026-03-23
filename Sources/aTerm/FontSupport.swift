import AppKit
import CoreText

enum FontSupport {
    private static let nerdProbeScalar: UniChar = 0xE0B0

    static var currentTerminalFontSupportsNerdGlyphs: Bool {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return fontSupportsNerdGlyphs(font)
    }

    static func fontSupportsNerdGlyphs(_ font: NSFont) -> Bool {
        let ctFont = font as CTFont
        var character = nerdProbeScalar
        var glyph: CGGlyph = 0
        return CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1) && glyph != 0
    }

    static func monospaceFontNames() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 13) else { return false }
                return font.isFixedPitch
            }
            .sorted()
    }
}
