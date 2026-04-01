# Security

## Reporting a vulnerability

If you find a security vulnerability in aTerm, **do not open a public GitHub issue.** Instead, report it privately via GitHub's [Security Advisories](https://github.com/samvaio00/aTerm/security/advisories/new) feature, or by emailing the maintainers directly (see the repository contact info).

Please include:
- A description of the vulnerability and its potential impact
- Steps to reproduce or a proof-of-concept
- Any relevant environment details (macOS version, aTerm version)

You will receive an acknowledgement within 48 hours. We aim to release a fix within 14 days for critical issues.

## Credential and secret handling

- aTerm stores **all** provider credentials (API keys, OAuth tokens) in the **macOS Keychain** using the `KeychainStore` module. Credentials are never written to files, environment variables, or the terminal buffer.
- The app uses **hardened runtime** with the minimum required entitlements: network client access, Keychain access, and inherited file handles for the PTY subprocess.
- OAuth tokens for providers that support it (e.g. Gemini) are handled by the app's sign-in flow and stored in the Keychain. They are never committed to the repository.

## For contributors: preventing accidental secret commits

- **Never commit** API keys, OAuth refresh tokens, passwords, private keys, `.env` files, or `.netrc` files. The [`.gitignore`](.gitignore) excludes common credential file patterns.
- If you accidentally push a secret: **revoke or rotate the credential immediately**, then remove it from git history using [`git filter-repo`](https://github.com/newren/git-filter-repo) before making the branch or repository public.
- CI runs with no credentials. Tests that require provider access must be mocked or skipped in the automated suite.

## Scope

The following are in scope for security reports:

- Credential leakage (API keys, OAuth tokens leaving the Keychain)
- Command injection through the PTY or shell integration hooks
- Sandbox escapes or entitlement abuses
- MCP server spawning or tool-call execution issues that could be exploited by a malicious `.termconfig` or MCP server definition
- XSS or script injection through OSC sequences rendered in the terminal

The following are **out of scope**:

- Issues in the user's shell, AI provider APIs, or MCP servers themselves
- Social engineering attacks that require physical access to the machine
- Issues that require the user to have already installed a malicious application
