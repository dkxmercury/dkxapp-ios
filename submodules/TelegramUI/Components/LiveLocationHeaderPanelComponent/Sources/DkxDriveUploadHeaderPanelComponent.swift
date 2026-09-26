import Foundation
import UIKit
import Display
import TelegramPresentationData
import ComponentFlow
import TelegramUIPreferences

// MARK: DKX полоса хода выгрузки в Google Drive. Стоит там же, где плеер
// музыки и трансляция геопозиции, и рисуется в их манере. Крестик отменяет
// текущий файл.
public final class DkxDriveUploadHeaderPanelComponent: Component {
    public let theme: PresentationTheme
    public let data: DkxDriveUploadProgress

    public init(theme: PresentationTheme, data: DkxDriveUploadProgress) {
        self.theme = theme
        self.data = data
    }

    public static func ==(lhs: DkxDriveUploadHeaderPanelComponent, rhs: DkxDriveUploadHeaderPanelComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.data != rhs.data {
            return false
        }
        return true
    }

    public final class View: UIView {
        private let iconView = UIImageView()
        private let titleLabel = UILabel()
        private let subtitleLabel = UILabel()
        private let closeButton = UIButton(type: .custom)
        private let trackView = UIView()
        private let progressView = UIView()

        private var component: DkxDriveUploadHeaderPanelComponent?

        public override init(frame: CGRect) {
            super.init(frame: frame)

            self.clipsToBounds = true
            self.iconView.contentMode = .center
            self.addSubview(self.iconView)

            self.titleLabel.font = Font.regular(12.0)
            self.titleLabel.textAlignment = .center
            self.addSubview(self.titleLabel)

            self.subtitleLabel.font = Font.regular(10.0)
            self.subtitleLabel.textAlignment = .center
            self.subtitleLabel.lineBreakMode = .byTruncatingMiddle
            self.addSubview(self.subtitleLabel)

            self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
            self.addSubview(self.closeButton)

            self.addSubview(self.trackView)
            self.addSubview(self.progressView)
        }

        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func closePressed() {
            DkxDriveUploadStatus.cancelCurrent()
        }

        func update(component: DkxDriveUploadHeaderPanelComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let previousTheme = self.component?.theme
            self.component = component

            let theme = component.theme
            let controlColor = theme.chat.inputPanel.panelControlColor
            if previousTheme !== theme {
                self.iconView.image = UIImage(systemName: "icloud.and.arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .regular))
                self.iconView.tintColor = controlColor
                self.titleLabel.textColor = theme.rootController.navigationBar.primaryTextColor
                self.subtitleLabel.textColor = theme.rootController.navigationBar.secondaryTextColor
                self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .regular)), for: .normal)
                self.closeButton.tintColor = controlColor
                self.trackView.backgroundColor = controlColor.withAlphaComponent(0.15)
                self.progressView.backgroundColor = controlColor
            }

            let data = component.data
            self.titleLabel.text = data.waiting > 0 ? DkxStrings.tr("Google Drive, файлов {}", data.waiting + 1) : "Google Drive"
            switch data.phase {
            case .preparing:
                self.subtitleLabel.text = DkxStrings.tr("Готовлю {}", data.fileName)
            case .uploading:
                self.subtitleLabel.text = "\(data.fileName) · \(Int((data.fraction * 100.0).rounded()))%"
            }

            let size = CGSize(width: availableSize.width, height: 40.0)
            let textWidth = max(0.0, size.width - 100.0)
            self.iconView.frame = CGRect(x: 9.0, y: 10.0, width: 22.0, height: 20.0)
            self.titleLabel.frame = CGRect(x: floor((size.width - textWidth) / 2.0), y: 6.0, width: textWidth, height: 15.0)
            self.subtitleLabel.frame = CGRect(x: floor((size.width - textWidth) / 2.0), y: 22.0, width: textWidth, height: 13.0)
            self.closeButton.frame = CGRect(x: size.width - 44.0, y: 0.0, width: 44.0, height: size.height)

            let fraction = data.phase == .uploading ? max(0.0, min(1.0, data.fraction)) : 0.0
            self.trackView.frame = CGRect(x: 0.0, y: size.height - 2.0, width: size.width, height: 2.0)
            transition.setFrame(view: self.progressView, frame: CGRect(x: 0.0, y: size.height - 2.0, width: floor(size.width * CGFloat(fraction)), height: 2.0))

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
