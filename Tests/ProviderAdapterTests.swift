import Foundation
import Foundation
import Testing
@testable import aTerm

struct ProviderAdapterTests {
    // MARK: - Builtin Providers
    
    @Test
    func builtinProvidersCoverAppendixFormats() {
        let formats = Set(BuiltinProviders.all.map(\.apiFormat))
        
        #expect(formats.contains(.openAICompatible) || formats.contains(.openAICompatible))
        #expect(formats.contains(.anthropic) || formats.contains(.anthropic))
        #expect(formats.contains(.gemini) || formats.contains(.gemini))
    }
    
    @Test
    func openAICompatibleProvidersUseBearerAuth() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "openai" })
        
        #expect(provider?.authType == .bearer)
        #expect(provider?.apiFormat == .openAICompatible)
        #expect(provider?.endpoint == "https://api.openai.com/v1/chat/completions")
    }
    
    @Test
    func anthropicProviderUsesXApiKey() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "anthropic" })
        
        #expect(provider?.authType == .xApiKey)
        #expect(provider?.apiFormat == .anthropic)
        #expect(provider?.endpoint == "https://api.anthropic.com/v1/messages")
        #expect(provider?.customHeaders["anthropic-version"] != nil)
    }
    
    @Test
    func geminiProviderUsesOAuth() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "gemini" })

        #expect(provider?.authType == .oauthToken)
        #expect(provider?.apiFormat == .gemini)
        #expect(provider?.oauthConfig != nil)
        #expect(provider?.oauthConfig?.authURL == "https://accounts.google.com/o/oauth2/v2/auth")
    }
    
    @Test
    func ollamaProviderUsesNoAuth() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "ollama" })
        
        #expect(provider?.authType == AuthType.none)
        #expect(provider?.apiFormat == .openAICompatible)
        #expect(provider?.endpoint == "http://localhost:11434/v1/chat/completions")
    }
    
    @Test
    func allBuiltinProvidersHaveModelsExceptLocal() {
        for provider in BuiltinProviders.all {
            // Ollama and llama.cpp have empty model lists by design (auto-detected at runtime)
            if provider.id == "ollama" || provider.id == "llamacpp" {
                continue
            }
            #expect(!provider.models.isEmpty, "Provider \(provider.name) should have at least one model")
        }
    }
    
    @Test
    func allBuiltinProvidersHaveUniqueIDs() {
        let ids = BuiltinProviders.all.map(\.id)
        let uniqueIDs = Set(ids)
        
        #expect(ids.count == uniqueIDs.count)
    }
    
    // MARK: - Provider Formats
    
    @Test
    func openAICompatibleFormats() {
        let openAIProviders = BuiltinProviders.all.filter { $0.apiFormat == .openAICompatible }
        let expectedProviders = ["openai", "grok", "together", "mistral", "ollama", "llamacpp", "openrouter", "deepseek", "kimi"]
        
        for expectedID in expectedProviders {
            #expect(openAIProviders.contains(where: { $0.id == expectedID }), "Should have \(expectedID) provider")
        }
    }
    
    @Test
    func mistralProviderConfiguration() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "mistral" })
        
        #expect(provider?.authType == .bearer)
        #expect(provider?.endpoint == "https://api.mistral.ai/v1/chat/completions")
    }
    
    @Test
    func grokProviderConfiguration() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "grok" })

        #expect(provider?.authType == .bearer)
        #expect(provider?.endpoint == "https://api.x.ai/v1/chat/completions")
    }
    
    @Test
    func togetherProviderConfiguration() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "together" })
        
        #expect(provider?.authType == .bearer)
        #expect(provider?.endpoint == "https://api.together.xyz/v1/chat/completions")
    }
    
    @Test
    func openRouterProviderConfiguration() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "openrouter" })

        #expect(provider?.authType == .oauthToken)
        #expect(provider?.endpoint == "https://openrouter.ai/api/v1/chat/completions")
        #expect(provider?.oauthConfig != nil)
    }
    
    @Test
    func deepseekProviderConfiguration() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "deepseek" })
        
        #expect(provider?.authType == .bearer)
        #expect(provider?.endpoint == "https://api.deepseek.com/v1/chat/completions")
    }
    
    @Test
    func kimiProviderConfiguration() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "kimi" })
        
        #expect(provider?.authType == .bearer)
        #expect(provider?.endpoint == "https://api.moonshot.cn/v1/chat/completions")
    }
    
    @Test
    func llamacppProviderConfiguration() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "llamacpp" })
        
        #expect(provider?.authType == AuthType.none)
        #expect(provider?.endpoint == "http://localhost:8080/v1/chat/completions")
    }
    
    // MARK: - Model Definitions
    
    @Test
    func openAIModels() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "openai" })
        let modelIDs = provider?.models.map(\.id) ?? []
        
        #expect(modelIDs.contains("gpt-4o"))
        #expect(modelIDs.contains("gpt-4o-mini"))
    }
    
    @Test
    func anthropicModels() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "anthropic" })
        let modelIDs = provider?.models.map(\.id) ?? []
        
        #expect(modelIDs.contains("claude-sonnet-4-5"))
        #expect(modelIDs.contains("claude-haiku-4-5"))
    }
    
    @Test
    func modelsHaveContextWindows() {
        for provider in BuiltinProviders.all {
            for model in provider.models {
                #expect(model.contextWindow > 0, "Model \(model.id) should have context window")
            }
        }
    }
    
    @Test
    func modelsHaveStreamingSupport() {
        for provider in BuiltinProviders.all {
            for model in provider.models {
                #expect(model.supportsStreaming == true, "Model \(model.id) should support streaming")
            }
        }
    }
    
    // MARK: - Custom Provider Creation
    
    @Test
    func customProviderCanBeCreated() {
        let provider = ModelProvider(
            id: "my-provider",
            name: "My Provider",
            endpoint: "https://my-api.com/chat",
            authType: .bearer,
            apiFormat: .openAICompatible,
            models: [
                ModelDefinition(id: "model1", name: "Model 1", contextWindow: 4096, supportsStreaming: true)
            ],
            customHeaders: ["X-Custom": "Value"],
            isBuiltin: false
        )
        
        #expect(provider.id == "my-provider")
        #expect(provider.name == "My Provider")
        #expect(provider.isBuiltin == false)
        #expect(provider.customHeaders["X-Custom"] == "Value")
    }
    
    // MARK: - Auth Types
    
    @Test
    func authTypeEquality() {
        #expect(AuthType.bearer == AuthType.bearer)
        #expect(AuthType.xApiKey == AuthType.xApiKey)
        #expect(AuthType.none == AuthType.none)
        #expect(AuthType.bearer != AuthType.xApiKey)
    }
    
    @Test
    func authTypeCodable() throws {
        let types: [AuthType] = [.bearer, .xApiKey, .oauthToken, .none]
        
        for type in types {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(AuthType.self, from: encoded)
            #expect(type == decoded)
        }
    }
    
    // MARK: - API Formats
    
    @Test
    func apiFormatEquality() {
        #expect(APIFormat.openAICompatible == APIFormat.openAICompatible)
        #expect(APIFormat.anthropic == APIFormat.anthropic)
        #expect(APIFormat.gemini == APIFormat.gemini)
        #expect(APIFormat.openAICompatible != APIFormat.anthropic)
    }
    
    @Test
    func apiFormatCodable() throws {
        let formats: [APIFormat] = [.openAICompatible, .anthropic, .gemini, .custom]
        
        for format in formats {
            let encoded = try JSONEncoder().encode(format)
            let decoded = try JSONDecoder().decode(APIFormat.self, from: encoded)
            #expect(format == decoded)
        }
    }
    
    // MARK: - Model Definition
    
    @Test
    func modelDefinitionProperties() {
        let model = ModelDefinition(
            id: "test-model",
            name: "Test Model",
            contextWindow: 128000,
            supportsStreaming: true
        )
        
        #expect(model.id == "test-model")
        #expect(model.name == "Test Model")
        #expect(model.contextWindow == 128000)
        #expect(model.supportsStreaming == true)
    }
    
    @Test
    func modelDefinitionCodable() throws {
        let model = ModelDefinition(
            id: "test-model",
            name: "Test Model",
            contextWindow: 4096,
            supportsStreaming: false
        )
        
        let encoded = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(ModelDefinition.self, from: encoded)
        
        #expect(model.id == decoded.id)
        #expect(model.name == decoded.name)
        #expect(model.contextWindow == decoded.contextWindow)
        #expect(model.supportsStreaming == decoded.supportsStreaming)
    }
    
    // MARK: - Model Provider Codable
    
    @Test
    func modelProviderCodable() throws {
        let provider = ModelProvider(
            id: "test-provider",
            name: "Test Provider",
            endpoint: "https://test.com",
            authType: .bearer,
            apiFormat: .openAICompatible,
            models: [
                ModelDefinition(id: "model1", name: "Model 1", contextWindow: 4096, supportsStreaming: true)
            ],
            customHeaders: ["X-Key": "Value"],
            isBuiltin: false
        )
        
        let encoded = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(ModelProvider.self, from: encoded)
        
        #expect(provider.id == decoded.id)
        #expect(provider.name == decoded.name)
        #expect(provider.endpoint == decoded.endpoint)
        #expect(provider.authType == decoded.authType)
        #expect(provider.apiFormat == decoded.apiFormat)
        #expect(provider.models.count == decoded.models.count)
        #expect(provider.customHeaders == decoded.customHeaders)
        #expect(provider.isBuiltin == decoded.isBuiltin)
    }
}
