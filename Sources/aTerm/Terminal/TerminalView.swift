import AppKit
import CoreText
import SwiftUI

struct TerminalView: NSViewRepresentable {
    let buffer: TerminalBuffer
    let appearance: TerminalAppearance
    let theme: TerminalTheme
    let searchQuery: String
    let isRegexSearchEnabled: Bool
    let searchMatches: [ScrollbackSearchMatch]
    let currentSearchIndex: Int
    let onInput: (Data) -> Void
    let onResize: (UInt16, UInt16) -> Void
    let onBecomeActive: () -> Void
    var onChatExit: (() -> Void)?
    var onChatEnter: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(onInput: onInput, onResize: onResize, onBecomeActive: onBecomeActive)
        coordinator.onChatExit = onChatExit
        coordinator.onChatEnter = onChatEnter
        return coordinator
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        let view = TerminalContainerView()
        view.configure(with: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        nsView.applyAppearance(appearance, theme: theme)
        nsView.updateBuffer(buffer)
        // Update chat callbacks in case they changed
        context.coordinator.onChatExit = onChatExit
        context.coordinator.onChatEnter = onChatEnter
        // When the running program switches to alternate screen (vim, less, claude, etc.),
        // grab keyboard focus so keystrokes go directly to the PTY
        if buffer.isAlternateScreen {
            nsView.focusTerminal()
        }
        // Grid recalculation happens via layout() on frame change — not here.
    }

    final class Coordinator: NSObject, TerminalInputHandling {
        private let onInput: (Data) -> Void
        private let onResize: (UInt16, UInt16) -> Void
        private let onBecomeActive: () -> Void
        var onChatExit: (() -> Void)?
        var onChatEnter: ((String) -> Void)?

        init(onInput: @escaping (Data) -> Void, onResize: @escaping (UInt16, UInt16) -> Void, onBecomeActive: @escaping () -> Void) {
            self.onInput = onInput
            self.onResize = onResize
            self.onBecomeActive = onBecomeActive
        }

        func send(bytes: Data) { onInput(bytes) }
        func resize(columns: UInt16, rows: UInt16) { onResize(columns, rows) }
        func didBecomeActive() { onBecomeActive() }
        func sendFocusEvent(focused: Bool) {
            // CSI I (focus in) / CSI O (focus out)
            let seq = focused ? "\u{1B}[I" : "\u{1B}[O"
            onInput(Data(seq.utf8))
        }
        func sendChatExit() { onChatExit?() }
        func sendChatEnter(content: String) { onChatEnter?(content) }
    }
}

@MainActor
protocol TerminalInputHandling: AnyObject {
    func send(bytes: Data)
    func resize(columns: UInt16, rows: UInt16)
    func didBecomeActive()
    func sendFocusEvent(focused: Bool)
    func sendChatExit()
    func sendChatEnter(content: String)
}

// MARK: - Selection Model

struct TerminalPosition: Comparable {
    let line: Int  // absolute line (scrollback + screen)
    let col: Int

    static func < (lhs: TerminalPosition, rhs: TerminalPosition) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.col < rhs.col
    }
}

struct TerminalSelection {
    var start: TerminalPosition
    var end: TerminalPosition

    var normalized: (start: TerminalPosition, end: TerminalPosition) {
        start < end ? (start, end) : (end, start)
    }

    func contains(line: Int, col: Int) -> Bool {
        let (s, e) = normalized
        if line < s.line || line > e.line { return false }
        if line == s.line && line == e.line { return col >= s.col && col < e.col }
        if line == s.line { return col >= s.col }
        if line == e.line { return col < e.col }
        return true
    }
}

// MARK: - Container View

@MainActor
final class TerminalContainerView: NSView {
    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    let gridView = TerminalGridView()
    private weak var handler: TerminalInputHandling?
    private(set) var appliedAppearance = TerminalAppearance.default
    private(set) var appliedTheme = BuiltinThemes.all.last!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        effectView.blendingMode = .behindWindow
        effectView.state = .active
        addSubview(effectView)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        gridView.containerView = self
        scrollView.documentView = gridView
        effectView.addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var lastLayoutSize: NSSize = .zero

    override func layout() {
        super.layout()
        effectView.frame = bounds
        scrollView.frame = bounds
        // Only recalculate grid when our size actually changes
        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            recalculateGrid()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Focus event reporting (mode 1004)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window)
        }
        
        // Always ensure terminal becomes first responder for traditional terminal mode
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Log.debug("focus", "viewDidMoveToWindow - attempting to make gridView first responder")
            let success = self.window?.makeFirstResponder(self.gridView) ?? false
            Log.debug("focus", "makeFirstResponder result: \(success)")
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        Log.debug("focus", "windowDidBecomeKey")
        // Ensure gridView becomes first responder when window becomes key
        DispatchQueue.main.async { [weak self] in
            let success = self?.window?.makeFirstResponder(self?.gridView) ?? false
            Log.debug("focus", "windowDidBecomeKey makeFirstResponder: \(success)")
        }
        if gridView.buffer?.focusEventMode == true {
            handler?.sendFocusEvent(focused: true)
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        Log.debug("focus", "windowDidResignKey")
        if gridView.buffer?.focusEventMode == true {
            handler?.sendFocusEvent(focused: false)
        }
    }

    func configure(with handler: TerminalInputHandling) {
        self.handler = handler
        gridView.inputHandler = handler
    }

    func focusTerminal() {
        Log.debug("focus", "focusTerminal called")
        guard let window = window else {
            Log.debug("focus", "focusTerminal: no window")
            return
        }
        let success = window.makeFirstResponder(gridView)
        Log.debug("focus", "focusTerminal result: \(success)")
    }
    
    override func becomeFirstResponder() -> Bool {
        Log.debug("focus", "TerminalContainerView becomeFirstResponder")
        // Forward to gridView
        return window?.makeFirstResponder(gridView) ?? false
    }

    func applyAppearance(_ appearance: TerminalAppearance, theme: TerminalTheme) {
        let themeChanged = theme.id != appliedTheme.id
        let appearanceChanged = appearance != appliedAppearance
        if themeChanged {
            Log.debug("ui", "applyAppearance: theme changed \(appliedTheme.id) → \(theme.id)")
        }
        guard themeChanged || appearanceChanged else { return }
        appliedAppearance = appearance
        appliedTheme = theme

        wantsLayer = true
        layer?.backgroundColor = theme.palette.background.withAlpha(appearance.opacity).nsColor.cgColor

        effectView.material = appearance.blur > 0.55 ? .hudWindow : .underWindowBackground
        effectView.alphaValue = appearance.blur
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = theme.palette.background.withAlpha(appearance.opacity).nsColor.cgColor

        gridView.updateAppearance(appearance: appearance, theme: theme)
    }

    func updateBuffer(_ buffer: TerminalBuffer) {
        let shouldFollowTail = isScrolledNearBottom()
        gridView.buffer = buffer
        gridView.needsDisplay = true

        let totalLines = buffer.totalLineCount
        let lineHeight = gridView.cellHeight
        // Add extra padding at bottom so cursor/prompt isn't hidden at edge
        let bottomPadding: CGFloat = 8
        let docHeight = max(CGFloat(totalLines) * lineHeight + bottomPadding, scrollView.contentView.bounds.height)
        gridView.frame = NSRect(x: 0, y: 0, width: scrollView.contentView.bounds.width, height: docHeight)

        if shouldFollowTail {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, docHeight - scrollView.contentView.bounds.height)))
        }
    }

    func recalculateGrid() {
        let cw = gridView.cellWidth
        let ch = gridView.cellHeight
        guard cw > 0, ch > 0 else { return }
        let horizontalInset = appliedAppearance.padding.left + appliedAppearance.padding.right
        let verticalInset = appliedAppearance.padding.top + appliedAppearance.padding.bottom
        let columns = max(20, Int((bounds.width - horizontalInset) / cw))
        let rows = max(5, Int((bounds.height - verticalInset) / ch))
        handler?.resize(columns: UInt16(columns), rows: UInt16(rows))
    }

    private func isScrolledNearBottom() -> Bool {
        guard gridView.frame.height > 0 else { return true }
        let visibleMaxY = scrollView.contentView.bounds.maxY
        let contentMaxY = gridView.frame.maxY
        return contentMaxY - visibleMaxY < gridView.cellHeight * 2
    }
}

// MARK: - Grid View (Core Text renderer + selection + mouse)

@MainActor
final class TerminalGridView: NSView {
    weak var inputHandler: TerminalInputHandling?
    weak var containerView: TerminalContainerView?
    var buffer: TerminalBuffer?

    private var font: NSFont = .monospacedSystemFont(ofSize: 18, weight: .medium)
    private var boldFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .bold)
    private var italicFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    private var termAppearance: TerminalAppearance = .default
    private var theme: TerminalTheme = BuiltinThemes.all.last!

    private(set) var cellWidth: CGFloat = 8
    private(set) var cellHeight: CGFloat = 16

    // Selection state
    private var selection: TerminalSelection?
    private var isDragging = false
    private var clickCount = 0

    // Cursor blink state
    private var cursorBlinkVisible = true
    private var cursorBlinkTimer: Timer?
    
    // Local line buffer for intercepting /chat commands
    private var localLineBuffer = ""
    private var isLocalBufferActive = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    func updateAppearance(appearance newAppearance: TerminalAppearance, theme newTheme: TerminalTheme) {
        self.termAppearance = newAppearance
        self.theme = newTheme

        // Use medium weight for better visibility
        font = NSFont(name: newAppearance.fontName, size: newAppearance.fontSize)
            ?? .monospacedSystemFont(ofSize: newAppearance.fontSize, weight: .medium)
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let italicDesc = font.fontDescriptor.withSymbolicTraits(.italic)
        italicFont = NSFont(descriptor: italicDesc, size: newAppearance.fontSize) ?? font

        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let charSize = ("W" as NSString).size(withAttributes: attrs)
        cellWidth = max(charSize.width + newAppearance.letterSpacing, 1)
        cellHeight = max((font.ascender - font.descender + font.leading) * newAppearance.lineHeight, 1)

        configureCursorBlink()
        needsDisplay = true
    }

    private func configureCursorBlink() {
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil

        if termAppearance.cursorBlink {
            cursorBlinkVisible = true
            cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.cursorBlinkVisible.toggle()
                    self.needsDisplay = true
                }
            }
        } else {
            cursorBlinkVisible = true
        }
    }

    // MARK: - Grid Position from Point

    private func gridPosition(for point: NSPoint) -> TerminalPosition {
        let paddingLeft = termAppearance.padding.left
        let paddingTop = termAppearance.padding.top
        let col = max(0, Int((point.x - paddingLeft) / cellWidth))
        let line = max(0, Int((point.y - paddingTop) / cellHeight))
        return TerminalPosition(line: line, col: col)
    }

    // MARK: - Selection Text

    func selectedText() -> String? {
        guard let selection, let buffer else { return nil }
        let (start, end) = selection.normalized
        var result = ""
        let scrollbackCount = buffer.scrollback.count

        for lineIdx in start.line...end.line {
            let cells: [TerminalCell]
            if lineIdx < scrollbackCount {
                guard lineIdx < buffer.scrollback.count else { continue }
                cells = buffer.scrollback[lineIdx]
            } else {
                let screenRow = lineIdx - scrollbackCount
                guard screenRow < buffer.rows else { continue }
                cells = buffer.line(screenRow)
            }

            let colStart = (lineIdx == start.line) ? start.col : 0
            let colEnd = (lineIdx == end.line) ? end.col : cells.count

            for col in colStart..<min(colEnd, cells.count) {
                result.append(cells[col].character)
            }

            // Trim trailing spaces on each line, add newline between lines
            if lineIdx < end.line {
                while result.hasSuffix(" ") { result.removeLast() }
                result.append("\n")
            }
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let buffer = buffer else { return }

        let themePalette = theme.palette
        let bgColor = themePalette.background.withAlpha(termAppearance.opacity).nsColor.cgColor
        ctx.setFillColor(bgColor)
        ctx.fill(dirtyRect)

        let paddingLeft = termAppearance.padding.left
        let paddingTop = termAppearance.padding.top

        let scrollbackLines = buffer.scrollback
        let totalScrollback = scrollbackLines.count
        let columns = buffer.columns
        let rows = buffer.rows

        let firstVisibleLine = max(0, Int(dirtyRect.minY / cellHeight))
        let lastVisibleLine = min(totalScrollback + rows - 1, Int(dirtyRect.maxY / cellHeight) + 1)

        let defaultFG = themePalette.foreground
        let defaultBG = themePalette.background
        let cursorColor = themePalette.cursor
        let selectionColor = themePalette.selection

        guard firstVisibleLine <= lastVisibleLine else { return }

        for lineIndex in firstVisibleLine...lastVisibleLine {
            let y = CGFloat(lineIndex) * cellHeight + paddingTop
            let cells: [TerminalCell]

            if lineIndex < totalScrollback {
                guard lineIndex < scrollbackLines.count else { continue }
                cells = scrollbackLines[lineIndex]
            } else {
                let screenRow = lineIndex - totalScrollback
                guard screenRow < rows else { continue }
                cells = buffer.line(screenRow)
            }

            for col in 0..<min(cells.count, columns) {
                let cell = cells[col]
                let x = CGFloat(col) * cellWidth + paddingLeft
                let cellRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)

                guard cellRect.intersects(dirtyRect) else { continue }

                let attrs = cell.attributes
                var fgSpec = attrs.fg
                var bgSpec = attrs.bg
                if attrs.inverse { swap(&fgSpec, &bgSpec) }

                let fgColor = resolveColor(fgSpec, default: defaultFG)
                let bgColorResolved = resolveColor(bgSpec, default: defaultBG)

                // Background
                if bgSpec != .default {
                    ctx.setFillColor(bgColorResolved.nsColor.cgColor)
                    ctx.fill(cellRect)
                }

                // Selection highlight
                if let selection, selection.contains(line: lineIndex, col: col) {
                    ctx.setFillColor(selectionColor.withAlpha(0.35).nsColor.cgColor)
                    ctx.fill(cellRect)
                }

                // Cursor
                let isScreenLine = lineIndex >= totalScrollback
                let screenRow = lineIndex - totalScrollback
                if isScreenLine, screenRow == buffer.cursorY, col == buffer.cursorX, buffer.cursorVisible, cursorBlinkVisible {
                    ctx.setFillColor(cursorColor.nsColor.withAlphaComponent(0.6).cgColor)
                    switch buffer.cursorShape {
                    case .block: ctx.fill(cellRect)
                    case .bar: ctx.fill(CGRect(x: x, y: y, width: 2, height: cellHeight))
                    case .underline: ctx.fill(CGRect(x: x, y: y + cellHeight - 2, width: cellWidth, height: 2))
                    }
                }

                // Character
                let ch = cell.character
                guard ch != " " || attrs.underline || attrs.strikethrough else { continue }

                let drawFont: NSFont
                if attrs.bold && attrs.italic {
                    drawFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)
                } else if attrs.bold { drawFont = boldFont }
                else if attrs.italic { drawFont = italicFont }
                else { drawFont = font }

                // Always draw at full brightness - ignore dim attribute for better visibility
                let attrString = NSAttributedString(string: String(ch), attributes: [
                    .font: drawFont,
                    .foregroundColor: fgColor.nsColor,
                ])
                let ctLine = CTLineCreateWithAttributedString(attrString)

                ctx.saveGState()
                ctx.translateBy(x: 0, y: y + cellHeight)
                ctx.scaleBy(x: 1, y: -1)
                ctx.textPosition = CGPoint(x: x, y: (cellHeight - font.ascender + font.descender) / 2 - font.descender)
                CTLineDraw(ctLine, ctx)
                ctx.restoreGState()

                if attrs.underline {
                    ctx.setStrokeColor(fgColor.nsColor.cgColor)
                    ctx.setLineWidth(1)
                    ctx.move(to: CGPoint(x: x, y: y + cellHeight - 1))
                    ctx.addLine(to: CGPoint(x: x + cellWidth, y: y + cellHeight - 1))
                    ctx.strokePath()
                }
                if attrs.strikethrough {
                    ctx.setStrokeColor(fgColor.nsColor.cgColor)
                    ctx.setLineWidth(1)
                    ctx.move(to: CGPoint(x: x, y: y + cellHeight / 2))
                    ctx.addLine(to: CGPoint(x: x + cellWidth, y: y + cellHeight / 2))
                    ctx.strokePath()
                }
            }
        }

        // Render inline images
        for img in buffer.inlineImages {
            let imgY = CGFloat(img.row) * cellHeight + paddingTop
            let imgX = CGFloat(img.col) * cellWidth + paddingLeft
            let imgWidth = CGFloat(img.widthCells) * cellWidth
            let imgHeight = CGFloat(img.heightCells) * cellHeight
            let imgRect = CGRect(x: imgX, y: imgY, width: imgWidth, height: imgHeight)

            guard imgRect.intersects(dirtyRect) else { continue }

            ctx.saveGState()
            // NSImage draws in flipped coordinates; we need to flip since isFlipped = true
            if let cgImage = img.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cgImage, in: imgRect)
            }
            ctx.restoreGState()
        }
    }

    private func resolveColor(_ spec: TerminalColorSpec, default defaultColor: ThemeColor) -> ThemeColor {
        switch spec {
        case .default: return defaultColor
        case .indexed(let i):
            // Use theme ANSI palette for 0-15 if available
            if let container = containerView, i < 16 {
                let palette = container.appliedTheme.palette.ansi
                if Int(i) < palette.count { return palette[Int(i)] }
            }
            let tc = TerminalColor.color256(i)
            return ThemeColor(red: Double(tc.r) / 255, green: Double(tc.g) / 255, blue: Double(tc.b) / 255)
        case .rgb(let r, let g, let b):
            return ThemeColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        Log.debug("input", "keyDown RECEIVED: characters='\(event.characters ?? "nil")' keyCode=\(event.keyCode)")
        
        let cmd = event.modifierFlags.contains(.command)

        // Cmd+C → copy selection
        if cmd, event.charactersIgnoringModifiers == "c" {
            if let text = selectedText() {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                return
            }
            // If no selection, let Ctrl+C (0x03) pass through
        }

        // Cmd+V → paste
        if cmd, event.charactersIgnoringModifiers == "v" {
            pasteFromClipboard()
            return
        }

        // Cmd+A → select all
        if cmd, event.charactersIgnoringModifiers == "a" {
            selectAll()
            return
        }

        // Clear selection on any other key
        if selection != nil {
            selection = nil
            needsDisplay = true
        }

        // Handle chat command interception
        if let data = TerminalKeyMapper.data(for: event) {
            // Check for Return key (keyCode 36)
            if event.keyCode == 36 {
                // Check if local buffer starts with /chat command
                let trimmed = localLineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.lowercased() == "/chat-exit" {
                    localLineBuffer = ""
                    inputHandler?.sendChatExit()
                    return
                }
                if trimmed.lowercased().hasPrefix("/chat ") || trimmed.lowercased() == "/chat" {
                    let chatContent = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                    localLineBuffer = ""
                    inputHandler?.sendChatEnter(content: chatContent)
                    return
                }
                // Not a chat command, send normally and clear buffer
                localLineBuffer = ""
                inputHandler?.send(bytes: data)
                return
            }
            
            // Handle backspace/delete (keyCode 51)
            if event.keyCode == 51 {
                if !localLineBuffer.isEmpty {
                    localLineBuffer.removeLast()
                }
                inputHandler?.send(bytes: data)
                return
            }
            
            // Handle escape (keyCode 53) - clear buffer
            if event.keyCode == 53 {
                localLineBuffer = ""
                inputHandler?.send(bytes: data)
                return
            }
            
            // Regular character - add to buffer and send
            if let chars = event.characters {
                localLineBuffer.append(chars)
            }
            inputHandler?.send(bytes: data)
            return
        }
        
        Log.debug("input", "keyDown: unmapped keyCode=\(event.keyCode)")
        super.keyDown(with: event)
    }

    // MARK: - Mouse (Selection + Reporting)

    override func mouseDown(with event: NSEvent) {
        inputHandler?.didBecomeActive()
        
        // CRITICAL: Ensure terminal takes focus on click
        let success = window?.makeFirstResponder(self) ?? false
        Log.debug("focus", "mouseDown makeFirstResponder: \(success)")

        // Cmd+click: open URL under cursor (OSC 8 hyperlinks or detected URLs)
        if event.modifierFlags.contains(.command) {
            let pos = gridPosition(for: convert(event.locationInWindow, from: nil))
            if let url = detectURL(at: pos) {
                NSWorkspace.shared.open(url)
                return
            }
        }

        // Mouse reporting
        if let buffer, buffer.mouseMode != .none, !event.modifierFlags.contains(.command) {
            sendMouseEvent(event, type: .press, button: 0)
            return
        }

        let pos = gridPosition(for: convert(event.locationInWindow, from: nil))
        clickCount = event.clickCount

        if clickCount == 2 {
            selectWord(at: pos)
        } else if clickCount == 3 {
            selectLine(at: pos)
        } else {
            selection = TerminalSelection(start: pos, end: pos)
            isDragging = true
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let buffer, buffer.mouseMode == .buttonMotion || buffer.mouseMode == .anyMotion {
            sendMouseEvent(event, type: .drag, button: 0)
            return
        }

        guard isDragging else { return }
        let pos = gridPosition(for: convert(event.locationInWindow, from: nil))
        selection?.end = pos
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let buffer, buffer.mouseMode != .none, !event.modifierFlags.contains(.command) {
            sendMouseEvent(event, type: .release, button: 0)
            return
        }
        isDragging = false

        // Clear selection if it's zero-width
        if let sel = selection, sel.start == sel.end {
            selection = nil
            needsDisplay = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // In alternate screen with mouse mode, send scroll as mouse buttons
        if let buffer, buffer.isAlternateScreen, buffer.mouseMode != .none {
            let button: UInt8 = event.scrollingDeltaY > 0 ? 64 : 65
            sendMouseReport(button: button, col: 0, row: 0, type: .press)
            return
        }
        super.scrollWheel(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(for: event)
    }

    // MARK: - Context Menu

    private func showContextMenu(for event: NSEvent) {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copySelection), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.isEnabled = selection != nil
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteAction), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = .command
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAllAction), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        menu.addItem(selectAllItem)

        let clearItem = NSMenuItem(title: "Clear Scrollback", action: #selector(clearScrollbackAction), keyEquivalent: "k")
        clearItem.keyEquivalentModifierMask = .command
        menu.addItem(clearItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copySelection() {
        if let text = selectedText() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    @objc private func pasteAction() {
        pasteFromClipboard()
    }

    @objc private func selectAllAction() {
        selectAll()
    }

    @objc private func clearScrollbackAction() {
        buffer?.eraseInDisplay(3)
        needsDisplay = true
    }

    // MARK: - Paste

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let sanitized = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")

        if let buffer, buffer.bracketedPasteMode {
            var data = Data("\u{1b}[200~".utf8)
            data.append(Data(sanitized.utf8))
            data.append(Data("\u{1b}[201~".utf8))
            inputHandler?.send(bytes: data)
        } else {
            inputHandler?.send(bytes: Data(sanitized.utf8))
        }
    }

    // MARK: - Selection Helpers

    private func selectWord(at pos: TerminalPosition) {
        guard let buffer else { return }
        let cells = cellsForLine(pos.line, buffer: buffer)
        guard pos.col < cells.count else { return }

        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.~/"))
        var start = pos.col
        var end = pos.col

        while start > 0, cells[start - 1].character.unicodeScalars.allSatisfy({ wordChars.contains($0) }) {
            start -= 1
        }
        while end < cells.count, cells[end].character.unicodeScalars.allSatisfy({ wordChars.contains($0) }) {
            end += 1
        }

        selection = TerminalSelection(
            start: TerminalPosition(line: pos.line, col: start),
            end: TerminalPosition(line: pos.line, col: end)
        )
    }

    private func selectLine(at pos: TerminalPosition) {
        guard let buffer else { return }
        let cols = buffer.columns
        selection = TerminalSelection(
            start: TerminalPosition(line: pos.line, col: 0),
            end: TerminalPosition(line: pos.line, col: cols)
        )
    }

    private func selectAll() {
        guard let buffer else { return }
        let totalLines = buffer.totalLineCount
        selection = TerminalSelection(
            start: TerminalPosition(line: 0, col: 0),
            end: TerminalPosition(line: max(0, totalLines - 1), col: buffer.columns)
        )
        needsDisplay = true
    }

    private func cellsForLine(_ lineIndex: Int, buffer: TerminalBuffer) -> [TerminalCell] {
        let scrollbackCount = buffer.scrollback.count
        if lineIndex < scrollbackCount {
            return buffer.scrollback[lineIndex]
        } else {
            let screenRow = lineIndex - scrollbackCount
            return buffer.line(screenRow)
        }
    }

    // MARK: - URL Detection

    private func detectURL(at pos: TerminalPosition) -> URL? {
        guard let buffer else { return nil }
        let allLines = buffer.allLines

        guard pos.line >= 0, pos.line < allLines.count else { return nil }
        let line = allLines[pos.line]

        // Check OSC 8 hyperlink on the cell
        if pos.col >= 0, pos.col < line.count, let hyperlink = line[pos.col].attributes.hyperlinkURL {
            return URL(string: hyperlink)
        }

        // Detect URLs in the line text
        let lineText = String(line.map(\.character))
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(lineText.startIndex..<lineText.endIndex, in: lineText)
        for match in detector.matches(in: lineText, range: range) {
            guard let matchRange = Range(match.range, in: lineText) else { continue }
            let startCol = lineText.distance(from: lineText.startIndex, to: matchRange.lowerBound)
            let endCol = lineText.distance(from: lineText.startIndex, to: matchRange.upperBound)
            if pos.col >= startCol && pos.col < endCol {
                return match.url
            }
        }

        return nil
    }

    // MARK: - Mouse Reporting

    private enum MouseEventType { case press, release, drag }

    private func sendMouseEvent(_ event: NSEvent, type: MouseEventType, button: UInt8) {
        let pos = gridPosition(for: convert(event.locationInWindow, from: nil))
        guard let buffer else { return }
        let scrollback = buffer.scrollback.count
        let row = max(0, pos.line - scrollback)
        let col = pos.col
        sendMouseReport(button: button, col: col, row: row, type: type)
    }

    private func sendMouseReport(button: UInt8, col: Int, row: Int, type: MouseEventType) {
        guard let buffer else { return }

        if buffer.mouseMode == .sgrExtended {
            // SGR extended mode: ESC [ < Cb ; Cx ; Cy M/m
            let cb = button
            let suffix: Character = type == .release ? "m" : "M"
            let report = "\u{1b}[<\(cb);\(col + 1);\(row + 1)\(suffix)"
            inputHandler?.send(bytes: Data(report.utf8))
        } else {
            // X10 mode: ESC [ M Cb Cx Cy (add 32 to each)
            let cb = button + 32
            let cx = UInt8(clamping: col + 33)
            let cy = UInt8(clamping: row + 33)
            inputHandler?.send(bytes: Data([0x1b, 0x5b, 0x4d, cb, cx, cy]))
        }
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return false }
        let paths = urls.map { path in
            let escaped = path.path.replacingOccurrences(of: " ", with: "\\ ")
            return escaped
        }.joined(separator: " ")
        inputHandler?.send(bytes: Data(paths.utf8))
        return true
    }
}

// MARK: - Keyboard Mapper

@MainActor
enum TerminalKeyMapper {
    nonisolated(unsafe) static var applicationCursorKeys = false

    static func data(for event: NSEvent) -> Data? {
        let flags = event.modifierFlags
        let ctrl = flags.contains(.control)
        let alt = flags.contains(.option)
        let shift = flags.contains(.shift)
        let arrowPrefix = applicationCursorKeys ? "\u{1b}O" : "\u{1b}["

        switch Int(event.keyCode) {
        case 36: return Data("\r".utf8)
        case 48: return shift ? Data("\u{1b}[Z".utf8) : Data("\t".utf8)
        case 51: return ctrl ? Data([0x08]) : Data([0x7f])
        case 117: return Data("\u{1b}[3~".utf8)
        case 53: return Data([0x1b])

        case 123:
            if ctrl { return Data("\u{1b}[1;5D".utf8) }
            if alt { return Data("\u{1b}b".utf8) }
            if shift { return Data("\u{1b}[1;2D".utf8) }
            return Data((arrowPrefix + "D").utf8)
        case 124:
            if ctrl { return Data("\u{1b}[1;5C".utf8) }
            if alt { return Data("\u{1b}f".utf8) }
            if shift { return Data("\u{1b}[1;2C".utf8) }
            return Data((arrowPrefix + "C").utf8)
        case 125:
            if ctrl { return Data("\u{1b}[1;5B".utf8) }
            if shift { return Data("\u{1b}[1;2B".utf8) }
            return Data((arrowPrefix + "B").utf8)
        case 126:
            if ctrl { return Data("\u{1b}[1;5A".utf8) }
            if shift { return Data("\u{1b}[1;2A".utf8) }
            return Data((arrowPrefix + "A").utf8)

        case 115: return Data("\u{1b}[H".utf8)
        case 119: return Data("\u{1b}[F".utf8)
        case 116: return Data("\u{1b}[5~".utf8)
        case 121: return Data("\u{1b}[6~".utf8)
        case 114: return Data("\u{1b}[2~".utf8)

        case 122: return Data("\u{1b}OP".utf8)
        case 120: return Data("\u{1b}OQ".utf8)
        case 99:  return Data("\u{1b}OR".utf8)
        case 118: return Data("\u{1b}OS".utf8)
        case 96:  return Data("\u{1b}[15~".utf8)
        case 97:  return Data("\u{1b}[17~".utf8)
        case 98:  return Data("\u{1b}[18~".utf8)
        case 100: return Data("\u{1b}[19~".utf8)
        case 101: return Data("\u{1b}[20~".utf8)
        case 109: return Data("\u{1b}[21~".utf8)
        case 103: return Data("\u{1b}[23~".utf8)
        case 111: return Data("\u{1b}[24~".utf8)

        default:
            if ctrl, let chars = event.charactersIgnoringModifiers?.lowercased(),
               let scalar = chars.unicodeScalars.first,
               scalar.value >= UInt32(Character("a").asciiValue!),
               scalar.value <= UInt32(Character("z").asciiValue!) {
                return Data([UInt8(scalar.value - UInt32(Character("a").asciiValue!) + 1)])
            }
            if alt, let chars = event.charactersIgnoringModifiers {
                return Data(("\u{1b}" + chars).utf8)
            }
            guard let characters = event.characters else { return nil }
            return Data(characters.utf8)
        }
    }
}
