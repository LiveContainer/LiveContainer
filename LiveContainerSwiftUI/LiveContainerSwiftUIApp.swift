//
//  LiveContainerSwiftUIApp.swift
//  LiveContainer
//
//  Created by s s on 2025/5/16.
//
import SwiftUI

@main
struct LiveContainerSwiftUIApp : App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State var appDataFolderNames: [String]
    @State var tweakFolderNames: [String]
    
    init() {
        let fm = FileManager()
        var tempAppDataFolderNames : [String] = []
        var tempTweakFolderNames : [String] = []
        
        var tempApps: [LCAppModel] = []
        var tempHiddenApps: [LCAppModel] = []

        do {
            // load apps
            try fm.createDirectory(at: LCPath.bundlePath, withIntermediateDirectories: true)
            let appDirs = try fm.contentsOfDirectory(atPath: LCPath.bundlePath.path)
            for appDir in appDirs {
                if !appDir.hasSuffix(".app") {
                    continue
                }
                let newApp = LCAppInfo(bundlePath: "\(LCPath.bundlePath.path)/\(appDir)")!
                newApp.relativeBundlePath = appDir
                newApp.isShared = false
                if newApp.isHidden {
                    tempHiddenApps.append(LCAppModel(appInfo: newApp))
                } else {
                    tempApps.append(LCAppModel(appInfo: newApp))
                }
            }
            if LCPath.lcGroupDocPath != LCPath.docPath {
                try fm.createDirectory(at: LCPath.lcGroupBundlePath, withIntermediateDirectories: true)
                let appDirsShared = try fm.contentsOfDirectory(atPath: LCPath.lcGroupBundlePath.path)
                for appDir in appDirsShared {
                    if !appDir.hasSuffix(".app") {
                        continue
                    }
                    let newApp = LCAppInfo(bundlePath: "\(LCPath.lcGroupBundlePath.path)/\(appDir)")!
                    newApp.relativeBundlePath = appDir
                    newApp.isShared = true
                    if newApp.isHidden {
                        tempHiddenApps.append(LCAppModel(appInfo: newApp))
                    } else {
                        tempApps.append(LCAppModel(appInfo: newApp))
                    }
                }
            }
            // load document folders
            try fm.createDirectory(at: LCPath.dataPath, withIntermediateDirectories: true)
            let dataDirs = try fm.contentsOfDirectory(atPath: LCPath.dataPath.path)
            for dataDir in dataDirs {
                let dataDirUrl = LCPath.dataPath.appendingPathComponent(dataDir)
                if !dataDirUrl.hasDirectoryPath {
                    continue
                }
                tempAppDataFolderNames.append(dataDir)
            }
            
            // load tweak folders
            try fm.createDirectory(at: LCPath.tweakPath, withIntermediateDirectories: true)
            let tweakDirs = try fm.contentsOfDirectory(atPath: LCPath.tweakPath.path)
            for tweakDir in tweakDirs {
                let tweakDirUrl = LCPath.tweakPath.appendingPathComponent(tweakDir)
                if !tweakDirUrl.hasDirectoryPath {
                    continue
                }
                tempTweakFolderNames.append(tweakDir)
            }
        } catch {
            NSLog("[LC] error:\(error)")
        }
        DataManager.shared.model.apps = tempApps
        DataManager.shared.model.hiddenApps = tempHiddenApps
        _appDataFolderNames = State(initialValue: tempAppDataFolderNames)
        _tweakFolderNames = State(initialValue: tempTweakFolderNames)
    }
    
    var body: some Scene {
        WindowGroup(id: "Main") {
            LCTabView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                .environmentObject(DataManager.shared.model)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            if #available(iOS 16.1, *) {
                GetOpenWindowActionView()
                    .hidden()
            }
        }
        
        if UIApplication.shared.supportsMultipleScenes, #available(iOS 16.1, *) {
            WindowGroup(id: "appView", for: UUID.self) { $id in
                if let id {
                    MultitaskAppWindow(id: id)
                }
            }

        }
    }
    
}
