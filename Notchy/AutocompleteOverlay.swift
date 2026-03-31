import AppKit

class GhostTextView: NSView {
    var ghostText: String = "" {
        didSet {
            isHidden = ghostText.isEmpty
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) {
        didSet { needsDisplay = true }
    }

    private let ghostColor = NSColor.white.withAlphaComponent(0.35)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard !ghostText.isEmpty else { return .zero }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (ghostText as NSString).size(withAttributes: attrs)
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !ghostText.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ghostColor,
        ]
        let drawPoint = NSPoint(x: 0, y: 0)
        (ghostText as NSString).draw(at: drawPoint, withAttributes: attrs)
    }
}
