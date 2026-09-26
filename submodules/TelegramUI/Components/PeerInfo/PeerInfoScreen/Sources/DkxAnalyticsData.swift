import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramUIPreferences

// Формулы расписаны в docs/wiki/dkx-analytics.md, эталон с тестами tools/dkx_analytics_ref.py

struct DkxAnalyticsPeriod {
    let days: Int
    let title: String
}

var dkxAnalyticsPeriods: [DkxAnalyticsPeriod] {
    return [
        DkxAnalyticsPeriod(days: 1, title: DkxStrings.tr("1 день")),
        DkxAnalyticsPeriod(days: 7, title: DkxStrings.tr("7 дней")),
        DkxAnalyticsPeriod(days: 14, title: DkxStrings.tr("14 дней")),
        DkxAnalyticsPeriod(days: 30, title: DkxStrings.tr("30 дней")),
        DkxAnalyticsPeriod(days: 60, title: DkxStrings.tr("2 мес")),
        DkxAnalyticsPeriod(days: 180, title: DkxStrings.tr("6 мес")),
        DkxAnalyticsPeriod(days: 365, title: DkxStrings.tr("1 год")),
        DkxAnalyticsPeriod(days: 730, title: DkxStrings.tr("2 года")),
        DkxAnalyticsPeriod(days: 1825, title: DkxStrings.tr("5 лет"))
    ]
}

let dkxAnalyticsDefaultPeriod = 3
let dkxAnalyticsMessageCap = 20000
// Просмотры у свежего поста ещё растут, в сравнения он не идёт
let dkxAnalyticsMatureAge: Int32 = 48 * 60 * 60
// Для длинных периодов прошлый такой же период не грузим, слишком долго
let dkxAnalyticsCompareMaxDays = 365

enum DkxPostKind: Int {
    case text
    case photo
    case video
    case album
    case voice
    case round
    case file
    case poll
    case link
    case sticker
    case location
    case other

    var title: String {
        switch self {
        case .text:
            return DkxStrings.tr("Текст")
        case .photo:
            return DkxStrings.tr("Фото")
        case .video:
            return DkxStrings.tr("Видео")
        case .album:
            return DkxStrings.tr("Альбом")
        case .voice:
            return DkxStrings.tr("Голосовое")
        case .round:
            return DkxStrings.tr("Кружок")
        case .file:
            return DkxStrings.tr("Файл")
        case .poll:
            return DkxStrings.tr("Опрос")
        case .link:
            return DkxStrings.tr("Ссылка")
        case .sticker:
            return DkxStrings.tr("Стикер")
        case .location:
            return DkxStrings.tr("Геопозиция")
        case .other:
            return DkxStrings.tr("Прочее")
        }
    }
}

struct DkxNamedCount: Equatable {
    let name: String
    let count: Int
}

struct DkxPost: Equatable {
    let id: EngineMessage.Id
    let date: Int32
    let kind: DkxPostKind
    let preview: String
    let fullText: String
    let views: Int
    let forwards: Int
    let comments: Int
    let reactions: Int
    let paidStars: Int
    let reactionItems: [DkxNamedCount]
    let isAd: Bool
    let authorId: Int64?
    let authorName: String?
    let sourceName: String?
    let domains: [String]

    var interactions: Int {
        return self.reactions + self.forwards + self.comments
    }

    var engagement: Double? {
        return self.views > 0 ? Double(self.interactions) / Double(self.views) * 100.0 : nil
    }
}

struct DkxBucket: Equatable {
    var posts: Int = 0
    var views: Int = 0
    var reactions: Int = 0
    var forwards: Int = 0
    var comments: Int = 0
    var maturePosts: Int = 0
    var matureViews: Int = 0

    var matureAvgViews: Double {
        return self.maturePosts == 0 ? 0.0 : Double(self.matureViews) / Double(self.maturePosts)
    }

    var avgViews: Double {
        return self.posts == 0 ? 0.0 : Double(self.views) / Double(self.posts)
    }

    var engagement: Double? {
        return self.views > 0 ? Double(self.reactions + self.forwards + self.comments) / Double(self.views) * 100.0 : nil
    }
}

struct DkxDayBucket: Equatable {
    let start: Int32
    var bucket: DkxBucket
}

struct DkxGrowthDay: Equatable {
    let start: Int32
    let joined: Int
    let left: Int
}

struct DkxSlotGain: Equatable {
    let weekday: Int
    let hour: Int
    let percent: Double
}

struct DkxBestTime: Equatable {
    let weekdays: [Int]
    let fromHour: Int
    let toHour: Int
    let gainPercent: Double
    let worstFromHour: Int
    let worstToHour: Int
    let worstPercent: Double
    let alternatives: [DkxSlotGain]
    let sampleSize: Int
}

struct DkxPostImpact: Equatable {
    let joined: Double
    let left: Double
    let dayJoined: Int
    let dayLeft: Int
    let postsThatDay: Int

    var net: Double {
        return self.joined - self.left
    }
}

struct DkxPeriodSummary: Equatable {
    let posts: Int
    let avgViews: Double
    let err: Double?
    let engagement: Double?
}

struct DkxGrowthTotals: Equatable {
    let joined: Int
    let left: Int
    let days: Int

    var net: Int {
        return self.joined - self.left
    }
}

struct DkxKindRow: Equatable {
    let kind: DkxPostKind
    let bucket: DkxBucket
}

struct DkxAnalyticsReport: Equatable {
    let isChannel: Bool
    let hasViews: Bool
    let members: Int?
    let periodDays: Int
    let periodStart: Int32
    let periodEnd: Int32
    let capped: Bool
    let posts: [DkxPost]
    let maturePostCount: Int
    let totalViews: Int
    let totalReactions: Int
    let totalForwards: Int
    let totalComments: Int
    let totalPaidStars: Int
    let avgViews: Double
    let medianViews: Double
    let err: Double?
    let engagement: Double?
    let postsPerDay: Double
    let days: [DkxDayBucket]
    let chart: [DkxDayBucket]
    let chartHourly: Bool
    let heat: [[DkxBucket]]
    let hours: [DkxBucket]
    let weekdays: [DkxBucket]
    let kinds: [DkxKindRow]
    let reactions: [DkxNamedCount]
    let sources: [DkxNamedCount]
    let domains: [DkxNamedCount]
    let authors: [DkxNamedCount]
    let adPosts: Int
    let adAvgViews: Double
    let nonAdAvgViews: Double
    let bestTime: DkxBestTime?
    let impacts: [EngineMessage.Id: DkxPostImpact]
    let growth: DkxGrowthTotals?
    let growthDays: [DkxGrowthDay]
    let typicalDayJoined: Int?
    let readingHours: [Double]?
    let activeAuthors: Int
    let previous: DkxPeriodSummary?
    let admin: DkxAdminStats?
    let viewsSeries: [Double]
    let viewsFromTelegram: Bool

    func isMature(_ post: DkxPost) -> Bool {
        return self.periodEnd - post.date >= dkxAnalyticsMatureAge
    }

    func ratio(_ post: DkxPost) -> Double? {
        guard self.hasViews, self.isMature(post), self.avgViews > 0.0 else {
            return nil
        }
        return Double(post.views) / self.avgViews
    }

    // Доля остальных зрелых постов, у которых просмотров меньше
    func percentile(_ post: DkxPost) -> Double? {
        guard self.hasViews, self.isMature(post), self.maturePostCount >= 5 else {
            return nil
        }
        var below = 0
        for other in self.posts where self.isMature(other) && other.id != post.id && other.views < post.views {
            below += 1
        }
        return Double(below) / Double(self.maturePostCount - 1) * 100.0
    }

    // Место поста среди зрелых по просмотрам, начиная с 1
    func viewsRank(_ post: DkxPost) -> Int? {
        guard self.hasViews, self.isMature(post) else {
            return nil
        }
        return 1 + self.posts.filter { self.isMature($0) && $0.views > post.views }.count
    }

    // Средние на пост по зрелым постам, как и средние просмотры
    func averages() -> (reactions: Double, forwards: Double, comments: Double, engagement: Double?) {
        let mature = self.posts.filter { self.isMature($0) }
        let source = mature.isEmpty ? self.posts : mature
        guard !source.isEmpty else {
            return (0.0, 0.0, 0.0, nil)
        }
        let count = Double(source.count)
        var views = 0
        var interactions = 0
        var reactions = 0
        var forwards = 0
        var comments = 0
        for post in source {
            views += post.views
            interactions += post.interactions
            reactions += post.reactions
            forwards += post.forwards
            comments += post.comments
        }
        var engagement: Double?
        if views > 0 {
            engagement = Double(interactions) / Double(views) * 100.0
        }
        return (Double(reactions) / count, Double(forwards) / count, Double(comments) / count, engagement)
    }

    func netRank(_ post: DkxPost) -> Int? {
        guard let impact = self.impacts[post.id] else {
            return nil
        }
        return 1 + self.impacts.values.filter { $0.net > impact.net }.count
    }

    static func == (lhs: DkxAnalyticsReport, rhs: DkxAnalyticsReport) -> Bool {
        return lhs.posts == rhs.posts && lhs.periodStart == rhs.periodStart && lhs.periodEnd == rhs.periodEnd && lhs.members == rhs.members && lhs.impacts == rhs.impacts && lhs.admin == rhs.admin
    }
}

func dkxMondayIndex(_ weekday: Int) -> Int {
    // У Calendar воскресенье это 1, у нас понедельник это 0
    return (weekday + 5) % 7
}

private func dkxKind(_ message: Message) -> DkxPostKind? {
    for media in message.media {
        if media is TelegramMediaAction {
            return nil
        }
        if media is TelegramMediaImage {
            return .photo
        }
        if let file = media as? TelegramMediaFile {
            if file.isInstantVideo {
                return .round
            }
            if file.isVoice {
                return .voice
            }
            if file.isSticker || file.isAnimatedSticker {
                return .sticker
            }
            if file.isVideo || file.isAnimated {
                return .video
            }
            return .file
        }
        if media is TelegramMediaPoll {
            return .poll
        }
        if media is TelegramMediaMap {
            return .location
        }
        if media is TelegramMediaWebpage {
            return .link
        }
    }
    if !message.text.isEmpty {
        return .text
    }
    return .other
}

func dkxHost(_ raw: String) -> String? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("mailto:") || value.hasPrefix("tel:") {
        return nil
    }
    if !value.contains("://") {
        value = "https://" + value
    }
    guard var host = URL(string: value)?.host?.lowercased(), !host.isEmpty else {
        return nil
    }
    if host.hasPrefix("www.") {
        host = String(host.dropFirst(4))
    }
    return host
}

// Реклама по пометкам, которые ставят по закону и по привычке
func dkxIsAd(_ text: String) -> Bool {
    let lower = text.lowercased()
    if lower.contains("erid") || lower.contains("#реклама") || lower.contains("на правах рекламы") {
        return true
    }
    for word in lower.components(separatedBy: CharacterSet.whitespacesAndNewlines) {
        if word == "#ad" || word == "#ads" || word == "#promo" {
            return true
        }
    }
    return false
}

private func dkxPeerName(_ peer: Peer) -> String {
    return EnginePeer(peer).compactDisplayTitle
}

private func dkxMakePost(_ group: [Message]) -> DkxPost? {
    guard let first = group.first else {
        return nil
    }
    var kinds: [DkxPostKind] = []
    var text = ""
    var views = 0
    var forwards = 0
    var comments = 0
    var reactionCounts: [String: Int] = [:]
    var paidStars = 0
    var domains: [String] = []
    for message in group {
        guard let messageKind = dkxKind(message) else {
            return nil
        }
        kinds.append(messageKind)
        if text.isEmpty && !message.text.isEmpty {
            text = message.text
        }
        for media in message.media {
            if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content, let host = dkxHost(content.url) {
                domains.append(host)
            }
        }
        for attribute in message.attributes {
            if let attribute = attribute as? ViewCountMessageAttribute {
                views = max(views, attribute.count)
            } else if let attribute = attribute as? ForwardCountMessageAttribute {
                forwards = max(forwards, attribute.count)
            } else if let attribute = attribute as? ReplyThreadMessageAttribute {
                comments = max(comments, Int(attribute.count))
            } else if let attribute = attribute as? ReactionsMessageAttribute {
                for reaction in attribute.reactions {
                    switch reaction.value {
                    case let .builtin(value):
                        reactionCounts[value, default: 0] += Int(reaction.count)
                    case .custom:
                        reactionCounts[DkxStrings.tr("свои эмодзи"), default: 0] += Int(reaction.count)
                    case .stars:
                        paidStars += Int(reaction.count)
                    }
                }
            } else if let attribute = attribute as? TextEntitiesMessageAttribute {
                let nsText = message.text as NSString
                for entity in attribute.entities {
                    switch entity.type {
                    case let .TextUrl(url):
                        if let host = dkxHost(url) {
                            domains.append(host)
                        }
                    case .Url:
                        let range = NSRange(location: entity.range.lowerBound, length: entity.range.count)
                        if range.location >= 0 && range.location + range.length <= nsText.length, let host = dkxHost(nsText.substring(with: range)) {
                            domains.append(host)
                        }
                    default:
                        break
                    }
                }
            }
        }
    }
    let kind: DkxPostKind
    if group.count > 1 {
        let mediaKinds = Set(kinds.filter { $0 != .text })
        kind = mediaKinds.count == 1 ? (mediaKinds.first ?? .album) : .album
    } else {
        kind = kinds.first ?? .other
    }
    let reactionItems = reactionCounts.map { DkxNamedCount(name: $0.key, count: $0.value) }.sorted(by: { lhs, rhs in
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        return lhs.name < rhs.name
    })
    let reactions = reactionItems.reduce(0) { $0 + $1.count }
    let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    let preview = singleLine.isEmpty ? kind.title : String(singleLine.prefix(160))
    var sourceName: String?
    if let forwardInfo = first.forwardInfo {
        if let peer = forwardInfo.source ?? forwardInfo.author {
            sourceName = dkxPeerName(peer)
        } else if let signature = forwardInfo.authorSignature {
            sourceName = signature
        }
    }
    var authorId: Int64?
    var authorName: String?
    if let author = first.author {
        authorId = author.id.toInt64()
        authorName = dkxPeerName(author)
    }
    return DkxPost(
        id: group.map { $0.id }.min() ?? first.id,
        date: group.map { $0.timestamp }.min() ?? first.timestamp,
        kind: kind,
        preview: preview,
        fullText: text,
        views: views,
        forwards: forwards,
        comments: comments,
        reactions: reactions,
        paidStars: paidStars,
        reactionItems: reactionItems,
        isAd: dkxIsAd(text),
        authorId: authorId,
        authorName: authorName,
        sourceName: sourceName,
        domains: Array(Set(domains)).sorted()
    )
}

// Альбом это несколько сообщений с общим groupingKey, считаем его одним постом
func dkxMakePosts(_ messages: [Message]) -> [DkxPost] {
    var groups: [Int64: [Message]] = [:]
    var singles: [[Message]] = []
    var seen = Set<MessageId>()
    for message in messages {
        if seen.contains(message.id) {
            continue
        }
        seen.insert(message.id)
        if let key = message.groupingKey {
            groups[key, default: []].append(message)
        } else {
            singles.append([message])
        }
    }
    var result: [DkxPost] = []
    for group in singles + Array(groups.values) {
        if let post = dkxMakePost(group.sorted(by: { $0.id < $1.id })) {
            result.append(post)
        }
    }
    return result.sorted(by: { lhs, rhs in
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.id > rhs.id
    })
}

func dkxParseStatsGraph(_ graph: StatsGraph) -> (x: [Double], series: [(id: String, name: String, values: [Double])])? {
    guard case let .Loaded(_, data) = graph, let raw = data.data(using: .utf8), let json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any], let columns = json["columns"] as? [[Any]] else {
        return nil
    }
    let names = json["names"] as? [String: String] ?? [:]
    var x: [Double] = []
    var series: [(id: String, name: String, values: [Double])] = []
    for column in columns {
        guard let id = column.first as? String else {
            continue
        }
        let values = column.dropFirst().map { ($0 as? NSNumber)?.doubleValue ?? 0.0 }
        if id == "x" {
            x = values
        } else {
            series.append((id: id, name: names[id] ?? id, values: values))
        }
    }
    if x.isEmpty || series.isEmpty {
        return nil
    }
    return (x: x, series: series)
}

// График подписчиков канала. Первая линия пришедшие, вторая ушедшие, по суткам UTC
func dkxGrowthDays(_ graph: StatsGraph) -> [DkxGrowthDay] {
    guard let parsed = dkxParseStatsGraph(graph) else {
        return []
    }
    let joinedIndex = parsed.series.firstIndex(where: { $0.name.lowercased().contains("join") }) ?? 0
    let leftIndex = parsed.series.firstIndex(where: { $0.name.lowercased().contains("left") }) ?? min(1, parsed.series.count - 1)
    if joinedIndex == leftIndex {
        return []
    }
    let joinedValues = parsed.series[joinedIndex].values
    let leftValues = parsed.series[leftIndex].values
    var result: [DkxGrowthDay] = []
    for (index, x) in parsed.x.enumerated() {
        let joined = index < joinedValues.count ? joinedValues[index] : 0.0
        let left = index < leftValues.count ? leftValues[index] : 0.0
        let seconds = Int64(x / 1000.0)
        let start = Int32(clamping: seconds - seconds % 86400)
        result.append(DkxGrowthDay(start: start, joined: Int(abs(joined).rounded()), left: Int(abs(left).rounded())))
    }
    return result
}

// Просмотры по часам суток от Telegram в UTC, переводим в часы телефона
func dkxReadingHours(_ graph: StatsGraph, secondsFromGMT: Int) -> [Double]? {
    guard let parsed = dkxParseStatsGraph(graph), let first = parsed.series.first else {
        return nil
    }
    var result = Array(repeating: 0.0, count: 24)
    let shift = Int((Double(secondsFromGMT) / 3600.0).rounded(.down))
    var any = false
    for (index, x) in parsed.x.enumerated() where index < first.values.count {
        let hour = Int(x)
        guard hour >= 0 && hour < 24 else {
            continue
        }
        result[((hour + shift) % 24 + 24) % 24] += first.values[index]
        any = true
    }
    return any ? result : nil
}

func dkxMedian(_ values: [Int]) -> Double {
    if values.isEmpty {
        return 0.0
    }
    let sorted = values.sorted()
    if sorted.count % 2 == 1 {
        return Double(sorted[sorted.count / 2])
    }
    return Double(sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
}

private func dkxTop(_ counts: [String: Int], limit: Int) -> [DkxNamedCount] {
    return counts.map { DkxNamedCount(name: $0.key, count: $0.value) }.sorted(by: { lhs, rhs in
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        return lhs.name < rhs.name
    }).prefix(limit).map { $0 }
}

// Средние просмотры группы постов к средним просмотрам всех остальных зрелых постов, в процентах
func dkxGainVsRest(posts: Int, views: Int, totalPosts: Int, totalViews: Int) -> Double? {
    let restPosts = totalPosts - posts
    let restViews = totalViews - views
    guard posts > 0, restPosts > 0, restViews > 0 else {
        return nil
    }
    return (Double(views) / Double(posts) / (Double(restViews) / Double(restPosts)) - 1.0) * 100.0
}

// Окно 3 часа по кругу суток, начинается с часа, где были посты. В окне от 4 зрелых
// постов, всего зрелых от 20. Каждое окно сравнивается со всеми постами вне его
func dkxBestTime(hours: [DkxBucket], weekdays: [DkxBucket], heat: [[DkxBucket]], matureCount: Int) -> DkxBestTime? {
    let totalPosts = hours.reduce(0) { $0 + $1.maturePosts }
    let totalViews = hours.reduce(0) { $0 + $1.matureViews }
    guard matureCount >= 20, totalPosts >= 20, totalViews > 0 else {
        return nil
    }
    var bestScore = -Double.greatestFiniteMagnitude
    var bestFrom = 0
    var worstScore = Double.greatestFiniteMagnitude
    var worstFrom = 0
    var windows = 0
    for from in 0 ..< 24 {
        var posts = 0
        var views = 0
        for offset in 0 ..< 3 {
            let bucket = hours[(from + offset) % 24]
            posts += bucket.maturePosts
            views += bucket.matureViews
        }
        guard hours[from].maturePosts > 0, posts >= 4, let score = dkxGainVsRest(posts: posts, views: views, totalPosts: totalPosts, totalViews: totalViews) else {
            continue
        }
        windows += 1
        if score > bestScore {
            bestScore = score
            bestFrom = from
        }
        if score < worstScore {
            worstScore = score
            worstFrom = from
        }
    }
    guard windows >= 2 else {
        return nil
    }
    var goodDays: [(day: Int, score: Double)] = []
    for (index, bucket) in weekdays.enumerated() where bucket.maturePosts >= 3 {
        if let score = dkxGainVsRest(posts: bucket.maturePosts, views: bucket.matureViews, totalPosts: totalPosts, totalViews: totalViews), score >= 5.0 {
            goodDays.append((day: index, score: score))
        }
    }
    goodDays.sort(by: { lhs, rhs in
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.day < rhs.day
    })
    var alternatives: [DkxSlotGain] = []
    for (day, row) in heat.enumerated() {
        for (hour, bucket) in row.enumerated() where bucket.maturePosts >= 2 {
            if (hour - bestFrom + 24) % 24 < 3 {
                continue
            }
            if let percent = dkxGainVsRest(posts: bucket.maturePosts, views: bucket.matureViews, totalPosts: totalPosts, totalViews: totalViews), percent > 5.0 {
                alternatives.append(DkxSlotGain(weekday: day, hour: hour, percent: percent))
            }
        }
    }
    alternatives.sort(by: { lhs, rhs in
        if lhs.percent != rhs.percent {
            return lhs.percent > rhs.percent
        }
        return lhs.weekday * 24 + lhs.hour < rhs.weekday * 24 + rhs.hour
    })
    return DkxBestTime(
        weekdays: goodDays.prefix(2).map { $0.day }.sorted(),
        fromHour: bestFrom,
        toHour: (bestFrom + 3) % 24,
        gainPercent: bestScore,
        worstFromHour: worstFrom,
        worstToHour: (worstFrom + 3) % 24,
        worstPercent: worstScore,
        alternatives: Array(alternatives.prefix(3)),
        sampleSize: matureCount
    )
}

// Прирост дня делится между постами этого дня по просмотрам. Сутки UTC, как у Telegram
func dkxImpacts(posts: [DkxPost], growth: [DkxGrowthDay]) -> [EngineMessage.Id: DkxPostImpact] {
    if growth.isEmpty {
        return [:]
    }
    var byDay: [Int32: DkxGrowthDay] = [:]
    for day in growth {
        byDay[day.start] = day
    }
    var postsByDay: [Int32: [DkxPost]] = [:]
    for post in posts {
        postsByDay[post.date - post.date % 86400, default: []].append(post)
    }
    var result: [EngineMessage.Id: DkxPostImpact] = [:]
    for (dayStart, dayPosts) in postsByDay {
        guard let day = byDay[dayStart] else {
            continue
        }
        let totalViews = dayPosts.reduce(0) { $0 + $1.views }
        for post in dayPosts {
            let share = totalViews > 0 ? Double(post.views) / Double(totalViews) : 1.0 / Double(dayPosts.count)
            result[post.id] = DkxPostImpact(joined: Double(day.joined) * share, left: Double(day.left) * share, dayJoined: day.joined, dayLeft: day.left, postsThatDay: dayPosts.count)
        }
    }
    return result
}

private func dkxAdd(_ bucket: inout DkxBucket, _ post: DkxPost, mature: Bool) {
    bucket.posts += 1
    bucket.views += post.views
    bucket.reactions += post.reactions
    bucket.forwards += post.forwards
    bucket.comments += post.comments
    if mature {
        bucket.maturePosts += 1
        bucket.matureViews += post.views
    }
}

private func dkxAverageViews(_ posts: [DkxPost], now: Int32) -> (avg: Double, median: Double, matureCount: Int) {
    let mature = posts.filter { now - $0.date >= dkxAnalyticsMatureAge }.map { $0.views }
    let source = mature.isEmpty ? posts.map { $0.views } : mature
    if source.isEmpty {
        return (0.0, 0.0, 0)
    }
    return (Double(source.reduce(0, +)) / Double(source.count), dkxMedian(source), mature.count)
}

private func dkxEngagement(_ posts: [DkxPost]) -> Double? {
    let views = posts.reduce(0) { $0 + $1.views }
    guard views > 0 else {
        return nil
    }
    let interactions = posts.reduce(0) { $0 + $1.interactions }
    return Double(interactions) / Double(views) * 100.0
}

func dkxSummary(_ posts: [DkxPost], members: Int?, now: Int32) -> DkxPeriodSummary {
    let hasViews = posts.contains(where: { $0.views > 0 })
    let average = dkxAverageViews(posts, now: now)
    var err: Double?
    if hasViews, let members, members > 0 {
        err = average.avg / Double(members) * 100.0
    }
    return DkxPeriodSummary(posts: posts.count, avgViews: average.avg, err: err, engagement: hasViews ? dkxEngagement(posts) : nil)
}

private func dkxBucketStarts(from start: Int32, to end: Int32, component: Calendar.Component, calendar: Calendar) -> [Int32] {
    var result: [Int32] = []
    var cursor: Date
    switch component {
    case .hour:
        let date = Date(timeIntervalSince1970: Double(start))
        cursor = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    case .weekOfYear:
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(start)))
        let offset = dkxMondayIndex(calendar.component(.weekday, from: dayStart))
        cursor = calendar.date(byAdding: .day, value: -offset, to: dayStart) ?? dayStart
    default:
        cursor = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(start)))
    }
    let endDate = Date(timeIntervalSince1970: Double(end))
    while cursor <= endDate && result.count < 4000 {
        result.append(Int32(cursor.timeIntervalSince1970))
        guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else {
            break
        }
        cursor = next
    }
    return result
}

private func dkxFill(_ starts: [Int32], _ posts: [DkxPost], now: Int32) -> [DkxDayBucket] {
    var buckets = starts.map { DkxDayBucket(start: $0, bucket: DkxBucket()) }
    for post in posts {
        var low = 0
        var high = starts.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= post.date {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        if found >= 0 {
            dkxAdd(&buckets[found].bucket, post, mature: now - post.date >= dkxAnalyticsMatureAge)
        }
    }
    return buckets
}

func dkxBuildReport(allPosts: [DkxPost], isChannel: Bool, members: Int?, periodDays: Int, now: Int32, capped: Bool, previousComplete: Bool, admin: DkxAdminStats?, calendar: Calendar = Calendar.current) -> DkxAnalyticsReport {
    let growth = admin?.growth ?? []
    let periodStart = now - Int32(periodDays) * 86400
    let posts = allPosts.filter { $0.date >= periodStart && $0.date <= now }
    let previousPosts = allPosts.filter { $0.date >= periodStart - Int32(periodDays) * 86400 && $0.date < periodStart }
    let hasViews = posts.contains(where: { $0.views > 0 })

    var totalViews = 0
    var totalReactions = 0
    var totalForwards = 0
    var totalComments = 0
    var totalPaidStars = 0
    var heat = Array(repeating: Array(repeating: DkxBucket(), count: 24), count: 7)
    var hours = Array(repeating: DkxBucket(), count: 24)
    var weekdays = Array(repeating: DkxBucket(), count: 7)
    var kindBuckets: [DkxPostKind: DkxBucket] = [:]
    var reactionCounts: [String: Int] = [:]
    var sourceCounts: [String: Int] = [:]
    var domainCounts: [String: Int] = [:]
    var authorCounts: [String: Int] = [:]
    var authorIds = Set<Int64>()
    var adPosts = 0
    var adMature = DkxBucket()
    var nonAdMature = DkxBucket()

    for post in posts {
        let mature = now - post.date >= dkxAnalyticsMatureAge
        totalViews += post.views
        totalReactions += post.reactions
        totalForwards += post.forwards
        totalComments += post.comments
        totalPaidStars += post.paidStars
        let date = Date(timeIntervalSince1970: Double(post.date))
        let hour = calendar.component(.hour, from: date)
        let weekday = dkxMondayIndex(calendar.component(.weekday, from: date))
        dkxAdd(&heat[weekday][hour], post, mature: mature)
        dkxAdd(&hours[hour], post, mature: mature)
        dkxAdd(&weekdays[weekday], post, mature: mature)
        var kindBucket = kindBuckets[post.kind] ?? DkxBucket()
        dkxAdd(&kindBucket, post, mature: mature)
        kindBuckets[post.kind] = kindBucket
        for item in post.reactionItems {
            reactionCounts[item.name, default: 0] += item.count
        }
        if let source = post.sourceName, !source.isEmpty {
            sourceCounts[source, default: 0] += 1
        }
        for domain in post.domains {
            domainCounts[domain, default: 0] += 1
        }
        if let authorId = post.authorId, let name = post.authorName {
            authorIds.insert(authorId)
            authorCounts[name, default: 0] += 1
        }
        if post.isAd {
            adPosts += 1
            if mature {
                dkxAdd(&adMature, post, mature: true)
            }
        } else if mature {
            dkxAdd(&nonAdMature, post, mature: true)
        }
    }

    let summary = dkxSummary(posts, members: members, now: now)
    let average = dkxAverageViews(posts, now: now)
    let days = dkxFill(dkxBucketStarts(from: periodStart, to: now, component: .day, calendar: calendar), posts, now: now)
    let chart: [DkxDayBucket]
    let chartHourly: Bool
    if periodDays <= 2 {
        chart = dkxFill(dkxBucketStarts(from: periodStart, to: now, component: .hour, calendar: calendar), posts, now: now)
        chartHourly = true
    } else if periodDays > 180 {
        chart = dkxFill(dkxBucketStarts(from: periodStart, to: now, component: .weekOfYear, calendar: calendar), posts, now: now)
        chartHourly = false
    } else {
        chart = days
        chartHourly = false
    }

    // Админу берём суточные просмотры всего канала от Telegram, если они покрывают период
    var viewsSeries = chart.map { Double($0.bucket.views) }
    var viewsFromTelegram = false
    if isChannel, let admin, !admin.dailyViews.isEmpty, !chartHourly, periodDays <= 180 {
        let firstDay = admin.dailyViewsStart - admin.dailyViewsStart % 86400
        let startDay = periodStart - periodStart % 86400
        if firstDay <= startDay {
            var values: [Double] = []
            for (index, value) in admin.dailyViews.enumerated() {
                let day = firstDay + Int32(index) * 86400
                if day >= startDay && day <= now {
                    values.append(value)
                }
            }
            if values.count >= 2 {
                viewsSeries = values
                viewsFromTelegram = true
            }
        }
    }

    let growthInPeriod = growth.filter { $0.start + 86400 > periodStart && $0.start <= now }
    var growthTotals: DkxGrowthTotals?
    if !growthInPeriod.isEmpty {
        growthTotals = DkxGrowthTotals(joined: growthInPeriod.reduce(0) { $0 + $1.joined }, left: growthInPeriod.reduce(0) { $0 + $1.left }, days: growthInPeriod.count)
    }

    let kinds = kindBuckets.map { DkxKindRow(kind: $0.key, bucket: $0.value) }.sorted(by: { lhs, rhs in
        if lhs.bucket.posts != rhs.bucket.posts {
            return lhs.bucket.posts > rhs.bucket.posts
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    })

    return DkxAnalyticsReport(
        isChannel: isChannel,
        hasViews: hasViews,
        members: members,
        periodDays: periodDays,
        periodStart: periodStart,
        periodEnd: now,
        capped: capped,
        posts: posts,
        maturePostCount: average.matureCount,
        totalViews: totalViews,
        totalReactions: totalReactions,
        totalForwards: totalForwards,
        totalComments: totalComments,
        totalPaidStars: totalPaidStars,
        avgViews: average.avg,
        medianViews: average.median,
        err: summary.err,
        engagement: summary.engagement,
        postsPerDay: Double(posts.count) / Double(max(1, periodDays)),
        days: days,
        chart: chart,
        chartHourly: chartHourly,
        heat: heat,
        hours: hours,
        weekdays: weekdays,
        kinds: kinds,
        reactions: dkxTop(reactionCounts, limit: 10),
        sources: dkxTop(sourceCounts, limit: 10),
        domains: dkxTop(domainCounts, limit: 10),
        authors: dkxTop(authorCounts, limit: 15),
        adPosts: adPosts,
        adAvgViews: adMature.matureAvgViews,
        nonAdAvgViews: nonAdMature.matureAvgViews,
        bestTime: hasViews ? dkxBestTime(hours: hours, weekdays: weekdays, heat: heat, matureCount: average.matureCount) : nil,
        impacts: isChannel ? dkxImpacts(posts: posts, growth: growth) : [:],
        growth: growthTotals,
        growthDays: growthInPeriod,
        typicalDayJoined: growth.isEmpty ? nil : Int(dkxMedian(growth.map { $0.joined }).rounded()),
        readingHours: admin?.hours,
        activeAuthors: authorIds.count,
        previous: previousComplete && !previousPosts.isEmpty ? dkxSummary(previousPosts, members: members, now: now) : nil,
        admin: admin,
        viewsSeries: viewsSeries,
        viewsFromTelegram: viewsFromTelegram
    )
}

struct DkxAnalyticsSource {
    let messages: [Message]
    let capped: Bool
    let oldestDate: Int32?
}

func dkxLoadHistory(context: AccountContext, peerId: EnginePeer.Id, minDate: Int32, cap: Int, progress: @escaping (Int) -> Void) -> Signal<DkxAnalyticsSource, NoError> {
    func page(_ state: SearchMessagesState?, _ collected: [Message], _ known: Set<MessageId>) -> Signal<DkxAnalyticsSource, NoError> {
        return context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: minDate, maxDate: nil), query: "", state: state, limit: 100)
        |> take(1)
        |> mapToSignal { result, nextState -> Signal<DkxAnalyticsSource, NoError> in
            var all = collected
            var knownIds = known
            var added = 0
            for message in result.messages where !knownIds.contains(message.id) {
                knownIds.insert(message.id)
                all.append(message)
                added += 1
            }
            progress(all.count)
            let oldest = all.map { $0.timestamp }.min()
            if all.count >= cap {
                return .single(DkxAnalyticsSource(messages: all, capped: true, oldestDate: oldest))
            }
            if result.completed || added == 0 {
                return .single(DkxAnalyticsSource(messages: all, capped: false, oldestDate: oldest))
            }
            return page(nextState, all, knownIds)
        }
    }
    return page(nil, [], Set())
}

struct DkxAnalyticsRaw {
    let posts: [DkxPost]
    let isChannel: Bool
    let members: Int?
    let capped: Bool
    let oldestDate: Int32?
    let loadedFrom: Int32
    let admin: DkxAdminStats?
}

func dkxLoadAnalytics(context: AccountContext, peerId: EnginePeer.Id, periodDays: Int, now: Int32, progress: @escaping (Int) -> Void) -> Signal<DkxAnalyticsRaw, NoError> {
    let loadDays = periodDays <= dkxAnalyticsCompareMaxDays ? periodDays * 2 : periodDays
    let minDate = now - Int32(loadDays) * 86400
    return context.engine.data.get(
        TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
        TelegramEngine.EngineData.Item.Peer.ParticipantCount(id: peerId)
    )
    |> mapToSignal { peer, members -> Signal<DkxAnalyticsRaw, NoError> in
        var isChannel = false
        if let peer, case let .channel(channel) = peer, case .broadcast = channel.info {
            isChannel = true
        }
        return combineLatest(
            dkxLoadHistory(context: context, peerId: peerId, minDate: minDate, cap: dkxAnalyticsMessageCap, progress: progress),
            dkxLoadAdminStats(context: context, peerId: peerId, isChannel: isChannel)
        )
        |> take(1)
        |> deliverOn(Queue.concurrentDefaultQueue())
        |> map { source, admin -> DkxAnalyticsRaw in
            return DkxAnalyticsRaw(posts: dkxMakePosts(source.messages), isChannel: isChannel, members: members, capped: source.capped, oldestDate: source.oldestDate, loadedFrom: minDate, admin: admin)
        }
    }
}

func dkxReport(_ raw: DkxAnalyticsRaw, periodDays: Int, now: Int32) -> DkxAnalyticsReport {
    let periodStart = now - Int32(periodDays) * 86400
    let previousStart = periodStart - Int32(periodDays) * 86400
    let currentCapped = raw.capped && (raw.oldestDate ?? now) > periodStart
    let previousComplete = raw.loadedFrom <= previousStart && (!raw.capped || (raw.oldestDate ?? now) <= previousStart)
    return dkxBuildReport(allPosts: raw.posts, isChannel: raw.isChannel, members: raw.members, periodDays: periodDays, now: now, capped: currentCapped, previousComplete: previousComplete, admin: raw.admin)
}
