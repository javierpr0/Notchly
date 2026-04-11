import AppKit
import Foundation

@MainActor
enum FullDiskAccessChecker {
    private static let dismissedKey = "fdaDismissed"

    /// Attempts to detect whether the app has Full Disk Access by trying to
    /// read a TCC-protected location. Returns true if access seems granted.
    static func hasFullDiskAccess() -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // These paths require Full Disk Access on modern macOS.
        // If any of them is readable, we assume FDA is granted.
        let protectedPaths = [
            home.appendingPathComponent("Library/Safari/Bookmarks.plist").path,
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path,
            home.appendingPathComponent("Library/Mail").path,
        ]

        for path in protectedPaths {
            if fm.isReadableFile(atPath: path) {
                return true
            }
            // If the file doesn't exist at all we can't conclude either way.
            if !fm.fileExists(atPath: path) { continue }
            return false
        }
        // All paths either didn't exist or were unreadable. Assume granted to
        // avoid showing the dialog on stripped-down systems.
        return true
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
        guard !userDismissed else { return }
        guard !hasFullDiskAccess() else { return }

        // Delay slightly so it doesn't block app launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showDialog()
        }
    }

    /// Always shows the dialog (used from the settings menu).
    static func showDialog() {
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
            openSystemSettings()
        case .alertThirdButtonReturn:
            setDismissed()
        default:
            break
        }
    }
}
