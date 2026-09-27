import Foundation
import SwiftSignalKit
import TelegramUIPreferences

public enum DkxImproveError {
    case noKeys
    case failed(String)
}

// Ошибка запроса с кодом ответа. Код 0 это нет связи или время вышло,
// код 200 это сервис ответил, но пустым текстом
public struct DkxAIFailure: Error {
    public let status: Int
    public let text: String

    // Перегрузка, лимит или сеть проходят сами, модель при этом рабочая
    public var isTemporary: Bool {
        return self.status == 0 || self.status == 408 || self.status == 429 || self.status >= 500
    }
}

public struct DkxAIModel: Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

private func dkxErrorText(status: Int, body: Data?) -> String {
    var detail = ""
    if let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            detail = message
            // OpenRouter пишет общее «Provider returned error», причина от самой модели лежит тут
            if let metadata = error["metadata"] as? [String: Any], let raw = metadata["raw"] as? String, !raw.isEmpty {
                detail += ". " + raw
            }
        } else if let message = json["message"] as? String {
            detail = message
        } else if let errors = json["errors"] as? [[String: Any]], let message = errors.first?["message"] as? String {
            detail = message
        }
    }
    // Бесплатные модели OpenRouter отвечают 404, если в настройках приватности аккаунта они выключены
    if detail.lowercased().contains("data policy") {
        return DkxStrings.tr("в настройках OpenRouter выключены бесплатные модели. Включите их на openrouter.ai/settings/privacy и выберите модель снова")
    }
    let base: String
    switch status {
    case 400:
        base = DkxStrings.tr("сервис не принял запрос")
    case 401, 403:
        base = DkxStrings.tr("ключ не подходит")
    case 402:
        base = DkxStrings.tr("на счёте сервиса нет денег")
    case 404:
        base = DkxStrings.tr("модель или адрес не найдены")
    case 429:
        base = DkxStrings.tr("лимит на сегодня или сервис перегружен")
    default:
        base = DkxStrings.tr("ответ {}", status)
    }
    if detail.isEmpty {
        return base
    }
    return base + ". " + String(detail.prefix(300))
}

// Модели рассуждений OpenAI не принимают temperature и max_tokens
private func dkxIsOpenAIReasoning(_ provider: DkxAIKeys.Provider, _ model: String) -> Bool {
    guard provider == .openai else {
        return false
    }
    let lower = model.lowercased()
    return lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.hasPrefix("gpt-5")
}

private func dkxSend(_ request: URLRequest, parse: @escaping ([String: Any]) -> String?) -> Signal<String, DkxAIFailure> {
    return Signal { subscriber in
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if let error = error {
                let text = (error as NSError).code == NSURLErrorTimedOut ? DkxStrings.tr("сервис не ответил вовремя") : DkxStrings.tr("нет связи с сервисом")
                subscriber.putError(DkxAIFailure(status: 0, text: text))
                return
            }
            var status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Квота исчерпана насовсем, это не перегрузка, ждать бесполезно
            if status == 429, let data, let raw = String(data: data, encoding: .utf8), raw.contains("insufficient_quota") || raw.contains("limit: 0") {
                status = 402
            }
            guard status == 200, let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                subscriber.putError(DkxAIFailure(status: status, text: dkxErrorText(status: status, body: data)))
                return
            }
            // OpenRouter отдаёт сбой модели кодом 200 с ошибкой внутри
            if let error = json["error"] as? [String: Any] {
                let code = (error["code"] as? Int) ?? 502
                subscriber.putError(DkxAIFailure(status: code, text: dkxErrorText(status: code, body: data)))
                return
            }
            let trimmed = parse(json)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                subscriber.putError(DkxAIFailure(status: 200, text: DkxStrings.tr("сервис вернул пустой ответ")))
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

public func dkxAIRequest(provider: DkxAIKeys.Provider, key: String? = nil, model: String? = nil, system: String, text: String, temperature: Double, maxTokens: Int, timeout: Double) -> Signal<String, DkxImproveError> {
    return dkxAIRequestRaw(provider: provider, key: key, model: model, system: system, text: text, temperature: temperature, maxTokens: maxTokens, timeout: timeout)
    |> mapError { failure -> DkxImproveError in
        return failure.status < 0 ? .noKeys : .failed(failure.text)
    }
}

// Gemma и часть моделей у посредников не принимают отдельную системную инструкцию.
// Им она уходит внутри сообщения, а при таком отказе запрос повторяется в этом виде
private func dkxAIRequestRaw(provider: DkxAIKeys.Provider, key: String?, model: String?, system: String, text: String, temperature: Double, maxTokens: Int, timeout: Double) -> Signal<String, DkxAIFailure> {
    guard let key = key ?? DkxAIKeys.key(provider), let model = model ?? DkxAIKeys.model(provider) else {
        return .fail(DkxAIFailure(status: -1, text: DkxStrings.tr("нет ключа")))
    }
    let fold = model.lowercased().contains("gemma")
    return dkxAIRequestOnce(provider: provider, key: key, model: model, system: system, text: text, temperature: temperature, maxTokens: maxTokens, timeout: timeout, foldSystem: fold)
    |> `catch` { failure -> Signal<String, DkxAIFailure> in
        let lower = failure.text.lowercased()
        let rejectsSystem = lower.contains("instruction") || lower.contains("system") || lower.contains("developer")
        if !fold && provider.format != .anthropic && failure.status == 400 && rejectsSystem {
            return dkxAIRequestOnce(provider: provider, key: key, model: model, system: system, text: text, temperature: temperature, maxTokens: maxTokens, timeout: timeout, foldSystem: true)
        }
        return .fail(failure)
    }
}

private func dkxAIRequestOnce(provider: DkxAIKeys.Provider, key: String, model: String, system: String, text: String, temperature: Double, maxTokens: Int, timeout: Double, foldSystem: Bool) -> Signal<String, DkxAIFailure> {
    let invalidAddress = DkxAIFailure(status: 404, text: DkxStrings.tr("неверный адрес API"))
    let userText = foldSystem ? system + "\n\n" + text : text
    let base = DkxAIKeys.base(provider)
    var request: URLRequest
    let body: [String: Any]
    let parse: ([String: Any]) -> String?
    switch provider.format {
    case .gemini:
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        guard let url = URL(string: base + "/models/" + encodedModel + ":generateContent") else {
            return .fail(invalidAddress)
        }
        request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        var fields: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": userText]]] as [String: Any]],
            "generationConfig": ["temperature": temperature, "maxOutputTokens": maxTokens] as [String: Any]
        ]
        if !foldSystem {
            fields["systemInstruction"] = ["parts": [["text": system]]]
        }
        body = fields
        parse = { json in
            guard let candidates = json["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] else {
                return nil
            }
            return parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        }
    case .anthropic:
        guard let url = URL(string: base + "/messages") else {
            return .fail(invalidAddress)
        }
        request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        body = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": text]],
            "temperature": min(1.0, temperature)
        ]
        parse = { json in
            guard let content = json["content"] as? [[String: Any]] else {
                return nil
            }
            return content.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        }
    case .openAI:
        guard let url = URL(string: base + "/chat/completions") else {
            return .fail(invalidAddress)
        }
        request = URLRequest(url: url)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        if provider == .openrouter {
            request.setValue("Dkx", forHTTPHeaderField: "X-Title")
        }
        var fields: [String: Any] = ["model": model]
        if foldSystem {
            fields["messages"] = [["role": "user", "content": userText]]
        } else {
            fields["messages"] = [["role": "system", "content": system], ["role": "user", "content": text]]
        }
        if dkxIsOpenAIReasoning(provider, model) {
            fields["max_completion_tokens"] = maxTokens
        } else {
            fields["temperature"] = temperature
            fields["max_tokens"] = maxTokens
        }
        // У GLM рассуждение по умолчанию включено, ответ приходит дольше и дороже
        if provider == .glm {
            fields["thinking"] = ["type": "disabled"]
        }
        // Qwen3 без потока отвечает ошибкой, пока рассуждение не выключено явно
        if provider == .qwen {
            fields["enable_thinking"] = false
        }
        body = fields
        parse = { json in
            guard let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any] else {
                return nil
            }
            if let content = message["content"] as? String {
                return content
            }
            if let parts = message["content"] as? [[String: Any]] {
                return parts.compactMap { $0["text"] as? String }.joined()
            }
            return nil
        }
    }
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    return dkxSend(request, parse: parse)
}

// Запрос по очереди сервисов. Не ответил один, пробуем следующий
public func dkxAIComplete(system: String, text: String, temperature: Double, maxTokens: Int, timeout: Double, preferring: DkxAIKeys.Provider? = nil) -> Signal<(String, DkxAIKeys.Provider), DkxImproveError> {
    let order = DkxAIKeys.order(preferring: preferring)
    guard !order.isEmpty else {
        return .fail(.noKeys)
    }
    var signal: Signal<(String, DkxAIKeys.Provider), DkxImproveError> = .fail(.failed(DkxStrings.tr("нет сервиса")))
    for (index, provider) in order.enumerated().reversed() {
        let attempt = dkxAIRequest(provider: provider, system: system, text: text, temperature: temperature, maxTokens: maxTokens, timeout: timeout)
        |> map { result -> (String, DkxAIKeys.Provider) in
            return (result, provider)
        }
        if index == order.count - 1 {
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

private func dkxGet(_ url: URL, provider: DkxAIKeys.Provider, key: String) -> Signal<[String: Any], DkxImproveError> {
    return Signal { subscriber in
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        switch provider.format {
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAI:
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if let error = error {
                subscriber.putError(.failed((error as NSError).code == NSURLErrorTimedOut ? DkxStrings.tr("сервис не ответил вовремя") : DkxStrings.tr("нет связи с сервисом")))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                subscriber.putError(.failed(dkxErrorText(status: status, body: data)))
                return
            }
            subscriber.putNext(json)
            subscriber.putCompletion()
        })
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}

// Список моделей, доступных по ключу. Он же проверка ключа
public func dkxAIListModels(provider: DkxAIKeys.Provider, key: String) -> Signal<[DkxAIModel], DkxImproveError> {
    let base = DkxAIKeys.base(provider)
    switch provider.format {
    case .gemini:
        func page(_ token: String?, _ collected: [DkxAIModel]) -> Signal<[DkxAIModel], DkxImproveError> {
            var address = base + "/models?pageSize=1000"
            if let token, let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                address += "&pageToken=" + encoded
            }
            guard let url = URL(string: address) else {
                return .fail(.failed(DkxStrings.tr("неверный адрес API")))
            }
            return dkxGet(url, provider: provider, key: key)
            |> mapToSignal { json -> Signal<[DkxAIModel], DkxImproveError> in
                var result = collected
                for item in json["models"] as? [[String: Any]] ?? [] {
                    let methods = item["supportedGenerationMethods"] as? [String] ?? []
                    guard methods.contains("generateContent"), var id = item["name"] as? String else {
                        continue
                    }
                    if id.hasPrefix("models/") {
                        id = String(id.dropFirst(7))
                    }
                    if !dkxIsTextModel(provider: provider, id: id) {
                        continue
                    }
                    result.append(DkxAIModel(id: id, name: item["displayName"] as? String ?? id))
                }
                if let next = json["nextPageToken"] as? String, !next.isEmpty, result.count < 5000 {
                    return page(next, result)
                }
                return .single(result)
            }
        }
        return page(nil, [])
    case .anthropic:
        guard let url = URL(string: base + "/models?limit=1000") else {
            return .fail(.failed(DkxStrings.tr("неверный адрес API")))
        }
        return dkxGet(url, provider: provider, key: key)
        |> map { json -> [DkxAIModel] in
            return (json["data"] as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["id"] as? String else {
                    return nil
                }
                return DkxAIModel(id: id, name: item["display_name"] as? String ?? id)
            }
        }
    case .openAI:
        if provider == .cloudflare {
            let root = base.hasSuffix("/ai/v1") ? String(base.dropLast(3)) : base
            func page(_ number: Int, _ collected: [DkxAIModel]) -> Signal<[DkxAIModel], DkxImproveError> {
                guard let url = URL(string: root + "/models/search?task=Text%20Generation&per_page=100&page=\(number)") else {
                    return .fail(.failed(DkxStrings.tr("неверный адрес API")))
                }
                return dkxGet(url, provider: provider, key: key)
                |> mapToSignal { json -> Signal<[DkxAIModel], DkxImproveError> in
                    let items = json["result"] as? [[String: Any]] ?? []
                    var result = collected
                    for item in items {
                        if let name = item["name"] as? String {
                            result.append(DkxAIModel(id: name, name: name))
                        }
                    }
                    if items.count >= 100 && number < 30 {
                        return page(number + 1, result)
                    }
                    return .single(result)
                }
            }
            return page(1, [])
        }
        guard let url = URL(string: base + "/models") else {
            return .fail(.failed(DkxStrings.tr("неверный адрес API")))
        }
        return dkxGet(url, provider: provider, key: key)
        |> map { json -> [DkxAIModel] in
            return (json["data"] as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["id"] as? String else {
                    return nil
                }
                // Из OpenRouter владелец берёт только бесплатные модели
                if provider == .openrouter && !dkxIsFreeOpenRouterModel(id: id, pricing: item["pricing"] as? [String: Any]) {
                    return nil
                }
                if !dkxIsTextModel(provider: provider, id: id) {
                    return nil
                }
                return DkxAIModel(id: id, name: item["name"] as? String ?? id)
            }
        }
    }
}

private func dkxIsFreeOpenRouterModel(id: String, pricing: [String: Any]?) -> Bool {
    if id.hasSuffix(":free") {
        return true
    }
    guard let pricing else {
        return false
    }
    func price(_ key: String) -> Double? {
        if let value = pricing[key] as? String {
            return Double(value)
        }
        return (pricing[key] as? NSNumber)?.doubleValue
    }
    guard let prompt = price("prompt"), let completion = price("completion") else {
        return false
    }
    return prompt == 0.0 && completion == 0.0 && (price("request") ?? 0.0) == 0.0
}

// Проверка выбранной модели коротким запросом. Ответ кодом 200 значит,
// что модель работает, даже если текст пустой, рассуждающие модели так умеют
public func dkxAICheckModel(provider: DkxAIKeys.Provider, key: String, model: String) -> Signal<Void, DkxAIFailure> {
    return dkxAIRequestRaw(provider: provider, key: key, model: model, system: "Ответь одним словом.", text: "Скажи ок", temperature: 0.0, maxTokens: 1024, timeout: 60.0)
    |> map { _ -> Void in
        return Void()
    }
}

// Модели для звука, картинок, видео, эмбеддингов и модерации текст не пишут. Плюс
// модели, которые у сервиса работают только через другой вид запроса или только потоком
private func dkxIsTextModel(provider: DkxAIKeys.Provider, id: String) -> Bool {
    let lower = id.lowercased()
    var markers = ["embed", "tts", "whisper", "transcribe", "dall-e", "imagen", "veo-", "image-generation", "-image", "moderation", "aqa", "audio", "realtime", "robotics", "computer-use", "live-", "-live", "ocr", "sora", "lyria", "banana"]
    switch provider {
    case .openai:
        markers += ["davinci", "babbage", "codex", "search-preview", "o1-pro", "o3-pro", "deep-research"]
    case .qwen:
        markers += ["qwq", "qvq", "-thinking", "qwen-mt"]
    default:
        break
    }
    return !markers.contains(where: { lower.contains($0) })
}
