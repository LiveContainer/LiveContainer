# Native Home Screen

The Home Screen is enabled by default. Switch it off or on in **Settings → Interface → Home Screen**.
The same switch is available in the desktop's ellipsis menu and in the app list's sorting menu.
The preference is persisted in LiveContainer's existing shared defaults.

## Using the desktop

- Tap an installed app to use LiveContainer's original launch/authentication/JIT path.
- Touch and hold for the original context menu: containers, settings, alternate launch, export and confirmed uninstall.
- Choose **Add to Dock** or **Remove from Dock** in that menu. The dock holds four apps on phones and six in wide windows.
- Drag icons to reorder. Drop on another page's dot to move to that page. Drop onto the dock to pin an app.
- Use **Search Apps** to search names and bundle identifiers, including apps pinned in the dock.
- Choose **Dusk**, **Ocean** or **Dawn** in the wallpaper menu. Each has a native light/dark variant.
- Open Settings, Tweaks or integrated SideStore from the desktop menu. An empty dock shows real navigation shortcuts.
- Use **Show App List** for the original app manager, including hidden-app authentication and advanced sorting.

The desktop uses the actual guest registry and original icons. No fixture applications are shipped.
Layout identifiers include the installed bundle path, so two versions of an app keep independent positions.
New installations appear automatically; removed/hidden apps are filtered from display. Reset only changes icon placement.

## Validation

Five portable unit tests exercise persistence, duplicate versions, inventory reconciliation, dock capacity and invalid drags.
The integrated IPA workflow compiles the full native UI and retains the package-manager regression checks.
The separate Simulator Preview workflow attempts an actual simulator host build and captures light/dark/list screenshots.
Its sample guest metadata and generated icon caches exist only in the test simulator, outside the release bundle.
Screenshots do not establish guest signing or tweak execution on a physical device.

Manual/device checks remain necessary for drag/context-menu gestures, VoiceOver, narrow split views, and launch regressions.
Folder creation, photo wallpapers and a categorized App Library are outside this desktop increment.
