# aTerm

Native macOS terminal emulator prototype with:

- Real `zsh` PTY sessions
- Per-tab themes and profiles
- Direct provider integrations with Keychain-backed secrets
- Smart input classification
- Managed agent tabs
- MCP server lifecycle controls

## Development

Requirements:

- macOS 13+
- Xcode 26+
- Swift 6.2+

Build:

```bash
swift build
```

Run from Xcode or by opening the Swift package in Xcode.

## Quick Start

1. Open the app.
2. Configure an AI provider in the sidebar.
3. Pick a model with `Cmd+M`.
4. Type shell commands, natural language requests, or questions in the smart input bar.
5. Launch agent tabs from the tab bar bolt button.

## Shell Integration

Use Preferences or onboarding to install the bundled `zsh` integration script. That enables cwd/title reporting hooks used by the terminal tabs.

## Status

This repo is a local-first prototype. Several Phase 8 items remain incomplete, most notably split panes, DMG packaging, and a full protocol-complete MCP client.
