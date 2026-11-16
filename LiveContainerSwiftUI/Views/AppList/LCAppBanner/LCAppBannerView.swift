//
//  LCAppBannerView.swift
//  LiveContainerSwiftUI
//

import Foundation
import UIKit

final class LCAppBannerRootView: UIView {
    static let bannerHeight: CGFloat = LCDesign.Size.bannerHeight

    let runControl = LCAppBannerRunControl()

    private let visualBackgroundView = UIView()
    private let washLayer = CAGradientLayer()
    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()
    private let versionLabel = UILabel()
    private let remarkLabel = UILabel()
    private let containerChip = LCAppBannerChipView()
    private let sharedBadge = LCAppBannerBadgeView(symbolName: "arrowshape.turn.up.left.fill")
    private let jitBadge = LCAppBannerBadgeView(symbolName: "bolt.fill")
    private let lockBadge = LCAppBannerBadgeView(symbolName: "lock.fill")
    private let bit32Badge = LCAppBannerBadgeView(text: "32")
    private let nameSpacer = UIView()
    private let nameStack = UIStackView()
    private let chipRow = UIStackView()
    private let detailStack = UIStackView()

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.bannerHeight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        isOpaque = false
        backgroundColor = .clear
        layer.cornerRadius = LCDesign.Radius.card
        layer.cornerCurve = .continuous
        layer.borderWidth = 1 / UIScreen.main.scale
        clipsToBounds = true

        visualBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        visualBackgroundView.isOpaque = false
        visualBackgroundView.isUserInteractionEnabled = false
        washLayer.startPoint = CGPoint(x: 0, y: 0.5)
        washLayer.endPoint = CGPoint(x: 1, y: 0.5)
        visualBackgroundView.layer.addSublayer(washLayer)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.layer.cornerRadius = LCDesign.Radius.icon
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.layer.borderWidth = 1 / UIScreen.main.scale
        iconImageView.clipsToBounds = true
        iconImageView.isAccessibilityElement = false

        configureLabel(nameLabel, font: Self.roundedFont(size: 16, weight: .semibold))
        configureLabel(versionLabel, font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
        configureLabel(remarkLabel, font: .italicSystemFont(ofSize: 11))

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameStack.axis = .horizontal
        nameStack.alignment = .center
        nameStack.spacing = 5
        nameStack.addArrangedSubview(nameLabel)
        nameStack.setCustomSpacing(7, after: nameLabel)
        nameStack.addArrangedSubview(sharedBadge)
        nameStack.addArrangedSubview(jitBadge)
        nameStack.addArrangedSubview(bit32Badge)
        nameStack.addArrangedSubview(lockBadge)
        nameStack.addArrangedSubview(nameSpacer)

        // Container chip sits on its own row; remark (if any) follows it so a long remark
        // gets truncated instead of pushing the chip away.
        let chipSpacer = UIView()
        chipSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        chipRow.axis = .horizontal
        chipRow.alignment = .center
        chipRow.spacing = 6
        chipRow.addArrangedSubview(containerChip)
        chipRow.addArrangedSubview(remarkLabel)
        chipRow.addArrangedSubview(chipSpacer)
        containerChip.setContentCompressionResistancePriority(.required, for: .horizontal)
        remarkLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailStack.axis = .vertical
        detailStack.alignment = .fill
        detailStack.distribution = .fill
        detailStack.spacing = 3
        detailStack.addArrangedSubview(nameStack)
        detailStack.addArrangedSubview(versionLabel)
        detailStack.setCustomSpacing(6, after: versionLabel)
        detailStack.addArrangedSubview(chipRow)
        detailStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailStack.isAccessibilityElement = true

        runControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualBackgroundView)
        addSubview(iconImageView)
        addSubview(detailStack)
        addSubview(runControl)

        NSLayoutConstraint.activate([
            visualBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            visualBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LCDesign.Spacing.cardInset),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: LCDesign.Size.icon),
            iconImageView.heightAnchor.constraint(equalToConstant: LCDesign.Size.icon),

            detailStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: LCDesign.Spacing.iconToText),
            detailStack.trailingAnchor.constraint(lessThanOrEqualTo: runControl.leadingAnchor, constant: -10),
            detailStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            runControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LCDesign.Spacing.cardInset),
            runControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            runControl.widthAnchor.constraint(equalToConstant: LCDesign.Size.runButton.width),
            runControl.heightAnchor.constraint(equalToConstant: LCDesign.Size.runButton.height)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        washLayer.frame = visualBackgroundView.bounds
        CATransaction.commit()
    }

    static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func configureLabel(_ label: UILabel, font: UIFont) {
        label.font = font
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.isAccessibilityElement = false
    }

    func update(
        model: LCAppModel,
        appInfo: LCAppInfo,
        dynamicColors: Bool,
        darkModeIcon: Bool,
        traitCollection: UITraitCollection
    ) {
        let icon = appInfo.iconIsDarkIcon(darkModeIcon) ?? UIImage()
        let mainColor = Self.extractMainHueColor(appInfo: appInfo, icon: icon, darkModeIcon: darkModeIcon)
        let accentColor = dynamicColors ? mainColor : (UIColor(named: "FontColor") ?? .systemBlue)
        let textColor = Self.readableTextColor(for: accentColor, traitCollection: traitCollection)

        let isDark = traitCollection.userInterfaceStyle == .dark
        let washColor = (dynamicColors ? mainColor : LCDesign.fallbackAccent).resolvedColor(with: traitCollection)
        let alphas = LCDesign.washAlphas(isDark: isDark)

        iconImageView.image = icon
        iconImageView.layer.borderColor = UIColor.label.withAlphaComponent(isDark ? 0.14 : 0.08).resolvedColor(with: traitCollection).cgColor
        nameLabel.text = model.displayName
        nameLabel.textColor = .label
        versionLabel.text = "\(model.version)  ·  \(model.bundleIdentifier)"
        versionLabel.textColor = .secondaryLabel
        remarkLabel.text = model.uiRemark
        remarkLabel.textColor = .secondaryLabel
        remarkLabel.isHidden = model.uiRemark.isEmpty
        let hasContainer = model.uiSelectedContainer != nil
        containerChip.update(
            symbolName: hasContainer ? "folder.fill" : "folder.badge.questionmark",
            text: model.uiSelectedContainer?.name ?? "lc.appBanner.noDataFolder".loc,
            tint: hasContainer ? textColor : .systemOrange
        )

        sharedBadge.isHidden = !model.uiIsShared
        sharedBadge.backgroundColor = UIColor(named: "BadgeColor") ?? .systemOrange
        jitBadge.isHidden = !model.uiIsJITNeeded || model.uiIs32bit
        jitBadge.backgroundColor = UIColor(named: "JITBadgeColor") ?? .systemPurple
        lockBadge.isHidden = !model.uiIsLocked || model.uiIsHidden
        lockBadge.backgroundColor = UIColor(named: "BadgeColor") ?? .systemOrange
        bit32Badge.isHidden = !model.uiIs32bit
        bit32Badge.backgroundColor = UIColor(named: "32BitBadgeColor") ?? .systemBlue

        // Neutral grouped surface + a horizontal wash of the icon colour, instead of a flat 50% fill.
        // Keeps text contrast stable whatever the icon colour is.
        visualBackgroundView.backgroundColor = .secondarySystemGroupedBackground
        washLayer.colors = [
            washColor.withAlphaComponent(alphas.start).cgColor,
            washColor.withAlphaComponent(alphas.end).cgColor
        ]
        layer.borderColor = washColor.withAlphaComponent(isDark ? 0.30 : 0.22).cgColor
        runControl.update(
            color: accentColor,
            isSigning: model.isSigningInProgress,
            progress: model.signProgress,
            isEnabled: !model.isAppRunning
        )

        var accessibilityParts = [model.displayName, "\(model.version), \(model.bundleIdentifier)"]
        if !model.uiRemark.isEmpty {
            accessibilityParts.append(model.uiRemark)
        }
        accessibilityParts.append(model.uiSelectedContainer?.name ?? "lc.appBanner.noDataFolder".loc)
        detailStack.accessibilityLabel = accessibilityParts.joined(separator: ", ")
    }

    private static func extractMainHueColor(appInfo: LCAppInfo, icon: UIImage, darkModeIcon: Bool) -> UIColor {
        if darkModeIcon, let cachedColor = appInfo.cachedColorDark {
            return cachedColor
        }
        if !darkModeIcon, let cachedColor = appInfo.cachedColor {
            return cachedColor
        }

        guard let cgImage = icon.cgImage else {
            return .clear
        }

        var pixelData = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .clear
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let averageColor = UIColor(
            red: CGFloat(pixelData[0]) / 255,
            green: CGFloat(pixelData[1]) / 255,
            blue: CGFloat(pixelData[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        averageColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let color: UIColor
        if brightness < 0.1 && saturation < 0.1 {
            color = .systemRed
        } else {
            color = UIColor(hue: hue, saturation: saturation, brightness: max(brightness, 0.3), alpha: 1)
        }

        if darkModeIcon {
            appInfo.cachedColorDark = color
        } else {
            appInfo.cachedColor = color
        }
        return color
    }

    private static func readableTextColor(for color: UIColor, traitCollection: UITraitCollection) -> UIColor {
        let resolvedColor = color.resolvedColor(with: traitCollection)
        let systemBackground = UIColor.systemBackground.resolvedColor(with: traitCollection)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var backgroundRed: CGFloat = 0
        var backgroundGreen: CGFloat = 0
        var backgroundBlue: CGFloat = 0
        var backgroundAlpha: CGFloat = 0
        resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        systemBackground.getRed(
            &backgroundRed,
            green: &backgroundGreen,
            blue: &backgroundBlue,
            alpha: &backgroundAlpha
        )

        red = 0.5 * red + 0.5 * backgroundRed
        green = 0.5 * green + 0.5 * backgroundGreen
        blue = 0.5 * blue + 0.5 * backgroundBlue
        let brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let offset: CGFloat = brightness < 0.5 ? 0.4 : -0.4
        return UIColor(
            red: min(max(red + offset, 0), 1),
            green: min(max(green + offset, 0), 1),
            blue: min(max(blue + offset, 0), 1),
            alpha: 1
        )
    }
}

private final class LCAppBannerBadgeView: UIView {
    private let contentView: UIView

    convenience init(symbolName: String) {
        let imageView = UIImageView(image: UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        ))
        imageView.tintColor = .white
        imageView.contentMode = .center
        self.init(contentView: imageView)
    }

    convenience init(text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = LCAppBannerRootView.roundedFont(size: 9, weight: .heavy)
        label.textAlignment = .center
        self.init(contentView: label)
    }

    private init(contentView: UIView) {
        self.contentView = contentView
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = LCDesign.Size.badge / 2
        clipsToBounds = true
        isAccessibilityElement = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: LCDesign.Size.badge),
            heightAnchor.constraint(equalToConstant: LCDesign.Size.badge),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

/// Small rounded "folder · container name" tag shown under the version line.
private final class LCAppBannerChipView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = LCDesign.Radius.chip
        layer.cornerCurve = .continuous
        isAccessibilityElement = false

        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 140)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(symbolName: String, text: String, tint: UIColor) {
        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = tint
        label.text = text
        label.textColor = tint
        backgroundColor = tint.withAlphaComponent(0.14)
    }
}

final class LCAppBannerRunControl: UIControl {
    private let baseLayer = CALayer()
    private let progressCircleLayer = CALayer()
    private let titleLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var progress = 0.0

    override var intrinsicContentSize: CGSize {
        LCDesign.Size.runButton
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        clipsToBounds = true
        layer.addSublayer(baseLayer)
        layer.addSublayer(progressCircleLayer)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let titleFont = LCAppBannerRootView.roundedFont(size: 15, weight: .bold)
        let playIcon = NSTextAttachment()
        playIcon.image = UIImage(
            systemName: "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        )?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let title = NSMutableAttributedString(attachment: playIcon)
        title.append(NSAttributedString(string: " " + "lc.appBanner.run".loc,
                                        attributes: [.font: titleFont, .foregroundColor: UIColor.white]))
        titleLabel.attributedText = title
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.1
        titleLabel.isUserInteractionEnabled = false

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.isUserInteractionEnabled = false

        addSubview(titleLabel)
        addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "lc.appBanner.run".loc
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        baseLayer.frame = bounds

        let width = bounds.width
        progressCircleLayer.frame = CGRect(
            x: (CGFloat(progress) - 2) * width,
            y: bounds.height / 2 - width,
            width: width * 2,
            height: width * 2
        )
        progressCircleLayer.cornerRadius = width
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -4, dy: -6).contains(point)
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }

    func update(color: UIColor, isSigning: Bool, progress: Double, isEnabled: Bool) {
        self.progress = min(max(progress, 0), 1)
        self.isEnabled = isEnabled
        alpha = isEnabled || isSigning ? 1 : 0.45

        baseLayer.backgroundColor = color.withAlphaComponent(isSigning ? 0.2 : 1).cgColor
        progressCircleLayer.backgroundColor = color.cgColor
        progressCircleLayer.isHidden = !isSigning
        titleLabel.isHidden = isSigning
        if isSigning {
            activityIndicator.startAnimating()
            accessibilityValue = NumberFormatter.localizedString(from: NSNumber(value: self.progress), number: .percent)
        } else {
            activityIndicator.stopAnimating()
            accessibilityValue = nil
        }
        accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
        setNeedsLayout()
    }
}

