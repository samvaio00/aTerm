# Changelog

All notable changes to aTerm are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

---

## [0.1.0] — 2026-04-01

Initial public release.

### Terminal emulation

- Real `forkpty` / `zsh` PTY — not a pseudo-shell or embedded browser engine
- Full VT100 / xterm-256color: SGR in 16, 256, and 24-bit RGB; cursor movement; scroll control; DEC line drawing charset (G0/G1)
- Alternate screen buffer (DECSET 1047 / 1049) with cursor save and restore
- DECSTBM scroll regions, including preservation across terminal resize
- Bracketed paste mode (DECSET 2004)
- Application cursor keys (DECCKM), auto-wrap (DECAWM)
- Mouse reporting: modes 1000 / 1002 / 1003 with SGR extended (1006) and urxvt (1015)
- Focus event reporting (mode 1004) — CSI I / CSI O on window key events
- OSC 0/2 window title, OSC 7 working directory, OSC 8 hyperlinks, OSC 52 clipboard, OSC 133 semantic prompt markers
- Sixel graphics (DCS with color palette, repeat counts) and iTerm2 inline images (OSC 1337 `File=`)
- Wide character / CJK / emoji rendering (correct two-cell layout)
- Primary DA (CSI c) and secondary DA (CSI > c) device attribute responses
- DECSCUSR cursor shape control (block, bar, underline) — applications can set their preferred cursor style
- Core Text rendering with Nerd Font glyph detection
- Text selection: drag, double-click word, triple-click line; Cmd+C to copy
- Cmd+click to open URLs (OSC 8 and `NSDataDetector`-detected)
- Right-click context menu; file drag-drop onto terminal
- Cursor blink animation (configurable)
- Scrollback with configurable history size

### Shell integration

- `ZshRuntime` injects a `ZDOTDIR` shim that wraps the user's existing zsh config
- Emits OSC 7 (cwd), OSC 0 (title), and OSC 133 (prompt / command / exit markers with timing)
- Installer built into the onboarding wizard and Settings → General

### AI and input classification

- SmartInputBar routes input between shell, AI-to-shell, and query flows
- Heuristic classifier covers common shell patterns without an LLM call
- LLM fallback for ambiguous input; disambiguation bar when confidence is low
- Prefix overrides: `$` → terminal, `>` → AI-to-shell, `!` → query
- AI-to-shell card: generated command is shown, editable, and run on Enter
- Query response card: streaming answer with collapse/expand and dismiss
- Conversation history per pane (up to 20 turns)
- Per-pane independent generation model and classifier model

### AI providers

Eleven built-in provider presets:

- Anthropic (Claude) — native Anthropic streaming API
- OpenAI — OpenAI-compatible
- Google Gemini — OAuth sign-in + Gemini API
- Ollama — auto-discovered from `localhost:11434/api/tags` on launch
- Grok (xAI) — OpenAI-compatible
- Mistral — OpenAI-compatible
- DeepSeek — OpenAI-compatible
- Kimi (Moonshot) — OpenAI-compatible
- Z.AI — OpenAI-compatible
- OpenRouter — OpenAI-compatible
- Together AI — OpenAI-compatible
- llama.cpp server — OpenAI-compatible (local)

All credentials stored in macOS Keychain only.

### MCP (Model Context Protocol)

- Full JSON-RPC 2.0 MCP host over stdio
- Server lifecycle: add, start, stop, restart from Settings → MCP
- `tools/list` discovery on connect; reconnection with backoff (2s, max 5 retries)
- `tools/call` routing with parsed arguments; results returned as `RichMessage`
- Tool call loop in `answerQuery()`: up to 5 round-trips per query
- Both OpenAI `function_call` and Anthropic `tool_use` formats parsed from streaming SSE

### Agent tabs

- One-click launch for Claude Code, Kimi Code, Codex, Aider, OpenClaw, and others
- Install detection using `path_helper` + Homebrew + common tool directories (works from GUI launch context)
- Agent tab UI: direct PTY input, exit banner with restart option, agent-specific title

### Tabs and panes

- Multi-tab with per-tab title, kind (shell / agent), and unread badge
- Split panes: up to 4 per tab, horizontal and vertical
- Per-pane close button when splits are active
- Session restoration: tabs and window geometry persisted across relaunches
- `TabKind` enum distinguishes shell sessions from agent sessions

### Themes and appearance

- Built-in theme collection
- `.itermcolors` import via drag-and-drop into the sidebar
- Theme catalog: browse and download from the mbadolato community collection
- Per-pane appearance: font, size, letter spacing, line height, opacity, frost/material blend, padding, cursor style, cursor blink, scrollback size
- App-level light / dark / system preference

### macOS integration

- Multiple independent windows (⌘N)
- Command palette (⌘P) — fuzzy search over actions, themes, and agents
- Model picker overlay (⌘M) — switch provider and model without leaving the terminal
- Finder extension: "Open in aTerm" right-click context menu
- Services menu: "Open Terminal Here" for folders
- `aterm://open?path=` URL scheme
- Scrollback export (⌘⇧S) as plain text
- Customizable keybindings in Settings → Keybindings
- 5-step onboarding wizard: welcome, agent detection, provider setup, theme picker, shell integration install

### Per-project config

`.termconfig` files auto-applied on `cd` (via OSC 7 cwd change). Supports `[profile]`, `[ai]`, `[mcp]`, and `[agents]` sections.

### Build and packaging

- Universal binary (Apple Silicon + Intel) via `lipo` in CI
- Ad-hoc code-signed with hardened runtime and production entitlements
- DMG produced by CI as a build artifact
- Homebrew cask formula in `Casks/aterm.rb`
- Zero external Swift package dependencies

---

[Unreleased]: https://github.com/samvaio00/aTerm/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/samvaio00/aTerm/releases/tag/v0.1.0
