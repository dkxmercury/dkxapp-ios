import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import ComponentFlow
import AccountContext
import TelegramUIPreferences

// MARK: DKX ряд меток над списком чатов. Нажатие на метку открывает её чаты.
// Цвета из той же палитры, что теги папок Telegram.
public final class DkxChatLabelsHeaderPanelComponent: Component {
    public let context: AccountContext
    public let theme: PresentationTheme
    public let labels: [DkxChatLabel]
    public let action: (Int32) -> Void

    public init(context: AccountContext, theme: PresentationTheme, labels: [DkxChatLabel], action: @escaping (Int32) -> Void) {
        self.context = context
        self.theme = theme
        self.labels = labels
        self.action = action
    }

    public static func ==(lhs: DkxChatLabelsHeaderPanelComponent, rhs: DkxChatLabelsHeaderPanelComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.labels != rhs.labels {
            return false
        }
        return true
    }

    public final class View: UIView {
        private let scrollView = UIScrollView()
        private var buttons: [UIButton] = []
        private var component: DkxChatLabelsHeaderPanelComponent?

        public override init(frame: CGRect) {
            super.init(frame: frame)
            self.clipsToBounds = true
            self.scrollView.showsHorizontalScrollIndicator = false
            self.scrollView.showsVerticalScrollIndicator = false
            self.scrollView.alwaysBounceHorizontal = false
            self.addSubview(self.scrollView)
        }

        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func buttonPressed(_ sender: UIButton) {
            guard let component = self.component, sender.tag >= 0, sender.tag < component.labels.count else {
                return
            }
            component.action(component.labels[sender.tag].id)
        }

        func update(component: DkxChatLabelsHeaderPanelComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let previous = self.component
            self.component = component

            let size = CGSize(width: availableSize.width, height: 40.0)
            self.scrollView.frame = CGRect(origin: CGPoint(), size: size)

            if previous == nil || previous?.labels != component.labels || previous?.theme !== component.theme {
                for button in self.buttons {
                    button.removeFromSuperview()
                }
                self.buttons.removeAll()

                let chipHeight: CGFloat = 28.0
                var x: CGFloat = 12.0
                for (index, label) in component.labels.enumerated() {
                    let color = component.context.peerNameColors.getChatFolderTag(PeerNameColor(rawValue: label.colorId), dark: component.theme.overallDarkAppearance).main
                    let button = UIButton(type: .custom)
                    button.tag = index
                    button.setTitle(label.title, for: .normal)
                    button.setTitleColor(color, for: .normal)
                    button.titleLabel?.font = Font.semibold(13.0)
                    button.backgroundColor = color.withAlphaComponent(0.14)
                    button.layer.cornerRadius = chipHeight / 2.0
                    button.addTarget(self, action: #selector(self.buttonPressed(_:)), for: .touchUpInside)
                    let titleWidth = ceil(button.titleLabel?.sizeThatFits(CGSize(width: 240.0, height: chipHeight)).width ?? 0.0)
                    let width = titleWidth + 24.0
                    button.frame = CGRect(x: x, y: floor((size.height - chipHeight) / 2.0), width: width, height: chipHeight)
                    x += width + 8.0
                    self.scrollView.addSubview(button)
                    self.buttons.append(button)
                }
                self.scrollView.contentSize = CGSize(width: x + 4.0, height: size.height)
            }
            return size
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
