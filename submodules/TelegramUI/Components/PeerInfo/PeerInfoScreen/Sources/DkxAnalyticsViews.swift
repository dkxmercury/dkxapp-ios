import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import TelegramUIPreferences
import UndoUI

struct DkxAnalyticsColors {
    let background: UIColor
    let card: UIColor
    let primary: UIColor
    let secondary: UIColor
    let accent: UIColor
    let separator: UIColor
    let track: UIColor
    let green: UIColor
    let red: UIColor
    let orange: UIColor
    let chip: UIColor
    let chevron: UIColor

    init(theme: PresentationTheme) {
        let dark = theme.overallDarkAppearance
        self.background = theme.list.blocksBackgroundColor
        self.card = theme.list.itemBlocksBackgroundColor
        self.primary = theme.list.itemPrimaryTextColor
        self.secondary = theme.list.itemSecondaryTextColor
        self.accent = theme.list.itemAccentColor
        self.separator = theme.list.itemBlocksSeparatorColor
        self.track = dark ? UIColor(rgb: 0x2c2c2e) : UIColor(rgb: 0xe5e5ea)
        self.green = dark ? UIColor(rgb: 0x30d158) : UIColor(rgb: 0x28a745)
        self.red = dark ? UIColor(rgb: 0xff6961) : UIColor(rgb: 0xe5352b)
        self.orange = UIColor(rgb: 0xf7a23e)
        self.chip = dark ? UIColor(rgb: 0x2c2c2e) : UIColor(rgb: 0xe5e5ea)
        self.chevron = dark ? UIColor(rgb: 0x5a5a5e) : UIColor(rgb: 0xc4c4c7)
    }
}

private var dkxAnFormatters: [String: NumberFormatter] = [:]

private func dkxAnFormatter(_ digits: Int) -> NumberFormatter {
    let locale = DkxStrings.locale
    let key = "\(locale.identifier)|\(digits)"
    if let formatter = dkxAnFormatters[key] {
        return formatter
    }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits
    dkxAnFormatters[key] = formatter
    return formatter
}

func dkxAnNumber(_ value: Int) -> String {
    return dkxAnFormatter(0).string(from: NSNumber(value: value)) ?? "\(value)"
}

func dkxAnDecimal(_ value: Double, digits: Int = 1) -> String {
    return dkxAnFormatter(digits).string(from: NSNumber(value: value)) ?? "\(value)"
}

func dkxAnPercent(_ value: Double) -> String {
    return dkxAnDecimal(value, digits: 1) + "%"
}

let dkxAnMinus = "\u{2212}"

func dkxAnSignedNumber(_ value: Int) -> String {
    if value > 0 {
        return "+" + dkxAnNumber(value)
    } else if value < 0 {
        return dkxAnMinus + dkxAnNumber(-value)
    }
    return "0"
}

func dkxAnSignedPercent(_ value: Double, digits: Int = 0) -> String {
    let scale = pow(10.0, Double(digits))
    let rounded = (value * scale).rounded() / scale
    if rounded > 0.0 {
        return "+" + dkxAnDecimal(rounded, digits: digits) + "%"
    } else if rounded < 0.0 {
        return dkxAnMinus + dkxAnDecimal(-rounded, digits: digits) + "%"
    }
    return "0%"
}

func dkxAnRatio(_ value: Double) -> String {
    return "\u{00D7}" + dkxAnDecimal(value, digits: 1)
}

func dkxAnHour(_ hour: Int) -> String {
    return String(format: "%02d:00", (hour % 24 + 24) % 24)
}

func dkxAnWeekdayShort(_ index: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = DkxStrings.locale
    let symbols: [String] = formatter.shortStandaloneWeekdaySymbols ?? []
    guard symbols.count == 7 else {
        return "\(index + 1)"
    }
    return symbols[(index + 1) % 7].replacingOccurrences(of: ".", with: "")
}

func dkxAnDate(_ timestamp: Int32, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = DkxStrings.locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
}

func dkxAnalyticsNavigationBarData(_ presentationData: PresentationData) -> NavigationBarPresentationData {
    return NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: presentationData.theme, hideBackground: false, hideSeparator: false, edgeEffectColor: presentationData.theme.list.blocksBackgroundColor, style: .glass), strings: NavigationBarStrings(presentationStrings: presentationData.strings))
}

func dkxAnLabel(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor, lines: Int = 1, alignment: NSTextAlignment = .left) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFont.systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.numberOfLines = lines
    label.textAlignment = alignment
    label.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
    return label
}

// Ставит подпись в точку и возвращает её высоту
@discardableResult
func dkxAnPlace(_ label: UILabel, in parent: UIView, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
    let size = label.sizeThatFits(CGSize(width: width, height: 10000.0))
    let height = ceil(size.height)
    label.frame = CGRect(x: x, y: y, width: width, height: height)
    parent.addSubview(label)
    return height
}

func dkxAnTextWidth(_ label: UILabel, limit: CGFloat = 1000.0) -> CGFloat {
    return min(limit, ceil(label.sizeThatFits(CGSize(width: limit, height: 100.0)).width))
}

// Цветной бейдж, как у изменений в плитках макета
func dkxAnBadge(_ text: String, color: UIColor) -> UIView {
    let badge = UIView()
    badge.backgroundColor = color.withAlphaComponent(0.15)
    badge.layer.cornerRadius = 10.0
    let label = dkxAnLabel(text, size: 12.0, weight: .semibold, color: color, alignment: .center)
    let width = dkxAnTextWidth(label, limit: 240.0) + 16.0
    badge.frame = CGRect(x: 0.0, y: 0.0, width: width, height: 21.0)
    label.frame = badge.bounds
    badge.addSubview(label)
    return badge
}

func dkxAnSymbol(_ name: String, size: CGFloat, weight: UIImage.SymbolWeight = .semibold, color: UIColor) -> UIImageView {
    let view = UIImageView(image: UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))?.withRenderingMode(.alwaysTemplate))
    view.tintColor = color
    view.contentMode = .center
    return view
}

final class DkxAnTapView: UIControl {
    var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }

    @objc private func pressed() {
        self.action?()
    }
}

final class DkxAnBarView: UIView {
    private let fill = UIView()
    var fraction: CGFloat = 0.0 {
        didSet {
            self.setNeedsLayout()
        }
    }
    // Шкала от середины, влево минус, вправо плюс
    var centered = false {
        didSet {
            self.setNeedsLayout()
        }
    }

    init(track: UIColor, color: UIColor) {
        super.init(frame: CGRect())
        self.backgroundColor = track
        self.clipsToBounds = true
        self.fill.backgroundColor = color
        self.addSubview(self.fill)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        self.layer.cornerRadius = bounds.height / 2.0
        self.fill.layer.cornerRadius = bounds.height / 2.0
        let value = max(-1.0, min(1.0, self.fraction))
        if self.centered {
            let half = bounds.width / 2.0
            let width = abs(value) * half
            self.fill.frame = CGRect(x: value >= 0.0 ? half : half - width, y: 0.0, width: width, height: bounds.height)
        } else {
            self.fill.frame = CGRect(x: 0.0, y: 0.0, width: max(0.0, value) * bounds.width, height: bounds.height)
        }
    }
}

final class DkxAnLineChartView: UIView {
    private let fillLayer = CAGradientLayer()
    private let fillMask = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let averageLayer = CAShapeLayer()
    private let peakLayer = CAShapeLayer()
    private let markerLayer = CAShapeLayer()

    var values: [Double] = [] {
        didSet {
            self.setNeedsLayout()
        }
    }
    var marker: Int?
    var showAverage = true
    var markPeak = true
    var showFill = true
    var lineWidth: CGFloat = 2.4 {
        didSet {
            self.lineLayer.lineWidth = self.lineWidth
        }
    }

    init(color: UIColor, guide: UIColor, background: UIColor) {
        super.init(frame: CGRect())
        self.isUserInteractionEnabled = false
        self.fillLayer.colors = [color.withAlphaComponent(0.45).cgColor, color.withAlphaComponent(0.0).cgColor]
        self.fillLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.fillLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.fillLayer.mask = self.fillMask
        self.lineLayer.strokeColor = color.cgColor
        self.lineLayer.fillColor = UIColor.clear.cgColor
        self.lineLayer.lineWidth = self.lineWidth
        self.lineLayer.lineJoin = .round
        self.lineLayer.lineCap = .round
        self.averageLayer.strokeColor = guide.cgColor
        self.averageLayer.lineWidth = 1.0
        self.averageLayer.lineDashPattern = [4, 4]
        self.averageLayer.fillColor = UIColor.clear.cgColor
        self.peakLayer.strokeColor = color.cgColor
        self.peakLayer.fillColor = background.cgColor
        self.peakLayer.lineWidth = 2.4
        self.markerLayer.strokeColor = guide.cgColor
        self.markerLayer.lineWidth = 1.0
        self.markerLayer.lineDashPattern = [4, 4]
        self.markerLayer.fillColor = UIColor.clear.cgColor
        self.layer.addSublayer(self.fillLayer)
        self.layer.addSublayer(self.averageLayer)
        self.layer.addSublayer(self.markerLayer)
        self.layer.addSublayer(self.lineLayer)
        self.layer.addSublayer(self.peakLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }
        let bounds = self.bounds
        self.fillLayer.frame = bounds
        self.fillMask.frame = bounds
        for layer in [self.lineLayer, self.averageLayer, self.peakLayer, self.markerLayer] {
            layer.frame = bounds
        }
        guard !self.values.isEmpty, bounds.width > 0.0, bounds.height > 0.0 else {
            self.lineLayer.path = nil
            self.fillMask.path = nil
            self.averageLayer.path = nil
            self.peakLayer.path = nil
            self.markerLayer.path = nil
            return
        }
        let maxValue = max(1e-9, self.values.max() ?? 1.0) * 1.08
        let count = self.values.count
        let top: CGFloat = 6.0
        let bottom: CGFloat = 3.0
        func yFor(_ value: Double) -> CGFloat {
            return bounds.height - bottom - CGFloat(value / maxValue) * (bounds.height - top - bottom)
        }
        func point(_ index: Int) -> CGPoint {
            let x = count == 1 ? bounds.width / 2.0 : CGFloat(index) / CGFloat(count - 1) * bounds.width
            return CGPoint(x: x, y: yFor(self.values[index]))
        }
        let line = UIBezierPath()
        if count == 1 {
            let y = yFor(self.values[0])
            line.move(to: CGPoint(x: 0.0, y: y))
            line.addLine(to: CGPoint(x: bounds.width, y: y))
        } else {
            line.move(to: point(0))
            for index in 1 ..< count {
                line.addLine(to: point(index))
            }
        }
        self.lineLayer.path = line.cgPath
        if self.showFill {
            let area = UIBezierPath(cgPath: line.cgPath)
            area.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
            area.addLine(to: CGPoint(x: 0.0, y: bounds.height))
            area.close()
            self.fillMask.path = area.cgPath
        } else {
            self.fillMask.path = nil
        }
        if self.showAverage {
            let y = yFor(self.values.reduce(0.0, +) / Double(count))
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0.0, y: y))
            path.addLine(to: CGPoint(x: bounds.width, y: y))
            self.averageLayer.path = path.cgPath
        } else {
            self.averageLayer.path = nil
        }
        if self.markPeak, count > 1, let peak = self.values.indices.max(by: { self.values[$0] < self.values[$1] }), self.values[peak] > 0.0 {
            let p = point(peak)
            self.peakLayer.path = UIBezierPath(ovalIn: CGRect(x: p.x - 5.0, y: p.y - 5.0, width: 10.0, height: 10.0)).cgPath
        } else {
            self.peakLayer.path = nil
        }
        if let marker = self.marker, marker >= 0, marker < count, count > 1 {
            let x = point(marker).x
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: 0.0))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
            self.markerLayer.path = path.cgPath
        } else {
            self.markerLayer.path = nil
        }
    }
}

final class DkxAnColumnsView: UIView {
    private var bars: [CALayer] = []
    private let color: UIColor
    private let highlight: UIColor

    var values: [Double] = [] {
        didSet {
            self.rebuild()
        }
    }
    var highlighted = Set<Int>() {
        didSet {
            self.rebuild()
        }
    }

    init(color: UIColor, highlight: UIColor) {
        self.color = color
        self.highlight = highlight
        super.init(frame: CGRect())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuild() {
        for bar in self.bars {
            bar.removeFromSuperlayer()
        }
        self.bars = self.values.indices.map { index in
            let bar = CALayer()
            bar.backgroundColor = (self.highlighted.contains(index) ? self.highlight : self.color).cgColor
            bar.cornerRadius = 3.0
            self.layer.addSublayer(bar)
            return bar
        }
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        guard !self.values.isEmpty else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let maxValue = max(1e-9, self.values.max() ?? 1.0)
        let gap: CGFloat = 3.0
        let width = max(1.0, (bounds.width - gap * CGFloat(self.values.count - 1)) / CGFloat(self.values.count))
        for (index, value) in self.values.enumerated() where index < self.bars.count {
            let height = max(2.0, CGFloat(value / maxValue) * bounds.height)
            self.bars[index].frame = CGRect(x: CGFloat(index) * (width + gap), y: bounds.height - height, width: width, height: height)
        }
        CATransaction.commit()
    }
}

// Пришедшие вверх, ушедшие вниз, под столбцами точка там, где был пост
final class DkxAnGrowthView: UIView {
    private var layers: [CALayer] = []
    private let colors: DkxAnalyticsColors

    var days: [(joined: Int, left: Int, hasPost: Bool)] = [] {
        didSet {
            self.rebuild()
        }
    }

    init(colors: DkxAnalyticsColors) {
        self.colors = colors
        super.init(frame: CGRect())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuild() {
        for layer in self.layers {
            layer.removeFromSuperlayer()
        }
        self.layers = []
        for _ in self.days {
            for color in [self.colors.green, self.colors.red, self.colors.accent] {
                let layer = CALayer()
                layer.backgroundColor = color.cgColor
                self.layer.addSublayer(layer)
                self.layers.append(layer)
            }
        }
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        guard !self.days.isEmpty else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let dotArea: CGFloat = 16.0
        let chartHeight = bounds.height - dotArea
        let half = chartHeight / 2.0
        var largest = 1
        for day in self.days {
            largest = max(largest, day.joined, day.left)
        }
        let maxValue = CGFloat(largest)
        let count = CGFloat(self.days.count)
        let gap: CGFloat = count > 60 ? 0.0 : 3.0
        let width = max(1.0, (bounds.width - gap * (count - 1.0)) / count)
        let radius = min(3.0, width / 2.0)
        for (index, day) in self.days.enumerated() {
            let x = CGFloat(index) * (width + gap)
            let up = CGFloat(day.joined) / maxValue * (half - 4.0)
            let down = CGFloat(day.left) / maxValue * (half - 4.0)
            let upLayer = self.layers[index * 3]
            let downLayer = self.layers[index * 3 + 1]
            let dotLayer = self.layers[index * 3 + 2]
            upLayer.frame = CGRect(x: x, y: half - up, width: width, height: up)
            upLayer.cornerRadius = radius
            upLayer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            downLayer.frame = CGRect(x: x, y: half, width: width, height: down)
            downLayer.cornerRadius = radius
            downLayer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            let dot = min(6.0, max(2.0, width))
            dotLayer.frame = CGRect(x: x + (width - dot) / 2.0, y: chartHeight + (dotArea - dot) / 2.0, width: dot, height: dot)
            dotLayer.cornerRadius = dot / 2.0
            dotLayer.isHidden = !day.hasPost
        }
        CATransaction.commit()
    }
}

final class DkxAnHeatmapView: UIView {
    private var cells: [CALayer] = []
    private var labels: [UILabel] = []
    private let colors: DkxAnalyticsColors
    static let labelWidth: CGFloat = 23.0
    static let rowHeight: CGFloat = 12.0
    static let gap: CGFloat = 3.0

    var values: [[Double?]] = [] {
        didSet {
            self.rebuild()
        }
    }

    init(colors: DkxAnalyticsColors) {
        self.colors = colors
        super.init(frame: CGRect())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuild() {
        for cell in self.cells {
            cell.removeFromSuperlayer()
        }
        for label in self.labels {
            label.removeFromSuperview()
        }
        self.cells = []
        self.labels = []
        let maxValue = max(1e-9, self.values.flatMap { $0.compactMap { $0 } }.max() ?? 1.0)
        for (row, rowValues) in self.values.enumerated() {
            let label = dkxAnLabel(dkxAnWeekdayShort(row).lowercased(with: DkxStrings.locale), size: 11.0, color: self.colors.secondary)
            self.addSubview(label)
            self.labels.append(label)
            for value in rowValues {
                let cell = CALayer()
                cell.cornerRadius = 3.0
                let intensity = value.map { CGFloat($0 / maxValue) } ?? 0.0
                cell.backgroundColor = self.colors.accent.withAlphaComponent(0.1 + 0.9 * intensity).cgColor
                self.layer.addSublayer(cell)
                self.cells.append(cell)
            }
        }
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        guard !self.values.isEmpty else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let columns = CGFloat(self.values.first?.count ?? 24)
        let gap = DkxAnHeatmapView.gap
        let cellWidth = (bounds.width - DkxAnHeatmapView.labelWidth - gap * (columns - 1.0)) / columns
        var index = 0
        for (row, rowValues) in self.values.enumerated() {
            let y = CGFloat(row) * (DkxAnHeatmapView.rowHeight + gap)
            self.labels[row].frame = CGRect(x: 0.0, y: y - 2.0, width: DkxAnHeatmapView.labelWidth, height: DkxAnHeatmapView.rowHeight + 4.0)
            for column in 0 ..< rowValues.count {
                self.cells[index].frame = CGRect(x: DkxAnHeatmapView.labelWidth + CGFloat(column) * (cellWidth + gap), y: y, width: cellWidth, height: DkxAnHeatmapView.rowHeight)
                index += 1
            }
        }
        CATransaction.commit()
    }
}

typealias DkxAnTile = (label: String, value: String, valueColor: UIColor?, note: String?, noteColor: UIColor?, spark: [Double]?, sparkColor: UIColor?)

class DkxAnalyticsBaseController: ViewController {
    let context: AccountContext
    var presentationData: PresentationData
    var colors: DkxAnalyticsColors
    let scrollView = UIScrollView()
    private var contentViews: [UIView] = []
    private var lastLayout: ContainerViewLayout?
    private var lastTopInset: CGFloat = 0.0
    private var presentationDataDisposable: Disposable?

    init(context: AccountContext, title: String) {
        self.context = context
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData
        self.colors = DkxAnalyticsColors(theme: presentationData.theme)

        super.init(navigationBarPresentationData: dkxAnalyticsNavigationBarData(presentationData))

        self._hasGlassStyle = true
        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.title = title
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            let previousTheme = self.presentationData.theme
            self.presentationData = presentationData
            if previousTheme !== presentationData.theme {
                self.colors = DkxAnalyticsColors(theme: presentationData.theme)
                self.setNavigationBarPresentationData(dkxAnalyticsNavigationBarData(presentationData), animated: false)
                self.statusBar.updateStatusBarStyle(presentationData.theme.rootController.statusBarStyle.style, animated: true)
                self.reload()
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.colors.background
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.displayNode.view.addSubview(self.scrollView)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        let previous = self.lastLayout
        let previousTopInset = self.lastTopInset
        self.lastLayout = layout
        self.lastTopInset = topInset

        let bottomInset = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom) + 16.0
        self.scrollView.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0.0, bottom: bottomInset, right: 0.0)
        self.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0.0, bottom: bottomInset, right: 0.0)

        if let previous {
            if previous.size.width != layout.size.width || previousTopInset != topInset {
                self.reload()
            }
        } else {
            self.reload()
            self.scrollView.contentOffset = CGPoint(x: 0.0, y: -topInset)
        }
    }

    func reload() {
        guard self.isViewLoaded, let layout = self.lastLayout else {
            return
        }
        for view in self.contentViews {
            view.removeFromSuperview()
        }
        self.contentViews.removeAll()
        self.displayNode.backgroundColor = self.colors.background

        let sideInset: CGFloat = 16.0 + max(layout.safeInsets.left, layout.safeInsets.right)
        let width = max(100.0, layout.size.width - sideInset * 2.0)
        let height = self.buildContent(x: sideInset, top: 8.0, width: width)
        self.scrollView.contentSize = CGSize(width: layout.size.width, height: height)

        let minOffset = -self.lastTopInset
        let maxOffset = max(minOffset, height + self.scrollView.contentInset.bottom - layout.size.height)
        if self.scrollView.contentOffset.y > maxOffset {
            self.scrollView.contentOffset = CGPoint(x: 0.0, y: maxOffset)
        }
    }

    func buildContent(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        return top
    }

    func add(_ view: UIView) {
        self.scrollView.addSubview(view)
        self.contentViews.append(view)
    }

    func makeCard(radius: CGFloat = 22.0) -> UIView {
        let card = UIView()
        card.backgroundColor = self.colors.card
        card.layer.cornerRadius = radius
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        return card
    }

    // Карточка с заголовком. content получает карточку, отступ, верх и ширину, отдаёт нижний край
    func addCard(x: CGFloat, top: CGFloat, width: CGFloat, title: String?, titleSize: CGFloat = 17.0, padding: CGFloat = 16.0, gap: CGFloat = 10.0, accessory: String? = nil, accessoryAction: (() -> Void)? = nil, content: (UIView, CGFloat, CGFloat, CGFloat) -> CGFloat) -> CGFloat {
        let card = self.makeCard()
        let innerWidth = width - padding * 2.0
        var y: CGFloat = padding
        if let title {
            var titleWidth = innerWidth
            let titleLabel = dkxAnLabel(title, size: titleSize, weight: .semibold, color: self.colors.primary)
            let titleHeight = ceil(titleLabel.sizeThatFits(CGSize(width: innerWidth, height: 100.0)).height)
            if let accessory {
                let accessoryLabel = dkxAnLabel(accessory, size: accessoryAction == nil ? 13.0 : 15.0, color: accessoryAction == nil ? self.colors.secondary : self.colors.accent, alignment: .right)
                let accessoryWidth = dkxAnTextWidth(accessoryLabel, limit: innerWidth * 0.55)
                let accessoryHeight = ceil(accessoryLabel.sizeThatFits(CGSize(width: accessoryWidth, height: 40.0)).height)
                // Выравнивание по базовой линии заголовка
                let accessoryY = y + titleLabel.font.ascender - accessoryLabel.font.ascender
                if let accessoryAction {
                    let tap = DkxAnTapView()
                    tap.action = accessoryAction
                    tap.frame = CGRect(x: padding + innerWidth - accessoryWidth - 10.0, y: accessoryY - 8.0, width: accessoryWidth + 20.0, height: accessoryHeight + 16.0)
                    accessoryLabel.frame = CGRect(x: 10.0, y: 8.0, width: accessoryWidth, height: accessoryHeight)
                    tap.addSubview(accessoryLabel)
                    card.addSubview(tap)
                } else {
                    accessoryLabel.frame = CGRect(x: padding + innerWidth - accessoryWidth, y: accessoryY, width: accessoryWidth, height: accessoryHeight)
                    card.addSubview(accessoryLabel)
                }
                titleWidth -= accessoryWidth + 8.0
            }
            titleLabel.frame = CGRect(x: padding, y: y, width: titleWidth, height: titleHeight)
            card.addSubview(titleLabel)
            y += titleHeight + gap
        }
        y = content(card, padding, y, innerWidth)
        card.frame = CGRect(x: x, y: top, width: width, height: y + padding)
        self.add(card)
        return top + y + padding
    }

    func addFootnote(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat, size: CGFloat = 12.0, center: Bool = false) -> CGFloat {
        let label = dkxAnLabel(text, size: size, color: self.colors.secondary, lines: 0, alignment: center ? .center : .left)
        let height = label.sizeThatFits(CGSize(width: width - 8.0, height: 10000.0)).height
        label.frame = CGRect(x: x + 4.0, y: top, width: width - 8.0, height: ceil(height))
        self.add(label)
        return top + ceil(height)
    }

    func makeButton(_ title: String, width: CGFloat, height: CGFloat, filled: Bool, fontSize: CGFloat, icon: String? = nil, action: @escaping () -> Void) -> UIView {
        let button = DkxAnTapView()
        button.backgroundColor = filled ? self.colors.accent : self.colors.card
        button.layer.cornerRadius = height / 2.0
        button.layer.cornerCurve = .continuous
        button.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        button.action = action
        let textColor = filled ? UIColor.white : self.colors.primary
        let label = dkxAnLabel(title, size: fontSize, weight: .semibold, color: textColor, alignment: .center)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        let labelWidth = dkxAnTextWidth(label, limit: width - 40.0)
        var contentWidth = labelWidth
        var imageView: UIImageView?
        if let icon {
            imageView = dkxAnSymbol(icon, size: 17.0, color: textColor)
            contentWidth += 30.0
        }
        var contentX = floor((width - contentWidth) / 2.0)
        if let imageView {
            imageView.frame = CGRect(x: contentX, y: 0.0, width: 20.0, height: height)
            button.addSubview(imageView)
            contentX += 30.0
        }
        label.frame = CGRect(x: contentX, y: 0.0, width: labelWidth, height: height)
        button.addSubview(label)
        return button
    }

    // Переключатели в несколько строк, как в макете
    func addChoices(_ titles: [String], selected: Int, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat = 34.0, fontSize: CGFloat = 14.0, padding: CGFloat = 14.0, action: @escaping (Int) -> Void) -> CGFloat {
        var cursorX = x
        var y = top
        for (index, title) in titles.enumerated() {
            let isSelected = index == selected
            let label = dkxAnLabel(title, size: fontSize, weight: isSelected ? .semibold : .regular, color: isSelected ? UIColor.black : self.colors.primary, alignment: .center)
            let buttonWidth = dkxAnTextWidth(label, limit: width) + padding * 2.0
            if cursorX > x && cursorX + buttonWidth > x + width {
                cursorX = x
                y += height + 8.0
            }
            let button = DkxAnTapView()
            button.backgroundColor = isSelected ? UIColor.white : self.colors.card
            if isSelected && !self.presentationData.theme.overallDarkAppearance {
                button.backgroundColor = self.colors.primary
                label.textColor = self.colors.card
            }
            button.layer.cornerRadius = height / 2.0
            button.frame = CGRect(x: cursorX, y: y, width: buttonWidth, height: height)
            label.frame = button.bounds
            button.addSubview(label)
            button.action = {
                action(index)
            }
            self.add(button)
            cursorX += buttonWidth + 8.0
        }
        return y + height
    }

    // Плитка показателя. Изменение бейджем, справа маленький график
    func makeTile(_ tile: DkxAnTile, width: CGFloat, compact: Bool) -> UIView {
        let view = self.makeCard(radius: compact ? 20.0 : 22.0)
        let padding: CGFloat = compact ? 13.0 : 14.0
        let innerWidth = width - padding * 2.0
        var y = padding
        y += dkxAnPlace(dkxAnLabel(tile.label, size: compact ? 12.0 : 13.0, color: self.colors.secondary), in: view, x: padding, y: y, width: innerWidth) + (compact ? 4.0 : 6.0)
        let valueLabel = dkxAnLabel(tile.value, size: compact ? 22.0 : 26.0, weight: .bold, color: tile.valueColor ?? self.colors.primary)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        y += dkxAnPlace(valueLabel, in: view, x: padding, y: y, width: innerWidth)
        if tile.note != nil || tile.spark != nil {
            y += compact ? 4.0 : 6.0
            let rowHeight: CGFloat = 22.0
            var noteWidth = innerWidth
            if let spark = tile.spark, spark.count > 1, let sparkColor = tile.sparkColor {
                let chart = DkxAnLineChartView(color: sparkColor, guide: .clear, background: self.colors.card)
                chart.showAverage = false
                chart.markPeak = false
                chart.showFill = false
                chart.lineWidth = 1.8
                chart.values = spark
                chart.frame = CGRect(x: padding + innerWidth - 64.0, y: y, width: 64.0, height: rowHeight)
                view.addSubview(chart)
                noteWidth -= 70.0
            }
            if let note = tile.note {
                if let noteColor = tile.noteColor {
                    let badge = dkxAnBadge(note, color: noteColor)
                    badge.frame = CGRect(x: padding, y: y + (rowHeight - badge.frame.height) / 2.0, width: min(noteWidth, badge.frame.width), height: badge.frame.height)
                    view.addSubview(badge)
                } else {
                    let label = dkxAnLabel(note, size: 12.0, color: self.colors.secondary, lines: 2)
                    let height = ceil(label.sizeThatFits(CGSize(width: noteWidth, height: 100.0)).height)
                    label.frame = CGRect(x: padding, y: y, width: noteWidth, height: max(rowHeight, height))
                    view.addSubview(label)
                    y += max(rowHeight, height) - rowHeight
                }
            }
            y += rowHeight
        }
        view.frame = CGRect(x: 0.0, y: 0.0, width: width, height: y + padding)
        return view
    }

    func addTiles(_ tiles: [DkxAnTile], columns: Int, x: CGFloat, top: CGFloat, width: CGFloat, compact: Bool) -> CGFloat {
        let gap: CGFloat = 10.0
        let tileWidth = floor((width - gap * CGFloat(columns - 1)) / CGFloat(columns))
        var y = top
        var index = 0
        while index < tiles.count {
            var rowHeight: CGFloat = 0.0
            var views: [UIView] = []
            for column in 0 ..< columns where index + column < tiles.count {
                let tile = self.makeTile(tiles[index + column], width: tileWidth, compact: compact)
                tile.frame.origin = CGPoint(x: x + CGFloat(column) * (tileWidth + gap), y: y)
                rowHeight = max(rowHeight, tile.frame.height)
                views.append(tile)
            }
            for view in views {
                view.frame.size.height = rowHeight
                self.add(view)
            }
            y += rowHeight + gap
            index += columns
        }
        return y - gap
    }

    // Строка «значок или имя, полоса, число», как у реакций в макете
    func addBarRow(to card: UIView, x: CGFloat, y: CGFloat, width: CGFloat, title: String, value: String, fraction: CGFloat, color: UIColor, titleWidth: CGFloat, titleSize: CGFloat, valueWidth: CGFloat = 52.0) -> CGFloat {
        let rowHeight: CGFloat = 26.0
        let titleLabel = dkxAnLabel(title, size: titleSize, color: self.colors.primary)
        titleLabel.frame = CGRect(x: x, y: y, width: titleWidth, height: rowHeight)
        card.addSubview(titleLabel)
        let valueLabel = dkxAnLabel(value, size: 14.0, color: self.colors.primary, alignment: .right)
        valueLabel.frame = CGRect(x: x + width - valueWidth, y: y, width: valueWidth, height: rowHeight)
        card.addSubview(valueLabel)
        let bar = DkxAnBarView(track: self.colors.track, color: color)
        bar.fraction = fraction
        bar.frame = CGRect(x: x + titleWidth + 10.0, y: y + (rowHeight - 8.0) / 2.0, width: max(10.0, width - titleWidth - valueWidth - 20.0), height: 8.0)
        card.addSubview(bar)
        return y + rowHeight
    }

    func showToast(_ text: String) {
        self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
}
