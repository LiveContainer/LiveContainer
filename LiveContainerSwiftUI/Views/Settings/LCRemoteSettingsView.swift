//
//  LCRemoteSettingsView.swift
//  LiveContainerSwiftUI
//
//  Remote control (HTTP API) settings: switch / port / token / usage.
//

import SwiftUI
import UIKit

struct LCRemoteSettingsView: View {
    @AppStorage("LCRemoteEnabled", store: LCUtils.appGroupUserDefault) private var enabled: Bool = false
    @AppStorage("LCRemotePort", store: LCUtils.appGroupUserDefault) private var port: Int = 8848

    @State private var token: String = LCRemoteConfig.token
    @State private var portText: String = ""
    @State private var statusText: String = ""
    @State private var errorText: String?
    @State private var copiedRecently = false
    @State private var confirmRegenerate = false

    private var keepAliveMode: LCRemoteKeepAliveMode {
        LCRemoteKeepAliveMode.stored
    }

    private var keepAliveBinding: Binding<LCRemoteKeepAliveMode> {
        Binding(get: { LCRemoteKeepAliveMode.stored },
                set: { newValue in
                    LCRemoteKeepAlive.shared.apply(newValue)
                    refreshStatus()
                })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable HTTP server", isOn: $enabled)
                    .onChange(of: enabled) { newValue in
                        LCRemoteControl.shared.applyEnabled(newValue)
                        refreshStatus()
                    }

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("8848", text: $portText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                    Button("Apply") { applyPort() }
                        .buttonStyle(.borderless)
                        .disabled(Int(portText) == nil || Int(portText) == port)
                }

                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusText)
                        .foregroundColor(LCRemoteControl.shared.isRunning ? .green : .secondary)
                }
            } header: {
                Text("Remote control")
            } footer: {
                Text("The server only listens while LiveContainer is in the foreground; backgrounding suspends the process and requests time out.\nPort range 1024-65535; changing it restarts the server.")
            }

            Section {
                Picker("Keep-alive", selection: keepAliveBinding) {
                    ForEach(LCRemoteKeepAliveMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text("Background keep-alive")
            } footer: {
                Text("iOS drops the socket once the process is suspended. \"Silent audio\" keeps it alive when locked via UIBackgroundModes: audio (costs battery and may mix with the guest app audio); \"screen stays awake\" plus Guided Access (Settings -> Accessibility) is the calmest long-run setup.")
            }

            Section {
                Text(token)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button(copiedRecently ? "Copied" : "Copy token") {
                        UIPasteboard.general.string = token
                        copiedRecently = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedRecently = false
                        }
                    }
                    // Multiple Buttons in one Form/List row cross-fire unless they are borderless
                    // (tapping Copy used to also hit Regenerate, so the copied token was instantly invalid)
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("Regenerate", role: .destructive) {
                        confirmRegenerate = true
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Token")
            } footer: {
                Text("Every request must send Authorization: Bearer <token> (except /health). Regenerating invalidates connected clients immediately.")
            }

            Section {
                Text(usageText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text("Usage")
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Remote Control")
        .alert("Regenerate token?", isPresented: $confirmRegenerate) {
            Button("Regenerate", role: .destructive) {
                token = LCRemoteConfig.regenerateToken()
                LCRemoteControl.shared.restart()
                refreshStatus()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Connected clients stop working immediately and must be reconfigured.")
        }
        .onAppear {
            portText = String(port)
            token = LCRemoteConfig.token
            refreshStatus()
        }
    }

    private var usageText: String {
        let p = String(port)
        let t = token
        return """
        curl http://<device-ip>:\(p)/api/v1/health
        curl -H 'Authorization: Bearer \(t)' http://<device-ip>:\(p)/api/v1/apps
        curl -H 'Authorization: Bearer \(t)' -F 'file=@app.ipa' http://<device-ip>:\(p)/api/v1/apps
        curl -H 'Authorization: Bearer \(t)' 'http://<device-ip>:\(p)/api/v1/logs?since=0&limit=200'
        curl -H 'Authorization: Bearer \(t)' -o shot.jpg http://<device-ip>:\(p)/api/v1/screenshot
        """
    }

    private func applyPort() {
        guard let v = Int(portText), v >= 1024, v <= 65535 else {
            errorText = "Port must be between 1024 and 65535"
            return
        }
        errorText = nil
        LCRemoteConfig.port = UInt16(v)
        LCRemoteControl.shared.restart()
        refreshStatus()
    }

    private func refreshStatus() {
        let control = LCRemoteControl.shared
        if !LCRemoteConfig.isEnabled {
            statusText = "Off"
        } else if control.isRunning {
            statusText = "Running on :\(control.boundPort)"
        } else {
            statusText = "Not running"
        }
        if let err = control.lastError {
            errorText = err
        }
    }
}
