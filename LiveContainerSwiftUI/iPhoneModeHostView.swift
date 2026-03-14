import SwiftUI

struct IPhoneModeHostView: View {
    let app: LCAppModel 
    @State var show = true
    @State var pid = 0
    
    
    let fixedRatio: CGFloat = 9.0 / 16.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                
                Color.black.ignoresSafeArea()

                
                AppSceneViewSwiftUI(
                    show: $show,
                    bundleId: app.appInfo.relativeBundlePath,
                    dataUUID: app.appInfo.dataUUID ?? "",
                    
                    initSize: CGSize(width: geometry.size.height * fixedRatio, height: geometry.size.height),
                    onAppInitialize: { pid, error in
                        if error == nil {
                            self.pid = Int(pid)
                        }
                    }
                )
                
                .aspectRatio(fixedRatio, contentMode: .fit)
                
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.all, edges: .all)
        .navigationBarHidden(true) 
    }
}
