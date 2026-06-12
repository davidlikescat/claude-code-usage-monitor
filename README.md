# Claude Code Usage Monitor

A lightweight macOS menubar app that displays your Claude Code API usage as a battery indicator.

## Features

- **Battery icon** in menubar showing 5-hour session remaining percentage
- **Popover panel** with detailed 5-hour session and 7-day weekly usage bars
- **Color-coded** progress: green (<50%), yellow (50-80%), red (>80%)
- **Countdown timers** showing time until rate limit resets
- **OAuth browser login** — click "Login with Browser" to authenticate via Anthropic OAuth
- **API Key support** — manual API key entry as fallback
- **Auto-detection** of credentials from Keychain, credentials file, or shell environment
- **Configurable polling** interval (1 min / 5 min / 15 min / 1 hour)
- **Launch at login** support

## Requirements

- macOS 13.0+
- Apple Silicon (arm64)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed (for browser login)

## Build

```bash
cd ClaudeUsage
./build.sh
```

The app will be built at `build/ClaudeUsage.app`.

## Install

```bash
cp -r build/ClaudeUsage.app /Applications/
```

Or double-click `ClaudeUsage.app` to run directly.

## Authentication

The app tries to find credentials in this order:

1. **macOS Keychain** — OAuth token stored by Claude Code (no password prompt)
2. **~/.claude/.credentials.json** — older Claude Code credentials file
3. **Saved API Key** — entered manually in the app
4. **Shell environment** — `ANTHROPIC_API_KEY` from `.zshrc` / `.bash_profile`

For Pro/Team subscription users, OAuth is recommended (uses your subscription, no API credits needed).

## Tech Stack

- Swift 5 + SwiftUI
- MenuBarExtra API
- ServiceManagement (launch at login)
- No third-party dependencies
