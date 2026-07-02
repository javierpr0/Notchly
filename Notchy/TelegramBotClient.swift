import Foundation

struct TelegramInlineButton {
    let text: String
    let callbackData: String
}

struct TelegramChat: Decodable {
    let id: Int64
}

struct TelegramUser: Decodable {
    let id: Int64
    let username: String?
}

/// Just enough of the replied-to message to match it against the alert we
/// sent (by message id) — decoding the full nested TelegramMessage here
/// would make TelegramMessage a self-referencing (infinite-size) struct.
struct TelegramReplyRef: Decodable {
    let messageId: Int
    enum CodingKeys: String, CodingKey { case messageId = "message_id" }
}

struct TelegramMessage: Decodable {
    let messageId: Int
    let chat: TelegramChat
    let from: TelegramUser?
    let text: String?
    let replyToMessage: TelegramReplyRef?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case chat, from, text
        case replyToMessage = "reply_to_message"
    }
}

struct TelegramCallbackQuery: Decodable {
    let id: String
    let from: TelegramUser
    let message: TelegramMessage?
    let data: String?
}

struct TelegramUpdate: Decodable {
    let updateId: Int
    let message: TelegramMessage?
    let callbackQuery: TelegramCallbackQuery?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
        case callbackQuery = "callback_query"
    }
}

private struct TelegramEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let description: String?
}

enum TelegramBotError: Error {
    case invalidToken
    case http(Int)
    case api(String)
}

/// Raw Telegram Bot API REST calls. No retry/lifecycle logic here — that's
/// TelegramService's job. Every call is a stateless POST with a JSON body,
/// which every Bot API method accepts (simpler than mixing GET query params).
struct TelegramBotClient {
    let token: String

    private func url(_ method: String) -> URL? {
        URL(string: "https://api.telegram.org/bot\(token)/\(method)")
    }

    private func post<T: Decodable>(_ method: String, body: [String: Any] = [:]) async throws -> T {
        guard let url = url(method) else { throw TelegramBotError.invalidToken }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TelegramBotError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let envelope = try JSONDecoder().decode(TelegramEnvelope<T>.self, from: data)
        guard envelope.ok, let result = envelope.result else {
            throw TelegramBotError.api(envelope.description ?? "unknown Telegram API error")
        }
        return result
    }

    /// Clears any webhook that may have been registered for this token
    /// elsewhere — getUpdates returns 409 Conflict until this is cleared.
    /// Safe to call unconditionally: it's a no-op if there's no webhook.
    func deleteWebhook() async throws {
        let _: Bool = try await post("deleteWebhook")
    }

    @discardableResult
    func sendMessage(chatId: Int64, text: String, buttons: [[TelegramInlineButton]]? = nil) async throws -> Int {
        var body: [String: Any] = ["chat_id": chatId, "text": text]
        if let buttons, !buttons.isEmpty {
            let keyboard = buttons.map { row in row.map { ["text": $0.text, "callback_data": $0.callbackData] } }
            body["reply_markup"] = ["inline_keyboard": keyboard]
        }
        let message: TelegramMessage = try await post("sendMessage", body: body)
        return message.messageId
    }

    func getUpdates(offset: Int, timeoutSeconds: Int) async throws -> [TelegramUpdate] {
        let body: [String: Any] = [
            "offset": offset,
            "timeout": timeoutSeconds,
            "allowed_updates": ["message", "callback_query"],
        ]
        return try await post("getUpdates", body: body)
    }

    func answerCallbackQuery(id: String, text: String? = nil) async throws {
        var body: [String: Any] = ["callback_query_id": id]
        if let text { body["text"] = text }
        let _: Bool = try await post("answerCallbackQuery", body: body)
    }
}
