import Foundation
import Testing
@testable import aTerm

struct ProviderAdapterTests {
    @Test
    func builtinProvidersCoverAppendixFormats() {
        let formats = Set(BuiltinProviders.all.map(\.apiFormat))

        #expect(formats.contains(.openAICompatible))
        #expect(formats.contains(.anthropic))
        #expect(formats.contains(.gemini))
    }

    @Test
    func openAICompatibleProvidersUseBearerAuth() {
        let provider = BuiltinProviders.all.first(where: { $0.id == "openai" })

        #expect(provider?.authType == .bearer)
        #expect(provider?.apiFormat == .openAICompatible)
    }
}
