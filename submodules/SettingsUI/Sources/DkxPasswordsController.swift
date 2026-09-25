import Foundation
import UIKit
import Security
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI

// «Пароли». Записи хранятся в системной Keychain, по одной на запись,
// только на этом устройстве: без синхронизации в iCloud и без переноса в
// резервную копию на другой телефон. Вход в раздел по Face ID с запасным
// паролем телефона. Скопированное из раздела само стирается из буфера
// обмена через две минуты.
//
// Дизайн выбран владельцем: вариант Б, карточки. Каждая запись в списке
// это отдельный блок с названием, логином, значками заполненных полей и
// кнопками копирования логина и пароля прямо из списка.

// MARK: - Хранилище

struct DkxPasswordEntry: Codable, Equatable {
    var id: String
    var title: String
    var url: String
    var login: String
    var password: String
    var email: String
    var phone: String
    var note: String
    var updatedAt: Int32

    static func empty() -> DkxPasswordEntry {
        return DkxPasswordEntry(id: UUID().uuidString, title: "", url: "", login: "", password: "", email: "", phone: "", note: "", updatedAt: 0)
    }

    var hasAnyField: Bool {
        return ![self.url, self.login, self.password, self.email, self.phone, self.note].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // Что показать, если название не задано
    var displayTitle: String {
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        if let host = URL(string: self.url)?.host, !host.isEmpty {
            return host
        }
        for value in [self.url, self.login, self.email, self.phone] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "Без названия"
    }

    var subtitle: String {
        for value in [self.login, self.email, self.phone, self.url] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    var filledFieldsLabel: String {
        var names: [String] = []
        if !self.url.isEmpty { names.append("ссылка") }
        if !self.login.isEmpty { names.append("логин") }
        if !self.password.isEmpty { names.append("пароль") }
        if !self.email.isEmpty { names.append("почта") }
        if !self.phone.isEmpty { names.append("номер") }
        if !self.note.isEmpty { names.append("заметка") }
        return names.joined(separator: " · ")
    }
}

enum DkxPasswordStore {
    private static let service = "uz.dkx.passwords"

    static func loadAll() -> [DkxPasswordEntry] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                DkxLog.write("пароли", "чтение Keychain, код \(status)")
            }
            return []
        }
        var items: [Data] = []
        if let array = result as? [Data] {
            items = array
        } else if let single = result as? Data {
            items = [single]
        }
        let decoder = JSONDecoder()
        let entries = items.compactMap { try? decoder.decode(DkxPasswordEntry.self, from: $0) }
        return entries.sorted(by: { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending })
    }

    @discardableResult
    static func save(_ entry: DkxPasswordEntry) -> Bool {
        guard let data = try? JSONEncoder().encode(entry) else {
            return false
        }
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: entry.id
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            DkxLog.write("пароли", "запись в Keychain, код \(status)")
        }
        return status == errSecSuccess
    }

    static func delete(id: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: id
        ]
        let status = SecItemDelete(match as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            DkxLog.write("пароли", "удаление из Keychain, код \(status)")
        }
    }
}

// Буфер обмена только на этом устройстве и с самоочисткой
private func dkxCopySecret(_ value: String) {
    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true, .expirationDate: Date(timeIntervalSinceNow: 120.0)])
}

// Сигнал списка: хранилище синхронное, а экраны должны обновляться после
// правок, поэтому держим версию и перечитываем по ней
private let dkxPasswordsVersion = ValuePromise<Int>(0, ignoreRepeated: false)
private let dkxPasswordsVersionValue = Atomic<Int>(value: 0)

private func dkxPasswordsChanged() {
    dkxPasswordsVersion.set(dkxPasswordsVersionValue.modify { $0 + 1 })
}

private func dkxPasswordsSignal() -> Signal<[DkxPasswordEntry], NoError> {
    return dkxPasswordsVersion.get()
    |> map { _ -> [DkxPasswordEntry] in
        return DkxPasswordStore.loadAll()
    }
}

// MARK: - Вход в раздел

// Открывает раздел после Face ID. Вызывается снаружи с функцией показа
// экрана, чтобы проверка шла до того, как список попадёт на экран.
public func dkxOpenPasswords(context: AccountContext, push: @escaping (ViewController) -> Void) {
    let _ = (DkxChatLock.authenticate(reason: "Открыть пароли")
    |> deliverOnMainQueue).start(next: { success in
        if success {
            push(dkxPasswordsController(context: context))
        } else {
            DkxLog.write("пароли", "проверка не прошла, раздел не открыт")
        }
    })
}

// MARK: - Список

private let dkxPasswordsPageSize = 30

private final class DkxPasswordsArguments {
    let add: () -> Void
    let open: (String) -> Void
    let copyLogin: (String) -> Void
    let copyPassword: (String) -> Void

    init(add: @escaping () -> Void, open: @escaping (String) -> Void, copyLogin: @escaping (String) -> Void, copyPassword: @escaping (String) -> Void) {
        self.add = add
        self.open = open
        self.copyLogin = copyLogin
        self.copyPassword = copyPassword
    }
}

private enum DkxPasswordsEntry: ItemListNodeEntry {
    case add
    case empty
    case card(index: Int32, DkxPasswordEntry)
    case copyLogin(index: Int32, String)
    case copyPassword(index: Int32, String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .add:
            return 0
        case .empty:
            return 1
        case let .card(index, _), let .copyLogin(index, _), let .copyPassword(index, _):
            return 2 + index
        case .footer:
            return Int32.max
        }
    }

    var stableId: Int32 {
        switch self {
        case .add:
            return 0
        case .empty:
            return 1
        case let .card(index, _):
            return 10 + index * 4
        case let .copyLogin(index, _):
            return 10 + index * 4 + 1
        case let .copyPassword(index, _):
            return 10 + index * 4 + 2
        case .footer:
            return Int32.max
        }
    }

    static func <(lhs: DkxPasswordsEntry, rhs: DkxPasswordsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxPasswordsArguments
        switch self {
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Новая запись", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Записей пока нет. Все поля необязательны, но хотя бы одно нужно заполнить."), sectionId: self.section)
        case let .card(_, entry):
            let detail = entry.filledFieldsLabel
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: entry.displayTitle, label: "", additionalDetailLabel: [entry.subtitle, detail].filter { !$0.isEmpty }.joined(separator: "\n"), sectionId: self.section, style: .blocks, action: {
                arguments.open(entry.id)
            })
        case let .copyLogin(_, id):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Скопировать логин", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.copyLogin(id)
            })
        case let .copyPassword(_, id):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Скопировать пароль", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.copyPassword(id)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func dkxPasswordsController(context: AccountContext) -> ViewController {
    let visibleCountValue = Atomic<Int>(value: dkxPasswordsPageSize)
    let visibleCountPromise = ValuePromise<Int>(dkxPasswordsPageSize, ignoreRepeated: true)
    let currentEntries = Atomic<[DkxPasswordEntry]>(value: [])

    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let showCopied: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .copy(text: text), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
    }

    let arguments = DkxPasswordsArguments(add: {
        pushControllerImpl?(dkxPasswordEditController(context: context, entry: nil))
    }, open: { id in
        guard let entry = currentEntries.with({ $0 }).first(where: { $0.id == id }) else {
            return
        }
        pushControllerImpl?(dkxPasswordDetailsController(context: context, entryId: entry.id))
    }, copyLogin: { id in
        guard let entry = currentEntries.with({ $0 }).first(where: { $0.id == id }) else {
            return
        }
        let value = !entry.login.isEmpty ? entry.login : entry.email
        dkxCopySecret(value)
        showCopied("Логин скопирован")
    }, copyPassword: { id in
        guard let entry = currentEntries.with({ $0 }).first(where: { $0.id == id }) else {
            return
        }
        dkxCopySecret(entry.password)
        showCopied("Пароль скопирован, буфер очистится через 2 минуты")
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        dkxPasswordsSignal(),
        visibleCountPromise.get()
    )
    |> map { presentationData, entries, visibleCount -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let _ = currentEntries.swap(entries)
        var items: [DkxPasswordsEntry] = [.add]
        if entries.isEmpty {
            items.append(.empty)
        }
        for (index, entry) in entries.prefix(visibleCount).enumerated() {
            let i = Int32(index)
            items.append(.card(index: i, entry))
            if !entry.login.isEmpty || !entry.email.isEmpty {
                items.append(.copyLogin(index: i, entry.id))
            }
            if !entry.password.isEmpty {
                items.append(.copyPassword(index: i, entry.id))
            }
        }
        if !entries.isEmpty {
            items.append(.footer("Записей: \(entries.count). Хранятся в Keychain только на этом телефоне и не уходят ни на сервер Telegram, ни в iCloud."))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Пароли"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: items, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .current)
    }
    // Подгрузка порциями при прокрутке к низу
    controller.visibleBottomContentOffsetChanged = { offset in
        guard case let .known(value) = offset, value < 200.0 else {
            return
        }
        let total = currentEntries.with { $0 }.count
        let visible = visibleCountValue.with { $0 }
        if visible < total {
            let updated = visibleCountValue.modify { $0 + dkxPasswordsPageSize }
            visibleCountPromise.set(updated)
        }
    }
    return controller
}

// MARK: - Карточка записи

private final class DkxPasswordDetailsArguments {
    let copy: (String, String) -> Void
    let toggleReveal: () -> Void
    let openUrl: (String) -> Void
    let delete: () -> Void

    init(copy: @escaping (String, String) -> Void, toggleReveal: @escaping () -> Void, openUrl: @escaping (String) -> Void, delete: @escaping () -> Void) {
        self.copy = copy
        self.toggleReveal = toggleReveal
        self.openUrl = openUrl
        self.delete = delete
    }
}

private enum DkxPasswordDetailsEntry: ItemListNodeEntry {
    case field(index: Int32, title: String, value: String, copyName: String)
    case passwordField(shown: String)
    case reveal(Bool)
    case openUrl(String)
    case noteHeader
    case note(String)
    case updated(String)
    case delete

    var section: ItemListSectionId {
        switch self {
        case .field, .passwordField, .reveal:
            return 0
        case .openUrl:
            return 1
        case .noteHeader, .note:
            return 2
        case .updated:
            return 3
        case .delete:
            return 4
        }
    }

    var stableId: Int32 {
        switch self {
        case let .field(index, _, _, _):
            return index
        case .passwordField:
            return 20
        case .reveal:
            return 21
        case .openUrl:
            return 30
        case .noteHeader:
            return 40
        case .note:
            return 41
        case .updated:
            return 50
        case .delete:
            return 60
        }
    }

    static func <(lhs: DkxPasswordDetailsEntry, rhs: DkxPasswordDetailsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxPasswordDetailsArguments
        switch self {
        case let .field(_, title, value, copyName):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.copy(value, copyName)
            })
        case let .passwordField(shown):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Пароль", label: shown, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.copy("", "Пароль")
            })
        case let .reveal(revealed):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: revealed ? "Скрыть пароль" : "Показать пароль", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.toggleReveal()
            })
        case let .openUrl(url):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Открыть ссылку", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openUrl(url)
            })
        case .noteHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗАМЕТКА", sectionId: self.section)
        case let .note(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .updated(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .delete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Удалить запись", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.delete()
            })
        }
    }
}

private func dkxPasswordDetailsController(context: AccountContext, entryId: String) -> ViewController {
    let revealedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    let revealedValue = Atomic<Bool>(value: false)
    let currentEntry = Atomic<DkxPasswordEntry?>(value: nil)

    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController, Bool) -> Void)?
    var dismissImpl: (() -> Void)?

    let arguments = DkxPasswordDetailsArguments(copy: { value, name in
        var text = value
        if name == "Пароль" {
            text = currentEntry.with { $0 }?.password ?? ""
        }
        if text.isEmpty {
            return
        }
        dkxCopySecret(text)
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let toast = name == "Пароль" ? "Пароль скопирован, буфер очистится через 2 минуты" : "\(name): скопировано"
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .copy(text: toast), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), false)
    }, toggleReveal: {
        revealedPromise.set(revealedValue.modify { !$0 })
    }, openUrl: { url in
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") {
            value = "https://" + value
        }
        if let parsed = URL(string: value) {
            context.sharedContext.applicationBindings.openUrl(parsed.absoluteString)
        }
    }, delete: {
        let title = currentEntry.with { $0 }?.displayTitle ?? ""
        presentControllerImpl?(textAlertController(context: context, title: "Удалить запись?", text: title, actions: [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                DkxPasswordStore.delete(id: entryId)
                dkxPasswordsChanged()
                dismissImpl?()
            })
        ]), true)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        dkxPasswordsSignal(),
        revealedPromise.get()
    )
    |> map { presentationData, entries, revealed -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entry = entries.first(where: { $0.id == entryId })
        let _ = currentEntry.swap(entry)
        var items: [DkxPasswordDetailsEntry] = []
        if let entry = entry {
            let fields: [(String, String)] = [("Ссылка", entry.url), ("Логин", entry.login), ("Почта", entry.email), ("Номер", entry.phone)]
            for (index, field) in fields.enumerated() where !field.1.isEmpty {
                items.append(.field(index: Int32(index), title: field.0, value: field.1, copyName: field.0))
            }
            if !entry.password.isEmpty {
                items.append(.passwordField(shown: revealed ? entry.password : String(repeating: "•", count: 12)))
                items.append(.reveal(revealed))
            }
            if !entry.url.isEmpty {
                items.append(.openUrl(entry.url))
            }
            if !entry.note.isEmpty {
                items.append(.noteHeader)
                items.append(.note(entry.note))
            }
            if entry.updatedAt > 0 {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ru_RU")
                formatter.dateFormat = "d MMMM yyyy, HH:mm"
                items.append(.updated("Изменено " + formatter.string(from: Date(timeIntervalSince1970: Double(entry.updatedAt))) + ". Нажатие на поле копирует его."))
            }
            items.append(.delete)
        }
        let title = entry?.displayTitle ?? "Запись"
        let rightButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Edit), style: .regular, enabled: entry != nil, action: {
            if let entry = currentEntry.with({ $0 }) {
                pushControllerImpl?(dkxPasswordEditController(context: context, entry: entry))
            }
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: items, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentControllerImpl = { [weak controller] c, isAlert in
        controller?.present(c, in: isAlert ? .window(.root) : .current)
    }
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}

// MARK: - Редактор

private enum DkxPasswordField: Int32 {
    case title
    case url
    case login
    case password
    case email
    case phone
}

private final class DkxPasswordEditArguments {
    let update: (DkxPasswordField, String) -> Void
    let updateNote: (String) -> Void

    init(update: @escaping (DkxPasswordField, String) -> Void, updateNote: @escaping (String) -> Void) {
        self.update = update
        self.updateNote = updateNote
    }
}

private enum DkxPasswordEditEntry: ItemListNodeEntry {
    case titleHeader
    case input(DkxPasswordField, String, String)
    case fieldsHeader
    case noteHeader
    case note(String)
    case hint(String)

    var section: ItemListSectionId {
        switch self {
        case .titleHeader:
            return 0
        case let .input(field, _, _):
            return field == .title ? 0 : 1
        case .fieldsHeader:
            return 1
        case .noteHeader, .note:
            return 2
        case .hint:
            return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .titleHeader:
            return 0
        case let .input(field, _, _):
            return field == .title ? 1 : 10 + field.rawValue
        case .fieldsHeader:
            return 9
        case .noteHeader:
            return 30
        case .note:
            return 31
        case .hint:
            return 40
        }
    }

    static func <(lhs: DkxPasswordEditEntry, rhs: DkxPasswordEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxPasswordEditArguments
        switch self {
        case .titleHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "НАЗВАНИЕ", sectionId: self.section)
        case let .input(field, text, placeholder):
            let type: ItemListSingleLineInputItemType
            switch field {
            case .title:
                type = .regular(capitalization: true, autocorrection: false)
            case .url:
                type = .regular(capitalization: false, autocorrection: false)
            case .login:
                type = .username
            case .password:
                type = .password
            case .email:
                type = .email
            case .phone:
                type = .number
            }
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: type, clearType: .onFocus, sectionId: self.section, textUpdated: { value in
                arguments.update(field, value)
            }, action: {})
        case .fieldsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ПОЛЯ, ВСЕ НЕОБЯЗАТЕЛЬНЫ", sectionId: self.section)
        case .noteHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗАМЕТКА", sectionId: self.section)
        case let .note(text):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Необязательно", maxLength: nil, sectionId: self.section, style: .blocks, minimalHeight: 60.0, textUpdated: { value in
                arguments.updateNote(value)
            })
        case let .hint(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

// entry равен nil для новой записи
private func dkxPasswordEditController(context: AccountContext, entry: DkxPasswordEntry?) -> ViewController {
    let isNew = entry == nil
    let initial = entry ?? DkxPasswordEntry.empty()
    let entryValue = Atomic<DkxPasswordEntry>(value: initial)
    let entryPromise = ValuePromise<DkxPasswordEntry>(initial, ignoreRepeated: true)
    var dismissImpl: (() -> Void)?

    let arguments = DkxPasswordEditArguments(update: { field, value in
        entryPromise.set(entryValue.modify { current in
            var updated = current
            switch field {
            case .title:
                updated.title = value
            case .url:
                updated.url = value
            case .login:
                updated.login = value
            case .password:
                updated.password = value
            case .email:
                updated.email = value
            case .phone:
                updated.phone = value
            }
            return updated
        })
    }, updateNote: { value in
        entryPromise.set(entryValue.modify { current in
            var updated = current
            updated.note = value
            return updated
        })
    })

    // Поля рисуются из начальных значений, иначе курсор прыгал бы в конец
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        entryPromise.get()
    )
    |> map { presentationData, current -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var items: [DkxPasswordEditEntry] = [
            .titleHeader,
            .input(.title, initial.title, "Например, Cloudflare"),
            .fieldsHeader,
            .input(.url, initial.url, "Ссылка"),
            .input(.login, initial.login, "Логин"),
            .input(.password, initial.password, "Пароль"),
            .input(.email, initial.email, "Почта"),
            .input(.phone, initial.phone, "Номер"),
            .noteHeader,
            .note(initial.note)
        ]
        let canSave = current.hasAnyField
        items.append(.hint(canSave ? "Запись хранится в Keychain только на этом телефоне." : "Заполните хотя бы одно поле, иначе сохранять нечего."))

        let rightButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: canSave, action: {
            var value = entryValue.with { $0 }
            value.updatedAt = Int32(Date().timeIntervalSince1970)
            if DkxPasswordStore.save(value) {
                dkxPasswordsChanged()
                dismissImpl?()
            }
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isNew ? "Новая запись" : "Изменить"), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: items, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}
