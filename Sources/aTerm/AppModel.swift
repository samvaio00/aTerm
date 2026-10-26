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
        Task {
            // Yield so the main window and Settings (if opened) can lay out before network + provider writes.
            try? await Task.sleep(nanoseconds: 400_000_000)
            await refreshOllamaModels()
        }
        Log.debug("app", "AppModel.init() done, onboarding=\(isOnboardingPresented)")
    }

    var selectedTab: TerminalTabViewModel? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    var allThemes: [TerminalTheme] {
        // Built-ins plus any themes imported by the user.
        importedThemes + BuiltinThemes.all
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

    /// Asks the AI to explain the most recent failed command and suggest a fix.
    func explainLastFailure(for pane: TerminalPaneViewModel?, customQuestion: String? = nil, inlinePrepared: Bool = false) {
        guard let pane else { return }
        if !inlinePrepared {
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
        }
        let ctx = pane.terminalContext()
        var prompt = "Explain why the last command failed and suggest a concrete fix or corrected command."
        if let customQuestion, !customQuestion.isEmpty {
            prompt += "\nUser note: \(customQuestion)"
        }
        if let last = ctx.lastCommands.last { prompt += "\nLast command: \(last)" }
        if let code = ctx.lastExitCode { prompt += "\nExit code: \(code)" }
        if !ctx.recentFailures.isEmpty { prompt += "\nRecent failures: \(ctx.recentFailures.joined(separator: ", "))" }
        if !ctx.lastOutputSnippet.isEmpty { prompt += "\nTerminal output (tail): \(ctx.lastOutputSnippet)" }
        pane.activeAITask?.cancel()
        pane.activeAITask = Task { @MainActor [weak self, weak pane] in
            guard let self, let pane else { return }
            await self.answerQuery(prompt, for: pane, inlinePrepared: true)
        }
    }

    /// Generates a corrected version of the most recent failed command.
    func fixLastCommand(for pane: TerminalPaneViewModel?, customHint: String? = nil, inlinePrepared: Bool = false) {
        guard let pane else { return }
        if !inlinePrepared {
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
        }
        let ctx = pane.terminalContext()
        let lastCommand = ctx.recentFailures.last ?? ctx.lastCommands.last
        guard let last = lastCommand else {
            pane.writeTerminalText("\u{1B}[33mNo recent command in history to fix.\u{1B}[0m\r\n")
            pane.finishInlineAIOutput()
            return
        }
        var request = "Fix the failed command: \(last)"
        if let code = ctx.lastExitCode { request += " (exit code \(code))" }
        if let customHint, !customHint.isEmpty { request += ". Hint: \(customHint)" }
        if !ctx.lastOutputSnippet.isEmpty { request += ". Terminal output: \(ctx.lastOutputSnippet)" }
        pane.activeAITask?.cancel()
        pane.activeAITask = Task { @MainActor [weak self, weak pane] in
            guard let self, let pane else { return }
            pane.writeTerminalText("\u{1B}[33m⚡ Generating fix for `\(last)`...\u{1B}[0m")
            await self.generateShellCommand(from: request, for: pane, showOverlayCard: false)
            guard !Task.isCancelled else { return }
            pane.clearCurrentTerminalLine()
            let generated = pane.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            pane.aiShellState = AIShellState()
            if generated.isEmpty || generated.hasPrefix("Generation failed") || generated.hasPrefix("No provider") {
                pane.writeTerminalText("\u{1B}[31m\(generated.isEmpty ? "Could not generate a fix." : generated)\u{1B}[0m\r\n")
                pane.finishInlineAIOutput()
            } else {
                pane.writeTerminalText("\u{1B}[32;1m✦ Suggested fix:\u{1B}[0m \u{1B}[1m\(generated)\u{1B}[0m \u{1B}[90m(press Return to run)\u{1B}[0m\r\n")
                pane.prefillShellPrompt(with: generated)
            }
        }
    }

    /// Returns an AI provider/model that can actually be used for this pane.
    /// Falls back to local Ollama when the configured provider requires missing credentials.
    func usableAIProviderAndModel(for pane: TerminalPaneViewModel) -> (provider: ModelProvider?, modelID: String?) {
        let configuredProvider = provider(for: pane.appearance.aiProvider)
        let configuredModelID = pane.appearance.aiModel ?? pane.appearance.classifierModel

        if let configuredProvider {
            let needsCredential = configuredProvider.authType != .none
            let hasCredential = !((try? keychainStore.readSecret(account: configuredProvider.id)) ?? "").isEmpty
            if !needsCredential || hasCredential {
                return (configuredProvider, configuredModelID ?? configuredProvider.models.first?.id)
            }
        }

        if let ollama = provider(for: "ollama"), !ollama.models.isEmpty {
            let preferred = ollama.models.first(where: { !$0.id.lowercased().contains("cloud") }) ?? ollama.models.first
            return (ollama, preferred?.id)
        }

        return (nil, nil)
    }

    func splitSelectedPane(_ orientation: PaneSplitOrientation) {
        selectedTab?.splitActivePane(orientation: orientation)
        if let selectedTab {
            configure(selectedTab)
        }
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
        // For builtin providers, merge OAuth and model list (custom models + fetched models) into the existing entry
        if let existingIndex = providers.firstIndex(where: { $0.id == provider.id }),
           providers[existingIndex].isBuiltin {
            var existing = providers[existingIndex]
            if let newOAuth = provider.oauthConfig {
                existing.oauthConfig = newOAuth
            }
            existing.models = provider.models
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
        pane.inputText = ""
        submitSmartInput(rawInput: rawInput, for: pane, lineAlreadyBufferedInShell: false)
    }

    /// Smart routing for a line typed at the zsh prompt (PTY already holds the text; Return was not sent yet).
    func submitSmartLineFromPrompt(_ rawInput: String, for pane: TerminalPaneViewModel) {
        submitSmartInput(rawInput: rawInput, for: pane, lineAlreadyBufferedInShell: true)
    }

    private func submitSmartInput(rawInput: String, for pane: TerminalPaneViewModel, lineAlreadyBufferedInShell: Bool) {
        let rawInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }

        if pane.isAgentTab {
            pane.sendTerminalCommand(rawInput)
            return
        }

        let lowerInput = rawInput.lowercased()

        // 1. Handle inline slash commands (/exit, /chat, /explain, /fix, /model, /clear, /help)
        if inputClassifier.isChatExitCommand(rawInput) {
            if pane.isChatModeActive {
                pane.exitChatMode()
            } else if lineAlreadyBufferedInShell {
                pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: true)
                pane.writeTerminalText("\u{1B}[90mNot in chat mode. Use `exit` to close the shell.\u{1B}[0m\r\n")
                pane.finishInlineAIOutput()
            }
            return
        }

        if inputClassifier.isChatCommand(rawInput) {
            let displayInput = inputClassifier.strippedOverrideInput(rawInput)
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            pane.enterChatMode(
                providerID: pane.appearance.chatProvider,
                modelID: pane.appearance.chatModel,
                showInitialPrompt: displayInput.isEmpty
            )
            if !displayInput.isEmpty {
                pane.writeTerminalText("\u{1B}[32;1mchat>\u{1B}[0m \(displayInput)\r\n")
                pane.activeAITask?.cancel()
                pane.activeAITask = Task { @MainActor [weak self, weak pane] in
                    guard let self, let pane else { return }
                    await self.answerChatQuery(displayInput, for: pane)
                }
            }
            return
        }

        if lowerInput == "/explain" || lowerInput.hasPrefix("/explain ") || lowerInput == "/why" || lowerInput.hasPrefix("/why ") || lowerInput == "explain" {
            let customNote = rawInput.drop(while: { !$0.isWhitespace }).trimmingCharacters(in: .whitespacesAndNewlines)
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            explainLastFailure(for: pane, customQuestion: customNote.isEmpty ? nil : customNote, inlinePrepared: true)
            return
        }

        if lowerInput == "/fix" || lowerInput.hasPrefix("/fix ") || lowerInput == "fix" {
            let customHint = rawInput.drop(while: { !$0.isWhitespace }).trimmingCharacters(in: .whitespacesAndNewlines)
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            fixLastCommand(for: pane, customHint: customHint.isEmpty ? nil : customHint, inlinePrepared: true)
            return
        }

        if lowerInput == "/clear" || lowerInput == "/reset" {
            pane.conversationHistory.clear()
            pane.chatConversationHistory.clear()
            pane.clearAssistantState()
            pane.clearScrollback()
            if lineAlreadyBufferedInShell {
                pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: true)
                pane.finishInlineAIOutput()
            }
            return
        }

        if lowerInput == "/model" || lowerInput == "/models" || lowerInput.hasPrefix("/model ") || lowerInput.hasPrefix("/models ") {
            let query = rawInput.drop(while: { !$0.isWhitespace }).trimmingCharacters(in: .whitespacesAndNewlines)
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            handleInlineModelCommand(query: query, for: pane)
            pane.finishInlineAIOutput()
            return
        }

        if lowerInput == "/smart" || lowerInput == "/mode smart" {
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            pane.aiRoutingMode = .smart
            pane.writeTerminalText("\u{1B}[32;1m✦ Routing mode set to Smart:\u{1B}[0m natural language routes to AI automatically; shell commands run directly in zsh.\r\n")
            pane.finishInlineAIOutput()
            return
        }

        if lowerInput == "/shell" || lowerInput == "/mode shell" {
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            pane.aiRoutingMode = .shell
            pane.writeTerminalText("\u{1B}[36;1m✦ Routing mode set to Shell-only:\u{1B}[0m unprefixed lines go directly to zsh; use \u{1B}[1m?\u{1B}[0m, \u{1B}[1m??\u{1B}[0m, \u{1B}[1m!\u{1B}[0m, or \u{1B}[1m/commands\u{1B}[0m for AI.\r\n")
            pane.finishInlineAIOutput()
            return
        }

        if lowerInput == "/mode" {
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            let modeDesc = pane.aiRoutingMode == .smart
                ? "\u{1B}[33;1mSmart\u{1B}[0m (natural language + shell commands)"
                : "\u{1B}[36;1mShell-only\u{1B}[0m (pure zsh unless prefixed with ?, ??, !, or /)"
            pane.writeTerminalText("\u{1B}[36;1mActive Routing Mode:\u{1B}[0m \(modeDesc)\r\n\u{1B}[90mRun `/smart` or `/shell` to switch.\u{1B}[0m\r\n")
            pane.finishInlineAIOutput()
            return
        }

        if lowerInput == "/help" || lowerInput == "/commands" || lowerInput == "/ai" || lowerInput == "/?" {
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            writeInlineAIHelp(to: pane)
            pane.finishInlineAIOutput()
            return
        }

        if pane.isChatModeActive {
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            pane.activeAITask?.cancel()
            pane.activeAITask = Task { @MainActor [weak self, weak pane] in
                guard let self, let pane else { return }
                await self.answerChatQuery(rawInput, for: pane)
            }
            return
        }

        let displayInput = inputClassifier.strippedOverrideInput(rawInput)
        let trimmedRaw = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Synchronous pre-parse: immediately route shell commands to PTY with zero AI delay,
        // and immediately route clear AI requests to their handler without a redundant LLM classification round-trip.
        if let fastResult = inputClassifier.fastClassify(trimmedRaw, context: pane.terminalContext(), routingMode: pane.aiRoutingMode) {
            Log.debug("classifier", "Fast-path: '\(displayInput)' -> \(fastResult.mode.rawValue) (\(fastResult.confidence.description): \(String(format: "%.2f", fastResult.score)))")
            if fastResult.mode == .terminal && !inputClassifier.isDangerousCommand(displayInput) && !trimmedRaw.hasPrefix("$") {
                pane.clearAssistantState()
                if lineAlreadyBufferedInShell {
                    pane.sendBufferedReturnToShell(commandForHistory: displayInput)
                } else {
                    pane.sendTerminalCommand(displayInput)
                }
                return
            }

            if fastResult.mode != .terminal {
                pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            }
            pane.activeAITask?.cancel()
            pane.activeAITask = Task { @MainActor [weak self, weak pane] in
                guard let self, let pane else { return }
                await self.executeClassificationResult(
                    fastResult,
                    input: displayInput,
                    rawInput: rawInput,
                    pane: pane,
                    lineAlreadyBufferedInShell: lineAlreadyBufferedInShell,
                    inlinePrepared: fastResult.mode != .terminal
                )
            }
            return
        }

        pane.activeAITask?.cancel()
        pane.activeAITask = Task { @MainActor [weak self, weak pane] in
            guard let self, let pane else { return }
            let (provider, classifierModelIDOpt) = self.usableAIProviderAndModel(for: pane)
            let classifierModelID = classifierModelIDOpt ?? pane.appearance.classifierModel ?? pane.appearance.aiModel

            do {
                let result = try await self.inputClassifier.classify(
                    rawInput,
                    context: pane.terminalContext(),
                    provider: provider,
                    modelID: classifierModelID
                )
                guard !Task.isCancelled else { return }

                guard let result else {
                    if lineAlreadyBufferedInShell {
                        pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: true)
                    }
                    pane.submissionState = .waitingForDisambiguation(displayInput)
                    pane.modeIndicatorText = "AMBIGUOUS"
                    return
                }

                Log.debug("classifier", "Input: '\(displayInput)' -> \(result.mode.rawValue) (\(result.confidence.description): \(String(format: "%.2f", result.score)))")
                Log.debug("classifier", "Reasons: \(result.explanation.reasons.joined(separator: "; "))")

                await self.executeClassificationResult(
                    result,
                    input: displayInput,
                    rawInput: rawInput,
                    pane: pane,
                    lineAlreadyBufferedInShell: lineAlreadyBufferedInShell
                )
            } catch {
                guard !Task.isCancelled else { return }
                if lineAlreadyBufferedInShell {
                    pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: true)
                    pane.writeTerminalText("\u{1B}[31mClassification failed: \(error.localizedDescription)\u{1B}[0m\r\n")
                    pane.finishInlineAIOutput()
                } else {
                    pane.queryResponse = QueryResponseState(
                        text: "Classification failed: \(error.localizedDescription)",
                        isStreaming: false,
                        suggestions: []
                    )
                }
                pane.modeIndicatorText = "ERROR"
            }
        }
    }

    private func handleInlineModelCommand(query: String, for pane: TerminalPaneViewModel) {
        let items = modelPickerItems
        if query.isEmpty {
            let (activeProv, activeMod) = usableAIProviderAndModel(for: pane)
            let currentLabel = activeProv != nil ? "\(activeProv!.name) · \(activeMod ?? "default")" : pane.activeProviderName
            pane.writeTerminalText("\u{1B}[36;1mActive AI Model:\u{1B}[0m \(currentLabel)\r\n")
            if !items.isEmpty {
                let preview = items.prefix(8).map { "\($0.provider.id)/\($0.model.id)" }.joined(separator: ", ")
                pane.writeTerminalText("\u{1B}[90mAvailable: \(preview)\(items.count > 8 ? ", ..." : "")\u{1B}[0m\r\n")
                pane.writeTerminalText("\u{1B}[90mTip: Run `/model <name>` to switch inline or press ⌘M to open the model picker.\u{1B}[0m\r\n")
            }
            return
        }

        let needle = query.lowercased()
        let match = items.first(where: {
            $0.model.id.lowercased() == needle ||
            $0.model.name.lowercased() == needle ||
            "\($0.provider.id)/\($0.model.id)".lowercased() == needle
        }) ?? items.first(where: {
            $0.model.id.lowercased().contains(needle) ||
            $0.model.name.lowercased().contains(needle) ||
            $0.provider.id.lowercased().contains(needle) ||
            $0.provider.name.lowercased().contains(needle)
        })

        if let match {
            pane.appearance.aiProvider = match.provider.id
            pane.appearance.aiModel = match.model.id
            refreshProviderLabel(for: pane)
            pane.markStateChanged()
            pane.writeTerminalText("\u{1B}[32;1m✦ Switched AI model to:\u{1B}[0m \(match.provider.name) · \(match.model.name)\r\n")
        } else {
            pane.writeTerminalText("\u{1B}[33mNo model matching '\(query)' found.\u{1B}[0m\r\n")
        }
    }

    func writeInlineAIHelp(to pane: TerminalPaneViewModel) {
        let help = """
        \u{1B}[36;1m╭──────────────────────────────────────────────────────────────────────────────╮\u{1B}[0m
        \u{1B}[36;1m│                       aTerm Usage & /Commands Reference                      │\u{1B}[0m
        \u{1B}[36;1m╰──────────────────────────────────────────────────────────────────────────────╯\u{1B}[0m
        \u{1B}[1mHOW IT WORKS\u{1B}[0m
          Type directly at your zsh prompt. Standard shell commands (\u{1B}[32mls\u{1B}[0m, \u{1B}[32mgit\u{1B}[0m, \u{1B}[32mvim\u{1B}[0m, pipes)
          run natively in the PTY, while natural language & slash commands invoke AI inline.

        \u{1B}[1mSLASH (/) COMMANDS\u{1B}[0m
          \u{1B}[35;1m/help\u{1B}[0m, \u{1B}[35;1m/commands\u{1B}[0m, \u{1B}[35;1m/?\u{1B}[0m      Display this usage and command reference inline
          \u{1B}[35;1m/chat [message]\u{1B}[0m          Enter multi-turn AI chat mode (or send an initial message)
          \u{1B}[35;1m/exit\u{1B}[0m, \u{1B}[35;1m/chat-exit\u{1B}[0m        Exit AI chat mode and return to the zsh shell prompt
          \u{1B}[35;1m/ask <question>\u{1B}[0m          Ask AI a question and stream the answer inline
          \u{1B}[35;1m/cmd <task>\u{1B}[0m              Generate & run a shell command from natural language
          \u{1B}[35;1m/explain [note]\u{1B}[0m          Explain why the last command failed and suggest a fix
          \u{1B}[35;1m/fix [hint]\u{1B}[0m              Generate a corrected command and prefill your zsh prompt
          \u{1B}[35;1m/model [name]\u{1B}[0m            Show active model or switch inline (e.g. \u{1B}[90m/model claude\u{1B}[0m)
          \u{1B}[35;1m/smart\u{1B}[0m, \u{1B}[35;1m/shell\u{1B}[0m, \u{1B}[35;1m/mode\u{1B}[0m    Inspect or switch between Smart and Shell-only routing
          \u{1B}[35;1m/clear\u{1B}[0m, \u{1B}[35;1m/reset\u{1B}[0m           Clear terminal scrollback and reset AI conversation memory

        \u{1B}[1mINLINE SHORTHAND PREFIXES\u{1B}[0m
          \u{1B}[36;1m? <question>\u{1B}[0m             Ask AI a question inline (also \u{1B}[36;1m!<question>\u{1B}[0m)
          \u{1B}[33;1m?? <task>\u{1B}[0m                Generate & execute a zsh command (also \u{1B}[33;1m><task>\u{1B}[0m)
          \u{1B}[32;1m$ <command>\u{1B}[0m              Force direct shell execution without AI classification
          \u{1B}[35;1mexplain\u{1B}[0m / \u{1B}[35;1mfix\u{1B}[0m            Quick aliases for \u{1B}[35m/explain\u{1B}[0m and \u{1B}[35m/fix\u{1B}[0m after a non-zero exit

        \u{1B}[1mKEYBOARD SHORTCUTS\u{1B}[0m
          \u{1B}[90m⌘T\u{1B}[0m New Tab   \u{1B}[90m⌘D\u{1B}[0m Split Right   \u{1B}[90m⇧⌘D\u{1B}[0m Split Down   \u{1B}[90m⌘M\u{1B}[0m Model Picker   \u{1B}[90m⌘P\u{1B}[0m Command Palette
          \u{1B}[90m⌘F\u{1B}[0m Find      \u{1B}[90m⌘K\u{1B}[0m Clear         \u{1B}[90m⌃C\u{1B}[0m Cancel AI     \u{1B}[90m⇧⌘/\u{1B}[0m Open Full Help Guide\r\n
        """
        pane.writeTerminalText(help)
    }

    func handleChatMessage(_ message: String, for pane: TerminalPaneViewModel) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower == "/help" || lower == "/commands" || lower == "/?" || lower == "/ai" {
            writeInlineAIHelp(to: pane)
            pane.showChatPrompt(leadingNewline: false)
            return
        }

        if lower == "/model" || lower == "/models" || lower.hasPrefix("/model ") || lower.hasPrefix("/models ") {
            let query = trimmed.drop(while: { !$0.isWhitespace }).trimmingCharacters(in: .whitespacesAndNewlines)
            handleInlineModelCommand(query: query, for: pane)
            pane.showChatPrompt(leadingNewline: false)
            return
        }

        if lower == "/smart" || lower == "/mode smart" {
            pane.aiRoutingMode = .smart
            pane.writeTerminalText("\u{1B}[32;1m✦ Routing mode set to Smart.\u{1B}[0m\r\n")
            pane.showChatPrompt(leadingNewline: false)
            return
        }

        if lower == "/shell" || lower == "/mode shell" {
            pane.aiRoutingMode = .shell
            pane.writeTerminalText("\u{1B}[36;1m✦ Routing mode set to Shell-only.\u{1B}[0m\r\n")
            pane.showChatPrompt(leadingNewline: false)
            return
        }

        pane.activeAITask?.cancel()
        pane.activeAITask = Task { @MainActor [weak self, weak pane] in
            guard let self, let pane else { return }
            await self.answerChatQuery(trimmed, for: pane)
        }
    }

    private func executeClassificationResult(
        _ result: ClassificationResult,
        input: String,
        rawInput: String,
        pane: TerminalPaneViewModel,
        lineAlreadyBufferedInShell: Bool,
        inlinePrepared: Bool = false
    ) async {
        switch result.mode {
        case .terminal:
            if inputClassifier.isDangerousCommand(input) {
                if lineAlreadyBufferedInShell {
                    if !inlinePrepared {
                        pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: true)
                    }
                    pane.writeTerminalText("\u{1B}[33;1m⚠️ Warning:\u{1B}[0m `\u{1B}[1m\(input)\u{1B}[0m` may be destructive. Pre-filling at prompt — press \u{1B}[1m$\(input)\u{1B}[0m or review carefully.\r\n")
                    pane.prefillShellPrompt(with: input)
                } else {
                    pane.queryResponse = QueryResponseState(
                        text: "⚠️ Warning: This command may be destructive. Press ⌘↵ to execute anyway, or try '!' prefix to ask about it.",
                        isStreaming: false,
                        suggestions: []
                    )
                }
                pane.modeIndicatorText = "WARNING"
                return
            }

            pane.clearAssistantState()
            if lineAlreadyBufferedInShell {
                // If user used an explicit '$' prefix, strip it and replace the buffered line
                let trimmedRaw = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedRaw.hasPrefix("$") {
                    if !inlinePrepared {
                        pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: true)
                    }
                    pane.executeGeneratedShellCommand(input)
                } else {
                    pane.sendBufferedReturnToShell(commandForHistory: input)
                }
            } else {
                pane.sendTerminalCommand(input)
            }

        case .aiToShell:
            if !inlinePrepared {
                pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            }
            pane.queryResponse = QueryResponseState()
            pane.submissionState = .idle
            pane.modeIndicatorText = "\(InputMode.aiToShell.rawValue) (\(result.confidence.description))"
            pane.writeTerminalText("\u{1B}[33m⚡ Generating command...\u{1B}[0m")
            await generateShellCommand(from: input, for: pane, showOverlayCard: false)
            guard !Task.isCancelled else { return }
            pane.clearCurrentTerminalLine()

            let generated = pane.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if generated.isEmpty || generated.hasPrefix("Generation failed") || generated.hasPrefix("No provider") {
                pane.aiShellState = AIShellState()
                pane.writeTerminalText("\u{1B}[31m\(generated.isEmpty ? "Could not generate command." : generated)\u{1B}[0m\r\n")
                pane.finishInlineAIOutput()
            } else if inputClassifier.isDangerousCommand(generated) || !Self.hasBalancedQuotes(generated) || generated.contains("\n") {
                pane.aiShellState = AIShellState()
                if inputClassifier.isDangerousCommand(generated) {
                    pane.writeTerminalText("\u{1B}[33;1m⚠️ Review potentially destructive command before running:\u{1B}[0m\r\n")
                }
                let singleLine = generated.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? generated
                pane.prefillShellPrompt(with: singleLine)
            } else {
                pane.aiShellState = AIShellState()
                pane.executeGeneratedShellCommand(generated)
            }

        case .query:
            if !inlinePrepared {
                pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: lineAlreadyBufferedInShell)
            }
            pane.aiShellState = AIShellState()
            pane.submissionState = .idle
            pane.modeIndicatorText = "\(InputMode.query.rawValue) (\(result.confidence.description))"
            await answerQuery(input, for: pane, inlinePrepared: true)
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
            pane.executeGeneratedShellCommand(input)
        case .aiToShell:
            pane.modeIndicatorText = InputMode.aiToShell.rawValue
            pane.activeAITask?.cancel()
            pane.activeAITask = Task { @MainActor [weak self, weak pane] in
                guard let self, let pane else { return }
                pane.writeTerminalText("\u{1B}[33m⚡ Generating command...\u{1B}[0m")
                await self.generateShellCommand(from: input, for: pane, showOverlayCard: false)
                guard !Task.isCancelled else { return }
                pane.clearCurrentTerminalLine()
                let generated = pane.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                pane.aiShellState = AIShellState()
                if generated.isEmpty || generated.hasPrefix("Generation failed") || generated.hasPrefix("No provider") {
                    pane.writeTerminalText("\u{1B}[31m\(generated.isEmpty ? "Could not generate command." : generated)\u{1B}[0m\r\n")
                    pane.finishInlineAIOutput()
                } else if self.inputClassifier.isDangerousCommand(generated) {
                    pane.writeTerminalText("\u{1B}[33;1m⚠️ Review potentially destructive command before running:\u{1B}[0m\r\n")
                    pane.prefillShellPrompt(with: generated)
                } else {
                    pane.executeGeneratedShellCommand(generated)
                }
            }
        case .query:
            pane.modeIndicatorText = InputMode.query.rawValue
            pane.activeAITask?.cancel()
            pane.activeAITask = Task { @MainActor [weak self, weak pane] in
                guard let self, let pane else { return }
                await self.answerQuery(input, for: pane, inlinePrepared: true)
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

    /// `.app` installs use `Contents/Resources`; `swift build` keeps `aTerm_aTerm.bundle` next to the executable.
    private static func bundledShellIntegrationURL() -> URL? {
        if let u = Bundle.main.url(forResource: "shell-integration", withExtension: "zsh", subdirectory: "Resources") {
            return u
        }
        guard let bin = Bundle.main.executableURL else { return nil }
        let dir = bin.deletingLastPathComponent()
        let candidates = [
            dir.appendingPathComponent("aTerm_aTerm.bundle/Resources/shell-integration.zsh"),
            dir.appendingPathComponent("aTerm_aTerm.bundle/Contents/Resources/shell-integration.zsh"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func installShellIntegration() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let destination = home.appendingPathComponent(".aterm-shell-integration.zsh")
        let zshrc = home.appendingPathComponent(".zshrc")
        let sourceLine = "\nsource \"\(destination.path)\"\n"

        guard let sourceURL = Self.bundledShellIntegrationURL() else {
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
            let extrasByID = stored.builtinExtraModels ?? [:]
            // Merge saved OAuth client IDs and user-added models back into builtin providers
            let builtins = BuiltinProviders.all.map { base -> ModelProvider in
                var p = base
                if let clientID = stored.oauthClientIDs[p.id],
                   var oauth = p.oauthConfig {
                    oauth.clientID = clientID
                    p.oauthConfig = oauth
                }
                let extras = extrasByID[p.id] ?? []
                if !extras.isEmpty {
                    var merged = p.models
                    let ids = Set(merged.map(\.id))
                    for m in extras where !ids.contains(m.id) {
                        merged.append(m)
                    }
                    p.models = merged
                }
                return p
            }
            providers = builtins + customProviders
            defaultProviderID = stored.defaultProviderID ?? "ollama"
            defaultModelID = stored.defaultModelID
        } else {
            providers = BuiltinProviders.all
            defaultProviderID = "ollama"
            defaultModelID = nil
            persistProviders()
        }
        // Do not persist on every launch when `providers.json` already exists — avoids extra I/O
        // and duplicate @Published churn while the UI (including Settings) is coming up.
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

    /// Re-scan common install locations for agent CLIs (GUI apps often have a minimal PATH until refreshed).
    func refreshAgentInstallationStatuses() {
        scanAgents()
    }

    private func autoStartGlobalMCPServers() {
        for server in mcpServers where server.autoStart && server.scope == .global {
            startMCPServer(server, cwd: nil)
        }
    }

    func refreshOllamaModels() async {
        guard let ollamaProvider = providers.first(where: { $0.id == "ollama" }) else { return }

        // Probe Ollama API for running models
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return }
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

            // Merge detected models into the provider list
            providers.removeAll(where: { $0.id == "ollama" })
            providers.append(updated)

            // Prefer a local (non-cloud) model when available.
            let preferredModel = updated.models.first(where: { !$0.id.lowercased().contains("cloud") }) ?? updated.models.first

            // Auto-select Ollama as the default provider when nothing is configured yet
            // or the current default requires credentials that are not stored.
            let currentProvider = provider(for: defaultProviderID)
            let currentNeedsCredential = (currentProvider?.authType ?? .none) != .none
            let currentHasCredential = !((try? keychainStore.readSecret(account: defaultProviderID ?? "")) ?? "").isEmpty
            if defaultProviderID == nil || (currentNeedsCredential && !currentHasCredential) {
                defaultProviderID = "ollama"
                defaultModelID = preferredModel?.id
                for tab in tabs {
                    for pane in tab.panes {
                        pane.appearance.aiProvider = "ollama"
                        pane.appearance.aiModel = defaultModelID
                    }
                    refreshProviderLabel(for: tab)
                }
            } else if defaultProviderID == "ollama" && defaultModelID == nil {
                defaultModelID = preferredModel?.id
            }
            persistProviders()
            tabs.forEach(applyDefaultProviderIfNeeded(to:))
            tabs.forEach(refreshProviderLabel(for:))
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
        for pane in tab.panes {
            pane.onChatRequest = { [weak self, weak pane] message in
                guard let self, let pane else { return }
                self.handleChatMessage(message, for: pane)
            }
            pane.onSubmitSmartLine = { [weak self, weak pane] line in
                guard let self, let pane else { return }
                self.submitSmartLineFromPrompt(line, for: pane)
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
        var builtinExtraModels: [String: [ModelDefinition]] = [:]
        for p in providers where p.isBuiltin {
            if let clientID = p.oauthConfig?.clientID, !clientID.isEmpty {
                oauthClientIDs[p.id] = clientID
            }
            let baseline = BuiltinProviders.all.first(where: { $0.id == p.id })?.models ?? []
            let baselineIDs = Set(baseline.map(\.id))
            let extras = p.models.filter { !baselineIDs.contains($0.id) }
            if !extras.isEmpty {
                builtinExtraModels[p.id] = extras
            }
        }
        providerStore.save(.init(
            providers: providers.filter { !$0.isBuiltin },
            defaultProviderID: defaultProviderID,
            defaultModelID: defaultModelID,
            oauthClientIDs: oauthClientIDs,
            builtinExtraModels: builtinExtraModels.isEmpty ? nil : builtinExtraModels
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
                            agentDefinitionID: agentDefinitionID,
                            conversationMessages: $0.conversationHistory.persistableMessages,
                            chatConversationMessages: $0.chatConversationHistory.persistableMessages
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
            if let messages = descriptor.conversationMessages {
                for m in messages { pane.conversationHistory.addMessage(role: m.role, text: m.text) }
            }
            if let messages = descriptor.chatConversationMessages {
                for m in messages { pane.chatConversationHistory.addMessage(role: m.role, text: m.text) }
            }
            return pane
        }

        let pane = TerminalPaneViewModel(
            id: descriptor.id,
            initialTitle: descriptor.title,
            workingDirectory: descriptor.workingDirectoryURL,
            profile: profile
        )
        applyDefaultProviderIfNeeded(to: pane)
        if let messages = descriptor.conversationMessages {
            for m in messages { pane.conversationHistory.addMessage(role: m.role, text: m.text) }
        }
        if let messages = descriptor.chatConversationMessages {
            for m in messages { pane.chatConversationHistory.addMessage(role: m.role, text: m.text) }
        }
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

    private static func cleanGeneratedCommand(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenceStart = cleaned.range(of: "```") {
            let afterOpen = cleaned[fenceStart.upperBound...]
            if let newlineIdx = afterOpen.firstIndex(of: "\n") {
                let bodyStart = afterOpen.index(after: newlineIdx)
                let remaining = afterOpen[bodyStart...]
                if let fenceEnd = remaining.range(of: "```") {
                    cleaned = String(remaining[..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    cleaned = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        if cleaned.hasPrefix("`") && cleaned.hasSuffix("`") && cleaned.count >= 2 && !cleaned.contains("\n") {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.hasPrefix("$ ") {
            cleaned = String(cleaned.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleaned.hasPrefix("% ") {
            cleaned = String(cleaned.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    private static func hasBalancedQuotes(_ command: String) -> Bool {
        var inSingle = false
        var inDouble = false
        var inBacktick = false
        var escaped = false

        for ch in command {
            if escaped {
                escaped = false
                continue
            }
            if ch == "\\" && !inSingle {
                escaped = true
                continue
            }
            if ch == "'" && !inDouble && !inBacktick {
                inSingle.toggle()
            } else if ch == "\"" && !inSingle && !inBacktick {
                inDouble.toggle()
            } else if ch == "`" && !inSingle {
                inBacktick.toggle()
            }
        }
        return !inSingle && !inDouble && !inBacktick && !escaped
    }

    private func generateShellCommand(from input: String, for pane: TerminalPaneViewModel, showOverlayCard: Bool = true) async {
        if showOverlayCard {
            pane.aiShellState = AIShellState(originalPrompt: input, generatedCommand: "", isGenerating: true, isEditing: false)
        }

        let (providerOpt, modelOpt) = usableAIProviderAndModel(for: pane)
        guard let provider = providerOpt,
              let modelID = modelOpt else {
            pane.aiShellState = AIShellState(
                originalPrompt: input,
                generatedCommand: "No provider or model configured.",
                isGenerating: false,
                isEditing: showOverlayCard
            )
            return
        }

        let ctx = pane.terminalContext()
        do {
            let rawCommand = try await providerRouter.complete(
                provider: provider,
                modelID: modelID,
                messages: [
                    ChatMessage(
                        role: "system",
                        content: "You are an expert macOS zsh command generator. Convert the user's request into a single executable zsh command (pipelines and && are allowed). Output ONLY the raw command with no markdown code fences, no backticks, and no explanation. Prefer the current directory (.) when no path is specified."
                    ),
                    ChatMessage(
                        role: "user",
                        content: "cwd=\(pane.currentWorkingDirectory?.path ?? ".")\ngitBranch=\(ctx.gitBranch ?? "none")\nproject=\(ctx.projectType.rawValue)\nrequest=\(input)"
                    )
                ]
            )
            let command = Self.cleanGeneratedCommand(rawCommand)

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
                isEditing: showOverlayCard
            )
        }
    }

    private func answerQuery(_ input: String, for pane: TerminalPaneViewModel, inlinePrepared: Bool = false) async {
        pane.queryResponse = QueryResponseState()
        if !inlinePrepared {
            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
        }
        defer {
            if !Task.isCancelled {
                pane.finishInlineAIOutput()
            }
        }

        // Try local MCP answer first (quick offline fallback)
        if let mcpAnswer = mcpHost.localFilesystemAnswer(question: input, cwd: pane.currentWorkingDirectory) {
            pane.conversationHistory.addUserMessage(input)
            pane.conversationHistory.addAssistantMessage(mcpAnswer)
            pane.writeTerminalText("\u{1B}[36;1mai>\u{1B}[0m \(mcpAnswer)\r\n")
            return
        }

        let (providerOpt, modelOpt) = usableAIProviderAndModel(for: pane)
        guard let provider = providerOpt,
              let modelID = modelOpt else {
            pane.writeTerminalText("\u{1B}[33mai> No AI provider or model configured. Open Settings (⌘,) or run /model to configure one.\u{1B}[0m\r\n")
            return
        }

        do {
            // Build system message with context
            let ctx = pane.terminalContext()
            let projectMemory = ProjectContextDetector.shared.projectMemorySnippet(for: pane.currentWorkingDirectory)
            let systemPrompt = """
            You answer terminal questions concisely. If a shell command would help, include it in a fenced ```bash block.
            Current directory: \(pane.currentWorkingDirectory?.path ?? "unknown")
            Git branch: \(ctx.gitBranch ?? "unknown")
            Project type: \(ctx.projectType.rawValue)
            Recent commands: \(ctx.lastCommands.joined(separator: " | "))
            Recent failures: \(ctx.recentFailures.joined(separator: " | "))
            Last exit code: \(ctx.lastExitCode.map(String.init) ?? "n/a")
            \(projectMemory.map { "\nProject memory:\n\($0)" } ?? "")
            You have access to MCP tools. Use them when the user's question requires real data from their filesystem, git, or other connected services.
            """

            pane.conversationHistory.addSystemMessage(systemPrompt)
            let userMsg = "Last output (tail): \(ctx.lastOutputSnippet)\n\nQuestion: \(input)"
            pane.conversationHistory.addUserMessage(userMsg)

            _ = try await streamAIResponse(
                provider: provider,
                modelID: modelID,
                conversationHistory: pane.conversationHistory,
                initialResponse: QueryResponseState(),
                pane: pane,
                useCard: false
            )
        } catch is CancellationError {
            // Cancelled via Ctrl+C
        } catch {
            if !Task.isCancelled {
                pane.writeTerminalText("\r\n\u{1B}[31mQuery failed: \(error.localizedDescription)\u{1B}[0m\r\n")
            }
        }
    }

    /// Answer query in chat mode (persistent context, uses separate chat model config)
    func answerChatQuery(_ input: String, for pane: TerminalPaneViewModel) async {
        defer {
            if !Task.isCancelled && pane.isChatModeActive {
                pane.showChatPrompt(leadingNewline: false)
            }
        }

        // Use chat-specific provider/model if configured, otherwise fall back to default
        let provider: ModelProvider
        let modelID: String
        
        if let chatProviderID = pane.chatProviderID,
           let chatModelID = pane.chatModelID,
           let chatProvider = self.provider(for: chatProviderID) {
            let needsCredential = chatProvider.authType != .none
            let hasCredential = !((try? keychainStore.readSecret(account: chatProvider.id)) ?? "").isEmpty
            if !needsCredential || hasCredential {
                provider = chatProvider
                modelID = chatModelID
            } else {
                let (fallbackProvider, fallbackModel) = usableAIProviderAndModel(for: pane)
                if let fallbackProvider, let fallbackModel {
                    provider = fallbackProvider
                    modelID = fallbackModel
                } else {
                    pane.writeTerminalText("\u{1B}[33mai> No provider or model configured for chat mode. Set up a model in Settings (⌘,).\u{1B}[0m\r\n")
                    return
                }
            }
        } else {
            let (fallbackProvider, fallbackModel) = usableAIProviderAndModel(for: pane)
            if let fallbackProvider, let fallbackModel {
                provider = fallbackProvider
                modelID = fallbackModel
            } else {
                pane.writeTerminalText("\u{1B}[33mai> No provider or model configured for chat mode. Set up a model in Settings (⌘,).\u{1B}[0m\r\n")
                return
            }
        }

        do {
            // Build chat system message (multi-turn: full history is sent each request)
            let systemPrompt = """
            You are a helpful assistant inside a terminal app. The messages in this chat are one continuous session—read earlier turns and keep continuity (user preferences, location, projects, names, decisions). Refer back when relevant; do not ask the user to repeat context they already gave unless it was many turns ago or unclear.

            Prefer concise answers. Use markdown: short paragraphs, ```bash or ```python for commands/code. Keep prose lines reasonably short so they read well in a fixed-width terminal.

            Current directory: \(pane.currentWorkingDirectory?.path ?? "unknown")
            \(ProjectContextDetector.shared.projectMemorySnippet(for: pane.currentWorkingDirectory).map { "\nProject memory:\n\($0)" } ?? "")
            """

            // Initialize history if needed
            if pane.chatConversationHistory.messages.isEmpty {
                pane.chatConversationHistory.addSystemMessage(systemPrompt)
            }
            
            pane.chatConversationHistory.addUserMessage(input)

            // Chat mode: stream text only (no MCP tools). Tool-enabled streams often return empty text on the first round-trip.
            let responseText = try await streamChatTextOnly(
                provider: provider,
                modelID: modelID,
                conversationHistory: pane.chatConversationHistory,
                pane: pane
            )
            let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pane.chatConversationHistory.addAssistantMessage(trimmed)
            }
            pane.queryResponse = QueryResponseState()
        } catch is CancellationError {
            // Cancelled via Ctrl+C
        } catch {
            if !Task.isCancelled {
                let errorText = "Chat query failed: \(error.localizedDescription)"
                pane.appendChatAssistantResponse(errorText)
                pane.queryResponse = QueryResponseState()
            }
        }
    }

    /// Streams assistant text without tools; returns the full string for in-terminal chat.
    private func streamChatTextOnly(
        provider: ModelProvider,
        modelID: String,
        conversationHistory: ConversationHistory,
        pane: TerminalPaneViewModel
    ) async throws -> String {
        var accumulated = ""
        var wroteHeader = false
        pane.writeTerminalText("\u{1B}[90m✦ Thinking...\u{1B}[0m")
        let stream = try providerRouter.streamResponse(
            provider: provider,
            modelID: modelID,
            messages: conversationHistory.simplifiedMessages
        )
        for try await chunk in stream {
            if !wroteHeader {
                pane.clearCurrentTerminalLine()
                pane.writeTerminalText("\u{1B}[36;1mai>\u{1B}[0m ")
                wroteHeader = true
            }
            accumulated.append(chunk)
            pane.writeTerminalText(chunk)
        }
        if !wroteHeader {
            pane.clearCurrentTerminalLine()
            pane.writeTerminalText("\u{1B}[36;1mai>\u{1B}[0m ")
        }
        pane.writeTerminalText("\r\n")
        return accumulated
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
        initialResponse: QueryResponseState,
        pane: TerminalPaneViewModel,
        useCard: Bool = true
    ) async throws -> QueryResponseState {
        var queryResponse = initialResponse
        var fullText = ""
        var wroteInlineHeader = false
        if useCard {
            queryResponse.isStreaming = true
            pane.queryResponse = queryResponse
        } else {
            pane.writeTerminalText("\u{1B}[90m✦ Thinking...\u{1B}[0m")
        }

        let toolSchemas = mcpHost.toolSchemas()
        let maxToolRoundTrips = 5

        func ensureInlineHeaderWritten() {
            guard !useCard && !wroteInlineHeader else { return }
            pane.clearCurrentTerminalLine()
            pane.writeTerminalText("\u{1B}[36;1mai>\u{1B}[0m ")
            wroteInlineHeader = true
        }

        func publishProgress() {
            if useCard {
                queryResponse.isStreaming = true
                pane.queryResponse = queryResponse
            }
        }

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
                    if useCard {
                        queryResponse.text.append(chunk)
                    } else {
                        ensureInlineHeaderWritten()
                        fullText.append(chunk)
                        pane.writeTerminalText(chunk)
                    }
                    publishProgress()
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
                        if useCard {
                            queryResponse.text.append(chunk)
                        } else {
                            ensureInlineHeaderWritten()
                            fullText.append(chunk)
                            pane.writeTerminalText(chunk)
                        }
                        publishProgress()
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
                    let note = "\n\u{1B}[90m[Used tool: \(call.name)]\u{1B}[0m\n"
                    if useCard {
                        queryResponse.text.append("\n\n*[Used tool: \(call.name)]*\n")
                    } else {
                        ensureInlineHeaderWritten()
                        pane.writeTerminalText(note)
                    }
                    publishProgress()
                } catch {
                    let errorMsg = "Tool '\(call.name)' failed: \(error.localizedDescription)"
                    toolResults.append(ToolCallResult(toolCallID: call.id, name: call.name, content: errorMsg))
                    let note = "\n\u{1B}[33m[\(errorMsg)]\u{1B}[0m\n"
                    if useCard {
                        queryResponse.text.append("\n\n*[\(errorMsg)]*\n")
                    } else {
                        ensureInlineHeaderWritten()
                        pane.writeTerminalText(note)
                    }
                    publishProgress()
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

        if useCard {
            queryResponse.isStreaming = false
            queryResponse.suggestions = extractSuggestions(from: queryResponse.text)
            pane.queryResponse = queryResponse
            return queryResponse
        } else {
            if !wroteInlineHeader {
                pane.clearCurrentTerminalLine()
            } else {
                pane.writeTerminalText("\r\n")
            }
            if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversationHistory.addAssistantMessage(fullText)
            }
            pane.queryResponse = QueryResponseState()
            return QueryResponseState()
        }
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

        if config.mcpAutoStart && !config.mcpServers.isEmpty {
            for serverID in config.mcpServers {
                if let definition = mcpServers.first(where: { $0.id == serverID }) {
                    startMCPServer(definition, cwd: directory)
                }
            }
        }

        if config.agentAutoStart, let defaultAgentID = config.defaultAgent,
           let definition = agentDefinitions.first(where: { $0.id == defaultAgentID }),
           agentStatuses[definition.id]?.isInstalled == true {
            launchAgent(definition, from: tab)
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
                            agentDefinitionID: agentDefinitionID,
                            conversationMessages: $0.conversationHistory.persistableMessages,
                            chatConversationMessages: $0.chatConversationHistory.persistableMessages
                        )
                    }
                )
            }
        )
    }
}
