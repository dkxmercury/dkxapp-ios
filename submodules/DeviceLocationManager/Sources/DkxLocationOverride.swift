import Foundation
import CoreLocation

// Подмена координат. Один выключатель на всё приложение: трансляция
// геопозиции, запросы местоположения от веб-ботов, экран выбора точки.
//
// Два режима. Точка: координата стоит на месте. Маршрут: координата едет
// по прямой из А в Б с заданной скоростью, от момента старта. Положение
// считается от настенных часов, а не накапливается по тикам, поэтому
// перезапуск приложения посреди маршрута ничего не сбивает.
//
// Значение держится в памяти. Перезапуск оно переживает за счёт настроек
// форка, но обращения к настройкам тут намеренно нет: этот модуль лежит
// ниже всех слоёв, которые умеют их читать, и зависит только от
// SwiftSignalKit. Значение кладут снаружи, из SharedAccountContext, который
// подписан на настройки и обновляет его при запуске и при каждой правке.
public final class DkxLocationOverride {
    public struct Sample {
        public let latitude: Double
        public let longitude: Double
        // Градусы от севера по часовой, либо −1, если направления нет
        public let course: Double
        // Метры в секунду, либо −1, если точка стоит
        public let speed: Double
        // Доля пройденного пути, для точки всегда 1
        public let fraction: Double
        // Длина маршрута в метрах, для точки 0
        public let distance: Double
    }

    private enum State {
        case point(latitude: Double, longitude: Double)
        // startedAt в секундах от 1970. nil значит, что старт не нажат и
        // координата стоит в точке А.
        case route(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double, metersPerSecond: Double, startedAt: Double?)
    }

    // Сколько секунд после прибытия ещё слать синтетические обновления,
    // чтобы последним ушло ровно Б, а не точка за шаг до неё.
    private static let arrivalGrace: Double = 10.0

    private static let lock = NSLock()
    private static var state: State?

    public static func setPoint(latitude: Double, longitude: Double) {
        guard isValid(latitude, longitude) else {
            return
        }
        lock.lock()
        state = .point(latitude: latitude, longitude: longitude)
        lock.unlock()
    }

    public static func setRoute(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double, metersPerSecond: Double, startedAt: Double?) {
        guard isValid(fromLatitude, fromLongitude), isValid(toLatitude, toLongitude), metersPerSecond > 0.0 else {
            return
        }
        lock.lock()
        state = .route(fromLatitude: fromLatitude, fromLongitude: fromLongitude, toLatitude: toLatitude, toLongitude: toLongitude, metersPerSecond: metersPerSecond, startedAt: startedAt)
        lock.unlock()
    }

    public static func clear() {
        lock.lock()
        state = nil
        lock.unlock()
    }

    public static func sample(at date: Date = Date()) -> Sample? {
        lock.lock()
        let snapshot = state
        lock.unlock()

        guard let current = snapshot else {
            return nil
        }
        switch current {
        case let .point(latitude, longitude):
            return Sample(latitude: latitude, longitude: longitude, course: -1.0, speed: -1.0, fraction: 1.0, distance: 0.0)
        case let .route(fromLatitude, fromLongitude, toLatitude, toLongitude, metersPerSecond, startedAt):
            return routeSample(fromLatitude: fromLatitude, fromLongitude: fromLongitude, toLatitude: toLatitude, toLongitude: toLongitude, metersPerSecond: metersPerSecond, startedAt: startedAt, now: date.timeIntervalSince1970)
        }
    }

    // Чистая функция, её же зовёт экран настроек, чтобы показать прогресс
    public static func routeSample(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double, metersPerSecond: Double, startedAt: Double?, now: Double) -> Sample {
        let from = CLLocation(latitude: fromLatitude, longitude: fromLongitude)
        let to = CLLocation(latitude: toLatitude, longitude: toLongitude)
        let distance = from.distance(from: to)
        let course = bearing(fromLatitude: fromLatitude, fromLongitude: fromLongitude, toLatitude: toLatitude, toLongitude: toLongitude)

        guard let startedAt = startedAt else {
            return Sample(latitude: fromLatitude, longitude: fromLongitude, course: course, speed: -1.0, fraction: 0.0, distance: distance)
        }
        let elapsed = max(0.0, now - startedAt)
        let travelled = min(distance, elapsed * metersPerSecond)
        let fraction = distance > 0.0 ? travelled / distance : 1.0

        // Линейная интерполяция по широте и долготе. На городских и
        // межгородских расстояниях отличие от дуги большого круга меньше
        // точности GPS. Переход через 180-й меридиан не учитывается.
        let latitude = fromLatitude + (toLatitude - fromLatitude) * fraction
        let longitude = fromLongitude + (toLongitude - fromLongitude) * fraction
        let speed = fraction < 1.0 ? metersPerSecond : -1.0
        return Sample(latitude: latitude, longitude: longitude, course: course, speed: speed, fraction: fraction, distance: distance)
    }

    // Нужны ли синтетические обновления по таймеру. Пока координата едет,
    // настоящий GPS может молчать, а получатель должен видеть движение.
    public static func needsTicking(at date: Date = Date()) -> Bool {
        lock.lock()
        let snapshot = state
        lock.unlock()

        guard let current = snapshot, case let .route(fromLatitude, fromLongitude, toLatitude, toLongitude, metersPerSecond, startedAtValue) = current, let startedAt = startedAtValue else {
            return false
        }
        let distance = CLLocation(latitude: fromLatitude, longitude: fromLongitude).distance(from: CLLocation(latitude: toLatitude, longitude: toLongitude))
        let duration = distance / metersPerSecond
        return date.timeIntervalSince1970 - startedAt < duration + arrivalGrace
    }

    // Подставляет координату, сохраняя время исходной точки, чтобы она не
    // выглядела протухшей.
    public static func apply(_ location: CLLocation) -> CLLocation {
        guard let sample = self.sample() else {
            return location
        }
        return makeLocation(sample, altitude: location.altitude, verticalAccuracy: location.verticalAccuracy, timestamp: location.timestamp)
    }

    // Точка для тика таймера, когда свежего обновления от GPS нет
    public static func synthesize(base: CLLocation?) -> CLLocation? {
        guard let sample = self.sample() else {
            return nil
        }
        return makeLocation(sample, altitude: base?.altitude ?? 0.0, verticalAccuracy: base?.verticalAccuracy ?? -1.0, timestamp: Date())
    }

    private static func makeLocation(_ sample: Sample, altitude: Double, verticalAccuracy: Double, timestamp: Date) -> CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
            altitude: altitude,
            horizontalAccuracy: 5.0,
            verticalAccuracy: verticalAccuracy,
            course: sample.speed > 0.0 ? sample.course : -1.0,
            speed: sample.speed,
            timestamp: timestamp
        )
    }

    private static func isValid(_ latitude: Double, _ longitude: Double) -> Bool {
        return CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    private static func bearing(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double) -> Double {
        let lat1 = fromLatitude * .pi / 180.0
        let lat2 = toLatitude * .pi / 180.0
        let deltaLon = (toLongitude - fromLongitude) * .pi / 180.0
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180.0 / .pi
        return (degrees + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
}
