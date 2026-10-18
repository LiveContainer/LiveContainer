# LiveContainer OS architecture and provenance

This branch starts at official LiveContainer `9108ae624ea001f7d7696d48407f890b48fa2653`.
Observed on 2026-10-18: LiveContainer/SideStore HEAD `ee3cc16a67f9fed766f79a0ed70938f0f8ad5a07`;
SideStore/SideStore HEAD `d97ec133719d79916675bdaf722b82a8d091d545`.
These reference HEADs do not establish the source of the prebuilt SideStore release asset.
The actual integrated dependency is pinned by SHA-256 in the OS workflow.

## Reused components

- `LCAppModel`, `LCAppInfo`: guest registry, launch, private/shared containers, existing signing.
- `LCTweaksView`: existing raw dylib/framework import and manual folders remain available.
- `TweakLoader/TweakLoader.m`: substrate preloading, selected-folder recursion, `.disabled` exclusion.
- `LCUtils.signFilesWithZSign`: actual signing; installer also checks signatures with upstream `checkCodeSignature`.
- `.github/build_github.sh`: original combined SideStore packaging; account and provisioning logic unchanged.

## Added vertical slice

`LiveContainerSwiftUI/PackageManager/Core` is Foundation-only Swift and is also compiled by SwiftPM.
`ArchiveBridge` wraps upstream-linked libarchive for in-memory, bounded tar entry reading. It never
extracts to disk, follows links, runs scripts, or invokes command-line decompression. Swift validates ar
members, paths, entry types, counts, expanded sizes, metadata, filter semantics and supported Mach-O commands.

`TweakInstallPlan` prepares a deliberately narrow runtime representation: matching, Bundles-only filters
and thin arm64 iOS dylibs with resolvable supported library references. It maps conventional rootful and
rootless injection directories to a guest's exclusive tweak folder. It is not a conventional rootless
Debian exporter and does not supply a virtual jailbreak filesystem.

`PackageStore` stages each package under `.transaction-UUID.disabled`, asks the injected production
signer to sign and verify, writes post-signing SHA-256 receipts, then atomically renames the whole
directory. Each package owns a separate directory. Enable/disable renames it with `.disabled` as
understood by upstream TweakLoader. Removal never targets guest data or another package directory.
No shared dependency installation is attempted, so no shared file reference counts are needed yet.

`LCDebPackageView` exposes import, target selection, inspection, explicit native-code trust, installation,
inventory, enable/disable and confirmed removal. It uses private, unlocked guests only. Existing
shared folders are rejected when another guest references them. Package loading still belongs to
the upstream loader; receipts explicitly say runtime testing has not occurred.
The loader records actual per-library `attempting`/`loaded`/`failed` results and errors beside a managed
package receipt. The package screen reads the last timestamped result separately from installation
status. A load that crashes during initialization may leave `attempting`; this is not proof of a crash
cause and is not an automatic recovery system. Native hook behavior still requires the controlled test.

## Remaining scope

See `COMPATIBILITY.md` and `TESTING.md`. Home Screen, folders, APT repositories, full Debian dependency
resolution, preference bundles, profiles and recovery are not implemented by this milestone.
