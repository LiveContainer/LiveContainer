//
//  LCScreenshot.swift
//  LiveContainerSwiftUI
//  Summary (EN): Window / full-screen screenshot to JPEG for visual verification.
//
//  Renders a view to JPEG for the caller (a real picture beats guessing the layout).
//  drawHierarchy gives the real composited result; layer.render is the fallback.
//

import UIKit

enum LCScreenshot {

    /// - Parameters:
    ///   - maxWidth: downscale proportionally beyond this width (saves bandwidth)
    ///   - quality: JPEG quality, 0-1
    static func jpeg(of view: UIView, maxWidth: CGFloat = 1290, quality: CGFloat = 0.7) -> Data? {
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { ctx in
            let drew = view.drawHierarchy(in: bounds, afterScreenUpdates: false)
            if !drew {
                view.layer.render(in: ctx.cgContext)
            }
        }

        let target: UIImage
        if bounds.width > maxWidth {
            let scale = maxWidth / bounds.width
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = 1
            target = UIGraphicsImageRenderer(size: size, format: f).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            target = image
        }
        return target.jpegData(compressionQuality: quality)
    }

    /// When windowId is nil the key window (whole LiveContainer UI) is captured.
    @MainActor
    static func capture(windowId: String?, maxWidth: CGFloat, quality: CGFloat) -> Data? {
        guard let view = LCWindowManager.captureView(windowId) else { return nil }
        return jpeg(of: view, maxWidth: maxWidth, quality: quality)
    }
}
