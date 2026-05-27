import SwiftUI
import AppKit

/// Native AppKit divider for split panes. Owns its own mouse handling
/// instead of relying on a SwiftUI `DragGesture` because the gesture
/// competes (and frequently loses) against adjacent NSViewRepresentable
/// terminals that set `acceptsFirstMouse = true`. Cursor handling uses
/// a tracking area so it survives SwiftUI layout updates that don't
/// re-invalidate cursor rects.
class ResizeCursorNSView: NSView {
    var isHorizontal = true
    /// Fires on mouseDown so the caller can snapshot the starting ratio.
    var onDragBegan: (() -> Void)?
    /// Caller of `onDragChanged` receives the signed delta in points along the
    /// resize axis (horizontal divider → x; vertical → y) since drag start.
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var dragStartLocation: NSPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private var resizeCursor: NSCursor {
        isHorizontal ? .resizeLeftRight : .resizeUpDown
    }

    override func cursorUpdate(with event: NSEvent) {
        resizeCursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        resizeCursor.set()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        // Only revert hover if not currently dragging — drag keeps hover state.
        if dragStartLocation == nil {
            onHoverChanged?(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        onDragBegan?()
        resizeCursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartLocation else { return }
        let current = event.locationInWindow
        let delta = isHorizontal ? (current.x - start.x) : (current.y - start.y)
        onDragChanged?(delta)
        resizeCursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        onDragEnded?()
        // Only clear hover if mouse actually left the divider bounds.
        let local = convert(event.locationInWindow, from: nil)
        if !bounds.contains(local) {
            onHoverChanged?(false)
        }
    }
}

struct ResizeCursorView: NSViewRepresentable {
    var isHorizontal: Bool
    var onDragBegan: () -> Void
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: () -> Void
    var onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ResizeCursorNSView {
        let view = ResizeCursorNSView()
        view.isHorizontal = isHorizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: ResizeCursorNSView, context: Context) {
        nsView.isHorizontal = isHorizontal
        nsView.onDragBegan = onDragBegan
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onHoverChanged = onHoverChanged
    }
}

struct SplitDividerView<First: View, Second: View>: View {
    let splitId: UUID
    let direction: SplitDirection
    let ratio: CGFloat
    @Bindable var sessionStore: SessionStore
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragStartRatio: CGFloat = 0
    private let dividerThickness: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let total = direction == .horizontal ? geo.size.width : geo.size.height
            let firstSize = total * ratio - dividerThickness / 2
            let secondSize = total * (1 - ratio) - dividerThickness / 2

            if direction == .horizontal {
                HStack(spacing: 0) {
                    first().frame(width: max(firstSize, 40))
                    dividerHandle(total: total, isHorizontal: true)
                    second().frame(width: max(secondSize, 40))
                }
            } else {
                VStack(spacing: 0) {
                    first().frame(height: max(firstSize, 40))
                    dividerHandle(total: total, isHorizontal: false)
                    second().frame(height: max(secondSize, 40))
                }
            }
        }
    }

    private func dividerHandle(total: CGFloat, isHorizontal: Bool) -> some View {
        ResizeCursorView(
            isHorizontal: isHorizontal,
            onDragBegan: {
                // Snapshot the ratio at the moment the drag begins. The native
                // delta is absolute from mouseDown, so we add it to this fixed
                // anchor instead of the live `ratio` (which itself updates
                // during the drag and would otherwise compound).
                dragStartRatio = ratio
                isDragging = true
            },
            onDragChanged: { delta in
                let newRatio = dragStartRatio + delta / total
                sessionStore.updateSplitRatio(splitId, ratio: newRatio)
            },
            onDragEnded: {
                isDragging = false
                sessionStore.persistSplitRatio()
                if let paneId = sessionStore.activeSession?.focusedPaneId {
                    TerminalManager.shared.focusTerminal(for: paneId)
                }
            },
            onHoverChanged: { hovering in
                isHovering = hovering
            }
        )
        .frame(
            width: isHorizontal ? dividerThickness : nil,
            height: isHorizontal ? nil : dividerThickness
        )
        .background(
            isDragging ? DS.Color.accent.opacity(0.65)
            : (isHovering ? DS.Color.accent.opacity(0.25) : DS.Color.borderHairline)
        )
    }
}

struct PaneControlsView: View {
    let paneId: UUID
    @Bindable var sessionStore: SessionStore
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            controlButton(icon: .splitLeft, help: L10n.shared.splitRight + " (←)") {
                sessionStore.splitFocusedPane(direction: .horizontal, placeNewBefore: true)
            }
            controlButton(icon: .splitRight, help: L10n.shared.splitRight) {
                sessionStore.splitFocusedPane(direction: .horizontal)
            }
            controlButton(icon: .splitUp, help: L10n.shared.splitDown + " (↑)") {
                sessionStore.splitFocusedPane(direction: .vertical, placeNewBefore: true)
            }
            controlButton(icon: .splitDown, help: L10n.shared.splitDown) {
                sessionStore.splitFocusedPane(direction: .vertical)
            }
            Rectangle()
                .fill(DS.Color.borderSubtle)
                .frame(width: 1, height: 12)
                .padding(.horizontal, 2)
            controlButton(icon: .close, help: L10n.shared.closePane) {
                sessionStore.closeFocusedPane()
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isHovering ? 1 : 0.78)
        )
        .opacity(isHovering ? 1 : 0.5)
        .onHover { hovering in
            withAnimation(DS.Motion.swift) { isHovering = hovering }
        }
    }

    private func controlButton(icon: NotchyIconKind, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NotchyIcon(kind: icon, size: 12)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SplitPaneView: View {
    let node: SplitNode
    let launchClaude: Bool
    let generation: Int
    var customCommand: String? = nil
    @Bindable var sessionStore: SessionStore

    private var focusedPaneId: UUID? {
        sessionStore.activeSession?.focusedPaneId
    }

    private var hasMultiplePanes: Bool {
        (sessionStore.activeSession?.splitRoot.allPaneIds.count ?? 0) > 1
    }

    var body: some View {
        switch node {
        case .pane(let paneId, let workingDirectory):
            TerminalSessionView(
                sessionId: paneId,
                workingDirectory: workingDirectory,
                launchClaude: launchClaude,
                generation: generation,
                customCommand: customCommand
            )
            .overlay(alignment: .topTrailing) {
                if focusedPaneId == paneId {
                    PaneControlsView(paneId: paneId, sessionStore: sessionStore)
                        .padding(6)
                }
            }
            // Focused pane indicator: subtle inner accent stripe on the
            // top edge, no heavy stroke. Reads as "this is active" without
            // adding a hard border to every pane.
            .overlay(alignment: .top) {
                if hasMultiplePanes && focusedPaneId == paneId {
                    LinearGradient(
                        colors: [DS.Color.accent.opacity(0.85), DS.Color.accent.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(DS.Motion.swift, value: focusedPaneId)

        case .split(let splitId, let direction, let first, let second, let ratio):
            SplitDividerView(
                splitId: splitId,
                direction: direction,
                ratio: ratio,
                sessionStore: sessionStore
            ) {
                SplitPaneView(node: first, launchClaude: launchClaude, generation: generation, customCommand: customCommand, sessionStore: sessionStore)
            } second: {
                SplitPaneView(node: second, launchClaude: launchClaude, generation: generation, customCommand: customCommand, sessionStore: sessionStore)
            }
        }
    }
}
