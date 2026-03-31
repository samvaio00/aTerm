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
    @Published var isCommandPalettePresented = false
    @Published var shellIntegrationMessage: String?

    private let sessionStore = SessionStore()
    private let themeStore = ThemeStore()
    private let profileStore = ProfileStore()
    private let providerStore = ProviderStore()
    private let agentStore = AgentStore()
    private let mcpStore = MCPStore()
    let oauthManager = OAuthManager()
    private var providerRouter: ProviderRouter
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
        providerRouter = ProviderRouter()
        providerRouter.oauthManager = oauthManager
        Log.debug("app", "AppModel.init() start")
        importedThemes = themeStore.loadImportedThemes()
        restoreProfiles()
        restoreProviders()
        restoreAgents()
        restoreMCPServers()
        showNerdFontBanner = !FontSupport.currentTerminalFontSupportsNerdGlyphs && !UserDefaults.standard.bool(forKey: nerdFontDismissalKey)
        isOnboardingPresented = !UserDefaults.standard.bool(forKey: onboardingDismissalKey)

        // Defer heavy work — run agent scanning off main thread
        Task.detached { [weak self] in
            guard let self else { return }
            let definitions = await self.agentDefinitions
            let detector = AgentDetector()
            let statuses = detector.detect(definitions)
            await MainActor.run {
                self.agentStatuses = statuses
                Log.debug("app", "Agent scan complete: \(statuses.count) agents")
            }
        }
        // MCP auto-start also deferred
        Task { @MainActor [weak self] in
            // Yield to let UI render first
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.autoStartGlobalMCPServers()
        }
        Task { await detectOllamaModels() }
        Log.debug("app", "AppModel.init() done, onboarding=\(isOnboardingPresented)")
    }

    var selectedTab: TerminalTabViewModel? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    var allThemes: [TerminalTheme] {
        // Single theme only - modern bright theme
        BuiltinThemes.all
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
        // For builtin providers, merge user changes (like OAuth client ID) into the existing entry
        if let existingIndex = providers.firstIndex(where: { $0.id == provider.id }),
           providers[existingIndex].isBuiltin {
            var existing = providers[existingIndex]
            if let newOAuth = provider.oauthConfig {
                existing.oauthConfig = newOAuth
            }
            providers[existingIndex] = existing
        } else {
            providers.removeAll(where: { $0.id == provider.id })
            providers.append(provider)
        }
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

    func submitInput(for pane: TerminalPaneViewModel) {
        Log.debug("input", "submitInput called, inputText='\(pane.inputText)', isAgent=\(pane.isAgentTab)")
        if pane.isAgentTab {
            let command = pane.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { return }
            pane.inputText = ""
            pane.sendTerminalCommand(command)
            return
        }

        let rawInput = pane.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }
        
        // Handle /chat-exit command
        if inputClassifier.isChatExitCommand(rawInput) {
            pane.exitChatMode()
            pane.inputText = ""
            return
        }
        
        // Handle /chat command - enter chat mode
        if inputClassifier.isChatCommand(rawInput) {
            let displayInput = inputClassifier.strippedOverrideInput(rawInput)
            pane.inputText = ""
            // Enter chat mode with separate chat model if configured
            pane.enterChatMode(providerID: pane.appearance.chatProvider, modelID: pane.appearance.chatModel)
            // Process the chat message immediately if there's content
            if !displayInput.isEmpty {
                Task { @MainActor in
                    await answerChatQuery(displayInput, for: pane)
                }
            }
            return
        }
        
        // If in chat mode, process all input as chat
        if pane.isChatModeActive {
            pane.inputText = ""
            Task { @MainActor in
                await answerChatQuery(rawInput, for: pane)
            }
            return
        }
        
        let displayInput = inputClassifier.strippedOverrideInput(rawInput)
        pane.inputText = ""

        Task { @MainActor in
            let provider = self.provider(for: pane.appearance.aiProvider)
            let classifierModelID = pane.appearance.classifierModel ?? pane.appearance.aiModel

            do {
                let result = try await inputClassifier.classify(
                    rawInput,
                    context: pane.terminalContext(),
                    provider: provider,
                    modelID: classifierModelID
                )

                guard let result else {
                    pane.submissionState = .waitingForDisambiguation(displayInput)
                    pane.modeIndicatorText = "AMBIGUOUS"
                    return
                }

                // Log classification explanation for debugging
                Log.debug("classifier", "Input: '\(displayInput)' -> \(result.mode.rawValue) (\(result.confidence.description): \(String(format: "%.2f", result.score)))")
                Log.debug("classifier", "Reasons: \(result.explanation.reasons.joined(separator: "; "))")

                await executeClassificationResult(result, input: displayInput, rawInput: rawInput, pane: pane)
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

    private func executeClassificationResult(
        _ result: ClassificationResult,
        input: String,
        rawInput: String,
        pane: TerminalPaneViewModel
    ) async {
        // Result available for potential feedback tracking

        switch result.mode {
        case .terminal:
            // Check for dangerous commands
            if inputClassifier.isDangerousCommand(input) {
                pane.queryResponse = QueryResponseState(
                    text: "⚠️ Warning: This command may be destructive. Press ⌘↵ to execute anyway, or try '!' prefix to ask about it.",
                    isStreaming: false,
                    suggestions: []
                )
                pane.modeIndicatorText = "WARNING"
                return
            }
            
            pane.clearAssistantState()
            pane.sendTerminalCommand(input)
            
        case .aiToShell:
            pane.queryResponse = QueryResponseState()
            pane.submissionState = .idle
            pane.modeIndicatorText = "\(InputMode.aiToShell.rawValue) (\(result.confidence.description))"
            await generateShellCommand(from: input, for: pane)
            
        case .query:
            pane.aiShellState = AIShellState()
            pane.submissionState = .idle
            pane.modeIndicatorText = "\(InputMode.query.rawValue) (\(result.confidence.description))"
            await answerQuery(input, for: pane)
        }
    }

    func resolveDisambiguation(as mode: InputMode, for pane: TerminalPaneViewModel) {
        guard case let .waitingForDisambiguation(input) = pane.submissionState else { return }
        pane.submissionState = .idle
        
        // Record user choice for learning
        ClassificationFeedbackStore.shared.recordDisambiguationChoice(
            input: input,
            chosenMode: mode,
            context: pane.terminalContext()
        )
        
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
    
    /// Records feedback when user corrects a classification
    func recordClassificationFeedback(
        input: String,
        originalMode: InputMode,
        correctedMode: InputMode,
        pane: TerminalPaneViewModel
    ) {
        ClassificationFeedbackStore.shared.recordCorrection(
            input: input,
            originalMode: originalMode,
            correctedMode: correctedMode,
            context: pane.terminalContext()
        )
    }

    func runGeneratedCommand(for pane: TerminalPaneViewModel) {
        let command = pane.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        pane.aiShellState = AIShellState()
        pane.sendTerminalCommand(command)
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
        // Check OAuth credentials first, then API key
        if let provider = provider(for: providerID),
           provider.authType == .oauthToken, provider.oauthConfig != nil {
            return oauthManager.isSignedIn(providerID: providerID)
        }
        return keychainStore.hasSecret(account: providerID)
    }

    func signInWithOAuth(providerID: String) async throws {
        guard let provider = provider(for: providerID) else { return }
        try await oauthManager.signIn(provider: provider)
        objectWillChange.send()
    }

    func signOutOAuth(providerID: String) throws {
        try oauthManager.signOut(providerID: providerID)
        objectWillChange.send()
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
        Log.debug("app", "completeOnboarding() called")
        isOnboardingPresented = false
        UserDefaults.standard.set(true, forKey: onboardingDismissalKey)
        Log.debug("app", "completeOnboarding() done, isOnboardingPresented=\(isOnboardingPresented)")
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
        // Always use fresh builtin providers to get model updates
        let builtinIDs = Set(BuiltinProviders.all.map { $0.id })
        if let stored = providerStore.load() {
            // Keep custom providers that aren't builtins
            let customProviders = stored.providers.filter { !builtinIDs.contains($0.id) }
            // Merge saved OAuth client IDs back into builtin providers
            let builtins = BuiltinProviders.all.map { p -> ModelProvider in
                guard var p = Optional(p),
                      let clientID = stored.oauthClientIDs[p.id],
                      var oauth = p.oauthConfig else { return p }
                oauth.clientID = clientID
                p.oauthConfig = oauth
                return p
            }
            providers = builtins + customProviders
            defaultProviderID = stored.defaultProviderID ?? "ollama"
            defaultModelID = stored.defaultModelID
        } else {
            providers = BuiltinProviders.all
            defaultProviderID = "ollama"
            defaultModelID = nil
        }
        persistProviders()
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
            startMCPServer(server, cwd: nil)
        }
    }

    private func detectOllamaModels() async {
        guard let ollamaProvider = providers.first(where: { $0.id == "ollama" }) else { return }

        // Probe Ollama API for running models
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }

            let detected = models.compactMap { model -> ModelDefinition? in
                guard let name = model["name"] as? String else { return nil }
                let size = model["size"] as? Int ?? 0
                let sizeGB = String(format: "%.1fGB", Double(size) / 1_073_741_824)
                return ModelDefinition(
                    id: name,
                    name: "\(name) (\(sizeGB))",
                    contextWindow: 128_000,
                    supportsStreaming: true
                )
            }

            guard !detected.isEmpty else { return }

            // Merge detected models with existing Ollama provider
            var updated = ollamaProvider
            let existingIDs = Set(updated.models.map(\.id))
            for model in detected where !existingIDs.contains(model.id) {
                updated.models.append(model)
            }

            // Update provider if new models found
            if updated.models.count != ollamaProvider.models.count {
                providers.removeAll(where: { $0.id == "ollama" })
                providers.append(updated)
                // Auto-select first Ollama model if none chosen yet
                if defaultProviderID == "ollama" && defaultModelID == nil {
                    defaultModelID = updated.models.first?.id
                }
                persistProviders()
                tabs.forEach(refreshProviderLabel(for:))
            }
        } catch {
            // Ollama not running — that's fine, skip silently
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
                // Mark unread if this tab is not selected
                if self.selectedTabID != tab.id {
                    tab.hasUnreadOutput = true
                }
                self.persistTabs()
                self.applyProjectConfigIfNeeded(to: tab, directory: tab.currentWorkingDirectory)
                self.refreshProviderLabel(for: tab)
            }
        }
    }

    private var lastAppliedConfigDirectories: [UUID: URL] = [:]

    private func persistProfiles() {
        profileStore.save(.init(defaultProfileID: defaultProfileID, profiles: profiles))
    }

    private func persistProviders() {
        // Collect OAuth client IDs from builtin providers (user-entered)
        var oauthClientIDs: [String: String] = [:]
        for p in providers where p.isBuiltin {
            if let clientID = p.oauthConfig?.clientID, !clientID.isEmpty {
                oauthClientIDs[p.id] = clientID
            }
        }
        providerStore.save(.init(
            providers: providers.filter { !$0.isBuiltin },
            defaultProviderID: defaultProviderID,
            defaultModelID: defaultModelID,
            oauthClientIDs: oauthClientIDs
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

    private func answerQuery(_ input: String, for pane: TerminalPaneViewModel) async {
        pane.queryResponse = QueryResponseState(text: "", isStreaming: true, suggestions: [])

        // Try local MCP answer first (quick offline fallback)
        if let mcpAnswer = mcpHost.localFilesystemAnswer(question: input, cwd: pane.currentWorkingDirectory) {
            pane.queryResponse = QueryResponseState(text: mcpAnswer, isStreaming: false, suggestions: [])
            pane.conversationHistory.addUserMessage(input)
            pane.conversationHistory.addAssistantMessage(mcpAnswer)
            return
        }

        guard let provider = provider(for: pane.appearance.aiProvider),
              let modelID = pane.appearance.aiModel else {
            pane.queryResponse = QueryResponseState(text: "No provider or model configured for query mode.", isStreaming: false, suggestions: [])
            return
        }

        do {
            // Build system message with context
            let systemPrompt = """
            You answer terminal questions concisely. If a shell command would help, include it in a fenced ```bash block.
            Current directory: \(pane.currentWorkingDirectory?.path ?? "unknown")
            Recent commands: \(pane.terminalContext().lastCommands.joined(separator: " | "))
            You have access to MCP tools. Use them when the user's question requires real data from their filesystem, git, or other connected services.
            """

            pane.conversationHistory.addSystemMessage(systemPrompt)
            let userMsg = "Last output: \(pane.terminalContext().lastOutputSnippet)\n\nQuestion: \(input)"
            pane.conversationHistory.addUserMessage(userMsg)

            pane.queryResponse = try await streamAIResponse(
                provider: provider,
                modelID: modelID,
                conversationHistory: pane.conversationHistory,
                initialResponse: pane.queryResponse
            )
        } catch {
            pane.queryResponse = QueryResponseState(
                text: "Query failed: \(error.localizedDescription)",
                isStreaming: false,
                suggestions: []
            )
        }
    }

    /// Answer query in chat mode (persistent context, uses separate chat model config)
    func answerChatQuery(_ input: String, for pane: TerminalPaneViewModel) async {
        // Reset response with streaming state
        pane.queryResponse = QueryResponseState(text: "", isStreaming: true, suggestions: [])

        // Use chat-specific provider/model if configured, otherwise fall back to default
        let provider: ModelProvider
        let modelID: String
        
        if let chatProviderID = pane.chatProviderID,
           let chatModelID = pane.chatModelID,
           let chatProvider = self.provider(for: chatProviderID) {
            provider = chatProvider
            modelID = chatModelID
        } else if let defaultProvider = self.provider(for: pane.appearance.aiProvider),
                  let defaultModel = pane.appearance.aiModel {
            provider = defaultProvider
            modelID = defaultModel
        } else {
            pane.queryResponse = QueryResponseState(
                text: "No provider or model configured for chat mode. Set up chat model in Settings.",
                isStreaming: false,
                suggestions: []
            )
            return
        }

        do {
            // Build chat system message (more conversational)
            let systemPrompt = """
            You are a helpful coding assistant. Answer questions about programming, terminal usage, and development workflows.
            Be conversational but concise. When shell commands would help, include them in ```bash blocks.
            Current directory: \(pane.currentWorkingDirectory?.path ?? "unknown")
            """

            // Initialize history if needed
            if pane.chatConversationHistory.messages.isEmpty {
                pane.chatConversationHistory.addSystemMessage(systemPrompt)
            }
            
            pane.chatConversationHistory.addUserMessage(input)

            // Stream response directly to pane (updates UI in real-time)
            try await streamAIResponseToPane(
                provider: provider,
                modelID: modelID,
                conversationHistory: pane.chatConversationHistory,
                pane: pane
            )
        } catch {
            pane.queryResponse = QueryResponseState(
                text: "Chat query failed: \(error.localizedDescription)",
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

    /// Shared AI response streaming logic for query and chat modes
    /// Returns updated QueryResponseState since struct properties can't be passed as inout
    private func streamAIResponse(
        provider: ModelProvider,
        modelID: String,
        conversationHistory: ConversationHistory,
        initialResponse: QueryResponseState
    ) async throws -> QueryResponseState {
        var queryResponse = initialResponse
        let toolSchemas = mcpHost.toolSchemas()
        let maxToolRoundTrips = 5

        // Tool call loop: stream response, execute any tool calls, feed results back
        for _ in 0..<maxToolRoundTrips {
            var responseText = ""
            var toolCalls: [ToolCallRequest] = []

            if toolSchemas.isEmpty {
                // No tools available — use simple text-only streaming
                let stream = try providerRouter.streamResponse(
                    provider: provider,
                    modelID: modelID,
                    messages: conversationHistory.simplifiedMessages
                )
                for try await chunk in stream {
                    responseText.append(chunk)
                    queryResponse.text.append(chunk)
                }
            } else {
                // Stream with tool support
                let stream = try providerRouter.streamWithTools(
                    provider: provider,
                    modelID: modelID,
                    richMessages: conversationHistory.messages,
                    tools: toolSchemas
                )
                for try await event in stream {
                    switch event {
                    case .text(let chunk):
                        responseText.append(chunk)
                        queryResponse.text.append(chunk)
                    case .toolCall(let request):
                        toolCalls.append(request)
                    }
                }
            }

            if toolCalls.isEmpty {
                // No tool calls — we're done
                conversationHistory.addAssistantMessage(responseText)
                break
            }

            // Execute tool calls and collect results
            var toolResults: [ToolCallResult] = []
            for call in toolCalls {
                do {
                    let result = try await mcpHost.callTool(name: call.name, arguments: call.arguments)
                    toolResults.append(ToolCallResult(toolCallID: call.id, name: call.name, content: result))
                    queryResponse.text.append("\n\n*[Used tool: \(call.name)]*\n")
                } catch {
                    let errorMsg = "Tool '\(call.name)' failed: \(error.localizedDescription)"
                    toolResults.append(ToolCallResult(toolCallID: call.id, name: call.name, content: errorMsg))
                    queryResponse.text.append("\n\n*[\(errorMsg)]*\n")
                }
            }

            // Add the assistant message with tool calls and results to history
            conversationHistory.addAssistantToolCallMessage(
                text: responseText,
                toolCalls: toolCalls,
                toolResults: toolResults
            )
            // Loop continues — next iteration sends history with tool results,
            // prompting the model to generate a final answer
        }

        queryResponse.isStreaming = false
        queryResponse.suggestions = extractSuggestions(from: queryResponse.text)
        return queryResponse
    }
    
    /// Streams AI response directly to pane (updates UI in real-time)
    private func streamAIResponseToPane(
        provider: ModelProvider,
        modelID: String,
        conversationHistory: ConversationHistory,
        pane: TerminalPaneViewModel
    ) async throws {
        let toolSchemas = mcpHost.toolSchemas()
        let maxToolRoundTrips = 5
        var fullText = ""

        // Tool call loop: stream response, execute any tool calls, feed results back
        for _ in 0..<maxToolRoundTrips {
            var responseText = ""
            var toolCalls: [ToolCallRequest] = []

            if toolSchemas.isEmpty {
                // No tools available — use simple text-only streaming
                let stream = try providerRouter.streamResponse(
                    provider: provider,
                    modelID: modelID,
                    messages: conversationHistory.simplifiedMessages
                )
                for try await chunk in stream {
                    responseText.append(chunk)
                    fullText.append(chunk)
                    // Update UI on main thread
                    await MainActor.run {
                        pane.queryResponse.text = fullText
                    }
                }
            } else {
                // Stream with tool support
                let stream = try providerRouter.streamWithTools(
                    provider: provider,
                    modelID: modelID,
                    richMessages: conversationHistory.messages,
                    tools: toolSchemas
                )
                for try await event in stream {
                    switch event {
                    case .text(let chunk):
                        responseText.append(chunk)
                        fullText.append(chunk)
                        await MainActor.run {
                            pane.queryResponse.text = fullText
                        }
                    case .toolCall(let request):
                        toolCalls.append(request)
                    }
                }
            }

            if toolCalls.isEmpty {
                // No tool calls — we're done
                conversationHistory.addAssistantMessage(responseText)
                break
            }

            // Execute tool calls and collect results
            var toolResults: [ToolCallResult] = []
            for call in toolCalls {
                do {
                    let result = try await mcpHost.callTool(name: call.name, arguments: call.arguments)
                    toolResults.append(ToolCallResult(toolCallID: call.id, name: call.name, content: result))
                    let toolNote = "\n\n*[Used tool: \(call.name)]*\n"
                    fullText.append(toolNote)
                    await MainActor.run {
                        pane.queryResponse.text = fullText
                    }
                } catch {
                    let errorMsg = "Tool '\(call.name)' failed: \(error.localizedDescription)"
                    toolResults.append(ToolCallResult(toolCallID: call.id, name: call.name, content: errorMsg))
                    let errorNote = "\n\n*[\(errorMsg)]*\n"
                    fullText.append(errorNote)
                    await MainActor.run {
                        pane.queryResponse.text = fullText
                    }
                }
            }

            // Add the assistant message with tool calls and results to history
            conversationHistory.addAssistantToolCallMessage(
                text: responseText,
                toolCalls: toolCalls,
                toolResults: toolResults
            )
        }

        // Final update with suggestions and streaming complete
        await MainActor.run {
            pane.queryResponse.isStreaming = false
            pane.queryResponse.suggestions = self.extractSuggestions(from: fullText)
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

    // MARK: - WindowModel Support (called by per-window WindowModel)

    func restoreTabViewModels() -> [TerminalTabViewModel] {
        let storedTabs = sessionStore.loadTabs()
        return storedTabs.compactMap { descriptor in
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
    }

    func makeShellTab(workingDirectory: URL? = nil) -> TerminalTabViewModel {
        let tab = TerminalTabViewModel(
            initialTitle: "zsh",
            workingDirectory: workingDirectory,
            profile: defaultProfile
        )
        applyDefaultProviderIfNeeded(to: tab)
        return tab
    }

    func makeAgentTab(_ definition: AgentDefinition, workingDirectory: URL?) -> TerminalTabViewModel? {
        guard let executablePath = agentStatuses[definition.id]?.executablePath else { return nil }

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
        applyDefaultProviderIfNeeded(to: tab)
        return tab
    }

    func applyProjectConfigIfNeeded(to tab: TerminalTabViewModel, directory: URL?) {
        guard let directory, let config = TermConfig.load(from: directory) else { return }

        if lastAppliedConfigDirectories[tab.id] == directory { return }
        lastAppliedConfigDirectories[tab.id] = directory

        if let profileName = config.profileName,
           let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(profileName) == .orderedSame }) {
            tab.applyProfile(profile)
        }

        if config.aiProvider != nil || config.aiModel != nil || config.classifierModel != nil {
            var appearance = tab.appearance
            if let aiProvider = config.aiProvider { appearance.aiProvider = aiProvider }
            if let aiModel = config.aiModel { appearance.aiModel = aiModel }
            if let classifierModel = config.classifierModel { appearance.classifierModel = classifierModel }
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

    func applyDefaultProviderIfNeeded(to tab: TerminalTabViewModel) {
        tab.panes.forEach(applyDefaultProviderIfNeeded(to:))
        refreshProviderLabel(for: tab)
    }

    func refreshProviderLabel(for tab: TerminalTabViewModel) {
        tab.panes.forEach(refreshProviderLabel(for:))
    }

    func persistProfilesPublic() {
        persistProfiles()
    }

    func persistTabs(_ tabs: [TerminalTabViewModel], windowID: UUID) {
        // For now, persist only the primary window's tabs (first window to persist wins)
        sessionStore.saveTabs(
            tabs.map {
                SessionStore.StoredTab(
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
}
