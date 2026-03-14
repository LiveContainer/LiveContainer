import SwiftUI

@available(iOS 16.1, *)
struct IPhoneModeHostView: View {
    let app: LCAppModel
    @State var show = true
    @State var pid = 0
    
    var body: some View {
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
                .clipped() 
            }
            
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all)
        .navigationBarHidden(true)
    }

    
    func calculateIPhoneSize(in container: CGSize) -> CGSize {
        let ratio: CGFloat = 9.0 / 16.0
        let availableHeight = container.height
        let availableWidth = container.width
        
        var targetHeight = availableHeight
        var targetWidth = targetHeight * ratio
        
        if targetWidth > availableWidth {
            targetWidth = availableWidth
            targetHeight = targetWidth / ratio
        }
        return CGSize(width: targetWidth, height: targetHeight)
    }
}
