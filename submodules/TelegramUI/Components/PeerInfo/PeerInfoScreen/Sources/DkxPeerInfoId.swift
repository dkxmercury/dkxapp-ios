import Foundation
import UIKit
import Display
import AccountContext
import TelegramCore
import TelegramPresentationData
import UndoUI
import TelegramUIPreferences

// MARK: DKX. Числовой Telegram ID в профиле, по нажатию копируется.
//
// Формат тот же, что ждёт Bot API и что показывают боты вроде @userinfobot:
// пользователи и боты как есть, обычные группы с минусом, каналы и
// супергруппы в виде -100 и дальше число. Считается арифметикой, а не
// склейкой строк, иначе у коротких идентификаторов потерялись бы нули.

func dkxBotApiId(_ peerId: EnginePeer.Id) -> String? {
    let raw = peerId.id._internalGetInt64Value()
    switch peerId.namespace {
    case Namespaces.Peer.CloudUser:
        return "\(raw)"
    case Namespaces.Peer.CloudGroup:
        return "\(-raw)"
    case Namespaces.Peer.CloudChannel:
        return "\(-(1000000000000 + raw))"
    default:
        // Секретные чаты и прочие локальные пространства: у них нет ID,
        // который понял бы кто-то снаружи
        return nil
    }
}

func dkxPeerIdItem(id: AnyHashable, peerId: EnginePeer.Id, presentationData: PresentationData, interaction: PeerInfoInteraction) -> PeerInfoScreenItem? {
    guard DkxRuntime.current.showPeerId, let text = dkxBotApiId(peerId) else {
        return nil
    }
    let copy: () -> Void = { [weak interaction] in
        UIPasteboard.general.string = text
        guard let controller = interaction?.getController() else {
            return
        }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .copy(text: "ID скопирован"), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
    }
    return PeerInfoScreenLabeledValueItem(
        id: id,
        label: "Telegram ID",
        text: text,
        textColor: .primary,
        action: { _, _ in
            copy()
        },
        longTapAction: { _ in
            copy()
        },
        requestLayout: { _ in
        }
    )
}
