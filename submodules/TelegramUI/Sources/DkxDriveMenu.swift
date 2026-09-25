import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import OverlayStatusController
import UndoUI
import SettingsUI
import TelegramUIPreferences

// MARK: DKX связка меню сообщения с выгрузкой в Google Drive. Движок входа и
// загрузки живёт в SettingsUI, тут только достаём файл сообщения и показываем
// ход и результат.

func dkxDriveMenuApplicable(message: Message) -> Bool {
    guard DkxRuntime.current.driveEnabled, DkxGoogleDrive.isConfigured, DkxGoogleDrive.isConnected else {
        return false
    }
    if message.containsSecretMedia {
        return false
    }
    return dkxDrivePickMedia(message: message) != nil
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

func dkxUploadMessageToDrive(context: AccountContext, message: Message, present: @escaping (ViewController, Any?) -> Void) {
    guard let media = dkxDrivePickMedia(message: message) else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let disposable = MetaDisposable()

    var dismissStatus: (() -> Void)?
    let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
        disposable.dispose()
        dismissStatus?()
    }))
    dismissStatus = { [weak statusController] in
        statusController?.dismiss()
    }
    present(statusController, nil)

    let account = context.account
    let userLocation: MediaResourceUserLocation = .peer(message.id.peerId)

    let fetch: Signal<Never, NoError>
    if let fileReference = media.fileReference {
        fetch = freeMediaFileInteractiveFetched(account: account, userLocation: userLocation, fileReference: fileReference)
        |> ignoreValues
        |> `catch` { _ in return .complete() }
    } else {
        fetch = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: userLocation, userContentType: .image, reference: media.imageReference!.resourceReference(media.resource))
        |> ignoreValues
        |> `catch` { _ in return .complete() }
    }

    let path = account.postbox.mediaBox.resourceData(media.resource)
    |> filter { $0.complete }
    |> take(1)
    |> map { $0.path }

    let chatTitle = (message.peers[message.id.peerId].flatMap { EnginePeer($0).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) }) ?? ""

    let signal = fetch
    |> then(path)
    |> mapToSignal { filePath -> Signal<DkxGoogleDriveUploadResult, NoError> in
        return DkxGoogleDriveUpload.upload(filePath: filePath, fileName: media.fileName, mimeType: media.mimeType, chatId: message.id.peerId.toInt64(), chatTitle: chatTitle, messageId: message.id.id)
    }
    |> deliverOnMainQueue

    disposable.set(signal.start(next: { result in
        dismissStatus?()
        let text: String
        switch result {
        case .uploaded:
            text = "Загружено в Google Drive"
        case .duplicate:
            text = "Уже было в Google Drive"
        case .notConnected:
            text = "Сначала войдите в Google в настройках Dkx"
        case let .failed(reason):
            text = "Не удалось: \(reason)"
        }
        present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
    }))
}
