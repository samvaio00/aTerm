import SwiftUI

struct KeybindingsSettingsTab: View {
    @State private var bindings: [KeyBinding] = KeybindingStore().load()
    @State private var editingBindingID: String?
    @State private var pendingKeyDisplay: String?
    private let store = KeybindingStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                // Editable app shortcuts
                Section("App Shortcuts") {
                    ForEach($bindings) { $binding in
                        HStack {
                            Text(binding.action)
                                .frame(width: 180, alignment: .leading)

                            if editingBindingID == binding.id {
                                Text(pendingKeyDisplay ?? "Press a key...")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .frame(width: 160, alignment: .leading)
                                    .background(
                                        KeyRecorderView { event in
                                            let display = KeybindingStore.displayString(for: event)
                                            binding.key = display
                                            binding.keyEquivalent = event.charactersIgnoringModifiers ?? ""
                                            binding.modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                                            editingBindingID = nil
                                            pendingKeyDisplay = nil
                                            store.save(bindings)
                                        }
                                        .frame(width: 1, height: 1)
                                        .opacity(0)
                                    )

                                Button("Cancel") {
                                    editingBindingID = nil
                                    pendingKeyDisplay = nil
                                }
                                .controlSize(.small)
                            } else {
                                Text(binding.key)
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(width: 160, alignment: .leading)

                                Button("Record") {
                                    editingBindingID = binding.id
                                    pendingKeyDisplay = nil
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }

                // Read-only terminal shortcuts
                Section("Terminal Shortcuts (not rebindable)") {
                    ForEach([
                        ("Ctrl+C", "Interrupt (SIGINT)"),
                        ("Ctrl+D", "EOF"),
                        ("Ctrl+Z", "Suspend (SIGTSTP)"),
                    ], id: \.0) { key, action in
                        HStack {
                            Text(action)
                                .frame(width: 180, alignment: .leading)
                            Text(key)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Button("Reset to Defaults") {
                    bindings = KeybindingStore.defaultBindings
                    store.save(bindings)
                }
                .controlSize(.small)
            }
            .padding(12)
        }
    }
}

/// NSView that captures a single key event for recording a shortcut
struct KeyRecorderView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    class KeyRecorderNSView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            // Only accept if a modifier is pressed (prevent bare letter captures)
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.isEmpty else { return }
            onKeyDown?(event)
        }
    }
}
