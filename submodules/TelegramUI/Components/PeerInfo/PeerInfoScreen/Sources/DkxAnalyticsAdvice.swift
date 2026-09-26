import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import TelegramUIPreferences
import DkxTextImprove

private func dkxAdviceLanguage() -> String {
    switch DkxRuntime.languageCode.split(separator: "-").first.map(String.init) ?? "" {
    case "", "ru":
        return "русском"
    case "uk":
        return "украинском"
    case "uz":
        return "узбекском, латиницей"
    default:
        return "английском"
    }
}

private func dkxAdviceNumber(_ value: Double) -> String {
    return String(format: "%.1f", value)
}

private func dkxAdviceDate(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
}

// Сводка цифр для ИИ. Служебный текст запроса, пользователю не показывается
func dkxAdvicePrompt(report: DkxAnalyticsReport, title: String, username: String?, periodTitle: String) -> (system: String, text: String) {
    let isChannel = report.isChannel
    var lines: [String] = []
    var header = isChannel ? "Канал " : "Группа "
    header += title
    if let username {
        header += " @" + username
    }
    lines.append(header)
    lines.append("Период \(periodTitle), с \(dkxAdviceDate(report.periodStart)) по \(dkxAdviceDate(report.periodEnd)), время телефона")
    if let members = report.members {
        lines.append((isChannel ? "Подписчиков сейчас " : "Участников сейчас ") + "\(members)")
    }
    lines.append("Постов \(report.posts.count), в день \(dkxAdviceNumber(report.postsPerDay))")
    if report.capped {
        lines.append("Загружены не все сообщения периода, только последние \(dkxAnalyticsMessageCap)")
    }
    if report.hasViews {
        lines.append("Просмотры на пост по постам старше 48 часов \(dkxAdviceNumber(report.avgViews)), медиана \(dkxAdviceNumber(report.medianViews)), таких постов \(report.maturePostCount)")
        if let err = report.err {
            lines.append("ERR, средние просмотры от подписчиков, \(dkxAdviceNumber(err))%")
        }
        if let engagement = report.engagement {
            lines.append("Вовлечённость, реакции, пересылки и комментарии от просмотров, \(dkxAdviceNumber(engagement))%")
        }
    }
    lines.append("Реакций \(report.totalReactions), пересылок \(report.totalForwards), комментариев \(report.totalComments)")
    if let previous = report.previous {
        var text = "Прошлый такой же период, постов \(previous.posts)"
        if report.hasViews {
            text += ", просмотры на пост \(dkxAdviceNumber(previous.avgViews))"
            if let err = previous.err {
                text += ", ERR \(dkxAdviceNumber(err))%"
            }
            if let engagement = previous.engagement {
                text += ", вовлечённость \(dkxAdviceNumber(engagement))%"
            }
        }
        lines.append(text)
    }
    if let growth = report.growth {
        lines.append("По данным Telegram за период пришло \(growth.joined), ушло \(growth.left), итого \(growth.net)")
        let days = report.growthDays.suffix(60).map { day -> String in
            return String(dkxAdviceDate(day.start).prefix(10)) + " +\(day.joined) -\(day.left)"
        }
        lines.append("Подписки по дням UTC " + days.joined(separator: ", "))
    }
    if report.hasViews {
        let hours = report.hours.enumerated().filter { $0.element.maturePosts > 0 }.map { "\($0.offset) ч \(Int($0.element.matureAvgViews)) (\($0.element.maturePosts))" }
        lines.append("Средние просмотры по часу публикации, в скобках число постов, " + hours.joined(separator: "; "))
        let days = report.weekdays.enumerated().filter { $0.element.maturePosts > 0 }.map { "\(dkxAnWeekdayShort($0.offset)) \(Int($0.element.matureAvgViews)) (\($0.element.maturePosts))" }
        lines.append("Средние просмотры по дню недели, " + days.joined(separator: "; "))
        if let best = report.bestTime {
            lines.append("Лучшее окно \(best.fromHour)-\(best.toHour) ч, \(dkxAdviceNumber(best.gainPercent))% к остальному времени, худшее \(best.worstFromHour)-\(best.worstToHour) ч, \(dkxAdviceNumber(best.worstPercent))%")
        }
    } else {
        let hours = report.hours.enumerated().filter { $0.element.posts > 0 }.map { "\($0.offset) ч \($0.element.posts)" }
        lines.append("Сообщений по часу, " + hours.joined(separator: "; "))
    }
    let kinds = report.kinds.map { row -> String in
        let average = row.bucket.maturePosts > 0 ? row.bucket.matureAvgViews : row.bucket.avgViews
        return report.hasViews ? "\(row.kind.title) \(row.bucket.posts) шт, \(Int(average)) просмотров в среднем" : "\(row.kind.title) \(row.bucket.posts) шт"
    }
    lines.append("Типы постов, " + kinds.joined(separator: "; "))
    if !report.reactions.isEmpty {
        lines.append("Реакции, " + report.reactions.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
    }
    if report.adPosts > 0 {
        lines.append("Рекламных постов \(report.adPosts), просмотры на рекламный пост \(Int(report.adAvgViews)), на обычный \(Int(report.nonAdAvgViews))")
    }
    if !report.sources.isEmpty {
        lines.append("Репосты из, " + report.sources.prefix(5).map { "\($0.name) \($0.count)" }.joined(separator: ", "))
    }
    if !report.isChannel && !report.authors.isEmpty {
        lines.append("Самые активные авторы, " + report.authors.prefix(8).map { "\($0.name) \($0.count)" }.joined(separator: ", "))
    }
    func describe(_ post: DkxPost) -> String {
        var parts = [dkxAdviceDate(post.date), post.kind.title]
        if report.hasViews {
            parts.append("просмотров \(post.views)")
            if let ratio = report.ratio(post) {
                parts.append("к среднему \(dkxAdviceNumber(ratio))")
            }
            if let engagement = post.engagement {
                parts.append("вовлечённость \(dkxAdviceNumber(engagement))%")
            }
        }
        parts.append("реакций \(post.reactions), пересылок \(post.forwards), комментариев \(post.comments)")
        if let impact = report.impacts[post.id] {
            parts.append("оценка подписок +\(Int(impact.joined.rounded())) -\(Int(impact.left.rounded()))")
        }
        if post.isAd {
            parts.append("реклама")
        }
        let text = post.fullText.replacingOccurrences(of: "\n", with: " ")
        parts.append("текст «" + String(text.prefix(140)) + "»")
        return parts.joined(separator: ", ")
    }
    let mature = report.posts.filter { report.isMature($0) }
    let ranked = (mature.isEmpty ? report.posts : mature).sorted(by: { report.hasViews ? $0.views > $1.views : $0.interactions > $1.interactions })
    lines.append("Лучшие посты")
    for post in ranked.prefix(10) {
        lines.append("- " + describe(post))
    }
    if ranked.count > 10 {
        lines.append("Слабые посты")
        for post in ranked.suffix(5) {
            lines.append("- " + describe(post))
        }
    }
    if let admin = report.admin {
        lines.append("Статистика Telegram с \(dkxAdviceDate(admin.periodStart)) по \(dkxAdviceDate(admin.periodEnd))")
        for value in admin.values {
            lines.append("\(value.label) сейчас \(dkxAdviceNumber(value.current)), раньше \(dkxAdviceNumber(value.previous))")
        }
        if let notifications = admin.notificationsPercent {
            lines.append("Уведомления включены у \(dkxAdviceNumber(notifications))%")
        }
        if !admin.viewsBySource.isEmpty {
            lines.append("Откуда просмотры, " + admin.viewsBySource.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
        }
        if !admin.followersBySource.isEmpty {
            lines.append("Откуда подписчики, " + admin.followersBySource.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
        }
        if !admin.languages.isEmpty {
            lines.append("Языки, " + admin.languages.prefix(6).map { "\($0.name) \($0.count)" }.joined(separator: ", "))
        }
        if let hours = admin.hours {
            lines.append("Просмотры канала по часам, время телефона, " + hours.enumerated().map { "\($0.offset) ч \(Int($0.element))" }.joined(separator: "; "))
        }
    }

    let subject = isChannel ? "канала" : "группы"
    let system = [
        "Ты опытный аналитик Telegram \(isChannel ? "каналов" : "групп"). Пользователь пришлёт статистику своего \(subject) за период.",
        "Ответь тремя частями. Сначала короткий итог, что происходит с \(isChannel ? "каналом" : "группой") и почему, с опорой на цифры.",
        "Потом прогноз на следующий такой же период. \(isChannel ? "Подписчики и просмотры на пост" : "Участники и активность"), с диапазоном от и до и объяснением, из каких цифр он следует.",
        "Потом от пяти до семи конкретных советов. Что публиковать, в какие дни и часы, какие форматы и темы усилить, от чего отказаться. Каждый совет подкрепи цифрой из статистики.",
        "Не выдумывай данных, которых нет. Если данных мало, так и скажи и объясни, чего не хватает. Подписки от поста это оценка по дню публикации, а не точная привязка.",
        "Пиши на \(dkxAdviceLanguage()) языке, простыми словами, как опытный коллега. Без markdown, без таблиц, без звёздочек и решёток. Части отделяй пустой строкой и коротким заголовком в отдельной строке."
    ].joined(separator: " ")
    return (system, lines.joined(separator: "\n"))
}

// Убирает разметку, если модель всё же её прислала
private func dkxCleanAdvice(_ text: String) -> String {
    var result: [String] = []
    for line in text.components(separatedBy: "\n") {
        var value = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "`", with: "")
        while value.hasPrefix("#") {
            value.removeFirst()
        }
        result.append(value.trimmingCharacters(in: .whitespaces))
    }
    return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

final class DkxAnalyticsAdviceController: DkxAnalyticsBaseController {
    private let report: DkxAnalyticsReport
    private let peer: EnginePeer?
    private let periodTitle: String
    private var loading = false
    private var advice: String?
    private var failure: String?
    private var author: String?
    private let requestDisposable = MetaDisposable()

    init(context: AccountContext, report: DkxAnalyticsReport, peer: EnginePeer?, periodTitle: String) {
        self.report = report
        self.peer = peer
        self.periodTitle = periodTitle
        super.init(context: context, title: DkxStrings.tr("Совет ИИ"))
        if DkxAIKeys.hasAnyKey {
            self.request()
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.requestDisposable.dispose()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Вернулись из «API ИИ» с новым ключом
        if self.advice == nil && !self.loading && self.failure == nil && DkxAIKeys.hasAnyKey {
            self.request()
        }
        self.reload()
    }

    private func request() {
        let title = self.peer?.displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder) ?? ""
        let prompt = dkxAdvicePrompt(report: self.report, title: title, username: self.peer?.addressName, periodTitle: self.periodTitle)
        self.loading = true
        self.failure = nil
        self.reload()
        self.requestDisposable.set((dkxAIComplete(system: prompt.system, text: prompt.text, temperature: 0.5, maxTokens: 3000, timeout: 120.0)
        |> deliverOnMainQueue).start(next: { [weak self] result, provider in
            guard let self else {
                return
            }
            self.loading = false
            self.advice = dkxCleanAdvice(result)
            self.author = provider.title + (DkxAIKeys.model(provider).map { ", " + $0 } ?? "")
            self.reload()
        }, error: { [weak self] error in
            guard let self else {
                return
            }
            self.loading = false
            switch error {
            case .noKeys:
                self.failure = DkxStrings.tr("Нет подключённого сервиса ИИ.")
            case let .failed(reason):
                self.failure = reason
            }
            self.reload()
        }))
    }

    override func buildContent(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        var y = top
        if !DkxAIKeys.hasAnyKey {
            y = self.addCard(x: x, top: y, width: width, title: DkxStrings.tr("Нужен ключ сервиса ИИ"), content: { card, inner, top, innerWidth in
                let text = DkxStrings.tr("Совет пишет ИИ по цифрам этого экрана. Подключите любой сервис в Dkx, раздел «API ИИ». Там вставляется ключ с сайта сервиса и выбирается модель.")
                return top + dkxAnPlace(dkxAnLabel(text, size: 15.0, color: self.colors.primary, lines: 0), in: card, x: inner, y: top, width: innerWidth)
            }) + 14.0
            let button = self.makeButton(DkxStrings.tr("Открыть «API ИИ»"), width: width, height: 52.0, filled: true, fontSize: 17.0, icon: "key", action: { [weak self] in
                guard let self else {
                    return
                }
                self.push(dkxAIKeysController(context: self.context))
            })
            button.frame.origin = CGPoint(x: x, y: y)
            self.add(button)
            return y + 52.0 + 8.0
        }
        if self.loading {
            return self.addCard(x: x, top: y, width: width, title: nil, content: { card, inner, top, innerWidth in
                let indicator = UIActivityIndicatorView(style: .medium)
                indicator.color = self.colors.secondary
                indicator.frame = CGRect(x: inner + (innerWidth - 30.0) / 2.0, y: top + 10.0, width: 30.0, height: 30.0)
                indicator.startAnimating()
                card.addSubview(indicator)
                let text = DkxStrings.tr("ИИ разбирает статистику за {}. Обычно это до минуты.", self.periodTitle)
                return top + 50.0 + dkxAnPlace(dkxAnLabel(text, size: 14.0, color: self.colors.secondary, lines: 0, alignment: .center), in: card, x: inner, y: top + 50.0, width: innerWidth)
            }) + 8.0
        }
        if let failure = self.failure {
            y = self.addCard(x: x, top: y, width: width, title: DkxStrings.tr("Совет не получен"), content: { card, inner, top, innerWidth in
                return top + dkxAnPlace(dkxAnLabel(failure, size: 15.0, color: self.colors.primary, lines: 0), in: card, x: inner, y: top, width: innerWidth)
            }) + 14.0
            let button = self.makeButton(DkxStrings.tr("Попробовать ещё раз"), width: width, height: 52.0, filled: true, fontSize: 17.0, icon: "arrow.clockwise", action: { [weak self] in
                self?.request()
            })
            button.frame.origin = CGPoint(x: x, y: y)
            self.add(button)
            return y + 52.0 + 8.0
        }
        guard let advice = self.advice else {
            return y
        }
        y = self.addCard(x: x, top: y, width: width, title: nil, content: { card, inner, top, innerWidth in
            let label = dkxAnLabel(advice, size: 16.0, color: self.colors.primary, lines: 0)
            return top + dkxAnPlace(label, in: card, x: inner, y: top, width: innerWidth)
        }) + 14.0
        let half = floor((width - 10.0) / 2.0)
        let again = self.makeButton(DkxStrings.tr("Спросить ещё раз"), width: half, height: 48.0, filled: false, fontSize: 15.0, icon: "arrow.clockwise", action: { [weak self] in
            self?.request()
        })
        again.frame.origin = CGPoint(x: x, y: y)
        self.add(again)
        let copy = self.makeButton(DkxStrings.tr("Скопировать"), width: half, height: 48.0, filled: false, fontSize: 15.0, icon: "doc.on.doc", action: { [weak self] in
            guard let self, let advice = self.advice else {
                return
            }
            UIPasteboard.general.string = advice
            self.showToast(DkxStrings.tr("Совет скопирован"))
        })
        copy.frame.origin = CGPoint(x: x + half + 10.0, y: y)
        self.add(copy)
        y += 48.0 + 14.0
        var note = DkxStrings.tr("ИИ может ошибаться. Цифры сверяйте с дашбордом, прогноз это ориентир, а не обещание.")
        if let author = self.author {
            note = DkxStrings.tr("Написал {}.", author) + " " + note
        }
        return self.addFootnote(note, x: x, top: y, width: width) + 8.0
    }
}
