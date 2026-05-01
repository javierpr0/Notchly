import AppKit
import SwiftUI

/// Centralized design tokens for chrome UI (everything outside the terminal
/// content itself). Terminal themes still control terminal background/text,
/// but the panel/tab bar/notch pill all read from here so the look stays
/// consistent regardless of the chosen terminal theme.
enum DS {
    // MARK: - Color

    enum Color {
        // Backgrounds (Notchly Dark)
        static let bgBase     = SwiftUI.Color(hex: 0x0E0F12)
        static let bgElevated = SwiftUI.Color(hex: 0x16181D)
        static let bgChrome   = SwiftUI.Color(hex: 0x1C1F26)
        static let bgPopover  = SwiftUI.Color(hex: 0x1A1C22)

        // Borders / dividers
        static let borderSubtle   = SwiftUI.Color.white.opacity(0.06)
        static let borderHairline = SwiftUI.Color.white.opacity(0.10)

        // Text
        static let textPrimary   = SwiftUI.Color(hex: 0xE6E8EC)
        static let textSecondary = SwiftUI.Color(hex: 0x9AA0AB)
        static let textTertiary  = SwiftUI.Color(hex: 0x5C6370)

        // Accent — Notchly violet
        static let accent     = SwiftUI.Color(hex: 0x7C5CFF)
        static let accentSoft = SwiftUI.Color(hex: 0x7C5CFF).opacity(0.18)
        static let accentGlow = SwiftUI.Color(hex: 0x7C5CFF).opacity(0.32)

        // Status — saturated, system-feeling colors so the notch reads at a
        // glance: amber for "working", orange for "needs your attention",
        // green for "finished".
        static let statusWorking = SwiftUI.Color(hex: 0xFBBF24) // amber
        static let statusWaiting = SwiftUI.Color(hex: 0xFB923C) // orange
        static let statusDone    = SwiftUI.Color(hex: 0x22C55E) // green
        static let statusIdle    = SwiftUI.Color(hex: 0x5C6370)

        // Hover/press tints (overlay on top of any bg)
        static let hoverTint = SwiftUI.Color.white.opacity(0.06)
        static let pressTint = SwiftUI.Color.white.opacity(0.10)
        static let activeTint = SwiftUI.Color.white.opacity(0.04)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Radius

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: - Typography

    enum Font {
        static let caption    = SwiftUI.Font.system(size: 10, weight: .medium)
        static let captionBold = SwiftUI.Font.system(size: 10, weight: .semibold)
        static let body       = SwiftUI.Font.system(size: 11, weight: .regular)
        static let bodyMedium = SwiftUI.Font.system(size: 11, weight: .medium)
        static let bodyBold   = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let title      = SwiftUI.Font.system(size: 13, weight: .medium)
        static let titleBold  = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let heading    = SwiftUI.Font.system(size: 15, weight: .semibold)
    }

    // MARK: - Motion

    enum Motion {
        /// Quick, snappy spring for state changes (tabs, splits, focus).
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.86)
        /// Linear-feeling fast ease for hover.
        static let swift = Animation.easeOut(duration: 0.16)
        /// Smooth color/opacity transitions.
        static let smooth = Animation.easeInOut(duration: 0.24)
        /// Slower transitions (panel show/hide).
        static let slow = Animation.easeInOut(duration: 0.32)
        /// Expressive bounce (notch pill expand only).
        static let bounce = Animation.spring(response: 0.42, dampingFraction: 0.65)
    }

    // MARK: - Shadow

    struct Elevation {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let pop = Elevation(
            color: SwiftUI.Color.black.opacity(0.18),
            radius: 12, x: 0, y: 4
        )
        static let panel = Elevation(
            color: SwiftUI.Color.black.opacity(0.32),
            radius: 48, x: 0, y: 20
        )
        static let glow = Elevation(
            color: Color.accent.opacity(0.40),
            radius: 16, x: 0, y: 0
        )
    }
}

// MARK: - View modifiers

extension View {
    func dsShadow(_ elevation: DS.Elevation) -> some View {
        shadow(color: elevation.color, radius: elevation.radius, x: elevation.x, y: elevation.y)
    }

    /// Standardized chrome button — uniform 28x28 hit target, hover tint,
    /// press scale. Intended for top bar / pane controls.
    func dsChromeButton(isActive: Bool = false) -> some View {
        modifier(ChromeButtonModifier(isActive: isActive))
    }
}

private struct ChromeButtonModifier: ViewModifier {
    var isActive: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        // Important: do NOT attach a DragGesture (even simultaneous) here.
        // SwiftUI on macOS will swallow the click on a parent Button when
        // the Button's label has a DragGesture(minimumDistance: 0), which is
        // exactly what a "press scale" effect requires. We give up the press
        // animation so taps stay reliable.
        content
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(isActive ? DS.Color.activeTint : (isHovering ? DS.Color.hoverTint : .clear))
            )
            .onHover { hovering in
                withAnimation(DS.Motion.swift) { isHovering = hovering }
            }
    }
}

// MARK: - Color helper

extension SwiftUI.Color {
    /// Hex literal initializer used across the chrome design system. The
    /// argument name is `alpha:` (not `opacity:`) so it stays compatible
    /// with the original CommandPaletteView call sites.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension NSColor {
    /// Bridge for AppKit callers that need DS.Color values as NSColor.
    static func ds(_ color: SwiftUI.Color) -> NSColor {
        NSColor(color)
    }
}
