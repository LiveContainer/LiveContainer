# Remote control: HTTP API and MCP

> **LiveContainer is an open-source project** (AGPL-3.0, upstream: https://github.com/LiveContainer/LiveContainer ).
> This document describes what the `remote-control` branch adds on top: a bearer-authenticated HTTP server inside
> the app that exposes install / launch / windows / UI taps / screenshots / tweaks / logs, plus an MCP bridge so
> agents such as Claude or Hermes can drive the device directly.
>
> All changes here are released under the same **AGPL-3.0** licence; this fork is not affiliated with upstream and
> only extends it. Nothing third-party runs on device (HTTP only), and the MCP bridge is one Python file using the
> standard library.

## Architecture

```
MCP client (Claude / Hermes / ...) --stdio--> tools/mcp/lc_mcp.py --HTTP + Bearer--> device :8848
                                                                                    (inside LiveContainer)
                                                                                    |
                                                                                    `-- 127.0.0.1:8850
                                                                                        (guest sidecar in LiveProcess)
```

The host writes the bearer token into an app-group file that the guest sidecar reads, so both sides share one token
while only port `8848` is reachable from outside. The sidecar binds loopback only.

## 1. Preparation (device)

1. Sideload `LiveContainer-remote.ipa` (unsigned; sign it with your own certificate and **keep App Extensions**,
   otherwise launching an app fails with `LiveProcess extension not found`).
2. In the app: Settings -> Remote Control -> enable *Enable HTTP server*
   - the port defaults to 8848 (changeable)
   - keep-alive: "Silent audio (online while locked)" is recommended
   - copy the **token** shown on that page
3. Make sure device and PC can reach each other (same Wi-Fi, or Tailscale).

## 2. Preparation (PC)

Copy `tools/mcp/lc_mcp.py` anywhere and set two environment variables:

| Variable | Meaning |
|---|---|
| `LC_REMOTE_URL` | device address, e.g. `http://192.168.1.8:8848` or `http://100.x.y.z:8848` |
| `LC_REMOTE_TOKEN` | the token shown on the Remote Control settings page |

**MCP client configuration**

```json
{
  "mcpServers": {
    "livecontainer": {
      "command": "python3",
      "args": ["/path/to/tools/mcp/lc_mcp.py"],
      "env": {
        "LC_REMOTE_URL": "http://192.168.1.8:8848",
        "LC_REMOTE_TOKEN": "<token>"
      }
    }
  }
}
```

Self-check (no device needed):

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | python3 lc_mcp.py
```

## 3. Tools (40)

### Device / install / launch

| Tool | Parameters | What it does |
|---|---|---|
| `lc_health` | — | liveness, version and port (the only route without a token) |
| `lc_apps` | — | installed apps: bundleId, name, version, containers, hidden flag, `isAppRunning` |
| `lc_install_ipa` | `ipa_path`, `replace?` | upload an IPA from this machine and install it |
| `lc_install_from_url` | `url`, `replace?` | let **the device download** and install it; returns a `jobId` immediately (best for large files / weak links) |
| `lc_jobs` | `job_id?` | async job state; omit to list recent jobs |
| `lc_uninstall_app` | `bundle_id`, `keep_data?` | uninstall; `keep_data=true` keeps the data container |
| `lc_launch_app` | `bundle_id`, `container?`, `url?`, `multitask?` | launch an app. `multitask=true` runs it in a container window (recommended for debugging, otherwise the host yields to the guest and the server drops) |
| `lc_open_app` | `bundle_id`, `container?`, `url?` | **one-shot**: open in a multitask window, wait for the guest side, return window + guest pid |
| `lc_close_app` | `bundle_id` | close an app by firing the window close button and confirming the process exited |
| `lc_window_chrome` | `window_id` | selectors bound to the three title-bar buttons |
| `lc_window_press` | `window_id`, `selector` | fire a title-bar button selector (`closeWindow`, `maximizeWindow`, `minimizeWindow`) |

### Tweaks (dylib / framework)

| Tool | Parameters | What it does |
|---|---|---|
| `lc_tweaks` | `folder?` | list tweaks with enabled state and signature info (cdhash / sigSize) |
| `lc_tweak_import` | `path`, `folder?` | upload a `.dylib` or a zipped `.framework`, store it and fix its rpath |
| `lc_tweak_toggle` | `name`, `enabled`, `folder?` | enable/disable (device side: adds/removes the `.disabled` suffix) |
| `lc_tweak_sign` | `folder?`, `force?` | ZSign re-sign; returns before/after cdhash per file and `changedCount`; `changedCount=0` means the certificate failed to load |
| `lc_tweak_delete` | `name`, `folder?` | delete a tweak |
| `lc_tweak_folder` | `name` | create a tweak subfolder (per-app tweaks) |

### Multitask windows

| Tool | Parameters | What it does |
|---|---|---|
| `lc_windows` | — | list windows: id (dataUUID), bundleId, pid, scale, maximized, frame, running |
| `lc_window_action` | `id`, `action`, `scale?`, `enabled?` | `action` in `scale` (0.4-3.0) / `pip` (minimise-restore) / `maximize` / `close` |

### UI automation (container)

| Tool | Parameters | What it does |
|---|---|---|
| `lc_ui_tree` | — | accessibility tree: label / identifier / text / frame / activatable |
| `lc_ui_activate` | `index?` / `label?` / `identifier?` / `text?` | activate an element (SwiftUI via `accessibilityActivate`, UIKit via `sendActions`) |
| `lc_ui_tap` | `x`, `y` | tap by screen coordinate (points; a frame centre from `ui_tree` works) |
| `lc_ui_taps` | `steps[]`, `detect_change?`, `capture_after?` | **tap sequence**: label / index / text / coordinates per step, optional `delayMs`; reports whether the screen changed and can screenshot afterwards |
| `lc_ui_tab` | `index?` / `name?` | switch the bottom tab (Sources / Apps / Tweaks / Settings) |
| `lc_ui_text` | `text` | type into the current first responder (activate or tap the field first) |
| `lc_screenshot` | `window_id?`, `out_path?`, `quality?`, `max_width?` | capture to JPEG, save locally, return the path; omit `window_id` for the whole UI |

### UI automation inside the guest app (through the sidecar in LiveProcess)

| Tool | Parameters | What it does |
|---|---|---|
| `lc_guest_info` | — | guest process info: bundleId / pid / screen and view size |
| `lc_guest_tree` | — | the guest app's own accessibility tree (in-app buttons included) |
| `lc_guest_activate` | `index?` / `label?` / `identifier?` / `text?` / `x,y` | activate an element inside the guest app |
| `lc_guest_taps` | `steps[]`, `detect_change?` | tap sequence inside the guest app, reports `changed` and `diff` per step |
| `lc_guest_text` | `text` | type into a guest text field (focuses one when nothing is focused) |
| `lc_guest_screenshot` | `max_width?`, `quality?`, `out_path?` | capture the guest app's own screen (no cross-process compositing artefacts) |
| `lc_guest_ocr` | `text?` | Vision OCR of the guest screen with boxes; `text` filters the result |
| `lc_guest_ocr_history` | `limit?` | previous OCR runs (also persisted to `ocr-log.jsonl`) |
| `lc_guest_inspect` | `index` | dump the view structure of one element |

### Logs

| Tool | Parameters | What it does |
|---|---|---|
| `lc_logs` | `since?`, `limit?`, `wait?` | LiveContainer's own process log (incremental + long poll) |
| `lc_log_push` | `msg`, `src?` | append a line from a tweak or script, readable through `lc_logs` |
| `lc_guest_logs` | `name?`, `offset?`, `limit?` | **guest app and injected tweak logs**; omit `name` to list files, pass it to read from `offset` (returns `next`) |
| `lc_guest_logs_clear` | `name?` | delete log files (omit to clear all) |

### Keep-alive

| Tool | Parameters | What it does |
|---|---|---|
| `lc_keepalive` | `mode` | `off` / `audio` (silent audio, stays online when locked) / `screenAwake` / `audioAndScreen` |

## 4. Common flows

**Install -> launch -> look**

```
lc_install_from_url {url, replace:true} -> poll lc_jobs {job_id} until done
-> lc_open_app {bundle_id} -> lc_guest_screenshot
```

**UI self-test loop**

```
lc_guest_tree -> pick a target index / text
-> lc_guest_activate {text:"Files"}   (or lc_guest_taps with coordinates)
-> lc_guest_screenshot               (verify the screen actually changed)
-> lc_guest_logs {name}              (read the app's / tweak's NSLog output)
```

**Install a tweak and prove it was signed**

```
lc_tweak_folder {name:"shark"}
lc_tweak_import {path:"/tmp/BlockNetPlus-arm64.dylib", folder:"shark"}
lc_tweak_sign {folder:"shark", force:true}   // changedCount must be > 0
lc_tweaks {folder:"shark"}                   // check signature.cdhash
```

**Tap inside a freshly installed IPA**

```
lc_guest_taps {steps:[
  {text:"Files"},
  {x:200, y:520, delayMs:1500, note:"landing page"},
  {x:120, y:300, delayMs:800,  note:"first entry"},
  {x:340, y:820, delayMs:800,  note:"bottom bar"}
], detectChange:true}
-> per-step ok / changed / diff, plus the screenshot path
```

## 5. How activation works

Three paths, in order of preference:

1. **Direct element activation** — `UIControl.sendActions(.touchUpInside)`, or `accessibilityActivate()` for
   non-controls such as SwiftUI buttons.
2. **Text matching** — every element carries `text` / `texts` gathered from `UILabel.text`, `UIButton.title(for:)`,
   `attributedTitle`, `UISegmentedControl` segments, `UITextField` and `CATextLayer.string`. `{"text": "Files"}`
   matches exactly first, then by substring.
3. **OCR fallback** — when neither the tree nor its text matches, the sidecar OCRs the screen with system Vision and
   taps the centre of the matching text box (the response carries `"via": "ocr"`). This is what makes text taps work
   in apps that paint their labels as images, and in WebView / Flutter UI.

Coordinate taps are a fallback only: no touch synthesis is involved, so tapping a blank area answers
"hit a UIView but found no activatable control" instead of pretending to click.

## 6. REST reference (curl works without MCP)

Everything except `/api/v1/health` needs `Authorization: Bearer <token>`.

```
GET    /api/v1/health
GET    /api/v1/config
GET    /api/v1/self                     # bundle / PlugIns (.appex) / Frameworks, for install problems
GET    /api/v1/apps
POST   /api/v1/apps                     # multipart or raw body IPA upload
POST   /api/v1/apps/from-url            # {url, replace} -> 202 jobId
POST   /api/v1/apps/open                # {bundleId} -> window + guest pid
DELETE /api/v1/apps/{bundleId}?keepData=1
POST   /api/v1/apps/{bundleId}/launch?container=&url=&multitask=1
GET    /api/v1/jobs    /api/v1/jobs/{id}
GET    /api/v1/tweaks?folder=
POST   /api/v1/tweaks?folder=           # multipart dylib upload
PATCH  /api/v1/tweaks                   # {name, enabled, folder}
DELETE /api/v1/tweaks?name=&folder=
POST   /api/v1/tweaks/sign?folder=&force=1
POST   /api/v1/tweakfolders             # {name}
GET    /api/v1/windows[?all=1]
GET    /api/v1/windows/{id}/chrome
POST   /api/v1/windows/{id}/{scale|pip|maximize|close|press}
GET    /api/v1/screenshot?windowId=&quality=&maxWidth=
GET    /api/v1/guest/info                              # proxied to the guest sidecar (127.0.0.1:8850)
GET    /api/v1/guest/ui/tree
GET    /api/v1/guest/ocr[?text=]   /api/v1/guest/ocr/history[?limit=]
GET    /api/v1/guest/inspect?index=
POST   /api/v1/guest/ui/{activate|tap|taps|text}
GET    /api/v1/guest/screenshot?maxWidth=&quality=
GET    /api/v1/ui/tree
POST   /api/v1/ui/{activate|tap|taps|tab|text}
GET    /api/v1/logs?since=&limit=&wait=
POST   /api/v1/logs                     # {msg, src} push a line
GET    /api/v1/logs/guest[?name=&offset=&limit=]
DELETE /api/v1/logs/guest[?name=]
POST   /api/v1/keepalive                # {mode}
```

## 7. Known limitations

- The server is only online while LiveContainer is in the foreground or kept alive by the audio mode; a suspended
  process times every request out.
- Container-side screenshots are composited in-process, so a guest window may come out black — use
  `lc_guest_screenshot`, which renders inside the guest process.
- In-guest taps rely on `multitask: true`: a non-multitask launch hands the foreground to the guest and the host
  server drops.
- `lc_guest_logs` covers stderr/stdout (NSLog / printf / Swift print). Logs written through `os_log()` go to the
  unified logging system and are not captured.
- Launching a guest app without App Extensions fails with `LiveProcess extension not found` (tick *Keep Extensions*
  when re-signing).
- Tweaks are only loaded after the device re-signs them; `changedCount=0` from `lc_tweak_sign` means the certificate
  is unusable (wrong p12 password or expired).
