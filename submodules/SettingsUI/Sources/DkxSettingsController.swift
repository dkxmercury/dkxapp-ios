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

private final class DkxSettingsControllerArguments {
    let updateHideStories: (Bool) -> Void
    let updateHidePremiumPromo: (Bool) -> Void
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

    init(
        updateHideStories: @escaping (Bool) -> Void,
        updateHidePremiumPromo: @escaping (Bool) -> Void,
        updateSpoofLocation: @escaping (Bool) -> Void,
        updateSpoofMode: @escaping (DkxSettings.SpoofMode) -> Void,
        updateSpoofCoordinate: @escaping (String) -> Void,
        pickPoint: @escaping () -> Void,
        pickRouteFrom: @escaping () -> Void,
        pickRouteTo: @escaping () -> Void,
        swapRoute: @escaping () -> Void,
        updateRouteSpeed: @escaping (Int32) -> Void,
        startRoute: @escaping () -> Void,
        disableSpoof: @escaping () -> Void
    ) {
        self.updateHideStories = updateHideStories
        self.updateHidePremiumPromo = updateHidePremiumPromo
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
    }
}

private enum DkxSettingsSection: Int32 {
    case interface
    case location
    case point
    case route
    case speed
    case routeControl
    case disable
    case features
}

private enum DkxSettingsControllerEntry: ItemListNodeEntry {
    case interfaceHeader
    case hideStories(Bool)
    case hidePremiumPromo(Bool)
    case interfaceFooter

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

    var section: ItemListSectionId {
        switch self {
        case .interfaceHeader, .hideStories, .hidePremiumPromo, .interfaceFooter:
            return DkxSettingsSection.interface.rawValue
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
        }
    }

    var stableId: Int32 {
        switch self {
        case .interfaceHeader:
            return 0
        case .hideStories:
            return 1
        case .hidePremiumPromo:
            return 2
        case .interfaceFooter:
            return 3
        case .locationHeader:
            return 10
        case .spoofLocation:
            return 11
        case .modePoint:
            return 12
        case .modeRoute:
            return 13
        case .locationFooter:
            return 14
        case .pointHeader:
            return 20
        case .spoofCoordinate:
            return 21
        case .pickPoint:
            return 22
        case .pointFooter:
            return 23
        case .routeHeader:
            return 30
        case .routeFrom:
            return 31
        case .routeTo:
            return 32
        case .routeSwap:
            return 33
        case .speedHeader:
            return 40
        case let .speed(index, _, _):
            return 41 + index
        case .routeStart:
            return 60
        case .routeStatus:
            return 61
        case .disableSpoof:
            return 70
        case .disableFooter:
            return 71
        case .featuresHeader:
            return 80
        case .featuresFooter:
            return 81
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
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Убрать предложения премиума", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHidePremiumPromo(value)
            })
        case .interfaceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Лента историй над списком чатов исчезнет полностью. Сами истории останутся доступны в профилях."), sectionId: self.section)

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
    // Убирание предложений премиума пока не показываем: единой точки нет,
    // это 58 разных мест, отдельная работа. Поле в настройках уже заведено.
    entries.append(.interfaceFooter)

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
