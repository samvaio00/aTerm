import SwiftUI

struct AgentsSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section {
                Button("Scan again") {
                    appModel.refreshAgentInstallationStatuses()
                }
            } footer: {
                Text("Looks in Homebrew paths, ~/.local/bin, Volta, path_helper output, and the app environment PATH.")
            }

            Section("Installed agents") {
                ForEach(appModel.availableAgents) { agent in
                HStack(spacing: 10) {
                    Circle()
                        .fill((appModel.agentStatuses[agent.id]?.isInstalled ?? false) ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name).fontWeight(.medium)
                        if let path = appModel.agentStatuses[agent.id]?.executablePath {
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Text("Not installed:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(agent.installHint)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    Spacer()
                    if appModel.defaultAgentID == agent.id {
                        Text("Default")
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Button("Set Default") {
                            appModel.setDefaultAgent(agent.id)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                }
                }
            }
        }
        .formStyle(.grouped)
    }
}
