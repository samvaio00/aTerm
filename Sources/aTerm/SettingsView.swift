import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ProfilesSettingsTab()
                .tabItem { Label("Profiles", systemImage: "person.crop.square") }
            ProvidersSettingsTab()
                .tabItem { Label("Providers", systemImage: "network") }
            AgentsSettingsTab()
                .tabItem { Label("Agents", systemImage: "bolt") }
            MCPSettingsTab()
                .tabItem { Label("MCP", systemImage: "server.rack") }
            KeybindingsSettingsTab()
                .tabItem { Label("Keys", systemImage: "keyboard") }
        }
        .padding(16)
        .frame(width: 760, height: 560)
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            LabeledContent("Default Shell") {
                Text((try? ShellLocator.detectZsh()) ?? "/bin/zsh")
                    .font(.system(size: 12, design: .monospaced))
            }
            LabeledContent("Default Profile") {
                Text(appModel.profiles.first(where: { $0.id == appModel.defaultProfileID })?.name ?? "Default")
            }
            Button("Install Shell Integration") {
                appModel.installShellIntegration()
            }
            if let message = appModel.shellIntegrationMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppearanceSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Text("Themes: \(appModel.allThemes.count)")
            Text("Monospace Fonts: \(FontSupport.monospaceFontNames().count)")
            Text("Theme preview and per-tab appearance controls remain available in the main sidebar.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfilesSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(appModel.profiles) { profile in
            HStack {
                Text(profile.name)
                Spacer()
                if appModel.defaultProfileID == profile.id {
                    Text("Default")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ProvidersSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(appModel.availableProviders) { provider in
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name)
                Text(provider.endpoint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AgentsSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(appModel.availableAgents) { agent in
            HStack {
                Circle()
                    .fill((appModel.agentStatuses[agent.id]?.isInstalled ?? false) ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(agent.name)
                Spacer()
                Text(appModel.agentStatuses[agent.id]?.executablePath ?? agent.installHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct MCPSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(appModel.availableMCPServers) { server in
            let snapshot = appModel.mcpSnapshots[server.id]
            HStack {
                Circle()
                    .fill(color(for: snapshot?.status ?? .stopped))
                    .frame(width: 8, height: 8)
                Text(server.name)
                Spacer()
                Text("\(snapshot?.toolCount ?? 0) tools")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for status: MCPServerStatus) -> Color {
        switch status {
        case .running: return .green
        case .error: return .red
        case .stopped: return .gray
        }
    }
}

private struct KeybindingsSettingsTab: View {
    var body: some View {
        List {
            Text("Cmd+T  New Tab")
            Text("Cmd+W  Close Tab")
            Text("Cmd+M  Model Picker")
            Text("Cmd+,  Preferences")
            Text("Cmd+F  Find in Scrollback")
            Text("Cmd+K  Clear Scrollback")
            Text("Cmd+D  Split Pane Horizontally")
            Text("Cmd+Shift+D  Split Pane Vertically")
        }
    }
}
