import Foundation
import Postbox

// Откуда пришло удаление. Перехватываем только remote, то есть когда сервер
// сообщил, что сообщение удалено. Все локальные удаления остаются как были.
public enum DkxDeleteReason {
    case local
    case remote
}

public enum DkxAntiDelete {
    // Разделяет список на те, что оставляем помеченными, и те, что реально удаляем.
    public static func partition(transaction: Transaction, ids: [MessageId]) -> (keep: [MessageId], drop: [MessageId]) {
        var keep: [MessageId] = []
        var drop: [MessageId] = []
        for id in ids {
            if self.shouldKeep(transaction: transaction, id: id) {
                keep.append(id)
            } else {
                drop.append(id)
            }
        }
        return (keep, drop)
    }

    private static func shouldKeep(transaction: Transaction, id: MessageId) -> Bool {
        // Только облачные. В локальных пространствах идентификаторы
        // переиспользуются, и пометка прилипнет к чужому сообщению.
        if id.namespace != Namespaces.Message.Cloud {
            return false
        }
        // Секретные чаты не трогаем никогда. Там исчезновение это модель
        // безопасности, а не поведение интерфейса.
        if id.peerId.namespace == Namespaces.Peer.SecretChat {
            return false
        }
        guard let message = transaction.getMessage(id) else {
            return false
        }
        // Содержимое с однократным просмотром тоже не задерживаем.
        if message.containsSecretMedia {
            return false
        }
        for attribute in message.attributes {
            // Сгорающие по таймеру оставлять нельзя, это прямо названо
            // в правилах Telegram как нарушение.
            if attribute is AutoremoveTimeoutMessageAttribute {
                return false
            }
            // Уже помечено. Оставляем, но метить повторно не нужно.
            if attribute is DkxDeletedMessageAttribute {
                return true
            }
        }
        return true
    }

    // Вешает пометку. Идемпотентно: если пометка уже есть, сообщение не трогается.
    //
    // channelPts нужен там, где мы отменяем удаление внутри перепроверки истории
    // канала. Рядом с тем удалением апстрим проставляет отметку "проверено на
    // этой версии состояния". Без неё оставленное сообщение будет попадать
    // в перепроверку снова и снова и тянуть запись в базу на каждой прокрутке.
    public static func mark(transaction: Transaction, ids: [MessageId], channelPts: Int32? = nil) {
        let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        for id in ids {
            transaction.updateMessage(id, update: { currentMessage in
                var alreadyMarked = false
                for attribute in currentMessage.attributes {
                    if attribute is DkxDeletedMessageAttribute {
                        alreadyMarked = true
                        break
                    }
                }
                if alreadyMarked && channelPts == nil {
                    return .skip
                }
                var storeForwardInfo: StoreMessageForwardInfo?
                if let forwardInfo = currentMessage.forwardInfo {
                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                }
                var updatedAttributes = currentMessage.attributes
                if let channelPts = channelPts {
                    for i in (0 ..< updatedAttributes.count).reversed() {
                        if updatedAttributes[i] is ChannelMessageStateVersionAttribute {
                            updatedAttributes.remove(at: i)
                        }
                    }
                    updatedAttributes.append(ChannelMessageStateVersionAttribute(pts: channelPts))
                }
                if !alreadyMarked {
                    updatedAttributes.append(DkxDeletedMessageAttribute(deletionDate: timestamp))
                }
                // customStableId оставляем nil, иначе строка в списке переедет
                // и чат дёрнется на ровном месте.
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: currentMessage.media))
            })
        }
    }
}
