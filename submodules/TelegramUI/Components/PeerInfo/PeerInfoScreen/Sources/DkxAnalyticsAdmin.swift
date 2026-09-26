import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramUIPreferences

struct DkxAdminValue: Equatable {
    let label: String
    let current: Double
    let previous: Double
    let isRate: Bool
}

struct DkxAdminPerson: Equatable {
    let name: String
    let values: [Int]
}

// То, что Telegram отдаёт только админу со статистикой. Период у Telegram свой
struct DkxAdminStats: Equatable {
    var isChannel: Bool
    var periodStart: Int32
    var periodEnd: Int32
    var values: [DkxAdminValue] = []
    var notificationsPercent: Double?
    var growth: [DkxGrowthDay] = []
    var hours: [Double]?
    var viewsBySource: [DkxNamedCount] = []
    var followersBySource: [DkxNamedCount] = []
    var languages: [DkxNamedCount] = []
    var dailyViews: [Double] = []
    var dailyViewsStart: Int32 = 0
    var topPosters: [DkxAdminPerson] = []
    var topAdmins: [DkxAdminPerson] = []
    var topInviters: [DkxAdminPerson] = []
}

private func dkxSourceName(_ name: String) -> String {
    switch name.lowercased() {
    case "followers":
        return DkxStrings.tr("Подписчики")
    case "channels":
        return DkxStrings.tr("Другие каналы")
    case "groups":
        return DkxStrings.tr("Группы")
    case "pm", "private chats":
        return DkxStrings.tr("Личные сообщения")
    case "url", "links":
        return DkxStrings.tr("Ссылки")
    case "search":
        return DkxStrings.tr("Поиск")
    case "other":
        return DkxStrings.tr("Другое")
    case "similar channels":
        return DkxStrings.tr("Похожие каналы")
    case "ads":
        return DkxStrings.tr("Реклама Telegram")
    default:
        return name
    }
}

// Сумма каждой линии графика за весь его отрезок
func dkxGraphSums(_ graph: StatsGraph, localize: Bool) -> [DkxNamedCount] {
    guard let parsed = dkxParseStatsGraph(graph) else {
        return []
    }
    var result: [DkxNamedCount] = []
    for series in parsed.series {
        let sum = series.values.reduce(0.0) { $0 + max(0.0, $1) }
        if sum > 0.0 {
            result.append(DkxNamedCount(name: localize ? dkxSourceName(series.name) : series.name, count: Int(sum.rounded())))
        }
    }
    return result.sorted(by: { lhs, rhs in
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        return lhs.name < rhs.name
    })
}

private func dkxGraphPending(_ graph: StatsGraph) -> Bool {
    if case .OnDemand = graph {
        return true
    }
    return false
}

private func dkxAdminFromChannel(_ stats: ChannelStats) -> DkxAdminStats {
    var result = DkxAdminStats(isChannel: true, periodStart: stats.period.minDate, periodEnd: stats.period.maxDate)
    result.values = [
        DkxAdminValue(label: DkxStrings.tr("Подписчики"), current: stats.followers.current, previous: stats.followers.previous, isRate: false),
        DkxAdminValue(label: DkxStrings.tr("Просмотры на пост"), current: stats.viewsPerPost.current, previous: stats.viewsPerPost.previous, isRate: false),
        DkxAdminValue(label: DkxStrings.tr("Репосты на пост"), current: stats.sharesPerPost.current, previous: stats.sharesPerPost.previous, isRate: true),
        DkxAdminValue(label: DkxStrings.tr("Реакции на пост"), current: stats.reactionsPerPost.current, previous: stats.reactionsPerPost.previous, isRate: true)
    ]
    if stats.viewsPerStory.current > 0.0 || stats.viewsPerStory.previous > 0.0 {
        result.values.append(DkxAdminValue(label: DkxStrings.tr("Просмотры на историю"), current: stats.viewsPerStory.current, previous: stats.viewsPerStory.previous, isRate: false))
    }
    if stats.enabledNotifications.total > 0.0 {
        result.notificationsPercent = stats.enabledNotifications.value / stats.enabledNotifications.total * 100.0
    }
    result.growth = dkxGrowthDays(stats.followersGraph)
    result.hours = dkxReadingHours(stats.topHoursGraph, secondsFromGMT: TimeZone.current.secondsFromGMT())
    result.viewsBySource = dkxGraphSums(stats.viewsBySourceGraph, localize: true)
    result.followersBySource = dkxGraphSums(stats.newFollowersBySourceGraph, localize: true)
    result.languages = dkxGraphSums(stats.languagesGraph, localize: false)
    if let parsed = dkxParseStatsGraph(stats.interactionsGraph), let views = parsed.series.first, let firstX = parsed.x.first, parsed.x.count > 1, abs(parsed.x[1] - parsed.x[0] - 86400000.0) < 3600000.0 {
        result.dailyViews = views.values
        result.dailyViewsStart = Int32(clamping: Int64(firstX / 1000.0))
    }
    return result
}

private func dkxAdminFromGroup(_ stats: GroupStats, names: [EnginePeer.Id: String]) -> DkxAdminStats {
    var result = DkxAdminStats(isChannel: false, periodStart: stats.period.minDate, periodEnd: stats.period.maxDate)
    result.values = [
        DkxAdminValue(label: DkxStrings.tr("Участники"), current: stats.members.current, previous: stats.members.previous, isRate: false),
        DkxAdminValue(label: DkxStrings.tr("Сообщения"), current: stats.messages.current, previous: stats.messages.previous, isRate: false),
        DkxAdminValue(label: DkxStrings.tr("Читали"), current: stats.viewers.current, previous: stats.viewers.previous, isRate: false),
        DkxAdminValue(label: DkxStrings.tr("Писали"), current: stats.posters.current, previous: stats.posters.previous, isRate: false)
    ]
    result.growth = dkxGrowthDays(stats.membersGraph)
    result.hours = dkxReadingHours(stats.topHoursGraph, secondsFromGMT: TimeZone.current.secondsFromGMT())
    result.followersBySource = dkxGraphSums(stats.newMembersBySourceGraph, localize: true)
    result.languages = dkxGraphSums(stats.languagesGraph, localize: false)
    func name(_ id: EnginePeer.Id) -> String {
        return names[id] ?? "id \(id.id._internalGetInt64Value())"
    }
    result.topPosters = stats.topPosters.map { DkxAdminPerson(name: name($0.peerId), values: [Int($0.messageCount), Int($0.averageChars)]) }
    result.topAdmins = stats.topAdmins.map { DkxAdminPerson(name: name($0.peerId), values: [Int($0.deletedCount), Int($0.kickedCount), Int($0.bannedCount)]) }
    result.topInviters = stats.topInviters.map { DkxAdminPerson(name: name($0.peerId), values: [Int($0.inviteCount)]) }
    return result
}

// Ждём догрузки графиков, но не дольше 15 секунд. Что не успело, пропускаем
private func dkxWaitStats<T>(state: Signal<T?, NoError>, request: @escaping () -> Void, pending: @escaping (T) -> Bool, keepAlive: AnyObject) -> Signal<T?, NoError> {
    return Signal<T?, NoError> { subscriber in
        var latest: T?
        var requested = false
        var finished = false
        let finish: () -> Void = {
            if finished {
                return
            }
            finished = true
            subscriber.putNext(latest)
            subscriber.putCompletion()
        }
        let timer = SwiftSignalKit.Timer(timeout: 15.0, repeat: false, completion: {
            finish()
        }, queue: Queue.mainQueue())
        timer.start()
        let disposable = (state
        |> deliverOnMainQueue).start(next: { value in
            guard let value else {
                return
            }
            latest = value
            if !requested {
                requested = true
                request()
            }
            if !pending(value) {
                finish()
            }
        })
        return ActionDisposable {
            timer.invalidate()
            disposable.dispose()
            let _ = keepAlive
        }
    }
    |> runOn(Queue.mainQueue())
}

func dkxLoadAdminStats(context: AccountContext, peerId: EnginePeer.Id, isChannel: Bool) -> Signal<DkxAdminStats?, NoError> {
    return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.CanViewStats(id: peerId))
    |> mapToSignal { canViewStats -> Signal<DkxAdminStats?, NoError> in
        guard canViewStats else {
            return .single(nil)
        }
        if isChannel {
            return Signal<ChannelStatsContext, NoError> { subscriber in
                subscriber.putNext(ChannelStatsContext(postbox: context.account.postbox, network: context.account.network, peerId: peerId))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(Queue.mainQueue())
            |> mapToSignal { statsContext -> Signal<DkxAdminStats?, NoError> in
                return dkxWaitStats(state: statsContext.state |> map { $0.stats }, request: {
                    statsContext.loadFollowersGraph()
                    statsContext.loadTopHoursGraph()
                    statsContext.loadViewsBySourceGraph()
                    statsContext.loadNewFollowersBySourceGraph()
                    statsContext.loadLanguagesGraph()
                    statsContext.loadInteractionsGraph()
                }, pending: { stats in
                    return [stats.followersGraph, stats.topHoursGraph, stats.viewsBySourceGraph, stats.newFollowersBySourceGraph, stats.languagesGraph, stats.interactionsGraph].contains(where: dkxGraphPending)
                }, keepAlive: statsContext)
                |> map { stats -> DkxAdminStats? in
                    return stats.map(dkxAdminFromChannel)
                }
            }
        } else {
            return Signal<GroupStatsContext, NoError> { subscriber in
                subscriber.putNext(GroupStatsContext(postbox: context.account.postbox, network: context.account.network, accountPeerId: context.account.peerId, peerId: peerId))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(Queue.mainQueue())
            |> mapToSignal { statsContext -> Signal<DkxAdminStats?, NoError> in
                return dkxWaitStats(state: statsContext.state |> map { $0.stats }, request: {
                    statsContext.loadMembersGraph()
                    statsContext.loadNewMembersBySourceGraph()
                    statsContext.loadLanguagesGraph()
                    statsContext.loadTopHoursGraph()
                }, pending: { stats in
                    return [stats.membersGraph, stats.newMembersBySourceGraph, stats.languagesGraph, stats.topHoursGraph].contains(where: dkxGraphPending)
                }, keepAlive: statsContext)
                |> mapToSignal { stats -> Signal<DkxAdminStats?, NoError> in
                    guard let stats else {
                        return .single(nil)
                    }
                    let ids = Array(Set(stats.topPosters.map { $0.peerId } + stats.topAdmins.map { $0.peerId } + stats.topInviters.map { $0.peerId }))
                    return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
                    |> map { peers -> DkxAdminStats? in
                        var names: [EnginePeer.Id: String] = [:]
                        for (id, peer) in peers {
                            if let peer {
                                names[id] = peer.compactDisplayTitle
                            }
                        }
                        return dkxAdminFromGroup(stats, names: names)
                    }
                }
            }
        }
    }
}
