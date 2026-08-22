import XCTest

@MainActor
final class StaleFilePrunerTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchly-pruner-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeJSON(_ name: String, modified: Date) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    func testStaleFilesReturnsOnlyFilesOlderThanCutoffSortedOldestFirst() throws {
        let now = Date()
        _ = try writeJSON("a.json", modified: now.addingTimeInterval(-200 * 24 * 3600))
        _ = try writeJSON("b.json", modified: now.addingTimeInterval(-100 * 24 * 3600))
        _ = try writeJSON("fresh.json", modified: now.addingTimeInterval(-1 * 24 * 3600))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("notes.txt"))

        let stale = StaleFilePruner.staleJSONFiles(in: dir, olderThan: now.addingTimeInterval(-90 * 24 * 3600))

        // Compare by file name: contentsOfDirectory resolves /var → /private/var,
        // so raw URLs never match the ones built from the test's directory.
        XCTAssertEqual(stale.map(\.lastPathComponent), ["a.json", "b.json"],
                       "only stale JSON, oldest first; fresh and non-JSON excluded")
    }

    func testPruneRemovesStaleAndKeepsFresh() throws {
        let now = Date()
        _ = try writeJSON("old.json", modified: now.addingTimeInterval(-365 * 24 * 3600))
        let fresh = try writeJSON("keep.json", modified: now)

        let removed = StaleFilePruner.prune(in: dir, olderThan: now.addingTimeInterval(-90 * 24 * 3600))

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("old.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testMissingDirectoryIsNotAnError() {
        let missing = dir.appendingPathComponent("does-not-exist")
        XCTAssertTrue(StaleFilePruner.staleJSONFiles(in: missing, olderThan: Date()).isEmpty)
        XCTAssertEqual(StaleFilePruner.prune(in: missing, olderThan: Date()), 0)
    }
}
