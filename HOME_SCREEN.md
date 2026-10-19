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
- Tap a folder for its 3×3 paginated grid. Tap the title to rename it; tap outside or pinch inward to dismiss. VoiceOver supports the Escape action. There is no close button.
- The panel expands from its measured icon position and returns there, with a damped spring and animated backdrop blur. Reduce Motion uses a short fade instead.
- Hold a dragged member outside the panel to close the folder and continue moving it on the desktop. Native lift/cancel previews show only the rounded icon.
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
# Editing and drag refinements

Removal badges now fade/scale with their own transition. Holding an icon for its context menu does
not enter editing: a drag activates editing only after more than eight points of actual movement.
The whole-scroll-view long-press recognizer was removed; empty-space long press and Edit remain.
Vertical scroll bounce is restored at the user's request, while the edge veil still reacts to scrolling.

After confirmation and successful bundle removal, a window-level snapshot breaks into tiled particles,
then the registry/grid removes the app. Cancellation or filesystem failure does not play a fake success
animation. Reduce Motion uses a short fade. Folder transitions retain a tappable surface through the
entire animation; tapping reverses the target, cancels obsolete completion tasks and retargets the spring.
The debug animation fixture exercises the same particle animator without removing files, and reverses
a folder opening twice before allowing it to settle.

Hold an empty part of the desktop to enter editing; tap empty space or Done to finish.
Folders remain with one app and disappear only after the last app leaves, matching Apple's documented behavior.
Icons use independently timed rocking animations, disabled with Reduce Motion. The remove badge
opens LC's existing uninstall confirmation and separate keep/delete-data choice. Shared guests keep
their existing uninstall restriction. Drag cancellation restores the saved layout, reconciled with
the current installed inventory.

Hold an app over a folder to open it without releasing the drag. Drag beyond the folder panel to
close it, then enter another folder or drop on the desktop. Folder edge hovering turns folder pages;
empty space accepts a drop at that page's end. Root and folder edge/dot changes use the native paged
TabView with a short ease-in/out transition. Reordering respects movement in both directions.

A masked system material softens the desktop's scroll boundaries. This is a composited blur/fade,
not a private variable-radius blur API. Visual fixtures include root/folder editing and a second page.
Fixture-driven animation recordings do not replace physical touch and drag acceptance testing.
