import Foundation

enum CursorStyle: String, Codable, CaseIterable, Identifiable {
    case block
    case bar
    case underline

    var id: String { rawValue }
}

enum AuthType: String, Codable, CaseIterable, Identifiable {
    case bearer
    case xApiKey
    case oauthToken
    case none

    var id: String { rawValue }
}

enum APIFormat: String, Codable, CaseIterable, Identifiable {
    case openAICompatible
    case anthropic
    case gemini
    case custom

    var id: String { rawValue }
}

struct ModelDefinition: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var contextWindow: Int
    var supportsStreaming: Bool
}

struct ModelProvider: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var endpoint: String
    var authType: AuthType
    var apiFormat: APIFormat
    var models: [ModelDefinition]
    var customHeaders: [String: String]
    var isBuiltin: Bool
}

struct TerminalPadding: Codable, Hashable {
    var top: Double = 12
    var bottom: Double = 12
    var left: Double = 12
    var right: Double = 12
}

struct TerminalAppearance: Codable, Hashable {
    var themeID: String
    var fontName: String
    var nonASCIIFontName: String
    var fontSize: Double
    var lineHeight: Double
    var letterSpacing: Double
    var opacity: Double
    var blur: Double
    var padding: TerminalPadding
    var cursorStyle: CursorStyle
    var scrollbackSize: Int
    var shellPath: String?
    var zshrcPath: String?
    var customEnvironment: [String: String]
    var defaultWorkingDirectoryPath: String?
    var aiProvider: String?
    var aiModel: String?
    var classifierModel: String?

    static let `default` = TerminalAppearance(
        themeID: "custom-default",
        fontName: "SF Mono",
        nonASCIIFontName: "SF Mono",
        fontSize: 13,
        lineHeight: 1.18,
        letterSpacing: 0,
        opacity: 0.96,
        blur: 0.45,
        padding: TerminalPadding(),
        cursorStyle: .bar,
        scrollbackSize: 10_000,
        shellPath: nil,
        zshrcPath: nil,
        customEnvironment: [:],
        defaultWorkingDirectoryPath: nil,
        aiProvider: nil,
        aiModel: nil,
        classifierModel: nil
    )
}

struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var appearance: TerminalAppearance

    init(id: UUID = UUID(), name: String, appearance: TerminalAppearance) {
        self.id = id
        self.name = name
        self.appearance = appearance
    }
}
