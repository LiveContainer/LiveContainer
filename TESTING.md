# Validation and outstanding device tests

## Automated

`swift test` compiles the actual Swift package core and C libarchive bridge. Fixtures are synthetic
Mach-O parser inputs, not executable or signed tweaks. `Tests/generate_fixtures.py` generates deterministic
ar/tar fixtures; committed fixture bytes allow macOS testing without additional Python compression modules.

Tests cover common compression, control continuation/unknown metadata, rootful/rootless runtime mapping,
mixed layouts, missing metadata, damaged ar, traversal/absolute paths, symbolic/hard links, duplicate and
case-colliding paths, file/count/expanded limits, scripts, dependencies, platform/CPU, target filters,
missing libraries, bounded substrate rewriting, truncated Mach-O commands, SHA-256 vectors, installation,
enable/disable, integrity failure, signing failure rollback and uninstall preservation of unrelated files.

Package store tests inject test signing closures to exercise transaction behavior. They do not claim
to test Apple signing. Production uses ZSign followed by upstream signature checking and refuses a missing
certificate. IPA verification checks ZIP integrity, expected root app/executable/frameworks, SideStore,
TweakLoader and required plist values; it does not execute any app.

## Physical device checklist — not run

The Actions artifact also contains `LCOSProbe.ipa` and rootful/rootless `LCOSProbe` DEBs, compiled from
`Tests/DeviceProbe` using the actual iOS SDK. Install the guest IPA through LiveContainer. With the tweak
disabled, **Run hook probe** must show **ORIGINAL**. After matching DEB installation and guest relaunch,
it must show **TWEAK HOOK ACTIVE**. Disable, relaunch and repeat to verify it returns to **ORIGINAL**.
The probe exercises a real method implementation replacement in a controlled guest; compilation alone
does not establish that injection or hooks work on a device.

- [ ] Install the combined IPA using a supported signed sideloading method.
- [ ] Confirm existing guest IPA import, launch, multiple containers, JIT/JIT-less and multitasking.
- [ ] Confirm original SideStore account/certificate/refresh and upgrade data preservation.
- [ ] Compile the controlled test tweak and guest; package matching filter and constructor marker.
- [ ] Import DEB, confirm target/name/layout and trust, install with valid certificate.
- [ ] Confirm actual `dlopen` and expected visible marker/hook behavior in the controlled guest.
- [ ] Disable and relaunch; confirm marker/hook is absent.
- [ ] Re-enable, then uninstall; confirm only package files were removed and guest data remains.
- [ ] Confirm wrong target, no certificate and incompatible package report real failures.
- [ ] Validate accessibility, large text and iPad layout on the package screen.

## Requested feature checklist

- [x] Official repository inspected and upstream baseline built in GitHub Actions.
- [x] Existing integrated SideStore packaging retained.
- [x] Local DEB implementation, conservative runtime adapter, receipts and native management UI.
- [ ] Device-proven tweak loading and behavior.
- [ ] Full rootful-to-rootless Debian converter/export and symbol analysis.
- [ ] General dependency/version/alternative resolution and shared runtime libraries.
- [ ] Home Screen/dock/pages/folders/wallpapers/App Library.
- [ ] APT sources, trust, search, downloads and updates.
- [ ] Tweak preferences, profiles, recovery and structured diagnostic export.
- [ ] Full regression and final acceptance criteria A–H.
