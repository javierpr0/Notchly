import Foundation

enum TerminalStatus: Equatable {
    /// Default — no special activity detected
    case idle
    /// Claude is working (status line matches token counter pattern)
    case working
    /// Claude is waiting for user input ("Esc to cancel")
    case waitingForInput
    /// Claude was interrupted by the user (Esc pressed)
    case interrupted
    /// Claude finished a task (confirmed via idle timer line after working)
    case taskCompleted
    /// Tab is sleeping — terminal process is killed to free resources.
    /// Selecting the tab wakes it (re-spawns the shell).
    case sleeping
}

struct TerminalSession: Identifiable {
    let id: UUID
    var projectName: String
    var projectPath: String?
    var workingDirectory: String
    var hasStarted: Bool
    var generation: Int
    /// Whether the user has ever manually selected this tab
    var hasBeenSelected: Bool
    var createdAt: Date

    // Split pane support
    var splitRoot: SplitNode
    var focusedPaneId: UUID
    var paneStatuses: [UUID: TerminalStatus] = [:]
    var paneWorkingStartedAt: [UUID: Date] = [:]

    /// When true, the tab's terminal processes are killed to free resources.
    /// The pane tree and working directories are preserved so the tab can be
    /// woken later. While sleeping, no terminal view is mounted and no status
    /// detection runs.
    var isSleeping: Bool = false

    /// When true, this tab's "task done" / "needs input" notifications are
    /// suppressed. Persisted so the preference survives restarts.
    var notificationsMuted: Bool = false

    /// Set when this tab runs inside a Notchly-created git worktree.
    /// `worktreeBranch` is the branch checked out there; `worktreeRepoRoot` is
    /// the main repo it was forked from (needed to remove the worktree on close).
    var worktreeBranch: String?
    var worktreeRepoRoot: String?
    var isWorktree: Bool { worktreeBranch != nil && worktreeRepoRoot != nil }

    /// Aggregate status across all panes. Single pass, no intermediate array:
    /// every tab render and every notch snapshot reads this property.
    var terminalStatus: TerminalStatus {
        if isSleeping { return .sleeping }
        var best = 0
        for status in paneStatuses.values {
            let rank: Int
            switch status {
            case .working: rank = 4
            case .waitingForInput: rank = 3
            case .taskCompleted: rank = 2
            case .interrupted: rank = 1
            case .idle, .sleeping: rank = 0
            }
            if rank > best {
                best = rank
                if rank == 4 { break }
            }
        }
        switch best {
        case 4: return .working
        case 3: return .waitingForInput
        case 2: return .taskCompleted
        case 1: return .interrupted
        default: return .idle
        }
    }

    /// Custom command to run instead of auto-detecting claude
    var customCommand: String?

    init(projectName: String, projectPath: String? = nil, workingDirectory: String? = nil, started: Bool = false, customCommand: String? = nil, worktreeBranch: String? = nil, worktreeRepoRoot: String? = nil) {
        self.id = UUID()
        self.projectName = projectName
        self.projectPath = projectPath
        let dir = workingDirectory ?? projectPath ?? NSHomeDirectory()
        self.workingDirectory = dir
        self.hasStarted = started
        self.generation = 0
        self.hasBeenSelected = started
        self.createdAt = Date()
        self.customCommand = customCommand
        self.worktreeBranch = worktreeBranch
        self.worktreeRepoRoot = worktreeRepoRoot

        let paneId = UUID()
        self.splitRoot = .pane(id: paneId, workingDirectory: dir)
        self.focusedPaneId = paneId
    }

    /// Restore a session from persisted data
    init(persisted: PersistedSession) {
        self.id = persisted.id
        self.projectName = persisted.projectName
        self.projectPath = persisted.projectPath
        self.workingDirectory = persisted.workingDirectory
        self.hasStarted = false
        self.generation = 0
        self.hasBeenSelected = false
        // Fall back to "now" only for payloads written before this field existed.
        self.createdAt = persisted.createdAt ?? Date()
        self.isSleeping = persisted.isSleeping ?? false
        self.notificationsMuted = persisted.notificationsMuted ?? false
        self.customCommand = persisted.customCommand
        self.worktreeBranch = persisted.worktreeBranch
        self.worktreeRepoRoot = persisted.worktreeRepoRoot

        if let root = persisted.splitRoot {
            self.splitRoot = root
            self.focusedPaneId = persisted.focusedPaneId ?? root.allPaneIds.first ?? UUID()
        } else {
            // Backward compat: old data without splits
            let paneId = UUID()
            self.splitRoot = .pane(id: paneId, workingDirectory: persisted.workingDirectory)
            self.focusedPaneId = paneId
        }
    }
}

/// Lightweight Codable representation for UserDefaults persistence.
/// New fields must be optional so decoding old payloads keeps working.
struct PersistedSession: Codable {
    let id: UUID
    let projectName: String
    let projectPath: String?
    let workingDirectory: String
    let splitRoot: SplitNode?
    let focusedPaneId: UUID?
    let isSleeping: Bool?
    let notificationsMuted: Bool?
    let customCommand: String?
    let worktreeBranch: String?
    let worktreeRepoRoot: String?
    let createdAt: Date?
}

extension PersistedSession {
    /// Captures the durable state of a live session.
    init(from s: TerminalSession) {
        self.init(
            id: s.id, projectName: s.projectName, projectPath: s.projectPath,
            workingDirectory: s.workingDirectory,
            splitRoot: s.splitRoot, focusedPaneId: s.focusedPaneId,
            isSleeping: s.isSleeping ? true : nil,
            notificationsMuted: s.notificationsMuted ? true : nil,
            customCommand: s.customCommand,
            worktreeBranch: s.worktreeBranch,
            worktreeRepoRoot: s.worktreeRepoRoot,
            createdAt: s.createdAt
        )
    }
}

/// Pure gate for promoting a working→idle pane to `taskCompleted` once the
/// confirmation window elapses. Kept side-effect-free so the notification
/// rules can be asserted directly; `SessionStore` owns the timing.
enum TaskCompletionGate {
    static func shouldConfirm(currentPaneStatus: TerminalStatus?,
                              workDuration: TimeInterval?,
                              minimumWorkDuration: TimeInterval) -> Bool {
        guard currentPaneStatus == .idle else { return false }
        guard let duration = workDuration else { return true }
        return duration >= minimumWorkDuration
    }
}
