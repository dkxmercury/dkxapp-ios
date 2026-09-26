import Foundation

let dkxStringsTable: [String: [String: String]] = {
    guard let data = dkxStringsJSON.data(using: .utf8), let table = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
        return [:]
    }
    return table
}()

// JSON строкой, а не литералом словаря, потому что словарь на тысячи строк Swift компилирует очень долго
private let dkxStringsJSON = #"""
{}
"""#
