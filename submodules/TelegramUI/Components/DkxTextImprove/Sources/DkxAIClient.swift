import Foundation
import SwiftSignalKit
import TelegramUIPreferences

public enum DkxImproveError {
    case noKeys
    case failed(String)
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
        } else if let message = json["message"] as? String {
            detail = message
        } else if let errors = json["errors"] as? [[String: Any]], let message = errors.first?["message"] as? String {
            detail = message
        }
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
    return base + ". " + String(detail.prefix(200))
}

// Модели рассуждений OpenAI не принимают temperature и max_tokens
private func dkxIsOpenAIReasoning(_ provider: DkxAIKeys.Provider, _ model: String) -> Bool {
    guard provider == .openai else {
        return false
    }
    let lower = model.lowercased()
    return lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.hasPrefix("gpt-5")
}

private func dkxSend(_ request: URLRequest, parse: @escaping ([String: Any]) -> String?) -> Signal<String, DkxImproveError> {
    return Signal { subscriber in
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
            let trimmed = parse(json)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                subscriber.putError(.failed(DkxStrings.tr("сервис вернул пустой ответ")))
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
    guard let key = key ?? DkxAIKeys.key(provider), let model = model ?? DkxAIKeys.model(provider) else {
        return .fail(.noKeys)
    }
    let base = DkxAIKeys.base(provider)
    var request: URLRequest
    let body: [String: Any]
    let parse: ([String: Any]) -> String?
    switch provider.format {
    case .gemini:
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        guard let url = URL(string: base + "/models/" + encodedModel + ":generateContent") else {
            return .fail(.failed(DkxStrings.tr("неверный адрес API")))
        }
        request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        body = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": text]]]],
            "generationConfig": ["temperature": temperature, "maxOutputTokens": maxTokens]
        ]
        parse = { json in
            guard let candidates = json["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] else {
                return nil
            }
            return parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        }
    case .anthropic:
        guard let url = URL(string: base + "/messages") else {
            return .fail(.failed(DkxStrings.tr("неверный адрес API")))
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
            return .fail(.failed(DkxStrings.tr("неверный адрес API")))
        }
        request = URLRequest(url: url)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        if provider == .openrouter {
            request.setValue("Dkx", forHTTPHeaderField: "X-Title")
        }
        var fields: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": text]]
        ]
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

// Проверка выбранной модели коротким запросом
public func dkxAICheckModel(provider: DkxAIKeys.Provider, key: String, model: String) -> Signal<Void, DkxImproveError> {
    return dkxAIRequest(provider: provider, key: key, model: model, system: "Ответь одним словом.", text: "Скажи ок", temperature: 0.0, maxTokens: 1024, timeout: 60.0)
    |> map { _ -> Void in
        return Void()
    }
}
