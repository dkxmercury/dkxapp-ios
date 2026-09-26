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
            return "Контакты"
        case .tabCalls:
            return "Звонки"
        case .editButtons:
            return "Кнопки фото, статуса и имени пользователя"
        case .myProfile:
            return "Мой профиль"
        case .proxy:
            return "Прокси"
        case .apps:
            return "Мини-приложения ботов"
        case .savedMessages:
            return "Избранное"
        case .recentCalls:
            return "Недавние звонки"
        case .devices:
            return "Устройства"
        case .chatFolders:
            return "Папки с чатами"
        case .notifications:
            return "Уведомления и звуки"
        case .privacy:
            return "Конфиденциальность"
        case .dataAndStorage:
            return "Данные и память"
        case .appearance:
            return "Оформление"
        case .powerSaving:
            return "Энергосбережение"
        case .language:
            return "Язык"
        case .premium:
            return "Telegram Premium"
        case .stars:
            return "Звёзды"
        case .ton:
            return "TON"
        case .business:
            return "Telegram для бизнеса"
        case .sendGift:
            return "Отправить подарок"
        case .passport:
            return "Telegram Passport"
        case .watch:
            return "Apple Watch"
        }
    }
}

public extension DkxSettings {
    func isHidden(_ section: DkxHiddenSection) -> Bool {
        return self.hiddenSections.contains(section.rawValue)
    }
}
