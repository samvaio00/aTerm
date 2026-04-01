# aTerm

**A native macOS terminal emulator with built-in AI and MCP — written entirely in Swift.**

[![Build](https://github.com/samvaio00/aTerm/actions/workflows/build.yml/badge.svg)](https://github.com/samvaio00/aTerm/actions/workflows/build.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

aTerm is a macOS terminal emulator that treats AI as a first-class feature — not a bolt-on. It runs a real `zsh` PTY, speaks full VT100/xterm, and has a built-in [Model Context Protocol](https://modelcontextprotocol.io) host so any AI model can call local tools directly from your terminal. It is written in pure Swift with no external dependencies and no bundled API keys.

**Standout properties at a glance:**

| Property | Detail |
|---|---|
| Language | Swift 6.2, SwiftUI — no Electron, no embedded runtime |
| Shell | Real `forkpty` / `zsh` PTY — not a pseudo-shell |
| AI providers | 11+ built-in (Anthropic, OpenAI, Gemini, Ollama, Grok, Mistral, DeepSeek, Kimi, Z.AI, OpenRouter, Together, llama.cpp) |
| MCP | Full JSON-RPC 2.0 host — start servers, discover tools, route tool calls to the model |
| Credentials | Stored in macOS Keychain only — never in files, never in code |
| Binary | Universal (Apple Silicon + Intel) |
| Dependencies | Zero external Swift packages |

---

## Features

### Terminal emulation

aTerm runs a genuine PTY-backed shell, not a wrapped web view.

- **Full VT100 / xterm-256color** — SGR in 16, 256, and 24-bit true color; full cursor and scroll control; DEC line drawing
- **Alternate screen** — compatible with vim, less, htop, and any TUI app
- **Broad escape sequence coverage** — DECSET modes, DECSTBM scroll regions, DEC charset designation, bracketed paste, application cursor keys, focus events (mode 1004)
- **Mouse reporting** — modes 1000 / 1002 / 1003 / 1006 (SGR extended); TUI apps work correctly
- **Shell integration** — installs a `ZDOTDIR` shim that injects hooks for cwd tracking (OSC 7), window title (OSC 0), and semantic prompt/command/exit markers (OSC 133) with timing
- **Sixel graphics and iTerm2 inline images** — rendered via Core Graphics directly in the grid
- **OSC 8 hyperlinks** — Cmd+click to open; also detects plain URLs with `NSDataDetector`
- **OSC 52 clipboard** — applications can write to the system clipboard
- **Wide character / CJK / emoji** — correct two-cell rendering
- **Core Text rendering** — sharp at any DPI; Nerd Font glyph detection; cursor blink; text selection with double-click word and triple-click line

### AI and input classification

The SmartInputBar at the bottom of every pane routes what you type to the right place automatically.

```
$ ls -la            → runs as a shell command
$ show me open ports → generates the right shell command, lets you review and run it
$ what does SIGPIPE mean → streams an AI answer with conversation history
```

- **Input classifier** — heuristics cover common patterns instantly; an LLM call handles ambiguous input; a disambiguation bar appears when confidence is low
- **Prefix overrides** — `$` forces terminal, `>` forces AI-to-shell command generation, `!` forces a query
- **Streaming completions** — token-by-token output for both shell generation and query flows
- **Conversation history** — up to 20 turns of multi-turn context per pane, independent per pane
- **AI-to-shell card** — generated commands are shown, editable, and executed on Enter; dismissed with Escape
- **Per-tab model selection** — ⌘M opens a floating model picker to switch provider and model without leaving the terminal

### AI providers

All providers use streaming and store credentials in the macOS Keychain. Ollama models are auto-discovered from `localhost:11434` on launch.

| Provider | Format |
|---|---|
| Anthropic (Claude) | Native Anthropic API |
| OpenAI (GPT, o-series) | OpenAI-compatible |
| Google Gemini | OAuth + Gemini API |
| Ollama | OpenAI-compatible (local) |
| Grok (xAI) | OpenAI-compatible |
| Mistral | OpenAI-compatible |
| DeepSeek | OpenAI-compatible |
| Kimi (Moonshot) | OpenAI-compatible |
| Z.AI | OpenAI-compatible |
| OpenRouter | OpenAI-compatible |
| Together AI | OpenAI-compatible |
| llama.cpp server | OpenAI-compatible (local) |

Each pane has an independent **generation model** and **classifier model** — you can use a small local model for classification and a large cloud model for answers.

### MCP (Model Context Protocol)

aTerm is a full MCP host. Any model can call tools from any running MCP server without leaving the terminal.

- **Server management** — add, start, stop, and restart servers from Settings → MCP
- **Tool discovery** — `tools/list` on connect; tool schemas are automatically included in requests
- **Tool call loop** — streaming responses may trigger tool calls; results are fed back into the conversation; up to 5 round-trips per query
- **Both OpenAI and Anthropic formats** — `function_call` and `tool_use` blocks parsed from streaming SSE

### Agent tabs

One-click launch for common AI coding CLIs. aTerm detects whether each agent is installed and shows install instructions when it isn't.

Detected agents: **Claude Code**, **Kimi Code**, **Codex**, **Aider**, **OpenClaw**, and more.

Agent tabs get a distinct UI mode — no SmartInputBar, input goes directly to the agent process, and an exit banner offers one-click restart.

### Tabs and split panes

- Up to **4 split panes** per tab, horizontal or vertical
- Per-pane close buttons when splits are active
- **Profiles** — attach an appearance preset, working directory, and default agent to a pane
- **Session restoration** — tabs and window geometry are saved and restored on relaunch
- **Unread badge** — blue dot on tabs with background activity

### Themes and appearance

- Built-in theme collection
- **`.itermcolors` import** — drag any iTerm2 color scheme into the sidebar
- **Theme catalog** — browse and download from the mbadolato community collection directly in the app
- Per-tab appearance: font, size, letter spacing, line height, opacity, frost/material, padding, cursor style, cursor blink, scrollback size
- **Light / Dark / System** app-level theme preference

### macOS integration

- **Command palette** (⌘P) — fuzzy search over actions, themes, and agents
- **Multiple windows** — ⌘N opens a new independent window, each with its own tab state
- **Finder extension** — "Open in aTerm" in the right-click context menu
- **Services menu** — "Open Terminal Here" for folders
- **`aterm://open?path=`** URL scheme — open a tab at any path from another app or script
- **Scrollback export** — ⌘⇧S saves the full buffer as plain text
- **Customizable keybindings** — reassign any built-in shortcut in Settings → Keybindings

### Per-project config

Drop a `.termconfig` file in any directory. aTerm picks it up when `cd` triggers an OSC 7 cwd change.

```ini
[profile]
name = myproject

[ai]
provider = anthropic
model = claude-opus-4-5
classifier_model = claude-haiku-4-5-20251001

[mcp]
servers = filesystem, github
auto_start = true

[agents]
default = claude-code
auto_start = false
```

---

## Requirements

- **macOS 13 Ventura** or later
- **Xcode 26 / Swift 6.2** (for building from source)

---

## Installation

### Download DMG (recommended)

Download the latest `aTerm-x.x.x.dmg` from [Releases](https://github.com/samvaio00/aTerm/releases), open it, and drag `aTerm.app` to `/Applications`.

### Homebrew

```bash
brew install --cask aterm
```

> The cask formula is in [`Casks/aterm.rb`](Casks/aterm.rb). Point `url` at your release asset before publishing to a tap.

### Build from source

```bash
git clone https://github.com/samvaio00/aTerm
cd aTerm
swift build -c release
```

Or open the package in Xcode 26+ and run the `aTerm` scheme directly.

A helper script builds a release binary, assembles `aTerm.app`, ad-hoc signs with entitlements, and installs to `/Applications`:

```bash
bash install.sh
```

---

## Quick start

1. **Launch aTerm.** A new `zsh` session opens automatically.
2. Type any shell command in the SmartInputBar at the bottom and press **Return** — it runs normally.
3. Type a plain-language description like `list all running docker containers` and press **Return** — aTerm generates the shell command and shows it in a card for you to review and run.
4. Type a question like `what does exit code 137 mean` and press **Return** — aTerm streams an AI answer.
5. Press **⌘,** to open Settings and add an AI provider key.
6. Press **⌘M** to pick a model per tab.
7. Press **⌘P** to open the command palette.

---

## Architecture

```
AppMain (@main)
  └─ AppModel                        central @MainActor orchestrator
       ├─ TerminalTabViewModel[]      one per tab
       │    └─ TerminalPaneViewModel  one per pane (supports splits)
       │         ├─ PTYSession        forkpty + AsyncStream<PTYEvent>
       │         ├─ TerminalBuffer    grid model: cells + attributes
       │         ├─ VT100Parser       escape sequence state machine
       │         └─ ConversationHistory  multi-turn AI context
       ├─ InputClassifier             heuristic + LLM fallback
       ├─ ProviderRouter              HTTP streaming to AI providers
       └─ MCPHost                     JSON-RPC 2.0 subprocess host
```

- **No external Swift packages** — everything is implemented from scratch: PTY, VT100 parser, theme parser, HTTP streaming, JSON-RPC, Base64, and wide-character detection.
- **Swift 6 concurrency** throughout — `@MainActor`, `async`/`await`, `AsyncStream`, structured cancellation.
- Credentials are only ever written to or read from the **macOS Keychain**.

Full architecture notes are in [`CLAUDE.md`](CLAUDE.md). Remaining work is tracked in [`TODO.md`](TODO.md).

---

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup, code style, and pull request guidelines.

Bug reports and feature requests: use the [issue tracker](https://github.com/samvaio00/aTerm/issues).

---

## License

**MIT** — see [`LICENSE`](LICENSE).
