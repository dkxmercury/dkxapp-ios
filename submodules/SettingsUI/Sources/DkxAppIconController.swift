import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import AppBundle

// MARK: DKX выбор значка приложения. Значки вшиты в сборку папками .alticon в
// Telegram/Telegram-iOS, имена перечислены в Telegram/BUILD. Штатный выбор
// значка Telegram в оформлении не тронут.

private let dkxAppIconNames: [String] = (2 ... 26).map { String(format: "Dkx%02d", $0) }

private func dkxAppIconNavigationBarData(_ presentationData: PresentationData) -> NavigationBarPresentationData {
    return NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: presentationData.theme, hideBackground: false, hideSeparator: false, edgeEffectColor: presentationData.theme.list.blocksBackgroundColor, style: .glass), strings: NavigationBarStrings(presentationStrings: presentationData.strings))
}

private final class DkxAppIconCell: UIControl {
    let name: String?
    private let imageView = UIImageView()
    private let ringView = UIView()
    private let label = UILabel()
    private let action: () -> Void

    init(name: String?, image: UIImage?, title: String, action: @escaping () -> Void) {
        self.name = name
        self.action = action
        super.init(frame: CGRect())

        self.ringView.isUserInteractionEnabled = false
        self.ringView.layer.borderWidth = 2.5
        self.ringView.layer.cornerCurve = .continuous
        self.addSubview(self.ringView)

        self.imageView.image = image
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        self.imageView.layer.cornerCurve = .continuous
        self.imageView.isUserInteractionEnabled = false
        self.addSubview(self.imageView)

        self.label.text = title
        self.label.font = UIFont.systemFont(ofSize: 12.0)
        self.label.textAlignment = .center
        self.addSubview(self.label)

        self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func pressed() {
        self.action()
    }

    override var isHighlighted: Bool {
        didSet {
            self.imageView.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }

    func update(selected: Bool, theme: PresentationTheme) {
        self.ringView.layer.borderColor = theme.list.itemAccentColor.cgColor
        self.ringView.isHidden = !selected
        self.label.textColor = selected ? theme.list.itemAccentColor : theme.list.itemSecondaryTextColor
    }

    static func height(width: CGFloat) -> CGFloat {
        return width + 20.0
    }

    func layout(width: CGFloat) {
        self.ringView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: width)
        self.ringView.layer.cornerRadius = width * 0.25
        let inset: CGFloat = 5.0
        let side = width - inset * 2.0
        self.imageView.frame = CGRect(x: inset, y: inset, width: side, height: side)
        self.imageView.layer.cornerRadius = side * 0.225
        self.label.frame = CGRect(x: -4.0, y: width + 3.0, width: width + 8.0, height: 16.0)
    }
}

private final class DkxAppIconController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private let scrollView = UIScrollView()
    private var cells: [DkxAppIconCell] = []
    private let footerLabel = UILabel()
    private var currentName: String?
    private var isApplying = false
    private var presentationDataDisposable: Disposable?

    init(context: AccountContext) {
        self.context = context
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData
        self.currentName = context.sharedContext.applicationBindings.getAlternateIconName()

        super.init(navigationBarPresentationData: dkxAppIconNavigationBarData(presentationData))

        self._hasGlassStyle = true
        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.title = "Значок приложения"

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            let previousTheme = self.presentationData.theme
            self.presentationData = presentationData
            if previousTheme !== presentationData.theme {
                self.setNavigationBarPresentationData(dkxAppIconNavigationBarData(presentationData), animated: false)
                self.statusBar.updateStatusBarStyle(presentationData.theme.rootController.statusBarStyle.style, animated: true)
                self.applyTheme()
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
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.displayNode.view.addSubview(self.scrollView)

        var cells: [DkxAppIconCell] = []
        cells.append(DkxAppIconCell(name: nil, image: UIImage(bundleImageName: "Settings/DkxPrimaryIcon"), title: "Основной", action: { [weak self] in
            self?.select(nil)
        }))
        for (index, name) in dkxAppIconNames.enumerated() {
            cells.append(DkxAppIconCell(name: name, image: UIImage(named: name, in: getAppBundle(), compatibleWith: nil), title: "\(index + 2)", action: { [weak self] in
                self?.select(name)
            }))
        }
        for cell in cells {
            self.scrollView.addSubview(cell)
        }
        self.cells = cells

        self.footerLabel.numberOfLines = 0
        self.footerLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.footerLabel.text = "iOS при каждой смене значка показывает окно, что значок изменён.\n\nВ Telegram свой выбор значка в «Оформлении» остался как был. Новые картинки добавляются в сборку, с телефона их не поставить."
        self.scrollView.addSubview(self.footerLabel)

        self.applyTheme()
        self.displayNodeDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Значок могли сменить в оформлении Telegram, пока экран был закрыт
        self.currentName = self.context.sharedContext.applicationBindings.getAlternateIconName()
        self.updateSelection()
    }

    private func applyTheme() {
        guard self.isNodeLoaded else {
            return
        }
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.footerLabel.textColor = self.presentationData.theme.list.freeTextColor
        self.updateSelection()
    }

    private func updateSelection() {
        for cell in self.cells {
            cell.update(selected: cell.name == self.currentName, theme: self.presentationData.theme)
        }
    }

    private func select(_ name: String?) {
        guard name != self.currentName, !self.isApplying else {
            return
        }
        self.isApplying = true
        self.context.sharedContext.applicationBindings.requestSetAlternateIconName(name, { [weak self] success in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.isApplying = false
                if success {
                    self.currentName = name
                    self.updateSelection()
                }
            }
        })
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bottomInset = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom) + 16.0
        self.scrollView.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0.0, bottom: bottomInset, right: 0.0)
        self.scrollView.verticalScrollIndicatorInsets = self.scrollView.contentInset

        let sideInset: CGFloat = 16.0
        let left = sideInset + layout.safeInsets.left
        let contentWidth = layout.size.width - left - sideInset - layout.safeInsets.right
        let columns: CGFloat = contentWidth >= 560.0 ? 6.0 : 4.0
        let spacing: CGFloat = 12.0
        let cellWidth = floor((contentWidth - spacing * (columns - 1.0)) / columns)
        let cellHeight = DkxAppIconCell.height(width: cellWidth)

        var y: CGFloat = 16.0
        for (index, cell) in self.cells.enumerated() {
            let column = CGFloat(index % Int(columns))
            let row = CGFloat(index / Int(columns))
            y = 16.0 + row * (cellHeight + spacing)
            cell.frame = CGRect(x: left + column * (cellWidth + spacing), y: y, width: cellWidth, height: cellHeight)
            cell.layout(width: cellWidth)
        }
        y += cellHeight + 20.0

        let footerSize = self.footerLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        self.footerLabel.frame = CGRect(x: left, y: y, width: contentWidth, height: ceil(footerSize.height))
        y += ceil(footerSize.height)

        let previousHeight = self.scrollView.contentSize.height
        self.scrollView.contentSize = CGSize(width: layout.size.width, height: y)
        if previousHeight == 0.0 {
            self.scrollView.contentOffset = CGPoint(x: 0.0, y: -topInset)
        }
    }
}

public func dkxAppIconController(context: AccountContext) -> ViewController {
    return DkxAppIconController(context: context)
}
