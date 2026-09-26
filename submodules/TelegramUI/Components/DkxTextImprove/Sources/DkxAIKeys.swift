import Foundation
import Security

// MARK: DKX ключи сервисов ИИ для «Улучшить текст». Вводятся в Dkx, живут в
// Keychain. Доступ AfterFirstUnlock без ThisDeviceOnly намеренно, так запись
// переживает удаление и повторную установку приложения и переезжает на новый
// телефон через шифрованную резервную копию. В коде и в сборке ключей нет.
public enum DkxAIKeys {
    public enum Provider: String, CaseIterable {
        case gemini
        case glm

        public var title: String {
            switch self {
            case .gemini:
                return "Gemini"
            case .glm:
                return "GLM"
            }
        }
    }

    private static let service = "uz.dkx.ai"
    private static let lock = NSLock()
    // Кнопку в поле ввода спрашивают на каждой перерисовке панели, Keychain
    // на каждый раз не дёргаем
    private static var cache: [Provider: String] = [:]
    private static var loaded = false

    private static func loadIfNeeded() {
        if loaded {
            return
        }
        loaded = true
        for provider in Provider.allCases {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: provider.rawValue,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty {
                cache[provider] = value
            }
        }
    }

    public static func key(_ provider: Provider) -> String? {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        return cache[provider]
    }

    public static var hasAnyKey: Bool {
        return Provider.allCases.contains(where: { key($0) != nil })
    }

    public static func setKey(_ provider: Provider, _ value: String?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        let _ = SecItemDelete(base as CFDictionary)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            cache[provider] = nil
            return
        }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess {
            cache[provider] = trimmed
        } else {
            cache[provider] = nil
        }
    }

    // Для строки в настройках, сам ключ на экран не выводим
    public static func maskedKey(_ provider: Provider) -> String? {
        guard let value = key(provider) else {
            return nil
        }
        if value.count <= 8 {
            return "••••"
        }
        return String(value.prefix(4)) + "…" + String(value.suffix(4))
    }
}
