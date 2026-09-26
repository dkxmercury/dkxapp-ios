import Foundation
import UIKit
import Security
import TelegramCore
import MtProtoKit
import AuthenticationServices
import SwiftSignalKit

// Выгрузка медиа в Google Drive. Вход по OAuth 2.0 с PKCE в системном окне,
// без GoogleSignIn SDK. Аккаунтов может быть несколько, у каждого свои токены
// в Keychain только на этом устройстве, своё имя и отметка основного.
// Client ID приходит в Info.plist при сборке из секрета GOOGLE_IOS_CLIENT_ID,
// в исходниках его нет.

public struct DkxDriveAccount: Equatable {
    public let id: String
    public let email: String
    public let name: String

    public var title: String {
        return self.name.isEmpty ? self.email : self.name
    }
}

public enum DkxGoogleDrive {
    // Client ID из Info.plist. Пусто, если сборка без секрета. Тогда вся
    // фича молчит и в интерфейсе показывается, что не настроено.
    public static var clientId: String {
        return (Bundle.main.object(forInfoDictionaryKey: "DkxGoogleClientID") as? String) ?? ""
    }

    public static var isConfigured: Bool {
        return !clientId.isEmpty
    }

    // Обратная схема из Client ID, её ждёт Google как redirect для iOS.
    // 130...apps.googleusercontent.com -> com.googleusercontent.apps.130...
    private static var redirectScheme: String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientId.hasSuffix(suffix) else {
            return nil
        }
        let core = String(clientId.dropLast(suffix.count))
        return "com.googleusercontent.apps.\(core)"
    }

    private static var redirectUri: String? {
        guard let scheme = redirectScheme else {
            return nil
        }
        return "\(scheme):/oauth2redirect"
    }

    private static let scope = "https://www.googleapis.com/auth/drive.file openid email"

    // Удержание системного окна входа на время сессии
    private static var activeSession: ASWebAuthenticationSession?
    private static var activeProvider: DkxAuthPresentationProvider?

    private static let keychainService = "uz.dkx.gdrive"
    private static let listKey = "accounts"
    private static let lock = NSLock()

    private static func keychainSet(_ key: String, _ value: String?) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        guard let value = value, let data = value.data(using: .utf8) else {
            SecItemDelete(match as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func keychainGet(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private struct StoredAccount: Codable {
        var id: String
        var email: String
        var name: String
    }

    private struct StoredList: Codable {
        var accounts: [StoredAccount]
        var main: String?
    }

    private static func loadList() -> StoredList {
        if let raw = keychainGet(listKey), let data = raw.data(using: .utf8), let list = try? JSONDecoder().decode(StoredList.self, from: data) {
            return list
        }
        // Вход из прошлых сборок был один и лежал без номера аккаунта
        var list = StoredList(accounts: [], main: nil)
        if let refreshToken = keychainGet("refresh_token") {
            let id = newAccountId()
            keychainSet("refresh_token.\(id)", refreshToken)
            keychainSet("client_id.\(id)", keychainGet("client_id"))
            keychainSet("access_token.\(id)", keychainGet("access_token"))
            keychainSet("access_expiry.\(id)", keychainGet("access_expiry"))
            list.accounts.append(StoredAccount(id: id, email: keychainGet("email") ?? "", name: ""))
            list.main = id
            for key in ["refresh_token", "client_id", "access_token", "access_expiry", "email"] {
                keychainSet(key, nil)
            }
            saveList(list)
            DkxLog.write("drive", "прежний вход перенесён в список аккаунтов")
        }
        return list
    }

    private static func saveList(_ list: StoredList) {
        if let data = try? JSONEncoder().encode(list), let raw = String(data: data, encoding: .utf8) {
            keychainSet(listKey, raw)
        }
    }

    private static func newAccountId() -> String {
        var bytes = [UInt8](repeating: 0, count: 6)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // Вход привязан к клиенту, который его выдал. После смены Client ID в
    // сборке старый вход не работает, и такой аккаунт считаем отвязанным.
    private static func isValid(_ id: String) -> Bool {
        return keychainGet("refresh_token.\(id)") != nil && keychainGet("client_id.\(id)") == clientId
    }

    public static var accounts: [DkxDriveAccount] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return loadList().accounts.filter { isValid($0.id) }.map { DkxDriveAccount(id: $0.id, email: $0.email, name: $0.name) }
    }

    public static var isConnected: Bool {
        return !accounts.isEmpty
    }

    // Основной аккаунт, если он выбран и ещё привязан
    public static var mainAccountId: String? {
        lock.lock()
        defer {
            lock.unlock()
        }
        let list = loadList()
        guard let main = list.main, list.accounts.contains(where: { $0.id == main }), isValid(main) else {
            return nil
        }
        return main
    }

    public static func setMain(_ id: String?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        var list = loadList()
        list.main = id
        saveList(list)
    }

    public static func rename(_ id: String, _ name: String) {
        lock.lock()
        defer {
            lock.unlock()
        }
        var list = loadList()
        if let index = list.accounts.firstIndex(where: { $0.id == id }) {
            list.accounts[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            saveList(list)
        }
    }

    public static func disconnect(_ id: String) {
        lock.lock()
        defer {
            lock.unlock()
        }
        for key in ["refresh_token", "client_id", "access_token", "access_expiry"] {
            keychainSet("\(key).\(id)", nil)
        }
        var list = loadList()
        list.accounts.removeAll(where: { $0.id == id })
        if list.main == id {
            list.main = nil
        }
        saveList(list)
        DkxLog.write("drive", "аккаунт отвязан")
    }

    // Куда грузить. Названный аккаунт, иначе основной, иначе единственный или первый
    public static func resolvedAccountId(_ preferred: String?) -> String? {
        let all = accounts
        if let preferred, all.contains(where: { $0.id == preferred }) {
            return preferred
        }
        if let main = mainAccountId {
            return main
        }
        return all.first?.id
    }

    // Нужно ли спрашивать аккаунт перед выгрузкой
    public static var needsChoice: Bool {
        return mainAccountId == nil && accounts.count > 1
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64Url(Data(bytes))
    }

    private static func challenge(from verifier: String) -> String {
        return base64Url(MTSha256(Data(verifier.utf8)))
    }

    private static func base64Url(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // Добавляет аккаунт. presentationAnchor даёт окно, над которым показать системный вход.
    // Тот же почтовый ящик второй раз не заводится, у него обновляется вход
    public static func connect(presentationAnchor: @escaping () -> ASPresentationAnchor) -> Signal<Bool, NoError> {
        guard isConfigured, let redirectUri = redirectUri, let redirectScheme = redirectScheme else {
            return .single(false)
        }
        return Signal { subscriber in
            let verifier = randomVerifier()
            let challengeValue = challenge(from: verifier)
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "redirect_uri", value: redirectUri),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scope),
                URLQueryItem(name: "code_challenge", value: challengeValue),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent select_account")
            ]
            guard let authUrl = components.url else {
                subscriber.putNext(false)
                subscriber.putCompletion()
                return EmptyDisposable
            }

            let session = ASWebAuthenticationSession(url: authUrl, callbackURLScheme: redirectScheme, completionHandler: { callbackUrl, error in
                // Отпускаем удержание сессии по завершении
                activeSession = nil
                activeProvider = nil
                guard let callbackUrl = callbackUrl,
                      let code = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                    if let error = error {
                        DkxLog.write("drive", "вход прерван, \(error.localizedDescription)")
                    }
                    subscriber.putNext(false)
                    subscriber.putCompletion()
                    return
                }
                exchangeCode(code: code, verifier: verifier, redirectUri: redirectUri, completion: { success in
                    subscriber.putNext(success)
                    subscriber.putCompletion()
                })
            })
            let provider = DkxAuthPresentationProvider(anchor: presentationAnchor)
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            // Систему надо держать за сессию и провайдер до самого конца, иначе
            // окно входа закроется сразу. Ссылки уходят в статику.
            activeSession = session
            activeProvider = provider
            session.start()

            return ActionDisposable {
                session.cancel()
            }
        }
        |> runOn(Queue.mainQueue())
    }

    private static func exchangeCode(code: String, verifier: String, redirectUri: String, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id=\(clientId)",
            "code=\(code)",
            "code_verifier=\(verifier)",
            "grant_type=authorization_code",
            "redirect_uri=\(redirectUri)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false)
                return
            }
            guard let refreshToken = json["refresh_token"] as? String, let accessToken = json["access_token"] as? String else {
                DkxLog.write("drive", "токен не получен")
                completion(false)
                return
            }
            var email = ""
            if let idToken = json["id_token"] as? String, let value = emailFromIdToken(idToken) {
                email = value
            }
            lock.lock()
            var list = loadList()
            let id: String
            if !email.isEmpty, let existing = list.accounts.first(where: { $0.email.lowercased() == email.lowercased() }) {
                id = existing.id
            } else {
                id = newAccountId()
                list.accounts.append(StoredAccount(id: id, email: email, name: ""))
            }
            keychainSet("refresh_token.\(id)", refreshToken)
            keychainSet("client_id.\(id)", clientId)
            storeAccessToken(accountId: id, token: accessToken, expiresIn: json["expires_in"] as? Double ?? 3600.0)
            if list.accounts.count == 1 {
                list.main = id
            }
            saveList(list)
            lock.unlock()
            DkxLog.write("drive", "аккаунт привязан")
            completion(true)
        }).resume()
    }

    private static func storeAccessToken(accountId: String, token: String, expiresIn: Double) {
        keychainSet("access_token.\(accountId)", token)
        keychainSet("access_expiry.\(accountId)", String(Date().timeIntervalSince1970 + expiresIn - 60.0))
    }

    private static func emailFromIdToken(_ idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }
        guard let data = Data(base64Encoded: payload), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["email"] as? String
    }

    // Свежий access token аккаунта, обновляется по refresh token при истечении
    static func accessToken(accountId: String, completion: @escaping (String?) -> Void) {
        if let token = keychainGet("access_token.\(accountId)"), let expiryString = keychainGet("access_expiry.\(accountId)"), let expiry = Double(expiryString), expiry > Date().timeIntervalSince1970 {
            completion(token)
            return
        }
        guard let refreshToken = keychainGet("refresh_token.\(accountId)") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id=\(clientId)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let token = json?["access_token"] as? String else {
                // Вход отозван, протух или выдан другим клиентом. Такой уже не
                // оживить, стираем его, и экран покажет, что аккаунта нет.
                if let error = json?["error"] as? String, ["invalid_grant", "invalid_client", "unauthorized_client"].contains(error) {
                    disconnect(accountId)
                    DkxLog.write("drive", "вход недействителен, \(error), отвязан")
                } else {
                    DkxLog.write("drive", "обновить вход не вышло, нет сети или ответа")
                }
                completion(nil)
                return
            }
            storeAccessToken(accountId: accountId, token: token, expiresIn: json?["expires_in"] as? Double ?? 3600.0)
            completion(token)
        }).resume()
    }
}

private final class DkxAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: () -> ASPresentationAnchor

    init(anchor: @escaping () -> ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return self.anchor()
    }
}
