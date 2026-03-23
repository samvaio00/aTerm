# Contributing

## Setup

1. Install Xcode 26 or newer.
2. Clone the repository.
3. Open the package in Xcode or run `swift build`.

## Development Notes

- The app is built as a macOS SwiftUI executable package.
- Credentials are stored in Keychain only.
- PTY, provider, agent, and MCP features are all local-first.

## Pull Requests

- Keep changes focused.
- Build locally before opening a PR.
- Note any runtime-only behavior that could not be verified in automation.
