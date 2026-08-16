//
//  LCMultitaskSettingView.swift
//  LiveContainer
//
//  Created by s s on 2026/3/21.
//

import SwiftUI

struct LCMultitaskSettingView: View {
    @AppStorage("LCMultitaskMode", store: LCUtils.appGroupUserDefault) var multitaskMode: MultitaskMode = .virtualWindow
    @AppStorage("LCLaunchInMultitaskMode") var launchInMultitaskMode = false
    @AppStorage("LCLaunchMultitaskMaximized") var launchMultitaskMaximized = false
    @AppStorage("LCMultitaskBottomWindowBar", store: LCUtils.appGroupUserDefault) var bottomWindowBar = false
    @AppStorage("LCMultitaskWindowBarMode", store: LCUtils.appGroupUserDefault) var windowBarMode = MultitaskWindowBarMode.default
    @AppStorage("LCAutoEndPiP", store: LCUtils.appGroupUserDefault) var autoEndPiP = false
    @AppStorage("LCSkipTerminatedScreen", store: LCUtils.appGroupUserDefault) var skipTerminatedScreen = false
    @AppStorage("LCRestartTerminatedApp", store: LCUtils.appGroupUserDefault) var restartTerminatedApp = false
    @AppStorage("LCMaxOneAppOnStage", store: LCUtils.appGroupUserDefault) var onlyOneAppOnStage = false
    @AppStorage("LCDockWidth", store: LCUtils.appGroupUserDefault) var dockWidth: Double = 80
    @AppStorage("LCHideCollapsedDock", store: LCUtils.appGroupUserDefault) var hideCollapsedDock: Bool = false
    @AppStorage("LCRedirectURLToHost", store: LCUtils.appGroupUserDefault) var redirectURLToHost = false
    
    @AppStorage("LCDeveloperMode") var developerMode = false
    @AppStorage("LCSharePrivateDataWithLiveProcess") var sharePrivateDataWithLiveProcess = false
    @AppStorage("LCMultitaskForceLegacyAPI") var forceLegacySceneAPI = false
    @AppStorage("BKNoWatchdogs") var disableLiveProcessWatchdog = false
    
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
                    Picker(selection: $windowBarMode) {
                        Text("lc.settings.windowBarMode.default".loc).tag(MultitaskWindowBarMode.default)
                        Text("lc.settings.windowBarMode.hide".loc).tag(MultitaskWindowBarMode.hidden)
                        Text("lc.settings.windowBarMode.overlay".loc).tag(MultitaskWindowBarMode.overlay)
                    } label: {
                        Text("lc.settings.windowBarMode".loc)
                    }
                    Toggle(isOn: $redirectURLToHost) {
                        Text("lc.settings.redirectURLToHost".loc)
                    }

                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("lc.settings.dockWidth".loc)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(Int(dockWidth))px")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    Slider(value: $dockWidth, in: 20...120) {
                        Text("lc.settings.dockWidth".loc)
                    }
                    .tint(.accentColor)
                }
                .padding(.vertical, 4)
                Toggle(isOn: $hideCollapsedDock) {
                    Text("lc.settings.hideCollapsedDock".loc)
                }
            }
            
            if developerMode {
                Section {
                    Toggle(isOn: $sharePrivateDataWithLiveProcess) {
                        Text("Allow Private Data access from LiveProcess")
                    }
                    Toggle(isOn: $disableLiveProcessWatchdog) {
                        Text("Disable LiveProcess watchdog termination")
                    }
                    if #available(iOS 18.0, *) {
                        Toggle(isOn: $forceLegacySceneAPI) {
                            Text("Force Legacy Scene API ")
                        }
                    }
                } header: {
                    Text("Developer Settings")
                }
            }
        }
        .navigationTitle("lc.appBanner.multitask".loc)
        .navigationBarTitleDisplayMode(.inline)
    }
}
