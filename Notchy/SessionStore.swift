import AppKit
import AVFoundation
import SwiftUI
import UserNotifications
import os

private let logger = Logger(subsystem: "com.notchly", category: "SessionStore")

/// Shared identifiers for the macOS notifications that carry a "View" action
/// back to a specific session (registered in AppDelegate, set in SessionStore).
enum AppNotification {
    static let sessionCategory = "NOTCHY_SESSION"
    /// Category for "needs input" notifications — carries a Continue action that
    /// sends Enter to the waiting pane without bringing the app forward.
    static let sessionWaitingCategory = "NOTCHY_SESSION_WAITING"
    static let sessionIdKey = "sessionId"
}

extension Notification.Name {
    static let NotchyHidePanel = Notification.Name("NotchyHidePanel")
    static let NotchyExpandPanel = Notification.Name("NotchyExpandPanel")
    static let NotchyNotchStatusChanged = Notification.Name("NotchyNotchStatusChanged")
    static let NotchyCheckForUpdates = Notification.Name("NotchyCheckForUpdates")
}

@Observable
@MainActor
class SessionStore {
    static let shared = SessionStore()

    var sessions: [TerminalSession] = []
    var activeSessionId: UUID?
    /// Sessions with output that arrived while they were not the active tab.
    /// Ephemeral (not persisted); cleared when the user opens the tab.
    var unreadSessionIds: Set<UUID> = []
    var isPinned: Bool = {
        if UserDefaults.standard.object(forKey: "isPinned") == nil { return true }
        return UserDefaults.standard.bool(forKey: "isPinned")
    }() {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: "isPinned")
        }
    }
    /// When true, sleeping tabs are hidden from the tab strip (still in the
    /// sessions list, accessible via the "💤 N" pill or the menu bar item).
    var hideSleepingTabs: Bool = UserDefaults.standard.bool(forKey: "hideSleepingTabs") {
        didSet {
            UserDefaults.standard.set(hideSleepingTabs, forKey: "hideSleepingTabs")
        }
    }
    /// User-adjustable background opacity for the whole panel (chrome,
    /// terminal area, file preview) — the desktop shows through below 1.0.
    /// Floor of 0.5 keeps text readable. Surfaced in settings as
    /// "Transparency" (1 − opacity).
    var panelOpacity: Double = {
        let stored = UserDefaults.standard.object(forKey: "panelOpacity") as? Double
        return min(max(stored ?? 1.0, 0.5), 1.0)
    }() {
        didSet {
            UserDefaults.standard.set(panelOpacity, forKey: "panelOpacity")
            TerminalManager.shared.refreshPanelOpacity()
        }
    }
    /// Blur intensity (0–1) applied behind the panel while transparency is
    /// active. Implemented as the NSVisualEffectView's alpha: 0 = sharp
    /// see-through, 1 = full frosted glass.
    var panelBlur: Double = {
        let stored = UserDefaults.standard.object(forKey: "panelBlur") as? Double
        return min(max(stored ?? 1.0, 0.0), 1.0)
    }() {
        didSet {
            UserDefaults.standard.set(panelBlur, forKey: "panelBlur")
        }
    }
    var isTerminalExpanded = true
    var isWindowFocused = true
    var isShowingDialog = false
    var showCommandPalette = false
    /// Non-nil while the inline file preview overlay is open (⌘-click on a path).
    var filePreview: FilePreviewRequest?
    var currentTheme: TerminalTheme = TerminalTheme.theme(forId: TerminalManager.shared.currentThemeId)

    /// The most recent checkpoint for the active session, used to show the undo button
    var lastCheckpoint: Checkpoint?
    /// Project name associated with lastCheckpoint
    var lastCheckpointProjectName: String?
    /// Project directory associated with lastCheckpoint
    var lastCheckpointProjectDir: String?

    /// Non-nil while a checkpoint operation is in progress (e.g. "Taking checkpoint…", "Restoring checkpoint…")
    var checkpointStatus: String?

    /// Activity token to prevent macOS idle sleep while Claude is working
    private var sleepActivity: NSObjectProtocol?

    /// Completion info from terminal status detection (populated by TerminalManager)
    var paneCompletionInfo: [UUID: PaneCompletionInfo] = [:]

    /// Sound playback
    private var activePlayers: [AVAudioPlayer] = []
    private var lastSoundPlayedAt: Date = .distantPast

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionId }
    }

    /// The status color for the notch (matches tab bar colors)
    var notchStatusColor: NSColor {
        guard let session = activeSession else { return .systemGreen }
        switch session.terminalStatus {
        case .waitingForInput: return .systemRed
        case .working: return .systemYellow
        case .sleeping: return .systemGray
        case .idle, .interrupted, .taskCompleted: return .systemGreen
        }
    }

    /// Tasks whose working phase was shorter than this don't emit a
    /// "task completed" pill/notification — avoids noise from trivial commands.
    private static let minTaskWorkDuration: TimeInterval = 7
    /// Window a pane must stay idle after working before it is promoted to
    /// taskCompleted — avoids false positives from brief idle flickers.
    private static let confirmationDelay: Duration = .seconds(3)
    private static let persistDebounceInterval: TimeInterval = 1.5

    private var persistDebounceTask: DispatchWorkItem?
    /// Set once the first successful file write has retired the legacy
    /// UserDefaults blob.
    private var hasMigratedLegacyStore = false
    /// Pending working→idle confirmation tasks keyed by pane. One per pane,
    /// cancelled before rescheduling and on pane teardown — rapid status
    /// flicker must not accumulate detached sleepers.
    private var completionTransitionTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        restoreSessions()
        requestNotificationPermission()
        if sessions.isEmpty {
            createQuickSession()
        }
    }

    // MARK: - Native Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendNotification(title: String, body: String, sessionId: UUID?, canContinue: Bool = false) {
        guard !isWindowFocused else { return }
        if let sessionId, sessions.first(where: { $0.id == sessionId })?.notificationsMuted == true { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let sessionId {
            content.categoryIdentifier = canContinue ? AppNotification.sessionWaitingCategory : AppNotification.sessionCategory
            content.userInfo = [AppNotification.sessionIdKey: sessionId.uuidString]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Sends Enter to the pane currently waiting for input — accepts the
    /// highlighted choice in Claude's permission prompt. Invoked from the
    /// notification's Continue action.
    func approveWaitingPane(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }),
              let paneId = session.paneStatuses.first(where: { $0.value == .waitingForInput })?.key
        else { return }
        TerminalManager.shared.sendCommand(to: paneId, command: "")
    }

    // MARK: - Session Persistence

    private func restoreSessions() {
        // File store first; fall back to the pre-file UserDefaults blob so
        // existing installs migrate transparently on this launch.
        guard let loaded = SessionPersistence.load() ?? SessionPersistence.legacyStore(in: .standard),
              !loaded.sessions.isEmpty else { return }
        sessions = loaded.sessions.map { TerminalSession(persisted: $0) }
        activeSessionId = loaded.activeSessionId ?? sessions.first?.id
        // Mark all restored sessions as started so terminals launch immediately
        for i in sessions.indices {
            sessions[i].hasStarted = true
            sessions[i].hasBeenSelected = true
        }
    }

    func saveSessions() {
        // Immediate flush — used at app termination, where debounce is unsafe.
        persistDebounceTask?.cancel()
        persistDebounceTask = nil
        persistNow()
    }

    /// Schedules a debounced persistence write. Multiple rapid mutations (drag
    /// reorder, working-directory updates, status churn) coalesce into one write.
    private func persistSessions() {
        persistDebounceTask?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.persistNow()
            }
        }
        persistDebounceTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.persistDebounceInterval, execute: work)
    }

    private func persistNow() {
        do {
            try SessionPersistence.save(sessions.map(PersistedSession.init(from:)),
                                        activeSessionId: activeSessionId)
        } catch {
            logger.error("Failed to persist sessions: \(error.localizedDescription, privacy: .public)")
            return
        }
        // First successful file write retires the legacy UserDefaults blob so
        // there is exactly one source of truth from here on.
        if !hasMigratedLegacyStore {
            hasMigratedLegacyStore = true
            UserDefaults.standard.removeObject(forKey: "persistedSessions")
            UserDefaults.standard.removeObject(forKey: "activeSessionId")
        }
    }

    func updateWorkingDirectory(_ paneId: UUID, directory: String) {
        guard let index = sessionIndex(forPane: paneId) else { return }
        let oldDir = sessions[index].splitRoot.workingDirectory(for: paneId)
        guard oldDir != directory else { return }
        sessions[index].splitRoot = sessions[index].splitRoot.updatingWorkingDirectory(paneId, to: directory)
        if sessions[index].focusedPaneId == paneId {
            sessions[index].workingDirectory = directory
        }
        persistSessions()
    }

    /// Select a tab — auto-starts the terminal and clears taskCompleted indicators.
    /// If the tab is sleeping, selecting it wakes it (terminal will respawn).
    func selectSession(_ id: UUID) {
        activeSessionId = id
        unreadSessionIds.remove(id)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            if sessions[index].isSleeping {
                sessions[index].isSleeping = false
            }
            sessions[index].hasBeenSelected = true
            startSessionIfNeeded(id)

            // Clear taskCompleted status on all panes when user opens the tab
            for paneId in sessions[index].paneStatuses.keys {
                if sessions[index].paneStatuses[paneId] == .taskCompleted {
                    sessions[index].paneStatuses[paneId] = .idle
                }
            }
            NotificationCenter.default.post(name: .NotchyNotchStatusChanged, object: nil)

            // Expand terminal if collapsed when user taps a tab
            if !isTerminalExpanded {
                isTerminalExpanded = true
                NotificationCenter.default.post(name: .NotchyExpandPanel, object: nil)
            }
        }
        persistSessions()
    }

    /// Mark session as started (terminal will be created when view renders).
    /// If the session is sleeping, wake it on the same tick so a single user
    /// action (clicking the tab or the placeholder) is enough to respawn.
    func startSessionIfNeeded(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[index].isSleeping {
            sessions[index].isSleeping = false
        }
        if !sessions[index].hasStarted {
            sessions[index].hasStarted = true
        }
    }

    func moveSessionLeft(_ sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }), index > 0 else { return }
        sessions.swapAt(index, index - 1)
        persistSessions()
    }

    func moveSessionRight(_ sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }), index < sessions.count - 1 else { return }
        sessions.swapAt(index, index + 1)
        persistSessions()
    }

    /// "+" button: creates a plain terminal session with no project association
    func createQuickSession() {
        let session = TerminalSession(
            projectName: "Terminal",
            started: true
        )
        sessions.append(session)
        activeSessionId = session.id
        persistSessions()
    }

    func createClaudeSession(command: String) {
        let dir = activeSession?.workingDirectory ?? NSHomeDirectory()
        let session = TerminalSession(
            projectName: "Claude",
            workingDirectory: dir,
            started: true,
            customCommand: command
        )
        sessions.append(session)
        activeSessionId = session.id
        persistSessions()
    }

    /// Opens a new tab rooted at a directory (e.g. a folder dropped onto the
    /// panel). Treated as a project so the terminal auto-launches Claude when a
    /// CLAUDE.md is present, matching the normal project-open behavior.
    func createSession(forDirectory dir: String) {
        // A folder name is attacker-controllable (cloned repo, unzipped
        // archive) and flows into notifications, the tab strip and menus.
        // Strip bidi-override / zero-width / control codepoints so it can't
        // spoof that UI (Trojan-Source style).
        let name = ShellSafety.sanitizeForDisplay((dir as NSString).lastPathComponent)
        let session = TerminalSession(
            projectName: name.isEmpty ? "Terminal" : name,
            projectPath: dir,
            workingDirectory: dir,
            started: true
        )
        sessions.append(session)
        activeSessionId = session.id
        persistSessions()
    }

    /// Duplicates a tab including its full split layout: the pane tree is cloned
    /// with fresh pane ids (so each new pane spawns its own terminal) at the same
    /// working directories. Live terminal state is not copied. The copy is
    /// inserted right after the original and becomes active.
    func duplicateSession(_ id: UUID) {
        guard let src = sessions.first(where: { $0.id == id }) else { return }
        let clonedRoot = src.splitRoot.clonedWithFreshIds()
        var dup = TerminalSession(
            projectName: src.projectName,
            projectPath: src.projectPath,
            workingDirectory: src.workingDirectory,
            started: true,
            customCommand: src.customCommand
        )
        dup.splitRoot = clonedRoot
        dup.focusedPaneId = clonedRoot.allPaneIds.first ?? dup.focusedPaneId
        let insertAt = (sessions.firstIndex(where: { $0.id == id }) ?? sessions.count - 1) + 1
        sessions.insert(dup, at: insertAt)
        activeSessionId = dup.id
        persistSessions()
    }

    /// Opens a sibling tab running in a fresh git worktree of the given tab's
    /// repo, so another Claude can work the same project in parallel without
    /// touching the original working tree. No-op (logged) if it isn't a git repo.
    @discardableResult
    func createWorktreeSession(from id: UUID) -> Bool {
        guard let src = sessions.first(where: { $0.id == id }) else { return false }
        let dir = src.projectPath ?? src.workingDirectory
        let handle: WorktreeHandle
        do {
            handle = try WorktreeManager.shared.createWorktree(forRepoAt: dir, name: src.projectName)
        } catch {
            logger.error("Worktree creation failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let session = TerminalSession(
            projectName: src.projectName,
            projectPath: handle.path,
            workingDirectory: handle.path,
            started: true,
            worktreeBranch: handle.branch,
            worktreeRepoRoot: handle.repoRoot
        )
        let insertAt = (sessions.firstIndex(where: { $0.id == id }) ?? sessions.count - 1) + 1
        sessions.insert(session, at: insertAt)
        activeSessionId = session.id
        persistSessions()
        return true
    }

    func toggleNotifications(_ id: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].notificationsMuted.toggle()
        persistSessions()
    }

    func renameSession(_ id: UUID, to newName: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].projectName = ShellSafety.sanitizeForDisplay(newName)
        persistSessions()
    }

    /// Cache mapping pane id → owning session id. Self-healing: every hit is
    /// verified against the current split tree and any miss triggers a full
    /// rebuild, so split/close/restore mutations never need to invalidate it.
    /// Avoids a DFS over every session's split tree on each output event.
    @ObservationIgnored private var paneToSessionCache: [UUID: UUID] = [:]

    private func sessionIndex(forPane paneId: UUID) -> Int? {
        if let sid = paneToSessionCache[paneId],
           let index = sessions.firstIndex(where: { $0.id == sid }),
           sessions[index].splitRoot.containsPane(paneId) {
            return index
        }
        paneToSessionCache.removeAll(keepingCapacity: true)
        for session in sessions {
            for pane in session.splitRoot.allPaneIds {
                paneToSessionCache[pane] = session.id
            }
        }
        guard let sid = paneToSessionCache[paneId],
              let index = sessions.firstIndex(where: { $0.id == sid }) else { return nil }
        return index
    }

    /// Flag a session as having unread output when a chunk arrives on a pane
    /// whose tab is not active. Idempotent: only mutates on the first chunk
    /// after the flag was cleared, so a busy background tab won't churn.
    func noteOutput(forPane paneId: UUID) {
        guard let index = sessionIndex(forPane: paneId) else { return }
        let sessionId = sessions[index].id
        guard sessionId != activeSessionId, !sessions[index].isSleeping else { return }
        guard !unreadSessionIds.contains(sessionId) else { return }
        unreadSessionIds.insert(sessionId)
    }

    func updateTerminalStatus(_ paneId: UUID, status: TerminalStatus) {
        guard let index = sessionIndex(forPane: paneId) else { return }
        // A sleeping session has no live terminals; any in-flight status callback
        // from a torn-down terminal must not resurrect paneStatuses.
        guard !sessions[index].isSleeping else { return }

        let oldPaneStatus = sessions[index].paneStatuses[paneId] ?? .idle
        guard oldPaneStatus != status else { return }

        // Once taskCompleted is set, only .working (new task) can overwrite it.
        // Cleared manually when the user selects the tab (selectSession).
        if oldPaneStatus == .taskCompleted && status != .working { return }

        let previousAggregate = sessions[index].terminalStatus
        sessions[index].paneStatuses[paneId] = status
        let newAggregate = sessions[index].terminalStatus
        let sessionId = sessions[index].id

        updateSleepPrevention()

        if status == .working && oldPaneStatus != .working {
            sessions[index].paneWorkingStartedAt[paneId] = Date()
        }

        // Aggregate status change triggers sounds/UI/notifications
        if newAggregate != previousAggregate {
            let sessionName = sessions[index].projectName
            if newAggregate == .waitingForInput && previousAggregate != .waitingForInput {
                playSound(named: "waitingForInput")
                sendNotification(title: L10n.shared.actionRequired, body: L10n.shared.needsInput(sessionName), sessionId: sessionId, canContinue: true)
                if isPinned && !isTerminalExpanded && sessionId == activeSessionId {
                    isTerminalExpanded = true
                    NotificationCenter.default.post(name: .NotchyExpandPanel, object: nil)
                }
            }
            else if newAggregate == .taskCompleted && previousAggregate != .taskCompleted {
                let info = paneCompletionInfo[paneId]
                let hadError = info?.hadError ?? false
                let title = hadError ? L10n.shared.taskFailed : L10n.shared.taskCompleted
                let body: String
                if let summary = info?.summary {
                    body = "\(sessionName): \(summary)"
                } else {
                    body = L10n.shared.sessionFinished(sessionName)
                }
                playSound(named: "taskCompleted")
                sendNotification(title: title, body: body, sessionId: sessionId)
                paneCompletionInfo.removeValue(forKey: paneId)
            }
            NotificationCenter.default.post(name: .NotchyNotchStatusChanged, object: nil)
        }

        // Per-pane working→idle delay for taskCompleted. Skip trivial tasks,
        // but measure the ACTUAL working duration (idle moment − start) now —
        // the old check read `now − start` inside the delayed task, so the 3 s
        // confirmation sleep inflated it and suppressed real short tasks.
        if status == .idle && oldPaneStatus == .working {
            let sessionId = sessions[index].id
            let workDuration = sessions[index].paneWorkingStartedAt[paneId].map { Date().timeIntervalSince($0) }
            scheduleTaskCompletionConfirmation(paneId: paneId, sessionId: sessionId, workDuration: workDuration)
        }
    }

    /// Pure gate for firing a "task completed" after the confirmation window:
    /// the pane must still be idle and the work must not have been trivial.
    private func scheduleTaskCompletionConfirmation(paneId: UUID, sessionId: UUID, workDuration: TimeInterval?) {
        completionTransitionTasks[paneId]?.cancel()
        completionTransitionTasks[paneId] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.confirmationDelay)
            guard !Task.isCancelled else { return }
            guard let self,
                  let index = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
            let paneStatus = self.sessions[index].paneStatuses[paneId]
            guard TaskCompletionGate.shouldConfirm(
                currentPaneStatus: paneStatus,
                workDuration: workDuration,
                minimumWorkDuration: Self.minTaskWorkDuration
            ) else { return }
            self.completionTransitionTasks[paneId] = nil
            self.updateTerminalStatus(paneId, status: .taskCompleted)
        }
    }

    /// Cancels any pending completion confirmation for every pane of a
    /// session that is being closed, slept or restarted.
    private func cancelCompletionTransitions(forSession id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        for paneId in sessions[index].splitRoot.allPaneIds {
            completionTransitionTasks[paneId]?.cancel()
            completionTransitionTasks.removeValue(forKey: paneId)
        }
    }

    private func playSound(named name: String) {
        let now = Date()
        guard now.timeIntervalSince(lastSoundPlayedAt) >= 1.0 else { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            activePlayers.removeAll { !$0.isPlaying }
            activePlayers.append(player)
            player.play()
            lastSoundPlayedAt = now
        } catch {
            logger.error("Failed to play sound '\(name)': \(error.localizedDescription)")
        }
    }

    private func updateSleepPrevention() {
        let anyWorking = sessions.contains { $0.terminalStatus == .working }
        if anyWorking && sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                reason: "Claude is working"
            )
        } else if !anyWorking, let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

    /// Close tab: removes the session entirely
    /// Refresh the lastCheckpoint for the active session
    func refreshLastCheckpoint() {
        guard let session = activeSession,
              let dir = session.projectPath else {
            lastCheckpoint = nil
            lastCheckpointProjectName = nil
            lastCheckpointProjectDir = nil
            return
        }
        let projectDir = (dir as NSString).deletingLastPathComponent
        let projectName = session.projectName
        let sessionId = session.id
        // `checkpoints` shells out to `git for-each-ref` and blocks on
        // waitUntilExit. This runs on every tab switch and every panel open, so
        // on main it stalls the UI for as long as git takes on that repo.
        Task.detached(priority: .userInitiated) {
            let latest = CheckpointManager.shared.checkpoints(for: projectName, in: projectDir).first
            await MainActor.run {
                let store = SessionStore.shared
                // The user may have switched tabs while git ran — a late result
                // for the previous tab must not overwrite the current one.
                guard store.activeSessionId == sessionId else { return }
                store.lastCheckpoint = latest
                store.lastCheckpointProjectName = projectName
                store.lastCheckpointProjectDir = projectDir
            }
        }
    }

    /// Restore the most recent checkpoint for the active session
    func restoreLastCheckpoint() {
        guard let checkpoint = lastCheckpoint,
              let projectDir = lastCheckpointProjectDir else { return }
        checkpointStatus = "Restoring checkpoint…"
        Task.detached(priority: .userInitiated) {
            do {
                try CheckpointManager.shared.restoreCheckpoint(checkpoint, to: projectDir)
            } catch {
                logger.error("Failed to restore checkpoint: \(error.localizedDescription)")
            }
            await MainActor.run {
                SessionStore.shared.checkpointStatus = nil
                SessionStore.shared.lastCheckpoint = nil
            }
        }
    }

    /// Create a checkpoint with progress status
    func createCheckpointForActiveSession() {
        guard let session = activeSession,
              let dir = session.projectPath else { return }
        let projectDir = (dir as NSString).deletingLastPathComponent
        let projectName = session.projectName
        checkpointStatus = "Saving checkpoint…"
        Task.detached(priority: .userInitiated) {
            do {
                try CheckpointManager.shared.createCheckpoint(projectName: projectName, projectDirectory: projectDir)
            } catch {
                logger.error("Failed to create checkpoint: \(error.localizedDescription)")
            }
            await MainActor.run {
                SessionStore.shared.refreshLastCheckpoint()
                SessionStore.shared.checkpointStatus = nil
            }
        }
    }

    /// Create a checkpoint for a specific session by ID
    func createCheckpoint(for sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }),
              let dir = session.projectPath else { return }
        let projectDir = (dir as NSString).deletingLastPathComponent
        let projectName = session.projectName
        checkpointStatus = "Saving checkpoint…"
        Task.detached(priority: .userInitiated) {
            do {
                try CheckpointManager.shared.createCheckpoint(projectName: projectName, projectDirectory: projectDir)
            } catch {
                logger.error("Failed to create checkpoint for \(projectName): \(error.localizedDescription)")
            }
            await MainActor.run {
                SessionStore.shared.refreshLastCheckpoint()
                SessionStore.shared.checkpointStatus = nil
            }
        }
    }

    /// Sessions that have a project path (eligible for checkpoints)
    var checkpointEligibleSessions: [TerminalSession] {
        sessions.filter { $0.projectPath != nil }
    }

    /// Restore a specific checkpoint for a session
    func restoreCheckpoint(_ checkpoint: Checkpoint, for sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }),
              let dir = session.projectPath else { return }
        let projectDir = (dir as NSString).deletingLastPathComponent
        checkpointStatus = "Restoring checkpoint…"
        Task.detached(priority: .userInitiated) {
            do {
                try CheckpointManager.shared.restoreCheckpoint(checkpoint, to: projectDir)
            } catch {
                logger.error("Failed to restore checkpoint: \(error.localizedDescription)")
            }
            await MainActor.run {
                SessionStore.shared.checkpointStatus = nil
                SessionStore.shared.refreshLastCheckpoint()
            }
        }
    }

    func restartSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        cancelCompletionTransitions(forSession: id)
        for paneId in sessions[index].splitRoot.allPaneIds {
            TerminalManager.shared.destroyTerminal(for: paneId)
        }
        sessions[index].paneStatuses.removeAll()
        sessions[index].paneWorkingStartedAt.removeAll()
        sessions[index].generation += 1
        updateSleepPrevention()
    }

    /// Puts a session to sleep: kills all of its pane shells, frees the terminal
    /// views, and marks the session as sleeping. The pane tree and working
    /// directories are preserved so `wakeSession` can spawn fresh shells in the
    /// same layout. While sleeping, the session contributes no aggregate status.
    func sleepSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              !sessions[index].isSleeping else { return }

        cancelCompletionTransitions(forSession: id)
        for paneId in sessions[index].splitRoot.allPaneIds {
            TerminalManager.shared.destroyTerminal(for: paneId)
        }
        sessions[index].paneStatuses.removeAll()
        sessions[index].paneWorkingStartedAt.removeAll()
        sessions[index].isSleeping = true
        // hasStarted=false forces TerminalSessionView to re-spawn on next render.
        sessions[index].hasStarted = false
        sessions[index].generation += 1

        // If the active tab was just put to sleep, fall through to a non-sleeping
        // sibling so the panel doesn't show an empty area waiting for a render.
        if activeSessionId == id, let next = sessions.first(where: { !$0.isSleeping && $0.id != id }) {
            activeSessionId = next.id
        }

        updateSleepPrevention()
        NotificationCenter.default.post(name: .NotchyNotchStatusChanged, object: nil)
        persistSessions()
    }

    /// Wakes a sleeping session. The terminal will spawn lazily when the session
    /// becomes active and the SwiftUI view renders.
    func wakeSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].isSleeping else { return }
        sessions[index].isSleeping = false
        // Don't auto-set hasStarted here — let the selection path do it so the
        // terminal view actually mounts on the same runloop tick.
        NotificationCenter.default.post(name: .NotchyNotchStatusChanged, object: nil)
        persistSessions()
    }

    func toggleSleep(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        if session.isSleeping {
            wakeSession(id)
            selectSession(id)
        } else {
            sleepSession(id)
        }
    }

    /// Sleeps every non-sleeping session except the active one (or `keepId`).
    /// One-shot way to free resources when many tabs accumulated.
    func sleepInactiveTabs(except keepId: UUID? = nil) {
        let preserve = keepId ?? activeSessionId
        for session in sessions where !session.isSleeping && session.id != preserve {
            sleepSession(session.id)
        }
    }

    /// Wakes every sleeping session. Used when the user wants to see all tabs
    /// live again.
    func wakeAllTabs() {
        for session in sessions where session.isSleeping {
            wakeSession(session.id)
        }
    }

    var sleepingTabCount: Int {
        sessions.filter { $0.isSleeping }.count
    }

    /// Closes a tab. When `discardWorktree` is true and the tab is a worktree,
    /// its git worktree and branch are deleted; otherwise they're left on disk.
    func closeSession(_ id: UUID, discardWorktree: Bool = false) {
        cancelCompletionTransitions(forSession: id)
        if discardWorktree,
           let s = sessions.first(where: { $0.id == id }),
           let branch = s.worktreeBranch, let root = s.worktreeRepoRoot {
            WorktreeManager.shared.discardWorktree(repoRoot: root, path: s.workingDirectory, branch: branch)
        }
        if let session = sessions.first(where: { $0.id == id }) {
            for paneId in session.splitRoot.allPaneIds {
                TerminalManager.shared.destroyTerminal(for: paneId)
                SessionHistoryManager.shared.deleteHistory(for: paneId)
            }
        }
        SessionHistoryManager.shared.deleteHistory(for: id)
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.first?.id
        }
        updateSleepPrevention()
        persistSessions()
    }

    // MARK: - Split Pane Operations

    func updateSplitRatio(_ splitId: UUID, ratio: CGFloat) {
        guard let index = sessions.firstIndex(where: { $0.splitRoot.containsPane(splitId) || $0.splitRoot.id == splitId }) else { return }
        let clamped = max(0.2, min(0.8, ratio))
        sessions[index].splitRoot = sessions[index].splitRoot.updatingRatio(splitId, to: clamped)
    }

    func persistSplitRatio() {
        persistSessions()
    }

    func splitFocusedPane(direction: SplitDirection, placeNewBefore: Bool = false) {
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }
        let paneId = sessions[index].focusedPaneId
        let (newRoot, newPaneId) = sessions[index].splitRoot.splitting(
            paneId, direction: direction, placeNewBefore: placeNewBefore
        )
        sessions[index].splitRoot = newRoot
        sessions[index].focusedPaneId = newPaneId
        persistSessions()
    }

    func closeFocusedPane() {
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }
        let paneId = sessions[index].focusedPaneId

        TerminalManager.shared.destroyTerminal(for: paneId)
        sessions[index].paneStatuses.removeValue(forKey: paneId)
        sessions[index].paneWorkingStartedAt.removeValue(forKey: paneId)

        if let newRoot = sessions[index].splitRoot.removing(paneId) {
            sessions[index].splitRoot = newRoot
            sessions[index].focusedPaneId = newRoot.allPaneIds.first ?? sessions[index].focusedPaneId
            updateSleepPrevention()
            persistSessions()
        } else {
            closeSession(sessions[index].id)
        }
    }

    func focusPane(_ paneId: UUID) {
        guard let index = sessionIndex(forPane: paneId) else { return }
        sessions[index].focusedPaneId = paneId
        TerminalManager.shared.focusTerminal(for: paneId)
    }

    func focusNextPane() {
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }
        if let next = sessions[index].splitRoot.nextPaneId(after: sessions[index].focusedPaneId) {
            sessions[index].focusedPaneId = next
            TerminalManager.shared.focusTerminal(for: next)
        }
    }

    func focusPreviousPane() {
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }
        if let prev = sessions[index].splitRoot.previousPaneId(before: sessions[index].focusedPaneId) {
            sessions[index].focusedPaneId = prev
            TerminalManager.shared.focusTerminal(for: prev)
        }
    }
}
