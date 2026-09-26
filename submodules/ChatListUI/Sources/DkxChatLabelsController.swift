import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI

// MARK: DKX экраны меток на чаты. Список меток в Dkx, редактор метки, выбор
// меток для чата из меню долгого нажатия и список чатов с меткой, куда ведёт
// ряд меток над списком чатов. Хранение в DkxChatLabels.

func dkxChatLabelColor(context: AccountContext, colorId: Int32, theme: PresentationTheme) -> UIColor {
    return context.peerNameColors.getChatFolderTag(PeerNameColor(rawValue: colorId), dark: theme.overallDarkAppearance).main
}

private func dkxChatLabelDot(context: AccountContext, colorId: Int32, theme: PresentationTheme) -> UIImage? {
    return generateFilledCircleImage(diameter: 14.0, color: dkxChatLabelColor(context: context, colorId: colorId, theme: theme))
}

private func dkxSettingsSignal(context: AccountContext) -> Signal<DkxSettings, NoError> {
    return context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
    |> map { sharedData -> DkxSettings in
        return sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings
    }
}

private func dkxUpdateSettings(context: AccountContext, _ f: @escaping (inout DkxSettings) -> Void) {
    let _ = updateDkxSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
        var updated = current
        f(&updated)
        return updated
    }).start()
}

// MARK: - Список меток в Dkx

private final class DkxChatLabelsArguments {
    let context: AccountContext
    let open: (Int32) -> Void
    let add: () -> Void

    init(context: AccountContext, open: @escaping (Int32) -> Void, add: @escaping () -> Void) {
        self.context = context
        self.open = open
        self.add = add
    }
}

private enum DkxChatLabelsEntry: ItemListNodeEntry {
    case header
    case label(index: Int32, label: DkxChatLabel, count: Int32)
    case add
    case footer

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .label(index, _, _):
            return 1 + index
        case .add:
            return 10000
        case .footer:
            return 10001
        }
    }

    static func <(lhs: DkxChatLabelsEntry, rhs: DkxChatLabelsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxChatLabelsArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("МЕТКИ"), sectionId: self.section)
        case let .label(_, label, count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: dkxChatLabelDot(context: arguments.context, colorId: label.colorId, theme: presentationData.theme), title: label.title, label: count == 0 ? "" : "\(count)", sectionId: self.section, style: .blocks, action: {
                arguments.open(label.id)
            })
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Новая метка"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Метка ставится долгим нажатием на чат в списке, пункт «Метки». На одном чате может быть несколько меток, группы тоже подходят. Метки видны под именем чата и рядом над списком чатов, нажатие на метку открывает её чаты. Хранятся только на этом телефоне, собеседники их не видят.")), sectionId: self.section)
        }
    }
}

public func dkxChatLabelsSettingsController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let arguments = DkxChatLabelsArguments(context: context, open: { id in
        pushImpl?(dkxChatLabelEditorController(context: context, labelId: id, assignTo: nil))
    }, add: {
        pushImpl?(dkxChatLabelEditorController(context: context, labelId: nil, assignTo: nil))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, dkxSettingsSignal(context: context))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxChatLabelsEntry] = []
        let labels = settings.chatLabels
        if !labels.isEmpty {
            entries.append(.header)
        }
        for (index, label) in labels.enumerated() {
            entries.append(.label(index: Int32(index), label: label, count: Int32(settings.peers(withChatLabel: label.id).count)))
        }
        entries.append(.add)
        entries.append(.footer)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(DkxStrings.tr("Метки")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Редактор метки

private struct DkxChatLabelEditorState: Equatable {
    var title: String
    var colorId: Int32
}

private final class DkxChatLabelEditorArguments {
    let context: AccountContext
    let updateTitle: (String) -> Void
    let updateColor: (Int32) -> Void
    let move: (Int) -> Void
    let delete: () -> Void

    init(context: AccountContext, updateTitle: @escaping (String) -> Void, updateColor: @escaping (Int32) -> Void, move: @escaping (Int) -> Void, delete: @escaping () -> Void) {
        self.context = context
        self.updateTitle = updateTitle
        self.updateColor = updateColor
        self.move = move
        self.delete = delete
    }
}

private enum DkxChatLabelEditorEntry: ItemListNodeEntry {
    case titleHeader
    case title(String)
    case colorHeader
    case color(index: Int32, colorId: Int32, title: String, checked: Bool)
    case moveUp
    case moveDown
    case delete

    var section: ItemListSectionId {
        switch self {
        case .titleHeader, .title:
            return 0
        case .colorHeader, .color:
            return 1
        case .moveUp, .moveDown:
            return 2
        case .delete:
            return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .titleHeader:
            return 0
        case .title:
            return 1
        case .colorHeader:
            return 2
        case let .color(index, _, _, _):
            return 3 + index
        case .moveUp:
            return 100
        case .moveDown:
            return 101
        case .delete:
            return 102
        }
    }

    static func <(lhs: DkxChatLabelEditorEntry, rhs: DkxChatLabelEditorEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxChatLabelEditorArguments
        switch self {
        case .titleHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("НАЗВАНИЕ"), sectionId: self.section)
        case let .title(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: DkxStrings.tr("Например, ждёт оплату"), type: .regular(capitalization: false, autocorrection: true), sectionId: self.section, textUpdated: { value in
                arguments.updateTitle(value)
            }, action: {})
        case .colorHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ЦВЕТ"), sectionId: self.section)
        case let .color(_, colorId, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: dkxChatLabelDot(context: arguments.context, colorId: colorId, theme: presentationData.theme), title: title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateColor(colorId)
            })
        case .moveUp:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Поднять выше"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.move(-1)
            })
        case .moveDown:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Опустить ниже"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.move(1)
            })
        case .delete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Удалить метку"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.delete()
            })
        }
    }
}

func dkxChatLabelEditorController(context: AccountContext, labelId: Int32?, assignTo: EnginePeer.Id?) -> ViewController {
    let existing = labelId.flatMap { id in DkxRuntime.current.chatLabels.first(where: { $0.id == id }) }
    let usedColors = Set(DkxRuntime.current.chatLabels.map { $0.colorId })
    let freeColor = dkxChatLabelColors.first(where: { !usedColors.contains($0.id) })?.id ?? 5
    let initial = DkxChatLabelEditorState(title: existing?.title ?? "", colorId: existing?.colorId ?? freeColor)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let updateState: ((inout DkxChatLabelEditorState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }

    var dismissImpl: (() -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let arguments = DkxChatLabelEditorArguments(context: context, updateTitle: { value in
        updateState { $0.title = value }
    }, updateColor: { value in
        updateState { $0.colorId = value }
    }, move: { delta in
        guard let labelId else {
            return
        }
        dkxUpdateSettings(context: context, { settings in
            var labels = settings.chatLabels
            guard let index = labels.firstIndex(where: { $0.id == labelId }) else {
                return
            }
            let target = index + delta
            guard target >= 0, target < labels.count else {
                return
            }
            labels.swapAt(index, target)
            settings.setChatLabels(labels)
        })
    }, delete: {
        guard let labelId else {
            return
        }
        let title = stateValue.with { $0.title }
        presentImpl?(textAlertController(context: context, title: DkxStrings.tr("Удалить метку?"), text: DkxStrings.tr("«{}» снимется со всех чатов.", title), actions: [
            TextAlertAction(type: .genericAction, title: DkxStrings.tr("Отмена"), action: {}),
            TextAlertAction(type: .destructiveAction, title: DkxStrings.tr("Удалить"), action: {
                dkxUpdateSettings(context: context, { settings in
                    settings.setChatLabels(settings.chatLabels.filter { $0.id != labelId })
                })
                dismissImpl?()
            })
        ]))
    })

    let save: () -> Void = {
        let state = stateValue.with { $0 }
        let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }
        dkxUpdateSettings(context: context, { settings in
            var labels = settings.chatLabels
            if let labelId, let index = labels.firstIndex(where: { $0.id == labelId }) {
                labels[index].title = title
                labels[index].colorId = state.colorId
                settings.setChatLabels(labels)
            } else {
                let id = settings.nextChatLabelId
                labels.append(DkxChatLabel(id: id, title: title, colorId: state.colorId))
                settings.setChatLabels(labels)
                if let assignTo {
                    settings.setChatLabel(id, peer: assignTo.toInt64(), assigned: true)
                }
            }
        })
        dismissImpl?()
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxChatLabelEditorEntry] = []
        entries.append(.titleHeader)
        entries.append(.title(state.title))
        entries.append(.colorHeader)
        for (index, color) in dkxChatLabelColors.enumerated() {
            entries.append(.color(index: Int32(index), colorId: color.id, title: color.title, checked: color.id == state.colorId))
        }
        if labelId != nil {
            entries.append(.moveUp)
            entries.append(.moveDown)
            entries.append(.delete)
        }
        let canSave = !state.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rightButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: canSave, action: {
            save()
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(labelId == nil ? DkxStrings.tr("Новая метка") : DkxStrings.tr("Метка")), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Метки одного чата, из меню долгого нажатия

private final class DkxChatLabelsPickerArguments {
    let context: AccountContext
    let toggle: (Int32, Bool) -> Void
    let add: () -> Void

    init(context: AccountContext, toggle: @escaping (Int32, Bool) -> Void, add: @escaping () -> Void) {
        self.context = context
        self.toggle = toggle
        self.add = add
    }
}

private enum DkxChatLabelsPickerEntry: ItemListNodeEntry {
    case label(index: Int32, label: DkxChatLabel, checked: Bool)
    case add
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .label(index, _, _):
            return index
        case .add:
            return 10000
        case .footer:
            return 10001
        }
    }

    static func <(lhs: DkxChatLabelsPickerEntry, rhs: DkxChatLabelsPickerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxChatLabelsPickerArguments
        switch self {
        case let .label(_, label, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: dkxChatLabelDot(context: arguments.context, colorId: label.colorId, theme: presentationData.theme), title: label.title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggle(label.id, !checked)
            })
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Новая метка"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func dkxChatLabelsPickerController(context: AccountContext, peerId: EnginePeer.Id, title: String) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let arguments = DkxChatLabelsPickerArguments(context: context, toggle: { labelId, assigned in
        dkxUpdateSettings(context: context, { settings in
            settings.setChatLabel(labelId, peer: peerId.toInt64(), assigned: assigned)
        })
    }, add: {
        pushImpl?(dkxChatLabelEditorController(context: context, labelId: nil, assignTo: peerId))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, dkxSettingsSignal(context: context))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxChatLabelsPickerEntry] = []
        let assigned = settings.chatLabelIds(forPeer: peerId.toInt64())
        let labels = settings.chatLabels
        for (index, label) in labels.enumerated() {
            entries.append(.label(index: Int32(index), label: label, checked: assigned.contains(label.id)))
        }
        entries.append(.add)
        entries.append(.footer(labels.isEmpty ? DkxStrings.tr("Меток пока нет. Создайте первую, она сразу встанет на «{}».", title) : DkxStrings.tr("Отмеченные метки видны под именем «{}» в списке чатов. Цвет и название меняются в Dkx, раздел «Метки».", title)))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(DkxStrings.tr("Метки")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Чаты с меткой, из ряда меток над списком чатов

private struct DkxLabelChatItem: Equatable {
    let peer: EnginePeer
    let preview: String
}

private final class DkxLabelChatsArguments {
    let context: AccountContext
    let openChat: (EnginePeer) -> Void

    init(context: AccountContext, openChat: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.openChat = openChat
    }
}

private enum DkxLabelChatsEntry: ItemListNodeEntry {
    case item(index: Int32, DkxLabelChatItem, title: String)
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .item(index, _, _):
            return index
        case .footer:
            return Int32.max
        }
    }

    static func <(lhs: DkxLabelChatsEntry, rhs: DkxLabelChatsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxLabelChatsArguments
        switch self {
        case let .item(_, item, title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, context: arguments.context, iconPeer: item.peer, title: title, label: "", additionalDetailLabel: item.preview.isEmpty ? nil : item.preview, sectionId: self.section, style: .blocks, action: {
                arguments.openChat(item.peer)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func dkxLabelChatsController(context: AccountContext, labelId: Int32) -> ViewController {
    var navigationControllerImpl: (() -> NavigationController?)?
    let arguments = DkxLabelChatsArguments(context: context, openChat: { peer in
        guard let navigationController = navigationControllerImpl?() else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
    })

    let peerIds: Signal<[EnginePeer.Id], NoError> = dkxSettingsSignal(context: context)
    |> map { settings -> [EnginePeer.Id] in
        return settings.peers(withChatLabel: labelId).map { EnginePeer.Id($0) }
    }
    |> distinctUntilChanged

    // Порядок как в списке чатов, свежие сверху. Кто глубже четырёхсот
    // последних, идёт в конце по имени.
    let items: Signal<[DkxLabelChatItem], NoError> = peerIds
    |> mapToSignal { peerIds -> Signal<[DkxLabelChatItem], NoError> in
        return combineLatest(
            context.engine.data.subscribe(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init))),
            context.account.viewTracker.tailChatListView(groupId: .root, count: 400)
        )
        |> map { peers, viewAndUpdate -> [DkxLabelChatItem] in
            var order: [EnginePeer.Id: Int] = [:]
            var previews: [EnginePeer.Id: String] = [:]
            for (index, entry) in viewAndUpdate.0.entries.reversed().enumerated() {
                guard case let .MessageEntry(entryData) = entry else {
                    continue
                }
                let id = entryData.renderedPeer.peerId
                order[id] = index
                if let message = entryData.messages.max(by: { $0.index < $1.index }) {
                    previews[id] = dkxMessagePreview(message)
                }
            }
            var result: [DkxLabelChatItem] = []
            for peerId in peerIds {
                if let peer = peers[peerId] ?? nil {
                    result.append(DkxLabelChatItem(peer: peer, preview: previews[peerId] ?? ""))
                }
            }
            result.sort(by: { lhs, rhs in
                let l = order[lhs.peer.id] ?? Int.max
                let r = order[rhs.peer.id] ?? Int.max
                if l != r {
                    return l < r
                }
                return lhs.peer.compactDisplayTitle < rhs.peer.compactDisplayTitle
            })
            return result
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, items, dkxSettingsSignal(context: context))
    |> map { presentationData, items, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let title = settings.chatLabels.first(where: { $0.id == labelId })?.title ?? DkxStrings.tr("Метка")
        var entries: [DkxLabelChatsEntry] = []
        for (index, item) in items.enumerated() {
            entries.append(.item(index: Int32(index), item, title: item.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)))
        }
        entries.append(.footer(items.isEmpty ? DkxStrings.tr("Чатов с этой меткой нет. Метка ставится долгим нажатием на чат, пункт «Метки».") : DkxStrings.tr("Снять метку можно долгим нажатием на чат, пункт «Метки».")))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}
