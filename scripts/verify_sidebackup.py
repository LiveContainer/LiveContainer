"""Verify the embedded helper retains its App Groups declaration before real provisioning/signing."""
import argparse
import io
import plistlib
import struct
import zipfile


def entitlements(binary):
    if binary[:4] != bytes.fromhex('cffaedfe'):
        raise ValueError('SideBackup is not a thin arm64 Mach-O')
    commands = struct.unpack_from('<I', binary, 16)[0]
    offset = 32
    for _ in range(commands):
        command, size = struct.unpack_from('<II', binary, offset)
        if size < 8 or offset + size > len(binary):
            raise ValueError('Invalid SideBackup load commands')
        if command == 0x1d:
            start, length = struct.unpack_from('<II', binary, offset + 8)
            blob = binary[start:start + length]
            if len(blob) < 12 or struct.unpack_from('>I', blob)[0] != 0xfade0cc0:
                raise ValueError('SideBackup code signature is missing')
            count = struct.unpack_from('>I', blob, 8)[0]
            if count > 64 or 12 + 8 * count > len(blob):
                raise ValueError('Invalid SideBackup signature index')
            for index in range(count):
                _, position = struct.unpack_from('>II', blob, 12 + 8 * index)
                magic, total = struct.unpack_from('>II', blob, position)
                if total < 8 or position + total > len(blob):
                    raise ValueError('Invalid SideBackup signature blob')
                if magic == 0xfade7171:
                    return plistlib.loads(blob[position + 8:position + total])
        offset += size
    raise ValueError('SideBackup entitlement declaration is absent; run upstream fakesign')


def verify_embedded_sidebackup(outer):
    resources = [name for name in outer.namelist() if name.endswith('/SideBackup.ipa')]
    if len(resources) != 1:
        raise ValueError('Expected one embedded SideBackup.ipa')
    with zipfile.ZipFile(io.BytesIO(outer.read(resources[0]))) as helper:
        infos = [name for name in helper.namelist() if name.count('/') == 2 and name.endswith('.app/Info.plist')]
        if len(infos) != 1:
            raise ValueError('Invalid embedded SideBackup bundle')
        info = plistlib.loads(helper.read(infos[0]))
        executable = infos[0][:-len('Info.plist')] + info['CFBundleExecutable']
        groups = entitlements(helper.read(executable)).get('com.apple.security.application-groups')
        if not isinstance(groups, list) or not groups or not all(isinstance(group, str) and group.startswith('group.') for group in groups):
            raise ValueError('SideBackup has no App Groups declaration; signing would drop shared-group access')
        return {'app_groups_declared': True, 'device_provisioning_verified': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa')
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as archive:
        print(verify_embedded_sidebackup(archive))
