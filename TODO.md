# TODO — aTerm Remaining Work

## Must-Fix for 0.1.0 Release

- [ ] **Verify Phase 5 UI cards** — Confirm QueryResponseCard, AIShellCard, DisambiguationBar, and SmartInputBar render correctly with streaming, edit/run buttons, and disambiguation choices
- [ ] **Full MCP tool invocation** — Parse function_call/tool_use from Anthropic and OpenAI API responses instead of string-matching heuristic; route to MCPHost.callTool(); feed result back into conversation and continue generation
- [ ] **Production entitlements** — Create proper .entitlements file with hardened runtime, PTY access, Keychain access, and network client for app signing and notarization
- [ ] **DMG packaging in CI** — Add create-dmg step to .github/workflows/build.yml to produce a signed/notarized DMG installer
- [ ] **Homebrew cask formula** — Write .rb formula for `brew install --cask aterm` (personal tap or homebrew-cask PR)
- [ ] **Window state restoration** — Implement NSUserActivity for macOS system restore (window size, position, scroll offset per tab)

## Should-Fix

- [ ] **Cursor blink animation** — Add a timer-based blink to TerminalGridView when cursorStyle has blink enabled
- [ ] **Theme catalog download** — Fetch theme index from iterm2colorschemes.com GitHub repo, display in-app catalog, download on demand
- [ ] **App-level theme preference** — Add "follow system / always light / always dark" setting in General preferences
- [ ] **Keybinding customization** — Make KeybindingsSettingsTab editable with rebindable shortcuts and reset-to-defaults
- [ ] **Split pane close buttons** — Add visible per-pane close (X) button in the pane header area
- [ ] **Collapsible query responses** — Add expand/collapse toggle on AI query answer cards
- [ ] **Editable generated command** — Wire the isEditing state in AIShellCard to show an inline text editor before execution

## Nice-to-Have

- [ ] **Finder extension** — Right-click folder → "Open in aTerm" via FinderSync extension
- [ ] **Services menu** — Register NSServices for "Open Terminal Here"
- [ ] **Multiple windows** — Support Cmd+N for new window (currently single-window with tabs)
- [ ] **URL detection & Cmd+click** — Scan terminal output for URLs, render underlined, open in browser on Cmd+click
- [ ] **Sixel / inline images** — Decode sixel graphics and iTerm2 inline image protocol (OSC 1337)
- [ ] **Universal binary** — Add explicit x86_64+arm64 target to Package.swift for Intel Mac support
- [ ] **OSC 52 clipboard** — Allow programs to read/write system clipboard via escape sequences
- [ ] **OSC 8 hyperlinks** — Render clickable hyperlinks from terminal escape sequences
- [ ] **Focus event reporting** — Send focus in/out sequences to PTY when window gains/loses focus
- [ ] **Scrollback export** — "Save Terminal Output As..." to file
- [ ] **Session recording/playback** — Record terminal sessions for replay
