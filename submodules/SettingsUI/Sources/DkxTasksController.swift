import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import ItemListDatePickerItem

// «Мои дела». Один экран с тремя видами, как на одобренном превью. Лента
// дел по группам, день по часам и месяц сеткой с отмеченными днями. Вид
// меняется кнопкой сверху. Завершение дела через подтверждение, как просил
// владелец. Редактор на стандартных списках. Хранение и напоминания в DkxTasks.

// MARK: - Общее

private func dkxStartOfDay(_ date: Date) -> Date {
    return Calendar.current.startOfDay(for: date)
}

private func dkxDayStart(_ timestamp: Int32) -> Date {
    return dkxStartOfDay(Date(timeIntervalSince1970: Double(timestamp)))
}

private func dkxMonthStart(_ date: Date) -> Date {
    let components = Calendar.current.dateComponents([.year, .month], from: date)
    return Calendar.current.date(from: components) ?? dkxStartOfDay(date)
}

private func dkxAddDays(_ date: Date, _ days: Int) -> Date {
    return Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
}

private func dkxFormat(_ date: Date, _ format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = format
    return formatter.string(from: date)
}

private func dkxCapitalized(_ text: String) -> String {
    guard let first = text.first else {
        return text
    }
    return String(first).uppercased() + String(text.dropFirst())
}

private func dkxTasksCountText(_ count: Int) -> String {
    let mod10 = count % 10
    let mod100 = count % 100
    if mod10 == 1 && mod100 != 11 {
        return "\(count) дело"
    } else if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) {
        return "\(count) дела"
    }
    return "\(count) дел"
}

private func dkxRelativeDay(_ day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) {
        return "сегодня"
    } else if calendar.isDateInTomorrow(day) {
        return "завтра"
    } else if calendar.isDateInYesterday(day) {
        return "вчера"
    }
    return dkxFormat(day, "d MMMM, EE")
}

private func dkxTimeLabel(_ task: DkxTask) -> String {
    if task.date == 0 {
        return ""
    }
    if !task.hasTime {
        return "весь день"
    }
    return dkxFormat(Date(timeIntervalSince1970: Double(task.date)), "HH:mm")
}

private func dkxRemindTitle(_ remind: DkxTask.Remind) -> String {
    switch remind {
    case .none:
        return "Без напоминания"
    case .atTime:
        return "В момент дела"
    case .hourBefore:
        return "За час"
    case .twoHoursBefore:
        return "За 2 часа"
    case .dayBefore:
        return "За день"
    }
}

// Строка под названием. День, если группа его не называет, напоминание и
// начало заметки
private func dkxTaskMeta(_ task: DkxTask, showDay: Bool) -> String {
    var parts: [String] = []
    if showDay && task.date != 0 {
        parts.append(dkxRelativeDay(dkxDayStart(task.date)))
    }
    if task.remind != .none && !task.done {
        parts.append("напомнит " + dkxRemindTitle(task.remind).lowercased())
    }
    let note = task.note.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    if !note.isEmpty {
        parts.append(note.count > 60 ? String(note.prefix(60)) + "…" : note)
    }
    return parts.joined(separator: " · ")
}

// Незавершённые раньше завершённых, внутри по времени. Дело на весь день
// хранится полночью, поэтому встаёт первым в своём дне.
private func dkxSortedByTime(_ tasks: [DkxTask]) -> [DkxTask] {
    return tasks.sorted(by: { lhs, rhs in
        if lhs.done != rhs.done {
            return !lhs.done
        }
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        return lhs.createdAt < rhs.createdAt
    })
}

// MARK: - Элементы экрана

private final class DkxTaskCardView: UIView {
    private let highlightButton = UIButton(type: .custom)
    private let barView = UIView()
    private let checkButton = UIButton(type: .custom)
    private let checkCircle = UIView()
    private let checkMark = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let timeLabel = UILabel()
    private let onCheck: () -> Void
    private let onOpen: () -> Void

    init(task: DkxTask, meta: String, overdue: Bool, tinted: Bool, theme: PresentationTheme, onCheck: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.onCheck = onCheck
        self.onOpen = onOpen
        super.init(frame: CGRect())

        let list = theme.list
        let accent = list.itemAccentColor
        self.layer.cornerRadius = 14.0
        self.clipsToBounds = true
        self.backgroundColor = tinted ? accent.withAlphaComponent(0.14) : list.itemBlocksBackgroundColor

        self.highlightButton.addTarget(self, action: #selector(self.openPressed), for: .touchUpInside)
        self.highlightButton.addTarget(self, action: #selector(self.highlightOn), for: .touchDown)
        self.highlightButton.addTarget(self, action: #selector(self.highlightOff), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        self.addSubview(self.highlightButton)

        if overdue || tinted {
            self.barView.backgroundColor = overdue ? list.itemDestructiveColor : accent
            self.barView.isUserInteractionEnabled = false
            self.addSubview(self.barView)
        }

        self.checkCircle.isUserInteractionEnabled = false
        self.checkCircle.layer.cornerRadius = 12.0
        if task.done {
            self.checkCircle.backgroundColor = accent
        } else {
            self.checkCircle.layer.borderWidth = 1.5
            self.checkCircle.layer.borderColor = list.itemSecondaryTextColor.withAlphaComponent(0.6).cgColor
        }
        self.checkMark.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11.0, weight: .bold))
        self.checkMark.tintColor = .white
        self.checkMark.contentMode = .center
        self.checkMark.isHidden = !task.done
        self.checkCircle.addSubview(self.checkMark)
        self.checkButton.addSubview(self.checkCircle)
        self.checkButton.addTarget(self, action: #selector(self.checkPressed), for: .touchUpInside)
        self.addSubview(self.checkButton)

        let title = task.title.isEmpty ? "Без названия" : task.title
        if task.done {
            self.titleLabel.attributedText = NSAttributedString(string: title, attributes: [
                .font: UIFont.systemFont(ofSize: 16.0),
                .foregroundColor: list.itemSecondaryTextColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ])
        } else {
            self.titleLabel.font = UIFont.systemFont(ofSize: 16.0)
            self.titleLabel.textColor = list.itemPrimaryTextColor
            self.titleLabel.text = title
        }
        self.titleLabel.numberOfLines = 3
        self.addSubview(self.titleLabel)

        self.metaLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.metaLabel.textColor = list.itemSecondaryTextColor
        self.metaLabel.text = meta
        self.metaLabel.isHidden = meta.isEmpty
        self.addSubview(self.metaLabel)

        self.timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14.0, weight: .regular)
        self.timeLabel.textColor = overdue ? list.itemDestructiveColor : list.itemSecondaryTextColor
        self.timeLabel.text = dkxTimeLabel(task)
        self.addSubview(self.timeLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Раскладывает содержимое под ширину и возвращает высоту карточки
    func layout(width: CGFloat) -> CGFloat {
        let sideInset: CGFloat = 14.0
        let checkSize: CGFloat = 24.0
        let textX = sideInset + checkSize + 12.0
        let hasTime = !(self.timeLabel.text ?? "").isEmpty
        let timeSize = self.timeLabel.sizeThatFits(CGSize(width: 120.0, height: 30.0))
        let timeWidth: CGFloat = hasTime ? ceil(timeSize.width) : 0.0
        let textWidth = max(40.0, width - textX - sideInset - (hasTime ? timeWidth + 10.0 : 0.0))
        let titleHeight = ceil(self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: 200.0)).height)
        let metaHeight: CGFloat = self.metaLabel.isHidden ? 0.0 : ceil(self.metaLabel.sizeThatFits(CGSize(width: textWidth, height: 40.0)).height)
        let verticalInset: CGFloat = 11.0
        let contentHeight = titleHeight + (metaHeight > 0.0 ? 2.0 + metaHeight : 0.0)
        let height = max(48.0, contentHeight + verticalInset * 2.0)
        let textY = floor((height - contentHeight) / 2.0)

        self.highlightButton.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        self.barView.frame = CGRect(x: 0.0, y: 0.0, width: 3.0, height: height)
        self.checkButton.frame = CGRect(x: 0.0, y: 0.0, width: textX - 4.0, height: height)
        self.checkCircle.frame = CGRect(x: sideInset, y: floor((height - checkSize) / 2.0), width: checkSize, height: checkSize)
        self.checkMark.frame = CGRect(x: 0.0, y: 0.0, width: checkSize, height: checkSize)
        self.titleLabel.frame = CGRect(x: textX, y: textY, width: textWidth, height: titleHeight)
        self.metaLabel.frame = CGRect(x: textX, y: textY + titleHeight + 2.0, width: textWidth, height: metaHeight)
        self.timeLabel.frame = CGRect(x: width - sideInset - timeWidth, y: floor((height - timeSize.height) / 2.0), width: timeWidth, height: ceil(timeSize.height))
        return height
    }

    @objc private func openPressed() {
        self.onOpen()
    }

    @objc private func checkPressed() {
        self.onCheck()
    }

    @objc private func highlightOn() {
        self.alpha = 0.65
    }

    @objc private func highlightOff() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 1.0
        })
    }
}

// Кнопка-таблетка с текстом, значком или обоими
private final class DkxPillView: UIView {
    private let button = UIButton(type: .custom)
    private let label = UILabel()
    private let iconView = UIImageView()
    private let action: () -> Void

    init(title: String, iconName: String?, textColor: UIColor, fillColor: UIColor, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: CGRect())
        self.backgroundColor = fillColor
        self.layer.cornerRadius = 16.0
        self.label.text = title
        self.label.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
        self.label.textColor = textColor
        self.addSubview(self.label)
        if let iconName = iconName {
            self.iconView.image = UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold))
            self.iconView.tintColor = textColor
            self.iconView.contentMode = .center
            self.addSubview(self.iconView)
        }
        self.button.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
        self.addSubview(self.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Размер под содержимое при высоте 32
    func layoutContent() -> CGSize {
        let height: CGFloat = 32.0
        let hasTitle = !(self.label.text ?? "").isEmpty
        let hasIcon = self.iconView.image != nil
        let labelSize = self.label.sizeThatFits(CGSize(width: 240.0, height: height))
        let labelWidth: CGFloat = hasTitle ? ceil(labelSize.width) : 0.0
        let iconSize = self.iconView.image?.size ?? CGSize()
        let iconWidth: CGFloat = hasIcon ? ceil(iconSize.width) : 0.0
        let spacing: CGFloat = hasTitle && hasIcon ? 6.0 : 0.0
        let horizontal: CGFloat = hasTitle ? 12.0 : 10.0
        let width = max(height, labelWidth + spacing + iconWidth + horizontal * 2.0)
        let contentX = floor((width - labelWidth - spacing - iconWidth) / 2.0)
        self.label.frame = CGRect(x: contentX, y: floor((height - labelSize.height) / 2.0), width: labelWidth, height: ceil(labelSize.height))
        self.iconView.frame = CGRect(x: contentX + labelWidth + spacing, y: floor((height - iconSize.height) / 2.0), width: iconWidth, height: ceil(iconSize.height))
        self.button.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        return CGSize(width: width, height: height)
    }

    @objc private func pressed() {
        self.action()
    }
}

private enum DkxDayMarker {
    case empty
    case open
    case done
}

private final class DkxDayCellView: UIView {
    private let button = UIButton(type: .custom)
    private let selectionView = UIView()
    private let numberLabel = UILabel()
    private let dotView = UIView()
    private let action: () -> Void

    init(number: Int, isSelected: Bool, isToday: Bool, marker: DkxDayMarker, theme: PresentationTheme, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: CGRect())
        let accent = theme.list.itemAccentColor
        self.selectionView.backgroundColor = isSelected ? accent : .clear
        self.selectionView.layer.cornerRadius = 12.0
        self.selectionView.isUserInteractionEnabled = false
        self.addSubview(self.selectionView)

        self.numberLabel.text = "\(number)"
        self.numberLabel.textAlignment = .center
        self.numberLabel.font = UIFont.systemFont(ofSize: 16.0, weight: isSelected || isToday ? .bold : .regular)
        self.numberLabel.textColor = isSelected ? .white : (isToday ? accent : theme.list.itemPrimaryTextColor)
        self.addSubview(self.numberLabel)

        self.dotView.layer.cornerRadius = 2.5
        self.dotView.isUserInteractionEnabled = false
        switch marker {
        case .empty:
            self.dotView.backgroundColor = .clear
        case .open:
            self.dotView.backgroundColor = isSelected ? .white : accent
        case .done:
            self.dotView.backgroundColor = isSelected ? UIColor.white.withAlphaComponent(0.6) : theme.list.itemSecondaryTextColor.withAlphaComponent(0.5)
        }
        self.addSubview(self.dotView)

        self.button.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
        self.addSubview(self.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutContent() {
        let size = self.bounds.size
        let side = max(0.0, min(size.width - 4.0, size.height - 4.0))
        self.selectionView.frame = CGRect(x: floor((size.width - side) / 2.0), y: floor((size.height - side) / 2.0), width: side, height: side)
        self.numberLabel.frame = CGRect(x: 0.0, y: floor(size.height / 2.0) - 13.0, width: size.width, height: 20.0)
        self.dotView.frame = CGRect(x: floor((size.width - 5.0) / 2.0), y: floor(size.height / 2.0) + 9.0, width: 5.0, height: 5.0)
        self.button.frame = CGRect(origin: CGPoint(), size: size)
    }

    @objc private func pressed() {
        self.action()
    }
}

// MARK: - Экран

private enum DkxTasksView {
    case feed
    case day
    case month
}

// Вид, подпись на кнопке, название в выборе
private let dkxTasksViews: [(DkxTasksView, String, String)] = [
    (.feed, "Лента", "Лента дел"),
    (.day, "День", "День по часам"),
    (.month, "Месяц", "Месяц")
]

private struct DkxFeedGroup {
    let title: String
    let subtitle: String
    let color: UIColor
    let tasks: [DkxTask]
    let overdue: Bool
    let showDay: Bool
}

private struct DkxTasksLayout {
    let layout: ContainerViewLayout
    let topInset: CGFloat
}

private func dkxTasksNavigationBarData(_ presentationData: PresentationData) -> NavigationBarPresentationData {
    return NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: presentationData.theme, hideBackground: false, hideSeparator: false, edgeEffectColor: presentationData.theme.list.blocksBackgroundColor, style: .glass), strings: NavigationBarStrings(presentationStrings: presentationData.strings))
}

private final class DkxTasksCalendarController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var tasks = DkxTasks.defaultValue
    private var mode: DkxTasksView = .feed
    private var selectedDay: Date
    private var monthStart: Date
    private var currentLayout: DkxTasksLayout?
    private let scrollView = UIScrollView()
    private var contentViews: [UIView] = []
    private var hourOffsets: [Int: CGFloat] = [:]
    private var pendingHourScroll = false
    private var tasksDisposable: Disposable?
    private var presentationDataDisposable: Disposable?

    init(context: AccountContext) {
        self.context = context
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData
        let today = dkxStartOfDay(Date())
        self.selectedDay = today
        self.monthStart = dkxMonthStart(today)

        super.init(navigationBarPresentationData: dkxTasksNavigationBarData(presentationData))

        self._hasGlassStyle = true
        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.title = "Мои дела"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: PresentationResourcesRootController.navigationAddIcon(presentationData.theme), style: .plain, target: self, action: #selector(self.addPressed))

        self.tasksDisposable = (dkxTasksSignal(accountManager: context.sharedContext.accountManager)
        |> deliverOnMainQueue).start(next: { [weak self] tasks in
            guard let strongSelf = self else {
                return
            }
            strongSelf.tasks = tasks
            strongSelf.reload(resetOffset: false)
        })

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let strongSelf = self else {
                return
            }
            let previousTheme = strongSelf.presentationData.theme
            strongSelf.presentationData = presentationData
            if previousTheme !== presentationData.theme {
                strongSelf.setNavigationBarPresentationData(dkxTasksNavigationBarData(presentationData), animated: false)
                strongSelf.statusBar.updateStatusBarStyle(presentationData.theme.rootController.statusBarStyle.style, animated: true)
                strongSelf.navigationItem.rightBarButtonItem = UIBarButtonItem(image: PresentationResourcesRootController.navigationAddIcon(presentationData.theme), style: .plain, target: strongSelf, action: #selector(DkxTasksCalendarController.addPressed))
                strongSelf.reload(resetOffset: false)
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.tasksDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.displayNode.view.addSubview(self.scrollView)
        self.displayNodeDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Сутки могли смениться, пока экран был закрыт
        self.reload(resetOffset: false)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        let previous = self.currentLayout
        self.currentLayout = DkxTasksLayout(layout: layout, topInset: topInset)

        let bottomInset = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom) + 16.0
        self.scrollView.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0.0, bottom: bottomInset, right: 0.0)
        self.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0.0, bottom: bottomInset, right: 0.0)

        if let previous = previous {
            if previous.layout.size.width != layout.size.width || previous.topInset != topInset {
                self.reload(resetOffset: false)
            }
        } else {
            self.reload(resetOffset: true)
        }
    }

    // MARK: Сборка содержимого

    private func add(_ view: UIView) {
        self.scrollView.addSubview(view)
        self.contentViews.append(view)
    }

    private func reload(resetOffset: Bool) {
        guard self.isViewLoaded, let current = self.currentLayout else {
            return
        }
        let layout = current.layout
        for view in self.contentViews {
            view.removeFromSuperview()
        }
        self.contentViews.removeAll()
        self.hourOffsets = [:]
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor

        let sideInset: CGFloat = 16.0 + max(layout.safeInsets.left, layout.safeInsets.right)
        let width = max(100.0, layout.size.width - sideInset * 2.0)

        var y = self.layoutHeader(x: sideInset, top: 8.0, width: width)
        switch self.mode {
        case .feed:
            y = self.layoutFeed(x: sideInset, top: y, width: width)
        case .day:
            y = self.layoutDay(x: sideInset, top: y, width: width)
        case .month:
            y = self.layoutMonth(x: sideInset, top: y, width: width)
        }
        self.scrollView.contentSize = CGSize(width: layout.size.width, height: y)

        let minOffset = -current.topInset
        let maxOffset = max(minOffset, y + self.scrollView.contentInset.bottom - layout.size.height)
        if resetOffset {
            self.scrollView.contentOffset = CGPoint(x: 0.0, y: minOffset)
        }
        if self.pendingHourScroll && self.mode == .day {
            self.pendingHourScroll = false
            if let target = self.hourOffsets[self.scrollTargetHour()] {
                self.scrollView.contentOffset = CGPoint(x: 0.0, y: max(minOffset, min(maxOffset, target - current.topInset - 60.0)))
            }
        }
        if self.scrollView.contentOffset.y > maxOffset {
            self.scrollView.contentOffset = CGPoint(x: 0.0, y: maxOffset)
        }
    }

    // Час, к которому прокрутить день. Чуть раньше текущего или раннего дела
    private func scrollTargetHour() -> Int {
        let calendar = Calendar.current
        var hour = calendar.isDateInToday(self.selectedDay) ? max(0, calendar.component(.hour, from: Date()) - 1) : 8
        let dayStart = Int32(self.selectedDay.timeIntervalSince1970)
        let dayEnd = Int32(dkxAddDays(self.selectedDay, 1).timeIntervalSince1970)
        for task in self.tasks.items where task.hasTime && task.date >= dayStart && task.date < dayEnd {
            hour = min(hour, calendar.component(.hour, from: Date(timeIntervalSince1970: Double(task.date))))
        }
        return hour
    }

    private func subtitleText() -> String {
        switch self.mode {
        case .feed:
            let todayStart = Int32(dkxStartOfDay(Date()).timeIntervalSince1970)
            let tomorrowStart = Int32(dkxAddDays(dkxStartOfDay(Date()), 1).timeIntervalSince1970)
            let open = self.tasks.items.filter { !$0.done }
            let today = open.filter { $0.date >= todayStart && $0.date < tomorrowStart }.count
            let overdue = open.filter { $0.date != 0 && $0.date < todayStart }.count
            if today == 0 && overdue == 0 {
                return "на сегодня дел нет"
            }
            var parts: [String] = []
            if today > 0 {
                parts.append("\(today) сегодня")
            }
            if overdue > 0 {
                parts.append("\(overdue) просрочено")
            }
            return parts.joined(separator: ", ")
        case .day:
            return dkxRelativeDay(self.selectedDay)
        case .month:
            return dkxFormat(self.monthStart, "LLLL yyyy")
        }
    }

    private func layoutHeader(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let theme = self.presentationData.theme
        let modeTitle = dkxTasksViews.first(where: { $0.0 == self.mode })?.1 ?? ""
        let modePill = DkxPillView(title: modeTitle, iconName: "chevron.down", textColor: theme.list.itemPrimaryTextColor, fillColor: theme.list.itemBlocksBackgroundColor, action: { [weak self] in
            self?.openModePicker()
        })
        let modeSize = modePill.layoutContent()
        var right = x + width
        modePill.frame = CGRect(x: right - modeSize.width, y: top, width: modeSize.width, height: modeSize.height)
        self.add(modePill)
        right -= modeSize.width + 8.0

        let isAway = !Calendar.current.isDateInToday(self.selectedDay) || self.monthStart != dkxMonthStart(Date())
        if self.mode != .feed && isAway {
            let todayPill = DkxPillView(title: "Сегодня", iconName: nil, textColor: theme.list.itemAccentColor, fillColor: theme.list.itemBlocksBackgroundColor, action: { [weak self] in
                self?.jumpToToday()
            })
            let todaySize = todayPill.layoutContent()
            todayPill.frame = CGRect(x: right - todaySize.width, y: top, width: todaySize.width, height: todaySize.height)
            self.add(todayPill)
            right -= todaySize.width + 8.0
        }

        let subtitle = UILabel()
        subtitle.font = UIFont.systemFont(ofSize: 14.0)
        subtitle.textColor = theme.list.itemSecondaryTextColor
        subtitle.text = self.subtitleText()
        let subtitleHeight = ceil(subtitle.sizeThatFits(CGSize(width: 1000.0, height: 40.0)).height)
        subtitle.frame = CGRect(x: x + 4.0, y: top + floor((32.0 - subtitleHeight) / 2.0), width: max(0.0, right - x - 4.0), height: subtitleHeight)
        self.add(subtitle)
        return top + 32.0 + 16.0
    }

    private func addSectionTitle(_ title: String, subtitle: String, color: UIColor, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .bold)
        titleLabel.textColor = color
        titleLabel.text = title.uppercased()
        let titleSize = titleLabel.sizeThatFits(CGSize(width: width, height: 30.0))
        let titleHeight = ceil(titleSize.height)
        titleLabel.frame = CGRect(x: x + 4.0, y: top, width: min(width - 4.0, ceil(titleSize.width)), height: titleHeight)
        self.add(titleLabel)
        if !subtitle.isEmpty {
            let subtitleLabel = UILabel()
            subtitleLabel.font = UIFont.systemFont(ofSize: 13.0)
            subtitleLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
            subtitleLabel.text = subtitle
            let subtitleX = titleLabel.frame.maxX + 8.0
            subtitleLabel.frame = CGRect(x: subtitleX, y: top, width: max(0.0, x + width - subtitleX), height: titleHeight)
            self.add(subtitleLabel)
        }
        return top + titleHeight + 8.0
    }

    private func addHint(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14.0)
        label.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = text
        let labelWidth = max(0.0, width - 20.0)
        let height = ceil(label.sizeThatFits(CGSize(width: labelWidth, height: 400.0)).height)
        label.frame = CGRect(x: x + 10.0, y: top, width: labelWidth, height: height)
        self.add(label)
        return top + height
    }

    private func addCard(_ task: DkxTask, meta: String, overdue: Bool, tinted: Bool, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let card = DkxTaskCardView(task: task, meta: meta, overdue: overdue, tinted: tinted, theme: self.presentationData.theme, onCheck: { [weak self] in
            self?.toggleDone(task)
        }, onOpen: { [weak self] in
            self?.openTask(task)
        })
        let height = card.layout(width: width)
        card.frame = CGRect(x: x, y: top, width: width, height: height)
        self.add(card)
        return top + height
    }

    // Две стрелки и заголовок, для дня и месяца
    private func layoutStepper(title: String, x: CGFloat, top: CGFloat, width: CGFloat, previous: @escaping () -> Void, next: @escaping () -> Void) -> CGFloat {
        let theme = self.presentationData.theme
        let nextPill = DkxPillView(title: "", iconName: "chevron.right", textColor: theme.list.itemSecondaryTextColor, fillColor: theme.list.itemBlocksBackgroundColor, action: next)
        let previousPill = DkxPillView(title: "", iconName: "chevron.left", textColor: theme.list.itemSecondaryTextColor, fillColor: theme.list.itemBlocksBackgroundColor, action: previous)
        let nextSize = nextPill.layoutContent()
        let previousSize = previousPill.layoutContent()
        nextPill.frame = CGRect(x: x + width - nextSize.width, y: top, width: nextSize.width, height: nextSize.height)
        previousPill.frame = CGRect(x: nextPill.frame.minX - 8.0 - previousSize.width, y: top, width: previousSize.width, height: previousSize.height)

        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .bold)
        titleLabel.textColor = theme.list.itemPrimaryTextColor
        titleLabel.text = title
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        let titleHeight = ceil(titleLabel.sizeThatFits(CGSize(width: 1000.0, height: 40.0)).height)
        titleLabel.frame = CGRect(x: x + 4.0, y: top + floor((32.0 - titleHeight) / 2.0), width: max(0.0, previousPill.frame.minX - x - 12.0), height: titleHeight)

        self.add(titleLabel)
        self.add(previousPill)
        self.add(nextPill)
        return top + 32.0 + 14.0
    }

    private func layoutFeed(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let list = self.presentationData.theme.list
        let today = dkxStartOfDay(Date())
        let todayStart = Int32(today.timeIntervalSince1970)
        let tomorrowStart = Int32(dkxAddDays(today, 1).timeIntervalSince1970)
        let afterTomorrowStart = Int32(dkxAddDays(today, 2).timeIntervalSince1970)
        let weekEnd = Int32(dkxAddDays(today, 7).timeIntervalSince1970)

        let open = dkxSortedByTime(self.tasks.items.filter { !$0.done })
        let done = Array(self.tasks.items.filter { $0.done }.sorted(by: { $0.doneAt > $1.doneAt }).prefix(20))

        let groups: [DkxFeedGroup] = [
            DkxFeedGroup(title: "Просрочено", subtitle: "", color: list.itemDestructiveColor, tasks: open.filter { $0.date != 0 && $0.date < todayStart }, overdue: true, showDay: true),
            DkxFeedGroup(title: "Сегодня", subtitle: dkxFormat(today, "d MMMM"), color: list.itemAccentColor, tasks: open.filter { $0.date >= todayStart && $0.date < tomorrowStart }, overdue: false, showDay: false),
            DkxFeedGroup(title: "Завтра", subtitle: dkxFormat(dkxAddDays(today, 1), "d MMMM"), color: list.itemSecondaryTextColor, tasks: open.filter { $0.date >= tomorrowStart && $0.date < afterTomorrowStart }, overdue: false, showDay: false),
            DkxFeedGroup(title: "На неделе", subtitle: "", color: list.itemSecondaryTextColor, tasks: open.filter { $0.date >= afterTomorrowStart && $0.date < weekEnd }, overdue: false, showDay: true),
            DkxFeedGroup(title: "Позже", subtitle: "", color: list.itemSecondaryTextColor, tasks: open.filter { $0.date >= weekEnd }, overdue: false, showDay: true),
            DkxFeedGroup(title: "Без даты", subtitle: "", color: list.itemSecondaryTextColor, tasks: open.filter { $0.date == 0 }, overdue: false, showDay: false),
            DkxFeedGroup(title: "Выполнено", subtitle: "последние", color: list.itemSecondaryTextColor, tasks: done, overdue: false, showDay: true)
        ]

        var y = top
        var shown = false
        for group in groups where !group.tasks.isEmpty {
            shown = true
            y = self.addSectionTitle(group.title, subtitle: group.subtitle, color: group.color, x: x, top: y, width: width)
            for task in group.tasks {
                y = self.addCard(task, meta: dkxTaskMeta(task, showDay: group.showDay), overdue: group.overdue, tinted: false, x: x, top: y, width: width) + 7.0
            }
            y += 14.0
        }
        if !shown {
            y = self.addHint("Дел пока нет. Нажмите плюс вверху, чтобы добавить первое.", x: x, top: y + 40.0, width: width)
        }
        return y
    }

    private func layoutDay(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let theme = self.presentationData.theme
        let calendar = Calendar.current
        var y = self.layoutStepper(title: dkxCapitalized(dkxFormat(self.selectedDay, "EEEE, d MMMM")), x: x, top: top, width: width, previous: { [weak self] in
            self?.shiftDay(-1)
        }, next: { [weak self] in
            self?.shiftDay(1)
        })

        let dayStart = Int32(self.selectedDay.timeIntervalSince1970)
        let dayEnd = Int32(dkxAddDays(self.selectedDay, 1).timeIntervalSince1970)
        let dayTasks = dkxSortedByTime(self.tasks.items.filter { $0.date >= dayStart && $0.date < dayEnd })

        let allDay = dayTasks.filter { !$0.hasTime }
        if !allDay.isEmpty {
            y = self.addSectionTitle("Весь день", subtitle: "", color: theme.list.itemSecondaryTextColor, x: x, top: y, width: width)
            for task in allDay {
                y = self.addCard(task, meta: dkxTaskMeta(task, showDay: false), overdue: false, tinted: false, x: x, top: y, width: width) + 7.0
            }
            y += 10.0
        }
        y += 8.0

        let isToday = calendar.isDateInToday(self.selectedDay)
        let now = Date()
        let nowHour = calendar.component(.hour, from: now)
        let nowMinute = calendar.component(.minute, from: now)
        let labelWidth: CGFloat = 44.0
        let contentX = x + labelWidth + 8.0
        let contentWidth = max(40.0, width - labelWidth - 8.0)
        let rowHeight: CGFloat = 44.0
        var offsets: [Int: CGFloat] = [:]

        for hour in 0 ..< 24 {
            let items = dayTasks.filter { $0.hasTime && calendar.component(.hour, from: Date(timeIntervalSince1970: Double($0.date))) == hour }
            let rowTop = y
            offsets[hour] = rowTop

            let line = UIView()
            line.backgroundColor = theme.list.itemBlocksSeparatorColor
            line.frame = CGRect(x: contentX, y: rowTop, width: contentWidth, height: UIScreenPixel)
            self.add(line)

            let label = UILabel()
            label.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)
            label.textColor = items.isEmpty ? theme.list.itemSecondaryTextColor.withAlphaComponent(0.5) : theme.list.itemPrimaryTextColor
            label.text = hour < 10 ? "0\(hour):00" : "\(hour):00"
            label.textAlignment = .right
            label.frame = CGRect(x: x, y: rowTop - 7.0, width: labelWidth, height: 14.0)
            self.add(label)

            var rowY = rowTop + 6.0
            for task in items {
                rowY = self.addCard(task, meta: dkxTaskMeta(task, showDay: false), overdue: false, tinted: !task.done, x: contentX, top: rowY, width: contentWidth) + 6.0
            }
            var rowBottom = max(rowTop + rowHeight, rowY + 4.0)
            if isToday && hour == nowHour {
                let markerY = items.isEmpty ? rowTop + floor(rowHeight * CGFloat(nowMinute) / 60.0) : rowY
                rowBottom = max(rowBottom, markerY + 12.0)
                self.addNowMarker(x: contentX, y: markerY, width: contentWidth)
            }
            y = rowBottom
        }
        self.hourOffsets = offsets
        return y + 8.0
    }

    private func addNowMarker(x: CGFloat, y: CGFloat, width: CGFloat) {
        let color = self.presentationData.theme.list.itemDestructiveColor
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
        label.textColor = color
        label.text = "сейчас"
        let labelSize = label.sizeThatFits(CGSize(width: 100.0, height: 20.0))
        label.frame = CGRect(x: x + width - ceil(labelSize.width), y: y - floor(labelSize.height / 2.0), width: ceil(labelSize.width), height: ceil(labelSize.height))

        let line = UIView(frame: CGRect(x: x, y: y - 0.75, width: max(0.0, width - ceil(labelSize.width) - 6.0), height: 1.5))
        line.backgroundColor = color.withAlphaComponent(0.6)
        line.isUserInteractionEnabled = false

        let dot = UIView(frame: CGRect(x: x - 3.5, y: y - 3.5, width: 7.0, height: 7.0))
        dot.backgroundColor = color
        dot.layer.cornerRadius = 3.5
        dot.isUserInteractionEnabled = false

        self.add(line)
        self.add(dot)
        self.add(label)
    }

    private func layoutMonth(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let theme = self.presentationData.theme
        let calendar = Calendar.current
        var y = self.layoutStepper(title: dkxCapitalized(dkxFormat(self.monthStart, "LLLL yyyy")), x: x, top: top, width: width, previous: { [weak self] in
            self?.shiftMonth(-1)
        }, next: { [weak self] in
            self?.shiftMonth(1)
        })

        let columnWidth = floor(width / 7.0)
        let gridX = x + floor((width - columnWidth * 7.0) / 2.0)
        let weekdays = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
        for (index, name) in weekdays.enumerated() {
            let label = UILabel()
            label.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
            label.textColor = theme.list.itemSecondaryTextColor
            label.textAlignment = .center
            label.text = name.uppercased()
            label.frame = CGRect(x: gridX + CGFloat(index) * columnWidth, y: y, width: columnWidth, height: 16.0)
            self.add(label)
        }
        y += 22.0

        // Неделя с понедельника. У Calendar weekday 1 это воскресенье, 2 понедельник
        let leading = (calendar.component(.weekday, from: self.monthStart) + 5) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: self.monthStart)?.count ?? 30
        let monthStartStamp = Int32(self.monthStart.timeIntervalSince1970)
        let monthEndStamp = Int32(dkxAddDays(self.monthStart, dayCount).timeIntervalSince1970)
        var openDays = Set<Int>()
        var doneDays = Set<Int>()
        for task in self.tasks.items where task.date >= monthStartStamp && task.date < monthEndStamp {
            let day = calendar.component(.day, from: Date(timeIntervalSince1970: Double(task.date)))
            if task.done {
                doneDays.insert(day)
            } else {
                openDays.insert(day)
            }
        }
        let selectedNumber: Int? = dkxMonthStart(self.selectedDay) == self.monthStart ? calendar.component(.day, from: self.selectedDay) : nil
        let todayNumber: Int? = dkxMonthStart(Date()) == self.monthStart ? calendar.component(.day, from: Date()) : nil
        let cellHeight: CGFloat = 46.0
        let rows = (leading + dayCount + 6) / 7

        for day in 1 ... dayCount {
            let position = leading + day - 1
            let marker: DkxDayMarker = openDays.contains(day) ? .open : (doneDays.contains(day) ? .done : .empty)
            let cell = DkxDayCellView(number: day, isSelected: day == selectedNumber, isToday: day == todayNumber, marker: marker, theme: theme, action: { [weak self] in
                self?.selectDayInMonth(day)
            })
            cell.frame = CGRect(x: gridX + CGFloat(position % 7) * columnWidth, y: y + CGFloat(position / 7) * cellHeight, width: columnWidth, height: cellHeight)
            cell.layoutContent()
            self.add(cell)
        }
        y += CGFloat(rows) * cellHeight + 18.0

        let dayStart = Int32(self.selectedDay.timeIntervalSince1970)
        let dayEnd = Int32(dkxAddDays(self.selectedDay, 1).timeIntervalSince1970)
        let dayTasks = dkxSortedByTime(self.tasks.items.filter { $0.date >= dayStart && $0.date < dayEnd })
        y = self.addSectionTitle(dkxFormat(self.selectedDay, "d MMMM, EEEE"), subtitle: dayTasks.isEmpty ? "дел нет" : dkxTasksCountText(dayTasks.count), color: theme.list.itemPrimaryTextColor, x: x, top: y, width: width)
        for task in dayTasks {
            y = self.addCard(task, meta: dkxTaskMeta(task, showDay: false), overdue: false, tinted: false, x: x, top: y, width: width) + 7.0
        }
        if dayTasks.isEmpty {
            y = self.addHint("Нажмите плюс вверху, чтобы добавить дело на этот день.", x: x, top: y + 8.0, width: width)
        }
        return y + 8.0
    }

    // MARK: Действия

    private func setMode(_ mode: DkxTasksView) {
        guard mode != self.mode else {
            return
        }
        self.mode = mode
        self.pendingHourScroll = mode == .day
        self.reload(resetOffset: true)
    }

    private func openModePicker() {
        let actionSheet = ActionSheetController(presentationData: self.presentationData)
        var items: [ActionSheetItem] = []
        for (mode, _, title) in dkxTasksViews {
            items.append(ActionSheetCheckboxItem(title: title, label: "", value: mode == self.mode, action: { [weak self, weak actionSheet] _ in
                actionSheet?.dismissAnimated()
                self?.setMode(mode)
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
    }

    private func shiftDay(_ delta: Int) {
        self.selectedDay = dkxStartOfDay(dkxAddDays(self.selectedDay, delta))
        self.monthStart = dkxMonthStart(self.selectedDay)
        self.reload(resetOffset: false)
    }

    private func shiftMonth(_ delta: Int) {
        let shifted = Calendar.current.date(byAdding: .month, value: delta, to: self.monthStart) ?? self.monthStart
        self.monthStart = dkxMonthStart(shifted)
        let today = dkxStartOfDay(Date())
        self.selectedDay = dkxMonthStart(today) == self.monthStart ? today : self.monthStart
        self.reload(resetOffset: false)
    }

    private func selectDayInMonth(_ day: Int) {
        self.selectedDay = dkxStartOfDay(dkxAddDays(self.monthStart, day - 1))
        self.reload(resetOffset: false)
    }

    private func jumpToToday() {
        let today = dkxStartOfDay(Date())
        self.selectedDay = today
        self.monthStart = dkxMonthStart(today)
        self.pendingHourScroll = self.mode == .day
        self.reload(resetOffset: false)
    }

    @objc private func addPressed() {
        let date = self.mode == .feed ? Date() : self.selectedDay
        self.push(dkxTaskEditController(context: self.context, task: nil, suggestedDate: Int32(date.timeIntervalSince1970)))
    }

    private func openTask(_ task: DkxTask) {
        let current = self.tasks.items.first(where: { $0.id == task.id }) ?? task
        self.push(dkxTaskEditController(context: self.context, task: current, suggestedDate: current.date))
    }

    private func store(_ task: DkxTask) {
        let _ = updateDkxTasksInteractively(accountManager: self.context.sharedContext.accountManager, { current in
            var updated = current
            if let index = updated.items.firstIndex(where: { $0.id == task.id }) {
                updated.items[index] = task
            }
            return updated
        }).start()
    }

    // Снять отметку можно сразу, а завершение только через подтверждение
    private func toggleDone(_ task: DkxTask) {
        let current = self.tasks.items.first(where: { $0.id == task.id }) ?? task
        if current.done {
            var updated = current
            updated.done = false
            updated.doneAt = 0
            self.store(updated)
            return
        }
        let alert = textAlertController(context: self.context, title: "Завершить дело?", text: current.title, actions: [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .defaultAction, title: "Завершить", action: { [weak self] in
                var updated = current
                updated.done = true
                updated.doneAt = Int32(Date().timeIntervalSince1970)
                self?.store(updated)
            })
        ])
        self.present(alert, in: .window(.root))
    }
}

public func dkxTasksController(context: AccountContext) -> ViewController {
    return DkxTasksCalendarController(context: context)
}

// MARK: - Редактор

private final class DkxTaskEditArguments {
    let updateTitle: (String) -> Void
    let updateNote: (String) -> Void
    let updateDate: (Int32) -> Void
    let toggleDateSelection: () -> Void
    let toggleTimeSelection: () -> Void
    let updateAllDay: (Bool) -> Void
    let updateRemind: (DkxTask.Remind) -> Void
    let openChat: () -> Void
    let complete: () -> Void
    let reopen: () -> Void
    let delete: () -> Void

    init(updateTitle: @escaping (String) -> Void, updateNote: @escaping (String) -> Void, updateDate: @escaping (Int32) -> Void, toggleDateSelection: @escaping () -> Void, toggleTimeSelection: @escaping () -> Void, updateAllDay: @escaping (Bool) -> Void, updateRemind: @escaping (DkxTask.Remind) -> Void, openChat: @escaping () -> Void, complete: @escaping () -> Void, reopen: @escaping () -> Void, delete: @escaping () -> Void) {
        self.updateTitle = updateTitle
        self.updateNote = updateNote
        self.updateDate = updateDate
        self.toggleDateSelection = toggleDateSelection
        self.toggleTimeSelection = toggleTimeSelection
        self.updateAllDay = updateAllDay
        self.updateRemind = updateRemind
        self.openChat = openChat
        self.complete = complete
        self.reopen = reopen
        self.delete = delete
    }
}

private let dkxRemindOptions: [DkxTask.Remind] = [.none, .atTime, .hourBefore, .twoHoursBefore, .dayBefore]

private enum DkxTaskEditEntry: ItemListNodeEntry {
    case title(String)
    case note(String)
    case whenHeader
    case allDay(Bool)
    case date(PresentationDateTimeFormat, Int32, Bool, Bool, Bool)
    case remindHeader
    case remind(Int32, String, Bool)
    case openChat
    case complete
    case reopen
    case delete

    var section: ItemListSectionId {
        switch self {
        case .title, .note:
            return 0
        case .whenHeader, .allDay, .date:
            return 1
        case .remindHeader, .remind:
            return 2
        case .openChat, .complete, .reopen:
            return 3
        case .delete:
            return 4
        }
    }

    var stableId: Int32 {
        switch self {
        case .title:
            return 0
        case .note:
            return 1
        case .whenHeader:
            return 10
        case .allDay:
            return 11
        case .date:
            return 12
        case .remindHeader:
            return 20
        case let .remind(index, _, _):
            return 21 + index
        case .openChat:
            return 35
        case .complete:
            return 40
        case .reopen:
            return 41
        case .delete:
            return 50
        }
    }

    static func <(lhs: DkxTaskEditEntry, rhs: DkxTaskEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DkxTaskEditArguments
        switch self {
        case let .title(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: "Что сделать", type: .regular(capitalization: true, autocorrection: true), sectionId: self.section, textUpdated: { value in
                arguments.updateTitle(value)
            }, action: {})
        case let .note(text):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Заметка, необязательно", maxLength: nil, sectionId: self.section, style: .blocks, minimalHeight: 60.0, textUpdated: { value in
                arguments.updateNote(value)
            })
        case .whenHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "КОГДА", sectionId: self.section)
        case let .allDay(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Весь день", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAllDay(value)
            })
        case let .date(dateTimeFormat, date, hasTime, displayingDate, displayingTime):
            // У дела на весь день выбора времени нет
            var toggleTime: (() -> Void)?
            if hasTime {
                toggleTime = {
                    arguments.toggleTimeSelection()
                }
            }
            return ItemListDatePickerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: dateTimeFormat, date: date, title: hasTime ? "Дата и время" : "Дата", displayingDateSelection: displayingDate, displayingTimeSelection: displayingTime, sectionId: self.section, style: .blocks, toggleDateSelection: {
                arguments.toggleDateSelection()
            }, toggleTimeSelection: toggleTime, updated: { value in
                arguments.updateDate(value)
            })
        case .remindHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "НАПОМНИТЬ", sectionId: self.section)
        case let .remind(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateRemind(dkxRemindOptions[Int(index)])
            })
        case .openChat:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Открыть чат", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openChat()
            })
        case .complete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Завершить дело", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.complete()
            })
        case .reopen:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Вернуть в работу", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reopen()
            })
        case .delete:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Удалить дело", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.delete()
            })
        }
    }
}

private struct DkxTaskEditState: Equatable {
    var task: DkxTask
    var displayingDateSelection = false
    var displayingTimeSelection = false
}

// task равен nil для нового дела
private func dkxTaskEditController(context: AccountContext, task: DkxTask?, suggestedDate: Int32) -> ViewController {
    let isNew = task == nil
    let now = Int32(Date().timeIntervalSince1970)
    // Новое дело по умолчанию на ближайший целый час выбранного дня
    let initialTask: DkxTask
    if let task = task {
        initialTask = task
    } else {
        let base = Date(timeIntervalSince1970: Double(suggestedDate))
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        let nowComponents = calendar.dateComponents([.hour], from: Date())
        components.hour = min(23, (nowComponents.hour ?? 9) + 1)
        components.minute = 0
        let date = calendar.date(from: components) ?? base
        initialTask = DkxTask(id: DkxTask.newId(), title: "", note: "", date: Int32(date.timeIntervalSince1970), hasTime: true, remind: .atTime, done: false, doneAt: 0, createdAt: now)
    }

    let statePromise = ValuePromise(DkxTaskEditState(task: initialTask), ignoreRepeated: true)
    let stateValue = Atomic(value: DkxTaskEditState(task: initialTask))
    let updateState: ((DkxTaskEditState) -> DkxTaskEditState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    let updateTask: (@escaping (inout DkxTask) -> Void) -> Void = { f in
        updateState { current in
            var updated = current
            f(&updated.task)
            return updated
        }
    }

    var dismissImpl: (() -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?
    let accountManager = context.sharedContext.accountManager

    let store: (DkxTask) -> Void = { task in
        let _ = updateDkxTasksInteractively(accountManager: accountManager, { current in
            var updated = current
            if let index = updated.items.firstIndex(where: { $0.id == task.id }) {
                updated.items[index] = task
            } else {
                updated.items.append(task)
            }
            return updated
        }).start()
    }

    let arguments = DkxTaskEditArguments(updateTitle: { value in
        updateTask { $0.title = value }
    }, updateNote: { value in
        updateTask { $0.note = value }
    }, updateDate: { value in
        updateTask { task in
            if task.hasTime {
                task.date = value
            } else {
                task.date = Int32(dkxStartOfDay(Date(timeIntervalSince1970: Double(value))).timeIntervalSince1970)
            }
        }
    }, toggleDateSelection: {
        updateState { current in
            var updated = current
            updated.displayingDateSelection = !updated.displayingDateSelection
            if updated.displayingDateSelection {
                updated.displayingTimeSelection = false
            }
            return updated
        }
    }, toggleTimeSelection: {
        updateState { current in
            var updated = current
            updated.displayingTimeSelection = !updated.displayingTimeSelection
            if updated.displayingTimeSelection {
                updated.displayingDateSelection = false
            }
            return updated
        }
    }, updateAllDay: { value in
        updateTask { task in
            task.hasTime = !value
            if value {
                task.date = Int32(dkxStartOfDay(Date(timeIntervalSince1970: Double(task.date))).timeIntervalSince1970)
            } else {
                task.date += 9 * 3600
            }
        }
    }, updateRemind: { value in
        updateTask { $0.remind = value }
    }, openChat: {
        let task = stateValue.with { $0 }.task
        guard task.isLinked else {
            return
        }
        let peerId = EnginePeer.Id(task.peerId)
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer = peer, let navigationController = navigationControllerImpl?() else {
                return
            }
            var subject: ChatControllerSubject?
            if task.messageId != 0 {
                subject = .message(id: .id(EngineMessage.Id(peerId: peerId, namespace: task.messageNamespace, id: task.messageId)), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false)
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: subject, keepStack: .always))
        })
    }, complete: {
        // Подтверждение перед завершением, как просил владелец
        let title = stateValue.with { $0 }.task.title
        presentControllerImpl?(textAlertController(context: context, title: "Завершить дело?", text: title, actions: [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .defaultAction, title: "Завершить", action: {
                var task = stateValue.with { $0 }.task
                task.done = true
                task.doneAt = Int32(Date().timeIntervalSince1970)
                store(task)
                dismissImpl?()
            })
        ]))
    }, reopen: {
        var task = stateValue.with { $0 }.task
        task.done = false
        task.doneAt = 0
        store(task)
        dismissImpl?()
    }, delete: {
        let title = stateValue.with { $0 }.task.title
        presentControllerImpl?(textAlertController(context: context, title: "Удалить дело?", text: title, actions: [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                let id = stateValue.with { $0 }.task.id
                let _ = updateDkxTasksInteractively(accountManager: accountManager, { current in
                    var updated = current
                    updated.items.removeAll(where: { $0.id == id })
                    return updated
                }).start()
                dismissImpl?()
            })
        ]))
    })

    // Поля ввода рисуются из начальных значений, иначе каждая клавиша
    // перерисовывала бы ячейку и курсор прыгал бы в конец
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DkxTaskEditEntry] = [.title(initialTask.title), .note(initialTask.note), .whenHeader, .allDay(!state.task.hasTime), .date(presentationData.dateTimeFormat, state.task.date, state.task.hasTime, state.displayingDateSelection, state.displayingTimeSelection), .remindHeader]
        for (index, option) in dkxRemindOptions.enumerated() {
            entries.append(.remind(Int32(index), dkxRemindTitle(option), option == state.task.remind))
        }
        // Чат открываем только из того аккаунта, где ставили напоминание
        if state.task.isLinked && (state.task.accountId == 0 || state.task.accountId == context.account.id.int64) {
            entries.append(.openChat)
        }
        if !isNew {
            entries.append(state.task.done ? .reopen : .complete)
            entries.append(.delete)
        }

        let canSave = !state.task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rightButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: canSave, action: {
            var task = stateValue.with { $0 }.task
            task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            task.note = task.note.trimmingCharacters(in: .whitespacesAndNewlines)
            store(task)
            dismissImpl?()
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isNew ? "Новое дело" : "Дело"), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}
