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
if component:
    run('codesign', '--force', '--sign', '-', str(app))
else:
    entitlements = out / 'simulator.entitlements'
    entitlements.write_bytes(plistlib.dumps({'application-identifier': 'AAAAA11111.' + bundle, 'get-task-allow': True}))
    run('codesign', '--force', '--deep', '--sign', '-', '--entitlements', str(entitlements), str(app))
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
candidates = [(runtime, item) for runtime, items in devices.items() for item in items if 'iPhone' in item['name'] and item['isAvailable']]
runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j']))['runtimes']
versions = {item['identifier']: tuple(int(part) for part in item['version'].split('.')) for item in runtimes}
runtime, template = max(candidates, key=lambda item: (versions.get(item[0], (0,)), 'Pro' in item[1]['name']))
print(f"Preview runtime: {runtime}; device: {template['name']}", flush=True)
device_types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '-j']))['devicetypes']
kind = next(item['identifier'] for item in device_types if item['name'] == template['name'])
udid = subprocess.check_output(['xcrun', 'simctl', 'create', 'LCOS Home Preview', kind, runtime], text=True).strip()
try:
    run('xcrun', 'simctl', 'boot', udid)
    run('xcrun', 'simctl', 'bootstatus', udid, '-b')
    run('open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', udid)
    run('xcrun', 'simctl', 'status_bar', udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100')
    run('xcrun', 'simctl', 'launch', udid, 'com.apple.Preferences')
    run('xcrun', 'simctl', 'io', udid, 'screenshot', str(out / 'simulator-health.png'))
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
    # Keep failure evidence before deleting the temporary device.
    subprocess.run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(out / 'simulator-final.png')], capture_output=True, timeout=30)
    with (out / 'simulator-runtime.log').open('w') as log:
        try:
            subprocess.run(['xcrun', 'simctl', 'spawn', udid, 'log', 'show', '--last', '8m', '--style', 'compact',
                            '--predicate', 'process == "LCOSHomePreview" OR process == "SpringBoard" OR process == "runningboardd" OR process == "amfid"'],
                           stdout=log, stderr=subprocess.STDOUT, timeout=45)
        except subprocess.TimeoutExpired:
            log.write('\nDiagnostic log capture timed out.\n')
    crashes = pathlib.Path.home() / 'Library/Logs/DiagnosticReports'
    for crash in crashes.glob('*'):
        if crash.is_file() and crash.name.startswith(('LCOSHomePreview', 'LiveContainer')):
            shutil.copyfile(crash, out / crash.name)
    subprocess.run(['xcrun', 'simctl', 'shutdown', udid], capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'delete', udid], capture_output=True)
