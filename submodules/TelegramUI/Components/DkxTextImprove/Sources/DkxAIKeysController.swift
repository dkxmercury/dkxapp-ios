import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// MARK: DKX ключи Gemini и GLM для «Улучшить текст». Ключ вставляется из
// буфера, перед сохранением проверяется коротким запросом.

private struct DkxAIKeysState: Equatable {
    var drafts: [String: String] = [:]
    var checking: String?
    var messages: [String: String] = [:]
    // Просто повод перерисовать строки после сохранения в Keychain
    var revision = 0
}

private final class DkxAIKeysArguments {
    let updateDraft: (DkxAIKeys.Provider, String) -> Void
    let paste: (DkxAIKeys.Provider) -> Void
    let save: (DkxAIKeys.Provider) -> Void
    let delete: (DkxAIKeys.Provider) -> Void

    init(updateDraft: @escaping (DkxAIKeys.Provider, String) -> Void, paste: @escaping (DkxAIKeys.Provider) -> Void, save: @escaping (DkxAIKeys.Provider) -> Void, delete: @escaping (DkxAIKeys.Provider) -> Void) {
        self.updateDraft = updateDraft
        self.paste = paste
        self.save = save
        self.delete = delete
    }
}

private enum DkxAIKeysEntry: ItemListNodeEntry {
    case header(Int32, String)
    case current(Int32, String)
    case input(Int32, DkxAIKeys.Provider, String)
    case paste(Int32, DkxAIKeys.Provider)
    case save(Int32, DkxAIKeys.Provider, Bool)
    case delete(Int32, DkxAIKeys.Provider)
    case footer(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .current(section, _), let .input(section, _, _), let .paste(section, _), let .save(section, _, _), let .delete(section, _), let .footer(section, _):
            return section
        }
    }

    var stableId: Int32 {
        let base = self.section * 100
        switch self {
        case .header:
            return base
        case .current:
            return base + 1
        case .input:
            return base + 2
        case .paste:
            return base + 3
        case .save:
            return base + 4
        case .delete:
            return base + 5
        case .footer:
            return base + 99
        }
    }

    static func <(lhs: DkxAIKeysEntry, rhs: DkxAIKeysEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxAIKeysArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .current(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .input(_, provider, text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: "Вставьте ключ", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateDraft(provider, value)
            }, action: {
                arguments.save(provider)
            })
        case let .paste(_, provider):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Вставить из буфера", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.paste(provider)
            })
        case let .save(_, provider, checking):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: checking ? "Проверяю…" : "Проверить и сохранить", kind: checking ? .disabled : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.save(provider)
            })
        case let .delete(_, provider):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Удалить ключ", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.delete(provider)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func dkxAIKeysEntries(state: DkxAIKeysState) -> [DkxAIKeysEntry] {
    var entries: [DkxAIKeysEntry] = []
    for (index, provider) in DkxAIKeys.Provider.allCases.enumerated() {
        let section = Int32(index)
        entries.append(.header(section, provider == .gemini ? "GEMINI, ДЛЯ УЗБЕКСКОГО" : "GLM, ДЛЯ РУССКОГО И АНГЛИЙСКОГО"))
        if let masked = DkxAIKeys.maskedKey(provider) {
            entries.append(.current(section, "Сохранён ключ \(masked)"))
        } else {
            entries.append(.current(section, "Ключа нет"))
        }
        entries.append(.input(section, provider, state.drafts[provider.rawValue] ?? ""))
        entries.append(.paste(section, provider))
        entries.append(.save(section, provider, state.checking == provider.rawValue))
        if DkxAIKeys.key(provider) != nil {
            entries.append(.delete(section, provider))
        }
        var footer = provider == .gemini ? "Ключ в Google AI Studio, раздел Get API key." : "Ключ на z.ai, раздел API Keys. Бесплатные модели GLM Flash."
        if let message = state.messages[provider.rawValue] {
            footer = message + "\n\n" + footer
        }
        entries.append(.footer(section, footer))
    }
    return entries
}

public func dkxAIKeysController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(DkxAIKeysState(), ignoreRepeated: true)
    let stateValue = Atomic(value: DkxAIKeysState())
    let updateState: ((inout DkxAIKeysState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }
    let checkDisposable = MetaDisposable()

    let arguments = DkxAIKeysArguments(updateDraft: { provider, value in
        updateState { $0.drafts[provider.rawValue] = value }
    }, paste: { provider in
        let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updateState { state in
            state.drafts[provider.rawValue] = value
            state.messages[provider.rawValue] = value.isEmpty ? "В буфере нет текста." : nil
        }
    }, save: { provider in
        let key = (stateValue.with { $0.drafts[provider.rawValue] } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, stateValue.with({ $0.checking }) == nil else {
            return
        }
        updateState { state in
            state.checking = provider.rawValue
            state.messages[provider.rawValue] = nil
        }
        checkDisposable.set((dkxCheckKey(provider: provider, key: key)
        |> deliverOnMainQueue).start(error: { error in
            var reason = "не удалось проверить"
            if case let .failed(text) = error {
                reason = text
            }
            updateState { state in
                state.checking = nil
                state.messages[provider.rawValue] = "Ключ не сохранён, \(reason)."
            }
        }, completed: {
            DkxAIKeys.setKey(provider, key)
            updateState { state in
                state.checking = nil
                state.drafts[provider.rawValue] = ""
                state.messages[provider.rawValue] = "Ключ работает и сохранён."
                state.revision += 1
            }
        }))
    }, delete: { provider in
        DkxAIKeys.setKey(provider, nil)
        updateState { state in
            state.messages[provider.rawValue] = "Ключ удалён."
            state.revision += 1
        }
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Ключи"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxAIKeysEntries(state: state), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        checkDisposable.dispose()
    }

    return ItemListController(context: context, state: signal)
}
