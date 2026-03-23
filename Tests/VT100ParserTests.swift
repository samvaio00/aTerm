import Foundation
import Testing
@testable import aTerm

@MainActor
struct VT100ParserTests {
    private func makeBufferAndParser() -> (TerminalBuffer, VT100Parser) {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        let parser = VT100Parser(buffer: buffer)
        return (buffer, parser)
    }
    
    // MARK: - Basic Character Output
    
    @Test
    func basicCharactersArePrinted() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("Hello".utf8))
        
        #expect(buffer.cell(at: 0, y: 0).character == "H")
        #expect(buffer.cell(at: 1, y: 0).character == "e")
        #expect(buffer.cell(at: 4, y: 0).character == "o")
        #expect(buffer.cursorX == 5)
    }
    
    @Test
    func unicodeCharactersAreHandled() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("こんにちは".utf8))
        
        // Should handle without crashing
        #expect(buffer.cursorX > 0)
    }
    
    // MARK: - Control Characters
    
    @Test
    func carriageReturnMovesToStart() {
        let (buffer, parser) = makeBufferAndParser()
        parser.feed(Data("ABC".utf8))
        
        parser.feed(Data("\r".utf8))
        
        #expect(buffer.cursorX == 0)
        #expect(buffer.cursorY == 0)
    }
    
    @Test
    func lineFeedMovesDown() {
        let (buffer, parser) = makeBufferAndParser()
        parser.feed(Data("AB".utf8))
        
        parser.feed(Data("\n".utf8))
        
        #expect(buffer.cursorX == 2)
        #expect(buffer.cursorY == 1)
    }
    
    @Test
    func backspaceMovesLeft() {
        let (buffer, parser) = makeBufferAndParser()
        parser.feed(Data("AB".utf8))
        
        parser.feed(Data("\u{08}".utf8)) // BS
        
        #expect(buffer.cursorX == 1)
    }
    
    @Test
    func tabAdvancesCursor() {
        let (buffer, parser) = makeBufferAndParser()
        parser.feed(Data("AB".utf8))
        
        parser.feed(Data("\t".utf8))
        
        #expect(buffer.cursorX == 8) // Next tab stop
    }
    
    @Test
    func bellSetsFlag() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{07}".utf8)) // BEL
        
        #expect(buffer.bellFired == true)
    }
    
    // MARK: - CSI Sequences
    
    @Test
    func csiCursorUp() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.moveCursorTo(x: 5, y: 10)
        
        parser.feed(Data("\u{1B}[3A".utf8)) // CUU 3
        
        #expect(buffer.cursorY == 7)
        #expect(buffer.cursorX == 5)
    }
    
    @Test
    func csiCursorDown() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.moveCursorTo(x: 5, y: 10)
        
        parser.feed(Data("\u{1B}[5B".utf8)) // CUD 5
        
        #expect(buffer.cursorY == 15)
    }
    
    @Test
    func csiCursorForward() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.moveCursorTo(x: 5, y: 10)
        
        parser.feed(Data("\u{1B}[10C".utf8)) // CUF 10
        
        #expect(buffer.cursorX == 15)
    }
    
    @Test
    func csiCursorBackward() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.moveCursorTo(x: 20, y: 10)
        
        parser.feed(Data("\u{1B}[5D".utf8)) // CUB 5
        
        #expect(buffer.cursorX == 15)
    }
    
    @Test
    func csiCursorPosition() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[10;20H".utf8)) // CUP row 10, col 20
        
        #expect(buffer.cursorY == 9)  // 0-indexed
        #expect(buffer.cursorX == 19) // 0-indexed
    }
    
    @Test
    func csiEraseInDisplay() {
        let (buffer, parser) = makeBufferAndParser()
        parser.feed(Data("ABCDEFGHIJ".utf8))
        buffer.moveCursorTo(x: 5, y: 0)
        
        parser.feed(Data("\u{1B}[0J".utf8)) // ED 0 - from cursor to end
        
        #expect(buffer.cell(at: 4, y: 0).character == "E")
        #expect(buffer.cell(at: 5, y: 0).character == " ")
    }
    
    @Test
    func csiEraseLine() {
        let (buffer, parser) = makeBufferAndParser()
        parser.feed(Data("ABCDEFGHIJ".utf8))
        buffer.moveCursorTo(x: 5, y: 0)
        
        parser.feed(Data("\u{1B}[2K".utf8)) // EL 2 - entire line
        
        #expect(buffer.cell(at: 0, y: 0).character == " ")
        #expect(buffer.cell(at: 9, y: 0).character == " ")
    }
    
    @Test
    func csiSetScrollRegion() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[5;20r".utf8)) // DECSTBM top=5, bottom=20
        
        #expect(buffer.scrollTop == 4)  // 0-indexed
        #expect(buffer.scrollBottom == 19) // 0-indexed
    }
    
    // MARK: - SGR (Select Graphic Rendition)
    
    @Test
    func sgrReset() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.currentAttributes.bold = true
        buffer.currentAttributes.fg = .indexed(1)
        
        parser.feed(Data("\u{1B}[0m".utf8)) // SGR reset
        
        #expect(buffer.currentAttributes.bold == false)
        #expect(buffer.currentAttributes.fg == .default)
    }
    
    @Test
    func sgrBold() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[1m".utf8)) // SGR bold
        
        #expect(buffer.currentAttributes.bold == true)
    }
    
    @Test
    func sgrColors() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[31m".utf8)) // SGR red fg
        #expect(buffer.currentAttributes.fg == .indexed(1))
        
        parser.feed(Data("\u{1B}[42m".utf8)) // SGR green bg
        #expect(buffer.currentAttributes.bg == .indexed(2))
    }
    
    @Test
    func sgrBrightColors() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[90m".utf8)) // SGR bright black
        #expect(buffer.currentAttributes.fg == .indexed(8))
        
        parser.feed(Data("\u{1B}[101m".utf8)) // SGR bright red bg
        #expect(buffer.currentAttributes.bg == .indexed(9))
    }
    
    @Test
    func sgr256Color() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[38;5;196m".utf8)) // SGR fg color 196
        #expect(buffer.currentAttributes.fg == .indexed(196))
        
        parser.feed(Data("\u{1B}[48;5;21m".utf8)) // SGR bg color 21
        #expect(buffer.currentAttributes.bg == .indexed(21))
    }
    
    @Test
    func sgrTrueColor() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[38;2;100;150;200m".utf8)) // SGR fg RGB
        #expect(buffer.currentAttributes.fg == .rgb(100, 150, 200))
        
        parser.feed(Data("\u{1B}[48;2;50;75;100m".utf8)) // SGR bg RGB
        #expect(buffer.currentAttributes.bg == .rgb(50, 75, 100))
    }
    
    @Test
    func sgrMultipleAttributes() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[1;3;31;47m".utf8)) // bold, italic, red fg, white bg
        
        #expect(buffer.currentAttributes.bold == true)
        #expect(buffer.currentAttributes.italic == true)
        #expect(buffer.currentAttributes.fg == .indexed(1))  // Red
        #expect(buffer.currentAttributes.bg == .indexed(7))   // White (not bright white)
    }
    
    @Test
    func sgrDisableAttributes() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.currentAttributes.bold = true
        buffer.currentAttributes.italic = true
        buffer.currentAttributes.underline = true
        
        parser.feed(Data("\u{1B}[22;23;24m".utf8)) // disable bold, italic, underline
        
        #expect(buffer.currentAttributes.bold == false)
        #expect(buffer.currentAttributes.italic == false)
        #expect(buffer.currentAttributes.underline == false)
    }
    
    // MARK: - DEC Private Mode Set/Reset
    
    @Test
    func decsetApplicationCursorKeys() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[?1h".utf8)) // DECSET 1
        #expect(buffer.applicationCursorKeys == true)
        
        parser.feed(Data("\u{1B}[?1l".utf8)) // DECRST 1
        #expect(buffer.applicationCursorKeys == false)
    }
    
    @Test
    func decsetCursorVisible() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.cursorVisible = true
        
        parser.feed(Data("\u{1B}[?25l".utf8)) // DECRST 25 - hide cursor
        #expect(buffer.cursorVisible == false)
        
        parser.feed(Data("\u{1B}[?25h".utf8)) // DECSET 25 - show cursor
        #expect(buffer.cursorVisible == true)
    }
    
    @Test
    func decsetAlternateScreen() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[?47h".utf8)) // DECSET 47 - alternate screen
        #expect(buffer.isAlternateScreen == true)
        
        parser.feed(Data("\u{1B}[?47l".utf8)) // DECRST 47 - main screen
        #expect(buffer.isAlternateScreen == false)
    }
    
    @Test
    func decsetBracketedPaste() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[?2004h".utf8)) // DECSET 2004
        #expect(buffer.bracketedPasteMode == true)
        
        parser.feed(Data("\u{1B}[?2004l".utf8)) // DECRST 2004
        #expect(buffer.bracketedPasteMode == false)
    }
    
    @Test
    func decsetMouseModes() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[?1000h".utf8)) // DECSET 1000 - mouse click
        #expect(buffer.mouseMode == .click)
        
        parser.feed(Data("\u{1B}[?1002h".utf8)) // DECSET 1002 - button motion
        #expect(buffer.mouseMode == .buttonMotion)
        
        parser.feed(Data("\u{1B}[?1003h".utf8)) // DECSET 1003 - any motion
        #expect(buffer.mouseMode == .anyMotion)
        
        parser.feed(Data("\u{1B}[?1006h".utf8)) // DECSET 1006 - SGR extended
        #expect(buffer.mouseMode == .sgrExtended)
    }
    
    @Test
    func decsetFocusEvents() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}[?1004h".utf8)) // DECSET 1004
        #expect(buffer.focusEventMode == true)
        
        parser.feed(Data("\u{1B}[?1004l".utf8)) // DECRST 1004
        #expect(buffer.focusEventMode == false)
    }
    
    // MARK: - Escape Sequences
    
    @Test
    func escapeSaveRestoreCursor() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.moveCursorTo(x: 15, y: 10)
        
        parser.feed(Data("\u{1B}7".utf8)) // DECSC
        buffer.moveCursorTo(x: 0, y: 0)
        
        parser.feed(Data("\u{1B}8".utf8)) // DECRC
        
        #expect(buffer.cursorX == 15)
        #expect(buffer.cursorY == 10)
    }
    
    @Test
    func escapeReverseIndex() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.moveCursorTo(x: 0, y: 5)
        
        parser.feed(Data("\u{1B}M".utf8)) // RI
        
        #expect(buffer.cursorY == 4)
    }
    
    @Test
    func escapeNextLine() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.moveCursorTo(x: 10, y: 5)
        
        parser.feed(Data("\u{1B}E".utf8)) // NEL
        
        #expect(buffer.cursorX == 0)
        #expect(buffer.cursorY == 6)
    }
    
    // MARK: - OSC Sequences
    
    @Test
    func oscSetTitle() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}]2;My Terminal\u{07}".utf8)) // OSC 2
        
        #expect(buffer.title == "My Terminal")
    }
    
    @Test
    func oscSetWorkingDirectory() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}]7;file:///Users/test/project\u{07}".utf8)) // OSC 7
        
        #expect(buffer.workingDirectory?.path == "/Users/test/project")
    }
    
    @Test
    func oscHyperlink() {
        let (buffer, parser) = makeBufferAndParser()
        
        // Start hyperlink
        parser.feed(Data("\u{1B}]8;;https://example.com\u{07}".utf8))
        #expect(buffer.currentAttributes.hyperlinkURL == "https://example.com")
        
        // End hyperlink
        parser.feed(Data("\u{1B}]8;;\u{07}".utf8))
        #expect(buffer.currentAttributes.hyperlinkURL == nil)
    }
    
    // MARK: - Charset Selection
    
    @Test
    func selectLineDrawingCharset() {
        let (buffer, parser) = makeBufferAndParser()
        
        parser.feed(Data("\u{1B}(0".utf8)) // Select G0 line drawing
        #expect(buffer.useLineDrawingCharset == true)
        
        parser.feed(Data("\u{1B}(B".utf8)) // Select G0 ASCII
        #expect(buffer.useLineDrawingCharset == false)
    }
    
    // MARK: - Full Reset
    
    @Test
    func fullReset() {
        let (buffer, parser) = makeBufferAndParser()
        buffer.moveCursorTo(x: 10, y: 5)
        buffer.currentAttributes.bold = true
        buffer.putChar("A")
        
        parser.feed(Data("\u{1B}c".utf8)) // RIS - full reset
        
        #expect(buffer.cursorX == 0)
        #expect(buffer.cursorY == 0)
        #expect(buffer.currentAttributes.bold == false)
        #expect(buffer.cell(at: 0, y: 0).character == " ")
    }
}
