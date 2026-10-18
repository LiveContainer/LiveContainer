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
destination=source/'SideStore/Core/LCOSSigningInjection';destination.mkdir(exist_ok=True)
files=[root/'Integrations/SideStore/LCOSSigningInjection.swift']+[root/'LiveContainerSwiftUI/PackageManager/Core'/name for name in ['SigningMachO.swift','SigningInjectionPreset.swift','PackageSHA256.swift']]
for file in files:shutil.copyfile(file,destination/file.name)
manifest={'repository':'LiveContainer/SideStore','commit':actual,'overlay':{file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in files},'signing_phase':'after bundle preparation, before ALTSigner.signApp'}
(source/'LCOS_SOURCE.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
