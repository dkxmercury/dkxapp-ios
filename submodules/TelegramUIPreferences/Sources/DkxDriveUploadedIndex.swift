import Foundation

// MARK: DKX какие файлы сообщений уже лежат на Google Drive. Нужен пометке
// «на диске» в строке статуса и пункту «Повторно загрузить». Ключ тот же, что
// у дедупа на диске, «чат_сообщение». Файл в Documents, по строке на ключ.
// Спрашивают при каждой вёрстке сообщения, поэтому набор держим в памяти.
public enum DkxDriveUploadedIndex {
    private static let lock = NSLock()
    private static var keys: Set<String>?

    private static var fileURL: URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("dkx-drive-uploaded.txt")
    }

    private static func key(chatId: Int64, messageId: Int32) -> String {
        return "\(chatId)_\(messageId)"
    }

    private static func loadedKeys() -> Set<String> {
        if let keys = self.keys {
            return keys
        }
        var result = Set<String>()
        if let url = self.fileURL, let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") where !line.isEmpty {
                result.insert(String(line))
            }
        }
        self.keys = result
        return result
    }

    public static func contains(chatId: Int64, messageId: Int32) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return loadedKeys().contains(key(chatId: chatId, messageId: messageId))
    }

    public static func add(chatId: Int64, messageId: Int32) {
        lock.lock()
        defer {
            lock.unlock()
        }
        let value = key(chatId: chatId, messageId: messageId)
        var current = loadedKeys()
        guard !current.contains(value) else {
            return
        }
        current.insert(value)
        self.keys = current
        guard let url = self.fileURL, let data = (value + "\n").data(using: .utf8) else {
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            let _ = try? data.write(to: url, options: .atomic)
        }
    }
}
