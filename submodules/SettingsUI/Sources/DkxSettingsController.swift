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

// Экран настроек форка. Сюда складываются все тумблеры, которые решает
// интерфейс. Строки захардкожены: свои ключи в Localizable.strings требуют
// прогона GenerateStrings.py, а это отдельный шаг сборки ради форка на
// несколько устройств.

private final class DkxSettingsControllerArguments {
    let updateHideStories: (Bool) -> Void
    let updateHidePremiumPromo: (Bool) -> Void

    init(
        updateHideStories: @escaping (Bool) -> Void,
        updateHidePremiumPromo: @escaping (Bool) -> Void
    ) {
        self.updateHideStories = updateHideStories
        self.updateHidePremiumPromo = updateHidePremiumPromo
    }
}

private enum DkxSettingsSection: Int32 {
    case interface
    case features
}

private enum DkxSettingsControllerEntry: ItemListNodeEntry {
    case interfaceHeader
    case hideStories(Bool)
    case hidePremiumPromo(Bool)
    case interfaceFooter

    case featuresHeader
    case featuresFooter

    var section: ItemListSectionId {
        switch self {
        case .interfaceHeader, .hideStories, .hidePremiumPromo, .interfaceFooter:
            return DkxSettingsSection.interface.rawValue
        case .featuresHeader, .featuresFooter:
            return DkxSettingsSection.features.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .interfaceHeader:
            return 0
        case .hideStories:
            return 1
        case .hidePremiumPromo:
            return 2
        case .interfaceFooter:
            return 3
        case .featuresHeader:
            return 4
        case .featuresFooter:
            return 5
        }
    }

    static func <(lhs: DkxSettingsControllerEntry, rhs: DkxSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxSettingsControllerArguments
        switch self {
        case .interfaceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИНТЕРФЕЙС", sectionId: self.section)
        case let .hideStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Скрыть ленту историй", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideStories(value)
            })
        case let .hidePremiumPromo(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Убрать предложения премиума", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHidePremiumPromo(value)
            })
        case .interfaceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Лента историй над списком чатов исчезнет полностью. Сами истории останутся доступны в профилях."), sectionId: self.section)
        case .featuresHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СООБЩЕНИЯ", sectionId: self.section)
        case .featuresFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Удалённые собеседником сообщения остаются в чате с пометкой «удалено». У отредактированных в контекстном меню доступна история правок.\n\nСекретные чаты и самоуничтожающиеся сообщения не затрагиваются."), sectionId: self.section)
        }
    }
}

private func dkxSettingsControllerEntries(settings: DkxSettings) -> [DkxSettingsControllerEntry] {
    var entries: [DkxSettingsControllerEntry] = []

    entries.append(.interfaceHeader)
    entries.append(.hideStories(settings.hideStories))
    // Убирание предложений премиума пока не показываем: единой точки нет,
    // это 58 разных мест, отдельная работа. Поле в настройках уже заведено.
    entries.append(.interfaceFooter)

    entries.append(.featuresHeader)
    entries.append(.featuresFooter)

    return entries
}

public func dkxSettingsController(context: AccountContext) -> ViewController {
    let arguments = DkxSettingsControllerArguments(
        updateHideStories: { value in
            let _ = updateDkxSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                updated.hideStories = value
                return updated
            }).start()
        },
        updateHidePremiumPromo: { value in
            let _ = updateDkxSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                updated.hidePremiumPromo = value
                return updated
            }).start()
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Dkx"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxSettingsControllerEntries(settings: settings), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
