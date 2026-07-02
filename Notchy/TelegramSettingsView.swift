import SwiftUI

/// Fills the app's Settings scene — opened from the gear popover's
/// "Telegram…" row (see PanelContentView.settingsMenuContent) since this
/// app is LSUIElement and has no conventional app menu.
struct TelegramSettingsView: View {
    @Bindable private var configStore = TelegramConfigStore.shared
    @State private var tokenInput = ""
    @State private var tokenSaved = TelegramKeychain.load() != nil
    @State private var isDetecting = false
    @State private var detectFailed = false

    var body: some View {
        Form {
            Section {
                Toggle(L10n.shared.telegramEnable, isOn: $configStore.config.enabled)
                Text(L10n.shared.telegramSetupIntro)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.shared.telegramToken) {
                SecureField(L10n.shared.telegramToken, text: $tokenInput)
                HStack {
                    Text(tokenSaved ? L10n.shared.telegramTokenSaved : L10n.shared.telegramTokenMissing)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.shared.telegramSaveToken) {
                        guard !tokenInput.isEmpty else { return }
                        TelegramKeychain.save(tokenInput)
                        tokenInput = ""
                        tokenSaved = true
                        TelegramService.shared.restart()
                    }
                    .disabled(tokenInput.isEmpty)
                    Button(L10n.shared.telegramRemoveToken) {
                        TelegramKeychain.delete()
                        tokenSaved = false
                        TelegramService.shared.restart()
                    }
                    .disabled(!tokenSaved)
                }
            }

            Section(L10n.shared.telegramChatId) {
                TextField(L10n.shared.telegramChatId, text: $configStore.config.chatId)
                HStack {
                    Button(isDetecting ? L10n.shared.telegramDetecting : L10n.shared.telegramDetectChatId) {
                        detectChatId()
                    }
                    .disabled(isDetecting)
                    if detectFailed {
                        Text(L10n.shared.telegramDetectFailed)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
            }

            Section {
                Toggle(L10n.shared.telegramFreeText, isOn: $configStore.config.freeTextEnabled)
                if configStore.config.freeTextEnabled {
                    Text(L10n.shared.telegramFreeTextWarning)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Section(L10n.shared.telegramAdvanced) {
                Text(L10n.shared.telegramAdvancedHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField(L10n.shared.telegramDenyKeystroke, text: $configStore.config.denyKeystroke)
                    .font(.system(size: 11, design: .monospaced))
                TextField(L10n.shared.telegramAlwaysAllowKeystroke, text: $configStore.config.alwaysAllowKeystroke)
                    .font(.system(size: 11, design: .monospaced))
            }

            Section {
                Text(L10n.shared.telegramTokenFooter)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 560)
        .navigationTitle(L10n.shared.telegram)
    }

    private func detectChatId() {
        let candidate = tokenInput.isEmpty ? TelegramKeychain.load() : tokenInput
        guard let token = candidate, !token.isEmpty else {
            detectFailed = true
            return
        }
        isDetecting = true
        detectFailed = false
        Task {
            let chatId = await TelegramService.shared.discoverChatId(token: token)
            isDetecting = false
            if let chatId {
                configStore.config.chatId = String(chatId)
            } else {
                detectFailed = true
            }
        }
    }
}
