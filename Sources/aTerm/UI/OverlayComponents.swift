import SwiftUI

// MARK: - Modern Model Picker

struct ModernModelPicker: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @State private var query = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    var filteredItems: [(provider: ModelProvider, model: ModelDefinition)] {
        guard !query.isEmpty else { return appModel.modelPickerItems }
        return appModel.modelPickerItems.filter {
            $0.provider.name.localizedCaseInsensitiveContains(query) ||
            $0.model.name.localizedCaseInsensitiveContains(query) ||
            $0.model.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var activeProviderID: String? {
        windowModel.selectedTab?.appearance.aiProvider
    }

    private var activeModelID: String? {
        windowModel.selectedTab?.appearance.aiModel
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    windowModel.dismissModelPicker()
                }
            
            // Picker card
            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("Select AI Model")
                            .font(DesignSystem.Typography.defaultFont(15, weight: .semibold))
                    }
                    Spacer()
                    Button("Esc") {
                        windowModel.dismissModelPicker()
                    }
                    .buttonStyle(ModernButtonStyle(variant: .ghost, size: .xs))
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.m)
                .background(DesignSystem.Colors.backgroundSecondary)
                
                SubtleDivider()
                
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search models and providers…", text: $query)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.defaultFont(14))
                        .focused($isSearchFocused)
                        .onSubmit {
                            if selectedIndex >= 0 && selectedIndex < filteredItems.count {
                                selectItem(filteredItems[selectedIndex], at: selectedIndex)
                            }
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.m)
                .background(DesignSystem.Colors.backgroundPrimary)
                
                SubtleDivider()

                // List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                                let isActive = (item.provider.id == activeProviderID && item.model.id == activeModelID)
                                ModelPickerRow(
                                    provider: item.provider,
                                    model: item.model,
                                    isSelected: selectedIndex == index,
                                    isActive: isActive,
                                    hasCredential: item.provider.authType == .none || appModel.hasStoredCredential(for: item.provider.id)
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectItem(item, at: index)
                                }
                                .onHover { hovering in
                                    if hovering {
                                        selectedIndex = index
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 380)
                    .onAppear {
                        if let activeIdx = filteredItems.firstIndex(where: { $0.provider.id == activeProviderID && $0.model.id == activeModelID }) {
                            selectedIndex = activeIdx
                            proxy.scrollTo(activeIdx, anchor: .center)
                        } else {
                            selectedIndex = 0
                        }
                    }
                    .onChange(of: query) { _ in
                        selectedIndex = 0
                    }
                    .onChange(of: selectedIndex) { newIdx in
                        withAnimation(DesignSystem.Animation.fast) {
                            proxy.scrollTo(newIdx)
                        }
                    }
                }
                
                SubtleDivider()

                // Footer
                HStack {
                    Text("\(filteredItems.count) models available")
                        .font(DesignSystem.Typography.defaultFont(11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("↑↓ navigate · ↵ select · esc close")
                        .font(DesignSystem.Typography.mono(10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.s)
                .background(DesignSystem.Colors.backgroundSecondary)
            }
            .frame(width: 520)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .modernShadow(DesignSystem.Shadows.large)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onMoveCommand { direction in
            guard !filteredItems.isEmpty else { return }
            switch direction {
            case .down:
                selectedIndex = min(selectedIndex + 1, filteredItems.count - 1)
            case .up:
                selectedIndex = max(selectedIndex - 1, 0)
            default:
                break
            }
        }
        .onExitCommand {
            windowModel.dismissModelPicker()
        }
    }
    
    private func selectItem(_ item: (provider: ModelProvider, model: ModelDefinition), at index: Int) {
        windowModel.assignModel(providerID: item.provider.id, modelID: item.model.id)
        windowModel.dismissModelPicker()
    }
}

private struct ModelPickerRow: View {
    let provider: ModelProvider
    let model: ModelDefinition
    let isSelected: Bool
    let isActive: Bool
    let hasCredential: Bool
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            // Provider status indicator
            Circle()
                .fill(hasCredential ? Color.green : Color.orange.opacity(0.6))
                .frame(width: 7, height: 7)
                .help(hasCredential ? "Ready" : "API key / sign-in required in Settings")
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(DesignSystem.Typography.defaultFont(13, weight: isSelected || isActive ? .semibold : .medium))
                    if isActive {
                        Tag(text: "ACTIVE", color: .accentColor)
                    }
                }
                Text("\(provider.name) · \(model.id)")
                    .font(DesignSystem.Typography.mono(10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()

            Text("\(model.contextWindow / 1000)k ctx")
                .font(DesignSystem.Typography.mono(10))
                .foregroundStyle(.tertiary)

            if isSelected || isActive {
                Image(systemName: isActive ? "checkmark.circle.fill" : "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .padding(.horizontal, 6)
        )
    }
}

// MARK: - Modern Command Palette

struct ModernCommandPalette: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @State private var query = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool
    
    fileprivate struct PaletteAction: Identifiable {
        let id: String
        let label: String
        let subtitle: String?
        let icon: String
        let shortcut: String?
        let action: () -> Void
    }
    
    private var actions: [PaletteAction] {
        let activePane = windowModel.selectedTab?.activePane
        let isChatActive = activePane?.isChatModeActive ?? false
        let isSmartMode = (activePane?.aiRoutingMode ?? .smart) == .smart

        let all: [PaletteAction] = [
            .init(
                id: "toggle-chat",
                label: isChatActive ? "Exit AI Chat Mode" : "Start AI Chat Mode (/chat)",
                subtitle: isChatActive ? "Return to zsh prompt" : "Enter multi-turn conversational AI inside the terminal",
                icon: "bubble.left.and.bubble.right",
                shortcut: "/chat"
            ) {
                dismiss()
                guard let pane = activePane else { return }
                if pane.isChatModeActive {
                    pane.exitChatMode()
                } else {
                    pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
                    pane.enterChatMode(providerID: pane.appearance.chatProvider, modelID: pane.appearance.chatModel)
                }
            },
            .init(
                id: "explain-failure",
                label: "Explain Last Error (/explain)",
                subtitle: "Ask AI why the last command failed and suggest a fix",
                icon: "exclamationmark.bubble",
                shortcut: "/explain"
            ) {
                dismiss()
                appModel.explainLastFailure(for: activePane)
            },
            .init(
                id: "fix-last-command",
                label: "Fix Last Command (/fix)",
                subtitle: "Generate a corrected command and prefill your prompt",
                icon: "wrench.and.screwdriver",
                shortcut: "/fix"
            ) {
                dismiss()
                appModel.fixLastCommand(for: activePane)
            },
            .init(
                id: "toggle-routing",
                label: isSmartMode ? "Switch to Shell-Only Routing" : "Switch to Smart AI Routing",
                subtitle: isSmartMode ? "Only route prefixed lines (!, ?, >, $) to AI" : "Automatically classify questions & natural language tasks",
                icon: "sparkles",
                shortcut: nil
            ) {
                dismiss()
                guard let pane = activePane else { return }
                pane.aiRoutingMode = (pane.aiRoutingMode == .smart ? .shell : .smart)
            },
            .init(id: "model-picker", label: "Switch AI Model", subtitle: "Change AI provider and model", icon: "cpu", shortcut: "⌘M") { dismiss(); windowModel.toggleModelPicker() },
            .init(id: "help-guide", label: "Help: Usage & /Commands Guide", subtitle: "Open full documentation for usage, slash commands, and prefixes", icon: "questionmark.circle", shortcut: "⇧⌘/") {
                dismiss()
                windowModel.isHelpPresented = true
            },
            .init(id: "help-inline", label: "Print /help in Terminal", subtitle: "Write the Usage & /Commands cheat sheet into the active pane", icon: "terminal", shortcut: nil) {
                if let pane = windowModel.selectedTab?.activePane {
                    pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
                    appModel.writeInlineAIHelp(to: pane)
                    pane.finishInlineAIOutput()
                }
                dismiss()
            },
            .init(id: "new-tab", label: "New Tab", subtitle: "Create a new terminal tab", icon: "plus.square", shortcut: "⌘T") { dismiss(); windowModel.createTabAndSelect(workingDirectory: windowModel.selectedTab?.currentWorkingDirectory) },
            .init(id: "split-h", label: "Split Horizontally", subtitle: "Split pane side by side", icon: "rectangle.split.2x1", shortcut: "⌘D") { windowModel.splitSelectedPane(.horizontal); dismiss() },
            .init(id: "split-v", label: "Split Vertically", subtitle: "Split pane top/bottom", icon: "rectangle.split.1x2", shortcut: "⌘⇧D") { windowModel.splitSelectedPane(.vertical); dismiss() },
            .init(id: "find", label: "Find in Scrollback", subtitle: "Search terminal output", icon: "magnifyingglass", shortcut: "⌘F") { windowModel.toggleSearchBar(); dismiss() },
            .init(id: "clear", label: "Clear Scrollback", subtitle: "Clear terminal history", icon: "trash", shortcut: "⌘K") { windowModel.clearSelectedScrollback(); dismiss() },
            .init(id: "agent-picker", label: "Launch Agent", subtitle: "Start an AI agent session", icon: "bolt", shortcut: nil) { dismiss(); windowModel.openAgentPicker() },
            .init(id: "close-tab", label: "Close Tab", subtitle: "Close the current tab", icon: "xmark.square", shortcut: "⌘W") { dismiss(); windowModel.closeSelectedTab() },
            .init(id: "settings", label: "Settings", subtitle: "Open preferences", icon: "gear", shortcut: "⌘,") { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil); dismiss() },
            .init(id: "shell-integration", label: "Install Shell Integration", subtitle: "Enable shell hooks in ~/.zshrc", icon: "terminal", shortcut: nil) { appModel.installShellIntegration(); dismiss() },
            .init(id: "refresh-ollama", label: "Refresh Ollama Models", subtitle: "Re-scan local Ollama models", icon: "arrow.clockwise", shortcut: nil) { Task { await appModel.refreshOllamaModels() }; dismiss() },
        ]
        + appModel.allThemes.map { theme in
            PaletteAction(id: "theme-\(theme.id)", label: "Theme: \(theme.name)", subtitle: "Change color scheme", icon: "paintbrush", shortcut: nil) {
                windowModel.applyTheme(theme)
                dismiss()
            }
        }
        + appModel.availableAgents.filter { appModel.agentStatuses[$0.id]?.isInstalled == true }.map { agent in
            PaletteAction(id: "agent-\(agent.id)", label: "Launch \(agent.name)", subtitle: "Start AI agent session", icon: "bolt.circle", shortcut: nil) {
                windowModel.launchAgent(agent)
                dismiss()
            }
        }
        
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter { 
            $0.label.lowercased().contains(q) || 
            ($0.subtitle?.lowercased().contains(q) ?? false) ||
            ($0.shortcut?.lowercased().contains(q) ?? false)
        }
    }
    
    private func dismiss() {
        windowModel.isCommandPalettePresented = false
    }
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            
            // Palette card
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    
                    TextField("Type a command or search…", text: $query)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.defaultFont(15))
                        .focused($isSearchFocused)
                        .onSubmit {
                            if selectedIndex >= 0 && selectedIndex < actions.count {
                                actions[selectedIndex].action()
                            } else if let first = actions.first {
                                first.action()
                            }
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.m)
                .background(DesignSystem.Colors.backgroundPrimary)
                
                SubtleDivider()
                
                // Actions list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                                CommandPaletteRow(
                                    action: action,
                                    isSelected: selectedIndex == index
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    action.action()
                                }
                                .onHover { hovering in
                                    if hovering {
                                        selectedIndex = index
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 380)
                    .onAppear { selectedIndex = 0 }
                    .onChange(of: query) { _ in selectedIndex = 0 }
                    .onChange(of: selectedIndex) { newIdx in
                        withAnimation(DesignSystem.Animation.fast) {
                            proxy.scrollTo(newIdx)
                        }
                    }
                }
                
                SubtleDivider()

                // Footer
                HStack {
                    Text("\(actions.count) commands")
                        .font(DesignSystem.Typography.defaultFont(11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("↑↓ navigate · ↵ select · esc close")
                        .font(DesignSystem.Typography.mono(10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.s)
                .background(DesignSystem.Colors.backgroundSecondary)
            }
            .frame(width: 540)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .modernShadow(DesignSystem.Shadows.large)
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onMoveCommand { direction in
            guard !actions.isEmpty else { return }
            switch direction {
            case .down:
                selectedIndex = min(selectedIndex + 1, actions.count - 1)
            case .up:
                selectedIndex = max(selectedIndex - 1, 0)
            default:
                break
            }
        }
        .onExitCommand { dismiss() }
    }
}

private struct CommandPaletteRow: View {
    let action: ModernCommandPalette.PaletteAction
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: action.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(action.label)
                    .font(DesignSystem.Typography.defaultFont(13, weight: isSelected ? .semibold : .regular))
                
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Typography.defaultFont(11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(DesignSystem.Typography.mono(10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Modern Agent Picker

struct ModernAgentPicker: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @State private var draftAgent = AgentDraft()
    @State private var isAddingNew = false
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    windowModel.closeAgentPicker()
                }
            
            // Picker card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("AI Agents")
                        .font(DesignSystem.Typography.defaultFont(16, weight: .semibold))
                    Spacer()
                    Button("Cancel") {
                        windowModel.closeAgentPicker()
                    }
                    .buttonStyle(ModernButtonStyle(variant: .ghost, size: .s))
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.m)
                .background(DesignSystem.Colors.backgroundSecondary)
                
                SubtleDivider()
                
                // Agent list
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.s) {
                        ForEach(appModel.availableAgents) { agent in
                            let status = appModel.agentStatuses[agent.id]
                            AgentRow(
                                agent: agent,
                                status: status,
                                onLaunch: {
                                    windowModel.launchAgent(agent)
                                }
                            )
                        }
                    }
                    .padding(DesignSystem.Spacing.m)
                }
                .frame(maxHeight: 320)
                
                if isAddingNew {
                    SubtleDivider()
                    
                    // Add new agent form
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                        Text("Add Custom Agent")
                            .font(DesignSystem.Typography.defaultFont(12, weight: .semibold))
                        
                        TextField("ID", text: $draftAgent.id)
                            .textFieldStyle(ModernTextFieldStyle())
                        TextField("Name", text: $draftAgent.name)
                            .textFieldStyle(ModernTextFieldStyle())
                        TextField("Command", text: $draftAgent.command)
                            .textFieldStyle(ModernTextFieldStyle())
                        
                        HStack {
                            Button("Save") {
                                appModel.upsertAgent(draftAgent.toDefinition())
                                draftAgent = AgentDraft()
                                isAddingNew = false
                            }
                            .buttonStyle(ModernButtonStyle(variant: .primary, size: .s))
                            .disabled(draftAgent.id.isEmpty || draftAgent.command.isEmpty)
                            
                            Button("Cancel") {
                                isAddingNew = false
                            }
                            .buttonStyle(ModernButtonStyle(variant: .ghost, size: .s))
                        }
                    }
                    .padding(DesignSystem.Spacing.m)
                    .background(DesignSystem.Colors.backgroundSecondary)
                } else {
                    // Add button
                    Button {
                        isAddingNew = true
                    } label: {
                        Label("Add Custom Agent", systemImage: "plus")
                            .font(DesignSystem.Typography.defaultFont(12))
                    }
                    .buttonStyle(ModernButtonStyle(variant: .secondary, size: .s))
                    .padding(DesignSystem.Spacing.m)
                }
            }
            .frame(width: 480)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                    .fill(.regularMaterial)
            )
            .modernShadow(DesignSystem.Shadows.large)
        }
    }
}

private struct AgentRow: View {
    let agent: AgentDefinition
    let status: AgentInstallationStatus?
    let onLaunch: () -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            // Status indicator
            Circle()
                .fill((status?.isInstalled ?? false) ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(DesignSystem.Typography.defaultFont(13, weight: .medium))
                Text((status?.isInstalled ?? false) ? (status?.executablePath ?? agent.command) : agent.installHint)
                    .font(DesignSystem.Typography.mono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button((status?.isInstalled ?? false) ? "Launch" : "Unavailable") {
                onLaunch()
            }
            .buttonStyle(ModernButtonStyle(
                variant: (status?.isInstalled ?? false) ? .primary : .secondary,
                size: .s
            ))
            .disabled(!(status?.isInstalled ?? false))
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                .strokeBorder(DesignSystem.Colors.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Helper Types

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

// MARK: - Modern Help & /Commands Overlay

struct ModernHelpOverlay: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel

    private func dismiss() {
        windowModel.isHelpPresented = false
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Top Bar
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text("Help — Usage & /Commands")
                        .font(DesignSystem.Typography.defaultFont(15, weight: .semibold))

                    Spacer()

                    if let pane = windowModel.selectedTab?.activePane, !pane.isAgentTab {
                        Button {
                            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
                            appModel.writeInlineAIHelp(to: pane)
                            pane.finishInlineAIOutput()
                            dismiss()
                        } label: {
                            Label("Print /help in Terminal", systemImage: "terminal")
                        }
                        .buttonStyle(ModernButtonStyle(variant: .secondary, size: .s))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Close (Esc)")
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, 12)
                .background(DesignSystem.Colors.backgroundSecondary)

                SubtleDivider()

                HelpSettingsTab()
                    .frame(maxHeight: 540)

                SubtleDivider()

                // Footer
                HStack {
                    Text("Tip: Type `/help` at your zsh prompt or inside `/chat` mode anytime.")
                        .font(DesignSystem.Typography.defaultFont(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("esc close")
                        .font(DesignSystem.Typography.mono(10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.s)
                .background(DesignSystem.Colors.backgroundSecondary)
            }
            .frame(width: 720)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .modernShadow(DesignSystem.Shadows.large)
        }
        .onExitCommand { dismiss() }
    }
}
