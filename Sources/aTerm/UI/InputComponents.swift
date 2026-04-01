import AppKit
import SwiftUI

// MARK: - Modern Smart Input Bar

struct ModernSmartInputBar: View {
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var pane: TerminalPaneViewModel
    @State private var isFocused = false
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            // Mode indicator with icon
            ModeIndicator(mode: pane.modeIndicatorText)
            
            // Input field
            ModernTextField(
                placeholder: "Enter command, natural language, or question...",
                text: $pane.inputText,
                onSubmit: { windowModel.submitInput(for: pane) }
            )
            
            // Send button
            Button(action: { windowModel.submitInput(for: pane) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(pane.inputText.isEmpty ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(pane.inputText.isEmpty)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(isFocused ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .onAppear {
            // Track focus state
            NotificationCenter.default.addObserver(
                forName: NSControl.textDidBeginEditingNotification,
                object: nil,
                queue: .main
            ) { [self] _ in
                MainActor.assumeIsolated {
                    isFocused = true
                }
            }
            NotificationCenter.default.addObserver(
                forName: NSControl.textDidEndEditingNotification,
                object: nil,
                queue: .main
            ) { [self] _ in
                MainActor.assumeIsolated {
                    isFocused = false
                }
            }
        }
    }
}

// MARK: - Mode Indicator

private struct ModeIndicator: View {
    let mode: String
    
    var body: some View {
        let config = modeConfig
        
        HStack(spacing: 4) {
            Image(systemName: config.icon)
                .font(.system(size: 10))
            Text(config.label)
                .font(DesignSystem.Typography.mono(11, weight: .semibold))
        }
        .foregroundColor(config.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(config.color.opacity(0.1))
        .cornerRadius(DesignSystem.Radius.s)
    }
    
    private var modeConfig: (icon: String, label: String, color: Color) {
        switch mode {
        case InputMode.aiToShell.rawValue:
            return ("bolt.fill", "AI", .yellow)
        case InputMode.query.rawValue:
            return ("questionmark", "ASK", .blue)
        case "AMBIGUOUS":
            return ("exclamationmark.triangle", "?", .orange)
        case "ERROR":
            return ("exclamationmark.octagon", "ERR", .red)
        default:
            return ("dollarsign", "SH", .green)
        }
    }
}

// MARK: - Modern Text Field

struct ModernTextField: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(DesignSystem.Typography.mono(13))
            .onSubmit(onSubmit)
    }
}

// MARK: - Modern AI Shell Card

struct ModernAIShellCard: View {
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var pane: TerminalPaneViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text("Generated Command")
                        .font(DesignSystem.Typography.defaultFont(12, weight: .semibold))
                }
                
                Spacer()
                
                Button {
                    pane.aiShellState = AIShellState()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss (Esc)")
            }
            
            // Content
            Group {
                if pane.aiShellState.isGenerating {
                    HStack(spacing: 8) {
                        ModernProgressView(size: .small)
                        Text("Generating command...")
                            .font(DesignSystem.Typography.defaultFont(12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if pane.aiShellState.isEditing {
                    TextField("Command", text: $pane.aiShellState.generatedCommand, axis: .vertical)
                        .textFieldStyle(ModernTextFieldStyle())
                        .font(DesignSystem.Typography.mono(12))
                } else {
                    Text(pane.aiShellState.generatedCommand)
                        .font(DesignSystem.Typography.mono(12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                }
            }
            
            // Actions
            HStack(spacing: DesignSystem.Spacing.s) {
                Button(pane.aiShellState.isEditing ? "Done" : "Edit") {
                    pane.aiShellState.isEditing.toggle()
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .s))
                .disabled(pane.aiShellState.isGenerating)
                
                Spacer()
                
                Button("Run ↵") {
                    windowModel.runGeneratedCommand(for: pane)
                }
                .buttonStyle(ModernButtonStyle(variant: .primary, size: .s))
                .keyboardShortcut(.return, modifiers: [])
                .disabled(pane.aiShellState.isGenerating || pane.aiShellState.generatedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.l, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.l, style: .continuous)
                        .strokeBorder(Color.yellow.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.top, DesignSystem.Spacing.m)
        .onExitCommand {
            pane.aiShellState = AIShellState()
        }
    }
}

// MARK: - Modern Query Response Card

struct ModernQueryResponseCard: View {
    @EnvironmentObject private var windowModel: WindowModel
    @ObservedObject var pane: TerminalPaneViewModel
    @State private var isCollapsed = false

    /// Explicit label color so answer text stays visible over `.thinMaterial` regardless of window appearance.
    private static let answerTextColor = Color(nsColor: .labelColor)

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text(pane.queryResponse.isStreaming ? "Thinking..." : "Answer")
                        .font(DesignSystem.Typography.defaultFont(12, weight: .semibold))
                        .foregroundStyle(Self.answerTextColor)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    if !pane.queryResponse.isStreaming {
                        Button {
                            withAnimation(DesignSystem.Animation.fast) {
                                isCollapsed.toggle()
                            }
                        } label: {
                            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isCollapsed ? "Expand" : "Collapse")
                        
                        Button {
                            pane.queryResponse = QueryResponseState()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss")
                    }
                }
            }
            
            // Content
            if !isCollapsed {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(pane.queryResponse.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(DesignSystem.Typography.defaultFont(12))
                            .foregroundStyle(Self.answerTextColor)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                            .id("query-answer-bottom")
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: pane.queryResponse.text) { _ in
                        if pane.queryResponse.isStreaming {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo("query-answer-bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Suggestions
                if !pane.queryResponse.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                        Text("Suggested commands:")
                            .font(DesignSystem.Typography.defaultFont(11, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        ForEach(pane.queryResponse.suggestions) { suggestion in
                            HStack {
                                Text(suggestion.command)
                                    .font(DesignSystem.Typography.mono(11))
                                    .lineLimit(2)
                                Spacer()
                                Button("Run") {
                                    windowModel.runQuerySuggestion(suggestion, for: pane)
                                }
                                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .xs))
                            }
                            .padding(DesignSystem.Spacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.s, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            )
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.l, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.l, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.top, DesignSystem.Spacing.m)
        .colorScheme(.dark)
    }
}

// MARK: - Modern Disambiguation Bar

struct ModernDisambiguationBar: View {
    @EnvironmentObject private var windowModel: WindowModel
    let input: String
    @ObservedObject var pane: TerminalPaneViewModel
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("How should I interpret this?")
                    .font(DesignSystem.Typography.defaultFont(12, weight: .medium))
            }
            
            Spacer()
            
            HStack(spacing: DesignSystem.Spacing.s) {
                Button("Shell Command") {
                    windowModel.resolveDisambiguation(as: .terminal, for: pane)
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .s))
                
                Button("AI Query") {
                    windowModel.resolveDisambiguation(as: .query, for: pane)
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .s))
                
                Button("Generate Command") {
                    windowModel.resolveDisambiguation(as: .aiToShell, for: pane)
                }
                .buttonStyle(ModernButtonStyle(variant: .primary, size: .s))
            }
            
            Divider()
                .frame(height: 20)
            
            Text(input)
                .font(DesignSystem.Typography.mono(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
