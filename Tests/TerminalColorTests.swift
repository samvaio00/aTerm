import Testing
@testable import aTerm

struct TerminalColorTests {
    // MARK: - TerminalColor
    
    @Test
    func ansiColorsAreCorrect() {
        // Black
        #expect(TerminalColor.ansi[0].r == 0)
        #expect(TerminalColor.ansi[0].g == 0)
        #expect(TerminalColor.ansi[0].b == 0)
        
        // Red
        #expect(TerminalColor.ansi[1].r == 205)
        #expect(TerminalColor.ansi[1].g == 49)
        #expect(TerminalColor.ansi[1].b == 49)
        
        // Green
        #expect(TerminalColor.ansi[2].r == 13)
        #expect(TerminalColor.ansi[2].g == 188)
        #expect(TerminalColor.ansi[2].b == 121)
        
        // White
        #expect(TerminalColor.ansi[7].r == 204)
        #expect(TerminalColor.ansi[7].g == 204)
        #expect(TerminalColor.ansi[7].b == 204)
    }
    
    @Test
    func color256First16AreAnsi() {
        for i in 0..<16 {
            let color = TerminalColor.color256(UInt8(i))
            #expect(color == TerminalColor.ansi[i])
        }
    }
    
    @Test
    func color256CubeColors() {
        // Test a few cube colors (16-231)
        let color16 = TerminalColor.color256(16)
        #expect(color16.r == 0)
        #expect(color16.g == 0)
        #expect(color16.b == 0)
        
        // Color 21: i=5, r=0, g=0, b=5 -> toVal(5) = 55 + 5*40 = 255
        let color21 = TerminalColor.color256(21)
        #expect(color21.r == 0)
        #expect(color21.g == 0)
        #expect(color21.b == 255)
        
        let color196 = TerminalColor.color256(196)
        #expect(color196.r == 255)
        #expect(color196.g == 0)
        #expect(color196.b == 0)
    }
    
    @Test
    func color256Grayscale() {
        // Grayscale colors (232-255)
        let color232 = TerminalColor.color256(232)
        #expect(color232.r == 8)
        #expect(color232.g == 8)
        #expect(color232.b == 8)
        
        let color255 = TerminalColor.color256(255)
        #expect(color255.r == 238)
        #expect(color255.g == 238)
        #expect(color255.b == 238)
    }
    
    // MARK: - TerminalColorSpec
    
    @Test
    func colorSpecDefault() {
        let spec = TerminalColorSpec.default
        let resolved = spec.resolve()
        #expect(resolved == .default)
    }
    
    @Test
    func colorSpecIndexed() {
        let spec = TerminalColorSpec.indexed(1)
        let resolved = spec.resolve()
        #expect(resolved == TerminalColor.ansi[1])
    }
    
    @Test
    func colorSpecRGB() {
        let spec = TerminalColorSpec.rgb(100, 150, 200)
        let resolved = spec.resolve()
        #expect(resolved.r == 100)
        #expect(resolved.g == 150)
        #expect(resolved.b == 200)
    }
    
    @Test
    func colorSpecIndexed256() {
        let spec = TerminalColorSpec.indexed(200)
        let resolved = spec.resolve()
        let expected = TerminalColor.color256(200)
        #expect(resolved == expected)
    }
    
    @Test
    func colorSpecEquality() {
        #expect(TerminalColorSpec.default == TerminalColorSpec.default)
        #expect(TerminalColorSpec.indexed(1) == TerminalColorSpec.indexed(1))
        #expect(TerminalColorSpec.rgb(1, 2, 3) == TerminalColorSpec.rgb(1, 2, 3))
        #expect(TerminalColorSpec.indexed(1) != TerminalColorSpec.indexed(2))
        #expect(TerminalColorSpec.default != TerminalColorSpec.indexed(0))
    }
    
    // MARK: - CellAttributes
    
    @Test
    func cellAttributesDefault() {
        let attrs = CellAttributes.default
        #expect(attrs.fg == .default)
        #expect(attrs.bg == .default)
        #expect(attrs.bold == false)
        #expect(attrs.dim == false)
        #expect(attrs.italic == false)
        #expect(attrs.underline == false)
        #expect(attrs.blink == false)
        #expect(attrs.inverse == false)
        #expect(attrs.hidden == false)
        #expect(attrs.strikethrough == false)
        #expect(attrs.hyperlinkURL == nil)
    }
    
    @Test
    func cellAttributesEquality() {
        let attrs1 = CellAttributes(fg: .indexed(1), bg: .indexed(2), bold: true, italic: true)
        let attrs2 = CellAttributes(fg: .indexed(1), bg: .indexed(2), bold: true, italic: true)
        let attrs3 = CellAttributes(fg: .indexed(1), bg: .indexed(2), bold: true, italic: false)
        
        #expect(attrs1 == attrs2)
        #expect(attrs1 != attrs3)
    }
    
    @Test
    func cellAttributesWithHyperlink() {
        var attrs = CellAttributes.default
        attrs.hyperlinkURL = "https://example.com"
        
        #expect(attrs.hyperlinkURL == "https://example.com")
    }
    
    // MARK: - TerminalCell
    
    @Test
    func terminalCellDefault() {
        let cell = TerminalCell()
        #expect(cell.character == " ")
        #expect(cell.attributes == .default)
        #expect(cell.width == 1)
    }
    
    @Test
    func terminalCellCustom() {
        let attrs = CellAttributes(bold: true)
        let cell = TerminalCell(character: "A", attributes: attrs, width: 2)
        
        #expect(cell.character == "A")
        #expect(cell.attributes.bold == true)
        #expect(cell.width == 2)
    }
    
    @Test
    func terminalCellEquality() {
        let cell1 = TerminalCell(character: "A", attributes: .default, width: 1)
        let cell2 = TerminalCell(character: "A", attributes: .default, width: 1)
        let cell3 = TerminalCell(character: "B", attributes: .default, width: 1)
        
        #expect(cell1 == cell2)
        #expect(cell1 != cell3)
    }
}

// MARK: - Wide Character Detection

@MainActor
struct WideCharacterTests {
    @Test
    func asciiIsNotWide() {
        #expect(TerminalBuffer.isWideCharacter("A") == false)
        #expect(TerminalBuffer.isWideCharacter("!") == false)
        #expect(TerminalBuffer.isWideCharacter("1") == false)
    }
    
    @Test
    func cjkIdeographsAreWide() {
        #expect(TerminalBuffer.isWideCharacter("漢") == true)
        #expect(TerminalBuffer.isWideCharacter("中") == true)
        #expect(TerminalBuffer.isWideCharacter("日") == true)
        #expect(TerminalBuffer.isWideCharacter("本") == true)
    }
    
    @Test
    func hangulIsWide() {
        #expect(TerminalBuffer.isWideCharacter("한") == true)
        #expect(TerminalBuffer.isWideCharacter("글") == true)
    }
    
    @Test
    func katakanaAreWide() {
        #expect(TerminalBuffer.isWideCharacter("カ") == true)
        #expect(TerminalBuffer.isWideCharacter("タ") == true)
    }
    
    @Test
    func hiraganaAreWide() {
        #expect(TerminalBuffer.isWideCharacter("か") == true)
        #expect(TerminalBuffer.isWideCharacter("た") == true)
    }
    
    @Test
    func emojiAreWide() {
        #expect(TerminalBuffer.isWideCharacter("😀") == true)
        #expect(TerminalBuffer.isWideCharacter("🎉") == true)
        #expect(TerminalBuffer.isWideCharacter("🚀") == true)
    }
    
    @Test
    func fullwidthFormsAreWide() {
        #expect(TerminalBuffer.isWideCharacter("Ａ") == true)
        #expect(TerminalBuffer.isWideCharacter("！") == true)
    }
}
