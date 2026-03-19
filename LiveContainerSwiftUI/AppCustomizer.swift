import UIKit
import SwiftUI

struct LCAppCustomizer {
    static let fileManager = FileManager.default
    static let customIconDir = LCPath.docPath.appendingPathComponent("CustomIcons", isDirectory: true)

    
    static func getCustomName(for bundleId: String, defaultName: String) -> String {
        return LCUtils.appGroupUserDefault.string(forKey: "LC_CustomName_\(bundleId)") ?? defaultName
    }

    
    static func setCustomName(for bundleId: String, name: String?) {
        if let name = name, !name.isEmpty {
            LCUtils.appGroupUserDefault.set(name, forKey: "LC_CustomName_\(bundleId)")
        } else {
            LCUtils.appGroupUserDefault.removeObject(forKey: "LC_CustomName_\(bundleId)")
        }
    }

    
    static func getCustomIcon(for bundleId: String) -> UIImage? {
        let iconURL = customIconDir.appendingPathComponent("\(bundleId).png")
        if fileManager.fileExists(atPath: iconURL.path) {
            return UIImage(contentsOfFile: iconURL.path)
        }
        return nil
    }

    
    static func setCustomIcon(for bundleId: String, image: UIImage?) {
        let iconURL = customIconDir.appendingPathComponent("\(bundleId).png")
        
        
        if !fileManager.fileExists(atPath: customIconDir.path) {
            try? fileManager.createDirectory(at: customIconDir, withIntermediateDirectories: true)
        }

        if let image = image {
            
            if let data = image.pngData() {
                try? data.write(to: iconURL)
            }
        } else {
            try? fileManager.removeItem(at: iconURL)
        }
    }
}

import SwiftUI
import PhotosUI

struct LCEditAppView: View {
    let app: LCAppModel
    @Environment(\.dismiss) var dismiss
    
    @State private var newName: String
    @State private var selectedImage: UIImage?
    
    
    @State private var internalImageSelection: Any? = nil 

    var onSave: () -> Void

    init(app: LCAppModel, onSave: @escaping () -> Void) {
        self.app = app
        self.onSave = onSave
        let bid = app.appInfo.bundleIdentifier() ?? ""
        _newName = State(initialValue: LCAppCustomizer.getCustomName(for: bid, defaultName: app.appInfo.displayName()))
        _selectedImage = State(initialValue: LCAppCustomizer.getCustomIcon(for: bid))
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 16) {
                        if #available(iOS 16.0, *) {
                            
                            PhotosPicker(selection: Binding(
                                get: { self.internalImageSelection as? PhotosPickerItem },
                                set: { self.internalImageSelection = $0 }
                            ), matching: .images) {
                                VStack(spacing: 12) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(uiImage: selectedImage ?? app.appInfo.iconIsDarkIcon(false) ?? UIImage(systemName: "app.dashed")!)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                                        
                                        
                                    }
                                    
                                    Text("Change Icon")
                                        .font(.headline)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            
                            Text("Icon editing requires iOS 16+")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 4) {
                            Text(app.appInfo.displayName())
                                .font(.headline)
                            
                            Text(app.appInfo.bundleIdentifier() ?? "")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                }
                
                Section(header: Text("EDIT INFO")) {
                    HStack {
                        Label("Display Name", systemImage: "character.cursor.ibeam")
                            .font(.subheadline)
                        Spacer()
                        TextField("Enter Name", text: $newName)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.accentColor)
                    }
                }
                
                Section {
                    Button(role: .destructive, action: resetToDefault) {
                        HStack {
                            Spacer()
                            Text("Reset To Default")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit App Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        
            .onChange(of: internalImageSelection != nil) { isSelected in
                if isSelected { handleImageSelection() }
            }
        }
    }

    private func handleImageSelection() {
        if #available(iOS 16.0, *) {
            guard let item = internalImageSelection as? PhotosPickerItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.selectedImage = uiImage
                    }
                }
            }
        }
    }

    private func resetToDefault() {
        let bid = app.appInfo.bundleIdentifier() ?? ""
        LCAppCustomizer.setCustomName(for: bid, name: nil)
        LCAppCustomizer.setCustomIcon(for: bid, image: nil)
        onSave()
        dismiss()
    }

    private func saveChanges() {
        let bid = app.appInfo.bundleIdentifier() ?? ""
        LCAppCustomizer.setCustomName(for: bid, name: newName)
        LCAppCustomizer.setCustomIcon(for: bid, image: selectedImage)
        onSave()
    }
}
struct LCGroupEditView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sortManager: LCAppSortManager
    @EnvironmentObject var sharedModel: SharedModel
    
    @State private var selectedApps = Set<String>()
    @State private var showAddGroupAlert = false
    @State private var newGroupName = ""
    @State private var searchText = "" 

    var body: some View {
        NavigationView {
            List {
                
                Section(header: Text("Group List")) {
                    ForEach(sortManager.customGroups.keys.sorted(), id: \.self) { name in
                        HStack {
                            Image(systemName: "folder").foregroundColor(.accentColor)
                            Text(name)
                            Spacer()
                            Text("\(sortManager.customGroups[name]?.count ?? 0) App")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        withAnimation {
                            let keys = sortManager.customGroups.keys.sorted()
                            indexSet.forEach { sortManager.customGroups.removeValue(forKey: keys[$0]) }
                        }
                    }
                }

                
                Section(header: Text("Select App (\(selectedApps.count))")) {
                    TextField("Search App...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .listRowSeparator(.hidden)
                    
                    ForEach(filteredApps, id: \.self) { app in
                        let bid = app.appInfo.bundleIdentifier() ?? ""
                        let currentGroup = findCurrentGroup(for: bid)
                        
                        HStack {
                            Image(systemName: selectedApps.contains(bid) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(selectedApps.contains(bid) ? .accentColor : .secondary)
                            
                            if let icon = app.appInfo.iconIsDarkIcon(false) {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(app.appInfo.displayName()).font(.body)
                                if let group = currentGroup {
                                    Text(group).font(.caption2).foregroundColor(.blue)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggleSelection(for: bid) }
                    }
                }
            }
            .navigationTitle("Manage Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            
            
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showAddGroupAlert = true }) {
                            Label("New Group", systemImage: "folder.badge.plus")
                        }

                        if !selectedApps.isEmpty {
                            Divider()
                            
                            
                            
Button(action: {
    withAnimation {
        for bid in selectedApps {
           
            sortManager.pinnedBundleIds.insert(bid) 
        }
        selectedApps.removeAll()
    }
}) {
    Label("Add to Favorites", systemImage: "star.fill")
}


                            Divider()

                            Section("Move To Group") {
                                ForEach(sortManager.customGroups.keys.sorted(), id: \.self) { name in
                                    Button(name) { moveToGroup(name) }
                                }
                            }
                            
                            Button(role: .destructive) {
                                moveToGroup(nil) 
                            } label: {
                                Label("Remove From Group", systemImage: "minus.circle")
                            }
                        }
                    } label: {
                        Image(systemName: selectedApps.isEmpty ? "folder.badge.plus" : "ellipsis.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            } 
        }
            .textFieldAlert(
                isPresented: $showAddGroupAlert,
                title: selectedApps.isEmpty ? "New Group" : "Move to New Group",
                text: $newGroupName,
                placeholder: "Enter Name",
                action: { name in
                    if let name = name, !name.isEmpty {
                        withAnimation {
                            sortManager.customGroups[name] = []
                            if !selectedApps.isEmpty { moveToGroup(name) }
                            newGroupName = ""
                        }
                    }
                },
                actionCancel: { _ in newGroupName = "" }
            )
        
    }

    
    private var filteredApps: [LCAppModel] {
        if searchText.isEmpty {
            return sharedModel.apps
        } else {
            return sharedModel.apps.filter { $0.appInfo.displayName().localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func toggleSelection(for bid: String) {
        if selectedApps.contains(bid) {
            selectedApps.remove(bid)
        } else {
            selectedApps.insert(bid)
        }
    }

    private func moveToGroup(_ groupName: String?) {
        withAnimation {
            sortManager.moveApps(selectedApps, to: groupName)
            selectedApps.removeAll() 
        }
    }

    private func findCurrentGroup(for bid: String) -> String? {
        for (name, ids) in sortManager.customGroups {
            if ids.contains(bid) { return name }
        }
        return nil
    }
}
