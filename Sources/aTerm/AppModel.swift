import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var tabs: [TerminalTabViewModel] = []
    @Published var selectedTabID: UUID?
    @Published var showNerdFontBanner = false
    @Published var importedThemes: [TerminalTheme] = []
    @Published var profiles: [Profile] = []
    @Published var defaultProfileID: UUID?
    @Published var providers: [ModelProvider] = []
    @Published var defaultProviderID: String?
    @Published var defaultModelID: String?
    @Published var isModelPickerPresented = false
    @Published var providerStatusMessage: String?
    @Published var agentDefinitions: [AgentDefinition] = []
    @Published var defaultAgentID: String?
    @Published var agentStatuses: [String: AgentInstallationStatus] = [:]
    @Published var isAgentPickerPresented = false
    @Published var mcpServers: [MCPServerDefinition] = []
    @Published var mcpSnapshots: [String: MCPServerSnapshot] = [:]
    @Published var isOnboardingPresented = false
    @Published var shellIntegrationMessage: String?

    private let sessionStore = SessionStore()
    private let themeStore = ThemeStore()
    private let profileStore = ProfileStore()
    private let providerStore = ProviderStore()
    private let agentStore = AgentStore()
    private let mcpStore = MCPStore()
    private let providerRouter = ProviderRouter()
    private let inputClassifier = InputClassifier()
    private let keychainStore = KeychainStore()
    private let agentDetector = AgentDetector()
    private let mcpHost = MCPHost()
    private let nerdFontDismissalKey = "dismissedNerdFontBanner"
    private let onboardingDismissalKey = "completedOnboarding"
    private var previewedThemeID: String?
    private var previewedTabID: UUID?
    private var previewBackupAppearance: TerminalAppearance?

    init() {
        importedThemes = themeStore.loadImportedThemes()
        restoreProfiles()
        restoreProviders()
        restoreAgents()
        restoreMCPServers()
        scanAgents()
        restoreTabs()
        showNerdFontBanner = !FontSupport.currentTerminalFontSupportsNerdGlyphs && !UserDefaults.standard.bool(forKey: nerdFontDismissalKey)
        isOnboardingPresented = !UserDefaults.standard.bool(forKey: onboardingDismissalKey)

        if tabs.isEmpty {
            createTabAndSelect()
        } else {
            tabs.forEach { tab in
                applyProjectConfigIfNeeded(to: tab, directory: tab.currentWorkingDirectory)
                refreshProviderLabel(for: tab)
                tab.startIfNeeded()
            }
        }

        autoStartGlobalMCPServers()
    }

    var selectedTab: TerminalTabViewModel? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    var allThemes: [TerminalTheme] {
        BuiltinThemes.all + importedThemes
    }

    var availableProviders: [ModelProvider] {
        providers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var modelPickerItems: [(provider: ModelProvider, model: ModelDefinition)] {
        availableProviders.flatMap { provider in
            provider.models.map { (provider, $0) }
        }
    }

    var availableAgents: [AgentDefinition] {
        agentDefinitions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var availableMCPServers: [MCPServerDefinition] {
        mcpServers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func theme(for id: String) -> TerminalTheme {
        allThemes.first(where: { $0.id == id }) ?? BuiltinThemes.all.last!
    }

    func provider(for id: String?) -> ModelProvider? {
        guard let id else { return nil }
        return providers.first(where: { $0.id == id })
    }

    func agent(for id: String?) -> AgentDefinition? {
        guard let id else { return nil }
        return agentDefinitions.first(where: { $0.id == id })
    }

    func createTabAndSelect(workingDirectory: URL? = nil) {
        let tab = makeShellTab(workingDirectory: workingDirectory, profile: defaultProfile)
        tabs.append(tab)
        selectedTabID = tab.id
        applyProjectConfigIfNeeded(to: tab, directory: workingDirectory)
        refreshProviderLabel(for: tab)
        tab.startIfNeeded()
        persistTabs()
    }

    func openAgentPicker() {
        isAgentPickerPresented = true
    }

    func closeAgentPicker() {
        isAgentPickerPresented = false
    }

    func startMCPServer(_ definition: MCPServerDefinition, cwd: URL?) {
        mcpHost.start(definition, cwd: cwd)
        refreshMCPSnapshot(for: definition)
    }

    func stopMCPServer(_ definition: MCPServerDefinition) {
        mcpHost.stop(definition.id)
        refreshMCPSnapshot(for: definition)
    }

    func restartMCPServer(_ definition: MCPServerDefinition, cwd: URL?) {
        mcpHost.restart(definition, cwd: cwd)
        refreshMCPSnapshot(for: definition)
    }

    func upsertMCPServer(_ definition: MCPServerDefinition) {
        mcpServers.removeAll(where: { $0.id == definition.id })
        mcpServers.append(definition)
        persistMCPServers()
        refreshMCPSnapshot(for: definition)
    }

    func launchAgent(_ definition: AgentDefinition, from sourceTab: TerminalTabViewModel? = nil) {
        guard let executablePath = agentStatuses[definition.id]?.executablePath else { return }
        let workingDirectory = sourceTab?.currentWorkingDirectory ?? selectedTab?.currentWorkingDirectory

        var environment: [String: String] = [:]
        if let authValue = try? keychainStore.readSecret(account: providerSecretAccount(forEnvVar: definition.authEnvVar)),
           !authValue.isEmpty {
            environment[definition.authEnvVar] = authValue
        }

        let launchConfiguration = PTYLaunchConfiguration.agent(
            executablePath: executablePath,
            arguments: definition.args,
            environment: environment,
            workingDirectory: workingDirectory,
            displayName: definition.name
        )

        let tab = TerminalTabViewModel(
            initialTitle: definition.name,
            workingDirectory: workingDirectory,
            profile: defaultProfile,
            kind: .agent(definition),
            launchConfiguration: launchConfiguration
        )
        configure(tab)
        tabs.append(tab)
        selectedTabID = tab.id
        tab.startIfNeeded()
        isAgentPickerPresented = false
        persistTabs()
    }

    func restartAgentTab(_ tab: TerminalTabViewModel) {
        tab.restartSessionIfPossible()
    }

    func restartAgentPane(_ pane: TerminalPaneViewModel) {
        pane.restartSessionIfPossible()
    }

    func splitSelectedPane(_ orientation: PaneSplitOrientation) {
        selectedTab?.splitActivePane(orientation: orientation)
        persistTabs()
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
        tabs.first(where: { $0.id == id })?.startIfNeeded()
    }

    func moveTab(draggedID: UUID, targetID: UUID) {
        guard draggedID != targetID,
              let fromIndex = tabs.firstIndex(where: { $0.id == draggedID }),
              let toIndex = tabs.firstIndex(where: { $0.id == targetID }) else { return }

        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: toIndex)
        persistTabs()
    }

    func dismissNerdFontBanner() {
        showNerdFontBanner = false
        UserDefaults.standard.set(true, forKey: nerdFontDismissalKey)
    }

    func importTheme(from url: URL) throws {
        let theme = try ThemeParser.parseTheme(at: url)
        importedThemes.removeAll(where: { $0.id == theme.id })
        importedThemes.append(theme)
        importedThemes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        themeStore.saveImportedThemes(importedThemes)
    }

    func applyTheme(_ theme: TerminalTheme, to tab: TerminalTabViewModel? = nil) {
        let target = tab ?? selectedTab
        target?.appearance.themeID = theme.id
        target?.markStateChanged()
    }

    func beginThemePreview(_ theme: TerminalTheme) {
        guard let tab = selectedTab else { return }
        if previewedThemeID == theme.id { return }
        previewedThemeID = theme.id
        previewedTabID = tab.id
        previewBackupAppearance = tab.appearance
        tab.appearance.themeID = theme.id
    }

    func endThemePreview() {
        guard let previewedTabID, let previewBackupAppearance,
              let tab = tabs.first(where: { $0.id == previewedTabID }) else { return }
        tab.appearance = previewBackupAppearance
        self.previewBackupAppearance = nil
        self.previewedTabID = nil
        self.previewedThemeID = nil
    }

    func updateSelectedTabAppearance(_ mutate: (inout TerminalAppearance) -> Void) {
        guard let selectedTab else { return }
        mutate(&selectedTab.appearance)
        refreshProviderLabel(for: selectedTab)
        selectedTab.markStateChanged()
    }

    func applyProfile(_ profile: Profile, to tab: TerminalTabViewModel? = nil) {
        let target = tab ?? selectedTab
        target?.applyProfile(profile)
        if defaultProfileID == nil {
            defaultProfileID = profile.id
        }
        if let target {
            applyDefaultProviderIfNeeded(to: target)
            refreshProviderLabel(for: target)
        }
        persistProfiles()
        persistTabs()
    }

    func createProfileFromSelectedTab(named name: String) {
        guard let selectedTab else { return }
        let profile = Profile(name: name, appearance: selectedTab.appearance)
        profiles.append(profile)
        defaultProfileID = defaultProfileID ?? profile.id
        selectedTab.applyProfile(profile)
        persistProfiles()
        persistTabs()
    }

    func setDefaultProfile(_ profileID: UUID) {
        defaultProfileID = profileID
        persistProfiles()
    }

    func upsertProvider(_ provider: ModelProvider, secret: String?) throws {
        providers.removeAll(where: { $0.id == provider.id })
        providers.append(provider)
        if let secret, !secret.isEmpty {
            try keychainStore.save(secret: secret, account: provider.id)
        }
        defaultProviderID = defaultProviderID ?? provider.id
        defaultModelID = defaultModelID ?? provider.models.first?.id
        persistProviders()
        tabs.forEach(refreshProviderLabel(for:))
    }

    func deleteProvider(_ providerID: String) {
        providers.removeAll(where: { $0.id == providerID })
        try? keychainStore.deleteSecret(account: providerID)
        if defaultProviderID == providerID {
            defaultProviderID = providers.first?.id
            defaultModelID = providers.first?.models.first?.id
        }
        tabs.forEach { tab in
            if tab.appearance.aiProvider == providerID {
                tab.appearance.aiProvider = defaultProviderID
                tab.appearance.aiModel = defaultModelID
                refreshProviderLabel(for: tab)
                tab.markStateChanged()
            }
        }
        persistProviders()
        persistTabs()
    }

    func setDefaultProvider(providerID: String, modelID: String?) {
        defaultProviderID = providerID
        defaultModelID = modelID
        persistProviders()
    }

    func assignModel(providerID: String, modelID: String, to tab: TerminalTabViewModel? = nil) {
        guard let target = tab ?? selectedTab else { return }
        target.appearance.aiProvider = providerID
        target.appearance.aiModel = modelID
        refreshProviderLabel(for: target)
        target.markStateChanged()
    }

    func submitInput(for tab: TerminalTabViewModel) {
        if tab.isAgentTab {
            let command = tab.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { return }
            tab.inputText = ""
            tab.sendTerminalCommand(command)
            return
        }

        let rawInput = tab.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }
        let displayInput = inputClassifier.strippedOverrideInput(rawInput)
        tab.inputText = ""

        Task { @MainActor in
            let provider = self.provider(for: tab.appearance.aiProvider)
            let classifierModelID = tab.appearance.classifierModel ?? tab.appearance.aiModel

            do {
                let classification = try await inputClassifier.classify(
                    rawInput,
                    context: tab.terminalContext(),
                    provider: provider,
                    modelID: classifierModelID
                )

                guard let classification else {
                    tab.submissionState = .waitingForDisambiguation(displayInput)
                    tab.modeIndicatorText = "AMBIGUOUS"
                    return
                }

                switch classification {
                case .terminal:
                    tab.clearAssistantState()
                    tab.sendTerminalCommand(displayInput)
                case .aiToShell:
                    tab.queryResponse = QueryResponseState()
                    tab.submissionState = .idle
                    tab.modeIndicatorText = InputMode.aiToShell.rawValue
                    await generateShellCommand(from: displayInput, for: tab)
                case .query:
                    tab.aiShellState = AIShellState()
                    tab.submissionState = .idle
                    tab.modeIndicatorText = InputMode.query.rawValue
                    await answerQuery(displayInput, for: tab)
                }
            } catch {
                tab.queryResponse = QueryResponseState(
                    text: "Classification failed: \(error.localizedDescription)",
                    isStreaming: false,
                    suggestions: []
                )
                tab.modeIndicatorText = "ERROR"
            }
        }
    }

    func submitInput(for pane: TerminalPaneViewModel) {
        if pane.isAgentTab {
            let command = pane.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { return }
            pane.inputText = ""
            pane.sendTerminalCommand(command)
            return
        }

        let rawInput = pane.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }
        let displayInput = inputClassifier.strippedOverrideInput(rawInput)
        pane.inputText = ""

        Task { @MainActor in
            let provider = self.provider(for: pane.appearance.aiProvider)
            let classifierModelID = pane.appearance.classifierModel ?? pane.appearance.aiModel

            do {
                let classification = try await inputClassifier.classify(
                    rawInput,
                    context: pane.terminalContext(),
                    provider: provider,
                    modelID: classifierModelID
                )

                guard let classification else {
                    pane.submissionState = .waitingForDisambiguation(displayInput)
                    pane.modeIndicatorText = "AMBIGUOUS"
                    return
                }

                switch classification {
                case .terminal:
                    pane.clearAssistantState()
                    pane.sendTerminalCommand(displayInput)
                case .aiToShell:
                    pane.queryResponse = QueryResponseState()
                    pane.submissionState = .idle
                    pane.modeIndicatorText = InputMode.aiToShell.rawValue
                    await generateShellCommand(from: displayInput, for: pane)
                case .query:
                    pane.aiShellState = AIShellState()
                    pane.submissionState = .idle
                    pane.modeIndicatorText = InputMode.query.rawValue
                    await answerQuery(displayInput, for: pane)
                }
            } catch {
                pane.queryResponse = QueryResponseState(
                    text: "Classification failed: \(error.localizedDescription)",
                    isStreaming: false,
                    suggestions: []
                )
                pane.modeIndicatorText = "ERROR"
            }
        }
    }

    func resolveDisambiguation(as mode: InputMode, for tab: TerminalTabViewModel) {
        guard case let .waitingForDisambiguation(input) = tab.submissionState else { return }
        tab.submissionState = .idle
        switch mode {
        case .terminal:
            tab.clearAssistantState()
            tab.sendTerminalCommand(input)
        case .aiToShell:
            tab.modeIndicatorText = InputMode.aiToShell.rawValue
            Task { @MainActor in
                await generateShellCommand(from: input, for: tab)
            }
        case .query:
            tab.modeIndicatorText = InputMode.query.rawValue
            Task { @MainActor in
                await answerQuery(input, for: tab)
            }
        }
    }

    func resolveDisambiguation(as mode: InputMode, for pane: TerminalPaneViewModel) {
        guard case let .waitingForDisambiguation(input) = pane.submissionState else { return }
        pane.submissionState = .idle
        switch mode {
        case .terminal:
            pane.clearAssistantState()
            pane.sendTerminalCommand(input)
        case .aiToShell:
            pane.modeIndicatorText = InputMode.aiToShell.rawValue
            Task { @MainActor in
                await generateShellCommand(from: input, for: pane)
            }
        case .query:
            pane.modeIndicatorText = InputMode.query.rawValue
            Task { @MainActor in
                await answerQuery(input, for: pane)
            }
        }
    }

    func runGeneratedCommand(for tab: TerminalTabViewModel) {
        let command = tab.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        tab.aiShellState = AIShellState()
        tab.sendTerminalCommand(command)
    }

    func runGeneratedCommand(for pane: TerminalPaneViewModel) {
        let command = pane.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        pane.aiShellState = AIShellState()
        pane.sendTerminalCommand(command)
    }

    func runQuerySuggestion(_ suggestion: QueryCommandSuggestion, for tab: TerminalTabViewModel) {
        tab.sendTerminalCommand(suggestion.command)
    }

    func runQuerySuggestion(_ suggestion: QueryCommandSuggestion, for pane: TerminalPaneViewModel) {
        pane.sendTerminalCommand(suggestion.command)
    }

    func toggleModelPicker() {
        isModelPickerPresented.toggle()
    }

    func dismissModelPicker() {
        isModelPickerPresented = false
    }

    func toggleSearchBar() {
        selectedTab?.isSearchPresented.toggle()
    }

    func clearSelectedScrollback() {
        selectedTab?.clearScrollback()
    }

    func testConnection(for provider: ModelProvider) async {
        do {
            let result = try await providerRouter.testConnection(provider: provider)
            providerStatusMessage = "\(provider.name): \(result.latencyMS) ms, \(result.message)"
        } catch {
            providerStatusMessage = "\(provider.name): \(error.localizedDescription)"
        }
    }

    func hasStoredCredential(for providerID: String) -> Bool {
        (try? keychainStore.readSecret(account: providerID))??.isEmpty == false
    }

    func upsertAgent(_ agent: AgentDefinition) {
        agentDefinitions.removeAll(where: { $0.id == agent.id })
        agentDefinitions.append(agent)
        if defaultAgentID == nil {
            defaultAgentID = agent.id
        }
        persistAgents()
        scanAgents()
    }

    func completeOnboarding() {
        isOnboardingPresented = false
        UserDefaults.standard.set(true, forKey: onboardingDismissalKey)
    }

    func installShellIntegration() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let destination = home.appendingPathComponent(".aterm-shell-integration.zsh")
        let zshrc = home.appendingPathComponent(".zshrc")
        let sourceLine = "\nsource \"\(destination.path)\"\n"

        guard let sourceURL = Bundle.module.url(forResource: "shell-integration", withExtension: "zsh", subdirectory: "Resources") else {
            shellIntegrationMessage = "Bundled shell integration script not found."
            return
        }

        do {
            let script = try String(contentsOf: sourceURL, encoding: .utf8)
            try script.write(to: destination, atomically: true, encoding: .utf8)

            let currentZshrc = (try? String(contentsOf: zshrc, encoding: .utf8)) ?? ""
            if !currentZshrc.contains(destination.path) {
                try (currentZshrc + sourceLine).write(to: zshrc, atomically: true, encoding: .utf8)
            }

            shellIntegrationMessage = "Installed shell integration into \(destination.path)"
        } catch {
            shellIntegrationMessage = "Failed to install shell integration: \(error.localizedDescription)"
        }
    }

    func setDefaultAgent(_ agentID: String) {
        defaultAgentID = agentID
        persistAgents()
    }

    private var defaultProfile: Profile {
        profiles.first(where: { $0.id == defaultProfileID }) ?? profiles.first ?? Profile(name: "Default", appearance: .default)
    }

    private func restoreProfiles() {
        if let stored = profileStore.load(), !stored.profiles.isEmpty {
            profiles = stored.profiles
            defaultProfileID = stored.defaultProfileID ?? stored.profiles.first?.id
            return
        }

        let defaultProfile = Profile(name: "Default", appearance: .default)
        profiles = [defaultProfile]
        self.defaultProfileID = defaultProfile.id
        persistProfiles()
    }

    private func restoreProviders() {
        if let stored = providerStore.load() {
            let customProviders = stored.providers.filter { !$0.isBuiltin }
            providers = BuiltinProviders.all + customProviders
            defaultProviderID = stored.defaultProviderID ?? BuiltinProviders.all.first?.id
            defaultModelID = stored.defaultModelID ?? BuiltinProviders.all.first?.models.first?.id
        } else {
            providers = BuiltinProviders.all
            defaultProviderID = BuiltinProviders.all.first?.id
            defaultModelID = BuiltinProviders.all.first?.models.first?.id
            persistProviders()
        }
    }

    private func restoreAgents() {
        if let stored = agentStore.load() {
            agentDefinitions = BuiltinAgents.all + stored.agents.filter { !$0.isBuiltin }
            defaultAgentID = stored.defaultAgentID ?? BuiltinAgents.all.first?.id
        } else {
            agentDefinitions = BuiltinAgents.all
            defaultAgentID = BuiltinAgents.all.first?.id
            persistAgents()
        }
    }

    private func restoreMCPServers() {
        if let stored = mcpStore.load() {
            mcpServers = BuiltinMCPServers.all + stored.servers.filter { !$0.isBuiltin }
        } else {
            mcpServers = BuiltinMCPServers.all
            persistMCPServers()
        }
        mcpServers.forEach(refreshMCPSnapshot(for:))
    }

    private func scanAgents() {
        agentStatuses = agentDetector.detect(agentDefinitions)
    }

    private func autoStartGlobalMCPServers() {
        for server in mcpServers where server.autoStart && server.scope == .global {
            startMCPServer(server, cwd: selectedTab?.currentWorkingDirectory)
        }
    }

    private func restoreTabs() {
        let storedTabs = sessionStore.loadTabs()
        tabs = storedTabs.compactMap { descriptor in
            let storedPanes = descriptor.panes ?? [
                SessionStore.StoredPane(
                    id: descriptor.activePaneID ?? UUID(),
                    title: descriptor.title,
                    workingDirectoryPath: descriptor.workingDirectoryPath,
                    profileID: descriptor.profileID,
                    agentDefinitionID: descriptor.agentDefinitionID
                )
            ]
            let panes = storedPanes.compactMap { self.makePane(from: $0) }
            guard !panes.isEmpty else { return nil }
            let profile = profiles.first(where: { $0.id == panes.first?.profileID }) ?? defaultProfile
            let tab = TerminalTabViewModel(
                id: descriptor.id,
                workingDirectory: panes.first?.currentWorkingDirectory,
                profile: profile,
                kind: panes.first?.kind ?? .shell,
                panes: panes,
                activePaneID: descriptor.activePaneID ?? panes.first?.id,
                splitOrientation: descriptor.resolvedSplitOrientation
            )
            return tab
        }
        selectedTabID = tabs.first?.id
    }

    private func makeShellTab(id: UUID = UUID(), title: String = "zsh", workingDirectory: URL? = nil, profile: Profile) -> TerminalTabViewModel {
        let tab = TerminalTabViewModel(
            id: id,
            initialTitle: title,
            workingDirectory: workingDirectory,
            profile: profile
        )
        applyDefaultProviderIfNeeded(to: tab)
        configure(tab)
        return tab
    }

    private func configure(_ tab: TerminalTabViewModel) {
        tab.stateDidChange = { [weak self, weak tab] in
            Task { @MainActor [weak self, weak tab] in
                guard let self, let tab else { return }
                self.persistTabs()
                self.applyProjectConfigIfNeeded(to: tab, directory: tab.currentWorkingDirectory)
                self.refreshProviderLabel(for: tab)
            }
        }
    }

    private func applyDefaultProviderIfNeeded(to tab: TerminalTabViewModel) {
        tab.panes.forEach(applyDefaultProviderIfNeeded(to:))
        refreshProviderLabel(for: tab)
    }

    private func refreshProviderLabel(for tab: TerminalTabViewModel) {
        tab.panes.forEach(refreshProviderLabel(for:))
    }

    private func applyProjectConfigIfNeeded(to tab: TerminalTabViewModel, directory: URL?) {
        guard let directory, let config = TermConfig.load(from: directory) else { return }

        if let profileName = config.profileName,
           let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(profileName) == .orderedSame }) {
            tab.applyProfile(profile)
        }

        if config.aiProvider != nil || config.aiModel != nil || config.classifierModel != nil {
            var appearance = tab.appearance
            if let aiProvider = config.aiProvider {
                appearance.aiProvider = aiProvider
            }
            if let aiModel = config.aiModel {
                appearance.aiModel = aiModel
            }
            if let classifierModel = config.classifierModel {
                appearance.classifierModel = classifierModel
            }
            tab.appearance = appearance
        }

        if !config.mcpServers.isEmpty {
            for serverID in config.mcpServers {
                if let definition = mcpServers.first(where: { $0.id == serverID }) {
                    startMCPServer(definition, cwd: directory)
                }
            }
        }

        refreshProviderLabel(for: tab)
    }

    private func persistProfiles() {
        profileStore.save(.init(defaultProfileID: defaultProfileID, profiles: profiles))
    }

    private func persistProviders() {
        providerStore.save(.init(
            providers: providers.filter { !$0.isBuiltin },
            defaultProviderID: defaultProviderID,
            defaultModelID: defaultModelID
        ))
    }

    private func persistAgents() {
        agentStore.save(.init(
            agents: agentDefinitions.filter { !$0.isBuiltin },
            defaultAgentID: defaultAgentID
        ))
    }

    private func persistMCPServers() {
        mcpStore.save(.init(
            servers: mcpServers.filter { !$0.isBuiltin }
        ))
    }

    private func refreshMCPSnapshot(for definition: MCPServerDefinition) {
        mcpSnapshots[definition.id] = mcpHost.snapshot(for: definition)
    }

    private func persistTabs() {
        sessionStore.saveTabs(
            tabs.map {
                return SessionStore.StoredTab(
                    id: $0.id,
                    title: $0.title,
                    workingDirectoryPath: $0.currentWorkingDirectory?.path,
                    profileID: $0.profileID,
                    agentDefinitionID: nil,
                    activePaneID: $0.activePaneID,
                    splitOrientation: $0.splitOrientation?.rawValue,
                    panes: $0.panes.map {
                        let agentDefinitionID: String?
                        if case let .agent(agent) = $0.kind {
                            agentDefinitionID = agent.id
                        } else {
                            agentDefinitionID = nil
                        }
                        return SessionStore.StoredPane(
                            id: $0.id,
                            title: $0.title,
                            workingDirectoryPath: $0.currentWorkingDirectory?.path,
                            profileID: $0.profileID,
                            agentDefinitionID: agentDefinitionID
                        )
                    }
                )
            }
        )
    }

    private func makePane(from descriptor: SessionStore.StoredPane) -> TerminalPaneViewModel? {
        let profile = profiles.first(where: { $0.id == descriptor.profileID }) ?? defaultProfile

        if let agentID = descriptor.agentDefinitionID,
           let definition = agent(for: agentID),
           let executablePath = agentStatuses[agentID]?.executablePath {
            let configuration = PTYLaunchConfiguration.agent(
                executablePath: executablePath,
                arguments: definition.args,
                environment: [:],
                workingDirectory: descriptor.workingDirectoryURL,
                displayName: definition.name
            )
            let pane = TerminalPaneViewModel(
                id: descriptor.id,
                initialTitle: definition.name,
                workingDirectory: descriptor.workingDirectoryURL,
                profile: profile,
                kind: .agent(definition),
                launchConfiguration: configuration
            )
            applyDefaultProviderIfNeeded(to: pane)
            return pane
        }

        let pane = TerminalPaneViewModel(
            id: descriptor.id,
            initialTitle: descriptor.title,
            workingDirectory: descriptor.workingDirectoryURL,
            profile: profile
        )
        applyDefaultProviderIfNeeded(to: pane)
        return pane
    }

    private func applyDefaultProviderIfNeeded(to pane: TerminalPaneViewModel) {
        if pane.appearance.aiProvider == nil {
            pane.appearance.aiProvider = defaultProviderID
        }
        if pane.appearance.aiModel == nil {
            let defaultProvider = provider(for: pane.appearance.aiProvider)
            pane.appearance.aiModel = defaultModelID ?? defaultProvider?.models.first?.id
        }
        refreshProviderLabel(for: pane)
    }

    private func refreshProviderLabel(for pane: TerminalPaneViewModel) {
        let provider = self.provider(for: pane.appearance.aiProvider)
        let modelName = provider?.models.first(where: { $0.id == pane.appearance.aiModel })?.name ?? pane.appearance.aiModel
        pane.setProviderLabel(providerName: provider?.name ?? pane.appearance.aiProvider, modelName: modelName)
    }

    private func generateShellCommand(from input: String, for tab: TerminalTabViewModel) async {
        tab.aiShellState = AIShellState(originalPrompt: input, generatedCommand: "", isGenerating: true, isEditing: false)

        guard let provider = provider(for: tab.appearance.aiProvider),
              let modelID = tab.appearance.aiModel else {
            tab.aiShellState = AIShellState(
                originalPrompt: input,
                generatedCommand: "No provider or model configured.",
                isGenerating: false,
                isEditing: true
            )
            return
        }

        do {
            let command = try await providerRouter.complete(
                provider: provider,
                modelID: modelID,
                messages: [
                    ChatMessage(role: "system", content: "Convert the request into a single shell command for zsh. Reply with only the command, no markdown, no explanation."),
                    ChatMessage(role: "user", content: "cwd=\(tab.currentWorkingDirectory?.path ?? "")\nrequest=\(input)")
                ]
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            tab.aiShellState = AIShellState(
                originalPrompt: input,
                generatedCommand: command,
                isGenerating: false,
                isEditing: false
            )
        } catch {
            tab.aiShellState = AIShellState(
                originalPrompt: input,
                generatedCommand: "Generation failed: \(error.localizedDescription)",
                isGenerating: false,
                isEditing: true
            )
        }
    }

    private func generateShellCommand(from input: String, for pane: TerminalPaneViewModel) async {
        pane.aiShellState = AIShellState(originalPrompt: input, generatedCommand: "", isGenerating: true, isEditing: false)

        guard let provider = provider(for: pane.appearance.aiProvider),
              let modelID = pane.appearance.aiModel else {
            pane.aiShellState = AIShellState(
                originalPrompt: input,
                generatedCommand: "No provider or model configured.",
                isGenerating: false,
                isEditing: true
            )
            return
        }

        do {
            let command = try await providerRouter.complete(
                provider: provider,
                modelID: modelID,
                messages: [
                    ChatMessage(role: "system", content: "Convert the request into a single shell command for zsh. Reply with only the command, no markdown, no explanation."),
                    ChatMessage(role: "user", content: "cwd=\(pane.currentWorkingDirectory?.path ?? "")\nrequest=\(input)")
                ]
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            pane.aiShellState = AIShellState(
                originalPrompt: input,
                generatedCommand: command,
                isGenerating: false,
                isEditing: false
            )
        } catch {
            pane.aiShellState = AIShellState(
                originalPrompt: input,
                generatedCommand: "Generation failed: \(error.localizedDescription)",
                isGenerating: false,
                isEditing: true
            )
        }
    }

    private func answerQuery(_ input: String, for tab: TerminalTabViewModel) async {
        tab.queryResponse = QueryResponseState(text: "", isStreaming: true, suggestions: [])

        if let mcpAnswer = mcpHost.localFilesystemAnswer(question: input, cwd: tab.currentWorkingDirectory) {
            tab.queryResponse = QueryResponseState(text: mcpAnswer, isStreaming: false, suggestions: [])
            return
        }

        guard let provider = provider(for: tab.appearance.aiProvider),
              let modelID = tab.appearance.aiModel else {
            tab.queryResponse = QueryResponseState(text: "No provider or model configured for query mode.", isStreaming: false, suggestions: [])
            return
        }

        do {
            let toolSummary = mcpHost.toolList().map(\.id).joined(separator: ", ")
            let stream = try providerRouter.streamResponse(
                provider: provider,
                modelID: modelID,
                messages: [
                    ChatMessage(role: "system", content: "You answer terminal questions concisely. If a shell command would help, include it in a fenced ```bash block. Active MCP tools: \(toolSummary)."),
                    ChatMessage(role: "user", content: "cwd=\(tab.currentWorkingDirectory?.path ?? "")\nlast_commands=\(tab.terminalContext().lastCommands.joined(separator: " | "))\nlast_output=\(tab.terminalContext().lastOutputSnippet)\n\nQuestion:\n\(input)")
                ]
            )

            for try await chunk in stream {
                tab.queryResponse.text.append(chunk)
            }
            tab.queryResponse.isStreaming = false
            tab.queryResponse.suggestions = extractSuggestions(from: tab.queryResponse.text)
        } catch {
            tab.queryResponse = QueryResponseState(
                text: "Query failed: \(error.localizedDescription)",
                isStreaming: false,
                suggestions: []
            )
        }
    }

    private func answerQuery(_ input: String, for pane: TerminalPaneViewModel) async {
        pane.queryResponse = QueryResponseState(text: "", isStreaming: true, suggestions: [])

        if let mcpAnswer = mcpHost.localFilesystemAnswer(question: input, cwd: pane.currentWorkingDirectory) {
            pane.queryResponse = QueryResponseState(text: mcpAnswer, isStreaming: false, suggestions: [])
            return
        }

        guard let provider = provider(for: pane.appearance.aiProvider),
              let modelID = pane.appearance.aiModel else {
            pane.queryResponse = QueryResponseState(text: "No provider or model configured for query mode.", isStreaming: false, suggestions: [])
            return
        }

        do {
            let toolSummary = mcpHost.toolList().map(\.id).joined(separator: ", ")
            let stream = try providerRouter.streamResponse(
                provider: provider,
                modelID: modelID,
                messages: [
                    ChatMessage(role: "system", content: "You answer terminal questions concisely. If a shell command would help, include it in a fenced ```bash block. Active MCP tools: \(toolSummary)."),
                    ChatMessage(role: "user", content: "cwd=\(pane.currentWorkingDirectory?.path ?? "")\nlast_commands=\(pane.terminalContext().lastCommands.joined(separator: " | "))\nlast_output=\(pane.terminalContext().lastOutputSnippet)\n\nQuestion:\n\(input)")
                ]
            )

            for try await chunk in stream {
                pane.queryResponse.text.append(chunk)
            }
            pane.queryResponse.isStreaming = false
            pane.queryResponse.suggestions = extractSuggestions(from: pane.queryResponse.text)
        } catch {
            pane.queryResponse = QueryResponseState(
                text: "Query failed: \(error.localizedDescription)",
                isStreaming: false,
                suggestions: []
            )
        }
    }

    private func extractSuggestions(from text: String) -> [QueryCommandSuggestion] {
        let pattern = "```bash\\s*([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let commandRange = Range(match.range(at: 1), in: text) else { return nil }
            let command = text[commandRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { return nil }
            return QueryCommandSuggestion(command: command)
        }
    }

    private func providerSecretAccount(forEnvVar envVar: String) -> String {
        switch envVar {
        case "ANTHROPIC_API_KEY": return "anthropic"
        case "OPENAI_API_KEY": return "openai"
        case "KIMI_API_KEY": return "kimi"
        case "OPENCLAW_API_KEY": return "openclaw"
        default: return envVar.lowercased()
        }
    }
}
