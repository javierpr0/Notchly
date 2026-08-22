import Foundation

/// String-level security gates for everything that crosses into the shell,
/// the notification centre, or a spawned process's environment.
///
/// Every function here is pure so the rules can be asserted directly. The
/// filesystem-dependent halves (does this shell exist, is this path really a
/// directory) stay in `TerminalManager`, which composes them with these checks.
enum ShellSafety {

    // MARK: - Text leaving the terminal

    // Compiled once — sanitizeForDisplay runs on every status evaluation.
    private static let csiRegex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]")
    private static let oscRegex = try? NSRegularExpression(pattern: "\u{001B}\\][^\u{0007}\u{001B}]*[\u{0007}\u{001B}]")

    /// Removes ANSI escape sequences, control characters, and bidi-override
    /// codepoints so terminal output cannot spoof or break notification text.
    static func sanitizeForDisplay(_ input: String) -> String {
        var stripped = input
        // Strip CSI escape sequences (ESC [ ... letter)
        if let regex = csiRegex {
            let range = NSRange(stripped.startIndex..., in: stripped)
            stripped = regex.stringByReplacingMatches(in: stripped, range: range, withTemplate: "")
        }
        // Strip OSC sequences (ESC ] ... BEL/ST)
        if let regex = oscRegex {
            let range = NSRange(stripped.startIndex..., in: stripped)
            stripped = regex.stringByReplacingMatches(in: stripped, range: range, withTemplate: "")
        }
        // Drop control + bidi override + zero-width characters.
        let blocked: Set<Unicode.Scalar> = [
            "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}",
            "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"
        ]
        let scalars = stripped.unicodeScalars.filter { scalar in
            if blocked.contains(scalar) { return false }
            // Allow tab and printable; drop other control codes
            if scalar.value < 0x20 && scalar != "\t" { return false }
            // DEL + C1 controls (U+007F–U+009F): U+0085 NEL and U+009B CSI are
            // treated as line/escape introducers by some renderers, so a hostile
            // program could spoof or break the notification line. Drop the range.
            if scalar.value >= 0x7F && scalar.value <= 0x9F { return false }
            return true
        }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - Text entering the shell

    /// Removes C0 control bytes (0x00–0x1F) and DEL (0x7F) from a string.
    /// Single-quote escaping neutralizes shell metacharacters but NOT control
    /// bytes: a newline/CR embedded in a path is delivered to the interactive
    /// shell's line editor as an Enter keypress, and an ESC byte can inject a
    /// terminal control sequence — neither is contained by quoting. Any path
    /// that reaches `send(txt:)` must be stripped first.
    static func stripControlCharacters(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F })
    }

    /// Sanitizes clipboard text before it reaches `send(txt:)`. Like paths,
    /// clipboard content is attacker-influenced (a web page can put anything
    /// on the pasteboard), so ESC bytes that would inject terminal control
    /// sequences are stripped. Unlike paths, newlines and tabs are preserved:
    /// multiline paste is a legitimate workflow — each newline behaves like
    /// pressing Enter, exactly as if the user had typed it.
    static func sanitizePastedText(_ s: String) -> String {
        String(s.unicodeScalars.filter { scalar in
            if scalar == "\n" || scalar == "\t" { return true }
            return scalar.value >= 0x20 && !(0x7F...0x9F).contains(scalar.value)
        })
    }

    /// Single-quotes a path for an interactive shell, closing and reopening the
    /// quote around each embedded quote (`'\''`).
    static func escape(_ path: String) -> String {
        "'" + stripControlCharacters(path).replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - .notchy.json gates

    /// Standard directories where a shell binary is acceptable. A `.notchy.json`
    /// pointing to anything outside these (e.g. `/tmp/evil`) is rejected.
    static let allowedShellDirectories: [String] = [
        "/bin/", "/usr/bin/", "/usr/local/bin/", "/opt/homebrew/bin/"
    ]

    /// Env keys that influence process loading or critical paths — never let
    /// a project config override these.
    private static let blockedEnvKeys: Set<String> = [
        "PATH", "SHELL", "HOME", "USER", "LOGNAME", "TMPDIR", "IFS",
        // Shell startup-file hijacks: a login shell reads these BEFORE any
        // command is typed, so allowing them turns a project's env config into
        // arbitrary pre-execution (e.g. ZDOTDIR → $ZDOTDIR/.zshenv).
        "ZDOTDIR", "BASH_ENV", "ENV"
    ]
    private static let blockedEnvPrefixes: [String] = ["DYLD_", "LD_"]

    static func isSafeEnvKey(_ key: String) -> Bool {
        if blockedEnvKeys.contains(key) { return false }
        if blockedEnvPrefixes.contains(where: { key.hasPrefix($0) }) { return false }
        return true
    }

    /// Path-shape half of the shell gate. The caller still has to confirm the
    /// binary is executable on disk.
    static func isAllowedShellPath(_ path: String) -> Bool {
        guard !path.contains(".."), !path.contains("\0") else { return false }
        return allowedShellDirectories.contains(where: { path.hasPrefix($0) })
    }

    // MARK: - OSC 7

    /// Parses an OSC 7 payload into a candidate directory path, rejecting any
    /// URL that points at another machine. OSC 7 is emitted by any program in
    /// the terminal, so a hostile script could otherwise pivot the working
    /// directory (and with it command-store scope, autocomplete and file
    /// lookups) to an arbitrary location. The caller must still confirm the
    /// path exists and is a directory.
    static func osc7Path(from raw: String, localHostNames: Set<String>) -> String? {
        if let url = URL(string: raw), url.scheme?.lowercased() == "file" {
            let host = url.host?.lowercased() ?? ""
            if !host.isEmpty,
               host != "localhost",
               host != "127.0.0.1",
               !localHostNames.contains(host) {
                return nil
            }
            return url.path
        }
        // A bare absolute path is what shells emit when they skip the URL form.
        if raw.hasPrefix("/") { return raw }
        return nil
    }
}
