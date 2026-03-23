import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system = "Follow System"
    case light = "Always Light"
    case dark = "Always Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct ATermApp: App {
    @StateObject private var appModel = AppModel()
    @AppStorage("appThemePreference") private var themePreference: String = AppThemePreference.system.rawValue

    private var resolvedScheme: ColorScheme? {
        AppThemePreference(rawValue: themePreference)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
                .environmentObject(appModel)
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(resolvedScheme)
        }
        .defaultSize(width: 1080, height: 720)
        .handlesExternalEvents(matching: ["aterm"])
        .commands {
            // Cmd+N is automatically provided by WindowGroup for new windows

            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openNewWindow()
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("New Tab") {
                    // Post to the focused window's WindowModel
                    NotificationCenter.default.post(name: .aTermNewTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Button("Close Tab") {
                    NotificationCenter.default.post(name: .aTermCloseTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Model Picker") {
                    NotificationCenter.default.post(name: .aTermToggleModelPicker, object: nil)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("Find in Scrollback") {
                    NotificationCenter.default.post(name: .aTermToggleSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Clear Scrollback") {
                    NotificationCenter.default.post(name: .aTermClearScrollback, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Split Pane Horizontally") {
                    NotificationCenter.default.post(name: .aTermSplitH, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Split Pane Vertically") {
                    NotificationCenter.default.post(name: .aTermSplitV, object: nil)
                }
                .keyboardShortcut("D", modifiers: [.command, .shift])

                Button("Command Palette") {
                    NotificationCenter.default.post(name: .aTermCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Save Terminal Output...") {
                    NotificationCenter.default.post(name: .aTermSaveOutput, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }

    // MARK: - URL Scheme Handling (aterm://open?path=/some/dir)

    func handleURL(_ url: URL) {
        guard url.scheme == "aterm", url.host == "open" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let path = components?.queryItems?.first(where: { $0.name == "path" })?.value else { return }
        let directoryURL = URL(fileURLWithPath: path)

        // Post notification — the focused window will handle it
        NotificationCenter.default.post(name: .aTermOpenDirectory, object: directoryURL)
    }

    private func openNewWindow() {
        // SwiftUI WindowGroup handles this via openWindow,
        // but for compatibility we use NSApp
        if let currentWindow = NSApp.keyWindow {
            // Cmd+N in WindowGroup creates a new window automatically
            // Trigger the default behavior
            NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
            _ = currentWindow // suppress warning
        }
    }
}

// MARK: - Command Notification Names

extension Notification.Name {
    static let aTermNewTab = Notification.Name("aTermNewTab")
    static let aTermCloseTab = Notification.Name("aTermCloseTab")
    static let aTermToggleModelPicker = Notification.Name("aTermToggleModelPicker")
    static let aTermToggleSearch = Notification.Name("aTermToggleSearch")
    static let aTermClearScrollback = Notification.Name("aTermClearScrollback")
    static let aTermSplitH = Notification.Name("aTermSplitH")
    static let aTermSplitV = Notification.Name("aTermSplitV")
    static let aTermCommandPalette = Notification.Name("aTermCommandPalette")
    static let aTermSaveOutput = Notification.Name("aTermSaveOutput")
    static let aTermOpenDirectory = Notification.Name("aTermOpenDirectory")
}
