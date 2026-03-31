import SwiftUI

struct ProvidersSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedProviderID: String?
    @State private var isAddingNew = false

    var body: some View {
        HSplitView {
            // Provider list
            VStack(alignment: .leading, spacing: 0) {
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
                HStack {
                    Button(action: { isAddingNew = true }) {
                        Label("Add Provider", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                    Spacer()
                }
            }
            .frame(minWidth: 200, maxWidth: 240)

            // Detail / editor
            if isAddingNew {
                ProviderEditorView(provider: nil, onSave: { provider, secret in
                    try? appModel.upsertProvider(provider, secret: secret)
                    isAddingNew = false
                    selectedProviderID = provider.id
                }, onCancel: { isAddingNew = false })
            } else if let id = selectedProviderID, let provider = appModel.provider(for: id) {
                ProviderEditorView(provider: provider, onSave: { updated, secret in
                    try? appModel.upsertProvider(updated, secret: secret)
                }, onCancel: { selectedProviderID = nil })
            } else {
                VStack {
                    Spacer()
                    Text("Select a provider or add a new one")
                        .foregroundStyle(.secondary)
                    Spacer()
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

    /// Provider with the current OAuth client ID from the text field applied
    private var providerWithCurrentOAuthClientID: ModelProvider? {
        guard var p = provider, var oauth = p.oauthConfig else { return provider }
        oauth.clientID = oauthClientID
        p.oauthConfig = oauth
        return p
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(provider == nil ? "New Provider" : name)
                    .font(.title2.bold())

                Group {
                    LabeledContent("ID") {
                        TextField("provider-slug", text: $slug)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isBuiltin)
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
                    LabeledContent("Auth Type") {
                        Picker("", selection: $authType) {
                            ForEach(AuthType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .disabled(isBuiltin)
                    }
                    LabeledContent("API Format") {
                        Picker("", selection: $apiFormat) {
                            Text("OpenAI Compatible").tag(APIFormat.openAICompatible)
                            Text("Anthropic").tag(APIFormat.anthropic)
                            Text("Gemini").tag(APIFormat.gemini)
                            Text("Custom").tag(APIFormat.custom)
                        }
                        .labelsHidden()
                        .disabled(isBuiltin)
                    }
                }

                Divider()

                if authType == .oauthToken, provider?.oauthConfig != nil {
                    if provider?.oauthConfig?.clientIDRequired == true {
                        LabeledContent("OAuth Client ID") {
                            TextField("Enter your OAuth client ID", text: $oauthClientID)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("Create at console.cloud.google.com → APIs & Services → Credentials → OAuth 2.0 Client ID (Desktop app).")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    OAuthSignInSection(provider: providerWithCurrentOAuthClientID)
                } else if authType != .none {
                    LabeledContent("API Key / Token") {
                        SecureField("Paste your API key", text: $secret)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Stored securely in macOS Keychain. Never written to disk.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("Models").font(.headline)
                ForEach(models) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.name).fontWeight(.medium)
                            Text(model.id)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !isBuiltin {
                            Button(role: .destructive) {
                                models.removeAll { $0.id == model.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !isBuiltin {
                    HStack {
                        TextField("Model ID", text: $modelID)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                        TextField("Display Name", text: $modelName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                        Button("Add") {
                            guard !modelID.isEmpty else { return }
                            let displayName = modelName.isEmpty ? modelID : modelName
                            models.append(ModelDefinition(id: modelID, name: displayName, contextWindow: 128_000, supportsStreaming: true))
                            modelID = ""
                            modelName = ""
                        }
                    }
                    
                    // Fetch models button for OpenAI-compatible endpoints
                    if apiFormat == .openAICompatible || apiFormat == .custom {
                        Button("Fetch Models from Endpoint") {
                            fetchModelsFromEndpoint()
                        }
                        .disabled(endpoint.isEmpty || isFetchingModels)
                        
                        if isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else if let fetchModelsError {
                            Text(fetchModelsError)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        } else if !fetchedModels.isEmpty {
                            Text("Found \(fetchedModels.count) models")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.system(size: 12))
                            .foregroundColor(testResult.contains("ms") ? .primary : .red)
                            .lineLimit(2)
                    }

                    Spacer()

                    if provider != nil, !isBuiltin {
                        Button("Delete", role: .destructive) {
                            if let id = provider?.id {
                                appModel.deleteProvider(id)
                                onCancel()
                            }
                        }
                    }

                    Button("Save") {
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
                        let updated = ModelProvider(
                            id: slug.isEmpty ? UUID().uuidString : slug,
                            name: name,
                            endpoint: endpoint,
                            authType: authType,
                            apiFormat: apiFormat,
                            models: models,
                            customHeaders: provider?.customHeaders ?? [:],
                            isBuiltin: false,
                            oauthConfig: oauthConfig
                        )
                        onSave(updated, secret.isEmpty ? nil : secret)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(slug.isEmpty && !isBuiltin)
                }
            }
            .padding(20)
        }
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
