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

// MARK: DKX «Скрыть разделы». Включённый тумблер прячет вкладку внизу или
// строку главного экрана настроек. Список и названия в DkxHiddenSection.

private final class DkxHiddenSectionsArguments {
    let update: (DkxHiddenSection, Bool) -> Void

    init(update: @escaping (DkxHiddenSection, Bool) -> Void) {
        self.update = update
    }
}

private enum DkxHiddenSectionsSection: Int32 {
    case tabs
    case settings
    case saved
}

private enum DkxHiddenSectionsEntry: ItemListNodeEntry {
    case tabsHeader
    case item(index: Int32, section: DkxHiddenSection, hidden: Bool)
    case tabsFooter
    case settingsHeader
    case settingsFooter
    case savedHeader
    case savedFooter

    var section: ItemListSectionId {
        switch self {
        case .tabsHeader, .tabsFooter:
            return DkxHiddenSectionsSection.tabs.rawValue
        case let .item(_, section, _):
            if section.isTab {
                return DkxHiddenSectionsSection.tabs.rawValue
            }
            return section.isSavedMessages ? DkxHiddenSectionsSection.saved.rawValue : DkxHiddenSectionsSection.settings.rawValue
        case .settingsHeader, .settingsFooter:
            return DkxHiddenSectionsSection.settings.rawValue
        case .savedHeader, .savedFooter:
            return DkxHiddenSectionsSection.saved.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .tabsHeader:
            return 0
        case let .item(index, _, _):
            return 1 + index
        case .tabsFooter:
            return 900
        case .settingsHeader:
            return 901
        case .settingsFooter:
            return 999
        case .savedHeader:
            return 1900
        case .savedFooter:
            return 1999
        }
    }

    // Вкладки идут до подписи своего раздела, строки настроек после заголовка своего
    private var sortKey: Int32 {
        switch self {
        case let .item(index, section, _):
            if section.isTab {
                return 1 + index
            }
            return section.isSavedMessages ? 1901 + index : 902 + index
        default:
            return self.stableId
        }
    }

    static func <(lhs: DkxHiddenSectionsEntry, rhs: DkxHiddenSectionsEntry) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxHiddenSectionsArguments
        switch self {
        case .tabsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ВКЛАДКИ ВНИЗУ"), sectionId: self.section)
        case let .item(_, section, hidden):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: section.title, value: hidden, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(section, value)
            })
        case .tabsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Сами экраны не пропадают. Контакты открываются из списка чатов при создании чата, звонки из «Недавних звонков» в настройках, если эта строка не спрятана.")), sectionId: self.section)
        case .settingsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ГЛАВНЫЙ ЭКРАН НАСТРОЕК"), sectionId: self.section)
        case .settingsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Включённый тумблер прячет строку. Вкладки «Чаты» и «Настройки» и строка Dkx не прячутся, иначе спрятанное было бы не вернуть. Строки, которых у вас и так нет, например Прокси без настроенного прокси, не появятся и при выключенном тумблере.")), sectionId: self.section)
        case .savedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ИЗБРАННОЕ"), sectionId: self.section)
        case .savedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Прячет штатные теги Telegram в Избранном. Пропадёт ряд тегов при поиске и ряд тегов в меню долгого нажатия на сообщение. Свои метки Dkx в Избранном работают отдельно и остаются.")), sectionId: self.section)
        }
    }
}

private func dkxHiddenSectionsEntries(settings: DkxSettings) -> [DkxHiddenSectionsEntry] {
    var entries: [DkxHiddenSectionsEntry] = []
    let all = DkxHiddenSection.allCases
    entries.append(.tabsHeader)
    for (index, section) in all.enumerated() where section.isTab {
        entries.append(.item(index: Int32(index), section: section, hidden: settings.isHidden(section)))
    }
    entries.append(.tabsFooter)
    entries.append(.settingsHeader)
    for (index, section) in all.enumerated() where !section.isTab && !section.isSavedMessages {
        entries.append(.item(index: Int32(index), section: section, hidden: settings.isHidden(section)))
    }
    entries.append(.settingsFooter)
    entries.append(.savedHeader)
    for (index, section) in all.enumerated() where section.isSavedMessages {
        entries.append(.item(index: Int32(index), section: section, hidden: settings.isHidden(section)))
    }
    entries.append(.savedFooter)
    return entries
}

func dkxHiddenSectionsController(context: AccountContext) -> ViewController {
    let accountManager = context.sharedContext.accountManager
    let arguments = DkxHiddenSectionsArguments(update: { section, hidden in
        let _ = updateDkxSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            updated.hiddenSections.removeAll(where: { $0 == section.rawValue })
            if hidden {
                updated.hiddenSections.append(section.rawValue)
            }
            return updated
        }).start()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
    )
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(DkxStrings.tr("Скрыть разделы")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxHiddenSectionsEntries(settings: settings), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
