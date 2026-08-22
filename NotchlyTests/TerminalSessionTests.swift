import XCTest

@MainActor
final class TerminalSessionTests: XCTestCase {

    private func session() -> TerminalSession {
        TerminalSession(projectName: "demo", projectPath: "/proj")
    }

    // MARK: - Construction

    func testNewSessionStartsAsASingleFocusedPane() {
        let s = session()
        XCTAssertEqual(s.splitRoot.allPaneIds.count, 1)
        XCTAssertEqual(s.focusedPaneId, s.splitRoot.allPaneIds[0])
        XCTAssertEqual(s.workingDirectory, "/proj")
        XCTAssertEqual(s.terminalStatus, .idle)
        XCTAssertFalse(s.isWorktree)
    }

    func testWorkingDirectoryFallsBackToProjectPathThenHome() {
        XCTAssertEqual(TerminalSession(projectName: "a", projectPath: "/p").workingDirectory, "/p")
        XCTAssertEqual(TerminalSession(projectName: "a").workingDirectory, NSHomeDirectory())
    }

    func testIsWorktreeRequiresBothBranchAndRepoRoot() {
        XCTAssertFalse(TerminalSession(projectName: "a", worktreeBranch: "feat").isWorktree)
        XCTAssertFalse(TerminalSession(projectName: "a", worktreeRepoRoot: "/repo").isWorktree)
        XCTAssertTrue(TerminalSession(projectName: "a", worktreeBranch: "feat", worktreeRepoRoot: "/repo").isWorktree)
    }

    // MARK: - Aggregate status priority

    /// The notch pill, the tab dot and idle-sleep prevention all read this.
    /// Ordering: working > waitingForInput > taskCompleted > interrupted > idle.
    func testAggregateStatusPicksTheHighestPriorityPane() {
        var s = session()
        let (tree, second) = s.splitRoot.splitting(s.focusedPaneId, direction: .horizontal)
        let (tree3, third) = tree.splitting(second, direction: .vertical)
        s.splitRoot = tree3
        let first = s.splitRoot.allPaneIds[0]

        s.paneStatuses = [first: .idle, second: .idle, third: .idle]
        XCTAssertEqual(s.terminalStatus, .idle)

        s.paneStatuses[second] = .interrupted
        XCTAssertEqual(s.terminalStatus, .interrupted)

        s.paneStatuses[third] = .taskCompleted
        XCTAssertEqual(s.terminalStatus, .taskCompleted)

        s.paneStatuses[first] = .waitingForInput
        XCTAssertEqual(s.terminalStatus, .waitingForInput)

        s.paneStatuses[second] = .working
        XCTAssertEqual(s.terminalStatus, .working)
    }

    func testSleepingOverridesEveryPaneStatus() {
        var s = session()
        s.paneStatuses[s.focusedPaneId] = .working
        s.isSleeping = true

        XCTAssertEqual(s.terminalStatus, .sleeping,
                       "a sleeping tab has no live process — it must never report as working")
    }

    func testSleepingPaneStatusRanksAsIdle() {
        var s = session()
        s.paneStatuses[s.focusedPaneId] = .sleeping
        XCTAssertEqual(s.terminalStatus, .idle)
    }

    // MARK: - Persistence

    func testPersistedSessionRoundTripRestoresPanesAndFlags() {
        var original = session()
        let (tree, second) = original.splitRoot.splitting(original.focusedPaneId, direction: .horizontal)
        original.splitRoot = tree
        original.focusedPaneId = second
        original.isSleeping = true
        original.notificationsMuted = true
        original.customCommand = "claude --resume"
        original.createdAt = Date(timeIntervalSince1970: 1_650_000_000)

        let persisted = PersistedSession(
            id: original.id,
            projectName: original.projectName,
            projectPath: original.projectPath,
            workingDirectory: original.workingDirectory,
            splitRoot: original.splitRoot,
            focusedPaneId: original.focusedPaneId,
            isSleeping: original.isSleeping,
            notificationsMuted: original.notificationsMuted,
            customCommand: original.customCommand,
            worktreeBranch: nil,
            worktreeRepoRoot: nil,
            createdAt: original.createdAt
        )
        let data = try! JSONEncoder().encode(persisted)
        let decoded = try! JSONDecoder().decode(PersistedSession.self, from: data)
        let restored = TerminalSession(persisted: decoded)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.splitRoot, original.splitRoot)
        XCTAssertEqual(restored.focusedPaneId, second)
        XCTAssertEqual(restored.createdAt, original.createdAt,
                       "creation date must survive a relaunch")
        XCTAssertTrue(restored.isSleeping)
        XCTAssertTrue(restored.notificationsMuted)
        XCTAssertFalse(restored.hasStarted, "a restored tab must start lazily")
        XCTAssertFalse(restored.hasBeenSelected)
    }

    /// Payloads written before split panes existed have no splitRoot. Decoding
    /// them must still yield a usable single-pane session.
    func testRestoringLegacyPayloadWithoutSplitsSynthesizesOnePane() {
        let legacy = """
        {"id":"\(UUID().uuidString)","projectName":"old","workingDirectory":"/legacy"}
        """.data(using: .utf8)!

        let decoded = try! JSONDecoder().decode(PersistedSession.self, from: legacy)
        let restored = TerminalSession(persisted: decoded)

        XCTAssertEqual(restored.splitRoot.allPaneIds.count, 1)
        XCTAssertEqual(restored.focusedPaneId, restored.splitRoot.allPaneIds[0])
        XCTAssertEqual(restored.splitRoot.workingDirectory(for: restored.focusedPaneId), "/legacy")
        XCTAssertFalse(restored.isSleeping)
        XCTAssertFalse(restored.notificationsMuted)
        XCTAssertLessThan(abs(restored.createdAt.timeIntervalSinceNow), 5,
                          "legacy payloads without createdAt fall back to now")
    }

    /// A tab launched with a custom command (e.g. `claude --resume`) must come
    /// back as that command after a relaunch instead of reverting to a shell.
    func testCustomCommandSurvivesPersistenceRoundTrip() {
        let original = TerminalSession(
            projectName: "demo", projectPath: "/proj",
            customCommand: "claude --resume"
        )

        let data = try! JSONEncoder().encode(PersistedSession(from: original))
        let restored = TerminalSession(
            persisted: try! JSONDecoder().decode(PersistedSession.self, from: data)
        )

        XCTAssertEqual(restored.customCommand, "claude --resume")
    }

    func testCustomCommandIsOptionalInLegacyPayloads() {
        let legacy = """
        {"id":"\(UUID().uuidString)","projectName":"old","workingDirectory":"/legacy"}
        """.data(using: .utf8)!

        let decoded = try! JSONDecoder().decode(PersistedSession.self, from: legacy)
        XCTAssertNil(decoded.customCommand)
        XCTAssertNil(TerminalSession(persisted: decoded).customCommand)
    }

    // MARK: - Dialog visibility registry

    /// Panel chrome and individual tabs report independently: one owner
    /// closing its dialog must not hide the panel while another's is open
    /// (this used to be a shared Bool, last writer won).
    func testDialogRegistryComposesConcurrentOwners() {
        var registry = DialogVisibilityRegistry()

        XCTAssertFalse(registry.isVisible)

        registry.setVisible(true, owner: "panelContent")
        XCTAssertTrue(registry.isVisible)

        registry.setVisible(true, owner: "tab.1")
        XCTAssertTrue(registry.isVisible, "second owner opening must keep it visible")

        registry.setVisible(false, owner: "panelContent")
        XCTAssertTrue(registry.isVisible, "panel closing its dialog must not drop the tab's registration")

        registry.setVisible(false, owner: "tab.1")
        XCTAssertFalse(registry.isVisible)
    }

    func testDialogRegistryIsIdempotentPerOwner() {
        var registry = DialogVisibilityRegistry()
        registry.setVisible(true, owner: "panelContent")
        registry.setVisible(true, owner: "panelContent")
        XCTAssertEqual(registry.visibleOwners.count, 1)
        registry.setVisible(false, owner: "tab.1")
        XCTAssertTrue(registry.isVisible, "unregistering an unknown owner must not clear others")
    }

    /// Closing a session removes its tabs' registrations wholesale — their
    /// views are gone and will never report false.
    func testDialogRegistryRemovesOwnersByPrefix() {
        var registry = DialogVisibilityRegistry()
        let sessionId = UUID()
        let otherSessionId = UUID()
        registry.setVisible(true, owner: "panelContent")
        registry.setVisible(true, owner: "tab.\(sessionId.uuidString)")
        registry.setVisible(true, owner: "tab.\(otherSessionId.uuidString)")

        registry.removeAll(ownersWithPrefix: "tab.\(sessionId.uuidString)")

        XCTAssertEqual(registry.visibleOwners, ["panelContent", "tab.\(otherSessionId.uuidString)"])
    }

    // MARK: - Task completion gate

    /// The pane must still be idle when the confirmation window elapses —
    /// a pane that resumed working must not fire "task completed".
    func testGateRequiresThePaneToStillBeIdle() {
        XCTAssertTrue(TaskCompletionGate.shouldConfirm(
            currentPaneStatus: .idle, workDuration: 30, minimumWorkDuration: 7))
        XCTAssertFalse(TaskCompletionGate.shouldConfirm(
            currentPaneStatus: .working, workDuration: 30, minimumWorkDuration: 7))
        XCTAssertFalse(TaskCompletionGate.shouldConfirm(
            currentPaneStatus: .waitingForInput, workDuration: 30, minimumWorkDuration: 7))
        XCTAssertFalse(TaskCompletionGate.shouldConfirm(
            currentPaneStatus: nil, workDuration: 30, minimumWorkDuration: 7),
            "a torn-down pane has no status to confirm")
    }

    /// Trivial commands (below the minimum duration) stay silent; an unknown
    /// duration still fires rather than suppressing a real completion.
    func testGateSuppressesTrivialTasksButFiresOnUnknownDuration() {
        XCTAssertTrue(TaskCompletionGate.shouldConfirm(
            currentPaneStatus: .idle, workDuration: nil, minimumWorkDuration: 7))
        XCTAssertFalse(TaskCompletionGate.shouldConfirm(
            currentPaneStatus: .idle, workDuration: 2, minimumWorkDuration: 7),
                       "a 2 s command is noise, not a completed task")
        XCTAssertEqual(TaskCompletionGate.shouldConfirm(
            currentPaneStatus: .idle, workDuration: 7, minimumWorkDuration: 7), true,
                       "exactly at the threshold counts as real work")
    }
}
