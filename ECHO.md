# Echo Launcher (iOS)

A fork of [LiveContainer](https://github.com/LiveContainer/LiveContainer) (AGPL-3.0) that installs, updates and
launches the Echo 3.6 iOS client. LiveContainer's loader, signing and JIT-less support are used unchanged.

## Stages

1. **Core** - single-game mode: install the game IPA named by the manifest, verify it, launch it with EchoIOS
   loaded from the tweak folder.
2. **Updates** - game IPA, EchoIOS, EchoGfx and paks update from the manifest; dylibs are re-signed on the
   device with the imported certificate (LiveContainer's ZSign path).
3. **Renderer switch** - "Echo (PC shaders)" or "Stock". Stock leaves out EchoGfx, the paks tagged
   `renderer: "echo"` and the extra command-line arguments.
4. **Mods** - list, download and toggle the backend's mods that carry an iOS pak.
5. **Launcher features** - sign-in, news, store, then the rest of the PC launcher's screens.

## Manifest (draft, served by the Echo backend over HTTPS)

```json
{
  "version": 1,
  "game":   { "build": "3.6-CL-4019403", "url": "https://.../game.ipa", "sha256": "...", "size": 0 },
  "client": [
    { "name": "EchoIOS.dylib", "build": 1, "url": "https://...", "sha256": "..." },
    { "name": "EchoGfx.dylib", "build": 1, "url": "https://...", "sha256": "...", "renderer": "echo" }
  ],
  "paks": [
    { "name": "pakchunkpadfix-iosclient_p", "pak": { "url": "...", "sha256": "..." }, "sig": { "url": "...", "sha256": "..." } },
    { "name": "pakchunkmetalmrt-iosclient_p", "renderer": "echo", "pak": { "url": "...", "sha256": "..." }, "sig": { "url": "...", "sha256": "..." } }
  ],
  "commandLine": { "all": [], "echo": ["-metaltlv"], "stock": [] },
  "settings": { "echo-ios.ini": { "url": "...", "sha256": "..." } }
}
```

Rules the launcher enforces: HTTPS only; every file is checked against its sha256 before it is used; a pak
name may appear once; file names may not contain path separators; entries tagged `renderer` are used only
when that renderer is selected; nothing is installed while the game is running.

## Status

- [x] Fork branch, display name
- [x] Bundle identifier rename (com.godbot100.echolauncher)
- [ ] URL scheme rename
- [x] Echo tab: manifest check, client library updates, game IPA download with integrity check
- [ ] Paks, command line, locking the app list to the one game
- [x] Renderer setting (switches the tagged client libraries)
- [ ] Mods
