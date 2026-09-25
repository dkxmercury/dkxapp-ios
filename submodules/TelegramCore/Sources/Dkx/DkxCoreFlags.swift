import Foundation

// Выключатели правок форка, которые живут в TelegramCore. Сам TelegramCore
// настроек интерфейса не видит, поэтому значения кладут снаружи: основное
// приложение из подписки на настройки в SharedAccountContext, процесс
// уведомлений из настроек, которые он читает на каждый пуш.
//
// По умолчанию всё включено: до первой загрузки настроек и в процессах,
// которые их не выставляют, поведение как раньше.
public final class DkxCoreFlags {
    private static let lock = NSLock()
    private static var antiDeleteValue = true
    private static var editHistoryValue = true

    // Удалённые собеседником сообщения остаются в чате
    public static var antiDelete: Bool {
        lock.lock()
        let value = antiDeleteValue
        lock.unlock()
        return value
    }

    // Новые версии в историю правок. Уже сохранённая история переносится
    // всегда, иначе выключение тумблера стёрло бы накопленное.
    public static var editHistory: Bool {
        lock.lock()
        let value = editHistoryValue
        lock.unlock()
        return value
    }

    public static func update(antiDelete: Bool, editHistory: Bool) {
        lock.lock()
        antiDeleteValue = antiDelete
        editHistoryValue = editHistory
        lock.unlock()
    }
}
