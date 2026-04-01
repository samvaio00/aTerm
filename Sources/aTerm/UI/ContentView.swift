import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var windowModel: WindowModel
    @State private var isSidebarVisible = false
    @State private var sidebarWidth: CGFloat = 320
    
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
        .onAppear {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private var mainContent: some View {
        ZStack {
            WindowFrameRestorer()
                .frame(width: 0, height: 0)
            
            // Main layout
            HStack(spacing: 0) {
                // Terminal area
                VStack(spacing: 0) {
                    // Banner
                    if appModel.showNerdFontBanner {
                        NerdFontBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Modern tab strip
                    ModernTabStrip(windowModel: windowModel, isSidebarVisible: $isSidebarVisible)
                    
                    SubtleDivider()
                    
                    // Terminal workspace
                    if let selectedTab = windowModel.selectedTab {
                        ModernTerminalWorkspace(tab: selectedTab)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyStateView(
                            icon: "terminal",
                            title: "No Tabs",
                            subtitle: "Press ⌘T to create a new tab"
                        )
                        .background(Color.black)
                    }
                }
                
                // Collapsible sidebar
                if isSidebarVisible, let selectedTab = windowModel.selectedTab {
                    ModernSidebar(tab: selectedTab)
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            
            // Overlays
            overlayGroup
        }
        .animation(DesignSystem.Animation.normal, value: isSidebarVisible)
        .animation(DesignSystem.Animation.normal, value: appModel.showNerdFontBanner)
    }
    
    @ViewBuilder
    private var overlayGroup: some View {
        // One branch only: multiple sibling `if`s become a TupleView that can sit full-size in the
        // ZStack and swallow clicks/keyboard even when every panel is closed.
        if windowModel.isModelPickerPresented {
            ModernModelPicker()
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if windowModel.isCommandPalettePresented {
            ModernCommandPalette()
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if windowModel.isAgentPickerPresented {
            ModernAgentPicker()
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

// MARK: - Window Command Handler

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

// MARK: - Modern Tab Strip

private struct ModernTabStrip: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var windowModel: WindowModel
    @Binding var isSidebarVisible: Bool
    
    private static let buildStamp = "b:2026-04-01-io"
    
    var body: some View {
        HStack(spacing: 0) {
            // Build stamp
            Text(Self.buildStamp)
                .font(DesignSystem.Typography.mono(9))
                .foregroundStyle(.tertiary)
                .padding(.leading, DesignSystem.Spacing.m)
            
            // Tab buttons
            HStack(spacing: 4) {
                ForEach(windowModel.tabs) { tab in
                    ModernTabButton(
                        tab: tab,
                        isSelected: windowModel.selectedTabID == tab.id
                    ) {
                        windowModel.selectTab(id: tab.id)
                    } onClose: {
                        windowModel.closeTab(id: tab.id)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.s)
            
            Spacer()
            
            // Toolbar actions
            HStack(spacing: DesignSystem.Spacing.xs) {
                ToolbarButton(icon: "plus", tooltip: "New Tab (⌘T)") {
                    windowModel.createTabAndSelect()
                }
                
                ToolbarButton(icon: "bolt", tooltip: "Launch Agent") {
                    windowModel.openAgentPicker()
                }
                
                ToolbarButton(
                    icon: "sidebar.right",
                    tooltip: "Toggle Sidebar (⌘⌥S)",
                    isActive: isSidebarVisible
                ) {
                    isSidebarVisible.toggle()
                }
            }
            .padding(.trailing, DesignSystem.Spacing.m)
        }
        .frame(height: DesignSystem.Layout.tabHeight)
        .background(DesignSystem.Colors.backgroundPrimary)
    }
}

private struct ModernTabButton: View {
    @ObservedObject var tab: TerminalTabViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Status indicator
            if tab.hasUnreadOutput {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }
            
            // Agent icon
            if tab.isAgentTab {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            
            // Title
            Text(tab.title)
                .font(DesignSystem.Typography.defaultFont(12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(isSelected || isHovered ? 0.6 : 0)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.fast) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private struct ToolbarButton: View {
    let icon: String
    let tooltip: String
    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle(isActive: isActive))
        .help(tooltip)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    let isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isActive ? .accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? Color.white.opacity(0.05) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .animation(DesignSystem.Animation.fast, value: isActive)
    }
}

// MARK: - Modern Terminal Workspace

private struct ModernTerminalWorkspace: View {
    @ObservedObject var tab: TerminalTabViewModel
    
    var body: some View {
        GeometryReader { geometry in
            paneLayout(for: tab.panes, in: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    @ViewBuilder
    private func paneLayout(for panes: [TerminalPaneViewModel], in size: CGSize) -> some View {
        switch panes.count {
        case 0:
            Color.black
        case 1:
            ModernTerminalPane(
                pane: panes[0],
                isActive: tab.activePaneID == panes[0].id,
                onSelect: { tab.selectPane(id: panes[0].id) },
                onClose: nil
            )
        case 2:
            if tab.splitOrientation == .vertical {
                VSplitView {
                    ModernTerminalPane(
                        pane: panes[0],
                        isActive: tab.activePaneID == panes[0].id,
                        onSelect: { tab.selectPane(id: panes[0].id) },
                        onClose: { tab.closePane(id: panes[0].id) }
                    )
                    ModernTerminalPane(
                        pane: panes[1],
                        isActive: tab.activePaneID == panes[1].id,
                        onSelect: { tab.selectPane(id: panes[1].id) },
                        onClose: { tab.closePane(id: panes[1].id) }
                    )
                }
            } else {
                HSplitView {
                    ModernTerminalPane(
                        pane: panes[0],
                        isActive: tab.activePaneID == panes[0].id,
                        onSelect: { tab.selectPane(id: panes[0].id) },
                        onClose: { tab.closePane(id: panes[0].id) }
                    )
                    ModernTerminalPane(
                        pane: panes[1],
                        isActive: tab.activePaneID == panes[1].id,
                        onSelect: { tab.selectPane(id: panes[1].id) },
                        onClose: { tab.closePane(id: panes[1].id) }
                    )
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
            ModernTerminalPane(
                pane: panes[0],
                isActive: tab.activePaneID == panes[0].id,
                onSelect: { tab.selectPane(id: panes[0].id) },
                onClose: nil
            )
        }
    }
    
    @ViewBuilder
    private func row(for panes: [TerminalPaneViewModel]) -> some View {
        HSplitView {
            ForEach(panes) { pane in
                ModernTerminalPane(
                    pane: pane,
                    isActive: tab.activePaneID == pane.id,
                    onSelect: { tab.selectPane(id: pane.id) },
                    onClose: tab.panes.count > 1 ? { tab.closePane(id: pane.id) } : nil
                )
            }
        }
    }
    
    @ViewBuilder
    private func column(for panes: [TerminalPaneViewModel]) -> some View {
        VSplitView {
            ForEach(panes) { pane in
                ModernTerminalPane(
                    pane: pane,
                    isActive: tab.activePaneID == pane.id,
                    onSelect: { tab.selectPane(id: pane.id) },
                    onClose: tab.panes.count > 1 ? { tab.closePane(id: pane.id) } : nil
                )
            }
        }
    }
}

// MARK: - Modern Terminal Pane

private struct ModernTerminalPane: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var pane: TerminalPaneViewModel
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Modern header
            ModernPaneHeader(pane: pane, isActive: isActive, onClose: onClose, onSelect: onSelect)
            
            SubtleDivider()
            
            // Terminal view with padding to prevent cursor/prompt being hidden at edges
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
                onBecomeActive: onSelect,
                onChatExit: {
                    pane.exitChatMode()
                },
                onChatEnter: { content in
                    pane.enterChatMode(providerID: pane.appearance.chatProvider, modelID: pane.appearance.chatModel)
                    if !content.isEmpty {
                        Task { @MainActor in
                            await appModel.answerChatQuery(content, for: pane)
                        }
                    }
                }
            )
            .id("\(pane.appearance.themeID)-\(pane.id)")
            // NSViewRepresentable has no intrinsic size; without max frame the view can collapse to
            // zero height so clicks/keys hit SwiftUI behind it and the PTY grid never focuses.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable(false)
            .background(Color(appModel.theme(for: pane.appearance.themeID).palette.background.nsColor))
            .padding(.vertical, 4)
            
            // Search bar
            if pane.isSearchPresented {
                ModernSearchBar(pane: pane)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Agent exit banner
            if let banner = pane.agentExitBanner {
                ModernAgentExitBanner(pane: pane, text: banner)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // AI cards stack (floating overlay)
            VStack(spacing: 0) {
                if case let .waitingForDisambiguation(input) = pane.submissionState {
                    ModernDisambiguationBar(input: input, pane: pane)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                if !pane.aiShellState.generatedCommand.isEmpty || pane.aiShellState.isGenerating {
                    ModernAIShellCard(pane: pane)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                if !pane.isChatModeActive && (!pane.queryResponse.text.isEmpty || pane.queryResponse.isStreaming) {
                    ModernQueryResponseCard(pane: pane)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, pane.isAlternateScreen ? 0 : DesignSystem.Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignSystem.Colors.terminalBackground)
        // Border must not participate in hit testing — otherwise it sits above `TerminalView` and
        // steals all clicks/keyboard routing from the AppKit grid (terminal appears frozen).
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(isActive ? DesignSystem.Colors.paneBorderActive : DesignSystem.Colors.paneBorder, lineWidth: isActive ? 1.5 : 0.5)
                .allowsHitTesting(false)
        }
        .onAppear { pane.startIfNeeded() }
        .animation(DesignSystem.Animation.normal, value: pane.isSearchPresented)
        .animation(DesignSystem.Animation.normal, value: pane.agentExitBanner != nil)
        .animation(DesignSystem.Animation.normal, value: pane.submissionState.isWaiting)
        .animation(DesignSystem.Animation.normal, value: pane.aiShellState.isGenerating)
        .animation(DesignSystem.Animation.normal, value: pane.queryResponse.isStreaming)
    }
}

// MARK: - Modern Pane Header

private struct ModernPaneHeader: View {
    @ObservedObject var pane: TerminalPaneViewModel
    let isActive: Bool
    let onClose: (() -> Void)?
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            // Title section
            HStack(spacing: 6) {
                Text(pane.title)
                    .font(DesignSystem.Typography.defaultFont(12, weight: .semibold))
                
                if pane.isAgentTab {
                    Tag(text: "AGENT", color: .orange)
                }
            }
            
            Spacer()
            
            // Info section
            HStack(spacing: DesignSystem.Spacing.m) {
                // Mode indicator
                HStack(spacing: 4) {
                    modeIcon
                    Text(pane.modeIndicatorText)
                        .font(DesignSystem.Typography.mono(10))
                }
                .foregroundStyle(.secondary)
                
                // Provider info
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                    Text("\(pane.activeProviderName)")
                        .font(DesignSystem.Typography.defaultFont(10))
                }
                .foregroundStyle(.tertiary)
                
                // Close button
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(IconButtonStyle(isActive: false))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.backgroundPrimary)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
    
    private var modeIcon: some View {
        let icon: String
        let color: Color
        
        switch pane.modeIndicatorText {
        case InputMode.aiToShell.rawValue:
            icon = "bolt.fill"
            color = .yellow
        case InputMode.query.rawValue:
            icon = "questionmark.circle.fill"
            color = .blue
        default:
            icon = "dollarsign.circle.fill"
            color = .green
        }
        
        return Image(systemName: icon)
            .font(.system(size: 10))
            .foregroundColor(color)
    }
}

// MARK: - Components

private struct ModernSearchBar: View {
    @ObservedObject var pane: TerminalPaneViewModel
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                TextField("Find in scrollback", text: $pane.searchQuery)
                    .textFieldStyle(ModernTextFieldStyle())
                    .onChange(of: pane.searchQuery) { _ in pane.refreshSearch() }
            }
            
            Toggle("Regex", isOn: $pane.isRegexSearchEnabled)
                .toggleStyle(.checkbox)
                .font(DesignSystem.Typography.defaultFont(11))
                .onChange(of: pane.isRegexSearchEnabled) { _ in pane.refreshSearch() }
            
            Text(matchText)
                .font(DesignSystem.Typography.mono(10))
                .foregroundStyle(.secondary)
            
            HStack(spacing: DesignSystem.Spacing.xs) {
                Button("◀") { pane.previousSearchMatch() }
                Button("▶") { pane.nextSearchMatch() }
            }
            .font(DesignSystem.Typography.defaultFont(10))
            
            Button("Close") { pane.isSearchPresented = false }
                .font(DesignSystem.Typography.defaultFont(10))
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    private var matchText: String {
        if pane.searchMatchCount == 0 {
            return "No matches"
        }
        return "\(pane.currentSearchIndex + 1) / \(pane.searchMatchCount)"
    }
}

private struct ModernAgentExitBanner: View {
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var pane: TerminalPaneViewModel
    let text: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(text)
                    .font(DesignSystem.Typography.defaultFont(12))
            }
            
            Spacer()
            
            HStack(spacing: DesignSystem.Spacing.m) {
                Toggle("Auto-restart", isOn: $pane.isAgentAutoRestartEnabled)
                    .toggleStyle(.checkbox)
                    .font(DesignSystem.Typography.defaultFont(11))
                
                Button("Restart") {
                    windowModel.restartAgentPane(pane)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
    }
}

private struct NerdFontBanner: View {
    @EnvironmentObject private var appModel: AppModel
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("Nerd Font recommended for Powerlevel10k and oh-my-zsh glyphs")
                    .font(DesignSystem.Typography.defaultFont(12))
            }
            
            Spacer()
            
            Button("Dismiss") {
                appModel.dismissNerdFontBanner()
            }
            .buttonStyle(ModernButtonStyle(variant: .secondary, size: .s))
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, 10)
        .background(DesignSystem.Colors.backgroundSecondary)
    }
}

// MARK: - Sidebar

private struct ModernSidebar: View {
    @ObservedObject var tab: TerminalTabViewModel
    
    var body: some View {
        AppearanceSidebarView(tab: tab)
            .background(DesignSystem.Colors.backgroundSecondary)
    }
}
