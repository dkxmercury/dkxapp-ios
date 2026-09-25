import Foundation
import LocalAuthentication
import SwiftSignalKit
import TelegramCore

// Face ID на отдельный чат, группу, канал или Избранное.
//
// Список закрытых лежит в DkxSettings.lockedPeers. Открытый после проверки
// чат остаётся открытым до ухода приложения в фон, потом снова закрыт.
// Именно фон, а не потеря фокуса: окно Face ID само снимает фокус с
// приложения, и замок захлопывался бы сразу после проверки.
//
// Проверка через deviceOwnerAuthentication: Face ID, а если не вышло,
// пароль телефона. Только биометрия оставила бы без доступа к чату при
// мокрых пальцах или в маске.
public final class DkxChatLock {
    private static let lock = NSLock()
    private static var unlocked = Set<Int64>()

    public static func isLocked(_ peerId: EnginePeer.Id) -> Bool {
        let settings = DkxRuntime.current
        return settings.chatLock && settings.lockedPeers.contains(peerId.toInt64())
    }

    // Закрыт и в этой сессии ещё не открывался
    public static func needsAuthentication(_ peerId: EnginePeer.Id) -> Bool {
        guard self.isLocked(peerId) else {
            return false
        }
        lock.lock()
        let result = !unlocked.contains(peerId.toInt64())
        lock.unlock()
        return result
    }

    public static func markUnlocked(_ peerId: EnginePeer.Id) {
        lock.lock()
        unlocked.insert(peerId.toInt64())
        lock.unlock()
    }

    public static func lockAll() {
        lock.lock()
        unlocked.removeAll()
        lock.unlock()
    }

    public static func authenticate(reason: String) -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                // На телефоне без пароля проверять нечем, пускаем, иначе чат
                // стал бы недоступен навсегда
                subscriber.putNext(true)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: { success, _ in
                subscriber.putNext(success)
                subscriber.putCompletion()
            })
            return ActionDisposable {
                context.invalidate()
            }
        }
    }
}
