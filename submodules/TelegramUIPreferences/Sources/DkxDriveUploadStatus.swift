import Foundation
import SwiftSignalKit

// Ход выгрузки в Google Drive для полосы под шапкой, там же, где плеер
// музыки. Загрузчик живёт в SettingsUI, полосы рисуют список чатов и чат, а
// этот модуль видят все трое.
public struct DkxDriveUploadProgress: Equatable {
    public enum Phase: Equatable {
        // Файл ещё докачивается из Telegram
        case preparing
        case uploading
    }

    public let id: Int64
    public let fileName: String
    public let phase: Phase
    // От 0 до 1, шаг в один процент, чтобы не перерисовывать полосу на каждый пакет
    public let fraction: Double
    // Сколько файлов ждёт очереди после текущего
    public let waiting: Int

    public init(id: Int64, fileName: String, phase: Phase, fraction: Double, waiting: Int) {
        self.id = id
        self.fileName = fileName
        self.phase = phase
        self.fraction = fraction
        self.waiting = waiting
    }
}

public enum DkxDriveUploadStatus {
    private static let value = ValuePromise<DkxDriveUploadProgress?>(nil, ignoreRepeated: true)
    private static let lock = NSLock()
    private static var cancelHandler: (() -> Void)?

    public static var signal: Signal<DkxDriveUploadProgress?, NoError> {
        return self.value.get()
    }

    public static func update(_ progress: DkxDriveUploadProgress?) {
        self.value.set(progress)
    }

    public static func setCancelHandler(_ f: (() -> Void)?) {
        self.lock.lock()
        self.cancelHandler = f
        self.lock.unlock()
    }

    // Крестик на полосе отменяет текущий файл, очередь идёт дальше
    public static func cancelCurrent() {
        self.lock.lock()
        let f = self.cancelHandler
        self.lock.unlock()
        f?()
    }
}
