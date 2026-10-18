"""Capture actual simulator UI. Fixture bundles are test-only metadata, never release resources."""
import json
import pathlib
import plistlib
import shutil
import subprocess
import time
import sys

root = pathlib.Path(__file__).resolve().parent.parent
out = root / 'artifacts' / 'home-preview'
out.mkdir(parents=True, exist_ok=True)

def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)

component = '--component' in sys.argv
app = root / ('artifacts/home-preview-build/LCOSHomePreview.app' if component else 'preview-build/Build/Products/Debug-iphonesimulator/LiveContainer.app')
info = plistlib.loads((app / 'Info.plist').read_bytes())
bundle = info['CFBundleIdentifier']
entitlements = out / 'simulator.entitlements'
entitlements.write_bytes(plistlib.dumps({'application-identifier': 'AAAAA11111.' + bundle, 'get-task-allow': True}))
run('codesign', '--force', '--deep', '--sign', '-', '--entitlements', str(entitlements), str(app))
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
candidates = [(runtime, item) for runtime, items in devices.items() for item in items if 'iPhone' in item['name'] and item['isAvailable']]
runtime, template = candidates[-1]
device_types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '-j']))['devicetypes']
kind = next(item['identifier'] for item in device_types if item['name'] == template['name'])
udid = subprocess.check_output(['xcrun', 'simctl', 'create', 'LCOS Home Preview', kind, runtime], text=True).strip()
try:
    run('xcrun', 'simctl', 'boot', udid)
    run('xcrun', 'simctl', 'bootstatus', udid, '-b')
    run('xcrun', 'simctl', 'install', udid, str(app))
    data = pathlib.Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, bundle, 'data'], text=True).strip())
    icons = out / 'fixture-icons'
    run('swift', str(root / 'Tests/HomeScreenPreview/MakeIcons.swift'), str(icons))
    names = ['Notes', 'Camera', 'Music', 'Maps', 'Books', 'Audio', 'Sketch', 'Mail', 'Files', 'Calendar', 'Photos', 'Player']
    ids = []
    for i, name in enumerate(names):
        folder = f'Preview{i}.app'
        identifier = f'org.example.homepreview.{i}'
        target = data / 'Documents/Applications' / folder
        target.mkdir(parents=True, exist_ok=True)
        (target / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier, 'CFBundleName': name,
            'CFBundleDisplayName': name, 'CFBundleExecutable': 'Preview', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0'}))
        for style in ['Light', 'Dark']:
            shutil.copyfile(icons / f'{i}.png', target / f'LCAppIcon{style}.png')
        ids.append(identifier + ':' + folder)
    layout = json.dumps({'version': 1, 'order': ids, 'dock': ids[-4:]})
    captures = [('light', 'YES', 'desktop-light.png'), ('dark', 'YES', 'desktop-dark.png')]
    if not component:
        captures.append(('light', 'NO', 'app-list.png'))
    for appearance, enabled, filename in captures:
        run('xcrun', 'simctl', 'ui', udid, 'appearance', appearance)
        subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle], capture_output=True)
        run('xcrun', 'simctl', 'launch', udid, bundle, '-LCOSHomeScreenEnabled', enabled,
            '-LCOSHomeLayout', layout, '-LCBundleIdChecked', 'YES', '-LCCertificateTeamId', 'AAAAA11111', '-AppleLanguages', '(en)')
        time.sleep(7)
        run('xcrun', 'simctl', 'io', udid, 'screenshot', str(out / filename))
    (out / 'README.txt').write_text('Screenshots render the production Home Screen and icon artwork source in a native component fixture host with test-only registry adapters and generated SF Symbol icons. Fixture apps are not production-installed apps. Original launch controllers, guest signing and tweak injection are not tested by these screenshots. The full host compiles for simulator but its launch was denied by SBMainWorkspace.\n', encoding='utf-8')
finally:
    subprocess.run(['xcrun', 'simctl', 'shutdown', udid], capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'delete', udid], capture_output=True)
