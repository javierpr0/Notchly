import AppKit
import AVFoundation
import SwiftUI
import UserNotifications
import os

private let logger = Logger(subsystem: "com.notchly", category: "SessionStore")

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
    var isPinned: Bool = {
        if UserDefaults.standard.object(forKey: "isPinned") == nil { return true }
        return UserDefaults.standard.bool(forKey: "isPinned")
    }() {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: "isPinned")
        }
    }
    var isTerminalExpanded = true
    var isWindowFocused = true
    var isShowingDialog = false
    var showCommandPalette = false

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
        case .idle, .interrupted, .taskCompleted: return .systemGreen
        }
    }

    private static let sessionsKey = "persistedSessions"
    private static let activeSessionKey = "activeSessionId"

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

    private func sendNotification(title: String, body: String) {
        guard !isWindowFocused else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Session Persistence

    private func restoreSessions() {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
              let persisted = try? JSONDecoder().decode([PersistedSession].self, from: data),
              !persisted.isEmpty else { return }
        sessions = persisted.map { TerminalSession(persisted: $0) }
        if let savedId = UserDefaults.standard.string(forKey: Self.activeSessionKey),
           let uuid = UUID(uuidString: savedId),
           sessions.contains(where: { $0.id == uuid }) {
            activeSessionId = uuid
        } else {
            activeSessionId = sessions.first?.id
        }
        // Mark all restored sessions as started so terminals launch immediately
        for i in sessions.indices {
            sessions[i].hasStarted = true
            sessions[i].hasBeenSelected = true
        }
    }

    func saveSessions() {
        persistSessions()
    }

    private func persistSessions() {
        let persisted = sessions.map {
            PersistedSession(
                id: $0.id, projectName: $0.projectName, projectPath: $0.projectPath,
                workingDirectory: $0.workingDirectory,
                splitRoot: $0.splitRoot, focusedPaneId: $0.focusedPaneId
            )
        }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
        if let activeId = activeSessionId {
            UserDefaults.standard.set(activeId.uuidString, forKey: Self.activeSessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeSessionKey)
        }
    }

    func updateWorkingDirectory(_ paneId: UUID, directory: String) {
        guard let index = sessions.firstIndex(where: { $0.splitRoot.containsPane(paneId) }) else { return }
        let oldDir = sessions[index].splitRoot.workingDirectory(for: paneId)
        guard oldDir != directory else { return }
        sessions[index].splitRoot = sessions[index].splitRoot.updatingWorkingDirectory(paneId, to: directory)
        if sessions[index].focusedPaneId == paneId {
            sessions[index].workingDirectory = directory
        }
        persistSessions()
    }

    /// Select a tab — auto-starts the terminal and clears taskCompleted indicators
    func selectSession(_ id: UUID) {
        activeSessionId = id
        if let index = sessions.firstIndex(where: { $0.id == id }) {
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

    /// Mark session as started (terminal will be created when view renders)
    func startSessionIfNeeded(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
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

    func renameSession(_ id: UUID, to newName: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].projectName = newName
        persistSessions()
    }

    func updateTerminalStatus(_ paneId: UUID, status: TerminalStatus) {
        guard let index = sessions.firstIndex(where: { $0.splitRoot.containsPane(paneId) }) else { return }

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
                sendNotification(title: L10n.shared.actionRequired, body: L10n.shared.needsInput(sessionName))
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
                sendNotification(title: title, body: body)
                paneCompletionInfo.removeValue(forKey: paneId)
            }
            NotificationCenter.default.post(name: .NotchyNotchStatusChanged, object: nil)
        }

        // Per-pane working→idle delay for taskCompleted
        if status == .idle && oldPaneStatus == .working {
            let workingStartedAt = sessions[index].paneWorkingStartedAt[paneId]
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard let idx = self.sessions.firstIndex(where: { $0.id == sessionId }),
                      self.sessions[idx].paneStatuses[paneId] == .idle else { return }
                if let started = workingStartedAt, Date().timeIntervalSince(started) < 10 {
                    return
                }
                self.updateTerminalStatus(paneId, status: .taskCompleted)
            }
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
        let checkpoints = CheckpointManager.shared.checkpoints(for: session.projectName, in: projectDir)
        lastCheckpoint = checkpoints.first
        lastCheckpointProjectName = session.projectName
        lastCheckpointProjectDir = projectDir
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
        for paneId in sessions[index].splitRoot.allPaneIds {
            TerminalManager.shared.destroyTerminal(for: paneId)
        }
        sessions[index].paneStatuses.removeAll()
        sessions[index].paneWorkingStartedAt.removeAll()
        sessions[index].generation += 1
    }

    func closeSession(_ id: UUID) {
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

    func splitFocusedPane(direction: SplitDirection) {
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }
        let paneId = sessions[index].focusedPaneId
        let (newRoot, newPaneId) = sessions[index].splitRoot.splitting(paneId, direction: direction)
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
            persistSessions()
        } else {
            closeSession(sessions[index].id)
        }
    }

    func focusPane(_ paneId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.splitRoot.containsPane(paneId) }) else { return }
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
