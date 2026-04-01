import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSidebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var tab: TerminalTabViewModel
    @State private var isImportingTheme = false
    @State private var isCatalogPresented = false
    @State private var newProfileName = ""
    @State private var quickAPIKey = ""
    @State private var quickKeySaved = false
    @State private var quickChatAPIKey = ""
    @State private var quickChatKeySaved = false
    @State private var draftMCPServer = MCPDraft()
    @State private var selectedProviderID: String = ""

    /// Includes current tab fonts so `Picker` selection always matches a tag (see FontSupport).
    private var fontPickerOptions: [String] {
        FontSupport.monospaceFontNamesMerged(with: [tab.appearance.fontName, tab.appearance.nonASCIIFontName])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileSection
                themeSection
                providerSection
                agentSection
                mcpSection
                fontSection
                layoutSection
                environmentSection
            }
            .padding(16)
        }
        .frame(minWidth: 320, idealWidth: 340, maxWidth: 360)
        .fileImporter(isPresented: $isImportingTheme, allowedContentTypes: [.xml, .data]) { result in
            guard case let .success(url) = result else { return }
            try? appModel.importTheme(from: url)
        }
        .sheet(isPresented: $isCatalogPresented) {
            ThemeCatalogSheet()
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Profiles", systemImage: "person.crop.square")
                .font(.headline)

            Picker("Active", selection: activeProfileBinding) {
                ForEach(appModel.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }

            Picker("Default", selection: defaultProfileBinding) {
                ForEach(appModel.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }

            HStack {
                TextField("New profile name", text: $newProfileName)
                Button("Save") {
                    let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    windowModel.createProfileFromSelectedTab(named: name)
                    newProfileName = ""
                }
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Themes", systemImage: "paintpalette")
                    .font(.headline)
                Spacer()
                Button("Catalog") {
                    isCatalogPresented = true
                }
                .controlSize(.small)
                Button("Import") {
                    isImportingTheme = true
                }
                .controlSize(.small)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(appModel.allThemes) { theme in
                    ThemeCard(theme: theme, isSelected: tab.appearance.themeID == theme.id)
                        .onTapGesture {
                            windowModel.applyTheme(theme, to: tab)
                        }
                        .onHover { isHovering in
                            if isHovering {
                                windowModel.beginThemePreview(theme)
                            } else {
                                windowModel.endThemePreview()
                            }
                        }
                }
            }
        }
    }

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Fonts", systemImage: "textformat")
                .font(.headline)

            Picker("ASCII", selection: asciiFontBinding) {
                ForEach(fontPickerOptions, id: \.self) { fontName in
                    Text(fontName).tag(fontName)
                }
            }

            Picker("Non-ASCII", selection: nonASCIIFontBinding) {
                ForEach(fontPickerOptions, id: \.self) { fontName in
                    Text(fontName).tag(fontName)
                }
            }

            LabeledSlider(title: "Font Size", value: fontSizeBinding, range: 10...24)
            LabeledSlider(title: "Line Height", value: lineHeightBinding, range: 1...1.8)
            LabeledSlider(title: "Letter Spacing", value: letterSpacingBinding, range: -0.5...2)
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Providers", systemImage: "network")
                .font(.headline)

            Picker("Provider", selection: providerBinding) {
                ForEach(appModel.availableProviders) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .onChange(of: tab.appearance.aiProvider) { newValue in
                selectedProviderID = newValue ?? ""
            }
            .onAppear {
                selectedProviderID = tab.appearance.aiProvider ?? ""
            }

            Picker("Model", selection: modelBinding) {
                ForEach(currentProvider?.models ?? [], id: \.id) { model in
                    Text(model.name.isEmpty ? model.id : model.name).tag(model.id)
                }
            }
            // Force refresh when provider changes
            .id("model-picker-\(selectedProviderID)")

            if let selectedProvider {
                HStack {
                    Text(selectedProvider.endpoint)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Test") {
                        Task {
                            await appModel.testConnection(for: selectedProvider)
                        }
                    }
                }

                if selectedProvider.authType != .none {
                    HStack(spacing: 6) {
                        SecureField("API Key", text: $quickAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        Button(quickKeySaved ? "Saved" : "Save") {
                            guard !quickAPIKey.isEmpty else { return }
                            try? appModel.upsertProvider(selectedProvider, secret: quickAPIKey)
                            quickAPIKey = ""
                            quickKeySaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { quickKeySaved = false }
                        }
                        .disabled(quickAPIKey.isEmpty)
                        .controlSize(.small)
                    }
                }
            }

            if let providerStatusMessage = appModel.providerStatusMessage {
                Text(providerStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Chat Model Selection
            Text("Chat Mode Model")
                .font(.system(size: 12, weight: .semibold))
            
            Picker("Chat Provider", selection: chatProviderBinding) {
                Text("Same as Default").tag("")
                ForEach(appModel.availableProviders) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            
            Picker("Chat Model", selection: chatModelBinding) {
                Text("Same as Default").tag("")
                ForEach(currentChatProvider?.models ?? [], id: \.id) { model in
                    Text(model.name.isEmpty ? model.id : model.name).tag(model.id)
                }
            }
            .id("chat-model-picker-\(tab.appearance.chatProvider ?? "")")
            .disabled(tab.appearance.chatProvider?.isEmpty ?? true)

            if let chatProv = currentChatProvider, let chatID = tab.appearance.chatProvider, !chatID.isEmpty {
                let chatUsesSameProviderAsDefault =
                    tab.appearance.aiProvider.map { $0 == chatID } ?? false
                if chatUsesSameProviderAsDefault, chatProv.authType != .none, chatProv.authType != .oauthToken {
                    Text("Chat mode uses the same provider — use the API key field above.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if chatProv.authType == .oauthToken {
                    Text("Sign in to \(chatProv.name) under Settings → Providers to use chat mode.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if chatProv.authType != .none {
                    HStack(spacing: 6) {
                        SecureField("API key (chat mode)", text: $quickChatAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        Button(quickChatKeySaved ? "Saved" : "Save") {
                            guard !quickChatAPIKey.isEmpty else { return }
                            try? appModel.upsertProvider(chatProv, secret: quickChatAPIKey)
                            quickChatAPIKey = ""
                            quickChatKeySaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { quickChatKeySaved = false }
                        }
                        .disabled(quickChatAPIKey.isEmpty)
                        .controlSize(.small)
                    }
                    Text("Stored in Keychain for this provider (same as Settings).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Layout", systemImage: "rectangle.inset.filled")
                .font(.headline)

            LabeledSlider(title: "Opacity", value: opacityBinding, range: 0.3...1)
            VStack(alignment: .leading, spacing: 4) {
                LabeledSlider(title: "Frost", value: blurBinding, range: 0...1)
                Text("Background material only. 0 is still fully visible; use Opacity to dim the pane.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Cursor", selection: cursorStyleBinding) {
                ForEach(CursorStyle.allCases) { cursorStyle in
                    Text(cursorStyle.rawValue.capitalized).tag(cursorStyle)
                }
            }

            LabeledSlider(title: "Padding", value: paddingBinding, range: 0...32)
            LabeledSlider(title: "Scrollback", value: scrollbackBinding, range: 1_000...20_000, step: 500)
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Agents", systemImage: "bolt")
                .font(.headline)

            Picker("Default Agent", selection: Binding(
                get: { appModel.defaultAgentID ?? appModel.availableAgents.first?.id ?? "" },
                set: { appModel.setDefaultAgent($0) }
            )) {
                ForEach(appModel.availableAgents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }

            ForEach(appModel.availableAgents) { agent in
                let status = appModel.agentStatuses[agent.id]
                HStack {
                    Circle()
                        .fill((status?.isInstalled ?? false) ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(agent.name)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if !(status?.isInstalled ?? false) {
                        Text("Install: \(agent.installHint)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MCP Servers", systemImage: "server.rack")
                .font(.headline)

            ForEach(appModel.availableMCPServers) { server in
                let snapshot = appModel.mcpSnapshots[server.id]
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(statusColor(snapshot?.status ?? .stopped))
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(server.name)
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text("\(snapshot?.toolCount ?? 0) tools")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        if let lastError = snapshot?.lastError {
                            Text(lastError)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        if let logs = snapshot?.recentLogs, let lastLog = logs.last, !lastLog.isEmpty {
                            Text(lastLog)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        HStack {
                            Button("Start") {
                                appModel.startMCPServer(server, cwd: tab.currentWorkingDirectory)
                            }
                            Button("Stop") {
                                appModel.stopMCPServer(server)
                            }
                            Button("Restart") {
                                appModel.restartMCPServer(server, cwd: tab.currentWorkingDirectory)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10, weight: .medium))
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Divider()

            Text("Add Custom SSE Server")
                .font(.system(size: 12, weight: .semibold))
            TextField("ID", text: $draftMCPServer.id)
            TextField("Name", text: $draftMCPServer.name)
            TextField("Endpoint URL", text: $draftMCPServer.endpoint)
            Toggle("Auto-start", isOn: $draftMCPServer.autoStart)
            Picker("Scope", selection: $draftMCPServer.scope) {
                ForEach(MCPScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            Button("Save SSE Server") {
                appModel.upsertMCPServer(draftMCPServer.toDefinition())
                draftMCPServer = MCPDraft()
            }
            .disabled(draftMCPServer.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftMCPServer.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Project Profile", systemImage: "folder.badge.gearshape")
                .font(.headline)

            Text(tab.currentWorkingDirectory?.path ?? "No working directory reported yet.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("`.termconfig` is read from the current working directory and can override the active profile, provider, and model.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var activeProfileBinding: Binding<UUID> {
        Binding(
            get: { tab.profileID ?? appModel.profiles.first?.id ?? UUID() },
            set: { newValue in
                guard let profile = appModel.profiles.first(where: { $0.id == newValue }) else { return }
                windowModel.applyProfile(profile, to: tab)
            }
        )
    }

    private var defaultProfileBinding: Binding<UUID> {
        Binding(
            get: { appModel.defaultProfileID ?? appModel.profiles.first?.id ?? UUID() },
            set: { newValue in appModel.setDefaultProfile(newValue) }
        )
    }

    private var asciiFontBinding: Binding<String> {
        Binding(get: { tab.appearance.fontName }, set: { value in mutateAppearance { $0.fontName = value } })
    }

    private var nonASCIIFontBinding: Binding<String> {
        Binding(get: { tab.appearance.nonASCIIFontName }, set: { value in mutateAppearance { $0.nonASCIIFontName = value } })
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(get: { tab.appearance.fontSize }, set: { value in mutateAppearance { $0.fontSize = value } })
    }

    private var lineHeightBinding: Binding<Double> {
        Binding(get: { tab.appearance.lineHeight }, set: { value in mutateAppearance { $0.lineHeight = value } })
    }

    private var letterSpacingBinding: Binding<Double> {
        Binding(get: { tab.appearance.letterSpacing }, set: { value in mutateAppearance { $0.letterSpacing = value } })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { tab.appearance.opacity }, set: { value in mutateAppearance { $0.opacity = value } })
    }

    private var blurBinding: Binding<Double> {
        Binding(get: { tab.appearance.blur }, set: { value in mutateAppearance { $0.blur = value } })
    }

    private var cursorStyleBinding: Binding<CursorStyle> {
        Binding(get: { tab.appearance.cursorStyle }, set: { value in mutateAppearance { $0.cursorStyle = value } })
    }

    private var paddingBinding: Binding<Double> {
        Binding(
            get: { tab.appearance.padding.left },
            set: { value in
                mutateAppearance {
                    $0.padding.left = value
                    $0.padding.right = value
                    $0.padding.top = value
                    $0.padding.bottom = value
                }
            }
        )
    }

    private var scrollbackBinding: Binding<Double> {
        Binding(get: { Double(tab.appearance.scrollbackSize) }, set: { value in mutateAppearance { $0.scrollbackSize = Int(value.rounded()) } })
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { tab.appearance.aiProvider ?? appModel.availableProviders.first?.id ?? "" },
            set: { value in
                selectedProviderID = value
                let modelID = appModel.provider(for: value)?.models.first?.id ?? ""
                windowModel.assignModel(providerID: value, modelID: modelID, to: tab)
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { tab.appearance.aiModel ?? selectedProvider?.models.first?.id ?? "" },
            set: { value in
                guard let providerID = tab.appearance.aiProvider else { return }
                windowModel.assignModel(providerID: providerID, modelID: value, to: tab)
            }
        )
    }

    private var chatProviderBinding: Binding<String> {
        Binding(
            get: { tab.appearance.chatProvider ?? "" },
            set: { value in
                mutateAppearance { 
                    $0.chatProvider = value.isEmpty ? nil : value
                    $0.chatModel = nil // Reset model when provider changes
                }
            }
        )
    }

    private var chatModelBinding: Binding<String> {
        Binding(
            get: { tab.appearance.chatModel ?? "" },
            set: { value in
                mutateAppearance { $0.chatModel = value.isEmpty ? nil : value }
            }
        )
    }

    private var currentChatProvider: ModelProvider? {
        appModel.provider(for: tab.appearance.chatProvider)
    }

    private var selectedProvider: ModelProvider? {
        appModel.provider(for: tab.appearance.aiProvider)
    }
    
    private var currentProvider: ModelProvider? {
        appModel.provider(for: selectedProviderID.isEmpty ? tab.appearance.aiProvider : selectedProviderID)
    }

    private func mutateAppearance(_ update: (inout TerminalAppearance) -> Void) {
        var appearance = tab.appearance
        update(&appearance)
        tab.appearance = appearance
        tab.markStateChanged()
        
        // Persist changes to the active profile
        if let profileID = tab.profileID,
           let profileIndex = appModel.profiles.firstIndex(where: { $0.id == profileID }) {
            appModel.profiles[profileIndex].appearance = appearance
            appModel.persistProfilesPublic()
        }
    }

    private func statusColor(_ status: MCPServerStatus) -> Color {
        switch status {
        case .running: return .green
        case .error: return .red
        case .stopped: return .gray
        }
    }
}
