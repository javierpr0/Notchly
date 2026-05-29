import SwiftUI

struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct SessionTabBar: View {
    @Bindable var sessionStore: SessionStore
    @State private var draggingSessionId: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var dragAccumulatedShift: CGFloat = 0
    @State private var lastSwapDate: Date = .distantPast

    /// Tabs shown in the strip. When `hideSleepingTabs` is on we drop sleeping
    /// entries so dormant work doesn't crowd the active list. The active tab
    /// is always shown (even if sleeping, which only happens transiently while
    /// it's waking up) so the user never sees the strip "lose" their current
    /// selection.
    private var visibleSessions: [TerminalSession] {
        if sessionStore.hideSleepingTabs {
            return sessionStore.sessions.filter { !$0.isSleeping || $0.id == sessionStore.activeSessionId }
        }
        return sessionStore.sessions
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(visibleSessions) { session in
                let index = sessionStore.sessions.firstIndex(where: { $0.id == session.id })
                SessionTab(
                    session: session,
                    isActive: session.id == sessionStore.activeSessionId,
                    terminalActive: session.hasStarted,
                    terminalStatus: session.terminalStatus,
                    foregroundOpacity: sessionStore.isWindowFocused ? 1.0 : 0.6,
                    canMoveLeft: (index ?? 0) > 0,
                    canMoveRight: (index ?? 0) < sessionStore.sessions.count - 1,
                    onSelect: {
                        if draggingSessionId == nil {
                            sessionStore.selectSession(session.id)
                        }
                    },
                    onClose: { sessionStore.closeSession(session.id) },
                    onRename: { newName in
                        sessionStore.renameSession(session.id, to: newName)
                    },
                    onMoveLeft: { sessionStore.moveSessionLeft(session.id) },
                    onMoveRight: { sessionStore.moveSessionRight(session.id) }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TabFramePreferenceKey.self,
                            value: [session.id: geo.frame(in: .named("tabBar"))]
                        )
                    }
                )
                .offset(x: draggingSessionId == session.id ? dragOffset - dragAccumulatedShift : 0)
                .zIndex(draggingSessionId == session.id ? 1 : 0)
                .opacity(draggingSessionId == session.id ? 0.85 : 1.0)
                .scaleEffect(draggingSessionId == session.id ? 1.04 : 1.0)
                .animation(DS.Motion.snap, value: draggingSessionId)
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named("tabBar"))
                        .onChanged { value in
                            if draggingSessionId == nil {
                                draggingSessionId = session.id
                                dragAccumulatedShift = 0
                            }
                            dragOffset = value.translation.width

                            // Cooldown: skip if last swap was < 100ms ago.
                            // Tighter than the previous 250ms — feels much
                            // more responsive when dragging quickly.
                            guard Date().timeIntervalSince(lastSwapDate) > 0.10 else { return }
                            guard let currentIndex = sessionStore.sessions.firstIndex(where: { $0.id == session.id }) else { return }

                            let visualOffset = dragOffset - dragAccumulatedShift

                            // Only check immediate neighbors
                            if visualOffset > 0, currentIndex < sessionStore.sessions.count - 1 {
                                let rightNeighbor = sessionStore.sessions[currentIndex + 1]
                                if let neighborFrame = tabFrames[rightNeighbor.id],
                                   visualOffset > neighborFrame.width * 0.5 {
                                    withAnimation(DS.Motion.snap) {
                                        sessionStore.sessions.swapAt(currentIndex, currentIndex + 1)
                                    }
                                    dragAccumulatedShift += neighborFrame.width + DS.Spacing.xxs
                                    lastSwapDate = Date()
                                }
                            } else if visualOffset < 0, currentIndex > 0 {
                                let leftNeighbor = sessionStore.sessions[currentIndex - 1]
                                if let neighborFrame = tabFrames[leftNeighbor.id],
                                   -visualOffset > neighborFrame.width * 0.5 {
                                    withAnimation(DS.Motion.snap) {
                                        sessionStore.sessions.swapAt(currentIndex, currentIndex - 1)
                                    }
                                    dragAccumulatedShift -= neighborFrame.width + DS.Spacing.xxs
                                    lastSwapDate = Date()
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(DS.Motion.snap) {
                                dragOffset = 0
                                dragAccumulatedShift = 0
                            }
                            draggingSessionId = nil
                            sessionStore.saveSessions()
                        }
                )
            }

            // When sleeping tabs are hidden, surface their count as a small
            // pill so the user knows they exist and can click to reveal them.
            if sessionStore.hideSleepingTabs && sessionStore.sleepingTabCount > 0 {
                Button {
                    sessionStore.hideSleepingTabs = false
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 7, weight: .medium))
                        Text(L10n.shared.sleepingCount(sessionStore.sleepingTabCount))
                            .font(DS.Font.caption)
                    }
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(DS.Color.hoverTint)
                    )
                }
                .buttonStyle(.plain)
                .help(L10n.shared.showSleeping)
                .contextMenu {
                    Button(L10n.shared.wakeAll) {
                        sessionStore.wakeAllTabs()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "tabBar")
        .onPreferenceChange(TabFramePreferenceKey.self) { frames in
            tabFrames = frames
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(DS.Motion.snap, value: sessionStore.hideSleepingTabs)
        .animation(DS.Motion.snap, value: sessionStore.sleepingTabCount)
    }
}

struct SessionTab: View {
    let session: TerminalSession
    let isActive: Bool
    let terminalActive: Bool
    var terminalStatus: TerminalStatus = .idle
    var foregroundOpacity: Double = 1.0
    var canMoveLeft: Bool = false
    var canMoveRight: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    var onMoveLeft: (() -> Void)?
    var onMoveRight: (() -> Void)?

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var latestCheckpoint: Checkpoint?
    @State private var showRestoreConfirmation = false
    @FocusState private var renameFieldFocused: Bool

    private var name: String { session.projectName }

    private func startRename() {
        renameText = name
        isRenaming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            renameFieldFocused = true
        }
    }

    private func commitRename() {
        isRenaming = false
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != name {
            onRename(trimmed)
        }
    }

    private func cancelRename() {
        isRenaming = false
        renameText = name
    }

    private func showHistory() {
        // History is logged per pane (terminal.sessionId is a pane id), so read
        // every pane in this session's split tree, not the session id — that
        // file never exists and the viewer always showed "No history".
        let panel = HistoryViewerPanel(sessionName: session.projectName, paneIds: session.splitRoot.allPaneIds)
        panel.makeKeyAndOrderFront(nil)
    }

    private func refreshLatestCheckpoint() {
        guard let dir = session.projectPath else { return }
        let projectDir = (dir as NSString).deletingLastPathComponent
        latestCheckpoint = CheckpointManager.shared.checkpoints(for: session.projectName, in: projectDir).first
    }

    @ViewBuilder
    private var statusIndicator: some View {
        Group {
            switch terminalStatus {
            case .working:
                NotchyIcon(kind: .working, size: 9, tint: DS.Color.statusWorking)
            case .waitingForInput:
                NotchyIcon(kind: .waiting, size: 9, tint: DS.Color.statusWaiting)
            case .taskCompleted:
                NotchyIcon(kind: .done, size: 9, tint: DS.Color.statusDone)
            case .sleeping:
                Image(systemName: "moon.fill")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(DS.Color.statusIdle.opacity(0.7))
                    .frame(width: 9, height: 9)
            case .idle, .interrupted:
                Circle()
                    .fill(DS.Color.statusIdle.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .frame(width: 9, height: 9)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .animation(DS.Motion.snap, value: terminalStatus)
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            statusIndicator

            ZStack {
                // Stable layout: invisible bold copy reserves width so the
                // tab does not jump when the active weight changes.
                Text(name)
                    .font(DS.Font.bodyBold)
                    .lineLimit(1)
                    .opacity(0)

                if isRenaming {
                    TextField("", text: $renameText, onCommit: commitRename)
                        .font(DS.Font.bodyBold)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .focused($renameFieldFocused)
                        .onExitCommand { cancelRename() }
                        .frame(minWidth: 40)
                } else {
                    Text(name)
                        .font(isActive ? DS.Font.bodyMedium : DS.Font.body)
                        .lineLimit(1)
                        .foregroundStyle(
                            isActive
                                ? DS.Color.textPrimary.opacity(foregroundOpacity)
                                : DS.Color.textSecondary.opacity(foregroundOpacity)
                        )
                }
            }

            if isHovering {
                Button(action: onClose) {
                    NotchyIcon(kind: .close, size: 9)
                        .foregroundStyle(DS.Color.textTertiary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(
                    isActive ? DS.Color.activeTint
                    : (isHovering ? DS.Color.hoverTint : Color.clear)
                )
        )
        // Active underline (no border box) — clear hierarchy without
        // pulling the eye like a saturated color would.
        .overlay(alignment: .bottom) {
            if isActive {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .padding(.horizontal, DS.Spacing.xs)
                    .offset(y: 1)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.swift, value: isHovering)
        .animation(DS.Motion.snap, value: isActive)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.arrow.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture(count: 2) {
            startRename()
        }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if session.projectPath != nil {
                Button(L10n.shared.saveCheckpoint) {
                    SessionStore.shared.createCheckpoint(for: session.id)
                }

                if latestCheckpoint != nil {
                    Button(L10n.shared.restoreLastCheckpointMenu) {
                        showRestoreConfirmation = true
                    }
                }

                Divider()
            }

            if canMoveLeft {
                Button(L10n.shared.moveLeft) {
                    onMoveLeft?()
                }
            }
            if canMoveRight {
                Button(L10n.shared.moveRight) {
                    onMoveRight?()
                }
            }

            Divider()

            Button(L10n.shared.sessionHistory) {
                showHistory()
            }

            Button(L10n.shared.renameTab) {
                startRename()
            }

            Button(session.isSleeping ? L10n.shared.wakeTab : L10n.shared.sleepTab) {
                SessionStore.shared.toggleSleep(session.id)
            }

            if SessionStore.shared.sessions.count > 1 {
                Button(L10n.shared.sleepOthers) {
                    SessionStore.shared.sleepInactiveTabs(except: session.id)
                }
            }

            if SessionStore.shared.sleepingTabCount > 0 {
                Button(SessionStore.shared.hideSleepingTabs ? L10n.shared.showSleeping : L10n.shared.hideSleeping) {
                    SessionStore.shared.hideSleepingTabs.toggle()
                }
            }

            Button(L10n.shared.restart) {
                SessionStore.shared.restartSession(session.id)
            }

            Button(L10n.shared.close, role: .destructive) {
                onClose()
            }
        }
        .onAppear {
            refreshLatestCheckpoint()
        }
        .onChange(of: isHovering) {
            if isHovering {
                refreshLatestCheckpoint()
            }
        }
        .alert(L10n.shared.restoreLastCheckpointMenu, isPresented: $showRestoreConfirmation) {
            Button(L10n.shared.restore, role: .destructive) {
                if let checkpoint = latestCheckpoint {
                    guard let dir = session.projectPath else { return }
                    let projectDir = (dir as NSString).deletingLastPathComponent
                    do {
                        try CheckpointManager.shared.restoreCheckpoint(checkpoint, to: projectDir)
                    } catch {
                        NSLog("Notchly: checkpoint restore failed: \(error.localizedDescription)")
                    }
                }
            }
            Button(L10n.shared.cancel, role: .cancel) {}
        } message: {
            Text(L10n.shared.restoreCheckpointMessage)
        }
        .onChange(of: isRenaming) {
            SessionStore.shared.isShowingDialog = isRenaming || showRestoreConfirmation
        }
        .onChange(of: showRestoreConfirmation) {
            SessionStore.shared.isShowingDialog = isRenaming || showRestoreConfirmation
        }
        .onChange(of: renameFieldFocused) {
            if !renameFieldFocused && isRenaming {
                commitRename()
            }
        }
    }
}


