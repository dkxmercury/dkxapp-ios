import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

// Загрузка файла в Google Drive. Дедуп по appProperties, раскладка папка
// Dkx и подпапка по чату. Загрузка resumable. Сессию на стороне Google
// заводим обычным запросом, а байты шлёт фоновая URLSession, поэтому большой
// файл догружается и при свёрнутом приложении. Файлы идут очередью по
// одному, ход виден в полосе под шапкой.

public enum DkxGoogleDriveUploadResult {
    case uploaded
    case duplicate
    case notConnected
    case cancelled
    case failed(String)
}

// Итог пачки загрузок, отдаётся вместе с последним файлом, когда очередь опустела
public struct DkxGoogleDriveBatchSummary {
    public let uploaded: Int
    public let duplicates: Int
    public let failed: Int
}

public final class DkxGoogleDriveUploadJob {
    let id: Int64
    public let fileName: String
    public let mimeType: String
    public let chatId: Int64
    public let chatTitle: String
    public let messageId: Int32
    // Докачивает файл из Telegram и отдаёт путь к нему
    public let prepare: Signal<String, NoError>
    // Повторная загрузка по просьбе владельца, дубль на диске не проверяем
    public let force: Bool
    public let completion: (DkxGoogleDriveUploadResult, DkxGoogleDriveBatchSummary?) -> Void

    public init(fileName: String, mimeType: String, chatId: Int64, chatTitle: String, messageId: Int32, force: Bool = false, prepare: Signal<String, NoError>, completion: @escaping (DkxGoogleDriveUploadResult, DkxGoogleDriveBatchSummary?) -> Void) {
        var value: Int64 = 0
        arc4random_buf(&value, MemoryLayout<Int64>.size)
        self.id = value
        self.fileName = fileName
        self.mimeType = mimeType
        self.chatId = chatId
        self.chatTitle = chatTitle
        self.messageId = messageId
        self.force = force
        self.prepare = prepare
        self.completion = completion
    }
}

// Очередь живёт на главном потоке, все ответы сети переносятся туда же.
// Готовим файлы не больше двух сразу, а готовый файл сразу отдаём фоновой
// сессии. Так несколько файлов грузятся параллельно и догружаются, даже если
// приложение свернули.
public enum DkxGoogleDriveUploadQueue {
    private final class Entry {
        let job: DkxGoogleDriveUploadJob
        let prepareDisposable = MetaDisposable()
        var preparing = false
        var uploading = false
        var fraction: Double = 0.0
        var task: URLSessionTask?

        init(job: DkxGoogleDriveUploadJob) {
            self.job = job
        }
    }

    private static let maxPreparing = 2
    private static var entries: [Entry] = []
    private static var batchUploaded = 0
    private static var batchDuplicates = 0
    private static var batchFailed = 0
    private static var lastPublished: DkxDriveUploadProgress?

    public static func enqueue(_ job: DkxGoogleDriveUploadJob) {
        Queue.mainQueue().async {
            DkxDriveUploadStatus.setCancelHandler({
                Queue.mainQueue().async {
                    self.cancelAll()
                }
            })
            self.entries.append(Entry(job: job))
            self.pump()
            self.publish()
        }
    }

    private static func contains(_ entry: Entry) -> Bool {
        return self.entries.contains(where: { $0 === entry })
    }

    private static func pump() {
        var slots = self.maxPreparing - self.entries.filter({ $0.preparing }).count
        for entry in self.entries where slots > 0 && !entry.preparing && !entry.uploading {
            slots -= 1
            self.prepare(entry)
        }
    }

    private static func prepare(_ entry: Entry) {
        entry.preparing = true
        let job = entry.job
        entry.prepareDisposable.set((job.prepare
        |> take(1)
        |> deliverOnMainQueue).start(next: { path in
            guard self.contains(entry) else {
                return
            }
            DkxGoogleDriveUpload.startSession(job: job, filePath: path, completion: { outcome in
                Queue.mainQueue().async {
                    guard self.contains(entry) else {
                        // Отменили, пока готовили. Временную копию убираем сразу
                        if case let .ready(_, fileUrl) = outcome {
                            let _ = try? FileManager.default.removeItem(at: fileUrl)
                        }
                        return
                    }
                    entry.preparing = false
                    switch outcome {
                    case let .finished(result):
                        self.finish(entry, result: result)
                    case let .ready(sessionUrl, fileUrl):
                        entry.uploading = true
                        entry.task = DkxDriveBackgroundSession.shared.upload(sessionUrl: sessionUrl, fileUrl: fileUrl, mimeType: job.mimeType, progress: { fraction in
                            guard self.contains(entry) else {
                                return
                            }
                            entry.fraction = fraction
                            self.publish()
                        }, completion: { result in
                            guard self.contains(entry) else {
                                return
                            }
                            if case .uploaded = result {
                                DkxLog.write("drive", "загружено, \(job.chatId)_\(job.messageId)")
                            }
                            self.finish(entry, result: result)
                        })
                        self.pump()
                        self.publish()
                    }
                }
            })
        }))
    }

    private static func finish(_ entry: Entry, result: DkxGoogleDriveUploadResult) {
        self.entries.removeAll(where: { $0 === entry })
        switch result {
        case .uploaded:
            self.batchUploaded += 1
            DkxDriveUploadedIndex.add(chatId: entry.job.chatId, messageId: entry.job.messageId)
        case .duplicate:
            self.batchDuplicates += 1
            DkxDriveUploadedIndex.add(chatId: entry.job.chatId, messageId: entry.job.messageId)
        case .failed, .notConnected:
            self.batchFailed += 1
        case .cancelled:
            break
        }
        entry.job.completion(result, self.takeSummaryIfDone())
        self.pump()
        self.publish()
    }

    private static func takeSummaryIfDone() -> DkxGoogleDriveBatchSummary? {
        guard self.entries.isEmpty else {
            return nil
        }
        let summary = DkxGoogleDriveBatchSummary(uploaded: self.batchUploaded, duplicates: self.batchDuplicates, failed: self.batchFailed)
        self.batchUploaded = 0
        self.batchDuplicates = 0
        self.batchFailed = 0
        return summary
    }

    // Общий ход по всем файлам. Готовящиеся файлы считаются с нулём.
    private static func publish() {
        guard let first = self.entries.first else {
            self.lastPublished = nil
            DkxDriveUploadStatus.update(nil)
            return
        }
        let count = self.entries.count
        let isUploading = self.entries.contains(where: { $0.uploading })
        let total = self.entries.reduce(0.0, { $0 + $1.fraction })
        let fraction = (total / Double(count) * 100.0).rounded() / 100.0
        let label = count == 1 ? first.job.fileName : "\(first.job.fileName) и ещё \(count - 1)"
        let progress = DkxDriveUploadProgress(id: first.job.id, fileName: label, phase: isUploading ? .uploading : .preparing, fraction: fraction, waiting: count - 1)
        if progress != self.lastPublished {
            self.lastPublished = progress
            DkxDriveUploadStatus.update(progress)
        }
    }

    // Крестик на полосе отменяет все загрузки разом
    private static func cancelAll() {
        let current = self.entries
        guard !current.isEmpty else {
            return
        }
        self.entries.removeAll()
        for entry in current {
            entry.prepareDisposable.set(nil)
            entry.task?.cancel()
        }
        DkxLog.write("drive", "отменено загрузок \(current.count)")
        let summary = self.takeSummaryIfDone()
        for (index, entry) in current.enumerated() {
            entry.job.completion(.cancelled, index == current.count - 1 ? summary : nil)
        }
        self.publish()
    }
}

// Фоновая сессия для самих байтов. Временную копию файла стираем по
// завершении, путь к ней лежит в описании задачи, чтобы найти его и после
// перезапуска приложения системой.
final class DkxDriveBackgroundSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let identifier = "uz.dkx.app.gdrive"
    static let shared = DkxDriveBackgroundSession()

    private var progressHandlers: [Int: (Double) -> Void] = [:]
    private var completionHandlers: [Int: (DkxGoogleDriveUploadResult) -> Void] = [:]
    var backgroundEventsCompletion: (() -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: DkxDriveBackgroundSession.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }()

    // Будит сессию, когда система перезапустила приложение ради её событий
    func activate() {
        let _ = self.session
    }

    func upload(sessionUrl: URL, fileUrl: URL, mimeType: String, progress: @escaping (Double) -> Void, completion: @escaping (DkxGoogleDriveUploadResult) -> Void) -> URLSessionTask {
        var request = URLRequest(url: sessionUrl)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let task = self.session.uploadTask(with: request, fromFile: fileUrl)
        task.taskDescription = fileUrl.path
        self.progressHandlers[task.taskIdentifier] = progress
        self.completionHandlers[task.taskIdentifier] = completion
        task.resume()
        return task
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else {
            return
        }
        self.progressHandlers[task.taskIdentifier]?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.progressHandlers.removeValue(forKey: task.taskIdentifier)
        let completion = self.completionHandlers.removeValue(forKey: task.taskIdentifier)
        if let path = task.taskDescription, !path.isEmpty {
            let _ = try? FileManager.default.removeItem(atPath: path)
        }

        let result: DkxGoogleDriveUploadResult
        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                result = .cancelled
            } else {
                result = .failed(error.localizedDescription)
            }
        } else {
            let code = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 || code == 201 {
                result = .uploaded
            } else {
                result = .failed("Google ответил кодом \(code)")
            }
        }
        if let completion = completion {
            completion(result)
        } else if case .uploaded = result {
            // Приложение перезапускалось, и ждать ответа уже некому
            DkxLog.write("drive", "фоновая загрузка закончилась после перезапуска")
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = self.backgroundEventsCompletion
        self.backgroundEventsCompletion = nil
        completion?()
    }
}

public enum DkxGoogleDriveUpload {
    // Кэш идентификаторов папок на сессию, чтобы не искать каждый раз
    private static var folderCache: [String: String] = [:]
    // Кто ждёт папку, которую сейчас ищут или создают. Без этого два файла
    // из одного чата, загружаемые разом, завели бы две одинаковые папки.
    private static var folderWaiters: [String: [(String?) -> Void]] = [:]
    private static let cacheLock = NSLock()

    public static var backgroundSessionIdentifier: String {
        return DkxDriveBackgroundSession.identifier
    }

    // Зовётся из AppDelegate, когда система разбудила приложение ради фоновой загрузки
    public static func handleBackgroundEvents(completion: @escaping () -> Void) {
        DkxDriveBackgroundSession.shared.backgroundEventsCompletion = completion
        DkxDriveBackgroundSession.shared.activate()
    }

    enum SessionOutcome {
        case finished(DkxGoogleDriveUploadResult)
        case ready(URL, URL)
    }

    private static func cachedFolder(_ key: String) -> String? {
        cacheLock.lock()
        defer {
            cacheLock.unlock()
        }
        return folderCache[key]
    }

    // Проверка дубля, папки, сессия загрузки и временная копия файла. Всё,
    // кроме самих байтов.
    static func startSession(job: DkxGoogleDriveUploadJob, filePath: String, completion: @escaping (SessionOutcome) -> Void) {
        guard DkxGoogleDrive.isConnected else {
            completion(.finished(.notConnected))
            return
        }
        DkxGoogleDrive.accessToken(completion: { token in
            guard let token = token else {
                completion(.finished(DkxGoogleDrive.isConnected ? .failed("Нужно войти в Google заново") : .notConnected))
                return
            }
            let dedupKey = "\(job.chatId)_\(job.messageId)"
            let checkDuplicate: (@escaping (Bool) -> Void) -> Void = { done in
                if job.force {
                    done(false)
                } else {
                    findDuplicate(token: token, key: dedupKey, completion: done)
                }
            }
            checkDuplicate({ exists in
                if exists {
                    DkxLog.write("drive", "уже загружено, \(dedupKey)")
                    completion(.finished(.duplicate))
                    return
                }
                ensureFolder(token: token, chatId: job.chatId, chatTitle: job.chatTitle, completion: { folderId in
                    createUploadSession(token: token, fileName: job.fileName, mimeType: job.mimeType, parentId: folderId, dedupKey: dedupKey, completion: { sessionUrl in
                        guard let sessionUrl = sessionUrl else {
                            completion(.finished(.failed("Google не принял загрузку")))
                            return
                        }
                        guard let copyUrl = makeTemporaryCopy(filePath: filePath, fileName: job.fileName) else {
                            completion(.finished(.failed("не удалось подготовить файл")))
                            return
                        }
                        completion(.ready(sessionUrl, copyUrl))
                    })
                })
            })
        })
    }

    // Фоновая сессия читает файл сама и может делать это после того, как
    // Telegram почистит кэш. Поэтому своя копия, а лучше жёсткая ссылка, она
    // не занимает места.
    private static func makeTemporaryCopy(filePath: String, fileName: String) -> URL? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dkx-drive", isDirectory: true)
        let _ = try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let ext = (fileName as NSString).pathExtension
        let target = directory.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : "." + ext))
        let source = URL(fileURLWithPath: filePath)
        if (try? FileManager.default.linkItem(at: source, to: target)) != nil {
            return target
        }
        if (try? FileManager.default.copyItem(at: source, to: target)) != nil {
            return target
        }
        return nil
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
        cacheLock.lock()
        if var waiters = folderWaiters[cacheKey] {
            waiters.append(completion)
            folderWaiters[cacheKey] = waiters
            cacheLock.unlock()
            return
        }
        folderWaiters[cacheKey] = [completion]
        cacheLock.unlock()
        let resolve: (String?) -> Void = { id in
            cacheLock.lock()
            if let id = id {
                folderCache[cacheKey] = id
            }
            let waiters = folderWaiters.removeValue(forKey: cacheKey) ?? []
            cacheLock.unlock()
            for waiter in waiters {
                waiter(id)
            }
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
            resolve(nil)
            return
        }
        URLSession.shared.dataTask(with: authorized(url, token: token), completionHandler: { data, _, _ in
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let files = json["files"] as? [[String: Any]], let id = files.first?["id"] as? String {
                resolve(id)
                return
            }
            createFolder(token: token, name: name, parentId: parentId, propKey: propKey, propValue: propValue, completion: { id in
                resolve(id)
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

    // Заводит resumable-сессию и отдаёт её адрес, куда потом шлются байты
    private static func createUploadSession(token: String, fileName: String, mimeType: String, parentId: String?, dedupKey: String, completion: @escaping (URL?) -> Void) {
        var metadata: [String: Any] = [
            "name": fileName,
            "appProperties": ["dkxKey": dedupKey]
        ]
        if let parentId = parentId {
            metadata["parents"] = [parentId]
        }
        var request = authorized(URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!, token: token, method: "POST")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: metadata)
        URLSession.shared.dataTask(with: request, completionHandler: { _, response, _ in
            guard let httpResponse = response as? HTTPURLResponse, let location = httpResponse.value(forHTTPHeaderField: "Location"), let sessionUrl = URL(string: location) else {
                completion(nil)
                return
            }
            completion(sessionUrl)
        }).resume()
    }
}
