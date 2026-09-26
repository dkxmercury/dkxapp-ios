import Foundation
import AVFoundation
import Speech
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

// Расшифровка голосовых и кружков на самом телефоне, когда нет Premium. Язык
// задаётся в Dkx. Если язык скачан на телефон, iOS распознаёт без сети, иначе
// звук уходит на серверы Apple, не Telegram.

public let dkxSpeechLocaleCandidates: [(id: String, title: String)] = [
    ("ru-RU", "Русский"),
    ("en-US", "Английский"),
    ("uz-UZ", "Узбекский")
]

// Узбекского в списке iOS может не быть, такие языки не предлагаем
public func dkxSupportedSpeechLocales() -> [(id: String, title: String)] {
    let supported = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
    return dkxSpeechLocaleCandidates.filter { supported.contains($0.id) }
}

public func dkxSpeechAccessDenied() -> Bool {
    let status = SFSpeechRecognizer.authorizationStatus()
    return status == .denied || status == .restricted
}

// Причина последней неудачи, её показывает сообщение в чате. Только главная очередь
private var dkxLastFailure: String?

public func dkxSetTranscriptionFailure(_ reason: String?) {
    Queue.mainQueue().async {
        dkxLastFailure = reason
    }
}

public func dkxTranscriptionFailureText() -> String {
    if dkxSpeechAccessDenied() {
        return DkxStrings.tr("Нет разрешения на распознавание речи. Включите его в настройках iOS, раздел Dkx.")
    }
    if let reason = dkxLastFailure {
        return DkxStrings.tr("Не удалось расшифровать, {}.", reason)
    }
    return DkxStrings.tr("Не удалось расшифровать. Проверьте язык в Dkx, раздел «Расшифровка голосовых».")
}

private let dkxTimeoutCode = -1001
private let dkxEmptyCode = -1002

private func dkxDescribe(_ error: NSError?) -> String {
    guard let error else {
        return DkxStrings.tr("распознавание вернуло пустой текст")
    }
    if error.domain == "dkx" && error.code == dkxTimeoutCode {
        return DkxStrings.tr("iOS не ответила за 90 секунд")
    }
    if error.domain == "dkx" && error.code == dkxEmptyCode {
        return DkxStrings.tr("распознавание вернуло пустой текст")
    }
    switch error.code {
    case 201, 1700:
        return DkxStrings.tr("на телефоне выключена диктовка. Включите её в настройках iOS, Основные, Клавиатура, «Включить диктовку», или включите Siri")
    case 1110:
        return DkxStrings.tr("в записи не слышно речи")
    case 1101, 1107:
        return DkxStrings.tr("служба распознавания iOS сейчас недоступна, попробуйте позже")
    default:
        return DkxStrings.tr("ошибка распознавания iOS {} {}", error.domain, error.code)
    }
}

private func dkxRecognize(recognizer: SFSpeechRecognizer, url: URL, onDevice: Bool, completion: @escaping (String?, NSError?) -> Void) -> SFSpeechRecognitionTask {
    let request = SFSpeechURLRecognitionRequest(url: url)
    if #available(iOS 16.0, *) {
        request.addsPunctuation = true
    }
    request.requiresOnDeviceRecognition = onDevice
    request.shouldReportPartialResults = false
    var finished = false
    let task = recognizer.recognitionTask(with: request, resultHandler: { result, error in
        if finished {
            return
        }
        if let result {
            if result.isFinal {
                finished = true
                completion(result.bestTranscription.formattedString, nil)
            }
        } else {
            finished = true
            completion(nil, error.map { $0 as NSError })
        }
    })
    // Задача иногда не отвечает вовсе, тогда отменяем сами
    Queue.mainQueue().after(90.0, {
        if finished {
            return
        }
        finished = true
        task.cancel()
        completion(nil, NSError(domain: "dkx", code: dkxTimeoutCode, userInfo: nil))
    })
    return task
}

// Пустой текст тоже неудача, иначе запасной заход через серверы Apple не случится
private func dkxRecognizeSignal(recognizer: SFSpeechRecognizer, url: URL, onDevice: Bool) -> Signal<String, NSError> {
    return Signal<String, NSError> { subscriber in
        let task = dkxRecognize(recognizer: recognizer, url: url, onDevice: onDevice, completion: { text, error in
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                subscriber.putNext(trimmed)
                subscriber.putCompletion()
            } else {
                subscriber.putError(error ?? NSError(domain: "dkx", code: dkxEmptyCode, userInfo: nil))
            }
        })
        return ActionDisposable {
            // Распознаватель держим до конца задачи, иначе она обрывается
            let _ = recognizer
            task.cancel()
        }
    }
    |> runOn(Queue.mainQueue())
}

private func dkxRecognizePiece(recognizer: SFSpeechRecognizer, url: URL) -> Signal<String, NSError> {
    let server = dkxRecognizeSignal(recognizer: recognizer, url: url, onDevice: false)
    guard recognizer.supportsOnDeviceRecognition else {
        return server
    }
    return dkxRecognizeSignal(recognizer: recognizer, url: url, onDevice: true)
    |> `catch` { error -> Signal<String, NSError> in
        DkxLog.write("расшифровка", "на телефоне не вышло, \(error.domain) \(error.code), пробую через Apple")
        return server
    }
}

private func dkxAudioDuration(_ url: URL) -> Double {
    guard let file = try? AVAudioFile(forReading: url) else {
        return 0.0
    }
    let rate = file.fileFormat.sampleRate
    return rate > 0.0 ? Double(file.length) / rate : 0.0
}

private func dkxExportPiece(url: URL, start: Double, length: Double) -> Signal<URL?, NoError> {
    return Signal { subscriber in
        let output = URL(fileURLWithPath: NSTemporaryDirectory() + "dkx-\(UInt64.random(in: 0 ... UInt64.max)).m4a")
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetAppleM4A) else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        session.outputURL = output
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: length, preferredTimescale: 600))
        session.exportAsynchronously {
            subscriber.putNext(session.status == .completed ? output : nil)
            subscriber.putCompletion()
        }
        return ActionDisposable {
            session.cancelExport()
        }
    }
}

// Серверы Apple распознают около минуты за раз, длинную запись режем на куски по 50 секунд
private func dkxSplitAudio(url: URL, duration: Double) -> Signal<[URL], NoError> {
    let step = 50.0
    var signal: Signal<[URL], NoError> = .single([])
    var start = 0.0
    while start < duration {
        let pieceStart = start
        let length = min(step, duration - start)
        signal = signal
        |> mapToSignal { urls -> Signal<[URL], NoError> in
            return dkxExportPiece(url: url, start: pieceStart, length: length)
            |> map { piece -> [URL] in
                guard let piece else {
                    return urls
                }
                return urls + [piece]
            }
        }
        start += step
    }
    return signal
    |> map { urls -> [URL] in
        return urls.isEmpty ? [url] : urls
    }
}

private func dkxRecognizer(locale: String) -> Signal<SFSpeechRecognizer?, NoError> {
    return Signal { subscriber in
        SFSpeechRecognizer.requestAuthorization { status in
            Queue.mainQueue().async {
                guard status == .authorized else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
                    dkxLastFailure = DkxStrings.tr("язык {} не поддерживается распознаванием iOS", locale)
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                subscriber.putNext(recognizer)
                subscriber.putCompletion()
            }
        }
        return EmptyDisposable
    }
}

public func dkxTranscribeAudio(path: String, locale: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    return dkxRecognizer(locale: locale)
    |> mapToSignal { recognizer -> Signal<LocallyTranscribedAudio?, NoError> in
        guard let recognizer else {
            return .single(nil)
        }
        // Копия во временной папке, как у штатной расшифровки Telegram
        let copyPath = NSTemporaryDirectory() + "dkx-\(UInt64.random(in: 0 ... UInt64.max)).m4a"
        let _ = try? FileManager.default.copyItem(atPath: path, toPath: copyPath)
        let source = URL(fileURLWithPath: FileManager.default.fileExists(atPath: copyPath) ? copyPath : path)
        let duration = dkxAudioDuration(source)
        let pieces: Signal<[URL], NoError> = duration > 55.0 ? dkxSplitAudio(url: source, duration: duration) : .single([source])
        return pieces
        |> mapToSignal { urls -> Signal<LocallyTranscribedAudio?, NoError> in
            var lastError: NSError?
            var texts: Signal<[String], NoError> = .single([])
            for pieceUrl in urls {
                texts = texts
                |> mapToSignal { collected -> Signal<[String], NoError> in
                    return dkxRecognizePiece(recognizer: recognizer, url: pieceUrl)
                    |> map { text -> [String] in
                        return collected + [text]
                    }
                    |> `catch` { error -> Signal<[String], NoError> in
                        // Пустой кусок, например тишина в конце, остальное не портит
                        lastError = error
                        return .single(collected)
                    }
                }
            }
            return texts
            |> deliverOnMainQueue
            |> map { collected -> LocallyTranscribedAudio? in
                for pieceUrl in Set(urls + [source]) where pieceUrl.path != path {
                    let _ = try? FileManager.default.removeItem(at: pieceUrl)
                }
                let joined = collected.joined(separator: " ")
                if joined.isEmpty {
                    let reason = dkxDescribe(lastError)
                    dkxLastFailure = reason
                    DkxLog.write("расшифровка", "не вышло, \(lastError?.domain ?? "") \(lastError?.code ?? 0), длина \(Int(duration)) с")
                    return nil
                }
                return LocallyTranscribedAudio(text: joined, isFinal: true)
            }
        }
    }
}

// Кружок это видео, распознавателю нужен отдельный звук. Файлы кэша Telegram
// без расширения, поэтому сначала ссылка с .mp4, по ней AVFoundation узнаёт тип.
public func dkxExtractAudio(videoPath: String) -> Signal<String?, NoError> {
    return Signal { subscriber in
        let base = NSTemporaryDirectory() + "dkx-\(UInt64.random(in: 0 ... UInt64.max))"
        let videoLink = base + ".mp4"
        let audioPath = base + ".m4a"
        do {
            try FileManager.default.linkItem(atPath: videoPath, toPath: videoLink)
        } catch {
            let _ = try? FileManager.default.copyItem(atPath: videoPath, toPath: videoLink)
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: videoLink))
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            let _ = try? FileManager.default.removeItem(atPath: videoLink)
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        session.outputURL = URL(fileURLWithPath: audioPath)
        session.outputFileType = .m4a
        session.exportAsynchronously {
            let _ = try? FileManager.default.removeItem(atPath: videoLink)
            if session.status == .completed {
                subscriber.putNext(audioPath)
            } else {
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
        }
        return ActionDisposable {
            session.cancelExport()
        }
    }
}
