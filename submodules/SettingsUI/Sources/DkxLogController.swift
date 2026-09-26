import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI

// Экран журнала форка. Показывает хвост журнала, отдаёт его целиком файлом
// или в буфер обмена. Полный журнал на экран не выводится, полмегабайта
// текста в одной ячейке списка раскладываются заметно долго.

private let dkxLogVisibleLines = 150

private final class DkxLogControllerArguments {
    let share: () -> Void
    let copy: () -> Void
    let refresh: () -> Void
    let clear: () -> Void

    init(share: @escaping () -> Void, copy: @escaping () -> Void, refresh: @escaping () -> Void, clear: @escaping () -> Void) {
        self.share = share
        self.copy = copy
        self.refresh = refresh
        self.clear = clear
    }
}

private enum DkxLogSection: Int32 {
    case actions
    case contents
}

private enum DkxLogEntry: ItemListNodeEntry {
    case share
    case copy
    case refresh
    case clear
    case actionsFooter
    case contentsHeader(String)
    case contents(String)

    var section: ItemListSectionId {
        switch self {
        case .share, .copy, .refresh, .clear, .actionsFooter:
            return DkxLogSection.actions.rawValue
        case .contentsHeader, .contents:
            return DkxLogSection.contents.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .share:
            return 0
        case .copy:
            return 1
        case .refresh:
            return 2
        case .clear:
            return 3
        case .actionsFooter:
            return 4
        case .contentsHeader:
            return 5
        case .contents:
            return 6
        }
    }

    static func <(lhs: DkxLogEntry, rhs: DkxLogEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxLogControllerArguments
        switch self {
        case .share:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Отправить журнал файлом", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.share()
            })
        case .copy:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Скопировать весь журнал", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.copy()
            })
        case .refresh:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Обновить", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.refresh()
            })
        case .clear:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Очистить журнал", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clear()
            })
        case .actionsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("В журнале только служебные записи форка и отчёты о падениях, то есть идентификаторы, счётчики и причины. Тексты сообщений, имена и номера сюда не пишутся.\n\nЕсли приложение упало, отчёт появится здесь после следующего запуска. Иногда iOS отдаёт его с задержкой до суток."), sectionId: self.section)
        case let .contentsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .contents(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func dkxLogEntries(contents: String) -> [DkxLogEntry] {
    var entries: [DkxLogEntry] = []
    entries.append(.share)
    entries.append(.copy)
    entries.append(.refresh)
    entries.append(.clear)
    entries.append(.actionsFooter)

    let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
    if lines.isEmpty {
        entries.append(.contentsHeader("ЖУРНАЛ"))
        entries.append(.contents("Журнал пуст."))
    } else {
        let visible = lines.suffix(dkxLogVisibleLines)
        let header = visible.count < lines.count ? "ПОСЛЕДНИЕ \(visible.count) ИЗ \(lines.count)" : "ВСЕГО ЗАПИСЕЙ \(lines.count)"
        entries.append(.contentsHeader(header))
        // Свежие сверху, так быстрее найти то, что случилось только что
        entries.append(.contents(visible.reversed().joined(separator: "\n")))
    }
    return entries
}

public func dkxLogController(context: AccountContext) -> ViewController {
    let contentsPromise = ValuePromise<String>(DkxLog.contents(), ignoreRepeated: true)
    var presentControllerImpl: ((ViewController) -> Void)?

    let showToast: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
    }

    let arguments = DkxLogControllerArguments(
        share: {
            guard let url = DkxLog.fileURL, FileManager.default.fileExists(atPath: url.path) else {
                showToast("Журнал пуст, отправлять нечего")
                return
            }
            // Копия с понятным именем, иначе в чат уйдёт безликий dkx.log
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HH-mm"
            let copyURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dkx-log-\(formatter.string(from: Date())).txt")
            let _ = try? FileManager.default.removeItem(at: copyURL)
            do {
                try FileManager.default.copyItem(at: url, to: copyURL)
            } catch {
                showToast("Не удалось подготовить файл")
                return
            }
            let activityController = UIActivityViewController(activityItems: [copyURL], applicationActivities: nil)
            context.sharedContext.applicationBindings.presentNativeController(activityController)
        },
        copy: {
            let text = DkxLog.contents()
            if text.isEmpty {
                showToast("Журнал пуст")
                return
            }
            UIPasteboard.general.string = text
            showToast("Журнал скопирован")
        },
        refresh: {
            contentsPromise.set(DkxLog.contents())
        },
        clear: {
            DkxLog.clear()
            contentsPromise.set(DkxLog.contents())
            showToast("Журнал очищен")
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        contentsPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, contents -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Журнал"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxLogEntries(contents: contents), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .current)
    }
    return controller
}
