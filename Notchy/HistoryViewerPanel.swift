import AppKit

class HistoryViewerPanel: NSPanel {
    private let scrollView: NSScrollView
    private let textView: NSTextView

    init(sessionName: String, sessionId: UUID) {
        let content = SessionHistoryManager.shared.readHistory(for: sessionId)

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1)
        textView.textColor = NSColor(white: 0.9, alpha: 1)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        scrollView.documentView = textView

        let windowRect = NSRect(x: 0, y: 0, width: 700, height: 500)
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = L10n.shared.historyTitle(sessionName)
        self.minSize = NSSize(width: 400, height: 300)
        self.contentView = scrollView
        self.isReleasedWhenClosed = false
        self.center()

        if content.isEmpty {
            textView.string = L10n.shared.noHistory
        } else {
            textView.string = content
            // Scroll to bottom
            textView.scrollToEndOfDocument(nil)
        }
    }
}
