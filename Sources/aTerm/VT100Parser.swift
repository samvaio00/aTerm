import Foundation

/// Full VT100/xterm escape sequence parser. Feeds characters into a TerminalBuffer.
@MainActor
final class VT100Parser {
    private let buffer: TerminalBuffer

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
            if code == 0x9C || char == "\\" { state = .ground }

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
                // Report cursor position (not sent back to PTY in this implementation)
            }
        case "s": buffer.saveCursor()           // SCP
        case "u": buffer.restoreCursor()        // RCP
        case "t": break                          // window manipulation (ignore)
        case "c": break                          // DA (ignore)
        case "q": break                          // DECSCUSR cursor style (ignore for now)
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
        case "133": // Semantic prompt markers
            handleOSC133(data)
        default: break
        }
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
