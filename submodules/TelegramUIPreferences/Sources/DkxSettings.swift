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
//
// Новое поле добавляется в трёх местах: объявление со значением по умолчанию
// в init(), чтение в init(from:) через decodeIfPresent и запись в encode.
// Старые сохранённые настройки без нового поля читаются со значением по
// умолчанию.
public struct DkxSettings: Codable, Equatable {
    public enum SpoofMode: Int32 {
        // Координата стоит в одной точке
        case point = 0
        // Координата едет по прямой из А в Б
        case route = 1
    }

    // Лента сторис над списком чатов
    public var hideStories: Bool
    // Предложения премиума, подсказки покупки, навязчивые баннеры
    public var hidePremiumPromo: Bool
    // Личные заметки на чаты. Ключ это идентификатор собеседника строкой,
    // потому что Codable плохо работает со словарями с числовыми ключами.
    // Заметка видна только владельцу и на сервер не уходит.
    public var chatNotes: [String: String]

    // Подмена координат, общий выключатель
    public var spoofLocation: Bool
    public var spoofMode: SpoofMode
    // Координаты хранятся текстом, ровно как введены или выбраны, в виде
    // «широта, долгота». Так их можно вставить из карт одной строкой.
    public var spoofCoordinate: String
    public var routeFrom: String
    public var routeTo: String
    // Скорость движения по маршруту, км/ч
    public var routeSpeed: Int32
    // Момент нажатия «Поехали», секунды от 1970. Ноль значит, что движение
    // не запущено и координата стоит в точке А.
    public var routeStartedAt: Int32

    public static var defaultSettings: DkxSettings {
        return DkxSettings()
    }

    public init() {
        self.hideStories = false
        self.hidePremiumPromo = false
        self.chatNotes = [:]
        self.spoofLocation = false
        self.spoofMode = .point
        self.spoofCoordinate = ""
        self.routeFrom = ""
        self.routeTo = ""
        self.routeSpeed = 15
        self.routeStartedAt = 0
    }

    public func note(for peerId: Int64) -> String? {
        if let value = self.chatNotes[String(peerId)], !value.isEmpty {
            return value
        }
        return nil
    }

    // Разбирает строку вида «48.858370, 2.294481». Точка с запятой и
    // пробелы допускаются, потому что карты копируют по-разному.
    public static func parseCoordinate(_ text: String) -> (latitude: Double, longitude: Double)? {
        let parts = text.replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2 else {
            return nil
        }
        guard let latitude = Double(parts[0]), let longitude = Double(parts[1]) else {
            return nil
        }
        guard latitude >= -90.0, latitude <= 90.0, longitude >= -180.0, longitude <= 180.0 else {
            return nil
        }
        return (latitude, longitude)
    }

    public static func formatCoordinate(latitude: Double, longitude: Double) -> String {
        return String(format: "%.6f, %.6f", latitude, longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        let defaults = DkxSettings()
        self.hideStories = (try container.decodeIfPresent(Int32.self, forKey: "hideStories") ?? 0) != 0
        self.hidePremiumPromo = (try container.decodeIfPresent(Int32.self, forKey: "hidePremiumPromo") ?? 0) != 0
        self.chatNotes = (try container.decodeIfPresent([String: String].self, forKey: "chatNotes")) ?? defaults.chatNotes
        self.spoofLocation = (try container.decodeIfPresent(Int32.self, forKey: "spoofLocation") ?? 0) != 0
        self.spoofMode = SpoofMode(rawValue: (try container.decodeIfPresent(Int32.self, forKey: "spoofMode")) ?? defaults.spoofMode.rawValue) ?? defaults.spoofMode
        self.spoofCoordinate = (try container.decodeIfPresent(String.self, forKey: "spoofCoordinate")) ?? defaults.spoofCoordinate
        self.routeFrom = (try container.decodeIfPresent(String.self, forKey: "routeFrom")) ?? defaults.routeFrom
        self.routeTo = (try container.decodeIfPresent(String.self, forKey: "routeTo")) ?? defaults.routeTo
        self.routeSpeed = (try container.decodeIfPresent(Int32.self, forKey: "routeSpeed")) ?? defaults.routeSpeed
        self.routeStartedAt = (try container.decodeIfPresent(Int32.self, forKey: "routeStartedAt")) ?? defaults.routeStartedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.hideStories ? 1 : 0) as Int32, forKey: "hideStories")
        try container.encode((self.hidePremiumPromo ? 1 : 0) as Int32, forKey: "hidePremiumPromo")
        try container.encode(self.chatNotes, forKey: "chatNotes")
        try container.encode((self.spoofLocation ? 1 : 0) as Int32, forKey: "spoofLocation")
        try container.encode(self.spoofMode.rawValue, forKey: "spoofMode")
        try container.encode(self.spoofCoordinate, forKey: "spoofCoordinate")
        try container.encode(self.routeFrom, forKey: "routeFrom")
        try container.encode(self.routeTo, forKey: "routeTo")
        try container.encode(self.routeSpeed, forKey: "routeSpeed")
        try container.encode(self.routeStartedAt, forKey: "routeStartedAt")
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
