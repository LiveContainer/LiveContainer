"""Deterministic, synthetic hostile and valid Debian parser fixtures (no third-party tweaks)."""
import ctypes
import gzip
import io
import lzma
import pathlib
import plistlib
import struct
import tarfile

ROOT = pathlib.Path(__file__).parent / 'PackageCoreTests' / 'Fixtures'
ROOT.mkdir(parents=True, exist_ok=True)
CONTROL = b'Package: org.livecontainer.test\nName: LC Test\nVersion: 1.0\nArchitecture: iphoneos-arm\nDescription: Fixture\n continued\nX-Unknown: preserved\n'
PREFIX = 'Library/MobileSubstrate/DynamicLibraries/'

def macho(cpu=0x100000c, dependency=None, padding=0):
    commands = struct.pack('<IIIIII', 0x32, 24, 2, 15 << 16, 15 << 16, 0)
    if dependency:
        name = dependency.encode() + b'\0'
        size = (24 + len(name) + padding + 7) // 8 * 8
        commands += struct.pack('<IIIIII', 0xc, size, 24, 0, 0, 0) + name + bytes(size - 24 - len(name))
    return struct.pack('<IIIIIIII', 0xfeedfacf, cpu, 0, 6, 2 if dependency else 1, len(commands), 0, 0) + commands

FILTER = plistlib.dumps({'Filter': {'Bundles': ['org.example.lcosguest']}})

def tar(entries):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for path, data, kind in entries:
            item = tarfile.TarInfo(path)
            item.mtime = 0
            if kind == 'symlink':
                item.type = tarfile.SYMTYPE
                item.linkname = '../../escape'
            elif kind == 'hardlink':
                item.type = tarfile.LNKTYPE
                item.linkname = '../../escape'
            else:
                item.size = len(data)
            archive.addfile(item, io.BytesIO(data))
    return out.getvalue()

def zstd(data):
    lib = ctypes.CDLL('libzstd.so.1')
    lib.ZSTD_compressBound.argtypes = [ctypes.c_size_t]
    lib.ZSTD_compressBound.restype = ctypes.c_size_t
    lib.ZSTD_compress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
    lib.ZSTD_compress.restype = ctypes.c_size_t
    out = ctypes.create_string_buffer(lib.ZSTD_compressBound(len(data)))
    count = lib.ZSTD_compress(out, len(out), data, len(data), 3)
    return out.raw[:count]

def deb(name, entries=None, control=CONTROL, extra_controls=(), compression='gz'):
    if entries is None:
        entries = [(PREFIX + 'Example.dylib', macho(), ''), (PREFIX + 'Example.plist', FILTER, '')]
    transform = {'': lambda x: x, 'gz': lambda x: gzip.compress(x, mtime=0), 'xz': lzma.compress, 'zst': zstd}[compression]
    control_entries = ([] if control is None else [('control', control, '')]) + list(extra_controls)
    suffix = '.' + compression if compression else ''
    members = [('debian-binary', b'2.0\n'), ('control.tar' + suffix, transform(tar(control_entries))),
               ('data.tar' + suffix, transform(tar(entries)))]
    output = b'!<arch>\n'
    for member, content in members:
        output += f'{member + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(content):<10}`\n'.encode() + content
        if len(content) % 2:
            output += b'\n'
    (ROOT / (name + '.deb')).write_bytes(output)

for compression in ['', 'gz', 'xz', 'zst']:
    deb('valid-' + (compression or 'tar'), compression=compression)
deb('rootless', [('var/jb/' + PREFIX + 'Example.dylib', macho(), ''), ('var/jb/' + PREFIX + 'Example.plist', FILTER, '')])
deb('mixed', [(PREFIX + 'Example.dylib', macho(), ''), ('var/jb/' + PREFIX + 'Example.plist', FILTER, '')])
deb('traversal', [('../escape', b'bad', '')])
deb('absolute', [('/tmp/escape', b'bad', '')])
deb('symlink', [('escape', b'', 'symlink')])
deb('hardlink', [('escape', b'', 'hardlink')])
deb('duplicate', [('same', b'1', ''), ('same', b'2', '')])
deb('case-collision', [('Same', b'1', ''), ('same', b'2', '')])
deb('missing-control', control=None)
deb('scripts', extra_controls=[('postinst', b'#!/bin/sh\ntouch /bad', '')])
deb('dependency', control=CONTROL + b'Depends: impossible (>= 2) | other\n')
deb('system', [('Library/LaunchDaemons/test.plist', b'bad', '')])
deb('wrong-cpu', [(PREFIX + 'Example.dylib', macho(cpu=0x1000007), ''), (PREFIX + 'Example.plist', FILTER, '')])
deb('wrong-filter', [(PREFIX + 'Example.dylib', macho(), ''), (PREFIX + 'Example.plist', plistlib.dumps({'Filter': {'Bundles': ['com.apple.springboard']}}), '')])
deb('missing-library', [(PREFIX + 'Example.dylib', macho(dependency='/var/jb/usr/lib/libmissing.dylib'), ''), (PREFIX + 'Example.plist', FILTER, '')])
deb('substrate-room', [(PREFIX + 'Example.dylib', macho(dependency='/usr/lib/libsubstrate.dylib', padding=64), ''), (PREFIX + 'Example.plist', FILTER, '')])
deb('substrate-no-room', [(PREFIX + 'Example.dylib', macho(dependency='/usr/lib/libsubstrate.dylib'), ''), (PREFIX + 'Example.plist', FILTER, '')])
deb('many-files', [(f'file{i}', b'content', '') for i in range(30)])
deb('large-file', [('large', b'A' * 20000, '')])
(ROOT / 'corrupt.deb').write_bytes(b'!<arch>\nnot an archive')
print('Generated', len(list(ROOT.glob('*.deb'))), 'fixtures')
