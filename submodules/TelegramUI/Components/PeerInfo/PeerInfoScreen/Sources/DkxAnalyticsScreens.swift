import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import TelegramUIPreferences
import StatisticsUI

func dkxAnalyticsItem(id: AnyHashable, peerId: EnginePeer.Id, context: AccountContext, interaction: PeerInfoInteraction) -> PeerInfoScreenItem {
    return PeerInfoScreenActionItem(id: id, text: DkxStrings.tr("Аналитика"), action: { [weak interaction] in
        guard let controller = interaction?.getController() else {
            return
        }
        controller.push(DkxAnalyticsController(context: context, peerId: peerId))
    })
}

private func dkxAnKindColor(_ kind: DkxPostKind) -> UIColor {
    switch kind {
    case .text:
        return UIColor(rgb: 0x3e88f7)
    case .photo:
        return UIColor(rgb: 0x34c759)
    case .video:
        return UIColor(rgb: 0xaf52de)
    case .album:
        return UIColor(rgb: 0x5ac8fa)
    case .voice, .round:
        return UIColor(rgb: 0xff9f0a)
    case .poll:
        return UIColor(rgb: 0xf7a23e)
    case .link:
        return UIColor(rgb: 0x0a84ff)
    case .sticker:
        return UIColor(rgb: 0xffcc00)
    case .location:
        return UIColor(rgb: 0xff453a)
    case .file, .other:
        return UIColor(rgb: 0x8e8e93)
    }
}

private func dkxAnKindIcon(_ kind: DkxPostKind) -> String {
    switch kind {
    case .text:
        return "text.alignleft"
    case .photo:
        return "photo"
    case .video:
        return "video"
    case .album:
        return "square.grid.2x2"
    case .voice:
        return "waveform"
    case .round:
        return "video.circle"
    case .file:
        return "doc"
    case .poll:
        return "chart.bar"
    case .link:
        return "link"
    case .sticker:
        return "face.smiling"
    case .location:
        return "mappin"
    case .other:
        return "ellipsis"
    }
}

private func dkxAnCover(_ color: UIColor, icon: String?, size: CGFloat) -> UIView {
    let cover = UIView()
    cover.isUserInteractionEnabled = false
    cover.backgroundColor = color
    cover.layer.cornerRadius = 12.0
    cover.layer.cornerCurve = .continuous
    if let icon {
        let iconView = dkxAnSymbol(icon, size: 18.0, weight: .medium, color: .white)
        iconView.frame = CGRect(x: 0.0, y: 0.0, width: size, height: size)
        cover.addSubview(iconView)
    }
    return cover
}

private func dkxAnWindowText(_ from: Int, _ to: Int) -> String {
    return dkxAnHour(from) + "\u{2013}" + dkxAnHour(to)
}

private func dkxAnImpactText(_ impact: DkxPostImpact) -> String {
    return "+" + dkxAnNumber(Int(impact.joined.rounded())) + " / " + dkxAnMinus + dkxAnNumber(Int(impact.left.rounded()))
}

private func dkxAnPeriodTitle(_ days: Int) -> String {
    return dkxAnalyticsPeriods.first(where: { $0.days == days })?.title ?? DkxStrings.plural(days, "{} день", "{} дня", "{} дней")
}

private func dkxAnChevron(_ colors: DkxAnalyticsColors) -> UIImageView {
    return dkxAnSymbol("chevron.right", size: 13.0, weight: .semibold, color: colors.chevron)
}

private func dkxAnMaxNet(_ report: DkxAnalyticsReport) -> Double {
    return report.impacts.values.map { abs($0.net) }.max() ?? 0.0
}

// Номер места, 1 это лучший
private func dkxAnPlaceText(_ place: Int) -> String {
    return DkxStrings.tr("{}-й", place)
}

final class DkxAnalyticsController: DkxAnalyticsBaseController {
    private let peerId: EnginePeer.Id
    private var peer: EnginePeer?
    private var periodIndex = dkxAnalyticsDefaultPeriod
    private var raw: DkxAnalyticsRaw?
    private var rawNow: Int32 = 0
    private var report: DkxAnalyticsReport?
    private var loading = true
    private var loadedCount = 0
    private let loadDisposable = MetaDisposable()
    private var peerDisposable: Disposable?
    private weak var progressLabel: UILabel?

    init(context: AccountContext, peerId: EnginePeer.Id) {
        self.peerId = peerId
        super.init(context: context, title: DkxStrings.tr("Аналитика"))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "icloud.and.arrow.up"), style: .plain, target: self, action: #selector(self.exportPressed))
        self.peerDisposable = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self else {
                return
            }
            self.peer = peer
            self.reload()
        })
        self.load()
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.loadDisposable.dispose()
        self.peerDisposable?.dispose()
    }

    private func load() {
        let days = dkxAnalyticsPeriods[self.periodIndex].days
        let needDays = days <= dkxAnalyticsCompareMaxDays ? days * 2 : days
        // Упёрлись в предел сообщений, новая загрузка даст то же самое
        if let raw = self.raw, raw.capped || raw.loadedFrom <= self.rawNow - Int32(needDays) * 86400 {
            let now = self.rawNow
            self.loadDisposable.set((Signal<DkxAnalyticsReport, NoError> { subscriber in
                subscriber.putNext(dkxReport(raw, periodDays: days, now: now))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(Queue.concurrentDefaultQueue())
            |> deliverOnMainQueue).start(next: { [weak self] report in
                guard let self else {
                    return
                }
                self.report = report
                self.loading = false
                self.reload()
            }))
            return
        }
        let now = Int32(Date().timeIntervalSince1970)
        self.loading = true
        self.loadedCount = 0
        self.report = nil
        self.reload()
        self.loadDisposable.set((dkxLoadAnalytics(context: self.context, peerId: self.peerId, periodDays: days, now: now, progress: { [weak self] count in
            Queue.mainQueue().async {
                self?.updateProgress(count)
            }
        })
        |> map { raw -> (DkxAnalyticsRaw, DkxAnalyticsReport) in
            return (raw, dkxReport(raw, periodDays: days, now: now))
        }
        |> deliverOnMainQueue).start(next: { [weak self] raw, report in
            guard let self else {
                return
            }
            self.raw = raw
            self.rawNow = now
            self.report = report
            self.loading = false
            self.reload()
        }))
    }

    private func updateProgress(_ count: Int) {
        self.loadedCount = count
        self.progressLabel?.text = DkxStrings.tr("Загружено сообщений {}", dkxAnNumber(count))
    }

    @objc private func exportPressed() {
        self.export()
    }

    private func export() {
        guard let report = self.report, !report.posts.isEmpty else {
            self.showToast(DkxStrings.tr("Нет данных для выгрузки"))
            return
        }
        dkxAnalyticsExport(context: self.context, report: report, peer: self.peer, periodTitle: dkxAnalyticsPeriods[self.periodIndex].title, controller: self)
    }

    private var peerTitle: String {
        return self.peer?.displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder) ?? ""
    }

    override func buildContent(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        var y = self.buildHeader(x: x, top: top, width: width) + 14.0
        y = self.addChoices(dkxAnalyticsPeriods.map { $0.title }, selected: self.periodIndex, x: x, top: y, width: width, action: { [weak self] index in
            guard let self, index != self.periodIndex else {
                return
            }
            self.periodIndex = index
            self.load()
        }) + 14.0

        guard !self.loading, let report = self.report else {
            return self.buildLoading(x: x, top: y, width: width)
        }
        if report.posts.isEmpty {
            return self.addCard(x: x, top: y, width: width, title: nil, content: { card, inner, top, innerWidth in
                let label = dkxAnLabel(DkxStrings.tr("За этот период сообщений нет"), size: 15.0, color: self.colors.secondary, lines: 0, alignment: .center)
                return top + dkxAnPlace(label, in: card, x: inner, y: top + 16.0, width: innerWidth) + 16.0
            })
        }
        if report.capped {
            y = self.addFootnote(DkxStrings.tr("Загружены последние {} сообщений, более ранние в расчёт не вошли", dkxAnNumber(dkxAnalyticsMessageCap)), x: x, top: y, width: width) + 14.0
        }
        let channelMode = report.isChannel && report.hasViews
        y = self.buildTiles(report, channelMode: channelMode, x: x, top: y, width: width) + 14.0
        y = self.buildChart(report, channelMode: channelMode, x: x, top: y, width: width) + 14.0
        y = self.buildHeat(report, channelMode: channelMode, x: x, top: y, width: width) + 14.0
        if channelMode {
            y = self.buildBestTime(report, x: x, top: y, width: width) + 14.0
        }
        y = self.buildKinds(report, channelMode: channelMode, x: x, top: y, width: width) + 14.0
        if channelMode {
            y = self.buildImpact(report, x: x, top: y, width: width)
        } else {
            y = self.buildActive(report, x: x, top: y, width: width)
        }
        if !report.reactions.isEmpty {
            y = self.buildReactions(report.reactions, x: x, top: y, width: width) + 14.0
        }
        y = self.buildSourcesAndDomains(report, x: x, top: y, width: width)
        if let admin = report.admin {
            y = self.buildAdmin(admin, x: x, top: y, width: width)
        }
        let advice = self.makeButton(DkxStrings.tr("Совет ИИ"), width: width, height: 52.0, filled: false, fontSize: 17.0, icon: "sparkles", action: { [weak self] in
            self?.openAdvice()
        })
        advice.frame.origin = CGPoint(x: x, y: y)
        self.add(advice)
        y += 52.0 + 10.0
        let button = self.makeButton(DkxStrings.tr("Выгрузить в Google Drive"), width: width, height: 52.0, filled: true, fontSize: 17.0, icon: "square.and.arrow.up", action: { [weak self] in
            self?.export()
        })
        button.frame.origin = CGPoint(x: x, y: y)
        self.add(button)
        y += 52.0 + 14.0
        y = self.addFootnote(DkxStrings.tr("Таблица .xlsx для Google Таблиц."), x: x, top: y, width: width, size: 13.0, center: true)
        return y + 8.0
    }

    private func buildHeader(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let avatarSize: CGFloat = 52.0
        let avatar = UIView()
        avatar.backgroundColor = self.colors.accent
        avatar.layer.cornerRadius = avatarSize / 2.0
        avatar.frame = CGRect(x: x, y: top, width: avatarSize, height: avatarSize)
        let letter = dkxAnLabel(String(self.peerTitle.prefix(1)).uppercased(), size: 22.0, weight: .bold, color: .white, alignment: .center)
        letter.frame = avatar.bounds
        avatar.addSubview(letter)
        self.add(avatar)

        let textX = x + avatarSize + 12.0
        let textWidth = width - avatarSize - 12.0
        let title = dkxAnLabel(self.peerTitle, size: 20.0, weight: .bold, color: self.colors.primary)
        title.frame = CGRect(x: textX, y: top + 3.0, width: textWidth, height: 25.0)
        self.add(title)

        var parts: [String] = []
        if let username = self.peer?.addressName, !username.isEmpty {
            parts.append("@" + username)
        }
        if let members = self.report?.members ?? self.raw?.members {
            var isChannel = false
            if let peer = self.peer, case let .channel(channel) = peer, case .broadcast = channel.info {
                isChannel = true
            }
            if isChannel {
                parts.append(dkxAnNumber(members) + " " + DkxStrings.plural(members, "подписчик", "подписчика", "подписчиков"))
            } else {
                parts.append(dkxAnNumber(members) + " " + DkxStrings.plural(members, "участник", "участника", "участников"))
            }
        }
        let subtitle = dkxAnLabel(parts.joined(separator: " \u{00B7} "), size: 14.0, color: self.colors.secondary)
        subtitle.frame = CGRect(x: textX, y: top + 30.0, width: textWidth, height: 18.0)
        self.add(subtitle)
        return top + avatarSize
    }

    private func buildLoading(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        return self.addCard(x: x, top: top, width: width, title: nil, content: { card, inner, top, innerWidth in
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = self.colors.secondary
            indicator.frame = CGRect(x: inner + (innerWidth - 30.0) / 2.0, y: top + 14.0, width: 30.0, height: 30.0)
            indicator.startAnimating()
            card.addSubview(indicator)
            var y = top + 56.0
            let progress = dkxAnLabel(DkxStrings.tr("Загружено сообщений {}", dkxAnNumber(self.loadedCount)), size: 15.0, color: self.colors.primary, alignment: .center)
            y += dkxAnPlace(progress, in: card, x: inner, y: y, width: innerWidth) + 6.0
            self.progressLabel = progress
            let hint = dkxAnLabel(DkxStrings.tr("Для больших каналов и длинных периодов загрузка занимает до пары минут"), size: 13.0, color: self.colors.secondary, lines: 0, alignment: .center)
            y += dkxAnPlace(hint, in: card, x: inner, y: y, width: innerWidth)
            return y
        })
    }

    private func buildTiles(_ report: DkxAnalyticsReport, channelMode: Bool, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        var tiles: [DkxAnTile] = []
        let active = report.chart.filter { $0.bucket.posts > 0 }
        func tone(_ value: Double) -> UIColor {
            return value >= 0.0 ? self.colors.green : self.colors.red
        }
        let membersText = report.members.map { dkxAnNumber($0) } ?? "\u{2014}"
        if channelMode {
            var subsNote: String?
            var subsColor: UIColor?
            var subsSpark: [Double]?
            if let growth = report.growth {
                subsNote = dkxAnSignedNumber(growth.net)
                subsColor = tone(Double(growth.net))
                var running = 0.0
                subsSpark = report.growthDays.map { day in
                    running += Double(day.joined - day.left)
                    return running
                }
            }
            tiles.append((DkxStrings.tr("Подписчики"), membersText, nil, subsNote, subsColor, subsSpark, self.colors.green))

            var viewsNote: String?
            var viewsColor: UIColor?
            if let previous = report.previous, previous.avgViews > 0.0 {
                let change = (report.avgViews / previous.avgViews - 1.0) * 100.0
                viewsNote = dkxAnSignedPercent(change)
                viewsColor = tone(change)
            }
            let viewsSpark = active.map { $0.bucket.avgViews }
            tiles.append((DkxStrings.tr("Просмотры на пост"), dkxAnNumber(Int(report.avgViews.rounded())), nil, viewsNote, viewsColor, viewsSpark, self.colors.accent))

            var errNote: String?
            var errColor: UIColor?
            if let err = report.err, let previousErr = report.previous?.err {
                errNote = dkxAnSignedPercent(err - previousErr, digits: 1)
                errColor = tone(err - previousErr)
            }
            let errText: String = report.err.map { dkxAnPercent($0) } ?? "\u{2014}"
            tiles.append(("ERR", errText, nil, errNote, errColor, viewsSpark, self.colors.red))

            var erNote: String?
            var erColor: UIColor?
            if let engagement = report.engagement, let previousEngagement = report.previous?.engagement {
                erNote = dkxAnSignedPercent(engagement - previousEngagement, digits: 1)
                erColor = tone(engagement - previousEngagement)
            }
            let erText: String = report.engagement.map { dkxAnPercent($0) } ?? "\u{2014}"
            let erSpark: [Double] = active.compactMap { $0.bucket.engagement }
            tiles.append((DkxStrings.tr("Вовлечённость"), erText, nil, erNote, erColor, erSpark, self.colors.orange))
        } else {
            var membersNote: String?
            var membersColor: UIColor?
            if let growth = report.growth {
                membersNote = dkxAnSignedNumber(growth.net)
                membersColor = tone(Double(growth.net))
            }
            tiles.append((report.isChannel ? DkxStrings.tr("Подписчики") : DkxStrings.tr("Участники"), membersText, nil, membersNote, membersColor, nil, nil))
            var postsNote: String?
            var postsColor: UIColor?
            if let previous = report.previous, previous.posts > 0 {
                let change = (Double(report.posts.count) / Double(previous.posts) - 1.0) * 100.0
                postsNote = dkxAnSignedPercent(change)
                postsColor = tone(change)
            }
            let postsSpark: [Double] = report.chart.map { Double($0.bucket.posts) }
            tiles.append((DkxStrings.tr("Сообщения"), dkxAnNumber(report.posts.count), nil, postsNote, postsColor, postsSpark, self.colors.accent))
            tiles.append((DkxStrings.tr("Сообщений в день"), dkxAnDecimal(report.postsPerDay), nil, nil, nil, nil, nil))
            tiles.append((DkxStrings.tr("Писали"), dkxAnNumber(report.activeAuthors), nil, nil, nil, nil, nil))
        }
        return self.addTiles(tiles, columns: 2, x: x, top: top, width: width, compact: false)
    }

    private func buildChart(_ report: DkxAnalyticsReport, channelMode: Bool, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let range = dkxAnDate(report.periodStart, template: "dMMM") + " \u{2014} " + dkxAnDate(report.periodEnd, template: "dMMM")
        let values = channelMode ? report.viewsSeries : report.chart.map { Double($0.bucket.posts) }
        return self.addCard(x: x, top: top, width: width, title: channelMode ? DkxStrings.tr("Просмотры") : DkxStrings.tr("Сообщения"), accessory: range, content: { card, inner, top, innerWidth in
            let chart = DkxAnLineChartView(color: self.colors.accent, guide: self.colors.secondary, background: self.colors.card)
            chart.values = values
            chart.frame = CGRect(x: inner, y: top, width: innerWidth, height: 180.0)
            card.addSubview(chart)
            let y = top + 190.0
            let peak = Int((values.max() ?? 0.0).rounded())
            let average = values.isEmpty ? 0.0 : values.reduce(0.0, +) / Double(values.count)
            let left = dkxAnLabel(DkxStrings.tr("Пик {}", dkxAnNumber(peak)), size: 13.0, color: self.colors.secondary)
            left.frame = CGRect(x: inner, y: y, width: innerWidth / 2.0, height: 17.0)
            card.addSubview(left)
            let right = dkxAnLabel(DkxStrings.tr("Среднее {}", dkxAnNumber(Int(average.rounded()))), size: 13.0, color: self.colors.secondary, alignment: .right)
            right.frame = CGRect(x: inner + innerWidth / 2.0, y: y, width: innerWidth / 2.0, height: 17.0)
            card.addSubview(right)
            return y + 17.0
        })
    }

    private func addHourAxis(to card: UIView, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let marks = ["0", "6", "12", "18", "23"]
        for (index, mark) in marks.enumerated() {
            let alignment: NSTextAlignment = index == 0 ? .left : (index == marks.count - 1 ? .right : .center)
            let label = dkxAnLabel(mark, size: 11.0, color: self.colors.secondary, alignment: alignment)
            let slot = width / CGFloat(marks.count - 1)
            let center = x + CGFloat(index) * slot
            switch alignment {
            case .left:
                label.frame = CGRect(x: center, y: y, width: 24.0, height: 14.0)
            case .right:
                label.frame = CGRect(x: center - 24.0, y: y, width: 24.0, height: 14.0)
            default:
                label.frame = CGRect(x: center - 12.0, y: y, width: 24.0, height: 14.0)
            }
            card.addSubview(label)
        }
        return y + 14.0
    }

    private func buildHeat(_ report: DkxAnalyticsReport, channelMode: Bool, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        var values: [[Double?]] = []
        var best: (day: Int, hour: Int, value: Double)?
        for (day, row) in report.heat.enumerated() {
            var rowValues: [Double?] = []
            for (hour, bucket) in row.enumerated() {
                let value: Double?
                if channelMode {
                    value = bucket.maturePosts > 0 ? bucket.matureAvgViews : nil
                    if bucket.maturePosts >= 2, let value, value > (best?.value ?? -1.0) {
                        best = (day, hour, value)
                    }
                } else {
                    value = bucket.posts > 0 ? Double(bucket.posts) : nil
                    if let value, value > (best?.value ?? -1.0) {
                        best = (day, hour, value)
                    }
                }
                rowValues.append(value)
            }
            values.append(rowValues)
        }
        let accessory = best.map { DkxStrings.tr("лучше всего {} {}", dkxAnWeekdayShort($0.day).lowercased(with: DkxStrings.locale), dkxAnHour($0.hour)) }
        return self.addCard(x: x, top: top, width: width, title: channelMode ? DkxStrings.tr("Когда читают") : DkxStrings.tr("Когда пишут"), accessory: accessory, content: { card, inner, top, innerWidth in
            let heat = DkxAnHeatmapView(colors: self.colors)
            heat.values = values
            let height = 7.0 * DkxAnHeatmapView.rowHeight + 6.0 * DkxAnHeatmapView.gap
            heat.frame = CGRect(x: inner, y: top, width: innerWidth, height: height)
            card.addSubview(heat)
            return self.addHourAxis(to: card, x: inner + DkxAnHeatmapView.labelWidth, y: top + height + 10.0, width: innerWidth - DkxAnHeatmapView.labelWidth)
        })
    }

    private func buildBestTime(_ report: DkxAnalyticsReport, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        return self.addCard(x: x, top: top, width: width, title: nil, content: { card, inner, top, innerWidth in
            let circle = UIView()
            circle.backgroundColor = self.colors.green.withAlphaComponent(0.16)
            circle.layer.cornerRadius = 18.0
            circle.frame = CGRect(x: inner, y: top, width: 36.0, height: 36.0)
            let icon = dkxAnSymbol("clock", size: 17.0, color: self.colors.green)
            icon.frame = circle.bounds
            circle.addSubview(icon)
            card.addSubview(circle)
            let title = dkxAnLabel(DkxStrings.tr("Лучшее время публикации"), size: 17.0, weight: .semibold, color: self.colors.primary)
            title.frame = CGRect(x: inner + 46.0, y: top, width: innerWidth - 46.0, height: 36.0)
            card.addSubview(title)
            var y = top + 46.0
            guard let best = report.bestTime else {
                let text = DkxStrings.tr("Мало данных для совета. Нужно от 20 постов старше 48 часов, сейчас {}.", dkxAnNumber(report.maturePostCount))
                return y + dkxAnPlace(dkxAnLabel(text, size: 14.0, color: self.colors.secondary, lines: 0), in: card, x: inner, y: y, width: innerWidth)
            }
            var main = dkxAnWindowText(best.fromHour, best.toHour)
            if !best.weekdays.isEmpty {
                let days = best.weekdays.map { dkxAnWeekdayShort($0).capitalized(with: DkxStrings.locale) }
                let daysText = days.count == 2 ? DkxStrings.tr("{} и {}", days[0], days[1]) : days.joined(separator: ", ")
                main = daysText + ", " + main
            }
            let mainLabel = dkxAnLabel(main, size: 24.0, weight: .bold, color: self.colors.primary, lines: 0)
            y += dkxAnPlace(mainLabel, in: card, x: inner, y: y, width: innerWidth) + 10.0
            let gain = DkxStrings.tr("в среднем {} просмотров к остальному времени", dkxAnSignedPercent(best.gainPercent))
            y += dkxAnPlace(dkxAnLabel(gain, size: 14.0, color: best.gainPercent >= 0.0 ? self.colors.green : self.colors.red, lines: 0), in: card, x: inner, y: y, width: innerWidth) + 10.0
            if !best.alternatives.isEmpty {
                var chipX = inner
                for alternative in best.alternatives {
                    let text = dkxAnWeekdayShort(alternative.weekday).capitalized(with: DkxStrings.locale) + " " + dkxAnHour(alternative.hour) + "  " + dkxAnSignedPercent(alternative.percent)
                    let label = dkxAnLabel(text, size: 13.0, color: self.colors.primary, alignment: .center)
                    let chipWidth = dkxAnTextWidth(label, limit: innerWidth) + 20.0
                    if chipX > inner && chipX + chipWidth > inner + innerWidth {
                        break
                    }
                    let chip = UIView()
                    chip.backgroundColor = self.colors.chip
                    chip.layer.cornerRadius = 12.0
                    chip.frame = CGRect(x: chipX, y: y, width: chipWidth, height: 28.0)
                    label.frame = chip.bounds
                    chip.addSubview(label)
                    card.addSubview(chip)
                    chipX += chipWidth + 8.0
                }
                y += 28.0 + 10.0
            }
            let worst = DkxStrings.tr("Хуже всего {}, в среднем {}. Считается по вашим постам за выбранный период, в расчёте постов старше 48 часов {}.", dkxAnWindowText(best.worstFromHour, best.worstToHour), dkxAnSignedPercent(best.worstPercent), dkxAnNumber(best.sampleSize))
            y += dkxAnPlace(dkxAnLabel(worst, size: 13.0, color: self.colors.secondary, lines: 0), in: card, x: inner, y: y, width: innerWidth)
            return y
        })
    }

    private func buildKinds(_ report: DkxAnalyticsReport, channelMode: Bool, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let rows = Array(report.kinds.prefix(6))
        func average(_ bucket: DkxBucket) -> Double {
            return bucket.maturePosts > 0 ? bucket.matureAvgViews : bucket.avgViews
        }
        let maxValue = rows.map { channelMode ? average($0.bucket) : Double($0.bucket.posts) }.max() ?? 1.0
        return self.addCard(x: x, top: top, width: width, title: channelMode ? DkxStrings.tr("Что заходит лучше") : DkxStrings.tr("Что пишут"), gap: 12.0, content: { card, inner, top, innerWidth in
            var y = top
            for row in rows {
                let name = dkxAnLabel(row.kind.title, size: 14.0, color: self.colors.primary)
                let nameWidth = dkxAnTextWidth(name, limit: innerWidth * 0.45)
                name.frame = CGRect(x: inner, y: y, width: nameWidth, height: 18.0)
                card.addSubview(name)
                let postsText = dkxAnNumber(row.bucket.posts) + " " + DkxStrings.plural(row.bucket.posts, "пост", "поста", "постов")
                let detailText = channelMode ? DkxStrings.tr("{} \u{00B7} {} в среднем", postsText, dkxAnNumber(Int(average(row.bucket).rounded()))) : postsText
                let detail = dkxAnLabel(detailText, size: 14.0, color: self.colors.secondary, alignment: .right)
                detail.frame = CGRect(x: inner + nameWidth + 8.0, y: y, width: innerWidth - nameWidth - 8.0, height: 18.0)
                card.addSubview(detail)
                y += 23.0
                let bar = DkxAnBarView(track: self.colors.track, color: self.colors.accent)
                let rowValue: Double = channelMode ? average(row.bucket) : Double(row.bucket.posts)
                bar.fraction = maxValue > 0.0 ? CGFloat(rowValue / maxValue) : 0.0
                bar.frame = CGRect(x: inner, y: y, width: innerWidth, height: 8.0)
                card.addSubview(bar)
                y += 8.0 + 12.0
            }
            return y - 12.0
        })
    }

    private func buildImpact(_ report: DkxAnalyticsReport, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let posts: [DkxPost]
        if !report.impacts.isEmpty {
            posts = report.posts.filter { report.impacts[$0.id] != nil }.sorted(by: { lhs, rhs in
                let left = report.impacts[lhs.id]?.net ?? 0.0
                let right = report.impacts[rhs.id]?.net ?? 0.0
                if left != right {
                    return left > right
                }
                return lhs.date > rhs.date
            })
        } else {
            posts = report.posts.filter { report.isMature($0) }.sorted(by: { $0.views != $1.views ? $0.views > $1.views : $0.date > $1.date })
        }
        let top3 = Array(posts.prefix(3))
        if top3.isEmpty {
            return top
        }
        let tints = [self.colors.accent, UIColor(rgb: 0x34c759), self.colors.orange]
        return self.addCard(x: x, top: top, width: width, title: DkxStrings.tr("Влияние постов"), gap: 14.0, accessory: DkxStrings.tr("Все посты"), accessoryAction: { [weak self] in
            self?.openPosts()
        }, content: { card, inner, top, innerWidth in
            var y = top
            for (index, post) in top3.enumerated() {
                let row = DkxAnTapView()
                row.action = { [weak self] in
                    self?.openPost(post)
                }
                row.frame = CGRect(x: 0.0, y: y - 4.0, width: innerWidth + inner * 2.0, height: 52.0)
                let cover = dkxAnCover(tints[index % tints.count], icon: dkxAnKindIcon(post.kind), size: 44.0)
                cover.frame = CGRect(x: inner, y: 4.0, width: 44.0, height: 44.0)
                row.addSubview(cover)
                let textX = inner + 56.0
                let textWidth = innerWidth - 56.0 - 20.0
                let text = dkxAnLabel(post.preview, size: 15.0, color: self.colors.primary)
                text.frame = CGRect(x: textX, y: 4.0, width: textWidth, height: 19.0)
                row.addSubview(text)
                var badgeX = textX
                if let ratio = report.ratio(post) {
                    let badge = dkxAnBadge(DkxStrings.tr("{} к среднему", dkxAnRatio(ratio)), color: ratio >= 1.0 ? self.colors.green : self.colors.red)
                    badge.frame.origin = CGPoint(x: badgeX, y: 28.0)
                    row.addSubview(badge)
                    badgeX += badge.frame.width + 6.0
                }
                if let impact = report.impacts[post.id] {
                    let badge = dkxAnBadge(dkxAnImpactText(impact), color: impact.net >= 0.0 ? self.colors.green : self.colors.red)
                    badge.frame.origin = CGPoint(x: badgeX, y: 28.0)
                    row.addSubview(badge)
                    badgeX += badge.frame.width + 6.0
                }
                if let engagement = post.engagement {
                    let er = dkxAnLabel("ER " + dkxAnPercent(engagement), size: 12.0, color: self.colors.secondary)
                    er.frame = CGRect(x: badgeX, y: 28.0, width: max(0.0, textX + textWidth - badgeX), height: 21.0)
                    row.addSubview(er)
                }
                let chevron = dkxAnChevron(self.colors)
                chevron.frame = CGRect(x: inner + innerWidth - 10.0, y: 4.0, width: 10.0, height: 44.0)
                row.addSubview(chevron)
                card.addSubview(row)
                y += 44.0 + 14.0
            }
            let note = report.impacts.isEmpty ? DkxStrings.tr("Подписки и отписки по постам видит только админ канала. Здесь посты с наибольшими просмотрами.") : DkxStrings.tr("Подписки и отписки это оценка по дню публикации. Telegram не привязывает их к посту.")
            y += dkxAnPlace(dkxAnLabel(note, size: 12.0, color: self.colors.secondary, lines: 0), in: card, x: inner, y: y, width: innerWidth)
            return y
        }) + 14.0
    }

    private func buildActive(_ report: DkxAnalyticsReport, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let rows = Array(report.authors.prefix(6))
        if rows.isEmpty {
            return top
        }
        let maxCount = Double(rows.first?.count ?? 1)
        return self.addCard(x: x, top: top, width: width, title: DkxStrings.tr("Самые активные"), gap: 12.0, accessory: DkxStrings.tr("Все сообщения"), accessoryAction: { [weak self] in
            self?.openPosts()
        }, content: { card, inner, top, innerWidth in
            var y = top
            for item in rows {
                y = self.addBarRow(to: card, x: inner, y: y, width: innerWidth, title: item.name, value: dkxAnNumber(item.count), fraction: CGFloat(Double(item.count) / max(1.0, maxCount)), color: self.colors.accent, titleWidth: min(130.0, innerWidth * 0.4), titleSize: 14.0) + 8.0
            }
            return y - 8.0
        }) + 14.0
    }

    private func openPosts() {
        guard let report = self.report else {
            return
        }
        self.push(DkxAnalyticsPostsController(context: self.context, report: report, peer: self.peer))
    }

    private func openAdvice() {
        guard let report = self.report else {
            return
        }
        self.push(DkxAnalyticsAdviceController(context: self.context, report: report, peer: self.peer, periodTitle: dkxAnalyticsPeriods[self.periodIndex].title))
    }

    private func openPost(_ post: DkxPost) {
        guard let report = self.report else {
            return
        }
        self.push(DkxAnalyticsPostController(context: self.context, report: report, post: post, peer: self.peer))
    }

    private func buildReactions(_ items: [DkxNamedCount], x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let rows = Array(items.prefix(5))
        let maxCount = Double(rows.first?.count ?? 1)
        let wide = rows.contains(where: { $0.name.count > 3 })
        return self.addCard(x: x, top: top, width: width, title: DkxStrings.tr("Реакции"), gap: 12.0, content: { card, inner, top, innerWidth in
            var y = top
            for item in rows {
                y = self.addBarRow(to: card, x: inner, y: y, width: innerWidth, title: item.name, value: dkxAnNumber(item.count), fraction: CGFloat(Double(item.count) / max(1.0, maxCount)), color: self.colors.orange, titleWidth: wide ? 110.0 : 26.0, titleSize: wide ? 14.0 : 20.0) + 6.0
            }
            return y - 6.0
        })
    }

    private func buildSmallList(_ items: [DkxNamedCount], title: String, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        return self.addCard(x: x, top: top, width: width, title: title, titleSize: 15.0, padding: 14.0, gap: 8.0, content: { card, inner, top, innerWidth in
            var y = top
            for item in items.prefix(3) {
                let label = dkxAnLabel(item.name + " \u{00B7} " + dkxAnNumber(item.count), size: 14.0, color: self.colors.primary)
                label.frame = CGRect(x: inner, y: y, width: innerWidth, height: 18.0)
                card.addSubview(label)
                y += 18.0 + 8.0
            }
            return y - 8.0
        })
    }

    private func buildSourcesAndDomains(_ report: DkxAnalyticsReport, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        var cards: [(String, [DkxNamedCount])] = []
        if !report.sources.isEmpty {
            cards.append((DkxStrings.tr("Откуда репосты"), report.sources))
        }
        if !report.domains.isEmpty {
            cards.append((DkxStrings.tr("Ссылки на сайты"), report.domains))
        }
        if cards.isEmpty {
            return top
        }
        let half = floor((width - 10.0) / 2.0)
        var bottom = top
        for (index, card) in cards.enumerated() {
            bottom = max(bottom, self.buildSmallList(card.1, title: card.0, x: x + CGFloat(index) * (half + 10.0), top: top, width: half))
        }
        return bottom + 14.0
    }

    // Блок только для админа. То, что Telegram считает сам, за свой период
    private func buildAdmin(_ admin: DkxAdminStats, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        var y = top
        let range = dkxAnDate(admin.periodStart, template: "dMMM") + " \u{2014} " + dkxAnDate(admin.periodEnd, template: "dMMM")
        y = self.addCard(x: x, top: y, width: width, title: DkxStrings.tr("Статистика Telegram"), gap: 12.0, accessory: range, content: { card, inner, top, innerWidth in
            var y = top
            var rows: [(String, String, String?, UIColor?)] = []
            for value in admin.values {
                let current = value.isRate ? dkxAnDecimal(value.current) : dkxAnNumber(Int(value.current.rounded()))
                var change: String?
                var color: UIColor?
                if value.previous > 0.0 {
                    let percent = (value.current / value.previous - 1.0) * 100.0
                    change = dkxAnSignedPercent(percent)
                    color = percent >= 0.0 ? self.colors.green : self.colors.red
                }
                rows.append((value.label, current, change, color))
            }
            if let notifications = admin.notificationsPercent {
                rows.append((DkxStrings.tr("Уведомления включены"), dkxAnPercent(notifications), nil, nil))
            }
            for row in rows {
                let label = dkxAnLabel(row.0, size: 15.0, color: self.colors.primary)
                label.frame = CGRect(x: inner, y: y, width: innerWidth * 0.55, height: 22.0)
                card.addSubview(label)
                var right = inner + innerWidth
                if let change = row.2, let color = row.3 {
                    let badge = dkxAnBadge(change, color: color)
                    badge.frame.origin = CGPoint(x: right - badge.frame.width, y: y + 0.5)
                    card.addSubview(badge)
                    right -= badge.frame.width + 8.0
                }
                let value = dkxAnLabel(row.1, size: 15.0, weight: .semibold, color: self.colors.primary, alignment: .right)
                value.frame = CGRect(x: inner + innerWidth * 0.55, y: y, width: right - inner - innerWidth * 0.55, height: 22.0)
                card.addSubview(value)
                y += 22.0 + 10.0
            }
            y += dkxAnPlace(dkxAnLabel(DkxStrings.tr("Изменение к предыдущему периоду Telegram."), size: 12.0, color: self.colors.secondary, lines: 0), in: card, x: inner, y: y, width: innerWidth)
            return y
        }) + 14.0

        func shares(_ items: [DkxNamedCount], title: String) {
            let rows = Array(items.prefix(6))
            let total = Double(max(1, items.reduce(0) { $0 + $1.count }))
            let maxCount = Double(rows.first?.count ?? 1)
            y = self.addCard(x: x, top: y, width: width, title: title, gap: 12.0, content: { card, inner, top, innerWidth in
                var y = top
                for item in rows {
                    y = self.addBarRow(to: card, x: inner, y: y, width: innerWidth, title: item.name, value: dkxAnPercent(Double(item.count) / total * 100.0), fraction: CGFloat(Double(item.count) / max(1.0, maxCount)), color: self.colors.accent, titleWidth: min(140.0, innerWidth * 0.42), titleSize: 14.0, valueWidth: 58.0) + 6.0
                }
                return y - 6.0
            }) + 14.0
        }
        if !admin.viewsBySource.isEmpty {
            shares(admin.viewsBySource, title: DkxStrings.tr("Откуда просмотры"))
        }
        if !admin.followersBySource.isEmpty {
            shares(admin.followersBySource, title: admin.isChannel ? DkxStrings.tr("Откуда подписчики") : DkxStrings.tr("Откуда участники"))
        }
        if !admin.languages.isEmpty {
            shares(admin.languages, title: DkxStrings.tr("Языки"))
        }
        if let hours = admin.hours {
            var bestFrom = 0
            var bestSum = -1.0
            for from in 0 ..< 24 {
                let sum = hours[from] + hours[(from + 1) % 24] + hours[(from + 2) % 24]
                if sum > bestSum {
                    bestSum = sum
                    bestFrom = from
                }
            }
            let title = admin.isChannel ? DkxStrings.tr("Просмотры по часам") : DkxStrings.tr("Активность по часам")
            y = self.addCard(x: x, top: y, width: width, title: title, gap: 12.0, accessory: dkxAnWindowText(bestFrom, (bestFrom + 3) % 24), content: { card, inner, top, innerWidth in
                let columns = DkxAnColumnsView(color: self.colors.accent.withAlphaComponent(0.35), highlight: self.colors.accent)
                columns.highlighted = Set([bestFrom, (bestFrom + 1) % 24, (bestFrom + 2) % 24])
                columns.values = hours
                columns.frame = CGRect(x: inner, y: top, width: innerWidth, height: 90.0)
                card.addSubview(columns)
                let y = self.addHourAxis(to: card, x: inner, y: top + 98.0, width: innerWidth) + 8.0
                return y + dkxAnPlace(dkxAnLabel(DkxStrings.tr("По времени телефона, все просмотры канала за период Telegram."), size: 12.0, color: self.colors.secondary, lines: 0), in: card, x: inner, y: y, width: innerWidth)
            }) + 14.0
        }
        func people(_ items: [DkxAdminPerson], title: String, detail: @escaping (DkxAdminPerson) -> String) {
            let rows = Array(items.prefix(8))
            y = self.addCard(x: x, top: y, width: width, title: title, gap: 12.0, content: { card, inner, top, innerWidth in
                var y = top
                for item in rows {
                    let name = dkxAnLabel(item.name, size: 15.0, color: self.colors.primary)
                    name.frame = CGRect(x: inner, y: y, width: innerWidth * 0.45, height: 20.0)
                    card.addSubview(name)
                    let value = dkxAnLabel(detail(item), size: 13.0, color: self.colors.secondary, alignment: .right)
                    value.adjustsFontSizeToFitWidth = true
                    value.minimumScaleFactor = 0.8
                    value.frame = CGRect(x: inner + innerWidth * 0.45 + 8.0, y: y, width: innerWidth * 0.55 - 8.0, height: 20.0)
                    card.addSubview(value)
                    y += 20.0 + 10.0
                }
                return y - 10.0
            }) + 14.0
        }
        if !admin.topPosters.isEmpty {
            people(admin.topPosters, title: DkxStrings.tr("Больше всех пишут"), detail: { item in
                return DkxStrings.tr("{} сообщ. \u{00B7} {} симв. в среднем", dkxAnNumber(item.values[0]), dkxAnNumber(item.values[1]))
            })
        }
        if !admin.topAdmins.isEmpty {
            people(admin.topAdmins, title: DkxStrings.tr("Действия админов"), detail: { item in
                return DkxStrings.tr("удалил {} \u{00B7} выгнал {} \u{00B7} ограничил {}", dkxAnNumber(item.values[0]), dkxAnNumber(item.values[1]), dkxAnNumber(item.values[2]))
            })
        }
        if !admin.topInviters.isEmpty {
            people(admin.topInviters, title: DkxStrings.tr("Больше всех пригласили"), detail: { item in
                return dkxAnNumber(item.values[0])
            })
        }
        return y
    }
}

final class DkxAnalyticsPostsController: DkxAnalyticsBaseController {
    private let report: DkxAnalyticsReport
    private let peer: EnginePeer?
    private var sortIndex = 0
    private var limit = 100
    private let sorts: [Int]

    init(context: AccountContext, report: DkxAnalyticsReport, peer: EnginePeer?) {
        self.report = report
        self.peer = peer
        if report.isChannel && report.hasViews {
            self.sorts = report.impacts.isEmpty ? [1, 2] : [0, 1, 2]
        } else {
            self.sorts = [4, 3]
        }
        super.init(context: context, title: report.isChannel && report.hasViews ? DkxStrings.tr("Влияние постов") : DkxStrings.tr("Сообщения"))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func sortTitle(_ sort: Int) -> String {
        switch sort {
        case 0:
            return DkxStrings.tr("По приросту")
        case 1:
            return DkxStrings.tr("По просмотрам")
        case 2:
            return DkxStrings.tr("По вовлечённости")
        case 3:
            return DkxStrings.tr("Новые")
        default:
            return DkxStrings.tr("По реакциям")
        }
    }

    private func sortedPosts() -> [DkxPost] {
        let report = self.report
        switch self.sorts[self.sortIndex] {
        case 0:
            return report.posts.sorted(by: { lhs, rhs in
                let left = report.impacts[lhs.id]?.net ?? -Double.greatestFiniteMagnitude
                let right = report.impacts[rhs.id]?.net ?? -Double.greatestFiniteMagnitude
                if left != right {
                    return left > right
                }
                return lhs.date > rhs.date
            })
        case 1:
            return report.posts.sorted(by: { $0.views != $1.views ? $0.views > $1.views : $0.date > $1.date })
        case 2:
            return report.posts.sorted(by: { lhs, rhs in
                let left = lhs.engagement ?? -1.0
                let right = rhs.engagement ?? -1.0
                if left != right {
                    return left > right
                }
                return lhs.date > rhs.date
            })
        case 3:
            return report.posts
        default:
            return report.posts.sorted(by: { lhs, rhs in
                let left = lhs.reactions + lhs.comments
                let right = rhs.reactions + rhs.comments
                if left != right {
                    return left > right
                }
                return lhs.date > rhs.date
            })
        }
    }

    override func buildContent(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let report = self.report
        let channelMode = report.isChannel && report.hasViews
        var y = top
        var tiles: [DkxAnTile] = []
        if let growth = report.growth {
            tiles.append((DkxStrings.tr("Пришло"), "+" + dkxAnNumber(growth.joined), self.colors.green, nil, nil, nil, nil))
            tiles.append((DkxStrings.tr("Ушло"), dkxAnMinus + dkxAnNumber(growth.left), self.colors.red, nil, nil, nil, nil))
            tiles.append((DkxStrings.tr("Итого"), dkxAnSignedNumber(growth.net), nil, nil, nil, nil, nil))
        } else if channelMode {
            tiles.append((DkxStrings.tr("Постов"), dkxAnNumber(report.posts.count), nil, nil, nil, nil, nil))
            tiles.append((DkxStrings.tr("Среднее"), dkxAnNumber(Int(report.avgViews.rounded())), nil, nil, nil, nil, nil))
            let erText: String = report.engagement.map { dkxAnPercent($0) } ?? "\u{2014}"
            tiles.append(("ER", erText, nil, nil, nil, nil, nil))
        } else {
            tiles.append((DkxStrings.tr("Сообщений"), dkxAnNumber(report.posts.count), nil, nil, nil, nil, nil))
            tiles.append((DkxStrings.tr("Писали"), dkxAnNumber(report.activeAuthors), nil, nil, nil, nil, nil))
            tiles.append((DkxStrings.tr("Реакции"), dkxAnNumber(report.totalReactions), nil, nil, nil, nil, nil))
        }
        y = self.addTiles(tiles, columns: 3, x: x, top: y, width: width, compact: true) + 14.0

        if !report.growthDays.isEmpty {
            var postDays = Set<Int32>()
            for post in report.posts {
                postDays.insert(post.date - post.date % 86400)
            }
            let days = report.growthDays.map { (joined: $0.joined, left: $0.left, hasPost: postDays.contains($0.start)) }
            y = self.addCard(x: x, top: y, width: width, title: DkxStrings.tr("Прирост по дням"), accessory: DkxStrings.tr("точки это посты"), content: { card, inner, top, innerWidth in
                let chart = DkxAnGrowthView(colors: self.colors)
                chart.days = days
                chart.frame = CGRect(x: inner, y: top, width: innerWidth, height: 156.0)
                card.addSubview(chart)
                let y = top + 166.0
                var legendX = inner
                for (text, color, round) in [(DkxStrings.tr("пришли"), self.colors.green, false), (DkxStrings.tr("ушли"), self.colors.red, false), (DkxStrings.tr("был пост"), self.colors.accent, true)] {
                    let mark = UIView()
                    mark.backgroundColor = color
                    mark.layer.cornerRadius = round ? 4.0 : 3.0
                    let markSize: CGFloat = round ? 8.0 : 10.0
                    mark.frame = CGRect(x: legendX, y: y + (16.0 - markSize) / 2.0, width: markSize, height: markSize)
                    card.addSubview(mark)
                    let label = dkxAnLabel(text, size: 12.0, color: self.colors.secondary)
                    let labelWidth = dkxAnTextWidth(label, limit: 200.0)
                    label.frame = CGRect(x: legendX + markSize + 6.0, y: y, width: labelWidth, height: 16.0)
                    card.addSubview(label)
                    legendX += markSize + 6.0 + labelWidth + 14.0
                }
                return y + 16.0
            }) + 14.0
        }

        if self.sorts.count > 1 {
            y = self.addChoices(self.sorts.map { self.sortTitle($0) }, selected: self.sortIndex, x: x, top: y, width: width, height: 32.0, fontSize: 13.0, padding: 12.0, action: { [weak self] index in
                guard let self, index != self.sortIndex else {
                    return
                }
                self.sortIndex = index
                self.limit = 100
                self.reload()
            }) + 14.0
        }

        let posts = self.sortedPosts()
        let visible = Array(posts.prefix(self.limit))
        let maxNet = dkxAnMaxNet(report)
        let card = self.makeCard()
        var rowY: CGFloat = 0.0
        let rowHeight: CGFloat = 82.0
        for (index, post) in visible.enumerated() {
            let row = DkxAnTapView()
            row.action = { [weak self] in
                self?.openPost(post)
            }
            row.frame = CGRect(x: 0.0, y: rowY, width: width, height: rowHeight)
            let cover = dkxAnCover(dkxAnKindColor(post.kind), icon: nil, size: 44.0)
            cover.frame = CGRect(x: 14.0, y: (rowHeight - 44.0) / 2.0, width: 44.0, height: 44.0)
            row.addSubview(cover)
            let textX: CGFloat = 70.0
            let textWidth = width - textX - 34.0
            let title = dkxAnLabel(post.preview, size: 15.0, color: self.colors.primary)
            title.frame = CGRect(x: textX, y: 12.0, width: textWidth, height: 19.0)
            row.addSubview(title)
            let date = dkxAnLabel(dkxAnDate(post.date, template: "EEdMMMHHmm"), size: 12.0, color: self.colors.secondary)
            date.frame = CGRect(x: textX, y: 36.0, width: textWidth, height: 15.0)
            row.addSubview(date)
            var metaX = textX
            let metaY: CGFloat = 56.0
            if let impact = report.impacts[post.id] {
                let bar = DkxAnBarView(track: self.colors.track, color: impact.net >= 0.0 ? self.colors.green : self.colors.red)
                bar.centered = true
                bar.fraction = maxNet > 0.0 ? CGFloat(impact.net / maxNet) : 0.0
                bar.frame = CGRect(x: metaX, y: metaY + 5.0, width: 90.0, height: 6.0)
                row.addSubview(bar)
                metaX += 98.0
                let subs = dkxAnLabel(dkxAnImpactText(impact), size: 12.0, weight: .semibold, color: impact.net >= 0.0 ? self.colors.green : self.colors.red)
                let subsWidth = dkxAnTextWidth(subs, limit: 120.0)
                subs.frame = CGRect(x: metaX, y: metaY, width: subsWidth, height: 16.0)
                row.addSubview(subs)
                metaX += subsWidth + 8.0
            }
            var parts: [String] = []
            if channelMode {
                if let ratio = report.ratio(post) {
                    parts.append(dkxAnRatio(ratio))
                } else {
                    parts.append(dkxAnNumber(post.views) + " " + DkxStrings.tr("просм."))
                }
                if let engagement = post.engagement {
                    parts.append("ER " + dkxAnPercent(engagement))
                }
            } else {
                if let author = post.authorName {
                    parts.append(author)
                }
                if post.reactions > 0 {
                    parts.append(DkxStrings.tr("реакций {}", dkxAnNumber(post.reactions)))
                }
            }
            let meta = dkxAnLabel(parts.joined(separator: " \u{00B7} "), size: 12.0, color: self.colors.secondary)
            meta.frame = CGRect(x: metaX, y: metaY, width: max(0.0, textX + textWidth - metaX), height: 16.0)
            row.addSubview(meta)
            let chevron = dkxAnChevron(self.colors)
            chevron.frame = CGRect(x: width - 24.0, y: 0.0, width: 10.0, height: rowHeight)
            row.addSubview(chevron)
            card.addSubview(row)
            rowY += rowHeight
            if index != visible.count - 1 {
                let separator = UIView()
                separator.backgroundColor = self.colors.separator
                separator.frame = CGRect(x: 0.0, y: rowY - 0.5, width: width, height: 0.5)
                card.addSubview(separator)
            }
        }
        card.frame = CGRect(x: x, y: y, width: width, height: rowY)
        self.add(card)
        y += rowY + 14.0
        if posts.count > visible.count {
            let more = self.makeButton(DkxStrings.tr("Показать ещё, осталось {}", dkxAnNumber(posts.count - visible.count)), width: width, height: 48.0, filled: false, fontSize: 15.0, action: { [weak self] in
                guard let self else {
                    return
                }
                self.limit += 100
                self.reload()
            })
            more.frame.origin = CGPoint(x: x, y: y)
            self.add(more)
            y += 48.0 + 14.0
        }
        if channelMode {
            let note = report.impacts.isEmpty ? DkxStrings.tr("Прирост и отток Telegram отдаёт по дням и только админу канала.") : DkxStrings.tr("Прирост и отток Telegram отдаёт по дням и только админу канала. Если в день было несколько постов, прирост делится между ними по просмотрам. Это оценка, а не точная привязка.")
            y = self.addFootnote(note, x: x, top: y, width: width)
        }
        return y + 8.0
    }

    private func openPost(_ post: DkxPost) {
        self.push(DkxAnalyticsPostController(context: self.context, report: self.report, post: post, peer: self.peer))
    }
}

private func dkxHalfTime(_ graph: StatsGraph) -> (hours: Int, values: [Double], daily: Bool)? {
    guard let parsed = dkxParseStatsGraph(graph), let views = parsed.series.first, views.values.count > 1, parsed.x.count > 1 else {
        return nil
    }
    let daily = parsed.x[1] - parsed.x[0] >= 86400000.0 - 1.0
    let total = views.values.reduce(0.0) { $0 + max(0.0, $1) }
    guard total > 0.0 else {
        return nil
    }
    var running = 0.0
    for (index, value) in views.values.enumerated() {
        running += max(0.0, value)
        if running >= total / 2.0 {
            return (index + 1, views.values, daily)
        }
    }
    return nil
}

final class DkxAnalyticsPostController: DkxAnalyticsBaseController {
    private let report: DkxAnalyticsReport
    private let post: DkxPost
    private let peer: EnginePeer?
    private var canViewStats = false
    private var statsLoading = false
    private var timeline: (hours: Int, values: [Double], daily: Bool)?
    private var typicalHalf: Int?
    private var reposts: [(peerId: EnginePeer.Id?, name: String, views: Int?, isChannel: Bool)] = []
    private var repostMembers: [EnginePeer.Id: Int] = [:]
    private var statsContext: MessageStatsContext?
    private var forwardsContext: StoryStatsPublicForwardsContext?
    private let statsDisposable = MetaDisposable()
    private let forwardsDisposable = MetaDisposable()
    private let membersDisposable = MetaDisposable()
    private let typicalDisposable = MetaDisposable()
    private var canViewDisposable: Disposable?

    init(context: AccountContext, report: DkxAnalyticsReport, post: DkxPost, peer: EnginePeer?) {
        self.report = report
        self.post = post
        self.peer = peer
        super.init(context: context, title: report.isChannel ? DkxStrings.tr("Разбор поста") : DkxStrings.tr("Разбор сообщения"))

        if report.isChannel {
            self.canViewDisposable = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.CanViewStats(id: post.id.peerId))
            |> deliverOnMainQueue).start(next: { [weak self] canViewStats in
                guard let self else {
                    return
                }
                self.canViewStats = canViewStats
                if canViewStats {
                    self.loadStats()
                }
                self.reload()
            })
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.statsDisposable.dispose()
        self.forwardsDisposable.dispose()
        self.membersDisposable.dispose()
        self.typicalDisposable.dispose()
        self.canViewDisposable?.dispose()
    }

    private func loadStats() {
        self.statsLoading = true
        let statsContext = MessageStatsContext(account: self.context.account, messageId: self.post.id)
        self.statsContext = statsContext
        self.statsDisposable.set((statsContext.state
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self, let stats = state.stats else {
                return
            }
            self.statsLoading = false
            self.timeline = dkxHalfTime(stats.interactionsGraph)
            self.reload()
        }))

        let forwardsContext = StoryStatsPublicForwardsContext(account: self.context.account, subject: .message(messageId: self.post.id))
        self.forwardsContext = forwardsContext
        self.forwardsDisposable.set((forwardsContext.state
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else {
                return
            }
            var result: [(peerId: EnginePeer.Id?, name: String, views: Int?, isChannel: Bool)] = []
            for forward in state.forwards {
                switch forward {
                case let .message(message):
                    let author = message.author
                    var isChannel = false
                    if let author, case let .channel(channel) = author, case .broadcast = channel.info {
                        isChannel = true
                    }
                    var views: Int?
                    for attribute in message.attributes {
                        if let attribute = attribute as? ViewCountMessageAttribute {
                            views = attribute.count
                        }
                    }
                    result.append((peerId: author?.id, name: author?.compactDisplayTitle ?? "", views: views, isChannel: isChannel))
                case let .story(peer, item):
                    result.append((peerId: peer.id, name: peer.compactDisplayTitle, views: item.views?.seenCount, isChannel: false))
                }
            }
            self.reposts = result
            self.loadRepostMembers()
            self.reload()
        }))

        // Сколько времени средний пост набирает половину просмотров, по 8 последним зрелым постам
        let others = self.report.posts.filter { self.report.isMature($0) && $0.id != self.post.id }.prefix(8)
        let account = self.context.account
        let signals = others.map { other -> Signal<Int?, NoError> in
            return Signal<Int?, NoError> { subscriber in
                let otherContext = MessageStatsContext(account: account, messageId: other.id)
                let disposable = (otherContext.state
                |> filter { $0.stats != nil }
                |> take(1)).start(next: { state in
                    var hours: Int?
                    if let graph = state.stats?.interactionsGraph, let half = dkxHalfTime(graph), !half.daily {
                        hours = half.hours
                    }
                    subscriber.putNext(hours)
                    subscriber.putCompletion()
                })
                return ActionDisposable {
                    disposable.dispose()
                    let _ = otherContext
                }
            }
            |> runOn(Queue.mainQueue())
            |> timeout(20.0, queue: Queue.mainQueue(), alternate: .single(nil))
        }
        if signals.count >= 3 {
            self.typicalDisposable.set((combineLatest(signals)
            |> deliverOnMainQueue).start(next: { [weak self] values in
                guard let self else {
                    return
                }
                let known = values.compactMap { $0 }
                if known.count >= 3 {
                    self.typicalHalf = Int(dkxMedian(known).rounded())
                    self.reload()
                }
            }))
        }
    }

    private func loadRepostMembers() {
        let ids = Array(Set(self.reposts.compactMap { $0.peerId }))
        if ids.isEmpty {
            return
        }
        self.membersDisposable.set((self.context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.ParticipantCount.init)))
        |> deliverOnMainQueue).start(next: { [weak self] counts in
            guard let self else {
                return
            }
            var result: [EnginePeer.Id: Int] = [:]
            for (id, count) in counts {
                if let count {
                    result[id] = count
                }
            }
            self.repostMembers = result
            self.reload()
        }))
    }

    override func buildContent(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let report = self.report
        let post = self.post
        var y = self.buildPostCard(x: x, top: top, width: width) + 14.0
        y = self.buildRank(x: x, top: y, width: width) + 14.0
        y = self.buildTiles(x: x, top: y, width: width) + 14.0
        if let timeline = self.timeline {
            y = self.buildTimeline(timeline, x: x, top: y, width: width) + 14.0
        } else if self.statsLoading {
            y = self.addFootnote(DkxStrings.tr("Загружаю статистику Telegram по посту"), x: x, top: y, width: width, center: true) + 14.0
        }
        if let impact = report.impacts[post.id] {
            y = self.buildImpact(impact, x: x, top: y, width: width) + 14.0
        }
        if !post.reactionItems.isEmpty {
            y = self.buildPostReactions(x: x, top: y, width: width) + 14.0
        }
        if !self.reposts.isEmpty {
            y = self.buildReposts(x: x, top: y, width: width) + 14.0
        }
        if report.isChannel, let best = report.bestTime {
            y = self.buildTimeNote(best, x: x, top: y, width: width) + 14.0
        }
        if self.peer != nil {
            let showStats = self.canViewStats
            let half = floor((width - 10.0) / 2.0)
            let openButton = self.makeButton(report.isChannel ? DkxStrings.tr("Открыть пост") : DkxStrings.tr("Открыть сообщение"), width: showStats ? half : width, height: 48.0, filled: false, fontSize: 15.0, action: { [weak self] in
                self?.openMessage()
            })
            openButton.frame.origin = CGPoint(x: x, y: y)
            self.add(openButton)
            if showStats {
                let stats = self.makeButton(DkxStrings.tr("Статистика Telegram"), width: half, height: 48.0, filled: false, fontSize: 15.0, action: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.push(messageStatsController(context: self.context, subject: .message(id: self.post.id)))
                })
                stats.frame.origin = CGPoint(x: x + half + 10.0, y: y)
                self.add(stats)
            }
            y += 48.0 + 14.0
        }
        if report.isChannel && !self.canViewStats {
            y = self.addFootnote(DkxStrings.tr("Просмотры по часам, репосты и подписки по дням Telegram показывает только админу канала."), x: x, top: y, width: width, center: true) + 8.0
        }
        return y
    }

    private func openMessage() {
        guard let peer = self.peer, let navigationController = self.navigationController as? NavigationController else {
            return
        }
        self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peer), subject: .message(id: .id(self.post.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
    }

    private func buildPostCard(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let post = self.post
        let card = self.makeCard()
        let band = UIView()
        band.backgroundColor = dkxAnKindColor(post.kind)
        band.frame = CGRect(x: 0.0, y: 0.0, width: width, height: 150.0)
        let icon = dkxAnSymbol(dkxAnKindIcon(post.kind), size: 36.0, weight: .regular, color: .white)
        icon.frame = band.bounds
        band.addSubview(icon)
        card.addSubview(band)
        var y: CGFloat = 150.0 + 14.0
        let text = post.fullText.isEmpty ? post.kind.title : String(post.fullText.prefix(600))
        y += dkxAnPlace(dkxAnLabel(text, size: 16.0, color: self.colors.primary, lines: 12), in: card, x: 16.0, y: y, width: width - 32.0) + 6.0
        let kindText = post.kind.title.lowercased(with: DkxStrings.locale)
        var meta = dkxAnDate(post.date, template: "EEEEdMMMMHHmm") + " \u{00B7} " + (post.kind != .text && !post.fullText.isEmpty ? DkxStrings.tr("{} и текст", kindText) : kindText)
        if post.isAd {
            meta += " \u{00B7} " + DkxStrings.tr("реклама")
        }
        y += dkxAnPlace(dkxAnLabel(meta, size: 13.0, color: self.colors.secondary, lines: 0), in: card, x: 16.0, y: y, width: width - 32.0) + 14.0
        card.frame = CGRect(x: x, y: top, width: width, height: y)
        self.add(card)
        return top + y
    }

    private func buildRank(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let report = self.report
        let post = self.post
        let period = dkxAnPeriodTitle(report.periodDays)
        let title: String
        var subtitle = ""
        let color: UIColor
        let icon: String
        if !report.hasViews {
            title = DkxStrings.tr("Реакций {}, ответов {}", dkxAnNumber(post.reactions), dkxAnNumber(post.comments))
            if let author = post.authorName {
                subtitle = DkxStrings.tr("Автор {}", author)
            }
            color = self.colors.accent
            icon = "bubble.left"
        } else if let percentile = report.percentile(post) {
            let value = Int(percentile.rounded())
            if value >= 50 {
                title = DkxStrings.tr("Лучше {} постов канала", "\(value)%")
                color = self.colors.green
                icon = "chart.line.uptrend.xyaxis"
            } else {
                title = DkxStrings.tr("Лучше только {} постов канала", "\(value)%")
                color = self.colors.orange
                icon = "chart.line.downtrend.xyaxis"
            }
            let viewsPlace = dkxAnPlaceText(report.viewsRank(post) ?? 1)
            if let netRank = report.netRank(post) {
                subtitle = DkxStrings.tr("{} по просмотрам и {} по приросту за {}", viewsPlace, dkxAnPlaceText(netRank), period)
            } else {
                subtitle = DkxStrings.tr("{} по просмотрам за {}", viewsPlace, period)
            }
        } else if !report.isMature(post) {
            title = DkxStrings.tr("Посту меньше 48 часов")
            subtitle = DkxStrings.tr("Просмотры ещё растут, сравнение с другими постами появится позже.")
            color = self.colors.accent
            icon = "clock"
        } else {
            title = DkxStrings.tr("Мало постов для сравнения")
            subtitle = DkxStrings.tr("Нужно хотя бы 5 постов старше 48 часов за период.")
            color = self.colors.accent
            icon = "chart.bar"
        }
        let banner = UIView()
        banner.layer.cornerRadius = 22.0
        banner.layer.cornerCurve = .continuous
        banner.backgroundColor = color.withAlphaComponent(0.12)
        let iconView = dkxAnSymbol(icon, size: 22.0, color: color)
        banner.addSubview(iconView)
        let textX: CGFloat = 54.0
        let textWidth = width - textX - 16.0
        var y: CGFloat = 14.0
        y += dkxAnPlace(dkxAnLabel(title, size: 16.0, weight: .semibold, color: self.colors.primary, lines: 0), in: banner, x: textX, y: y, width: textWidth)
        if !subtitle.isEmpty {
            y += 2.0
            y += dkxAnPlace(dkxAnLabel(subtitle, size: 13.0, color: self.colors.secondary, lines: 0), in: banner, x: textX, y: y, width: textWidth)
        }
        y += 14.0
        iconView.frame = CGRect(x: 14.0, y: 0.0, width: 28.0, height: y)
        banner.frame = CGRect(x: x, y: top, width: width, height: y)
        self.add(banner)
        return top + y
    }

    private func buildTiles(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let report = self.report
        let post = self.post
        let averages = report.averages()
        let mature = report.isMature(post)
        func ratioNote(_ value: Int, _ average: Double) -> (String?, UIColor?) {
            guard mature, average > 0.0 else {
                return (nil, nil)
            }
            let ratio = Double(value) / average
            return (DkxStrings.tr("{} к среднему", dkxAnRatio(ratio)), ratio >= 1.0 ? self.colors.green : self.colors.red)
        }
        var tiles: [DkxAnTile] = []
        if report.hasViews {
            let viewsNote = ratioNote(post.views, report.avgViews)
            tiles.append((DkxStrings.tr("Просмотры"), dkxAnNumber(post.views), nil, viewsNote.0, viewsNote.1, nil, nil))
        }
        let reactionsNote = ratioNote(post.reactions, averages.reactions)
        tiles.append((DkxStrings.tr("Реакции"), dkxAnNumber(post.reactions), nil, reactionsNote.0, reactionsNote.1, nil, nil))
        if report.hasViews {
            let forwardsNote = ratioNote(post.forwards, averages.forwards)
            tiles.append((DkxStrings.tr("Пересылки"), dkxAnNumber(post.forwards), nil, forwardsNote.0, forwardsNote.1, nil, nil))
        }
        let commentsNote = ratioNote(post.comments, averages.comments)
        tiles.append((report.isChannel ? DkxStrings.tr("Комментарии") : DkxStrings.tr("Ответы"), dkxAnNumber(post.comments), nil, commentsNote.0, commentsNote.1, nil, nil))
        if report.hasViews {
            if let members = report.members, members > 0 {
                tiles.append(("ERR", dkxAnPercent(Double(post.views) / Double(members) * 100.0), nil, DkxStrings.tr("просмотры от подписчиков"), nil, nil, nil))
            }
            if let engagement = post.engagement {
                var note: String?
                var noteColor: UIColor?
                if mature, let average = averages.engagement {
                    note = DkxStrings.tr("{} к среднему", dkxAnSignedPercent(engagement - average, digits: 1))
                    noteColor = engagement >= average ? self.colors.green : self.colors.red
                }
                tiles.append((DkxStrings.tr("Вовлечённость"), dkxAnPercent(engagement), nil, note, noteColor, nil, nil))
            }
        }
        return self.addTiles(tiles, columns: 2, x: x, top: top, width: width, compact: true)
    }

    private func buildTimeline(_ timeline: (hours: Int, values: [Double], daily: Bool), x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        var cumulative: [Double] = []
        var running = 0.0
        for value in timeline.values {
            running += max(0.0, value)
            cumulative.append(running)
        }
        let span = timeline.values.count
        let accessory = timeline.daily ? DkxStrings.plural(span, "{} день", "{} дня", "{} дней") : DkxStrings.plural(span, "{} час", "{} часа", "{} часов")
        let typicalHalf = self.typicalHalf
        return self.addCard(x: x, top: top, width: width, title: DkxStrings.tr("Просмотры после публикации"), accessory: accessory, content: { card, inner, top, innerWidth in
            let chart = DkxAnLineChartView(color: self.colors.accent, guide: self.colors.secondary, background: self.colors.card)
            chart.showAverage = false
            chart.markPeak = false
            chart.marker = timeline.hours - 1
            chart.values = cumulative
            chart.frame = CGRect(x: inner, y: top, width: innerWidth, height: 150.0)
            card.addSubview(chart)
            var y = top + 158.0
            let unit = timeline.daily ? DkxStrings.tr("дн") : DkxStrings.tr("ч")
            let marks = 5
            for index in 0 ..< marks {
                let value = Int((Double(span) * Double(index) / Double(marks - 1)).rounded())
                let alignment: NSTextAlignment = index == 0 ? .left : (index == marks - 1 ? .right : .center)
                let label = dkxAnLabel("\(value) " + unit, size: 11.0, color: self.colors.secondary, alignment: alignment)
                let position = inner + innerWidth * CGFloat(index) / CGFloat(marks - 1)
                var labelX: CGFloat = position - 20.0
                if index == 0 {
                    labelX = position
                } else if index == marks - 1 {
                    labelX = position - 40.0
                }
                label.frame = CGRect(x: labelX, y: y, width: 40.0, height: 14.0)
                card.addSubview(label)
            }
            y += 14.0 + 10.0
            var text: String
            if timeline.daily {
                text = DkxStrings.tr("Половину просмотров пост набрал за первые {} дн.", timeline.hours)
            } else {
                text = DkxStrings.tr("Половину просмотров пост набрал за первые {} ч.", timeline.hours)
                if let typicalHalf {
                    text += " " + DkxStrings.tr("У среднего поста канала на это уходит {} ч.", typicalHalf)
                }
            }
            y += dkxAnPlace(dkxAnLabel(text, size: 13.0, color: self.colors.secondary, lines: 0), in: card, x: inner, y: y, width: innerWidth)
            return y
        })
    }

    private func buildImpact(_ impact: DkxPostImpact, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let report = self.report
        return self.addCard(x: x, top: top, width: width, title: DkxStrings.tr("Подписчики в день публикации"), content: { card, inner, top, innerWidth in
            var boxes: [(String, String, UIColor, UIColor)] = [
                (DkxStrings.tr("пришли"), "+" + dkxAnNumber(impact.dayJoined), self.colors.green, self.colors.green.withAlphaComponent(0.12)),
                (DkxStrings.tr("ушли"), dkxAnMinus + dkxAnNumber(impact.dayLeft), self.colors.red, self.colors.red.withAlphaComponent(0.12))
            ]
            if let typical = report.typicalDayJoined {
                boxes.append((DkxStrings.tr("обычно"), "+" + dkxAnNumber(typical), self.colors.primary, self.colors.chip))
            }
            let gap: CGFloat = 10.0
            let boxWidth = floor((innerWidth - gap * CGFloat(boxes.count - 1)) / CGFloat(boxes.count))
            for (index, box) in boxes.enumerated() {
                let view = UIView()
                view.backgroundColor = box.3
                view.layer.cornerRadius = 16.0
                view.frame = CGRect(x: inner + CGFloat(index) * (boxWidth + gap), y: top, width: boxWidth, height: 66.0)
                let label = dkxAnLabel(box.0, size: 12.0, color: self.colors.secondary)
                label.frame = CGRect(x: 12.0, y: 12.0, width: boxWidth - 24.0, height: 15.0)
                view.addSubview(label)
                let value = dkxAnLabel(box.1, size: 22.0, weight: .bold, color: box.2)
                value.adjustsFontSizeToFitWidth = true
                value.minimumScaleFactor = 0.6
                value.frame = CGRect(x: 12.0, y: 29.0, width: boxWidth - 24.0, height: 26.0)
                view.addSubview(value)
                card.addSubview(view)
            }
            var y = top + 66.0 + 10.0
            let note: String
            if impact.postsThatDay > 1 {
                note = DkxStrings.tr("Оценка по дню публикации. В тот день постов было {}, прирост поделён по их просмотрам.", dkxAnNumber(impact.postsThatDay))
            } else {
                note = DkxStrings.tr("Оценка по дню публикации. В тот день пост был один.")
            }
            y += dkxAnPlace(dkxAnLabel(note, size: 12.0, color: self.colors.secondary, lines: 0), in: card, x: inner, y: y, width: innerWidth)
            return y
        })
    }

    private func buildPostReactions(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let rows = Array(self.post.reactionItems.prefix(6))
        let maxCount = Double(rows.first?.count ?? 1)
        let wide = rows.contains(where: { $0.name.count > 3 })
        return self.addCard(x: x, top: top, width: width, title: DkxStrings.tr("Реакции"), gap: 12.0, content: { card, inner, top, innerWidth in
            var y = top
            for item in rows {
                y = self.addBarRow(to: card, x: inner, y: y, width: innerWidth, title: item.name, value: dkxAnNumber(item.count), fraction: CGFloat(Double(item.count) / max(1.0, maxCount)), color: self.colors.orange, titleWidth: wide ? 110.0 : 26.0, titleSize: wide ? 14.0 : 20.0, valueWidth: 40.0) + 6.0
            }
            return y - 6.0
        })
    }

    private func buildReposts(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let rows = Array(self.reposts.prefix(10))
        let palette: [UInt32] = [0x34c759, 0xaf52de, 0xf7a23e, 0x3e88f7, 0xff453a, 0x5ac8fa]
        return self.addCard(x: x, top: top, width: width, title: DkxStrings.tr("Публичные репосты"), gap: 6.0, content: { card, inner, top, innerWidth in
            var y = top
            for (index, row) in rows.enumerated() {
                let rowTop = y + 10.0
                let avatar = UIView()
                avatar.backgroundColor = UIColor(rgb: palette[index % palette.count])
                avatar.layer.cornerRadius = 19.0
                avatar.frame = CGRect(x: inner, y: rowTop, width: 38.0, height: 38.0)
                let letter = dkxAnLabel(String(row.name.prefix(1)).uppercased(), size: 16.0, weight: .bold, color: .white, alignment: .center)
                letter.frame = avatar.bounds
                avatar.addSubview(letter)
                card.addSubview(avatar)
                let viewsText = row.views.map { dkxAnNumber($0) + " " + DkxStrings.tr("просм.") } ?? ""
                let views = dkxAnLabel(viewsText, size: 14.0, color: self.colors.secondary, alignment: .right)
                let viewsWidth = dkxAnTextWidth(views, limit: 120.0)
                views.frame = CGRect(x: inner + innerWidth - viewsWidth, y: rowTop, width: viewsWidth, height: 38.0)
                card.addSubview(views)
                let textWidth = innerWidth - 50.0 - viewsWidth - 8.0
                let name = dkxAnLabel(row.name, size: 15.0, color: self.colors.primary)
                name.frame = CGRect(x: inner + 50.0, y: rowTop + 1.0, width: textWidth, height: 19.0)
                card.addSubview(name)
                let subtitle: String
                if let peerId = row.peerId, let count = self.repostMembers[peerId] {
                    subtitle = dkxAnNumber(count) + " " + (row.isChannel ? DkxStrings.plural(count, "подписчик", "подписчика", "подписчиков") : DkxStrings.plural(count, "участник", "участника", "участников"))
                } else {
                    subtitle = row.isChannel ? DkxStrings.tr("канал") : DkxStrings.tr("группа")
                }
                let sub = dkxAnLabel(subtitle, size: 12.0, color: self.colors.secondary)
                sub.frame = CGRect(x: inner + 50.0, y: rowTop + 22.0, width: textWidth, height: 15.0)
                card.addSubview(sub)
                y = rowTop + 38.0 + 10.0
            }
            return y - 10.0
        })
    }

    private func buildTimeNote(_ best: DkxBestTime, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let hour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: Double(self.post.date)))
        let inWindow = (hour - best.fromHour + 24) % 24 < 3
        let time = dkxAnDate(self.post.date, template: "EEEEHHmm")
        let text: String
        if inWindow {
            text = DkxStrings.tr("Опубликован {}, в лучшее окно канала. Посты в это время набирают в среднем {} просмотров к остальному времени.", time, dkxAnSignedPercent(best.gainPercent))
        } else {
            text = DkxStrings.tr("Опубликован {}. Лучшее окно канала {}, посты в нём набирают в среднем {} просмотров к остальному времени.", time, dkxAnWindowText(best.fromHour, best.toHour), dkxAnSignedPercent(best.gainPercent))
        }
        return self.addCard(x: x, top: top, width: width, title: nil, padding: 14.0, content: { card, inner, top, innerWidth in
            let icon = dkxAnSymbol("clock", size: 18.0, color: inWindow ? self.colors.green : self.colors.secondary)
            icon.frame = CGRect(x: inner, y: top, width: 22.0, height: 22.0)
            card.addSubview(icon)
            return top + dkxAnPlace(dkxAnLabel(text, size: 14.0, color: self.colors.primary, lines: 0), in: card, x: inner + 34.0, y: top + 1.0, width: innerWidth - 34.0)
        })
    }
}
