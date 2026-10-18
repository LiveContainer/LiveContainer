"""Compile the production desktop component for native simulator visual QA, with test-only model adapters."""
import json
import pathlib
import plistlib
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'artifacts/home-preview-build/LCOSHomePreview.app'
app.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
sources = ['Tests/HomeScreenPreview/PreviewHost.swift', 'LiveContainerSwiftUI/HomeScreen/Core/LCHomeLayout.swift',
           'LiveContainerSwiftUI/HomeScreen/LCHomeIconArtwork.swift', 'LiveContainerSwiftUI/HomeScreen/LCHomeScreenView.swift']
subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-target', 'arm64-apple-ios15.0-simulator', '-sdk', sdk,
                '-parse-as-library', *[str(root / source) for source in sources], '-o', str(app / 'LCOSHomePreview')], check=True)
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.example.lcoshomepreview',
    'CFBundleExecutable': 'LCOSHomePreview', 'CFBundleName': 'Home Screen Preview', 'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0', 'CFBundlePackageType': 'APPL', 'MinimumOSVersion': '15.0',
    'CFBundleSupportedPlatforms': ['iPhoneSimulator'], 'UIDeviceFamily': [1, 2], 'UILaunchScreen': {}}))
catalog = json.loads((root / 'Resources/Localizable.xcstrings').read_text(encoding='utf-8'))
for language in ['en', 'ru']:
    translations = {key: entry['localizations'][language]['stringUnit']['value'] for key, entry in catalog['strings'].items()
                    if 'stringUnit' in entry.get('localizations', {}).get(language, {})}
    directory = app / (language + '.lproj')
    directory.mkdir(exist_ok=True)
    (directory / 'Localizable.strings').write_bytes(plistlib.dumps(translations, fmt=plistlib.FMT_BINARY))
print('Compiled production Home Screen sources in a fixture-only native preview host')
