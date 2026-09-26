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
// Новое поле добавляется в трёх местах. Объявление со значением по умолчанию
// в init(), чтение в init(from:) через decodeIfPresent и запись в encode.
// Старые сохранённые настройки без нового поля читаются со значением по
// умолчанию.
//
// Кодировщик Postbox не умеет словари со строковыми ключами и массивы Double,
// чтение таких полей роняет приложение. Храним только Int32, Int64, String,
// Bool через Int32 и массивы Int32, Int64, String.
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
    // Главные правки форка. Удалённые остаются, правки сохраняются
    public var antiDelete: Bool
    public var editHistory: Bool

    // Мелкие добавки в интерфейс, у каждой свой тумблер
    public var showContactBadge: Bool
    public var showNoteInHeader: Bool
    public var showPeerId: Bool

    // Список «Без ответа». Личные чаты, где последним написал собеседник.
    // Порог в часах, сколько он должен ждать, чтобы попасть в список. Ноль
    // значит сразу.
    public var unansweredFilter: Bool
    public var unansweredHours: Int32

    // Шаблоны быстрых ответов. Кнопка в поле ввода открывает список,
    // выбранный текст вставляется туда, где стоит курсор.
    public var quickReplies: Bool
    // Пункт «Все сообщения автора» в меню сообщения в группе
    public var authorMessages: Bool
    // Пункт «Выгрузить чат в файл» в профиле
    public var chatExport: Bool
    // Фото и видео из галереи уходят оригиналом, файлом
    public var mediaNoCompression: Bool

    // Face ID на отдельные чаты. Идентификаторы в виде toInt64, логика в
    // DkxChatLock
    public var chatLock: Bool

    // Разделы «Мои дела» и «Пароли» в главных настройках
    public var todoEnabled: Bool
    public var passwordsEnabled: Bool
    // Пункт «В Google Drive» в меню медиа
    public var driveEnabled: Bool
    // Пункт «Напомнить позже» в меню чата в списке и в меню сообщения
    public var remindLater: Bool
    // Расшифровка голосовых и кружков на телефоне, когда нет Premium, и её язык
    public var localTranscription: Bool
    public var transcriptionLocale: String
    // «Улучшить текст». Последние выбранные стиль, смайлики, обращение и язык,
    // свой стиль текстом и счётчик запросов за день, день в виде ГГГГММДД
    public var improveText: Bool
    public var improveStyle: Int32
    public var improveCustom: String
    public var improveEmoji: Int32
    public var improveAddress: Int32
    public var improveLanguage: Int32
    public var improveDay: Int32
    public var improveCount: Int32
    public var lockedPeers: [Int64]
    public var quickReplyTemplates: [String]
    // Спрятанные вкладки и строки настроек, rawValue из DkxHiddenSection
    public var hiddenSections: [String]
    // Метки на чаты, разбор в DkxChatLabels. Сами метки тремя массивами,
    // назначения парами «чат, метка» двумя
    public var labelIds: [Int32]
    public var labelTitles: [String]
    public var labelColors: [Int32]
    public var labelPeers: [Int64]
    public var labelPeerLabels: [Int32]
    // Своё закрепление чатов, только на этом телефоне. Первый в списке выше всех
    public var localPins: [Int64]

    // Панель подмены на экране карты. Выключенная прячет панель, и
    // приложение отдаёт настоящую геопозицию.
    public var spoofPanel: Bool
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
    // Ехать по дорогам. Путь из маршрутизатора, широта и долгота подряд.
    // Пустой путь значит прямую из А в Б. routePathSource для показа, кто
    // проложил маршрут. На диск путь пишется строкой через запятую.
    public var routeByRoads: Bool
    public var routePath: [Double]
    public var routePathSource: String

    public static var defaultSettings: DkxSettings {
        return DkxSettings()
    }

    public init() {
        self.hideStories = false
        self.hidePremiumPromo = false
        self.antiDelete = true
        self.editHistory = true
        self.showContactBadge = true
        self.showNoteInHeader = true
        self.showPeerId = true
        self.unansweredFilter = true
        self.unansweredHours = 0
        self.quickReplies = true
        self.authorMessages = true
        self.chatExport = true
        self.mediaNoCompression = false
        self.chatLock = true
        self.todoEnabled = true
        self.passwordsEnabled = true
        self.driveEnabled = false
        self.remindLater = true
        self.localTranscription = true
        self.transcriptionLocale = "ru-RU"
        self.improveText = true
        self.improveStyle = 0
        self.improveCustom = ""
        self.improveEmoji = 1
        self.improveAddress = 2
        self.improveLanguage = 0
        self.improveDay = 0
        self.improveCount = 0
        self.lockedPeers = []
        self.quickReplyTemplates = []
        self.hiddenSections = []
        self.labelIds = []
        self.labelTitles = []
        self.labelColors = []
        self.labelPeers = []
        self.labelPeerLabels = []
        self.localPins = []
        self.spoofPanel = true
        self.spoofLocation = false
        self.spoofMode = .point
        self.spoofCoordinate = ""
        self.routeFrom = ""
        self.routeTo = ""
        self.routeSpeed = 15
        self.routeStartedAt = 0
        self.routeByRoads = true
        self.routePath = []
        self.routePathSource = ""
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

    // Путь, по которому едет маршрут. По дорогам, если он проложен, иначе
    // прямая из А в Б. nil, если какой-то из точек нет.
    public var effectiveRoutePath: [Double]? {
        guard let from = DkxSettings.parseCoordinate(self.routeFrom), let to = DkxSettings.parseCoordinate(self.routeTo) else {
            return nil
        }
        if self.routeByRoads && self.routePath.count >= 4 {
            return self.routePath
        }
        return [from.latitude, from.longitude, to.latitude, to.longitude]
    }

    static func encodePath(_ path: [Double]) -> String {
        return path.map { String($0) }.joined(separator: ",")
    }

    static func decodePath(_ text: String) -> [Double] {
        return text.split(separator: ",").compactMap { Double($0) }
    }

    public static func formatCoordinate(latitude: Double, longitude: Double) -> String {
        return String(format: "%.6f, %.6f", latitude, longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        let defaults = DkxSettings()
        self.hideStories = (try container.decodeIfPresent(Int32.self, forKey: "hideStories") ?? 0) != 0
        self.hidePremiumPromo = (try container.decodeIfPresent(Int32.self, forKey: "hidePremiumPromo") ?? 0) != 0
        self.antiDelete = (try container.decodeIfPresent(Int32.self, forKey: "antiDelete")).map { $0 != 0 } ?? defaults.antiDelete
        self.editHistory = (try container.decodeIfPresent(Int32.self, forKey: "editHistory")).map { $0 != 0 } ?? defaults.editHistory
        self.showContactBadge = (try container.decodeIfPresent(Int32.self, forKey: "showContactBadge")).map { $0 != 0 } ?? defaults.showContactBadge
        self.showNoteInHeader = (try container.decodeIfPresent(Int32.self, forKey: "showNoteInHeader")).map { $0 != 0 } ?? defaults.showNoteInHeader
        self.showPeerId = (try container.decodeIfPresent(Int32.self, forKey: "showPeerId")).map { $0 != 0 } ?? defaults.showPeerId
        self.unansweredFilter = (try container.decodeIfPresent(Int32.self, forKey: "unansweredFilter")).map { $0 != 0 } ?? defaults.unansweredFilter
        self.unansweredHours = (try container.decodeIfPresent(Int32.self, forKey: "unansweredHours")) ?? defaults.unansweredHours
        self.quickReplies = (try container.decodeIfPresent(Int32.self, forKey: "quickReplies")).map { $0 != 0 } ?? defaults.quickReplies
        self.authorMessages = (try container.decodeIfPresent(Int32.self, forKey: "authorMessages")).map { $0 != 0 } ?? defaults.authorMessages
        self.chatExport = (try container.decodeIfPresent(Int32.self, forKey: "chatExport")).map { $0 != 0 } ?? defaults.chatExport
        self.mediaNoCompression = (try container.decodeIfPresent(Int32.self, forKey: "mediaNoCompression")).map { $0 != 0 } ?? defaults.mediaNoCompression
        self.chatLock = (try container.decodeIfPresent(Int32.self, forKey: "chatLock")).map { $0 != 0 } ?? defaults.chatLock
        self.todoEnabled = (try container.decodeIfPresent(Int32.self, forKey: "todoEnabled")).map { $0 != 0 } ?? defaults.todoEnabled
        self.passwordsEnabled = (try container.decodeIfPresent(Int32.self, forKey: "passwordsEnabled")).map { $0 != 0 } ?? defaults.passwordsEnabled
        self.driveEnabled = (try container.decodeIfPresent(Int32.self, forKey: "driveEnabled")).map { $0 != 0 } ?? defaults.driveEnabled
        self.remindLater = (try container.decodeIfPresent(Int32.self, forKey: "remindLater")).map { $0 != 0 } ?? defaults.remindLater
        self.localTranscription = (try container.decodeIfPresent(Int32.self, forKey: "localTranscription")).map { $0 != 0 } ?? defaults.localTranscription
        self.transcriptionLocale = (try container.decodeIfPresent(String.self, forKey: "transcriptionLocale")) ?? defaults.transcriptionLocale
        self.improveText = (try container.decodeIfPresent(Int32.self, forKey: "improveText")).map { $0 != 0 } ?? defaults.improveText
        self.improveStyle = (try container.decodeIfPresent(Int32.self, forKey: "improveStyle")) ?? defaults.improveStyle
        self.improveCustom = (try container.decodeIfPresent(String.self, forKey: "improveCustom")) ?? defaults.improveCustom
        self.improveEmoji = (try container.decodeIfPresent(Int32.self, forKey: "improveEmoji")) ?? defaults.improveEmoji
        self.improveAddress = (try container.decodeIfPresent(Int32.self, forKey: "improveAddress")) ?? defaults.improveAddress
        self.improveLanguage = (try container.decodeIfPresent(Int32.self, forKey: "improveLanguage")) ?? defaults.improveLanguage
        self.improveDay = (try container.decodeIfPresent(Int32.self, forKey: "improveDay")) ?? defaults.improveDay
        self.improveCount = (try container.decodeIfPresent(Int32.self, forKey: "improveCount")) ?? defaults.improveCount
        self.lockedPeers = (try container.decodeIfPresent([Int64].self, forKey: "lockedPeers")) ?? defaults.lockedPeers
        self.quickReplyTemplates = (try container.decodeIfPresent([String].self, forKey: "quickReplyTemplates")) ?? defaults.quickReplyTemplates
        self.hiddenSections = (try container.decodeIfPresent([String].self, forKey: "hiddenSections")) ?? defaults.hiddenSections
        self.labelIds = (try container.decodeIfPresent([Int32].self, forKey: "labelIds")) ?? defaults.labelIds
        self.labelTitles = (try container.decodeIfPresent([String].self, forKey: "labelTitles")) ?? defaults.labelTitles
        self.labelColors = (try container.decodeIfPresent([Int32].self, forKey: "labelColors")) ?? defaults.labelColors
        self.labelPeers = (try container.decodeIfPresent([Int64].self, forKey: "labelPeers")) ?? defaults.labelPeers
        self.labelPeerLabels = (try container.decodeIfPresent([Int32].self, forKey: "labelPeerLabels")) ?? defaults.labelPeerLabels
        self.localPins = (try container.decodeIfPresent([Int64].self, forKey: "localPins")) ?? defaults.localPins
        self.spoofPanel = (try container.decodeIfPresent(Int32.self, forKey: "spoofPanel")).map { $0 != 0 } ?? defaults.spoofPanel
        self.spoofLocation = (try container.decodeIfPresent(Int32.self, forKey: "spoofLocation") ?? 0) != 0
        self.spoofMode = SpoofMode(rawValue: (try container.decodeIfPresent(Int32.self, forKey: "spoofMode")) ?? defaults.spoofMode.rawValue) ?? defaults.spoofMode
        self.spoofCoordinate = (try container.decodeIfPresent(String.self, forKey: "spoofCoordinate")) ?? defaults.spoofCoordinate
        self.routeFrom = (try container.decodeIfPresent(String.self, forKey: "routeFrom")) ?? defaults.routeFrom
        self.routeTo = (try container.decodeIfPresent(String.self, forKey: "routeTo")) ?? defaults.routeTo
        self.routeSpeed = (try container.decodeIfPresent(Int32.self, forKey: "routeSpeed")) ?? defaults.routeSpeed
        self.routeStartedAt = (try container.decodeIfPresent(Int32.self, forKey: "routeStartedAt")) ?? defaults.routeStartedAt
        self.routeByRoads = (try container.decodeIfPresent(Int32.self, forKey: "routeByRoads")).map { $0 != 0 } ?? defaults.routeByRoads
        self.routePath = (try container.decodeIfPresent(String.self, forKey: "routePathText")).map(DkxSettings.decodePath) ?? defaults.routePath
        self.routePathSource = (try container.decodeIfPresent(String.self, forKey: "routePathSource")) ?? defaults.routePathSource
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.hideStories ? 1 : 0) as Int32, forKey: "hideStories")
        try container.encode((self.hidePremiumPromo ? 1 : 0) as Int32, forKey: "hidePremiumPromo")
        try container.encode((self.antiDelete ? 1 : 0) as Int32, forKey: "antiDelete")
        try container.encode((self.editHistory ? 1 : 0) as Int32, forKey: "editHistory")
        try container.encode((self.showContactBadge ? 1 : 0) as Int32, forKey: "showContactBadge")
        try container.encode((self.showNoteInHeader ? 1 : 0) as Int32, forKey: "showNoteInHeader")
        try container.encode((self.showPeerId ? 1 : 0) as Int32, forKey: "showPeerId")
        try container.encode((self.unansweredFilter ? 1 : 0) as Int32, forKey: "unansweredFilter")
        try container.encode(self.unansweredHours, forKey: "unansweredHours")
        try container.encode((self.quickReplies ? 1 : 0) as Int32, forKey: "quickReplies")
        try container.encode((self.authorMessages ? 1 : 0) as Int32, forKey: "authorMessages")
        try container.encode((self.chatExport ? 1 : 0) as Int32, forKey: "chatExport")
        try container.encode((self.mediaNoCompression ? 1 : 0) as Int32, forKey: "mediaNoCompression")
        try container.encode((self.chatLock ? 1 : 0) as Int32, forKey: "chatLock")
        try container.encode((self.todoEnabled ? 1 : 0) as Int32, forKey: "todoEnabled")
        try container.encode((self.passwordsEnabled ? 1 : 0) as Int32, forKey: "passwordsEnabled")
        try container.encode((self.driveEnabled ? 1 : 0) as Int32, forKey: "driveEnabled")
        try container.encode((self.remindLater ? 1 : 0) as Int32, forKey: "remindLater")
        try container.encode((self.localTranscription ? 1 : 0) as Int32, forKey: "localTranscription")
        try container.encode(self.transcriptionLocale, forKey: "transcriptionLocale")
        try container.encode((self.improveText ? 1 : 0) as Int32, forKey: "improveText")
        try container.encode(self.improveStyle, forKey: "improveStyle")
        try container.encode(self.improveCustom, forKey: "improveCustom")
        try container.encode(self.improveEmoji, forKey: "improveEmoji")
        try container.encode(self.improveAddress, forKey: "improveAddress")
        try container.encode(self.improveLanguage, forKey: "improveLanguage")
        try container.encode(self.improveDay, forKey: "improveDay")
        try container.encode(self.improveCount, forKey: "improveCount")
        try container.encode(self.lockedPeers, forKey: "lockedPeers")
        try container.encode(self.quickReplyTemplates, forKey: "quickReplyTemplates")
        try container.encode(self.hiddenSections, forKey: "hiddenSections")
        try container.encode(self.labelIds, forKey: "labelIds")
        try container.encode(self.labelTitles, forKey: "labelTitles")
        try container.encode(self.labelColors, forKey: "labelColors")
        try container.encode(self.labelPeers, forKey: "labelPeers")
        try container.encode(self.labelPeerLabels, forKey: "labelPeerLabels")
        try container.encode(self.localPins, forKey: "localPins")
        try container.encode((self.spoofPanel ? 1 : 0) as Int32, forKey: "spoofPanel")
        try container.encode((self.spoofLocation ? 1 : 0) as Int32, forKey: "spoofLocation")
        try container.encode(self.spoofMode.rawValue, forKey: "spoofMode")
        try container.encode(self.spoofCoordinate, forKey: "spoofCoordinate")
        try container.encode(self.routeFrom, forKey: "routeFrom")
        try container.encode(self.routeTo, forKey: "routeTo")
        try container.encode(self.routeSpeed, forKey: "routeSpeed")
        try container.encode(self.routeStartedAt, forKey: "routeStartedAt")
        try container.encode((self.routeByRoads ? 1 : 0) as Int32, forKey: "routeByRoads")
        try container.encode(DkxSettings.encodePath(self.routePath), forKey: "routePathText")
        try container.encode(self.routePathSource, forKey: "routePathSource")
    }
}

// Снимок настроек для мест, где подписаться на сигнал неудобно. Это ячейки
// списков, шапка чата, строки профиля. Обновляет его SharedAccountContext при
// запуске и при каждой правке настроек. Экран, открытый в момент правки,
// увидит новое значение при следующей перерисовке.
//
// До первой загрузки настроек тут значения по умолчанию, это доли секунды
// после запуска.
public final class DkxRuntime {
    private static let lock = NSLock()
    private static var value = DkxSettings.defaultSettings
    // Строки списка чатов спрашивают метки на каждой перерисовке, поэтому
    // готовая раскладка по чатам, а не проход по парам каждый раз
    private static var labelsByPeer: [Int64: [DkxChatLabel]] = [:]
    // Главный список чатов подписан на своё закрепление, ему нужен сигнал
    private static let localPinsPromise = ValuePromise<[Int64]>([], ignoreRepeated: true)
    private static var language = "ru"

    public static var languageCode: String {
        lock.lock()
        let result = language
        lock.unlock()
        return result
    }

    public static func updateLanguage(_ code: String) {
        let normalized = code.lowercased()
        lock.lock()
        language = normalized
        lock.unlock()
    }

    public static var localPinsSignal: Signal<[Int64], NoError> {
        return localPinsPromise.get()
    }

    public static var current: DkxSettings {
        lock.lock()
        let result = value
        lock.unlock()
        return result
    }

    public static func update(_ settings: DkxSettings) {
        let labels = settings.chatLabelsByPeer()
        lock.lock()
        value = settings
        labelsByPeer = labels
        lock.unlock()
        localPinsPromise.set(settings.localPins)
    }

    public static func chatLabels(forPeer peerId: Int64) -> [DkxChatLabel] {
        lock.lock()
        let result = labelsByPeer[peerId] ?? []
        lock.unlock()
        return result
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
