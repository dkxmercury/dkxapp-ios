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

private func dkxAIKeyHint(_ provider: DkxAIKeys.Provider) -> String {
    switch provider {
    case .deepseek:
        return DkxStrings.tr("Ключ берётся на platform.deepseek.com в разделе API Keys.")
    case .qwen:
        return DkxStrings.tr("Ключ берётся в Alibaba Cloud Model Studio в разделе API Key. Адрес по умолчанию международный, для Китая его можно сменить ниже.")
    case .glm:
        return DkxStrings.tr("Ключ берётся на z.ai в разделе API Keys. Модели Flash там бесплатные.")
    case .openai:
        return DkxStrings.tr("Ключ берётся на platform.openai.com в разделе API keys.")
    case .claude:
        return DkxStrings.tr("Ключ берётся на console.anthropic.com в разделе API Keys.")
    case .xiaomi:
        return DkxStrings.tr("Ключ берётся на платформе Xiaomi MiMo в разделе API Keys. Если сервис сменил адрес, впишите новый ниже.")
    case .cloudflare:
        return DkxStrings.tr("Нужны токен с правом Workers AI и номер аккаунта. Оба есть в панели Cloudflare, номер аккаунта справа на главной странице.")
    case .mistral:
        return DkxStrings.tr("Ключ берётся на console.mistral.ai в разделе API Keys.")
    case .gemini:
        return DkxStrings.tr("Ключ берётся в Google AI Studio, кнопка Get API key.")
    case .openrouter:
        return DkxStrings.tr("Ключ берётся на openrouter.ai в разделе Keys. В списке только бесплатные модели разных компаний.")
    }
}

private func dkxAIStatus(_ provider: DkxAIKeys.Provider) -> String {
    if DkxAIKeys.key(provider) == nil {
        return DkxStrings.tr("нет ключа")
    }
    if provider.needsAccount && DkxAIKeys.account(provider) == nil {
        return DkxStrings.tr("нет номера аккаунта")
    }
    guard let model = DkxAIKeys.model(provider) else {
        return DkxStrings.tr("выберите модель")
    }
    if DkxAIKeys.main == provider {
        return DkxStrings.tr("основной, {}", model)
    }
    return model
}

// Строка для раздела «API ИИ» в Dkx
public func dkxAISummary() -> String {
    let ready = DkxAIKeys.Provider.allCases.filter { DkxAIKeys.isReady($0) }
    if ready.isEmpty {
        return DkxStrings.tr("не подключены")
    }
    if let main = DkxAIKeys.main, DkxAIKeys.isReady(main) {
        return main.title
    }
    return ready.map { $0.title }.joined(separator: ", ")
}

private final class DkxAIListArguments {
    let open: (DkxAIKeys.Provider) -> Void

    init(open: @escaping (DkxAIKeys.Provider) -> Void) {
        self.open = open
    }
}

private enum DkxAIListEntry: ItemListNodeEntry {
    case header
    case provider(Int32, DkxAIKeys.Provider, String)
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .provider(index, _, _):
            return 1 + index
        case .footer:
            return 1000
        }
    }

    static func <(lhs: DkxAIListEntry, rhs: DkxAIListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxAIListArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("СЕРВИСЫ"), sectionId: self.section)
        case let .provider(_, provider, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: provider.title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.open(provider)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func dkxAIKeysController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = DkxAIListArguments(open: { provider in
        pushControllerImpl?(dkxAIProviderController(context: context, provider: provider))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxAIListEntry] = [.header]
        for (index, provider) in DkxAIKeys.Provider.allCases.enumerated() {
            entries.append(.provider(Int32(index), provider, dkxAIStatus(provider)))
        }
        entries.append(.footer(DkxStrings.tr("Здесь подключаются сервисы ИИ для «Улучшить текст» и «Совет ИИ» в аналитике. Откройте сервис, вставьте ключ с его сайта и выберите модель из списка. Можно подключить несколько. Первым работает основной сервис, если он не ответил, запрос сам уходит в следующий. Для узбекского текста первым идёт Gemini, если он подключён.\n\nКлючи хранятся в Keychain этого телефона. Они переживают переустановку приложения и никуда, кроме самого сервиса, не отправляются.")))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(DkxStrings.tr("API ИИ")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    // Ключи лежат в Keychain, после возврата с экрана сервиса перерисовываем сами
    controller.didAppear = { _ in
        refresh.set(0)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

private struct DkxAIProviderState: Equatable {
    var draftKey = ""
    var draftAccount = ""
    var draftModel = ""
    var draftBase = ""
    var busy = false
    var keyMessage: String?
    var modelMessage: String?
    var models: [DkxAIModel]?
    var revision = 0
}

private final class DkxAIProviderArguments {
    let updateKey: (String) -> Void
    let updateAccount: (String) -> Void
    let updateModel: (String) -> Void
    let updateBase: (String) -> Void
    let pasteKey: () -> Void
    let checkKey: () -> Void
    let deleteKey: () -> Void
    let pickModel: () -> Void
    let saveModel: () -> Void
    let makeMain: () -> Void
    let saveBase: () -> Void

    init(updateKey: @escaping (String) -> Void, updateAccount: @escaping (String) -> Void, updateModel: @escaping (String) -> Void, updateBase: @escaping (String) -> Void, pasteKey: @escaping () -> Void, checkKey: @escaping () -> Void, deleteKey: @escaping () -> Void, pickModel: @escaping () -> Void, saveModel: @escaping () -> Void, makeMain: @escaping () -> Void, saveBase: @escaping () -> Void) {
        self.updateKey = updateKey
        self.updateAccount = updateAccount
        self.updateModel = updateModel
        self.updateBase = updateBase
        self.pasteKey = pasteKey
        self.checkKey = checkKey
        self.deleteKey = deleteKey
        self.pickModel = pickModel
        self.saveModel = saveModel
        self.makeMain = makeMain
        self.saveBase = saveBase
    }
}

private enum DkxAIProviderEntry: ItemListNodeEntry {
    case keyHeader
    case keyCurrent(String)
    case keyInput(String)
    case keyPaste
    case accountInput(String)
    case keyCheck(Bool, Bool)
    case keyDelete
    case keyFooter(String)
    case modelHeader
    case modelCurrent(String)
    case modelPick(Bool)
    case modelInput(String)
    case modelSave(Bool)
    case modelFooter(String)
    case mainHeader
    case mainAction(Bool, Bool)
    case mainFooter(String)
    case baseHeader
    case baseInput(String, String)
    case baseSave
    case baseFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .keyHeader, .keyCurrent, .keyInput, .keyPaste, .accountInput, .keyCheck, .keyDelete, .keyFooter:
            return 0
        case .modelHeader, .modelCurrent, .modelPick, .modelInput, .modelSave, .modelFooter:
            return 1
        case .mainHeader, .mainAction, .mainFooter:
            return 2
        case .baseHeader, .baseInput, .baseSave, .baseFooter:
            return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .keyHeader:
            return 0
        case .keyCurrent:
            return 1
        case .keyInput:
            return 2
        case .keyPaste:
            return 3
        case .accountInput:
            return 4
        case .keyCheck:
            return 5
        case .keyDelete:
            return 6
        case .keyFooter:
            return 7
        case .modelHeader:
            return 100
        case .modelCurrent:
            return 101
        case .modelPick:
            return 102
        case .modelInput:
            return 103
        case .modelSave:
            return 104
        case .modelFooter:
            return 105
        case .mainHeader:
            return 200
        case .mainAction:
            return 201
        case .mainFooter:
            return 202
        case .baseHeader:
            return 300
        case .baseInput:
            return 301
        case .baseSave:
            return 302
        case .baseFooter:
            return 303
        }
    }

    static func <(lhs: DkxAIProviderEntry, rhs: DkxAIProviderEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxAIProviderArguments
        switch self {
        case .keyHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("КЛЮЧ"), sectionId: self.section)
        case let .keyCurrent(text), let .modelCurrent(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .keyInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: DkxStrings.tr("Вставьте ключ"), type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateKey(value)
            }, action: {
                arguments.checkKey()
            })
        case .keyPaste:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Вставить из буфера"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.pasteKey()
            })
        case let .accountInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: DkxStrings.tr("Номер аккаунта Cloudflare"), type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateAccount(value)
            }, action: {
                arguments.checkKey()
            })
        case let .keyCheck(busy, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: busy ? DkxStrings.tr("Проверяю…") : DkxStrings.tr("Проверить ключ и загрузить модели"), kind: busy || !enabled ? .disabled : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.checkKey()
            })
        case .keyDelete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Удалить ключ"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.deleteKey()
            })
        case let .keyFooter(text), let .modelFooter(text), let .mainFooter(text), let .baseFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .modelHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("МОДЕЛЬ"), sectionId: self.section)
        case let .modelPick(enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Выбрать из списка"), enabled: enabled, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.pickModel()
            })
        case let .modelInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: DkxStrings.tr("Или впишите название модели"), type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateModel(value)
            }, action: {
                arguments.saveModel()
            })
        case let .modelSave(busy):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: busy ? DkxStrings.tr("Проверяю…") : DkxStrings.tr("Проверить и выбрать эту модель"), kind: busy ? .disabled : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.saveModel()
            })
        case .mainHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ОСНОВНОЙ СЕРВИС"), sectionId: self.section)
        case let .mainAction(isMain, ready):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: isMain ? DkxStrings.tr("Это основной сервис") : DkxStrings.tr("Сделать основным"), kind: isMain || !ready ? .disabled : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.makeMain()
            })
        case .baseHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("АДРЕС API"), sectionId: self.section)
        case let .baseInput(text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateBase(value)
            }, action: {
                arguments.saveBase()
            })
        case .baseSave:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Сохранить адрес"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.saveBase()
            })
        }
    }
}

private func dkxAIProviderEntries(provider: DkxAIKeys.Provider, state: DkxAIProviderState) -> [DkxAIProviderEntry] {
    var entries: [DkxAIProviderEntry] = []
    let hasKey = DkxAIKeys.key(provider) != nil
    entries.append(.keyHeader)
    if let masked = DkxAIKeys.maskedKey(provider) {
        entries.append(.keyCurrent(DkxStrings.tr("Сохранён ключ {}", masked)))
    } else {
        entries.append(.keyCurrent(DkxStrings.tr("Ключа нет")))
    }
    entries.append(.keyInput(state.draftKey))
    entries.append(.keyPaste)
    if provider.needsAccount {
        entries.append(.accountInput(state.draftAccount))
    }
    entries.append(.keyCheck(state.busy, hasKey || !state.draftKey.isEmpty))
    if hasKey {
        entries.append(.keyDelete)
    }
    var keyFooter = dkxAIKeyHint(provider)
    if let message = state.keyMessage {
        keyFooter = message + "\n\n" + keyFooter
    }
    entries.append(.keyFooter(keyFooter))

    entries.append(.modelHeader)
    if let model = DkxAIKeys.model(provider) {
        entries.append(.modelCurrent(DkxStrings.tr("Выбрана модель {}", model)))
    } else {
        entries.append(.modelCurrent(DkxStrings.tr("Модель не выбрана, сервис пока не работает")))
    }
    entries.append(.modelPick(hasKey))
    entries.append(.modelInput(state.draftModel))
    entries.append(.modelSave(state.busy))
    var modelFooter = DkxStrings.tr("Список моделей приходит от самого сервиса по вашему ключу. Если сервис список не отдаёт, впишите название модели с его сайта. Перед выбором модель проверяется коротким запросом.")
    if let message = state.modelMessage {
        modelFooter = message + "\n\n" + modelFooter
    }
    entries.append(.modelFooter(modelFooter))

    entries.append(.mainHeader)
    entries.append(.mainAction(DkxAIKeys.main == provider, DkxAIKeys.isReady(provider)))
    entries.append(.mainFooter(DkxStrings.tr("Основной сервис получает запросы первым. Остальные подключённые сервисы подстраховывают, если он не ответил.")))

    entries.append(.baseHeader)
    entries.append(.baseInput(state.draftBase, provider.defaultBase))
    entries.append(.baseSave)
    entries.append(.baseFooter(DkxStrings.tr("Обычно менять не нужно. Пустое поле значит адрес по умолчанию, он написан серым.")))
    return entries
}

private func dkxAIProviderController(context: AccountContext, provider: DkxAIKeys.Provider) -> ViewController {
    var initial = DkxAIProviderState()
    initial.draftAccount = DkxAIKeys.account(provider) ?? ""
    initial.draftBase = DkxAIKeys.customBase(provider) ?? ""
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let updateState: ((inout DkxAIProviderState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }
    let requestDisposable = MetaDisposable()
    var pushControllerImpl: ((ViewController) -> Void)?

    func reasonText(_ error: DkxImproveError) -> String {
        switch error {
        case .noKeys:
            return DkxStrings.tr("нет ключа")
        case let .failed(text):
            return text
        }
    }

    let currentKey: () -> String? = {
        let draft = stateValue.with { $0.draftKey }.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.isEmpty ? DkxAIKeys.key(provider) : draft
    }

    // Модель проверяется запросом, ключ из черновика сохраняется только вместе с рабочей моделью
    let chooseModel: (String) -> Void = { model in
        guard let key = currentKey(), !model.isEmpty else {
            updateState { $0.modelMessage = DkxStrings.tr("Сначала вставьте ключ.") }
            return
        }
        if provider.needsAccount {
            DkxAIKeys.setAccount(provider, stateValue.with { $0.draftAccount })
        }
        updateState { state in
            state.busy = true
            state.modelMessage = nil
        }
        requestDisposable.set((dkxAICheckModel(provider: provider, key: key, model: model)
        |> deliverOnMainQueue).start(error: { error in
            updateState { state in
                state.busy = false
                state.modelMessage = DkxStrings.tr("Модель {} не ответила, {}.", model, reasonText(error))
            }
        }, completed: {
            DkxAIKeys.setKey(provider, key)
            DkxAIKeys.setModel(provider, model)
            if DkxAIKeys.main == nil {
                DkxAIKeys.setMain(provider)
            }
            updateState { state in
                state.busy = false
                state.draftKey = ""
                state.draftModel = ""
                state.modelMessage = DkxStrings.tr("Модель {} отвечает и выбрана.", model)
                state.revision += 1
            }
        }))
    }

    let openPicker: ([DkxAIModel]) -> Void = { models in
        pushControllerImpl?(dkxAIModelPickerController(context: context, provider: provider, models: models, select: { model in
            chooseModel(model)
        }))
    }

    let loadModels: (Bool) -> Void = { openAfter in
        guard let key = currentKey() else {
            updateState { $0.keyMessage = DkxStrings.tr("Сначала вставьте ключ.") }
            return
        }
        if provider.needsAccount {
            let account = stateValue.with { $0.draftAccount }.trimmingCharacters(in: .whitespacesAndNewlines)
            if account.isEmpty {
                updateState { $0.keyMessage = DkxStrings.tr("Впишите номер аккаунта Cloudflare.") }
                return
            }
            DkxAIKeys.setAccount(provider, account)
        }
        updateState { state in
            state.busy = true
            state.keyMessage = nil
        }
        requestDisposable.set((dkxAIListModels(provider: provider, key: key)
        |> deliverOnMainQueue).start(next: { models in
            let sorted = models.sorted(by: { $0.id.lowercased() < $1.id.lowercased() })
            DkxAIKeys.setKey(provider, key)
            updateState { state in
                state.busy = false
                state.draftKey = ""
                state.models = sorted
                state.keyMessage = sorted.isEmpty ? DkxStrings.tr("Ключ работает, но сервис не отдал ни одной модели. Впишите модель вручную.") : DkxStrings.tr("Ключ работает. Моделей {}, выберите одну.", sorted.count)
                state.revision += 1
            }
            if openAfter && !sorted.isEmpty {
                openPicker(sorted)
            }
        }, error: { error in
            updateState { state in
                state.busy = false
                state.keyMessage = DkxStrings.tr("Список моделей не получен, {}. Если ключ верный, впишите модель вручную ниже, ключ сохранится вместе с ней.", reasonText(error))
            }
        }))
    }

    let arguments = DkxAIProviderArguments(updateKey: { value in
        updateState { $0.draftKey = value }
    }, updateAccount: { value in
        updateState { $0.draftAccount = value }
    }, updateModel: { value in
        updateState { $0.draftModel = value }
    }, updateBase: { value in
        updateState { $0.draftBase = value }
    }, pasteKey: {
        let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updateState { state in
            state.draftKey = value
            state.keyMessage = value.isEmpty ? DkxStrings.tr("В буфере нет текста.") : nil
        }
    }, checkKey: {
        if stateValue.with({ $0.busy }) {
            return
        }
        loadModels(true)
    }, deleteKey: {
        requestDisposable.set(nil)
        DkxAIKeys.setKey(provider, nil)
        updateState { state in
            state.busy = false
            state.models = nil
            state.keyMessage = DkxStrings.tr("Ключ удалён.")
            state.revision += 1
        }
    }, pickModel: {
        if stateValue.with({ $0.busy }) {
            return
        }
        if let models = stateValue.with({ $0.models }), !models.isEmpty {
            openPicker(models)
        } else {
            loadModels(true)
        }
    }, saveModel: {
        if stateValue.with({ $0.busy }) {
            return
        }
        chooseModel(stateValue.with { $0.draftModel }.trimmingCharacters(in: .whitespacesAndNewlines))
    }, makeMain: {
        guard DkxAIKeys.isReady(provider) else {
            return
        }
        DkxAIKeys.setMain(provider)
        updateState { $0.revision += 1 }
    }, saveBase: {
        DkxAIKeys.setCustomBase(provider, stateValue.with { $0.draftBase })
        updateState { state in
            state.draftBase = DkxAIKeys.customBase(provider) ?? ""
            state.keyMessage = DkxStrings.tr("Адрес сохранён. Проверьте ключ заново.")
            state.models = nil
            state.revision += 1
        }
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(provider.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxAIProviderEntries(provider: provider, state: state), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        requestDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

private let dkxAIModelsPerPage = 50

private struct DkxAIPickerState: Equatable {
    var query = ""
    var page = 0
}

private final class DkxAIPickerArguments {
    let updateQuery: (String) -> Void
    let select: (String) -> Void
    let page: (Int) -> Void

    init(updateQuery: @escaping (String) -> Void, select: @escaping (String) -> Void, page: @escaping (Int) -> Void) {
        self.updateQuery = updateQuery
        self.select = select
        self.page = page
    }
}

private enum DkxAIPickerEntry: ItemListNodeEntry {
    case search(String)
    case model(Int32, DkxAIModel, Bool)
    case previous
    case next
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .search:
            return 0
        case .model:
            return 1
        case .previous, .next, .footer:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .search:
            return 0
        case let .model(index, _, _):
            return 10 + index
        case .previous:
            return 100000
        case .next:
            return 100001
        case .footer:
            return 100002
        }
    }

    static func <(lhs: DkxAIPickerEntry, rhs: DkxAIPickerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxAIPickerArguments
        switch self {
        case let .search(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: DkxStrings.tr("Поиск модели"), type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateQuery(value)
            }, action: {
            })
        case let .model(_, model, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: model.name, subtitle: model.name == model.id ? nil : model.id, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(model.id)
            })
        case .previous:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Предыдущие"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.page(-1)
            })
        case .next:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Следующие"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.page(1)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func dkxAIModelPickerController(context: AccountContext, provider: DkxAIKeys.Provider, models: [DkxAIModel], select: @escaping (String) -> Void) -> ViewController {
    let statePromise = ValuePromise(DkxAIPickerState(), ignoreRepeated: true)
    let stateValue = Atomic(value: DkxAIPickerState())
    let updateState: ((inout DkxAIPickerState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }
    var dismissImpl: (() -> Void)?

    let arguments = DkxAIPickerArguments(updateQuery: { value in
        updateState { state in
            state.query = value
            state.page = 0
        }
    }, select: { id in
        select(id)
        dismissImpl?()
    }, page: { delta in
        updateState { $0.page = max(0, $0.page + delta) }
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? models : models.filter { $0.id.lowercased().contains(query) || $0.name.lowercased().contains(query) }
        let pages = max(1, (filtered.count + dkxAIModelsPerPage - 1) / dkxAIModelsPerPage)
        let page = min(state.page, pages - 1)
        let current = DkxAIKeys.model(provider)
        var entries: [DkxAIPickerEntry] = [.search(state.query)]
        let start = page * dkxAIModelsPerPage
        for (offset, model) in filtered.dropFirst(start).prefix(dkxAIModelsPerPage).enumerated() {
            entries.append(.model(Int32(offset), model, model.id == current))
        }
        if page > 0 {
            entries.append(.previous)
        }
        if page < pages - 1 {
            entries.append(.next)
        }
        if filtered.isEmpty {
            entries.append(.footer(DkxStrings.tr("Ничего не нашлось. Название модели можно вписать вручную на прошлом экране.")))
        } else {
            entries.append(.footer(DkxStrings.tr("Страница {} из {}, моделей {}. Нажмите на модель, она проверится и станет рабочей.", page + 1, pages, filtered.count)))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(DkxStrings.tr("Модели {}", provider.title)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}
