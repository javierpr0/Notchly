import Foundation

/// Removes files that have not been modified since a cutoff date. Used to
/// garbage-collect per-directory command stores: every directory ever
/// visited seeds its own JSON file, and nothing pruned them before.
///
/// Pure Foundation so the rules are unit-testable.
enum StaleFilePruner {

    /// Returns the JSON files directly inside `directory` whose modification
    /// date is older than `cutoff`, sorted oldest first.
    static func staleJSONFiles(in directory: URL, olderThan cutoff: Date,
                               fileManager: FileManager = .default) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                else { return nil }
                return (url, date)
            }
            .filter { $0.1 < cutoff }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Deletes stale files, returning how many were removed. Failures to
    /// remove are ignored: pruning is opportunistic housekeeping.
    @discardableResult
    static func prune(in directory: URL, olderThan cutoff: Date,
                      fileManager: FileManager = .default) -> Int {
        let stale = staleJSONFiles(in: directory, olderThan: cutoff, fileManager: fileManager)
        for file in stale {
            try? fileManager.removeItem(at: file)
        }
        return stale.count
    }
}
