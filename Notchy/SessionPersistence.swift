import Foundation

/// Versioned envelope for the on-disk session store. Bump `currentVersion`
/// and add a migration step in `load` whenever a non-additive shape change
/// ships — otherwise decoding fails wholesale and every tab is lost.
struct PersistedSessionsFile: Codable {
    static let currentVersion = 1

    var version: Int = PersistedSessionsFile.currentVersion
    var sessions: [PersistedSession]
    var activeSessionId: UUID?
}

/// File-backed persistence for sessions, written atomically on every change.
/// Replaces the old UserDefaults blob (a crash could lose up to the whole
/// debounce window plus cfprefsd's async flush). The legacy blob is still
/// readable so existing installs migrate transparently on first launch.
///
/// Pure Foundation: the format and recovery rules are unit-testable.
enum SessionPersistence {

    /// A decoded store ready to be applied to the session list.
    struct Store {
        var sessions: [PersistedSession]
        var activeSessionId: UUID?
    }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchly", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    // MARK: - Saving

    /// Writes the store atomically (temp file + rename) so a crash mid-write
    /// can never leave a half-written blob behind.
    static func save(_ sessions: [PersistedSession], activeSessionId: UUID?,
                     to url: URL = SessionPersistence.fileURL) throws {
        let envelope = PersistedSessionsFile(sessions: sessions, activeSessionId: activeSessionId)
        let data = try JSONEncoder().encode(envelope)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Loading

    /// Loads the store from disk. Returns nil when the file is missing or
    /// undecodable; an undecodable file is first backed up beside itself with
    /// a timestamp instead of being clobbered by the next save.
    static func load(from url: URL = SessionPersistence.fileURL) -> Store? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let envelope = try JSONDecoder().decode(PersistedSessionsFile.self, from: data)
            return applyMigrations(envelope)
        } catch {
            backUpCorruptFile(at: url)
            return nil
        }
    }

    /// Reads the pre-file storage layout (`persistedSessions` data blob +
    /// `activeSessionId` string in UserDefaults). Used as a migration source;
    /// returns nil when nothing was stored there.
    static func legacyStore(in defaults: UserDefaults,
                            sessionsKey: String = "persistedSessions",
                            activeKey: String = "activeSessionId") -> Store? {
        guard let data = defaults.data(forKey: sessionsKey) else { return nil }
        guard let sessions = try? JSONDecoder().decode([PersistedSession].self, from: data) else {
            return nil
        }
        let activeId = defaults.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
        return Store(sessions: sessions, activeSessionId: activeId)
    }

    // MARK: - Migration

    private static func applyMigrations(_ envelope: PersistedSessionsFile) -> Store? {
        switch envelope.version {
        case PersistedSessionsFile.currentVersion:
            let knownIds = Set(envelope.sessions.map(\.id))
            let activeId = envelope.activeSessionId.flatMap { knownIds.contains($0) ? $0 : nil }
            return Store(sessions: envelope.sessions, activeSessionId: activeId ?? envelope.sessions.first?.id)
        default:
            // Future versions: migrate forward step by step here.
            return nil
        }
    }

    private static func backUpCorruptFile(at url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("sessions.corrupt-\(stamp).json")
        try? FileManager.default.copyItem(at: url, to: backupURL)
    }
}
