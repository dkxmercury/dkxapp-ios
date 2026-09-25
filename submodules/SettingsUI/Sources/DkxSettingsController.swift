import Foundation
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
    }
}

private final class DkxSettingsControllerArguments {
    let updateHideStories: (Bool) -> Void
    let updateHidePremiumPromo: (Bool) -> Void
    let updateToggle: (DkxToggle, Bool) -> Void
    let updateUnansweredHours: (Int32) -> Void
    let updateSpoofLocation: (Bool) -> Void
    let updateSpoofMode: (DkxSettings.SpoofMode) -> Void
    let updateSpoofCoordinate: (String) -> Void
    let pickPoint: () -> Void
    let pickRouteFrom: () -> Void
    let pickRouteTo: () -> Void
    let swapRoute: () -> Void
    let updateRouteSpeed: (Int32) -> Void
    let startRoute: () -> Void
    let disableSpoof: () -> Void
    let openLog: () -> Void
    let openDebug: () -> Void

    init(
        updateHideStories: @escaping (Bool) -> Void,
        updateHidePremiumPromo: @escaping (Bool) -> Void,
        updateToggle: @escaping (DkxToggle, Bool) -> Void,
        updateUnansweredHours: @escaping (Int32) -> Void,
        updateSpoofLocation: @escaping (Bool) -> Void,
        updateSpoofMode: @escaping (DkxSettings.SpoofMode) -> Void,
        updateSpoofCoordinate: @escaping (String) -> Void,
        pickPoint: @escaping () -> Void,
        pickRouteFrom: @escaping () -> Void,
        pickRouteTo: @escaping () -> Void,
        swapRoute: @escaping () -> Void,
        updateRouteSpeed: @escaping (Int32) -> Void,
        startRoute: @escaping () -> Void,
        disableSpoof: @escaping () -> Void,
        openLog: @escaping () -> Void,
        openDebug: @escaping () -> Void
    ) {
        self.updateHideStories = updateHideStories
        self.updateHidePremiumPromo = updateHidePremiumPromo
        self.updateToggle = updateToggle
        self.updateUnansweredHours = updateUnansweredHours
        self.updateSpoofLocation = updateSpoofLocation
        self.updateSpoofMode = updateSpoofMode
        self.updateSpoofCoordinate = updateSpoofCoordinate
        self.pickPoint = pickPoint
        self.pickRouteFrom = pickRouteFrom
        self.pickRouteTo = pickRouteTo
        self.swapRoute = swapRoute
        self.updateRouteSpeed = updateRouteSpeed
        self.startRoute = startRoute
        self.disableSpoof = disableSpoof
        self.openLog = openLog
        self.openDebug = openDebug
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
    case debug
}

private enum DkxSettingsControllerEntry: ItemListNodeEntry {
    case interfaceHeader
    case hideStories(Bool)
    case hidePremiumPromo(Bool)
    case interfaceFooter

    case chatsHeader
    case toggle(DkxToggle, Bool)
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

    case speedHeader
    case speed(index: Int32, title: String, checked: Bool)

    case routeStart(title: String, enabled: Bool)
    case routeStatus(String)

    case disableSpoof
    case disableFooter

    case featuresHeader
    case featuresFooter

    case debugHeader
    case openLog
    case openDebug
    case debugFooter

    var section: ItemListSectionId {
        switch self {
        case .interfaceHeader, .hideStories, .hidePremiumPromo, .interfaceFooter:
            return DkxSettingsSection.interface.rawValue
        case .chatsHeader, .toggle, .chatsFooter:
            return DkxSettingsSection.chats.rawValue
        case .unansweredHeader, .unansweredThreshold, .unansweredFooter:
            return DkxSettingsSection.unanswered.rawValue
        case .locationHeader, .spoofLocation, .modePoint, .modeRoute, .locationFooter:
            return DkxSettingsSection.location.rawValue
        case .pointHeader, .spoofCoordinate, .pickPoint, .pointFooter:
            return DkxSettingsSection.point.rawValue
        case .routeHeader, .routeFrom, .routeTo, .routeSwap:
            return DkxSettingsSection.route.rawValue
        case .speedHeader, .speed:
            return DkxSettingsSection.speed.rawValue
        case .routeStart, .routeStatus:
            return DkxSettingsSection.routeControl.rawValue
        case .disableSpoof, .disableFooter:
            return DkxSettingsSection.disable.rawValue
        case .featuresHeader, .featuresFooter:
            return DkxSettingsSection.features.rawValue
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
        case let .toggle(toggle, _):
            return 101 + toggle.rawValue
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
        case .featuresFooter:
            return 2001
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
            return ItemListTextItem(presentationData: presentationData, text: .plain("Лента историй над списком чатов исчезнет полностью. Сами истории останутся доступны в профилях.

Без навязывания пропадут плашки и экраны покупки Premium, пункты Premium, Business и подарков в настройках, значки подарков в поле ввода, а при наборе будут предлагаться только ваши стикеры, без чужих паков. Если Premium уже есть, он продолжит работать. Покупка Stars остаётся. Применяется при следующем открытии экрана."), sectionId: self.section)

        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "КОНТАКТЫ И ЧАТЫ", sectionId: self.section)
        case let .toggle(toggle, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: dkxToggleTitle(toggle), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateToggle(toggle, value)
            })
        case .chatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Метка «сохранил» или «не сохранил» видна в шапке чата и в списке контактов, только для тех, кого вы сами сохранили.

Заметка в шапке чата это первая строка вашей заметки из профиля собеседника. Правится в профиле через «Изменить».

Включённое или выключенное применяется при следующем открытии экрана."), sectionId: self.section)

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
        case .featuresFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Удалённые собеседником сообщения остаются в чате с пометкой «удалено». У отредактированных в контекстном меню доступна история правок.\n\nСекретные чаты и самоуничтожающиеся сообщения не затрагиваются."), sectionId: self.section)

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
    guard let from = DkxSettings.parseCoordinate(settings.routeFrom), let to = DkxSettings.parseCoordinate(settings.routeTo) else {
        return "Выберите на карте обе точки. Пока маршрут не задан, отдаётся настоящая координата."
    }
    let metersPerSecond = Double(max(1, settings.routeSpeed)) / 3.6
    let startedAt: Double? = settings.routeStartedAt > 0 ? Double(settings.routeStartedAt) : nil
    let sample = DkxLocationOverride.routeSample(fromLatitude: from.latitude, fromLongitude: from.longitude, toLatitude: to.latitude, toLongitude: to.longitude, metersPerSecond: metersPerSecond, startedAt: startedAt, now: Double(now))

    if startedAt == nil {
        return "Координата стоит в точке А. Расстояние \(dkxFormatDistance(sample.distance)), в пути около \(dkxFormatDuration(sample.distance / metersPerSecond))."
    }
    if sample.fraction >= 1.0 {
        return "Прибыли в точку Б. Координата стоит там, пока вы не выключите подмену или не начнёте заново."
    }
    let travelled = sample.distance * sample.fraction
    let remaining = sample.distance - travelled
    return "В пути: \(dkxFormatDistance(travelled)) из \(dkxFormatDistance(sample.distance)), до точки Б около \(dkxFormatDuration(remaining / metersPerSecond)).\n\nТрансляция геопозиции обновляется раз в несколько секунд, стрелка у получателя смотрит по ходу движения."
}

private func dkxSettingsControllerEntries(settings: DkxSettings, state: DkxSettingsControllerState, now: Int32) -> [DkxSettingsControllerEntry] {
    var entries: [DkxSettingsControllerEntry] = []

    entries.append(.interfaceHeader)
    entries.append(.hideStories(settings.hideStories))
    entries.append(.hidePremiumPromo(settings.hidePremiumPromo))
    entries.append(.interfaceFooter)

    entries.append(.chatsHeader)
    for toggle in [DkxToggle.contactBadge, .noteInHeader, .peerId, .unanswered] {
        entries.append(.toggle(toggle, dkxToggleValue(toggle, settings)))
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
    entries.append(.featuresFooter)

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
        updateToggle: { toggle, value in
            update { dkxToggleUpdate(toggle, value, &$0) }
        },
        updateUnansweredHours: { value in
            update { $0.unansweredHours = value }
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
                update { settings in
                    settings.routeFrom = value
                    settings.routeStartedAt = 0
                }
            })
        },
        pickRouteTo: {
            // Если Б ещё нет, карта открывается в точке А, так удобнее
            let current = currentSettings.with { $0.routeTo.isEmpty ? $0.routeFrom : $0.routeTo }
            openPicker(current, { value in
                update { settings in
                    settings.routeTo = value
                    settings.routeStartedAt = 0
                }
            })
        },
        swapRoute: {
            update { settings in
                let from = settings.routeFrom
                settings.routeFrom = settings.routeTo
                settings.routeTo = from
                settings.routeStartedAt = 0
            }
        },
        updateRouteSpeed: { value in
            update { settings in
                // Смена скорости на ходу не должна телепортировать точку.
                // Сдвигаем момент старта так, чтобы пройденное расстояние
                // осталось прежним, а дальше точка шла с новой скоростью.
                if settings.routeStartedAt > 0, value > 0, let from = DkxSettings.parseCoordinate(settings.routeFrom), let to = DkxSettings.parseCoordinate(settings.routeTo) {
                    let now = Date().timeIntervalSince1970
                    let sample = DkxLocationOverride.routeSample(fromLatitude: from.latitude, fromLongitude: from.longitude, toLatitude: to.latitude, toLongitude: to.longitude, metersPerSecond: Double(max(1, settings.routeSpeed)) / 3.6, startedAt: Double(settings.routeStartedAt), now: now)
                    let travelled = sample.distance * sample.fraction
                    settings.routeStartedAt = Int32(max(1.0, now - travelled / (Double(value) / 3.6)))
                }
                settings.routeSpeed = value
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
    return controller
}
