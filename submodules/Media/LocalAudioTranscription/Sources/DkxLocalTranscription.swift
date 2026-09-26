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

public func dkxTranscribeAudio(path: String, locale: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    return Signal { subscriber in
        let disposable = MetaDisposable()
        SFSpeechRecognizer.requestAuthorization { status in
            Queue.mainQueue().async {
                guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
                if #available(iOS 16.0, *) {
                    request.addsPunctuation = true
                }
                request.taskHint = .dictation
                request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
                request.shouldReportPartialResults = false

                let task = recognizer.recognitionTask(with: request, resultHandler: { result, _ in
                    guard let result = result else {
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                        return
                    }
                    guard result.isFinal else {
                        return
                    }
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    subscriber.putNext(text.isEmpty ? nil : LocallyTranscribedAudio(text: text, isFinal: true))
                    subscriber.putCompletion()
                })
                disposable.set(ActionDisposable {
                    // Распознаватель держим до конца задачи, иначе она обрывается
                    let _ = recognizer
                    task.cancel()
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
