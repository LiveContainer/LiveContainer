# Privileged guests, Husk and cellular refresh

Target reported by the user: iPhone 16 Pro, iOS 27.0. Findings checked 2026-10-19.

## Husk

[Leviidev/Husk](https://github.com/Leviidev/Husk) documents two debugger paths: external StikDebug,
and an embedded HuskJITHelper app extension. iOS does not register guest extensions imported into LC.
This fork uses the external path; it does not pretend that merely attaching a debugger grants usable
executable memory on TXM devices.

On a new import of `com.husk.app`, LC detects the bounded UTF-8 `husk-jit.js` shipped inside that IPA,
selects it as the JIT launch script and enables Launch with JIT. Existing installations have a
“Use bundled Husk JIT script” button in app settings. User-selected scripts are preserved on updates.
Select StikDebug in LC's JIT settings and configure its pairing and external loopback VPN. A StikDebug
inside LC must use the shared-app/another-instance setup described by upstream LC.

Guest `stikjit://enable-jit` requests targeting the guest's bundle ID are rewritten to the real host
bundle ID and current process PID while preserving the script and other query arguments. Requests
for unrelated bundle IDs or explicit different PIDs are left alone. Both UIApplication and UIScene
open-URL paths use this correction. These hooks require LC's normal TweakLoader injection to be enabled.

Source references: [Husk JIT setup](https://github.com/Leviidev/Husk/blob/main/docs/06-built-in-jit.md),
[LiveContainer JIT setup](https://livecontainer.github.io/docs/guides/jit-support).
The user's screenshots show debugger attached but trap servicer not answering and executable memory
not claimed. Those are failures, not successful JIT. Actual generated-code execution and Android
guest startup on the user's phone remain device acceptance checks.

## Other permissions and extensions

Host `get-task-allow` and increased-memory-limit declarations are already present in entitlements.xml.
The sideloader must obtain a profile that actually grants them. LC cannot confer arbitrary guest
entitlements, register arbitrary guest extensions dynamically, or restore vulnerabilities patched in
iOS 27. A VPN provider or app requiring its own registered helper should be installed natively through
SideStore with extensions retained. DEB injection also cannot grant additional sandbox permissions.

## Refresh over cellular

The pinned LiveContainer/SideStore revision already includes an experimental Cellular Refresh feature:
SideStore → Settings → User Customizations → Cellular Refresh. Configure its Turn Off Cellular and
Turn On Cellular shortcut names in Apple Shortcuts. It toggles cellular data around device-service
operations when Wi-Fi is unavailable and bypasses the normal Wi-Fi readiness precheck.

Its `ensureMinimuxerReady` rejects the WireGuard/EMP mode while Cellular Refresh is enabled because
toggling cellular pauses that tunnel. Use the supported LocalDevVPN connection setup instead.
The feature defaults off and is not enabled automatically by this fork. Opening a Shortcut successfully
does not prove the device connection or refresh succeeded. LTE/5G-only installation/refresh, recovery
after a failed shortcut and cellular restoration must be tested on the physical phone.

Reviewed pinned source: `SideStore/Core/Shortcuts/CellularRefreshManager.swift`,
`SideStore/Core/DeviceApi/MinimuxerWrapper.swift`, and the UserCustomizationsView controls.
