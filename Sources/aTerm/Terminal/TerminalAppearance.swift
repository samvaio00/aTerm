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
    case queryParam
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bearer: return "Bearer Token"
        case .xApiKey: return "x-api-key"
        case .oauthToken: return "OAuth Sign-In"
        case .queryParam: return "Query Parameter"
        case .none: return "None"
        }
    }
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

struct OAuthConfig: Codable, Hashable {
    var clientID: String = ""
    var authURL: String
    var tokenURL: String
    var scopes: [String]
    /// Custom redirect URI scheme (defaults to "aterm" → aterm://oauth/callback)
    var redirectScheme: String = "aterm"
    /// If true, the flow doesn't require a client ID (e.g., OpenRouter)
    var clientIDRequired: Bool = true
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
    var oauthConfig: OAuthConfig?
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
    var cursorBlink: Bool = false
    var scrollbackSize: Int
    var shellPath: String?
    var zshrcPath: String?
    var customEnvironment: [String: String]
    var defaultWorkingDirectoryPath: String?
    var aiProvider: String?
    var aiModel: String?
    var classifierModel: String?
    var chatProvider: String?
    var chatModel: String?

    static let `default` = TerminalAppearance(
        themeID: "modern",
        fontName: "SF Mono",
        nonASCIIFontName: "SF Mono",
        fontSize: 18,
        lineHeight: 1.25,
        letterSpacing: 0.5,
        opacity: 1.0,
        blur: 0,
        padding: TerminalPadding(),
        cursorStyle: .block,
        cursorBlink: true,
        scrollbackSize: 10_000,
        shellPath: nil,
        zshrcPath: nil,
        customEnvironment: [:],
        defaultWorkingDirectoryPath: nil,
        aiProvider: nil,
        aiModel: nil,
        classifierModel: nil,
        chatProvider: nil,
        chatModel: nil
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
