//
//  LCDownloadView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2025/1/22.
//

import SwiftUI

public final class DownloadHelper : ObservableObject {
    @Published var downloadProgress : Float = 0.0
    @Published var downloadedSize : Int64 = 0
    @Published var totalSize : Int64 = 0
    @Published var isDownloading = false
    @Published var cancelled = false
    private var downloadTask: URLSessionDownloadTask?
    private var continuation: UnsafeContinuation<(), Never>?
    
    func download(url: URL, to: URL) async throws {
        var ansError: Error? = nil

        await MainActor.run {
            cancelled = false
            
            downloadProgress = 0.0
            downloadedSize = 0
            totalSize = 0
            
            isDownloading = true
        }
        
        await withUnsafeContinuation { c in
            continuation = c
            let session = URLSession(configuration: .default, delegate: DownloadDelegate(progressCallback: { progress, downloaded, total in
                Task{ await MainActor.run {
                    self.downloadProgress = progress
                    self.downloadedSize = downloaded
                    self.totalSize = total
                }}
            }, completeCallback: {tempFileURL, error in
                Task{ await MainActor.run {
                    self.isDownloading = false
                }}
                if let error {
                    print(error)
                    ansError = error
                }
                if let tempFileURL {
                    do {
                        let fm = FileManager.default
                        print(to)
                        try fm.moveItem(at: tempFileURL, to: to)
                    } catch {
                        ansError = error
                    }
                }
                if self.continuation != nil {
                    c.resume()
                }

            }), delegateQueue: .main)

            downloadTask = session.downloadTask(with: url)
            downloadTask?.resume()
        }
        if let ansError {
            throw ansError
        }
    }
    
    func cancel() {
        if let continuation {
            continuation.resume()
        }
        cancelled = true
        continuation = nil
        downloadTask?.cancel()
        isDownloading = false
    }
}

struct DownloadAlert : View {
    @StateObject var helper : DownloadHelper
    var body: some View {
        
        Color.black.opacity(0.2) // Semi-transparent grey background
            .edgesIgnoringSafeArea(.all) // Covers entire screen
        
        VStack {
            Text("lc.download.downloading".loc)
                .font(.headline)
                .padding(.top)
            
            ProgressView(value: helper.downloadProgress, total: 1)
                .padding()
            
            Text("\(formatBytes(helper.downloadedSize)) / \(formatBytes(helper.totalSize))")
                .font(.subheadline)
                .padding(.bottom)
            
            Button(action: cancelDownload) {
                Text("lc.common.cancel".loc)
                    .foregroundColor(.red)
                    .padding(.bottom)
            }
        }
        .frame(width: 300)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding()
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB] // Allow KB, MB, and GB
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func cancelDownload() {
        helper.cancel()
    }
}

public struct DownloadAlertModifier: ViewModifier {
    @ObservedObject var helper : DownloadHelper
    @State var show = false
    
    public func body(content: Content) -> some View {

        ZStack {
            content
            if show {
                DownloadAlert(helper: helper)
                
            }
            
        }
        .onChange(of: helper.isDownloading) { newVal in
            withAnimation(.easeInOut(duration: 0.1)) {
                show = newVal
            }
        }
    }
}

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressCallback: (Float, Int64, Int64) -> Void
    let completeCallback: (URL?, Error?) -> Void

    init(progressCallback: @escaping (Float, Int64, Int64) -> Void,
         completeCallback: @escaping (URL?, Error?) -> Void) {
        self.progressCallback = progressCallback
        self.completeCallback = completeCallback
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        progressCallback(progress, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode

            // Check if the status code is in the 2xx range
            if (200...299).contains(statusCode) {
                completeCallback(location, nil)
            } else {
                completeCallback(location, NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(statusCode)"]))
            }
        } else {
            completeCallback(location, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }
        

    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completeCallback(nil, error)
        } else {

        }
    }
}

extension View {
    public func downloadAlert(helper: DownloadHelper) -> some View {
        self.modifier(DownloadAlertModifier(helper: helper))
    }
}
