//
//  LCAppIconPickerView.swift
//  LiveContainerSwiftUI
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

private struct LCIconChoice: Identifiable {
    let name: String?
    let label: String
    let image: UIImage

    var id: String { name ?? "" }
}

struct LCAppIconPickerView: View {
    @ObservedObject var model: LCAppModel

    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) var darkModeIcon = false

    @State private var choices: [LCIconChoice] = []
    @State private var customChoice: LCIconChoice?
    @State private var importerShow = false
    @State private var photoPickerShow = false
    @State private var errorShow = false
    @State private var errorInfo = ""

    @Environment(\.presentationMode) private var presentationMode

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 20)]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(choices) { choice in
                        iconCell(choice)
                    }
                    if let customChoice {
                        iconCell(customChoice)
                    }
                }
                .padding()

                Menu {
                    Button {
                        photoPickerShow = true
                    } label: {
                        Label("lc.appSettings.chooseFromPhotos".loc, systemImage: "photo")
                    }
                    Button {
                        importerShow = true
                    } label: {
                        Label("lc.appSettings.chooseFromFiles".loc, systemImage: "folder")
                    }
                } label: {
                    Label("lc.appSettings.chooseCustomIcon".loc, systemImage: "photo.badge.plus")
                }
                .padding(.bottom)

                if choices.count <= 1 && customChoice == nil {
                    Text("lc.appSettings.noAlternateIcons".loc)
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("lc.appSettings.appIcon".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("lc.common.done".loc) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .fileImporter(isPresented: $importerShow, allowedContentTypes: [.image]) { result in
            importCustomIcon(result: result)
        }
        .sheet(isPresented: $photoPickerShow) {
            PhotoIconPicker { image in
                setCustomIcon(image)
            }
            .ignoresSafeArea()
        }
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {})
        } message: {
            Text(errorInfo)
        }
        .onAppear {
            loadChoices()
        }
    }

    @ViewBuilder
    private func iconCell(_ choice: LCIconChoice) -> some View {
        let isSelected = model.uiCustomIconName == choice.name

        Button {
            model.uiCustomIconName = choice.name
        } label: {
            VStack(spacing: 6) {
                IconImageView(icon: choice.image)
                    .frame(width: 70, height: 70)
                    .overlay {
                        RoundedRectangle(cornerRadius: 70 * 0.2667)
                            .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                    }
                Text(choice.label)
                    .font(.caption)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadChoices() {
        var newChoices: [LCIconChoice] = []

        // generated directly; iconIsDarkIcon would return the override instead
        if let bundlePath = model.appInfo.bundlePath(),
           let defaultIcon = UIImage.generateIcon(forBundleURL: URL(fileURLWithPath: bundlePath),
                                                  style: darkModeIcon ? .Dark : .Light,
                                                  hasBorder: true) {
            newChoices.append(LCIconChoice(name: nil, label: "lc.common.default".loc, image: defaultIcon))
        }

        for name in model.availableIconNames {
            if let image = model.appInfo.image(forIconName: name) {
                newChoices.append(LCIconChoice(name: name, label: name, image: image))
            }
        }

        choices = newChoices
        loadCustomChoice()
    }

    private func loadCustomChoice() {
        if let image = UIImage(contentsOfFile: model.appInfo.customIconPath()) {
            customChoice = LCIconChoice(name: LCCustomIconName,
                                        label: "lc.appSettings.customIcon".loc,
                                        image: image)
        } else {
            customChoice = nil
        }
    }

    private func importCustomIcon(result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                throw "lc.appSettings.customIconReadErr".loc
            }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let image = UIImage(contentsOfFile: url.path) else {
                throw "lc.appSettings.customIconReadErr".loc
            }
            setCustomIcon(image)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    private func setCustomIcon(_ image: UIImage?) {
        guard let image else {
            errorInfo = "lc.appSettings.customIconReadErr".loc
            errorShow = true
            return
        }
        do {
            try model.setCustomIcon(image: image.resizedForIcon())
            loadCustomChoice()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
}

// Not SwiftUI's PhotosPicker: that's iOS 16+ and this app targets 15.
private struct PhotoIconPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoIconPicker
        init(_ parent: PhotoIconPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.parent.onPick(object as? UIImage)
                }
            }
        }
    }
}

fileprivate extension UIImage {
    // Center-crops to a square and caps the size. Icons are square, and the
    // image is also embedded verbatim into app clip profiles.
    func resizedForIcon() -> UIImage {
        let shortSide = min(size.width, size.height)
        let target = min(shortSide, 512)
        let canvas = CGSize(width: target, height: target)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            let scale = target / shortSide
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            // overflow on the long axis is clipped by the square canvas
            let origin = CGPoint(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2)
            draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
