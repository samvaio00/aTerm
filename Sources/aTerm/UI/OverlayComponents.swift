import SwiftUI

// MARK: - Modern Model Picker

struct ModernModelPicker: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @State private var query = ""
    @State private var selectedIndex: Int = 0
    
    var filteredItems: [(provider: ModelProvider, model: ModelDefinition)] {
        guard !query.isEmpty else { return appModel.modelPickerItems }
        return appModel.modelPickerItems.filter {
            $0.provider.name.localizedCaseInsensitiveContains(query) ||
            $0.model.name.localizedCaseInsensitiveContains(query) ||
            $0.model.id.localizedCaseInsensitiveContains(query)
        }
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
                    Text("Select Model")
                        .font(DesignSystem.Typography.defaultFont(16, weight: .semibold))
                    Spacer()
                    Button("Cancel") {
                        windowModel.dismissModelPicker()
                    }
                    .buttonStyle(ModernButtonStyle(variant: .ghost, size: .s))
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
                    
                    TextField("Search models and providers...", text: $query)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.defaultFont(14))
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.m)
                .background(DesignSystem.Colors.backgroundPrimary)
                
                // List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.model.id) { index, item in
                                ModelPickerRow(
                                    provider: item.provider,
                                    model: item.model,
                                    isSelected: selectedIndex == index
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectItem(item, at: index)
                                }
                                .background(
                                    selectedIndex == index ? Color.accentColor.opacity(0.1) : Color.clear
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 400)
                    .onAppear {
                        selectedIndex = 0
                    }
                    .onChange(of: query) { _ in
                        selectedIndex = 0
                    }
                }
                
                // Footer
                HStack {
                    Text("\(filteredItems.count) models available")
                        .font(DesignSystem.Typography.defaultFont(11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("↑↓ to navigate · ↵ to select")
                        .font(DesignSystem.Typography.mono(10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.s)
                .background(DesignSystem.Colors.backgroundSecondary)
            }
            .frame(width: 500)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                    .fill(.regularMaterial)
            )
            .modernShadow(DesignSystem.Shadows.large)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            // Focus search field on appear
            DispatchQueue.main.async {
                // Could implement focus management here
            }
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
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            // Provider indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(DesignSystem.Typography.defaultFont(13, weight: .medium))
                Text("\(provider.name) · \(model.id)")
                    .font(DesignSystem.Typography.mono(10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }
    
    private var statusColor: Color {
        // Could check provider health here
        .green
    }
}

// MARK: - Modern Command Palette

struct ModernCommandPalette: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @State private var query = ""
    @State private var selectedIndex: Int = 0
    
    fileprivate struct PaletteAction: Identifiable {
        let id: String
        let label: String
        let subtitle: String?
        let icon: String
        let shortcut: String?
        let action: () -> Void
    }
    
    private var actions: [PaletteAction] {
        let all: [PaletteAction] = [
            .init(id: "new-tab", label: "New Tab", subtitle: "Create a new terminal tab", icon: "plus.square", shortcut: "⌘T") { dismiss(); windowModel.createTabAndSelect() },
            .init(id: "close-tab", label: "Close Tab", subtitle: "Close the current tab", icon: "xmark.square", shortcut: "⌘W") { dismiss(); windowModel.closeSelectedTab() },
            .init(id: "model-picker", label: "Switch Model", subtitle: "Change AI provider and model", icon: "cpu", shortcut: "⌘M") { dismiss(); windowModel.toggleModelPicker() },
            .init(id: "agent-picker", label: "Launch Agent", subtitle: "Start an AI agent session", icon: "bolt", shortcut: nil) { dismiss(); windowModel.openAgentPicker() },
            .init(id: "find", label: "Find in Scrollback", subtitle: "Search terminal output", icon: "magnifyingglass", shortcut: "⌘F") { windowModel.toggleSearchBar(); dismiss() },
            .init(id: "clear", label: "Clear Scrollback", subtitle: "Clear terminal history", icon: "trash", shortcut: "⌘K") { windowModel.clearSelectedScrollback(); dismiss() },
            .init(id: "split-h", label: "Split Horizontally", subtitle: "Split pane side by side", icon: "rectangle.split.2x1", shortcut: "⌘D") { windowModel.splitSelectedPane(.horizontal); dismiss() },
            .init(id: "split-v", label: "Split Vertically", subtitle: "Split pane top/bottom", icon: "rectangle.split.1x2", shortcut: "⌘⇧D") { windowModel.splitSelectedPane(.vertical); dismiss() },
            .init(id: "settings", label: "Settings", subtitle: "Open preferences", icon: "gear", shortcut: "⌘,") { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil); dismiss() },
            .init(id: "shell-integration", label: "Install Shell Integration", subtitle: "Enable shell hooks", icon: "terminal", shortcut: nil) { appModel.installShellIntegration(); dismiss() },
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
            ($0.subtitle?.lowercased().contains(q) ?? false)
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
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    TextField("Type a command or search...", text: $query)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.defaultFont(15))
                        .onSubmit {
                            if let first = actions.first { 
                                first.action() 
                            }
                        }
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.m)
                .background(DesignSystem.Colors.backgroundPrimary)
                
                SubtleDivider()
                
                // Actions list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
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
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 380)
                    .onAppear { selectedIndex = 0 }
                    .onChange(of: query) { _ in selectedIndex = 0 }
                }
                
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
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                    .fill(.thinMaterial)
            )
            .modernShadow(DesignSystem.Shadows.large)
            .padding(.top, 100)
            .frame(maxHeight: .infinity, alignment: .top)
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
                .font(.system(size: 14))
                .frame(width: 24)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(action.label)
                    .font(DesignSystem.Typography.defaultFont(13, weight: isSelected ? .medium : .regular))
                
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Typography.defaultFont(11))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(DesignSystem.Typography.mono(10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                    )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
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
