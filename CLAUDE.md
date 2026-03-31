# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

Open `Notchy.xcodeproj` in Xcode and build (Cmd+B). Or from the command line:

```bash
xcodebuild -project Notchy.xcodeproj -scheme Notchy -configuration Debug build
```

There are no tests or linting configured yet.

## Overview

Notchly is a macOS menu bar app that provides a floating terminal panel anchored to the MacBook notch. When the user hovers over the notch or clicks the menu bar icon, a floating panel appears with embedded terminal sessions (via SwiftTerm). Sessions persist across app restarts and can be created manually via the "+" button.

## Architecture

**App lifecycle**: `NotchyApp` (in `BotdockApp.swift`) uses `@NSApplicationDelegateAdaptor` to delegate to `AppDelegate`, which owns the `NSStatusItem` (menu bar icon), the `TerminalPanel`, and the `NotchWindow`. The SwiftUI `App` body is an empty `Settings` scene — all UI lives in the panel and notch window.

**Notch integration**: `NotchWindow` is an always-visible `NSPanel` positioned over the MacBook notch. It detects notch dimensions via `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, tracks mouse hover to trigger the main panel, and expands with a bounce animation (via `CVDisplayLinkWrapper`) when any session is working. `NotchPillContent` (SwiftUI) renders status icons (spinner, checkmark, warning) inside the pill. `NotchDisplayState` computes a priority-based aggregate status across all sessions.

**Session management**: `SessionStore` (singleton, `@Observable`) holds the list of `TerminalSession` values and the active selection. Sessions are persisted to UserDefaults and restored on launch. Sessions use lazy terminal startup — `hasStarted` is false until the user actually selects a tab. The store manages sleep prevention (`IOPMAssertion`) while Claude is working and sends native macOS notifications (`UNUserNotification`) when Claude finishes or needs input.

**Split panes**: Each session has a `SplitNode` (recursive `indirect enum` in `SplitNode.swift`) representing a binary tree of terminal panes. `SplitPaneView` renders the tree recursively. Each pane has its own UUID, working directory, and terminal status. The focused pane shows visual controls (split right, split down, close). Status is tracked per-pane via `paneStatuses` dictionary with a computed aggregate for the session.

**Terminal status detection**: `ClickThroughTerminalView` (subclass of `LocalProcessTerminalView`, defined in `TerminalManager.swift`) reads the terminal buffer on every `dataReceived` (debounced 150ms) and classifies the output into `TerminalStatus` states: `.working` (spinner chars + token counter), `.waitingForInput` ("Esc to cancel" for tool permissions), `.interrupted`, `.idle`. The `idle → taskCompleted` transition uses a 3-second delay to avoid false positives from brief working→idle flickers.

**Terminal embedding**: `TerminalManager` (singleton) owns a `[UUID: LocalProcessTerminalView]` dictionary keyed by pane ID. Terminals are created on demand, spawning the user's login shell with `TERM_PROGRAM=Apple_Terminal` (enables OSC 7 directory reporting), then sending `cd <project-dir> && clear && claude` if a CLAUDE.md exists. `TerminalSessionView` is an `NSViewRepresentable` that attaches/detaches the terminal view to a container. OSC 7 URLs are parsed to extract clean file paths for directory persistence.

**Autocomplete (ghost text)**: `ClickThroughTerminalView` provides inline autocomplete at the shell prompt. When the user types 2+ characters at a shell prompt (`$`, `%`, `>`), it queries `AutocompleteEngine` for matching commands from `CommandStore`. The best match renders as semi-transparent ghost text (via `GhostTextView`, an NSView subview) positioned at the cursor. Tab or right arrow accepts the suggestion. `CommandStore` persists commands per directory in `~/.notchly/commands/`, seeds with ~450 common defaults (git, npm, docker, claude, etc.), and imports `~/.zsh_history`. `AutocompleteEngine` supports prefix and fuzzy matching, ranked by frequency, recency, and length.

**Project config**: `ProjectConfig` loads an optional `.notchy.json` file from the working directory, allowing per-project customization of shell, environment variables, and launch command.

**Panel**: `TerminalPanel` is an `NSPanel` (borderless, floating, non-activating) that shows/hides below the notch or status item. It hides on resign-key unless pinned. Horizontal resize grows equally from both sides (centered). Panel dimensions persist across sessions. Supports Cmd+S for checkpoints, Cmd+D/Shift+D for splits, Cmd+1-9 for tab jump.

**Tab bar**: `SessionTabBar` renders tabs with status indicators. Tabs support drag reordering (via `DragGesture`, not `NSDragging`, since the panel is non-activating), context menu (rename, close, move, checkpoint save/restore, restart), and Cmd+Shift+Arrow to reorder (handled in `TerminalPanel`).

**Checkpoints**: `CheckpointManager` creates git snapshots using custom refs (`refs/Notchy-snapshots/<project>/<timestamp>`). It uses a temporary `GIT_INDEX_FILE` to avoid disturbing the user's staging area. Checkpoints can be created (Cmd+S or menu), listed, and restored.

**Hover behavior**: `AppDelegate` manages a dual interaction model — notch hover opens the panel with mouse-tracking that auto-hides when the cursor leaves, while status item click opens normally with resign-key hiding. The backtick key (keyCode 50) is a global hotkey to toggle the panel.

## Key files

| File | Purpose |
|------|---------|
| `BotdockApp.swift` | App entry point (`NotchyApp`) |
| `AppDelegate.swift` | Menu bar icon, hotkey, hover tracking, panel lifecycle |
| `TerminalManager.swift` | Terminal creation, `ClickThroughTerminalView`, status detection, autocomplete integration |
| `TerminalPanel.swift` | Floating panel window, keyboard shortcuts |
| `TerminalSessionView.swift` | NSViewRepresentable bridge to SwiftUI |
| `SessionStore.swift` | Session state, persistence, status tracking, split pane ops, notifications |
| `SessionTabBar.swift` | Tab UI, drag reordering, context menu |
| `TerminalSession.swift` | Data models for sessions and split nodes |
| `SplitNode.swift` | Binary tree structure for split panes |
| `SplitPaneView.swift` | Recursive split pane layout |
| `NotchWindow.swift` | Notch overlay, hover detection, bounce animation, `NotchPillContent`, `NotchDisplayState` |
| `PanelContentView.swift` | Main panel UI composition (tabs, buttons, terminal area) |
| `CheckpointManager.swift` | Git snapshot creation and restoration |
| `ProjectConfig.swift` | Per-project `.notchy.json` config loader |
| `CommandStore.swift` | Command storage per directory, zsh history import, default commands |
| `AutocompleteEngine.swift` | Prefix/fuzzy matching and scoring |
| `AutocompleteOverlay.swift` | `GhostTextView` — semi-transparent inline suggestion overlay |

## Dependencies

- **SwiftTerm** (`migueldeicaza/SwiftTerm`) — terminal emulator view (`LocalProcessTerminalView`)

## Entitlements

The app requires `com.apple.security.automation.apple-events` for AppleScript communication with Xcode.
