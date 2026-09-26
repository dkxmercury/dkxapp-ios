import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUIPreferences

// MARK: DKX своё закрепление чатов, только на этом телефоне и без лимита.
// Штатное закрепление трогать нельзя, его база сразу шлёт на сервер, а там
// лимит. Поэтому строки закреплённых собираются отдельно и подмешиваются в
// начало главного списка, сразу под штатно закреплёнными. Нужны отдельно ещё
// и потому, что старый чат иначе не попал бы в загруженную часть списка.

private func dkxLocalPinnedItems(account: Account, peerIds: [EnginePeer.Id]) -> Signal<[EngineChatList.Item], NoError> {
    if peerIds.isEmpty {
        return .single([])
    }
    let topKey: PostboxViewKey = .topChatMessage(peerIds: peerIds)
    var keys: [PostboxViewKey] = [topKey]
    for peerId in peerIds {
        keys.append(.basicPeer(peerId))
        keys.append(.combinedReadState(peerId: peerId, handleThreads: false))
    }
    return account.postbox.combinedView(keys: keys)
    |> map { views -> [EngineChatList.Item] in
        let top = views.views[topKey] as? TopChatMessageView
        var result: [EngineChatList.Item] = []
        for (order, peerId) in peerIds.enumerated() {
            guard let basic = views.views[.basicPeer(peerId)] as? BasicPeerView, let peer = basic.peer, !(peer is TelegramSecretChat) else {
                continue
            }
            let message = top?.messages[peerId]
            let readState = (views.views[.combinedReadState(peerId: peerId, handleThreads: false)] as? CombinedReadStateView)?.state
            let isMuted = basic.notificationSettings?.isRemovedFromTotalUnreadCount(default: false) ?? false
            // Номер только для порядка. Дата в строке берётся из самого сообщения
            let orderValue = Int32.max - Int32(order)
            let sortIndex = MessageIndex(id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: orderValue), timestamp: orderValue)
            result.append(EngineChatList.Item(
                id: .chatList(peerId),
                index: .chatList(ChatListIndex(pinningIndex: nil, messageIndex: sortIndex)),
                messages: message.map { [EngineMessage($0)] } ?? [],
                readCounters: EnginePeerReadCounters(state: readState, isMuted: isMuted),
                isMuted: isMuted,
                draft: nil,
                threadData: nil,
                renderedPeer: EngineRenderedPeer(peer: EnginePeer(peer)),
                presence: nil,
                hasUnseenMentions: false,
                hasUnseenReactions: false,
                hasUnseenPollVotes: false,
                forumTopicData: nil,
                topForumTopicItems: [],
                hasFailed: false,
                isContact: basic.isContact,
                autoremoveTimeout: nil,
                storyStats: nil,
                displayAsTopicList: false,
                isPremiumRequiredToMessage: false,
                mediaDraftContentType: nil
            ))
        }
        return result
    }
}

// Штатно закреплённый чат остаётся на своём месте, свой пин ему не нужен
private func dkxApplyLocalPins(_ list: EngineChatList, pinned: [EngineChatList.Item]) -> EngineChatList {
    if pinned.isEmpty {
        return list
    }
    let pinnedIds = Set(pinned.map { $0.renderedPeer.peerId })
    var serverPinned = Set<EnginePeer.Id>()
    var items: [EngineChatList.Item] = []
    for item in list.items {
        if case let .chatList(index) = item.index, index.pinningIndex != nil {
            serverPinned.insert(item.renderedPeer.peerId)
            items.append(item)
            continue
        }
        if pinnedIds.contains(item.renderedPeer.peerId) {
            continue
        }
        items.append(item)
    }
    if !list.hasLater {
        items.append(contentsOf: pinned.filter { !serverPinned.contains($0.renderedPeer.peerId) })
        items.sort(by: { $0.index < $1.index })
    }
    return EngineChatList(items: items, groupItems: list.groupItems, additionalItems: list.additionalItems, hasEarlier: list.hasEarlier, hasLater: list.hasLater, isLoading: list.isLoading)
}

func dkxWithLocalPins(_ signal: Signal<ChatListNodeViewUpdate, NoError>, account: Account) -> Signal<ChatListNodeViewUpdate, NoError> {
    let pinned = DkxRuntime.localPinsSignal
    |> mapToSignal { ids -> Signal<[EngineChatList.Item], NoError> in
        return dkxLocalPinnedItems(account: account, peerIds: ids.map { EnginePeer.Id($0) })
    }
    // Обновление одних только закреплённых не должно повторно крутить список
    // к позиции из прошлого обновления, поэтому обновления списка нумеруем
    let counter = Atomic<Int>(value: 0)
    let numbered = signal
    |> map { update -> (Int, ChatListNodeViewUpdate) in
        return (counter.modify { $0 + 1 }, update)
    }
    let lastSeen = Atomic<Int>(value: 0)
    return combineLatest(numbered, pinned)
    |> map { numberedUpdate, pinned -> ChatListNodeViewUpdate in
        let (number, update) = numberedUpdate
        let isNew = lastSeen.swap(number) != number
        return ChatListNodeViewUpdate(list: dkxApplyLocalPins(update.list, pinned: pinned), type: isNew ? update.type : .Generic, scrollPosition: isNew ? update.scrollPosition : nil)
    }
}
