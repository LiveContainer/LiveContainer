# Compatibility — first local DEB milestone

## Supported by the implementation, pending device validation

- Debian ar 2.0, control/data tar, gzip and xz; zstd only when built into system libarchive.
- Control metadata, multiline values and retained unknown fields.
- Rootful `Library/MobileSubstrate/DynamicLibraries` and `usr/lib/TweakInject`; same paths below `var/jb`.
- Bundles-only filter plists that explicitly match the chosen private arm64 guest.
- Thin arm64 iOS MH_DYLIB; bounds-checked load commands and minimum device OS check.
- System-library dependencies from a limited allowlist, including direct `/usr/lib/swift/libswift*.dylib`
  runtime libraries supplied by iOS; upstream CydiaSubstrate framework install name. This accepts the
  dependency path without bundling or rewriting Swift libraries; the device must provide the required runtime.
- Substrate dependency rewriting only when the existing load-command string capacity is sufficient.
- Per-package atomic publication after ZSign and upstream signature checks; post-signing SHA-256 receipts.
- Per-guest enable, disable and uninstall through existing selected tweak folder behavior.

## Rejected with an explicit reason

Links/hardlinks, sparse/special files, traversal, case collisions, duplicate members, excessive files or
expanded size, unsupported compression, malformed metadata, mixed layouts, maintainer actions, system
services, SpringBoard filters, non-matching filters, dependencies needing resolution, arm64e/fat/other
architecture, other platform binaries, insufficient path capacity, extra resource trees, preference
bundles and unresolved libraries. Versioned/alternative dependencies are not automatically satisfied.

Known binary-embedded jailbreak resource paths require source adaptation. Detecting a few known paths
does not prove the absence of all privileged behavior. Full symbol/API analysis is future work.

No claim of universal rootful conversion, system-wide injection, extra entitlements or complete jailbreak
emulation is made. Native loaded code can access host-process data. Per-app folders are organizational
boundaries and are not strong isolation. Trust only code whose publisher and source you accept.

Installation and signature checks do not prove `dlopen`, hook execution or useful behavior. Physical-device
tests remain required. SideStore credentials and refresh continue through the original trusted interface.

Raw dylib/framework import remains upstream functionality. Managed DEB framework/resource dependency
installation, upgrades, downgrades, conventional rootless DEB export and APT are incomplete.
