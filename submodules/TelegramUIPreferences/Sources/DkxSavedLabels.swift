import Foundation
import Security
import SwiftSignalKit

// MARK: DKX свои метки на сообщения в Избранном. Отдельно от меток чатов.
// Лежат в Keychain без ThisDeviceOnly, чтобы пережить переустановку и
// переехать на новый телефон через шифрованную копию. Номера сообщений в
// Избранном серверные, после переустановки метки встают на те же сообщения.
public struct DkxSavedLabel: Codable, Equatable {
    public let id: Int32
    public var title: String
    public var colorId: Int32

    public init(id: Int32, title: String, colorId: Int32) {
        self.id = id
        self.title = title
        self.colorId = colorId
    }
}

// account это peerId своего Избранного, у каждого аккаунта оно своё
public struct DkxSavedLabelMark: Codable, Equatable {
    public let account: Int64
    public let message: Int32
    public let label: Int32

    public init(account: Int64, message: Int32, label: Int32) {
        self.account = account
        self.message = message
        self.label = label
    }
}

public struct DkxSavedLabels: Codable, Equatable {
    public var labels: [DkxSavedLabel]
    public var marks: [DkxSavedLabelMark]

    public init() {
        self.labels = []
        self.marks = []
    }

    public var nextLabelId: Int32 {
        return (self.labels.map { $0.id }.max() ?? 0) + 1
    }

    public func labelIds(account: Int64, message: Int32) -> Set<Int32> {
        return Set(self.marks.filter { $0.account == account && $0.message == message }.map { $0.label })
    }

    // Свежие сверху
    public func messages(account: Int64, label: Int32) -> [Int32] {
        return self.marks.filter { $0.account == account && $0.label == label }.map { $0.message }.sorted(by: >)
    }

    public mutating func set(label: Int32, account: Int64, message: Int32, assigned: Bool) {
        self.marks.removeAll(where: { $0.account == account && $0.message == message && $0.label == label })
        if assigned {
            self.marks.append(DkxSavedLabelMark(account: account, message: message, label: label))
        }
    }

    // Метки с удалённых меток уходят вместе с ними
    public mutating func setLabels(_ labels: [DkxSavedLabel]) {
        self.labels = labels
        let valid = Set(labels.map { $0.id })
        self.marks.removeAll(where: { !valid.contains($0.label) })
    }

    public mutating func removeMessages(account: Int64, messages: Set<Int32>) {
        self.marks.removeAll(where: { $0.account == account && messages.contains($0.message) })
    }
}

public enum DkxSavedLabelsStore {
    private static let service = "uz.dkx.savedlabels"
    private static let item = "v1"
    private static let lock = NSLock()
    private static var cache = DkxSavedLabels()
    private static var loaded = false
    private static let promise = ValuePromise<DkxSavedLabels>(DkxSavedLabels(), ignoreRepeated: true)

    // До первой разблокировки после включения Keychain не отдаёт запись. Тогда
    // не считаем хранилище пустым и не пишем, иначе затрём сохранённые метки
    private static func loadIfNeeded() {
        if loaded {
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            if let data = result as? Data, let value = try? JSONDecoder().decode(DkxSavedLabels.self, from: data) {
                cache = value
                loaded = true
            }
        } else if status == errSecItemNotFound {
            loaded = true
        }
    }

    public static var current: DkxSavedLabels {
        lock.lock()
        loadIfNeeded()
        let result = cache
        lock.unlock()
        return result
    }

    public static var signal: Signal<DkxSavedLabels, NoError> {
        promise.set(current)
        return promise.get()
    }

    public static func update(_ f: (inout DkxSavedLabels) -> Void) {
        lock.lock()
        loadIfNeeded()
        guard loaded else {
            lock.unlock()
            return
        }
        var updated = cache
        f(&updated)
        guard updated != cache, let data = try? JSONEncoder().encode(updated) else {
            lock.unlock()
            return
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item
        ]
        let changes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        var status = SecItemUpdate(base as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = base
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        if status == errSecSuccess {
            cache = updated
        }
        let saved = status == errSecSuccess
        lock.unlock()
        if saved {
            promise.set(updated)
        }
    }
}
