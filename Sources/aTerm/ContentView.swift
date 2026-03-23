import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack {
            HSplitView {
                VStack(spacing: 0) {
                    if appModel.showNerdFontBanner {
                        NerdFontBanner()
                    }

                    TabStripView()

                    Divider()

                    if let selectedTab = appModel.selectedTab {
                        TerminalWorkspace(tab: selectedTab)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "terminal")
                                .font(.system(size: 28, weight: .medium))
                            Text("No Tabs")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    }
                }

                if let selectedTab = appModel.selectedTab {
                    AppearanceSidebarView(tab: selectedTab)
                        .frame(minWidth: 320)
                }
            }

            if appModel.isModelPickerPresented {
                ModelPickerOverlay()
            }

            if appModel.isCommandPalettePresented {
                CommandPaletteOverlay()
            }

            if appModel.isAgentPickerPresented {
                AgentPickerOverlay()
            }

            if appModel.isOnboardingPresented {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    OnboardingView()
                }
            }
        }
    }
}

private struct TerminalPane: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var pane: TerminalPaneViewModel
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(pane.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(pane.modeIndicatorText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(pane.profileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(pane.activeProviderName) · \(pane.activeModelName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(pane.statusText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            TerminalView(
                buffer: pane.terminalBuffer,
                appearance: pane.appearance,
                theme: appModel.theme(for: pane.appearance.themeID),
                searchQuery: pane.searchQuery,
                isRegexSearchEnabled: pane.isRegexSearchEnabled,
                searchMatches: pane.searchMatches,
                currentSearchIndex: pane.currentSearchIndex,
                onInput: pane.handleInput(_:),
                onResize: pane.updateTerminalSize(columns:rows:),
                onBecomeActive: onSelect
            )
            // bufferVersion change triggers updateNSView via @Published
            .onChange(of: pane.bufferVersion) { _ in }
            .background(Color(appModel.theme(for: pane.appearance.themeID).palette.background.nsColor))

            if pane.isSearchPresented {
                ScrollbackSearchBar(pane: pane)
            }

            if let banner = pane.agentExitBanner {
                AgentExitBanner(pane: pane, text: banner)
            }

            if case let .waitingForDisambiguation(input) = pane.submissionState {
                DisambiguationBar(input: input, pane: pane)
            }

            if !pane.aiShellState.generatedCommand.isEmpty || pane.aiShellState.isGenerating {
                AIShellCard(pane: pane)
            }

            if !pane.queryResponse.text.isEmpty || pane.queryResponse.isStreaming {
                QueryResponseCard(pane: pane)
            }

            SmartInputBar(pane: pane)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .task {
            pane.startIfNeeded()
        }
    }
}

private struct TerminalWorkspace: View {
    @ObservedObject var tab: TerminalTabViewModel

    var body: some View {
        paneLayout(for: tab.panes)
    }

    @ViewBuilder
    private func paneLayout(for panes: [TerminalPaneViewModel]) -> some View {
        switch panes.count {
        case 0:
            Color.black
        case 1:
            paneView(panes[0])
        case 2:
            if tab.splitOrientation == .vertical {
                VSplitView {
                    paneView(panes[0])
                    paneView(panes[1])
                }
            } else {
                HSplitView {
                    paneView(panes[0])
                    paneView(panes[1])
                }
            }
        case 3, 4:
            if tab.splitOrientation == .vertical {
                VSplitView {
                    row(for: Array(panes.prefix(2)))
                    row(for: Array(panes.dropFirst(2)))
                }
            } else {
                HSplitView {
                    column(for: Array(panes.prefix(2)))
                    column(for: Array(panes.dropFirst(2)))
                }
            }
        default:
            paneView(panes[0])
        }
    }

    @ViewBuilder
    private func row(for panes: [TerminalPaneViewModel]) -> some View {
        HSplitView {
            ForEach(panes) { pane in
                paneView(pane)
            }
        }
    }

    @ViewBuilder
    private func column(for panes: [TerminalPaneViewModel]) -> some View {
        VSplitView {
            ForEach(panes) { pane in
                paneView(pane)
            }
        }
    }

    private func paneView(_ pane: TerminalPaneViewModel) -> some View {
        TerminalPane(
            pane: pane,
            isActive: tab.activePaneID == pane.id,
            onSelect: { tab.selectPane(id: pane.id) },
            onClose: tab.panes.count > 1 ? { tab.closePane(id: pane.id) } : nil
        )
    }
}

private struct ScrollbackSearchBar: View {
    @ObservedObject var pane: TerminalPaneViewModel

    var body: some View {
        HStack(spacing: 10) {
            TextField("Find in scrollback", text: $pane.searchQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: pane.searchQuery) { _ in
                    pane.refreshSearch()
                }
            Toggle("Regex", isOn: $pane.isRegexSearchEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .onChange(of: pane.isRegexSearchEnabled) { _ in
                    pane.refreshSearch()
                }
            Text(pane.searchMatchCount == 0 ? "0 matches" : "\(pane.currentSearchIndex + 1) of \(pane.searchMatchCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Prev") {
                pane.previousSearchMatch()
            }
            Button("Next") {
                pane.nextSearchMatch()
            }
            Button("Close") {
                pane.isSearchPresented = false
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct AgentExitBanner: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var pane: TerminalPaneViewModel
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Toggle("Auto-restart", isOn: $pane.isAgentAutoRestartEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Button("Restart") {
                appModel.restartAgentPane(pane)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}

private struct SmartInputBar: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var pane: TerminalPaneViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text(inputPrefix)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            TextField("Enter a command, natural language request, or question", text: $pane.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .onSubmit {
                    appModel.submitInput(for: pane)
                }

            Button("Send") {
                appModel.submitInput(for: pane)
            }
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var inputPrefix: String {
        switch pane.modeIndicatorText {
        case InputMode.aiToShell.rawValue:
            return "⚡"
        case InputMode.query.rawValue:
            return "?"
        default:
            return "$"
        }
    }
}

private struct AIShellCard: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var pane: TerminalPaneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generated command")
                .font(.system(size: 12, weight: .semibold))

            if pane.aiShellState.isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else {
                TextField("Generated command", text: $pane.aiShellState.generatedCommand, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            HStack {
                Button(pane.aiShellState.isEditing ? "Done Editing" : "Edit") {
                    pane.aiShellState.isEditing.toggle()
                }
                .disabled(pane.aiShellState.isGenerating)

                Spacer()

                Button("Run") {
                    appModel.runGeneratedCommand(for: pane)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pane.aiShellState.isGenerating || pane.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }
}

private struct QueryResponseCard: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var pane: TerminalPaneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("?")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text(pane.queryResponse.isStreaming ? "Streaming answer..." : "Answer")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

            ScrollView {
                Text(pane.queryResponse.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)

            if !pane.queryResponse.suggestions.isEmpty {
                ForEach(pane.queryResponse.suggestions) { suggestion in
                    HStack {
                        Text(suggestion.command)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(2)
                        Spacer()
                        Button("Run") {
                            appModel.runQuerySuggestion(suggestion, for: pane)
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }
}

private struct DisambiguationBar: View {
    @EnvironmentObject private var appModel: AppModel
    let input: String
    @ObservedObject var pane: TerminalPaneViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Did you mean:")
                .font(.system(size: 12, weight: .medium))
            Button("Run as shell command") {
                appModel.resolveDisambiguation(as: .terminal, for: pane)
            }
            Button("Answer as query") {
                appModel.resolveDisambiguation(as: .query, for: pane)
            }
            Button("Generate shell command") {
                appModel.resolveDisambiguation(as: .aiToShell, for: pane)
            }
            Spacer()
            Text(input)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct NerdFontBanner: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Nerd Font recommended for Powerlevel10k and oh-my-zsh glyphs.")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Dismiss") {
                appModel.dismissNerdFontBanner()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ModelPickerOverlay: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var query = ""

    var filteredItems: [(provider: ModelProvider, model: ModelDefinition)] {
        guard !query.isEmpty else { return appModel.modelPickerItems }
        return appModel.modelPickerItems.filter {
            $0.provider.name.localizedCaseInsensitiveContains(query) ||
            $0.model.name.localizedCaseInsensitiveContains(query) ||
            $0.model.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Model Picker")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        appModel.dismissModelPicker()
                    }
                }

                TextField("Search providers and models", text: $query)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredItems, id: \.model.id) { item in
                            Button {
                                appModel.assignModel(providerID: item.provider.id, modelID: item.model.id)
                                appModel.dismissModelPicker()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.model.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("\(item.provider.name) · \(item.model.id)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .padding(18)
            .frame(width: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .onTapGesture {
            appModel.dismissModelPicker()
        }
    }
}

private struct AgentPickerOverlay: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var draftAgent = AgentDraft()

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Agents")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        appModel.closeAgentPicker()
                    }
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appModel.availableAgents) { agent in
                            let status = appModel.agentStatuses[agent.id]
                            HStack {
                                Circle()
                                    .fill((status?.isInstalled ?? false) ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text((status?.isInstalled ?? false) ? (status?.executablePath ?? agent.command) : agent.installHint)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button((status?.isInstalled ?? false) ? "Launch" : "Unavailable") {
                                    appModel.launchAgent(agent)
                                }
                                .disabled(!(status?.isInstalled ?? false))
                            }
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 260)

                Divider()

                Text("Add Custom Agent")
                    .font(.system(size: 12, weight: .semibold))
                TextField("ID", text: $draftAgent.id)
                TextField("Name", text: $draftAgent.name)
                TextField("Command", text: $draftAgent.command)
                TextField("Auth Env Var", text: $draftAgent.authEnvVar)
                TextField("Install Hint", text: $draftAgent.installHint)
                TextField("Args (space separated)", text: $draftAgent.args)

                HStack {
                    Button("Save Agent") {
                        appModel.upsertAgent(draftAgent.toDefinition())
                        draftAgent = AgentDraft()
                    }
                    .disabled(draftAgent.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftAgent.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
            }
            .padding(18)
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .onTapGesture {
            appModel.closeAgentPicker()
        }
    }
}

private struct CommandPaletteOverlay: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var query = ""

    private struct PaletteAction: Identifiable {
        let id: String
        let label: String
        let icon: String
        let action: () -> Void
    }

    private var actions: [PaletteAction] {
        let all: [PaletteAction] = [
            .init(id: "new-tab", label: "New Tab", icon: "plus.square") { appModel.createTabAndSelect(); dismiss() },
            .init(id: "close-tab", label: "Close Tab", icon: "xmark.square") { appModel.closeSelectedTab(); dismiss() },
            .init(id: "model-picker", label: "Switch Model", icon: "brain") { dismiss(); appModel.toggleModelPicker() },
            .init(id: "agent-picker", label: "Launch Agent", icon: "bolt") { dismiss(); appModel.openAgentPicker() },
            .init(id: "find", label: "Find in Scrollback", icon: "magnifyingglass") { appModel.toggleSearchBar(); dismiss() },
            .init(id: "clear", label: "Clear Scrollback", icon: "trash") { appModel.clearSelectedScrollback(); dismiss() },
            .init(id: "split-h", label: "Split Horizontally", icon: "rectangle.split.2x1") { appModel.splitSelectedPane(.horizontal); dismiss() },
            .init(id: "split-v", label: "Split Vertically", icon: "rectangle.split.1x2") { appModel.splitSelectedPane(.vertical); dismiss() },
            .init(id: "shell-integration", label: "Install Shell Integration", icon: "terminal") { appModel.installShellIntegration(); dismiss() },
        ]
        // Add theme switching actions
        + appModel.allThemes.map { theme in
            PaletteAction(id: "theme-\(theme.id)", label: "Theme: \(theme.name)", icon: "paintbrush") {
                appModel.applyTheme(theme)
                dismiss()
            }
        }
        // Add agent launch actions
        + appModel.availableAgents.filter { appModel.agentStatuses[$0.id]?.isInstalled == true }.map { agent in
            PaletteAction(id: "agent-\(agent.id)", label: "Launch \(agent.name)", icon: "bolt.circle") {
                appModel.launchAgent(agent)
                dismiss()
            }
        }

        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter { $0.label.lowercased().contains(q) }
    }

    private func dismiss() {
        appModel.isCommandPalettePresented = false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Type a command...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .onSubmit {
                            if let first = actions.first { first.action() }
                        }
                }
                .padding(12)

                Divider()

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(actions) { action in
                            Button {
                                action.action()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: action.icon)
                                        .frame(width: 20)
                                        .foregroundStyle(.secondary)
                                    Text(action.label)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(Color.primary.opacity(0.001)) // hit target
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
            .frame(width: 480)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onExitCommand { dismiss() }
    }
}

private struct AgentDraft {
    var id = ""
    var name = ""
    var command = ""
    var authEnvVar = ""
    var installHint = ""
    var args = ""

    func toDefinition() -> AgentDefinition {
        AgentDefinition(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            command: command.trimmingCharacters(in: .whitespacesAndNewlines),
            args: args.split(whereSeparator: \.isWhitespace).map(String.init),
            authEnvVar: authEnvVar.trimmingCharacters(in: .whitespacesAndNewlines),
            installCheck: "which \(command.trimmingCharacters(in: .whitespacesAndNewlines))",
            installHint: installHint.trimmingCharacters(in: .whitespacesAndNewlines),
            protocolType: .interactiveCLI,
            isBuiltin: false
        )
    }
}
