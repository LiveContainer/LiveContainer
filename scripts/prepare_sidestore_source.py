"""Apply the signing overlay to one pinned personal SideStore build; never publishes upstream."""
import hashlib,json,pathlib,shutil,subprocess,sys
root=pathlib.Path(__file__).resolve().parent.parent
source=pathlib.Path(sys.argv[1]).resolve()
expected=(root/'Integrations/SideStore/SOURCE_COMMIT').read_text().strip()
actual=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
assert actual==expected, 'SideStore source revision changed; review signing integration before rebuilding'
operation=source/'SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift'
s=operation.read_text(encoding='utf-8')
anchor='        let appBundleURL = try await self.prepareAppBundle(for: appBundle, profiles: profiles, appexBundleIds: context.appexBundleIds ?? [:])'
assert s.count(anchor)==1
s=s.replace(anchor, '        let lcosOriginalBundleIdentifier = self.context.bundleIdentifier\n'+anchor+'\n        try SigningBundleIdentifiers.validateBundle(at: appBundleURL)\n        try LCOSSigningInjection.prepare(at: appBundleURL, bundleIdentifier: lcosOriginalBundleIdentifier)')
anchor='        let newBundleID = appexBundleIds[identifier] ?? profile.bundleIdentifier'
assert s.count(anchor)==1
s=s.replace(anchor, '''        if context.useMainProfile, identifier != context.targetBundleIdentifier, appexBundleIds[identifier] == nil {
            throw OperationError.invalidParameters("Missing extension bundle ID mapping for " + identifier)
        }
'''+anchor)
operation.write_text(s,encoding='utf-8')

extension_operation=source/'SideStore/Core/Operations/PipelineOperations/PrepareAppExtensionBundleIDsOperation.swift'
s=extension_operation.read_text(encoding='utf-8')
start=s.index('        if self.context.useMainProfile {')
end=s.index('        self.setProgress(100)',start)
s=s[:start]+'''        if self.context.useMainProfile {
            guard let appBundle = self.context.targetAppBundle,
                  let profile = self.context.provisioningProfiles?[self.context.targetBundleIdentifier] else {
                throw OperationError.invalidParameters("Missing main profile for extension bundle ID preparation")
            }
            self.context.appexBundleIds = try SigningBundleIdentifiers.extensionMap(
                originalParent: appBundle.bundleIdentifier, targetParent: self.context.targetBundleIdentifier,
                signedParent: profile.bundleIdentifier, extensions: appBundle.appExtensions.map { $0.bundleIdentifier })
        }
'''+s[end:]
extension_operation.write_text(s,encoding='utf-8')

executor=source/'SideStore/Core/Operations/PipelineExecutor.swift'
s=executor.read_text(encoding='utf-8')
anchor='''                let step = try UserCustomizationOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil'''
assert s.count(anchor)==1
s=s.replace(anchor,'''                let step = try UserCustomizationOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                switch appOperation {
                case .install, .update, .reinstall:
                    if let handler = context.handler as? PipelineHandler {
                        try await handler.configureLCOSInjection(identifier: context.bundleIdentifier, appName: downloadingApp.name)
                    }
                default: break
                }
                return nil''')
executor.write_text(s,encoding='utf-8')
handler=source/'SideStore/Handlers/PipelineHandler.swift'
s=handler.read_text(encoding='utf-8')
anchor='    let isResignActive: Bool'
assert s.count(anchor)==1
s=s.replace(anchor,'''    @MainActor
    func configureLCOSInjection(identifier: String, appName: String) async throws {
        guard let presenter = self.activePresenter else { return }
        try await LCOSSigningInjectionUI.configure(identifier: identifier, appName: appName, presenter: presenter)
    }

'''+anchor)
handler.write_text(s,encoding='utf-8')
destination=source/'SideStore/Core/LCOSSigningInjection';destination.mkdir(exist_ok=True)
files=[root/'Integrations/SideStore'/name for name in ['LCOSSigningInjection.swift','LCOSSigningInjectionUI.swift']]+[root/'LiveContainerSwiftUI/PackageManager/Core'/name for name in ['SigningMachO.swift','SigningInjectionPreset.swift','SigningBundleIdentifiers.swift','PackageSHA256.swift']]
for file in files:shutil.copyfile(file,destination/file.name)
manifest={'schema':1,'resign_operation_sha256':hashlib.sha256(operation.read_bytes()).hexdigest(),'repository':'LiveContainer/SideStore','commit':actual,'overlay':{file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in files},'signing_phase':'after bundle preparation, before ALTSigner.signApp'}
manifest['install_ui']={'executor_sha256':hashlib.sha256(executor.read_bytes()).hexdigest(),'handler_sha256':hashlib.sha256(handler.read_bytes()).hexdigest(),'phase':'manual install/update/reinstall customization; no background refresh UI'}
manifest['extension_ids']={'prepare_sha256':hashlib.sha256(extension_operation.read_bytes()).hexdigest(),'validate_before_signing':True}
(source/'LCOS_SOURCE.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
