import Foundation
import Postbox

// Предыдущие версии текста сообщения, от самой старой к самой свежей.
//
// Хранится двумя параллельными массивами примитивов намеренно. Постбоксовый
// decodeObjectArrayForKey при сбое разбора одного элемента возвращает пустой
// массив целиком, без ошибки и без лога, то есть одна битая запись стёрла бы
// всю историю. С массивами строк и чисел такого класса ошибок нет.
//
// Имя класса после первой установки менять нельзя, хэш типа считается от него.
public class DkxEditHistoryAttribute: MessageAttribute {
    // Текст версии и момент, когда её заменили. Длины всегда совпадают.
    public let texts: [String]
    public let dates: [Int32]

    public var associatedMessageIds: [MessageId] = []

    public init(texts: [String], dates: [Int32]) {
        let count = min(texts.count, dates.count)
        self.texts = Array(texts.prefix(count))
        self.dates = Array(dates.prefix(count))
    }

    required public init(decoder: PostboxDecoder) {
        let texts = decoder.decodeStringArrayForKey("t")
        let dates = decoder.decodeInt32ArrayForKey("d")
        let count = min(texts.count, dates.count)
        self.texts = Array(texts.prefix(count))
        self.dates = Array(dates.prefix(count))
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeStringArray(self.texts, forKey: "t")
        encoder.encodeInt32Array(self.dates, forKey: "d")
    }
}
