import SwiftUI

struct ExploreView: View {
    @State private var searchText = ""

    var body: some View {
        
            ScrollView {
                VStack(spacing: 20) {
                    // 這裡可以放置未來的推廣內容或功能卡片
                    headerSection
                    
                    Spacer().frame(height: 50)
                    
                    Image(systemName: "safari.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                        .opacity(0.3)
                    
                    Text("Explore New Features")
                        .font(.title3.bold())
                        .foregroundColor(.secondary)
                    
                    Text("Stay tuned for upcoming tools and system extensions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            
        }
    
    
    // 預留一個頂部的裝飾區塊
    private var headerSection: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .frame(height: 150)
            .overlay {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Featured")
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                    Text("Welcome to the new Ecosystem")
                        .font(.headline)
                    Text("Discover tweaks and apps specifically optimized for iOS 26.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

