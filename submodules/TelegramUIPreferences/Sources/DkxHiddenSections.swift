import Foundation

// Вкладки и строки главного экрана настроек, которые можно спрятать в Dkx.
// В DkxSettings.hiddenSections лежат их rawValue, поэтому строки не менять,
// иначе сохранённый выбор потеряется. Чаты, Настройки и строка Dkx сюда не
// входят, без них спрятанное не вернуть.
public enum DkxHiddenSection: String, CaseIterable {
    case tabContacts = "tab.contacts"
    case tabCalls = "tab.calls"

    case editButtons = "settings.editButtons"
    case myProfile = "settings.myProfile"
    case proxy = "settings.proxy"
    case apps = "settings.apps"
    case savedMessages = "settings.savedMessages"
    case recentCalls = "settings.recentCalls"
    case devices = "settings.devices"
    case chatFolders = "settings.chatFolders"
    case notifications = "settings.notifications"
    case privacy = "settings.privacy"
    case dataAndStorage = "settings.dataAndStorage"
    case appearance = "settings.appearance"
    case powerSaving = "settings.powerSaving"
    case language = "settings.language"
    case premium = "settings.premium"
    case stars = "settings.stars"
    case ton = "settings.ton"
    case business = "settings.business"
    case sendGift = "settings.sendGift"
    case passport = "settings.passport"
    case watch = "settings.watch"

    case savedTags = "saved.tags"

    public var isSavedMessages: Bool {
        return self == .savedTags
    }

    public var isTab: Bool {
        switch self {
        case .tabContacts, .tabCalls:
            return true
        default:
            return false
        }
    }

    public var title: String {
        switch self {
        case .tabContacts:
            return DkxStrings.tr("Контакты")
        case .tabCalls:
            return DkxStrings.tr("Звонки")
        case .editButtons:
            return DkxStrings.tr("Кнопки фото, статуса и имени пользователя")
        case .myProfile:
            return DkxStrings.tr("Мой профиль")
        case .proxy:
            return DkxStrings.tr("Прокси")
        case .apps:
            return DkxStrings.tr("Мини-приложения ботов")
        case .savedMessages:
            return DkxStrings.tr("Избранное")
        case .recentCalls:
            return DkxStrings.tr("Недавние звонки")
        case .devices:
            return DkxStrings.tr("Устройства")
        case .chatFolders:
            return DkxStrings.tr("Папки с чатами")
        case .notifications:
            return DkxStrings.tr("Уведомления и звуки")
        case .privacy:
            return DkxStrings.tr("Конфиденциальность")
        case .dataAndStorage:
            return DkxStrings.tr("Данные и память")
        case .appearance:
            return DkxStrings.tr("Оформление")
        case .powerSaving:
            return DkxStrings.tr("Энергосбережение")
        case .language:
            return DkxStrings.tr("Язык")
        case .premium:
            return "Telegram Premium"
        case .stars:
            return DkxStrings.tr("Звёзды")
        case .ton:
            return "TON"
        case .business:
            return DkxStrings.tr("Telegram для бизнеса")
        case .sendGift:
            return DkxStrings.tr("Отправить подарок")
        case .passport:
            return "Telegram Passport"
        case .watch:
            return "Apple Watch"
        case .savedTags:
            return DkxStrings.tr("Теги в Избранном")
        }
    }
}

public extension DkxSettings {
    func isHidden(_ section: DkxHiddenSection) -> Bool {
        return self.hiddenSections.contains(section.rawValue)
    }
}
