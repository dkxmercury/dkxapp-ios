import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramUIPreferences
import SettingsUI

private func dkxXlsxDate(_ timestamp: Int32, utc: Bool = false, time: Bool = true) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    if utc {
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
    }
    formatter.dateFormat = time ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
}

private func dkxRound(_ value: Double, _ digits: Int = 2) -> Double {
    let scale = pow(10.0, Double(digits))
    return (value * scale).rounded() / scale
}

private func dkxPostLink(_ post: DkxPost, username: String?) -> String {
    if let username, !username.isEmpty {
        return "https://t.me/\(username)/\(post.id.id)"
    }
    if post.id.peerId.namespace == Namespaces.Peer.CloudChannel {
        return "https://t.me/c/\(post.id.peerId.id._internalGetInt64Value())/\(post.id.id)"
    }
    return ""
}

func dkxAnalyticsSheets(report: DkxAnalyticsReport, title: String, username: String?, periodTitle: String) -> [DkxXlsxSheet] {
    typealias Cell = DkxXlsxCell
    func text(_ value: String) -> Cell {
        return .text(value)
    }
    func number(_ value: Double) -> Cell {
        return .number(value)
    }
    func int(_ value: Int) -> Cell {
        return .number(Double(value))
    }
    let yes = DkxStrings.tr("да")
    let no = DkxStrings.tr("нет")
    var sheets: [DkxXlsxSheet] = []

    var summary: [[Cell]] = [[text(DkxStrings.tr("Показатель")), text(DkxStrings.tr("Значение")), text(DkxStrings.tr("Как считается"))]]
    summary.append([text(report.isChannel ? DkxStrings.tr("Канал") : DkxStrings.tr("Группа")), text(title), text("")])
    if let username, !username.isEmpty {
        summary.append([text(DkxStrings.tr("Ссылка")), text("https://t.me/" + username), text("")])
    }
    summary.append([text(DkxStrings.tr("Период")), text(periodTitle), text("")])
    summary.append([text(DkxStrings.tr("С")), text(dkxXlsxDate(report.periodStart)), text(DkxStrings.tr("время телефона"))])
    summary.append([text(DkxStrings.tr("По")), text(dkxXlsxDate(report.periodEnd)), text("")])
    summary.append([text(report.isChannel ? DkxStrings.tr("Постов") : DkxStrings.tr("Сообщений")), int(report.posts.count), text(DkxStrings.tr("альбом считается одним постом, служебные сообщения не считаются"))])
    if let members = report.members {
        summary.append([text(report.isChannel ? DkxStrings.tr("Подписчиков сейчас") : DkxStrings.tr("Участников сейчас")), int(members), text("")])
    }
    if report.hasViews {
        summary.append([text(DkxStrings.tr("Просмотров всего")), int(report.totalViews), text(DkxStrings.tr("сумма просмотров постов периода"))])
        summary.append([text(DkxStrings.tr("Просмотры на пост")), number(dkxRound(report.avgViews)), text(DkxStrings.tr("среднее по постам старше 48 часов, если их нет, то по всем"))])
        summary.append([text(DkxStrings.tr("Медиана просмотров")), number(dkxRound(report.medianViews)), text(DkxStrings.tr("по тем же постам"))])
        if let err = report.err {
            summary.append([text("ERR, %"), number(dkxRound(err)), text(DkxStrings.tr("просмотры на пост / подписчики сейчас × 100"))])
        }
        if let engagement = report.engagement {
            summary.append([text(DkxStrings.tr("Вовлечённость, %")), number(dkxRound(engagement)), text(DkxStrings.tr("(реакции + пересылки + комментарии) / просмотры × 100, по всем постам периода"))])
        }
    }
    summary.append([text(DkxStrings.tr("Реакций")), int(report.totalReactions), text("")])
    summary.append([text(DkxStrings.tr("Пересылок")), int(report.totalForwards), text("")])
    summary.append([text(DkxStrings.tr("Комментариев")), int(report.totalComments), text("")])
    if report.totalPaidStars > 0 {
        summary.append([text(DkxStrings.tr("Платных звёзд")), int(report.totalPaidStars), text("")])
    }
    summary.append([text(DkxStrings.tr("Постов в день")), number(dkxRound(report.postsPerDay)), text(DkxStrings.tr("посты / дни периода"))])
    if let growth = report.growth {
        summary.append([text(DkxStrings.tr("Пришло")), int(growth.joined), text(DkxStrings.tr("данные Telegram, сутки UTC"))])
        summary.append([text(DkxStrings.tr("Ушло")), int(growth.left), text(DkxStrings.tr("данные Telegram, сутки UTC"))])
        summary.append([text(DkxStrings.tr("Итого")), int(growth.net), text("")])
    }
    if let best = report.bestTime {
        summary.append([text(DkxStrings.tr("Лучшее время")), text(dkxAnHour(best.fromHour) + "-" + dkxAnHour(best.toHour)), text(DkxStrings.tr("окно 3 часа с наибольшими средними просмотрами, время телефона"))])
        summary.append([text(DkxStrings.tr("Прибавка лучшего окна, %")), number(dkxRound(best.gainPercent)), text(DkxStrings.tr("средние просмотры в окне к средним просмотрам остальных постов"))])
        summary.append([text(DkxStrings.tr("Худшее время")), text(dkxAnHour(best.worstFromHour) + "-" + dkxAnHour(best.worstToHour)), text("")])
        summary.append([text(DkxStrings.tr("Разница худшего окна, %")), number(dkxRound(best.worstPercent)), text("")])
    }
    summary.append([text(DkxStrings.tr("Рекламных постов")), int(report.adPosts), text(DkxStrings.tr("по пометкам {}", "erid, #реклама, #ad"))])
    if report.adAvgViews > 0.0 {
        summary.append([text(DkxStrings.tr("Просмотры на рекламный пост")), number(dkxRound(report.adAvgViews)), text(DkxStrings.tr("посты старше 48 часов"))])
        summary.append([text(DkxStrings.tr("Просмотры на обычный пост")), number(dkxRound(report.nonAdAvgViews)), text(DkxStrings.tr("посты старше 48 часов"))])
    }
    if let previous = report.previous {
        summary.append([text(DkxStrings.tr("Прошлый период, постов")), int(previous.posts), text(DkxStrings.tr("такой же длины перед выбранным"))])
        if report.hasViews {
            summary.append([text(DkxStrings.tr("Прошлый период, просмотры на пост")), number(dkxRound(previous.avgViews)), text("")])
            if let err = previous.err {
                summary.append([text(DkxStrings.tr("Прошлый период, ERR, %")), number(dkxRound(err)), text(DkxStrings.tr("к числу подписчиков сейчас"))])
            }
            if let engagement = previous.engagement {
                summary.append([text(DkxStrings.tr("Прошлый период, вовлечённость, %")), number(dkxRound(engagement)), text("")])
            }
        }
    }
    summary.append([text(DkxStrings.tr("Выгрузка обрезана")), text(report.capped ? yes : no), text(report.capped ? DkxStrings.tr("загружены последние {} сообщений", report.loadedMessages) : "")])
    sheets.append(DkxXlsxSheet(name: DkxStrings.tr("Сводка"), rows: summary))

    var days: [[Cell]] = [[text(DkxStrings.tr("Дата")), text(DkxStrings.tr("Постов")), text(DkxStrings.tr("Просмотров")), text(DkxStrings.tr("Реакций")), text(DkxStrings.tr("Пересылок")), text(DkxStrings.tr("Комментариев"))]]
    for day in report.days {
        days.append([text(dkxXlsxDate(day.start, time: false)), int(day.bucket.posts), int(day.bucket.views), int(day.bucket.reactions), int(day.bucket.forwards), int(day.bucket.comments)])
    }
    sheets.append(DkxXlsxSheet(name: DkxStrings.tr("По дням"), rows: days))

    if !report.growthDays.isEmpty {
        var growth: [[Cell]] = [[text(DkxStrings.tr("Дата UTC")), text(DkxStrings.tr("Пришло")), text(DkxStrings.tr("Ушло")), text(DkxStrings.tr("Итого"))]]
        for day in report.growthDays {
            growth.append([text(dkxXlsxDate(day.start, utc: true, time: false)), int(day.joined), int(day.left), int(day.joined - day.left)])
        }
        sheets.append(DkxXlsxSheet(name: DkxStrings.tr("Подписчики"), rows: growth))
    }

    var hoursHeader: [Cell] = [text(DkxStrings.tr("Час")), text(DkxStrings.tr("Постов")), text(DkxStrings.tr("Постов старше 48 часов")), text(DkxStrings.tr("Просмотры на пост"))]
    if report.readingHours != nil {
        hoursHeader.append(text(DkxStrings.tr("Просмотры канала, Telegram")))
    }
    var hours: [[Cell]] = [hoursHeader]
    for (hour, bucket) in report.hours.enumerated() {
        var row: [Cell] = [text(dkxAnHour(hour)), int(bucket.posts), int(bucket.maturePosts), number(dkxRound(bucket.matureAvgViews))]
        if let readingHours = report.readingHours, hour < readingHours.count {
            row.append(number(dkxRound(readingHours[hour])))
        }
        hours.append(row)
    }
    sheets.append(DkxXlsxSheet(name: DkxStrings.tr("По часам"), rows: hours))

    var weekdays: [[Cell]] = [[text(DkxStrings.tr("День")), text(DkxStrings.tr("Постов")), text(DkxStrings.tr("Постов старше 48 часов")), text(DkxStrings.tr("Просмотры на пост"))]]
    for (index, bucket) in report.weekdays.enumerated() {
        weekdays.append([text(dkxAnWeekdayShort(index)), int(bucket.posts), int(bucket.maturePosts), number(dkxRound(bucket.matureAvgViews))])
    }
    sheets.append(DkxXlsxSheet(name: DkxStrings.tr("Дни недели"), rows: weekdays))

    var kinds: [[Cell]] = [[text(DkxStrings.tr("Тип")), text(DkxStrings.tr("Постов")), text(DkxStrings.tr("Просмотры на пост")), text(DkxStrings.tr("Реакций")), text(DkxStrings.tr("Пересылок")), text(DkxStrings.tr("Комментариев"))]]
    for row in report.kinds {
        let average = row.bucket.maturePosts > 0 ? row.bucket.matureAvgViews : row.bucket.avgViews
        kinds.append([text(row.kind.title), int(row.bucket.posts), number(dkxRound(average)), int(row.bucket.reactions), int(row.bucket.forwards), int(row.bucket.comments)])
    }
    sheets.append(DkxXlsxSheet(name: DkxStrings.tr("Типы"), rows: kinds))

    var posts: [[Cell]] = [[text(DkxStrings.tr("Дата")), text(DkxStrings.tr("Тип")), text(DkxStrings.tr("Текст")), text(DkxStrings.tr("Просмотры")), text(DkxStrings.tr("Реакции")), text(DkxStrings.tr("Пересылки")), text(DkxStrings.tr("Комментарии")), text(DkxStrings.tr("Звёзды")), text(DkxStrings.tr("Вовлечённость, %")), text(DkxStrings.tr("К среднему, раз")), text(DkxStrings.tr("Пришло, оценка")), text(DkxStrings.tr("Ушло, оценка")), text(DkxStrings.tr("Реклама")), text(DkxStrings.tr("Автор")), text(DkxStrings.tr("Ссылка"))]]
    for post in report.posts {
        var row: [Cell] = []
        row.append(text(dkxXlsxDate(post.date)))
        row.append(text(post.kind.title))
        row.append(text(String(post.fullText.prefix(32000))))
        row.append(int(post.views))
        row.append(int(post.reactions))
        row.append(int(post.forwards))
        row.append(int(post.comments))
        row.append(int(post.paidStars))
        if let engagement = post.engagement {
            row.append(number(dkxRound(engagement)))
        } else {
            row.append(text(""))
        }
        if let ratio = report.ratio(post) {
            row.append(number(dkxRound(ratio)))
        } else {
            row.append(text(""))
        }
        if let impact = report.impacts[post.id] {
            row.append(number(dkxRound(impact.joined, 1)))
            row.append(number(dkxRound(impact.left, 1)))
        } else {
            row.append(text(""))
            row.append(text(""))
        }
        row.append(text(post.isAd ? yes : no))
        row.append(text(post.authorName ?? ""))
        row.append(text(dkxPostLink(post, username: username)))
        posts.append(row)
    }
    sheets.append(DkxXlsxSheet(name: report.isChannel ? DkxStrings.tr("Посты") : DkxStrings.tr("Сообщения"), rows: posts))

    func named(_ items: [DkxNamedCount], name: String, header: [String]) {
        guard !items.isEmpty else {
            return
        }
        var rows: [[Cell]] = [header.map { text($0) }]
        for item in items {
            rows.append([text(item.name), int(item.count)])
        }
        sheets.append(DkxXlsxSheet(name: name, rows: rows))
    }
    named(report.reactions, name: DkxStrings.tr("Реакции"), header: [DkxStrings.tr("Реакция"), DkxStrings.tr("Количество")])
    named(report.sources, name: DkxStrings.tr("Источники"), header: [DkxStrings.tr("Откуда репост"), DkxStrings.tr("Постов")])
    named(report.domains, name: DkxStrings.tr("Сайты"), header: [DkxStrings.tr("Сайт"), DkxStrings.tr("Постов со ссылкой")])
    if !report.isChannel {
        named(report.authors, name: DkxStrings.tr("Авторы"), header: [DkxStrings.tr("Автор"), DkxStrings.tr("Сообщений")])
    }

    if let admin = report.admin {
        var values: [[Cell]] = [[text(DkxStrings.tr("Показатель")), text(DkxStrings.tr("Сейчас")), text(DkxStrings.tr("Прошлый период"))]]
        values.append([text(DkxStrings.tr("Период Telegram")), text(dkxXlsxDate(admin.periodStart) + " - " + dkxXlsxDate(admin.periodEnd)), text("")])
        for value in admin.values {
            values.append([text(value.label), number(dkxRound(value.current)), number(dkxRound(value.previous))])
        }
        if let notifications = admin.notificationsPercent {
            values.append([text(DkxStrings.tr("Уведомления включены, %")), number(dkxRound(notifications)), text("")])
        }
        sheets.append(DkxXlsxSheet(name: "Telegram", rows: values))

        var sources: [[Cell]] = [[text(DkxStrings.tr("Раздел")), text(DkxStrings.tr("Название")), text(DkxStrings.tr("Значение"))]]
        for (section, items) in [(DkxStrings.tr("Откуда просмотры"), admin.viewsBySource), (admin.isChannel ? DkxStrings.tr("Откуда подписчики") : DkxStrings.tr("Откуда участники"), admin.followersBySource), (DkxStrings.tr("Языки"), admin.languages)] {
            for item in items {
                sources.append([text(section), text(item.name), int(item.count)])
            }
        }
        if sources.count > 1 {
            sheets.append(DkxXlsxSheet(name: DkxStrings.tr("Источники Telegram"), rows: sources))
        }
        var people: [[Cell]] = [[text(DkxStrings.tr("Раздел")), text(DkxStrings.tr("Имя")), text(DkxStrings.tr("Значение 1")), text(DkxStrings.tr("Значение 2")), text(DkxStrings.tr("Значение 3"))]]
        for item in admin.topPosters {
            people.append([text(DkxStrings.tr("Сообщений и символов в среднем")), text(item.name)] + item.values.map { int($0) })
        }
        for item in admin.topAdmins {
            people.append([text(DkxStrings.tr("Удалил, выгнал, ограничил")), text(item.name)] + item.values.map { int($0) })
        }
        for item in admin.topInviters {
            people.append([text(DkxStrings.tr("Пригласил")), text(item.name)] + item.values.map { int($0) })
        }
        if people.count > 1 {
            sheets.append(DkxXlsxSheet(name: DkxStrings.tr("Участники Telegram"), rows: people))
        }
    }
    return sheets
}

func dkxAnalyticsExport(context: AccountContext, report: DkxAnalyticsReport, peer: EnginePeer?, periodTitle: String, controller: DkxAnalyticsBaseController) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let title = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? ""
    let username = peer?.addressName
    let safeTitle = String(title.map { character -> Character in
        return "/\\:?*\"<>|".contains(character) ? "_" : character
    }.prefix(60))
    let fileName = DkxStrings.tr("Аналитика {} {}.xlsx", safeTitle, dkxXlsxDate(report.periodEnd, time: false))
    let path = NSTemporaryDirectory() + fileName
    let chatId = report.posts.first?.id.peerId.toInt64() ?? 0

    let _ = (Signal<Bool, NoError> { subscriber in
        let sheets = dkxAnalyticsSheets(report: report, title: title, username: username, periodTitle: periodTitle)
        subscriber.putNext(dkxWriteXlsx(sheets: sheets, to: path))
        subscriber.putCompletion()
        return EmptyDisposable
    }
    |> runOn(Queue.concurrentDefaultQueue())
    |> deliverOnMainQueue).start(next: { [weak controller] success in
        guard let controller else {
            return
        }
        guard success else {
            controller.showToast(DkxStrings.tr("Не удалось собрать таблицу"))
            return
        }
        let share = {
            let activityController = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
            context.sharedContext.applicationBindings.presentNativeController(activityController)
        }
        guard DkxRuntime.current.driveEnabled else {
            share()
            return
        }
        guard DkxGoogleDrive.isConnected else {
            controller.showToast(DkxStrings.tr("Сначала войдите в Google в настройках Dkx"))
            share()
            return
        }
        dkxDriveChooseAccount(context: context, present: { [weak controller] sheet, _ in
            controller?.present(sheet, in: .window(.root))
        }, completion: { [weak controller] accountId in
            DkxGoogleDriveUploadQueue.enqueue(DkxGoogleDriveUploadJob(fileName: fileName, mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", chatId: chatId, chatTitle: title, messageId: 0, force: true, accountId: accountId, prepare: .single(path), completion: { [weak controller] result, _ in
                switch result {
                case .uploaded, .duplicate:
                    controller?.showToast(DkxStrings.tr("Таблица загружена в Google Drive"))
                case .notConnected:
                    controller?.showToast(DkxStrings.tr("Сначала войдите в Google в настройках Dkx"))
                    share()
                case let .failed(reason):
                    controller?.showToast(DkxStrings.tr("Не удалось загрузить таблицу. {}", reason))
                case .cancelled:
                    break
                }
            }))
            controller?.showToast(DkxStrings.tr("Таблица в очереди на Google Drive, ход загрузки вверху экрана"))
        })
    })
}
