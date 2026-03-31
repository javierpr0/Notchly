import SwiftUI
import AppKit

/// A transparent view that initiates window dragging on mouseDown
/// and triggers a callback on double-click.
/// Place this behind interactive controls so it only catches clicks on empty space.
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> DragAreaView {
        let view = DragAreaView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DragAreaView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }

    class DragAreaView: NSView {
        var onDoubleClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

struct PanelContentView: View {
    @Bindable var sessionStore: SessionStore
    var onClose: () -> Void
    var onToggleExpand: (() -> Void)?
    @State private var showRestoreConfirmation = false
    @State private var showClaudeMenu = false
    @State private var claudeUseChrome = false
    @State private var claudeSkipPermissions = false

    private var foregroundOpacity: Double {
        sessionStore.isWindowFocused ? 1.0 : 0.6
    }

    /// When expanded + unfocused, make chrome backgrounds semi-transparent
    private var chromeBackgroundOpacity: Double {
        (!sessionStore.isWindowFocused && sessionStore.isTerminalExpanded) ? 0.5 : 1.0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: tabs + controls
            HStack(spacing: 8) {

                ZStack {
                    Button(action: { sessionStore.isPinned.toggle() }) {
                        Image(systemName: sessionStore.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .medium))
                            .rotationEffect(.degrees(sessionStore.isPinned ? 0 : 45))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(foregroundOpacity))
                    .help(sessionStore.isPinned ? "Unpin panel" : "Pin panel open")
                }
                .padding(.trailing, -4)
                .padding(.leading, -10)

                Rectangle()
                    .foregroundColor(.clear)
                    .frame(height: 12)
                    .overlay(
                        WindowDragArea(onDoubleClick: {
                        sessionStore.isTerminalExpanded.toggle()
                        onToggleExpand?()
                        })
                            .frame(height: 200)
                    )


                SessionTabBar(sessionStore: sessionStore)

                Rectangle()
                    .foregroundColor(.clear)
                    .frame(height: 12)
                    .overlay(
                        WindowDragArea(onDoubleClick: {
                        sessionStore.isTerminalExpanded.toggle()
                        onToggleExpand?()
                        })
                            .frame(height: 200)
                    )

                ZStack {
                    Button(action: { showClaudeMenu.toggle() }) {
                        ClaudeIconView()
                            .frame(width: 14, height: 14)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .opacity(showClaudeMenu ? 1.0 : foregroundOpacity)
                    }
                    .buttonStyle(.plain)
                    .help("Launch Claude")
                    .popover(isPresented: $showClaudeMenu, arrowEdge: .bottom) {
                        claudeMenuContent
                    }
                }
                .padding(.leading, -4)

                ZStack {
                    Button(action: { sessionStore.createQuickSession() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(foregroundOpacity))
                    .help("New terminal")
                }
                .padding(.leading, -4)
                .padding(.trailing, -10)
            }
            .padding(.horizontal, 12)
            .background(Color(nsColor: NSColor(white: 0.12, alpha: 1.0)).opacity(chromeBackgroundOpacity))

            if sessionStore.isTerminalExpanded, sessionStore.checkpointStatus != nil || sessionStore.lastCheckpoint != nil {
                HStack(spacing: 6) {
                    if let status = sessionStore.checkpointStatus {
                        Image(systemName: "progress.indicator")
                            .font(.system(size: 10, weight: .semibold))
                        Text(status)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button {
                            showRestoreConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Restore last checkpoint")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: NSColor(white: 0.18, alpha: 1.0)))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.trailing, 6)
                        .opacity(0)
                        
                    } else if let checkpoint = sessionStore.lastCheckpoint {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Checkpoint Saved")
                            .font(.system(size: 11, weight: .medium))
                        Text(checkpoint.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))

                        Spacer()

                        Button {
                            showRestoreConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Restore last checkpoint")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: NSColor(white: 0.18, alpha: 1.0)))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.trailing, 6)

                        Button(action: { sessionStore.lastCheckpoint = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: NSColor(white: 0.18, alpha: 1.0)).opacity(chromeBackgroundOpacity))
                .foregroundColor(.white.opacity(0.8))
            }

            if sessionStore.isTerminalExpanded {
                Divider()

                // Terminal area
                if let session = sessionStore.activeSession {
                    if session.hasStarted {
                        SplitPaneView(
                            node: session.splitRoot,
                            launchClaude: session.projectPath != nil,
                            generation: session.generation,
                            customCommand: session.customCommand,
                            sessionStore: sessionStore
                        )
                    } else {
                        placeholderView("Click a project tab to start a terminal session")
                            .onTapGesture {
                                sessionStore.startSessionIfNeeded(session.id)
                            }
                    }
                } else if sessionStore.sessions.isEmpty {
                    placeholderView("No sessions.\nClick + to create a new session.")
                } else {
                    placeholderView("Select a project to begin")
                }
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8.5, bottomLeadingRadius: 9.5, bottomTrailingRadius: 9.5, topTrailingRadius: 8.5))
        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1.0)).opacity(chromeBackgroundOpacity))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8.5, bottomLeadingRadius: 9.5, bottomTrailingRadius: 9.5, topTrailingRadius: 8.5))
        .onAppear {
            sessionStore.refreshLastCheckpoint()
        }
        .onChange(of: sessionStore.activeSessionId) {
            sessionStore.refreshLastCheckpoint()
        }
        .onChange(of: showRestoreConfirmation) {
            sessionStore.isShowingDialog = showRestoreConfirmation || showClaudeMenu
        }
        .onChange(of: showClaudeMenu) {
            sessionStore.isShowingDialog = showRestoreConfirmation || showClaudeMenu
        }
        .alert("Restore last checkpoint", isPresented: $showRestoreConfirmation) {
            Button("Restore last checkpoint", role: .destructive) {
                sessionStore.restoreLastCheckpoint()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite your current working directory with the checkpoint. Are you sure?")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if notification.object is TerminalPanel {
                sessionStore.isWindowFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if notification.object is TerminalPanel {
                sessionStore.isWindowFocused = false
            }
        }
    }

    private func buildClaudeCommand(mode: String) -> String {
        var parts = ["claude"]
        if mode != "new" { parts.append("--\(mode)") }
        if claudeUseChrome { parts.append("--chrome") }
        if claudeSkipPermissions { parts.append("--dangerously-skip-permissions") }
        return parts.joined(separator: " ")
    }

    private func launchClaude(mode: String) {
        let cmd = buildClaudeCommand(mode: mode)
        if let paneId = sessionStore.activeSession?.focusedPaneId {
            TerminalManager.shared.sendCommand(to: paneId, command: cmd)
        }
        showClaudeMenu = false
    }

    @ViewBuilder
    private var claudeMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            claudeMenuItem(title: "New Session", subtitle: "Start fresh", icon: "plus.circle.fill", color: .green) {
                launchClaude(mode: "new")
            }
            claudeMenuItem(title: "Continue", subtitle: "Last conversation", icon: "arrow.right.circle.fill", color: .blue) {
                launchClaude(mode: "continue")
            }
            claudeMenuItem(title: "Resume", subtitle: "Pick a conversation", icon: "clock.arrow.circlepath", color: .orange) {
                launchClaude(mode: "resume")
            }

            Divider().padding(.vertical, 4)

            Toggle(isOn: $claudeUseChrome) {
                Label("Use Chrome", systemImage: "globe")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Toggle(isOn: $claudeSkipPermissions) {
                Label("Skip Permissions", systemImage: "exclamationmark.shield.fill")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .padding(.vertical, 8)
        .frame(width: 220)
    }

    private func claudeMenuItem(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placeholderView(_ message: String) -> some View {
        Color(nsColor: NSColor(white: 0.1, alpha: 1.0))
            .overlay {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(0)
            }
    }
}
