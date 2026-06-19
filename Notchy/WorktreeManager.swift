import Foundation
import os

private let logger = Logger(subsystem: "com.notchly", category: "WorktreeManager")

enum WorktreeError: LocalizedError {
    case notAGitRepo
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepo: return "Directory is not inside a git repository"
        case .gitFailed(let msg): return "Git error: \(msg)"
        }
    }
}

struct WorktreeHandle {
    let path: String
    let branch: String
    let repoRoot: String
}

/// Creates and tears down git worktrees so a tab can run an isolated copy of a
/// repo (parallel Claude sessions without fighting over one working tree).
final class WorktreeManager {
    static let shared = WorktreeManager()

    /// ~/.notchly/worktrees — where all Notchly-created worktrees live.
    private var storeRoot: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".notchly/worktrees")
    }

    // ponytail: git runner duplicated from CheckpointManager. Extract a shared
    // GitRunner only if a third caller shows up.
    private lazy var gitPath: String = {
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for dir in envPath.split(separator: ":").map(String.init) {
                let candidate = (dir as NSString).appendingPathComponent("git")
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/usr/bin/git"
    }()

    @discardableResult
    private func git(_ args: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw WorktreeError.gitFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    /// Top level of the repo that contains `directory`, or nil if not a repo.
    func repoRoot(for directory: String) -> String? {
        try? git(["rev-parse", "--show-toplevel"], in: directory)
    }

    /// Creates a worktree off the current HEAD of the repo containing `directory`.
    /// Branch: `notchly/<name>-<6hex>`, checked out at `~/.notchly/worktrees/<repo>/<name>-<6hex>`.
    func createWorktree(forRepoAt directory: String, name: String) throws -> WorktreeHandle {
        guard let root = repoRoot(for: directory) else { throw WorktreeError.notAGitRepo }

        let base = { () -> String in
            let s = CheckpointManager.sanitizeRefComponent(name)
            return s.isEmpty ? "wt" : s
        }()
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        let leaf = "\(base)-\(suffix)"
        let branch = "notchly/\(leaf)"

        let repoName = CheckpointManager.sanitizeRefComponent((root as NSString).lastPathComponent)
        let parent = (storeRoot as NSString).appendingPathComponent(repoName.isEmpty ? "repo" : repoName)
        let path = (parent as NSString).appendingPathComponent(leaf)
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)

        try git(["worktree", "add", path, "-b", branch], in: root)
        return WorktreeHandle(path: path, branch: branch, repoRoot: root)
    }

    /// True when the worktree has uncommitted changes — used to warn before discard.
    func hasUncommittedChanges(at path: String) -> Bool {
        guard let out = try? git(["status", "--porcelain"], in: path) else { return false }
        return !out.isEmpty
    }

    /// Removes the worktree and deletes its branch. Best-effort; failures are logged.
    func discardWorktree(repoRoot: String, path: String, branch: String) {
        do { try git(["worktree", "remove", "--force", path], in: repoRoot) }
        catch { logger.warning("worktree remove failed: \(error.localizedDescription, privacy: .public)") }
        do { try git(["branch", "-D", branch], in: repoRoot) }
        catch { logger.warning("branch delete failed: \(error.localizedDescription, privacy: .public)") }
    }
}
