import Foundation
import Postbox

public enum DkxEditHistory {
    // Потолок на случай бота, который правит сообщение в цикле. Первую версию
    // держим всегда, она самая интересная, остальное вытесняется свежим.
    public static let maxVersions = 20

    // Вызывается в момент применения правки от сервера. previousMessage это
    // полное сообщение до правки, сервер старый текст не присылает никогда,
    // поэтому снимок можно взять только здесь.
    public static func appendVersion(previousMessage: Message, newText: String, attributes: inout [MessageAttribute]) {
        // ВАЖНО. attributes это набор атрибутов, пришедший с сервера, и он
        // целиком заменяет прежний через withUpdatedAttributes. Наших атрибутов
        // сервер не знает, поэтому их надо переносить вручную на КАЖДОМ
        // обновлении, а не только когда изменился текст.
        //
        // Иначе происходит вот что. Первая правка сохраняет историю, а любое
        // следующее обновление того же сообщения (счётчик просмотров, реакция,
        // повторная правка без смены текста) выходит отсюда рано и затирает
        // её набором с сервера.
        //
        // Апстрим делает ровно то же самое рядом для TranslationMessageAttribute
        // и FactCheckMessageAttribute, и именно поэтому те блоки существуют.
        carryOver(previousMessage: previousMessage, attributes: &attributes)

        // Тумблер выключен: накопленное сохраняем, новые версии не заводим
        if !DkxCoreFlags.editHistory {
            return
        }

        // Текст не изменился. Это правка медиа, реакций, разметки или чего-то
        // ещё, новую версию заводить незачем, но перенос выше уже случился.
        if previousMessage.text == newText {
            return
        }
        if previousMessage.text.isEmpty {
            return
        }
        // Секретные чаты не трогаем, там исчезновение это модель безопасности.
        if previousMessage.id.peerId.namespace == Namespaces.Peer.SecretChat {
            return
        }

        var texts: [String] = []
        var dates: [Int32] = []
        for attribute in previousMessage.attributes {
            if let existing = attribute as? DkxEditHistoryAttribute {
                texts = existing.texts
                dates = existing.dates
                break
            }
        }

        texts.append(previousMessage.text)
        dates.append(Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970))

        if texts.count > maxVersions {
            let keepRecent = maxVersions - 1
            texts = [texts[0]] + texts.suffix(keepRecent)
            dates = [dates[0]] + dates.suffix(keepRecent)
        }

        // В attributes лежат атрибуты нового сообщения, пришедшие от сервера.
        // Нашего среди них быть не может, но убираем на всякий случай, чтобы
        // не получить два.
        attributes.removeAll(where: { $0 is DkxEditHistoryAttribute })
        attributes.append(DkxEditHistoryAttribute(texts: texts, dates: dates))
        DkxLog.write("правка", "сохранена версия \(texts.count) для \(previousMessage.id)")
    }

    // Переносит наши атрибуты из прежнего сообщения в новый набор с сервера.
    private static func carryOver(previousMessage: Message, attributes: inout [MessageAttribute]) {
        for attribute in previousMessage.attributes {
            if attribute is DkxEditHistoryAttribute {
                if !attributes.contains(where: { $0 is DkxEditHistoryAttribute }) {
                    attributes.append(attribute)
                }
            } else if attribute is DkxDeletedMessageAttribute {
                // Пометку удалённого тоже переносим, иначе правка по уже
                // помеченному сообщению стёрла бы её.
                if !attributes.contains(where: { $0 is DkxDeletedMessageAttribute }) {
                    attributes.append(attribute)
                }
            }
        }
    }
}
