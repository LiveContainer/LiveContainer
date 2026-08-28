//
//  LCAppBannerView.swift
//  LiveContainerSwiftUI
//

import Foundation
import UIKit

final class LCAppBannerRootView: UIView {
    static let bannerHeight: CGFloat = 88

    let runControl = LCAppBannerRunControl()

    private let visualBackgroundView = UIView()
    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()
    private let versionLabel = UILabel()
    private let remarkLabel = UILabel()
    private let containerLabel = UILabel()
    private let sharedBadge = LCAppBannerBadgeView(symbolName: "arrowshape.turn.up.left.fill")
    private let jitBadge = LCAppBannerBadgeView(symbolName: "bolt.fill")
    private let lockBadge = LCAppBannerBadgeView(symbolName: "lock.fill")
    private let bit32Badge = LCAppBannerBadgeView(text: "32")
    private let nameSpacer = UIView()
    private let nameStack = UIStackView()
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
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true

        visualBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        visualBackgroundView.isOpaque = false
        visualBackgroundView.isUserInteractionEnabled = false

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.layer.cornerRadius = 16
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.clipsToBounds = true
        iconImageView.isAccessibilityElement = false

        configureLabel(nameLabel, font: .systemFont(ofSize: 16, weight: .bold))
        configureLabel(versionLabel, font: .systemFont(ofSize: 12))
        configureLabel(remarkLabel, font: .systemFont(ofSize: 10))
        configureLabel(containerLabel, font: .systemFont(ofSize: 8))

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameStack.translatesAutoresizingMaskIntoConstraints = false
        nameStack.axis = .horizontal
        nameStack.alignment = .center
        nameStack.spacing = 8
        nameStack.addArrangedSubview(nameLabel)
        nameStack.addArrangedSubview(sharedBadge)
        nameStack.addArrangedSubview(jitBadge)
        nameStack.addArrangedSubview(bit32Badge)
        nameStack.addArrangedSubview(lockBadge)
        nameStack.addArrangedSubview(nameSpacer)

        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailStack.axis = .vertical
        detailStack.alignment = .fill
        detailStack.distribution = .fill
        detailStack.spacing = 1
        detailStack.addArrangedSubview(nameStack)
        detailStack.addArrangedSubview(versionLabel)
        detailStack.addArrangedSubview(remarkLabel)
        detailStack.addArrangedSubview(containerLabel)
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

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 60),
            iconImageView.heightAnchor.constraint(equalToConstant: 60),

            detailStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
            detailStack.trailingAnchor.constraint(lessThanOrEqualTo: runControl.leadingAnchor, constant: -10),
            detailStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            runControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            runControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            runControl.widthAnchor.constraint(equalToConstant: 70),
            runControl.heightAnchor.constraint(equalToConstant: 32)
        ])
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

        iconImageView.image = icon
        nameLabel.text = model.displayName
        nameLabel.textColor = .label
        versionLabel.text = "\(model.version) - \(model.bundleIdentifier)"
        versionLabel.textColor = textColor
        remarkLabel.text = model.uiRemark
        remarkLabel.textColor = textColor.withAlphaComponent(0.8)
        remarkLabel.isHidden = model.uiRemark.isEmpty
        containerLabel.text = model.uiSelectedContainer?.name ?? "lc.appBanner.noDataFolder".loc
        containerLabel.textColor = textColor

        sharedBadge.isHidden = !model.uiIsShared
        sharedBadge.backgroundColor = UIColor(named: "BadgeColor") ?? .systemOrange
        jitBadge.isHidden = !model.uiIsJITNeeded || model.uiIs32bit
        jitBadge.backgroundColor = UIColor(named: "JITBadgeColor") ?? .systemPurple
        lockBadge.isHidden = !model.uiIsLocked || model.uiIsHidden
        lockBadge.backgroundColor = UIColor(named: "BadgeColor") ?? .systemOrange
        bit32Badge.isHidden = !model.uiIs32bit
        bit32Badge.backgroundColor = UIColor(named: "32BitBadgeColor") ?? .systemBlue

        visualBackgroundView.backgroundColor = dynamicColors
            ? mainColor.withAlphaComponent(0.5)
            : (UIColor(named: "AppBannerBG") ?? .secondarySystemBackground)
        runControl.update(
            color: accentColor,
            isSigning: model.isSigningInProgress,
            progress: model.signProgress,
            isEnabled: !model.isAppRunning
        )

        var accessibilityParts = [model.displayName, "\(model.version) - \(model.bundleIdentifier)"]
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
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 8)
        ))
        imageView.tintColor = .white
        imageView.contentMode = .center
        self.init(contentView: imageView)
    }

    convenience init(text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 8)
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
        layer.cornerRadius = 8
        clipsToBounds = true
        isAccessibilityElement = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 16),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

final class LCAppBannerRunControl: UIControl {
    private let baseLayer = CALayer()
    private let progressCircleLayer = CALayer()
    private let titleLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var progress = 0.0

    override var intrinsicContentSize: CGSize {
        CGSize(width: 70, height: 32)
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
        titleLabel.text = "lc.appBanner.run".loc
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
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

    func update(color: UIColor, isSigning: Bool, progress: Double, isEnabled: Bool) {
        self.progress = min(max(progress, 0), 1)
        self.isEnabled = isEnabled

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

