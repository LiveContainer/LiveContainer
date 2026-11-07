import SwiftUI
import SideSign

struct TrollBoxAppleAccountSection: View {
    @StateObject private var manager = TrollBoxAppleAccountManager.shared
    @State private var appleID = ""
    @State private var password = ""

    var body: some View {
        Section {
            if manager.isSignedIn {
                if let account = manager.account {
                    HStack {
                        Text("Apple Account")
                        Spacer()
                        Text(account.appleID)
                            .foregroundColor(.secondary)
                    }
                }

                if !manager.teams.isEmpty {
                    Picker("Developer Team", selection: $manager.selectedTeamID) {
                        ForEach(manager.teams) { team in
                            Text("\(team.name) (\(team.type.displayName))")
                                .tag(Optional(team.identifier))
                        }
                    }
                } else {
                    Text("No developer teams were returned.")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Teams") {
                    Task {
                        do {
                            try await manager.refreshTeams()
                        } catch {
                            manager.errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(manager.isBusy)

                Button("Sign Out", role: .destructive) {
                    manager.signOut()
                }
            } else {
                TextField("Apple Account email", text: $appleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)

                SecureField("Password", text: $password)

                Button {
                    Task {
                        await manager.signIn(
                            appleID: appleID.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password
                        )
                        if manager.isSignedIn {
                            password = ""
                        }
                    }
                } label: {
                    if manager.isBusy {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(
                    manager.isBusy ||
                    appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    password.isEmpty
                )
            }

            if manager.isBusy {
                ProgressView("Connecting to Apple…")
            }

            if let error = manager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Apple Account")
        }
        .onAppear {
            Task {
                await manager.restoreSession()
            }
        }
        .sheet(
            isPresented: Binding(
                get: { manager.pendingTwoFactorRequest != nil },
                set: { presented in
                    if !presented {
                        manager.completeTwoFactor(.cancel)
                    }
                }
            )
        ) {
            TrollBoxTwoFactorView(manager: manager)
        }
    }
}

private struct TrollBoxTwoFactorView: View {
    @ObservedObject var manager: TrollBoxAppleAccountManager
    @Environment(\.dismiss) private var dismiss
    @State private var verificationCode = ""

    private var request: TwoFactorRequest? {
        manager.pendingTwoFactorRequest
    }

    var body: some View {
        NavigationView {
            Form {
                if let request {
                    switch request {
                    case .selectDeliveryMethod(let preferredMode, let phoneNumbers):
                        Section {
                            Text("Choose how Apple should verify your identity.")
                                .foregroundStyle(.secondary)

                            Button("Use Trusted Apple Device") {
                                manager.completeTwoFactor(.requestTrustedDevice)
                            }

                            ForEach(phoneNumbers) { phone in
                                Button("Send SMS to \(phone.number)") {
                                    manager.completeTwoFactor(
                                        .requestSMS(phoneID: phone.id)
                                    )
                                }

                                Button("Call \(phone.number)") {
                                    manager.completeTwoFactor(
                                        .requestVoice(phoneID: phone.id)
                                    )
                                }
                            }
                        } header: {
                            Text("Verification Method")
                        } footer: {
                            Text("Preferred method: \(preferredMode.rawValue)")
                        }

                    case .trustedDevice(let error):
                        verificationEntry(
                            title: "Trusted Device",
                            message: "Enter the verification code shown on your trusted Apple device.",
                            error: error
                        )

                    case .sms(let phoneNumbers, let activeID, let error):
                        verificationEntry(
                            title: "SMS Verification",
                            message: "Enter the code sent to \(phoneNumbers.first(where: { $0.id == activeID })?.number ?? "your trusted phone").",
                            error: error
                        )
                        deliveryOptions(phoneNumbers)

                    case .voice(let phoneNumbers, let activeID, let error):
                        verificationEntry(
                            title: "Phone Verification",
                            message: "Enter the code from the call to \(phoneNumbers.first(where: { $0.id == activeID })?.number ?? "your trusted phone").",
                            error: error
                        )
                        deliveryOptions(phoneNumbers)
                    }
                }
            }
            .navigationTitle("Two-Factor Authentication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        manager.completeTwoFactor(.cancel)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func verificationEntry(
        title: String,
        message: String,
        error: String?
    ) -> some View {
        Section {
            Text(message)
                .foregroundStyle(.secondary)

            TextField("Verification code", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            Button("Verify") {
                manager.completeTwoFactor(
                    .verificationCode(verificationCode)
                )
            }
            .disabled(verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(title)
        }
    }

    @ViewBuilder
    private func deliveryOptions(_ phoneNumbers: [TrustedPhoneNumber]) -> some View {
        if !phoneNumbers.isEmpty {
            Section("Other Verification Options") {
                Button("Use Trusted Apple Device") {
                    manager.completeTwoFactor(.requestTrustedDevice)
                }

                ForEach(phoneNumbers) { phone in
                    Button("Send SMS to \(phone.number)") {
                        manager.completeTwoFactor(
                            .requestSMS(phoneID: phone.id)
                        )
                    }

                    Button("Call \(phone.number)") {
                        manager.completeTwoFactor(
                            .requestVoice(phoneID: phone.id)
                        )
                    }
                }
            }
        }
    }
}
