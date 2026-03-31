import AppKit
import Foundation

struct TerminalColor: Equatable, Hashable {
    let r: UInt8, g: UInt8, b: UInt8

    static let `default` = TerminalColor(r: 0, g: 0, b: 0)
    static let defaultFG = TerminalColor(r: 204, g: 204, b: 204)
    static let defaultBG = TerminalColor(r: 30, g: 30, b: 30)

    static let ansi: [TerminalColor] = [
        TerminalColor(r: 0, g: 0, b: 0),       // 0 black
        TerminalColor(r: 205, g: 49, b: 49),    // 1 red
        TerminalColor(r: 13, g: 188, b: 121),   // 2 green
        TerminalColor(r: 229, g: 229, b: 16),   // 3 yellow
        TerminalColor(r: 36, g: 114, b: 200),   // 4 blue
        TerminalColor(r: 188, g: 63, b: 188),   // 5 magenta
        TerminalColor(r: 17, g: 168, b: 205),   // 6 cyan
        TerminalColor(r: 204, g: 204, b: 204),  // 7 white
        TerminalColor(r: 118, g: 118, b: 118),  // 8 bright black
        TerminalColor(r: 241, g: 76, b: 76),    // 9 bright red
        TerminalColor(r: 35, g: 209, b: 139),   // 10 bright green
        TerminalColor(r: 245, g: 245, b: 67),   // 11 bright yellow
        TerminalColor(r: 59, g: 142, b: 234),   // 12 bright blue
        TerminalColor(r: 214, g: 112, b: 214),  // 13 bright magenta
        TerminalColor(r: 41, g: 184, b: 219),   // 14 bright cyan
        TerminalColor(r: 242, g: 242, b: 242),  // 15 bright white
    ]

    /// Generate 256-color palette entry
    static func color256(_ index: UInt8) -> TerminalColor {
        if index < 16 {
            return ansi[Int(index)]
        } else if index < 232 {
            let i = Int(index) - 16
            let r = i / 36
            let g = (i % 36) / 6
            let b = i % 6
            let toVal: (Int) -> UInt8 = { $0 == 0 ? 0 : UInt8(55 + $0 * 40) }
            return TerminalColor(r: toVal(r), g: toVal(g), b: toVal(b))
        } else {
            let gray = UInt8(8 + (Int(index) - 232) * 10)
            return TerminalColor(r: gray, g: gray, b: gray)
        }
    }
}

enum TerminalColorSpec: Equatable, Hashable {
    case `default`
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)

    func resolve(palette: [TerminalColor] = TerminalColor.ansi) -> TerminalColor {
        switch self {
        case .default: return .default
        case .indexed(let i):
            if i < 16, i < palette.count { return palette[Int(i)] }
            return TerminalColor.color256(i)
        case .rgb(let r, let g, let b):
            return TerminalColor(r: r, g: g, b: b)
        }
    }
}

struct CellAttributes: Equatable, Hashable {
    var fg: TerminalColorSpec = .default
    var bg: TerminalColorSpec = .default
    var bold = false
    var dim = false
    var italic = false
    var underline = false
    var blink = false
    var inverse = false
    var hidden = false
    var strikethrough = false
    var hyperlinkURL: String?

    static let `default` = CellAttributes()
}

struct TerminalCell: Equatable {
    var character: Character = " "
    var attributes: CellAttributes = .default
    var width: UInt8 = 1  // 1 for normal, 2 for wide chars, 0 for continuation
}

/// An inline image placed in the terminal grid
struct TerminalInlineImage: Identifiable {
    let id = UUID()
    let image: NSImage
    /// Grid row where the image starts (absolute line index including scrollback)
    let row: Int
    /// Grid column where the image starts
    let col: Int
    /// Width in cells
    let widthCells: Int
    /// Height in cells
    let heightCells: Int
}

@MainActor
final class TerminalBuffer {
    private(set) var columns: Int
    private(set) var rows: Int

    private(set) var cursorX: Int = 0
    private(set) var cursorY: Int = 0
    var cursorVisible: Bool = true
    var cursorShape: CursorStyle = .block

    var currentAttributes: CellAttributes = .default

    // Main screen
    private var mainScreen: [[TerminalCell]] = []
    private var mainScrollback: [[TerminalCell]] = []
    private var mainCursorX: Int = 0
    private var mainCursorY: Int = 0

    // Alternate screen
    private var altScreen: [[TerminalCell]] = []
    private(set) var isAlternateScreen = false

    // Active screen reference (points to mainScreen or altScreen)
    private var screen: [[TerminalCell]] {
        get { isAlternateScreen ? altScreen : mainScreen }
        set {
            if isAlternateScreen { altScreen = newValue }
            else { mainScreen = newValue }
        }
    }

    // Scroll region (top and bottom, 0-indexed)
    private(set) var scrollTop: Int = 0
    private(set) var scrollBottom: Int = 0

    // Saved cursor state (DECSC/DECRC)
    private var savedCursorX: Int = 0
    private var savedCursorY: Int = 0
    private var savedAttributes: CellAttributes = .default

    enum MouseMode: Equatable {
        case none
        case click        // 1000
        case buttonMotion // 1002
        case anyMotion    // 1003
        case sgrExtended  // 1006 (modifier, used with above)
    }

    // Mode flags
    var applicationCursorKeys = false
    var bracketedPasteMode = false
    var mouseMode: MouseMode = .none
    var focusEventMode = false
    var useLineDrawingCharset = false
    var autoWrap = true
    private var wrapPending = false

    /// DEC Special Graphics character map
    private static let lineDrawingMap: [Character: Character] = [
        "j": "┘", "k": "┐", "l": "┌", "m": "└", "n": "┼",
        "q": "─", "t": "├", "u": "┤", "v": "┴", "w": "┬",
        "x": "│", "a": "▒", "f": "°", "g": "±", "h": "░",
        "y": "≤", "z": "≥", "`": "◆", "~": "·", "o": "⎺",
        "s": "⎽", "p": "⎻", "r": "⎼",
    ]

    // Inline images
    private(set) var inlineImages: [TerminalInlineImage] = []

    // Title and working directory
    var title: String?
    var workingDirectory: URL?

    // Scrollback limit
    var scrollbackLimit: Int = 10_000

    // Bell
    var bellFired = false

    // Semantic prompt markers (for Cmd+Up/Down navigation)
    struct PromptMark {
        let scrollbackLine: Int  // absolute line index in scrollback
        var exitCode: Int?
        var duration: Double?
    }
    private(set) var promptMarks: [PromptMark] = []
    var lastCommandExitCode: Int?
    var lastCommandDuration: Double?

    func markPromptStart() {
        let absoluteLine = mainScrollback.count + cursorY
        promptMarks.append(PromptMark(scrollbackLine: absoluteLine))
        markDirty()
    }

    func markCommandFinished(exitCode: Int?, duration: Double?) {
        lastCommandExitCode = exitCode
        lastCommandDuration = duration
        if !promptMarks.isEmpty {
            promptMarks[promptMarks.count - 1].exitCode = exitCode
            promptMarks[promptMarks.count - 1].duration = duration
        }
    }

    // Dirty tracking for efficient rendering
    private(set) var isDirty = true

    init(columns: Int = 80, rows: Int = 24) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        scrollBottom = self.rows - 1
        mainScreen = Self.makeEmptyScreen(columns: self.columns, rows: self.rows)
        altScreen = Self.makeEmptyScreen(columns: self.columns, rows: self.rows)
    }

    // MARK: - Resize

    func resize(columns newCols: Int, rows newRows: Int) {
        let newCols = max(newCols, 1)
        let newRows = max(newRows, 1)
        guard newCols != columns || newRows != rows else { return }

        mainScreen = Self.resizeScreen(mainScreen, oldCols: columns, oldRows: rows, newCols: newCols, newRows: newRows)
        altScreen = Self.resizeScreen(altScreen, oldCols: columns, oldRows: rows, newCols: newCols, newRows: newRows)

        let oldRows = rows
        columns = newCols
        rows = newRows
        // Preserve scroll regions proportionally; reset if they spanned the full screen
        if scrollTop == 0 && scrollBottom == oldRows - 1 {
            scrollTop = 0
            scrollBottom = newRows - 1
        } else {
            scrollTop = min(scrollTop, newRows - 1)
            scrollBottom = min(scrollBottom, newRows - 1)
            if scrollTop >= scrollBottom {
                scrollTop = 0
                scrollBottom = newRows - 1
            }
        }
        cursorX = min(cursorX, newCols - 1)
        cursorY = min(cursorY, newRows - 1)
        markDirty()
    }

    // MARK: - Character Output

    func putChar(_ char: Character) {
        if wrapPending {
            wrapPending = false
            carriageReturn()
            lineFeed()
        }

        if cursorX >= columns {
            cursorX = columns - 1
        }
        if cursorY >= rows {
            cursorY = rows - 1
        }

        // Apply DEC line drawing charset substitution
        let outputChar: Character
        if useLineDrawingCharset, let mapped = Self.lineDrawingMap[char] {
            outputChar = mapped
        } else {
            outputChar = char
        }

        // Detect wide characters (CJK, emoji)
        let isWide = Self.isWideCharacter(outputChar)
        if isWide && cursorX >= columns - 1 {
            // Not enough room for a wide char — wrap
            if autoWrap {
                screen[cursorY][cursorX] = TerminalCell(character: " ", attributes: currentAttributes, width: 1)
                carriageReturn()
                lineFeed()
            }
        }

        screen[cursorY][cursorX] = TerminalCell(character: outputChar, attributes: currentAttributes, width: isWide ? 2 : 1)
        if isWide, cursorX + 1 < columns {
            // Mark next cell as continuation
            screen[cursorY][cursorX + 1] = TerminalCell(character: " ", attributes: currentAttributes, width: 0)
        }

        cursorX += isWide ? 2 : 1
        if cursorX >= columns {
            if autoWrap {
                cursorX = columns - 1
                wrapPending = true
            } else {
                cursorX = columns - 1
            }
        }
        markDirty()
    }

    // MARK: - Cursor Movement

    func moveCursorTo(x: Int, y: Int) {
        cursorX = clampX(x)
        cursorY = clampY(y)
        wrapPending = false
        markDirty()
    }

    func moveCursorUp(_ n: Int = 1) {
        cursorY = max(cursorY - n, scrollTop)
        wrapPending = false
        markDirty()
    }

    func moveCursorDown(_ n: Int = 1) {
        cursorY = min(cursorY + n, scrollBottom)
        wrapPending = false
        markDirty()
    }

    func moveCursorForward(_ n: Int = 1) {
        cursorX = min(cursorX + n, columns - 1)
        wrapPending = false
        markDirty()
    }

    func moveCursorBackward(_ n: Int = 1) {
        cursorX = max(cursorX - n, 0)
        wrapPending = false
        markDirty()
    }

    func carriageReturn() {
        cursorX = 0
        wrapPending = false
        markDirty()
    }

    func lineFeed() {
        wrapPending = false
        if cursorY == scrollBottom {
            scrollUp(1)
        } else if cursorY < rows - 1 {
            cursorY += 1
        }
        markDirty()
    }

    func reverseLineFeed() {
        if cursorY == scrollTop {
            scrollDown(1)
        } else if cursorY > 0 {
            cursorY -= 1
        }
        markDirty()
    }

    func tab() {
        let nextTab = ((cursorX / 8) + 1) * 8
        cursorX = min(nextTab, columns - 1)
        markDirty()
    }

    func backspace() {
        if cursorX > 0 {
            cursorX -= 1
            wrapPending = false
        }
        markDirty()
    }

    // MARK: - Erase Operations

    func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0: // from cursor to end
            eraseLine(0)
            for row in (cursorY + 1)..<rows {
                screen[row] = Self.makeEmptyRow(columns: columns, attributes: currentAttributes)
            }
        case 1: // from start to cursor
            for row in 0..<cursorY {
                screen[row] = Self.makeEmptyRow(columns: columns, attributes: currentAttributes)
            }
            eraseLine(1)
        case 2: // entire screen
            for row in 0..<rows {
                screen[row] = Self.makeEmptyRow(columns: columns, attributes: currentAttributes)
            }
        case 3: // entire screen + scrollback
            mainScrollback.removeAll()
            for row in 0..<rows {
                screen[row] = Self.makeEmptyRow(columns: columns, attributes: currentAttributes)
            }
        default: break
        }
        markDirty()
    }

    func eraseLine(_ mode: Int) {
        guard cursorY < rows else { return }
        switch mode {
        case 0: // from cursor to end of line
            for col in cursorX..<columns {
                screen[cursorY][col] = TerminalCell(character: " ", attributes: currentAttributes)
            }
        case 1: // from start to cursor
            for col in 0...min(cursorX, columns - 1) {
                screen[cursorY][col] = TerminalCell(character: " ", attributes: currentAttributes)
            }
        case 2: // entire line
            screen[cursorY] = Self.makeEmptyRow(columns: columns, attributes: currentAttributes)
        default: break
        }
        markDirty()
    }

    // MARK: - Insert / Delete

    func insertLines(_ n: Int) {
        let count = min(n, scrollBottom - cursorY + 1)
        guard count > 0, cursorY >= scrollTop, cursorY <= scrollBottom else { return }
        for _ in 0..<count {
            screen.remove(at: scrollBottom)
            screen.insert(Self.makeEmptyRow(columns: columns, attributes: currentAttributes), at: cursorY)
        }
        markDirty()
    }

    func deleteLines(_ n: Int) {
        let count = min(n, scrollBottom - cursorY + 1)
        guard count > 0, cursorY >= scrollTop, cursorY <= scrollBottom else { return }
        for _ in 0..<count {
            screen.remove(at: cursorY)
            screen.insert(Self.makeEmptyRow(columns: columns, attributes: currentAttributes), at: scrollBottom)
        }
        markDirty()
    }

    func insertChars(_ n: Int) {
        guard cursorY < rows else { return }
        let count = min(n, columns - cursorX)
        guard count > 0 else { return }
        var row = screen[cursorY]
        row.insert(contentsOf: Array(repeating: TerminalCell(character: " ", attributes: currentAttributes), count: count), at: cursorX)
        screen[cursorY] = Array(row.prefix(columns))
        markDirty()
    }

    func deleteChars(_ n: Int) {
        guard cursorY < rows else { return }
        let count = min(n, columns - cursorX)
        guard count > 0 else { return }
        var row = screen[cursorY]
        row.removeSubrange(cursorX..<(cursorX + count))
        row.append(contentsOf: Array(repeating: TerminalCell(character: " ", attributes: currentAttributes), count: count))
        screen[cursorY] = Array(row.prefix(columns))
        markDirty()
    }

    func eraseChars(_ n: Int) {
        guard cursorY < rows else { return }
        let count = min(n, columns - cursorX)
        for i in 0..<count {
            screen[cursorY][cursorX + i] = TerminalCell(character: " ", attributes: currentAttributes)
        }
        markDirty()
    }

    // MARK: - Scrolling

    func scrollUp(_ n: Int) {
        let count = min(n, scrollBottom - scrollTop + 1)
        guard count > 0 else { return }
        for _ in 0..<count {
            let removed = screen[scrollTop]
            screen.remove(at: scrollTop)
            screen.insert(Self.makeEmptyRow(columns: columns, attributes: currentAttributes), at: scrollBottom)
            if !isAlternateScreen {
                mainScrollback.append(removed)
                if mainScrollback.count > scrollbackLimit {
                    mainScrollback.removeFirst(mainScrollback.count - scrollbackLimit)
                }
            }
        }
        markDirty()
    }

    func scrollDown(_ n: Int) {
        let count = min(n, scrollBottom - scrollTop + 1)
        guard count > 0 else { return }
        for _ in 0..<count {
            screen.remove(at: scrollBottom)
            screen.insert(Self.makeEmptyRow(columns: columns, attributes: currentAttributes), at: scrollTop)
        }
        markDirty()
    }

    // MARK: - Scroll Region

    func setScrollRegion(top: Int, bottom: Int) {
        let t = max(0, top)
        let b = min(rows - 1, bottom)
        guard t < b else { return }
        scrollTop = t
        scrollBottom = b
        moveCursorTo(x: 0, y: 0)
    }

    func resetScrollRegion() {
        scrollTop = 0
        scrollBottom = rows - 1
    }

    // MARK: - Alternate Screen

    func switchToAlternateScreen() {
        guard !isAlternateScreen else { return }
        mainCursorX = cursorX
        mainCursorY = cursorY
        isAlternateScreen = true
        altScreen = Self.makeEmptyScreen(columns: columns, rows: rows)
        cursorX = 0
        cursorY = 0
        scrollTop = 0
        scrollBottom = rows - 1
        markDirty()
    }

    func switchToMainScreen() {
        guard isAlternateScreen else { return }
        isAlternateScreen = false
        cursorX = mainCursorX
        cursorY = mainCursorY
        scrollTop = 0
        scrollBottom = rows - 1
        markDirty()
    }

    // MARK: - Save / Restore Cursor

    func saveCursor() {
        savedCursorX = cursorX
        savedCursorY = cursorY
        savedAttributes = currentAttributes
    }

    func restoreCursor() {
        cursorX = clampX(savedCursorX)
        cursorY = clampY(savedCursorY)
        currentAttributes = savedAttributes
        wrapPending = false
        markDirty()
    }

    // MARK: - Full Reset

    func reset() {
        cursorX = 0
        cursorY = 0
        currentAttributes = .default
        autoWrap = true
        wrapPending = false
        applicationCursorKeys = false
        bracketedPasteMode = false
        mouseMode = .none
        useLineDrawingCharset = false
        cursorVisible = true
        cursorShape = .block
        scrollTop = 0
        scrollBottom = rows - 1
        isAlternateScreen = false
        mainScreen = Self.makeEmptyScreen(columns: columns, rows: rows)
        altScreen = Self.makeEmptyScreen(columns: columns, rows: rows)
        mainScrollback.removeAll()
        markDirty()
    }

    // MARK: - Read Access

    func cell(at x: Int, y: Int) -> TerminalCell {
        guard y >= 0, y < rows, x >= 0, x < columns else {
            return TerminalCell()
        }
        return screen[y][x]
    }

    func line(_ y: Int) -> [TerminalCell] {
        guard y >= 0, y < rows else { return Self.makeEmptyRow(columns: columns) }
        return screen[y]
    }

    var scrollback: [[TerminalCell]] { mainScrollback }

    /// Place an inline image at the current cursor position.
    /// The image occupies `widthCells` x `heightCells` grid cells.
    /// Cursor advances past the image.
    func placeInlineImage(_ image: NSImage, widthCells: Int, heightCells: Int) {
        let absoluteRow = mainScrollback.count + cursorY
        let img = TerminalInlineImage(
            image: image, row: absoluteRow, col: cursorX,
            widthCells: widthCells, heightCells: heightCells
        )
        inlineImages.append(img)

        // Cap stored images to prevent unbounded memory growth
        if inlineImages.count > 200 {
            inlineImages.removeFirst(inlineImages.count - 200)
        }

        // Advance cursor past the image
        for _ in 0..<heightCells {
            lineFeed()
        }
    }

    var totalLineCount: Int { mainScrollback.count + rows }

    /// All lines: scrollback + active screen
    var allLines: [[TerminalCell]] {
        var lines = mainScrollback
        lines.append(contentsOf: isAlternateScreen ? mainScreen : screen)
        return lines
    }

    /// Snapshot visible screen + scrollback as plain text
    func plainText(includeScrollback: Bool = true) -> String {
        var lines: [[TerminalCell]] = []
        if includeScrollback {
            lines.append(contentsOf: mainScrollback)
        }
        lines.append(contentsOf: isAlternateScreen ? mainScreen : screen)

        return lines.map { row in
            let s = String(row.map(\.character))
            return s.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    /// Returns up to maxChars from the last non-empty screen line (cheap operation)
    func lastScreenLine(maxChars: Int) -> String {
        for row in stride(from: rows - 1, through: 0, by: -1) {
            let cells = line(row)
            let text = String(cells.map(\.character)).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if !text.isEmpty { return String(text.suffix(maxChars)) }
        }
        return ""
    }

    func clearDirty() {
        isDirty = false
    }

    // MARK: - Private Helpers

    private func markDirty() {
        isDirty = true
    }

    private func clampX(_ x: Int) -> Int { max(0, min(x, columns - 1)) }
    private func clampY(_ y: Int) -> Int { max(0, min(y, rows - 1)) }

    /// Detect East Asian Wide and emoji characters
    static func isWideCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let v = scalar.value
        // CJK Unified Ideographs
        if v >= 0x4E00 && v <= 0x9FFF { return true }
        // CJK Unified Ideographs Extension A/B
        if v >= 0x3400 && v <= 0x4DBF { return true }
        if v >= 0x20000 && v <= 0x2A6DF { return true }
        // CJK Compatibility Ideographs
        if v >= 0xF900 && v <= 0xFAFF { return true }
        // Fullwidth forms
        if v >= 0xFF01 && v <= 0xFF60 { return true }
        if v >= 0xFFE0 && v <= 0xFFE6 { return true }
        // Hangul Syllables
        if v >= 0xAC00 && v <= 0xD7AF { return true }
        // Katakana/Hiragana
        if v >= 0x3000 && v <= 0x303F { return true }
        if v >= 0x3040 && v <= 0x309F { return true }
        if v >= 0x30A0 && v <= 0x30FF { return true }
        // Emoji (common ranges)
        if v >= 0x1F300 && v <= 0x1F9FF { return true }
        if v >= 0x1FA00 && v <= 0x1FAFF { return true }
        return false
    }

    private static func makeEmptyRow(columns: Int, attributes: CellAttributes = .default) -> [TerminalCell] {
        Array(repeating: TerminalCell(character: " ", attributes: attributes), count: columns)
    }

    private static func makeEmptyScreen(columns: Int, rows: Int) -> [[TerminalCell]] {
        (0..<rows).map { _ in makeEmptyRow(columns: columns) }
    }

    private static func resizeScreen(_ screen: [[TerminalCell]], oldCols: Int, oldRows: Int, newCols: Int, newRows: Int) -> [[TerminalCell]] {
        var result = screen.map { row -> [TerminalCell] in
            if row.count < newCols {
                return row + Array(repeating: TerminalCell(), count: newCols - row.count)
            } else {
                return Array(row.prefix(newCols))
            }
        }
        if result.count < newRows {
            result.append(contentsOf: (0..<(newRows - result.count)).map { _ in makeEmptyRow(columns: newCols) })
        } else if result.count > newRows {
            result = Array(result.suffix(newRows))
        }
        return result
    }
}
