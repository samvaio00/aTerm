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
                    ModernSidebar(tab: selectedTab, isSidebarVisible: $isSidebarVisible)
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
        } else if windowModel.isHelpPresented {
            ModernHelpOverlay()
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
            .modifier(TabCommandHandler(windowModel: windowModel))
            .modifier(PaneCommandHandler(windowModel: windowModel))
            .modifier(URLCommandHandler(windowModel: windowModel))
    }
}

private struct TabCommandHandler: ViewModifier {
    @ObservedObject var windowModel: WindowModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .aTermNewTab)) { _ in
                windowModel.createTabAndSelect()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aTermCloseTab)) { _ in
                windowModel.closeSelectedTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aTermToggleModelPicker)) { _ in
                windowModel.toggleModelPicker()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aTermCommandPalette)) { _ in
                windowModel.isCommandPalettePresented.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aTermToggleHelp)) { _ in
                windowModel.isHelpPresented.toggle()
            }
    }
}

private struct PaneCommandHandler: ViewModifier {
    @ObservedObject var windowModel: WindowModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .aTermToggleSearch)) { _ in
                windowModel.toggleSearchBar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aTermClearScrollback)) { _ in
                windowModel.clearSelectedScrollback()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aTermSplitH)) { _ in
                windowModel.splitSelectedPane(.horizontal)
            }
            .onReceive(NotificationCenter.default.publisher(for: .aTermSplitV)) { _ in
                windowModel.splitSelectedPane(.vertical)
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

private struct URLCommandHandler: ViewModifier {
    @ObservedObject var windowModel: WindowModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .aTermOpenDirectory)) { n in
                if let url = n.object as? URL {
                    windowModel.createTabAndSelect(workingDirectory: url)
                }
            }
            .onOpenURL { url in
                guard url.scheme == "aterm", url.host == "open",
                      let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let path = c.queryItems?.first(where: { $0.name == "path" })?.value else { return }
                windowModel.createTabAndSelect(workingDirectory: URL(fileURLWithPath: path))
            }
    }
}

// MARK: - Modern Tab Strip

private struct ModernTabStrip: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var windowModel: WindowModel
    @Binding var isSidebarVisible: Bool
    @State private var draggedTabID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tab strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(windowModel.tabs) { tab in
                        ModernTabButton(
                            tab: tab,
                            isSelected: windowModel.selectedTabID == tab.id,
                            showCloseButton: windowModel.tabs.count > 1
                        ) {
                            windowModel.selectTab(id: tab.id)
                        } onClose: {
                            windowModel.closeTab(id: tab.id)
                        }
                        .onDrag {
                            draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabReorderDropDelegate(
                            targetTabID: tab.id,
                            draggedTabID: $draggedTabID,
                            windowModel: windowModel
                        ))
                        .contextMenu {
                            Button {
                                windowModel.createTabAndSelect(workingDirectory: tab.currentWorkingDirectory)
                            } label: {
                                Label("New Tab Here", systemImage: "plus.square.on.square")
                            }
                            Divider()
                            Button {
                                windowModel.selectTab(id: tab.id)
                                windowModel.splitSelectedPane(.horizontal)
                            } label: {
                                Label("Split Horizontally", systemImage: "rectangle.split.2x1")
                            }
                            Button {
                                windowModel.selectTab(id: tab.id)
                                windowModel.splitSelectedPane(.vertical)
                            } label: {
                                Label("Split Vertically", systemImage: "rectangle.split.1x2")
                            }
                            Divider()
                            Button {
                                tab.clearScrollback()
                            } label: {
                                Label("Clear Scrollback", systemImage: "trash")
                            }
                            if windowModel.tabs.count > 1 {
                                Divider()
                                Button(role: .destructive) {
                                    windowModel.closeTab(id: tab.id)
                                } label: {
                                    Label("Close Tab", systemImage: "xmark")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.s)
                .padding(.vertical, 4)
            }

            Spacer(minLength: DesignSystem.Spacing.s)

            // Toolbar actions
            HStack(spacing: 4) {
                ToolbarButton(icon: "plus", tooltip: "New Tab (⌘T)") {
                    windowModel.createTabAndSelect(workingDirectory: windowModel.selectedTab?.currentWorkingDirectory)
                }

                ToolbarButton(icon: "rectangle.split.2x1", tooltip: "Split Pane (⌘D)") {
                    windowModel.splitSelectedPane(.horizontal)
                }

                ToolbarButton(
                    icon: "command",
                    tooltip: "Command Palette (⌘P)",
                    isActive: windowModel.isCommandPalettePresented
                ) {
                    windowModel.isCommandPalettePresented.toggle()
                }

                ToolbarButton(
                    icon: "bolt",
                    tooltip: "Launch AI Agent",
                    isActive: windowModel.isAgentPickerPresented
                ) {
                    windowModel.openAgentPicker()
                }

                ToolbarButton(
                    icon: "questionmark.circle",
                    tooltip: "Usage & /Commands Guide (⇧⌘/)",
                    isActive: windowModel.isHelpPresented
                ) {
                    windowModel.isHelpPresented.toggle()
                }

                ToolbarButton(
                    icon: "sidebar.right",
                    tooltip: "Toggle Appearance, AI & Help Sidebar",
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

private struct TabReorderDropDelegate: DropDelegate {
    let targetTabID: UUID
    @Binding var draggedTabID: UUID?
    let windowModel: WindowModel

    func dropEntered(info: DropInfo) {
        guard let draggedTabID, draggedTabID != targetTabID else { return }
        withAnimation(DesignSystem.Animation.fast) {
            windowModel.moveTab(draggedID: draggedTabID, targetID: targetTabID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }
}

private struct ModernTabButton: View {
    @ObservedObject var tab: TerminalTabViewModel
    let isSelected: Bool
    let showCloseButton: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    private var isInChatMode: Bool {
        tab.activePane?.isChatModeActive ?? false
    }

    var body: some View {
        HStack(spacing: 6) {
            // Unread output dot
            if tab.hasUnreadOutput && !isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }

            // Tab type icon
            if tab.isAgentTab {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            } else if isInChatMode {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.purple)
            } else {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.75))
            }

            // Title
            Text(tab.title)
                .font(DesignSystem.Typography.defaultFont(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)

            if tab.panes.count > 1 {
                Text("\(tab.panes.count)")
                    .font(DesignSystem.Typography.mono(9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }

            // Close button
            if showCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isSelected || isHovered ? 0.75 : 0)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(0.09)
                            : (isHovered ? Color.primary.opacity(0.04) : Color.clear)
                    )
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
            }
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

    private var themeBackgroundColor: Color {
        Color(appModel.theme(for: pane.appearance.themeID).palette.background.nsColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Modern header
            ModernPaneHeader(pane: pane, isActive: isActive, onClose: onClose, onSelect: onSelect)
            
            SubtleDivider()
            
            // Terminal view
            TerminalView(
                buffer: pane.terminalBuffer,
                bufferVersion: pane.bufferVersion,
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
            .background(themeBackgroundColor)
            
            // Agent exit banner
            if let banner = pane.agentExitBanner {
                ModernAgentExitBanner(pane: pane, text: banner)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if pane.isSearchPresented {
                ModernSearchBar(pane: pane)
                    .padding(.top, 38)
                    .padding(.trailing, DesignSystem.Spacing.m)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
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
        .background(themeBackgroundColor)
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
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var pane: TerminalPaneViewModel
    let isActive: Bool
    let onClose: (() -> Void)?
    let onSelect: () -> Void
    @State private var isAIGuidePresented = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            // Left: Directory / Title + Git branch + Last Exit Status
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: pane.isAgentTab ? "bolt.fill" : "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(pane.isAgentTab ? .orange : .secondary)

                    Text(pane.abbreviatedWorkingDirectory ?? pane.title)
                        .font(DesignSystem.Typography.mono(11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let branch = pane.gitBranch, !branch.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9, weight: .semibold))
                        Text(branch)
                            .font(DesignSystem.Typography.mono(10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }

                if pane.isAgentTab {
                    Tag(text: "AGENT", color: .orange)
                }

                // Exit status & one-click Explain/Fix actions when last command failed
                if let exitCode = pane.lastExitCode, !pane.isChatModeActive {
                    if exitCode == 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("0")
                                .font(DesignSystem.Typography.mono(9, weight: .medium))
                        }
                        .foregroundStyle(.green.opacity(0.8))
                        .help("Last command succeeded (exit 0)")
                    } else {
                        HStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("exit \(exitCode)")
                                    .font(DesignSystem.Typography.mono(9, weight: .semibold))
                            }
                            .foregroundStyle(.red)

                            Button {
                                appModel.explainLastFailure(for: pane)
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8))
                                    Text("Explain")
                                        .font(DesignSystem.Typography.defaultFont(9, weight: .semibold))
                                }
                                .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .help("Explain why the last command failed (/explain)")

                            Button {
                                appModel.fixLastCommand(for: pane)
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .font(.system(size: 8))
                                    Text("Fix")
                                        .font(DesignSystem.Typography.defaultFont(9, weight: .semibold))
                                }
                                .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .help("Generate a corrected command at the prompt (/fix)")
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.red.opacity(0.25), lineWidth: 0.5)
                                )
                        )
                    }
                }
            }

            Spacer(minLength: 8)

            // Right: AI Mode, Chat Mode, Model Selector, AI Guide, Close Pane
            HStack(spacing: 6) {
                // Active mode indicator
                if pane.modeIndicatorText != "TERMINAL" && !pane.isChatModeActive {
                    HStack(spacing: 4) {
                        modeIcon
                        Text(pane.modeIndicatorText)
                            .font(DesignSystem.Typography.mono(9, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                }

                // Chat Mode toggle pill
                Button {
                    if pane.isChatModeActive {
                        pane.exitChatMode()
                    } else {
                        pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
                        pane.enterChatMode(providerID: pane.appearance.chatProvider, modelID: pane.appearance.chatModel)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: pane.isChatModeActive ? "bubble.left.and.bubble.right.fill" : "bubble.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text(pane.isChatModeActive ? "Chat Mode · Exit" : "Chat")
                            .font(DesignSystem.Typography.defaultFont(10, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(pane.isChatModeActive ? Color.purple.opacity(0.2) : Color.primary.opacity(0.05))
                            .overlay(
                                Capsule()
                                    .strokeBorder(pane.isChatModeActive ? Color.purple.opacity(0.45) : Color.clear, lineWidth: 0.5)
                            )
                    )
                    .foregroundStyle(pane.isChatModeActive ? Color.purple : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(pane.isChatModeActive ? "Exit interactive AI chat mode (/exit)" : "Enter interactive multi-turn AI chat mode (/chat)")

                // Smart vs Shell routing toggle pill
                Button {
                    pane.aiRoutingMode = (pane.aiRoutingMode == .shell ? .smart : .shell)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: pane.aiRoutingMode == .shell ? "dollarsign.circle" : "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                        Text(pane.aiRoutingMode == .shell ? "Shell" : "Smart")
                            .font(DesignSystem.Typography.defaultFont(10, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(pane.aiRoutingMode == .smart ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                    )
                    .foregroundStyle(pane.aiRoutingMode == .shell ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(pane.aiRoutingMode == .smart
                      ? "Smart Mode: natural language questions & tasks route to AI automatically; shell commands run natively"
                      : "Shell Mode: only explicit prefixes (!, ?, >, $) or /chat route to AI")

                // Interactive Model Picker pill
                Button {
                    windowModel.toggleModelPicker()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 9))
                        Text(modelDisplayLabel)
                            .font(DesignSystem.Typography.mono(10))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .opacity(0.6)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.05))
                    )
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Switch AI Provider & Model (⌘M or /model)")

                // Quick AI Commands Guide Popover
                Button {
                    isAIGuidePresented.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Inline AI Commands & Shortcuts (/help)")
                .popover(isPresented: $isAIGuidePresented, arrowEdge: .bottom) {
                    AIGuidePopoverView(pane: pane, isPresented: $isAIGuidePresented)
                }

                // Close pane button (when split)
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(IconButtonStyle(isActive: false))
                    .foregroundStyle(.secondary)
                    .help("Close Split Pane")
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.backgroundPrimary)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var modelDisplayLabel: String {
        let model = pane.activeModelName
        if model != "No model" && !model.isEmpty {
            return "\(pane.activeProviderName) · \(model)"
        }
        return pane.activeProviderName
    }

    private var modeIcon: some View {
        let icon: String
        let color: Color
        
        if pane.modeIndicatorText.hasPrefix(InputMode.aiToShell.rawValue) {
            icon = "bolt.fill"
            color = .yellow
        } else if pane.modeIndicatorText.hasPrefix(InputMode.query.rawValue) {
            icon = "questionmark.circle.fill"
            color = .blue
        } else {
            icon = "dollarsign.circle.fill"
            color = .green
        }
        
        return Image(systemName: icon)
            .font(.system(size: 9))
            .foregroundColor(color)
    }
}

private struct AIGuidePopoverView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var pane: TerminalPaneViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Usage & /Commands Quick Reference")
                    .font(DesignSystem.Typography.defaultFont(13, weight: .semibold))
                Spacer()
                Button("Full Guide") {
                    isPresented = false
                    windowModel.isHelpPresented = true
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .xs))
            }

            Text("Type directly at your zsh prompt. Standard shell commands run natively in zsh; slash commands & prefixes invoke AI inline.")
                .font(DesignSystem.Typography.defaultFont(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SubtleDivider()

            Text("SLASH (/) COMMANDS")
                .font(DesignSystem.Typography.mono(10, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                guideRow(prefix: "/help, /commands", desc: "Print full usage & /commands reference in terminal")
                guideRow(prefix: "/chat [message]", desc: "Enter multi-turn AI chat (/exit or Ctrl+C to leave)")
                guideRow(prefix: "/ask <question>", desc: "Ask AI a question and stream the answer inline")
                guideRow(prefix: "/cmd <task>", desc: "Generate & execute a zsh command from plain English")
                guideRow(prefix: "/explain [note]", desc: "Explain the last failed command & suggest a fix")
                guideRow(prefix: "/fix [hint]", desc: "Generate a corrected command at your zsh prompt")
                guideRow(prefix: "/model [name]", desc: "Show or switch the active AI model inline")
                guideRow(prefix: "/smart, /shell", desc: "Switch between Smart and Shell-only routing")
                guideRow(prefix: "/clear, /reset", desc: "Clear scrollback and reset AI conversation memory")
            }

            SubtleDivider()

            Text("INLINE SHORTHAND PREFIXES")
                .font(DesignSystem.Typography.mono(10, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                guideRow(prefix: "? <q> / !<q>", desc: "Ask AI a question inline without switching modes")
                guideRow(prefix: "?? <t> / ><t>", desc: "Generate & run a zsh command from natural language")
                guideRow(prefix: "$ <command>", desc: "Force direct shell execution without AI")
                guideRow(prefix: "explain / fix", desc: "Quick unprefixed aliases after a command fails")
            }

            SubtleDivider()

            HStack(spacing: 8) {
                Button("Print /help") {
                    isPresented = false
                    pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
                    appModel.writeInlineAIHelp(to: pane)
                    pane.finishInlineAIOutput()
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .xs))

                Button("Explain Error") {
                    isPresented = false
                    appModel.explainLastFailure(for: pane)
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .xs))

                Spacer()

                Button("Start /chat") {
                    isPresented = false
                    if !pane.isChatModeActive {
                        pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
                        pane.enterChatMode(providerID: pane.appearance.chatProvider, modelID: pane.appearance.chatModel)
                    }
                }
                .buttonStyle(ModernButtonStyle(variant: .primary, size: .xs))
            }
        }
        .padding(14)
        .frame(width: 420)
    }

    private func guideRow(prefix: String, desc: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(prefix)
                .font(DesignSystem.Typography.mono(11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 125, alignment: .leading)
            Text(desc)
                .font(DesignSystem.Typography.defaultFont(11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Components

private struct ModernSearchBar: View {
    @ObservedObject var pane: TerminalPaneViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Find in terminal…", text: $pane.searchQuery)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.defaultFont(12))
                    .frame(width: 170)
                    .focused($isSearchFocused)
                    .onChange(of: pane.searchQuery) { _ in pane.refreshSearch() }
                    .onSubmit {
                        pane.nextSearchMatch()
                    }

                if !pane.searchQuery.isEmpty {
                    Button {
                        pane.searchQuery = ""
                        pane.refreshSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.85))
            )

            Toggle("Regex", isOn: $pane.isRegexSearchEnabled)
                .toggleStyle(.checkbox)
                .font(DesignSystem.Typography.defaultFont(11))
                .onChange(of: pane.isRegexSearchEnabled) { _ in pane.refreshSearch() }

            Text(matchText)
                .font(DesignSystem.Typography.mono(10))
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, alignment: .center)

            HStack(spacing: 2) {
                Button {
                    pane.previousSearchMatch()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(pane.searchMatchCount == 0)
                .help("Previous Match")

                Button {
                    pane.nextSearchMatch()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(pane.searchMatchCount == 0)
                .help("Next Match (↵)")
            }

            Button {
                pane.isSearchPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Find Bar (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        )
        .modernShadow(DesignSystem.Shadows.medium)
        .onAppear {
            pane.refreshSearch()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onExitCommand {
            pane.isSearchPresented = false
        }
    }

    private var matchText: String {
        if pane.searchQuery.isEmpty {
            return "0 / 0"
        }
        if pane.searchMatchCount == 0 {
            return "0 matches"
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
    @Binding var isSidebarVisible: Bool
    
    var body: some View {
        AppearanceSidebarView(tab: tab) {
            withAnimation(DesignSystem.Animation.normal) {
                isSidebarVisible = false
            }
        }
        .background(DesignSystem.Colors.backgroundSecondary)
    }
}
