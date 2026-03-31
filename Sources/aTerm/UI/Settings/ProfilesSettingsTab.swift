import SwiftUI

struct ProfilesSettingsTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(appModel.profiles) { profile in
                    HStack {
                        Text(profile.name)
                            .fontWeight(appModel.defaultProfileID == profile.id ? .bold : .regular)
                        Spacer()
                        if appModel.defaultProfileID == profile.id {
                            Text("Default")
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15))
                                .clipShape(Capsule())
                        } else {
                            Button("Set Default") {
                                appModel.setDefaultProfile(profile.id)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                TextField("New profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)
                Button("Create from Current Tab") {
                    guard !newProfileName.isEmpty else { return }
                    appModel.createProfileFromSelectedTab(named: newProfileName)
                    newProfileName = ""
                }
                .disabled(newProfileName.isEmpty)
            }
            .padding(.horizontal, 8)
        }
    }
}
