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
        ZStack {
            
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            Form {
                
                Section {
                    VStack(spacing: 20) {
                        Spacer(minLength: 5)
                        
                        
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: selectedImage ?? app.appInfo.iconIsDarkIcon(false) ?? UIImage(systemName: "app.dashed")!)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) 
                                .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
                                .overlay(
                                    
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                            
                            
                            if #available(iOS 16.0, *) {
                                PhotosPicker(selection: Binding(
                                    get: { self.internalItemSelection as? PhotosPickerItem },
                                    set: { self.internalItemSelection = $0 }
                                ), matching: .images) {
                                    Image(systemName: "pencil.circle.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .font(.system(size: 32))
                                        .background(Circle().fill(Color(UIColor.secondarySystemGroupedBackground)))
                                        .offset(x: 10, y: 10)
                                }
                            }
                        }
                        
                        VStack(spacing: 4) {
                            Text(app.appInfo.displayName())
                                .font(.headline)
                            Text(app.appInfo.bundleIdentifier() ?? "")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer(minLength: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear) 
                }
                
                
                Section(header: Text("EDIT INFO")) {
                    HStack {
                        Label("Display Name", systemImage: "character.cursor.ibeam")
                            .font(.subheadline)
                        Spacer()
                        TextField("Enter name", text: $newName)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.accentColor)
                    }
                }
                
                
                Section {
                    Button(role: .destructive) {
                        resetToDefault()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset To Default")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit App Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    saveChanges()
                    dismiss()
                }
                
            }
        }
    }
    .onChange(of: String(describing: internalItemSelection)) { _ in
        handleImageSelection()
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
    if let img = selectedImage {
        LCAppCustomizer.setCustomIcon(for: bid, image: img)
    }
    onSave()
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

