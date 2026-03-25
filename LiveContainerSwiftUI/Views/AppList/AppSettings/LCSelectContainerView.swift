//
//  LCSelectContainerView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/12/6.
//

import SwiftUI

protocol LCSelectContainerViewDelegate {
    func addContainers(containers: Set<String>)
}

struct LCSelectContainerView : View{
    @State private var multiSelection = Set<String>()
    @State private var unusedContainers : [LCContainer] = []
    @Binding var isPresent : Bool
    public var delegate : LCSelectContainerViewDelegate

    @EnvironmentObject private var sharedModel : SharedModel
    
    var body: some View {
        NavigationView {
            List(selection: $multiSelection) {
                ForEach(unusedContainers, id: \.folderName) { container in
                    VStack(alignment: .leading) {
                        Text(container.name)
                        Text("\(container.folderName) - \(container.appIdentifier ?? "lc.container.selectUnused.unknownApp".loc)")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    }
                }
                if unusedContainers.count == 0 {
                    Text("lc.container.selectUnused.noUnused".loc)
                }
            }
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresent = false
                    } label: {
                        Text("lc.common.cancel".loc)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if multiSelection.count > 0 {
                        Button {
                            isPresent = false
                            delegate.addContainers(containers: multiSelection)
                        } label: {
                            Text("lc.common.done".loc)
                        }
                    }
                }
                
            }
            .navigationTitle(Text("lc.container.selectUnused".loc))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear() {
            loadUnusedContainers()
        }
        
    }
    
    func loadUnusedContainers() {
        // load document folders
        var appDataFolderNames: [String] = []
        multiSelection.removeAll()
        unusedContainers = []
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: LCPath.dataPath, withIntermediateDirectories: true)
            let dataDirs = try fm.contentsOfDirectory(atPath: LCPath.dataPath.path)
            for dataDir in dataDirs {
                let dataDirUrl = LCPath.dataPath.appendingPathComponent(dataDir)
                if !dataDirUrl.hasDirectoryPath {
                    continue
                }
                appDataFolderNames.append(dataDir)
            }
        } catch {
            
        }

        
        var folderNameToAppDict : [String:LCAppModel] = [:]
        for app in sharedModel.apps {
            for container in app.appInfo.containers {
                folderNameToAppDict[container.folderName] = app;
            }
        }
        for app in sharedModel.hiddenApps {
            for container in app.appInfo.containers {
                folderNameToAppDict[container.folderName] = app;
            }
        }
        
        var unusedFolders : [String]  = []
        for appDataFolderName in appDataFolderNames {
            if folderNameToAppDict[appDataFolderName] == nil {
                unusedFolders.append(appDataFolderName)
            }
        }
        
        unusedContainers = unusedFolders.map { folder in
            let ans = LCContainer(folderName: folder, name: folder, isShared: false)
            ans.loadName()
            return ans;
        }
        
    }
}
