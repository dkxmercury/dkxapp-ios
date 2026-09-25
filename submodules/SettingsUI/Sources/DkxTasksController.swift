import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import ItemListDatePickerItem

// «Мои дела». Список дел по дню, неделе или месяцу вокруг выбранной даты,
// либо все незавершённые разом с подгрузкой при прокрутке. Редактор с
// датой, временем и напоминанием. Завершение дела через подтверждение, как
// просил владелец. Хранение и напоминания в DkxTasks.

// MARK: - Общее

private enum DkxTasksMode: Int32 {
    case day
    case week
    case month
    case all
}

private let dkxTasksModes: [(DkxTasksMode, String)] = [
    (.day, "День"),
    (.week, "Неделя"),
    (.month, "Месяц"),
    (.all, "Все незавершённые")
]

// Порция при подгрузке в режиме «Все»
private let dkxTasksPageSize = 50

private func dkxStartOfDay(_ date: Date) -> Date {
    return Calendar.current.startOfDay(for: date)
}

private func dkxPeriod(mode: DkxTasksMode, around date: Date) -> (Int32, Int32)? {
    let calendar = Calendar.current
    switch mode {
    case .day:
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (Int32(start.timeIntervalSince1970), Int32(end.timeIntervalSince1970))
    case .week:
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return nil
        }
        return (Int32(interval.start.timeIntervalSince1970), Int32(interval.end.timeIntervalSince1970))
    case .month:
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            return nil
        }
        return (Int32(interval.start.timeIntervalSince1970), Int32(interval.end.timeIntervalSince1970))
    case .all:
        return nil
    }
}

private func dkxDayTitle(_ timestamp: Int32) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp))
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "EEEE, d MMMM"
    let text = formatter.string(from: date).uppercased()
    if calendar.isDateInToday(date) {
        return "СЕГОДНЯ, " + text
    } else if calendar.isDateInTomorrow(date) {
        return "ЗАВТРА, " + text
    } else if calendar.isDateInYesterday(date) {
        return "ВЧЕРА, " + text
    }
    return text
}

private func dkxTimeLabel(_ task: DkxTask) -> String {
    if task.date == 0 {
        return ""
    }
    if !task.hasTime {
        return "весь день"
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(task.date)))
}

private func dkxRemindTitle(_ remind: DkxTask.Remind) -> String {
    switch remind {
    case .none:
        return "Без напоминания"
    case .atTime:
        return "В момент дела"
    case .hourBefore:
        return "За час"
    case .twoHoursBefore:
        return "За 2 часа"
    case .dayBefore:
        return "За день"
    }
}

private func dkxTaskDetail(_ task: DkxTask) -> String? {
    var parts: [String] = []
    if task.remind != .none && !task.done {
        parts.append("напомнит: " + dkxRemindTitle(task.remind).lowercased())
    }
    let note = task.note.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    if !note.isEmpty {
        parts.append(note.count > 60 ? String(note.prefix(60)) + "…" : note)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

// MARK: - Список

private final class DkxTasksArguments {
    let add: () -> Void
    let open: (Int64) -> Void
    let setMode: (DkxTasksMode) -> Void
    let setDate: (Int32) -> Void
    let toggleDateSelection: () -> Void

    init(add: @escaping () -> Void, open: @escaping (Int64) -> Void, setMode: @escaping (DkxTasksMode) -> Void, setDate: @escaping (Int32) -> Void, toggleDateSelection: @escaping () -> Void) {
        self.add = add
        self.open = open
        self.setMode = setMode
        self.setDate = setDate
        self.toggleDateSelection = toggleDateSelection
    }
}

private enum DkxTasksEntry: ItemListNodeEntry {
    case add
    case modeHeader
    case mode(DkxTasksMode, String, Bool)
    case date(PresentationDateTimeFormat, Int32, Bool)
    case groupHeader(Int32, String)
    case task(Int32, DkxTask)
    case empty(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .add:
            return 0
        case .modeHeader, .mode, .date:
            return 1
        case let .groupHeader(group, _):
            return 10 + group
        case let .task(order, _):
            return 10 + (order >> 16)
        case .empty:
            return 2
        case .footer:
            return 100000
        }
    }

    // Порядок: секция в старших битах, место внутри неё в младших
    var stableId: Int32 {
        switch self {
        case .add:
            return 0
        case .modeHeader:
            return 1
        case let .mode(mode, _, _):
            return 2 + mode.rawValue
        case .date:
            return 9
        case .empty:
            return 20
        case let .groupHeader(group, _):
            return (group + 1) << 16
        case let .task(order, _):
            return ((order >> 16) + 1) << 16 | ((order & 0xFFFF) + 1)
        case .footer:
            return Int32.max
        }
    }

    static func <(lhs: DkxTasksEntry, rhs: DkxTasksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxTasksArguments
        switch self {
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Новое дело", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case .modeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ВИД", sectionId: self.section)
        case let .mode(mode, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setMode(mode)
            })
        case let .date(dateTimeFormat, date, displayingDateSelection):
            return ItemListDatePickerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: dateTimeFormat, date: date, title: "Дата", displayingDateSelection: displayingDateSelection, displayingTimeSelection: false, sectionId: self.section, style: .blocks, toggleDateSelection: {
                arguments.toggleDateSelection()
            }, toggleTimeSelection: nil, updated: { value in
                arguments.setDate(value)
            })
        case let .groupHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .task(_, task):
            let label = task.done ? "✓ " + dkxTimeLabel(task) : dkxTimeLabel(task)
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: task.title, titleColor: task.done ? .accent : .primary, label: label, additionalDetailLabel: dkxTaskDetail(task), sectionId: self.section, style: .blocks, action: {
                arguments.open(task.id)
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct DkxTasksState: Equatable {
    var mode: DkxTasksMode = .day
    var date: Int32 = Int32(Date().timeIntervalSince1970)
    var displayingDateSelection = false
    var visibleCount = dkxTasksPageSize
}

private func dkxTasksEntries(tasks: DkxTasks, state: DkxTasksState, presentationData: PresentationData) -> [DkxTasksEntry] {
    var entries: [DkxTasksEntry] = [.add, .modeHeader]
    for (mode, title) in dkxTasksModes {
        entries.append(.mode(mode, title, mode == state.mode))
    }
    if state.mode != .all {
        entries.append(.date(presentationData.dateTimeFormat, state.date, state.displayingDateSelection))
    }

    let todayStart = Int32(dkxStartOfDay(Date()).timeIntervalSince1970)
    var groups: [(String, [DkxTask])] = []

    if case let (start, end)? = dkxPeriod(mode: state.mode, around: Date(timeIntervalSince1970: Double(state.date))) {
        // Просроченные показываем всегда, пока их не закрыли
        let overdue = tasks.items.filter { !$0.done && $0.date != 0 && $0.date < todayStart && $0.date < start }.sorted(by: { $0.date < $1.date })
        if !overdue.isEmpty {
            groups.append(("ПРОСРОЧЕНО", overdue))
        }
        let inPeriod = tasks.items.filter { $0.date >= start && $0.date < end }.sorted(by: { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.createdAt < rhs.createdAt
        })
        var byDay: [(Int32, [DkxTask])] = []
        for task in inPeriod where !task.done {
            let day = Int32(dkxStartOfDay(Date(timeIntervalSince1970: Double(task.date))).timeIntervalSince1970)
            if let index = byDay.firstIndex(where: { $0.0 == day }) {
                byDay[index].1.append(task)
            } else {
                byDay.append((day, [task]))
            }
        }
        for (day, items) in byDay {
            groups.append((dkxDayTitle(day), items))
        }
        let done = inPeriod.filter { $0.done }
        if !done.isEmpty {
            groups.append(("ВЫПОЛНЕНО: \(done.count)", done))
        }
        if byDay.isEmpty && overdue.isEmpty {
            entries.append(.empty(done.isEmpty ? "На этот период дел нет." : "Все дела на этот период выполнены."))
        }
    } else {
        // Все незавершённые: сначала с датой по порядку, потом без даты
        let open = tasks.items.filter { !$0.done }.sorted(by: { lhs, rhs in
            if (lhs.date == 0) != (rhs.date == 0) {
                return lhs.date != 0
            }
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.createdAt < rhs.createdAt
        })
        if open.isEmpty {
            entries.append(.empty("Незавершённых дел нет."))
        } else {
            let visible = Array(open.prefix(state.visibleCount))
            groups.append(("НЕЗАВЕРШЁННЫЕ: \(open.count)", visible))
        }
    }

    for (groupIndex, group) in groups.enumerated() {
        let groupId = Int32(groupIndex)
        entries.append(.groupHeader(groupId, group.0))
        for (itemIndex, task) in group.1.enumerated() {
            entries.append(.task((groupId << 16) | Int32(min(itemIndex, 0xFFFE)), task))
        }
    }

    entries.append(.footer("Завершить, изменить или удалить дело можно, открыв его. Напоминания приходят обычным уведомлением телефона."))
    return entries
}

public func dkxTasksController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(DkxTasksState(), ignoreRepeated: true)
    let stateValue = Atomic(value: DkxTasksState())
    let updateState: ((DkxTasksState) -> DkxTasksState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var pushControllerImpl: ((ViewController) -> Void)?
    let accountManager = context.sharedContext.accountManager
    let currentTasks = Atomic<DkxTasks>(value: DkxTasks.defaultValue)

    let arguments = DkxTasksArguments(add: {
        let date = stateValue.with { $0 }.date
        pushControllerImpl?(dkxTaskEditController(context: context, task: nil, suggestedDate: date))
    }, open: { id in
        guard let task = currentTasks.with({ $0 }).items.first(where: { $0.id == id }) else {
            return
        }
        pushControllerImpl?(dkxTaskEditController(context: context, task: task, suggestedDate: task.date))
    }, setMode: { mode in
        updateState { current in
            var updated = current
            updated.mode = mode
            updated.visibleCount = dkxTasksPageSize
            return updated
        }
    }, setDate: { value in
        updateState { current in
            var updated = current
            updated.date = value
            return updated
        }
    }, toggleDateSelection: {
        updateState { current in
            var updated = current
            updated.displayingDateSelection = !updated.displayingDateSelection
            return updated
        }
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get(),
        dkxTasksSignal(accountManager: accountManager)
    )
    |> map { presentationData, state, tasks -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let _ = currentTasks.swap(tasks)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Мои дела"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxTasksEntries(tasks: tasks, state: state, presentationData: presentationData), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    // Подгрузка при прокрутке в режиме «Все»: у низа списка показываем
    // следующую порцию
    controller.visibleBottomContentOffsetChanged = { offset in
        guard case let .known(value) = offset, value < 200.0 else {
            return
        }
        let state = stateValue.with { $0 }
        guard state.mode == .all else {
            return
        }
        let openCount = currentTasks.with { $0 }.items.filter { !$0.done }.count
        if state.visibleCount < openCount {
            updateState { current in
                var updated = current
                updated.visibleCount += dkxTasksPageSize
                return updated
            }
        }
    }
    return controller
}

// MARK: - Редактор

private final class DkxTaskEditArguments {
    let updateTitle: (String) -> Void
    let updateNote: (String) -> Void
    let updateDate: (Int32) -> Void
    let toggleDateSelection: () -> Void
    let toggleTimeSelection: () -> Void
    let updateAllDay: (Bool) -> Void
    let updateRemind: (DkxTask.Remind) -> Void
    let complete: () -> Void
    let reopen: () -> Void
    let delete: () -> Void

    init(updateTitle: @escaping (String) -> Void, updateNote: @escaping (String) -> Void, updateDate: @escaping (Int32) -> Void, toggleDateSelection: @escaping () -> Void, toggleTimeSelection: @escaping () -> Void, updateAllDay: @escaping (Bool) -> Void, updateRemind: @escaping (DkxTask.Remind) -> Void, complete: @escaping () -> Void, reopen: @escaping () -> Void, delete: @escaping () -> Void) {
        self.updateTitle = updateTitle
        self.updateNote = updateNote
        self.updateDate = updateDate
        self.toggleDateSelection = toggleDateSelection
        self.toggleTimeSelection = toggleTimeSelection
        self.updateAllDay = updateAllDay
        self.updateRemind = updateRemind
        self.complete = complete
        self.reopen = reopen
        self.delete = delete
    }
}

private let dkxRemindOptions: [DkxTask.Remind] = [.none, .atTime, .hourBefore, .twoHoursBefore, .dayBefore]

private enum DkxTaskEditEntry: ItemListNodeEntry {
    case title(String)
    case note(String)
    case whenHeader
    case allDay(Bool)
    case date(PresentationDateTimeFormat, Int32, Bool, Bool, Bool)
    case remindHeader
    case remind(Int32, String, Bool)
    case complete
    case reopen
    case delete

    var section: ItemListSectionId {
        switch self {
        case .title, .note:
            return 0
        case .whenHeader, .allDay, .date:
            return 1
        case .remindHeader, .remind:
            return 2
        case .complete, .reopen:
            return 3
        case .delete:
            return 4
        }
    }

    var stableId: Int32 {
        switch self {
        case .title:
            return 0
        case .note:
            return 1
        case .whenHeader:
            return 10
        case .allDay:
            return 11
        case .date:
            return 12
        case .remindHeader:
            return 20
        case let .remind(index, _, _):
            return 21 + index
        case .complete:
            return 40
        case .reopen:
            return 41
        case .delete:
            return 50
        }
    }

    static func <(lhs: DkxTaskEditEntry, rhs: DkxTaskEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxTaskEditArguments
        switch self {
        case let .title(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: "Что сделать", type: .regular(capitalization: true, autocorrection: true), sectionId: self.section, textUpdated: { value in
                arguments.updateTitle(value)
            }, action: {})
        case let .note(text):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Заметка, необязательно", maxLength: nil, sectionId: self.section, style: .blocks, minimalHeight: 60.0, textUpdated: { value in
                arguments.updateNote(value)
            })
        case .whenHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "КОГДА", sectionId: self.section)
        case let .allDay(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Весь день", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAllDay(value)
            })
        case let .date(dateTimeFormat, date, hasTime, displayingDate, displayingTime):
            // У дела на весь день выбора времени нет
            var toggleTime: (() -> Void)?
            if hasTime {
                toggleTime = {
                    arguments.toggleTimeSelection()
                }
            }
            return ItemListDatePickerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: dateTimeFormat, date: date, title: hasTime ? "Дата и время" : "Дата", displayingDateSelection: displayingDate, displayingTimeSelection: displayingTime, sectionId: self.section, style: .blocks, toggleDateSelection: {
                arguments.toggleDateSelection()
            }, toggleTimeSelection: toggleTime, updated: { value in
                arguments.updateDate(value)
            })
        case .remindHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "НАПОМНИТЬ", sectionId: self.section)
        case let .remind(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateRemind(dkxRemindOptions[Int(index)])
            })
        case .complete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Завершить дело", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.complete()
            })
        case .reopen:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Вернуть в работу", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reopen()
            })
        case .delete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Удалить дело", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.delete()
            })
        }
    }
}

private struct DkxTaskEditState: Equatable {
    var task: DkxTask
    var displayingDateSelection = false
    var displayingTimeSelection = false
}

// task равен nil для нового дела
private func dkxTaskEditController(context: AccountContext, task: DkxTask?, suggestedDate: Int32) -> ViewController {
    let isNew = task == nil
    let now = Int32(Date().timeIntervalSince1970)
    // Новое дело по умолчанию на ближайший целый час выбранного дня
    let initialTask: DkxTask
    if let task = task {
        initialTask = task
    } else {
        let base = Date(timeIntervalSince1970: Double(suggestedDate))
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        let nowComponents = calendar.dateComponents([.hour], from: Date())
        components.hour = min(23, (nowComponents.hour ?? 9) + 1)
        components.minute = 0
        let date = calendar.date(from: components) ?? base
        initialTask = DkxTask(id: DkxTask.newId(), title: "", note: "", date: Int32(date.timeIntervalSince1970), hasTime: true, remind: .atTime, done: false, doneAt: 0, createdAt: now)
    }

    let statePromise = ValuePromise(DkxTaskEditState(task: initialTask), ignoreRepeated: true)
    let stateValue = Atomic(value: DkxTaskEditState(task: initialTask))
    let updateState: ((DkxTaskEditState) -> DkxTaskEditState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    let updateTask: (@escaping (inout DkxTask) -> Void) -> Void = { f in
        updateState { current in
            var updated = current
            f(&updated.task)
            return updated
        }
    }

    var dismissImpl: (() -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    let accountManager = context.sharedContext.accountManager

    let store: (DkxTask) -> Void = { task in
        let _ = updateDkxTasksInteractively(accountManager: accountManager, { current in
            var updated = current
            if let index = updated.items.firstIndex(where: { $0.id == task.id }) {
                updated.items[index] = task
            } else {
                updated.items.append(task)
            }
            return updated
        }).start()
    }

    let arguments = DkxTaskEditArguments(updateTitle: { value in
        updateTask { $0.title = value }
    }, updateNote: { value in
        updateTask { $0.note = value }
    }, updateDate: { value in
        updateTask { task in
            if task.hasTime {
                task.date = value
            } else {
                task.date = Int32(dkxStartOfDay(Date(timeIntervalSince1970: Double(value))).timeIntervalSince1970)
            }
        }
    }, toggleDateSelection: {
        updateState { current in
            var updated = current
            updated.displayingDateSelection = !updated.displayingDateSelection
            if updated.displayingDateSelection {
                updated.displayingTimeSelection = false
            }
            return updated
        }
    }, toggleTimeSelection: {
        updateState { current in
            var updated = current
            updated.displayingTimeSelection = !updated.displayingTimeSelection
            if updated.displayingTimeSelection {
                updated.displayingDateSelection = false
            }
            return updated
        }
    }, updateAllDay: { value in
        updateTask { task in
            task.hasTime = !value
            if value {
                task.date = Int32(dkxStartOfDay(Date(timeIntervalSince1970: Double(task.date))).timeIntervalSince1970)
            } else {
                task.date += 9 * 3600
            }
        }
    }, updateRemind: { value in
        updateTask { $0.remind = value }
    }, complete: {
        // Подтверждение перед завершением, как просил владелец
        let title = stateValue.with { $0 }.task.title
        presentControllerImpl?(textAlertController(context: context, title: "Завершить дело?", text: title, actions: [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .defaultAction, title: "Завершить", action: {
                var task = stateValue.with { $0 }.task
                task.done = true
                task.doneAt = Int32(Date().timeIntervalSince1970)
                store(task)
                dismissImpl?()
            })
        ]))
    }, reopen: {
        var task = stateValue.with { $0 }.task
        task.done = false
        task.doneAt = 0
        store(task)
        dismissImpl?()
    }, delete: {
        let title = stateValue.with { $0 }.task.title
        presentControllerImpl?(textAlertController(context: context, title: "Удалить дело?", text: title, actions: [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                let id = stateValue.with { $0 }.task.id
                let _ = updateDkxTasksInteractively(accountManager: accountManager, { current in
                    var updated = current
                    updated.items.removeAll(where: { $0.id == id })
                    return updated
                }).start()
                dismissImpl?()
            })
        ]))
    })

    // Поля ввода рисуются из начальных значений, иначе каждая клавиша
    // перерисовывала бы ячейку и курсор прыгал бы в конец
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxTaskEditEntry] = [.title(initialTask.title), .note(initialTask.note), .whenHeader, .allDay(!state.task.hasTime), .date(presentationData.dateTimeFormat, state.task.date, state.task.hasTime, state.displayingDateSelection, state.displayingTimeSelection), .remindHeader]
        for (index, option) in dkxRemindOptions.enumerated() {
            entries.append(.remind(Int32(index), dkxRemindTitle(option), option == state.task.remind))
        }
        if !isNew {
            entries.append(state.task.done ? .reopen : .complete)
            entries.append(.delete)
        }

        let canSave = !state.task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rightButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: canSave, action: {
            var task = stateValue.with { $0 }.task
            task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            task.note = task.note.trimmingCharacters(in: .whitespacesAndNewlines)
            store(task)
            dismissImpl?()
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isNew ? "Новое дело" : "Дело"), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
