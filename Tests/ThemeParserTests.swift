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
    
    @Test
    func parsesCompleteITermColors() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Background Color</key>
            <dict>
                <key>Red Component</key><real>0.0</real>
                <key>Green Component</key><real>0.0</real>
                <key>Blue Component</key><real>0.0</real>
            </dict>
            <key>Foreground Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
            <key>Cursor Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>0.0</real>
            </dict>
            <key>Selection Color</key>
            <dict>
                <key>Red Component</key><real>0.2</real>
                <key>Green Component</key><real>0.4</real>
                <key>Blue Component</key><real>0.6</real>
            </dict>
            <key>Ansi 0 Color</key>
            <dict>
                <key>Red Component</key><real>0.0</real>
                <key>Green Component</key><real>0.0</real>
                <key>Blue Component</key><real>0.0</real>
            </dict>
            <key>Ansi 1 Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>0.0</real>
                <key>Blue Component</key><real>0.0</real>
            </dict>
            <key>Ansi 2 Color</key>
            <dict>
                <key>Red Component</key><real>0.0</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>0.0</real>
            </dict>
            <key>Ansi 3 Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>0.0</real>
            </dict>
            <key>Ansi 4 Color</key>
            <dict>
                <key>Red Component</key><real>0.0</real>
                <key>Green Component</key><real>0.0</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
            <key>Ansi 5 Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>0.0</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
            <key>Ansi 6 Color</key>
            <dict>
                <key>Red Component</key><real>0.0</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
            <key>Ansi 7 Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
            <key>Ansi 8 Color</key>
            <dict>
                <key>Red Component</key><real>0.5</real>
                <key>Green Component</key><real>0.5</real>
                <key>Blue Component</key><real>0.5</real>
            </dict>
            <key>Ansi 9 Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>0.5</real>
                <key>Blue Component</key><real>0.5</real>
            </dict>
            <key>Ansi 10 Color</key>
            <dict>
                <key>Red Component</key><real>0.5</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>0.5</real>
            </dict>
            <key>Ansi 11 Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>0.5</real>
            </dict>
            <key>Ansi 12 Color</key>
            <dict>
                <key>Red Component</key><real>0.5</real>
                <key>Green Component</key><real>0.5</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
            <key>Ansi 13 Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>0.5</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
            <key>Ansi 14 Color</key>
            <dict>
                <key>Red Component</key><real>0.5</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
            <key>Ansi 15 Color</key>
            <dict>
                <key>Red Component</key><real>1.0</real>
                <key>Green Component</key><real>1.0</real>
                <key>Blue Component</key><real>1.0</real>
            </dict>
        </dict>
        </plist>
        """
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CompleteTheme.itermcolors")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let theme = try ThemeParser.parseTheme(at: url)
        
        #expect(theme.palette.background.hexString == "#000000")
        #expect(theme.palette.foreground.hexString == "#FFFFFF")
        #expect(theme.palette.cursor.hexString == "#FFFF00")
        #expect(theme.palette.selection.hexString == "#336699")
        #expect(theme.palette.ansi.count == 16)
        #expect(theme.palette.ansi[0].hexString == "#000000")
        #expect(theme.palette.ansi[1].hexString == "#FF0000")
        #expect(theme.palette.ansi[2].hexString == "#00FF00")
        #expect(theme.palette.ansi[7].hexString == "#FFFFFF")
        #expect(theme.palette.ansi[8].hexString == "#808080")
        #expect(theme.palette.ansi[15].hexString == "#FFFFFF")
    }
    
    @Test
    func parsesPartialThemeWithDefaults() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Background Color</key>
            <dict>
                <key>Red Component</key><real>0.1</real>
                <key>Green Component</key><real>0.1</real>
                <key>Blue Component</key><real>0.1</real>
            </dict>
        </dict>
        </plist>
        """
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PartialTheme.itermcolors")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let theme = try ThemeParser.parseTheme(at: url)
        
        #expect(theme.palette.background.hexString == "#1A1A1A")
        // Should have defaults for missing colors
        #expect(theme.palette.ansi.count == 16)
    }
    
    @Test
    func throwsOnInvalidXML() {
        let xml = "not valid xml"
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InvalidTheme.itermcolors")
        try? xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        
        #expect(throws: (any Error).self) {
            _ = try ThemeParser.parseTheme(at: url)
        }
    }
    
    @Test
    func throwsOnMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NonExistent.itermcolors")
        
        #expect(throws: (any Error).self) {
            _ = try ThemeParser.parseTheme(at: url)
        }
    }
}

// MARK: - ThemeColor Tests

struct ThemeColorTests {
    @Test
    func createsFromHex() {
        let color = ThemeColor(hex: "#FF5733")
        
        #expect(color.red == 1.0)
        #expect(color.green == 0.3411764705882353)
        #expect(color.blue == 0.2)
    }
    
    @Test
    func createsFromHexWithoutHash() {
        let color = ThemeColor(hex: "FF5733")
        
        #expect(color.red == 1.0)
        #expect(color.green == 0.3411764705882353)
        #expect(color.blue == 0.2)
    }
    
    @Test
    func createsWithAlpha() {
        let color = ThemeColor(hex: "#FF5733", alpha: 0.5)
        
        #expect(color.alpha == 0.5)
    }
    
    @Test
    func generatesHexString() {
        let color = ThemeColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        
        #expect(color.hexString == "#FF0000")
    }
    
    @Test
    func createsFromRGB() {
        let color = ThemeColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1.0)
        
        #expect(color.red == 0.5)
        #expect(color.green == 0.25)
        #expect(color.blue == 0.75)
    }
}

// MARK: - Builtin Themes Tests

struct BuiltinThemesTests {
    @Test
    func hasExpectedThemes() {
        let themes = BuiltinThemes.all
        
        // Should have at least the themes mentioned in spec
        let themeNames = themes.map(\.name)
        #expect(themeNames.contains("Dracula"))
        #expect(themeNames.contains("Nord"))
        #expect(themeNames.contains("Solarized Dark"))
        #expect(themeNames.contains("Solarized Light"))
        #expect(themeNames.contains("One Dark"))
        #expect(themeNames.contains("Monokai"))
        #expect(themeNames.contains("Gruvbox Dark"))
        #expect(themeNames.contains("Tokyo Night"))
        #expect(themeNames.contains("Catppuccin Mocha"))
        #expect(themeNames.contains("Material Dark"))
    }
    
    @Test
    func allThemesHaveValidPalettes() {
        let themes = BuiltinThemes.all
        
        for theme in themes {
            #expect(theme.palette.ansi.count == 16, "Theme \(theme.name) should have 16 ANSI colors")
        }
    }
    
    @Test
    func allThemesAreBuiltin() {
        for theme in BuiltinThemes.all {
            #expect(theme.isBuiltin == true)
        }
    }
    
    @Test
    func themesHaveUniqueIDs() {
        let ids = BuiltinThemes.all.map(\.id)
        let uniqueIDs = Set(ids)
        
        #expect(ids.count == uniqueIDs.count)
    }
}
