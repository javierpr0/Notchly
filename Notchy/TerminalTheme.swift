import AppKit
import SwiftTerm

struct TerminalTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor
    let selection: NSColor
    let ansiColors: [NSColor] // 16 colors: 8 normal + 8 bright

    func swiftTermColors() -> [SwiftTerm.Color] {
        ansiColors.map { nsColor -> SwiftTerm.Color in
            let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
            return SwiftTerm.Color(
                red: UInt16(c.redComponent * 65535),
                green: UInt16(c.greenComponent * 65535),
                blue: UInt16(c.blueComponent * 65535)
            )
        }
    }

    // Derived chrome colors for the full-app theming
    var chromeBackground: NSColor {
        background.blended(withFraction: 0.1, of: .white) ?? background
    }

    var chromeBackgroundDarker: NSColor {
        background.blended(withFraction: 0.05, of: .white) ?? background
    }

    var chromeForeground: NSColor {
        foreground
    }

    var chromeSecondary: NSColor {
        foreground.withAlphaComponent(0.5)
    }

    var chromeAccent: NSColor {
        cursor
    }

    var chromeDivider: NSColor {
        foreground.withAlphaComponent(0.12)
    }

    static let allThemes: [TerminalTheme] = [
        .default, .dracula, .oneDark, .solarizedDark, .solarizedLight,
        .nord, .monokai, .tokyoNight, .gruvboxDark, .catppuccinMocha
    ]

    static func theme(forId id: String) -> TerminalTheme {
        allThemes.first { $0.id == id } ?? .default
    }
}

// MARK: - Helper

private func hex(_ hex: String) -> NSColor {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let scanner = Scanner(string: h)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)
    return NSColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255,
        alpha: 1
    )
}

// MARK: - Theme Definitions

extension TerminalTheme {
    static let `default` = TerminalTheme(
        id: "default",
        name: "Default",
        background: NSColor(white: 0.1, alpha: 1),
        foreground: NSColor(white: 0.9, alpha: 1),
        cursor: NSColor(white: 0.9, alpha: 1),
        selection: NSColor(white: 0.3, alpha: 1),
        ansiColors: [
            hex("000000"), hex("CC0000"), hex("4E9A06"), hex("C4A000"),
            hex("3465A4"), hex("75507B"), hex("06989A"), hex("D3D7CF"),
            hex("555753"), hex("EF2929"), hex("8AE234"), hex("FCE94F"),
            hex("729FCF"), hex("AD7FA8"), hex("34E2E2"), hex("EEEEEC"),
        ]
    )

    static let dracula = TerminalTheme(
        id: "dracula",
        name: "Dracula",
        background: hex("282A36"),
        foreground: hex("F8F8F2"),
        cursor: hex("F8F8F2"),
        selection: hex("44475A"),
        ansiColors: [
            hex("21222C"), hex("FF5555"), hex("50FA7B"), hex("F1FA8C"),
            hex("BD93F9"), hex("FF79C6"), hex("8BE9FD"), hex("F8F8F2"),
            hex("6272A4"), hex("FF6E6E"), hex("69FF94"), hex("FFFFA5"),
            hex("D6ACFF"), hex("FF92DF"), hex("A4FFFF"), hex("FFFFFF"),
        ]
    )

    static let oneDark = TerminalTheme(
        id: "one-dark",
        name: "One Dark",
        background: hex("282C34"),
        foreground: hex("ABB2BF"),
        cursor: hex("528BFF"),
        selection: hex("3E4451"),
        ansiColors: [
            hex("282C34"), hex("E06C75"), hex("98C379"), hex("E5C07B"),
            hex("61AFEF"), hex("C678DD"), hex("56B6C2"), hex("ABB2BF"),
            hex("5C6370"), hex("E06C75"), hex("98C379"), hex("E5C07B"),
            hex("61AFEF"), hex("C678DD"), hex("56B6C2"), hex("FFFFFF"),
        ]
    )

    static let solarizedDark = TerminalTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        background: hex("002B36"),
        foreground: hex("839496"),
        cursor: hex("839496"),
        selection: hex("073642"),
        ansiColors: [
            hex("073642"), hex("DC322F"), hex("859900"), hex("B58900"),
            hex("268BD2"), hex("D33682"), hex("2AA198"), hex("EEE8D5"),
            hex("002B36"), hex("CB4B16"), hex("586E75"), hex("657B83"),
            hex("839496"), hex("6C71C4"), hex("93A1A1"), hex("FDF6E3"),
        ]
    )

    static let solarizedLight = TerminalTheme(
        id: "solarized-light",
        name: "Solarized Light",
        background: hex("FDF6E3"),
        foreground: hex("657B83"),
        cursor: hex("657B83"),
        selection: hex("EEE8D5"),
        ansiColors: [
            hex("073642"), hex("DC322F"), hex("859900"), hex("B58900"),
            hex("268BD2"), hex("D33682"), hex("2AA198"), hex("EEE8D5"),
            hex("002B36"), hex("CB4B16"), hex("586E75"), hex("657B83"),
            hex("839496"), hex("6C71C4"), hex("93A1A1"), hex("FDF6E3"),
        ]
    )

    static let nord = TerminalTheme(
        id: "nord",
        name: "Nord",
        background: hex("2E3440"),
        foreground: hex("D8DEE9"),
        cursor: hex("D8DEE9"),
        selection: hex("434C5E"),
        ansiColors: [
            hex("3B4252"), hex("BF616A"), hex("A3BE8C"), hex("EBCB8B"),
            hex("81A1C1"), hex("B48EAD"), hex("88C0D0"), hex("E5E9F0"),
            hex("4C566A"), hex("BF616A"), hex("A3BE8C"), hex("EBCB8B"),
            hex("81A1C1"), hex("B48EAD"), hex("8FBCBB"), hex("ECEFF4"),
        ]
    )

    static let monokai = TerminalTheme(
        id: "monokai",
        name: "Monokai",
        background: hex("272822"),
        foreground: hex("F8F8F2"),
        cursor: hex("F8F8F0"),
        selection: hex("49483E"),
        ansiColors: [
            hex("272822"), hex("F92672"), hex("A6E22E"), hex("F4BF75"),
            hex("66D9EF"), hex("AE81FF"), hex("A1EFE4"), hex("F8F8F2"),
            hex("75715E"), hex("F92672"), hex("A6E22E"), hex("F4BF75"),
            hex("66D9EF"), hex("AE81FF"), hex("A1EFE4"), hex("F9F8F5"),
        ]
    )

    static let tokyoNight = TerminalTheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        background: hex("1A1B26"),
        foreground: hex("C0CAF5"),
        cursor: hex("C0CAF5"),
        selection: hex("33467C"),
        ansiColors: [
            hex("15161E"), hex("F7768E"), hex("9ECE6A"), hex("E0AF68"),
            hex("7AA2F7"), hex("BB9AF7"), hex("7DCFFF"), hex("A9B1D6"),
            hex("414868"), hex("F7768E"), hex("9ECE6A"), hex("E0AF68"),
            hex("7AA2F7"), hex("BB9AF7"), hex("7DCFFF"), hex("C0CAF5"),
        ]
    )

    static let gruvboxDark = TerminalTheme(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        background: hex("282828"),
        foreground: hex("EBDBB2"),
        cursor: hex("EBDBB2"),
        selection: hex("3C3836"),
        ansiColors: [
            hex("282828"), hex("CC241D"), hex("98971A"), hex("D79921"),
            hex("458588"), hex("B16286"), hex("689D6A"), hex("A89984"),
            hex("928374"), hex("FB4934"), hex("B8BB26"), hex("FABD2F"),
            hex("83A598"), hex("D3869B"), hex("8EC07C"), hex("EBDBB2"),
        ]
    )

    static let catppuccinMocha = TerminalTheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        background: hex("1E1E2E"),
        foreground: hex("CDD6F4"),
        cursor: hex("F5E0DC"),
        selection: hex("45475A"),
        ansiColors: [
            hex("45475A"), hex("F38BA8"), hex("A6E3A1"), hex("F9E2AF"),
            hex("89B4FA"), hex("F5C2E7"), hex("94E2D5"), hex("BAC2DE"),
            hex("585B70"), hex("F38BA8"), hex("A6E3A1"), hex("F9E2AF"),
            hex("89B4FA"), hex("F5C2E7"), hex("94E2D5"), hex("A6ADC8"),
        ]
    )
}
