import Foundation
import TelegramCore
import SwiftSignalKit

// Настройки форка. Сюда добавляются все тумблеры, которые живут в слое
// интерфейса. Читаются через sharedData по ключу ApplicationSpecificSharedDataKeys.dkxSettings.
//
// Важно про слой. Отсюда нельзя управлять поведением из TelegramCore, потому
// что TelegramUIPreferences зависит от TelegramCore, а не наоборот. Поэтому
// сохранение удалённых сообщений и история правок тумблеров не имеют, они
// зашиты. Тут только то, что решает интерфейс.
public struct DkxSettings: Codable, Equatable {
    // Лента сторис над списком чатов
    public var hideStories: Bool
    // Предложения премиума, подсказки покупки, навязчивые баннеры
    public var hidePremiumPromo: Bool

    public static var defaultSettings: DkxSettings {
        return DkxSettings(
            hideStories: false,
            hidePremiumPromo: false
        )
    }

    public init(hideStories: Bool, hidePremiumPromo: Bool) {
        self.hideStories = hideStories
        self.hidePremiumPromo = hidePremiumPromo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.hideStories = (try container.decodeIfPresent(Int32.self, forKey: "hideStories") ?? 0) != 0
        self.hidePremiumPromo = (try container.decodeIfPresent(Int32.self, forKey: "hidePremiumPromo") ?? 0) != 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.hideStories ? 1 : 0) as Int32, forKey: "hideStories")
        try container.encode((self.hidePremiumPromo ? 1 : 0) as Int32, forKey: "hidePremiumPromo")
    }
}

public func updateDkxSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (DkxSettings) -> DkxSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.dkxSettings, { entry in
            let currentSettings: DkxSettings
            if let entry = entry?.get(DkxSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = DkxSettings.defaultSettings
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
