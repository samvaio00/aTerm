import SwiftUI

struct ProvidersSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedProviderID: String?
    @State private var isAddingNew = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Providers")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                List(appModel.availableProviders, selection: $selectedProviderID) { provider in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(appModel.hasStoredCredential(for: provider.id) || provider.authType == .none ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name).fontWeight(.medium)
                            Text("\(provider.models.count) models")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(provider.id)
                }
                .listStyle(.sidebar)

                Divider()
                Button {
                    isAddingNew = true
                    selectedProviderID = nil
                } label: {
                    Label("Add custom provider", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

            Group {
                if isAddingNew {
                    ProviderEditorView(provider: nil, onSave: { provider, secret in
                        try? appModel.upsertProvider(provider, secret: secret)
                        isAddingNew = false
                        selectedProviderID = provider.id
                    }, onCancel: {
                        isAddingNew = false
                    })
                } else if let id = selectedProviderID, let provider = appModel.provider(for: id) {
                    ProviderEditorView(provider: provider, onSave: { updated, secret in
                        try? appModel.upsertProvider(updated, secret: secret)
                    }, onCancel: { selectedProviderID = nil })
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "network")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text("Select a provider")
                            .font(.headline)
                        Text("Choose a built-in provider to add API keys or custom models, or create a new OpenAI-compatible endpoint.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct ProviderEditorView: View {
    let provider: ModelProvider?
    let onSave: (ModelProvider, String?) -> Void
    let onCancel: () -> Void
    @EnvironmentObject private var appModel: AppModel

    @State private var slug: String
    @State private var name: String
    @State private var endpoint: String
    @State private var authType: AuthType
    @State private var apiFormat: APIFormat
    @State private var secret: String = ""
    @State private var modelID: String = ""
    @State private var modelName: String = ""
    @State private var models: [ModelDefinition]
    @State private var oauthClientID: String
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isFetchingModels = false
    @State private var fetchedModels: [ModelDefinition] = []
    @State private var fetchModelsError: String?

    init(provider: ModelProvider?, onSave: @escaping (ModelProvider, String?) -> Void, onCancel: @escaping () -> Void) {
        self.provider = provider
        self.onSave = onSave
        self.onCancel = onCancel
        _slug = State(initialValue: provider?.id ?? "")
        _name = State(initialValue: provider?.name ?? "")
        _endpoint = State(initialValue: provider?.endpoint ?? "")
        _authType = State(initialValue: provider?.authType ?? .bearer)
        _apiFormat = State(initialValue: provider?.apiFormat ?? .openAICompatible)
        _models = State(initialValue: provider?.models ?? [])
        _oauthClientID = State(initialValue: provider?.oauthConfig?.clientID ?? "")
    }

    private var isBuiltin: Bool { provider?.isBuiltin ?? false }

    /// Built-in catalog model IDs for this provider (user-added models are not in this set).
    private var builtinBaselineModelIDs: Set<String> {
        guard let id = provider?.id else { return [] }
        let baseline = BuiltinProviders.all.first(where: { $0.id == id })?.models ?? []
        return Set(baseline.map(\.id))
    }

    private func canRemoveModel(_ model: ModelDefinition) -> Bool {
        if !isBuiltin { return true }
        return !builtinBaselineModelIDs.contains(model.id)
    }

    private var canSaveNewProvider: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Provider with the current OAuth client ID from the text field applied
    private var providerWithCurrentOAuthClientID: ModelProvider? {
        guard var p = provider, var oauth = p.oauthConfig else { return provider }
        oauth.clientID = oauthClientID
        p.oauthConfig = oauth
        return p
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(provider == nil ? "New provider" : name)
                        .font(.title2.bold())
                    if isBuiltin {
                        Text("Built-in")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.5))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Button("Cancel", role: .cancel) { onCancel() }
                        .keyboardShortcut(.cancelAction)
                }

                GroupBox("Connection") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("ID") {
                            TextField("my-provider", text: $slug)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isBuiltin)
                        }
                        if provider == nil {
                            Text("Leave blank to derive from the name (lowercase, hyphens).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Name") {
                            TextField("Provider Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isBuiltin)
                        }
                        LabeledContent("Endpoint") {
                            TextField("https://api.example.com/v1/chat/completions", text: $endpoint)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isBuiltin)
                        }
                        LabeledContent("Auth type") {
                            Picker("", selection: $authType) {
                                ForEach(AuthType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220, alignment: .leading)
                            .disabled(isBuiltin)
                        }
                        LabeledContent("API format") {
                            Picker("", selection: $apiFormat) {
                                Text("OpenAI compatible").tag(APIFormat.openAICompatible)
                                Text("Anthropic").tag(APIFormat.anthropic)
                                Text("Gemini").tag(APIFormat.gemini)
                                Text("Custom").tag(APIFormat.custom)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220, alignment: .leading)
                            .disabled(isBuiltin)
                        }
                    }
                    .padding(4)
                }

                GroupBox("Authentication") {
                    VStack(alignment: .leading, spacing: 10) {
                        if authType == .oauthToken, provider?.oauthConfig != nil {
                            if provider?.oauthConfig?.clientIDRequired == true {
                                LabeledContent("OAuth client ID") {
                                    TextField("Enter your OAuth client ID", text: $oauthClientID)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Text("Create at console.cloud.google.com → APIs & Services → Credentials → OAuth 2.0 Client ID (Desktop app).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            OAuthSignInSection(provider: providerWithCurrentOAuthClientID)
                        } else if authType != .none {
                            LabeledContent("API key / token") {
                                SecureField("Paste your API key", text: $secret)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Text("Stored in macOS Keychain only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No credentials required for this provider.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }

                GroupBox("Models") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isBuiltin
                             ? "Add models by ID, or fetch from the endpoint. Catalog models cannot be removed."
                             : "Define models manually, fetch from the endpoint, or both.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if models.isEmpty {
                            Text("No models yet — add at least one, or use “Fetch models”.")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }

                        ForEach(models) { model in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name).fontWeight(.medium)
                                    Text(model.id)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if canRemoveModel(model) {
                                    Button(role: .destructive) {
                                        models.removeAll { $0.id == model.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove model")
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TextField("Model ID", text: $modelID)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 140, idealWidth: 180)
                            TextField("Display name (optional)", text: $modelName)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 140, idealWidth: 200)
                            Button("Add model") {
                                let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                let displayName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                                let finalName = displayName.isEmpty ? trimmed : displayName
                                let exists = models.contains { $0.id == trimmed }
                                guard !exists else { return }
                                models.append(ModelDefinition(id: trimmed, name: finalName, contextWindow: 128_000, supportsStreaming: true))
                                modelID = ""
                                modelName = ""
                            }
                            .disabled(modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if apiFormat == .openAICompatible || apiFormat == .custom {
                            HStack(spacing: 8) {
                                Button("Fetch models from endpoint") {
                                    fetchModelsFromEndpoint()
                                }
                                .disabled(endpoint.isEmpty || isFetchingModels)
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            if let fetchModelsError {
                                Text(fetchModelsError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else if !fetchedModels.isEmpty {
                                Text("Merged \(fetchedModels.count) model(s) from the server.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(4)
                }

                HStack(spacing: 12) {
                    Button("Test connection") {
                        testConnection()
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.contains("ms") ? Color.primary : Color.red)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 8)

                    if provider != nil, !isBuiltin {
                        Button("Delete provider", role: .destructive) {
                            if let id = provider?.id {
                                appModel.deleteProvider(id)
                                onCancel()
                            }
                        }
                    }

                    Button("Save") {
                        saveProvider()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(provider == nil && !canSaveNewProvider)
                }
            }
            .padding(20)
        }
    }

    private func saveProvider() {
        var oauthConfig = provider?.oauthConfig
        if let existing = oauthConfig, !oauthClientID.isEmpty {
            oauthConfig = OAuthConfig(
                clientID: oauthClientID,
                authURL: existing.authURL,
                tokenURL: existing.tokenURL,
                scopes: existing.scopes,
                redirectScheme: existing.redirectScheme,
                clientIDRequired: existing.clientIDRequired
            )
        }
        let trimmedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let derivedID: String = {
            if !trimmedSlug.isEmpty { return trimmedSlug }
            let fromName = trimmedName.lowercased().replacingOccurrences(of: " ", with: "-")
            if !fromName.isEmpty { return fromName }
            return UUID().uuidString
        }()
        let updated = ModelProvider(
            id: derivedID,
            name: trimmedName.isEmpty ? derivedID : trimmedName,
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            authType: authType,
            apiFormat: apiFormat,
            models: models,
            customHeaders: provider?.customHeaders ?? [:],
            isBuiltin: provider?.isBuiltin ?? false,
            oauthConfig: oauthConfig
        )
        onSave(updated, secret.isEmpty ? nil : secret)
    }

    private func testConnection() {
        let testProvider = ModelProvider(
            id: slug, name: name, endpoint: endpoint,
            authType: authType, apiFormat: apiFormat,
            models: models, customHeaders: provider?.customHeaders ?? [:],
            isBuiltin: false
        )
        isTesting = true
        testResult = nil
        Task {
            await appModel.testConnection(for: testProvider)
            testResult = appModel.providerStatusMessage
            isTesting = false
        }
    }
    
    private func fetchModelsFromEndpoint() {
        guard !endpoint.isEmpty else { return }
        isFetchingModels = true
        fetchModelsError = nil
        fetchedModels = []
        
        Task {
            do {
                let router = ProviderRouter()
                let apiKey = authType == .none ? nil : secret
                let fetched = try await router.fetchModels(endpoint: endpoint, apiKey: apiKey)
                await MainActor.run {
                    // Merge fetched models with existing ones (avoid duplicates)
                    let existingIDs = Set(models.map(\.id))
                    let newModels = fetched.filter { !existingIDs.contains($0.id) }
                    models.append(contentsOf: newModels)
                    fetchedModels = fetched
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    fetchModelsError = "Failed: \(error.localizedDescription)"
                    isFetchingModels = false
                }
            }
        }
    }
}

struct OAuthSignInSection: View {
    let provider: ModelProvider?
    @EnvironmentObject private var appModel: AppModel
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private var isSignedIn: Bool {
        guard let id = provider?.id else { return false }
        return appModel.hasStoredCredential(for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSignedIn {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Signed in to \(provider?.name ?? "provider")")
                        .fontWeight(.medium)
                    Spacer()
                    Button("Sign Out") {
                        guard let id = provider?.id else { return }
                        try? appModel.signOutOAuth(providerID: id)
                    }
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        signIn()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                            Text("Sign in to \(provider?.name ?? "provider")")
                        }
                    }
                    .disabled(isSigningIn)

                    if isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Text("Signs in via your browser. No API key needed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func signIn() {
        guard let id = provider?.id else { return }
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                try await appModel.signInWithOAuth(providerID: id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
