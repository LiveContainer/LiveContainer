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
s=s.replace(anchor, '        let lcosOriginalBundleIdentifier = self.context.bundleIdentifier\n'+anchor+'\n        try LCOSSigningInjection.prepare(at: appBundleURL, bundleIdentifier: lcosOriginalBundleIdentifier)')
operation.write_text(s,encoding='utf-8')

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
files=[root/'Integrations/SideStore'/name for name in ['LCOSSigningInjection.swift','LCOSSigningInjectionUI.swift']]+[root/'LiveContainerSwiftUI/PackageManager/Core'/name for name in ['SigningMachO.swift','SigningInjectionPreset.swift','PackageSHA256.swift']]
for file in files:shutil.copyfile(file,destination/file.name)
manifest={'schema':1,'resign_operation_sha256':hashlib.sha256(operation.read_bytes()).hexdigest(),'repository':'LiveContainer/SideStore','commit':actual,'overlay':{file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in files},'signing_phase':'after bundle preparation, before ALTSigner.signApp'}
manifest['install_ui']={'executor_sha256':hashlib.sha256(executor.read_bytes()).hexdigest(),'handler_sha256':hashlib.sha256(handler.read_bytes()).hexdigest(),'phase':'manual install/update/reinstall customization; no background refresh UI'}
(source/'LCOS_SOURCE.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
