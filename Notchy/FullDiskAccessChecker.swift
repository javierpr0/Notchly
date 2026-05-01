import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.notchly", category: "FullDiskAccess")

@MainActor
enum FullDiskAccessChecker {
    private static let dismissedKey = "fdaDismissed"

    /// Tracks the last detection result. macOS does not refresh the TCC
    /// context for a running process when the user grants Full Disk Access,
    /// so we have to actually attempt a read each time we want to know
    /// (cheap) and re-check when the app regains focus.
    private static var cachedResult: Bool?
    /// Set when the user has chosen "Open Settings"; if we come back to the
    /// app and detection still says "no FDA", we know the user actually
    /// went through the flow and just needs a restart for it to take effect.
    private static var awaitingPermissionGrant: Bool = false
    private static var didInstallActiveObserver = false

    /// Detects FDA by attempting to actually read TCC-protected files.
    /// `isReadableFile(atPath:)` lies under TCC — protected paths may report
    /// as non-existent rather than non-readable — so a real read is the only
    /// reliable signal.
    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Paths that ALWAYS require FDA to read for the current user, in
        // order of how reliable they are as a signal:
        // 1. user-level TCC.db: present on every macOS install since 10.14
        // 2. Safari Bookmarks.plist: present whenever Safari has run
        // 3. Mail directory: present whenever Mail has run
        let candidates: [URL] = [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            home.appendingPathComponent("Library/Mail"),
        ]

        for url in candidates {
            switch probeReadable(at: url) {
            case .readable:
                return true
            case .denied:
                return false
            case .notPresent:
                continue
            }
        }

        // Every candidate was missing (extremely unusual — TCC.db is built
        // into macOS). Treat as granted to avoid pestering the user on
        // stripped systems.
        return true
    }

    private enum ProbeResult {
        case readable
        case denied
        case notPresent
    }

    private static func probeReadable(at url: URL) -> ProbeResult {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            // For directories, attempt a listing — that's the operation that
            // actually goes through TCC.
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
                return .readable
            } catch let error as NSError {
                return classify(error, exists: exists)
            }
        }

        if !exists {
            // Under TCC, fileExists may report `false` for protected files
            // we can't see. Try a read anyway — if we get back an
            // EPERM/EACCES, the file IS there but we lack permission.
            return probeFileRead(at: url, knownExists: false)
        }

        return probeFileRead(at: url, knownExists: true)
    }

    private static func probeFileRead(at url: URL, knownExists: Bool) -> ProbeResult {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
            return .readable
        } catch let error as NSError {
            return classify(error, exists: knownExists)
        }
    }

    private static func classify(_ error: NSError, exists: Bool) -> ProbeResult {
        // Foundation maps EPERM/EACCES to NSFileReadNoPermissionError.
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileReadNoPermissionError:
                return .denied
            case NSFileReadNoSuchFileError:
                return .notPresent
            default:
                break
            }
        }
        if error.domain == NSPOSIXErrorDomain {
            if error.code == Int(EACCES) || error.code == Int(EPERM) { return .denied }
            if error.code == Int(ENOENT) { return .notPresent }
        }
        // Unknown error: if we already saw the file exist, treat as denied;
        // otherwise treat as missing so we try the next candidate.
        return exists ? .denied : .notPresent
    }

    /// Has the user chosen to never be asked again?
    static var userDismissed: Bool {
        UserDefaults.standard.bool(forKey: dismissedKey)
    }

    static func setDismissed() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    static func resetDismissal() {
        UserDefaults.standard.set(false, forKey: dismissedKey)
    }

    /// Opens System Settings directly to the Full Disk Access panel.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Shows the permission dialog if the user hasn't dismissed it and FDA is not granted.
    static func promptIfNeeded() {
        installActiveObserverIfNeeded()
        guard !userDismissed else { return }
        let granted = hasFullDiskAccess()
        cachedResult = granted
        guard !granted else { return }

        // Delay slightly so it doesn't block app launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showDialog()
        }
    }

    /// Re-detect when the app regains focus. If the user just came back from
    /// System Settings and FDA is now visible to us, mark the cached state
    /// granted (no further prompts). If they came back and we STILL can't
    /// see protected files, the permission was probably granted but the TCC
    /// context for this process has not refreshed — offer a restart instead
    /// of looping the same prompt.
    private static func installActiveObserverIfNeeded() {
        guard !didInstallActiveObserver else { return }
        didInstallActiveObserver = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handleAppBecameActive()
            }
        }
    }

    private static func handleAppBecameActive() {
        let granted = hasFullDiskAccess()
        defer { cachedResult = granted }

        guard awaitingPermissionGrant else { return }
        awaitingPermissionGrant = false

        if granted {
            // Permission visible: stop pestering.
            logger.info("Full Disk Access detected after returning from Settings")
            return
        }

        // User came back from Settings but TCC still reports no access.
        // The most common cause is that the permission was granted while the
        // process was running, and TCC will only honor it for new processes.
        promptRestart()
    }

    private static func promptRestart() {
        let alert = NSAlert()
        alert.messageText = L10n.shared.fdaTitle
        alert.informativeText = "If you just granted Full Disk Access, Notchly needs to restart for the new permission to apply. macOS only refreshes a process's permissions on relaunch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restart Notchly")
        alert.addButton(withTitle: L10n.shared.fdaLater)
        alert.addButton(withTitle: L10n.shared.fdaDontAskAgain)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            relaunchApp()
        case .alertThirdButtonReturn:
            setDismissed()
        default:
            break
        }
    }

    private static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        do {
            try task.run()
        } catch {
            logger.error("Failed to relaunch: \(error.localizedDescription)")
            return
        }
        // Give launch services a moment to spawn the new instance, then quit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    /// Always shows the dialog (used from the settings menu).
    static func showDialog() {
        installActiveObserverIfNeeded()
        let alert = NSAlert()
        alert.messageText = L10n.shared.fdaTitle
        alert.informativeText = L10n.shared.fdaMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.shared.fdaOpenSettings)
        alert.addButton(withTitle: L10n.shared.fdaLater)
        alert.addButton(withTitle: L10n.shared.fdaDontAskAgain)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            awaitingPermissionGrant = true
            openSystemSettings()
        case .alertThirdButtonReturn:
            setDismissed()
        default:
            break
        }
    }
}
