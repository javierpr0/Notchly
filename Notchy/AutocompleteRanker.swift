import Foundation

struct AutocompleteSuggestion: Equatable {
    let command: String
    let score: Double
}

/// Ranks stored commands against what the user has typed. Split out from
/// `AutocompleteEngine` so the scoring can be exercised with a fixed command
/// list and a fixed `now`, without touching CommandStore's disk-backed cache.
final class AutocompleteRanker {
    let maxSuggestions: Int

    init(maxSuggestions: Int = 7) {
        self.maxSuggestions = maxSuggestions
    }

    /// Caches lowercased forms of command strings so the per-keystroke loop
    /// doesn't reallocate them. Bounded by the universe of unique commands
    /// the user has ever seen (~hundreds), so unbounded growth is not a concern.
    private var lowercasedCache: [String: String] = [:]

    private func lowercased(_ source: String) -> String {
        if let cached = lowercasedCache[source] { return cached }
        let lc = source.lowercased()
        lowercasedCache[source] = lc
        return lc
    }

    func rank(input: String, commands: [StoredCommand], now: Date = Date()) -> [AutocompleteSuggestion] {
        guard input.count >= 2, !commands.isEmpty else { return [] }

        let lowercasedInput = input.lowercased()
        var scored: [AutocompleteSuggestion] = []

        for cmd in commands {
            // Skip exact matches
            guard cmd.text != input else { continue }

            let lowercasedCmd = lowercased(cmd.text)
            var score: Double = 0

            if lowercasedCmd.hasPrefix(lowercasedInput) {
                // Exact prefix match — highest base score
                score = 100
            } else if Self.fuzzyMatch(query: lowercasedInput, target: lowercasedCmd) {
                // Fuzzy match — lower base score
                score = 40
            } else {
                continue
            }

            // Frequency bonus (log scale to avoid domination)
            score += min(log2(Double(cmd.count) + 1) * 5, 30)

            // Recency bonus
            let daysSinceUse = now.timeIntervalSince(cmd.lastUsed) / 86400
            if daysSinceUse < 1 {
                score += 20
            } else if daysSinceUse < 7 {
                score += 10
            } else if daysSinceUse < 30 {
                score += 5
            }

            // Shorter commands slightly preferred (less noise)
            score -= Double(cmd.text.count) * 0.1

            scored.append(AutocompleteSuggestion(command: cmd.text, score: score))
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(maxSuggestions))
    }

    /// Subsequence match: every character of `query` appears in `target`, in
    /// order, not necessarily adjacent.
    static func fuzzyMatch(query: String, target: String) -> Bool {
        var queryIdx = query.startIndex
        var targetIdx = target.startIndex

        while queryIdx < query.endIndex && targetIdx < target.endIndex {
            if query[queryIdx] == target[targetIdx] {
                queryIdx = query.index(after: queryIdx)
            }
            targetIdx = target.index(after: targetIdx)
        }

        return queryIdx == query.endIndex
    }
}
