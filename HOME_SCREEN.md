# Native App Grid

The **App Grid** toggle in Settings → Interface switches the existing app manager between list and grid.
The same preference is available in the grid menu and the list sorting menu. Both retain the normal tab bar.
Grid mode has a pure white background in light mode and pure black in dark mode, with no wallpaper or Dock.
Version-one Dock placements migrate back into the grid without dropping installed applications.

## Apple-style controls

On iOS 26+, header controls, search, folder surfaces and list cards use native Liquid Glass.
Tabs, menus, navigation and forms retain the system appearance. Scroll edges use the soft system effect
for progressive blur. Earlier iOS versions retain native material and standard navigation fallbacks.
App artwork is displayed normally so original icons and signing/lock states stay recognizable.

## Moving apps and folders

- Use **Edit Apps**, or lift an icon with a long press. Icons jiggle while editing; Reduce Motion is respected.
- Drag near another icon's edge to reorder with animated displacement.
- Hold over its center until it expands, then release to create a folder or add to an existing folder.
- Hold near the screen edge to change pages. UIKit handles lift previews and drag cancellation.
- Tap a folder for its 3×3 paginated grid. Tap the title to rename it; tap outside, close, or pinch inward to dismiss.
- Move an icon outside the open folder, use its minus control in edit mode, or its Move Out action to return it to the grid.
- A folder with one remaining app dissolves. Nested folders are not supported.
- **Done** exits editing. The menu can reset placement without deleting app data.

The grid uses the actual registry and original launch/authentication/JIT/context-menu controllers.
Fixture app metadata and generated icons are used only by simulator QA and are excluded from release bundles.
Folder behavior follows SpringBoard conventions within the application; it does not embed Apple's private SpringBoard implementation.

## Validation

Ten core tests cover old-layout migration, inventory reconciliation, folder persistence and membership,
rename, moving out, duplicate versions, capacity and invalid destinations. Simulator QA captures light/dark
modes, an open paginated folder and the original list using the actual UI sources. The full-host mode also
uses the original app controllers. Physical-device gestures, VoiceOver and guest launch need device verification.
