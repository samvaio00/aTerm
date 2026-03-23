import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSidebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var tab: TerminalTabViewModel
    @State private var isImportingTheme = false
    @State private var newProfileName = ""
    @State private var draftProvider = ProviderDraft()
    @State private var isSavingProvider = false
    @State private var draftMCPServer = MCPDraft()

    private var availableFonts: [String] {
        FontSupport.monospaceFontNames()
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
                    appModel.createProfileFromSelectedTab(named: name)
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
                Button("Import") {
                    isImportingTheme = true
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(appModel.allThemes) { theme in
                    ThemeCard(theme: theme, isSelected: tab.appearance.themeID == theme.id)
                        .onTapGesture {
                            appModel.applyTheme(theme, to: tab)
                        }
                        .onHover { isHovering in
                            if isHovering {
                                appModel.beginThemePreview(theme)
                            } else {
                                appModel.endThemePreview()
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
                ForEach(availableFonts, id: \.self) { fontName in
                    Text(fontName).tag(fontName)
                }
            }

            Picker("Non-ASCII", selection: nonASCIIFontBinding) {
                ForEach(availableFonts, id: \.self) { fontName in
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

            Picker("Model", selection: modelBinding) {
                ForEach(selectedProvider?.models ?? [], id: \.id) { model in
                    Text(model.name.isEmpty ? model.id : model.name).tag(model.id)
                }
            }

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
            }

            if let providerStatusMessage = appModel.providerStatusMessage {
                Text(providerStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Add or Update Provider")
                .font(.system(size: 12, weight: .semibold))

            TextField("Slug", text: $draftProvider.id)
            TextField("Name", text: $draftProvider.name)
            TextField("Endpoint URL", text: $draftProvider.endpoint)

            Picker("Auth", selection: $draftProvider.authType) {
                ForEach(AuthType.allCases) { authType in
                    Text(authType.rawValue).tag(authType)
                }
            }

            Picker("Format", selection: $draftProvider.apiFormat) {
                ForEach(APIFormat.allCases) { apiFormat in
                    Text(apiFormat.rawValue).tag(apiFormat)
                }
            }

            SecureField("API Key / Token", text: $draftProvider.secret)

            HStack {
                TextField("Model ID", text: $draftProvider.modelID)
                TextField("Display Name", text: $draftProvider.modelName)
                Button("Add Model") {
                    draftProvider.addModel()
                }
            }

            ForEach(draftProvider.models, id: \.id) { model in
                HStack {
                    Text(model.name.isEmpty ? model.id : model.name)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button("Remove") {
                        draftProvider.models.removeAll(where: { $0.id == model.id })
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button(isSavingProvider ? "Saving..." : "Save Provider") {
                    saveDraftProvider()
                }
                .disabled(isSavingProvider || draftProvider.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let selectedProvider, !selectedProvider.isBuiltin {
                    Button("Delete") {
                        appModel.deleteProvider(selectedProvider.id)
                    }
                }
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Layout", systemImage: "rectangle.inset.filled")
                .font(.headline)

            LabeledSlider(title: "Opacity", value: opacityBinding, range: 0.3...1)
            LabeledSlider(title: "Blur", value: blurBinding, range: 0...1)

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

    private var activeProfileBinding: Binding<UUID> {
        Binding(
            get: { tab.profileID ?? appModel.profiles.first?.id ?? UUID() },
            set: { newValue in
                guard let profile = appModel.profiles.first(where: { $0.id == newValue }) else { return }
                appModel.applyProfile(profile, to: tab)
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
                let modelID = appModel.provider(for: value)?.models.first?.id ?? ""
                appModel.assignModel(providerID: value, modelID: modelID, to: tab)
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { tab.appearance.aiModel ?? selectedProvider?.models.first?.id ?? "" },
            set: { value in
                guard let providerID = tab.appearance.aiProvider else { return }
                appModel.assignModel(providerID: providerID, modelID: value, to: tab)
            }
        )
    }

    private var selectedProvider: ModelProvider? {
        appModel.provider(for: tab.appearance.aiProvider)
    }

    private func mutateAppearance(_ update: (inout TerminalAppearance) -> Void) {
        var appearance = tab.appearance
        update(&appearance)
        tab.appearance = appearance
        tab.markStateChanged()
    }

    private func saveDraftProvider() {
        let provider = draftProvider.toProvider()
        isSavingProvider = true
        defer { isSavingProvider = false }
        do {
            try appModel.upsertProvider(provider, secret: draftProvider.secret.isEmpty ? nil : draftProvider.secret)
            draftProvider = ProviderDraft()
        } catch {
            appModel.providerStatusMessage = error.localizedDescription
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

private struct ProviderDraft {
    var id = ""
    var name = ""
    var endpoint = ""
    var authType: AuthType = .bearer
    var apiFormat: APIFormat = .openAICompatible
    var secret = ""
    var modelID = ""
    var modelName = ""
    var models: [ModelDefinition] = []

    mutating func addModel() {
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        models.append(.init(id: trimmedID, name: modelName, contextWindow: 128_000, supportsStreaming: true))
        modelID = ""
        modelName = ""
    }

    func toProvider() -> ModelProvider {
        ModelProvider(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            authType: authType,
            apiFormat: apiFormat,
            models: models,
            customHeaders: [:],
            isBuiltin: false
        )
    }
}

private struct MCPDraft {
    var id = ""
    var name = ""
    var endpoint = ""
    var autoStart = false
    var scope: MCPScope = .global

    func toDefinition() -> MCPServerDefinition {
        MCPServerDefinition(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            transport: .sse,
            command: nil,
            args: [],
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            autoStart: autoStart,
            scope: scope,
            isBuiltin: false
        )
    }
}

private struct ThemeCard: View {
    let theme: TerminalTheme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(theme.palette.background.nsColor))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("$ git status")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Text("clean")
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(theme.palette.ansi[10].nsColor))
                    }
                    .foregroundStyle(Color(theme.palette.foreground.nsColor))
                    .padding(8)
                }
                .frame(height: 72)

            Text(theme.name)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
        .font(.system(size: 12, weight: .medium))
    }

    private var formattedValue: String {
        if step >= 1 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }
}
