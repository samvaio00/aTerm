import Foundation
import AuthenticationServices
import CryptoKit

enum OAuthError: LocalizedError {
    case noOAuthConfig
    case callbackMissingCode
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .noOAuthConfig: return "Provider has no OAuth configuration."
        case .callbackMissingCode: return "OAuth callback did not contain an authorization code."
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .refreshFailed(let msg): return "Token refresh failed: \(msg)"
        case .userCancelled: return "Sign-in was cancelled."
        }
    }
}

/// Stored in Keychain as JSON — holds both tokens and expiry.
struct OAuthTokenData: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var tokenType: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        // Refresh 60s before actual expiry
        return Date() >= expiresAt.addingTimeInterval(-60)
    }
}

@MainActor
final class OAuthManager: NSObject, ObservableObject {
    private let keychainStore = KeychainStore()

    /// In-memory cache of valid access tokens (provider ID → token data)
    private var tokenCache: [String: OAuthTokenData] = [:]

    // MARK: - Public API

    /// Start the OAuth sign-in flow for a provider. Opens the browser.
    func signIn(provider: ModelProvider) async throws {
        guard let oauth = provider.oauthConfig else {
            throw OAuthError.noOAuthConfig
        }

        if oauth.clientIDRequired && oauth.clientID.isEmpty {
            throw OAuthError.tokenExchangeFailed("Client ID is required. Enter it in Settings → Providers.")
        }

        let callbackURI = "\(oauth.redirectScheme)://oauth/callback"
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(from: codeVerifier)

        var components = URLComponents(string: oauth.authURL)!

        if oauth.clientIDRequired {
            // Standard OAuth 2.0 PKCE flow (Google, etc.)
            components.queryItems = [
                URLQueryItem(name: "client_id", value: oauth.clientID),
                URLQueryItem(name: "redirect_uri", value: callbackURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: oauth.scopes.joined(separator: " ")),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]
        } else {
            // Simplified flow (OpenRouter) — just a callback URL
            components.queryItems = [
                URLQueryItem(name: "callback_url", value: callbackURI),
            ]
        }

        let authURL = components.url!
        let callbackScheme = oauth.redirectScheme

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.userCancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: OAuthError.callbackMissingCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        // Extract authorization code from callback URL
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.callbackMissingCode
        }

        // Exchange code for tokens
        let tokenData = try await exchangeCode(
            code: code,
            codeVerifier: oauth.clientIDRequired ? codeVerifier : nil,
            provider: provider
        )

        // Store token data in Keychain (as JSON)
        try persistTokenData(tokenData, for: provider.id)
        tokenCache[provider.id] = tokenData
        Log.debug("oauth", "Sign-in complete for \(provider.name)")
    }

    /// Sign out — clear tokens
    func signOut(providerID: String) throws {
        try keychainStore.deleteSecret(account: oauthAccount(providerID))
        tokenCache.removeValue(forKey: providerID)
        Log.debug("oauth", "Signed out of \(providerID)")
    }

    /// Get a valid access token, refreshing if needed
    func validAccessToken(for provider: ModelProvider) async throws -> String {
        // Check memory cache first
        if let cached = tokenCache[provider.id], !cached.isExpired {
            return cached.accessToken
        }

        // Load from Keychain
        guard var tokenData = loadTokenData(for: provider.id) else {
            throw OAuthError.noOAuthConfig
        }

        // Refresh if expired
        if tokenData.isExpired, let refreshToken = tokenData.refreshToken {
            tokenData = try await refreshAccessToken(
                refreshToken: refreshToken,
                provider: provider
            )
            try persistTokenData(tokenData, for: provider.id)
        }

        tokenCache[provider.id] = tokenData
        return tokenData.accessToken
    }

    /// Check if we have stored OAuth credentials for a provider
    func isSignedIn(providerID: String) -> Bool {
        keychainStore.hasSecret(account: oauthAccount(providerID))
    }

    // MARK: - Token Exchange

    private func exchangeCode(code: String, codeVerifier: String?, provider: ModelProvider) async throws -> OAuthTokenData {
        guard let oauth = provider.oauthConfig else { throw OAuthError.noOAuthConfig }

        var body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "\(oauth.redirectScheme)://oauth/callback",
        ]
        if let codeVerifier {
            body["code_verifier"] = codeVerifier
        }
        if oauth.clientIDRequired {
            body["client_id"] = oauth.clientID
        }

        return try await tokenRequest(url: oauth.tokenURL, body: body)
    }

    private func refreshAccessToken(refreshToken: String, provider: ModelProvider) async throws -> OAuthTokenData {
        guard let oauth = provider.oauthConfig else { throw OAuthError.noOAuthConfig }

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauth.clientID,
        ]

        var tokenData = try await tokenRequest(url: oauth.tokenURL, body: body)
        // Refresh responses may not include a new refresh token — keep the old one
        if tokenData.refreshToken == nil {
            tokenData.refreshToken = refreshToken
        }
        Log.debug("oauth", "Token refreshed for \(provider.name)")
        return tokenData
    }

    private func tokenRequest(url: String, body: [String: String]) async throws -> OAuthTokenData {
        guard let tokenURL = URL(string: url) else {
            throw OAuthError.tokenExchangeFailed("Invalid token URL")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Non-HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data.prefix(500), encoding: .utf8) ?? "unknown"
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.tokenExchangeFailed("Invalid JSON response")
        }

        guard let accessToken = json["access_token"] as? String else {
            // OpenRouter returns an API key instead
            if let key = json["key"] as? String {
                return OAuthTokenData(accessToken: key, refreshToken: nil, expiresAt: nil, tokenType: "apikey")
            }
            throw OAuthError.tokenExchangeFailed("No access_token in response")
        }

        let expiresIn = json["expires_in"] as? Int
        let expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }

        return OAuthTokenData(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: expiresAt,
            tokenType: json["token_type"] as? String
        )
    }

    // MARK: - Keychain Persistence

    private func oauthAccount(_ providerID: String) -> String {
        "oauth:\(providerID)"
    }

    private func persistTokenData(_ tokenData: OAuthTokenData, for providerID: String) throws {
        let data = try JSONEncoder().encode(tokenData)
        let json = String(data: data, encoding: .utf8) ?? ""
        try keychainStore.save(secret: json, account: oauthAccount(providerID))
    }

    private func loadTokenData(for providerID: String) -> OAuthTokenData? {
        guard let json = try? keychainStore.readSecret(account: oauthAccount(providerID)),
              let data = json.data(using: .utf8),
              let tokenData = try? JSONDecoder().decode(OAuthTokenData.self, from: data) else {
            return nil
        }
        return tokenData
    }

    // MARK: - PKCE Helpers

    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? ASPresentationAnchor()
    }
}
