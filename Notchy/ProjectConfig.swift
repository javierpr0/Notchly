import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.emac.notchly", category: "ProjectConfig")

/// Per-project configuration loaded from `.notchy.json` in the project root.
///
/// Example `.notchy.json`:
/// ```json
/// {
///   "shell": "/bin/bash",
///   "command": "npm run dev",
///   "env": {
///     "NODE_ENV": "development",
///     "PORT": "3000"
///   }
/// }
/// ```
///
/// `.notchy.json` can launch arbitrary shells, set environment variables, and
/// run arbitrary commands. Cloning a repo with a malicious `.notchy.json` would
/// otherwise allow code execution as soon as Notchly opens the directory, so
/// each project must be explicitly trusted by the user before its config is
/// applied. Trust is persisted by canonical path; defaults (no .notchy.json)
/// require no prompt.
struct ProjectConfig: Codable {
    var shell: String?
    var command: String?
    var env: [String: String]?

    /// Reads the raw config without applying any trust check. Callers should
    /// only use this when they have already verified the project is trusted
    /// (e.g. via `ProjectTrustStore.loadTrustedConfig(from:)`).
    static func loadRaw(from directory: String) -> ProjectConfig? {
        let path = (directory as NSString).appendingPathComponent(".notchy.json")
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
            return try JSONDecoder().decode(ProjectConfig.self, from: data)
        } catch {
            logger.error("Failed to decode .notchy.json: \(error.localizedDescription)")
            return nil
        }
    }
}

enum ProjectTrustStore {
    private static let trustedKey = "trustedProjectPaths"
    private static let dismissedKey = "dismissedProjectPaths"

    /// Returns the project's config only if the user has trusted it. If a
    /// `.notchy.json` exists but the project is untrusted, prompts the user
    /// once (modally) and persists the answer. Repeated rejections suppress
    /// the prompt.
    @MainActor
    static func loadTrustedConfig(from directory: String) -> ProjectConfig? {
        let path = (directory as NSString).appendingPathComponent(".notchy.json")
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let canonical = canonicalPath(directory)

        if isTrusted(canonical) {
            return ProjectConfig.loadRaw(from: directory)
        }
        if isDismissed(canonical) { return nil }

        // Read the raw config to surface what the user is being asked to trust.
        guard let raw = ProjectConfig.loadRaw(from: directory) else { return nil }

        let alert = NSAlert()
        alert.messageText = "Trust this project's launch config?"
        alert.informativeText = trustPromptBody(for: directory, config: raw)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Trust & Apply")
        alert.addButton(withTitle: "Open Without Config")
        alert.addButton(withTitle: "Don't Ask Again")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            addTrusted(canonical)
            return raw
        case .alertSecondButtonReturn:
            return nil
        case .alertThirdButtonReturn:
            addDismissed(canonical)
            return nil
        default:
            return nil
        }
    }

    static func revokeTrust(for directory: String) {
        let canonical = canonicalPath(directory)
        var trusted = trustedSet()
        trusted.remove(canonical)
        UserDefaults.standard.set(Array(trusted), forKey: trustedKey)
    }

    private static func canonicalPath(_ directory: String) -> String {
        let url = URL(fileURLWithPath: directory).standardizedFileURL
        return url.resolvingSymlinksInPath().path
    }

    private static func trustedSet() -> Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: trustedKey) ?? []))
    }

    private static func dismissedSet() -> Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []))
    }

    private static func isTrusted(_ canonical: String) -> Bool {
        trustedSet().contains(canonical)
    }

    private static func isDismissed(_ canonical: String) -> Bool {
        dismissedSet().contains(canonical)
    }

    private static func addTrusted(_ canonical: String) {
        var trusted = trustedSet()
        trusted.insert(canonical)
        UserDefaults.standard.set(Array(trusted), forKey: trustedKey)
    }

    private static func addDismissed(_ canonical: String) {
        var dismissed = dismissedSet()
        dismissed.insert(canonical)
        UserDefaults.standard.set(Array(dismissed), forKey: dismissedKey)
    }

    private static func trustPromptBody(for directory: String, config: ProjectConfig) -> String {
        var lines = ["Project: \(directory)"]
        if let shell = config.shell { lines.append("Shell: \(shell)") }
        if let command = config.command { lines.append("Command: \(command)") }
        if let env = config.env, !env.isEmpty {
            let preview = env.keys.sorted().prefix(5).joined(separator: ", ")
            lines.append("Env: \(preview)\(env.count > 5 ? ", …" : "")")
        }
        lines.append("")
        lines.append("Untrusted .notchy.json files can run arbitrary code. Only trust projects you wrote or audited.")
        return lines.joined(separator: "\n")
    }
}
