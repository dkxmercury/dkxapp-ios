import Foundation
import MapKit
import SwiftSignalKit
import TelegramCore

// Маршрут по дорогам для подмены геолокации. Сначала встроенный в iOS
// маршрутизатор Apple, ему не нужен ключ. Если Apple маршрут не дал, а в
// некоторых странах он дорог не знает, пробуем открытый OSRM на данных
// OpenStreetMap, ему ключ тоже не нужен. Не вышло ни там, ни там, значит
// точка поедет по прямой, и экран настроек это покажет.
//
// Координаты уходят в маршрутизатор. Это точки для проверки ботов, а не
// настоящее местоположение владельца, но помнить об этом стоит.

struct DkxRoadRoute {
    // Широта и долгота подряд
    let path: [Double]
    let source: String
}

// Больше точек не храним. Путь лежит в настройках и читается при каждой
// их правке. На городских маршрутах точность от прореживания не страдает.
private let dkxMaxRoutePoints = 1500

private func dkxThin(_ coordinates: [CLLocationCoordinate2D]) -> [Double] {
    guard !coordinates.isEmpty else {
        return []
    }
    let step = max(1, Int((Double(coordinates.count) / Double(dkxMaxRoutePoints)).rounded(.up)))
    var result: [Double] = []
    result.reserveCapacity((coordinates.count / step + 2) * 2)
    var index = 0
    while index < coordinates.count {
        result.append(coordinates[index].latitude)
        result.append(coordinates[index].longitude)
        index += step
    }
    // Последняя точка должна быть ровно точкой Б
    if let last = coordinates.last, result.count >= 2, (result[result.count - 2] != last.latitude || result[result.count - 1] != last.longitude) {
        result.append(last.latitude)
        result.append(last.longitude)
    }
    return result
}

func dkxComputeRoadRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, walking: Bool) -> Signal<DkxRoadRoute?, NoError> {
    return dkxAppleRoute(from: from, to: to, walking: walking)
    |> mapToSignal { route -> Signal<DkxRoadRoute?, NoError> in
        if let route = route {
            return .single(route)
        }
        return dkxOsrmRoute(from: from, to: to, walking: walking)
    }
    |> map { route -> DkxRoadRoute? in
        if let route = route {
            DkxLog.write("гео", "маршрут по дорогам проложил \(route.source), точек \(route.path.count / 2)")
        } else {
            DkxLog.write("гео", "маршрут по дорогам не получен, едем по прямой")
        }
        return route
    }
}

private func dkxAppleRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, walking: Bool) -> Signal<DkxRoadRoute?, NoError> {
    return Signal { subscriber in
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = walking ? .walking : .automobile
        let directions = MKDirections(request: request)
        directions.calculate(completionHandler: { response, error in
            if let route = response?.routes.first {
                let polyline = route.polyline
                var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
                polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
                let path = dkxThin(coordinates)
                subscriber.putNext(path.count >= 4 ? DkxRoadRoute(path: path, source: "Apple") : nil)
            } else {
                if let error = error {
                    DkxLog.write("гео", "Apple не проложил маршрут, \(error.localizedDescription)")
                }
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
        })
        return ActionDisposable {
            directions.cancel()
        }
    }
}

private func dkxOsrmRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, walking: Bool) -> Signal<DkxRoadRoute?, NoError> {
    return Signal { subscriber in
        // Пешеходный профиль есть только на зеркале openstreetmap.de,
        // автомобильный на основном демонстрационном сервере OSRM
        let base = walking ? "https://routing.openstreetmap.de/routed-foot/route/v1/foot/" : "https://router.project-osrm.org/route/v1/driving/"
        let coordinates = String(format: "%.6f,%.6f;%.6f,%.6f", from.longitude, from.latitude, to.longitude, to.latitude)
        guard let url = URL(string: base + coordinates + "?overview=full&geometries=geojson") else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, _, error in
            var result: DkxRoadRoute?
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let routes = json["routes"] as? [[String: Any]],
               let geometry = routes.first?["geometry"] as? [String: Any],
               let points = geometry["coordinates"] as? [[Double]] {
                let coordinates = points.compactMap { point -> CLLocationCoordinate2D? in
                    guard point.count >= 2 else {
                        return nil
                    }
                    return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
                }
                let path = dkxThin(coordinates)
                if path.count >= 4 {
                    result = DkxRoadRoute(path: path, source: "OpenStreetMap")
                }
            } else if let error = error {
                DkxLog.write("гео", "OSRM не ответил, \(error.localizedDescription)")
            }
            subscriber.putNext(result)
            subscriber.putCompletion()
        })
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}
