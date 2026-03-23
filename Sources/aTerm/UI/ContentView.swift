import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var windowModel: WindowModel
    @State private var isSidebarVisible = false

    init(appModel: AppModel) {
        _windowModel = StateObject(wrappedValue: WindowModel(appModel: appModel))
    }

    var body: some View {
        Group {
            if appModel.isOnboardingPresented {
                OnboardingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            } else {
                mainContent
            }
        }
        .environmentObject(windowModel)
        .modifier(WindowCommandHandler(windowModel: windowModel))
    }

    private var mainContent: some View {
        ZStack {
            WindowFrameRestorer()
                .frame(width: 0, height: 0)

            HSplitView {
                VStack(spacing: 0) {
                    if appModel.showNerdFontBanner {
                        NerdFontBanner()
                    }

                    WindowTabStripView(windowModel: windowModel, isSidebarVisible: $isSidebarVisible)

                    Divider()

                    if let selectedTab = windowModel.selectedTab {
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

                if isSidebarVisible, let selectedTab = windowModel.selectedTab {
                    AppearanceSidebarView(tab: selectedTab)
                        .frame(minWidth: 320)
                }
            }

            if windowModel.isModelPickerPresented {
                ModelPickerOverlay()
            }

            if windowModel.isCommandPalettePresented {
                CommandPaletteOverlay()
            }

            if windowModel.isAgentPickerPresented {
                AgentPickerOverlay()
            }
        }
    }
}

/// Handles menu command notifications for the focused window (part 1: tab commands)
private struct WindowCommandHandler: ViewModifier {
    @ObservedObject var windowModel: WindowModel

    func body(content: Content) -> some View {
        content
            .onAppear { windowModel.restoreOrCreateInitialTabs() }
            .onReceive(NotificationCenter.default.publisher(for: .aTermNewTab)) { _ in windowModel.createTabAndSelect() }
            .onReceive(NotificationCenter.default.publisher(for: .aTermCloseTab)) { _ in windowModel.closeSelectedTab() }
            .onReceive(NotificationCenter.default.publisher(for: .aTermToggleModelPicker)) { _ in windowModel.toggleModelPicker() }
            .onReceive(NotificationCenter.default.publisher(for: .aTermToggleSearch)) { _ in windowModel.toggleSearchBar() }
            .onReceive(NotificationCenter.default.publisher(for: .aTermClearScrollback)) { _ in windowModel.clearSelectedScrollback() }
            .modifier(WindowCommandHandler2(windowModel: windowModel))
    }
}

/// Handles menu command notifications for the focused window (part 2: split/palette/URL)
private struct WindowCommandHandler2: ViewModifier {
    @ObservedObject var windowModel: WindowModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .aTermSplitH)) { _ in windowModel.splitSelectedPane(.horizontal) }
            .onReceive(NotificationCenter.default.publisher(for: .aTermSplitV)) { _ in windowModel.splitSelectedPane(.vertical) }
            .onReceive(NotificationCenter.default.publisher(for: .aTermCommandPalette)) { _ in windowModel.isCommandPalettePresented.toggle() }
            .onReceive(NotificationCenter.default.publisher(for: .aTermOpenDirectory)) { n in
                if let url = n.object as? URL { windowModel.createTabAndSelect(workingDirectory: url) }
            }
            .onOpenURL { url in
                guard url.scheme == "aterm", url.host == "open",
                      let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let path = c.queryItems?.first(where: { $0.name == "path" })?.value else { return }
                windowModel.createTabAndSelect(workingDirectory: URL(fileURLWithPath: path))
            }
            .onReceive(NotificationCenter.default.publisher(for: .aTermSaveOutput)) { _ in
                guard let pane = windowModel.selectedTab?.activePane else { return }
                let text = pane.exportScrollbackText()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.plainText]
                panel.nameFieldStringValue = "terminal-output.txt"
                panel.begin { r in
                    guard r == .OK, let url = panel.url else { return }
                    try? text.write(to: url, atomically: true, encoding: .utf8)
                }
            }
    }
}

/// Tab strip that uses WindowModel for per-window tabs
private struct WindowTabStripView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var windowModel: WindowModel
    @Binding var isSidebarVisible: Bool

    // This string is set at compile time — check it matches your latest build
    private static let buildStamp = "b:2026-03-23T12:50"

    var body: some View {
        HStack(spacing: 0) {
            Text(Self.buildStamp)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)

            ForEach(windowModel.tabs) { tab in
                TabButton(tab: tab, isSelected: windowModel.selectedTabID == tab.id) {
                    windowModel.selectTab(id: tab.id)
                } onClose: {
                    windowModel.closeTab(id: tab.id)
                }
            }

            Spacer()

            Button {
                windowModel.createTabAndSelect()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Button {
                windowModel.openAgentPicker()
            } label: {
                Image(systemName: "bolt")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Button {
                isSidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSidebarVisible ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .help("Toggle Sidebar")
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TabButton: View {
    @ObservedObject var tab: TerminalTabViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if tab.hasUnreadOutput {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
            if tab.isAgentTab {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Text(tab.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 0.6 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
            // Force NSView recreation when theme or buffer changes
            .id("\(pane.appearance.themeID)-\(pane.id)")
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
    @EnvironmentObject private var windowModel: WindowModel
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
                windowModel.restartAgentPane(pane)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}

private struct SmartInputBar: View {
    @EnvironmentObject private var windowModel: WindowModel
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
                    windowModel.submitInput(for: pane)
                }

            Button("Send") {
                windowModel.submitInput(for: pane)
            }
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
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var pane: TerminalPaneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("⚡ Generated command")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    pane.aiShellState = AIShellState()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss (Esc)")
            }

            if pane.aiShellState.isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else if pane.aiShellState.isEditing {
                TextField("Generated command", text: $pane.aiShellState.generatedCommand, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            } else {
                Text(pane.aiShellState.generatedCommand)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack {
                Button(pane.aiShellState.isEditing ? "Done" : "Edit") {
                    pane.aiShellState.isEditing.toggle()
                }
                .disabled(pane.aiShellState.isGenerating)

                Spacer()

                Button("Run ↵") {
                    windowModel.runGeneratedCommand(for: pane)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(pane.aiShellState.isGenerating || pane.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .onExitCommand {
            pane.aiShellState = AIShellState()
        }
    }
}

private struct QueryResponseCard: View {
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var pane: TerminalPaneViewModel
    @State private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("?")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text(pane.queryResponse.isStreaming ? "Streaming answer..." : "Answer")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !pane.queryResponse.isStreaming {
                    Button {
                        isCollapsed.toggle()
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Expand" : "Collapse")

                    Button {
                        pane.queryResponse = QueryResponseState()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }

            if !isCollapsed {
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
                                windowModel.runQuerySuggestion(suggestion, for: pane)
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
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
    @EnvironmentObject private var windowModel: WindowModel
    let input: String
    @ObservedObject var pane: TerminalPaneViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Did you mean:")
                .font(.system(size: 12, weight: .medium))
            Button("Run as shell command") {
                windowModel.resolveDisambiguation(as: .terminal, for: pane)
            }
            Button("Answer as query") {
                windowModel.resolveDisambiguation(as: .query, for: pane)
            }
            Button("Generate shell command") {
                windowModel.resolveDisambiguation(as: .aiToShell, for: pane)
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
    @EnvironmentObject private var windowModel: WindowModel
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
                        windowModel.dismissModelPicker()
                    }
                }

                TextField("Search providers and models", text: $query)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredItems, id: \.model.id) { item in
                            Button {
                                windowModel.assignModel(providerID: item.provider.id, modelID: item.model.id)
                                windowModel.dismissModelPicker()
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
            windowModel.dismissModelPicker()
        }
    }
}

private struct AgentPickerOverlay: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @State private var draftAgent = AgentDraft()

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Agents")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        windowModel.closeAgentPicker()
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
                                    windowModel.launchAgent(agent)
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
            windowModel.closeAgentPicker()
        }
    }
}

private struct CommandPaletteOverlay: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @State private var query = ""

    private struct PaletteAction: Identifiable {
        let id: String
        let label: String
        let icon: String
        let action: () -> Void
    }

    private var actions: [PaletteAction] {
        let all: [PaletteAction] = [
            .init(id: "new-tab", label: "New Tab", icon: "plus.square") { windowModel.createTabAndSelect(); dismiss() },
            .init(id: "close-tab", label: "Close Tab", icon: "xmark.square") { windowModel.closeSelectedTab(); dismiss() },
            .init(id: "model-picker", label: "Switch Model", icon: "brain") { dismiss(); windowModel.toggleModelPicker() },
            .init(id: "agent-picker", label: "Launch Agent", icon: "bolt") { dismiss(); windowModel.openAgentPicker() },
            .init(id: "find", label: "Find in Scrollback", icon: "magnifyingglass") { windowModel.toggleSearchBar(); dismiss() },
            .init(id: "clear", label: "Clear Scrollback", icon: "trash") { windowModel.clearSelectedScrollback(); dismiss() },
            .init(id: "split-h", label: "Split Horizontally", icon: "rectangle.split.2x1") { windowModel.splitSelectedPane(.horizontal); dismiss() },
            .init(id: "split-v", label: "Split Vertically", icon: "rectangle.split.1x2") { windowModel.splitSelectedPane(.vertical); dismiss() },
            .init(id: "shell-integration", label: "Install Shell Integration", icon: "terminal") { appModel.installShellIntegration(); dismiss() },
        ]
        // Add theme switching actions
        + appModel.allThemes.map { theme in
            PaletteAction(id: "theme-\(theme.id)", label: "Theme: \(theme.name)", icon: "paintbrush") {
                windowModel.applyTheme(theme)
                dismiss()
            }
        }
        // Add agent launch actions
        + appModel.availableAgents.filter { appModel.agentStatuses[$0.id]?.isInstalled == true }.map { agent in
            PaletteAction(id: "agent-\(agent.id)", label: "Launch \(agent.name)", icon: "bolt.circle") {
                windowModel.launchAgent(agent)
                dismiss()
            }
        }

        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter { $0.label.lowercased().contains(q) }
    }

    private func dismiss() {
        windowModel.isCommandPalettePresented = false
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
