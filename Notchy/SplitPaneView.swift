import SwiftUI
import AppKit

class ResizeCursorNSView: NSView {
    var isHorizontal = true

    override var intrinsicContentSize: NSSize {
        // Expand fully in the non-constrained axis
        isHorizontal ? NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
                     : NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func resetCursorRects() {
        discardCursorRects()
        guard bounds.width > 0 && bounds.height > 0 else { return }
        let cursor: NSCursor = isHorizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct ResizeCursorView: NSViewRepresentable {
    var isHorizontal: Bool

    func makeNSView(context: Context) -> ResizeCursorNSView {
        let view = ResizeCursorNSView()
        view.isHorizontal = isHorizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: ResizeCursorNSView, context: Context) {
        nsView.isHorizontal = isHorizontal
        nsView.window?.invalidateCursorRects(for: nsView)
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
        ResizeCursorView(isHorizontal: isHorizontal)
            .frame(
                width: isHorizontal ? dividerThickness : nil,
                height: isHorizontal ? nil : dividerThickness
            )
            .background(isDragging ? DS.Color.accent.opacity(0.65) : DS.Color.borderHairline)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let delta = isHorizontal ? value.translation.width : value.translation.height
                        let newRatio = ratio + delta / total
                        sessionStore.updateSplitRatio(splitId, ratio: newRatio)
                    }
                    .onEnded { _ in
                        isDragging = false
                        sessionStore.persistSplitRatio()
                    }
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
