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

    /// Cached monospace font list — computed once, reused forever.
    /// Uses the font manager’s fixed-pitch set (actual PostScript names). The old implementation
    /// wrongly passed *family* names to `NSFont(name:size:)`, so defaults like "SF Mono" never
    /// appeared in pickers and SwiftUI logged `Picker: the selection … is invalid`.
    static let cachedMonospaceFontNames: [String] = {
        let fm = NSFontManager.shared
        if let names = fm.availableFontNames(with: .fixedPitchFontMask), !names.isEmpty {
            return Array(Set(names)).sorted()
        }
        return fm.availableFontFamilies
            .filter { family in
                fm.font(withFamily: family, traits: .fixedPitchFontMask, weight: 5, size: 13)?.isFixedPitch == true
            }
            .sorted()
    }()

    static func monospaceFontNames() -> [String] {
        cachedMonospaceFontNames
    }

    /// Ensures profile/saved font names stay valid `Picker` tags even if they fall off the system list.
    static func monospaceFontNamesMerged(with extras: [String]) -> [String] {
        var set = Set(monospaceFontNames())
        for raw in extras {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { set.insert(t) }
        }
        return set.sorted()
    }
}
