import Foundation
import UIKit
import MapKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import DeviceLocationManager

// MARK: DKX панель подмены геопозиции прямо над картой в экране отправки.
// Переключатель Настоящая, Точка, Маршрут. Точки ставятся долгим нажатием на
// карту, в маршруте первое нажатие ставит А, следующие ставят Б. Метки
// перетаскиваются, «Заново» стирает маршрут. Настройки те же, что читает
// подмена в DeviceLocationManager.

private let dkxSpoofSpeeds: [Int32] = [5, 15, 40, 90]

private func dkxSpoofDistance(_ meters: Double) -> String {
    if meters < 1000.0 {
        return DkxStrings.tr("{} м", Int(meters.rounded()))
    }
    return String(format: DkxStrings.tr("%.1f км"), locale: DkxStrings.locale, meters / 1000.0)
}

private func dkxSpoofStatus(_ settings: DkxSettings) -> String {
    guard settings.spoofLocation else {
        return DkxStrings.tr("Отдаётся настоящая геопозиция")
    }
    switch settings.spoofMode {
    case .point:
        if DkxSettings.parseCoordinate(settings.spoofCoordinate) != nil {
            return DkxStrings.tr("Стоим в точке. Метку можно перетащить пальцем")
        }
        return DkxStrings.tr("Долгое нажатие на карту ставит точку")
    case .route:
        let hasFrom = DkxSettings.parseCoordinate(settings.routeFrom) != nil
        let hasTo = DkxSettings.parseCoordinate(settings.routeTo) != nil
        if !hasFrom {
            return DkxStrings.tr("Долгое нажатие на карту ставит точку А")
        }
        if !hasTo {
            return DkxStrings.tr("Точка А есть. Долгое нажатие ставит Б")
        }
        guard let path = settings.effectiveRoutePath else {
            return DkxStrings.tr("Долгое нажатие переставит Б")
        }
        let metersPerSecond = Double(max(1, settings.routeSpeed)) / 3.6
        let startedAt: Double? = settings.routeStartedAt > 0 ? Double(settings.routeStartedAt) : nil
        let sample = DkxLocationOverride.routeSample(path: path, metersPerSecond: metersPerSecond, startedAt: startedAt, now: Date().timeIntervalSince1970)
        var road = ""
        if settings.routeByRoads && settings.routePathSource == "…" {
            road = DkxStrings.tr(", прокладываю по дорогам")
        } else if settings.routeByRoads && settings.routePath.count < 4 {
            road = DkxStrings.tr(", дорогу не нашли, едем прямо")
        }
        if startedAt == nil {
            return DkxStrings.tr("Маршрут {}{}. Метки можно перетащить, движение начнётся с трансляцией", dkxSpoofDistance(sample.distance), road)
        }
        if sample.fraction >= 1.0 {
            return DkxStrings.tr("Приехали в точку Б")
        }
        return DkxStrings.tr("В пути, {} из {}{}", dkxSpoofDistance(sample.distance * sample.fraction), dkxSpoofDistance(sample.distance), road)
    }
}

private final class DkxSpoofChip: UIButton {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: CGRect())
        self.titleLabel?.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.layer.cornerRadius = 14.0
        self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, color: UIColor) {
        self.setTitle(title, for: .normal)
        self.setTitleColor(color, for: .normal)
        self.backgroundColor = color.withAlphaComponent(0.12)
    }

    // Ширина под текст с полями по 12 пунктов
    func fittingWidth() -> CGFloat {
        let size = self.titleLabel?.sizeThatFits(CGSize(width: 200.0, height: 28.0)) ?? CGSize()
        return ceil(size.width) + 24.0
    }

    @objc private func pressed() {
        self.action()
    }
}

final class DkxSpoofPanelView: UIView {
    private let backgroundView = UIView()
    private let modeControl = UISegmentedControl(items: [DkxStrings.tr("Настоящая"), DkxStrings.tr("Точка"), DkxStrings.tr("Маршрут")])
    private let statusLabel = UILabel()
    // Кнопок больше, чем влезает в узкий экран, поэтому ряд прокручивается
    private let chipsView = UIScrollView()
    private var startChip: DkxSpoofChip?
    private var speedChip: DkxSpoofChip?
    private var roadsChip: DkxSpoofChip?
    private var reverseChip: DkxSpoofChip?
    private var resetChip: DkxSpoofChip?

    var modeChanged: ((Int) -> Void)?
    var speedPressed: (() -> Void)?
    var roadsPressed: (() -> Void)?
    var startPressed: (() -> Void)?
    var reversePressed: (() -> Void)?
    var resetPressed: (() -> Void)?

    private var showsRouteControls = false
    private var showsStatus = false

    private let chipHeight: CGFloat = 28.0

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundView.layer.cornerRadius = 16.0
        self.backgroundView.clipsToBounds = true
        self.backgroundView.isUserInteractionEnabled = false
        self.addSubview(self.backgroundView)

        self.modeControl.addTarget(self, action: #selector(self.modeAction), for: .valueChanged)
        self.addSubview(self.modeControl)

        self.statusLabel.font = UIFont.systemFont(ofSize: 12.0)
        self.statusLabel.numberOfLines = 2
        self.addSubview(self.statusLabel)

        self.chipsView.showsHorizontalScrollIndicator = false
        self.chipsView.showsVerticalScrollIndicator = false
        self.chipsView.alwaysBounceHorizontal = false
        self.addSubview(self.chipsView)

        let startChip = DkxSpoofChip(action: { [weak self] in
            self?.startPressed?()
        })
        let speedChip = DkxSpoofChip(action: { [weak self] in
            self?.speedPressed?()
        })
        let roadsChip = DkxSpoofChip(action: { [weak self] in
            self?.roadsPressed?()
        })
        let reverseChip = DkxSpoofChip(action: { [weak self] in
            self?.reversePressed?()
        })
        let resetChip = DkxSpoofChip(action: { [weak self] in
            self?.resetPressed?()
        })
        self.startChip = startChip
        self.speedChip = speedChip
        self.roadsChip = roadsChip
        self.reverseChip = reverseChip
        self.resetChip = resetChip
        for chip in [startChip, speedChip, roadsChip, reverseChip, resetChip] {
            self.chipsView.addSubview(chip)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func modeAction() {
        self.modeChanged?(self.modeControl.selectedSegmentIndex)
    }

    func update(settings: DkxSettings, theme: PresentationTheme) {
        let list = theme.list
        self.backgroundView.backgroundColor = list.itemBlocksBackgroundColor.withAlphaComponent(0.94)
        self.statusLabel.textColor = list.itemSecondaryTextColor
        self.modeControl.selectedSegmentTintColor = list.itemAccentColor
        self.modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13.0, weight: .semibold)], for: .selected)
        self.modeControl.setTitleTextAttributes([.foregroundColor: list.itemPrimaryTextColor, .font: UIFont.systemFont(ofSize: 13.0)], for: .normal)

        if !settings.spoofLocation {
            self.modeControl.selectedSegmentIndex = 0
        } else {
            self.modeControl.selectedSegmentIndex = settings.spoofMode == .point ? 1 : 2
        }

        self.showsStatus = settings.spoofLocation
        self.showsRouteControls = settings.spoofLocation && settings.spoofMode == .route
        self.statusLabel.text = dkxSpoofStatus(settings)

        let hasFrom = DkxSettings.parseCoordinate(settings.routeFrom) != nil
        let hasTo = DkxSettings.parseCoordinate(settings.routeTo) != nil

        let accent = list.itemAccentColor
        if settings.routeStartedAt > 0 {
            self.startChip?.update(title: DkxStrings.tr("Стоп"), color: list.itemDestructiveColor)
        } else {
            self.startChip?.update(title: DkxStrings.tr("Поехали"), color: accent)
        }
        self.speedChip?.update(title: DkxStrings.tr("{} км/ч", settings.routeSpeed), color: accent)
        self.roadsChip?.update(title: settings.routeByRoads ? DkxStrings.tr("По дорогам") : DkxStrings.tr("Напрямую"), color: accent)
        self.reverseChip?.update(title: DkxStrings.tr("Обратно"), color: accent)
        self.resetChip?.update(title: DkxStrings.tr("Заново"), color: list.itemDestructiveColor)

        self.statusLabel.isHidden = !self.showsStatus
        self.chipsView.isHidden = !self.showsRouteControls
        self.reverseChip?.isHidden = !(hasFrom && hasTo)
        self.resetChip?.isHidden = !hasFrom
        self.layoutChips()
    }

    private func layoutChips() {
        var x: CGFloat = 8.0
        for chip in [self.startChip, self.speedChip, self.roadsChip, self.reverseChip, self.resetChip] {
            guard let chip = chip, !chip.isHidden else {
                continue
            }
            let chipWidth = chip.fittingWidth()
            chip.frame = CGRect(x: x, y: 0.0, width: chipWidth, height: self.chipHeight)
            x += chipWidth + 6.0
        }
        self.chipsView.contentSize = CGSize(width: x + 2.0, height: self.chipHeight)
    }

    // Раскладка под ширину, возвращает высоту панели. Под строку состояния
    // всегда две строки, чтобы панель не прыгала от длины подсказки.
    func layout(width: CGFloat) -> CGFloat {
        let inset: CGFloat = 8.0
        let controlHeight: CGFloat = 32.0
        self.modeControl.frame = CGRect(x: inset, y: inset, width: width - inset * 2.0, height: controlHeight)
        var y = inset + controlHeight

        if self.showsStatus {
            y += 6.0
            let statusHeight = ceil(self.statusLabel.font.lineHeight * 2.0)
            self.statusLabel.frame = CGRect(x: inset + 4.0, y: y, width: width - inset * 2.0 - 8.0, height: statusHeight)
            y += statusHeight
        }
        if self.showsRouteControls {
            y += 6.0
            self.chipsView.frame = CGRect(x: 0.0, y: y, width: width, height: self.chipHeight)
            self.layoutChips()
            y += self.chipHeight
        }
        y += inset
        self.backgroundView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: y)
        return y
    }
}

// Логика панели. Читает и пишет настройки Dkx, прокладывает маршрут по
// дорогам, рисует метки на карте и раз в секунду обновляет строку состояния,
// пока точка едет.
final class DkxSpoofPanelController {
    let view = DkxSpoofPanelView()
    var layoutUpdated: (() -> Void)?

    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private weak var mapNode: LocationMapNode?
    private var theme: PresentationTheme
    private var settings = DkxSettings.defaultSettings
    private var settingsDisposable: Disposable?
    private let routeDisposable = MetaDisposable()
    private var timer: SwiftSignalKit.Timer?

    init(accountManager: AccountManager<TelegramAccountManagerTypes>, mapNode: LocationMapNode, theme: PresentationTheme) {
        self.accountManager = accountManager
        self.mapNode = mapNode
        self.theme = theme

        self.view.modeChanged = { [weak self] index in
            self?.setMode(index)
        }
        self.view.speedPressed = { [weak self] in
            self?.cycleSpeed()
        }
        self.view.roadsPressed = { [weak self] in
            self?.toggleRoads()
        }
        self.view.startPressed = { [weak self] in
            self?.toggleStart()
        }
        self.view.reversePressed = { [weak self] in
            self?.reverseRoute()
        }
        self.view.resetPressed = { [weak self] in
            self?.resetRoute()
        }
        mapNode.dkxSpoofAnnotationMoved = { [weak self] kind, coordinate in
            self?.handleDrag(kind, coordinate: coordinate)
        }

        self.settingsDisposable = (accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
        |> map { sharedData -> DkxSettings in
            return sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings
        }
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            self?.apply(settings)
        })

        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
            guard let self, self.settings.spoofLocation, self.settings.spoofMode == .route, self.settings.routeStartedAt > 0 else {
                return
            }
            self.view.update(settings: self.settings, theme: self.theme)
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
    }

    deinit {
        self.settingsDisposable?.dispose()
        self.routeDisposable.dispose()
        self.timer?.invalidate()
    }

    func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        self.view.update(settings: self.settings, theme: theme)
    }

    private func apply(_ settings: DkxSettings) {
        let previous = self.settings
        self.settings = settings
        self.view.update(settings: settings, theme: self.theme)
        self.updateMap()
        if previous.spoofLocation != settings.spoofLocation || previous.spoofMode != settings.spoofMode {
            self.layoutUpdated?()
        }
    }

    private func updateMap() {
        let settings = self.settings
        var point: CLLocationCoordinate2D?
        var from: CLLocationCoordinate2D?
        var to: CLLocationCoordinate2D?
        var path: [Double] = []
        if settings.spoofLocation {
            switch settings.spoofMode {
            case .point:
                point = DkxSettings.parseCoordinate(settings.spoofCoordinate).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            case .route:
                from = DkxSettings.parseCoordinate(settings.routeFrom).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                to = DkxSettings.parseCoordinate(settings.routeTo).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                path = settings.effectiveRoutePath ?? []
            }
        }
        self.mapNode?.dkxUpdateSpoofOverlay(point: point, from: from, to: to, path: path)
    }

    private func update(_ f: @escaping (inout DkxSettings) -> Void, completed: (() -> Void)? = nil) {
        let _ = (updateDkxSettingsInteractively(accountManager: self.accountManager, { current in
            var updated = current
            f(&updated)
            return updated
        })
        |> deliverOnMainQueue).start(completed: {
            completed?()
        })
    }

    // Правка, после которой прежний путь не годится. Сначала путь сбрасываем
    // на прямую, потом прокладываем по дорогам заново.
    private func updateRoute(_ f: @escaping (inout DkxSettings) -> Void) {
        self.update({ settings in
            f(&settings)
            settings.routePath = []
            settings.routePathSource = settings.routeByRoads ? "…" : ""
        }, completed: { [weak self] in
            self?.recomputeRoute()
        })
    }

    // Настройки перечитываем, а не берём из подписки. Она может ещё не
    // донести правку, после которой нас позвали
    private func recomputeRoute() {
        self.routeDisposable.set((self.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
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
        |> deliverOnMainQueue).start(next: { [weak self] requested, route in
            guard let self, requested.routeByRoads, DkxSettings.parseCoordinate(requested.routeTo) != nil else {
                return
            }
            self.update({ current in
                // Точки успели поменять, пока считали. Такой путь уже чужой.
                guard current.routeFrom == requested.routeFrom, current.routeTo == requested.routeTo, current.routeByRoads else {
                    return
                }
                current.routePath = route?.path ?? []
                current.routePathSource = route?.source ?? "нет"
            })
        }))
    }

    private func setMode(_ index: Int) {
        self.update({ settings in
            settings.spoofLocation = index != 0
            if index == 1 {
                settings.spoofMode = .point
            } else if index == 2 {
                settings.spoofMode = .route
            }
            // Смена режима всегда останавливает движение
            settings.routeStartedAt = 0
        })
    }

    func handleLongPress(_ coordinate: CLLocationCoordinate2D) {
        let text = DkxSettings.formatCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let settings = self.settings
        if !settings.spoofLocation || settings.spoofMode == .point {
            self.update({ current in
                current.spoofLocation = true
                current.spoofMode = .point
                current.spoofCoordinate = text
                current.routeStartedAt = 0
            })
            return
        }
        if DkxSettings.parseCoordinate(settings.routeFrom) != nil {
            self.updateRoute({ current in
                current.routeTo = text
                current.routeStartedAt = 0
            })
        } else {
            self.updateRoute({ current in
                current.routeFrom = text
                current.routeTo = ""
                current.routeStartedAt = 0
            })
        }
    }

    // Сдвиг А или Б останавливает движение, иначе точка прыгнула бы на новый путь
    private func handleDrag(_ kind: DkxSpoofAnnotation.Kind, coordinate: CLLocationCoordinate2D) {
        let text = DkxSettings.formatCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        switch kind {
        case .point:
            self.update({ current in
                current.spoofCoordinate = text
            })
        case .from:
            self.updateRoute({ current in
                current.routeFrom = text
                current.routeStartedAt = 0
            })
        case .to:
            self.updateRoute({ current in
                current.routeTo = text
                current.routeStartedAt = 0
            })
        }
    }

    // Обратная дорога по дорогам не всегда та же, поэтому путь считается заново
    private func reverseRoute() {
        self.updateRoute({ current in
            let from = current.routeFrom
            current.routeFrom = current.routeTo
            current.routeTo = from
            current.routeStartedAt = 0
        })
    }

    private func resetRoute() {
        self.routeDisposable.set(nil)
        self.update({ current in
            current.routeFrom = ""
            current.routeTo = ""
            current.routePath = []
            current.routePathSource = ""
            current.routeStartedAt = 0
        })
    }

    private func cycleSpeed() {
        let current = self.settings.routeSpeed
        let index = dkxSpoofSpeeds.firstIndex(of: current) ?? 0
        let value = dkxSpoofSpeeds[(index + 1) % dkxSpoofSpeeds.count]
        // Пешком и на колёсах дороги разные, при переходе через эту границу
        // маршрут пересчитывается
        if (current <= 5) != (value <= 5) {
            self.updateRoute({ settings in
                settings.routeSpeed = value
                settings.routeStartedAt = 0
            })
            return
        }
        self.update({ settings in
            // Смена скорости на ходу не телепортирует точку. Сдвигаем момент
            // старта так, чтобы пройденное осталось прежним.
            if settings.routeStartedAt > 0, let path = settings.effectiveRoutePath {
                let now = Date().timeIntervalSince1970
                let sample = DkxLocationOverride.routeSample(path: path, metersPerSecond: Double(max(1, settings.routeSpeed)) / 3.6, startedAt: Double(settings.routeStartedAt), now: now)
                let travelled = sample.distance * sample.fraction
                settings.routeStartedAt = Int32(max(1.0, now - travelled / (Double(value) / 3.6)))
            }
            settings.routeSpeed = value
        })
    }

    private func toggleRoads() {
        self.updateRoute({ settings in
            settings.routeByRoads = !settings.routeByRoads
        })
    }

    private func toggleStart() {
        self.update({ settings in
            if settings.routeStartedAt > 0 {
                settings.routeStartedAt = 0
            } else if settings.effectiveRoutePath != nil {
                settings.routeStartedAt = Int32(Date().timeIntervalSince1970)
            }
        })
    }
}

// Трансляция сама трогает маршрут с места, отдельный «Поехали» не нужен
func dkxStartRouteForBroadcast(accountManager: AccountManager<TelegramAccountManagerTypes>) {
    let _ = updateDkxSettingsInteractively(accountManager: accountManager, { current in
        var updated = current
        if updated.spoofPanel && updated.spoofLocation && updated.spoofMode == .route && updated.routeStartedAt == 0 && updated.effectiveRoutePath != nil {
            updated.routeStartedAt = Int32(Date().timeIntervalSince1970)
            DkxLog.write("гео", "маршрут тронулся с началом трансляции")
        }
        return updated
    }).start()
}

// Долгое нажатие должно срабатывать вместе с жестами самой карты
final class DkxSpoofLongPressDelegate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: ((UIGestureRecognizer) -> Bool)?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return self.shouldBegin?(gestureRecognizer) ?? true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
