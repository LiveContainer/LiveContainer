# SideStore signing injection

This is a personal LiveContainer fork integration, not an upstream SideStore contribution.
GitHub Actions checks out the revision in SOURCE_COMMIT, adds the shared portable injector and a single
call in ResignAppOperation after bundle preparation and before ALTSigner.signApp, then archives SideStore.
The combined IPA packages this source-built SideStore. Source, overlay and patched-operation hashes are
recorded in SIDESTORE_SOURCE.json and embedded as LCOSSigningIntegration.json in the SideStore framework.
The prebuilt nightly remains an explicit fallback only for callers of the upstream packaging script;
the integrated OS workflow requires its source-built signing implementation.

## Use

During a foreground **Install / Update / Reinstall** in embedded SideStore, the injection sheet opens
after application customization. Its target is the selected IPA's original bundle identifier, before
Apple's provisioning suffix. Import a DEB or dylib, review and enable it, then choose Install.
Continue without files for a normal installation; Cancel aborts the installation. This screen is no
longer in LiveContainer Settings. The libraries are copied into an owned
Frameworks/LCOSInjected directory and added as executable load commands before SideStore signs the result.
Multiple libraries are supported. Re-importing a library with the same filename replaces its earlier version.
Disable or delete the preset and reinstall/sign again to remove owned load commands from modified bundles.
Profile-only refresh does not alter executable contents or show the injection sheet.
Previously installed applications change only after SideStore successfully signs and installs the refreshed copy.

DEB extraction, maintainer-script rejection, bundle filters and Mach-O dependency adaptation reuse the
existing package-manager validator. Direct dylibs require an explicit target. Bundled Substrate is included
when a validated dependency needs it. Encrypted executables, arm64e tweak libraries, unsupported dependencies,
resource packages, insufficient load-command padding and protected host/system targets fail explicitly.
No maintainer scripts are executed. No certificate/account details are stored in presets.

The payload is hash-checked and staged before executable modification; failed staging leaves the app intact.
The normal SideStore certificate/provisioning/signing/install operations run afterward. Header changes
invalidate old signatures and must never be exported as an already-signed app before that step.

Portable tests cover payload corruption, rollback, removal, idempotence and preserved code bytes.
The Xcode-built controlled ARM64 device guest is also injected and ad-hoc signed/verified in macOS CI.
These tests do not establish hook compatibility or a successful Apple-account install/refresh on a phone.

## Extension bundle identifiers

The single-profile path now fetches the profile under the effective target bundle ID and keys its
extension map by the effective extension IDs used during resigning. Previously a custom target could
miss that map and fall back to the parent profile's ID for every extension, causing IXErrorDomain
Code 8 / mismatched bundle IDs. A missing mapping now fails explicitly; prepared PlugIns metadata
is checked for parent-dot prefixes and duplicate IDs before signing. This does not override Apple's
provisioning rules or recover already-corrupted extension IDs; reinstall such an app from a fresh IPA.

## SideBackup entitlement preservation

The source build must run upstream `make build fakesign`, including `fakesign-sidebackup`.
Without the initial entitlement declaration in the embedded SideBackup binary, SideSign drops the
App Groups entitlement even when a profile contains it. The result is the purple “SideBackup could
not start” screen. Both the source IPA and final integrated IPA now reject a missing declaration.
This check does not grant entitlements: the final device installation still needs a valid provisioning
profile granting the shared app group.
