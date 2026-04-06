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
    @State private var selectedThemeId = TerminalManager.shared.currentThemeId
    @State private var showSettings = false
    @State private var currentFontSize = TerminalManager.shared.fontSize

    private var theme: TerminalTheme { sessionStore.currentTheme }

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

                HStack(spacing: 2) {
                    Button(action: { sessionStore.isPinned.toggle() }) {
                        Image(systemName: sessionStore.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .medium))
                            .rotationEffect(.degrees(sessionStore.isPinned ? 0 : 45))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: theme.chromeForeground).opacity(foregroundOpacity))
                    .help(sessionStore.isPinned ? L10n.shared.unpinPanel : L10n.shared.pinPanelOpen)

                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .opacity(showSettings ? 1.0 : foregroundOpacity)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: theme.chromeForeground))
                    .help(L10n.shared.settings)
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        settingsMenuContent
                    }
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
                    .help(L10n.shared.launchClaude)
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
                    .foregroundColor(Color(nsColor: theme.chromeForeground).opacity(foregroundOpacity))
                    .help(L10n.shared.newTerminal)
                }
                .padding(.leading, -4)
                .padding(.trailing, -10)
            }
            .padding(.horizontal, 12)
            .background(Color(nsColor: theme.chromeBackground).opacity(chromeBackgroundOpacity))

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
                                Text(L10n.shared.restoreLastCheckpoint)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: theme.chromeBackgroundDarker))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.trailing, 6)
                        .opacity(0)
                        
                    } else if let checkpoint = sessionStore.lastCheckpoint {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.shared.checkpointSaved)
                            .font(.system(size: 11, weight: .medium))
                        Text(checkpoint.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: theme.chromeForeground).opacity(0.5))

                        Spacer()

                        Button {
                            showRestoreConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text(L10n.shared.restoreLastCheckpoint)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: theme.chromeBackgroundDarker))
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
                        .foregroundColor(Color(nsColor: theme.chromeForeground).opacity(0.4))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: theme.chromeBackgroundDarker).opacity(chromeBackgroundOpacity))
                .foregroundColor(Color(nsColor: theme.chromeForeground).opacity(0.8))
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
                        placeholderView(L10n.shared.clickTabToStart)
                            .onTapGesture {
                                sessionStore.startSessionIfNeeded(session.id)
                            }
                    }
                } else if sessionStore.sessions.isEmpty {
                    placeholderView(L10n.shared.noSessions)
                } else {
                    placeholderView(L10n.shared.selectProject)
                }
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8.5, bottomLeadingRadius: 9.5, bottomTrailingRadius: 9.5, topTrailingRadius: 8.5))
        .background(Color(nsColor: theme.background).opacity(chromeBackgroundOpacity))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8.5, bottomLeadingRadius: 9.5, bottomTrailingRadius: 9.5, topTrailingRadius: 8.5))
        .overlay {
            if sessionStore.showCommandPalette,
               let session = sessionStore.activeSession {
                let dir = session.projectPath ?? session.workingDirectory
                ZStack {
                    Color.black.opacity(0.3)
                        .onTapGesture { sessionStore.showCommandPalette = false }
                    VStack {
                        CommandPaletteView(
                            currentDirectory: dir,
                            onExecute: { command in
                                TerminalManager.shared.sendCommand(to: session.focusedPaneId, command: command)
                            },
                            onDismiss: { sessionStore.showCommandPalette = false }
                        )
                        .padding(.top, 60)
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            sessionStore.refreshLastCheckpoint()
        }
        .onChange(of: sessionStore.activeSessionId) {
            sessionStore.refreshLastCheckpoint()
        }
        .onChange(of: showRestoreConfirmation) {
            sessionStore.isShowingDialog = showRestoreConfirmation || showClaudeMenu || showSettings || sessionStore.showCommandPalette
        }
        .onChange(of: showClaudeMenu) {
            sessionStore.isShowingDialog = showRestoreConfirmation || showClaudeMenu || showSettings || sessionStore.showCommandPalette
        }
        .onChange(of: showSettings) {
            sessionStore.isShowingDialog = showRestoreConfirmation || showClaudeMenu || showSettings || sessionStore.showCommandPalette
        }
        .onChange(of: sessionStore.showCommandPalette) {
            sessionStore.isShowingDialog = showRestoreConfirmation || showClaudeMenu || showSettings || sessionStore.showCommandPalette
        }
        .alert(L10n.shared.restoreCheckpointTitle, isPresented: $showRestoreConfirmation) {
            Button(L10n.shared.restoreLastCheckpoint, role: .destructive) {
                sessionStore.restoreLastCheckpoint()
            }
            Button(L10n.shared.cancel, role: .cancel) {}
        } message: {
            Text(L10n.shared.restoreCheckpointMessage)
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
            claudeMenuItem(title: L10n.shared.newSessionTitle, subtitle: L10n.shared.startFresh, icon: "plus.circle.fill", color: .green) {
                launchClaude(mode: "new")
            }
            claudeMenuItem(title: L10n.shared.continueTitle, subtitle: L10n.shared.lastConversation, icon: "arrow.right.circle.fill", color: .blue) {
                launchClaude(mode: "continue")
            }
            claudeMenuItem(title: L10n.shared.resumeTitle, subtitle: L10n.shared.pickConversation, icon: "clock.arrow.circlepath", color: .orange) {
                launchClaude(mode: "resume")
            }

            Divider().padding(.vertical, 4)

            Toggle(isOn: $claudeUseChrome) {
                Label(L10n.shared.useChrome, systemImage: "globe")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Toggle(isOn: $claudeSkipPermissions) {
                Label(L10n.shared.skipPermissions, systemImage: "exclamationmark.shield.fill")
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

    @ViewBuilder
    private var settingsMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.shared.theme)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(TerminalTheme.allThemes) { theme in
                Button {
                    TerminalManager.shared.setTheme(theme.id)
                    selectedThemeId = theme.id
                    sessionStore.currentTheme = theme
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: theme.background))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color(nsColor: theme.foreground), lineWidth: 1)
                            )
                            .frame(width: 16, height: 16)
                        Text(theme.name)
                            .font(.system(size: 12))
                        Spacer()
                        if theme.id == selectedThemeId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }

            Divider().padding(.vertical, 6)

            Text(L10n.shared.fontSize)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            HStack(spacing: 6) {
                Button(action: {
                    TerminalManager.shared.decreaseFontSize()
                    currentFontSize = TerminalManager.shared.fontSize
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("\(Int(currentFontSize))pt")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 36)

                Button(action: {
                    TerminalManager.shared.increaseFontSize()
                    currentFontSize = TerminalManager.shared.fontSize
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    TerminalManager.shared.resetFontSize()
                    currentFontSize = TerminalManager.shared.fontSize
                } label: {
                    Text(L10n.shared.reset)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

            Divider().padding(.vertical, 6)

            Text(L10n.shared.languageLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                Button {
                    L10n.shared.language = lang
                } label: {
                    HStack(spacing: 8) {
                        Text(lang.displayName)
                            .font(.system(size: 12))
                        Spacer()
                        if lang == L10n.shared.language {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }

            Divider().padding(.vertical, 6)

            Button {
                NotificationCenter.default.post(name: .NotchyCheckForUpdates, object: nil)
                showSettings = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Text(L10n.shared.checkForUpdates)
                        .font(.system(size: 12))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        Color(nsColor: theme.background)
            .overlay {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(0)
            }
    }
}
