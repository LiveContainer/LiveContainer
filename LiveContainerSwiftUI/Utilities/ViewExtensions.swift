//
//  ViewExtensions.swift
//  LiveContainer
//
//  Created by s s on 2026/3/20.
//

import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import SafariServices
import Security
import Combine

struct SafariView: UIViewControllerRepresentable {
    let url: Binding<URL>
    func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> SFSafariViewController {
        return SFSafariViewController(url: url.wrappedValue)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
        
    }
}

// https://stackoverflow.com/questions/56726663/how-to-add-a-textfield-to-alert-in-swiftui
extension View {

    public func textFieldAlert(
        isPresented: Binding<Bool>,
        title: String,
        text: Binding<String>,
        placeholder: String = "",
        action: @escaping (String?) -> Void,
        actionCancel: @escaping (String?) -> Void
    ) -> some View {
        self.modifier(TextFieldAlertModifier(isPresented: isPresented, title: title, text: text, placeholder: placeholder, action: action, actionCancel: actionCancel))
    }
    
    public func betterFileImporter(
        isPresented: Binding<Bool>,
        types : [UTType],
        multiple : Bool = false,
        callback: @escaping ([URL]) -> (),
        onDismiss: @escaping () -> Void
    ) -> some View {
        self.modifier(DocModifier(isPresented: isPresented, types: types, multiple: multiple, callback: callback, onDismiss: onDismiss))
    }
    
    func betterContextMenu(menuProvider: @escaping () -> UIMenu) -> some View {
        self.modifier(UIKitContextMenuModifier(menuProvider: menuProvider))
    }
    
    func onBackground(_ f: @escaping () -> Void) -> some View {
        self.onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification),
            perform: { _ in f() }
        )
    }
    
    func onForeground(_ f: @escaping () -> Void) -> some View {
        self.onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification),
            perform: { _ in f() }
        )
    }
    
    func rainbow() -> some View {
        self.modifier(RainbowAnimation())
    }
    
    func navigationBarProgressBar(show: Binding<Bool>, progress: Binding<Float>) -> some View {
        self.modifier(NavigationBarProgressModifier(show: show, progress: progress))
    }
    
    func modifier<ModifiedContent: View>(@ViewBuilder body: (_ content: Self) -> ModifiedContent
    ) -> ModifiedContent {
        body(self)
    }
}

public struct DocModifier: ViewModifier {
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State private var docController: UIDocumentPickerViewController?
    @State private var delegate : UIDocumentPickerDelegate
    
    @Binding var isPresented: Bool

    var callback: ([URL]) -> ()
    private let onDismiss: () -> Void
    private let types : [UTType]
    private let multiple : Bool
    
    init(isPresented : Binding<Bool>, types : [UTType], multiple : Bool, callback: @escaping ([URL]) -> (), onDismiss: @escaping () -> Void) {
        self.callback = callback
        self.onDismiss = onDismiss
        self.types = types
        self.multiple = multiple
        self.delegate = Coordinator(callback: callback, onDismiss: onDismiss)
        self._isPresented = isPresented
    }

    public func body(content: Content) -> some View {
        content.onChange(of: isPresented) { isPresented in
            if isPresented, docController == nil {
                let controller = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
                controller.allowsMultipleSelection = multiple
                controller.delegate = delegate
                self.docController = controller
                sceneDelegate.window?.rootViewController?.present(controller, animated: true)
            } else if !isPresented, let docController = docController {
                docController.dismiss(animated: true)
                self.docController = nil
            }
        }
    }

    private func shutdown() {
        isPresented = false
        docController = nil
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var callback: ([URL]) -> ()
        private let onDismiss: () -> Void
        
        init(callback: @escaping ([URL]) -> Void, onDismiss: @escaping () -> Void) {
            self.callback = callback
            self.onDismiss = onDismiss
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            callback(urls)
            onDismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDismiss()
        }
    }

}

public struct TextFieldAlertModifier: ViewModifier {
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State private var alertController: UIAlertController?

    @Binding var isPresented: Bool

    let title: String
    let text: Binding<String>
    let placeholder: String
    let action: (String?) -> Void
    let actionCancel: (String?) -> Void

    public func body(content: Content) -> some View {
        content.onChange(of: isPresented) { isPresented in
            if isPresented, alertController == nil {
                let alertController = makeAlertController()
                self.alertController = alertController
                sceneDelegate.window?.rootViewController?.present(alertController, animated: true)
            } else if !isPresented, let alertController = alertController {
                alertController.dismiss(animated: true)
                self.alertController = nil
            }
        }
    }

    private func makeAlertController() -> UIAlertController {
        let controller = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        controller.addTextField {
            $0.placeholder = self.placeholder
            $0.text = self.text.wrappedValue
            $0.clearButtonMode = .always
        }
        controller.addAction(UIAlertAction(title: "lc.common.cancel".loc, style: .cancel) { _ in
            self.actionCancel(nil)
            shutdown()
        })
        controller.addAction(UIAlertAction(title: "lc.common.ok".loc, style: .default) { _ in
            self.action(controller.textFields?.first?.text)
            shutdown()
        })
        return controller
    }

    private func shutdown() {
        isPresented = false
        alertController = nil
    }

}

struct NavigationBarProgressModifier: ViewModifier {
    @Binding var show: Bool
    @Binding var progress: Float

    func body(content: Content) -> some View {
        content
            .background(NavigationBarProgressView(show: $show, progress: $progress))
    }
}

private struct NavigationBarProgressView: UIViewControllerRepresentable {
    @Binding var show: Bool
    @Binding var progress: Float

    func makeUIViewController(context: Context) -> ProgressInjectorViewController {
        ProgressInjectorViewController(progress: progress)
    }

    func updateUIViewController(_ uiViewController: ProgressInjectorViewController, context: Context) {
        uiViewController.updateProgress(!show, progress)
    }

    class ProgressInjectorViewController: UIViewController {
        private var progressView: UIProgressView?

        init(progress: Float) {
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            injectProgressView()
        }

        func updateProgress(_ hidden: Bool, _ progress: Float) {
            progressView?.setProgress(progress, animated: false)
            progressView?.isHidden = hidden
        }

        private func injectProgressView() {
            guard let navigationBar = self.navigationController?.navigationBar, progressView == nil else { return }

            let barProgress = UIProgressView(progressViewStyle: .bar)
            barProgress.translatesAutoresizingMaskIntoConstraints = false
            var contentView : UIView? = nil
            for curView in navigationBar.subviews {
                if NSStringFromClass(curView.classForCoder) == "_UINavigationBarContentView" ||
                    NSStringFromClass(curView.classForCoder) == "UIKit.NavigationBarContentView" {
                    contentView = curView
                    break
                }
            }
            if let contentView {
                contentView.addSubview(barProgress)
                NSLayoutConstraint.activate([
                    barProgress.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    barProgress.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    barProgress.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                ])
            }
            self.progressView = barProgress
        }

    }
}

// https://kieranb662.github.io/blog/2020/04/15/Rainbow
struct RainbowAnimation: ViewModifier {
    // 1
    @State var isOn: Bool = false
    let hueColors = stride(from: 0, to: 1, by: 0.01).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }
    // 2
    var duration: Double = 4
    var animation: Animation {
        Animation
            .linear(duration: duration)
            .repeatForever(autoreverses: false)
    }

    func body(content: Content) -> some View {
    // 3
        let gradient = LinearGradient(gradient: Gradient(colors: hueColors+hueColors), startPoint: .leading, endPoint: .trailing)
        return content.overlay(GeometryReader { proxy in
            ZStack {
                gradient
    // 4
                    .frame(width: 2*proxy.size.width)
    // 5
                    .offset(x: self.isOn ? -proxy.size.width : 0)
            }
        })
    // 6
        .onAppear {
            withAnimation(self.animation) {
                self.isOn = true
            }
        }
        .mask(content)
    }
}

struct BasicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}


private struct UIKitContextMenuModifier : ViewModifier {
    let menuProvider: () -> UIMenu
    
    func body(content: Content) -> some View {
        UIKitContextMenuContainer(menuProvider: menuProvider, content: content)
    }
}

private struct UIKitContextMenuContainer<Content: View>: UIViewControllerRepresentable {
    let menuProvider: () -> UIMenu
    let content: Content

    init(menuProvider: @escaping () -> UIMenu,  content: Content) {
        self.menuProvider = menuProvider
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(menuProvider: menuProvider)
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        if #available(iOS 16.0, *) {
            controller.sizingOptions = [.intrinsicContentSize]
        }
        controller.view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return controller
    }

    func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
        uiViewController.rootView = content
        context.coordinator.menuProvider = menuProvider
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context) -> CGSize? {
        let targetSize = CGSize(
            width: proposal.width ?? UIView.layoutFittingCompressedSize.width,
            height: proposal.height ?? UIView.layoutFittingCompressedSize.height
        )

        return uiViewController.sizeThatFits(in: targetSize)
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var menuProvider: () -> UIMenu

        init(menuProvider: @escaping () -> UIMenu) {
            self.menuProvider = menuProvider
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                self.menuProvider()
            }
        }
    }
}
