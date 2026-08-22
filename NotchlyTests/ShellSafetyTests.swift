import XCTest

@MainActor
final class ShellSafetyTests: XCTestCase {

    // MARK: - Text entering the shell

    func testEscapeWrapsThePathInSingleQuotes() {
        XCTAssertEqual(ShellSafety.escape("/Users/me/proj"), "'/Users/me/proj'")
    }

    func testEscapeNeutralisesShellMetacharacters() {
        XCTAssertEqual(ShellSafety.escape("/tmp/a b;rm -rf /"), "'/tmp/a b;rm -rf /'")
        XCTAssertEqual(ShellSafety.escape("/tmp/$(whoami)"), "'/tmp/$(whoami)'")
        XCTAssertEqual(ShellSafety.escape("/tmp/`id`"), "'/tmp/`id`'")
    }

    /// The classic break-out: close the quote, run a command, reopen it.
    func testEscapeClosesAndReopensAroundEmbeddedQuotes() {
        XCTAssertEqual(ShellSafety.escape("/tmp/'; rm -rf /; '"), "'/tmp/'\\''; rm -rf /; '\\'''")
    }

    /// Quoting does not contain control bytes: a newline reaches the line
    /// editor as Enter, so the rest of the path would execute as a command.
    func testEscapeStripsControlBytesBeforeQuoting() {
        let escaped = ShellSafety.escape("/tmp/a\nrm -rf ~\r\u{001B}[31mb")
        XCTAssertEqual(escaped, "'/tmp/arm -rf ~[31mb'")
    }

    func testEscapeDropsNulBytes() {
        // Asserted on the scalars rather than compared as a string: a failure
        // message carrying a raw NUL takes the test runner down with it.
        let scalars = ShellSafety.escape("/tmp/a\u{0000}b").unicodeScalars
        XCTAssertFalse(scalars.contains("\u{0000}"))
        XCTAssertEqual(scalars.count, 9)
    }

    func testStripControlCharactersKeepsPrintableUnicode() {
        XCTAssertEqual(ShellSafety.stripControlCharacters("/tmp/año — ünïcode"), "/tmp/año — ünïcode")
        XCTAssertEqual(ShellSafety.stripControlCharacters("a\u{007F}b"), "ab")
        XCTAssertEqual(ShellSafety.stripControlCharacters("a\tb"), "ab", "tab is a C0 byte and goes too")
    }

    // MARK: - Text leaving the app

    func testSanitizeStripsAnsiSequences() {
        XCTAssertEqual(ShellSafety.sanitizeForDisplay("\u{001B}[1;31mDanger\u{001B}[0m"), "Danger")
        XCTAssertEqual(ShellSafety.sanitizeForDisplay("\u{001B}]0;fake title\u{0007}ok"), "ok")
    }

    func testSanitizeStripsBidiAndZeroWidthSpoofing() {
        // Right-to-left override is how output fakes a different message.
        XCTAssertEqual(ShellSafety.sanitizeForDisplay("safe\u{202E}txt.exe"), "safetxt.exe")
        XCTAssertEqual(ShellSafety.sanitizeForDisplay("a\u{200B}b\u{FEFF}c"), "abc")
    }

    func testSanitizeDropsC0AndC1ControlsButKeepsTabs() {
        XCTAssertEqual(ShellSafety.sanitizeForDisplay("a\nb\rc\u{0000}d"), "abcd")
        XCTAssertEqual(ShellSafety.sanitizeForDisplay("a\u{0085}b\u{009B}c"), "abc")
        XCTAssertEqual(ShellSafety.sanitizeForDisplay("col\tumn"), "col\tumn")
    }

    func testSanitizeLeavesOrdinaryTextAlone() {
        XCTAssertEqual(ShellSafety.sanitizeForDisplay("Añadido el test ✅"), "Añadido el test ✅")
    }

    // MARK: - .notchy.json env gate

    func testLoaderAndPathEnvKeysAreRejected() {
        for key in ["DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "LD_PRELOAD"] {
            XCTAssertFalse(ShellSafety.isSafeEnvKey(key), "\(key) allows code injection into the shell")
        }
        for key in ["PATH", "SHELL", "HOME", "USER", "LOGNAME", "TMPDIR", "IFS"] {
            XCTAssertFalse(ShellSafety.isSafeEnvKey(key))
        }
    }

    /// A login shell reads these before the user types anything, so allowing
    /// them turns a project config into arbitrary pre-execution.
    func testShellStartupFileHijacksAreRejected() {
        for key in ["ZDOTDIR", "BASH_ENV", "ENV"] {
            XCTAssertFalse(ShellSafety.isSafeEnvKey(key))
        }
    }

    func testOrdinaryProjectEnvKeysAreAllowed() {
        for key in ["NODE_ENV", "PORT", "DATABASE_URL", "MY_DYLD", "PATH_PREFIX"] {
            XCTAssertTrue(ShellSafety.isSafeEnvKey(key))
        }
    }

    // MARK: - .notchy.json shell gate

    func testOnlyShellsInStandardDirectoriesAreAccepted() {
        XCTAssertTrue(ShellSafety.isAllowedShellPath("/bin/zsh"))
        XCTAssertTrue(ShellSafety.isAllowedShellPath("/usr/local/bin/fish"))
        XCTAssertTrue(ShellSafety.isAllowedShellPath("/opt/homebrew/bin/nu"))

        XCTAssertFalse(ShellSafety.isAllowedShellPath("/tmp/evil"))
        XCTAssertFalse(ShellSafety.isAllowedShellPath("~/evil"))
        XCTAssertFalse(ShellSafety.isAllowedShellPath("zsh"), "a bare name would resolve through PATH")
    }

    func testShellPathTraversalAndNulBytesAreRejected() {
        XCTAssertFalse(ShellSafety.isAllowedShellPath("/bin/../tmp/evil"))
        XCTAssertFalse(ShellSafety.isAllowedShellPath("/bin/zsh\u{0000}/../../tmp/evil"))
    }

    // MARK: - OSC 7

    private let localNames: Set<String> = ["mac-de-eduardo.local", "mac-de-eduardo"]

    func testOsc7AcceptsLocalFileURLsAndBareAbsolutePaths() {
        XCTAssertEqual(ShellSafety.osc7Path(from: "file:///Users/me/proj", localHostNames: localNames), "/Users/me/proj")
        XCTAssertEqual(ShellSafety.osc7Path(from: "file://localhost/Users/me", localHostNames: localNames), "/Users/me")
        XCTAssertEqual(ShellSafety.osc7Path(from: "file://mac-de-eduardo.local/Users/me", localHostNames: localNames), "/Users/me")
        XCTAssertEqual(ShellSafety.osc7Path(from: "/Users/me/proj", localHostNames: localNames), "/Users/me/proj")
    }

    /// Any program in the terminal can emit OSC 7; a remote host means the
    /// path is not ours to adopt as a working directory.
    func testOsc7RejectsForeignHosts() {
        XCTAssertNil(ShellSafety.osc7Path(from: "file://evil.example.com/etc", localHostNames: localNames))
        XCTAssertNil(ShellSafety.osc7Path(from: "file://192.168.1.50/etc", localHostNames: localNames))
    }

    func testOsc7RejectsNonFileSchemesAndRelativePaths() {
        XCTAssertNil(ShellSafety.osc7Path(from: "http://example.com/x", localHostNames: localNames))
        XCTAssertNil(ShellSafety.osc7Path(from: "../../etc", localHostNames: localNames))
        XCTAssertNil(ShellSafety.osc7Path(from: "", localHostNames: localNames))
    }

    func testOsc7DecodesPercentEscapedPaths() {
        XCTAssertEqual(ShellSafety.osc7Path(from: "file:///Users/me/my%20proj", localHostNames: localNames),
                       "/Users/me/my proj")
    }
}
