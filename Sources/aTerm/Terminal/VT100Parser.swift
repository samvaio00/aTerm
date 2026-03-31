import AppKit
import Foundation

/// Full VT100/xterm escape sequence parser. Feeds characters into a TerminalBuffer.
@MainActor
final class VT100Parser {
    private let buffer: TerminalBuffer
    /// Callback to send data back to the PTY (for DSR/CPR responses)
    var sendToPTY: ((Data) -> Void)?

    private enum State {
        case ground
        case escape
        case escapeIntermediate
        case csi
        case csiParam
        case csiIntermediate
        case osc
        case oscString
        case dcs
        case charset
    }

    private var state: State = .ground
    private var params: [Int] = []
    private var currentParam: Int = 0
    private var hasParam = false
    private var intermediateChars: [Character] = []
    private var oscPayload = ""
    private var dcsPayload = ""
    private var pendingBytes: [UInt8] = []
    private var utf8Decoder = UTF8StreamDecoder()

    init(buffer: TerminalBuffer) {
        self.buffer = buffer
    }

    func feed(_ data: Data) {
        for byte in data {
            if let char = utf8Decoder.decode(byte) {
                processCharacter(char)
            }
        }
    }

    func reset() {
        state = .ground
        params = []
        currentParam = 0
        hasParam = false
        intermediateChars = []
        oscPayload = ""
        pendingBytes = []
        utf8Decoder = UTF8StreamDecoder()
    }

    // MARK: - Character Processing

    private func processCharacter(_ char: Character) {
        guard let scalar = char.unicodeScalars.first else { return }
        let code = scalar.value

        // Handle C0 control characters in any state
        if code < 0x20 {
            switch code {
            case 0x00: return // NUL - ignore
            case 0x07: // BEL
                if state == .osc || state == .oscString {
                    handleOSC(oscPayload)
                    state = .ground
                    return
                }
                buffer.bellFired = true
                return
            case 0x08: // BS
                buffer.backspace()
                return
            case 0x09: // HT (tab)
                buffer.tab()
                return
            case 0x0A, 0x0B, 0x0C: // LF, VT, FF
                buffer.lineFeed()
                return
            case 0x0D: // CR
                buffer.carriageReturn()
                return
            case 0x0E: return // SO - shift out (ignore)
            case 0x0F: return // SI - shift in (ignore)
            case 0x1B: // ESC
                state = .escape
                intermediateChars = []
                return
            case 0x18, 0x1A: // CAN, SUB - abort sequence
                state = .ground
                return
            default: return
            }
        }

        switch state {
        case .ground:
            handleGround(char)

        case .escape:
            handleEscape(char, code: code)

        case .escapeIntermediate:
            handleEscapeIntermediate(char, code: code)

        case .csi, .csiParam:
            handleCSIParam(char, code: code)

        case .csiIntermediate:
            handleCSIIntermediate(char, code: code)

        case .osc, .oscString:
            handleOSCString(char, code: code)

        case .dcs:
            if code == 0x9C || (char == "\\" && dcsPayload.hasSuffix("\u{1B}")) {
                // ST received — process DCS payload
                if dcsPayload.hasSuffix("\u{1B}") { dcsPayload.removeLast() }
                handleDCS(dcsPayload)
                dcsPayload = ""
                state = .ground
            } else {
                dcsPayload.append(char)
            }

        case .charset:
            // G0 charset designation: '0' = DEC Special Graphics, 'B' = ASCII
            if let scalar = char.unicodeScalars.first {
                switch scalar.value {
                case 0x30: // '0' → DEC line drawing
                    buffer.useLineDrawingCharset = true
                case 0x42: // 'B' → ASCII (default)
                    buffer.useLineDrawingCharset = false
                default: break
                }
            }
            state = .ground
        }
    }

    // MARK: - State Handlers

    private func handleGround(_ char: Character) {
        buffer.putChar(char)
    }

    private func handleEscape(_ char: Character, code: UInt32) {
        switch code {
        case 0x5B: // [  → CSI
            state = .csiParam
            params = []
            currentParam = 0
            hasParam = false
            intermediateChars = []
        case 0x5D: // ]  → OSC
            state = .osc
            oscPayload = ""
        case 0x28, 0x29, 0x2A, 0x2B: // ( ) * + → charset
            state = .charset
        case 0x37: // 7 → DECSC (save cursor)
            buffer.saveCursor()
            state = .ground
        case 0x38: // 8 → DECRC (restore cursor)
            buffer.restoreCursor()
            state = .ground
        case 0x44: // D → IND (index, move cursor down / scroll)
            buffer.lineFeed()
            state = .ground
        case 0x45: // E → NEL (next line)
            buffer.carriageReturn()
            buffer.lineFeed()
            state = .ground
        case 0x4D: // M → RI (reverse index)
            buffer.reverseLineFeed()
            state = .ground
        case 0x50: // P → DCS
            dcsPayload = ""
            state = .dcs
        case 0x63: // c → RIS (full reset)
            buffer.reset()
            state = .ground
        case 0x20...0x2F: // intermediate
            intermediateChars.append(char)
            state = .escapeIntermediate
        default:
            state = .ground
        }
    }

    private func handleEscapeIntermediate(_ char: Character, code: UInt32) {
        if code >= 0x20, code <= 0x2F {
            intermediateChars.append(char)
        } else {
            state = .ground
        }
    }

    private func handleCSIParam(_ char: Character, code: UInt32) {
        switch code {
        case 0x30...0x39: // 0-9
            hasParam = true
            currentParam = currentParam * 10 + Int(code - 0x30)
        case 0x3B: // ;
            params.append(hasParam ? currentParam : 0)
            currentParam = 0
            hasParam = false
        case 0x3A: // : (subparam separator, treat like ;)
            params.append(hasParam ? currentParam : 0)
            currentParam = 0
            hasParam = false
        case 0x3C...0x3F: // < = > ? (private mode prefix)
            intermediateChars.append(char)
        case 0x20...0x2F: // intermediate
            if hasParam { params.append(currentParam) }
            intermediateChars.append(char)
            state = .csiIntermediate
        case 0x40...0x7E: // final byte
            if hasParam { params.append(currentParam) }
            executeCSI(char, params: params)
            state = .ground
        default:
            state = .ground
        }
    }

    private func handleCSIIntermediate(_ char: Character, code: UInt32) {
        if code >= 0x20, code <= 0x2F {
            intermediateChars.append(char)
        } else if code >= 0x40, code <= 0x7E {
            if hasParam { params.append(currentParam) }
            executeCSI(char, params: params)
            state = .ground
        } else {
            state = .ground
        }
    }

    private func handleOSCString(_ char: Character, code: UInt32) {
        if code == 0x9C { // ST
            handleOSC(oscPayload)
            state = .ground
        } else if char == "\\" && oscPayload.hasSuffix("\u{1B}") {
            oscPayload.removeLast()
            handleOSC(oscPayload)
            state = .ground
        } else {
            oscPayload.append(char)
        }
    }

    // MARK: - CSI Execution

    private func executeCSI(_ final: Character, params: [Int]) {
        let isPrivate = intermediateChars.contains("?")
        let p = params
        let p0 = p.first ?? 0
        let n = max(p0, 1)

        switch final {
        case "A": buffer.moveCursorUp(n)       // CUU
        case "B": buffer.moveCursorDown(n)      // CUD
        case "C": buffer.moveCursorForward(n)   // CUF
        case "D": buffer.moveCursorBackward(n)  // CUB
        case "E": // CNL
            buffer.moveCursorDown(n)
            buffer.carriageReturn()
        case "F": // CPL
            buffer.moveCursorUp(n)
            buffer.carriageReturn()
        case "G": // CHA - cursor horizontal absolute
            buffer.moveCursorTo(x: max(p0, 1) - 1, y: buffer.cursorY)
        case "H", "f": // CUP / HVP
            let row = max(p.count > 0 ? p[0] : 1, 1) - 1
            let col = max(p.count > 1 ? p[1] : 1, 1) - 1
            buffer.moveCursorTo(x: col, y: row)
        case "J": buffer.eraseInDisplay(p0)     // ED
        case "K": buffer.eraseLine(p0)          // EL
        case "L": buffer.insertLines(n)         // IL
        case "M": buffer.deleteLines(n)         // DL
        case "P": buffer.deleteChars(n)         // DCH
        case "S": buffer.scrollUp(n)            // SU
        case "T": buffer.scrollDown(n)          // SD
        case "X": buffer.eraseChars(n)          // ECH
        case "@": buffer.insertChars(n)         // ICH
        case "d": // VPA - vertical position absolute
            buffer.moveCursorTo(x: buffer.cursorX, y: max(p0, 1) - 1)
        case "m": handleSGR(p)                  // SGR
        case "r": // DECSTBM
            let top = max(p.count > 0 ? p[0] : 1, 1) - 1
            let bottom = (p.count > 1 ? p[1] : buffer.rows) - 1
            buffer.setScrollRegion(top: top, bottom: bottom)
        case "h": // SM / DECSET
            if isPrivate { handleDECSET(p, enable: true) }
        case "l": // RM / DECRST
            if isPrivate { handleDECSET(p, enable: false) }
        case "n": // DSR - device status report
            if p0 == 6 {
                // CPR: report cursor position as ESC[row;colR (1-based)
                let row = buffer.cursorY + 1
                let col = buffer.cursorX + 1
                let response = "\u{1B}[\(row);\(col)R"
                sendToPTY?(Data(response.utf8))
            } else if p0 == 5 {
                // Status report: terminal OK
                sendToPTY?(Data("\u{1B}[0n".utf8))
            }
        case "s": buffer.saveCursor()           // SCP
        case "u": buffer.restoreCursor()        // RCP
        case "t": break                          // window manipulation (ignore)
        case "c": // DA - device attributes
            if intermediateChars.contains(">") {
                // Secondary DA (CSI > c): report as VT220-like terminal
                // Pp=1 (VT220), Pv=10 (firmware version), Pc=0 (ROM cartridge)
                sendToPTY?(Data("\u{1B}[>1;10;0c".utf8))
            } else if intermediateChars.contains("=") {
                // Tertiary DA (CSI = c): ignore
                break
            } else {
                // Primary DA (CSI c or CSI 0 c): report as VT220 with ANSI color, etc.
                // 62 = VT220, 1 = 132 cols, 4 = Sixel, 6 = selective erase, 22 = ANSI color
                sendToPTY?(Data("\u{1B}[?62;1;2;4;6;22c".utf8))
            }
        case "q": // DECSCUSR - cursor style
            let style = p0
            switch style {
            case 0, 1: buffer.cursorShape = .block       // blinking block (or default)
            case 2:    buffer.cursorShape = .block        // steady block
            case 3:    buffer.cursorShape = .underline    // blinking underline
            case 4:    buffer.cursorShape = .underline    // steady underline
            case 5:    buffer.cursorShape = .bar          // blinking bar
            case 6:    buffer.cursorShape = .bar          // steady bar
            default: break
            }
        default: break
        }
    }

    // MARK: - SGR (Select Graphic Rendition)

    private func handleSGR(_ params: [Int]) {
        let p = params.isEmpty ? [0] : params
        var i = 0
        while i < p.count {
            let code = p[i]
            switch code {
            case 0:
                buffer.currentAttributes = .default
            case 1:
                buffer.currentAttributes.bold = true
            case 2:
                buffer.currentAttributes.dim = true
            case 3:
                buffer.currentAttributes.italic = true
            case 4:
                buffer.currentAttributes.underline = true
            case 5, 6:
                buffer.currentAttributes.blink = true
            case 7:
                buffer.currentAttributes.inverse = true
            case 8:
                buffer.currentAttributes.hidden = true
            case 9:
                buffer.currentAttributes.strikethrough = true
            case 21:
                buffer.currentAttributes.underline = true // double underline → underline
            case 22:
                buffer.currentAttributes.bold = false
                buffer.currentAttributes.dim = false
            case 23:
                buffer.currentAttributes.italic = false
            case 24:
                buffer.currentAttributes.underline = false
            case 25:
                buffer.currentAttributes.blink = false
            case 27:
                buffer.currentAttributes.inverse = false
            case 28:
                buffer.currentAttributes.hidden = false
            case 29:
                buffer.currentAttributes.strikethrough = false

            // Foreground colors
            case 30...37:
                buffer.currentAttributes.fg = .indexed(UInt8(code - 30))
            case 38:
                if let color = parseExtendedColor(p, startIndex: &i) {
                    buffer.currentAttributes.fg = color
                }
            case 39:
                buffer.currentAttributes.fg = .default
            case 90...97:
                buffer.currentAttributes.fg = .indexed(UInt8(code - 90 + 8))

            // Background colors
            case 40...47:
                buffer.currentAttributes.bg = .indexed(UInt8(code - 40))
            case 48:
                if let color = parseExtendedColor(p, startIndex: &i) {
                    buffer.currentAttributes.bg = color
                }
            case 49:
                buffer.currentAttributes.bg = .default
            case 100...107:
                buffer.currentAttributes.bg = .indexed(UInt8(code - 100 + 8))

            default: break
            }
            i += 1
        }
    }

    private func parseExtendedColor(_ params: [Int], startIndex i: inout Int) -> TerminalColorSpec? {
        guard i + 1 < params.count else { return nil }
        let mode = params[i + 1]
        switch mode {
        case 5: // 256-color: 38;5;N or 48;5;N
            guard i + 2 < params.count else { i += 1; return nil }
            let colorIndex = UInt8(clamping: params[i + 2])
            i += 2
            return .indexed(colorIndex)
        case 2: // 24-bit RGB: 38;2;R;G;B or 48;2;R;G;B
            guard i + 4 < params.count else { i += 1; return nil }
            let r = UInt8(clamping: params[i + 2])
            let g = UInt8(clamping: params[i + 3])
            let b = UInt8(clamping: params[i + 4])
            i += 4
            return .rgb(r, g, b)
        default:
            i += 1
            return nil
        }
    }

    // MARK: - DEC Private Mode Set/Reset

    private func handleDECSET(_ params: [Int], enable: Bool) {
        for mode in params {
            switch mode {
            case 1: // DECCKM - application cursor keys
                buffer.applicationCursorKeys = enable
            case 7: // DECAWM - auto-wrap
                buffer.autoWrap = enable
            case 12: // cursor blink (ignore)
                break
            case 25: // DECTCEM - cursor visible
                buffer.cursorVisible = enable
            case 47: // alternate screen (no save/restore cursor)
                if enable { buffer.switchToAlternateScreen() }
                else { buffer.switchToMainScreen() }
            case 1000: // X11 mouse click tracking
                buffer.mouseMode = enable ? .click : .none
            case 1002: // button-event tracking
                buffer.mouseMode = enable ? .buttonMotion : .none
            case 1003: // any-event tracking
                buffer.mouseMode = enable ? .anyMotion : .none
            case 1006: // SGR extended mouse mode
                if enable { buffer.mouseMode = .sgrExtended }
                else if buffer.mouseMode == .sgrExtended { buffer.mouseMode = .none }
            case 1015: // urxvt mouse mode (treat as SGR)
                if enable { buffer.mouseMode = .sgrExtended }
                else if buffer.mouseMode == .sgrExtended { buffer.mouseMode = .none }
            case 1004: // Focus event tracking
                buffer.focusEventMode = enable
            case 1049: // alternate screen + save/restore cursor
                if enable {
                    buffer.saveCursor()
                    buffer.switchToAlternateScreen()
                    buffer.eraseInDisplay(2)
                } else {
                    buffer.switchToMainScreen()
                    buffer.restoreCursor()
                }
            case 2004: // bracketed paste
                buffer.bracketedPasteMode = enable
            default: break
            }
        }
    }

    // MARK: - OSC

    private func handleOSC(_ payload: String) {
        // OSC format: "code;data"
        guard let semicolonIndex = payload.firstIndex(of: ";") else {
            // Handle numeric-only OSC or no semicolon
            if state == .osc {
                oscPayload = payload
                state = .oscString
            }
            return
        }

        let codeStr = payload[payload.startIndex..<semicolonIndex]
        let data = String(payload[payload.index(after: semicolonIndex)...])

        switch codeStr {
        case "0": // Set icon name and window title
            buffer.title = data
        case "1": // Set icon name
            break
        case "2": // Set window title
            buffer.title = data
        case "7": // Set working directory (file:// URL)
            if let url = URL(string: data) {
                buffer.workingDirectory = url
            } else if data.hasPrefix("file://") {
                let path = String(data.dropFirst(7))
                if let hostEnd = path.firstIndex(of: "/") {
                    buffer.workingDirectory = URL(fileURLWithPath: String(path[hostEnd...]))
                }
            }
        case "8": // Hyperlinks (OSC 8 ; params ; uri ST)
            handleOSC8(data)
        case "52": // Clipboard (OSC 52 ; selection ; base64-data ST)
            handleOSC52(data)
        case "133": // Semantic prompt markers
            handleOSC133(data)
        case "1337": // iTerm2 inline image protocol
            handleOSC1337(data)
        default: break
        }
    }

    private func handleOSC8(_ data: String) {
        // Format: "params;uri" — params is typically "id=..." or empty
        // An empty URI closes the hyperlink
        guard let semicolonIndex = data.firstIndex(of: ";") else { return }
        let uri = String(data[data.index(after: semicolonIndex)...])

        if uri.isEmpty {
            // Close hyperlink
            buffer.currentAttributes.hyperlinkURL = nil
        } else {
            // Open hyperlink — subsequent characters will carry this URL
            buffer.currentAttributes.hyperlinkURL = uri
        }
    }

    private func handleOSC52(_ data: String) {
        // Format: "selection;base64data"
        // selection is typically "c" (clipboard) or "p" (primary)
        guard let semicolonIndex = data.firstIndex(of: ";") else { return }
        let base64 = String(data[data.index(after: semicolonIndex)...])

        if base64 == "?" {
            // Read request — not implemented (would require writing back to PTY)
            return
        }

        // Write to system clipboard
        guard let decoded = Data(base64Encoded: base64),
              let text = String(data: decoded, encoding: .utf8) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - iTerm2 Inline Image Protocol (OSC 1337)

    private func handleOSC1337(_ data: String) {
        // Format: File=[params]:[base64data]
        // params are semicolon-separated key=value pairs:
        //   name=<base64 filename>, size=<bytes>, width=<val>, height=<val>,
        //   preserveAspectRatio=0|1, inline=0|1
        guard data.hasPrefix("File=") else { return }
        let stripped = String(data.dropFirst(5))
        guard let colonIndex = stripped.firstIndex(of: ":") else { return }

        let paramString = String(stripped[stripped.startIndex..<colonIndex])
        let base64Data = String(stripped[stripped.index(after: colonIndex)...])

        // Parse params
        var params: [String: String] = [:]
        for pair in paramString.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0])] = String(kv[1])
            }
        }

        // Only display if inline=1
        guard params["inline"] == "1" else { return }

        // Decode image data
        guard let imageData = Data(base64Encoded: base64Data, options: .ignoreUnknownCharacters),
              let image = NSImage(data: imageData) else { return }

        let (widthCells, heightCells) = computeImageCellSize(image: image, params: params)
        buffer.placeInlineImage(image, widthCells: widthCells, heightCells: heightCells)
    }

    private func computeImageCellSize(image: NSImage, params: [String: String]) -> (width: Int, height: Int) {
        let cols = buffer.columns
        let rows = buffer.rows

        // Parse width/height from params (e.g. "80px", "20", "50%", "auto")
        func parseDimension(_ value: String?, totalCells: Int, pixelsPerCell: Double) -> Int? {
            guard let value, value != "auto" else { return nil }
            if value.hasSuffix("px") {
                let px = Double(value.dropLast(2)) ?? 0
                return max(1, Int((px / pixelsPerCell).rounded(.up)))
            } else if value.hasSuffix("%") {
                let pct = Double(value.dropLast(1)) ?? 100
                return max(1, Int(Double(totalCells) * pct / 100))
            } else if let cells = Int(value) {
                return max(1, cells)
            }
            return nil
        }

        let approxCellWidthPx: Double = 8
        let approxCellHeightPx: Double = 16

        if let w = parseDimension(params["width"], totalCells: cols, pixelsPerCell: approxCellWidthPx),
           let h = parseDimension(params["height"], totalCells: rows, pixelsPerCell: approxCellHeightPx) {
            return (w, h)
        }

        // Auto-size: fit to terminal width, preserve aspect ratio
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return (1, 1) }

        let maxWidthCells = max(1, cols - buffer.cursorX)
        let widthCells: Int
        if let w = parseDimension(params["width"], totalCells: cols, pixelsPerCell: approxCellWidthPx) {
            widthCells = min(w, maxWidthCells)
        } else {
            widthCells = min(Int((imgW / approxCellWidthPx).rounded(.up)), maxWidthCells)
        }

        let heightCells: Int
        if let h = parseDimension(params["height"], totalCells: rows, pixelsPerCell: approxCellHeightPx) {
            heightCells = h
        } else {
            let aspect = imgH / imgW
            let pixelWidth = Double(widthCells) * approxCellWidthPx
            heightCells = max(1, Int((pixelWidth * aspect / approxCellHeightPx).rounded(.up)))
        }

        return (widthCells, heightCells)
    }

    // MARK: - DCS (Sixel Graphics)

    private func handleDCS(_ payload: String) {
        // Sixel data starts with optional parameters then 'q'
        // Format: Pn;Pn;Pnq<sixel data>
        guard let qIndex = payload.firstIndex(of: "q") else { return }
        let sixelData = String(payload[payload.index(after: qIndex)...])
        guard !sixelData.isEmpty else { return }

        if let image = decodeSixel(sixelData) {
            // Size: sixel images are typically pixel-based; fit to terminal
            let approxCellWidthPx: Double = 8
            let approxCellHeightPx: Double = 16
            let imgW = image.size.width
            let imgH = image.size.height
            let widthCells = max(1, min(buffer.columns, Int((imgW / approxCellWidthPx).rounded(.up))))
            let heightCells = max(1, Int((imgH / approxCellHeightPx).rounded(.up)))
            buffer.placeInlineImage(image, widthCells: widthCells, heightCells: heightCells)
        }
    }

    /// Decode sixel graphics data into an NSImage.
    /// Sixel encodes 6 vertical pixels per character. Each character maps to a pattern.
    private func decodeSixel(_ data: String) -> NSImage? {
        // First pass: determine dimensions and handle repeats
        var tempX = 0, tempY = 0, maxX = 0, maxY = 0
        var scanRepeat = false, scanRepeatStr = ""
        var scanColor = false

        for ch in data {
            if scanColor {
                if ch == ";" || ch.isNumber { continue }
                scanColor = false
                // fall through
            }
            if scanRepeat {
                if ch.isNumber { scanRepeatStr.append(ch); continue }
                let n = Int(scanRepeatStr) ?? 1
                scanRepeat = false
                scanRepeatStr = ""
                if let code = ch.asciiValue, code >= 63, code <= 126 { tempX += n }
                maxX = max(maxX, tempX)
                continue
            }
            switch ch {
            case "#": scanColor = true
            case "$": tempX = 0
            case "-": tempX = 0; tempY += 6
            case "!": scanRepeat = true; scanRepeatStr = ""
            default:
                if let code = ch.asciiValue, code >= 63, code <= 126 { tempX += 1 }
            }
            maxX = max(maxX, tempX)
            maxY = max(maxY, tempY + 6)
        }

        guard maxX > 0, maxY > 0 else { return nil }

        let width = maxX, height = maxY
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4, bitsPerPixel: 32
        ) else { return nil }

        let pixels = bitmapRep.bitmapData!
        memset(pixels, 0, width * height * 4)

        // Color palette (256 registers)
        var palette = [(r: UInt8, g: UInt8, b: UInt8)](repeating: (255, 255, 255), count: 256)
        // Initialize first 16 to ANSI colors
        let ansi = TerminalColor.ansi
        for i in 0..<min(16, ansi.count) { palette[i] = (ansi[i].r, ansi[i].g, ansi[i].b) }

        var currentR: UInt8 = 255, currentG: UInt8 = 255, currentB: UInt8 = 255
        var x = 0, y = 0
        var repeatCount = 0
        var parsingRepeat = false, repeatString = ""
        var parsingColor = false, colorString = ""

        for ch in data {
            if parsingColor {
                if ch == ";" || ch.isNumber {
                    colorString.append(ch)
                    continue
                }
                // Parse color string: Pc or Pc;Pu;Px;Py;Pz
                let parts = colorString.split(separator: ";").compactMap { Int($0) }
                if parts.count >= 5 {
                    let pc = parts[0] % 256
                    let pu = parts[1]
                    if pu == 2 {
                        // RGB (0-100 scale)
                        palette[pc] = (UInt8(min(255, parts[2] * 255 / 100)),
                                       UInt8(min(255, parts[3] * 255 / 100)),
                                       UInt8(min(255, parts[4] * 255 / 100)))
                    }
                    currentR = palette[pc].r; currentG = palette[pc].g; currentB = palette[pc].b
                } else if let pc = parts.first {
                    let idx = pc % 256
                    currentR = palette[idx].r; currentG = palette[idx].g; currentB = palette[idx].b
                }
                parsingColor = false
                colorString = ""
                // Fall through to process current char
            }

            if parsingRepeat {
                if ch.isNumber { repeatString.append(ch); continue }
                repeatCount = Int(repeatString) ?? 1
                parsingRepeat = false; repeatString = ""
            }

            switch ch {
            case "#":
                parsingColor = true; colorString = ""; continue
            case "$": x = 0
            case "-": x = 0; y += 6
            case "!":
                parsingRepeat = true; repeatString = ""; repeatCount = 1; continue
            default:
                if let code = ch.asciiValue, code >= 63, code <= 126 {
                    let pattern = Int(code) - 63
                    let count = max(1, repeatCount); repeatCount = 0
                    for _ in 0..<count where x < width {
                        for bit in 0..<6 where pattern & (1 << bit) != 0 {
                            let py = y + bit
                            if py < height {
                                let offset = (py * width + x) * 4
                                pixels[offset] = currentR
                                pixels[offset + 1] = currentG
                                pixels[offset + 2] = currentB
                                pixels[offset + 3] = 255
                            }
                        }
                        x += 1
                    }
                }
            }
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmapRep)
        return image
    }

    private func handleOSC133(_ data: String) {
        let parts = data.split(separator: ";", maxSplits: 2)
        guard let marker = parts.first else { return }

        switch marker {
        case "A": buffer.markPromptStart()
        case "B", "C": break // prompt end / command output start
        case "D":
            let exitCode = parts.count > 1 ? Int(parts[1]) : nil
            buffer.markCommandFinished(exitCode: exitCode, duration: nil)
        case "E":
            let exitCode = parts.count > 1 ? Int(parts[1]) : nil
            let duration = parts.count > 2 ? Double(parts[2]) : nil
            buffer.markCommandFinished(exitCode: exitCode, duration: duration)
        default: break
        }
    }
}

// MARK: - UTF8 Stream Decoder

private struct UTF8StreamDecoder {
    private var buffer: [UInt8] = []
    private var expected: Int = 0

    mutating func decode(_ byte: UInt8) -> Character? {
        if expected == 0 {
            if byte < 0x80 {
                return Character(UnicodeScalar(byte))
            } else if byte & 0xE0 == 0xC0 {
                buffer = [byte]
                expected = 1
                return nil
            } else if byte & 0xF0 == 0xE0 {
                buffer = [byte]
                expected = 2
                return nil
            } else if byte & 0xF8 == 0xF0 {
                buffer = [byte]
                expected = 3
                return nil
            } else {
                return Character("?") // invalid start byte
            }
        } else {
            guard byte & 0xC0 == 0x80 else {
                // Invalid continuation byte — reset and retry
                buffer = []
                expected = 0
                return decode(byte)
            }
            buffer.append(byte)
            expected -= 1
            if expected == 0 {
                let str = String(bytes: buffer, encoding: .utf8)
                buffer = []
                return str?.first ?? Character("?")
            }
            return nil
        }
    }

    mutating func reset() {
        buffer = []
        expected = 0
    }
}
