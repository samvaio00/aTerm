import Foundation

/// Per-window state. Each window creates its own WindowModel.
/// Shared state (providers, themes, profiles, agents, MCP) lives on AppModel.
@MainActor
final class WindowModel: ObservableObject, Identifiable {
    let id = UUID()
    let appModel: AppModel

    @Published private(set) var tabs: [TerminalTabViewModel] = []
    @Published var selectedTabID: UUID?
    @Published var isModelPickerPresented = false
    @Published var isAgentPickerPresented = false
    @Published var isCommandPalettePresented = false
    private var didRestore = false

    var selectedTab: TerminalTabViewModel? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    /// Initialise with restored tabs from the session store (used for the first window only).
    /// If onboarding is active, defer tab creation until onboarding completes.
    func restoreOrCreateInitialTabs() {
        Log.debug("window", "restoreOrCreateInitialTabs() didRestore=\(didRestore) onboarding=\(appModel.isOnboardingPresented)")
        guard !didRestore else { return }
        didRestore = true

        if appModel.isOnboardingPresented {
            Log.debug("window", "Deferring tab restore — onboarding active")
            return
        }

        performTabRestore()
    }

    /// Called after onboarding completes to actually start tabs.
    func onboardingDidComplete(selectedThemeID: String? = nil) {
        Log.debug("window", "onboardingDidComplete() tabs.count=\(tabs.count) themeID=\(selectedThemeID ?? "nil")")
        performTabRestore()
        if let selectedThemeID {
            for tab in tabs {
                tab.appearance.themeID = selectedThemeID
                tab.markStateChanged()
            }
        }
        Log.debug("window", "onboardingDidComplete() done — tabs.count=\(tabs.count)")
    }

    private func performTabRestore() {
        guard tabs.isEmpty else {
            Log.debug("window", "performTabRestore() skipped — already have \(tabs.count) tabs")
            return
        }
        Log.debug("window", "performTabRestore() creating tabs...")
        let restored = appModel.restoreTabViewModels()
        Log.debug("window", "Restored \(restored.count) tabs from session store")
        if restored.isEmpty {
            Log.debug("window", "No stored tabs — creating new shell tab")
            createTabAndSelect()
        } else {
            tabs = restored
            tabs.forEach { tab in
                configure(tab)
                appModel.applyProjectConfigIfNeeded(to: tab, directory: tab.currentWorkingDirectory)
                appModel.refreshProviderLabel(for: tab)
                tab.startIfNeeded()
            }
            selectedTabID = tabs.first?.id
        }
        Log.debug("window", "performTabRestore() done — tabs.count=\(tabs.count) selectedTabID=\(selectedTabID?.uuidString ?? "nil")")
    }

    // MARK: - Tab Management

    func createTabAndSelect(workingDirectory: URL? = nil) {
        Log.debug("window", "createTabAndSelect() cwd=\(workingDirectory?.path ?? "nil")")
        let tab = appModel.makeShellTab(workingDirectory: workingDirectory)
        configure(tab)
        tabs.append(tab)
        selectedTabID = tab.id
        Log.debug("window", "Tab created id=\(tab.id) — configuring provider & starting PTY")
        appModel.applyProjectConfigIfNeeded(to: tab, directory: workingDirectory)
        appModel.refreshProviderLabel(for: tab)
        tab.startIfNeeded()
        persistTabs()
        Log.debug("window", "createTabAndSelect() done — tabs.count=\(tabs.count)")
    }

    func closeSelectedTab() {
        guard let selectedTab else { return }
        closeTab(id: selectedTab.id)
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].terminate()
        tabs.remove(at: index)

        if tabs.isEmpty {
            createTabAndSelect()
            return
        }

        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }

        persistTabs()
    }

    func selectTab(id: UUID) {
        selectedTabID = id
        let tab = tabs.first(where: { $0.id == id })
        tab?.hasUnreadOutput = false
        tab?.startIfNeeded()
    }

    func moveTab(draggedID: UUID, targetID: UUID) {
        guard draggedID != targetID,
              let fromIndex = tabs.firstIndex(where: { $0.id == draggedID }),
              let toIndex = tabs.firstIndex(where: { $0.id == targetID }) else { return }

        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: toIndex)
        persistTabs()
    }

    func splitSelectedPane(_ orientation: PaneSplitOrientation) {
        selectedTab?.splitActivePane(orientation: orientation)
        persistTabs()
    }

    // MARK: - Overlays

    func toggleModelPicker() {
        isModelPickerPresented.toggle()
    }

    func dismissModelPicker() {
        isModelPickerPresented = false
    }

    func openAgentPicker() {
        isAgentPickerPresented = true
    }

    func closeAgentPicker() {
        isAgentPickerPresented = false
    }

    func toggleSearchBar() {
        selectedTab?.isSearchPresented.toggle()
    }

    func clearSelectedScrollback() {
        selectedTab?.clearScrollback()
    }

    // MARK: - Theme / Profile Application (per-window tab targeting)

    func applyTheme(_ theme: TerminalTheme, to tab: TerminalTabViewModel? = nil) {
        let target = tab ?? selectedTab
        guard let target else {
            Log.error("window", "applyTheme: no target tab")
            return
        }
        let oldThemeID = target.appearance.themeID
        // Set on ALL panes in the tab, not just via the computed property
        for pane in target.panes {
            var appearance = pane.appearance
            appearance.themeID = theme.id
            pane.appearance = appearance
        }
        target.markStateChanged()
        objectWillChange.send()
        // Clear preview state so hovering away doesn't reset the theme
        previewBackupAppearance = nil
        previewedTabID = nil
        previewedThemeID = nil
        Log.debug("window", "applyTheme: \(oldThemeID) → \(theme.id) on \(target.panes.count) panes")
    }

    private var previewedThemeID: String?
    private var previewedTabID: UUID?
    private var previewBackupAppearance: TerminalAppearance?

    func beginThemePreview(_ theme: TerminalTheme) {
        guard let tab = selectedTab else { return }
        if previewedThemeID == theme.id { return }
        previewedThemeID = theme.id
        previewedTabID = tab.id
        previewBackupAppearance = tab.appearance
        // Update all panes for preview
        for pane in tab.panes {
            var appearance = pane.appearance
            appearance.themeID = theme.id
            pane.appearance = appearance
        }
        tab.markStateChanged()
        objectWillChange.send()
    }

    func endThemePreview() {
        guard let previewedTabID, let previewBackupAppearance,
              let tab = tabs.first(where: { $0.id == previewedTabID }) else { return }
        // Restore all panes
        for pane in tab.panes {
            pane.appearance = previewBackupAppearance
        }
        tab.markStateChanged()
        objectWillChange.send()
        self.previewBackupAppearance = nil
        self.previewedTabID = nil
        self.previewedThemeID = nil
    }

    func applyProfile(_ profile: Profile, to tab: TerminalTabViewModel? = nil) {
        let target = tab ?? selectedTab
        target?.applyProfile(profile)
        if let target {
            appModel.applyDefaultProviderIfNeeded(to: target)
            appModel.refreshProviderLabel(for: target)
        }
        appModel.persistProfilesPublic()
        persistTabs()
    }

    func createProfileFromSelectedTab(named name: String) {
        guard let selectedTab else { return }
        let profile = Profile(name: name, appearance: selectedTab.appearance)
        appModel.profiles.append(profile)
        appModel.defaultProfileID = appModel.defaultProfileID ?? profile.id
        selectedTab.applyProfile(profile)
        appModel.persistProfilesPublic()
        persistTabs()
    }

    func assignModel(providerID: String, modelID: String, to tab: TerminalTabViewModel? = nil) {
        guard let target = tab ?? selectedTab else { return }
        // Update appearance on all panes to ensure consistency
        for pane in target.panes {
            var appearance = pane.appearance
            appearance.aiProvider = providerID
            appearance.aiModel = modelID
            pane.appearance = appearance
        }
        appModel.refreshProviderLabel(for: target)
        target.markStateChanged()
        objectWillChange.send()
    }

    func updateSelectedTabAppearance(_ mutate: (inout TerminalAppearance) -> Void) {
        guard let selectedTab else { return }
        mutate(&selectedTab.appearance)
        appModel.refreshProviderLabel(for: selectedTab)
        selectedTab.markStateChanged()
    }

    // MARK: - Agent Launch

    func launchAgent(_ definition: AgentDefinition, from sourceTab: TerminalTabViewModel? = nil) {
        guard let tab = appModel.makeAgentTab(definition, workingDirectory: sourceTab?.currentWorkingDirectory ?? selectedTab?.currentWorkingDirectory) else { return }
        configure(tab)
        tabs.append(tab)
        selectedTabID = tab.id
        tab.startIfNeeded()
        isAgentPickerPresented = false
        persistTabs()
    }

    // MARK: - Input Handling (delegates to AppModel for AI/classification)

    func submitInput(for pane: TerminalPaneViewModel) {
        appModel.submitInput(for: pane)
    }

    func resolveDisambiguation(as mode: InputMode, for pane: TerminalPaneViewModel) {
        appModel.resolveDisambiguation(as: mode, for: pane)
    }

    func runGeneratedCommand(for pane: TerminalPaneViewModel) {
        appModel.runGeneratedCommand(for: pane)
    }

    func runQuerySuggestion(_ suggestion: QueryCommandSuggestion, for pane: TerminalPaneViewModel) {
        appModel.runQuerySuggestion(suggestion, for: pane)
    }

    func restartAgentPane(_ pane: TerminalPaneViewModel) {
        pane.restartSessionIfPossible()
    }

    // MARK: - Private

    private func configure(_ tab: TerminalTabViewModel) {
        tab.stateDidChange = { [weak self, weak tab] in
            Task { @MainActor [weak self, weak tab] in
                guard let self, let tab else { return }
                if self.selectedTabID != tab.id {
                    tab.hasUnreadOutput = true
                }
                self.persistTabs()
                self.appModel.applyProjectConfigIfNeeded(to: tab, directory: tab.currentWorkingDirectory)
                self.appModel.refreshProviderLabel(for: tab)
            }
        }
    }

    func persistTabs() {
        // Each window persists its tabs independently using its windowID
        appModel.persistTabs(tabs, windowID: id)
    }
}
