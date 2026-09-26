import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import TelegramUIPreferences
import UndoUI
import ChatScheduleTimeController

// MARK: DKX «Напомнить позже» из меню чата в списке и из меню сообщения.
// Напоминание ложится делом в «Мои дела» со ссылкой на чат и сообщение,
// уведомление открывает этот чат на этом сообщении.

public func dkxPresentRemindLater(context: AccountContext, peerId: EnginePeer.Id, messageId: EngineMessage.Id?, title: String, note: String, present: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let calendar = Calendar.current
    let now = Date()

    var options: [(String, Date)] = []
    options.append(("Через час", now.addingTimeInterval(3600.0)))
    options.append(("Через 3 часа", now.addingTimeInterval(3.0 * 3600.0)))
    // Вечер предлагаем, только пока до него есть хотя бы полчаса
    if let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now), evening.timeIntervalSince(now) > 30.0 * 60.0 {
        options.append(("Сегодня в 19:00", evening))
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)), let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
        options.append(("Завтра в 9:00", morning))
    }

    let schedule: (Date) -> Void = { date in
        dkxAddReminder(context: context, peerId: peerId, messageId: messageId, title: title, note: note, date: date, present: present)
    }

    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Напомнить позже")]
    for (label, date) in options {
        items.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            schedule(date)
        }))
    }
    items.append(ActionSheetButtonItem(title: "Выбрать дату и время", color: .accent, action: { [weak actionSheet] in
        actionSheet?.dismissAnimated()
        let controller = ChatScheduleTimeController(context: context, mode: .reminders, style: .default, currentTime: nil, minimalTime: Int32(Date().timeIntervalSince1970) + 60, dismissByTapOutside: true, completion: { time in
            schedule(Date(timeIntervalSince1970: Double(time)))
        })
        present(controller)
    }))
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    present(actionSheet)
}

private func dkxAddReminder(context: AccountContext, peerId: EnginePeer.Id, messageId: EngineMessage.Id?, title: String, note: String, date: Date, present: @escaping (ViewController) -> Void) {
    let task = DkxTask(
        id: DkxTask.newId(),
        title: title,
        note: note,
        date: Int32(date.timeIntervalSince1970),
        hasTime: true,
        remind: .atTime,
        done: false,
        doneAt: 0,
        createdAt: Int32(Date().timeIntervalSince1970),
        accountId: context.account.id.int64,
        peerId: peerId.toInt64(),
        messageNamespace: messageId?.namespace ?? 0,
        messageId: messageId?.id ?? 0
    )
    let _ = updateDkxTasksInteractively(accountManager: context.sharedContext.accountManager, { current in
        var updated = current
        updated.items.append(task)
        return updated
    }).start()

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'сегодня в' H:mm" : "d MMMM 'в' H:mm"
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Напомню \(formatter.string(from: date)). Дело лежит в «Моих делах».", timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
}
