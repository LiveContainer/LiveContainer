"""Exercise the production SideStore bridge with a controlled SDK-built app on macOS."""
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
out = root / 'artifacts' / 'signing-bridge'
out.mkdir(parents=True, exist_ok=True)
core = root / 'LiveContainerSwiftUI' / 'PackageManager' / 'Core'
stub = out / 'BridgeStub.o'
subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-c', str(root / 'Tests/SigningIntegration/BridgeStub.m'),
                '-o', str(stub)], check=True)
sources = [core / name for name in ['SigningMachO.swift', 'SigningInjectionPreset.swift', 'PackageSHA256.swift']]
sources += [root / 'Integrations/SideStore/LCOSSigningInjection.swift', root / 'Integrations/SideStore/LCOSSigningInjectionUI.swift', root / 'Tests/SigningIntegration/Main.swift']
binary = out / 'SigningBridgeTest'
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources), str(stub),
                '-framework', 'Foundation', '-o', str(binary)], check=True)
with tempfile.TemporaryDirectory(prefix='shared-group-', dir=out) as group:
    subprocess.run([str(binary), str(root / 'artifacts/device-probe')], check=True,
                   env={**os.environ, 'LCOS_TEST_GROUP': group})
