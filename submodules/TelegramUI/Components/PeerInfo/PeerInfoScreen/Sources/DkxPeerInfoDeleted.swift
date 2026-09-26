import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import TelegramStringFormatting

// MARK: DKX кнопки «Удалённое» и «Изменённое» в профиле собеседника. Ищут в
// базе на телефоне сообщения с пометками форка, в личном чате и в общих
// группах. На сервере удалённых уже нет, поэтому найдётся только то, что
// телефон успел сохранить.

private enum DkxPeerHistoryMode {
    case deleted
    case edited
}

// Сколько последних сообщений просматривать, в группах меньше, иначе долго
private let dkxScanLimitPrivate = 30000
private let dkxScanLimitGroup = 5000
private let dkxMaxResults = 500

func dkxPeerHistoryItems(firstId: Int, user: TelegramUser, context: AccountContext, interaction: PeerInfoInteraction) -> [PeerInfoScreenItem] {
    guard user.id != context.account.peerId, user.botInfo == nil else {
        return []
    }
    var items: [PeerInfoScreenItem] = []
    let peerId = user.id
    if DkxRuntime.current.antiDelete {
        items.append(PeerInfoScreenActionItem(id: firstId, text: "Удалённое", action: { [weak interaction] in
            guard let controller = interaction?.getController() else {
                return
            }
            controller.push(dkxPeerHistoryController(context: context, peerId: peerId, mode: .deleted))
        }))
    }
    if DkxRuntime.current.editHistory {
        items.append(PeerInfoScreenActionItem(id: firstId + 1, text: "Изменённое", action: { [weak interaction] in
            guard let controller = interaction?.getController() else {
                return
            }
            controller.push(dkxPeerHistoryController(context: context, peerId: peerId, mode: .edited))
        }))
    }
    return items
}

private struct DkxFoundMessage: Equatable {
    let id: EngineMessage.Id
    let chatTitle: String
    let date: Int32
    let text: String
    let versions: Int
}

private func dkxMediaDescription(_ message: Message) -> String {
    for media in message.media {
        if media is TelegramMediaImage {
            return "Фото"
        }
        if let file = media as? TelegramMediaFile {
            if file.isVoice {
                return "Голосовое"
            }
            if file.isInstantVideo {
                return "Кружок"
            }
            if file.isSticker || file.isAnimatedSticker {
                return "Стикер"
            }
            if file.isVideo {
                return "Видео"
            }
            if file.isMusic {
                return "Аудио"
            }
            return "Файл"
        }
        if media is TelegramMediaMap {
            return "Геопозиция"
        }
        if media is TelegramMediaContact {
            return "Контакт"
        }
        if media is TelegramMediaPoll {
            return "Опрос"
        }
    }
    return "Сообщение"
}

// Общие группы грузятся с сервера страницами, берём до двух сотен
private func dkxCommonGroupIds(context: AccountContext, peerId: EnginePeer.Id) -> Signal<[EnginePeer.Id], NoError> {
    let groups = GroupsInCommonContext(account: context.account, peerId: peerId)
    return groups.state
    |> mapToSignal { state -> Signal<[EnginePeer.Id], NoError> in
        switch state.dataState {
        case .loading:
            return .complete()
        case let .ready(canLoadMore):
            if canLoadMore && state.peers.count < 200 {
                groups.loadMore()
                return .complete()
            }
            return .single(state.peers.map { $0.peerId })
        }
    }
    |> take(1)
    |> timeout(10.0, queue: .mainQueue(), alternate: .single([]))
}

private func dkxScanPeerHistory(context: AccountContext, authorId: EnginePeer.Id, chatIds: [EnginePeer.Id], mode: DkxPeerHistoryMode) -> Signal<[DkxFoundMessage], NoError> {
    return context.account.postbox.transaction { transaction -> [DkxFoundMessage] in
        var result: [DkxFoundMessage] = []
        for chatId in chatIds {
            var candidates: [MessageId] = []
            let limit = chatId == authorId ? dkxScanLimitPrivate : dkxScanLimitGroup
            transaction.scanMessageAttributes(peerId: chatId, namespace: Namespaces.Message.Cloud, limit: limit, { id, attributes in
                switch mode {
                case .deleted:
                    if attributes.contains(where: { $0 is DkxDeletedMessageAttribute }) {
                        candidates.append(id)
                    }
                case .edited:
                    if attributes.contains(where: { ($0 as? DkxEditHistoryAttribute).map({ !$0.texts.isEmpty }) ?? false }) {
                        candidates.append(id)
                    }
                }
                return true
            })
            if candidates.isEmpty {
                continue
            }
            let isPrivate = chatId == authorId
            let chatTitle = isPrivate ? "Личный чат" : (transaction.getPeer(chatId).map { EnginePeer($0).compactDisplayTitle } ?? "Группа")
            for id in candidates {
                guard let message = transaction.getMessage(id) else {
                    continue
                }
                // В личном чате удалённое целиком на совести собеседника, даже
                // ваши сообщения. Правки и всё в группах только его собственные.
                if !(isPrivate && mode == .deleted) && message.author?.id != authorId {
                    continue
                }
                let text = message.text.isEmpty ? dkxMediaDescription(message) : message.text
                var date = message.timestamp
                var versions = 0
                for attribute in message.attributes {
                    if let deleted = attribute as? DkxDeletedMessageAttribute, mode == .deleted, deleted.deletionDate != 0 {
                        date = deleted.deletionDate
                    } else if let history = attribute as? DkxEditHistoryAttribute, mode == .edited {
                        versions = history.texts.count
                        if let last = history.dates.last {
                            date = max(date, last)
                        }
                    }
                }
                result.append(DkxFoundMessage(id: message.id, chatTitle: chatTitle, date: date, text: text, versions: versions))
            }
        }
        result.sort(by: { $0.date > $1.date })
        if result.count > dkxMaxResults {
            result.removeLast(result.count - dkxMaxResults)
        }
        return result
    }
}

private final class DkxPeerHistoryArguments {
    let open: (EngineMessage.Id) -> Void

    init(open: @escaping (EngineMessage.Id) -> Void) {
        self.open = open
    }
}

private enum DkxPeerHistoryEntry: ItemListNodeEntry {
    case status(String)
    case message(index: Int32, label: String, text: String, id: EngineMessage.Id)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .status:
            return 0
        case let .message(index, _, _, _):
            return 1 + index
        }
    }

    static func <(lhs: DkxPeerHistoryEntry, rhs: DkxPeerHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxPeerHistoryArguments
        switch self {
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .message(_, label, text, id):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: {
                arguments.open(id)
            })
        }
    }
}

private func dkxPeerHistoryController(context: AccountContext, peerId: EnginePeer.Id, mode: DkxPeerHistoryMode) -> ViewController {
    var navigationControllerImpl: (() -> NavigationController?)?

    let arguments = DkxPeerHistoryArguments(open: { id in
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: id.peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer, let navigationController = navigationControllerImpl?() else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
        })
    })

    let found: Signal<[DkxFoundMessage]?, NoError> = .single(nil)
    |> then(
        dkxCommonGroupIds(context: context, peerId: peerId)
        |> mapToSignal { groupIds -> Signal<[DkxFoundMessage]?, NoError> in
            return dkxScanPeerHistory(context: context, authorId: peerId, chatIds: [peerId] + groupIds, mode: mode)
            |> map { Optional($0) }
        }
    )

    let title = mode == .deleted ? "Удалённое" : "Изменённое"
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, found)
    |> map { presentationData, found -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxPeerHistoryEntry] = []
        if let found {
            if found.isEmpty {
                entries.append(.status(mode == .deleted ? "Удалённых сообщений нет. Сохраняются только те, что собеседник удалил при включённом «Сохранять удалённые», и только если телефон успел их получить." : "Изменённых сообщений нет. Прежние версии сохраняются при включённой «Истории правок»."))
            } else {
                entries.append(.status("Найдено \(found.count). Личный чат и общие группы, нажатие открывает сообщение."))
                for (index, item) in found.enumerated() {
                    let date = stringForMediumDate(timestamp: item.date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
                    var label = "\(item.chatTitle) · \(date)"
                    if mode == .edited {
                        label += " · правок \(item.versions)"
                    }
                    entries.append(.message(index: Int32(index), label: label, text: item.text, id: item.id))
                }
            }
        } else {
            entries.append(.status("Ищу в личном чате и общих группах…"))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}
