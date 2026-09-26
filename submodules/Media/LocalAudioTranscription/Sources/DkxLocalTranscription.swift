import Foundation
import AVFoundation
import Speech
import SwiftSignalKit

// MARK: DKX расшифровка голосовых и кружков на самом телефоне, когда нет
// Premium. Язык задаётся в Dkx. Если язык скачан на телефон, iOS распознаёт
// без сети, иначе звук уходит на серверы Apple, не Telegram.

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

private func dkxRecognize(recognizer: SFSpeechRecognizer, url: URL, onDevice: Bool, completion: @escaping (String?) -> Void) -> SFSpeechRecognitionTask {
    let request = SFSpeechURLRecognitionRequest(url: url)
    if #available(iOS 16.0, *) {
        request.addsPunctuation = true
    }
    request.taskHint = .dictation
    request.requiresOnDeviceRecognition = onDevice
    request.shouldReportPartialResults = false
    var finished = false
    return recognizer.recognitionTask(with: request, resultHandler: { result, _ in
        if finished {
            return
        }
        if let result {
            if result.isFinal {
                finished = true
                completion(result.bestTranscription.formattedString)
            }
        } else {
            finished = true
            completion(nil)
        }
    })
}

public func dkxTranscribeAudio(path: String, locale: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    return Signal { subscriber in
        let disposable = MetaDisposable()
        SFSpeechRecognizer.requestAuthorization { status in
            Queue.mainQueue().async {
                guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                let url = URL(fileURLWithPath: path)
                let finish: (String?) -> Void = { text in
                    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    subscriber.putNext(trimmed.isEmpty ? nil : LocallyTranscribedAudio(text: trimmed, isFinal: true))
                    subscriber.putCompletion()
                }
                // Без скачанной модели языка распознавание на телефоне падает с ошибкой, тогда второй заход через серверы Apple
                let onDevice = recognizer.supportsOnDeviceRecognition
                let first = dkxRecognize(recognizer: recognizer, url: url, onDevice: onDevice, completion: { text in
                    if text != nil || !onDevice {
                        finish(text)
                        return
                    }
                    Queue.mainQueue().async {
                        let second = dkxRecognize(recognizer: recognizer, url: url, onDevice: false, completion: finish)
                        disposable.set(ActionDisposable {
                            let _ = recognizer
                            second.cancel()
                        })
                    }
                })
                disposable.set(ActionDisposable {
                    // Распознаватель держим до конца задачи, иначе она обрывается
                    let _ = recognizer
                    first.cancel()
                })
            }
        }
        return disposable
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
