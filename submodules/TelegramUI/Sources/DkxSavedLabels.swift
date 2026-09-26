import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI
import TelegramStringFormatting
import ChatPresentationInterfaceState
import LegacyChatHeaderPanelComponent

// MARK: DKX свои метки на сообщения в Избранном. Выбор меток из меню
// сообщения, ряд меток под заголовком Избранного, список сообщений метки и
// редактор. Хранение в DkxSavedLabelsStore, с метками чатов не связано.

private func dkxSavedLabelColor(context: AccountContext, colorId: Int32, dark: Bool) -> UIColor {
    return context.peerNameColors.getChatFolderTag(PeerNameColor(rawValue: colorId), dark: dark).main
}

private func dkxSavedLabelDot(context: AccountContext, colorId: Int32, theme: PresentationTheme) -> UIImage? {
    return generateFilledCircleImage(diameter: 14.0, color: dkxSavedLabelColor(context: context, colorId: colorId, dark: theme.overallDarkAppearance))
}

func dkxSavedLabelsPanelApplicable(_ state: ChatPresentationInterfaceState, context: AccountContext) -> Bool {
    guard state.chatLocation.peerId == context.account.peerId, state.subject == nil else {
        return false
    }
    if case .standard(.default) = state.mode {
        return true
    }
    return false
}

func dkxSavedLabelsApplicable(context: AccountContext, message: Message) -> Bool {
    return message.id.peerId == context.account.peerId && message.id.namespace == Namespaces.Message.Cloud
}

// Кнопка тегов в панели выделения Избранного. Штатные теги остаются тем, у кого Premium и они не спрятаны
func dkxSavedLabelsSelectionOverride(context: AccountContext, controller: ViewController, messageIds: [EngineMessage.Id], isPremium: Bool) -> Bool {
    if isPremium && !DkxRuntime.current.isHidden(.savedTags) {
        return false
    }
    let ids = messageIds.filter { $0.peerId == context.account.peerId && $0.namespace == Namespaces.Message.Cloud }
    if ids.isEmpty {
        return false
    }
    controller.push(dkxSavedLabelsPickerController(context: context, messageIds: ids))
    return true
}

// MARK: - Выбор меток для сообщения

private final class DkxSavedLabelsPickerArguments {
    let context: AccountContext
    let toggle: (Int32, Bool) -> Void
    let add: () -> Void

    init(context: AccountContext, toggle: @escaping (Int32, Bool) -> Void, add: @escaping () -> Void) {
        self.context = context
        self.toggle = toggle
        self.add = add
    }
}

private enum DkxSavedLabelsPickerEntry: ItemListNodeEntry {
    case label(index: Int32, label: DkxSavedLabel, checked: Bool, partial: String?)
    case add
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .label(index, _, _, _):
            return index
        case .add:
            return 10000
        case .footer:
            return 10001
        }
    }

    static func <(lhs: DkxSavedLabelsPickerEntry, rhs: DkxSavedLabelsPickerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxSavedLabelsPickerArguments
        switch self {
        case let .label(_, label, checked, partial):
            let title = partial.map { label.title + " · " + $0 } ?? label.title
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: dkxSavedLabelDot(context: arguments.context, colorId: label.colorId, theme: presentationData.theme), title: title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
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

func dkxSavedLabelsPickerController(context: AccountContext, messageId: EngineMessage.Id) -> ViewController {
    return dkxSavedLabelsPickerController(context: context, messageIds: [messageId])
}

// Метка отмечена, только если стоит на всех выбранных сообщениях. Нажатие ставит её всем или снимает со всех
func dkxSavedLabelsPickerController(context: AccountContext, messageIds: [EngineMessage.Id]) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let arguments = DkxSavedLabelsPickerArguments(context: context, toggle: { labelId, assigned in
        DkxSavedLabelsStore.update { labels in
            for messageId in messageIds {
                labels.set(label: labelId, account: messageId.peerId.toInt64(), message: messageId.id, assigned: assigned)
            }
        }
    }, add: {
        pushImpl?(dkxSavedLabelEditorController(context: context, labelId: nil, assignTo: messageIds))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, DkxSavedLabelsStore.signal)
    |> map { presentationData, labels -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxSavedLabelsPickerEntry] = []
        for (index, label) in labels.labels.enumerated() {
            let count = messageIds.filter { labels.labelIds(account: $0.peerId.toInt64(), message: $0.id).contains(label.id) }.count
            let partial = count > 0 && count < messageIds.count ? DkxStrings.tr("у {} из {}", count, messageIds.count) : nil
            entries.append(.label(index: Int32(index), label: label, checked: !messageIds.isEmpty && count == messageIds.count, partial: partial))
        }
        entries.append(.add)
        if messageIds.count == 1 {
            entries.append(.footer(labels.labels.isEmpty ? DkxStrings.tr("Меток пока нет. Создайте первую, она сразу встанет на это сообщение.") : DkxStrings.tr("Метки видны рядом под заголовком Избранного, нажатие на метку показывает её сообщения. Название, цвет и порядок меняются там же, кнопкой «Изменить». Метки хранятся на этом телефоне и не пропадают при переустановке.")))
        } else {
            entries.append(.footer(labels.labels.isEmpty ? DkxStrings.tr("Меток пока нет. Создайте первую, она сразу встанет на выбранные сообщения.") : DkxStrings.tr("Отмеченные метки стоят на всех выбранных сообщениях. Нажатие ставит метку всем или снимает со всех.")))
        }
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

private struct DkxSavedLabelEditorState: Equatable {
    var title: String
    var colorId: Int32
}

private final class DkxSavedLabelEditorArguments {
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

private enum DkxSavedLabelEditorEntry: ItemListNodeEntry {
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

    static func <(lhs: DkxSavedLabelEditorEntry, rhs: DkxSavedLabelEditorEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxSavedLabelEditorArguments
        switch self {
        case .titleHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("НАЗВАНИЕ"), sectionId: self.section)
        case let .title(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: DkxStrings.tr("Например, чеки"), type: .regular(capitalization: false, autocorrection: true), sectionId: self.section, textUpdated: { value in
                arguments.updateTitle(value)
            }, action: {})
        case .colorHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ЦВЕТ"), sectionId: self.section)
        case let .color(_, colorId, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: dkxSavedLabelDot(context: arguments.context, colorId: colorId, theme: presentationData.theme), title: title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
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

func dkxSavedLabelEditorController(context: AccountContext, labelId: Int32?, assignTo: [EngineMessage.Id]) -> ViewController {
    let current = DkxSavedLabelsStore.current
    let existing = labelId.flatMap { id in current.labels.first(where: { $0.id == id }) }
    let usedColors = Set(current.labels.map { $0.colorId })
    let freeColor = dkxChatLabelColors.first(where: { !usedColors.contains($0.id) })?.id ?? 5
    let initial = DkxSavedLabelEditorState(title: existing?.title ?? "", colorId: existing?.colorId ?? freeColor)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let updateState: ((inout DkxSavedLabelEditorState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }

    var dismissImpl: (() -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let arguments = DkxSavedLabelEditorArguments(context: context, updateTitle: { value in
        updateState { $0.title = value }
    }, updateColor: { value in
        updateState { $0.colorId = value }
    }, move: { delta in
        guard let labelId else {
            return
        }
        DkxSavedLabelsStore.update { labels in
            var list = labels.labels
            guard let index = list.firstIndex(where: { $0.id == labelId }) else {
                return
            }
            let target = index + delta
            guard target >= 0, target < list.count else {
                return
            }
            list.swapAt(index, target)
            labels.setLabels(list)
        }
    }, delete: {
        guard let labelId else {
            return
        }
        let title = stateValue.with { $0.title }
        presentImpl?(textAlertController(context: context, title: DkxStrings.tr("Удалить метку?"), text: DkxStrings.tr("«{}» снимется со всех сообщений.", title), actions: [
            TextAlertAction(type: .genericAction, title: DkxStrings.tr("Отмена"), action: {}),
            TextAlertAction(type: .destructiveAction, title: DkxStrings.tr("Удалить"), action: {
                DkxSavedLabelsStore.update { labels in
                    labels.setLabels(labels.labels.filter { $0.id != labelId })
                }
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
        DkxSavedLabelsStore.update { labels in
            var list = labels.labels
            if let labelId, let index = list.firstIndex(where: { $0.id == labelId }) {
                list[index].title = title
                list[index].colorId = state.colorId
                labels.setLabels(list)
            } else {
                let id = labels.nextLabelId
                list.append(DkxSavedLabel(id: id, title: title, colorId: state.colorId))
                labels.setLabels(list)
                for messageId in assignTo {
                    labels.set(label: id, account: messageId.peerId.toInt64(), message: messageId.id, assigned: true)
                }
            }
        }
        dismissImpl?()
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxSavedLabelEditorEntry] = []
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

// MARK: - Сообщения с меткой

private func dkxSavedMessagePreview(_ message: Message) -> String {
    if !message.text.isEmpty {
        return message.text
    }
    for media in message.media {
        if media is TelegramMediaImage {
            return DkxStrings.tr("Фото")
        }
        if let file = media as? TelegramMediaFile {
            if file.isVoice {
                return DkxStrings.tr("Голосовое")
            }
            if file.isInstantVideo {
                return DkxStrings.tr("Кружок")
            }
            if file.isSticker || file.isAnimatedSticker {
                return DkxStrings.tr("Стикер")
            }
            if let fileName = file.fileName, !fileName.isEmpty {
                return fileName
            }
            if file.isVideo {
                return DkxStrings.tr("Видео")
            }
            if file.isMusic {
                return DkxStrings.tr("Аудио")
            }
            return DkxStrings.tr("Файл")
        }
        if media is TelegramMediaMap {
            return DkxStrings.tr("Геопозиция")
        }
        if media is TelegramMediaContact {
            return DkxStrings.tr("Контакт")
        }
        if media is TelegramMediaPoll {
            return DkxStrings.tr("Опрос")
        }
    }
    return DkxStrings.tr("Сообщение")
}

private struct DkxSavedLabelItem: Equatable {
    let id: EngineMessage.Id
    let date: Int32
    let text: String
}

private final class DkxSavedLabelMessagesArguments {
    let open: (EngineMessage.Id) -> Void

    init(open: @escaping (EngineMessage.Id) -> Void) {
        self.open = open
    }
}

private enum DkxSavedLabelMessagesEntry: ItemListNodeEntry {
    case status(String)
    case message(index: Int32, label: String, text: String, id: EngineMessage.Id)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .status:
            return 0
        case let .message(index, _, _, _):
            return 1 + index
        }
    }

    static func <(lhs: DkxSavedLabelMessagesEntry, rhs: DkxSavedLabelMessagesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxSavedLabelMessagesArguments
        switch self {
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .message(_, label, text, id):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: {
                arguments.open(id)
            })
        }
    }
}

func dkxSavedLabelMessagesController(context: AccountContext, labelId: Int32) -> ViewController {
    let accountPeerId = context.account.peerId
    var navigationControllerImpl: (() -> NavigationController?)?
    var pushImpl: ((ViewController) -> Void)?

    let arguments = DkxSavedLabelMessagesArguments(open: { id in
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: accountPeerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer, let navigationController = navigationControllerImpl?() else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
        })
    })

    let messageIds: Signal<[EngineMessage.Id], NoError> = DkxSavedLabelsStore.signal
    |> map { labels -> [EngineMessage.Id] in
        return labels.messages(account: accountPeerId.toInt64(), label: labelId).map { EngineMessage.Id(peerId: accountPeerId, namespace: Namespaces.Message.Cloud, id: $0) }
    }
    |> distinctUntilChanged

    // После переустановки Избранное на телефоне ещё не загружено, поэтому
    // недостающие сообщения берём с сервера
    let items: Signal<[DkxSavedLabelItem]?, NoError> = messageIds
    |> mapToSignal { ids -> Signal<[DkxSavedLabelItem]?, NoError> in
        if ids.isEmpty {
            return .single([])
        }
        return .single(nil)
        |> then(
            context.engine.messages.getMessagesLoadIfNecessary(ids, strategy: .cloud(skipLocal: false))
            |> mapToSignal { result -> Signal<[DkxSavedLabelItem]?, GetMessagesError> in
                guard case let .result(messages) = result else {
                    return .complete()
                }
                let found = messages.map { DkxSavedLabelItem(id: $0.id, date: $0.timestamp, text: dkxSavedMessagePreview($0)) }
                return .single(found.sorted(by: { $0.id.id > $1.id.id }))
            }
            |> `catch` { _ -> Signal<[DkxSavedLabelItem]?, NoError> in
                return .single([])
            }
        )
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, items, DkxSavedLabelsStore.signal)
    |> map { presentationData, items, labels -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let title = labels.labels.first(where: { $0.id == labelId })?.title ?? DkxStrings.tr("Метка")
        var entries: [DkxSavedLabelMessagesEntry] = []
        if let items {
            if items.isEmpty {
                entries.append(.status(DkxStrings.tr("Сообщений с этой меткой нет. Метка ставится долгим нажатием на сообщение в Избранном, пункт «Метки».")))
            } else {
                entries.append(.status(DkxStrings.tr("Нажатие открывает сообщение в Избранном. Снять метку можно долгим нажатием на сообщение, пункт «Метки».")))
                for (index, item) in items.enumerated() {
                    let date = stringForMediumDate(timestamp: item.date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
                    entries.append(.message(index: Int32(index), label: date, text: item.text, id: item.id))
                }
            }
        } else {
            entries.append(.status(DkxStrings.tr("Ищу…")))
        }
        let rightButton = ItemListNavigationButton(content: .text(DkxStrings.tr("Изменить")), style: .regular, enabled: true, action: {
            pushImpl?(dkxSavedLabelEditorController(context: context, labelId: labelId, assignTo: []))
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Ряд меток под заголовком Избранного

private final class DkxSavedLabelChipView: UIView {
    let label = UILabel()
    var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubview(self.label)
        self.layer.cornerRadius = 14.0
        self.clipsToBounds = true
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        self.action?()
    }
}

final class DkxSavedLabelsTitlePanelNode: ChatTitleAccessoryPanelNode {
    private let context: AccountContext
    private let scrollView: UIScrollView
    private var chips: [Int32: DkxSavedLabelChipView] = [:]
    private var labels: [DkxSavedLabel] = []
    private var disposable: Disposable?
    private var lastLayout: (width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, theme: PresentationTheme)?

    var hasLabels: Bool {
        return !self.labels.isEmpty
    }

    init(context: AccountContext) {
        self.context = context
        self.scrollView = UIScrollView()
        self.labels = DkxSavedLabelsStore.current.labels

        super.init()

        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.alwaysBounceHorizontal = true
        self.scrollView.scrollsToTop = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.scrollView.disablesInteractiveTransitionGestureRecognizer = true
        self.view.addSubview(self.scrollView)

        self.disposable = (DkxSavedLabelsStore.signal
        |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self else {
                return
            }
            let hadLabels = !self.labels.isEmpty
            self.labels = value.labels
            self.layoutChips()
            // Первая метка или удалена последняя, чату надо добавить или убрать панель
            if hadLabels != !self.labels.isEmpty {
                self.interfaceInteraction?.requestLayout(.animated(duration: 0.25, curve: .easeInOut))
            }
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    private func open(labelId: Int32) {
        guard let chatController = self.interfaceInteraction?.chatController() else {
            return
        }
        chatController.push(dkxSavedLabelMessagesController(context: self.context, labelId: labelId))
    }

    private func layoutChips() {
        guard let layout = self.lastLayout else {
            return
        }
        let panelHeight: CGFloat = 40.0
        let chipHeight: CGFloat = 28.0
        let dark = layout.theme.overallDarkAppearance
        let valid = Set(self.labels.map { $0.id })
        for (id, chip) in self.chips where !valid.contains(id) {
            chip.removeFromSuperview()
            self.chips[id] = nil
        }
        var x = layout.leftInset + 16.0
        for label in self.labels {
            let chip: DkxSavedLabelChipView
            if let current = self.chips[label.id] {
                chip = current
            } else {
                chip = DkxSavedLabelChipView(frame: CGRect())
                let labelId = label.id
                chip.action = { [weak self] in
                    self?.open(labelId: labelId)
                }
                self.chips[label.id] = chip
                self.scrollView.addSubview(chip)
            }
            let color = dkxSavedLabelColor(context: self.context, colorId: label.colorId, dark: dark)
            chip.backgroundColor = color.withAlphaComponent(0.16)
            chip.label.text = label.title
            chip.label.font = Font.medium(14.0)
            chip.label.textColor = color
            let textSize = chip.label.sizeThatFits(CGSize(width: 220.0, height: chipHeight))
            let textWidth = min(220.0, ceil(textSize.width))
            let textHeight = ceil(textSize.height)
            chip.frame = CGRect(x: x, y: floor((panelHeight - chipHeight) / 2.0), width: textWidth + 24.0, height: chipHeight)
            chip.label.frame = CGRect(x: 12.0, y: floor((chipHeight - textHeight) / 2.0), width: textWidth, height: textHeight)
            x += textWidth + 24.0 + 8.0
        }
        self.scrollView.frame = CGRect(x: 0.0, y: 0.0, width: layout.width, height: panelHeight)
        self.scrollView.contentSize = CGSize(width: x - 8.0 + layout.rightInset + 16.0, height: panelHeight)
    }

    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) -> LayoutResult {
        self.lastLayout = (width, leftInset, rightInset, interfaceState.theme)
        self.layoutChips()
        return LayoutResult(backgroundHeight: 40.0, insetHeight: 40.0, hitTestSlop: 0.0)
    }
}
