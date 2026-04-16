# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.19.0] - 2026-04-13

### Fixed
- Option+key combinations now produce the Latin character the keyboard layout generates (e.g. Option+2 → `@` on Spanish ISO) instead of being swallowed. SwiftTerm's `optionAsMetaKey=false` wasn't enough on all layouts, so we now forward `event.characters` directly when Option is held without Command/Control.

## [0.18.0] - 2026-04-13

### Changed
- Terminal scrollback buffer increased from 500 to 10,000 lines so full session history stays visible when scrolling up

## [0.17.0] - 2026-04-09

### Added
- Full Disk Access detection and first-run prompt with deep link to System Settings
- Full Disk Access menu entry in settings to re-open the permission panel anytime

### Fixed
- Option key now produces Latin characters (`@`, `#`, `{`, `}`, `[`, `]`) instead of sending Meta sequences
- Command palette commands now persist across sessions (SHA256 hash for per-directory storage instead of colliding short hash)
- Scroll monitor cleanup on terminal view deallocation to prevent memory leak

## [0.16.0] - 2026-04-06

### Added
- Scroll support inside TUI apps (Claude Code, vim, etc.) — scroll events are forwarded as arrow keys when mouse mode is active

### Fixed
- Links no longer auto-open on hover — only Cmd+click opens URLs, like standard terminals

## [0.14.0] - 2026-04-05

### Added
- Full app theming — changing terminal theme now applies to tabs, header, controls, and all chrome
- Theme-derived colors for backgrounds, foregrounds, dividers, and accents

## [0.13.0] - 2026-04-05

### Added
- "Check for Updates" button in settings panel
- Bilingual README (English + Spanish)
- CHANGELOG.md following Keep a Changelog format
- Release script (`scripts/release.sh`) with CHANGELOG validation
- Sparkle language syncs with app language setting

### Fixed
- "Reset" button in font size settings no longer wraps to 2 lines

## [0.12.0] - 2026-04-05

### Added
- Terminal search (Cmd+F) with match navigation using SwiftTerm's built-in search
- Command palette (Cmd+P) with per-directory command history and fuzzy search
- Settings panel (gear icon) with theme selector, font size controls, and language switch
- Smart notifications — detect success/error in task output, show summary in notification body
- Bilingual UI — English and Spanish with in-app language switch
- Localization system (`L10n`) for all user-facing strings

### Changed
- Moved theme selector from Claude menu to dedicated settings panel
- Font size buttons now have visible backgrounds for easier clicking

## [0.11.0] - 2026-04-05

### Added
- Sparkle auto-update framework with EdDSA signing
- "Check for Updates" menu item in status bar menu
- Automatic update checks every 24 hours
- GitHub Actions workflow signs DMG and updates `appcast.xml` automatically
- Setup script (`scripts/setup-sparkle.sh`) for one-command key generation

### Fixed
- Re-sign embedded frameworks to fix launch crash on ad-hoc signed builds
- Deferred Sparkle initialization to prevent crash when code signature validation fails

## [0.10.0] - 2026-04-02

### Added
- Terminal themes — 10 built-in themes (Default, Dracula, One Dark, Solarized Dark/Light, Nord, Monokai, Tokyo Night, Gruvbox Dark, Catppuccin Mocha)
- Session history manager — logs terminal output for later review
- Smart file drag-and-drop into terminal

## [0.9.1] - 2026-04-02

### Fixed
- Prevent SwiftTerm from auto-opening URLs in the browser
- Copy-on-select — selecting text automatically copies to clipboard
- Task completion checkmark persists until user selects the tab

## [0.9.0] - 2026-04-01

### Added
- Right-click "Copy Output" on command blocks (Warp-style)
- Right-click "Copy Command" to copy the command that produced the output
- Context menu with "Paste" option

### Fixed
- Task completion indicator now persists until user interacts with the tab

## [0.8.1] - 2026-03-31

### Fixed
- Task completed indicator persists until tab is selected instead of auto-clearing after 3 seconds

## [0.8.0] - 2026-03-31

### Added
- Inline ghost text autocomplete for shell commands
- Command store with per-directory history, zsh history import, and ~450 default commands
- Autocomplete engine with prefix and fuzzy matching ranked by frequency and recency
- Enhanced checkpoint menu with save/restore per session
- Checkpoint restore confirmation dialog

## [0.7.0] - 2026-03-30

### Added
- Claude launcher button with New Session, Continue, and Resume modes
- Close button on tabs
- Chrome and Skip Permissions toggles for Claude launch

## [0.6.0] - 2026-03-29

### Changed
- Renamed app from Notchy to Notchly

## [0.5.0] - 2026-03-28

### Added
- Adjustable terminal font size (Cmd+/Cmd-/Cmd+0)

## [0.4.1] - 2026-03-27

### Fixed
- MainActor isolation errors in Release build
- Strict concurrency disabled in release configuration
- CI runner updated to macos-16 for macOS 26 SDK support

## [0.4.0] - 2026-03-26

### Added
- Draggable split dividers for resizing panes
- Per-project configuration via `.notchy.json` (custom shell, env vars, launch command)

### Fixed
- Split pane resize behavior

## [0.3.0] - 2026-03-25

### Added
- Inline tab rename (double-click to edit)
- Tab reorder via context menu (Move Left/Right)
- Terminal fade-in animation on session start
- Animated BotFace with state-based expressions

## [0.2.0] - 2026-03-24

### Added
- Release automation with DMG packaging via GitHub Actions
- Tab reordering via drag gesture
- Keyboard navigation (Cmd+1-9, Cmd+Shift+Arrow)
- Git checkpoints UI (save/restore)
- Native macOS notifications when Claude finishes or needs input
- Split panes (horizontal and vertical)
- Centered panel resize (grows from both sides)
- Working directory persistence across restarts

## [0.1.0] - 2026-03-23

### Added
- Initial release
- Menu bar app with floating terminal panel anchored to MacBook notch
- Notch hover detection to reveal panel
- Multi-session tabs
- Global backtick hotkey to toggle panel
- Pin panel open option

[Unreleased]: https://github.com/javierpr0/notchly/compare/v0.19.0...HEAD
[0.19.0]: https://github.com/javierpr0/notchly/compare/v0.18.0...v0.19.0
[0.18.0]: https://github.com/javierpr0/notchly/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/javierpr0/notchly/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/javierpr0/notchly/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/javierpr0/notchly/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/javierpr0/notchly/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/javierpr0/notchly/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/javierpr0/notchly/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/javierpr0/notchly/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/javierpr0/notchly/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/javierpr0/notchly/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/javierpr0/notchly/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/javierpr0/notchly/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/javierpr0/notchly/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/javierpr0/notchly/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/javierpr0/notchly/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/javierpr0/notchly/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/javierpr0/notchly/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/javierpr0/notchly/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/javierpr0/notchly/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/javierpr0/notchly/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/javierpr0/notchly/releases/tag/v0.2.0
