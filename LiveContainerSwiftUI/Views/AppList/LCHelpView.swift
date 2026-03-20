//
//  LCHelpView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2025/1/4.
//

import SwiftUI

struct LCHelpView : View {
    @Binding var isPresent : Bool
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("lc.helpView.text1")
                    Text("")
                    Text("lc.helpView.text2")
                }
                .padding()
            }
            .navigationTitle("lc.helpView.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem {
                    Button("lc.common.done") {
                        isPresent = false
                    }
                }
            }
        }
    }
}
