import Foundation
import AuthenticationServices
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import LocalAudioTranscription
import ChatListUI
import DkxTextImprove
import ItemListUI
import PresentationDataUtils
import AccountContext

// Экран настроек форка. Сюда складываются все тумблеры, которые решает
// интерфейс. Строки захардкожены. Свои ключи в Localizable.strings требуют
// прогона GenerateStrings.py, а это отдельный шаг сборки ради форка на
// несколько устройств.
//
// Подмена геопозиции настраивается прямо на экране карты, здесь только
// выключатель её панели.

// Тумблеры фич форка. Каждая новая фича с выключателем добавляется сюда,
// в dkxToggleValue и dkxToggleUpdate ниже и строкой в список экрана.
private enum DkxToggle: Int32 {
    case contactBadge
    case noteInHeader
    case peerId
    case unanswered
    case quickReplies
    case authorMessages
    case chatExport
    case mediaNoCompression
    case chatLock
    case todo
    case passwords
    case remindLater
}

private var dkxUnansweredThresholds: [(hours: Int32, title: String)] {
    return [
        (0, DkxStrings.tr("Сразу")),
        (1, DkxStrings.tr("Ждёт больше часа")),
        (3, DkxStrings.tr("Ждёт больше 3 часов")),
        (24, DkxStrings.tr("Ждёт больше суток"))
    ]
}

private func dkxToggleValue(_ toggle: DkxToggle, _ settings: DkxSettings) -> Bool {
    switch toggle {
    case .contactBadge:
        return settings.showContactBadge
    case .noteInHeader:
        return settings.showNoteInHeader
    case .peerId:
        return settings.showPeerId
    case .unanswered:
        return settings.unansweredFilter
    case .quickReplies:
        return settings.quickReplies
    case .authorMessages:
        return settings.authorMessages
    case .chatExport:
        return settings.chatExport
    case .mediaNoCompression:
        return settings.mediaNoCompression
    case .chatLock:
        return settings.chatLock
    case .todo:
        return settings.todoEnabled
    case .passwords:
        return settings.passwordsEnabled
    case .remindLater:
        return settings.remindLater
    }
}

private func dkxToggleUpdate(_ toggle: DkxToggle, _ value: Bool, _ settings: inout DkxSettings) {
    switch toggle {
    case .contactBadge:
        settings.showContactBadge = value
    case .noteInHeader:
        settings.showNoteInHeader = value
    case .peerId:
        settings.showPeerId = value
    case .unanswered:
        settings.unansweredFilter = value
    case .quickReplies:
        settings.quickReplies = value
    case .authorMessages:
        settings.authorMessages = value
    case .chatExport:
        settings.chatExport = value
    case .mediaNoCompression:
        settings.mediaNoCompression = value
    case .chatLock:
        settings.chatLock = value
    case .todo:
        settings.todoEnabled = value
    case .passwords:
        settings.passwordsEnabled = value
    case .remindLater:
        settings.remindLater = value
    }
}

private func dkxToggleTitle(_ toggle: DkxToggle) -> String {
    switch toggle {
    case .contactBadge:
        return DkxStrings.tr("Метка «сохранил»")
    case .noteInHeader:
        return DkxStrings.tr("Заметка в шапке чата")
    case .peerId:
        return DkxStrings.tr("Telegram ID в профиле")
    case .unanswered:
        return DkxStrings.tr("Список «Без ответа»")
    case .quickReplies:
        return DkxStrings.tr("Шаблоны быстрых ответов")
    case .authorMessages:
        return DkxStrings.tr("Все сообщения автора в группе")
    case .chatExport:
        return DkxStrings.tr("Выгрузка чата в файл")
    case .mediaNoCompression:
        return DkxStrings.tr("Фото и видео без сжатия")
    case .chatLock:
        return DkxStrings.tr("Face ID на отдельные чаты")
    case .todo:
        return DkxStrings.tr("«Мои дела» в настройках")
    case .passwords:
        return DkxStrings.tr("«Пароли» в настройках")
    case .remindLater:
        return DkxStrings.tr("«Напомнить позже» у чатов и сообщений")
    }
}

private final class DkxSettingsControllerArguments {
    let updateHideStories: (Bool) -> Void
    let updateHidePremiumPromo: (Bool) -> Void
    let openAppIcon: () -> Void
    let openHiddenSections: () -> Void
    let updateAntiDelete: (Bool) -> Void
    let updateEditHistory: (Bool) -> Void
    let updateToggle: (DkxToggle, Bool) -> Void
    let updateUnansweredHours: (Int32) -> Void
    let updateTranscription: (Bool) -> Void
    let updateTranscriptionLocale: (String) -> Void
    let updateImproveText: (Bool) -> Void
    let openImproveKeys: () -> Void
    let openQuickReplies: () -> Void
    let openChatLabels: () -> Void
    let updateSpoofPanel: (Bool) -> Void
    let openLog: () -> Void
    let openDebug: () -> Void
    let updateDriveEnabled: (Bool) -> Void
    let connectDrive: () -> Void
    let switchDriveAccount: () -> Void
    let disconnectDrive: () -> Void

    init(
        updateHideStories: @escaping (Bool) -> Void,
        updateHidePremiumPromo: @escaping (Bool) -> Void,
        openAppIcon: @escaping () -> Void,
        openHiddenSections: @escaping () -> Void,
        updateAntiDelete: @escaping (Bool) -> Void,
        updateEditHistory: @escaping (Bool) -> Void,
        updateToggle: @escaping (DkxToggle, Bool) -> Void,
        updateUnansweredHours: @escaping (Int32) -> Void,
        updateTranscription: @escaping (Bool) -> Void,
        updateTranscriptionLocale: @escaping (String) -> Void,
        updateImproveText: @escaping (Bool) -> Void,
        openImproveKeys: @escaping () -> Void,
        openQuickReplies: @escaping () -> Void,
        openChatLabels: @escaping () -> Void,
        updateSpoofPanel: @escaping (Bool) -> Void,
        openLog: @escaping () -> Void,
        openDebug: @escaping () -> Void,
        updateDriveEnabled: @escaping (Bool) -> Void,
        connectDrive: @escaping () -> Void,
        switchDriveAccount: @escaping () -> Void,
        disconnectDrive: @escaping () -> Void
    ) {
        self.updateHideStories = updateHideStories
        self.updateHidePremiumPromo = updateHidePremiumPromo
        self.openAppIcon = openAppIcon
        self.openHiddenSections = openHiddenSections
        self.updateAntiDelete = updateAntiDelete
        self.updateEditHistory = updateEditHistory
        self.updateToggle = updateToggle
        self.updateUnansweredHours = updateUnansweredHours
        self.updateTranscription = updateTranscription
        self.updateTranscriptionLocale = updateTranscriptionLocale
        self.updateImproveText = updateImproveText
        self.openImproveKeys = openImproveKeys
        self.openQuickReplies = openQuickReplies
        self.openChatLabels = openChatLabels
        self.updateSpoofPanel = updateSpoofPanel
        self.openLog = openLog
        self.openDebug = openDebug
        self.updateDriveEnabled = updateDriveEnabled
        self.connectDrive = connectDrive
        self.switchDriveAccount = switchDriveAccount
        self.disconnectDrive = disconnectDrive
    }
}

private enum DkxSettingsSection: Int32 {
    case interface
    case chats
    case unanswered
    case transcription
    case improve
    case location
    case features
    case drive
    case debug
}

private enum DkxSettingsControllerEntry: ItemListNodeEntry {
    case interfaceHeader
    case hideStories(Bool)
    case hidePremiumPromo(Bool)
    case openAppIcon
    case openHiddenSections(Int32)
    case interfaceFooter

    case chatsHeader
    case toggle(DkxToggle, Bool)
    case openQuickReplies(Int32)
    case openChatLabels(Int32)
    case chatsFooter

    case unansweredHeader
    case unansweredThreshold(index: Int32, title: String, checked: Bool)
    case unansweredFooter

    case transcriptionHeader
    case transcription(Bool)
    case transcriptionLocale(index: Int32, id: String, title: String, checked: Bool)
    case transcriptionFooter(String)

    case improveHeader
    case improveToggle(Bool)
    case improveKeys(String)
    case improveFooter(String)

    case locationHeader
    case spoofPanel(Bool)
    case locationFooter(String)

    case featuresHeader
    case antiDelete(Bool)
    case editHistory(Bool)
    case featuresFooter

    case driveHeader
    case driveToggle(Bool)
    case driveAccount(String, Bool)
    case driveSwitch
    case driveDisconnect
    case driveFooter(String)
    case debugHeader
    case openLog
    case openDebug
    case debugFooter

    var section: ItemListSectionId {
        switch self {
        case .interfaceHeader, .hideStories, .hidePremiumPromo, .openAppIcon, .openHiddenSections, .interfaceFooter:
            return DkxSettingsSection.interface.rawValue
        case .chatsHeader, .toggle, .openQuickReplies, .openChatLabels, .chatsFooter:
            return DkxSettingsSection.chats.rawValue
        case .unansweredHeader, .unansweredThreshold, .unansweredFooter:
            return DkxSettingsSection.unanswered.rawValue
        case .transcriptionHeader, .transcription, .transcriptionLocale, .transcriptionFooter:
            return DkxSettingsSection.transcription.rawValue
        case .improveHeader, .improveToggle, .improveKeys, .improveFooter:
            return DkxSettingsSection.improve.rawValue
        case .locationHeader, .spoofPanel, .locationFooter:
            return DkxSettingsSection.location.rawValue
        case .featuresHeader, .antiDelete, .editHistory, .featuresFooter:
            return DkxSettingsSection.features.rawValue
        case .driveHeader, .driveToggle, .driveAccount, .driveSwitch, .driveDisconnect, .driveFooter:
            return DkxSettingsSection.drive.rawValue
        case .debugHeader, .openLog, .openDebug, .debugFooter:
            return DkxSettingsSection.debug.rawValue
        }
    }

    // Номера с запасом, по сотне на раздел, чтобы новые строки вставлялись
    // без перенумерации. Порядок на экране задаётся именно ими.
    var stableId: Int32 {
        switch self {
        case .interfaceHeader:
            return 0
        case .hideStories:
            return 1
        case .hidePremiumPromo:
            return 2
        case .openAppIcon:
            return 3
        case .openHiddenSections:
            return 4
        case .interfaceFooter:
            return 99
        case .chatsHeader:
            return 100
        // У тумблеров чётные номера, нечётное место сразу под тумблером
        // занимает его вложенная строка, если она есть
        case let .toggle(toggle, _):
            return 101 + toggle.rawValue * 2
        case .openQuickReplies:
            return 101 + DkxToggle.quickReplies.rawValue * 2 + 1
        case .openChatLabels:
            return 190
        case .chatsFooter:
            return 199
        case .unansweredHeader:
            return 200
        case let .unansweredThreshold(index, _, _):
            return 201 + index
        case .unansweredFooter:
            return 299
        case .transcriptionHeader:
            return 300
        case .transcription:
            return 301
        case let .transcriptionLocale(index, _, _, _):
            return 302 + index
        case .transcriptionFooter:
            return 399
        case .improveHeader:
            return 400
        case .improveToggle:
            return 401
        case .improveKeys:
            return 402
        case .improveFooter:
            return 499
        case .locationHeader:
            return 1000
        case .spoofPanel:
            return 1001
        case .locationFooter:
            return 1099
        case .featuresHeader:
            return 2000
        case .antiDelete:
            return 2001
        case .editHistory:
            return 2002
        case .featuresFooter:
            return 2003
        case .driveHeader:
            return 2500
        case .driveToggle:
            return 2501
        case .driveAccount:
            return 2502
        case .driveSwitch:
            return 2503
        case .driveDisconnect:
            return 2504
        case .driveFooter:
            return 2505
        case .debugHeader:
            return 3000
        case .openLog:
            return 3001
        case .openDebug:
            return 3002
        case .debugFooter:
            return 3003
        }
    }

    static func <(lhs: DkxSettingsControllerEntry, rhs: DkxSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxSettingsControllerArguments
        switch self {
        case .interfaceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ИНТЕРФЕЙС"), sectionId: self.section)
        case let .hideStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Скрыть ленту историй"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideStories(value)
            })
        case let .hidePremiumPromo(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Убрать навязывание премиума"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHidePremiumPromo(value)
            })
        case .openAppIcon:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Значок приложения"), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openAppIcon()
            })
        case let .openHiddenSections(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Скрыть разделы"), label: count == 0 ? DkxStrings.tr("нет") : "\(count)", sectionId: self.section, style: .blocks, action: {
                arguments.openHiddenSections()
            })
        case .interfaceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Лента историй над списком чатов исчезнет полностью. Сами истории останутся доступны в профилях.\n\nБез навязывания пропадут плашки и экраны покупки Premium, пункты Premium, Business и подарков в настройках, значки подарков в поле ввода, а при наборе будут предлагаться только ваши стикеры, без чужих паков. Если Premium уже есть, он продолжит работать. Покупка Stars остаётся. Применяется при следующем открытии экрана.")), sectionId: self.section)

        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("КОНТАКТЫ И ЧАТЫ"), sectionId: self.section)
        case let .toggle(toggle, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: dkxToggleTitle(toggle), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateToggle(toggle, value)
            })
        case let .openQuickReplies(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Шаблоны"), label: count == 0 ? DkxStrings.tr("нет") : "\(count)", sectionId: self.section, style: .blocks, action: {
                arguments.openQuickReplies()
            })
        case let .openChatLabels(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Метки на чаты"), label: count == 0 ? DkxStrings.tr("нет") : "\(count)", sectionId: self.section, style: .blocks, action: {
                arguments.openChatLabels()
            })
        case .chatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Метка «сохранил» или «не сохранил» видна в шапке чата и в профиле собеседника, только для тех, кого вы сами сохранили.\n\nЗаметка в шапке чата это первая строка вашей заметки из профиля собеседника. Правится в профиле через «Изменить».\n\nШаблоны вставляются кнопкой в поле ввода, она появляется после добавления первого шаблона. «Все сообщения автора» есть в меню долгого нажатия на сообщение в группе. «Выгрузить чат в файл» в профиле собеседника, группы или канала. Там вся история текстом, с пометками удалённых и прежними версиями изменённых.\n\nБез сжатия фото и видео из галереи уходят оригиналом, файлом, как через «Отправить файлом». Получатель увидит файл, а не картинку в ленте. Предел размера 2 ГБ держит сервер Telegram, его не поднять.\n\nFace ID на чат ставится долгим нажатием на чат в списке, пункт «Закрыть Face ID». У закрытого чата скрыт текст последнего сообщения и предпросмотр, открывается он после проверки и снова закрывается, когда приложение уходит в фон. Снять замок или выключить эту настройку можно только после проверки.\n\n«Мои дела» открываются из главных настроек, строка под «Моим профилем». Вид меняется кнопкой вверху, это лента, день по часам и месяц. Выключенный тумблер прячет строку, сами дела и напоминания остаются. «Пароли» там же, открываются по Face ID, записи лежат в Keychain только на этом телефоне.\n\n«Напомнить позже» есть в меню долгого нажатия на чат в списке и на сообщение. Напоминание ложится делом в «Мои дела», уведомление открывает этот чат.\n\nВключённое или выключенное применяется при следующем открытии экрана.")), sectionId: self.section)

        case .unansweredHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("БЕЗ ОТВЕТА"), sectionId: self.section)
        case let .unansweredThreshold(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateUnansweredHours(dkxUnansweredThresholds[Int(index)].hours)
            })
        case .transcriptionHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("РАСШИФРОВКА ГОЛОСОВЫХ"), sectionId: self.section)
        case let .transcription(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Расшифровка без Premium"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateTranscription(value)
            })
        case let .transcriptionLocale(_, id, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateTranscriptionLocale(id)
            })
        case let .transcriptionFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .improveHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("УЛУЧШИТЬ ТЕКСТ"), sectionId: self.section)
        case let .improveToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Кнопка в поле ввода"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateImproveText(value)
            })
        case let .improveKeys(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Ключи Gemini и GLM"), label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openImproveKeys()
            })
        case let .improveFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .unansweredFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Список открывается долгим нажатием на вкладку «Чаты». В нём личные чаты, где последним написал собеседник, без ботов и архива. Сверху те, кто ждёт дольше всех.")), sectionId: self.section)

        case .locationHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ГЕОПОЗИЦИЯ"), sectionId: self.section)
        case let .spoofPanel(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Панель подмены на карте"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSpoofPanel(value)
            })
        case let .locationFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case .featuresHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("СООБЩЕНИЯ"), sectionId: self.section)
        case let .antiDelete(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Сохранять удалённые"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAntiDelete(value)
            })
        case let .editHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Сохранять историю правок"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateEditHistory(value)
            })
        case .featuresFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Удалённые собеседником сообщения остаются в чате с пометкой «удалено». У отредактированных в контекстном меню доступна история правок.\n\nСекретные чаты и самоуничтожающиеся сообщения не затрагиваются.")), sectionId: self.section)

        case .driveHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "GOOGLE DRIVE", sectionId: self.section)
        case let .driveToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Выгрузка в Google Drive"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateDriveEnabled(value)
            })
        case let .driveAccount(text, isConnected):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: isConnected ? DkxStrings.tr("Аккаунт") : DkxStrings.tr("Войти в Google"), label: text, sectionId: self.section, style: .blocks, disclosureStyle: isConnected ? .none : .arrow, action: {
                if !isConnected {
                    arguments.connectDrive()
                }
            })
        case .driveSwitch:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Привязать другой аккаунт"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.switchDriveAccount()
            })
        case .driveDisconnect:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Отвязать аккаунт"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.disconnectDrive()
            })
        case let .driveFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .debugHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DkxStrings.tr("ОТЛАДКА"), sectionId: self.section)
        case .openLog:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Журнал Dkx"), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openLog()
            })
        case .openDebug:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: DkxStrings.tr("Отладочное меню Telegram"), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openDebug()
            })
        case .debugFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DkxStrings.tr("Полные логи Telegram пишутся только по запросу. В отладочном меню включите Log to File, повторите проблему и нажмите Send Logs там же.")), sectionId: self.section)
        }
    }
}

private func dkxSettingsControllerEntries(settings: DkxSettings) -> [DkxSettingsControllerEntry] {
    var entries: [DkxSettingsControllerEntry] = []

    entries.append(.interfaceHeader)
    entries.append(.hideStories(settings.hideStories))
    entries.append(.hidePremiumPromo(settings.hidePremiumPromo))
    entries.append(.openAppIcon)
    entries.append(.openHiddenSections(Int32(settings.hiddenSections.count)))
    entries.append(.interfaceFooter)

    entries.append(.chatsHeader)
    for toggle in [DkxToggle.contactBadge, .noteInHeader, .peerId, .unanswered, .quickReplies, .authorMessages, .chatExport, .mediaNoCompression, .chatLock, .todo, .passwords, .remindLater] {
        entries.append(.toggle(toggle, dkxToggleValue(toggle, settings)))
    }
    if settings.quickReplies {
        entries.append(.openQuickReplies(Int32(settings.quickReplyTemplates.count)))
    }
    entries.append(.openChatLabels(Int32(settings.chatLabels.count)))
    entries.append(.chatsFooter)

    if settings.unansweredFilter {
        entries.append(.unansweredHeader)
        for i in 0 ..< dkxUnansweredThresholds.count {
            entries.append(.unansweredThreshold(index: Int32(i), title: dkxUnansweredThresholds[i].title, checked: dkxUnansweredThresholds[i].hours == settings.unansweredHours))
        }
        entries.append(.unansweredFooter)
    }

    entries.append(.transcriptionHeader)
    entries.append(.transcription(settings.localTranscription))
    if settings.localTranscription {
        let locales = dkxSupportedSpeechLocales()
        for (index, locale) in locales.enumerated() {
            entries.append(.transcriptionLocale(index: Int32(index), id: locale.id, title: DkxStrings.tr(locale.title), checked: locale.id == settings.transcriptionLocale))
        }
        var text = DkxStrings.tr("Кнопка расшифровки появляется у голосовых и кружков. Есть Premium, расшифровывает Telegram. Нет Premium, расшифровывает сам телефон на выбранном языке, на сервер Telegram ничего не уходит. Если язык не скачан на телефон, iOS распознаёт через серверы Apple.")
        if !locales.contains(where: { $0.id == "uz-UZ" }) {
            text += DkxStrings.tr("\n\nУзбекский iOS пока не распознаёт, поэтому его нет в списке.")
        }
        entries.append(.transcriptionFooter(text))
    } else {
        entries.append(.transcriptionFooter(DkxStrings.tr("Без Premium кнопки расшифровки не будет.")))
    }

    entries.append(.improveHeader)
    entries.append(.improveToggle(settings.improveText))
    if settings.improveText {
        let keys = DkxAIKeys.Provider.allCases.filter { DkxAIKeys.key($0) != nil }.map { $0.title }
        entries.append(.improveKeys(keys.isEmpty ? DkxStrings.tr("нет") : keys.joined(separator: DkxStrings.tr(" и "))))
        let now = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = Int32((now.year ?? 0) * 10000 + (now.month ?? 0) * 100 + (now.day ?? 0))
        let count = settings.improveDay == today ? settings.improveCount : 0
        entries.append(.improveFooter(DkxStrings.tr("Кнопка с волшебной палочкой появляется в поле ввода, когда там есть текст. Стиль, смайлики, обращение и язык выбираются на её экране, последний выбор запоминается. Ключи хранятся в Keychain этого телефона и переживают переустановку приложения. Сегодня запросов {}.", count)))
    } else {
        entries.append(.improveFooter(DkxStrings.tr("Кнопки «Улучшить текст» в поле ввода не будет.")))
    }

    entries.append(.locationHeader)
    entries.append(.spoofPanel(settings.spoofPanel))
    if settings.spoofPanel {
        entries.append(.locationFooter(DkxStrings.tr("Подмена настраивается прямо на карте, в экране отправки геопозиции. Там переключатель Настоящая, Точка или Маршрут, точки ставятся долгим нажатием на карту. Трансляция сама запускает движение по маршруту.\n\nДействует на трансляцию, отправку местоположения и запросы ботов. На системные карты и другие приложения не влияет.")))
    } else {
        entries.append(.locationFooter(DkxStrings.tr("Панель на карте скрыта, приложение отдаёт настоящую геопозицию.")))
    }

    entries.append(.featuresHeader)
    entries.append(.antiDelete(settings.antiDelete))
    entries.append(.editHistory(settings.editHistory))
    entries.append(.featuresFooter)

    entries.append(.driveHeader)
    entries.append(.driveToggle(settings.driveEnabled))
    if settings.driveEnabled {
        if !DkxGoogleDrive.isConfigured {
            entries.append(.driveFooter(DkxStrings.tr("Client ID не задан в сборке. Выгрузка недоступна.")))
        } else if DkxGoogleDrive.isConnected {
            entries.append(.driveAccount(DkxGoogleDrive.connectedEmail ?? DkxStrings.tr("подключён"), true))
            entries.append(.driveSwitch)
            entries.append(.driveDisconnect)
            entries.append(.driveFooter(DkxStrings.tr("У любого фото, видео, голосового или файла в меню долгого нажатия есть пункт «В Google Drive». Файлы грузятся фоном, ход виден в полосе вверху экрана. Папка Dkx, внутри по чатам, только на ваш диск. Права ограничены файлами, которые загрузило это приложение.")))
        } else {
            entries.append(.driveAccount(DkxStrings.tr("не подключён"), false))
            entries.append(.driveFooter(DkxStrings.tr("Войдите в свой Google-аккаунт, чтобы выгружать медиа на Google Drive.")))
        }
    } else {
        entries.append(.driveFooter(DkxStrings.tr("Пункт «В Google Drive» в меню медиа. Файлы уходят только на ваш диск, в папку Dkx.")))
    }

    entries.append(.debugHeader)
    // Экран журнала Dkx убран по просьбе владельца. Запись идёт дальше, тихо,
    // по ней разбираем падения
    entries.append(.openDebug)
    entries.append(.debugFooter)

    return entries
}

public func dkxSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var driveAnchorImpl: (() -> ASPresentationAnchor?)?

    let accountManager = context.sharedContext.accountManager
    let update: (@escaping (inout DkxSettings) -> Void) -> Void = { f in
        let _ = updateDkxSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            f(&updated)
            return updated
        }).start()
    }

    // Вход в Google лежит в Keychain, а не в настройках, поэтому строку
    // аккаунта перерисовываем сами после входа и отвязки
    let driveRefresh = ValuePromise<Int32>(0, ignoreRepeated: false)
    let connectDrive: () -> Void = {
        guard let anchor = driveAnchorImpl?() else {
            return
        }
        let _ = (DkxGoogleDrive.connect(presentationAnchor: { anchor })
        |> deliverOnMainQueue).start(next: { _ in
            driveRefresh.set(0)
        })
    }

    let arguments = DkxSettingsControllerArguments(
        updateHideStories: { value in
            update { $0.hideStories = value }
        },
        updateHidePremiumPromo: { value in
            update { $0.hidePremiumPromo = value }
        },
        openAppIcon: {
            pushControllerImpl?(dkxAppIconController(context: context))
        },
        openHiddenSections: {
            pushControllerImpl?(dkxHiddenSectionsController(context: context))
        },
        updateAntiDelete: { value in
            update { $0.antiDelete = value }
        },
        updateEditHistory: { value in
            update { $0.editHistory = value }
        },
        updateToggle: { toggle, value in
            if toggle == .chatLock && !value {
                // Выключить замки может только владелец, иначе их снимали бы
                // здесь в обход проверки
                let _ = (DkxChatLock.authenticate(reason: DkxStrings.tr("Выключить Face ID на чатах"))
                |> deliverOnMainQueue).start(next: { success in
                    if success {
                        update { dkxToggleUpdate(toggle, value, &$0) }
                    }
                })
                return
            }
            update { dkxToggleUpdate(toggle, value, &$0) }
        },
        updateUnansweredHours: { value in
            update { $0.unansweredHours = value }
        },
        updateTranscription: { value in
            update { $0.localTranscription = value }
        },
        updateTranscriptionLocale: { value in
            update { $0.transcriptionLocale = value }
        },
        updateImproveText: { value in
            update { $0.improveText = value }
        },
        openImproveKeys: {
            pushControllerImpl?(dkxAIKeysController(context: context))
        },
        openQuickReplies: {
            pushControllerImpl?(dkxQuickRepliesController(context: context))
        },
        openChatLabels: {
            pushControllerImpl?(dkxChatLabelsSettingsController(context: context))
        },
        updateSpoofPanel: { value in
            update { settings in
                settings.spoofPanel = value
                // Без панели подмену не выключить, поэтому вместе с ней
                // возвращаем настоящую геопозицию
                if !value {
                    settings.spoofLocation = false
                    settings.routeStartedAt = 0
                }
            }
        },
        openLog: {
            pushControllerImpl?(dkxLogController(context: context))
        },
        openDebug: {
            if let controller = context.sharedContext.makeDebugSettingsController(context: context) {
                pushControllerImpl?(controller)
            }
        },
        updateDriveEnabled: { value in
            update { $0.driveEnabled = value }
        },
        connectDrive: {
            connectDrive()
        },
        switchDriveAccount: {
            DkxGoogleDrive.disconnect()
            driveRefresh.set(0)
            connectDrive()
        },
        disconnectDrive: {
            DkxGoogleDrive.disconnect()
            driveRefresh.set(0)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.dkxSettings]),
        driveRefresh.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.dkxSettings]?.get(DkxSettings.self) ?? DkxSettings.defaultSettings

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Dkx"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: dkxSettingsControllerEntries(settings: settings), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    // Ключи ИИ и вход в Google лежат в Keychain, после возврата с их экранов
    // строки перерисовываем сами
    controller.didAppear = { _ in
        driveRefresh.set(0)
    }
    pushControllerImpl = { [weak controller] c in
        if let controller = controller {
            (controller.navigationController as? NavigationController)?.pushViewController(c)
        }
    }
    driveAnchorImpl = { [weak controller] in
        return controller?.view.window
    }
    return controller
}
