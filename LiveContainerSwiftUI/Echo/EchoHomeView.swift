//
//  EchoHomeView.swift
//  Echo Launcher
//

import SwiftUI

struct EchoHomeView: View {
    @StateObject private var store = EchoStore()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Game")) {
                    if let manifest = store.manifest {
                        HStack {
                            Text("Build")
                            Spacer()
                            Text(manifest.game.build).foregroundColor(.secondary)
                        }
                        if store.gameNeedsInstall {
                            Button("Install Fortnite") {
                                Task { await store.installGame() }
                            }
                            .disabled(store.busy)
                        }
                    }
                    Button("Check for updates") {
                        Task { await store.refresh() }
                    }
                    .disabled(store.busy)
                    if !store.status.isEmpty {
                        Text(store.status).font(.footnote).foregroundColor(.secondary)
                    }
                    if store.busy {
                        ProgressView()
                    }
                }
                Section(header: Text("Renderer"), footer: Text("Stock uses the game's own iOS shaders. Echo loads the converted PC shaders. Takes effect the next time the game starts.")) {
                    Picker("Renderer", selection: Binding(get: { store.renderer }, set: { store.setRenderer($0) })) {
                        ForEach(EchoRenderer.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text("Server"), footer: Text("The HTTPS address of the Echo update manifest.")) {
                    TextField("https://", text: $store.manifestAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("Echo")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            if !store.manifestAddress.isEmpty {
                await store.refresh()
            }
        }
    }
}
