import SwiftUI
import SwiftTerm

private class ClickThroughContainerView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // SwiftTerm derives every line's baseline from frame.height; SwiftUI
    // hands us fractional heights, which puts all glyph baselines off the
    // physical pixel grid and renders text slightly blurry. Size the
    // terminal manually, snapped to whole physical pixels.
    override func layout() {
        super.layout()
        guard let terminal = subviews.first else { return }
        let scale = window?.backingScaleFactor ?? 2
        let snapped = NSRect(
            x: 0,
            y: 0,
            width: floor(bounds.width * scale) / scale,
            height: floor(bounds.height * scale) / scale
        )
        if terminal.frame != snapped {
            terminal.frame = snapped
        }
    }
}

struct TerminalSessionView: NSViewRepresentable {
    let sessionId: UUID
    let workingDirectory: String
    var launchClaude: Bool = true
    var generation: Int = 0
    var customCommand: String? = nil

    class Coordinator {
        var currentSessionId: UUID?
        var currentGeneration: Int = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = ClickThroughContainerView(frame: .zero)
        container.wantsLayer = true
        attachTerminal(to: container, context: context)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.currentSessionId != sessionId || context.coordinator.currentGeneration != generation {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            attachTerminal(to: nsView, context: context)
        }
    }

    private func attachTerminal(to container: NSView, context: Context) {
        context.coordinator.currentSessionId = sessionId
        context.coordinator.currentGeneration = generation
        let terminal = TerminalManager.shared.terminal(for: sessionId, workingDirectory: workingDirectory, launchClaude: launchClaude, customCommand: customCommand)

        // Remove from previous superview if it was in a different container
        terminal.removeFromSuperview()

        // Manual layout (see ClickThroughContainerView.layout) instead of
        // edge-anchored constraints, so the frame can pixel-snap.
        terminal.translatesAutoresizingMaskIntoConstraints = true
        terminal.autoresizingMask = []
        container.addSubview(terminal)
        container.needsLayout = true

        // Give terminal keyboard focus
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
    }
}
