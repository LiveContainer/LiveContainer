# SideStore signing injection

This is a personal LiveContainer fork integration, not an upstream SideStore contribution.
GitHub Actions checks out the revision in SOURCE_COMMIT, adds the shared portable injector and a single
call in ResignAppOperation after bundle preparation and before ALTSigner.signApp, then archives SideStore.
The combined IPA packages this source-built SideStore. Source, overlay and patched-operation hashes are
recorded in SIDESTORE_SOURCE.json and embedded as LCOSSigningIntegration.json in the SideStore framework.
The prebuilt nightly remains an explicit fallback only for callers of the upstream packaging script;
the integrated OS workflow requires its source-built signing implementation.

## Use

Open **Settings → SideStore Injection** in LiveContainer. Enter the original app bundle identifier
(before Apple's provisioning suffix), import a DEB or dylib, review the target and enable the preset.
Install or refresh that application in the integrated SideStore. The libraries are copied into an owned
Frameworks/LCOSInjected directory and added as executable load commands before SideStore signs the result.
Multiple libraries are supported. Re-importing a library with the same filename replaces its earlier version.
Disable or delete the preset and refresh again to remove owned load commands from cached modified bundles.
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
