# Build

## Baseline evidence

The unmodified upstream commit `9108ae624ea001f7d7696d48407f890b48fa2653` successfully built in the user's fork:
https://github.com/CORBENDALLAS111/LiveContainer/actions/runs/39130423940
The run contains the original standalone and combined SideStore IPAs. It does not include OS changes.

## Modified build

Use **LiveContainer OS - Integrated IPA** in GitHub Actions and select `codex/livecontainer-os`.
The workflow also runs on pushes to `codex/**` and on pull requests. It initializes pinned submodules,
selects Xcode 26.2, runs SwiftPM unit tests, archives the upstream LiveContainer scheme, invokes upstream
combined packaging, verifies the resulting ZIP and bundled components, and uploads
`LiveContainerOS+SideStore.ipa` with `SHA256SUMS`, `SOURCE_COMMIT`, `SUBMODULES` and `build-evidence.json`.
Compilation logs are uploaded even on failure. No developer credentials or provisioning secrets are supplied.

The SideStore and dylibify download checksums are pinned. If a mutable nightly asset changes, packaging
intentionally fails; review the new asset and update the checksum explicitly. The source of the SideStore
prebuilt asset is not verified merely by recording the repository's current HEAD.

## Local

Windows/WSL can run `swift test` with Swift 5.9+ and libarchive development headers. iOS compilation needs
macOS/Xcode. Open the existing Xcode project and follow upstream signing configuration in xcconfigs.
Do not treat a Linux SwiftPM build as an iOS application build.

The structural IPA checker can also run locally:

```sh
python3 scripts/verify_ipa.py LiveContainerOS+SideStore.ipa --integrated
```

## Installation

The resulting distribution must be signed and provisioned using LiveContainer's supported sideloading
workflow. Follow the upstream guide at https://livecontainer.github.io/docs/intro. Keep app extensions
when required by upstream. A CI-packaged IPA does not grant an Apple development certificate, arbitrary
entitlements, unlimited validity, or guaranteed background refresh. Back up existing app data before
testing this development fork. The original bundle identifier is retained.
