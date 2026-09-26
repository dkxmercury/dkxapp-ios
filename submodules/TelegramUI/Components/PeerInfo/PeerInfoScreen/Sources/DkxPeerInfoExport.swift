import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import AccountContext
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import PresentationDataUtils
import OverlayStatusController
import UndoUI
import SettingsUI

// MARK: DKX. Выгрузка чата в текстовый файл. Пункт в профиле собеседника,
// группы или канала. Догружает с сервера всю историю, собирает текст с
// датами и авторами, отмечает удалённые и изменённые сообщения, отдаёт
// файл в системное меню «Поделиться».

func dkxExportChatItem(id: AnyHashable, peerId: EnginePeer.Id, context: AccountContext, interaction: PeerInfoInteraction) -> PeerInfoScreenItem? {
    guard DkxRuntime.current.chatExport else {
        return nil
    }
    return PeerInfoScreenActionItem(id: id, text: "Выгрузить чат в файл", action: { [weak interaction] in
        guard let controller = interaction?.getController() else {
            return
        }
        dkxRunChatExport(context: context, peerId: peerId, controller: controller)
    })
}

// MARK: DKX все медиа чата за период на Google Drive, экран в SettingsUI
func dkxChatMediaDriveItem(id: AnyHashable, peerId: EnginePeer.Id, context: AccountContext, interaction: PeerInfoInteraction) -> PeerInfoScreenItem? {
    guard DkxRuntime.current.driveEnabled else {
        return nil
    }
    return PeerInfoScreenActionItem(id: id, text: "Медиа в Google Drive", action: { [weak interaction] in
        guard let controller = interaction?.getController() else {
            return
        }
        controller.push(dkxChatMediaDriveController(context: context, peerId: peerId))
    })
}

private func dkxRunChatExport(context: AccountContext, peerId: EnginePeer.Id, controller: ViewController) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let disposable = MetaDisposable()

    var dismissStatus: (() -> Void)?
    let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
        disposable.dispose()
        dismissStatus?()
        DkxLog.write("выгрузка", "отменена")
    }))
    dismissStatus = { [weak statusController] in
        statusController?.dismiss()
    }
    controller.present(statusController, in: .window(.root))

    let account = context.account
    DkxLog.write("выгрузка", "старт, чат \(peerId)")

    let signal = DkxChatExport.loadFullHistory(account: account, peerId: peerId)
    |> reduceLeft(value: 0, f: { $0 + $1 })
    |> mapToSignal { loaded -> Signal<(Int, [Message], EnginePeer?), NoError> in
        return combineLatest(
            DkxChatExport.collectMessages(account: account, peerId: peerId),
            context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        )
        |> map { messages, peer -> (Int, [Message], EnginePeer?) in
            return (loaded, messages, peer)
        }
    }
    |> deliverOnMainQueue

    disposable.set(signal.start(next: { loaded, messages, peer in
        dismissStatus?()
        DkxLog.write("выгрузка", "с сервера догружено \(loaded), всего в файле \(messages.count)")

        let title = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "чат"
        let text = dkxFormatChatExport(title: title, messages: messages, accountPeerId: account.peerId, presentationData: presentationData)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let safeTitle = String(title.map { ch -> Character in
            return "/\\:?*\"<>|".contains(ch) ? "_" : ch
        }.prefix(60))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Чат \(safeTitle) \(dateFormatter.string(from: Date())).txt")
        do {
            let _ = try? FileManager.default.removeItem(at: url)
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            DkxLog.write("выгрузка", "не удалось записать файл, \(error.localizedDescription)")
            controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Не удалось записать файл", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
            return
        }
        let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        context.sharedContext.applicationBindings.presentNativeController(activityController)
    }))
}

private func dkxFormatChatExport(title: String, messages: [Message], accountPeerId: PeerId, presentationData: PresentationData) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ru_RU")
    dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
    let shortFormatter = DateFormatter()
    shortFormatter.locale = Locale(identifier: "ru_RU")
    shortFormatter.dateFormat = "dd.MM HH:mm"

    var lines: [String] = []
    lines.append("Чат \(title)")
    lines.append("Выгружено \(dateFormatter.string(from: Date()))")
    lines.append("Сообщений \(messages.count)")
    if messages.count >= DkxChatExport.maxBatches * 100 {
        lines.append("Выгрузка упёрлась в предел, самые старые сообщения могли не попасть.")
    }
    lines.append("")

    for message in messages {
        let date = dateFormatter.string(from: Date(timeIntervalSince1970: Double(message.timestamp)))
        let author: String
        if let peer = message.author {
            if peer.id == accountPeerId {
                author = "Я"
            } else {
                author = EnginePeer(peer).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            }
        } else {
            author = title
        }

        var parts: [String] = []
        if let forwardInfo = message.forwardInfo {
            let source = forwardInfo.author.flatMap { EnginePeer($0).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) } ?? forwardInfo.authorSignature ?? "неизвестно"
            parts.append("(переслано от \(source))")
        }
        for media in message.media {
            if let label = dkxExportMediaLabel(media) {
                parts.append(label)
            }
        }
        if !message.text.isEmpty {
            parts.append(message.text)
        }
        if parts.isEmpty {
            parts.append("[пусто]")
        }

        var line = "[\(date)] \(author): " + parts.joined(separator: " ")
        for attribute in message.attributes {
            if let deleted = attribute as? DkxDeletedMessageAttribute {
                line += "\n    (удалено \(shortFormatter.string(from: Date(timeIntervalSince1970: Double(deleted.deletionDate)))))"
            } else if let history = attribute as? DkxEditHistoryAttribute, !history.texts.isEmpty {
                line += "\n    (изменено, прежние версии"
                for i in 0 ..< min(history.texts.count, history.dates.count) {
                    let when = shortFormatter.string(from: Date(timeIntervalSince1970: Double(history.dates[i])))
                    line += "\n     \(when): \(history.texts[i])"
                }
                line += ")"
            }
        }
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}

private func dkxExportMediaLabel(_ media: Media) -> String? {
    if media is TelegramMediaImage {
        return "[фото]"
    } else if let file = media as? TelegramMediaFile {
        if file.isVoice {
            return "[голосовое]"
        } else if file.isInstantVideo {
            return "[кружок]"
        } else if file.isVideo {
            return "[видео]"
        } else if file.isSticker || file.isAnimatedSticker {
            return "[стикер]"
        } else if file.isMusic {
            return "[аудио]"
        }
        return "[файл \(file.fileName ?? "")]"
    } else if let map = media as? TelegramMediaMap {
        return "[геопозиция \(map.latitude), \(map.longitude)]"
    } else if let contact = media as? TelegramMediaContact {
        return "[контакт \(contact.firstName) \(contact.lastName) \(contact.phoneNumber)]"
    } else if media is TelegramMediaPoll {
        return "[опрос]"
    } else if media is TelegramMediaAction {
        return "[служебное]"
    } else if media is TelegramMediaWebpage {
        // Превью ссылки, сама ссылка уже есть в тексте
        return nil
    }
    return nil
}
