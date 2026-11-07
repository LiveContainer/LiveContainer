import SwiftUI
import SideSign

struct TrollBoxAnisetteSettingsSection: View {
    @StateObject private var manager = TrollBoxAnisetteManager.shared

    var body: some View {
        Section {
            if manager.isLoadingServers {
                ProgressView("Loading Anisette servers…")
            }

            if manager.servers.isEmpty {
                Text("No servers loaded.")
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "Anisette Server",
                    selection: $manager.selectedServerAddress
                ) {
                    ForEach(manager.servers) { server in
                        Text(server.name.isEmpty ? server.address : server.name)
                            .tag(server.address)
                    }
                }

                Toggle(
                    "Automatic Server Rotation",
                    isOn: $manager.automaticRotation
                )

                Text(
                    manager.automaticRotation
                    ? "Other servers will be tried if the selected server fails."
                    : "Only the selected server will be used."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let lastServer = manager.lastSuccessfulServer {
                HStack {
                    Text("Last Successful Server")
                    Spacer()
                    Text(URL(string: lastServer)?.host ?? lastServer)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let status = manager.statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button {
                Task {
                    await manager.loadServers()
                }
            } label: {
                Label("Refresh Anisette Servers", systemImage: "arrow.clockwise")
            }
            .disabled(manager.isLoadingServers)
        } header: {
            Text("Anisette Configuration")
        } footer: {
            Text("Choose which Anisette server TrollBox uses for Apple Account authentication.")
        }
        .task {
            await manager.loadServers()
        }
    }
}