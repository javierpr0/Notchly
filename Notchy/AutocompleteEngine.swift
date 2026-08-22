import Foundation

class AutocompleteEngine {
    static let shared = AutocompleteEngine()

    /// Only ever touched from TerminalManager's serial autocomplete queue, so
    /// the ranker's lowercase cache stays single-threaded.
    private let ranker = AutocompleteRanker()

    func suggestions(for input: String, in directory: String) -> [AutocompleteSuggestion] {
        guard input.count >= 2 else { return [] }
        return ranker.rank(input: input, commands: CommandStore.shared.commands(for: directory))
    }
}
