import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import AccountContext

// MARK: DKX. Список «Без ответа». Личные чаты, где последним написал
// собеседник, самые долгие ожидания сверху. Для продаж видно, кому пора
// ответить. Отвечаешь, и человек сам пропадает из списка.
//
// Папки Telegram хранятся на сервере, условия «последнее сообщение от них»
// у них нет, поэтому это отдельный экран, а не вкладка папок. Вход из меню
// долгого нажатия на вкладку «Чаты». Смотрим только основной список, без
// архива, заархивированное владелец убрал сам.

// Сколько последних чатов просматривать. Дальше хвост списка обычно
// давно неактивен.
private let dkxUnansweredScanCount = 400

private struct DkxUnansweredItem: Equatable {
    let peer: EnginePeer
    let waiting: Int32
    let preview: String
}

private final class DkxUnansweredArguments {
    // Нужен ячейкам для аватаров
    let context: AccountContext
    let openChat: (EnginePeer) -> Void

    init(context: AccountContext, openChat: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.openChat = openChat
    }
}

private enum DkxUnansweredEntry: ItemListNodeEntry {
    case header(String)
    case item(index: Int32, DkxUnansweredItem, title: String, waiting: String)
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .item(index, _, _, _):
            return 1 + index
        case .footer:
            return Int32.max
        }
    }

    static func <(lhs: DkxUnansweredEntry, rhs: DkxUnansweredEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxUnansweredArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .item(_, item, title, waiting):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, context: arguments.context, iconPeer: item.peer, title: title, label: waiting, additionalDetailLabel: item.preview.isEmpty ? nil : item.preview, sectionId: self.section, style: .blocks, action: {
                arguments.openChat(item.peer)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func dkxFormatWaiting(_ seconds: Int32) -> String {
    if seconds < 60 {
        return "только что"
    }
    let minutes = seconds / 60
    if minutes < 60 {
        return "\(minutes) мин"
    }
    let hours = minutes / 60
    if hours < 24 {
        return "\(hours) ч"
    }
    return "\(hours / 24) дн"
}

func dkxMessagePreview(_ message: Message) -> String {
    let text = message.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    if !text.isEmpty {
        return text.count > 80 ? String(text.prefix(80)) + "…" : text
    }
    for media in message.media {
        if media is TelegramMediaImage {
            return "Фото"
        } else if let file = media as? TelegramMediaFile {
            if file.isVoice {
                return "Голосовое"
            } else if file.isVideo {
                return file.isInstantVideo ? "Кружок" : "Видео"
            } else if file.isSticker || file.isAnimatedSticker {
                return "Стикер"
            }
            return "Файл"
        } else if media is TelegramMediaMap {
            return "Геопозиция"
        } else if media is TelegramMediaContact {
            return "Контакт"
        }
    }
    return ""
}

private func dkxUnansweredItems(view: ChatListView, accountPeerId: EnginePeer.Id, thresholdHours: Int32, now: Int32) -> [DkxUnansweredItem] {
    var result: [DkxUnansweredItem] = []
    for entry in view.entries {
        guard case let .MessageEntry(entryData) = entry else {
            continue
        }
        guard let user = entryData.renderedPeer.peer as? TelegramUser else {
            continue
        }
        // Боты, Избранное и служебный чат Telegram ответа не ждут
        if user.botInfo != nil || user.id == accountPeerId || user.id.id._internalGetInt64Value() == 777000 {
            continue
        }
        guard let message = entryData.messages.max(by: { $0.index < $1.index }) else {
            continue
        }
        guard message.flags.contains(.Incoming) else {
            continue
        }
        let waiting = max(0, now - message.timestamp)
        if waiting < thresholdHours * 3600 {
            continue
        }
        result.append(DkxUnansweredItem(peer: EnginePeer(user), waiting: waiting, preview: dkxMessagePreview(message)))
    }
    result.sort(by: { $0.waiting > $1.waiting })
    return result
}

public func dkxUnansweredController(context: AccountContext) -> ViewController {
    var navigationControllerImpl: (() -> NavigationController?)?

    let arguments = DkxUnansweredArguments(context: context, openChat: { peer in
        guard let navigationController = navigationControllerImpl?() else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
    })

    let accountPeerId = context.account.peerId
    let items: Signal<[DkxUnansweredItem], NoError> = combineLatest(
        context.account.viewTracker.tailChatListView(groupId: .root, count: dkxUnansweredScanCount),
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
    )
    |> map { viewAndUpdate, sharedData -> [DkxUnansweredItem] in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings
        let now = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        return dkxUnansweredItems(view: viewAndUpdate.0, accountPeerId: accountPeerId, thresholdHours: settings.unansweredHours, now: now)
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        items
    )
    |> map { presentationData, items -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxUnansweredEntry] = []
        if items.isEmpty {
            entries.append(.footer("Все, кто писал последним, уже получили ответ. Порог ожидания настраивается в настройках Dkx."))
        } else {
            entries.append(.header("ЖДУТ ОТВЕТА \(items.count)"))
            for (index, item) in items.enumerated() {
                entries.append(.item(index: Int32(index), item, title: item.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), waiting: dkxFormatWaiting(item.waiting)))
            }
            entries.append(.footer("Личные чаты, где последним написал собеседник, без ботов и архива. Сверху те, кто ждёт дольше всех. Ответили, и человек пропадёт из списка сам."))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Без ответа"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}
