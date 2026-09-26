import Foundation

public enum DkxStrings {
    public static func tr(_ ru: String) -> String {
        return translation(ru).text
    }

    public static func tr(_ ru: String, _ args: CustomStringConvertible...) -> String {
        return fill(translation(ru).text, args.map { $0.description })
    }

    // Ключ это три русские формы через «|», в переводе формы языка через «|» по dkxPluralIndex
    public static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let (text, language) = translation(one + "|" + few + "|" + many)
        let forms = text.components(separatedBy: "|")
        let index = min(dkxPluralIndex(language, count), forms.count - 1)
        return fill(forms[index], ["\(count)"])
    }

    private static func translation(_ ru: String) -> (text: String, language: String) {
        let language = DkxRuntime.languageCode
        if language == "ru" || language.isEmpty {
            return (ru, "ru")
        }
        guard let variants = dkxStringsTable[ru] else {
            return (ru, "ru")
        }
        if let value = variants[language] {
            return (value, language)
        }
        if let base = language.split(separator: "-").first.map(String.init), base != language, let value = variants[base] {
            return (value, base)
        }
        if let value = variants["en"] {
            return (value, "en")
        }
        return (ru, "ru")
    }

    // «{}» берёт аргументы по порядку, «{1}» и «{2}» по номеру, если переводу нужен другой порядок
    private static func fill(_ template: String, _ args: [String]) -> String {
        var result = ""
        var rest = Substring(template)
        var next = 0
        while let open = rest.firstIndex(of: "{") {
            result.append(contentsOf: rest[..<open])
            let inner = rest[rest.index(after: open)...]
            if let close = inner.firstIndex(of: "}") {
                let name = inner[..<close]
                var arg: String?
                if name.isEmpty {
                    if next < args.count {
                        arg = args[next]
                        next += 1
                    }
                } else if let position = Int(name), position >= 1, position <= args.count {
                    arg = args[position - 1]
                }
                if let arg = arg {
                    result.append(contentsOf: arg)
                    rest = inner[inner.index(after: close)...]
                    continue
                }
            }
            result.append(contentsOf: "{")
            rest = inner
        }
        result.append(contentsOf: rest)
        return result
    }
}

// Правила CLDR для целых чисел, индекс формы в порядке категорий языка
private func dkxPluralIndex(_ language: String, _ count: Int) -> Int {
    let n = abs(count)
    let n10 = n % 10
    let n100 = n % 100
    switch language {
    case "ru", "uk", "be":
        if n10 == 1 && n100 != 11 {
            return 0
        }
        if (2...4).contains(n10) && !(12...14).contains(n100) {
            return 1
        }
        return 2
    case "pl":
        if n == 1 {
            return 0
        }
        if (2...4).contains(n10) && !(12...14).contains(n100) {
            return 1
        }
        return 2
    case "ar":
        if n == 0 {
            return 0
        }
        if n == 1 {
            return 1
        }
        if n == 2 {
            return 2
        }
        if (3...10).contains(n100) {
            return 3
        }
        if (11...99).contains(n100) {
            return 4
        }
        return 5
    case "fr", "pt", "fa":
        return n <= 1 ? 0 : 1
    case "id", "ms", "ko":
        return 0
    default:
        return n == 1 ? 0 : 1
    }
}
