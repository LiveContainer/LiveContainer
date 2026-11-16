// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 S2Arm contributors
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 横屏时灵动岛 / 刘海在不在界面的右侧（trailing）。iPhone 横屏时系统给左右两边同样的安全区（灵动岛机型 59 pt），
/// 但传感器只在一边：贴屏幕右缘的浮窗、设置页可以不扣右边的安全区，只有传感器转到右边时不行，否则右侧的开关被它盖住（PR #452 核出）。
/// 界面朝向 landscapeLeft = 设备顶部（传感器那一端）在右边；竖屏、iPad、Mac 都按「不在右侧」
enum SensorEdge {
    @MainActor static var onTrailing: Bool {
        #if canImport(UIKit) && !os(macOS)
        // 只看手机自己的应用场景：接了外接显示器时多一个外接屏场景（ios/extdisplay.m，iOS 27 起），它的朝向不是手机的（审计 P2-272）
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.session.role == .windowApplication }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return UIDevice.current.userInterfaceIdiom == .phone && scene?.interfaceOrientation == .landscapeLeft
        #else
        return false
        #endif
    }
}

/// 贴屏幕右缘的页面（壳设置页、手柄页）横向不扣安全区，只有灵动岛转到右边时右侧照扣。旋转时页面本身的输入不变、不一定重画，
/// 所以朝向放进状态里，出现时和每次设备转向时更新
struct TrailingOverlaySafeArea: ViewModifier {
    @State private var sensorOnTrailing = false
    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(edges: sensorOnTrailing ? [.leading, .bottom] : [.leading, .trailing, .bottom])
            .onAppear { sensorOnTrailing = SensorEdge.onTrailing }
            #if canImport(UIKit) && !os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                sensorOnTrailing = SensorEdge.onTrailing
            }
            #endif
    }
}
