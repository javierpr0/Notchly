import Foundation

/// Non-secret Telegram integration settings. The bot token itself lives in
/// Keychain (TelegramKeychain), never here — this file is chmod 0600 but
/// still plaintext JSON, not a place for a credential.
struct TelegramConfig: Codable, Equatable {
    var enabled: Bool = false
    var chatId: String = ""
    var freeTextEnabled: Bool = false
    /// Raw keystroke to send for "Deny" / "Always allow" buttons. Empty means
    /// the button isn't shown — see TelegramConfig.decodeKeystroke for syntax.
    var denyKeystroke: String = ""
    var alwaysAllowKeystroke: String = ""

    /// Expands a small escape syntax typed into a settings TextField into raw
    /// bytes to send to the terminal: \r \n \t and \xHH (arbitrary hex byte,
    /// e.g. \x1b for Escape). Anything else passes through literally.
    static func decodeKeystroke(_ raw: String) -> String {
        let chars = Array(raw)
        var result = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count {
                switch chars[i + 1] {
                case "r": result.append("\r"); i += 2; continue
                case "n": result.append("\n"); i += 2; continue
                case "t": result.append("\t"); i += 2; continue
                case "x":
                    if i + 3 < chars.count, let byte = UInt8(String(chars[(i + 2)...(i + 3)]), radix: 16) {
                        result.append(Character(UnicodeScalar(byte)))
                        i += 4
                        continue
                    }
                default: break
                }
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }
}

@Observable
@MainActor
final class TelegramConfigStore {
    static let shared = TelegramConfigStore()

    private let dir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".notchly")
    }()
    private var fileURL: URL { dir.appendingPathComponent("telegram.json") }

    var config: TelegramConfig {
        didSet {
            guard config != oldValue else { return }
            save()
            if config.enabled != oldValue.enabled {
                TelegramService.shared.restart()
            }
        }
    }

    private init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

        // Build the path inline rather than via the `fileURL` computed
        // property — calling any computed property/method on self isn't
        // allowed until every stored property (incl. `config`) has a value.
        let file = dir.appendingPathComponent("telegram.json")
        if let data = try? Data(contentsOf: file), let loaded = try? JSONDecoder().decode(TelegramConfig.self, from: data) {
            config = loaded
        } else {
            config = TelegramConfig()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
