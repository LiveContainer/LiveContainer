//
//  LCHelpView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2025/1/4.
//

import SwiftUI

struct LCHelpView : View {
    @Binding var isPresent : Bool
    @State var helpURL = URL(string: "https://livecontainer.github.io/docs/faq")!
    
    var body: some View {
        SafariView(url: $helpURL)
    }
}
