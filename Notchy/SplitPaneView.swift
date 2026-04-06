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
            .background(isDragging ? Color.accentColor.opacity(0.6) : Color(white: 0.25))
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
        HStack(spacing: 2) {
            controlButton(icon: "square.split.2x1", help: L10n.shared.splitRight) {
                sessionStore.splitFocusedPane(direction: .horizontal)
            }
            controlButton(icon: "square.split.1x2", help: L10n.shared.splitDown) {
                sessionStore.splitFocusedPane(direction: .vertical)
            }
            controlButton(icon: "xmark", help: L10n.shared.closePane) {
                sessionStore.closeFocusedPane()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(isHovering ? 1 : 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(isHovering ? 1 : 0.4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func controlButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(Color(nsColor: SessionStore.shared.currentTheme.chromeForeground))
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
            .overlay {
                if hasMultiplePanes && focusedPaneId == paneId {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }

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
