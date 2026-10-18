//
//  LCAppBanner.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UIKit

protocol LCAppBannerDelegate {
    func removeApp(app: LCAppModel)
    func installMdm(data: Data)
    func openNavigationView(view: AnyView)
    func promptForGeneratedIconStyle() async -> GeneratedIconStyle?
}

struct LCAppBanner: UIViewControllerRepresentable {
    var delegate: LCAppBannerDelegate
    var homeScreen = false
    var iconSide: CGFloat = 62
    var showLabel = true
    var isDocked = false
    var onToggleDock: (() -> Void)?

    @ObservedObject var model: LCAppModel

    @AppStorage("dynamicColors", store: LCUtils.appGroupUserDefault) private var dynamicColors = true
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkModeIcon = false
    private let sharedModel = DataManager.shared.model

    init(appModel: LCAppModel, delegate: LCAppBannerDelegate, homeScreen: Bool = false,
         iconSide: CGFloat = 62, showLabel: Bool = true, isDocked: Bool = false, onToggleDock: (() -> Void)? = nil) {
        _model = ObservedObject(wrappedValue: appModel)
        self.delegate = delegate
        self.homeScreen = homeScreen
        self.iconSide = iconSide
        self.showLabel = showLabel
        self.isDocked = isDocked
        self.onToggleDock = onToggleDock
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = LCAppBannerViewController(delegate: delegate, config: LCAppBannerConfiguration(model: model, dynamicColors: dynamicColors, darkModeIcon: darkModeIcon), homeScreen: homeScreen, iconSide: iconSide, showLabel: showLabel)
        viewController.onToggleDock = onToggleDock
        viewController.isDocked = isDocked
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let viewController = uiViewController as? LCAppBannerViewController else {
            return
        }
        viewController.update(
            model: model,
            dynamicColors: dynamicColors,
            darkModeIcon: darkModeIcon
        )
        viewController.updateHomeIcon(side: iconSide, showLabel: showLabel)
        viewController.onToggleDock = onToggleDock
        viewController.isDocked = isDocked
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIViewController, context: Context) -> CGSize? {
        guard let width = proposal.width else {
            return nil
        }
        return CGSize(width: width, height: homeScreen ? iconSide + (showLabel ? 30 : 8) : LCAppBannerRootView.bannerHeight)
    }
}
