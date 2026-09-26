import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import TelegramUIPreferences

private struct DkxDriveAccountState: Equatable {
    var draftName: String
    var message: String?
    var revision = 0
}

private final class DkxDriveAccountArguments {
    let updateName: (String) -> Void
    let saveName: () -> Void
    let setMain: (Bool) -> Void
    let disconnect: () -> Void

    init(updateName: @escaping (String) -> Void, saveName: @escaping () -> Void, setMain: @escaping (Bool) -> Void, disconnect: @escaping () -> Void) {
        self.updateName = updateName
        self.saveName = saveName
        self.setMain = setMain
        self.disconnect = disconnect
    }
}

private enum DkxDriveAccountEntry: ItemListNodeEntry {
    case nameHeader
    case nameInput(String, String)
    case nameSave
    case nameFooter(String)
    case mainSwitch(Bool)
    case mainFooter(String)
    case disconnect
    case disconnectFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .nameHeader, .nameInput, .nameSave, .nameFooter:
            return 0
        case .mainSwitch, .mainFooter:
            return 1
        case .disconnect, .disconnectFooter:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .nameHeader:
            return 0
        case .nameInput:
            return 1
        case .nameSave:
            return 2
        case .nameFooter:
            return 3
        case .mainSwitch:
            return 10
        case .mainFooter:
            return 11
        case .disconnect:
            return 20
        case .disconnectFooter:
            return 21
        }
    }

    static func <(lhs: DkxDriveAccountEntry, rhs: DkxDriveAccountEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxDriveAccountArguments
        switch self {
        case .nameHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("НАЗВАНИЕ"), sectionId: self.section)
        case let .nameInput(text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: .regular(capitalization: true, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateName(value)
            }, action: {
                arguments.saveName()
            })
        case .nameSave:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Сохранить название"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.saveName()
            })
        case let .nameFooter(text), let .mainFooter(text), let .disconnectFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .mainSwitch(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Основной аккаунт"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setMain(value)
            })
        case .disconnect:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Отвязать аккаунт"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.disconnect()
            })
        }
    }
}

func dkxDriveAccountController(context: AccountContext, accountId: String) -> ViewController {
    let account = DkxGoogleDrive.accounts.first(where: { $0.id == accountId })
    let email = account?.email ?? ""
    let initial = DkxDriveAccountState(draftName: account?.name ?? "")
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let updateState: ((inout DkxDriveAccountState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }
    var dismissImpl: (() -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let arguments = DkxDriveAccountArguments(updateName: { value in
        updateState { $0.draftName = value }
    }, saveName: {
        DkxGoogleDrive.rename(accountId, stateValue.with { $0.draftName })
        updateState { state in
            state.message = DkxStrings.tr("Название сохранено.")
            state.revision += 1
        }
    }, setMain: { value in
        DkxGoogleDrive.setMain(value ? accountId : nil)
        updateState { $0.revision += 1 }
    }, disconnect: {
        presentImpl?(textAlertController(context: context, title: DkxStrings.tr("Отвязать аккаунт?"), text: DkxStrings.tr("Файлы на диске останутся. Чтобы снова грузить на этот диск, аккаунт придётся добавить заново."), actions: [
            TextAlertAction(type: .genericAction, title: DkxStrings.tr("Отмена"), action: {}),
            TextAlertAction(type: .destructiveAction, title: DkxStrings.tr("Отвязать"), action: {
                DkxGoogleDrive.disconnect(accountId)
                dismissImpl?()
            })
        ]))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isMain = DkxGoogleDrive.mainAccountId == accountId
        var nameFooter = DkxStrings.tr("Название видно только вам, например «Рабочий» или «Личный». Если оставить поле пустым, будет видна почта.")
        if let message = state.message {
            nameFooter = message + "\n\n" + nameFooter
        }
        var entries: [DkxDriveAccountEntry] = []
        entries.append(.nameHeader)
        entries.append(.nameInput(state.draftName, email.isEmpty ? DkxStrings.tr("Название") : email))
        entries.append(.nameSave)
        entries.append(.nameFooter(nameFooter))
        entries.append(.mainSwitch(isMain))
        entries.append(.mainFooter(DkxStrings.tr("Все выгрузки уходят на основной аккаунт без вопросов. Если основной не выбран, а аккаунтов несколько, Dkx при каждой выгрузке спросит, на какой диск загрузить.")))
        entries.append(.disconnect)
        entries.append(.disconnectFooter(email.isEmpty ? DkxStrings.tr("Файлы на диске после отвязки останутся.") : DkxStrings.tr("Почта {}. Файлы на диске после отвязки останутся.", email)))
        let title = account?.title ?? "Google Drive"
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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
