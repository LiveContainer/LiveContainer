# Privileged guests, Husk and cellular refresh

## Persistent folder grants and concealment

Guest settings can store one real Files folder bookmark. Bootstrap reacquires its security-scoped
access for the guest lifetime and creates a managed alias at `Documents/LiveContainer Access/Shared`.
Changing/revoking the grant requires restarting the guest. Expired grants report a launch error with
reselection instructions. Recursive mounts, unmanaged directories and non-symlink replacement data
are rejected/preserved. This exposes only a selected folder actually accessible to the host; it grants
no private entitlements or system-wide filesystem access. CLI integration tests exercise the actual
mount/revocation helper using controlled local bookmarks; file-provider access on the phone remains
a device acceptance check.

The per-guest **Conceal LiveContainer indicators** toggle retains upstream dyld masking and additionally
filters LC/LP helper variables and DYLD_INSERT_LIBRARIES from `ProcessInfo.environment` for non-SideStore
guests. Real `environ`/`getenv` values stay intact so internal helpers continue working. Runtime classes,
kernel process information, code signatures and real container paths can still reveal the host.
The toggle is a compatibility aid, not a guarantee of undetectability or extra privileges.

## AirCard / Tendies quick review

The screenshot identifies AirCard-iOS. Its upstream README lists LiveContainer installation and
iOS 27.0 support, using a local device-service tunnel plus a pairing record. This is separate from
direct filesystem permission inside the host sandbox. A NeoSpring respring alone does not establish
that a wallpaper descriptor was installed.

A limited review of upstream `ios-app/TendiesEngine.swift` found that extraction failures can `continue`,
zero discovered descriptors are not rejected, and secondary modern-provider writes use `try?`.
The function can therefore reach its final success message without every intended wallpaper write
having succeeded. These are possible explanations, not a diagnosis of the user's installed version.
The file also instructs selecting the installed wallpaper from Lock Screen settings after writing.
No AirCard binary, exploit, pairing credentials or wallpaper data were changed by this fork.

Source: https://github.com/Mak5er/AirCard-iOS (reviewed 2026-10-19).

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

Guests execute within the host process and already share its kernel sandbox and actually granted
entitlements. Their virtual home directories are path redirection, not a second iOS security sandbox.
Removing that redirection cannot create broader kernel permissions. Stock iOS cannot grant the host
arbitrary private entitlements merely because they appear in an IPA's entitlement plist.

Per-guest **Open selected files and folders in place** enables the system file picker with the real
host identity, preserves the guest's requested content types and copy/open semantics, and disables
LC's legacy forced-copy / always-success security-scope workaround for that guest. It defaults off
and survives guest updates. Restart the guest after changing it. The guest must itself handle
security-scoped URLs and bookmarks correctly. It grants no access beyond the objects selected in Files.

[Nugget Mobile's original repository](https://github.com/leminlimez/Nugget-Mobile) is archived and
explicitly excludes recent iOS versions. Its SparseRestore dependency is separate from LC's path
redirection. No compatible iOS 27 exploit is supplied by this fork. A generic “full access” toggle
would not make that implementation work on the reported device.

Runtime model reference: [Apple platform security](https://support.apple.com/guide/security/sec15bfe098e/web).

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
