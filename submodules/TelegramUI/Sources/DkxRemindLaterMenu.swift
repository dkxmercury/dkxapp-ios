import Foundation
import UIKit
import Postbox
import TelegramCore
import Display
import AccountContext
import TelegramPresentationData
import TelegramUIPreferences
import ChatListUI

// MARK: DKX «Напомнить позже» из меню сообщения. Общая часть с меню чата
// лежит в ChatListUI, тут только название чата и начало текста сообщения.

func dkxRemindLaterApplicable(message: Message) -> Bool {
    return DkxRuntime.current.remindLater && message.id.namespace == Namespaces.Message.Cloud
}

func dkxRemindLaterForMessage(context: AccountContext, message: Message, present: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let chatTitle = (message.peers[message.id.peerId].flatMap { EnginePeer($0).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) }) ?? DkxStrings.tr("Чат")
    let text = message.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    let note: String
    if text.isEmpty {
        note = DkxStrings.tr("Сообщение с вложением")
    } else if text.count > 200 {
        note = String(text.prefix(200)) + "…"
    } else {
        note = text
    }
    dkxPresentRemindLater(context: context, peerId: message.id.peerId, messageId: message.id, title: chatTitle, note: note, present: present)
}
