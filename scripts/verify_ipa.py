"""Read-only structural IPA verification. Does not claim device functionality or provisioning validity."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import zipfile
from verify_sidebackup import verify_embedded_sidebackup

def verify(path, integrated=False, source_commit=None, signing_injection=False):
    path = pathlib.Path(path)
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError('IPA is absent or empty')
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Damaged ZIP entry')
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP entries')
        if any(name.startswith('/') or '..' in pathlib.PurePosixPath(name).parts for name in names):
            raise ValueError('Unsafe IPA entry path')
        roots = [name for name in names if name.count('/') == 2 and name.startswith('Payload/') and name.endswith('.app/Info.plist')]
        if len(roots) != 1:
            raise ValueError('Expected exactly one root application')
        root = roots[0][:-len('Info.plist')]
        info = plistlib.loads(archive.read(roots[0]))
        for key in ['CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleVersion', 'MinimumOSVersion']:
            if not info.get(key):
                raise ValueError('Missing Info.plist value: ' + key)
        executable = root + info['CFBundleExecutable']
        if archive.read(executable)[:4] not in [bytes.fromhex('cffaedfe'), bytes.fromhex('cafebabe'), bytes.fromhex('bebafeca')]:
            raise ValueError('Missing Mach-O executable')
        for suffix in ['Frameworks/LiveContainerSwiftUI.framework/LiveContainerSwiftUI',
                       'Frameworks/CydiaSubstrate.framework/CydiaSubstrate', 'Frameworks/TweakLoader.dylib']:
            if root + suffix not in names:
                raise ValueError('Missing required component: ' + suffix)
        if integrated:
            for suffix in ['Frameworks/SideStoreApp.framework/SideStore',
                           'Frameworks/SideStoreApp.framework/Info.plist',
                           'Frameworks/SideStoreSupport.framework/SideStoreSupport',
                           'PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension']:
                if root + suffix not in names:
                    raise ValueError('Missing integrated component: ' + suffix)
            if 'group.com.SideStore.SideStore' not in info.get('ALTAppGroups', []):
                raise ValueError('Missing SideStore app group declaration')
        if signing_injection:
            side = root + 'Frameworks/SideStoreApp.framework/'
            manifest = json.loads(archive.read(side + 'LCOSSigningIntegration.json'))
            if manifest.get('schema') != 1 or len(manifest.get('commit', '')) != 40 or not manifest.get('resign_operation_sha256'):
                raise ValueError('Missing SideStore signing overlay provenance')
            if b'LCOSInjected' not in archive.read(side + 'SideStore'):
                raise ValueError('SideStore binary lacks the signing injection implementation')
            if 'LCOSSigningInjectionUI.swift' not in manifest.get('overlay', {}) or not manifest.get('install_ui'):
                raise ValueError('Missing SideStore installation UI integration provenance')
            if b'LCOSSigningInjectionPresenter' not in archive.read(side + 'SideStore'):
                raise ValueError('SideStore binary lacks the installation UI bridge')
            if not manifest.get('extension_ids', {}).get('validate_before_signing') or 'SigningBundleIdentifiers.swift' not in manifest.get('overlay', {}):
                raise ValueError('Missing extension bundle ID correction provenance')
            verify_embedded_sidebackup(archive)
        return {'file': path.name, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'bundle': info['CFBundleIdentifier'], 'signing_injection': signing_injection, 'integrated': integrated, 'entries': len(names),
                'source_commit': source_commit,
                'verification': 'ZIP integrity and expected components only', 'device_tested': False}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa')
    parser.add_argument('--integrated', action='store_true')
    parser.add_argument('--signing-injection', action='store_true')
    parser.add_argument('--output')
    parser.add_argument('--source-commit')
    args = parser.parse_args()
    evidence = verify(args.ipa, args.integrated, args.source_commit, args.signing_injection)
    result = json.dumps(evidence, indent=2)
    if args.output:
        pathlib.Path(args.output).write_text(result + '\n', encoding='utf-8')
    print(result)
