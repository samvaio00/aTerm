import SwiftUI

// MARK: - Help Guide Catalog

struct HelpCommandItem: Identifiable {
    let id = UUID()
    let command: String
    let aliases: [String]
    let summary: String
    let example: String
    let accent: Color
}

struct HelpShortcutItem: Identifiable {
    let id = UUID()
    let keys: String
    let action: String
}

enum HelpGuideCatalog {
    static let slashCommands: [HelpCommandItem] = [
        HelpCommandItem(
            command: "/help",
            aliases: ["/commands", "/?", "/ai"],
            summary: "Prints the complete Usage & /Commands reference directly in your terminal scrollback.",
            example: "/help",
            accent: .cyan
        ),
        HelpCommandItem(
            command: "/chat [message]",
            aliases: [],
            summary: "Enters interactive multi-turn AI Chat Mode inside the terminal. Pass an optional message to ask immediately.",
            example: "/chat how do I optimize this Dockerfile?",
            accent: .purple
        ),
        HelpCommandItem(
            command: "/exit",
            aliases: ["/chat-exit", "/quit", "/q"],
            summary: "Exits AI Chat Mode and returns to your zsh shell prompt (Ctrl+C or Ctrl+D on an empty line also exits).",
            example: "/exit",
            accent: .secondary
        ),
        HelpCommandItem(
            command: "/ask <question>",
            aliases: ["? <question>", "!<question>"],
            summary: "Forces inline AI question answering and streams the response directly into the terminal.",
            example: "/ask what is the difference between soft and mixed git reset?",
            accent: .cyan
        ),
        HelpCommandItem(
            command: "/cmd <task>",
            aliases: ["?? <task>", "><task>"],
            summary: "Generates a zsh command from natural language and executes it (or prefills your prompt if destructive).",
            example: "/cmd find all files larger than 100MB modified this week",
            accent: .yellow
        ),
        HelpCommandItem(
            command: "/explain [note]",
            aliases: ["/why", "explain"],
            summary: "Analyzes the last failed command, exit code, and terminal output to explain the error and suggest a fix.",
            example: "/explain why did the codesign step fail?",
            accent: .orange
        ),
        HelpCommandItem(
            command: "/fix [hint]",
            aliases: ["fix"],
            summary: "Generates a corrected command for the most recent command failure and prefills your zsh prompt.",
            example: "/fix use the current git branch name",
            accent: .green
        ),
        HelpCommandItem(
            command: "/model [name]",
            aliases: ["/models"],
            summary: "Displays the active AI provider & model, or switches to a matching model inline without opening a menu.",
            example: "/model claude",
            accent: .blue
        ),
        HelpCommandItem(
            command: "/smart",
            aliases: ["/mode smart"],
            summary: "Switches the pane to Smart routing: shell commands run in zsh while natural language routes to AI.",
            example: "/smart",
            accent: .yellow
        ),
        HelpCommandItem(
            command: "/shell",
            aliases: ["/mode shell"],
            summary: "Switches the pane to Shell-only routing: unprefixed input goes strictly to zsh; use ?, ??, !, or / for AI.",
            example: "/shell",
            accent: .green
        ),
        HelpCommandItem(
            command: "/mode",
            aliases: [],
            summary: "Shows whether the current pane is in Smart or Shell-only routing mode.",
            example: "/mode",
            accent: .teal
        ),
        HelpCommandItem(
            command: "/clear",
            aliases: ["/reset"],
            summary: "Clears terminal scrollback and resets the AI conversation history for the active pane.",
            example: "/clear",
            accent: .red
        )
    ]

    static let prefixCommands: [HelpCommandItem] = [
        HelpCommandItem(
            command: "? <question>",
            aliases: ["!<question>"],
            summary: "Ask AI a question inline from the zsh prompt without switching modes.",
            example: "? how do I check which process is listening on port 8080",
            accent: .cyan
        ),
        HelpCommandItem(
            command: "?? <task>",
            aliases: ["><task>"],
            summary: "Translate natural language into a zsh command and run it inline.",
            example: "?? compress the build folder into a tar.gz archive",
            accent: .yellow
        ),
        HelpCommandItem(
            command: "$ <command>",
            aliases: [],
            summary: "Bypass AI classification and force raw shell execution in zsh.",
            example: "$ echo \"hello world\"",
            accent: .green
        ),
        HelpCommandItem(
            command: "explain / fix",
            aliases: ["explain why"],
            summary: "Type `explain` or `fix` directly at the prompt after a failed command to diagnose or repair it.",
            example: "fix",
            accent: .orange
        )
    ]

    static let shortcuts: [HelpShortcutItem] = [
        HelpShortcutItem(keys: "⌘T", action: "New Terminal Tab"),
        HelpShortcutItem(keys: "⌘W", action: "Close Active Tab"),
        HelpShortcutItem(keys: "⌘D", action: "Split Pane Right (Horizontal)"),
        HelpShortcutItem(keys: "⇧⌘D", action: "Split Pane Down (Vertical)"),
        HelpShortcutItem(keys: "⌘M", action: "Open AI Model Picker"),
        HelpShortcutItem(keys: "⌘P", action: "Open Command Palette"),
        HelpShortcutItem(keys: "⌘F", action: "Find in Terminal Scrollback"),
        HelpShortcutItem(keys: "⌘K", action: "Clear Terminal Scrollback"),
        HelpShortcutItem(keys: "⇧⌘S", action: "Export Terminal Output to File"),
        HelpShortcutItem(keys: "⌃C", action: "Cancel Active AI Stream / Interrupt Shell")
    ]
}

// MARK: - Full Help Settings / Modal Content View

struct HelpSettingsTab: View {
    @State private var filterText = ""

    private var filteredSlashCommands: [HelpCommandItem] {
        guard !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return HelpGuideCatalog.slashCommands
        }
        let q = filterText.lowercased()
        return HelpGuideCatalog.slashCommands.filter {
            $0.command.lowercased().contains(q) ||
            $0.aliases.contains(where: { $0.lowercased().contains(q) }) ||
            $0.summary.lowercased().contains(q) ||
            $0.example.lowercased().contains(q)
        }
    }

    private var filteredPrefixes: [HelpCommandItem] {
        guard !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return HelpGuideCatalog.prefixCommands
        }
        let q = filterText.lowercased()
        return HelpGuideCatalog.prefixCommands.filter {
            $0.command.lowercased().contains(q) ||
            $0.aliases.contains(where: { $0.lowercased().contains(q) }) ||
            $0.summary.lowercased().contains(q) ||
            $0.example.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header & Search
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.cyan)
                            Text("aTerm Usage & /Commands Guide")
                                .font(DesignSystem.Typography.defaultFont(16, weight: .semibold))
                        }
                        Text("Everything works directly at your normal zsh prompt—no separate input box required.")
                            .font(DesignSystem.Typography.defaultFont(12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("Filter commands...", text: $filterText)
                            .textFieldStyle(.plain)
                            .font(DesignSystem.Typography.defaultFont(12))
                            .frame(width: 170)
                        if !filterText.isEmpty {
                            Button {
                                filterText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }

                // Usage Overview Cards
                if filterText.isEmpty {
                    usageOverviewSection
                }

                // Slash Commands Section
                if !filteredSlashCommands.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Slash (/) Commands", systemImage: "slash.circle.fill")
                            .font(DesignSystem.Typography.defaultFont(13, weight: .semibold))
                            .foregroundStyle(.primary)

                        VStack(spacing: 8) {
                            ForEach(filteredSlashCommands) { item in
                                HelpCommandRowCard(item: item)
                            }
                        }
                    }
                }

                // Inline Prefixes Section
                if !filteredPrefixes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Inline Shorthand Prefixes", systemImage: "terminal.fill")
                            .font(DesignSystem.Typography.defaultFont(13, weight: .semibold))
                            .foregroundStyle(.primary)

                        VStack(spacing: 8) {
                            ForEach(filteredPrefixes) { item in
                                HelpCommandRowCard(item: item)
                            }
                        }
                    }
                }

                // Keyboard Shortcuts Section
                if filterText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Keyboard Shortcuts", systemImage: "keyboard")
                            .font(DesignSystem.Typography.defaultFont(13, weight: .semibold))
                            .foregroundStyle(.primary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(HelpGuideCatalog.shortcuts) { shortcut in
                                HStack {
                                    Text(shortcut.action)
                                        .font(DesignSystem.Typography.defaultFont(12))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(shortcut.keys)
                                        .font(DesignSystem.Typography.mono(11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .fill(Color.primary.opacity(0.08))
                                        )
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var usageOverviewSection: some View {
        HStack(alignment: .top, spacing: 12) {
            usageCard(
                icon: "bolt.fill",
                color: .yellow,
                title: "1. Smart Shell Prompt",
                bodyText: "Type normal shell commands (`ls`, `git`, `vim`, pipes, tab completion) and they execute natively in zsh. Type a question or task in plain English and aTerm routes it to AI inline."
            )
            usageCard(
                icon: "bubble.left.and.bubble.right.fill",
                color: .purple,
                title: "2. Multi-Turn /chat Mode",
                bodyText: "Run `/chat` (or click the Chat pill in the pane header) to enter an interactive `chat>` session with conversation memory. Type `/exit` or press `Ctrl+C` to return to zsh."
            )
            usageCard(
                icon: "wrench.and.screwdriver.fill",
                color: .orange,
                title: "3. Instant Error Recovery",
                bodyText: "When a command exits with an error (`✗ exit N`), type `/explain` or `/fix`—or click the **Explain** / **Fix** buttons in the pane header—to diagnose or prefill a corrected command."
            )
        }
    }

    private func usageCard(icon: String, color: Color, title: String, bodyText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignSystem.Typography.defaultFont(12, weight: .semibold))
            }
            Text(.init(bodyText))
                .font(DesignSystem.Typography.defaultFont(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.m, style: .continuous)
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

private struct HelpCommandRowCard: View {
    let item: HelpCommandItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.command)
                        .font(DesignSystem.Typography.mono(12, weight: .semibold))
                        .foregroundStyle(item.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(item.accent.opacity(0.12))
                        )

                    ForEach(item.aliases, id: \.self) { alias in
                        Text(alias)
                            .font(DesignSystem.Typography.mono(10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }

                Text(item.summary)
                    .font(DesignSystem.Typography.defaultFont(12))
                    .foregroundStyle(.primary.opacity(0.9))

                HStack(spacing: 4) {
                    Text("Example:")
                        .font(DesignSystem.Typography.defaultFont(10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(item.example)
                        .font(DesignSystem.Typography.mono(10))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Compact Sidebar Help Section View

struct SidebarHelpSectionView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var tab: TerminalTabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Quick Actions Card
            VStack(alignment: .leading, spacing: 8) {
                Label("Quick Terminal Actions", systemImage: "bolt.horizontal.circle")
                    .font(.headline)

                Text("Run a command in the focused pane or open the full interactive reference.")
                    .font(DesignSystem.Typography.defaultFont(11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        if let pane = tab.activePane {
                            pane.prepareForInlineAIOutput(lineAlreadyBufferedInShell: false)
                            appModel.writeInlineAIHelp(to: pane)
                            pane.finishInlineAIOutput()
                        }
                    } label: {
                        Label("Print /help", systemImage: "terminal")
                    }
                    .buttonStyle(ModernButtonStyle(variant: .secondary, size: .s))

                    Button {
                        windowModel.isHelpPresented = true
                    } label: {
                        Label("Full Guide", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(ModernButtonStyle(variant: .primary, size: .s))
                }
            }

            Divider().opacity(0.4)

            // How Usage Works
            VStack(alignment: .leading, spacing: 8) {
                Label("How Usage Works", systemImage: "sparkles")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    sidebarBullet(
                        badge: "Smart",
                        color: .yellow,
                        text: "Shell commands (`ls`, `git`, `vim`, pipes) run natively in zsh; plain-English questions & tasks route to AI inline."
                    )
                    sidebarBullet(
                        badge: "Shell",
                        color: .green,
                        text: "Unprefixed lines always run in zsh. Prefix with `?`, `??`, `!`, or `/` whenever you want AI assistance."
                    )
                    sidebarBullet(
                        badge: "Chat",
                        color: .purple,
                        text: "Multi-turn AI conversation inside your terminal (`chat>`). Exit anytime with `/exit` or `Ctrl+C`."
                    )
                }
            }

            Divider().opacity(0.4)

            // Slash Commands Reference
            VStack(alignment: .leading, spacing: 8) {
                Label("Slash (/) Commands", systemImage: "slash.circle")
                    .font(.headline)

                VStack(spacing: 6) {
                    ForEach(HelpGuideCatalog.slashCommands) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.command)
                                    .font(DesignSystem.Typography.mono(11, weight: .semibold))
                                    .foregroundStyle(item.accent)
                                if !item.aliases.isEmpty {
                                    Text(item.aliases.joined(separator: ", "))
                                        .font(DesignSystem.Typography.mono(10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Text(item.summary)
                                .font(DesignSystem.Typography.defaultFont(11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        )
                    }
                }
            }

            Divider().opacity(0.4)

            // Inline Prefixes Reference
            VStack(alignment: .leading, spacing: 8) {
                Label("Inline Prefixes", systemImage: "chevron.right.square")
                    .font(.headline)

                VStack(spacing: 6) {
                    ForEach(HelpGuideCatalog.prefixCommands) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.command)
                                    .font(DesignSystem.Typography.mono(11, weight: .semibold))
                                    .foregroundStyle(item.accent)
                                if !item.aliases.isEmpty {
                                    Text(item.aliases.joined(separator: ", "))
                                        .font(DesignSystem.Typography.mono(10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Text(item.summary)
                                .font(DesignSystem.Typography.defaultFont(11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        )
                    }
                }
            }
        }
    }

    private func sidebarBullet(badge: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(badge)
                .font(DesignSystem.Typography.mono(10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 46, alignment: .center)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.14))
                )
            Text(.init(text))
                .font(DesignSystem.Typography.defaultFont(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
