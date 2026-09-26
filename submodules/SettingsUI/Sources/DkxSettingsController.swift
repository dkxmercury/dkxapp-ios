import Foundation
import CoreLocation
import AuthenticationServices
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import DeviceLocationManager

// Экран настроек форка. Сюда складываются все тумблеры, которые решает
// интерфейс. Строки захардкожены: свои ключи в Localizable.strings требуют
// прогона GenerateStrings.py, а это отдельный шаг сборки ради форка на
// несколько устройств.

// Выбор точки на карте открывается снаружи: сам экран карты живёт в
// LocationUI, а тянуть его в зависимости SettingsUI ради одного вызова
// незачем. Первый аргумент это стартовая точка карты, если она уже есть.
public typealias DkxMakeLocationPicker = (_ initial: (latitude: Double, longitude: Double)?, _ completion: @escaping (_ latitude: Double, _ longitude: Double) -> Void) -> ViewController

private struct DkxRouteSpeed {
    let kmh: Int32
    let title: String
}

private let dkxRouteSpeeds: [DkxRouteSpeed] = [
    DkxRouteSpeed(kmh: 5, title: "Пешком, 5 км/ч"),
    DkxRouteSpeed(kmh: 15, title: "Велосипед или самокат, 15 км/ч"),
    DkxRouteSpeed(kmh: 40, title: "Машина по городу, 40 км/ч"),
    DkxRouteSpeed(kmh: 90, title: "Машина по трассе, 90 км/ч")
]

// Тумблеры фич форка. Каждая новая фича с выключателем добавляется сюда,
// в dkxToggleValue и dkxToggleUpdate ниже и строкой в список экрана.
private enum DkxToggle: Int32 {
    case contactBadge
    case noteInHeader
    case peerId
    case unanswered
    case quickReplies
    case authorMessages
    case chatExport
    case mediaNoCompression
    case chatLock
    case todo
    case passwords
}

private let dkxUnansweredThresholds: [(hours: Int32, title: String)] = [
    (0, "Сразу"),
    (1, "Ждёт больше часа"),
    (3, "Ждёт больше 3 часов"),
    (24, "Ждёт больше суток")
]

private func dkxToggleValue(_ toggle: DkxToggle, _ settings: DkxSettings) -> Bool {
    switch toggle {
    case .contactBadge:
        return settings.showContactBadge
    case .noteInHeader:
        return settings.showNoteInHeader
    case .peerId:
        return settings.showPeerId
    case .unanswered:
        return settings.unansweredFilter
    case .quickReplies:
        return settings.quickReplies
    case .authorMessages:
        return settings.authorMessages
    case .chatExport:
        return settings.chatExport
    case .mediaNoCompression:
        return settings.mediaNoCompression
    case .chatLock:
        return settings.chatLock
    case .todo:
        return settings.todoEnabled
    case .passwords:
        return settings.passwordsEnabled
    }
}

private func dkxToggleUpdate(_ toggle: DkxToggle, _ value: Bool, _ settings: inout DkxSettings) {
    switch toggle {
    case .contactBadge:
        settings.showContactBadge = value
    case .noteInHeader:
        settings.showNoteInHeader = value
    case .peerId:
        settings.showPeerId = value
    case .unanswered:
        settings.unansweredFilter = value
    case .quickReplies:
        settings.quickReplies = value
    case .authorMessages:
        settings.authorMessages = value
    case .chatExport:
        settings.chatExport = value
    case .mediaNoCompression:
        settings.mediaNoCompression = value
    case .chatLock:
        settings.chatLock = value
    case .todo:
        settings.todoEnabled = value
    case .passwords:
        settings.passwordsEnabled = value
    }
}

private func dkxToggleTitle(_ toggle: DkxToggle) -> String {
    switch toggle {
    case .contactBadge:
        return "Метка «сохранил»"
    case .noteInHeader:
        return "Заметка в шапке чата"
    case .peerId:
        return "Telegram ID в профиле"
    case .unanswered:
        return "Список «Без ответа»"
    case .quickReplies:
        return "Шаблоны быстрых ответов"
    case .authorMessages:
        return "Все сообщения автора в группе"
    case .chatExport:
        return "Выгрузка чата в файл"
    case .mediaNoCompression:
        return "Фото и видео без сжатия"
    case .chatLock:
        return "Face ID на отдельные чаты"
    case .todo:
        return "«Мои дела» в настройках"
    case .passwords:
        return "«Пароли» в настройках"
    }
}

private final class DkxSettingsControllerArguments {
    let updateHideStories: (Bool) -> Void
    let updateHidePremiumPromo: (Bool) -> Void
    let updateAntiDelete: (Bool) -> Void
    let updateEditHistory: (Bool) -> Void
    let updateToggle: (DkxToggle, Bool) -> Void
    let updateUnansweredHours: (Int32) -> Void
    let openQuickReplies: () -> Void
    let updateSpoofLocation: (Bool) -> Void
    let updateSpoofMode: (DkxSettings.SpoofMode) -> Void
    let updateSpoofCoordinate: (String) -> Void
    let pickPoint: () -> Void
    let pickRouteFrom: () -> Void
    let pickRouteTo: () -> Void
    let swapRoute: () -> Void
    let updateRouteByRoads: (Bool) -> Void
    let updateRouteSpeed: (Int32) -> Void
    let startRoute: () -> Void
    let disableSpoof: () -> Void
    let openLog: () -> Void
    let openDebug: () -> Void
    let updateDriveEnabled: (Bool) -> Void
    let connectDrive: () -> Void
    let disconnectDrive: () -> Void

    init(
        updateHideStories: @escaping (Bool) -> Void,
        updateHidePremiumPromo: @escaping (Bool) -> Void,
        updateAntiDelete: @escaping (Bool) -> Void,
        updateEditHistory: @escaping (Bool) -> Void,
        updateToggle: @escaping (DkxToggle, Bool) -> Void,
        updateUnansweredHours: @escaping (Int32) -> Void,
        openQuickReplies: @escaping () -> Void,
        updateSpoofLocation: @escaping (Bool) -> Void,
        updateSpoofMode: @escaping (DkxSettings.SpoofMode) -> Void,
        updateSpoofCoordinate: @escaping (String) -> Void,
        pickPoint: @escaping () -> Void,
        pickRouteFrom: @escaping () -> Void,
        pickRouteTo: @escaping () -> Void,
        swapRoute: @escaping () -> Void,
        updateRouteSpeed: @escaping (Int32) -> Void,
        updateRouteByRoads: @escaping (Bool) -> Void,
        startRoute: @escaping () -> Void,
        disableSpoof: @escaping () -> Void,
        openLog: @escaping () -> Void,
        openDebug: @escaping () -> Void,
        updateDriveEnabled: @escaping (Bool) -> Void,
        connectDrive: @escaping () -> Void,
        disconnectDrive: @escaping () -> Void
    ) {
        self.updateHideStories = updateHideStories
        self.updateHidePremiumPromo = updateHidePremiumPromo
        self.updateAntiDelete = updateAntiDelete
        self.updateEditHistory = updateEditHistory
        self.updateToggle = updateToggle
        self.updateUnansweredHours = updateUnansweredHours
        self.openQuickReplies = openQuickReplies
        self.updateSpoofLocation = updateSpoofLocation
        self.updateSpoofMode = updateSpoofMode
        self.updateSpoofCoordinate = updateSpoofCoordinate
        self.pickPoint = pickPoint
        self.pickRouteFrom = pickRouteFrom
        self.pickRouteTo = pickRouteTo
        self.swapRoute = swapRoute
        self.updateRouteByRoads = updateRouteByRoads
        self.updateRouteSpeed = updateRouteSpeed
        self.startRoute = startRoute
        self.disableSpoof = disableSpoof
        self.openLog = openLog
        self.openDebug = openDebug
        self.updateDriveEnabled = updateDriveEnabled
        self.connectDrive = connectDrive
        self.disconnectDrive = disconnectDrive
    }
}

private enum DkxSettingsSection: Int32 {
    case interface
    case chats
    case unanswered
    case location
    case point
    case route
    case speed
    case routeControl
    case disable
    case features
    case drive
    case debug
}

private enum DkxSettingsControllerEntry: ItemListNodeEntry {
    case interfaceHeader
    case hideStories(Bool)
    case hidePremiumPromo(Bool)
    case interfaceFooter

    case chatsHeader
    case toggle(DkxToggle, Bool)
    case openQuickReplies(Int32)
    case chatsFooter

    case unansweredHeader
    case unansweredThreshold(index: Int32, title: String, checked: Bool)
    case unansweredFooter

    case locationHeader
    case spoofLocation(Bool)
    case modePoint(Bool)
    case modeRoute(Bool)
    case locationFooter(String)

    case pointHeader
    case spoofCoordinate(String)
    case pickPoint
    case pointFooter(String)

    case routeHeader
    case routeFrom(String)
    case routeTo(String)
    case routeSwap(Bool)
    case routeByRoads(Bool)

    case speedHeader
    case speed(index: Int32, title: String, checked: Bool)

    case routeStart(title: String, enabled: Bool)
    case routeStatus(String)

    case disableSpoof
    case disableFooter

    case featuresHeader
    case antiDelete(Bool)
    case editHistory(Bool)
    case featuresFooter

    case driveHeader
    case driveToggle(Bool)
    case driveAccount(String, Bool)
    case driveDisconnect
    case driveFooter(String)
    case debugHeader
    case openLog
    case openDebug
    case debugFooter

    var section: ItemListSectionId {
        switch self {
        case .interfaceHeader, .hideStories, .hidePremiumPromo, .interfaceFooter:
            return DkxSettingsSection.interface.rawValue
        case .chatsHeader, .toggle, .openQuickReplies, .chatsFooter:
            return DkxSettingsSection.chats.rawValue
        case .unansweredHeader, .unansweredThreshold, .unansweredFooter:
            return DkxSettingsSection.unanswered.rawValue
        case .locationHeader, .spoofLocation, .modePoint, .modeRoute, .locationFooter:
            return DkxSettingsSection.location.rawValue
        case .pointHeader, .spoofCoordinate, .pickPoint, .pointFooter:
            return DkxSettingsSection.point.rawValue
        case .routeHeader, .routeFrom, .routeTo, .routeSwap, .routeByRoads:
            return DkxSettingsSection.route.rawValue
        case .speedHeader, .speed:
            return DkxSettingsSection.speed.rawValue
        case .routeStart, .routeStatus:
            return DkxSettingsSection.routeControl.rawValue
        case .disableSpoof, .disableFooter:
            return DkxSettingsSection.disable.rawValue
        case .featuresHeader, .antiDelete, .editHistory, .featuresFooter:
            return DkxSettingsSection.features.rawValue
        case .driveHeader, .driveToggle, .driveAccount, .driveDisconnect, .driveFooter:
            return DkxSettingsSection.drive.rawValue
        case .debugHeader, .openLog, .openDebug, .debugFooter:
            return DkxSettingsSection.debug.rawValue
        }
    }

    // Номера с запасом, по сотне на раздел, чтобы новые строки вставлялись
    // без перенумерации. Порядок на экране задаётся именно ими.
    var stableId: Int32 {
        switch self {
        case .interfaceHeader:
            return 0
        case .hideStories:
            return 1
        case .hidePremiumPromo:
            return 2
        case .interfaceFooter:
            return 99
        case .chatsHeader:
            return 100
        // У тумблеров чётные номера, нечётное место сразу под тумблером
        // занимает его вложенная строка, если она есть
        case let .toggle(toggle, _):
            return 101 + toggle.rawValue * 2
        case .openQuickReplies:
            return 101 + DkxToggle.quickReplies.rawValue * 2 + 1
        case .chatsFooter:
            return 199
        case .unansweredHeader:
            return 200
        case let .unansweredThreshold(index, _, _):
            return 201 + index
        case .unansweredFooter:
            return 299
        case .locationHeader:
            return 1000
        case .spoofLocation:
            return 1001
        case .modePoint:
            return 1002
        case .modeRoute:
            return 1003
        case .locationFooter:
            return 1099
        case .pointHeader:
            return 1100
        case .spoofCoordinate:
            return 1101
        case .pickPoint:
            return 1102
        case .pointFooter:
            return 1199
        case .routeHeader:
            return 1200
        case .routeFrom:
            return 1201
        case .routeTo:
            return 1202
        case .routeSwap:
            return 1203
        case .routeByRoads:
            return 1204
        case .speedHeader:
            return 1300
        case let .speed(index, _, _):
            return 1301 + index
        case .routeStart:
            return 1400
        case .routeStatus:
            return 1401
        case .disableSpoof:
            return 1500
        case .disableFooter:
            return 1501
        case .featuresHeader:
            return 2000
        case .antiDelete:
            return 2001
        case .editHistory:
            return 2002
        case .featuresFooter:
            return 2003
        case .driveHeader:
            return 2500
        case .driveToggle:
            return 2501
        case .driveAccount:
            return 2502
        case .driveDisconnect:
            return 2503
        case .driveFooter:
            return 2504
        case .debugHeader:
            return 3000
        case .openLog:
            return 3001
        case .openDebug:
            return 3002
        case .debugFooter:
            return 3003
        }
    }

    static func <(lhs: DkxSettingsControllerEntry, rhs: DkxSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxSettingsControllerArguments
        switch self {
        case .interfaceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИНТЕРФЕЙС", sectionId: self.section)
        case let .hideStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Скрыть ленту историй", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideStories(value)
            })
        case let .hidePremiumPromo(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Убрать навязывание премиума", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHidePremiumPromo(value)
            })
        case .interfaceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Лента историй над списком чатов исчезнет полностью. Сами истории останутся доступны в профилях.\n\nБез навязывания пропадут плашки и экраны покупки Premium, пункты Premium, Business и подарков в настройках, значки подарков в поле ввода, а при наборе будут предлагаться только ваши стикеры, без чужих паков. Если Premium уже есть, он продолжит работать. Покупка Stars остаётся. Применяется при следующем открытии экрана."), sectionId: self.section)

        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "КОНТАКТЫ И ЧАТЫ", sectionId: self.section)
        case let .toggle(toggle, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: dkxToggleTitle(toggle), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateToggle(toggle, value)
            })
        case let .openQuickReplies(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Шаблоны", label: count == 0 ? "нет" : "\(count)", sectionId: self.section, style: .blocks, action: {
                arguments.openQuickReplies()
            })
        case .chatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Метка «сохранил» или «не сохранил» видна в шапке чата и в профиле собеседника, только для тех, кого вы сами сохранили.\n\nЗаметка в шапке чата это первая строка вашей заметки из профиля собеседника. Правится в профиле через «Изменить».\n\nШаблоны вставляются кнопкой в поле ввода, она появляется после добавления первого шаблона. «Все сообщения автора» есть в меню долгого нажатия на сообщение в группе. «Выгрузить чат в файл» в профиле собеседника, группы или канала: вся история текстом, с пометками удалённых и прежними версиями изменённых.\n\nБез сжатия фото и видео из галереи уходят оригиналом, файлом, как через «Отправить файлом». Получатель увидит файл, а не картинку в ленте. Предел размера 2 ГБ держит сервер Telegram, его не поднять.\n\nFace ID на чат: долгое нажатие на чат в списке, «Закрыть Face ID». У закрытого чата скрыт текст последнего сообщения и предпросмотр, открывается он после проверки и снова закрывается, когда приложение уходит в фон. Снять замок или выключить эту настройку можно только после проверки.\n\n«Мои дела» открываются из главных настроек, строка под «Моим профилем». Вид меняется кнопкой вверху: лента, день по часам, месяц. Выключенный тумблер прячет строку, сами дела и напоминания остаются. «Пароли» там же, открываются по Face ID, записи лежат в Keychain только на этом телефоне.\n\nВключённое или выключенное применяется при следующем открытии экрана."), sectionId: self.section)

        case .unansweredHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "БЕЗ ОТВЕТА", sectionId: self.section)
        case let .unansweredThreshold(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateUnansweredHours(dkxUnansweredThresholds[Int(index)].hours)
            })
        case .unansweredFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Список открывается долгим нажатием на вкладку «Чаты». В нём личные чаты, где последним написал собеседник, без ботов и архива. Сверху те, кто ждёт дольше всех."), sectionId: self.section)

        case .locationHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ГЕОЛОКАЦИЯ", sectionId: self.section)
        case let .spoofLocation(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Подменять координаты", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSpoofLocation(value)
            })
        case let .modePoint(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "Стоять в точке", style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateSpoofMode(.point)
            })
        case let .modeRoute(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "Двигаться из А в Б", style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateSpoofMode(.route)
            })
        case let .locationFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case .pointHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ТОЧКА", sectionId: self.section)
        case let .spoofCoordinate(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: value, placeholder: "широта, долгота", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateSpoofCoordinate(value)
            }, action: {})
        case .pickPoint:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Выбрать на карте", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.pickPoint()
            })
        case let .pointFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case .routeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "МАРШРУТ", sectionId: self.section)
        case let .routeFrom(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Точка А", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pickRouteFrom()
            })
        case let .routeTo(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Точка Б", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pickRouteTo()
            })
        case let .routeSwap(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Поменять А и Б местами", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.swapRoute()
                }
            })

        case let .routeByRoads(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "По дорогам", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRouteByRoads(value)
            })
        case .speedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СКОРОСТЬ", sectionId: self.section)
        case let .speed(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateRouteSpeed(dkxRouteSpeeds[Int(index)].kmh)
            })

        case let .routeStart(title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.startRoute()
                }
            })
        case let .routeStatus(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case .disableSpoof:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Выключить подмену", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.disableSpoof()
            })
        case .disableFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Сразу вернётся настоящая геопозиция. Выбранные точки и скорость сохранятся, движение начнётся заново при следующем включении."), sectionId: self.section)

        case .featuresHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СООБЩЕНИЯ", sectionId: self.section)
        case let .antiDelete(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Сохранять удалённые", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAntiDelete(value)
            })
        case let .editHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Сохранять историю правок", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateEditHistory(value)
            })
        case .featuresFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Удалённые собеседником сообщения остаются в чате с пометкой «удалено». У отредактированных в контекстном меню доступна история правок.\n\nСекретные чаты и самоуничтожающиеся сообщения не затрагиваются."), sectionId: self.section)

        case .driveHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "GOOGLE DRIVE", sectionId: self.section)
        case let .driveToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Выгрузка в Google Drive", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateDriveEnabled(value)
            })
        case let .driveAccount(text, isConnected):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: isConnected ? "Аккаунт" : "Войти в Google", label: text, sectionId: self.section, style: .blocks, disclosureStyle: isConnected ? .none : .arrow, action: {
                if !isConnected {
                    arguments.connectDrive()
                }
            })
        case .driveDisconnect:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Отвязать аккаунт", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.disconnectDrive()
            })
        case let .driveFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .debugHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ОТЛАДКА", sectionId: self.section)
        case .openLog:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Журнал Dkx", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openLog()
            })
        case .openDebug:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Отладочное меню Telegram", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openDebug()
            })
        case .debugFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Журнал Dkx пишется всегда и показывает, что делали правки форка, плюс отчёты о падениях.\n\nПолные логи Telegram пишутся только по запросу: в отладочном меню включите Log to File, повторите проблему и нажмите Send Logs."), sectionId: self.section)
        }
    }
}

// Локальное состояние нужно только полю ввода. Если рисовать его прямо из
// настроек, каждая нажатая клавиша уезжала бы на диск и возвращалась новым
// значением сигнала, а курсор прыгал бы в конец строки.
private struct DkxSettingsControllerState: Equatable {
    var coordinate: String?
}

private func dkxFormatDistance(_ meters: Double) -> String {
    if meters < 1000.0 {
        return "\(Int(meters.rounded())) м"
    }
    return String(format: "%.1f км", meters / 1000.0).replacingOccurrences(of: ".", with: ",")
}

private func dkxFormatDuration(_ seconds: Double) -> String {
    if seconds < 60.0 {
        return "меньше минуты"
    }
    let minutes = Int((seconds / 60.0).rounded(.up))
    if minutes < 60 {
        return "\(minutes) мин"
    }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
}

private func dkxRouteStatus(settings: DkxSettings, now: Int32) -> String {
    guard let path = settings.effectiveRoutePath else {
        return "Выберите на карте обе точки. Пока маршрут не задан, отдаётся настоящая координата."
    }
    let metersPerSecond = Double(max(1, settings.routeSpeed)) / 3.6
    let startedAt: Double? = settings.routeStartedAt > 0 ? Double(settings.routeStartedAt) : nil
    let sample = DkxLocationOverride.routeSample(path: path, metersPerSecond: metersPerSecond, startedAt: startedAt, now: Double(now))
    let roadStatus: String
    if !settings.routeByRoads {
        roadStatus = "По прямой."
    } else if settings.routePath.count >= 4 {
        roadStatus = "По дорогам, маршрут проложил \(settings.routePathSource)."
    } else if settings.routePathSource == "…" {
        roadStatus = "Прокладываю маршрут по дорогам…"
    } else {
        roadStatus = "Дорогу найти не удалось, точка поедет по прямой."
    }

    if startedAt == nil {
        return "Координата стоит в точке А. Расстояние \(dkxFormatDistance(sample.distance)), в пути около \(dkxFormatDuration(sample.distance / metersPerSecond)).\n\n" + roadStatus
    }
    if sample.fraction >= 1.0 {
        return "Прибыли в точку Б. Координата стоит там, пока вы не выключите подмену или не начнёте заново."
    }
    let travelled = sample.distance * sample.fraction
    let remaining = sample.distance - travelled
    return "В пути: \(dkxFormatDistance(travelled)) из \(dkxFormatDistance(sample.distance)), до точки Б около \(dkxFormatDuration(remaining / metersPerSecond)). " + roadStatus + "\n\nТрансляция геопозиции обновляется раз в несколько секунд, стрелка у получателя смотрит по ходу движения."
}

private func dkxSettingsControllerEntries(settings: DkxSettings, state: DkxSettingsControllerState, now: Int32) -> [DkxSettingsControllerEntry] {
    var entries: [DkxSettingsControllerEntry] = []

    entries.append(.interfaceHeader)
    entries.append(.hideStories(settings.hideStories))
    entries.append(.hidePremiumPromo(settings.hidePremiumPromo))
    entries.append(.interfaceFooter)

    entries.append(.chatsHeader)
    for toggle in [DkxToggle.contactBadge, .noteInHeader, .peerId, .unanswered, .quickReplies, .authorMessages, .chatExport, .mediaNoCompression, .chatLock, .todo, .passwords] {
        entries.append(.toggle(toggle, dkxToggleValue(toggle, settings)))
    }
    if settings.quickReplies {
        entries.append(.openQuickReplies(Int32(settings.quickReplyTemplates.count)))
    }
    entries.append(.chatsFooter)

    if settings.unansweredFilter {
        entries.append(.unansweredHeader)
        for i in 0 ..< dkxUnansweredThresholds.count {
            entries.append(.unansweredThreshold(index: Int32(i), title: dkxUnansweredThresholds[i].title, checked: dkxUnansweredThresholds[i].hours == settings.unansweredHours))
        }
        entries.append(.unansweredFooter)
    }

    entries.append(.locationHeader)
    entries.append(.spoofLocation(settings.spoofLocation))
    if settings.spoofLocation {
        entries.append(.modePoint(settings.spoofMode == .point))
        entries.append(.modeRoute(settings.spoofMode == .route))
        entries.append(.locationFooter("Подмена действует на трансляцию геопозиции, отправку местоположения и запросы от ботов. На системные карты и другие приложения она не влияет."))
    } else {
        entries.append(.locationFooter("Приложение будет отдавать выбранную точку или маршрут вместо настоящей геопозиции. Выключается здесь же в любой момент."))
    }

    if settings.spoofLocation {
        switch settings.spoofMode {
        case .point:
            let coordinateText = state.coordinate ?? settings.spoofCoordinate
            entries.append(.pointHeader)
            entries.append(.spoofCoordinate(coordinateText))
            entries.append(.pickPoint)
            let footer: String
            if coordinateText.isEmpty {
                footer = "Вставьте широту и долготу через запятую или выберите точку на карте. Пока точка не задана, отдаётся настоящая координата."
            } else if let coordinate = DkxSettings.parseCoordinate(coordinateText) {
                footer = "Точка принята: \(DkxSettings.formatCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))."
            } else {
                footer = "Не удалось разобрать строку. Нужны два числа через запятую: широта от минус 90 до 90, долгота от минус 180 до 180. Пока строка неверна, отдаётся настоящая координата."
            }
            entries.append(.pointFooter(footer))
        case .route:
            let hasFrom = DkxSettings.parseCoordinate(settings.routeFrom) != nil
            let hasTo = DkxSettings.parseCoordinate(settings.routeTo) != nil
            entries.append(.routeHeader)
            entries.append(.routeFrom(hasFrom ? settings.routeFrom : "выбрать"))
            entries.append(.routeTo(hasTo ? settings.routeTo : "выбрать"))
            entries.append(.routeSwap(hasFrom && hasTo))
            entries.append(.routeByRoads(settings.routeByRoads))

            entries.append(.speedHeader)
            for i in 0 ..< dkxRouteSpeeds.count {
                entries.append(.speed(index: Int32(i), title: dkxRouteSpeeds[i].title, checked: dkxRouteSpeeds[i].kmh == settings.routeSpeed))
            }

            entries.append(.routeStart(title: settings.routeStartedAt > 0 ? "Начать заново из точки А" : "Поехали", enabled: hasFrom && hasTo))
            entries.append(.routeStatus(dkxRouteStatus(settings: settings, now: now)))
        }

        entries.append(.disableSpoof)
        entries.append(.disableFooter)
    }

    entries.append(.featuresHeader)
    entries.append(.antiDelete(settings.antiDelete))
    entries.append(.editHistory(settings.editHistory))
    entries.append(.featuresFooter)

    entries.append(.driveHeader)
    entries.append(.driveToggle(settings.driveEnabled))
    if settings.driveEnabled {
        if !DkxGoogleDrive.isConfigured {
            entries.append(.driveFooter("Client ID не задан в сборке. Выгрузка недоступна."))
        } else if DkxGoogleDrive.isConnected {
            entries.append(.driveAccount(DkxGoogleDrive.connectedEmail ?? "подключён", true))
            entries.append(.driveDisconnect)
            entries.append(.driveFooter("У любого фото, видео, голосового или файла в меню долгого нажатия появится пункт «В Google Drive». Файлы уходят в папку Dkx, внутри по чатам, только на ваш диск. Права ограничены файлами, которые загрузило это приложение."))
        } else {
            entries.append(.driveAccount("не подключён", false))
            entries.append(.driveFooter("Войдите в свой Google-аккаунт, чтобы выгружать медиа на Google Drive. В тестовом режиме Google вход нужно повторять раз в 7 дней."))
        }
    } else {
        entries.append(.driveFooter("Пункт «В Google Drive» в меню медиа. Файлы уходят только на ваш диск, в папку Dkx."))
    }

    entries.append(.debugHeader)
    entries.append(.openLog)
    entries.append(.openDebug)
    entries.append(.debugFooter)

    return entries
}

public func dkxSettingsController(context: AccountContext, makeLocationPicker: @escaping DkxMakeLocationPicker) -> ViewController {
    let statePromise = ValuePromise(DkxSettingsControllerState(), ignoreRepeated: true)
    let stateValue = Atomic(value: DkxSettingsControllerState())
    let updateState: ((DkxSettingsControllerState) -> DkxSettingsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var pushControllerImpl: ((ViewController) -> Void)?
    var driveAnchorImpl: (() -> ASPresentationAnchor?)?

    let accountManager = context.sharedContext.accountManager
    let update: (@escaping (inout DkxSettings) -> Void) -> Void = { f in
        let _ = updateDkxSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            f(&updated)
            return updated
        }).start()
    }

    // Текущие настройки нужны синхронно, чтобы открыть карту на уже
    // выбранной точке
    let currentSettings = Atomic<DkxSettings>(value: DkxSettings.defaultSettings)

    // Маршрут по дорогам. Считается после любой правки, которая меняет
    // путь, и кладётся в настройки, только если точки за время расчёта не
    // поменялись. Пока считается, точка едет по прямой.
    let routeDisposable = MetaDisposable()
    let recomputeRoute: () -> Void = {
        routeDisposable.set((accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
        |> take(1)
        |> map { sharedData -> DkxSettings in
            return sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings
        }
        |> mapToSignal { settings -> Signal<(DkxSettings, DkxRoadRoute?), NoError> in
            guard settings.routeByRoads, let from = DkxSettings.parseCoordinate(settings.routeFrom), let to = DkxSettings.parseCoordinate(settings.routeTo) else {
                return .single((settings, nil))
            }
            return dkxComputeRoadRoute(from: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude), to: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude), walking: settings.routeSpeed <= 5)
            |> map { route -> (DkxSettings, DkxRoadRoute?) in
                return (settings, route)
            }
        }
        |> deliverOnMainQueue).start(next: { requested, route in
            update { current in
                guard current.routeFrom == requested.routeFrom, current.routeTo == requested.routeTo, current.routeByRoads == requested.routeByRoads else {
                    return
                }
                if !current.routeByRoads {
                    current.routePath = []
                    current.routePathSource = ""
                    return
                }
                current.routePath = route?.path ?? []
                current.routePathSource = route?.source ?? "нет"
            }
        }))
    }
    // Правка, после которой прежний путь больше не годится
    let updateRoute: (@escaping (inout DkxSettings) -> Void) -> Void = { f in
        let _ = (updateDkxSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            f(&updated)
            updated.routePath = []
            updated.routePathSource = updated.routeByRoads ? "…" : ""
            return updated
        })
        |> deliverOnMainQueue).start(completed: {
            recomputeRoute()
        })
    }

    let openPicker: (String, @escaping (String) -> Void) -> Void = { current, completion in
        let initial = DkxSettings.parseCoordinate(current)
        let controller = makeLocationPicker(initial, { latitude, longitude in
            completion(DkxSettings.formatCoordinate(latitude: latitude, longitude: longitude))
        })
        pushControllerImpl?(controller)
    }

    let arguments = DkxSettingsControllerArguments(
        updateHideStories: { value in
            update { $0.hideStories = value }
        },
        updateHidePremiumPromo: { value in
            update { $0.hidePremiumPromo = value }
        },
        updateAntiDelete: { value in
            update { $0.antiDelete = value }
        },
        updateEditHistory: { value in
            update { $0.editHistory = value }
        },
        updateToggle: { toggle, value in
            if toggle == .chatLock && !value {
                // Выключить замки может только владелец, иначе их снимали бы
                // здесь в обход проверки
                let _ = (DkxChatLock.authenticate(reason: "Выключить Face ID на чатах")
                |> deliverOnMainQueue).start(next: { success in
                    if success {
                        update { dkxToggleUpdate(toggle, value, &$0) }
                    }
                })
                return
            }
            update { dkxToggleUpdate(toggle, value, &$0) }
        },
        updateUnansweredHours: { value in
            update { $0.unansweredHours = value }
        },
        openQuickReplies: {
            pushControllerImpl?(dkxQuickRepliesController(context: context))
        },
        updateSpoofLocation: { value in
            update { settings in
                settings.spoofLocation = value
                // Выключение всегда останавливает движение, чтобы при
                // следующем включении не оказаться посреди старого маршрута
                settings.routeStartedAt = 0
            }
        },
        updateSpoofMode: { value in
            update { settings in
                settings.spoofMode = value
                settings.routeStartedAt = 0
            }
        },
        updateSpoofCoordinate: { value in
            updateState { current in
                var updated = current
                updated.coordinate = value
                return updated
            }
            update { $0.spoofCoordinate = value }
        },
        pickPoint: {
            openPicker(currentSettings.with { $0.spoofCoordinate }, { value in
                updateState { current in
                    var updated = current
                    updated.coordinate = value
                    return updated
                }
                update { $0.spoofCoordinate = value }
            })
        },
        pickRouteFrom: {
            openPicker(currentSettings.with { $0.routeFrom }, { value in
                updateRoute { settings in
                    settings.routeFrom = value
                    settings.routeStartedAt = 0
                }
            })
        },
        pickRouteTo: {
            // Если Б ещё нет, карта открывается в точке А, так удобнее
            let current = currentSettings.with { $0.routeTo.isEmpty ? $0.routeFrom : $0.routeTo }
            openPicker(current, { value in
                updateRoute { settings in
                    settings.routeTo = value
                    settings.routeStartedAt = 0
                }
            })
        },
        swapRoute: {
            updateRoute { settings in
                let from = settings.routeFrom
                settings.routeFrom = settings.routeTo
                settings.routeTo = from
                settings.routeStartedAt = 0
            }
        },
        updateRouteSpeed: { value in
            // Пешком и на колёсах дороги разные: при переходе через эту
            // границу маршрут пересчитывается
            let wasWalking = currentSettings.with { $0.routeSpeed <= 5 }
            if wasWalking != (value <= 5) {
                updateRoute { settings in
                    settings.routeSpeed = value
                    settings.routeStartedAt = 0
                }
                return
            }
            update { settings in
                // Смена скорости на ходу не должна телепортировать точку.
                // Сдвигаем момент старта так, чтобы пройденное расстояние
                // осталось прежним, а дальше точка шла с новой скоростью.
                if settings.routeStartedAt > 0, value > 0, let path = settings.effectiveRoutePath {
                    let now = Date().timeIntervalSince1970
                    let sample = DkxLocationOverride.routeSample(path: path, metersPerSecond: Double(max(1, settings.routeSpeed)) / 3.6, startedAt: Double(settings.routeStartedAt), now: now)
                    let travelled = sample.distance * sample.fraction
                    settings.routeStartedAt = Int32(max(1.0, now - travelled / (Double(value) / 3.6)))
                }
                settings.routeSpeed = value
            }
        },
        updateRouteByRoads: { value in
            updateRoute { settings in
                settings.routeByRoads = value
            }
        },
        startRoute: {
            update { $0.routeStartedAt = Int32(Date().timeIntervalSince1970) }
        },
        disableSpoof: {
            update { settings in
                settings.spoofLocation = false
                settings.routeStartedAt = 0
            }
        },
        openLog: {
            pushControllerImpl?(dkxLogController(context: context))
        },
        openDebug: {
            if let controller = context.sharedContext.makeDebugSettingsController(context: context) {
                pushControllerImpl?(controller)
            }
        },
        updateDriveEnabled: { value in
            update { $0.driveEnabled = value }
        },
        connectDrive: {
            guard let anchor = driveAnchorImpl?() else {
                return
            }
            let _ = DkxGoogleDrive.connect(presentationAnchor: { anchor }).start()
        },
        disconnectDrive: {
            DkxGoogleDrive.disconnect()
        }
    )

    // Раз в секунду, чтобы прогресс маршрута на экране шёл сам
    let clock: Signal<Int32, NoError> = Signal { subscriber in
        subscriber.putNext(Int32(Date().timeIntervalSince1970))
        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: {
            subscriber.putNext(Int32(Date().timeIntervalSince1970))
        }, queue: Queue.mainQueue())
        timer.start()
        return ActionDisposable {
            timer.invalidate()
        }
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get(),
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings]),
        clock
    )
    |> deliverOnMainQueue
    |> map { presentationData, state, sharedData, now -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings
        let _ = currentSettings.swap(settings)

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Dkx"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxSettingsControllerEntries(settings: settings, state: state, now: now), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        if let controller = controller {
            (controller.navigationController as? NavigationController)?.pushViewController(c)
        }
    }
    driveAnchorImpl = { [weak controller] in
        return controller?.view.window
    }
    return controller
}
