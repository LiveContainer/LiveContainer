import SwiftUI

@available(iOS 16.1, *)
struct IPhoneModeHostView: View {
    
    let dataUUID: String
    
    @State var show = true
    @State var pid = 0
    @EnvironmentObject var sharedModel: SharedModel 

    var body: some View {
        
        if let app = (sharedModel.apps + sharedModel.hiddenApps).first(where: { $0.appInfo.dataUUID == dataUUID }) {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    let targetSize = calculateIPhoneSize(in: geometry.size)

                    AppSceneViewSwiftUI(
                        show: $show,
                        bundleId: app.appInfo.relativeBundlePath,
                        dataUUID: app.appInfo.dataUUID ?? "",
                        initSize: targetSize,
                        onAppInitialize: { pid, error in
                            if error == nil { self.pid = Int(pid) }
                        }
                    )
                    .frame(width: targetSize.width, height: targetSize.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
        } else {
            Text("App Not Found")
        }
    }

    func calculateIPhoneSize(in container: CGSize) -> CGSize {
        let ratio: CGFloat = 9.0 / 16.0
        var targetHeight = container.height
        var targetWidth = targetHeight * ratio
        if targetWidth > container.width {
            targetWidth = container.width
            targetHeight = targetWidth / ratio
        }
        return CGSize(width: targetWidth, height: targetHeight)
    }
}
@available(iOS 16.1, *)
struct IPhoneModeWrapperView: View {
    @State private var dataUUID: String? = nil

    var body: some View {
        Group {
            if let uuid = dataUUID {
                IPhoneModeHostView(dataUUID: uuid)
            } else {
                Color.black 
            }
        }
        .onContinueUserActivity("com.livecontainer.iphonemode") { activity in
            if let uuid = activity.userInfo?["dataUUID"] as? String {
                self.dataUUID = uuid
            }
        }
    }
}
