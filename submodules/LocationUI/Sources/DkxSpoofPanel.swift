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
// карту, в маршруте первое нажатие ставит А, второе Б, третье начинает новый
// маршрут. Настройки те же, что читает подмена в DeviceLocationManager.

private let dkxSpoofSpeeds: [Int32] = [5, 15, 40, 90]

private func dkxSpoofDistance(_ meters: Double) -> String {
    if meters < 1000.0 {
        return "\(Int(meters.rounded())) м"
    }
    return String(format: "%.1f км", meters / 1000.0).replacingOccurrences(of: ".", with: ",")
}

private func dkxSpoofStatus(_ settings: DkxSettings) -> String {
    guard settings.spoofLocation else {
        return "Отдаётся настоящая геопозиция"
    }
    switch settings.spoofMode {
    case .point:
        if DkxSettings.parseCoordinate(settings.spoofCoordinate) != nil {
            return "Стоим в точке. Долгое нажатие на карту переставит её"
        }
        return "Долгое нажатие на карту ставит точку"
    case .route:
        let hasFrom = DkxSettings.parseCoordinate(settings.routeFrom) != nil
        let hasTo = DkxSettings.parseCoordinate(settings.routeTo) != nil
        if !hasFrom {
            return "Долгое нажатие на карту ставит точку А"
        }
        if !hasTo {
            return "Точка А есть. Долгое нажатие ставит Б"
        }
        guard let path = settings.effectiveRoutePath else {
            return "Долгое нажатие начнёт новый маршрут"
        }
        let metersPerSecond = Double(max(1, settings.routeSpeed)) / 3.6
        let startedAt: Double? = settings.routeStartedAt > 0 ? Double(settings.routeStartedAt) : nil
        let sample = DkxLocationOverride.routeSample(path: path, metersPerSecond: metersPerSecond, startedAt: startedAt, now: Date().timeIntervalSince1970)
        var road = ""
        if settings.routeByRoads && settings.routePathSource == "…" {
            road = ", прокладываю по дорогам"
        } else if settings.routeByRoads && settings.routePath.count < 4 {
            road = ", дорогу не нашли, едем прямо"
        }
        if startedAt == nil {
            return "Маршрут \(dkxSpoofDistance(sample.distance))\(road). Трансляция запустит движение сама"
        }
        if sample.fraction >= 1.0 {
            return "Приехали в точку Б"
        }
        return "В пути, \(dkxSpoofDistance(sample.distance * sample.fraction)) из \(dkxSpoofDistance(sample.distance))\(road)"
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
    private let modeControl = UISegmentedControl(items: ["Настоящая", "Точка", "Маршрут"])
    private let statusLabel = UILabel()
    private var speedChip: DkxSpoofChip?
    private var roadsChip: DkxSpoofChip?
    private var startChip: DkxSpoofChip?

    var modeChanged: ((Int) -> Void)?
    var speedPressed: (() -> Void)?
    var roadsPressed: (() -> Void)?
    var startPressed: (() -> Void)?

    private var showsRouteControls = false
    private var showsStatus = false

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

        let speedChip = DkxSpoofChip(action: { [weak self] in
            self?.speedPressed?()
        })
        let roadsChip = DkxSpoofChip(action: { [weak self] in
            self?.roadsPressed?()
        })
        let startChip = DkxSpoofChip(action: { [weak self] in
            self?.startPressed?()
        })
        self.speedChip = speedChip
        self.roadsChip = roadsChip
        self.startChip = startChip
        self.addSubview(speedChip)
        self.addSubview(roadsChip)
        self.addSubview(startChip)
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

        let accent = list.itemAccentColor
        self.speedChip?.update(title: "\(settings.routeSpeed) км/ч", color: accent)
        self.roadsChip?.update(title: settings.routeByRoads ? "По дорогам" : "Напрямую", color: accent)
        if settings.routeStartedAt > 0 {
            self.startChip?.update(title: "Стоп", color: list.itemDestructiveColor)
        } else {
            self.startChip?.update(title: "Поехали", color: accent)
        }
        self.statusLabel.isHidden = !self.showsStatus
        self.speedChip?.isHidden = !self.showsRouteControls
        self.roadsChip?.isHidden = !self.showsRouteControls
        self.startChip?.isHidden = !self.showsRouteControls
    }

    // Раскладка под ширину, возвращает высоту панели
    func layout(width: CGFloat) -> CGFloat {
        let inset: CGFloat = 8.0
        let controlHeight: CGFloat = 32.0
        self.modeControl.frame = CGRect(x: inset, y: inset, width: width - inset * 2.0, height: controlHeight)
        var y = inset + controlHeight

        if self.showsRouteControls {
            y += 8.0
            let chipHeight: CGFloat = 28.0
            var x = width - inset
            for chip in [self.startChip, self.roadsChip, self.speedChip] {
                guard let chip = chip else {
                    continue
                }
                let chipWidth = chip.fittingWidth()
                x -= chipWidth
                chip.frame = CGRect(x: x, y: y, width: chipWidth, height: chipHeight)
                x -= 6.0
            }
            let statusWidth = max(0.0, x - inset - 4.0)
            let statusHeight = min(chipHeight + 4.0, ceil(self.statusLabel.sizeThatFits(CGSize(width: statusWidth, height: 40.0)).height))
            self.statusLabel.frame = CGRect(x: inset + 4.0, y: y + floor((chipHeight - statusHeight) / 2.0), width: statusWidth, height: statusHeight)
            y += chipHeight
        } else if self.showsStatus {
            y += 6.0
            let statusWidth = width - inset * 2.0 - 8.0
            let statusHeight = ceil(self.statusLabel.sizeThatFits(CGSize(width: statusWidth, height: 40.0)).height)
            self.statusLabel.frame = CGRect(x: inset + 4.0, y: y, width: statusWidth, height: statusHeight)
            y += statusHeight
        }
        y += inset
        self.backgroundView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: y)
        return y
    }
}

// Логика панели: читает и пишет настройки Dkx, прокладывает маршрут по
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

    // Настройки перечитываем, а не берём из подписки: она может ещё не
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
        let hasFrom = DkxSettings.parseCoordinate(settings.routeFrom) != nil
        let hasTo = DkxSettings.parseCoordinate(settings.routeTo) != nil
        if hasFrom && !hasTo {
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
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
