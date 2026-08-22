import XCTest

@MainActor
final class SessionPersistenceTests: XCTestCase {

    private var workDir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchly-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        fileURL = workDir.appendingPathComponent("sessions.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private func sampleSessions() -> [PersistedSession] {
        [
            PersistedSession(
                id: UUID(), projectName: "alpha", projectPath: "/alpha",
                workingDirectory: "/alpha", splitRoot: nil, focusedPaneId: nil,
                isSleeping: true, notificationsMuted: true,
                customCommand: "claude --resume", worktreeBranch: "feat", worktreeRepoRoot: "/repo",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            PersistedSession(
                id: UUID(), projectName: "beta", projectPath: nil,
                workingDirectory: "/beta", splitRoot: nil, focusedPaneId: nil,
                isSleeping: nil, notificationsMuted: nil,
                customCommand: nil, worktreeBranch: nil, worktreeRepoRoot: nil,
                createdAt: nil
            ),
        ]
    }

    // MARK: - Round trip

    func testSaveThenLoadPreservesSessionsAndActivePointer() throws {
        let original = sampleSessions()
        let activeId = original[1].id

        try SessionPersistence.save(original, activeSessionId: activeId, to: fileURL)
        let loaded = SessionPersistence.load(from: fileURL)

        XCTAssertEqual(loaded?.sessions.count, 2)
        XCTAssertEqual(loaded?.sessions.map(\.id), original.map(\.id))
        XCTAssertEqual(loaded?.sessions.first?.customCommand, "claude --resume")
        XCTAssertEqual(loaded?.sessions.first?.isSleeping, true)
        XCTAssertEqual(loaded?.activeSessionId, activeId)
    }

    /// A stale pointer (session closed elsewhere) must not leave the store
    /// pointing at nothing — fall back to the first session instead.
    func testUnknownActivePointerFallsBackToFirstSession() throws {
        let original = sampleSessions()
        try SessionPersistence.save(original, activeSessionId: UUID(), to: fileURL)

        let loaded = SessionPersistence.load(from: fileURL)
        XCTAssertEqual(loaded?.activeSessionId, original[0].id)
    }

    func testSavingTwiceReplacesThePreviousContents() throws {
        try SessionPersistence.save(sampleSessions(), activeSessionId: nil, to: fileURL)
        let single = [PersistedSession(
            id: UUID(), projectName: "only", projectPath: nil, workingDirectory: "/x",
            splitRoot: nil, focusedPaneId: nil, isSleeping: nil, notificationsMuted: nil,
            customCommand: nil, worktreeBranch: nil, worktreeRepoRoot: nil, createdAt: nil
        )]
        try SessionPersistence.save(single, activeSessionId: single[0].id, to: fileURL)

        let loaded = SessionPersistence.load(from: fileURL)
        XCTAssertEqual(loaded?.sessions.count, 1)
        XCTAssertEqual(loaded?.sessions.first?.projectName, "only")
    }

    // MARK: - Corruption recovery

    /// A blob that cannot decode must be preserved for inspection, never
    /// silently dropped nor overwritten by the next save.
    func testCorruptFileIsBackedUpAndLoadReturnsNil() throws {
        let corrupt = Data("this is not json".utf8)
        try corrupt.write(to: fileURL)

        XCTAssertNil(SessionPersistence.load(from: fileURL))

        let siblings = try FileManager.default.contentsOfDirectory(atPath: workDir.path)
            .filter { $0.hasPrefix("sessions.corrupt-") }
        XCTAssertEqual(siblings.count, 1, "exactly one timestamped backup must exist")

        let backupData = try Data(contentsOf: workDir.appendingPathComponent(siblings[0]))
        XCTAssertEqual(backupData, corrupt, "the backup must hold the original bytes")
    }

    // MARK: - Legacy UserDefaults migration

    func testLegacyStoreReadsOldDefaultsKeys() throws {
        let suiteName = "legacy-test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let sessions = sampleSessions()
        let data = try JSONEncoder().encode(sessions)
        suite.set(data, forKey: "persistedSessions")
        suite.set(sessions[0].id.uuidString, forKey: "activeSessionId")

        let legacy = SessionPersistence.legacyStore(in: suite)
        XCTAssertEqual(legacy?.sessions.count, 2)
        XCTAssertEqual(legacy?.activeSessionId, sessions[0].id)
    }

    func testLegacyStoreReturnsNilWithoutStoredDataOrWithGarbage() {
        let suite = UserDefaults(suiteName: "legacy-test-\(UUID().uuidString)")!
        XCTAssertNil(SessionPersistence.legacyStore(in: suite))

        suite.set(Data("garbage".utf8), forKey: "persistedSessions")
        XCTAssertNil(SessionPersistence.legacyStore(in: suite),
                     "undecodable legacy blobs are not worth migrating — start fresh")
    }
}
