import SwiftUI
import AppKit

/// A request to preview a file inline in the panel (⌘-click on a path).
struct FilePreviewRequest: Equatable {
    let url: URL
    let line: Int?
}

/// Read-only inline file viewer shown as an overlay inside the panel.
/// Text renders in an NSTextView — the find bar works there, and
/// TerminalPanel's focus-restore whitelist already covers NSTextView, so it
/// keeps keyboard focus inside the non-activating panel. Images render
/// natively; binaries and huge files open in the default external app instead.
struct FilePreviewView: View {
    let request: FilePreviewRequest
    let onDismiss: () -> Void

    private enum Content {
        case text(String)
        case image(NSImage)
    }

    @State private var content: Content?
    @State private var escMonitor: Any?

    private nonisolated static let maxPreviewBytes = 5 * 1024 * 1024
    private nonisolated static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "icns"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.1))
            switch content {
            case .text(let string):
                TextFileView(text: string, highlightLine: request.line)
            case .image(let image):
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .padding(12)
                }
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)).opacity(SessionStore.shared.panelOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .task(id: request) { await load() }
        .onAppear {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event } // Esc
                onDismiss()
                return nil
            }
        }
        .onDisappear {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            escMonitor = nil
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(request.url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                    if let line = request.line {
                        Text(":\(line)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(request.url.deletingLastPathComponent().path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([request.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help(L10n.shared.revealInFinder)
            Button {
                NSWorkspace.shared.open(request.url)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .help(L10n.shared.openInDefaultApp)
            Button(action: onDismiss) {
                NotchyIcon(kind: .close)
            }
            .buttonStyle(.plain)
            .help(L10n.shared.close)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
    }

    private func load() async {
        let url = request.url
        let result: Content? = await Task.detached(priority: .userInitiated) { () -> Content? in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= Self.maxPreviewBytes else { return nil }
            if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
                guard let image = NSImage(contentsOf: url) else { return nil }
                return .image(image)
            }
            guard let data = try? Data(contentsOf: url),
                  let string = String(data: data, encoding: .utf8) else { return nil }
            return .text(string)
        }.value

        if let result {
            content = result
        } else {
            // Binary, unreadable, or too large — hand off to the default app.
            NSWorkspace.shared.open(url)
            onDismiss()
        }
    }
}

/// NSTextView-backed read-only text display, mirroring HistoryViewerPanel's
/// configuration (find bar, incremental search, monospaced).
private struct TextFileView: NSViewRepresentable {
    let text: String
    let highlightLine: Int?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = NSColor(white: 0.9, alpha: 1)
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Take keyboard focus so ⌘F/arrows work; the panel's focus-restore
        // whitelist (NSTextView) keeps it here until the preview closes.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }
        textView.string = text
        guard let line = highlightLine else { return }
        let range = Self.range(ofLine: line, in: text)
        // Defer until after layout so the scroll target exists.
        DispatchQueue.main.async {
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }
    }

    /// NSRange of a 1-based line number (the whole line, without its newline).
    private static func range(ofLine line: Int, in text: String) -> NSRange {
        var current = 1
        var start = text.startIndex
        while current < line, let newline = text[start...].firstIndex(of: "\n") {
            start = text.index(after: newline)
            current += 1
        }
        let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
        return NSRange(start..<end, in: text)
    }
}
