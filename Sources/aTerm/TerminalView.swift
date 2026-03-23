import AppKit
import SwiftUI

struct TerminalView: NSViewRepresentable {
    let text: String
    let appearance: TerminalAppearance
    let theme: TerminalTheme
    let searchQuery: String
    let isRegexSearchEnabled: Bool
    let searchMatches: [ScrollbackSearchMatch]
    let currentSearchIndex: Int
    let onInput: (Data) -> Void
    let onResize: (UInt16, UInt16) -> Void
    let onBecomeActive: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize, onBecomeActive: onBecomeActive)
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        let view = TerminalContainerView()
        view.configure(with: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        nsView.applyAppearance(appearance, theme: theme)
        nsView.updateText(
            text,
            searchQuery: searchQuery,
            isRegexSearchEnabled: isRegexSearchEnabled,
            searchMatches: searchMatches,
            currentSearchIndex: currentSearchIndex
        )
        nsView.recalculateGrid()
    }

    final class Coordinator: NSObject, TerminalInputHandling {
        private let onInput: (Data) -> Void
        private let onResize: (UInt16, UInt16) -> Void
        private let onBecomeActive: () -> Void

        init(onInput: @escaping (Data) -> Void, onResize: @escaping (UInt16, UInt16) -> Void, onBecomeActive: @escaping () -> Void) {
            self.onInput = onInput
            self.onResize = onResize
            self.onBecomeActive = onBecomeActive
        }

        func send(bytes: Data) {
            onInput(bytes)
        }

        func resize(columns: UInt16, rows: UInt16) {
            onResize(columns, rows)
        }

        func didBecomeActive() {
            onBecomeActive()
        }
    }
}

@MainActor
protocol TerminalInputHandling: AnyObject {
    func send(bytes: Data)
    func resize(columns: UInt16, rows: UInt16)
    func didBecomeActive()
}

@MainActor
final class TerminalContainerView: NSView {
    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let textView = TerminalTextView()
    private weak var handler: TerminalInputHandling?
    private var appliedAppearance = TerminalAppearance.default
    private var appliedTheme = BuiltinThemes.all.last!

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

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = .clear
        textView.insertionPointColor = .white
        textView.textColor = .white
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.drawsBackground = false
        textView.inputHandler = self

        scrollView.documentView = textView
        effectView.addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        scrollView.frame = bounds
        recalculateGrid()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(textView)
    }

    func configure(with handler: TerminalInputHandling) {
        self.handler = handler
    }

    func applyAppearance(_ appearance: TerminalAppearance, theme: TerminalTheme) {
        appliedAppearance = appearance
        appliedTheme = theme

        wantsLayer = true
        layer?.backgroundColor = theme.palette.background.withAlpha(appearance.opacity).nsColor.cgColor

        effectView.material = appearance.blur > 0.55 ? .hudWindow : .underWindowBackground
        effectView.alphaValue = appearance.blur
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = theme.palette.background.withAlpha(appearance.opacity).nsColor.cgColor

        let font = NSFont(name: appearance.fontName, size: appearance.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: appearance.fontSize, weight: .regular)
        textView.font = font
        textView.textColor = theme.palette.foreground.nsColor
        textView.insertionPointColor = theme.palette.cursor.nsColor
        textView.textContainerInset = NSSize(width: appearance.padding.left, height: appearance.padding.top)
        textView.cursorStyle = appearance.cursorStyle
        textView.defaultParagraphStyle = paragraphStyle(for: appearance, font: font)
        updateText(
            textView.string,
            searchQuery: "",
            isRegexSearchEnabled: false,
            searchMatches: [],
            currentSearchIndex: 0
        )
    }

    func updateText(
        _ text: String,
        searchQuery: String,
        isRegexSearchEnabled: Bool,
        searchMatches: [ScrollbackSearchMatch],
        currentSearchIndex: Int
    ) {
        let attributes = textAttributes()
        let attributedText = NSMutableAttributedString(string: text, attributes: attributes)
        applySearchHighlights(
            to: attributedText,
            query: searchQuery,
            isRegexSearchEnabled: isRegexSearchEnabled,
            searchMatches: searchMatches,
            currentSearchIndex: currentSearchIndex
        )
        guard textView.attributedString() != attributedText else { return }
        let shouldFollowTail = isScrolledNearBottom()
        textView.textStorage?.setAttributedString(attributedText)
        if let selectedMatch = selectedSearchMatch(from: searchMatches, currentSearchIndex: currentSearchIndex) {
            textView.scrollRangeToVisible(NSRange(location: selectedMatch.location, length: max(selectedMatch.length, 1)))
        } else if shouldFollowTail {
            textView.scrollToEndOfDocument(nil)
        }
    }

    func recalculateGrid() {
        guard let font = textView.font else { return }
        let cell = "W" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: appliedAppearance.letterSpacing]
        let charSize = cell.size(withAttributes: attributes)
        let lineHeight = max(font.boundingRectForFont.height * appliedAppearance.lineHeight, 1)
        let horizontalInset = appliedAppearance.padding.left + appliedAppearance.padding.right
        let verticalInset = appliedAppearance.padding.top + appliedAppearance.padding.bottom
        let columns = max(20, Int((bounds.width - horizontalInset) / max(charSize.width, 1)))
        let rows = max(5, Int((bounds.height - verticalInset) / lineHeight))
        handler?.resize(columns: UInt16(columns), rows: UInt16(rows))
    }

    private func textAttributes() -> [NSAttributedString.Key: Any] {
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: appliedAppearance.fontSize, weight: .regular)
        return [
            .font: font,
            .foregroundColor: appliedTheme.palette.foreground.nsColor,
            .paragraphStyle: paragraphStyle(for: appliedAppearance, font: font),
            .kern: appliedAppearance.letterSpacing,
        ]
    }

    private func applySearchHighlights(
        to attributedText: NSMutableAttributedString,
        query: String,
        isRegexSearchEnabled: Bool,
        searchMatches: [ScrollbackSearchMatch],
        currentSearchIndex: Int
    ) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        for (index, match) in searchMatches.enumerated() {
            let range = NSRange(location: match.location, length: match.length)
            let color = index == currentSearchIndex
                ? appliedTheme.palette.cursor.withAlpha(0.4).nsColor
                : appliedTheme.palette.selection.withAlpha(isRegexSearchEnabled ? 0.45 : 0.3).nsColor
            attributedText.addAttribute(.backgroundColor, value: color, range: range)
            if index == currentSearchIndex {
                attributedText.addAttribute(.foregroundColor, value: appliedTheme.palette.background.nsColor, range: range)
            }
        }
    }

    private func isScrolledNearBottom() -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visibleMaxY = scrollView.contentView.bounds.maxY
        let contentMaxY = documentView.frame.maxY
        return contentMaxY - visibleMaxY < 24
    }

    private func selectedSearchMatch(from searchMatches: [ScrollbackSearchMatch], currentSearchIndex: Int) -> ScrollbackSearchMatch? {
        guard searchMatches.indices.contains(currentSearchIndex) else { return nil }
        return searchMatches[currentSearchIndex]
    }

    private func paragraphStyle(for appearance: TerminalAppearance, font: NSFont) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = font.ascender - font.descender + font.leading
        paragraph.maximumLineHeight = paragraph.minimumLineHeight * appearance.lineHeight
        return paragraph
    }
}

@MainActor
extension TerminalContainerView: TerminalInputHandling {
    func send(bytes: Data) {
        handler?.send(bytes: bytes)
    }

    func resize(columns: UInt16, rows: UInt16) {
        handler?.resize(columns: columns, rows: rows)
    }

    func didBecomeActive() {
        handler?.didBecomeActive()
    }
}

@MainActor
final class TerminalTextView: NSTextView {
    weak var inputHandler: TerminalInputHandling?
    var cursorStyle: CursorStyle = .bar

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if let data = TerminalKeyMapper.data(for: event) {
            inputHandler?.send(bytes: data)
            return
        }

        super.keyDown(with: event)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard flag else { return }

        switch cursorStyle {
        case .bar:
            let bar = NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
            color.setFill()
            bar.fill()
        case .underline:
            let underline = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2)
            color.setFill()
            underline.fill()
        case .block:
            let block = NSRect(x: rect.minX, y: rect.minY, width: max(rect.width, 8), height: rect.height)
            color.withAlphaComponent(0.45).setFill()
            block.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        inputHandler?.didBecomeActive()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        inputHandler?.didBecomeActive()
        return super.becomeFirstResponder()
    }
}

enum TerminalKeyMapper {
    static func data(for event: NSEvent) -> Data? {
        switch Int(event.keyCode) {
        case 36:
            return Data("\r".utf8)
        case 48:
            return Data("\t".utf8)
        case 51:
            return Data([0x7f])
        case 53:
            return Data([0x1b])
        case 123:
            return Data("\u{1b}[D".utf8)
        case 124:
            return Data("\u{1b}[C".utf8)
        case 125:
            return Data("\u{1b}[B".utf8)
        case 126:
            return Data("\u{1b}[A".utf8)
        default:
            guard let characters = event.characters else { return nil }
            return Data(characters.utf8)
        }
    }
}
