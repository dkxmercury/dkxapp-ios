import Foundation
import CoreLocation

// Подмена координат. Один выключатель на всё приложение. Трансляция
// геопозиции, запросы местоположения от веб-ботов, экран выбора точки.
//
// Два режима. В точке координата стоит на месте. В маршруте координата едет
// по ломаной от первой точки к последней с заданной скоростью, от момента
// старта. Прямая из А в Б это ломаная из двух точек, маршрут по дорогам
// это ломаная из маршрутизатора. Положение считается от настенных часов, а
// не накапливается по тикам, поэтому перезапуск приложения посреди
// маршрута ничего не сбивает.
//
// Значение держится в памяти. Перезапуск оно переживает за счёт настроек
// форка, но обращения к настройкам тут намеренно нет. Этот модуль лежит
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
        // В path широта и долгота подряд, не меньше двух точек. startedAt в
        // секундах от 1970, nil значит, что старт не нажат и координата
        // стоит в первой точке.
        case route(path: [Double], metersPerSecond: Double, startedAt: Double?)
    }

    // Сколько секунд после прибытия ещё слать синтетические обновления,
    // чтобы последней ушла ровно конечная точка, а не точка за шаг до неё.
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
        self.setRoute(path: [fromLatitude, fromLongitude, toLatitude, toLongitude], metersPerSecond: metersPerSecond, startedAt: startedAt)
    }

    public static func setRoute(path: [Double], metersPerSecond: Double, startedAt: Double?) {
        guard self.isValidPath(path), metersPerSecond > 0.0 else {
            return
        }
        lock.lock()
        state = .route(path: path, metersPerSecond: metersPerSecond, startedAt: startedAt)
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
        case let .route(path, metersPerSecond, startedAt):
            return self.routeSample(path: path, metersPerSecond: metersPerSecond, startedAt: startedAt, now: date.timeIntervalSince1970)
        }
    }

    // Прямая из А в Б. Оставлено для экрана настроек и старых вызовов.
    public static func routeSample(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double, metersPerSecond: Double, startedAt: Double?, now: Double) -> Sample {
        return self.routeSample(path: [fromLatitude, fromLongitude, toLatitude, toLongitude], metersPerSecond: metersPerSecond, startedAt: startedAt, now: now)
    }

    // Длина ломаной в метрах
    public static func pathLength(_ path: [Double]) -> Double {
        var total = 0.0
        var i = 2
        while i + 1 < path.count {
            total += CLLocation(latitude: path[i - 2], longitude: path[i - 1]).distance(from: CLLocation(latitude: path[i], longitude: path[i + 1]))
            i += 2
        }
        return total
    }

    // Чистая функция, её же зовёт экран настроек, чтобы показать прогресс
    public static func routeSample(path: [Double], metersPerSecond: Double, startedAt: Double?, now: Double) -> Sample {
        guard self.isValidPath(path) else {
            return Sample(latitude: path.first ?? 0.0, longitude: path.count > 1 ? path[1] : 0.0, course: -1.0, speed: -1.0, fraction: 1.0, distance: 0.0)
        }
        let pointCount = path.count / 2
        var segmentLengths: [Double] = []
        segmentLengths.reserveCapacity(pointCount - 1)
        for index in 0 ..< pointCount - 1 {
            let a = CLLocation(latitude: path[index * 2], longitude: path[index * 2 + 1])
            let b = CLLocation(latitude: path[index * 2 + 2], longitude: path[index * 2 + 3])
            segmentLengths.append(a.distance(from: b))
        }
        let distance = segmentLengths.reduce(0.0, +)

        let firstCourse = self.bearing(fromLatitude: path[0], fromLongitude: path[1], toLatitude: path[2], toLongitude: path[3])
        guard let startedAt = startedAt else {
            return Sample(latitude: path[0], longitude: path[1], course: firstCourse, speed: -1.0, fraction: 0.0, distance: distance)
        }
        let elapsed = max(0.0, now - startedAt)
        let travelled = min(distance, elapsed * metersPerSecond)
        let fraction = distance > 0.0 ? travelled / distance : 1.0

        // Ищем участок, на котором сейчас точка. Внутри участка линейная
        // интерполяция по широте и долготе. Участки короткие, отличие от
        // дуги большого круга меньше точности GPS. Переход через 180-й
        // меридиан не учитывается.
        var remaining = travelled
        var segment = 0
        while segment < segmentLengths.count - 1 && remaining > segmentLengths[segment] {
            remaining -= segmentLengths[segment]
            segment += 1
        }
        let length = segmentLengths[segment]
        let t = length > 0.0 ? min(1.0, remaining / length) : 1.0
        let fromLatitude = path[segment * 2]
        let fromLongitude = path[segment * 2 + 1]
        let toLatitude = path[segment * 2 + 2]
        let toLongitude = path[segment * 2 + 3]
        let latitude = fromLatitude + (toLatitude - fromLatitude) * t
        let longitude = fromLongitude + (toLongitude - fromLongitude) * t
        let course = self.bearing(fromLatitude: fromLatitude, fromLongitude: fromLongitude, toLatitude: toLatitude, toLongitude: toLongitude)
        let speed = fraction < 1.0 ? metersPerSecond : -1.0
        return Sample(latitude: latitude, longitude: longitude, course: course, speed: speed, fraction: fraction, distance: distance)
    }

    // Нужны ли синтетические обновления по таймеру. Пока координата едет,
    // настоящий GPS может молчать, а получатель должен видеть движение.
    public static func needsTicking(at date: Date = Date()) -> Bool {
        lock.lock()
        let snapshot = state
        lock.unlock()

        guard let current = snapshot, case let .route(path, metersPerSecond, startedAtValue) = current, let startedAt = startedAtValue else {
            return false
        }
        let duration = self.pathLength(path) / metersPerSecond
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

    private static func isValidPath(_ path: [Double]) -> Bool {
        guard path.count >= 4, path.count % 2 == 0 else {
            return false
        }
        var i = 0
        while i + 1 < path.count {
            if !self.isValid(path[i], path[i + 1]) {
                return false
            }
            i += 2
        }
        return true
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
