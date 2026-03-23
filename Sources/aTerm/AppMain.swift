import SwiftUI

@main
struct ATermApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 720)
        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appModel.createTabAndSelect()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Button("Close Tab") {
                    appModel.closeSelectedTab()
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appModel.selectedTab == nil)

                Button("Model Picker") {
                    appModel.toggleModelPicker()
                }
                .keyboardShortcut("m", modifiers: .command)
                .disabled(appModel.selectedTab == nil)

                Button("Find in Scrollback") {
                    appModel.toggleSearchBar()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(appModel.selectedTab == nil)

                Button("Clear Scrollback") {
                    appModel.clearSelectedScrollback()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(appModel.selectedTab == nil)

                Button("Split Pane Horizontally") {
                    appModel.splitSelectedPane(.horizontal)
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(appModel.selectedTab == nil)

                Button("Split Pane Vertically") {
                    appModel.splitSelectedPane(.vertical)
                }
                .keyboardShortcut("D", modifiers: [.command, .shift])
                .disabled(appModel.selectedTab == nil)

                Button("Command Palette") {
                    appModel.isCommandPalettePresented.toggle()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
    }
}
