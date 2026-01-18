//
//  LCJITLessDiagnose.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/12/19.
//
import SwiftUI

struct LCEntitlementView : View {
    @State var loaded = false
    @State var entitlementReadSuccess = false
    
    @State var teamId : String?
    @State var getTaskAllow = false
    @State var keyChainAccessGroup = false
    @State var correctBundleId : String?
    @State var isBundleIdCorrect = false
    @State var appGroup = false
    
    @State var entitlementContent = "Failed to Load Entitlement."
    
    var body: some View {
        if loaded {
            Form {
                Section {
                    HStack {
                        Text("lc.jitlessDiag.bundleId".loc)
                        Spacer()
                        Text(Bundle.main.bundleIdentifier ?? "lc.common.unknown".loc)
                            .foregroundStyle(entitlementReadSuccess && teamId != nil ? (isBundleIdCorrect ? .green : .red): .gray)
                            .textSelection(.enabled)
                    }
                    
                    if entitlementReadSuccess {
                        if !isBundleIdCorrect && teamId != nil {
                            HStack {
                                Text("lc.jitlessDiag.bundleIdExpected".loc)
                                Spacer()
                                Text(correctBundleId ?? "lc.common.unknown".loc)
                                    .foregroundStyle(.gray)
                            }
                        }
                        HStack {
                            Text("lc.jitlessDiag.teamId".loc)
                            Spacer()
                            Text(teamId ?? "lc.common.unknown".loc)
                                .foregroundStyle(.gray)
                        }
                        HStack {
                            Text("get-task-allow")
                            Spacer()
                            Text(getTaskAllow ? "lc.common.yes".loc : "lc.common.no".loc)
                                .foregroundStyle(getTaskAllow ? .green : .red)
                        }
                        HStack {
                            Text("com.apple.security.application-groups \("lc.common.correct".loc)")
                            Spacer()
                            Text(appGroup ? "lc.common.yes".loc : "lc.common.no".loc)
                                .foregroundStyle(appGroup ? .green : .red)
                        }
                        HStack {
                            Text("keychain-access-groups \("lc.common.correct".loc)")
                            Spacer()
                            Text(keyChainAccessGroup ? "lc.common.yes".loc : "lc.common.no".loc)
                                .foregroundStyle(keyChainAccessGroup ? .green : .red)
                        }

                    }
                }

                
                Section {
                    Button {
                        UIPasteboard.general.string = entitlementContent
                    } label: {
                        Text("lc.common.copy".loc)
                    }
                    Text(entitlementContent)
                        .font(.system(.subheadline, design: .monospaced))
                }
            }
            .navigationTitle("lc.jielessDiag.entitlement".loc)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("lc.common.loading".loc)
                .onAppear() {
                    onAppear()
                }
        }
    }
    
    func onAppear() {
        if loaded {
            return
        }
        
        defer {
            loaded = true
        }
        
        guard let entitlementXML = getLCEntitlementXML() else {
            entitlementContent = "Failed to load entitlement."
            return
        }
        entitlementContent = entitlementXML
        
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let entitlementDict = try? PropertyListSerialization.propertyList(from: entitlementXML.data(using: .utf8) ?? Data(), format: &format) as? [String : AnyObject] else {
            return
        }
        entitlementReadSuccess = true
        let entitlementTeamId = entitlementDict["com.apple.developer.team-identifier"] as? String
        teamId = entitlementTeamId
        if let entitlementTeamId {
            if let appGroups = entitlementDict["com.apple.security.application-groups"] as? Array<String> {
                if appGroups.count > 0 {
                    appGroup = true
                }
            }
            if let keyChainAccessGroups = entitlementDict["keychain-access-groups"] as? Array<String> {
                var notFound = true
                if keyChainAccessGroups.contains("\(entitlementTeamId).com.kdt.livecontainer.shared") {
                    notFound = false
                    for i in 1..<SharedModel.keychainAccessGroupCount {
                        if !keyChainAccessGroups.contains("\(entitlementTeamId).com.kdt.livecontainer.shared.\(i)") {
                            notFound = true
                            continue
                        }
                    }
                }
                keyChainAccessGroup = !notFound
            }
        }
        if let appIdentifier = entitlementDict["application-identifier"] as? String, appIdentifier.count > 11 {
            let startIndex = appIdentifier.index(appIdentifier.startIndex, offsetBy: 11)
            correctBundleId = String(appIdentifier[startIndex...])
            if let bundleId = Bundle.main.bundleIdentifier {
                isBundleIdCorrect = bundleId == correctBundleId
            }
        }
        
        getTaskAllow = entitlementDict["get-task-allow"] as? Bool ?? false

    }
    
}

struct LCJITLessDiagnoseView : View {
    @State var loaded = false
    @State var appGroupId = "Unknown"
    @State var store : Store = .SideStore
    @State var certificateDataFound = false
    @State var certificatePasswordFound = false
    @State var appGroupAccessible = false
    @State var certTeamId : String?
    @State var expectedTeamId : String?
    @State var certLastUpdateDateStr : String? = nil
    @State var certificateStatus : Int = -1
    @State var certificateValidateUntil : String? = nil
    
    @State var isJITLessTestInProgress = false
    
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    let storeName = LCUtils.getStoreName()
    
    var body: some View {
        if loaded {
            Form {
                Section {
                    HStack {
                        Text("lc.jitlessDiag.bundleId".loc)
                        Spacer()
                        Text(Bundle.main.bundleIdentifier ?? "lc.common.unknown".loc)
                            .foregroundStyle(.gray)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Text("lc.jitlessDiag.appGroupId".loc)
                        Spacer()
                        Text(appGroupId)
                            .foregroundStyle(appGroupId == "Unknown" ? .red : .green)
                    }
                    HStack {
                        Text("lc.jitlessDiag.appGroupAccessible".loc)
                        Spacer()
                        Text(appGroupAccessible ? "lc.common.yes".loc : "lc.common.no".loc)
                            .foregroundStyle(appGroupAccessible ? .green : .red)
                    }
                    HStack {
                        Text("lc.jitlessDiag.store".loc)
                        Spacer()
                        if store == .AltStore {
                            Text("AltStore")
                                .foregroundStyle(.gray)
                        } else if store == .SideStore {
                            Text("SideStore")
                                .foregroundStyle(.gray)
                        } else if store == .ADP {
                            Text("lc.common.ADP".loc)
                                .foregroundStyle(.gray)
                        } else {
                            Text("lc.common.unknown".loc)
                                .foregroundStyle(.gray)
                        }
                        
                    }
                    NavigationLink {
                        LCEntitlementView()
                    } label: {
                        Text("lc.jielessDiag.entitlement".loc)
                    }
                }
                    
                Section() {
                    HStack {
                        Text("lc.jitlessDiag.certDataFound".loc)
                        Spacer()
                        Text(certificateDataFound ? "lc.common.yes".loc : "lc.common.no".loc)
                            .foregroundStyle(certificateDataFound ? .green : .red)
                        
                    }
                    HStack {
                        Text("lc.jitlessDiag.certPassFound".loc)
                        Spacer()
                        Text(certificatePasswordFound ? "lc.common.yes".loc : "lc.common.no".loc)
                            .foregroundStyle(certificatePasswordFound ? .green : .red)
                    }
                    
                    HStack {
                        Text("lc.jitlessDiag.certLastUpdate".loc)
                        Spacer()
                        if let certLastUpdateDateStr {
                            Text(certLastUpdateDateStr)
                                .foregroundStyle(.green)
                        } else {
                            Text("lc.common.unknown".loc)
                                .foregroundStyle(.red)
                        }
                        
                    }
                    if certificateDataFound && certTeamId != nil && certTeamId != expectedTeamId {
                        HStack {
                            Text("lc.jitlessDiag.expectedTeamId".loc)
                            Spacer()
                            Text(expectedTeamId ?? "lc.common.unknown".loc)
                                .foregroundStyle(.gray)
                        }
                    }
                    if certificateDataFound {
                        HStack {
                            Text("lc.jitlessDiag.certTeamId".loc)
                            Spacer()
                            Text(certTeamId ?? "lc.common.unknown".loc)
                                .foregroundStyle(certTeamId != nil && certTeamId == expectedTeamId ? .green : .red)
                        }
                        HStack {
                            Text("lc.jitlessDiag.certificateStatus".loc)
                            Spacer()
                            Text(certificateStatus == -1 ? "lc.jitlessDiag.checking".loc : getStatusText(status: certificateStatus))
                                .foregroundStyle(certificateStatus == 0 ? .green : .red)
                        }
                        HStack {
                            Text("lc.jitlessDiag.certificateValidateUntil".loc)
                            Spacer()
                            Text(certificateValidateUntil != nil ? certificateValidateUntil! : "lc.common.unknown".loc)
                                .foregroundStyle(certificateStatus == 0 ? .green : .red)
                        }
                    }
                    
                }
                                
                Section {
                    Button {
                        testJITLessMode()
                    } label: {
                        Text("lc.settings.testJitLess".loc)
                    }
                    .disabled(isJITLessTestInProgress)
                    
                    Button {
                        getHelp()
                    } label: {
                        // we apply a super cool rainbow effect so people will never miss this button
                        Text("lc.jitlessDiag.getHelp".loc)
                            .bold()
                            .rainbow()
                    }
                }

            }
            .navigationTitle("lc.settings.jitlessDiagnose".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onAppear()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    
                }
            }
            .alert("lc.common.error".loc, isPresented: $errorShow){
            } message: {
                Text(errorInfo)
            }
            .alert("lc.common.success".loc, isPresented: $successShow){
            } message: {
                Text(successInfo)
            }
            
        } else {
            Text("lc.common.loading".loc)
                .onAppear() {
                    onAppear()
                }
        }

    }
    
    func onAppear() {
        appGroupId = LCUtils.appGroupID() ?? "lc.common.unknown".loc
        store = LCUtils.store()
        appGroupAccessible = LCUtils.appGroupPath() != nil
        certificateDataFound = LCUtils.certificateData() != nil
        certificatePasswordFound = LCUtils.certificatePassword() != nil
        if let lastUpdateDate = LCUtils.appGroupUserDefault.object(forKey: "LCCertificateUpdateDate") as? Date {
            let formatter1 = DateFormatter()
            formatter1.dateStyle = .short
            formatter1.timeStyle = .medium
            certLastUpdateDateStr = formatter1.string(from: lastUpdateDate)
        }
        if certificateDataFound {
            validateCertificate()
        }
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil), let teamId = value.takeRetainedValue() as? String else {
            errorInfo = "Failed to read com.apple.developer.team-identifier"
            errorShow = true
            return
        }
        expectedTeamId = teamId
        
        loaded = true
    }
    
    func testJITLessMode() {
        if !certificateDataFound {
            errorInfo = "lc.settings.error.certNotImported".loc
            errorShow = true
            return;
        }

        isJITLessTestInProgress = true
        LCUtils.validateJITLessSetup { success, error in
            if success {
                successInfo = "lc.jitlessSetup.success".loc
                successShow = true
            } else {
                errorInfo = "lc.jitlessSetup.error.testLibLoadFailed %@ %@ %@".localizeWithFormat(storeName, storeName, storeName) + "\n" + (error?.localizedDescription ?? "")
                errorShow = true
            }
            isJITLessTestInProgress = false
        }
    
    }
    
    func getHelp() {
        UIApplication.shared.open(URL(string: "https://github.com/khanhduytran0/LiveContainer/issues/265#issuecomment-2558409380")!)
    }
    
    func validateCertificate() {
        certificateStatus = -1
        certificateValidateUntil = nil
        
        Task {
            do {
                let certWrapper = try LCCertWrapper.initWithCertData(LCUtils.certificateData(), password: LCUtils.certificatePassword())
                if let date = certWrapper.notValidAfter {
                    let formatter1 = DateFormatter()
                    formatter1.dateStyle = .short
                    formatter1.timeStyle = .medium
                    certificateValidateUntil = formatter1.string(from: date)
                }
                if let ou = certWrapper.organizationalUnit {
                    certTeamId = ou
                }
                let statusStr = try certWrapper.checkValidity()
                if statusStr == "Valid" {
                    certificateStatus = 0
                } else {
                    certificateStatus = 1
                }

            } catch {
                errorInfo = error.localizedDescription.loc
                errorShow = true
                certificateStatus = 2
            }
        }
    }
    
    func getStatusText(status: Int) -> String {
        switch status {
        case 0:
            return "lc.jitlessDiag.certificateValid".loc
        case 1:
            return "lc.jitlessDiag.certificateRevoked".loc
        default:
            return "lc.common.unknown".loc
        }
    }
}
