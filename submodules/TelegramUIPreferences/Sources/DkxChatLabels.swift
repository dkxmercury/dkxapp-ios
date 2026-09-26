import Foundation

// MARK: DKX свои метки на чаты. Хранятся в DkxSettings параллельными
// массивами, словари декодер Postbox не читает. Метки идут в том порядке, в
// каком лежат, пары «чат и метка» лежат отдельно. Живут только на телефоне,
// лимиты папок Telegram их не касаются.
public struct DkxChatLabel: Equatable {
    public let id: Int32
    public var title: String
    public var colorId: Int32

    public init(id: Int32, title: String, colorId: Int32) {
        self.id = id
        self.title = title
        self.colorId = colorId
    }
}

// Те же семь цветов, что у тегов папок Telegram, номера из PeerNameColor.
// Список чатов красит метки штатной палитрой тегов.
public let dkxChatLabelColors: [(id: Int32, title: String)] = [
    (0, "Красный"),
    (1, "Оранжевый"),
    (2, "Фиолетовый"),
    (3, "Зелёный"),
    (4, "Бирюзовый"),
    (5, "Синий"),
    (6, "Розовый")
]

public extension DkxSettings {
    var chatLabels: [DkxChatLabel] {
        let count = min(self.labelIds.count, self.labelTitles.count, self.labelColors.count)
        return (0 ..< count).map { DkxChatLabel(id: self.labelIds[$0], title: self.labelTitles[$0], colorId: self.labelColors[$0]) }
    }

    var nextChatLabelId: Int32 {
        return (self.labelIds.max() ?? 0) + 1
    }

    // Пары удалённых меток уходят вместе с ними
    mutating func setChatLabels(_ labels: [DkxChatLabel]) {
        self.labelIds = labels.map { $0.id }
        self.labelTitles = labels.map { $0.title }
        self.labelColors = labels.map { $0.colorId }
        let valid = Set(self.labelIds)
        var peers: [Int64] = []
        var ids: [Int32] = []
        for i in 0 ..< min(self.labelPeers.count, self.labelPeerLabels.count) where valid.contains(self.labelPeerLabels[i]) {
            peers.append(self.labelPeers[i])
            ids.append(self.labelPeerLabels[i])
        }
        self.labelPeers = peers
        self.labelPeerLabels = ids
    }

    func chatLabelIds(forPeer peerId: Int64) -> Set<Int32> {
        var result = Set<Int32>()
        for i in 0 ..< min(self.labelPeers.count, self.labelPeerLabels.count) where self.labelPeers[i] == peerId {
            result.insert(self.labelPeerLabels[i])
        }
        return result
    }

    func peers(withChatLabel labelId: Int32) -> [Int64] {
        var result: [Int64] = []
        for i in 0 ..< min(self.labelPeers.count, self.labelPeerLabels.count) where self.labelPeerLabels[i] == labelId {
            result.append(self.labelPeers[i])
        }
        return result
    }

    mutating func setChatLabel(_ labelId: Int32, peer peerId: Int64, assigned: Bool) {
        var peers: [Int64] = []
        var ids: [Int32] = []
        for i in 0 ..< min(self.labelPeers.count, self.labelPeerLabels.count) {
            if self.labelPeers[i] == peerId && self.labelPeerLabels[i] == labelId {
                continue
            }
            peers.append(self.labelPeers[i])
            ids.append(self.labelPeerLabels[i])
        }
        if assigned {
            peers.append(peerId)
            ids.append(labelId)
        }
        self.labelPeers = peers
        self.labelPeerLabels = ids
    }

    // Для строк списка чатов, в порядке меток, а не в порядке назначения
    func chatLabelsByPeer() -> [Int64: [DkxChatLabel]] {
        let labels = self.chatLabels
        var order: [Int32: Int] = [:]
        for (index, label) in labels.enumerated() {
            order[label.id] = index
        }
        var result: [Int64: [DkxChatLabel]] = [:]
        for i in 0 ..< min(self.labelPeers.count, self.labelPeerLabels.count) {
            if let index = order[self.labelPeerLabels[i]] {
                result[self.labelPeers[i], default: []].append(labels[index])
            }
        }
        for (peerId, peerLabels) in result {
            result[peerId] = peerLabels.sorted(by: { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) })
        }
        return result
    }
}
