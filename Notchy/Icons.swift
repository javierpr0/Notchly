import SwiftUI

/// Custom icon set for Notchly chrome. Hand-drawn vector paths matched to
/// a single visual language: geometric, 1.5pt stroke, rounded caps,
/// optical-aligned within a 16pt frame. Use via `NotchyIcon(.pin)`.
enum NotchyIconKind {
    case pin, pinFilled
    case gear
    case plus
    case close
    case splitRight, splitDown, splitLeft, splitUp
    case working
    case waiting
    case done
    case bookmark
    case restore
    case search
    case chrome
    case shield
    case download
    case chevronUpDown
    case sparkle
}

struct NotchyIcon: View {
    let kind: NotchyIconKind
    var size: CGFloat = 14
    var weight: CGFloat = 1.5

    var body: some View {
        shape
            .frame(width: size, height: size)
    }

    // Split into helpers so the Swift type-checker can resolve each branch
    // independently. A single 20-case switch returning concrete View types
    // exceeds the type-check time budget under -O.
    @ViewBuilder
    private var shape: some View {
        switch kind {
        case .pin, .pinFilled, .gear, .plus, .close:
            primaryShape
        case .splitRight, .splitDown, .splitLeft, .splitUp:
            splitShape
        case .working, .waiting, .done:
            statusShape
        case .bookmark, .restore, .search, .chrome, .shield, .download, .chevronUpDown, .sparkle:
            miscShape
        }
    }

    @ViewBuilder
    private var primaryShape: some View {
        switch kind {
        case .pin:        PinShape(filled: false, lineWidth: weight)
        case .pinFilled:  PinShape(filled: true, lineWidth: weight)
        case .gear:       GearShape(lineWidth: weight)
        case .plus:       PlusShape(lineWidth: weight)
        case .close:      CloseShape(lineWidth: weight)
        default:          EmptyView()
        }
    }

    @ViewBuilder
    private var splitShape: some View {
        switch kind {
        case .splitRight: SplitArrowShape(direction: .right, lineWidth: weight)
        case .splitDown:  SplitArrowShape(direction: .down, lineWidth: weight)
        case .splitLeft:  SplitArrowShape(direction: .left, lineWidth: weight)
        case .splitUp:    SplitArrowShape(direction: .up, lineWidth: weight)
        default:          EmptyView()
        }
    }

    @ViewBuilder
    private var statusShape: some View {
        switch kind {
        case .working: WorkingSpinnerShape(lineWidth: weight)
        case .waiting: WaitingShape(lineWidth: weight)
        case .done:    DoneShape(lineWidth: weight)
        default:       EmptyView()
        }
    }

    @ViewBuilder
    private var miscShape: some View {
        switch kind {
        case .bookmark:      BookmarkShape(lineWidth: weight)
        case .restore:       RestoreShape(lineWidth: weight)
        case .search:        SearchShape(lineWidth: weight)
        case .chrome:        ChromeShape(lineWidth: weight)
        case .shield:        ShieldShape(lineWidth: weight)
        case .download:      DownloadShape(lineWidth: weight)
        case .chevronUpDown: ChevronUpDownShape(lineWidth: weight)
        case .sparkle:       SparkleShape(lineWidth: weight)
        default:             EmptyView()
        }
    }
}

// MARK: - Drawing helpers

private extension View {
    func iconCanvas(_ size: CGFloat = 16) -> some View {
        frame(width: size, height: size)
    }
}

// MARK: - Pin (45° tilted, rounded body)

private struct PinShape: View {
    let filled: Bool
    let lineWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            // A pin tilted 45° pointing bottom-left. Body is a rounded
            // triangle with a flat head.
            let path = Path { p in
                p.move(to: CGPoint(x: s * 0.18, y: s * 0.82))
                p.addLine(to: CGPoint(x: s * 0.42, y: s * 0.58))
                p.addLine(to: CGPoint(x: s * 0.32, y: s * 0.48))
                p.addLine(to: CGPoint(x: s * 0.62, y: s * 0.18))
                p.addLine(to: CGPoint(x: s * 0.82, y: s * 0.38))
                p.addLine(to: CGPoint(x: s * 0.52, y: s * 0.68))
                p.addLine(to: CGPoint(x: s * 0.42, y: s * 0.58))
            }
            if filled {
                ctx.fill(path, with: .color(.primary))
            } else {
                ctx.stroke(path, with: .color(.primary),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            // Tail line
            var tail = Path()
            tail.move(to: CGPoint(x: s * 0.18, y: s * 0.82))
            tail.addLine(to: CGPoint(x: s * 0.06, y: s * 0.94))
            ctx.stroke(tail, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

// MARK: - Gear

private struct GearShape: View {
    let lineWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let center = CGPoint(x: s / 2, y: s / 2)
            let outer = s * 0.44
            let inner = s * 0.30
            let teeth = 8

            // Toothed silhouette built from alternating outer/inner radii
            var gear = Path()
            for i in 0..<(teeth * 2) {
                let angle = Double(i) / Double(teeth * 2) * .pi * 2 - .pi / 2
                let r = i % 2 == 0 ? outer : inner
                let pt = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if i == 0 { gear.move(to: pt) } else { gear.addLine(to: pt) }
            }
            gear.closeSubpath()

            ctx.stroke(gear, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

            // Inner hole
            let hole = Path(ellipseIn: CGRect(
                x: center.x - s * 0.12, y: center.y - s * 0.12,
                width: s * 0.24, height: s * 0.24
            ))
            ctx.stroke(hole, with: .color(.primary), lineWidth: lineWidth)
        }
    }
}

// MARK: - Plus / Close

private struct PlusShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let inset: CGFloat = s * 0.22
            var path = Path()
            path.move(to: CGPoint(x: s / 2, y: inset))
            path.addLine(to: CGPoint(x: s / 2, y: s - inset))
            path.move(to: CGPoint(x: inset, y: s / 2))
            path.addLine(to: CGPoint(x: s - inset, y: s / 2))
            ctx.stroke(path, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

private struct CloseShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let inset: CGFloat = s * 0.26
            var path = Path()
            path.move(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: s - inset, y: s - inset))
            path.move(to: CGPoint(x: s - inset, y: inset))
            path.addLine(to: CGPoint(x: inset, y: s - inset))
            ctx.stroke(path, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

// MARK: - Split direction

private struct SplitArrowShape: View {
    enum Dir { case right, down, left, up }
    let direction: Dir
    let lineWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let inset: CGFloat = s * 0.18
            // Outer rounded rect
            let frame = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
            let outer = Path(roundedRect: frame, cornerRadius: s * 0.14)
            ctx.stroke(outer, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            // Divider line + accent shading on the "new" half
            let mid: CGFloat
            var divider = Path()
            var shade = Path()
            switch direction {
            case .right:
                mid = frame.midX
                divider.move(to: CGPoint(x: mid, y: frame.minY + 1))
                divider.addLine(to: CGPoint(x: mid, y: frame.maxY - 1))
                shade = Path(roundedRect: CGRect(x: mid + 0.6, y: frame.minY + 1,
                                                 width: frame.maxX - mid - 1.6,
                                                 height: frame.height - 2),
                             cornerRadius: s * 0.10)
            case .left:
                mid = frame.midX
                divider.move(to: CGPoint(x: mid, y: frame.minY + 1))
                divider.addLine(to: CGPoint(x: mid, y: frame.maxY - 1))
                shade = Path(roundedRect: CGRect(x: frame.minX + 1, y: frame.minY + 1,
                                                 width: mid - frame.minX - 1.6,
                                                 height: frame.height - 2),
                             cornerRadius: s * 0.10)
            case .down:
                mid = frame.midY
                divider.move(to: CGPoint(x: frame.minX + 1, y: mid))
                divider.addLine(to: CGPoint(x: frame.maxX - 1, y: mid))
                shade = Path(roundedRect: CGRect(x: frame.minX + 1, y: mid + 0.6,
                                                 width: frame.width - 2,
                                                 height: frame.maxY - mid - 1.6),
                             cornerRadius: s * 0.10)
            case .up:
                mid = frame.midY
                divider.move(to: CGPoint(x: frame.minX + 1, y: mid))
                divider.addLine(to: CGPoint(x: frame.maxX - 1, y: mid))
                shade = Path(roundedRect: CGRect(x: frame.minX + 1, y: frame.minY + 1,
                                                 width: frame.width - 2,
                                                 height: mid - frame.minY - 1.6),
                             cornerRadius: s * 0.10)
            }
            ctx.stroke(divider, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            ctx.fill(shade, with: .color(.primary.opacity(0.35)))
        }
    }
}

// MARK: - Status

private struct WorkingSpinnerShape: View {
    let lineWidth: CGFloat
    @State private var rotating = false
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let center = CGPoint(x: s / 2, y: s / 2)
            let radius = s * 0.36
            var arc = Path()
            arc.addArc(center: center, radius: radius,
                       startAngle: .degrees(0), endAngle: .degrees(280),
                       clockwise: false)
            ctx.stroke(arc, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(.degrees(rotating ? 360 : 0))
        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
        .onAppear { rotating = true }
    }
}

private struct WaitingShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            // Triangle outline with exclamation inside
            var triangle = Path()
            triangle.move(to: CGPoint(x: s * 0.50, y: s * 0.16))
            triangle.addLine(to: CGPoint(x: s * 0.92, y: s * 0.84))
            triangle.addLine(to: CGPoint(x: s * 0.08, y: s * 0.84))
            triangle.closeSubpath()
            ctx.stroke(triangle, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            var bang = Path()
            bang.move(to: CGPoint(x: s * 0.50, y: s * 0.42))
            bang.addLine(to: CGPoint(x: s * 0.50, y: s * 0.62))
            ctx.stroke(bang, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: s * 0.46, y: s * 0.70, width: s * 0.08, height: s * 0.08)),
                     with: .color(.primary))
        }
    }
}

private struct DoneShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            var check = Path()
            check.move(to: CGPoint(x: s * 0.20, y: s * 0.54))
            check.addLine(to: CGPoint(x: s * 0.42, y: s * 0.74))
            check.addLine(to: CGPoint(x: s * 0.80, y: s * 0.30))
            ctx.stroke(check, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth + 0.3, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Bookmark / Restore

private struct BookmarkShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            var path = Path()
            path.move(to: CGPoint(x: s * 0.26, y: s * 0.16))
            path.addLine(to: CGPoint(x: s * 0.74, y: s * 0.16))
            path.addLine(to: CGPoint(x: s * 0.74, y: s * 0.86))
            path.addLine(to: CGPoint(x: s * 0.50, y: s * 0.66))
            path.addLine(to: CGPoint(x: s * 0.26, y: s * 0.86))
            path.closeSubpath()
            ctx.stroke(path, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
    }
}

private struct RestoreShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let center = CGPoint(x: s / 2, y: s / 2 + 1)
            let radius = s * 0.34
            var arc = Path()
            arc.addArc(center: center, radius: radius,
                       startAngle: .degrees(20), endAngle: .degrees(280),
                       clockwise: false)
            ctx.stroke(arc, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            // Counter-clockwise arrowhead at the top-right
            var head = Path()
            head.move(to: CGPoint(x: center.x + radius * 0.92, y: center.y - radius * 0.20))
            head.addLine(to: CGPoint(x: center.x + radius * 1.18, y: center.y - radius * 0.50))
            head.move(to: CGPoint(x: center.x + radius * 0.92, y: center.y - radius * 0.20))
            head.addLine(to: CGPoint(x: center.x + radius * 0.62, y: center.y - radius * 0.46))
            ctx.stroke(head, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            // Hands
            var hands = Path()
            hands.move(to: center)
            hands.addLine(to: CGPoint(x: center.x, y: center.y - radius * 0.55))
            hands.move(to: center)
            hands.addLine(to: CGPoint(x: center.x + radius * 0.35, y: center.y))
            ctx.stroke(hands, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

// MARK: - Search / Chrome / Shield / Download / Chevron / Sparkle

private struct SearchShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let center = CGPoint(x: s * 0.42, y: s * 0.42)
            let radius = s * 0.26
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                              width: radius * 2, height: radius * 2)),
                       with: .color(.primary), lineWidth: lineWidth)
            var handle = Path()
            handle.move(to: CGPoint(x: center.x + radius * 0.7, y: center.y + radius * 0.7))
            handle.addLine(to: CGPoint(x: s * 0.86, y: s * 0.86))
            ctx.stroke(handle, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

private struct ChromeShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let frame = CGRect(x: s * 0.10, y: s * 0.16, width: s * 0.80, height: s * 0.68)
            ctx.stroke(Path(roundedRect: frame, cornerRadius: s * 0.12),
                       with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            var bar = Path()
            bar.move(to: CGPoint(x: frame.minX + 3, y: frame.minY + s * 0.18))
            bar.addLine(to: CGPoint(x: frame.maxX - 3, y: frame.minY + s * 0.18))
            ctx.stroke(bar, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: frame.minX + 3, y: frame.minY + s * 0.06,
                                            width: 3, height: 3)),
                     with: .color(.primary))
        }
    }
}

private struct ShieldShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            var path = Path()
            path.move(to: CGPoint(x: s * 0.50, y: s * 0.10))
            path.addLine(to: CGPoint(x: s * 0.85, y: s * 0.24))
            path.addLine(to: CGPoint(x: s * 0.85, y: s * 0.50))
            path.addQuadCurve(to: CGPoint(x: s * 0.50, y: s * 0.92),
                              control: CGPoint(x: s * 0.85, y: s * 0.86))
            path.addQuadCurve(to: CGPoint(x: s * 0.15, y: s * 0.50),
                              control: CGPoint(x: s * 0.15, y: s * 0.86))
            path.addLine(to: CGPoint(x: s * 0.15, y: s * 0.24))
            path.closeSubpath()
            ctx.stroke(path, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
    }
}

private struct DownloadShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            var arrow = Path()
            arrow.move(to: CGPoint(x: s * 0.50, y: s * 0.16))
            arrow.addLine(to: CGPoint(x: s * 0.50, y: s * 0.66))
            ctx.stroke(arrow, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            var head = Path()
            head.move(to: CGPoint(x: s * 0.30, y: s * 0.48))
            head.addLine(to: CGPoint(x: s * 0.50, y: s * 0.70))
            head.addLine(to: CGPoint(x: s * 0.70, y: s * 0.48))
            ctx.stroke(head, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            var tray = Path()
            tray.move(to: CGPoint(x: s * 0.18, y: s * 0.84))
            tray.addLine(to: CGPoint(x: s * 0.82, y: s * 0.84))
            ctx.stroke(tray, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

private struct ChevronUpDownShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            var path = Path()
            path.move(to: CGPoint(x: s * 0.30, y: s * 0.36))
            path.addLine(to: CGPoint(x: s * 0.50, y: s * 0.20))
            path.addLine(to: CGPoint(x: s * 0.70, y: s * 0.36))
            path.move(to: CGPoint(x: s * 0.30, y: s * 0.64))
            path.addLine(to: CGPoint(x: s * 0.50, y: s * 0.80))
            path.addLine(to: CGPoint(x: s * 0.70, y: s * 0.64))
            ctx.stroke(path, with: .color(.primary),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct SparkleShape: View {
    let lineWidth: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            // Four-point star
            var star = Path()
            star.move(to: CGPoint(x: s * 0.50, y: s * 0.10))
            star.addLine(to: CGPoint(x: s * 0.58, y: s * 0.42))
            star.addLine(to: CGPoint(x: s * 0.90, y: s * 0.50))
            star.addLine(to: CGPoint(x: s * 0.58, y: s * 0.58))
            star.addLine(to: CGPoint(x: s * 0.50, y: s * 0.90))
            star.addLine(to: CGPoint(x: s * 0.42, y: s * 0.58))
            star.addLine(to: CGPoint(x: s * 0.10, y: s * 0.50))
            star.addLine(to: CGPoint(x: s * 0.42, y: s * 0.42))
            star.closeSubpath()
            ctx.fill(star, with: .color(.primary))
        }
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
        ForEach(NotchyIconKind.allCases, id: \.self) { kind in
            VStack(spacing: 6) {
                NotchyIcon(kind: kind, size: 24)
                    .foregroundStyle(.white)
                Text(kind.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
    .padding(24)
    .background(Color(hex: 0x0E0F12))
}

extension NotchyIconKind: CaseIterable, Hashable {
    var label: String {
        switch self {
        case .pin: "pin"
        case .pinFilled: "pinFilled"
        case .gear: "gear"
        case .plus: "plus"
        case .close: "close"
        case .splitRight: "splitRight"
        case .splitDown: "splitDown"
        case .splitLeft: "splitLeft"
        case .splitUp: "splitUp"
        case .working: "working"
        case .waiting: "waiting"
        case .done: "done"
        case .bookmark: "bookmark"
        case .restore: "restore"
        case .search: "search"
        case .chrome: "chrome"
        case .shield: "shield"
        case .download: "download"
        case .chevronUpDown: "chevronUpDown"
        case .sparkle: "sparkle"
        }
    }
}
