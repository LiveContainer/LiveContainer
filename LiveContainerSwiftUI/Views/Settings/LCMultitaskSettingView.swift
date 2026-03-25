//
//  LCMultitaskSettingView.swift
//  LiveContainer
//
//  Created by s s on 2026/3/21.
//

import SwiftUI
//⭐️⭐️⭐️
@available(iOS 16.0, *)
struct ControlMenuContent: View {
    let app: DockAppModel
    @EnvironmentObject var dockManager: MultitaskDockManager

    var body: some View {
      
        let _ = dockManager.menuUpdateTrigger 
        let viewController = app.view?._viewDelegate() as? DecoratedAppSceneViewController
        
        Group {
            if let vc = viewController {
                let isInPiP = PiPManager.shared.isPiP(withDecoratedVC: vc)
                let isMax = vc.isMaximized

                Section {
                   
                    if isInPiP {
                        Button {
                            PiPManager.shared.stopPiP()
                        } label: {
                            Label("Restore from PiP", systemImage: "pip.enter")
                        }
                    } else {
                        Button {
                            if let appSceneVC = vc.appSceneVC {
                                PiPManager.shared.startPiP(withVC: appSceneVC)
                            }
                        } label: {
                            Label("Enter PiP Mode", systemImage: "pip.exit")
                        }
                    }

                   
                    Button {
                        vc.maximizeWindow()
                    } label: {
                        Label(isMax ? "Exit FullScreen" : "FullScreen", 
                              systemImage: isMax ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }

                   
                    Button {
                        vc.minimizeWindow()
                    } label: {
                        Label("Minimize", systemImage: "rectangle.stack.badge.minus")
                    }
                }

                Divider()

              
                Section {
                    Button(role: .destructive) {
                        vc.closeWindow()
                        dockManager.removeRunningApp(app.appUUID)
                    } label: {
                        Label("Close App", systemImage: "xmark.circle")
                    }
                }

                Divider()

              
                Button(role: .cancel) {
                    // back
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                
            } else {
                
                Text("Window is unavailable")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct LCMultitaskSettingView: View {
    @AppStorage("LCMultitaskMode", store: LCUtils.appGroupUserDefault) var multitaskMode: MultitaskMode = .virtualWindow
    @AppStorage("LCLaunchInMultitaskMode") var launchInMultitaskMode = false
    @AppStorage("LCLaunchMultitaskMaximized") var launchMultitaskMaximized = false
    @AppStorage("LCMultitaskBottomWindowBar", store: LCUtils.appGroupUserDefault) var bottomWindowBar = false
    @AppStorage("LCAutoEndPiP", store: LCUtils.appGroupUserDefault) var autoEndPiP = false
    @AppStorage("LCSkipTerminatedScreen", store: LCUtils.appGroupUserDefault) var skipTerminatedScreen = false
    @AppStorage("LCRestartTerminatedApp", store: LCUtils.appGroupUserDefault) var restartTerminatedApp = false
    @AppStorage("LCMaxOneAppOnStage", store: LCUtils.appGroupUserDefault) var onlyOneAppOnStage = false
    @AppStorage("LCDockWidth", store: LCUtils.appGroupUserDefault) var dockWidth: Double = 80
    @AppStorage("LCRedirectURLToHost", store: LCUtils.appGroupUserDefault) var redirectURLToHost = false
    
    var body: some View {
        List {
            Section {
                if(UIApplication.shared.supportsMultipleScenes) {
                    Picker(selection: $multitaskMode) {
                        Text("lc.settings.multitaskMode.virtualWindow".loc).tag(MultitaskMode.virtualWindow)
                        Text("lc.settings.multitaskMode.nativeWindow".loc).tag(MultitaskMode.nativeWindow)
                    } label: {
                        Text("lc.settings.multitaskMode".loc)
                    }
                }
                Toggle(isOn: $launchInMultitaskMode) {
                    Text("lc.settings.autoLaunchInMultitaskMode".loc)
                }
                
                if multitaskMode == .virtualWindow {
                    Toggle(isOn: $launchMultitaskMaximized) {
                        Text("lc.settings.launchMultitaskMaximized".loc)
                    }
                    if launchMultitaskMaximized {
                        Toggle(isOn: $onlyOneAppOnStage) {
                            Text("lc.settings.onlyOneAppOnStage".loc)
                        }
                    }
                    Toggle(isOn: $autoEndPiP) {
                        Text("lc.settings.autoEndPiP".loc)
                    }
                    Toggle(isOn: $skipTerminatedScreen) {
                        Text("lc.settings.skipTerminatedScreen".loc)
                    }
                    if skipTerminatedScreen {
                        Toggle(isOn: $restartTerminatedApp) {
                            Text("lc.settings.restartTerminatedApp".loc)
                        }
                    }
                    Toggle(isOn: $bottomWindowBar) {
                        Text("lc.settings.bottomWindowBar".loc)
                    }
                    Toggle(isOn: $redirectURLToHost) {
                        Text("lc.settings.redirectURLToHost".loc)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("lc.settings.dockWidth".loc)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(Int(dockWidth))px")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        Slider(value: $dockWidth, in: 60...110) {
                            Text("lc.settings.dockWidth".loc)
                        }
                        .tint(.accentColor)
                    }
                    .padding(.vertical, 4)
                }
            } 
        }
        .navigationTitle("lc.appBanner.multitask".loc)
        .navigationBarTitleDisplayMode(.inline)
    }
}
