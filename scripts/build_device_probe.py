"""Build a real controlled guest IPA and rootful/rootless test DEBs on macOS/Xcode."""
import gzip
import io
import pathlib
import plistlib
import subprocess
import tarfile
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
out = root / 'artifacts' / 'device-probe'
app = out / 'Payload' / 'LCOSProbe.app'
app.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
common = ['xcrun', '--sdk', 'iphoneos', 'clang', '-arch', 'arm64', '-isysroot', sdk,
          '-miphoneos-version-min=15.0', '-fobjc-arc', '-framework', 'UIKit', '-framework', 'Foundation']
subprocess.run(common + [str(root / 'Tests/DeviceProbe/Guest.m'), '-o', str(app / 'LCOSProbe')], check=True)
subprocess.run(common + ['-dynamiclib', str(root / 'Tests/DeviceProbe/Tweak.m'), '-Wl,-install_name,@rpath/LCOSProbe.dylib',
                        '-o', str(out / 'LCOSProbe.dylib')], check=True)
(app / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'org.example.lcosguest', 'CFBundleExecutable': 'LCOSProbe',
    'CFBundleName': 'LCOS Probe', 'CFBundleDisplayName': 'LCOS Probe', 'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0', 'CFBundlePackageType': 'APPL', 'MinimumOSVersion': '15.0',
    'UIDeviceFamily': [1, 2], 'UILaunchScreen': {}}))
with zipfile.ZipFile(out / 'LCOSProbe.ipa', 'w', zipfile.ZIP_DEFLATED) as ipa:
    for path in app.iterdir():
        ipa.write(path, path.relative_to(out).as_posix())

def tar_gz(files):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for name, data in files.items():
            entry = tarfile.TarInfo(name); entry.size = len(data); entry.mode = 0o644
            archive.addfile(entry, io.BytesIO(data))
    return gzip.compress(stream.getvalue(), mtime=0)

for layout, prefix in [('rootful', ''), ('rootless', 'var/jb/')]:
    control = f'Package: org.example.lcosprobe\nName: LCOS Hook Probe\nVersion: 1.0\nArchitecture: {"iphoneos-arm64" if prefix else "iphoneos-arm"}\nDescription: Controlled manual hook validation\n'.encode()
    directory = prefix + 'Library/MobileSubstrate/DynamicLibraries/'
    files = {directory + 'LCOSProbe.dylib': (out / 'LCOSProbe.dylib').read_bytes(),
             directory + 'LCOSProbe.plist': plistlib.dumps({'Filter': {'Bundles': ['org.example.lcosguest']}})}
    members = {'debian-binary': b'2.0\n', 'control.tar.gz': tar_gz({'control': control}), 'data.tar.gz': tar_gz(files)}
    result = b'!<arch>\n'
    for name, data in members.items():
        result += f'{name + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode() + data
        if len(data) % 2: result += b'\n'
    (out / f'LCOSProbe-{layout}.deb').write_bytes(result)
print('Built device probe in', out)
