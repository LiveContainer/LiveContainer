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

import SwiftUI
import PhotosUI

struct LCEditAppView: View {
    let app: LCAppModel
    @Environment(\.dismiss) var dismiss
    
    @State private var newName: String
    @State private var selectedImage: UIImage?
    
   
    @State private var internalItemSelection: Any? = nil 
    
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
                Section("Appearance") {
                    HStack {
                        Spacer()
                        VStack {
                            
                            Image(uiImage: selectedImage ?? app.appInfo.iconIsDarkIcon(false) ?? UIImage(systemName: "app.dashed")!)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .cornerRadius(16)
                            
                            if #available(iOS 16.0, *) {
                            
                                PhotosPicker(selection: Binding(
                                    get: { self.internalItemSelection as? PhotosPickerItem },
                                    set: { self.internalItemSelection = $0 }
                                ), matching: .images) {
                                    Text("Change Icon").font(.caption)
                                }
                            } else {
                                Text("Icon change requires iOS 16").font(.caption).foregroundColor(.gray)
                            }
                        }
                        Spacer()
                    }.padding(.vertical)

                    TextField("Display Name", text: $newName)
                }
                
                Section {
                    Button("Reset to Default", role: .destructive) {
                        let bid = app.appInfo.bundleIdentifier() ?? ""
                        LCAppCustomizer.setCustomName(for: bid, name: nil)
                        LCAppCustomizer.setCustomIcon(for: bid, image: nil)
                        onSave() 
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit App") 
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let bid = app.appInfo.bundleIdentifier() ?? ""
                        LCAppCustomizer.setCustomName(for: bid, name: newName)
                        if let img = selectedImage {
                            LCAppCustomizer.setCustomIcon(for: bid, image: img)
                        }
                        onSave() 
                        dismiss()
                    }
                }
            }
        }
        
        .onChange(of: internalItemSelection == nil) { _ in
            handleImageSelection()
        }
    }

    private func handleImageSelection() {
        if #available(iOS 16.0, *), let item = internalItemSelection as? PhotosPickerItem {
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
}

