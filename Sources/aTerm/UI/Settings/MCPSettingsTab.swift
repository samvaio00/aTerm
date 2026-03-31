import SwiftUI

struct MCPSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            ForEach(appModel.availableMCPServers) { server in
                let snapshot = appModel.mcpSnapshots[server.id]
                let status = snapshot?.status ?? .stopped
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor(status))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(server.name).fontWeight(.medium)
                            Text("(\(server.transport == .stdio ? "stdio" : "SSE"))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(snapshot?.toolCount ?? 0) tools")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if let error = snapshot?.lastError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        if status == .running {
                            Button("Stop") {
                                appModel.stopMCPServer(server)
                            }
                            .controlSize(.small)
                            Button("Restart") {
                                appModel.restartMCPServer(server, cwd: appModel.selectedTab?.currentWorkingDirectory)
                            }
                            .controlSize(.small)
                        } else {
                            Button("Start") {
                                appModel.startMCPServer(server, cwd: appModel.selectedTab?.currentWorkingDirectory)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func statusColor(_ status: MCPServerStatus) -> Color {
        switch status {
        case .running: return .green
        case .error: return .red
        case .stopped: return .gray.opacity(0.5)
        }
    }
}
