# LiveContainer
Run unsigned iOS app without actually installing it!
- Allows you to install unlimited apps (10 apps limit of free developer account do not apply here!)
- Codesigning is entirely bypassed (requires JIT), no need to sign your apps before installing.

## Compatibility
Unfortunately not all apps work in LiveContainer so we have a [compatibility list](https://github.com/khanhduytran0/LiveContainer/labels/compatibility) to tell if there is apps that have issues. If they arent on this list. Then its likely going run. However, if it doesnt work please make a [github issue](https://github.com/khanhduytran0/LiveContainer/issues/new/choose) about it.

## Building
```
export THEOS=/path/to/theos
git submodule init
git submodule update
make package
```

## Usage
Requires SideStore; AltStore does not work because it expects the app opened before enabling JIT.
- Build from source or get prebuilt ipa in [the Actions tab](https://github.com/khanhduytran0/LiveContainer/actions)
- Open LiveContainer, tap the plus icon in the upper right hand corner and select IPA files to install.
- Choose the app you want to open in the next launch.
- Tap the play icon, it will jump to SideStore and exit.
- In SideStore, hold down LiveContainer and tap `Enable JIT`. If you have SideStore build supporting JIT URL scheme, it jumps back to LiveContainer with JIT enabled and the guest app is ready to use.

## How does it work?

### Patching guest executable
- Patch `__PAGEZERO` segment:
  + Change `vmaddr` to `0xFFFFC000` (`0x100000000 - 0x4000`)
  + Change `vmsize` to `0x4000`
- Change `MH_EXECUTE` to `MH_DYLIB`.

### Patching `@executable_path`
- Call `_dyld_get_image_name(0)` to get image name pointer.
- Overwrite its content with guest executable path.

### Patching `NSBundle.mainBundle`
- This property is overwritten with the guest app's bundle.

### Bypassing Library Validation
- Derived from [Restoring Dyld Memory Loading](https://blog.xpnsec.com/restoring-dyld-memory-loading)
- JIT is required to bypass codesigning.

### dlopening the executable
- Call `dlopen` with the guest app's executable
- Find the entry point
- Jump to the entry point
- The guest app's entry point calls `UIApplicationMain` and start up like any other iOS apps.

## Limitations
- Entitlements from the guest app are not applied to the host app. This isn't a big deal since sideloaded apps requires only basic entitlements.
- App Permissions are globally applied.
- Guest app containers are not sandboxed. This means one guest app can access other guest apps' data.
- arm64e executable is untested. It is recommended to use arm64 binary.
- Only one guest app can run at a time. This is much more like 3 apps limit where you have to disable an app to run another (switching between app in LiveContainer is instant).
- Remote push notification might not work. ~~If you have a paid developer account then you don't even have to use LiveContainer~~
- Querying URL schemes might not work(?)

## TODO
- Isolating `NSFileManager.defaultManager` and `NSUserDefaults.userDefaults`
- Auto lock orientation
- Simulate App Group(?)
- More(?)

## License
[Apache License 2.0](https://github.com/khanhduytran0/LiveContainer/blob/main/LICENSE)

## Credits
- [xpn's blogpost: Restoring Dyld Memory Loading](https://blog.xpnsec.com/restoring-dyld-memory-loading)
- [LinusHenze's CFastFind](https://github.com/pinauten/PatchfinderUtils/blob/master/Sources/CFastFind/CFastFind.c): [MIT license](https://github.com/pinauten/PatchfinderUtils/blob/master/LICENSE)
- [fishhook](https://github.com/facebook/fishhook): [BSD 3-Clause license](https://github.com/facebook/fishhook/blob/main/LICENSE)
- [MBRoundProgressView](https://gist.github.com/saturngod/1224648)
- @haxi0 for icon
