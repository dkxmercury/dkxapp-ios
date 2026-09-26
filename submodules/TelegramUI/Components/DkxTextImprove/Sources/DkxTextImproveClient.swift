import Foundation
import SwiftSignalKit
import TelegramUIPreferences

// Запросы «Улучшить текст» через сервисы из раздела «API ИИ». Для узбекского
// первым идёт Gemini, он лучше других держит узбекский. Упал один сервис,
// запрос уходит в следующий.

public var dkxImproveStyles: [String] {
    return [DkxStrings.tr("Исправить ошибки"), DkxStrings.tr("Деловой"), DkxStrings.tr("Дружелюбный"), DkxStrings.tr("Короче"), DkxStrings.tr("Подробнее"), DkxStrings.tr("Продающий"), DkxStrings.tr("Вежливый отказ"), DkxStrings.tr("Свой стиль")]
}
public var dkxImproveEmoji: [String] {
    return [DkxStrings.tr("Без смайликов"), DkxStrings.tr("Как в тексте"), DkxStrings.tr("Добавить уместные")]
}
public var dkxImproveAddress: [String] {
    return [DkxStrings.tr("На «вы»"), DkxStrings.tr("На «ты»"), DkxStrings.tr("Как в тексте")]
}
public var dkxImproveLanguages: [String] {
    return [DkxStrings.tr("Как в тексте"), DkxStrings.tr("Русский"), DkxStrings.tr("Узбекский"), DkxStrings.tr("Английский")]
}

private let dkxStylePrompts: [String] = [
    "Исправь только ошибки, опечатки и пунктуацию. Слова, порядок слов и смысл не меняй.",
    "Сделай текст деловым и вежливым, коротко и по делу.",
    "Сделай текст дружелюбным и тёплым, без панибратства.",
    "Сократи текст, оставь главное.",
    "Распиши текст чуть подробнее и понятнее, без воды.",
    "Сделай текст продающим. Подчеркни выгоду для собеседника, но не навязывайся.",
    "Переформулируй текст как вежливый и мягкий отказ, суть сохрани."
]

private let dkxEmojiPrompts: [String] = [
    "Смайлики и эмодзи не используй, если они были, убери.",
    "Смайлики оставь как в тексте, новых не добавляй.",
    "Добавь два или три уместных эмодзи, не больше."
]

private let dkxAddressPrompts: [String] = [
    "К собеседнику обращайся на «вы».",
    "К собеседнику обращайся на «ты».",
    "Обращение к собеседнику оставь как в тексте."
]

private let dkxLanguagePrompts: [String] = [
    "Пиши на том же языке, что и оригинал. Не переводи.",
    "Готовый текст напиши на русском языке.",
    "Готовый текст напиши на узбекском языке, латиницей.",
    "Готовый текст напиши на английском языке."
]

public struct DkxImproveOptions: Equatable {
    public var style: Int32
    public var custom: String
    public var emoji: Int32
    public var address: Int32
    public var language: Int32

    public init(style: Int32, custom: String, emoji: Int32, address: Int32, language: Int32) {
        self.style = style
        self.custom = custom
        self.emoji = emoji
        self.address = address
        self.language = language
    }
}

private func dkxPick(_ list: [String], _ index: Int32) -> String {
    return list[max(0, min(Int(index), list.count - 1))]
}

private func dkxSystemPrompt(_ options: DkxImproveOptions) -> String {
    var parts: [String] = ["Ты редактор сообщений в мессенджере. Перепиши текст, который пришлёт пользователь."]
    let custom = options.custom.trimmingCharacters(in: .whitespacesAndNewlines)
    if Int(options.style) == dkxImproveStyles.count - 1 && !custom.isEmpty {
        parts.append("Что сделать с текстом. " + custom)
    } else {
        parts.append(dkxPick(dkxStylePrompts, options.style))
    }
    parts.append(dkxPick(dkxEmojiPrompts, options.emoji))
    parts.append(dkxPick(dkxAddressPrompts, options.address))
    parts.append(dkxPick(dkxLanguagePrompts, options.language))
    parts.append("Верни только готовый текст сообщения, без кавычек, без пояснений и без вариантов на выбор.")
    return parts.joined(separator: " ")
}

// Узбекский узнаём по буквам ў қ ғ ҳ, по апострофу в o' и g' и по частым словам
public func dkxLooksUzbek(_ text: String) -> Bool {
    let lower = text.lowercased()
    if lower.contains(where: { "ўқғҳ".contains($0) }) {
        return true
    }
    if lower.unicodeScalars.contains(where: { (0x0400 ... 0x04FF).contains($0.value) }) {
        return false
    }
    for marker in ["o'", "g'", "oʻ", "gʻ", "o‘", "g‘", "o`", "g`"] where lower.contains(marker) {
        return true
    }
    let common: Set<String> = ["va", "bu", "men", "siz", "biz", "salom", "rahmat", "qanday", "kerak", "yoq", "bor", "emas", "uchun", "bilan", "ham", "yaxshi", "iltimos", "buyurtma", "ertaga", "bugun", "keyin", "mumkin"]
    let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
    return words.intersection(common).count >= 2
}

// Отдаёт готовый текст и сервис, который его написал
public func dkxImproveText(_ text: String, options: DkxImproveOptions, variant: Int) -> Signal<(String, DkxAIKeys.Provider), DkxImproveError> {
    let preferGemini = options.language == 2 || (options.language == 0 && dkxLooksUzbek(text))
    // «Ещё вариант» просит сервис быть смелее, иначе он повторит тот же текст
    let temperature = variant == 0 ? 0.4 : 0.9
    return dkxAIComplete(system: dkxSystemPrompt(options), text: text, temperature: temperature, maxTokens: 2048, timeout: 45.0, preferring: preferGemini ? .gemini : nil)
}
