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
    let createdAt: Date

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

    /// Aggregate status across all panes
    var terminalStatus: TerminalStatus {
        if isSleeping { return .sleeping }
        let statuses = Array(paneStatuses.values)
        if statuses.isEmpty { return .idle }
        if statuses.contains(.working) { return .working }
        if statuses.contains(.waitingForInput) { return .waitingForInput }
        if statuses.contains(.taskCompleted) { return .taskCompleted }
        if statuses.contains(.interrupted) { return .interrupted }
        return .idle
    }

    /// Custom command to run instead of auto-detecting claude
    var customCommand: String?

    init(projectName: String, projectPath: String? = nil, workingDirectory: String? = nil, started: Bool = false, customCommand: String? = nil) {
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
        self.createdAt = Date()
        self.isSleeping = persisted.isSleeping ?? false

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
}
