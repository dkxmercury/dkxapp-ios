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
        // Текст не изменился. Это правка медиа, реакций, разметки или чего-то
        // ещё, версию заводить незачем.
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
    }
}
