import Foundation

enum ANSIParser {
    static func displayString(for data: Data) -> String {
        let string = String(decoding: data, as: UTF8.self)
        return stripCSISequences(from: string)
    }

    private static func stripCSISequences(from string: String) -> String {
        var result = ""
        var isEscaping = false
        var isCSI = false

        for character in string {
            if isEscaping {
                if character == "[" {
                    isCSI = true
                    continue
                }

                isEscaping = false
                continue
            }

            if isCSI {
                if character.isASCII, let scalar = character.unicodeScalars.first, scalar.value >= 0x40, scalar.value <= 0x7E {
                    isEscaping = false
                    isCSI = false
                }
                continue
            }

            if character == "\u{1B}" {
                isEscaping = true
                continue
            }

            result.append(character)
        }

        return result
    }
}
