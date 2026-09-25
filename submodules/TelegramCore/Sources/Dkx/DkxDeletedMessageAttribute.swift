import Foundation
import Postbox

// Имя класса после первой установки менять нельзя. Postbox вычисляет хэш типа
// как murMurHash от строки с именем класса, поэтому переименование осиротит
// все уже сохранённые пометки, без ошибки и без возможности восстановить.
public class DkxDeletedMessageAttribute: MessageAttribute {
    public let deletionDate: Int32

    public var associatedMessageIds: [MessageId] = []

    public init(deletionDate: Int32) {
        self.deletionDate = deletionDate
    }

    required public init(decoder: PostboxDecoder) {
        self.deletionDate = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletionDate, forKey: "d")
    }
}
