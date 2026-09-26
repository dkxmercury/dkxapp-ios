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
import ItemListDatePickerItem

// MARK: DKX все медиа чата за период на Google Drive. Ищет на сервере по типу
// медиа и датам, в телефоне вся история не лежит. Найденное уходит в ту же
// очередь, что и пункт «В Google Drive» в меню сообщения, дубли она пропускает.

private let dkxChatMediaCap = 3000

private var dkxChatMediaPeriods: [String] {
    return [DkxStrings.tr("Сегодня"), DkxStrings.tr("7 дней"), DkxStrings.tr("30 дней"), DkxStrings.tr("Всё время"), DkxStrings.tr("Свои даты")]
}

private enum DkxChatMediaKind: Int32 {
    case photos
    case files
    case voice

    var title: String {
        switch self {
        case .photos:
            return DkxStrings.tr("Фото и видео")
        case .files:
            return DkxStrings.tr("Файлы")
        case .voice:
            return DkxStrings.tr("Голосовые и кружки")
        }
    }

    var tags: MessageTags {
        switch self {
        case .photos:
            return .photoOrVideo
        case .files:
            return .file
        case .voice:
            return .voiceOrInstantVideo
        }
    }
}

private struct DkxChatMediaState: Equatable {
    var period: Int32 = 1
    var fromDate: Int32
    var toDate: Int32
    var showingFrom = false
    var showingTo = false
    var kinds: Set<Int32> = [DkxChatMediaKind.photos.rawValue, DkxChatMediaKind.files.rawValue, DkxChatMediaKind.voice.rawValue]
    var searching = false
}

private final class DkxChatMediaArguments {
    let selectPeriod: (Int32) -> Void
    let toggleFrom: () -> Void
    let toggleTo: () -> Void
    let updateFrom: (Int32) -> Void
    let updateTo: (Int32) -> Void
    let toggleKind: (DkxChatMediaKind, Bool) -> Void
    let start: () -> Void

    init(selectPeriod: @escaping (Int32) -> Void, toggleFrom: @escaping () -> Void, toggleTo: @escaping () -> Void, updateFrom: @escaping (Int32) -> Void, updateTo: @escaping (Int32) -> Void, toggleKind: @escaping (DkxChatMediaKind, Bool) -> Void, start: @escaping () -> Void) {
        self.selectPeriod = selectPeriod
        self.toggleFrom = toggleFrom
        self.toggleTo = toggleTo
        self.updateFrom = updateFrom
        self.updateTo = updateTo
        self.toggleKind = toggleKind
        self.start = start
    }
}

private enum DkxChatMediaEntry: ItemListNodeEntry {
    case periodHeader
    case period(index: Int32, title: String, checked: Bool)
    case fromDate(PresentationDateTimeFormat, Int32, Bool)
    case toDate(PresentationDateTimeFormat, Int32, Bool)
    case kindsHeader
    case kind(DkxChatMediaKind, Bool)
    case start(searching: Bool, enabled: Bool)
    case footer

    var section: ItemListSectionId {
        switch self {
        case .periodHeader, .period, .fromDate, .toDate:
            return 0
        case .kindsHeader, .kind:
            return 1
        case .start, .footer:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .periodHeader:
            return 0
        case let .period(index, _, _):
            return 1 + index
        case .fromDate:
            return 10
        case .toDate:
            return 11
        case .kindsHeader:
            return 100
        case let .kind(kind, _):
            return 101 + kind.rawValue
        case .start:
            return 200
        case .footer:
            return 201
        }
    }

    static func <(lhs: DkxChatMediaEntry, rhs: DkxChatMediaEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxChatMediaArguments
        switch self {
        case .periodHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ПЕРИОД"), sectionId: self.section)
        case let .period(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectPeriod(index)
            })
        case let .fromDate(dateTimeFormat, date, showing):
            return ItemListDatePickerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: dateTimeFormat, date: date, title: DkxStrings.tr("С"), displayingDateSelection: showing, displayingTimeSelection: false, sectionId: self.section, style: .blocks, toggleDateSelection: {
                arguments.toggleFrom()
            }, toggleTimeSelection: nil, updated: { value in
                arguments.updateFrom(value)
            })
        case let .toDate(dateTimeFormat, date, showing):
            return ItemListDatePickerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: dateTimeFormat, date: date, title: DkxStrings.tr("По"), displayingDateSelection: showing, displayingTimeSelection: false, sectionId: self.section, style: .blocks, toggleDateSelection: {
                arguments.toggleTo()
            }, toggleTimeSelection: nil, updated: { value in
                arguments.updateTo(value)
            })
        case .kindsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ЧТО ВЫГРУЖАТЬ"), sectionId: self.section)
        case let .kind(kind, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: kind.title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleKind(kind, value)
            })
        case let .start(searching, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: searching ? DkxStrings.tr("Ищу…") : DkxStrings.tr("Найти и выгрузить"), kind: enabled && !searching ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.start()
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Поиск идёт на сервере Telegram, поэтому находится и то, что не загружено на телефон. Перед выгрузкой покажу, сколько нашлось. Файлы грузятся фоном, ход виден в полосе вверху экрана, повторы на диск не попадут. За один раз до {} файлов.", dkxChatMediaCap)), sectionId: self.section)
        }
    }
}

private func dkxChatMediaEntries(state: DkxChatMediaState, dateTimeFormat: PresentationDateTimeFormat) -> [DkxChatMediaEntry] {
    var entries: [DkxChatMediaEntry] = []
    entries.append(.periodHeader)
    for (index, title) in dkxChatMediaPeriods.enumerated() {
        entries.append(.period(index: Int32(index), title: title, checked: Int32(index) == state.period))
    }
    if state.period == 4 {
        entries.append(.fromDate(dateTimeFormat, state.fromDate, state.showingFrom))
        entries.append(.toDate(dateTimeFormat, state.toDate, state.showingTo))
    }
    entries.append(.kindsHeader)
    for kind in [DkxChatMediaKind.photos, .files, .voice] {
        entries.append(.kind(kind, state.kinds.contains(kind.rawValue)))
    }
    entries.append(.start(searching: state.searching, enabled: !state.kinds.isEmpty))
    entries.append(.footer)
    return entries
}

private func dkxStartOfDay(_ timestamp: Int32) -> Int32 {
    return Int32(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(timestamp))).timeIntervalSince1970)
}

// Страницы поиска по одному типу медиа, пока сервер отдаёт новое
private func dkxLoadChatMedia(context: AccountContext, peerId: EnginePeer.Id, tags: MessageTags, minDate: Int32?, maxDate: Int32?, cap: Int) -> Signal<[Message], NoError> {
    func page(_ state: SearchMessagesState?, _ collected: [Message]) -> Signal<[Message], NoError> {
        return context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: tags, reactions: nil, threadId: nil, minDate: minDate, maxDate: maxDate), query: "", state: state, limit: 100)
        |> take(1)
        |> mapToSignal { result, nextState -> Signal<[Message], NoError> in
            let known = Set(collected.map { $0.id })
            let fresh = result.messages.filter { !known.contains($0.id) }
            let all = collected + fresh
            if result.completed || fresh.isEmpty || all.count >= cap {
                return .single(all)
            }
            return page(nextState, all)
        }
    }
    return page(nil, [])
}

private func dkxSizeText(_ bytes: Int64) -> String {
    let megabytes = Double(bytes) / 1_048_576.0
    if megabytes >= 1024.0 {
        return String(format: DkxStrings.tr("%.1f ГБ"), megabytes / 1024.0).replacingOccurrences(of: ".", with: ",")
    }
    return DkxStrings.tr("{} МБ", max(1, Int(megabytes.rounded())))
}

public func dkxChatMediaDriveController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let now = Int32(Date().timeIntervalSince1970)
    let statePromise = ValuePromise(DkxChatMediaState(fromDate: now - 7 * 86400, toDate: now), ignoreRepeated: true)
    let stateValue = Atomic(value: DkxChatMediaState(fromDate: now - 7 * 86400, toDate: now))
    let updateState: ((inout DkxChatMediaState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }

    var presentControllerImpl: ((ViewController) -> Void)?
    let searchDisposable = MetaDisposable()

    let showAlert: (String, String) -> Void = { title, text in
        presentControllerImpl?(textAlertController(context: context, title: title, text: text, actions: [TextAlertAction(type: .defaultAction, title: DkxStrings.tr("Понятно"), action: {})]))
    }

    let arguments = DkxChatMediaArguments(selectPeriod: { index in
        updateState { $0.period = index }
    }, toggleFrom: {
        updateState { state in
            state.showingFrom = !state.showingFrom
            state.showingTo = false
        }
    }, toggleTo: {
        updateState { state in
            state.showingTo = !state.showingTo
            state.showingFrom = false
        }
    }, updateFrom: { value in
        updateState { $0.fromDate = value }
    }, updateTo: { value in
        updateState { $0.toDate = value }
    }, toggleKind: { kind, value in
        updateState { state in
            if value {
                state.kinds.insert(kind.rawValue)
            } else {
                state.kinds.remove(kind.rawValue)
            }
        }
    }, start: {
        let state = stateValue.with { $0 }
        guard !state.searching, !state.kinds.isEmpty else {
            return
        }
        guard DkxRuntime.current.driveEnabled, DkxGoogleDrive.isConfigured, DkxGoogleDrive.isConnected else {
            showAlert(DkxStrings.tr("Google Drive не подключён"), DkxStrings.tr("Включите Google Drive в настройках Dkx и войдите в Google."))
            return
        }

        let now = Int32(Date().timeIntervalSince1970)
        var minDate: Int32?
        var maxDate: Int32?
        switch state.period {
        case 0:
            minDate = dkxStartOfDay(now)
        case 1:
            minDate = now - 7 * 86400
        case 2:
            minDate = now - 30 * 86400
        case 4:
            let from = min(state.fromDate, state.toDate)
            let to = max(state.fromDate, state.toDate)
            minDate = dkxStartOfDay(from)
            maxDate = dkxStartOfDay(to) + 86400 - 1
        default:
            break
        }

        let kinds = [DkxChatMediaKind.photos, .files, .voice].filter { state.kinds.contains($0.rawValue) }
        var signal: Signal<[Message], NoError> = .single([])
        for kind in kinds {
            signal = signal
            |> mapToSignal { collected -> Signal<[Message], NoError> in
                if collected.count >= dkxChatMediaCap {
                    return .single(collected)
                }
                return dkxLoadChatMedia(context: context, peerId: peerId, tags: kind.tags, minDate: minDate, maxDate: maxDate, cap: dkxChatMediaCap - collected.count)
                |> map { collected + $0 }
            }
        }

        updateState { $0.searching = true }
        DkxLog.write("drive", "поиск медиа чата \(peerId), период \(state.period)")
        searchDisposable.set((signal
        |> deliverOnMainQueue).start(next: { messages in
            updateState { $0.searching = false }
            var seen = Set<MessageId>()
            let filtered = messages.filter { message in
                if message.containsSecretMedia || seen.contains(message.id) {
                    return false
                }
                if let minDate, message.timestamp < minDate {
                    return false
                }
                if let maxDate, message.timestamp > maxDate {
                    return false
                }
                seen.insert(message.id)
                return true
            }.sorted(by: { $0.timestamp < $1.timestamp })
            DkxLog.write("drive", "найдено медиа \(filtered.count)")

            guard !filtered.isEmpty else {
                showAlert(DkxStrings.tr("Ничего не нашлось"), DkxStrings.tr("За этот период в чате нет медиа выбранных типов."))
                return
            }
            var bytes: Int64 = 0
            for message in filtered {
                for media in message.media {
                    if let file = media as? TelegramMediaFile, let size = file.size {
                        bytes += size
                    }
                }
            }
            var text = DkxStrings.tr("Файлов {}", filtered.count)
            if bytes > 0 {
                text += DkxStrings.tr(", объём около {}", dkxSizeText(bytes))
            }
            if filtered.count >= dkxChatMediaCap {
                text += DkxStrings.tr(". Это предел за один раз, остальное выгрузите следующим заходом")
            }
            text += "."
            presentControllerImpl?(textAlertController(context: context, title: DkxStrings.tr("Выгрузить на Google Drive?"), text: text, actions: [
                TextAlertAction(type: .genericAction, title: DkxStrings.tr("Отмена"), action: {}),
                TextAlertAction(type: .defaultAction, title: DkxStrings.tr("Выгрузить"), action: {
                    dkxUploadMessagesToDrive(context: context, messages: filtered, present: { controller, _ in
                        presentControllerImpl?(controller)
                    })
                })
            ]))
        }))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(DkxStrings.tr("Медиа в Google Drive")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxChatMediaEntries(state: state, dateTimeFormat: presentationData.dateTimeFormat), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        searchDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
