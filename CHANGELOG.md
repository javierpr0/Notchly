# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.27.0] - 2026-06-19

### Added
- Run a tab in an isolated git worktree: right-click a project tab and pick "Open in Worktree" to spin up a separate working copy of the repo on a fresh `notchly/…` branch, opened as its own tab. Several Claude sessions can now work the same project in parallel without fighting over one working tree. The tab shows a branch badge, and closing it asks whether to discard the worktree (and its branch) or keep it on disk.

## [0.26.1] - 2026-06-19

### Fixed
- Tabs no longer paint over the side controls when they outgrow the strip: once the tabs would run wider than the available space they scroll horizontally instead of overlapping the pin/settings buttons on the left and the Claude/new-tab buttons on the right. With few tabs they stay centered as before.

## [0.26.0] - 2026-06-17

### Added
- Open a folder by dragging it onto the panel: drop a folder (or a file, which resolves to its enclosing folder) anywhere on the panel to open a new terminal tab rooted there. A highlighted drop zone appears while you drag. If the folder has a CLAUDE.md, Claude launches automatically — same as opening a project.
- Duplicate a tab with its full split layout: a new "Duplicate Tab" item in the tab context menu recreates the entire pane tree, so a tab with three terminals duplicates into another tab with three terminals at the same directories. Each pane gets a fresh terminal (live terminal state is not copied).
- Mute notifications per tab: each tab's context menu can silence its "task done" / "needs input" notifications. The setting persists across restarts.

## [0.25.0] - 2026-06-17

### Removed
- Tab groups: the grouping/filter feature from 0.24.0 is gone. Tabs are a single flat list again — create, sleep, wake and close them freely without any group bookkeeping. It added complexity without earning its keep.

### Added
- Confirmation before "Sleep Other Tabs": this closes every other tab's terminal and loses their running work, so it now asks first and shows how many tabs would be affected.
- Confirmation before closing a busy tab: a tab that is working or waiting for input asks before closing; idle tabs still close instantly so the common case stays friction-free.
- Update check on every launch: Notchly now checks for updates at startup and notifies you when one is available, letting you choose when to install. It never installs silently or closes the app out from under a running session.

### Changed
- Sleeping tabs shown in the strip are dimmed so they read as asleep at a glance.

## [0.24.0] - 2026-06-02

### Added
- Tab groups: assign tabs to named groups and filter the strip by the active group. A dropdown in the chrome switches between "All" and each group (create / rename / delete), and each tab's context menu has "Move to Group". Group membership is exclusive and persists across restarts; a new tab joins the active group so the strip never loses your focus.
- Unread-output badge: a tab that is not active shows an accent dot when new output arrives on it, so background work is visible at a glance. Cleared when you open the tab.
- Attention counter in the notch pill: when more than one session is active (working, waiting for input, or just completed) the pill shows the count next to the status icon.
- "View" action on notifications: tapping a "task done" / "needs input" notification (or its View button) brings Notchly forward and opens the session that fired it.

### Fixed
- Tab drag-to-reorder stopped working: the tab's tap gestures (select / double-click rename) outranked the reorder drag, so the drag never started. The reorder gesture is now high-priority, so dragging reorders while a plain click still selects.

## [0.23.2] - 2026-05-29

### Security
- Notification text now strips C1 control characters (U+0080–U+009F, including NEL and CSI) in addition to C0/DEL, closing a notification-spoofing vector from hostile terminal output.

### Fixed
- Session history viewer always showed "No history". History is written per pane, but the viewer read a log keyed by the session id (a file that never exists). It now reads and concatenates every pane's log in the session's split tree.
- Claimed warm-pool terminals briefly flashed the previous shell's `$HOME` prompt because the reveal counter wasn't reset. A claimed terminal now stays hidden until its own `cd && clear` completes.
- A warm terminal whose shell had already exited could be handed to a new tab. The pool now verifies the process is alive before handoff and falls back to a fresh spawn.
- A terminal whose shell exited (`exit`, crash, failing login script) left the tab/notch showing a frozen status and leaked the dead terminal. `processTerminated` now clears it and resets status (a later reselect respawns a fresh shell).
- Restoring a checkpoint no longer fails silently — the error is logged instead of being swallowed by `try?`.
- "Task completed" notifications were suppressed for many real tasks: the trivial-task filter measured wall time including the 3-second confirmation delay. It now measures actual working duration.

### Changed
- Sparkle appcast now advertises the correct minimum macOS (26.0). It previously defaulted to 14.0, offering the update to systems that cannot run the app.
- Internal cleanup: removed dead code and de-duplicated the terminal buffer-reading and launch-command paths (no behavior change).

## [0.23.1] - 2026-05-28

### Changed
- Terminal output is now buffered to session history as raw bytes and handed straight to the writer queue, dropping the per-chunk `String` decode + re-encode that ran on the main thread during heavy output.

### Fixed
- Opening the session history viewer no longer freezes the app on a large log. The flush, the up-to-5 MB file read, and the ANSI-stripping regex passes now run off the main thread and fill the window asynchronously instead of blocking the UI on `queue.sync` + a synchronous read.
- Session history no longer silently drops output whose UTF-8 split across a read boundary — chunks were decoded with `String(bytes:encoding:)`, which returns nil (and discarded the whole chunk) when a multi-byte sequence straddled two reads.
- Opening a tab no longer stalls the UI while it checks for `CLAUDE.md`. The probe ran as a synchronous `fileExists` on the main thread on every spawn; it now runs off-main, so a working directory on a slow or unresponsive volume (asleep external drive, wedged network mount) can't freeze tab open.
- Per-directory autocomplete commands are no longer lost on restart. Saved files were written with ISO-8601 dates but read back with the default `JSONDecoder`, so every cold load threw and returned an empty list — the in-memory cache masked it until the next launch.

## [0.23.0] - 2026-05-27

### Added
- Sleep tabs: dorms a tab's shell processes to free RAM/CPU while preserving the split layout and working directories. Right-click any tab → "Dormir pestaña". Selecting a sleeping tab wakes it instantly and respawns the shell in the same directory.
- "Dormir las demás" / "Despertar todas" context menu shortcuts to bulk-sleep every other tab or wake every sleeping one at once.
- "Ocultar dormidas" toggle that hides sleeping tabs from the strip and replaces them with a compact "💤 N dormidas" pill at the end of the tab bar.
- Pre-warmed terminal pool: one idle shell sits ready in `$HOME` so the next `+`-tab open skips the ~100–500 ms fork + exec + shell-startup cost. Pool re-arms after every claim. The warm path is skipped for projects with a custom `shell` or `env` in `.notchy.json` so user config is honored.
- Workspace trust prompt for `.notchy.json`: untrusted projects can no longer auto-execute a `command` or `shell` override when opened. Three-button dialog (Trust & Apply / Open Without Config / Don't Ask Again) per directory, persisted.

### Changed
- `.notchy.json` shell paths are now restricted to `/bin/`, `/usr/bin/`, `/usr/local/bin/`, `/opt/homebrew/bin/` and must point to an executable file. Anything else is silently rejected.
- `.notchy.json` env vars are filtered before merging: `PATH`, `SHELL`, `HOME`, `USER`, `LOGNAME`, `TMPDIR`, `IFS`, and any `DYLD_*` / `LD_*` keys are dropped so a malicious config cannot pivot the loader.
- Session persistence is now debounced (1.5 s) so tab reorders, working-directory updates, and status changes coalesce into one UserDefaults write instead of one per mutation.
- Terminal history writes are batched per session (250 ms debounce or 32 KB backpressure) so heavy output (compiles, `npm install`, `git log`) no longer issues a seek + write + chmod per chunk. History still flushes on quit, deletion, and read.
- Status detection scans only the last 40 rows of the terminal buffer instead of the whole screen, cutting per-tick work during bursts.
- Autocomplete keeps a per-command lowercased cache so the suggestion loop no longer re-lowercases hundreds of strings on every keystroke.
- Split-pane divider is now an AppKit-native hit zone with `NSTrackingArea`-driven cursor updates. Every divider in a nested split tree is draggable, the cursor swaps to `resizeLeftRight` / `resizeUpDown` immediately on hover, and the drag math anchors at mouse-down instead of compounding through SwiftUI re-evaluations.
- Git checkpoint binary resolution now honors `$PATH` first (so asdf / mise / brew shims work), and writes the temp index under a freshly-created `0o700` directory so a hostile symlink at the predicted path cannot redirect the write.

### Fixed
- Terminal no longer goes "deaf" after resizing the panel or a split pane. The view reclaims `firstResponder` and forces a redraw on `viewDidEndLiveResize`, on `NSWindow.didEndLiveResizeNotification`, and after the divider gesture releases, so typed characters appear immediately without an extra click.
- Session History context-menu label rendered as `Historial de sesi��n` because the source file held replacement characters; the string is now `Historial de sesión`.
- `destroyTerminal` now calls `removeFromSuperview` so the PTY actually closes when a session is restarted or put to sleep; previously the shell process kept running until the SwiftUI host released the view.
- OSC 7 directory updates from terminal output now require a valid `file://` URL, reject NUL/CR/LF, are canonicalized through `standardizedFileURL`, and must resolve to an existing directory before being applied — a hostile script can no longer pivot the working directory.
- Project name is sanitized before being embedded in a Git ref so spaces, `..`, `~`, `.lock` suffixes, and other invalid characters can't break `update-ref` or the snapshot listing glob.
- `CVDisplayLinkWrapper.stop()` now releases its retained reference even when the callback never fires (display sleep, external stop), fixing a small leak per notch expand/collapse animation.
- Status timer / autocomplete timer are invalidated in `ClickThroughTerminalView.deinit` so a torn-down pane doesn't fire callbacks against a freed view.

## [0.20.0] - 2026-04-23

### Fixed
- Commands are now scoped to the session project root, not whichever directory the shell is currently in, so the palette and autocomplete see the same entries you recorded even after `cd`-ing into subfolders.
- Command history import no longer overwrites commands recorded while zsh history was being read in the background — the merge now happens against a fresh snapshot, so recent entries survive app restarts.
- Ghost text autocomplete now aligns exactly with the terminal grid. Cell width is computed using the same glyph advancement + pixel-snap formula SwiftTerm uses internally, fixing the drift that grew as the cursor moved right.
- Keyboard focus now returns to the active terminal pane after the panel regains key status and after clicks on SwiftUI chrome (tabs, buttons), so typing no longer silently disappears until the user clicks back inside the terminal.

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

[Unreleased]: https://github.com/javierpr0/notchly/compare/v0.27.0...HEAD
[0.27.0]: https://github.com/javierpr0/notchly/compare/v0.26.1...v0.27.0
[0.26.1]: https://github.com/javierpr0/notchly/compare/v0.26.0...v0.26.1
[0.26.0]: https://github.com/javierpr0/notchly/compare/v0.25.0...v0.26.0
[0.25.0]: https://github.com/javierpr0/notchly/compare/v0.24.0...v0.25.0
[0.24.0]: https://github.com/javierpr0/notchly/compare/v0.23.2...v0.24.0
[0.23.2]: https://github.com/javierpr0/notchly/compare/v0.23.1...v0.23.2
[0.23.1]: https://github.com/javierpr0/notchly/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/javierpr0/notchly/compare/v0.22.5...v0.23.0
[0.20.0]: https://github.com/javierpr0/notchly/compare/v0.19.0...v0.20.0
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
