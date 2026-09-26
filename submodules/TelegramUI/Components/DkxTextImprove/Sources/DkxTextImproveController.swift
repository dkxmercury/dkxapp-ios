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

// MARK: DKX экран «Улучшить текст», открывается кнопкой в поле ввода. Сразу
// просит вариант с прошлыми настройками, смена стиля, смайликов, обращения
// или языка просит заново. Готовый вариант можно поправить руками, «Заменить»
// кладёт его в поле ввода вместо исходного.

private enum DkxImproveStatus: Equatable {
    case loading
    case done(String)
    case failed(String)
}

private struct DkxImproveState: Equatable {
    var options: DkxImproveOptions
    var result: String
    var status: DkxImproveStatus
    var variant: Int
}

private final class DkxImproveArguments {
    let updateResult: (String) -> Void
    let again: () -> Void
    let selectStyle: (Int32) -> Void
    let updateCustom: (String) -> Void
    let applyCustom: () -> Void
    let selectEmoji: (Int32) -> Void
    let selectAddress: (Int32) -> Void
    let selectLanguage: (Int32) -> Void

    init(updateResult: @escaping (String) -> Void, again: @escaping () -> Void, selectStyle: @escaping (Int32) -> Void, updateCustom: @escaping (String) -> Void, applyCustom: @escaping () -> Void, selectEmoji: @escaping (Int32) -> Void, selectAddress: @escaping (Int32) -> Void, selectLanguage: @escaping (Int32) -> Void) {
        self.updateResult = updateResult
        self.again = again
        self.selectStyle = selectStyle
        self.updateCustom = updateCustom
        self.applyCustom = applyCustom
        self.selectEmoji = selectEmoji
        self.selectAddress = selectAddress
        self.selectLanguage = selectLanguage
    }
}

private enum DkxImproveEntry: ItemListNodeEntry {
    case resultHeader
    case result(String)
    case status(String)
    case again(Bool)
    case styleHeader
    case style(index: Int32, title: String, checked: Bool)
    case custom(String)
    case applyCustom
    case emojiHeader
    case emoji(index: Int32, title: String, checked: Bool)
    case addressHeader
    case address(index: Int32, title: String, checked: Bool)
    case languageHeader
    case language(index: Int32, title: String, checked: Bool)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .resultHeader, .result, .status, .again:
            return 0
        case .styleHeader, .style, .custom, .applyCustom:
            return 1
        case .emojiHeader, .emoji:
            return 2
        case .addressHeader, .address:
            return 3
        case .languageHeader, .language, .footer:
            return 4
        }
    }

    var stableId: Int32 {
        switch self {
        case .resultHeader:
            return 0
        case .result:
            return 1
        case .status:
            return 2
        case .again:
            return 3
        case .styleHeader:
            return 100
        case let .style(index, _, _):
            return 101 + index
        case .custom:
            return 150
        case .applyCustom:
            return 151
        case .emojiHeader:
            return 200
        case let .emoji(index, _, _):
            return 201 + index
        case .addressHeader:
            return 300
        case let .address(index, _, _):
            return 301 + index
        case .languageHeader:
            return 400
        case let .language(index, _, _):
            return 401 + index
        case .footer:
            return 499
        }
    }

    static func <(lhs: DkxImproveEntry, rhs: DkxImproveEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxImproveArguments
        switch self {
        case .resultHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ГОТОВЫЙ ВАРИАНТ", sectionId: self.section)
        case let .result(text):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Здесь появится улучшенный текст", maxLength: nil, sectionId: self.section, style: .blocks, minimalHeight: 80.0, textUpdated: { value in
                arguments.updateResult(value)
            })
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .again(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Ещё вариант", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.again()
            })
        case .styleHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СТИЛЬ", sectionId: self.section)
        case let .style(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectStyle(index)
            })
        case let .custom(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: "Например, строже и без приветствия", type: .regular(capitalization: true, autocorrection: true), sectionId: self.section, textUpdated: { value in
                arguments.updateCustom(value)
            }, action: {
                arguments.applyCustom()
            })
        case .applyCustom:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Применить свой стиль", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyCustom()
            })
        case .emojiHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СМАЙЛИКИ", sectionId: self.section)
        case let .emoji(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectEmoji(index)
            })
        case .addressHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ОБРАЩЕНИЕ", sectionId: self.section)
        case let .address(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectAddress(index)
            })
        case .languageHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЯЗЫК", sectionId: self.section)
        case let .language(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectLanguage(index)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func dkxImproveEntries(state: DkxImproveState, todayCount: Int32) -> [DkxImproveEntry] {
    var entries: [DkxImproveEntry] = []
    entries.append(.resultHeader)
    entries.append(.result(state.result))
    switch state.status {
    case .loading:
        entries.append(.status("Думаю…"))
    case let .done(provider):
        entries.append(.status("Написал \(provider). Текст можно поправить здесь же, потом «Заменить» вверху."))
    case let .failed(reason):
        entries.append(.status("Не получилось, \(reason)."))
    }
    entries.append(.again(state.status != .loading))

    entries.append(.styleHeader)
    for (index, title) in dkxImproveStyles.enumerated() {
        entries.append(.style(index: Int32(index), title: title, checked: Int32(index) == state.options.style))
    }
    if Int(state.options.style) == dkxImproveStyles.count - 1 {
        entries.append(.custom(state.options.custom))
        entries.append(.applyCustom)
    }
    entries.append(.emojiHeader)
    for (index, title) in dkxImproveEmoji.enumerated() {
        entries.append(.emoji(index: Int32(index), title: title, checked: Int32(index) == state.options.emoji))
    }
    entries.append(.addressHeader)
    for (index, title) in dkxImproveAddress.enumerated() {
        entries.append(.address(index: Int32(index), title: title, checked: Int32(index) == state.options.address))
    }
    entries.append(.languageHeader)
    for (index, title) in dkxImproveLanguages.enumerated() {
        entries.append(.language(index: Int32(index), title: title, checked: Int32(index) == state.options.language))
    }
    entries.append(.footer("Сегодня запросов \(todayCount). Русский и английский улучшает GLM, узбекский Gemini, при сбое запрос уходит в другой сервис. Бесплатный Gemini может показывать тексты сотрудникам Google, личное туда лучше не отправлять."))
    return entries
}

private func dkxTodayStamp() -> Int32 {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    return Int32((components.year ?? 0) * 10000 + (components.month ?? 0) * 100 + (components.day ?? 0))
}

public func dkxTextImproveController(context: AccountContext, text: String, apply: @escaping (String) -> Void) -> ViewController {
    let accountManager = context.sharedContext.accountManager
    let settings = DkxRuntime.current
    let initialOptions = DkxImproveOptions(style: settings.improveStyle, custom: settings.improveCustom, emoji: settings.improveEmoji, address: settings.improveAddress, language: settings.improveLanguage)
    let initial = DkxImproveState(options: initialOptions, result: "", status: .loading, variant: 0)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let updateState: ((inout DkxImproveState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }

    let requestDisposable = MetaDisposable()
    var dismissImpl: (() -> Void)?

    // Прошлые настройки запоминаются, в следующий раз экран откроется с ними
    let saveOptions: (DkxImproveOptions) -> Void = { options in
        let _ = updateDkxSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            updated.improveStyle = options.style
            updated.improveCustom = options.custom
            updated.improveEmoji = options.emoji
            updated.improveAddress = options.address
            updated.improveLanguage = options.language
            return updated
        }).start()
    }

    let countRequest: () -> Void = {
        let today = dkxTodayStamp()
        let _ = updateDkxSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            if updated.improveDay != today {
                updated.improveDay = today
                updated.improveCount = 0
            }
            updated.improveCount += 1
            return updated
        }).start()
    }

    let run: () -> Void = {
        let state = stateValue.with { $0 }
        updateState { $0.status = .loading }
        requestDisposable.set((dkxImproveText(text, options: state.options, variant: state.variant)
        |> deliverOnMainQueue).start(next: { result, provider in
            countRequest()
            updateState { state in
                state.result = result
                state.status = .done(provider.title)
            }
        }, error: { error in
            updateState { state in
                switch error {
                case .noKeys:
                    state.status = .failed("нет ключей. Вставьте ключ Gemini или GLM в Dkx, раздел «Улучшить текст»")
                case let .failed(reason):
                    state.status = .failed(reason)
                }
            }
        }))
    }

    let changeOptions: ((inout DkxImproveOptions) -> Void) -> Void = { f in
        updateState { state in
            f(&state.options)
            state.variant = 0
        }
        saveOptions(stateValue.with { $0.options })
        run()
    }

    let arguments = DkxImproveArguments(updateResult: { value in
        updateState { $0.result = value }
    }, again: {
        updateState { $0.variant += 1 }
        run()
    }, selectStyle: { index in
        // Свой стиль просим только после ввода указания, пустой ничего не даст
        if Int(index) == dkxImproveStyles.count - 1 {
            updateState { $0.options.style = index }
            saveOptions(stateValue.with { $0.options })
            return
        }
        changeOptions { $0.style = index }
    }, updateCustom: { value in
        updateState { $0.options.custom = value }
    }, applyCustom: {
        changeOptions { _ in }
    }, selectEmoji: { index in
        changeOptions { $0.emoji = index }
    }, selectAddress: { index in
        changeOptions { $0.address = index }
    }, selectLanguage: { index in
        changeOptions { $0.language = index }
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get(),
        accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings])
    )
    |> map { presentationData, state, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings
        let todayCount = settings.improveDay == dkxTodayStamp() ? settings.improveCount : 0
        let canApply = !state.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.status != .loading
        let leftButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
            dismissImpl?()
        })
        let rightButton = ItemListNavigationButton(content: .text("Заменить"), style: .bold, enabled: canApply, action: {
            let result = stateValue.with { $0.result }
            apply(result)
            dismissImpl?()
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Улучшить текст"), leftNavigationButton: leftButton, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxImproveEntries(state: state, todayCount: todayCount), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        requestDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    run()
    return controller
}
