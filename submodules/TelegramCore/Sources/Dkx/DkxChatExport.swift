import Foundation
import Postbox
import SwiftSignalKit

// Выгрузка чата в файл, часть про данные. Оформление текста живёт в слое
// интерфейса, ему нужны строки локализации.
//
// Сначала догружаем с сервера всю историю тем же механизмом, которым
// Telegram заполняет дыры при прокрутке вверх, потом берём все сообщения
// чата из локальной базы. Так в выгрузку попадают и сохранённые нами
// удалённые сообщения, которых на сервере уже нет, и история правок.
public enum DkxChatExport {
    // Порция загрузки и предел порций. 300 по 100 это 30 тысяч сообщений,
    // дальше выгрузка остановится и честно скажет, сколько успела.
    private static let batchSize = 100
    public static let maxBatches = 300

    // Выдаёт число сообщений в каждой пришедшей порции и завершается, когда
    // дыр не осталось, сервер перестал отдавать новое или кончился предел.
    public static func loadFullHistory(account: Account, peerId: PeerId) -> Signal<Int, NoError> {
        // В секретных чатах истории на сервере нет
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return .complete()
        }
        return self.step(account: account, peerId: peerId, remaining: self.maxBatches)
    }

    private static func step(account: Account, peerId: PeerId, remaining: Int) -> Signal<Int, NoError> {
        if remaining <= 0 {
            DkxLog.write("выгрузка", "предел порций, остановился")
            return .complete()
        }
        return account.postbox.transaction { transaction -> ClosedRange<Int32>? in
            let holes = transaction.getHoles(peerId: peerId, namespace: Namespaces.Message.Cloud)
            // Берём верхнюю дыру и грузим от свежих к старым, как прокрутка
            guard let last = holes.rangeView.last else {
                return nil
            }
            let lower = Int32(clamping: max(1, last.lowerBound))
            let upper = Int32(clamping: last.upperBound - 1)
            if upper < lower {
                return nil
            }
            return lower ... upper
        }
        |> mapToSignal { range -> Signal<Int, NoError> in
            guard let range = range else {
                return .complete()
            }
            let direction: MessageHistoryViewRelativeHoleDirection = .range(
                start: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: range.upperBound),
                end: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: range.lowerBound)
            )
            return fetchMessageHistoryHole(accountPeerId: account.peerId, source: .network(account.network), postbox: account.postbox, peerInput: .direct(peerId: peerId, threadId: nil), namespace: Namespaces.Message.Cloud, direction: direction, space: .everywhere, count: self.batchSize)
            |> mapToSignal { result -> Signal<Int, NoError> in
                // Дыра не уменьшилась, значит дальше грузить нечего или
                // сервер отказал. Без этой проверки цикл крутился бы вечно.
                guard let result = result, !result.removedIndices.isEmpty else {
                    return .complete()
                }
                return .single(result.ids.count)
                |> then(self.step(account: account, peerId: peerId, remaining: remaining - 1))
            }
        }
    }

    // Все сообщения чата из локальной базы, от старых к новым. Локальные
    // пространства вроде неотправленных тоже берём, чтобы выгрузка
    // совпадала с тем, что видно в чате.
    public static func collectMessages(account: Account, peerId: PeerId) -> Signal<[Message], NoError> {
        return account.postbox.transaction { transaction -> [Message] in
            var result: [Message] = []
            for namespace in [Namespaces.Message.Cloud, Namespaces.Message.Local, Namespaces.Message.SecretIncoming] {
                transaction.scanTopMessages(peerId: peerId, namespace: namespace, limit: self.maxBatches * self.batchSize + 1000, { message in
                    result.append(message)
                    return true
                })
            }
            result.sort(by: { $0.index < $1.index })
            return result
        }
    }
}
