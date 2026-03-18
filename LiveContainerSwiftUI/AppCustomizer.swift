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
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage?
    
    var onSave: () -> Void

    init(app: LCAppModel, onSave: @escaping () -> Void) {
        self.app = app
        self.onSave = onSave
        _newName = State(initialValue: LCAppCustomizer.getCustomName(for: app.appInfo.bundleIdentifier() ?? "", defaultName: app.appInfo.displayName()))
        _selectedImage = State(initialValue: LCAppCustomizer.getCustomIcon(for: app.appInfo.bundleIdentifier() ?? ""))
    }

    var body: some View {
        NavigationView {
            Form {
                Section("lc.manager.edit.appearance".loc) {
                    HStack {
                        Spacer()
                        VStack {
                            if let img = selectedImage {
                                Image(uiImage: img)
                                    .resizable().frame(width: 80, height: 80).cornerRadius(16)
                            } else {
                                
                                Image(uiImage: app.appInfo.iconIsDarkIcon(false))
                                    .resizable().frame(width: 80, height: 80).cornerRadius(16)
                            }
                            
                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                Text("lc.manager.edit.changeIcon".loc).font(.caption)
                            }
                        }
                        Spacer()
                    }.padding(.vertical)

                    TextField("lc.manager.edit.namePlaceholder".loc, text: $newName)
                }
                
                Section {
                    Button("lc.manager.edit.reset".loc, role: .destructive) {
                        LCAppCustomizer.setCustomName(for: app.appInfo.bundleIdentifier() ?? "", name: nil)
                        LCAppCustomizer.setCustomIcon(for: app.appInfo.bundleIdentifier() ?? "", image: nil)
                        onSave()
                        dismiss()
                    }
                }
            }
            .navigationTitle("lc.manager.edit.title".loc)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("lc.common.done".loc) {
                        LCAppCustomizer.setCustomName(for: app.appInfo.bundleIdentifier() ?? "", name: newName)
                        if let img = selectedImage {
                            LCAppCustomizer.setCustomIcon(for: app.appInfo.bundleIdentifier() ?? "", image: img)
                        }
                        onSave()
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadData() {
                        selectedImage = UIImage(data: data)
                    }
                }
            }
        }
    }
}

