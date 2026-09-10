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

private class SizedHostingController<Content: View>: UIHostingController<Content> {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let size = sizeThatFits(in: UIView.layoutFittingCompressedSize)
        if preferredContentSize != size {
            preferredContentSize = size
        }
    }
}

struct IconImageView: View {
    var icon: UIImage
    
    var body: some View {
        GeometryReader { g in
            Image(uiImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: g.size.width*0.2667))
        }
    }
}


extension UIViewController {
    func presentConfirmation(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String
    ) async -> Bool? {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else {
            return nil
        }

        return await withUnsafeContinuation { continuation in
            let finishConfirmation =  { (result: Bool?, alert: UIAlertController?) in
                alert?.dismiss(animated: true) {
                    continuation.resume(returning: result)
                }
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { [weak alert] _ in
                finishConfirmation(true, alert)
            })
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { [weak alert] _ in
                finishConfirmation(false, alert)
            })
            present(alert, animated: true)
        }
    }

    func showError(_ message: String) {
        guard viewIfLoaded?.window != nil else {
            return
        }

        let presentError = { [weak self] in
            guard let self else {
                return
            }
            let alert = UIAlertController(title: "lc.common.error".loc, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "lc.common.ok".loc, style: .default))
            alert.addAction(UIAlertAction(title: "lc.common.copy".loc, style: .default) { _ in
                UIPasteboard.general.string = message
            })
            self.present(alert, animated: true)
        }

        if let presentedViewController {
            presentedViewController.dismiss(animated: true, completion: presentError)
        } else {
            presentError()
        }
    }
}
