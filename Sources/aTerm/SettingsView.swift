import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProvidersSettingsTab()
                .tabItem { Label("Providers", systemImage: "network") }
            ProfilesSettingsTab()
                .tabItem { Label("Profiles", systemImage: "person.crop.square") }
            AgentsSettingsTab()
                .tabItem { Label("Agents", systemImage: "bolt") }
            MCPSettingsTab()
                .tabItem { Label("MCP", systemImage: "server.rack") }
            KeybindingsSettingsTab()
                .tabItem { Label("Keys", systemImage: "keyboard") }
        }
        .padding(16)
        .frame(width: 780, height: 600)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("Shell") {
                LabeledContent("Default Shell") {
                    Text((try? ShellLocator.detectZsh()) ?? "/bin/zsh")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Default Profile") {
                    Picker("", selection: Binding(
                        get: { appModel.defaultProfileID ?? appModel.profiles.first?.id ?? UUID() },
                        set: { appModel.setDefaultProfile($0) }
                    )) {
                        ForEach(appModel.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            Section("Shell Integration") {
                Button("Install Shell Integration") {
                    appModel.installShellIntegration()
                }
                if let message = appModel.shellIntegrationMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Providers (full add/edit/delete/test)

private struct ProvidersSettingsTab: View {
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

private struct ProviderEditorView: View {
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
    @State private var testResult: String?
    @State private var isTesting = false

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
    }

    private var isBuiltin: Bool { provider?.isBuiltin ?? false }

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
                            Text("Bearer Token").tag(AuthType.bearer)
                            Text("x-api-key").tag(AuthType.xApiKey)
                            Text("OAuth Token").tag(AuthType.oauthToken)
                            Text("None").tag(AuthType.none)
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

                if authType != .none {
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
                        let updated = ModelProvider(
                            id: slug.isEmpty ? UUID().uuidString : slug,
                            name: name,
                            endpoint: endpoint,
                            authType: authType,
                            apiFormat: apiFormat,
                            models: models,
                            customHeaders: provider?.customHeaders ?? [:],
                            isBuiltin: false
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
}

// MARK: - Profiles

private struct ProfilesSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(appModel.profiles) { profile in
                    HStack {
                        Text(profile.name)
                            .fontWeight(appModel.defaultProfileID == profile.id ? .bold : .regular)
                        Spacer()
                        if appModel.defaultProfileID == profile.id {
                            Text("Default")
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15))
                                .clipShape(Capsule())
                        } else {
                            Button("Set Default") {
                                appModel.setDefaultProfile(profile.id)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                TextField("New profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)
                Button("Create from Current Tab") {
                    guard !newProfileName.isEmpty else { return }
                    appModel.createProfileFromSelectedTab(named: newProfileName)
                    newProfileName = ""
                }
                .disabled(newProfileName.isEmpty)
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Agents

private struct AgentsSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            ForEach(appModel.availableAgents) { agent in
                HStack(spacing: 10) {
                    Circle()
                        .fill((appModel.agentStatuses[agent.id]?.isInstalled ?? false) ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name).fontWeight(.medium)
                        if let path = appModel.agentStatuses[agent.id]?.executablePath {
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Text("Not installed:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(agent.installHint)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    Spacer()
                    if appModel.defaultAgentID == agent.id {
                        Text("Default")
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Button("Set Default") {
                            appModel.setDefaultAgent(agent.id)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

// MARK: - MCP

private struct MCPSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            ForEach(appModel.availableMCPServers) { server in
                let snapshot = appModel.mcpSnapshots[server.id]
                let status = snapshot?.status ?? .stopped
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor(status))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(server.name).fontWeight(.medium)
                            Text("(\(server.transport == .stdio ? "stdio" : "SSE"))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(snapshot?.toolCount ?? 0) tools")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if let error = snapshot?.lastError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        if status == .running {
                            Button("Stop") {
                                appModel.stopMCPServer(server)
                            }
                            .controlSize(.small)
                            Button("Restart") {
                                appModel.restartMCPServer(server, cwd: appModel.selectedTab?.currentWorkingDirectory)
                            }
                            .controlSize(.small)
                        } else {
                            Button("Start") {
                                appModel.startMCPServer(server, cwd: appModel.selectedTab?.currentWorkingDirectory)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func statusColor(_ status: MCPServerStatus) -> Color {
        switch status {
        case .running: return .green
        case .error: return .red
        case .stopped: return .gray.opacity(0.5)
        }
    }
}

// MARK: - Keybindings

private struct KeybindingsSettingsTab: View {
    private let bindings: [(key: String, action: String)] = [
        ("Cmd+T", "New Tab"),
        ("Cmd+W", "Close Tab"),
        ("Cmd+M", "Model Picker"),
        ("Cmd+,", "Preferences"),
        ("Cmd+F", "Find in Scrollback"),
        ("Cmd+K", "Clear Scrollback"),
        ("Cmd+D", "Split Horizontally"),
        ("Cmd+Shift+D", "Split Vertically"),
        ("Ctrl+C", "Interrupt (SIGINT)"),
        ("Ctrl+D", "EOF"),
        ("Ctrl+Z", "Suspend (SIGTSTP)"),
    ]

    var body: some View {
        List {
            ForEach(bindings, id: \.key) { binding in
                HStack {
                    Text(binding.key)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 160, alignment: .leading)
                    Text(binding.action)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }
}
