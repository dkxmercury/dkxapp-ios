import Foundation
import UserNotifications
import TelegramCore
import SwiftSignalKit

// «Мои дела»: задачи с датой, временем и напоминанием. Хранятся отдельным
// ключом, а не в DkxSettings: дел может быть много, а настройки читаются
// целиком при каждой перерисовке экранов.
//
// Напоминания это локальные уведомления системы с идентификатором
// dkx-task-<id>. В userInfo лежит ключ dkxTask, по нему AppDelegate
// отличает их от уведомлений Telegram.

public struct DkxTask: Codable, Equatable {
    public enum Remind: Int32 {
        case none = -1
        case atTime = 0
        case hourBefore = 60
        case twoHoursBefore = 120
        case dayBefore = 1440
    }

    public var id: Int64
    public var title: String
    public var note: String
    // Секунды от 1970. Для дела на весь день это полночь того дня.
    public var date: Int32
    public var hasTime: Bool
    public var remind: Remind
    public var done: Bool
    public var doneAt: Int32
    public var createdAt: Int32

    public init(id: Int64, title: String, note: String, date: Int32, hasTime: Bool, remind: Remind, done: Bool, doneAt: Int32, createdAt: Int32) {
        self.id = id
        self.title = title
        self.note = note
        self.date = date
        self.hasTime = hasTime
        self.remind = remind
        self.done = done
        self.doneAt = doneAt
        self.createdAt = createdAt
    }

    public static func newId() -> Int64 {
        var value: Int64 = 0
        arc4random_buf(&value, MemoryLayout<Int64>.size)
        return value == Int64.min ? 1 : abs(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.id = try container.decode(Int64.self, forKey: "id")
        self.title = (try container.decodeIfPresent(String.self, forKey: "title")) ?? ""
        self.note = (try container.decodeIfPresent(String.self, forKey: "note")) ?? ""
        self.date = (try container.decodeIfPresent(Int32.self, forKey: "date")) ?? 0
        self.hasTime = ((try container.decodeIfPresent(Int32.self, forKey: "hasTime")) ?? 0) != 0
        self.remind = Remind(rawValue: (try container.decodeIfPresent(Int32.self, forKey: "remind")) ?? Remind.none.rawValue) ?? .none
        self.done = ((try container.decodeIfPresent(Int32.self, forKey: "done")) ?? 0) != 0
        self.doneAt = (try container.decodeIfPresent(Int32.self, forKey: "doneAt")) ?? 0
        self.createdAt = (try container.decodeIfPresent(Int32.self, forKey: "createdAt")) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.id, forKey: "id")
        try container.encode(self.title, forKey: "title")
        try container.encode(self.note, forKey: "note")
        try container.encode(self.date, forKey: "date")
        try container.encode((self.hasTime ? 1 : 0) as Int32, forKey: "hasTime")
        try container.encode(self.remind.rawValue, forKey: "remind")
        try container.encode((self.done ? 1 : 0) as Int32, forKey: "done")
        try container.encode(self.doneAt, forKey: "doneAt")
        try container.encode(self.createdAt, forKey: "createdAt")
    }
}

public struct DkxTasks: Codable, Equatable {
    public var items: [DkxTask]

    public static var defaultValue: DkxTasks {
        return DkxTasks(items: [])
    }

    public init(items: [DkxTask]) {
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.items = (try container.decodeIfPresent([DkxTask].self, forKey: "items")) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.items, forKey: "items")
    }
}

public func dkxTasksSignal(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<DkxTasks, NoError> {
    return accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxTasks])
    |> map { sharedData -> DkxTasks in
        return sharedData.entries[ApplicationSpecificSharedDataKeys.dkxTasks]?.get(DkxTasks.self) ?? DkxTasks.defaultValue
    }
    |> distinctUntilChanged
}

// Меняет список и пересобирает напоминания по изменённым делам
public func updateDkxTasksInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (DkxTasks) -> DkxTasks) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> (DkxTasks, DkxTasks) in
        var previous = DkxTasks.defaultValue
        var updated = DkxTasks.defaultValue
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.dkxTasks, { entry in
            previous = entry?.get(DkxTasks.self) ?? DkxTasks.defaultValue
            updated = f(previous)
            return SharedPreferencesEntry(updated)
        })
        return (previous, updated)
    }
    |> map { previous, updated -> Void in
        DkxTaskReminders.sync(previous: previous, updated: updated)
    }
}

public enum DkxTaskReminders {
    public static let userInfoKey = "dkxTask"

    private static func identifier(_ task: DkxTask) -> String {
        return "dkx-task-\(task.id)"
    }

    // Когда сработает напоминание, или nil, если его нет или время прошло
    public static func fireDate(_ task: DkxTask) -> Date? {
        if task.done || task.remind == .none || task.date == 0 {
            return nil
        }
        // Дело на весь день напоминает в 9 утра своего дня
        var base = Double(task.date)
        if !task.hasTime {
            base += 9.0 * 3600.0
        }
        let fire = Date(timeIntervalSince1970: base - Double(task.remind.rawValue) * 60.0)
        if fire.timeIntervalSinceNow <= 0 {
            return nil
        }
        return fire
    }

    static func sync(previous: DkxTasks, updated: DkxTasks) {
        let center = UNUserNotificationCenter.current()
        var previousById: [Int64: DkxTask] = [:]
        for task in previous.items {
            previousById[task.id] = task
        }
        let updatedIds = Set(updated.items.map { $0.id })

        // Удалённые дела: только снять напоминание
        let removed = previous.items.filter { !updatedIds.contains($0.id) }.map { self.identifier($0) }
        if !removed.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: removed)
        }
        // Новые и изменённые: снять старое и поставить заново, если нужно
        for task in updated.items {
            if let old = previousById[task.id], old == task {
                continue
            }
            center.removePendingNotificationRequests(withIdentifiers: [self.identifier(task)])
            guard let fire = self.fireDate(task) else {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = "Мои дела"
            content.body = task.title
            content.sound = .default
            content.userInfo = [self.userInfoKey: String(task.id)]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: self.identifier(task), content: content, trigger: trigger), withCompletionHandler: nil)
        }
        DkxLog.write("дела", "дел \(updated.items.count), напоминания пересобраны")
    }
}
