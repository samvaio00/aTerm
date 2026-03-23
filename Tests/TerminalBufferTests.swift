import Testing
@testable import aTerm

@MainActor
struct TerminalBufferTests {
    // MARK: - Initialization
    
    @Test
    func initializationCreatesCorrectSize() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        
        #expect(buffer.columns == 80)
        #expect(buffer.rows == 24)
        #expect(buffer.cursorX == 0)
        #expect(buffer.cursorY == 0)
    }
    
    @Test
    func initializationClampsSize() {
        let buffer = TerminalBuffer(columns: 0, rows: 0)
        
        #expect(buffer.columns == 1)
        #expect(buffer.rows == 1)
    }
    
    // MARK: - Character Output
    
    @Test
    func putCharAdvancesCursor() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        
        buffer.putChar("A")
        
        #expect(buffer.cursorX == 1)
        #expect(buffer.cursorY == 0)
        #expect(buffer.cell(at: 0, y: 0).character == "A")
    }
    
    @Test
    func putCharWrapsAtEndOfLine() {
        let buffer = TerminalBuffer(columns: 5, rows: 5)
        buffer.moveCursorTo(x: 4, y: 0)
        
        buffer.putChar("A")
        buffer.putChar("B")
        
        #expect(buffer.cursorX == 1)
        #expect(buffer.cursorY == 1)
        #expect(buffer.cell(at: 0, y: 1).character == "B")
    }
    
    @Test
    func putCharHandlesWideCharacters() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        
        // CJK character (wide)
        buffer.putChar("漢")
        
        #expect(buffer.cursorX == 2)
        let cell0 = buffer.cell(at: 0, y: 0)
        let cell1 = buffer.cell(at: 1, y: 0)
        #expect(cell0.width == 2)
        #expect(cell1.width == 0) // continuation cell
    }
    
    // MARK: - Cursor Movement
    
    @Test
    func moveCursorToSetsPosition() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        
        buffer.moveCursorTo(x: 10, y: 5)
        
        #expect(buffer.cursorX == 10)
        #expect(buffer.cursorY == 5)
    }
    
    @Test
    func moveCursorToClampsPosition() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        
        buffer.moveCursorTo(x: 100, y: 50)
        
        #expect(buffer.cursorX == 79)
        #expect(buffer.cursorY == 23)
    }
    
    @Test
    func moveCursorUpStopsAtScrollTop() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.setScrollRegion(top: 5, bottom: 20)
        buffer.moveCursorTo(x: 0, y: 7)
        
        buffer.moveCursorUp(5)
        
        #expect(buffer.cursorY == 5) // stops at scrollTop
    }
    
    @Test
    func moveCursorDownStopsAtScrollBottom() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.setScrollRegion(top: 5, bottom: 10)
        buffer.moveCursorTo(x: 0, y: 8)
        
        buffer.moveCursorDown(5)
        
        #expect(buffer.cursorY == 10) // stops at scrollBottom
    }
    
    @Test
    func carriageReturnMovesToStart() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.moveCursorTo(x: 50, y: 10)
        
        buffer.carriageReturn()
        
        #expect(buffer.cursorX == 0)
        #expect(buffer.cursorY == 10)
    }
    
    @Test
    func lineFeedAdvancesRow() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.moveCursorTo(x: 10, y: 5)
        
        buffer.lineFeed()
        
        #expect(buffer.cursorX == 10)
        #expect(buffer.cursorY == 6)
    }
    
    @Test
    func lineFeedAtBottomScrolls() {
        let buffer = TerminalBuffer(columns: 80, rows: 5)
        buffer.moveCursorTo(x: 0, y: 4)
        buffer.putChar("A")
        
        buffer.lineFeed()
        
        #expect(buffer.cursorY == 4) // stays at bottom
        #expect(buffer.scrollback.count == 1) // line scrolled into scrollback
    }
    
    @Test
    func reverseLineFeedMovesUp() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.moveCursorTo(x: 10, y: 5)
        
        buffer.reverseLineFeed()
        
        #expect(buffer.cursorY == 4)
    }
    
    @Test
    func tabMovesToNextTabStop() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.moveCursorTo(x: 5, y: 0)
        
        buffer.tab()
        
        #expect(buffer.cursorX == 8) // next multiple of 8
    }
    
    @Test
    func backspaceMovesLeft() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.moveCursorTo(x: 10, y: 5)
        
        buffer.backspace()
        
        #expect(buffer.cursorX == 9)
    }
    
    @Test
    func backspaceStopsAtZero() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        
        buffer.backspace()
        
        #expect(buffer.cursorX == 0)
    }
    
    // MARK: - Erase Operations
    
    @Test
    func eraseInDisplayClearsFromCursor() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        // Fill with characters
        for y in 0..<5 {
            for x in 0..<10 {
                buffer.moveCursorTo(x: x, y: y)
                buffer.putChar("X")
            }
        }
        buffer.moveCursorTo(x: 5, y: 2)
        
        buffer.eraseInDisplay(0)
        
        #expect(buffer.cell(at: 4, y: 2).character == "X") // before cursor
        #expect(buffer.cell(at: 5, y: 2).character == " ") // at cursor
        #expect(buffer.cell(at: 0, y: 3).character == " ") // next line
    }
    
    @Test
    func eraseInDisplayClearsToCursor() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        for y in 0..<5 {
            for x in 0..<10 {
                buffer.moveCursorTo(x: x, y: y)
                buffer.putChar("X")
            }
        }
        buffer.moveCursorTo(x: 5, y: 2)
        
        buffer.eraseInDisplay(1)
        
        #expect(buffer.cell(at: 0, y: 0).character == " ") // first line (cleared)
        #expect(buffer.cell(at: 4, y: 2).character == " ") // before cursor (cleared)
        #expect(buffer.cell(at: 5, y: 2).character == " ") // at cursor (cleared by eraseLine(1))
        #expect(buffer.cell(at: 9, y: 2).character == "X") // after cursor (preserved)
    }
    
    @Test
    func eraseInDisplayClearsAll() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        for y in 0..<5 {
            for x in 0..<10 {
                buffer.moveCursorTo(x: x, y: y)
                buffer.putChar("X")
            }
        }
        
        buffer.eraseInDisplay(2)
        
        #expect(buffer.cell(at: 0, y: 0).character == " ")
        #expect(buffer.cell(at: 9, y: 4).character == " ")
    }
    
    @Test
    func eraseInDisplayClearsScrollback() {
        let buffer = TerminalBuffer(columns: 10, rows: 3)
        // Fill screen and scroll some lines
        for i in 0..<5 {
            buffer.moveCursorTo(x: 0, y: 2)
            buffer.putChar(Character("A"))
            buffer.lineFeed()
        }
        let scrollbackBefore = buffer.scrollback.count
        #expect(scrollbackBefore > 0)
        
        buffer.eraseInDisplay(3)
        
        #expect(buffer.scrollback.isEmpty)
    }
    
    @Test
    func eraseLineClearsFromCursor() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        for x in 0..<10 {
            buffer.moveCursorTo(x: x, y: 2)
            buffer.putChar("X")
        }
        buffer.moveCursorTo(x: 5, y: 2)
        
        buffer.eraseLine(0)
        
        #expect(buffer.cell(at: 4, y: 2).character == "X")
        #expect(buffer.cell(at: 5, y: 2).character == " ")
        #expect(buffer.cell(at: 9, y: 2).character == " ")
    }
    
    // MARK: - Insert/Delete
    
    @Test
    func insertCharsShiftsRight() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        buffer.putChar("A")
        buffer.putChar("B")
        buffer.putChar("C")
        buffer.moveCursorTo(x: 1, y: 0)
        
        buffer.insertChars(2)
        
        #expect(buffer.cell(at: 0, y: 0).character == "A")
        #expect(buffer.cell(at: 1, y: 0).character == " ")
        #expect(buffer.cell(at: 3, y: 0).character == "B")
        #expect(buffer.cell(at: 4, y: 0).character == "C")
    }
    
    @Test
    func deleteCharsShiftsLeft() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        buffer.putChar("A")
        buffer.putChar("B")
        buffer.putChar("C")
        buffer.putChar("D")
        buffer.moveCursorTo(x: 1, y: 0)
        
        buffer.deleteChars(2)
        
        #expect(buffer.cell(at: 0, y: 0).character == "A")
        #expect(buffer.cell(at: 1, y: 0).character == "D")
        #expect(buffer.cell(at: 2, y: 0).character == " ")
    }
    
    @Test
    func insertLinesPushesDown() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        buffer.moveCursorTo(x: 0, y: 0)
        buffer.putChar("A")
        buffer.moveCursorTo(x: 0, y: 1)
        buffer.putChar("B")
        buffer.moveCursorTo(x: 0, y: 2)
        buffer.putChar("C")
        buffer.moveCursorTo(x: 0, y: 1)
        
        buffer.insertLines(1)
        
        #expect(buffer.cell(at: 0, y: 0).character == "A")
        #expect(buffer.cell(at: 0, y: 1).character == " ") // new line
        #expect(buffer.cell(at: 0, y: 2).character == "B")
    }
    
    @Test
    func deleteLinesPullsUp() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        buffer.moveCursorTo(x: 0, y: 0)
        buffer.putChar("A")
        buffer.moveCursorTo(x: 0, y: 1)
        buffer.putChar("B")
        buffer.moveCursorTo(x: 0, y: 2)
        buffer.putChar("C")
        buffer.moveCursorTo(x: 0, y: 1)
        
        buffer.deleteLines(1)
        
        #expect(buffer.cell(at: 0, y: 0).character == "A")
        #expect(buffer.cell(at: 0, y: 1).character == "C")
    }
    
    // MARK: - Scroll Region
    
    @Test
    func setScrollRegionClampsValues() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        
        buffer.setScrollRegion(top: -5, bottom: 100)
        
        #expect(buffer.scrollTop == 0)
        #expect(buffer.scrollBottom == 23)
    }
    
    @Test
    func scrollUpMovesContentUp() {
        let buffer = TerminalBuffer(columns: 10, rows: 5)
        buffer.moveCursorTo(x: 0, y: 2)
        buffer.putChar("X")
        buffer.resetScrollRegion()
        buffer.moveCursorTo(x: 0, y: 0)
        
        buffer.scrollUp(1)
        
        #expect(buffer.cell(at: 0, y: 1).character == "X")
    }
    
    // MARK: - Alternate Screen
    
    @Test
    func alternateScreenSwitching() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.putChar("A")
        buffer.moveCursorTo(x: 10, y: 5)
        
        buffer.switchToAlternateScreen()
        
        #expect(buffer.isAlternateScreen == true)
        #expect(buffer.cursorX == 0)
        #expect(buffer.cursorY == 0)
        
        buffer.putChar("B")
        
        buffer.switchToMainScreen()
        
        #expect(buffer.isAlternateScreen == false)
        #expect(buffer.cursorX == 10)
        #expect(buffer.cursorY == 5)
        #expect(buffer.cell(at: 0, y: 0).character == "A")
    }
    
    // MARK: - Save/Restore Cursor
    
    @Test
    func saveAndRestoreCursor() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.moveCursorTo(x: 15, y: 10)
        buffer.currentAttributes.bold = true
        
        buffer.saveCursor()
        buffer.moveCursorTo(x: 0, y: 0)
        buffer.currentAttributes = .default
        
        buffer.restoreCursor()
        
        #expect(buffer.cursorX == 15)
        #expect(buffer.cursorY == 10)
        #expect(buffer.currentAttributes.bold == true)
    }
    
    // MARK: - Resize
    
    @Test
    func resizeChangesDimensions() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.putChar("A")
        buffer.moveCursorTo(x: 70, y: 20)
        
        buffer.resize(columns: 100, rows: 30)
        
        #expect(buffer.columns == 100)
        #expect(buffer.rows == 30)
        #expect(buffer.cursorX == 70)
        #expect(buffer.cursorY == 20)
        #expect(buffer.cell(at: 0, y: 0).character == "A")
    }
    
    @Test
    func resizeClampsCursor() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.moveCursorTo(x: 70, y: 20)
        
        buffer.resize(columns: 50, rows: 15)
        
        #expect(buffer.columns == 50)
        #expect(buffer.rows == 15)
        #expect(buffer.cursorX == 49)
        #expect(buffer.cursorY == 14)
    }
    
    // MARK: - Reset
    
    @Test
    func resetClearsAll() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.putChar("A")
        buffer.moveCursorTo(x: 10, y: 5)
        buffer.currentAttributes.bold = true
        buffer.applicationCursorKeys = true
        
        buffer.reset()
        
        #expect(buffer.cursorX == 0)
        #expect(buffer.cursorY == 0)
        #expect(buffer.currentAttributes.bold == false)
        #expect(buffer.applicationCursorKeys == false)
        #expect(buffer.cell(at: 0, y: 0).character == " ")
    }
    
    // MARK: - Text Output
    
    @Test
    func plainTextOutput() {
        let buffer = TerminalBuffer(columns: 10, rows: 3)
        buffer.putChar("H")
        buffer.putChar("i")
        buffer.lineFeed()
        buffer.putChar("B")
        buffer.putChar("y")
        buffer.putChar("e")
        
        let text = buffer.plainText()
        
        #expect(text.contains("Hi"))
        #expect(text.contains("Bye"))
    }
    
    @Test
    func lastScreenLineReturnsRecentContent() {
        let buffer = TerminalBuffer(columns: 10, rows: 3)
        buffer.putChar("H")
        buffer.putChar("i")
        
        let lastLine = buffer.lastScreenLine(maxChars: 10)
        
        #expect(lastLine == "Hi")
    }
    
    // MARK: - Prompt Marks
    
    @Test
    func markPromptStartRecordsPosition() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.moveCursorTo(x: 0, y: 5)
        
        buffer.markPromptStart()
        
        #expect(buffer.promptMarks.count == 1)
    }
    
    @Test
    func markCommandFinishedRecordsExitCode() {
        let buffer = TerminalBuffer(columns: 80, rows: 24)
        buffer.markPromptStart()
        
        buffer.markCommandFinished(exitCode: 42, duration: 1.5)
        
        #expect(buffer.lastCommandExitCode == 42)
        #expect(buffer.lastCommandDuration == 1.5)
    }
}
