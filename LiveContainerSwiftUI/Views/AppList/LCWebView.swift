//
//  SwiftUIView.swift
//
//  Created by s s on 2024/8/23.
//

import SwiftUI
@preconcurrency import WebKit

struct LCWebView: View {
    @State private var webView : WebView
    @State private var didAppear = false
    
    @Binding var url : URL
    @Binding var isPresent: Bool
    @State private var loadStatus = 0.0
    @State private var uiLoadStatus = 0.0
    @State private var pageTitle = ""
    @State private var pageURL: URL?
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var showShareSheet = false
    
    @State private var runAppAlert = YesNoHelper()
    @State private var runAppAlertMsg = ""
    
    @State private var installAppAlert = YesNoHelper()
    @State private var installAppAlertMsg = ""
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    @EnvironmentObject private var sharedModel : SharedModel

    private let navigationBarHeight: CGFloat = 60
    private let bottomBarHeight: CGFloat = 64
    
    var itmsServicesHandler: ((String) async -> Void)?
    
    init(url: Binding<URL>, isPresent: Binding<Bool>, itmsServicesHandler: ((String) async -> Void)? = nil) {
        self._webView = State(initialValue: WebView())
        self._url = url
        self._isPresent = isPresent
        self.itmsServicesHandler = itmsServicesHandler
    }
    
    var body: some View {
        
        GeometryReader { geometry in
            ZStack {
                // Extend the web view itself under the bars and the home indicator.
                // Scroll insets keep the first and last page content reachable.
                webView.withContentInsets(UIEdgeInsets(
                    top: geometry.safeAreaInsets.top + navigationBarHeight,
                    left: geometry.safeAreaInsets.leading,
                    bottom: geometry.safeAreaInsets.bottom + bottomBarHeight,
                    right: geometry.safeAreaInsets.trailing
                ))
                .ignoresSafeArea(.container)

                VStack(spacing: 0) {
                    navigationBar
                    Spacer(minLength: 0)
                    bottomBar
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(.systemBackground))
        .onAppear {
            if !didAppear {
                onViewAppear()
                didAppear = true
                webView.loadURL(url: url)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [currentURL])
        }
        .alert("lc.webView.runApp".loc, isPresented: $runAppAlert.show) {
            Button("lc.appBanner.run".loc, action: {
                runAppAlert.close(result: true)
            })
            Button("lc.common.cancel".loc, role: .cancel, action: {
                runAppAlert.close(result: false)
            })
        } message: {
            Text(runAppAlertMsg)
        }
        .alert("lc.webView.installApp".loc, isPresented: $installAppAlert.show) {
            Button("lc.common.install".loc, action: {
                installAppAlert.close(result: true)
            })
            Button("lc.common.cancel".loc, role: .cancel, action: {
                installAppAlert.close(result: false)
            })
        } message: {
            Text(installAppAlertMsg)
        }
        
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        
    }
    
    private var currentURL: URL {
        pageURL ?? url
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button {
                isPresent = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .modifier(LCWebViewGlassBackground(shape: Circle(), isInteractive: true))
            }

            VStack(spacing: 3) {
                Text(pageTitle.isEmpty ? (currentURL.host ?? currentURL.absoluteString) : pageTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 4) {
                    if currentURL.scheme == "https" {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                    }
                    Text(currentURL.host ?? currentURL.absoluteString)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.horizontal, 12)
            .modifier(LCWebViewGlassBackground(shape: Capsule()))
            Button {
                if isLoading {
                    webView.webView.stopLoading()
                } else {
                    webView.reload()
                }
            } label: {
                if isLoading {
                    Image(systemName: "xmark")
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .font(.system(size: 20, weight: .medium))
            .frame(width: 44, height: 44)
            .modifier(LCWebViewGlassBackground(shape: Circle(), isInteractive: true))
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            ProgressView(value: uiLoadStatus)
                .progressViewStyle(.linear)
                .opacity(isLoading ? 1 : 0)
                .scaleEffect(y: 0.5, anchor: .bottom)
                .allowsHitTesting(false)
        }
        .onChange(of: loadStatus) { newValue in
            if newValue > uiLoadStatus {
                withAnimation(.easeInOut(duration: 0.2)) {
                    uiLoadStatus = newValue
                }
            } else {
                uiLoadStatus = newValue
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button(action: webView.goBack) {
                Image(systemName: "chevron.backward")
                    .frame(width: 44, height: 44)
            }
            .disabled(!canGoBack)

            Spacer(minLength: 0)
            Button(action: webView.goForward) {
                Image(systemName: "chevron.forward")
                    .frame(width: 44, height: 44)
            }
            .disabled(!canGoForward)

            Spacer(minLength: 0)
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 44)
            }

            Spacer(minLength: 0)
            Button {
                UIApplication.shared.open(currentURL)
            } label: {
                Image(systemName: "safari")
                    .frame(width: 44, height: 44)
            }
            .disabled(!["http", "https"].contains(currentURL.scheme ?? ""))
        }
        .font(.system(size: 20))
        .frame(maxWidth: 420)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .modifier(LCWebViewGlassBackground(shape: Capsule(), isInteractive: true))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    func onViewAppear() {
        let observer = WebViewLoadObserver(loadStatus: $loadStatus, pageURL: $pageURL, canGoBack: $canGoBack, canGoForward: $canGoForward, isLoading: $isLoading, webView: webView.webView)
        let webViewDelegate = WebViewDelegate(pageTitle: $pageTitle, urlSchemeHandler: onURLSchemeDetected, universalLinkHandler: onUniversalLinkDetected)
        webView.setDelegate(delegete: webViewDelegate)
        webView.setObserver(observer: observer)
    }

    func launchToApp(app: LCAppModel, url: URL) async {
        let bundleId = app.appInfo.relativeBundlePath!
        if let runningLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: app.uiDefaultDataFolder){
            let encodedUrl = Data(url.absoluteString.utf8).base64EncodedString()
            if let urlToOpen = URL(string: "\(runningLC)://livecontainer-launch?bundle-name=\(bundleId)&open-url=\(encodedUrl)"), UIApplication.shared.canOpenURL(urlToOpen) {
                NSLog("[LC] urlToOpen = \(urlToOpen.absoluteString)")
                await UIApplication.shared.open(urlToOpen)
                isPresent = false
                return
            }

        }
        
        do {
            try await app.runApp(urlStr: url.absoluteString)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    public func onURLSchemeDetected(url: URL) async {
        var appToLaunch : LCAppModel? = nil
        var appListsToConsider = [sharedModel.apps]
        
        if url.scheme == "itms-services", let handler = itmsServicesHandler {
            installAppAlertMsg = "lc.webView.installAppDesc"
            
            if let doInstall = await installAppAlert.open(), !doInstall {
                return
            }
            isPresent = false
            Task { await handler(url.absoluteString) }
            return
        }
        
        if sharedModel.isHiddenAppUnlocked || !LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding") {
            appListsToConsider.append(sharedModel.hiddenApps)
        }
        appLoop:
        for appList in appListsToConsider {
            for app in appList {
                if let schemes = app.appInfo.urlSchemes() {
                    for scheme in schemes {
                        if let scheme = scheme as? String, scheme == url.scheme {
                            appToLaunch = app
                            break appLoop
                        }
                    }
                }
            }
        }
    
        
        guard let appToLaunch = appToLaunch else {
            errorInfo = "lc.appList.schemeCannotOpenError %@".localizeWithFormat(url.scheme!)
            errorShow = true
            return
        }
        
        if appToLaunch.appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
            
            do {
                if !(try await LCUtils.authenticateUser()) {
                    return
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
                return
            }
        }
        
        runAppAlertMsg = "lc.webView.pageLaunch %@".localizeWithFormat(appToLaunch.appInfo.displayName()!)
        
        if let doRunApp = await runAppAlert.open(), !doRunApp {
            return
        }
        
        await launchToApp(app: appToLaunch, url: url)
        
    }
    
    public func onUniversalLinkDetected(url: URL, bundleIDs: [String]) async {
        var bundleIDToAppDict: [String: LCAppModel] = [:]
        for app in sharedModel.apps {
            bundleIDToAppDict[app.appInfo.bundleIdentifier()!] = app
        }
        if !LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding") || sharedModel.isHiddenAppUnlocked {
            for app in sharedModel.hiddenApps {
                bundleIDToAppDict[app.appInfo.bundleIdentifier()!] = app
            }
        }
        
        var appToLaunch: LCAppModel? = nil
        for bundleID in bundleIDs {
            if let app = bundleIDToAppDict[bundleID] {
                appToLaunch = app
                break
            }
        }
        guard let appToLaunch = appToLaunch else {
            return
        }
        
        if appToLaunch.appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
            do {
                if !(try await LCUtils.authenticateUser()) {
                    return
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
                return
            }
        }
        
        runAppAlertMsg = "lc.webView.pageCanBeOpenIn %@".localizeWithFormat(appToLaunch.appInfo.displayName()!)
        if let doRunApp = await runAppAlert.open(), !doRunApp {
            return
        }
        await launchToApp(app: appToLaunch, url: url)
    }
}

private struct LCWebViewGlassBackground<S: Shape>: ViewModifier {
    let shape: S
    var isInteractive = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(isInteractive), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

class WebViewLoadObserver: NSObject {
    private var observations: [NSKeyValueObservation] = []

    init(loadStatus: Binding<Double>, pageURL: Binding<URL?>, canGoBack: Binding<Bool>, canGoForward: Binding<Bool>, isLoading: Binding<Bool>, webView: WKWebView) {
        super.init()
        observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { webView, _ in
                loadStatus.wrappedValue = webView.estimatedProgress
            },
            webView.observe(\.url, options: [.initial, .new]) { webView, _ in
                pageURL.wrappedValue = webView.url
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { webView, _ in
                canGoBack.wrappedValue = webView.canGoBack
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { webView, _ in
                canGoForward.wrappedValue = webView.canGoForward
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { webView, _ in
                isLoading.wrappedValue = webView.isLoading
            }
        ]
    }
}

class WebViewDelegate : NSObject,WKNavigationDelegate {
    private var pageTitle: Binding<String>
    private var urlSchemeHandler: (URL) async -> Void
    private var universalLinkHandler: (URL , [String]) async -> Void // url, [String] of all apps that can open this web page
    var domainBundleIdDict : [String:[String]] = [:]
    
    init(pageTitle: Binding<String>, urlSchemeHandler: @escaping (URL) async -> Void, universalLinkHandler: @escaping (URL , [String]) async -> Void) {
        self.pageTitle = pageTitle
        self.urlSchemeHandler = urlSchemeHandler
        self.universalLinkHandler = universalLinkHandler
        super.init()
    }
    
    func webView(_ webView: WKWebView,
                   decidePolicyFor navigationAction: WKNavigationAction,
                   decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler((WKNavigationActionPolicy)(rawValue: WKNavigationActionPolicy.allow.rawValue + 2)!)
        guard let url = navigationAction.request.url, let scheme = navigationAction.request.url?.scheme else {
            return
        }
        if(scheme == "https") {
            Task {
                await self.loadDomainAssociations(url: url)
                if let host = url.host, let appIDs = self.domainBundleIdDict[host] {
                    Task{ await self.universalLinkHandler(url, appIDs) }
                }
            }
            return
        }
        if(scheme == "http" || scheme == "about" || scheme == "itms-apps") {
            return;
        }
        Task{ await urlSchemeHandler(url) }

    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.pageTitle.wrappedValue = webView.title ?? ""
    }
    
    
    func loadDomainAssociations(url: URL) async {
        if url.scheme != "https" || url.host == nil {
            return
        }
        if self.domainBundleIdDict[url.host!] != nil {
            return
        }
        guard let host = url.host else {
            return
        }
        
        // download and read apple-app-site-association
        let appleAppSiteAssociationURLs = [
            URL(string: "https://\(host)/apple-app-site-association")!,
            URL(string: "https://\(host)/.well-known/apple-app-site-association")!
            ]

        await withTaskGroup(of: Void.self) { group in
            for siteAssociationURL in appleAppSiteAssociationURLs {
                group.addTask {
                    await withUnsafeContinuation { c in
                        let task = URLSession.shared.dataTask(with: siteAssociationURL) { data, response, error in
                            do {
                                guard let data = data else {
                                    c.resume()
                                    return
                                }
                                let siteAssociationObj = try JSONDecoder().decode(SiteAssociation.self, from: data)
                                guard let detailItems = siteAssociationObj.applinks?.details else {
                                    c.resume()
                                    return
                                }
                                self.domainBundleIdDict[host] = []
                                for item in detailItems {
                                    self.domainBundleIdDict[host]!.append(contentsOf: item.getBundleIds())
                                }
                            } catch {
                                
                            }
                            c.resume()
                        }
                        
                        task.resume()
                    }
                }
            }
        }

    }
}

struct WebView: UIViewRepresentable {
    
    let webView: WKWebView
    var observer: WebViewLoadObserver?
    var delegate: WKNavigationDelegate?
    private var contentInsets: UIEdgeInsets = .zero
    
    init() {
        self.webView = WKWebView()
    }
    
    mutating func setDelegate(delegete: WKNavigationDelegate) {
        self.delegate = delegete
        self.webView.navigationDelegate = delegete
    }
    
    mutating func setObserver(observer: WebViewLoadObserver) {
        self.observer = observer
    }
    
    func makeUIView(context: Context) -> WKWebView {
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let scrollView = uiView.scrollView
        guard scrollView.contentInset != contentInsets else {
            return
        }
        let isAtTop = scrollView.contentOffset.y <= -scrollView.contentInset.top
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
        if isAtTop {
            scrollView.contentOffset.y = -contentInsets.top
        }
    }

    func withContentInsets(_ insets: UIEdgeInsets) -> WebView {
        var view = self
        view.contentInsets = insets
        return view
    }
    
    func reload() {
        webView.reload()
    }
    
    func goBack(){
        webView.goBack()
    }
    
    func goForward(){
        webView.goForward()
    }
    
    
    func loadURL(url: URL) {
        webView.load(URLRequest(url: url))
    }
    

}

