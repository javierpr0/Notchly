import AppKit
import Foundation

class SessionHistoryManager {
    static let shared = SessionHistoryManager()

    private let baseDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".notchly/history")
    }()

    private let queue = DispatchQueue(label: "com.notchly.SessionHistory")
    private let maxFileSize: UInt64 = 5 * 1024 * 1024
    private let keepSize = 3 * 1024 * 1024
    private static let maxOpenHandles = 8

    /// Long-lived FileHandles keyed by sessionId. Reusing the handle avoids
    /// open/seek/close per chunk during streaming output. Bounded with a
    /// simple FIFO eviction.
    private var openHandles: [UUID: FileHandle] = [:]
    private var handleAccessOrder: [UUID] = []

    private init() {
        try? FileManager.default.createDirectory(
            at: baseDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Enforce restrictive perms even if the directory already existed.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDir.path)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closeAllHandles),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        closeAllHandles()
    }

    func logPath(for sessionId: UUID) -> URL {
        baseDir.appendingPathComponent("\(sessionId.uuidString).log")
    }

    func appendText(_ text: String, for sessionId: UUID) {
        guard !text.isEmpty else { return }
        queue.async { [self] in
            let path = logPath(for: sessionId)
            guard let data = text.data(using: .utf8) else { return }
            let handle = handle(for: sessionId, path: path)
            handle?.seekToEndOfFile()
            handle?.write(data)
            // History contains raw terminal output (which can include API
            // tokens, prompts, file contents). Force 0o600 so other local
            // users on the machine cannot read it.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            rotateIfNeeded(at: path, sessionId: sessionId)
        }
    }

    func readHistory(for sessionId: UUID) -> String {
        let path = logPath(for: sessionId)
        // Flush any buffered writes so reads see the latest data.
        queue.sync { [self] in
            openHandles[sessionId]?.synchronizeFile()
        }
        let raw = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        return Self.stripAnsi(raw)
    }

    func deleteHistory(for sessionId: UUID) {
        queue.async { [self] in
            closeHandle(for: sessionId)
            try? FileManager.default.removeItem(at: logPath(for: sessionId))
        }
    }

    @objc private func closeAllHandles() {
        queue.sync { [self] in
            for handle in openHandles.values {
                try? handle.close()
            }
            openHandles.removeAll()
            handleAccessOrder.removeAll()
        }
    }

    private func handle(for sessionId: UUID, path: URL) -> FileHandle? {
        if let existing = openHandles[sessionId] {
            touchHandle(sessionId)
            return existing
        }
        // Create file with restrictive perms if missing.
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(
                atPath: path.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        guard let handle = try? FileHandle(forWritingTo: path) else { return nil }
        openHandles[sessionId] = handle
        touchHandle(sessionId)
        evictIfNeeded()
        return handle
    }

    private func touchHandle(_ sessionId: UUID) {
        if let idx = handleAccessOrder.firstIndex(of: sessionId) {
            handleAccessOrder.remove(at: idx)
        }
        handleAccessOrder.append(sessionId)
    }

    private func evictIfNeeded() {
        while openHandles.count > Self.maxOpenHandles, let oldest = handleAccessOrder.first {
            handleAccessOrder.removeFirst()
            if let handle = openHandles.removeValue(forKey: oldest) {
                try? handle.close()
            }
        }
    }

    private func closeHandle(for sessionId: UUID) {
        if let handle = openHandles.removeValue(forKey: sessionId) {
            try? handle.close()
        }
        if let idx = handleAccessOrder.firstIndex(of: sessionId) {
            handleAccessOrder.remove(at: idx)
        }
    }

    private func rotateIfNeeded(at path: URL, sessionId: UUID) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let size = attrs[.size] as? UInt64,
              size > maxFileSize else { return }
        guard let data = try? Data(contentsOf: path) else { return }
        let keepFrom = data.count - keepSize
        guard keepFrom > 0 else { return }
        let tail = data.suffix(from: keepFrom)
        guard let nl = tail.firstIndex(of: UInt8(ascii: "\n")) else { return }
        let clean = tail.suffix(from: tail.index(after: nl))

        // Atomic temp+rename: a crash mid-rotation must not lose the log.
        let tmp = path.appendingPathExtension("rotate")
        do {
            try clean.write(to: tmp, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
            // Close the existing handle so replaceItem can rename underneath.
            closeHandle(for: sessionId)
            _ = try? FileManager.default.replaceItemAt(path, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    static func stripAnsi(_ text: String) -> String {
        var result = text
        // CSI sequences: ESC [ ... letter
        result = result.replacingOccurrences(of: "\\x1b\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)
        // OSC sequences: ESC ] ... BEL or ST
        result = result.replacingOccurrences(of: "\\x1b\\][^\u{07}\u{1b}]*[\u{07}]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\x1b\\][^\u{07}\u{1b}]*\\x1b\\\\", with: "", options: .regularExpression)
        // Single ESC + character
        result = result.replacingOccurrences(of: "\\x1b[()][AB012]", with: "", options: .regularExpression)
        // Bare ESC sequences
        result = result.replacingOccurrences(of: "\\x1b[>=]", with: "", options: .regularExpression)
        return result
    }
}
