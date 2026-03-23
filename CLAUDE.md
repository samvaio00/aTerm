# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build                          # Build the package
swift test                           # Run all tests
swift test --filter ClassifierTests  # Run a single test suite
swift test --filter ClassifierTests/testShellBuiltins  # Run a single test case
```

The app can also be opened as a Swift package in Xcode 26+ and run from there.

## Architecture

aTerm is a native macOS terminal emulator built as a SwiftUI executable package (Swift 6.2, macOS 13+). It has no external dependencies. See TODO.md for remaining work and prompt.txt for the original design spec.

### Core Data Flow

```
AppMain (@main)
  └─ AppModel (central orchestrator, @MainActor)
       ├─ TerminalTabViewModel[] (one per tab)
       │    └─ TerminalPaneViewModel[] (one per pane, supports splits)
       │         ├─ PTYSession (forkpty, AsyncStream<PTYEvent>)
       │         ├─ TerminalBuffer (grid model: cells with colors/attributes)
       │         ├─ VT100Parser (escape sequence state machine)
       │         └─ ConversationHistory (multi-turn AI query context)
       ├─ InputClassifier (heuristic + LLM fallback)
       ├─ ProviderRouter (HTTP streaming to AI providers)
       └─ MCPHost (JSON-RPC 2.0 subprocess lifecycle + tool invocation)
```

**AppModel** is the single source of truth. Views consume it via `@EnvironmentObject`. All view models and the classifier are `@MainActor final class` using `@Published` properties.

## Folder Structure

Source files are organized by domain following Appendix A from the design spec:

```
Sources/aTerm/
├── AppMain.swift              # @main entry point
├── AppModel.swift             # Central orchestrator
├── WindowModel.swift          # Per-window state
├── Logger.swift               # Logging utilities
│
├── Terminal/                  # Terminal emulation core
│   ├── PTYSession.swift       # forkpty wrapper
│   ├── TerminalBuffer.swift   # Grid-based cell model
│   ├── VT100Parser.swift      # Escape sequence state machine
│   ├── TerminalView.swift     # Rendering (Core Text)
│   ├── TerminalTabViewModel.swift  # Tab + pane view models
│   ├── TerminalAppearance.swift    # Visual settings
│   ├── ZshRuntime.swift       # Shell integration
│   ├── FontSupport.swift      # Nerd Font detection
│   ├── ANSIParser.swift       # ANSI color support
│   └── TerminalStreamDecoder.swift # UTF-8 decoding
│
├── AI/                        # AI provider system
│   ├── InputClassifier.swift  # Heuristic + LLM classification
│   ├── ProviderRouter.swift   # HTTP streaming to providers
│   ├── BuiltinProviders.swift # Provider presets
│   ├── AgentRegistry.swift    # Agent definitions
│   └── AssistantSession.swift # AI conversation
│
├── MCP/                       # Model Context Protocol
│   ├── MCPHost.swift          # MCP host implementation
│   └── MCPRegistry.swift      # Server registry
│
├── Config/                    # Persistence & settings
│   ├── SessionStore.swift     # Tab state persistence
│   ├── ProfileStore.swift     # Profile storage
│   ├── ProviderStore.swift    # Provider config storage
│   ├── ThemeStore.swift       # Theme storage
│   ├── KeychainStore.swift    # Secure credential storage
│   ├── KeybindingStore.swift  # Keybinding storage
│   ├── TermConfig.swift       # .termconfig parser
│   └── AppSupport.swift       # App Support utilities
│
├── Themes/                    # Theme system
│   ├── TerminalTheme.swift    # Theme data model
│   ├── BuiltinThemes.swift    # Built-in themes
│   ├── ThemeParser.swift      # .itermcolors parser
│   ├── ThemeCatalog.swift     # Theme browser/download
│   └── ThemeColor.swift       # Color utilities
│
└── UI/                        # SwiftUI views
    ├── ContentView.swift      # Main window content
    ├── SettingsView.swift     # Preferences window
    ├── TabStripView.swift     # Tab bar
    ├── AppearanceSidebarView.swift  # Theme browser
    └── OnboardingView.swift   # First-launch wizard
```

### Terminal Emulation

- **TerminalBuffer** — Grid-based model: rows x columns of `TerminalCell` (character + `CellAttributes` with fg/bg color, bold, italic, underline, dim, strikethrough, inverse, hyperlinkURL). Supports main + alternate screen buffers, scroll regions, cursor save/restore, scrollback, DEC line drawing charset, wide/CJK character detection, mouse mode tracking, focus event mode (1004), prompt marks for semantic scrollback.
- **VT100Parser** — Full state machine: SGR colors (16, 256, 24-bit RGB), cursor movement, screen clearing, scroll regions (DECSTBM), alternate screen (DECSET 1049/47), insert/delete, OSC for title/cwd/OSC 133 prompt markers/OSC 52 clipboard/OSC 8 hyperlinks, bracketed paste, application cursor keys, mouse modes (1000/1002/1003/1006), focus events (1004), DEC charset designation (G0/G1).
- **TerminalGridView** — Custom `NSView` using Core Text. Draws cells with proper colors and font attributes. Supports text selection (drag, double-click word, triple-click line), Cmd+C/V clipboard, Cmd+click URL opening (OSC 8 hyperlinks + NSDataDetector URL detection), right-click context menu, mouse reporting for TUI apps, file drag-drop, cursor blink animation. Theme ANSI palette colors mapped for indices 0-15.
- **TerminalKeyMapper** — Full keyboard: Ctrl+A-Z (0x01-0x1a), F1-F12, Home/End/PgUp/PgDn/Insert/Delete, arrow keys with Ctrl/Alt/Shift, application cursor mode, Alt+key meta encoding.

PTY output flows: `PTYSession` → `VT100Parser.feed(data)` → `TerminalBuffer` state updates → `TerminalGridView.needsDisplay`. The `displayText` string for search is only regenerated when search is active (200ms debounce).

### Input Submission Flow

User input goes through `AppModel.submitInput(for: pane)`:
1. Prefix overrides: `$` forces terminal, `>` forces AI-to-shell, `!` forces query
2. `InputClassifier.classify()` runs heuristics first, falls back to LLM if ambiguous
3. Three modes: `.terminal` (send to PTY), `.aiToShell` (generate shell command via completion), `.query` (stream AI response with conversation history)
4. If classification returns `nil`, a disambiguation bar appears for the user to pick

### PTY & Shell Integration

- `PTYSession` wraps Darwin `forkpty()`, emits output via `AsyncStream<PTYEvent>`. Thread-safe via `NSLock`. Graceful terminate: SIGTERM then SIGKILL after 3s.
- `ZshRuntime` creates a runtime `ZDOTDIR` in App Support that wraps user's zsh config and injects shell hooks
- `shell-integration.zsh` emits OSC 7 (cwd), OSC 0 (title), OSC 133 (prompt/command/exit markers with timing)

### AI Provider System

- `ProviderRouter` handles three API formats: OpenAI-compatible, Anthropic, and Gemini
- Supports tool schemas in request bodies (`ToolSchema` with `toOpenAIFormat()`/`toAnthropicFormat()`)
- `streamResponse()` (AsyncThrowingStream with cancellation via `onTermination`) for queries
- `complete()` (single request) for AI-to-shell command generation
- Credentials stored in Keychain via `KeychainStore`
- Each pane can have separate `aiModel` (generation) and `classifierModel` (classification) settings
- Built-in presets for 11 providers; Ollama models auto-detected from localhost:11434/api/tags on launch
- `ConversationHistory` per pane maintains multi-turn context (max 20 messages)

### MCP Host

- `MCPHost` manages server subprocesses with JSON-RPC 2.0 protocol over stdio
- Initialize handshake → tools/list discovery → tools/call routing
- Reconnection with 2s backoff, max 5 retries on crash
- `callTool(name:arguments:)` routes to correct server and returns text result
- `toolSchemas()` converts `MCPToolDescriptor` (with description + inputSchema) to `ToolSchema` for API requests
- `ProviderRouter.streamWithTools()` parses `function_call`/`tool_use` from OpenAI and Anthropic streaming SSE responses, accumulating arguments across chunks
- `AppModel.answerQuery()` runs a tool call loop (up to 5 round-trips): stream → detect tool calls → execute via MCPHost → feed `RichMessage` results back → continue generation

### Tabs & Panes

- `TabKind` enum: `.shell` or `.agent(AgentDefinition)` — affects launch config, title behavior, and exit handling
- Tabs support up to 4 split panes (horizontal/vertical) via `splitActivePane()`
- `hasUnreadOutput` badge on tabs with background activity (blue dot in tab strip)
- Profiles attach appearance + working directory + agent config to panes

### Per-Project Config

`.termconfig` files are auto-detected when the terminal's working directory changes. Supports:
- `[profile]` name
- `[ai]` provider, model, classifier_model
- `[mcp]` servers list with auto_start
- `[agents]` default agent with auto_start

### Persistence

All stores (SessionStore, ThemeStore, ProfileStore, ProviderStore, AgentStore, MCPStore) use JSON encoding to `~/Library/Application Support/aTerm/`.

### Key UI Components

- **Command Palette** (Cmd+P) — fuzzy search over actions, themes, and agents
- **Model Picker** (Cmd+M) — floating overlay to switch provider/model per tab
- **Settings Window** — tabbed: General, Providers (full CRUD), Profiles, Agents, MCP (start/stop/restart), Keybindings
- **Onboarding Wizard** — 5-step: welcome, agent detection, provider setup with API key, theme picker, shell integration install

## Test Structure

Tests are in `Tests/` (flat directory, no subdirectory):
- `ClassifierTests` — input classification heuristics
- `ThemeParserTests` — theme file parsing
- `ProviderAdapterTests` — provider API format handling
