import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appThemePreference") private var themePreference: String = AppThemePreference.system.rawValue
    @State private var resolvedShellPath = "/bin/zsh"

    var body: some View {
        Form {
            Section("Shell") {
                LabeledContent("Default Shell") {
                    Text(resolvedShellPath)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Default Profile") {
                    Picker("", selection: Binding(
                        get: { appModel.defaultProfileID ?? appModel.profiles.first?.id ?? UUID() },
                        set: { appModel.setDefaultProfile($0) }
                    )) {
                        ForEach(appModel.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            Section("Appearance") {
                LabeledContent("Theme") {
                    Picker("", selection: $themePreference) {
                        ForEach(AppThemePreference.allCases) { pref in
                            Text(pref.rawValue).tag(pref.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            Section("Shell Integration") {
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
        .task {
            resolvedShellPath = (try? ShellLocator.detectZsh()) ?? "/bin/zsh"
        }
    }
}
