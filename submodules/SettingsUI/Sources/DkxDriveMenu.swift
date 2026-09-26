import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import UndoUI
import TelegramUIPreferences

// MARK: DKX связка меню сообщения и профиля чата с выгрузкой в Google Drive.
// Тут достаём файл сообщения и показываем ход и результат, движок входа и
// загрузки рядом, в DkxGoogleDrive и DkxGoogleDriveUpload.

// У альбома в меню приходят все его сообщения, пункт выгружает их разом
public func dkxDriveMenuApplicable(messages: [Message]) -> Bool {
    guard DkxRuntime.current.driveEnabled, DkxGoogleDrive.isConfigured, DkxGoogleDrive.isConnected else {
        return false
    }
    return messages.contains(where: { !$0.containsSecretMedia && dkxDrivePickMedia(message: $0) != nil })
}

private struct DkxDriveMedia {
    let resource: MediaResource
    let fileReference: FileMediaReference?
    let imageReference: ImageMediaReference?
    let fileName: String
    let mimeType: String
}

private func dkxDrivePickMedia(message: Message) -> DkxDriveMedia? {
    for media in message.media {
        if let file = media as? TelegramMediaFile {
            let name: String
            if let fileName = file.fileName, !fileName.isEmpty {
                name = fileName
            } else if file.isVoice {
                name = "voice_\(message.id.id).ogg"
            } else if file.isVideo {
                name = "video_\(message.id.id).mp4"
            } else {
                let ext = file.mimeType.components(separatedBy: "/").last ?? "bin"
                name = "file_\(message.id.id).\(ext)"
            }
            return DkxDriveMedia(resource: file.resource, fileReference: .message(message: MessageReference(message), media: file), imageReference: nil, fileName: name, mimeType: file.mimeType.isEmpty ? "application/octet-stream" : file.mimeType)
        } else if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
            return DkxDriveMedia(resource: representation.resource, fileReference: nil, imageReference: .message(message: MessageReference(message), media: image), fileName: "photo_\(message.id.id).jpg", mimeType: "image/jpeg")
        }
    }
    return nil
}

public func dkxUploadMessagesToDrive(context: AccountContext, messages: [Message], present: @escaping (ViewController, Any?) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let showToast: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
    }

    var count = 0
    for message in messages where !message.containsSecretMedia {
        guard let media = dkxDrivePickMedia(message: message) else {
            continue
        }
        count += 1
        let account = context.account
        let userLocation: MediaResourceUserLocation = .peer(message.id.peerId)

        let fetch: Signal<Never, NoError>
        if let fileReference = media.fileReference {
            fetch = freeMediaFileInteractiveFetched(account: account, userLocation: userLocation, fileReference: fileReference)
            |> ignoreValues
            |> `catch` { _ -> Signal<Never, NoError> in return .complete() }
        } else if let imageReference = media.imageReference {
            fetch = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: userLocation, userContentType: .image, reference: imageReference.resourceReference(media.resource))
            |> ignoreValues
            |> `catch` { _ -> Signal<Never, NoError> in return .complete() }
        } else {
            fetch = .complete()
        }

        let path = account.postbox.mediaBox.resourceData(media.resource)
        |> filter { $0.complete }
        |> take(1)
        |> map { $0.path }

        let prepare = fetch
        |> map { _ -> String in }
        |> then(path)

        let chatTitle = (message.peers[message.id.peerId].flatMap { EnginePeer($0).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) }) ?? ""
        let fileName = media.fileName

        // Загрузка идёт фоном, ход виден в полосе под шапкой. Экран не держим.
        // По отдельному файлу говорим только об ошибке, остальное одним итогом.
        DkxGoogleDriveUploadQueue.enqueue(DkxGoogleDriveUploadJob(fileName: fileName, mimeType: media.mimeType, chatId: message.id.peerId.toInt64(), chatTitle: chatTitle, messageId: message.id.id, prepare: prepare, completion: { result, summary in
            if case let .failed(reason) = result {
                showToast("Не удалось загрузить \(fileName). \(reason)")
            } else if case .notConnected = result, summary != nil {
                showToast("Сначала войдите в Google в настройках Dkx")
            }
            if let summary = summary, let text = dkxDriveSummaryText(summary) {
                showToast(text)
            }
        }))
    }
    if count == 1 {
        showToast("Файл в очереди на Google Drive, ход загрузки вверху экрана")
    } else if count > 1 {
        showToast("Файлов в очереди на Google Drive \(count), ход загрузки вверху экрана")
    }
}

private func dkxDriveSummaryText(_ summary: DkxGoogleDriveBatchSummary) -> String? {
    if summary.failed == 0 && summary.duplicates == 0 {
        if summary.uploaded == 1 {
            return "Загружено в Google Drive"
        } else if summary.uploaded > 1 {
            return "Загружено в Google Drive, файлов \(summary.uploaded)"
        }
        return nil
    }
    if summary.uploaded == 0 && summary.failed == 0 {
        return summary.duplicates == 1 ? "Уже было в Google Drive" : "Всё это уже было в Google Drive"
    }
    var parts: [String] = []
    if summary.uploaded > 0 {
        parts.append("загружено \(summary.uploaded)")
    }
    if summary.duplicates > 0 {
        parts.append("уже были \(summary.duplicates)")
    }
    if summary.failed > 0 {
        parts.append("не удалось \(summary.failed)")
    }
    return "Google Drive, " + parts.joined(separator: ", ")
}
