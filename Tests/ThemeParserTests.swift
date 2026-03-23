import Foundation
import Testing
@testable import aTerm

struct ThemeParserTests {
    @Test
    func parsesITermThemeFile() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Background Color</key>
            <dict>
                <key>Red Component</key><real>0.1</real>
                <key>Green Component</key><real>0.2</real>
                <key>Blue Component</key><real>0.3</real>
            </dict>
            <key>Foreground Color</key>
            <dict>
                <key>Red Component</key><real>0.9</real>
                <key>Green Component</key><real>0.8</real>
                <key>Blue Component</key><real>0.7</real>
            </dict>
            <key>Cursor Color</key>
            <dict>
                <key>Red Component</key><real>0.4</real>
                <key>Green Component</key><real>0.5</real>
                <key>Blue Component</key><real>0.6</real>
            </dict>
        </dict>
        </plist>
        """

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AppendixTheme.itermcolors")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let theme = try ThemeParser.parseTheme(at: url)

        #expect(theme.name == "AppendixTheme")
        #expect(theme.palette.background.hexString == "#1A334D")
        #expect(theme.palette.foreground.hexString == "#E6CCB3")
        #expect(theme.palette.cursor.hexString == "#668099")
    }
}
