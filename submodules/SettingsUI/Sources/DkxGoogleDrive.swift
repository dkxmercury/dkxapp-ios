import Foundation
import UIKit
import Security
import TelegramCore
import MtProtoKit
import AuthenticationServices
import SwiftSignalKit

// Выгрузка медиа в Google Drive. Вход по OAuth 2.0 с PKCE в системном окне,
// без GoogleSignIn SDK. Токен обновления и почта аккаунта лежат в Keychain
// только на этом устройстве. Client ID приходит в Info.plist при сборке из
// секрета GOOGLE_IOS_CLIENT_ID, в исходниках его нет.

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

    // MARK: Keychain

    private static let keychainService = "uz.dkx.gdrive"

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

    public static var connectedEmail: String? {
        return keychainGet("email")
    }

    public static var isConnected: Bool {
        return keychainGet("refresh_token") != nil
    }

    public static func disconnect() {
        keychainSet("refresh_token", nil)
        keychainSet("email", nil)
        keychainSet("access_token", nil)
        keychainSet("access_expiry", nil)
        DkxLog.write("drive", "аккаунт отвязан")
    }

    // MARK: PKCE

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

    // MARK: Вход

    // presentationAnchor даёт окно, над которым показать системный вход
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
                URLQueryItem(name: "prompt", value: "consent")
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
            keychainSet("refresh_token", refreshToken)
            storeAccessToken(accessToken, expiresIn: json["expires_in"] as? Double ?? 3600.0)
            if let idToken = json["id_token"] as? String, let email = emailFromIdToken(idToken) {
                keychainSet("email", email)
            }
            DkxLog.write("drive", "аккаунт привязан")
            completion(true)
        }).resume()
    }

    private static func storeAccessToken(_ token: String, expiresIn: Double) {
        keychainSet("access_token", token)
        keychainSet("access_expiry", String(Date().timeIntervalSince1970 + expiresIn - 60.0))
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

    // MARK: Токен доступа

    // Свежий access token, обновляется по refresh token при истечении
    static func accessToken(completion: @escaping (String?) -> Void) {
        if let token = keychainGet("access_token"), let expiryString = keychainGet("access_expiry"), let expiry = Double(expiryString), expiry > Date().timeIntervalSince1970 {
            completion(token)
            return
        }
        guard let refreshToken = keychainGet("refresh_token") else {
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
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let token = json["access_token"] as? String else {
                // Refresh протух, в Testing это раз в 7 дней. Просим войти заново.
                DkxLog.write("drive", "refresh не сработал, нужен повторный вход")
                completion(nil)
                return
            }
            storeAccessToken(token, expiresIn: json["expires_in"] as? Double ?? 3600.0)
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
