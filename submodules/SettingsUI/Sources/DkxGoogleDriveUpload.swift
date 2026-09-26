import Foundation
import SwiftSignalKit
import TelegramCore

// Загрузка файла в Google Drive. Дедуп по appProperties, раскладка папка
// Dkx и подпапка по чату. Загрузка resumable. Заводим сессию, потом шлём
// байты одним PUT из файла. Фоновая догрузка больших видео отдельным шагом,
// пока грузим на переднем плане.

public enum DkxGoogleDriveUploadResult {
    case uploaded
    case duplicate
    case notConnected
    case failed(String)
}

public enum DkxGoogleDriveUpload {
    // Кэш идентификаторов папок на сессию, чтобы не искать каждый раз
    private static var folderCache: [String: String] = [:]
    private static let cacheLock = NSLock()

    private static func cachedFolder(_ key: String) -> String? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return folderCache[key]
    }

    private static func cacheFolder(_ key: String, _ id: String) {
        cacheLock.lock(); folderCache[key] = id; cacheLock.unlock()
    }

    public static func upload(filePath: String, fileName: String, mimeType: String, chatId: Int64, chatTitle: String, messageId: Int32) -> Signal<DkxGoogleDriveUploadResult, NoError> {
        return Signal { subscriber in
            guard DkxGoogleDrive.isConnected else {
                subscriber.putNext(.notConnected)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let cancelled = Atomic<Bool>(value: false)
            DkxGoogleDrive.accessToken(completion: { token in
                guard let token = token else {
                    subscriber.putNext(.failed("Нужно войти в Google заново"))
                    subscriber.putCompletion()
                    return
                }
                let dedupKey = "\(chatId)_\(messageId)"
                findDuplicate(token: token, key: dedupKey, completion: { exists in
                    if cancelled.with({ $0 }) {
                        subscriber.putCompletion()
                        return
                    }
                    if exists {
                        DkxLog.write("drive", "уже загружено, \(dedupKey)")
                        subscriber.putNext(.duplicate)
                        subscriber.putCompletion()
                        return
                    }
                    ensureFolder(token: token, chatId: chatId, chatTitle: chatTitle, completion: { folderId in
                        if cancelled.with({ $0 }) {
                            subscriber.putCompletion()
                            return
                        }
                        performUpload(token: token, filePath: filePath, fileName: fileName, mimeType: mimeType, parentId: folderId, dedupKey: dedupKey, completion: { result in
                            subscriber.putNext(result)
                            subscriber.putCompletion()
                        })
                    })
                })
            })
            return ActionDisposable {
                let _ = cancelled.swap(true)
            }
        }
        |> runOn(Queue.concurrentDefaultQueue())
    }

    private static func authorized(_ url: URL, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func findDuplicate(token: String, key: String, completion: @escaping (Bool) -> Void) {
        let query = "appProperties has { key='dkxKey' and value='\(key)' } and trashed=false"
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "spaces", value: "drive")
        ]
        guard let url = components.url else {
            completion(false)
            return
        }
        URLSession.shared.dataTask(with: authorized(url, token: token), completionHandler: { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let files = json["files"] as? [[String: Any]] else {
                completion(false)
                return
            }
            completion(!files.isEmpty)
        }).resume()
    }

    // Возвращает id подпапки чата внутри папки Dkx, создавая обе при нужде.
    // parentId nil означает загрузку в корень, если папку сделать не вышло.
    private static func ensureFolder(token: String, chatId: Int64, chatTitle: String, completion: @escaping (String?) -> Void) {
        ensureSingleFolder(token: token, name: "Dkx", parentId: nil, propKey: "dkxRoot", propValue: "1", completion: { rootId in
            guard let rootId = rootId else {
                completion(nil)
                return
            }
            let safeTitle = chatTitle.isEmpty ? "Чат \(chatId)" : chatTitle
            ensureSingleFolder(token: token, name: safeTitle, parentId: rootId, propKey: "dkxChatId", propValue: String(chatId), completion: { chatFolderId in
                completion(chatFolderId ?? rootId)
            })
        })
    }

    private static func ensureSingleFolder(token: String, name: String, parentId: String?, propKey: String, propValue: String, completion: @escaping (String?) -> Void) {
        let cacheKey = "\(propKey)=\(propValue)"
        if let cached = cachedFolder(cacheKey) {
            completion(cached)
            return
        }
        var query = "mimeType='application/vnd.google-apps.folder' and appProperties has { key='\(propKey)' and value='\(propValue)' } and trashed=false"
        if let parentId = parentId {
            query += " and '\(parentId)' in parents"
        }
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "spaces", value: "drive")
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: authorized(url, token: token), completionHandler: { data, _, _ in
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let files = json["files"] as? [[String: Any]], let id = files.first?["id"] as? String {
                cacheFolder(cacheKey, id)
                completion(id)
                return
            }
            createFolder(token: token, name: name, parentId: parentId, propKey: propKey, propValue: propValue, completion: { id in
                if let id = id {
                    cacheFolder(cacheKey, id)
                }
                completion(id)
            })
        }).resume()
    }

    private static func createFolder(token: String, name: String, parentId: String?, propKey: String, propValue: String, completion: @escaping (String?) -> Void) {
        var metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "appProperties": [propKey: propValue]
        ]
        if let parentId = parentId {
            metadata["parents"] = [parentId]
        }
        var request = authorized(URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!, token: token, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: metadata)
        URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["id"] as? String else {
                completion(nil)
                return
            }
            completion(id)
        }).resume()
    }

    private static func performUpload(token: String, filePath: String, fileName: String, mimeType: String, parentId: String?, dedupKey: String, completion: @escaping (DkxGoogleDriveUploadResult) -> Void) {
        var metadata: [String: Any] = [
            "name": fileName,
            "appProperties": ["dkxKey": dedupKey]
        ]
        if let parentId = parentId {
            metadata["parents"] = [parentId]
        }
        var startRequest = authorized(URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!, token: token, method: "POST")
        startRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        startRequest.httpBody = try? JSONSerialization.data(withJSONObject: metadata)
        URLSession.shared.dataTask(with: startRequest, completionHandler: { _, response, _ in
            guard let httpResponse = response as? HTTPURLResponse, let location = httpResponse.value(forHTTPHeaderField: "Location"), let sessionUrl = URL(string: location) else {
                completion(.failed("Google не принял загрузку"))
                return
            }
            var putRequest = URLRequest(url: sessionUrl)
            putRequest.httpMethod = "PUT"
            putRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            let fileUrl = URL(fileURLWithPath: filePath)
            let task = URLSession.shared.uploadTask(with: putRequest, fromFile: fileUrl, completionHandler: { _, response, error in
                if let error = error {
                    completion(.failed(error.localizedDescription))
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 || code == 201 {
                    DkxLog.write("drive", "загружено, \(dedupKey)")
                    completion(.uploaded)
                } else {
                    completion(.failed("Код \(code)"))
                }
            })
            task.resume()
        }).resume()
    }
}
