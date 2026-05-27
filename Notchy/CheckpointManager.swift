import Foundation
import os

private let logger = Logger(subsystem: "com.notchly", category: "CheckpointManager")

struct Checkpoint: Identifiable {
    let id: String          // full ref name
    let date: Date
    let commitHash: String

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM h:mma"
        return formatter.string(from: date)
    }
}

enum CheckpointError: LocalizedError {
    case gitFailed(String)
    case notAGitRepo

    var errorDescription: String? {
        switch self {
        case .gitFailed(let msg): return "Git error: \(msg)"
        case .notAGitRepo: return "Project directory is not a git repository"
        }
    }
}

class CheckpointManager {
    static let shared = CheckpointManager()

    private let refPrefix = "refs/Notchy-snapshots"

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    private lazy var gitPath: String = {
        // Honor the user's PATH first (e.g. asdf, mise, brew shims, custom installs),
        // then fall back to common system locations.
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for dir in envPath.split(separator: ":").map(String.init) {
                let candidate = (dir as NSString).appendingPathComponent("git")
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/usr/bin/git"
    }()

    @discardableResult
    private func git(_ args: [String], in directory: String, environment: [String: String]? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        if let environment {
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { _, new in new }
            process.environment = env
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CheckpointError.gitFailed(errOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    /// Creates a checkpoint by capturing the full working tree as a git commit stored under a custom ref.
    /// Uses a temporary index so the user's staging area is not affected.
    func createCheckpoint(projectName: String, projectDirectory: String) throws {
        // Verify this is a git repo
        _ = try git(["rev-parse", "--git-dir"], in: projectDirectory)

        let safeName = Self.sanitizeRefComponent(projectName)
        guard !safeName.isEmpty else {
            throw CheckpointError.gitFailed("project name produces an invalid git ref")
        }
        let timestamp = dateFormatter.string(from: Date())
        let refName = "\(refPrefix)/\(safeName)/\(timestamp)"

        // Use a temporary index file to avoid disturbing the user's staged changes.
        // Wrap the index in a freshly-created, owner-only directory so a stale
        // file or hostile symlink at the predicted path cannot redirect the write.
        let tempParent = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("Notchy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            atPath: tempParent,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let tempIndex = (tempParent as NSString).appendingPathComponent("index")
        defer {
            do {
                try FileManager.default.removeItem(atPath: tempParent)
            } catch {
                logger.warning("Failed to clean up temp index dir: \(error.localizedDescription)")
            }
        }

        let env = ["GIT_INDEX_FILE": tempIndex]

        // Stage everything into the temp index
        try git(["add", "-A"], in: projectDirectory, environment: env)

        // Write the tree object from the temp index
        let tree = try git(["write-tree"], in: projectDirectory, environment: env)
        guard Self.isValidGitObjectHash(tree) else {
            throw CheckpointError.gitFailed("write-tree returned an invalid object hash: \(tree)")
        }

        // Create a detached commit (no parent) holding the tree
        let commit = try git(["commit-tree", tree, "-m", "Notchy checkpoint \(timestamp)"], in: projectDirectory)
        guard Self.isValidGitObjectHash(commit) else {
            throw CheckpointError.gitFailed("commit-tree returned an invalid object hash: \(commit)")
        }

        // Store the commit under a custom ref
        try git(["update-ref", refName, commit], in: projectDirectory)
    }

    /// Returns true if the directory is inside a git repository
    func isGitRepo(in directory: String) -> Bool {
        (try? git(["rev-parse", "--git-dir"], in: directory)) != nil
    }

    /// Lists all checkpoints for a project, newest first
    func checkpoints(for projectName: String, in projectDirectory: String) -> [Checkpoint] {
        let safeName = Self.sanitizeRefComponent(projectName)
        guard !safeName.isEmpty else { return [] }
        let refPattern = "\(refPrefix)/\(safeName)/"
        guard let output = try? git(
            ["for-each-ref", "--format=%(refname) %(objectname:short)", refPattern],
            in: projectDirectory
        ), !output.isEmpty else {
            return []
        }

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let refName = String(parts[0])
            let hash = String(parts[1])
            // Extract the timestamp portion from the ref name
            guard let lastSlash = refName.lastIndex(of: "/") else { return nil }
            let timestamp = String(refName[refName.index(after: lastSlash)...])
            guard let date = dateFormatter.date(from: timestamp) else { return nil }
            return Checkpoint(id: refName, date: date, commitHash: hash)
        }
        .sorted { $0.date > $1.date }
    }

    /// Restores a checkpoint by checking out all files from its tree into the working directory.
    /// Before doing so, a "before-restore" snapshot is captured automatically so the
    /// user can recover any uncommitted work that the checkout would otherwise overwrite.
    func restoreCheckpoint(_ checkpoint: Checkpoint, to projectDirectory: String) throws {
        // Best-effort safety snapshot. Failures here are logged but do not
        // block the restore — checkpoints are still recoverable from the
        // snapshot ref hierarchy if anything goes wrong.
        let preName = "before-restore"
        do {
            try createCheckpoint(projectName: preName, projectDirectory: projectDirectory)
        } catch {
            logger.warning("Auto-snapshot before restore failed: \(error.localizedDescription)")
        }
        try git(["checkout", checkpoint.commitHash, "--", "."], in: projectDirectory)
    }

    /// Clears all checkpoints for a project by deleting their refs
    func clearCheckpoints(for projectName: String, in projectDirectory: String) {
        let list = checkpoints(for: projectName, in: projectDirectory)
        for checkpoint in list {
            do {
                try git(["update-ref", "-d", checkpoint.id], in: projectDirectory)
            } catch {
                logger.warning("Failed to delete checkpoint ref \(checkpoint.id): \(error.localizedDescription)")
            }
        }
    }

    /// Returns true when the string looks like a git object hash (SHA-1 or SHA-256).
    static func isValidGitObjectHash(_ raw: String) -> Bool {
        let len = raw.count
        guard len == 40 || len == 64 else { return false }
        return raw.allSatisfy { $0.isHexDigit }
    }

    /// Sanitizes a project name so it is safe to embed in a git ref path.
    /// Git ref rules: no spaces, no `:`, `~`, `^`, `?`, `*`, `[`, `\\`, `..`, leading/trailing `/` or `.`,
    /// and components cannot end with `.lock`. We replace anything outside `[A-Za-z0-9._-]` with `_`,
    /// collapse repeats, and trim leading/trailing dots and underscores.
    static func sanitizeRefComponent(_ raw: String) -> String {
        let allowed: Set<Character> = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        var out = ""
        var lastWasUnderscore = false
        for ch in raw {
            if allowed.contains(ch) {
                out.append(ch)
                lastWasUnderscore = false
            } else if !lastWasUnderscore {
                out.append("_")
                lastWasUnderscore = true
            }
        }
        // Trim leading/trailing dots, slashes, underscores
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "._/"))
        // Disallow `..` sequences and the `.lock` suffix
        let collapsed = trimmed.replacingOccurrences(of: "..", with: "_")
        if collapsed.hasSuffix(".lock") {
            return String(collapsed.dropLast(5))
        }
        return collapsed
    }
}
