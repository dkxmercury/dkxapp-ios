import Foundation
import Darwin

// Журнал форка. Короткие строки о том, что сделали наши правки и где
// что-то пошло не так, чтобы владелец мог скопировать журнал из настроек и
// переслать разработчику.
//
// Файл один на все процессы: приложение и расширение уведомлений пишут в
// общую папку группы. Запись идёт через O_APPEND одним вызовом write, такая
// дозапись не перемешивает строки разных процессов.
//
// Правило для вызывающих: только идентификаторы, счётчики и причины. Текст
// сообщений, номера телефонов и имена в журнал не пишутся, потому что он
// уходит наружу целиком.
public final class DkxLog {
    private static let queue = DispatchQueue(label: "dkx.log")
    // Больше этого файл обрезается до последней половины
    private static let maxBytes: Int = 512 * 1024

    public static var fileURL: URL? {
        guard let path = DkxLog.path else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static var path: String? {
        let rootPath = Logger.shared.rootPath
        if rootPath.isEmpty {
            return nil
        }
        return rootPath + "/logs/dkx.log"
    }

    // Короткое имя процесса: Telegram для приложения, имя расширения для
    // остальных
    private static let processName: String = {
        return Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
    }()

    public static func write(_ tag: String, _ message: String) {
        let date = Date()
        DkxLog.queue.async {
            guard let path = DkxLog.path else {
                return
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "dd.MM HH:mm:ss.SSS"
            let line = "\(formatter.string(from: date)) [\(DkxLog.processName)] \(tag): \(message)\n"
            DkxLog.append(line, path: path)
        }
    }

    public static func contents() -> String {
        return DkxLog.queue.sync { () -> String in
            guard let path = DkxLog.path, let data = FileManager.default.contents(atPath: path) else {
                return ""
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    public static func clear() {
        DkxLog.queue.sync { () -> Void in
            guard let path = DkxLog.path else {
                return
            }
            let _ = try? FileManager.default.removeItem(atPath: path)
        }
    }

    private static func append(_ line: String, path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        let _ = try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)

        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, S_IRUSR | S_IWUSR)
        if fd < 0 {
            return
        }
        let bytes = Array(line.utf8)
        let _ = bytes.withUnsafeBytes { buffer in
            Darwin.write(fd, buffer.baseAddress, buffer.count)
        }
        var info = stat()
        let size = fstat(fd, &info) == 0 ? Int(info.st_size) : 0
        close(fd)

        if size > DkxLog.maxBytes {
            DkxLog.trim(path: path)
        }
    }

    // Оставляет вторую половину файла, начиная с целой строки
    private static func trim(path: String) {
        guard let data = FileManager.default.contents(atPath: path) else {
            return
        }
        var tail = data.suffix(from: data.count / 2)
        if let newline = tail.firstIndex(of: 0x0A) {
            tail = tail.suffix(from: tail.index(after: newline))
        }
        let _ = try? Data(tail).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
