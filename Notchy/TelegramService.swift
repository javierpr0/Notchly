import Foundation
import os

private let logger = Logger(subsystem: "com.notchly", category: "TelegramService")

/// Owns the Telegram long-polling loop and routes messages/button taps back
/// into the right terminal pane. Entirely opt-in — a no-op unless enabled in
/// settings with a saved token and chat id.
@Observable
@MainActor
final class TelegramService {
    static let shared = TelegramService()

    private static let lastOffsetKey = "telegramLastUpdateOffset"

    private var pollTask: Task<Void, Never>?
    private var lastOffset: Int {
        get { UserDefaults.standard.integer(forKey: Self.lastOffsetKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastOffsetKey) }
    }

    // ponytail: in-memory only, lost on relaunch — a free-text reply-to an
    // alert sent before the last restart won't route. Button taps are
    // unaffected (paneId travels in callback_data, not this map). Persist
    // this if reply-to-old-alerts-after-restart turns out to matter.
    private var alertedPanes: [Int: UUID] = [:]

    private init() {}

    func startIfConfigured() {
        guard pollTask == nil else { return }
        let config = TelegramConfigStore.shared.config
        guard config.enabled, let token = TelegramKeychain.load(), !token.isEmpty else { return }
        let client = TelegramBotClient(token: token)
        pollTask = Task { [weak self] in await self?.pollLoop(client: client) }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func restart() {
        stop()
        startIfConfigured()
    }

    // MARK: - Outbound notifications (called from SessionStore)

    func notifyWaitingForInput(paneId: UUID, title: String, body: String) {
        send(paneId: paneId, title: title, body: body, includeButtons: true)
    }

    func notifyTaskCompleted(paneId: UUID, title: String, body: String) {
        send(paneId: paneId, title: title, body: body, includeButtons: false)
    }

    private func send(paneId: UUID, title: String, body: String, includeButtons: Bool) {
        let config = TelegramConfigStore.shared.config
        guard config.enabled, let chatId = Int64(config.chatId),
              let token = TelegramKeychain.load(), !token.isEmpty else { return }
        let client = TelegramBotClient(token: token)
        let text = "\(title)\n\(body)"

        var buttons: [[TelegramInlineButton]] = []
        if includeButtons {
            buttons.append([
                TelegramInlineButton(text: L10n.shared.telegramButtonApprove, callbackData: "approve|\(paneId.uuidString)"),
                TelegramInlineButton(text: L10n.shared.telegramButtonInterrupt, callbackData: "interrupt|\(paneId.uuidString)"),
            ])
            var extra: [TelegramInlineButton] = []
            if !config.denyKeystroke.isEmpty {
                extra.append(TelegramInlineButton(text: L10n.shared.telegramButtonDeny, callbackData: "deny|\(paneId.uuidString)"))
            }
            if !config.alwaysAllowKeystroke.isEmpty {
                extra.append(TelegramInlineButton(text: L10n.shared.telegramButtonAlwaysAllow, callbackData: "always_allow|\(paneId.uuidString)"))
            }
            if !extra.isEmpty { buttons.append(extra) }
        }

        Task { [weak self] in
            do {
                let messageId = try await client.sendMessage(chatId: chatId, text: text, buttons: buttons.isEmpty ? nil : buttons)
                if includeButtons { self?.alertedPanes[messageId] = paneId }
            } catch {
                logger.error("sendMessage failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Poll loop

    private func pollLoop(client: TelegramBotClient) async {
        do {
            try await client.deleteWebhook()
        } catch {
            logger.error("deleteWebhook failed: \(error.localizedDescription, privacy: .public)")
        }
        while !Task.isCancelled {
            do {
                let updates = try await client.getUpdates(offset: lastOffset + 1, timeoutSeconds: 25)
                for update in updates {
                    lastOffset = max(lastOffset, update.updateId)
                    await handle(update, client: client)
                }
            } catch {
                guard !Task.isCancelled else { break }
                logger.error("getUpdates failed: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func handle(_ update: TelegramUpdate, client: TelegramBotClient) async {
        // Whitelist: only the configured chat may ever act on anything. Read
        // live (not captured at loop start) so editing chat id while enabled
        // takes effect without a restart.
        let whitelisted = Int64(TelegramConfigStore.shared.config.chatId)

        if let callback = update.callbackQuery {
            guard let chatId = callback.message?.chat.id, whitelisted != nil, chatId == whitelisted else { return }
            await handleCallback(callback, client: client)
        } else if let message = update.message {
            guard whitelisted != nil, message.chat.id == whitelisted else { return }
            await handleMessage(message, client: client)
        }
    }

    private func handleCallback(_ callback: TelegramCallbackQuery, client: TelegramBotClient) async {
        guard let raw = callback.data else {
            try? await client.answerCallbackQuery(id: callback.id)
            return
        }
        let parts = raw.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let paneId = UUID(uuidString: String(parts[1])),
              let status = SessionStore.shared.paneStatus(for: paneId) else {
            try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckSessionUnavailable)
            return
        }

        switch String(parts[0]) {
        case "approve":
            guard status == .waitingForInput else {
                try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckNoLongerWaiting)
                return
            }
            TerminalManager.shared.sendCommand(to: paneId, command: "")
            try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckSent)

        case "interrupt":
            guard status != .sleeping else {
                try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckSleeping)
                return
            }
            TerminalManager.shared.sendRaw(to: paneId, text: "\u{03}")
            try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckSent)

        case "deny":
            let keystroke = TelegramConfigStore.shared.config.denyKeystroke
            guard status == .waitingForInput, !keystroke.isEmpty else {
                try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckNotAvailable)
                return
            }
            TerminalManager.shared.sendRaw(to: paneId, text: TelegramConfig.decodeKeystroke(keystroke))
            try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckSent)

        case "always_allow":
            let keystroke = TelegramConfigStore.shared.config.alwaysAllowKeystroke
            guard status == .waitingForInput, !keystroke.isEmpty else {
                try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckNotAvailable)
                return
            }
            TerminalManager.shared.sendRaw(to: paneId, text: TelegramConfig.decodeKeystroke(keystroke))
            try? await client.answerCallbackQuery(id: callback.id, text: L10n.shared.telegramAckSent)

        default:
            try? await client.answerCallbackQuery(id: callback.id)
        }
    }

    private func handleMessage(_ message: TelegramMessage, client: TelegramBotClient) async {
        guard TelegramConfigStore.shared.config.freeTextEnabled,
              let text = message.text, !text.isEmpty else { return }

        var targetPane: UUID?
        if let replyId = message.replyToMessage?.messageId, let mapped = alertedPanes[replyId] {
            targetPane = mapped
        } else {
            let waiting = SessionStore.shared.sessions.flatMap { session in
                session.paneStatuses.filter { $0.value == .waitingForInput }.map(\.key)
            }
            if waiting.count == 1 {
                targetPane = waiting[0]
            } else {
                let note = waiting.isEmpty ? L10n.shared.telegramNoSessionWaiting : L10n.shared.telegramMultipleWaiting
                try? await client.sendMessage(chatId: message.chat.id, text: note)
                return
            }
        }

        guard let paneId = targetPane, SessionStore.shared.paneStatus(for: paneId) != nil else {
            try? await client.sendMessage(chatId: message.chat.id, text: L10n.shared.telegramAckSessionUnavailable)
            return
        }
        TerminalManager.shared.sendCommand(to: paneId, command: text)
    }

    // MARK: - Settings helper (chat id discovery)

    /// Fetches the most recent message sent to the bot and returns its chat
    /// id, so Settings can offer "Detect chat ID" instead of making the user
    /// find their numeric Telegram id by hand. Pauses the live poll loop
    /// during the call (two concurrent getUpdates long-polls on the same
    /// token 409 each other) and resumes it afterward.
    func discoverChatId(token: String) async -> Int64? {
        let wasPolling = pollTask != nil
        stop()
        defer { if wasPolling { startIfConfigured() } }

        let client = TelegramBotClient(token: token)
        guard let updates = try? await client.getUpdates(offset: -1, timeoutSeconds: 0) else { return nil }
        return updates.last?.message?.chat.id ?? updates.last?.callbackQuery?.message?.chat.id
    }
}
