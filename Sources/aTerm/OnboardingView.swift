import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var step = 0

    private let titles = [
        "Welcome",
        "Detect Agents",
        "Add Provider",
        "Choose Theme",
        "Install Shell Integration",
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text(titles[step])
                .font(.system(size: 24, weight: .bold))

            Group {
                switch step {
                case 0:
                    Text("aTerm combines native terminal sessions, model-flexible AI routing, agents, and MCP tools in a local-first macOS app.")
                case 1:
                    Text("Detected agents: \(appModel.availableAgents.filter { appModel.agentStatuses[$0.id]?.isInstalled == true }.map(\.name).joined(separator: ", "))")
                case 2:
                    Text("Configured providers: \(appModel.availableProviders.map(\.name).joined(separator: ", "))")
                case 3:
                    Text("Active theme count: \(appModel.allThemes.count). Per-tab theme controls are available in the sidebar.")
                default:
                    VStack(spacing: 10) {
                        Text("Install the shell integration script for cwd reporting and semantic shell hooks.")
                        Button("Install Now") {
                            appModel.installShellIntegration()
                        }
                    }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack {
                if step > 0 {
                    Button("Back") {
                        step -= 1
                    }
                }
                Spacer()
                Button(step == titles.count - 1 ? "Finish" : "Next") {
                    if step == titles.count - 1 {
                        appModel.completeOnboarding()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
