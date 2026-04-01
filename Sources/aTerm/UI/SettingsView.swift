import SwiftUI

/// One section at a time so opening Settings does not eagerly build every tab (Providers list,
/// MCP rows, key recorder, etc.), which can freeze the main window on slower machines.
private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case providers
    case profiles
    case agents
    case mcp
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .providers: return "Providers"
        case .profiles: return "Profiles"
        case .agents: return "Agents"
        case .mcp: return "MCP"
        case .shortcuts: return "Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "network"
        case .profiles: return "person.crop.square"
        case .agents: return "bolt"
        case .mcp: return "server.rack"
        case .shortcuts: return "keyboard"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var section: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(SettingsSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Group {
                switch section {
                case .general:
                    GeneralSettingsTab()
                case .providers:
                    ProvidersSettingsTab()
                case .profiles:
                    ProfilesSettingsTab()
                case .agents:
                    AgentsSettingsTab()
                case .mcp:
                    MCPSettingsTab()
                case .shortcuts:
                    KeybindingsSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 560, idealHeight: 620)
    }
}
