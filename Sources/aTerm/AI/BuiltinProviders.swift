import Foundation

enum BuiltinProviders {
    static let all: [ModelProvider] = [
        provider(
            id: "anthropic",
            name: "Anthropic",
            endpoint: "https://api.anthropic.com/v1/messages",
            authType: .xApiKey,
            apiFormat: .anthropic,
            models: [
                .init(id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5", contextWindow: 200_000, supportsStreaming: true),
                .init(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", contextWindow: 200_000, supportsStreaming: true),
                .init(id: "claude-opus-4-5", name: "Claude Opus 4.5", contextWindow: 200_000, supportsStreaming: true),
            ],
            customHeaders: ["anthropic-version": "2023-06-01"]
        ),
        provider(
            id: "openai",
            name: "OpenAI",
            endpoint: "https://api.openai.com/v1/chat/completions",
            authType: .bearer,
            apiFormat: .openAICompatible,
            models: [
                .init(id: "gpt-4o", name: "GPT-4o", contextWindow: 128_000, supportsStreaming: true),
                .init(id: "gpt-4o-mini", name: "GPT-4o Mini", contextWindow: 128_000, supportsStreaming: true),
                .init(id: "o3-mini", name: "o3-mini", contextWindow: 200_000, supportsStreaming: true),
            ]
        ),
        provider(
            id: "gemini",
            name: "Google Gemini",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent",
            authType: .oauthToken,
            apiFormat: .gemini,
            models: [
                .init(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", contextWindow: 1_000_000, supportsStreaming: true),
                .init(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", contextWindow: 1_000_000, supportsStreaming: true),
            ],
            oauthConfig: OAuthConfig(
                authURL: "https://accounts.google.com/o/oauth2/v2/auth",
                tokenURL: "https://oauth2.googleapis.com/token",
                scopes: ["https://www.googleapis.com/auth/generative-language"]
            )
        ),
        provider(id: "grok", name: "xAI Grok", endpoint: "https://api.x.ai/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: [
            .init(id: "grok-4.5", name: "Grok 4.5", contextWindow: 128_000, supportsStreaming: true),
            .init(id: "grok-4.5-fast", name: "Grok 4.5 Fast", contextWindow: 128_000, supportsStreaming: true),
        ]),
        provider(id: "mistral", name: "Mistral", endpoint: "https://api.mistral.ai/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: [
            .init(id: "mistral-large-latest", name: "Mistral Large", contextWindow: 128_000, supportsStreaming: true),
            .init(id: "mistral-small-latest", name: "Mistral Small", contextWindow: 128_000, supportsStreaming: true),
        ]),
        provider(
            id: "openrouter",
            name: "OpenRouter",
            endpoint: "https://openrouter.ai/api/v1/chat/completions",
            authType: .oauthToken,
            apiFormat: .openAICompatible,
            models: [
                .init(id: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4", contextWindow: 200_000, supportsStreaming: true),
                .init(id: "openai/gpt-4o", name: "GPT-4o", contextWindow: 128_000, supportsStreaming: true),
                .init(id: "google/gemini-2.5-pro", name: "Gemini 2.5 Pro", contextWindow: 1_000_000, supportsStreaming: true),
            ],
            oauthConfig: OAuthConfig(
                authURL: "https://openrouter.ai/auth",
                tokenURL: "https://openrouter.ai/api/v1/auth/keys",
                scopes: [],
                clientIDRequired: false
            )
        ),
        provider(id: "together", name: "Together AI", endpoint: "https://api.together.xyz/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: [
            .init(id: "meta-llama/Llama-3.3-70B-Instruct-Turbo", name: "Llama 3.3 70B Turbo", contextWindow: 128_000, supportsStreaming: true),
            .init(id: "Qwen/Qwen2.5-72B-Instruct-Turbo", name: "Qwen 2.5 72B Turbo", contextWindow: 32_768, supportsStreaming: true),
        ]),
        provider(id: "deepseek", name: "DeepSeek", endpoint: "https://api.deepseek.com/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: [
            .init(id: "deepseek-chat", name: "DeepSeek V3", contextWindow: 64_000, supportsStreaming: true),
            .init(id: "deepseek-reasoner", name: "DeepSeek R1", contextWindow: 64_000, supportsStreaming: true),
        ]),
        provider(id: "kimi", name: "Kimi", endpoint: "https://api.moonshot.cn/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: [
            .init(id: "kimi-k2.5", name: "Kimi K2.5", contextWindow: 256_000, supportsStreaming: true),
            .init(id: "moonshot-v1-128k", name: "Moonshot V1 128K", contextWindow: 128_000, supportsStreaming: true),
        ]),
        provider(id: "ollama", name: "Ollama (local)", endpoint: "http://localhost:11434/v1/chat/completions", authType: .none, apiFormat: .openAICompatible, models: []),
        provider(id: "llamacpp", name: "llama.cpp (local)", endpoint: "http://localhost:8080/v1/chat/completions", authType: .none, apiFormat: .openAICompatible, models: []),
    ]

    private static func provider(
        id: String,
        name: String,
        endpoint: String,
        authType: AuthType,
        apiFormat: APIFormat,
        models: [ModelDefinition],
        customHeaders: [String: String] = [:],
        oauthConfig: OAuthConfig? = nil
    ) -> ModelProvider {
        ModelProvider(
            id: id,
            name: name,
            endpoint: endpoint,
            authType: authType,
            apiFormat: apiFormat,
            models: models,
            customHeaders: customHeaders,
            isBuiltin: true,
            oauthConfig: oauthConfig
        )
    }
}

