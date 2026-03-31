import Foundation

struct AutocompleteSuggestion {
    let command: String
    let score: Double
}

class AutocompleteEngine {
    static let shared = AutocompleteEngine()
    private let maxSuggestions = 7

    func suggestions(for input: String, in directory: String) -> [AutocompleteSuggestion] {
        guard input.count >= 2 else { return [] }

        let commands = CommandStore.shared.commands(for: directory)
        guard !commands.isEmpty else { return [] }

        let lowercasedInput = input.lowercased()

        var scored: [AutocompleteSuggestion] = []

        for cmd in commands {
            // Skip exact matches
            guard cmd.text != input else { continue }

            let lowercasedCmd = cmd.text.lowercased()
            var score: Double = 0

            if lowercasedCmd.hasPrefix(lowercasedInput) {
                // Exact prefix match — highest base score
                score = 100
            } else if fuzzyMatch(query: lowercasedInput, target: lowercasedCmd) {
                // Fuzzy match — lower base score
                score = 40
            } else {
                continue
            }

            // Frequency bonus (log scale to avoid domination)
            score += min(log2(Double(cmd.count) + 1) * 5, 30)

            // Recency bonus
            let daysSinceUse = Date().timeIntervalSince(cmd.lastUsed) / 86400
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

    private func fuzzyMatch(query: String, target: String) -> Bool {
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
