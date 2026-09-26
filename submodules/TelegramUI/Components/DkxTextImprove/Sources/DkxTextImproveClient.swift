import Foundation
import SwiftSignalKit

// MARK: DKX запросы «Улучшить текст». GLM-4.5-Flash для русского и
// английского, Gemini Flash-Lite для узбекского, он единственный из
// бесплатных держит узбекский язык. Упал один сервис, запрос уходит в другой.

public let dkxImproveStyles: [String] = ["Исправить ошибки", "Деловой", "Дружелюбный", "Короче", "Подробнее", "Продающий", "Вежливый отказ", "Свой стиль"]
public let dkxImproveEmoji: [String] = ["Без смайликов", "Как в тексте", "Добавить уместные"]
public let dkxImproveAddress: [String] = ["На «вы»", "На «ты»", "Как в тексте"]
public let dkxImproveLanguages: [String] = ["Как в тексте", "Русский", "Узбекский", "Английский"]

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

public enum DkxImproveError {
    case noKeys
    case failed(String)
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

private func dkxErrorText(status: Int) -> String {
    switch status {
    case 400:
        return "сервис не принял запрос"
    case 401, 403:
        return "ключ не подходит"
    case 429:
        return "лимит на сегодня или сервис перегружен"
    default:
        return "ответ \(status)"
    }
}

private func dkxRequest(provider: DkxAIKeys.Provider, key: String, system: String, text: String, temperature: Double) -> Signal<String, DkxImproveError> {
    return Signal { subscriber in
        var request: URLRequest
        let body: [String: Any]
        switch provider {
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": text]]]],
                "generationConfig": ["temperature": temperature]
            ]
        case .glm:
            request = URLRequest(url: URL(string: "https://api.z.ai/api/paas/v4/chat/completions")!)
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            body = [
                "model": "glm-4.5-flash",
                "messages": [["role": "system", "content": system], ["role": "user", "content": text]],
                "thinking": ["type": "disabled"],
                "temperature": temperature
            ]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if let error = error {
                subscriber.putError(.failed((error as NSError).code == NSURLErrorTimedOut ? "сервис не ответил за 30 секунд" : "нет связи с сервисом"))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                subscriber.putError(.failed(dkxErrorText(status: status)))
                return
            }
            var result: String?
            switch provider {
            case .gemini:
                if let candidates = json["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] {
                    result = parts.compactMap { $0["text"] as? String }.joined()
                }
            case .glm:
                if let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any] {
                    result = message["content"] as? String
                }
            }
            let trimmed = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                subscriber.putError(.failed("сервис вернул пустой ответ"))
            } else {
                subscriber.putNext(trimmed)
                subscriber.putCompletion()
            }
        })
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}

// Отдаёт готовый текст и сервис, который его написал
public func dkxImproveText(_ text: String, options: DkxImproveOptions, variant: Int) -> Signal<(String, DkxAIKeys.Provider), DkxImproveError> {
    let preferGemini = options.language == 2 || (options.language == 0 && dkxLooksUzbek(text))
    let order: [DkxAIKeys.Provider] = preferGemini ? [.gemini, .glm] : [.glm, .gemini]
    let available: [(DkxAIKeys.Provider, String)] = order.compactMap { provider in
        return DkxAIKeys.key(provider).map { (provider, $0) }
    }
    guard !available.isEmpty else {
        return .fail(.noKeys)
    }
    let system = dkxSystemPrompt(options)
    // «Ещё вариант» просит сервис быть смелее, иначе он повторит тот же текст
    let temperature = variant == 0 ? 0.4 : 0.9
    var signal: Signal<(String, DkxAIKeys.Provider), DkxImproveError> = .fail(.failed("нет сервиса"))
    for (index, item) in available.enumerated().reversed() {
        let attempt = dkxRequest(provider: item.0, key: item.1, system: system, text: text, temperature: temperature)
        |> map { result -> (String, DkxAIKeys.Provider) in
            return (result, item.0)
        }
        if index == available.count - 1 {
            signal = attempt
        } else {
            let fallback = signal
            signal = attempt
            |> `catch` { _ -> Signal<(String, DkxAIKeys.Provider), DkxImproveError> in
                return fallback
            }
        }
    }
    return signal
}

// Проверка ключа перед сохранением, короткий запрос без расхода лимита на текст
public func dkxCheckKey(provider: DkxAIKeys.Provider, key: String) -> Signal<Void, DkxImproveError> {
    return dkxRequest(provider: provider, key: key, system: "Ответь одним словом.", text: "Скажи ок", temperature: 0.0)
    |> map { _ -> Void in
        return Void()
    }
}
