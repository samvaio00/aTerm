import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProvidersSettingsTab()
                .tabItem { Label("Providers", systemImage: "network") }
            ProfilesSettingsTab()
                .tabItem { Label("Profiles", systemImage: "person.crop.square") }
            AgentsSettingsTab()
                .tabItem { Label("Agents", systemImage: "bolt") }
            MCPSettingsTab()
                .tabItem { Label("MCP", systemImage: "server.rack") }
            KeybindingsSettingsTab()
                .tabItem { Label("Keys", systemImage: "keyboard") }
        }
        .padding(16)
        .frame(width: 780, height: 600)
    }
}
