import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var step = 0

    private let titles = [
        "Welcome to aTerm",
        "Detect Agents",
        "Add AI Provider",
        "Choose Theme",
        "Shell Integration",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<titles.count, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Text(titles[step])
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 12)

            // Step content
            Group {
                switch step {
                case 0: welcomeStep
                case 1: agentStep
                case 2: providerStep
                case 3: themeStep
                default: shellIntegrationStep
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            // Navigation
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .controlSize(.large)
                }
                Spacer()
                Button(step == titles.count - 1 ? "Get Started" : "Next") {
                    if step == titles.count - 1 {
                        appModel.completeOnboarding()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, 16)
        }
        .padding(28)
        .frame(width: 560, height: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 12) {
            Text("A native macOS terminal with flexible AI, agents, and MCP tools. No backend, no telemetry — everything runs locally.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                featureIcon("terminal", "Real PTY Shell")
                featureIcon("brain", "Multi-Provider AI")
                featureIcon("bolt", "Managed Agents")
                featureIcon("server.rack", "MCP Tools")
            }
            .padding(.top, 8)
        }
    }

    private func featureIcon(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 90)
    }

    // MARK: - Step 1: Agents

    private var agentStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("We scanned your system for coding agents:")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(appModel.availableAgents) { agent in
                        let status = appModel.agentStatuses[agent.id]
                        let installed = status?.isInstalled ?? false
                        HStack(spacing: 10) {
                            Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(installed ? .green : .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name).fontWeight(.medium)
                                if installed {
                                    Text(status?.executablePath ?? "")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                } else {
                                    HStack(spacing: 4) {
                                        Text(agent.installHint)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.orange)
                                            .textSelection(.enabled)
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(agent.installHint, forType: .string)
                                        } label: {
                                            Image(systemName: "doc.on.clipboard")
                                                .font(.system(size: 10))
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Copy install command")
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(installed ? Color.green.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Provider

    @State private var selectedPreset: String = "anthropic"
    @State private var apiKey: String = ""
    @State private var providerTestResult: String?

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a provider and enter your API key to enable AI features.")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            Picker("Provider", selection: $selectedPreset) {
                ForEach(appModel.availableProviders) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .labelsHidden()

            if let provider = appModel.provider(for: selectedPreset), provider.authType != .none {
                SecureField("Paste your API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("Save & Test") {
                        guard let provider = appModel.provider(for: selectedPreset), !apiKey.isEmpty else { return }
                        try? appModel.upsertProvider(provider, secret: apiKey)
                        providerTestResult = "Testing..."
                        Task {
                            await appModel.testConnection(for: provider)
                            providerTestResult = appModel.providerStatusMessage
                        }
                    }
                    .disabled(apiKey.isEmpty)

                    if let result = providerTestResult {
                        Text(result)
                            .font(.system(size: 12))
                            .foregroundColor(result.contains("ms") ? .green : .orange)
                            .lineLimit(2)
                    }
                }

                Text("Stored in macOS Keychain. Never saved to disk.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("This provider doesn't require authentication (e.g., local Ollama).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if appModel.providers.contains(where: { appModel.hasStoredCredential(for: $0.id) }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("You have credentials configured. You can add more in Settings later.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Step 3: Theme

    private var themeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick a theme. You can change this anytime from the sidebar.")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 10)]
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(appModel.allThemes) { theme in
                        let isActive = appModel.selectedTab?.appearance.themeID == theme.id
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(theme.palette.background.nsColor))
                                .frame(height: 52)
                                .overlay(
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("$ ls")
                                            .foregroundColor(Color(theme.palette.foreground.nsColor))
                                        Text("README")
                                            .foregroundColor(Color(theme.palette.ansi.indices.contains(4) ? theme.palette.ansi[4].nsColor : theme.palette.foreground.nsColor))
                                    }
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(6),
                                    alignment: .topLeading
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                            Text(theme.name)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .onTapGesture {
                            appModel.applyTheme(theme)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Shell Integration

    private var shellIntegrationStep: some View {
        VStack(spacing: 14) {
            Text("Install the shell integration script for working directory reporting and enhanced terminal hooks.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            Button("Install Shell Integration") {
                appModel.installShellIntegration()
            }
            .controlSize(.large)

            if let message = appModel.shellIntegrationMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(message.contains("Installed") ? .green : .orange)
            }

            Text("This sources a small script in your .zshrc. You can skip this and install later from Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
