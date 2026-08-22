import XCTest

@MainActor
final class AutocompleteRankerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func cmd(_ text: String, count: Int = 1, daysAgo: Double = 0) -> StoredCommand {
        StoredCommand(text: text, count: count, lastUsed: now.addingTimeInterval(-daysAgo * 86400))
    }

    private func rank(_ input: String, _ commands: [StoredCommand]) -> [String] {
        AutocompleteRanker().rank(input: input, commands: commands, now: now).map(\.command)
    }

    // MARK: - Matching

    func testNeedsAtLeastTwoCharacters() {
        XCTAssertTrue(rank("g", [cmd("git status")]).isEmpty)
        XCTAssertFalse(rank("gi", [cmd("git status")]).isEmpty)
    }

    func testEmptyCommandListYieldsNothing() {
        XCTAssertTrue(rank("git", []).isEmpty)
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(rank("GIT ST", [cmd("git status")]), ["git status"])
    }

    func testTheExactCommandIsNotSuggestedBackToTheUser() {
        XCTAssertEqual(rank("git status", [cmd("git status"), cmd("git status -s")]), ["git status -s"])
    }

    func testNonMatchingCommandsAreExcluded() {
        XCTAssertTrue(rank("git", [cmd("npm run dev")]).isEmpty)
    }

    // MARK: - Ranking

    func testPrefixMatchesOutrankFuzzyMatches() {
        // "gst" is a subsequence of "git status" but a prefix of "gst --all",
        // even though the fuzzy candidate is used far more often.
        let result = rank("gst", [cmd("git status", count: 500, daysAgo: 0), cmd("gst --all", count: 1, daysAgo: 300)])
        XCTAssertEqual(result.first, "gst --all")
        XCTAssertEqual(result.count, 2)
    }

    func testFrequentCommandsWinAmongEqualPrefixMatches() {
        XCTAssertEqual(rank("git p", [cmd("git push", count: 1, daysAgo: 1), cmd("git pull", count: 64, daysAgo: 1)]).first,
                       "git pull")
    }

    func testRecentCommandsWinAmongEqualPrefixMatches() {
        XCTAssertEqual(rank("git p", [cmd("git push", count: 4, daysAgo: 400), cmd("git pull", count: 4, daysAgo: 0)]).first,
                       "git pull")
    }

    func testShorterCommandsBreakTiesAmongEqualPrefixMatches() {
        XCTAssertEqual(rank("npm ru", [cmd("npm run dev --verbose --watch"), cmd("npm run dev")]).first,
                       "npm run dev")
    }

    /// Frequency is capped so a single hammered command cannot bury a fresh
    /// prefix match forever.
    func testTheFrequencyBonusIsBounded() {
        let scores = AutocompleteRanker().rank(
            input: "git p",
            commands: [cmd("git pull", count: 1_000_000, daysAgo: 400), cmd("git pull x", count: 1_000_000, daysAgo: 400)],
            now: now
        )
        // base 100 + capped bonus 30 − length penalty
        XCTAssertEqual(scores[0].score, 100 + 30 - 0.8, accuracy: 0.0001)
    }

    func testResultsAreCappedAtTheConfiguredMaximum() {
        let commands = (1...20).map { cmd("git branch \($0)") }
        XCTAssertEqual(AutocompleteRanker().rank(input: "git b", commands: commands, now: now).count, 7)
        XCTAssertEqual(AutocompleteRanker(maxSuggestions: 3).rank(input: "git b", commands: commands, now: now).count, 3)
    }

    func testResultsComeBackSortedByDescendingScore() {
        let scores = AutocompleteRanker().rank(
            input: "gi",
            commands: [cmd("git status", count: 1, daysAgo: 100), cmd("git push", count: 50, daysAgo: 0), cmd("grip", count: 2)],
            now: now
        ).map(\.score)
        XCTAssertEqual(scores, scores.sorted(by: >))
    }

    // MARK: - Fuzzy matching

    func testFuzzyMatchIsAnInOrderSubsequence() {
        XCTAssertTrue(AutocompleteRanker.fuzzyMatch(query: "gst", target: "git status"))
        XCTAssertTrue(AutocompleteRanker.fuzzyMatch(query: "dcu", target: "docker compose up"))
        XCTAssertFalse(AutocompleteRanker.fuzzyMatch(query: "tsg", target: "git status"), "order matters")
        XCTAssertFalse(AutocompleteRanker.fuzzyMatch(query: "gitx", target: "git"))
    }

    func testFuzzyMatchAcceptsAnEmptyQueryAndRejectsAnEmptyTarget() {
        XCTAssertTrue(AutocompleteRanker.fuzzyMatch(query: "", target: "anything"))
        XCTAssertFalse(AutocompleteRanker.fuzzyMatch(query: "a", target: ""))
    }

    // MARK: - Cache

    func testTheLowercaseCacheDoesNotChangeResultsAcrossCalls() {
        let ranker = AutocompleteRanker()
        let commands = [cmd("Git Status"), cmd("git stash")]

        let first = ranker.rank(input: "git st", commands: commands, now: now)
        let second = ranker.rank(input: "git st", commands: commands, now: now)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 2)
    }
}
