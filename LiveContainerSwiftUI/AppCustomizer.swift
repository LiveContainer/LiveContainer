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




