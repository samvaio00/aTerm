import Foundation

struct TerminalDecodedChunk {
    var displayText = ""
    var title: String?
    var workingDirectory: URL?
}

final class TerminalStreamDecoder {
    private var pending = ""

    func reset() {
        pending = ""
    }

    func consume(_ data: Data) -> TerminalDecodedChunk {
        var chunk = TerminalDecodedChunk()
        let text = pending + String(decoding: data, as: UTF8.self)
        pending = ""

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            guard character == "\u{1B}" else {
                chunk.displayText.append(character)
                index = text.index(after: index)
                continue
            }

            let sequenceStart = index
            let nextIndex = text.index(after: index)
            guard nextIndex < text.endIndex else {
                pending = String(text[sequenceStart...])
                break
            }

            let controlType = text[nextIndex]
            if controlType == "[" {
                if let endIndex = findCSIEnd(in: text, from: nextIndex) {
                    index = text.index(after: endIndex)
                } else {
                    pending = String(text[sequenceStart...])
                    break
                }
                continue
            }

            if controlType == "]" {
                if let parsedOSC = parseOSC(in: text, from: nextIndex) {
                    applyOSC(parsedOSC.payload, to: &chunk)
                    index = parsedOSC.nextIndex
                } else {
                    pending = String(text[sequenceStart...])
                    break
                }
                continue
            }

            index = text.index(after: nextIndex)
        }

        return chunk
    }

    private func findCSIEnd(in text: String, from bracketIndex: String.Index) -> String.Index? {
        var index = text.index(after: bracketIndex)
        while index < text.endIndex {
            let scalar = text[index].unicodeScalars.first?.value ?? 0
            if scalar >= 0x40 && scalar <= 0x7E {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func parseOSC(in text: String, from bracketIndex: String.Index) -> (payload: String, nextIndex: String.Index)? {
        var cursor = text.index(after: bracketIndex)
        var payload = ""

        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "\u{07}" {
                return (payload, text.index(after: cursor))
            }
            if character == "\u{1B}" {
                let next = text.index(after: cursor)
                guard next < text.endIndex else { return nil }
                if text[next] == "\\" {
                    return (payload, text.index(after: next))
                }
            }
            payload.append(character)
            cursor = text.index(after: cursor)
        }

        return nil
    }

    private func applyOSC(_ payload: String, to chunk: inout TerminalDecodedChunk) {
        let parts = payload.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard let opcode = parts.first else { return }
        let value = parts.count > 1 ? String(parts[1]) : ""

        switch opcode {
        case "0", "2":
            chunk.title = value
        case "7":
            chunk.workingDirectory = decodeWorkingDirectory(from: value)
        default:
            break
        }
    }

    private func decodeWorkingDirectory(from value: String) -> URL? {
        guard value.hasPrefix("file://") else { return nil }
        let withoutScheme = String(value.dropFirst("file://".count))
        guard let slashIndex = withoutScheme.firstIndex(of: "/") else { return nil }
        let rawPath = String(withoutScheme[slashIndex...]).replacingOccurrences(of: "%20", with: " ")
        return URL(fileURLWithPath: rawPath)
    }
}
