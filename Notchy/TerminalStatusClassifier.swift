import Foundation

/// Turns the tail of the terminal buffer into a `TerminalStatus`.
///
/// This heuristic keys off Claude Code's on-screen copy (spinner glyphs, the
/// token-counter line, "Esc to cancel"), which makes it the most fragile
/// surface in the app: a wording change upstream silently breaks every
/// notification, the notch pill and idle-sleep prevention. Kept free of
/// AppKit/SwiftTerm so it can be driven directly from tests with canned rows.
enum TerminalStatusClassifier {

    /// Claude draws this rule between its output and the prompt box. Everything
    /// above it is "what Claude said"; the box below is chrome.
    static let separator = "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"

    private static let spinnerCharacters: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽"]
    private static let errorPatterns: [String] = ["error:", "failed", "permission denied"]
    private static let errorSymbols: Set<Character> = ["\u{2717}", "\u{2718}"]

    /// detectError only ever needs to look at the bottom of the scanned tail.
    static let errorScanRows = 25

    struct Reading: Equatable {
        var status: TerminalStatus
        /// Last visible line, sanitized — used as the notification body.
        /// Only computed for `.idle`, since that is the only state that can
        /// promote to `.taskCompleted`.
        var summary: String?
        var hadError: Bool
    }

    /// Single entry point used by the terminal view: one pass over the tail
    /// rows produces the status plus everything the notification needs.
    static func evaluate(tailLines: [String]) -> Reading {
        let (visible, full) = texts(fromTail: tailLines)
        let status = classify(visibleText: visible, fullText: full)
        guard status == .idle else {
            return Reading(status: status, summary: nil, hadError: false)
        }
        return Reading(
            status: status,
            summary: extractSummary(from: visible),
            hadError: detectError(in: tailLines.suffix(errorScanRows))
        )
    }

    /// Splits the scanned tail into the text above the prompt separator
    /// (`visible`) and the whole tail (`full`). "Esc to cancel" and
    /// "esc to interrupt" live inside the prompt box, below the separator,
    /// so they are only ever found in `full`.
    static func texts(fromTail tailLines: [String]) -> (visible: String, full: String) {
        let aboveSeparator: [String]
        if let idx = tailLines.lastIndex(where: { $0.contains(separator) }) {
            aboveSeparator = Array(tailLines.prefix(idx))
        } else {
            aboveSeparator = tailLines
        }
        return (relevantText(from: aboveSeparator), relevantText(from: tailLines))
    }

    /// Last 20 non-blank lines, joined by newlines.
    static func relevantText(from lines: [String]) -> String {
        let nonBlankLines = lines.filter { !$0.allSatisfy({ $0 == " " }) }
        return nonBlankLines.suffix(20).joined(separator: "\n")
    }

    static func classify(visibleText: String, fullText: String) -> TerminalStatus {
        if hasTokenCounterLine(visibleText) || fullText.contains("esc to interrupt") {
            return .working
        }
        if fullText.contains("Esc to cancel") { return .waitingForInput }
        if visibleText.contains("Interrupted") { return .interrupted }
        return .idle
    }

    /// A Claude status line looks like `✻ Thinking… (12s · ↑ 1.2k tokens)`:
    /// spinner glyph, space, and an ellipsis somewhere after it.
    static func hasTokenCounterLine(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.contains { line in
            guard let first = line.first, spinnerCharacters.contains(first) else { return false }
            guard line.dropFirst().first == " " else { return false }
            return line.contains("…")
        }
    }

    static func extractSummary(from text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(separator) }
        guard let last = lines.last else { return nil }
        // Notifications display whatever appeared on the last visible line,
        // which is attacker-controllable (any program in the terminal can emit
        // bidi overrides / control chars / arbitrary unicode). Strip control
        // and bidi characters before letting the text leave the app.
        return ShellSafety.sanitizeForDisplay(String(last.prefix(100)))
    }

    static func detectError<S: Sequence>(in lines: S) -> Bool where S.Element == String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            for pattern in errorPatterns where lower.contains(pattern) { return true }
            if let first = trimmed.first, errorSymbols.contains(first) { return true }
        }
        return false
    }

    /// True when the visible rows look like an active Claude Code session
    /// rather than a bare shell prompt.
    static func looksLikeClaudeCode(lines: [String]) -> Bool {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("\u{276F}") { return true }
            if hasTokenCounterLine(trimmed) { return true }
            if trimmed.contains("Esc to cancel") || trimmed.contains("esc to interrupt") { return true }
        }
        return false
    }
}
