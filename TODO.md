# TODO — aTerm Remaining Work

## Must-Fix for 0.1.0 Release

- [x] **Verify Phase 5 UI cards** — Fixed AIShellCard (read-only by default, editable on Edit click, Escape to dismiss, Run ↵ shortcut), QueryResponseCard (collapse/expand toggle, dismiss button), SmartInputBar (removed conflicting keyboard shortcut)
- [x] **Full MCP tool invocation** — ProviderRouter.streamWithTools() parses function_call/tool_use from OpenAI and Anthropic streaming responses; AppModel.answerQuery() runs a tool call loop (up to 5 round-trips) routing to MCPHost.callTool() with parsed arguments and feeding results back via RichMessage conversation history
- [x] **Production entitlements** — Created aTerm.entitlements (hardened runtime, network client, Keychain access, inherited file handles for PTY, disable library validation for shell integration) and Info.plist (bundle ID com.aterm.app, macOS 13+, developer-tools category)
- [x] **DMG packaging in CI** — Updated .github/workflows/build.yml: release build, test run, app bundle creation, ad-hoc codesign with entitlements, create-dmg with app drop link, upload artifact
- [x] **Homebrew cask formula** — Created Casks/aterm.rb for `brew install --cask aterm`
- [x] **Window state restoration** — Added WindowState persistence to SessionStore (JSON file in App Support), WindowFrameRestorer (NSViewRepresentable) saves/restores window frame via setFrameAutosaveName + NSWindow notifications

## Should-Fix

- [x] **Cursor blink animation** — Added `cursorBlink` flag to TerminalAppearance; TerminalGridView runs a 0.53s repeating Timer that toggles cursor visibility and triggers redraw
- [x] **Theme catalog download** — ThemeCatalog fetches GitHub API index for mbadolato/iTerm2-Color-Schemes; ThemeCatalogSheet provides search, download, and one-click import via AppearanceSidebarView "Catalog" button
- [x] **App-level theme preference** — AppThemePreference enum (Follow System / Always Light / Always Dark) with @AppStorage; applied via .preferredColorScheme in ATermApp; picker in General settings tab
- [x] **Keybinding customization** — KeybindingStore persists to keybindings.json; KeybindingsSettingsTab shows editable list with Record button (KeyRecorderView captures NSEvent), Cancel, and Reset to Defaults
- [x] **Split pane close buttons** — Per-pane close (X) button already present in TerminalPane header when tab has >1 pane
- [x] **Collapsible query responses** — QueryResponseCard now has collapse/expand chevron toggle
- [x] **Editable generated command** — AIShellCard shows read-only command by default; Edit button toggles to inline TextField editor

## Nice-to-Have

- [x] **Finder extension** — FinderSync extension source in Sources/aTermFinderExtension with "Open in aTerm" context menu; uses `aterm://open?path=` URL scheme; CI builds and bundles into PlugIns/; URL handler in ContentView creates new tab at specified directory
- [x] **Services menu** — NSServices entry in Info.plist for "Open Terminal Here" on public.folder
- [x] **Multiple windows** — WindowModel extracted from AppModel holds per-window state (tabs, selectedTabID, overlays); AppModel remains shared singleton for providers/themes/profiles/agents/MCP; each WindowGroup window creates its own WindowModel; Cmd+N opens new window; menu commands route via NotificationCenter to focused window
- [x] **URL detection & Cmd+click** — NSDataDetector scans line text for URLs; Cmd+click opens in browser; also supports OSC 8 hyperlink URLs on cells
- [x] **Sixel / inline images** — VT100Parser decodes sixel graphics (DCS with full color palette support, repeat counts) and iTerm2 inline images (OSC 1337 File= protocol with width/height/inline params); TerminalBuffer stores TerminalInlineImage objects; TerminalGridView renders images via CGContext.draw
- [x] **Universal binary** — CI workflow builds arm64 + x86_64 separately and lipo-creates a universal binary for the DMG
- [x] **OSC 52 clipboard** — VT100Parser handles OSC 52; base64-decodes data and writes to NSPasteboard
- [x] **OSC 8 hyperlinks** — VT100Parser handles OSC 8; stores hyperlink URL in CellAttributes.hyperlinkURL; Cmd+click opens
- [x] **Focus event reporting** — DECSET mode 1004 tracked in TerminalBuffer.focusEventMode; TerminalContainerView sends CSI I/O on window key/resign notifications
- [x] **Scrollback export** — "Save Terminal Output..." menu item (Cmd+Shift+S) exports plainText via NSSavePanel
