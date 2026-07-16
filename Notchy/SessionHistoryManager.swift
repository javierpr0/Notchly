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

    /// Coalesced write batching: under heavy terminal output (compiles, npm,
    /// git log) `appendData` is called hundreds of times per second. Issuing
    /// one seek+write per chunk back-pressures the dispatch queue. We buffer
    /// bytes per session and flush either on a short debounce or when the
    /// buffer exceeds `flushBytesThreshold`, whichever comes first.
    private static let flushInterval: DispatchTimeInterval = .milliseconds(250)
    private static let flushBytesThreshold = 32 * 1024

    private struct PendingWrite {
        var data: Data
        var timer: DispatchSourceTimer?
    }
    private var pendingWrites: [UUID: PendingWrite] = [:]

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

    func appendData(_ data: Data, for sessionId: UUID) {
        guard !data.isEmpty else { return }
        queue.async { [self] in
            if pendingWrites[sessionId] != nil {
                // Append in place — pulling the struct out into a local first
                // makes the Data multiply-referenced and forces a full
                // copy-on-write of the accumulated buffer on every chunk.
                pendingWrites[sessionId]!.data.append(data)
                if pendingWrites[sessionId]!.data.count >= Self.flushBytesThreshold {
                    flushPending(for: sessionId)
                }
            } else {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + Self.flushInterval)
                timer.setEventHandler { [weak self] in
                    self?.flushPending(for: sessionId)
                }
                timer.resume()
                pendingWrites[sessionId] = PendingWrite(data: data, timer: timer)
                if data.count >= Self.flushBytesThreshold {
                    flushPending(for: sessionId)
                }
            }
        }
    }

    /// MUST be called on `queue`. Drains the pending buffer for a session
    /// (seek-to-end + one write + chmod + rotate check). Safe to call when
    /// nothing is pending.
    private func flushPending(for sessionId: UUID) {
        guard let pending = pendingWrites.removeValue(forKey: sessionId) else { return }
        pending.timer?.cancel()
        guard !pending.data.isEmpty else { return }
        let path = logPath(for: sessionId)
        let handle = handle(for: sessionId, path: path)
        handle?.seekToEndOfFile()
        handle?.write(pending.data)
        // History contains raw terminal output (which can include API tokens,
        // prompts, file contents). Force 0o600 so other local users on the
        // machine cannot read it.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        rotateIfNeeded(at: path, sessionId: sessionId)
    }

    /// Reads the session log entirely off the main thread. The flush, the up-to
    /// 5 MB file read and the ANSI-stripping regex passes all run on `queue`;
    /// only the final delivery hops back to main. Avoids a multi-hundred-ms
    /// main-thread stall when opening the history viewer on a large log.
    func readHistoryAsync(for sessionId: UUID, completion: @escaping (String) -> Void) {
        readHistoryAsync(for: [sessionId], completion: completion)
    }

    /// Reads and concatenates the logs of several panes (a session's split
    /// tree) in tree order, each separated by a divider. All file work runs on
    /// `queue`; only delivery hops to main.
    func readHistoryAsync(for paneIds: [UUID], completion: @escaping (String) -> Void) {
        queue.async { [self] in
            var parts: [String] = []
            for paneId in paneIds {
                flushPending(for: paneId)
                openHandles[paneId]?.synchronizeFile()
                let raw = (try? String(contentsOf: logPath(for: paneId), encoding: .utf8)) ?? ""
                let stripped = Self.stripAnsi(raw)
                if !stripped.isEmpty { parts.append(stripped) }
            }
            let joined = parts.joined(separator: "\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n")
            DispatchQueue.main.async { completion(joined) }
        }
    }

    func deleteHistory(for sessionId: UUID) {
        queue.async { [self] in
            if let pending = pendingWrites.removeValue(forKey: sessionId) {
                pending.timer?.cancel()
            }
            closeHandle(for: sessionId)
            try? FileManager.default.removeItem(at: logPath(for: sessionId))
        }
    }

    @objc private func closeAllHandles() {
        queue.sync { [self] in
            // Flush any in-flight buffered writes so we don't lose history on quit.
            for sessionId in Array(pendingWrites.keys) {
                flushPending(for: sessionId)
            }
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
