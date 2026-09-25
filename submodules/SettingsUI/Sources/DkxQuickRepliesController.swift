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

// Шаблоны быстрых ответов: список и редактор одного шаблона. Сами шаблоны
// лежат в DkxSettings.quickReplyTemplates, вставляются кнопкой в поле ввода
// чата. Хранятся только на устройстве.

private let dkxQuickReplyMaxLength: Int32 = 4096

// MARK: - Список

private final class DkxQuickRepliesArguments {
    let add: () -> Void
    let edit: (Int) -> Void

    init(add: @escaping () -> Void, edit: @escaping (Int) -> Void) {
        self.add = add
        self.edit = edit
    }
}

private enum DkxQuickRepliesEntry: ItemListNodeEntry {
    case add
    case header(String)
    case template(index: Int32, preview: String)
    case footer

    var section: ItemListSectionId {
        switch self {
        case .add:
            return 0
        case .header, .template, .footer:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .add:
            return 0
        case .header:
            return 1
        case let .template(index, _):
            return 2 + index
        case .footer:
            return Int32.max
        }
    }

    static func <(lhs: DkxQuickRepliesEntry, rhs: DkxQuickRepliesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxQuickRepliesArguments
        switch self {
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Добавить шаблон", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .template(index, preview):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: preview, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.edit(Int(index))
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain("В чате шаблоны открываются кнопкой в поле ввода, рядом со стикерами. Выбранный текст вставляется туда, где стоит курсор, и его можно дописать перед отправкой. Порядок в меню тот же, что здесь."), sectionId: self.section)
        }
    }
}

private func dkxTemplatePreview(_ text: String) -> String {
    let line = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    return line.count > 60 ? String(line.prefix(60)) + "…" : line
}

public func dkxQuickRepliesController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = DkxQuickRepliesArguments(add: {
        pushControllerImpl?(dkxQuickReplyEditController(context: context, index: nil, initialText: ""))
    }, edit: { index in
        let templates = DkxRuntime.current.quickReplyTemplates
        guard index < templates.count else {
            return
        }
        pushControllerImpl?(dkxQuickReplyEditController(context: context, index: index, initialText: templates[index]))
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
    )
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings
        var entries: [DkxQuickRepliesEntry] = [.add]
        if !settings.quickReplyTemplates.isEmpty {
            entries.append(.header("ШАБЛОНЫ: \(settings.quickReplyTemplates.count)"))
            for (index, text) in settings.quickReplyTemplates.enumerated() {
                entries.append(.template(index: Int32(index), preview: dkxTemplatePreview(text)))
            }
        }
        entries.append(.footer)

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Шаблоны"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Редактор одного шаблона

private final class DkxQuickReplyEditArguments {
    let updateText: (String) -> Void
    let delete: () -> Void

    init(updateText: @escaping (String) -> Void, delete: @escaping () -> Void) {
        self.updateText = updateText
        self.delete = delete
    }
}

private enum DkxQuickReplyEditEntry: ItemListNodeEntry {
    case text(String)
    case info
    case delete

    var section: ItemListSectionId {
        switch self {
        case .text, .info:
            return 0
        case .delete:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .text:
            return 0
        case .info:
            return 1
        case .delete:
            return 2
        }
    }

    static func <(lhs: DkxQuickReplyEditEntry, rhs: DkxQuickReplyEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxQuickReplyEditArguments
        switch self {
        case let .text(text):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Текст шаблона", maxLength: ItemListMultilineInputItemTextLimit(value: Int(dkxQuickReplyMaxLength), display: false), sectionId: self.section, style: .blocks, minimalHeight: 120.0, textUpdated: { value in
                arguments.updateText(value)
            })
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Можно в несколько строк. Переносы сохранятся."), sectionId: self.section)
        case .delete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Удалить шаблон", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.delete()
            })
        }
    }
}

// index равен nil для нового шаблона
private func dkxQuickReplyEditController(context: AccountContext, index: Int?, initialText: String) -> ViewController {
    let textValue = Atomic<String>(value: initialText)
    let textPromise = ValuePromise<String>(initialText, ignoreRepeated: true)
    var dismissImpl: (() -> Void)?

    let accountManager = context.sharedContext.accountManager

    let save: () -> Void = {
        let text = textValue.with { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
        let _ = updateDkxSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            if text.isEmpty {
                // Пустой шаблон при правке равносилен удалению
                if let index = index, index < updated.quickReplyTemplates.count {
                    updated.quickReplyTemplates.remove(at: index)
                }
            } else if let index = index, index < updated.quickReplyTemplates.count {
                updated.quickReplyTemplates[index] = text
            } else {
                updated.quickReplyTemplates.append(text)
            }
            return updated
        }).start()
        dismissImpl?()
    }

    let arguments = DkxQuickReplyEditArguments(updateText: { value in
        let _ = textValue.swap(value)
        textPromise.set(value)
    }, delete: {
        guard let index = index else {
            dismissImpl?()
            return
        }
        let _ = updateDkxSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            if index < updated.quickReplyTemplates.count {
                updated.quickReplyTemplates.remove(at: index)
            }
            return updated
        }).start()
        dismissImpl?()
    })

    // Поле рисуется из начального текста, а не из текущего: иначе каждая
    // клавиша перерисовывала бы ячейку и курсор прыгал бы в конец
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        textPromise.get()
    )
    |> map { presentationData, text -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxQuickReplyEditEntry] = [.text(initialText), .info]
        if index != nil {
            entries.append(.delete)
        }
        let canSave = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || index != nil
        let rightButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: canSave, action: {
            save()
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(index == nil ? "Новый шаблон" : "Шаблон"), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}
