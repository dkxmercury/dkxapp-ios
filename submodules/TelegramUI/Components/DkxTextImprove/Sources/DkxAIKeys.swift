import Foundation
import Security

// Ключи и выбор моделей сервисов ИИ. Живут в Keychain с AfterFirstUnlock без
// ThisDeviceOnly намеренно, так запись переживает удаление и повторную установку
// приложения и переезжает на новый телефон через шифрованную резервную копию.
// В коде и в сборке ключей нет.
public enum DkxAIKeys {
    public enum Format {
        case openAI
        case anthropic
        case gemini
    }

    public enum Provider: String, CaseIterable {
        case deepseek
        case qwen
        case glm
        case openai
        case claude
        case xiaomi
        case cloudflare
        case mistral
        case gemini
        case openrouter

        public var title: String {
            switch self {
            case .deepseek:
                return "DeepSeek"
            case .qwen:
                return "Qwen"
            case .glm:
                return "GLM"
            case .openai:
                return "OpenAI"
            case .claude:
                return "Claude"
            case .xiaomi:
                return "Xiaomi MiMo"
            case .cloudflare:
                return "Cloudflare"
            case .mistral:
                return "Mistral"
            case .gemini:
                return "Gemini"
            case .openrouter:
                return "OpenRouter"
            }
        }

        public var format: Format {
            switch self {
            case .claude:
                return .anthropic
            case .gemini:
                return .gemini
            default:
                return .openAI
            }
        }

        // У Cloudflare в адресе номер аккаунта, он подставляется вместо {account}
        public var defaultBase: String {
            switch self {
            case .deepseek:
                return "https://api.deepseek.com"
            case .qwen:
                return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
            case .glm:
                return "https://api.z.ai/api/paas/v4"
            case .openai:
                return "https://api.openai.com/v1"
            case .claude:
                return "https://api.anthropic.com/v1"
            case .xiaomi:
                return "https://api.xiaomimimo.com/v1"
            case .cloudflare:
                return "https://api.cloudflare.com/client/v4/accounts/{account}/ai/v1"
            case .mistral:
                return "https://api.mistral.ai/v1"
            case .gemini:
                return "https://generativelanguage.googleapis.com/v1beta"
            case .openrouter:
                return "https://openrouter.ai/api/v1"
            }
        }

        public var needsAccount: Bool {
            return self == .cloudflare
        }
    }

    private struct Config: Codable {
        var main: String?
        var models: [String: String] = [:]
        var bases: [String: String] = [:]
        var accounts: [String: String] = [:]
    }

    private static let service = "uz.dkx.ai"
    private static let configAccount = "config"
    private static let lock = NSLock()
    // Кнопку в поле ввода спрашивают на каждой перерисовке панели, Keychain
    // на каждый раз не дёргаем
    private static var cache: [Provider: String] = [:]
    private static var config = Config()
    private static var loaded = false

    private static func read(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return data
        }
        return nil
    }

    @discardableResult
    private static func write(_ account: String, _ data: Data?) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let _ = SecItemDelete(base as CFDictionary)
        guard let data else {
            return true
        }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private static func loadIfNeeded() {
        if loaded {
            return
        }
        loaded = true
        for provider in Provider.allCases {
            if let data = read(provider.rawValue), let value = String(data: data, encoding: .utf8), !value.isEmpty {
                cache[provider] = value
            }
        }
        if let data = read(configAccount), let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        }
        // Ключи Gemini и GLM из прошлых сборок работали на этих моделях, выбор сохраняем
        if cache[.gemini] != nil && config.models[Provider.gemini.rawValue] == nil {
            config.models[Provider.gemini.rawValue] = "gemini-3.5-flash-lite"
        }
        if cache[.glm] != nil && config.models[Provider.glm.rawValue] == nil {
            config.models[Provider.glm.rawValue] = "glm-4.5-flash"
        }
    }

    private static func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            write(configAccount, data)
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

    public static func setKey(_ provider: Provider, _ value: String?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            write(provider.rawValue, nil)
            cache[provider] = nil
            config.models[provider.rawValue] = nil
            if config.main == provider.rawValue {
                config.main = nil
            }
            saveConfig()
            return
        }
        if write(provider.rawValue, trimmed.data(using: .utf8)) {
            cache[provider] = trimmed
        } else {
            cache[provider] = nil
        }
    }

    public static func model(_ provider: Provider) -> String? {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        return config.models[provider.rawValue]
    }

    public static func setModel(_ provider: Provider, _ value: String?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        config.models[provider.rawValue] = trimmed.isEmpty ? nil : trimmed
        saveConfig()
    }

    // Свой адрес API, если сервис переехал или нужен другой регион. Пусто, значит обычный
    public static func customBase(_ provider: Provider) -> String? {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        return config.bases[provider.rawValue]
    }

    public static func setCustomBase(_ provider: Provider, _ value: String?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        var trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        config.bases[provider.rawValue] = trimmed.isEmpty ? nil : trimmed
        saveConfig()
    }

    public static func account(_ provider: Provider) -> String? {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        return config.accounts[provider.rawValue]
    }

    public static func setAccount(_ provider: Provider, _ value: String?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        config.accounts[provider.rawValue] = trimmed.isEmpty ? nil : trimmed
        saveConfig()
    }

    public static var main: Provider? {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        return config.main.flatMap(Provider.init(rawValue:))
    }

    public static func setMain(_ provider: Provider?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        loadIfNeeded()
        config.main = provider?.rawValue
        saveConfig()
    }

    public static func base(_ provider: Provider) -> String {
        let value = customBase(provider) ?? provider.defaultBase
        return value.replacingOccurrences(of: "{account}", with: account(provider) ?? "")
    }

    // Сервис готов к работе, когда есть ключ и выбрана модель
    public static func isReady(_ provider: Provider) -> Bool {
        if key(provider) == nil || model(provider) == nil {
            return false
        }
        if provider.needsAccount && account(provider) == nil {
            return false
        }
        return true
    }

    public static var hasAnyKey: Bool {
        return Provider.allCases.contains(where: { isReady($0) })
    }

    // Порядок попыток. Основной первым, дальше остальные готовые по списку
    public static func order(preferring preferred: Provider? = nil) -> [Provider] {
        var result: [Provider] = []
        if let preferred, isReady(preferred) {
            result.append(preferred)
        }
        if let main, isReady(main), !result.contains(main) {
            result.append(main)
        }
        for provider in Provider.allCases where isReady(provider) && !result.contains(provider) {
            result.append(provider)
        }
        return result
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
