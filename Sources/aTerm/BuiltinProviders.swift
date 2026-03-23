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
            ]
        ),
        provider(
            id: "openai",
            name: "OpenAI",
            endpoint: "https://api.openai.com/v1/chat/completions",
            authType: .bearer,
            apiFormat: .openAICompatible,
            models: [
                .init(id: "gpt-5.4", name: "GPT-5.4", contextWindow: 400_000, supportsStreaming: true),
                .init(id: "gpt-5.4-mini", name: "GPT-5.4 Mini", contextWindow: 400_000, supportsStreaming: true),
            ]
        ),
        provider(id: "gemini", name: "Google Gemini", endpoint: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:streamGenerateContent", authType: .bearer, apiFormat: .gemini, models: [
            .init(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", contextWindow: 1_000_000, supportsStreaming: true),
            .init(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", contextWindow: 1_000_000, supportsStreaming: true),
        ]),
        provider(id: "mistral", name: "Mistral", endpoint: "https://api.mistral.ai/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: []),
        provider(id: "groq", name: "Groq", endpoint: "https://api.groq.com/openai/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: []),
        provider(id: "openrouter", name: "OpenRouter", endpoint: "https://openrouter.ai/api/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: []),
        provider(id: "together", name: "Together AI", endpoint: "https://api.together.xyz/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: []),
        provider(id: "kimi", name: "Kimi", endpoint: "https://api.moonshot.cn/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: []),
        provider(id: "deepseek", name: "DeepSeek", endpoint: "https://api.deepseek.com/v1/chat/completions", authType: .bearer, apiFormat: .openAICompatible, models: []),
        provider(id: "ollama", name: "Ollama (local)", endpoint: "http://localhost:11434/v1/chat/completions", authType: .none, apiFormat: .openAICompatible, models: []),
        provider(id: "llama-cpp", name: "llama.cpp (local)", endpoint: "http://localhost:8080/v1/chat/completions", authType: .none, apiFormat: .openAICompatible, models: []),
    ]

    private static func provider(
        id: String,
        name: String,
        endpoint: String,
        authType: AuthType,
        apiFormat: APIFormat,
        models: [ModelDefinition]
    ) -> ModelProvider {
        ModelProvider(
            id: id,
            name: name,
            endpoint: endpoint,
            authType: authType,
            apiFormat: apiFormat,
            models: models,
            customHeaders: [:],
            isBuiltin: true
        )
    }
}
