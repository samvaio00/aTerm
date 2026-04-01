import SwiftUI

struct ProfilesSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var newProfileName = ""

    var body: some View {
        Form {
            Section("Profiles") {
                ForEach(appModel.profiles) { profile in
                    HStack {
                        Text(profile.name)
                            .fontWeight(appModel.defaultProfileID == profile.id ? .bold : .regular)
                        Spacer()
                        if appModel.defaultProfileID == profile.id {
                            Text("Default")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15))
                                .clipShape(Capsule())
                        } else {
                            Button("Set default") {
                                appModel.setDefaultProfile(profile.id)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section("New profile") {
                LabeledContent("Name") {
                    TextField("Profile name", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Create from current tab") {
                    guard !newProfileName.isEmpty else { return }
                    appModel.createProfileFromSelectedTab(named: newProfileName)
                    newProfileName = ""
                }
                .disabled(newProfileName.isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}
