import XCTest

/// These tests pin the heuristic that drives every notification, the notch
/// pill and idle-sleep prevention. The rows below imitate what Claude Code
/// actually paints; if upstream changes its copy, these are the tests that
/// should fail first.
@MainActor
final class TerminalStatusClassifierTests: XCTestCase {

    private let rule = String(repeating: "\u{2500}", count: 40)

    /// The rule Claude draws above its input area, followed by the box content.
    private func promptBox(_ inner: String...) -> [String] {
        [rule] + inner
    }

    // MARK: - working

    func testSpinnerWithTokenCounterMeansWorking() {
        let rows = ["● Reading the file.", "", "✻ Thinking… (12s · ↑ 1.2k tokens)"] + promptBox(" > ")
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .working)
    }

    func testEscToInterruptMeansWorkingEvenWithoutASpinner() {
        let rows = ["● Running tests."] + promptBox(" > ", "  (esc to interrupt)")
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .working)
    }

    func testWorkingBeatsWaitingWhenBothMarkersArePresent() {
        let rows = ["✽ Compiling… (3s)"] + promptBox(" > ", "  Esc to cancel")
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .working)
    }

    func testEverySpinnerGlyphIsRecognised() {
        for glyph in ["·", "✢", "✳", "✶", "✻", "✽"] {
            XCTAssertTrue(TerminalStatusClassifier.hasTokenCounterLine("\(glyph) Working… (1s)"),
                          "\(glyph) should be treated as a spinner")
        }
    }

    func testSpinnerLineNeedsBothTheSpaceAndTheEllipsis() {
        XCTAssertFalse(TerminalStatusClassifier.hasTokenCounterLine("✻Thinking… (1s)"),
                       "no space after the glyph — not Claude's status line")
        XCTAssertFalse(TerminalStatusClassifier.hasTokenCounterLine("✻ Thinking (1s)"),
                       "no ellipsis — not Claude's status line")
    }

    func testProseMentioningWorkingIsNotWorking() {
        let rows = ["● The build is still working on it…"] + promptBox(" > ")
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .idle,
                       "plain prose must not be mistaken for the status line")
    }

    // MARK: - waitingForInput

    func testEscToCancelInThePromptBoxMeansWaitingForInput() {
        let rows = ["● I need to run a command."] + promptBox(
            "  Do you want to proceed?",
            "  1. Yes  2. No",
            "  Esc to cancel"
        )
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .waitingForInput)
    }

    // MARK: - interrupted

    func testInterruptedIsReadFromTheVisibleAreaOnly() {
        let above = ["● Interrupted by user"] + promptBox(" > ")
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: above).status, .interrupted)

        let below = ["● All done."] + promptBox(" > Interrupted")
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: below).status, .idle,
                       "text the user typed into the prompt box must not flip the status")
    }

    // MARK: - idle, summary and errors

    func testIdleSummaryIsTheLastVisibleLine() {
        let rows = ["● First step done.", "", "● Added the migration."] + promptBox(" > ")
        let reading = TerminalStatusClassifier.evaluate(tailLines: rows)

        XCTAssertEqual(reading.status, .idle)
        XCTAssertEqual(reading.summary, "● Added the migration.")
        XCTAssertFalse(reading.hadError)
    }

    func testSummaryIsSanitizedAndCappedAtOneHundredCharacters() {
        let hostile = "\u{001B}[31m\u{202E}Everything is fine" + String(repeating: "x", count: 200)
        let reading = TerminalStatusClassifier.evaluate(tailLines: [hostile] + promptBox(" > "))

        let summary = try! XCTUnwrap(reading.summary)
        XCTAssertFalse(summary.contains("\u{001B}"), "escape sequences must never reach a notification")
        XCTAssertFalse(summary.contains("\u{202E}"), "bidi overrides must never reach a notification")
        XCTAssertLessThanOrEqual(summary.count, 100)
    }

    func testNoSummaryOrErrorIsComputedWhileWorking() {
        let rows = ["error: boom", "✻ Thinking… (1s)"] + promptBox(" > ")
        let reading = TerminalStatusClassifier.evaluate(tailLines: rows)

        XCTAssertNil(reading.summary)
        XCTAssertFalse(reading.hadError, "errors only matter when a task has finished")
    }

    func testErrorPatternsAndSymbolsAreDetected() {
        XCTAssertTrue(TerminalStatusClassifier.detectError(in: ["  error: cannot find module"]))
        XCTAssertTrue(TerminalStatusClassifier.detectError(in: ["3 tests failed"]))
        XCTAssertTrue(TerminalStatusClassifier.detectError(in: ["bash: permission denied"]))
        XCTAssertTrue(TerminalStatusClassifier.detectError(in: ["\u{2717} build"]), "leading ✗ marks a failure")
        XCTAssertFalse(TerminalStatusClassifier.detectError(in: ["\u{2713} build"]), "leading ✓ is a success")
        XCTAssertFalse(TerminalStatusClassifier.detectError(in: ["", "   ", "all good"]))
    }

    func testErrorSymbolOnlyCountsAtTheStartOfTheLine() {
        XCTAssertFalse(TerminalStatusClassifier.detectError(in: ["the ✗ glyph is documented here"]))
    }

    // MARK: - Tail slicing

    func testTextAboveTheSeparatorExcludesThePromptBox() {
        let rows = ["● Done."] + promptBox(" > secret typing")
        let (visible, full) = TerminalStatusClassifier.texts(fromTail: rows)

        XCTAssertEqual(visible, "● Done.")
        XCTAssertTrue(full.contains("secret typing"))
    }

    /// The split happens at the LAST rule in the tail, so when the prompt is
    /// drawn as a fully bordered box its content lands in the visible text.
    func testABorderedPromptBoxPutsItsContentInTheVisibleText() {
        let rows = ["● All done.", rule, " > Interrupted", rule]
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .interrupted)
    }

    func testWithoutASeparatorEverythingIsVisible() {
        let rows = ["$ ls", "a.txt", "b.txt"]
        let (visible, full) = TerminalStatusClassifier.texts(fromTail: rows)

        XCTAssertEqual(visible, full)
        XCTAssertEqual(visible, "$ ls\na.txt\nb.txt")
    }

    func testRelevantTextDropsBlankRowsAndKeepsTheLastTwenty() {
        let lines = (1...30).map { "line \($0)" } + ["   ", "        "]
        let text = TerminalStatusClassifier.relevantText(from: lines)

        XCTAssertEqual(text.components(separatedBy: "\n").count, 20)
        XCTAssertTrue(text.hasPrefix("line 11"))
        XCTAssertTrue(text.hasSuffix("line 30"))
    }

    func testEmptyBufferIsIdleWithNoSummary() {
        let reading = TerminalStatusClassifier.evaluate(tailLines: [])
        XCTAssertEqual(reading.status, .idle)
        XCTAssertNil(reading.summary)
    }

    // MARK: - Claude detection

    func testClaudeIsDetectedFromItsPromptGlyphOrStatusLine() {
        XCTAssertTrue(TerminalStatusClassifier.looksLikeClaudeCode(lines: ["\u{276F} "]))
        XCTAssertTrue(TerminalStatusClassifier.looksLikeClaudeCode(lines: ["  ✻ Thinking… (1s)"]))
        XCTAssertTrue(TerminalStatusClassifier.looksLikeClaudeCode(lines: ["  Esc to cancel"]))
        XCTAssertFalse(TerminalStatusClassifier.looksLikeClaudeCode(lines: ["user@mac ~ %", "$ ls"]))
    }

    // MARK: - opencode

    /// opencode paints its busy line as `<braille frame> <label>`; frames and
    /// labels come from `packages/tui/src/component/spinner.tsx` and the
    /// tool display titles of the TUI (v1.18.x).
    func testOpenCodeSpinnerWithKnownLabelMeansWorking() {
        let rows = ["⠹ Thinking", "", "Ask anything... \"plan the work\""]
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .working)
    }

    func testOpenCodeToolLabelsMeanWorking() {
        for line in ["⠸ Edit src/main.ts", "⠼ Shell command", "⠦ Grep \"pattern\"", "⠏ Thinking: refactor auth"] {
            XCTAssertTrue(TerminalStatusClassifier.hasOpenCodeSpinnerLine(line), "\(line) should read as busy")
        }
    }

    func testBareBrailleWithoutOpencodeLabelIsNotWorking() {
        // A README or a yarn progress bar can paint braille; without one of
        // opencode's own labels that must stay idle.
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: ["⠋ Loading assets..."]).status, .idle)
        XCTAssertFalse(TerminalStatusClassifier.hasOpenCodeSpinnerLine("⠋ random output"))
        XCTAssertFalse(TerminalStatusClassifier.hasOpenCodeSpinnerLine("⠹Thinking"))
    }

    func testOpenCodePermissionDialogMeansWaitingForInput() {
        let rows = [
            "  Permission required",
            "  ❯ Allow once   Allow always   Reject"
        ]
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .waitingForInput)
    }

    func testAllowOnceAndRejectTogetherMeansWaitingEvenWithoutHeader() {
        let rows = ["  Allow once", "  Allow always", "  Reject"]
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .waitingForInput)
    }

    func testOpenCodeInterruptedMarkerIsRecognised() {
        let rows = ["You said something · interrupted", "Ask anything... \"tip\""]
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .interrupted)
    }

    func testIdleOpenCodeScreenIsIdle() {
        let rows = ["Done with the task.", "Ask anything... \"tip\""]
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .idle)
    }

    func testOpenCodeQuestionDialogMeansWaitingForInput() {
        let rows = [
            "  Which database should we use?",
            "  ❯ Postgres",
            "    SQLite",
            "  ↑↓ select   enter submit   esc dismiss"
        ]
        XCTAssertEqual(TerminalStatusClassifier.evaluate(tailLines: rows).status, .waitingForInput)
    }

    func testQuestionFooterNeedsBothTheEscapeAndAnActionHint() {
        XCTAssertTrue(TerminalStatusClassifier.hasOpenCodeQuestionFooter("enter confirm  esc dismiss"))
        XCTAssertTrue(TerminalStatusClassifier.hasOpenCodeQuestionFooter("↑↓ select   enter toggle   esc dismiss"))
        XCTAssertFalse(TerminalStatusClassifier.hasOpenCodeQuestionFooter("esc dismiss"))
        XCTAssertFalse(TerminalStatusClassifier.hasOpenCodeQuestionFooter("press esc to dismiss the panel"))
    }

    func testSummaryStopsBeforeOpenCodePromptTip() {
        let reading = TerminalStatusClassifier.evaluate(tailLines: [
            "Migrated the auth module to the new API.",
            "All tests pass.",
            "Ask anything... \"plan the refactor\""
        ])
        XCTAssertEqual(reading.status, .idle)
        XCTAssertEqual(reading.summary, "All tests pass.")
    }

    func testOpenCodeIsDetectedFromPlaceholderOrDialog() {
        XCTAssertTrue(TerminalStatusClassifier.looksLikeOpenCode(lines: ["Ask anything... \"tip\""]))
        XCTAssertTrue(TerminalStatusClassifier.looksLikeOpenCode(lines: ["Permission required"]))
        XCTAssertTrue(TerminalStatusClassifier.looksLikeOpenCode(lines: ["⠹ Thinking"]))
        XCTAssertFalse(TerminalStatusClassifier.looksLikeOpenCode(lines: ["user@mac ~ %"]))
    }

    func testAgentCLIDetectionCoversBothTools() {
        XCTAssertTrue(TerminalStatusClassifier.looksLikeAgentCLI(lines: ["\u{276F} "]))
        XCTAssertTrue(TerminalStatusClassifier.looksLikeAgentCLI(lines: ["Ask anything... \"tip\""]))
        XCTAssertFalse(TerminalStatusClassifier.looksLikeAgentCLI(lines: ["$ ls"]))
    }
}
