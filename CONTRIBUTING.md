# Contributing to aTerm

Thank you for your interest in contributing. aTerm is a native macOS terminal emulator written in Swift 6.2 with no external dependencies. This document covers how to get set up, how the project is organized, and what to keep in mind when submitting a pull request.

---

## Table of contents

- [Setup](#setup)
- [Project structure](#project-structure)
- [Build and test](#build-and-test)
- [Development workflow](#development-workflow)
- [Code style](#code-style)
- [Security](#security)
- [Pull requests](#pull-requests)
- [Reporting bugs and requesting features](#reporting-bugs-and-requesting-features)

---

## Setup

1. **macOS 13+** and **Xcode 26 / Swift 6.2** or later.
2. Clone the repository:
   ```bash
   git clone https://github.com/samvaio00/aTerm
   cd aTerm
   ```
3. Build:
   ```bash
   swift build
   ```
4. Run tests:
   ```bash
   swift test
   ```
5. Open in Xcode:
   ```bash
   open Package.swift
   ```
   Select the `aTerm` scheme and run. Xcode 26 is required to run the app from the IDE.

No `npm install`, no CocoaPods, no Carthage. The project has **zero external Swift packages**.

---

## Project structure

```
Sources/aTerm/
├── AppMain.swift              @main entry point, app-level commands
├── AppModel.swift             Central @MainActor orchestrator
├── WindowModel.swift          Per-window state (tabs, overlays)
│
├── Terminal/                  Terminal emulation
│   ├── PTYSession.swift       forkpty wrapper, AsyncStream<PTYEvent>
│   ├── TerminalBuffer.swift   Grid cell model (main + alternate screen)
│   ├── VT100Parser.swift      Full escape sequence state machine
│   ├── TerminalView.swift     NSView rendering (Core Text), key/mouse handling
│   ├── TerminalTabViewModel.swift  Tab + pane view models
│   ├── TerminalAppearance.swift    Visual settings data model
│   ├── ZshRuntime.swift       Shell integration ZDOTDIR shim
│   └── ...
│
├── AI/                        AI provider system
│   ├── InputClassifier.swift  Heuristic + LLM-fallback classifier
│   ├── ProviderRouter.swift   HTTP streaming (OpenAI / Anthropic / Gemini)
│   ├── BuiltinProviders.swift Provider presets
│   ├── AgentRegistry.swift    Agent definitions + install detection
│   └── AssistantSession.swift AI conversation helpers
│
├── MCP/                       Model Context Protocol
│   ├── MCPHost.swift          Subprocess lifecycle, JSON-RPC 2.0, tool routing
│   └── MCPRegistry.swift      Persisted server configuration
│
├── Config/                    Persistence
│   ├── SessionStore.swift     Tab/window state
│   ├── ProfileStore.swift     Profiles
│   ├── ProviderStore.swift    Provider config (URLs, model lists)
│   ├── ThemeStore.swift       Themes
│   ├── KeychainStore.swift    Secrets (API keys, OAuth tokens)
│   ├── KeybindingStore.swift  Keybindings
│   └── TermConfig.swift       .termconfig parser
│
├── Themes/                    Theme system
│   ├── TerminalTheme.swift    Theme data model
│   ├── BuiltinThemes.swift    Bundled themes
│   ├── ThemeParser.swift      .itermcolors importer
│   └── ThemeCatalog.swift     Community catalog browser
│
└── UI/                        SwiftUI views
    ├── ContentView.swift       Main window layout
    ├── SettingsView.swift      Preferences window
    └── ...

Tests/
├── ClassifierTests.swift
├── ThemeParserTests.swift
├── ProviderAdapterTests.swift
└── ...
```

---

## Build and test

```bash
swift build                          # debug build
swift build -c release               # release build
swift test                           # all tests
swift test --filter ClassifierTests  # one suite
swift test --filter ClassifierTests/testShellBuiltins  # one test
```

CI runs on every push and pull request. See [`.github/workflows/build.yml`](.github/workflows/build.yml) for the full matrix (arm64, x86_64, universal binary, DMG).

---

## Development workflow

### Running the app

```bash
swift build && open "$(swift build --show-bin-path)/aTerm"
```

Or from Xcode: select the `aTerm` scheme, press ⌘R.

### Debug logging

`Log.debug("category", "message")` writes to both `os_log` (visible in Console.app) and `stderr`. When running via `swift run`, logs appear directly in the terminal.

### Adding a built-in provider

Edit `Sources/aTerm/AI/BuiltinProviders.swift`. Follow the existing pattern. If the provider uses OpenAI-compatible streaming, set `format: .openAI`. For Anthropic format, use `.anthropic`. Gemini is `.gemini`.

### Adding an agent

Edit `Sources/aTerm/AI/AgentRegistry.swift`. Provide a name, command, detection paths (Homebrew, common tool directories), and optional install URL. aTerm resolves PATH using `path_helper` so Homebrew-installed tools are found even in a GUI launch context.

### Terminal emulation changes

- `TerminalBuffer` owns grid state — all mutations must go through its methods, not by writing to `screen` directly.
- `VT100Parser` feeds characters into `TerminalBuffer`. After adding a new escape sequence, add a corresponding test in `Tests/` (see `VT100ParserTests.swift` for examples).
- `TerminalView.swift` contains `TerminalGridView` (the `NSView` renderer), `TerminalContainerView` (the scroll container), and `TerminalKeyMapper`. Rendering changes should leave the buffer model untouched.

---

## Code style

- **Swift 6 strict concurrency** — no `@preconcurrency` workarounds; no data races. New code must compile cleanly with full concurrency checking.
- **`@MainActor`** on all view models and classes that own UI state.
- **No external dependencies** — if a feature needs a library, implement the relevant parts directly. This keeps the binary lean and avoids supply-chain risk.
- Prefer small, focused functions over large ones. Keep each file to its domain.
- No docstrings or type annotations on code you didn't write. Add comments only where the logic is non-obvious.
- Do not add error handling, fallbacks, or feature flags for hypothetical scenarios.

---

## Security

- **Never commit** API keys, OAuth tokens, passwords, private keys, `.env` files, `.netrc`, or any file that might contain credentials.
- The app stores provider secrets in the **macOS Keychain** via `KeychainStore`. Do not persist credentials anywhere else.
- If you accidentally push a secret, **revoke or rotate the credential immediately**, then scrub git history with [`git filter-repo`](https://github.com/newren/git-filter-repo) before making the branch public.
- Tracked files should contain only public endpoints and non-secret configuration. See [`.gitignore`](.gitignore) for the full exclusion list.
- Be careful with PTY and shell integration changes — they have elevated access to the user's shell environment. Avoid code patterns that could lead to command injection.

---

## Pull requests

1. **Open an issue first** for significant changes so the approach can be discussed before code is written.
2. **Keep PRs focused.** One logical change per PR. Don't bundle refactors with features.
3. **Build and test locally** before opening a PR:
   ```bash
   swift build && swift test
   ```
4. **Note any runtime-only behavior** that could not be verified by automated tests — for example, changes to PTY behavior, focus handling, or OS-level integrations.
5. **Do not include** generated files, `.build/` output, `.DS_Store`, or machine-specific paths.
6. Write a clear PR description explaining what changed and why.

### PR checklist

- [ ] `swift build` passes
- [ ] `swift test` passes with no new failures
- [ ] No credentials or secrets in any committed file
- [ ] No external Swift packages added
- [ ] Changes are limited to what the PR description says

---

## Reporting bugs and requesting features

Use the [issue tracker](https://github.com/samvaio00/aTerm/issues).

- **Bugs** — use the Bug report template. Include macOS version, the steps to reproduce, what you expected, and what happened. A crash log or Console.app capture is very helpful.
- **Feature requests** — use the Feature request template. Describe the problem you are trying to solve, not just the solution you have in mind.
