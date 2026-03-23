import AppKit
import Foundation

struct KeyBinding: Identifiable, Codable, Hashable {
    let id: String          // Action identifier e.g. "newTab"
    let action: String      // Display name
    var key: String         // Display string e.g. "Cmd+T"
    var keyEquivalent: String  // SwiftUI KeyboardShortcut character
    var modifiers: UInt     // NSEvent.ModifierFlags rawValue

    var eventModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }
}

struct KeybindingStore {
    static let defaultBindings: [KeyBinding] = [
        KeyBinding(id: "newTab", action: "New Tab", key: "Cmd+T", keyEquivalent: "t", modifiers: NSEvent.ModifierFlags.command.rawValue),
        KeyBinding(id: "closeTab", action: "Close Tab", key: "Cmd+W", keyEquivalent: "w", modifiers: NSEvent.ModifierFlags.command.rawValue),
        KeyBinding(id: "modelPicker", action: "Model Picker", key: "Cmd+M", keyEquivalent: "m", modifiers: NSEvent.ModifierFlags.command.rawValue),
        KeyBinding(id: "preferences", action: "Preferences", key: "Cmd+,", keyEquivalent: ",", modifiers: NSEvent.ModifierFlags.command.rawValue),
        KeyBinding(id: "find", action: "Find in Scrollback", key: "Cmd+F", keyEquivalent: "f", modifiers: NSEvent.ModifierFlags.command.rawValue),
        KeyBinding(id: "clear", action: "Clear Scrollback", key: "Cmd+K", keyEquivalent: "k", modifiers: NSEvent.ModifierFlags.command.rawValue),
        KeyBinding(id: "splitH", action: "Split Horizontally", key: "Cmd+D", keyEquivalent: "d", modifiers: NSEvent.ModifierFlags.command.rawValue),
        KeyBinding(id: "splitV", action: "Split Vertically", key: "Cmd+Shift+D", keyEquivalent: "D", modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue),
        KeyBinding(id: "commandPalette", action: "Command Palette", key: "Cmd+P", keyEquivalent: "p", modifiers: NSEvent.ModifierFlags.command.rawValue),
    ]

    private let fileManager = FileManager.default

    func load() -> [KeyBinding] {
        guard let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode([KeyBinding].self, from: data) else {
            return Self.defaultBindings
        }
        // Merge: keep stored overrides, add any new defaults
        var result = stored
        for defaultBinding in Self.defaultBindings {
            if !result.contains(where: { $0.id == defaultBinding.id }) {
                result.append(defaultBinding)
            }
        }
        return result
    }

    func save(_ bindings: [KeyBinding]) {
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(bindings)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to save keybindings: \(error)\n", stderr)
        }
    }

    private var storageURL: URL {
        AppSupport.baseURL.appendingPathComponent("keybindings.json")
    }

    // MARK: - Key Display String

    static func displayString(for event: NSEvent) -> String {
        var parts: [String] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Cmd") }

        let keyName: String
        switch event.keyCode {
        case 36: keyName = "Return"
        case 48: keyName = "Tab"
        case 49: keyName = "Space"
        case 51: keyName = "Delete"
        case 53: keyName = "Escape"
        case 123: keyName = "Left"
        case 124: keyName = "Right"
        case 125: keyName = "Down"
        case 126: keyName = "Up"
        default:
            keyName = event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }
}
