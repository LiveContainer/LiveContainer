#!/usr/bin/env python3
"""MCP bridge for the LiveContainer remote-control API (stdio -> HTTP).

Zero dependencies, standard library only. The device only speaks REST; the MCP layer lives here, so every MCP client stays dependency-free.

Usage (register it in your MCP client, e.g. Hermes mcp_servers):
    command: python3
    args: ["/home/congyong/workspace/lc-mcp/lc_mcp.py"]
    env:
      LC_REMOTE_URL:   http://100.x.y.z:8848      # device address
      LC_REMOTE_TOKEN: <token shown in Settings -> Remote Control on the device>

Self-check (no device needed):
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | python3 lc_mcp.py
"""

import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from urllib.parse import quote
import uuid

SERVER_NAME = "livecontainer-remote"
SERVER_VERSION = "0.1.0"
PROTOCOL_VERSION = "2024-11-05"

BASE = os.environ.get("LC_REMOTE_URL", "").rstrip("/")
TOKEN = os.environ.get("LC_REMOTE_TOKEN", "")
TIMEOUT = float(os.environ.get("LC_REMOTE_TIMEOUT", "300"))


# ── HTTP ────────────────────────────────────────────────────────────────────
def _request(method, path, data=None, content_type=None, timeout=None):
    if not BASE:
        raise RuntimeError("LC_REMOTE_URL is not set (e.g. http://<device-ip>:8848)")
    url = BASE + path
    req = urllib.request.Request(url, data=data, method=method)
    if TOKEN:
        req.add_header("Authorization", "Bearer " + TOKEN)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=timeout or TIMEOUT) as resp:
            body = resp.read()
            ctype = resp.headers.get("Content-Type", "")
            if "json" in ctype:
                return json.loads(body or b"{}")
            return body
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"HTTP {e.code}: {detail}") from None


def api_get(path):
    return _request("GET", path)


def api_delete(path):
    return _request("DELETE", path)


def api_upload(path, filepath):
    """Upload a single file as multipart/form-data."""
    boundary = "----lcmcp" + uuid.uuid4().hex
    filename = os.path.basename(filepath)
    ctype = mimetypes.guess_type(filename)[0] or "application/octet-stream"
    with open(filepath, "rb") as fh:
        payload = fh.read()
    head = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: {ctype}\r\n\r\n"
    ).encode()
    tail = f"\r\n--{boundary}--\r\n".encode()
    body = head + payload + tail
    return _request("POST", path, data=body,
                    content_type=f"multipart/form-data; boundary={boundary}")


# -- tool implementations --──────────────────────────────────────────────────────────────
def tool_health(_args):
    return api_get("/api/v1/health")


def tool_apps(_args):
    return api_get("/api/v1/apps")


def tool_install(args):
    path = args.get("ipa_path", "")
    if not os.path.isfile(path):
        raise RuntimeError(f"file not found: {path}")
    replace = "1" if args.get("replace", True) else "0"
    return api_upload(f"/api/v1/apps?replace={replace}", path)


def tool_uninstall(args):
    bundle_id = args.get("bundle_id", "")
    if not bundle_id:
        raise RuntimeError("bundle_id is required")
    keep = "1" if args.get("keep_data", False) else "0"
    return api_delete(f"/api/v1/apps/{urllib.parse.quote(bundle_id)}?keepData={keep}")


def tool_logs(args):
    since = int(args.get("since", 0))
    limit = int(args.get("limit", 200))
    wait = int(args.get("wait", 0))
    return api_get(f"/api/v1/logs?since={since}&limit={limit}&wait={wait}")


def tool_launch(args):
    bundle_id = args.get("bundle_id", "")
    if not bundle_id:
        raise RuntimeError("bundle_id is required")
    qs = []
    if args.get("container"):
        qs.append("container=" + urllib.parse.quote(args["container"]))
    if args.get("url"):
        qs.append("url=" + urllib.parse.quote(args["url"], safe=""))
    if args.get("multitask") is not None:
        qs.append("multitask=" + ("1" if args["multitask"] else "0"))
    suffix = ("?" + "&".join(qs)) if qs else ""
    return _request("POST", f"/api/v1/apps/{urllib.parse.quote(bundle_id)}/launch{suffix}")


def tool_tweaks(args):
    folder = args.get("folder")
    q = ("?folder=" + urllib.parse.quote(folder)) if folder else ""
    return api_get("/api/v1/tweaks" + q)


def tool_tweak_import(args):
    path = args.get("path", "")
    if not os.path.isfile(path):
        raise RuntimeError(f"file not found: {path}")
    qs = []
    if args.get("folder"):
        qs.append("folder=" + urllib.parse.quote(args["folder"]))
    qs.append("filename=" + urllib.parse.quote(os.path.basename(path)))
    return api_upload("/api/v1/tweaks?" + "&".join(qs), path)


def tool_tweak_toggle(args):
    body = json.dumps({
        "name": args.get("name", ""),
        "enabled": bool(args.get("enabled", True)),
        "folder": args.get("folder"),
    }).encode()
    return _request("PATCH", "/api/v1/tweaks", data=body, content_type="application/json")


def tool_tweak_delete(args):
    name = args.get("name", "")
    if not name:
        raise RuntimeError("name is required")
    qs = ["name=" + urllib.parse.quote(name)]
    if args.get("folder"):
        qs.append("folder=" + urllib.parse.quote(args["folder"]))
    return api_delete("/api/v1/tweaks?" + "&".join(qs))


def tool_tweak_sign(args):
    qs = ["force=" + ("1" if args.get("force") else "0")]
    if args.get("folder"):
        qs.append("folder=" + urllib.parse.quote(args["folder"]))
    return _request("POST", "/api/v1/tweaks/sign?" + "&".join(qs))


def tool_tweak_folder(args):
    name = args.get("name", "")
    if not name:
        raise RuntimeError("name is required")
    return _request("POST", "/api/v1/tweakfolders", data=json.dumps({"name": name}).encode(),
                    content_type="application/json")


def tool_windows(_args):
    return api_get("/api/v1/windows")


def tool_window_action(args):
    wid = args.get("id", "")
    action = args.get("action", "")
    if not wid or not action:
        raise RuntimeError("need id and action (scale|pip|maximize|close|press)")
    body = {}
    if args.get("scale") is not None:
        body["scale"] = float(args["scale"])
    if args.get("enabled") is not None:
        body["enabled"] = bool(args["enabled"])
    return _request("POST", f"/api/v1/windows/{urllib.parse.quote(wid)}/{action}",
                    data=json.dumps(body).encode(), content_type="application/json")


def tool_screenshot(args):
    qs = []
    if args.get("window_id"):
        qs.append("windowId=" + urllib.parse.quote(args["window_id"]))
    qs.append("quality=%d" % int(args.get("quality", 70)))
    qs.append("maxWidth=%d" % int(args.get("max_width", 1290)))
    data = _request("GET", "/api/v1/screenshot?" + "&".join(qs))
    if not isinstance(data, (bytes, bytearray)) or not data:
        raise RuntimeError("screenshot came back empty or not binary")
    out = args.get("out_path") or f"/tmp/lc-shot-{int(time.time())}.jpg"
    with open(out, "wb") as fh:
        fh.write(data)
    return {"path": out, "bytes": len(data)}


def tool_keepalive(args):
    mode = args.get("mode", "")
    if mode not in ("off", "audio", "screenAwake", "audioAndScreen"):
        raise RuntimeError("mode must be off / audio / screenAwake / audioAndScreen")
    return _request("POST", "/api/v1/keepalive",
                    data=json.dumps({"mode": mode}).encode(),
                    content_type="application/json")


def tool_install_from_url(args):
    url = args.get("url", "")
    if not url:
        raise RuntimeError("url is required")
    body = {"url": url, "replace": bool(args.get("replace", True))}
    return _request("POST", "/api/v1/apps/from-url",
                    data=json.dumps(body).encode(), content_type="application/json")


def tool_jobs(args):
    jid = args.get("job_id")
    if jid:
        return api_get("/api/v1/jobs/" + urllib.parse.quote(jid))
    return api_get("/api/v1/jobs")


def tool_ui_tree(_args):
    return api_get("/api/v1/ui/tree")


def tool_ui_activate(args):
    body = {}
    for k in ("index", "label", "identifier"):
        if args.get(k) is not None:
            body[k] = args[k]
    if not body:
        raise RuntimeError("need one of index / label / identifier / text")
    return _request("POST", "/api/v1/ui/activate",
                    data=json.dumps(body).encode(), content_type="application/json")


def tool_ui_tap(args):
    body = {"x": float(args["x"]), "y": float(args["y"])}
    return _request("POST", "/api/v1/ui/tap",
                    data=json.dumps(body).encode(), content_type="application/json")


def tool_ui_tab(args):
    body = {}
    if args.get("index") is not None:
        body["index"] = int(args["index"])
    if args.get("name"):
        body["name"] = args["name"]
    return _request("POST", "/api/v1/ui/tab",
                    data=json.dumps(body).encode(), content_type="application/json")


def tool_ui_text(args):
    return _request("POST", "/api/v1/ui/text",
                    data=json.dumps({"text": args.get("text", "")}).encode(),
                    content_type="application/json")


def tool_guest_logs(args):
    name = args.get("name")
    if not name:
        return api_get("/api/v1/logs/guest")
    qs = ["name=" + urllib.parse.quote(name),
          "offset=%d" % int(args.get("offset", 0)),
          "limit=%d" % int(args.get("limit", 65536))]
    return api_get("/api/v1/logs/guest?" + "&".join(qs))


def tool_guest_logs_clear(args):
    qs = ""
    if args.get("name"):
        qs = "?name=" + urllib.parse.quote(args["name"])
    return api_delete("/api/v1/logs/guest" + qs)


def tool_ui_taps(args):
    steps = args.get("steps") or []
    if not isinstance(steps, list) or not steps:
        raise RuntimeError("steps must be a non-empty array, e.g. [{\"label\":\"Launch\"},{\"x\":200,\"y\":300,\"delayMs\":800}]")
    body = {"steps": steps,
            "detectChange": bool(args.get("detect_change", True)),
            "captureAfter": bool(args.get("capture_after", True))}
    if args.get("window_id"):
        body["windowId"] = args["window_id"]
    res = _request("POST", "/api/v1/ui/taps",
                   data=json.dumps(body).encode(), content_type="application/json")
    b64 = None
    if isinstance(res, dict) and res.get("screenshotB64"):
        b64 = res.pop("screenshotB64")
    out_path = None
    if b64:
        import base64
        out_path = args.get("out_path") or f"/tmp/lc-seq-{int(time.time())}.jpg"
        with open(out_path, "wb") as fh:
            fh.write(base64.b64decode(b64))
        res["screenshot_path"] = out_path
    return res


def tool_guest_tree(_args):
    return api_get("/api/v1/guest/ui/tree")


def tool_guest_activate(args):
    body = {}
    for k in ("index", "label", "identifier", "x", "y"):
        if args.get(k) is not None:
            body[k] = args[k]
    if not body:
        raise RuntimeError("need one of index / label / identifier / text / x+y")
    return _request("POST", "/api/v1/guest/ui/activate",
                    data=json.dumps(body).encode(), content_type="application/json")


def tool_guest_taps(args):
    steps = args.get("steps") or []
    if not steps:
        raise RuntimeError("steps must be a non-empty array")
    body = {"steps": steps, "detectChange": bool(args.get("detect_change", True))}
    return _request("POST", "/api/v1/guest/ui/taps",
                    data=json.dumps(body).encode(), content_type="application/json")


def tool_guest_text(args):
    return _request("POST", "/api/v1/guest/ui/text",
                    data=json.dumps({"text": args.get("text", "")}).encode(),
                    content_type="application/json")


def tool_guest_screenshot(args):
    qs = ["maxWidth=%d" % int(args.get("max_width", 900)),
          "quality=%d" % int(args.get("quality", 70))]
    data = _request("GET", "/api/v1/guest/screenshot?" + "&".join(qs))
    if not isinstance(data, (bytes, bytearray)) or not data:
        raise RuntimeError("guest screenshot came back empty")
    out = args.get("out_path") or f"/tmp/lc-guest-{int(time.time())}.jpg"
    with open(out, "wb") as fh:
        fh.write(data)
    return {"path": out, "bytes": len(data)}


def tool_guest_info(_args):
    return api_get("/api/v1/guest/info")


def tool_open_app(args):
    bundle_id = args.get("bundle_id", "")
    if not bundle_id:
        raise RuntimeError("bundle_id is required (get it from lc_apps)")
    body = {"bundleId": bundle_id}
    if args.get("container"):
        body["container"] = args["container"]
    if args.get("url"):
        body["url"] = args["url"]
    return _request("POST", "/api/v1/apps/open",
                    data=json.dumps(body).encode(), content_type="application/json")


def tool_window_chrome(args):
    wid = args.get("window_id", "")
    if not wid:
        raise RuntimeError("window_id is required (get it from lc_windows)")
    return api_get("/api/v1/windows/%s/chrome" % wid)


def tool_window_press(args):
    wid = args.get("window_id", "")
    sel = args.get("selector", "")
    if not wid or not sel:
        raise RuntimeError("need window_id and selector (closeWindow / maximizeWindow / minimizeWindow)")
    return _request("POST", "/api/v1/windows/%s/press" % wid,
                    data=json.dumps({"selector": sel}).encode(), content_type="application/json")


def tool_close_app(args):
    """Close an app by bundleId: find its multitask window, fire the close button event (closeWindow) and confirm the process exited."""
    bundle_id = args.get("bundle_id", "")
    if not bundle_id:
        raise RuntimeError("bundle_id is required")
    wins = api_get("/api/v1/windows")
    targets = [w for w in wins.get("windows", []) if w.get("bundleId", "").startswith(bundle_id)]
    if not targets:
        return {"closed": False, "reason": "no window for this app (it may not have been running)", "bundleId": bundle_id}
    results = []
    for w in targets:
        r = _request("POST", "/api/v1/windows/%s/close" % w["id"],
                     data=b"{}", content_type="application/json")
        results.append({"window": w["id"], "result": r})
    alive = api_get("/api/v1/windows")
    return {"bundleId": bundle_id, "results": results,
            "windowsLeft": alive.get("count", -1)}


def tool_guest_ocr(args):
    qs = []
    if args.get("text"):
        qs.append("text=" + quote(str(args["text"])))
    if args.get("no_cache"):
        qs.append("no_cache=1")
    path = "/api/v1/guest/ocr" + (("?" + "&".join(qs)) if qs else "")
    return api_get(path)


def tool_guest_ocr_history(args):
    return api_get("/api/v1/guest/ocr/history?limit=%d" % int(args.get("limit", 20)))


def tool_guest_inspect(args):
    idx = args.get("index")
    if idx is None:
        raise RuntimeError("index is required (from lc_guest_tree)")
    return api_get("/api/v1/guest/inspect?index=%d" % int(idx))


def tool_log_push(args):
    msg = args.get("msg", "")
    if not msg:
        raise RuntimeError("msg is required")
    body = {"msg": msg, "src": args.get("src", "mcp")}
    return _request("POST", "/api/v1/logs",
                    data=json.dumps(body).encode(), content_type="application/json")


TOOLS = [
    {
        "name": "lc_window_chrome",
        "description": "Lists the selectors bound to the three title-bar buttons (close / maximize / minimize) so callers press buttons instead of guessing behaviour.",
        "inputSchema": {"type": "object", "properties": {"window_id": {"type": "string"}}, "required": ["window_id"]},
    },
    {
        "name": "lc_window_press",
        "description": "Fires the selector bound to a title-bar button (equivalent to tapping it): closeWindow / maximizeWindow / minimizeWindow.",
        "inputSchema": {
            "type": "object",
            "properties": {"window_id": {"type": "string"}, "selector": {"type": "string"}},
            "required": ["window_id", "selector"],
        },
    },
    {
        "name": "lc_close_app",
        "description": "Closes an app by bundle_id: fires the window close button and confirms the process exited. Use it to clean up after debugging.",
        "inputSchema": {"type": "object", "properties": {"bundle_id": {"type": "string"}}, "required": ["bundle_id"]},
    },
    {
        "name": "lc_open_app",
        "description": "Opens an installed app in a multitask window, waits for the guest side, and returns the window plus guest pid. Start here for in-app work.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "bundle_id": {"type": "string", "description": "from lc_apps"},
                "container": {"type": "string", "description": "data container folderName, optional"},
                "url": {"type": "string", "description": "launch URL, optional"},
            },
            "required": ["bundle_id"],
        },
    },
    {
        "name": "lc_health",
        "description": "Liveness probe: LiveContainer version and port. No token required.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "lc_apps",
        "description": "Lists installed apps in LiveContainer (bundleId, version, containers, hidden flag).",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "lc_install_ipa",
        "description": "Uploads an IPA from this machine and installs it. Returns the installed bundleId.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ipa_path": {"type": "string", "description": "absolute path to the local .ipa"},
                "replace": {"type": "boolean", "description": "replace an existing bundleId (default true)"},
            },
            "required": ["ipa_path"],
        },
    },
    {
        "name": "lc_uninstall_app",
        "description": "Uninstalls an app by bundleId. keep_data=true keeps its data container.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "bundle_id": {"type": "string"},
                "keep_data": {"type": "boolean", "description": "default false (delete data too)"},
            },
            "required": ["bundle_id"],
        },
    },
    {
        "name": "lc_launch_app",
        "description": "Launches an installed app, optionally with a data container folder and launch URL.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "bundle_id": {"type": "string"},
                "container": {"type": "string", "description": "data container folderName; omit for the default container"},
                "url": {"type": "string", "description": "launch URL passed to the app"},
                "multitask": {"type": "boolean", "description": "true = run in a LiveContainer multitask window (host UI stays up, HTTP server keeps serving)"},
            },
            "required": ["bundle_id"],
        },
    },
    {
        "name": "lc_tweaks",
        "description": "Lists tweaks (root or a specific folder) with their enabled state. Omit folder for the root.",
        "inputSchema": {
            "type": "object",
            "properties": {"folder": {"type": "string"}},
        },
    },
    {
        "name": "lc_tweak_import",
        "description": "Uploads a .dylib / .framework (zip) into the device tweak folder and re-signs it when a certificate is available.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "absolute path to the local file"},
                "folder": {"type": "string", "description": "tweak subfolder; omit for the global folder"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "lc_tweak_toggle",
        "description": "Enables or disables a tweak (the device adds/removes the .disabled suffix).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "tweak display name, e.g. BlockNetPlus.dylib"},
                "enabled": {"type": "boolean"},
                "folder": {"type": "string"},
            },
            "required": ["name", "enabled"],
        },
    },
    {
        "name": "lc_tweak_delete",
        "description": "Deletes a tweak.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "folder": {"type": "string"}},
            "required": ["name"],
        },
    },
    {
        "name": "lc_tweak_sign",
        "description": "Runs ZSign over a tweak folder (force=true re-signs even valid signatures).",
        "inputSchema": {
            "type": "object",
            "properties": {"folder": {"type": "string"}, "force": {"type": "boolean"}},
        },
    },
    {
        "name": "lc_tweak_folder",
        "description": "Creates a tweak subfolder (per-app tweak folder).",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}},
            "required": ["name"],
        },
    },
    {
        "name": "lc_windows",
        "description": "Lists multitask windows: id (dataUUID), bundleId, pid, scale, maximized, frame.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "lc_window_action",
        "description": "Window actions: scale (0.4-3.0), pip (minimise/restore), maximize, close.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "window id (dataUUID from lc_windows)"},
                "action": {"type": "string", "enum": ["scale", "pip", "maximize", "close"]},
                "scale": {"type": "number", "description": "scale factor when action=scale"},
                "enabled": {"type": "boolean", "description": "toggle for action=pip/maximize"},
            },
            "required": ["id", "action"],
        },
    },
    {
        "name": "lc_screenshot",
        "description": "Captures the screen or a window as JPEG, saves it locally and returns the path for visual inspection.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "window_id": {"type": "string", "description": "omit to capture the whole LiveContainer UI"},
                "out_path": {"type": "string", "description": "local output path, default /tmp/lc-shot-<ts>.jpg"},
                "quality": {"type": "integer", "description": "JPEG quality 1-100, default 70"},
                "max_width": {"type": "integer", "description": "max width, default 1290"},
            },
        },
    },
    {
        "name": "lc_keepalive",
        "description": "Sets the device keep-alive mode: off / audio (silent audio, online while locked) / screenAwake / audioAndScreen.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "mode": {"type": "string", "enum": ["off", "audio", "screenAwake", "audioAndScreen"]},
            },
            "required": ["mode"],
        },
    },
    {
        "name": "lc_install_from_url",
        "description": "Lets the device download and install the IPA itself (no long upload, survives suspension). Returns a jobId to poll with lc_jobs.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "direct http(s) link to the IPA"},
                "replace": {"type": "boolean", "description": "replace an existing bundleId (default true)"},
            },
            "required": ["url"],
        },
    },
    {
        "name": "lc_jobs",
        "description": "Shows async job state (omit job_id to list recent jobs).",
        "inputSchema": {
            "type": "object",
            "properties": {"job_id": {"type": "string"}},
        },
    },
    {
        "name": "lc_guest_ocr",
        "description": "OCR the current guest screen (system Vision, Chinese + English) and return text with boxes. Use it when the view tree has no text (painted UI, WebView).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "only return results containing this text"},
            },
        },
    },
    {
        "name": "lc_guest_ocr_history",
        "description": "Reviews OCR history (every run is persisted) to see what a page contained at the time.",
        "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer"}}},
    },
    {
        "name": "lc_guest_inspect",
        "description": "Dumps an element view structure (class/frame/subviews/text) to tell whether its text is a control or painted.",
        "inputSchema": {"type": "object", "properties": {"index": {"type": "integer"}}, "required": ["index"]},
    },
    {
        "name": "lc_guest_info",
        "description": "Guest process info (bundleId / pid / view size). Requires the guest app to be running.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "lc_guest_tree",
        "description": "Dumps the accessibility tree of the guest app itself (taken inside the guest process, so in-app buttons are visible).",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "lc_guest_activate",
        "description": "Activates an element inside the guest app: index / label / identifier / text / x+y via accessibilityActivate in the guest process.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "index": {"type": "integer"},
                "label": {"type": "string"},
                "identifier": {"type": "string"},
                "x": {"type": "number"},
                "y": {"type": "number"},
            },
        },
    },
    {
        "name": "lc_guest_taps",
        "description": "Runs ordered taps inside the guest app (label/index/text/coordinates) and reports whether the screen changed after each step.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "steps": {"type": "array", "items": {"type": "object"},
                          "description": "each step: {label?|identifier?|text?|index?|x,y}, optional delayMs"},
                "detect_change": {"type": "boolean"},
            },
            "required": ["steps"],
        },
    },
    {
        "name": "lc_guest_text",
        "description": "Types into the current text field inside the guest app.",
        "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
    },
    {
        "name": "lc_guest_screenshot",
        "description": "Screenshots the guest app itself (rendered in-process, avoiding cross-process compositing artefacts) and saves it locally.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "max_width": {"type": "integer", "description": "default 900"},
                "quality": {"type": "integer", "description": "JPEG quality 1-100, default 70"},
                "out_path": {"type": "string"},
            },
        },
    },
    {
        "name": "lc_ui_tree",
        "description": "Dumps the accessibility tree of the container UI (label/identifier/frame/activatable). Call this first, then activate by index.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "lc_ui_activate",
        "description": "Activates an element by index (from lc_ui_tree), label, identifier or text via accessibilityActivate / UIControl.sendActions.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "index": {"type": "integer"},
                "label": {"type": "string", "description": "element text, substring match"},
                "identifier": {"type": "string"},
            },
        },
    },
    {
        "name": "lc_ui_taps",
        "description": "Runs ordered taps (label / index / text / coordinates), each with an optional delayMs, reporting whether the screen changed per step, optionally saving a screenshot afterwards.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "steps": {
                    "type": "array",
                    "description": "steps. Each: {label?} or {identifier?} or {text?} or {index?} or {x,y}, optional delayMs (default 400) and note",
                    "items": {
                        "type": "object",
                        "properties": {
                            "label": {"type": "string"},
                            "identifier": {"type": "string"},
                            "index": {"type": "integer"},
                            "x": {"type": "number"},
                            "y": {"type": "number"},
                            "delayMs": {"type": "integer"},
                            "note": {"type": "string"},
                        },
                    },
                },
                "detect_change": {"type": "boolean", "description": "compare screenshots per step to detect change (default true)"},
                "capture_after": {"type": "boolean", "description": "save one screenshot after the run and return its path (default true)"},
                "window_id": {"type": "string", "description": "window to capture; omit for the whole UI"},
                "out_path": {"type": "string", "description": "screenshot path, default /tmp/lc-seq-<ts>.jpg"},
            },
            "required": ["steps"],
        },
    },
    {
        "name": "lc_ui_tap",
        "description": "Taps screen coordinates (x,y); the hit control is driven through sendActions or accessibilityActivate.",
        "inputSchema": {
            "type": "object",
            "properties": {"x": {"type": "number"}, "y": {"type": "number"}},
            "required": ["x", "y"],
        },
    },
    {
        "name": "lc_ui_tab",
        "description": "Switches the bottom tab by index or name (e.g. Apps / Tweaks / Settings / Sources).",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}, "name": {"type": "string"}},
        },
    },
    {
        "name": "lc_ui_text",
        "description": "Types into the current first responder (activate the field first).",
        "inputSchema": {
            "type": "object",
            "properties": {"text": {"type": "string"}},
            "required": ["text"],
        },
    },
    {
        "name": "lc_guest_logs",
        "description": "Reads guest app / injected tweak stdout-stderr. Omit name to list files; with name, reads from offset and returns next for the following call.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "log file name from the listing"},
                "offset": {"type": "integer", "description": "start byte, default 0"},
                "limit": {"type": "integer", "description": "max bytes to read, default 65536"},
            },
        },
    },
    {
        "name": "lc_guest_logs_clear",
        "description": "Deletes guest log files (omit name to clear all).",
        "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}},
    },
    {
        "name": "lc_log_push",
        "description": "Appends one line to the device log ring buffer (container / guest / tweak / script) and read it back with lc_logs by seq.",
        "inputSchema": {
            "type": "object",
            "properties": {"msg": {"type": "string"}, "src": {"type": "string", "description": "default mcp"}},
            "required": ["msg"],
        },
    },
    {
        "name": "lc_logs",
        "description": "Reads device logs (in-process stdout/stderr ring buffer). since=<latest> for deltas; wait = long-poll seconds.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "since": {"type": "integer", "description": "start after this seq (default 0)"},
                "limit": {"type": "integer", "description": "max records (default 200)"},
                "wait": {"type": "integer", "description": "seconds to wait when there is nothing new (default 0)"},
            },
        },
    },
]

HANDLERS = {
    "lc_window_chrome": tool_window_chrome,
    "lc_window_press": tool_window_press,
    "lc_close_app": tool_close_app,
    "lc_open_app": tool_open_app,
    "lc_health": tool_health,
    "lc_apps": tool_apps,
    "lc_install_ipa": tool_install,
    "lc_uninstall_app": tool_uninstall,
    "lc_launch_app": tool_launch,
    "lc_tweaks": tool_tweaks,
    "lc_tweak_import": tool_tweak_import,
    "lc_tweak_toggle": tool_tweak_toggle,
    "lc_tweak_delete": tool_tweak_delete,
    "lc_tweak_sign": tool_tweak_sign,
    "lc_tweak_folder": tool_tweak_folder,
    "lc_windows": tool_windows,
    "lc_window_action": tool_window_action,
    "lc_screenshot": tool_screenshot,
    "lc_install_from_url": tool_install_from_url,
    "lc_ui_tree": tool_ui_tree,
    "lc_ui_activate": tool_ui_activate,
    "lc_guest_ocr": tool_guest_ocr,
    "lc_guest_ocr_history": tool_guest_ocr_history,
    "lc_guest_inspect": tool_guest_inspect,
    "lc_guest_info": tool_guest_info,
    "lc_guest_tree": tool_guest_tree,
    "lc_guest_activate": tool_guest_activate,
    "lc_guest_taps": tool_guest_taps,
    "lc_guest_text": tool_guest_text,
    "lc_guest_screenshot": tool_guest_screenshot,
    "lc_ui_taps": tool_ui_taps,
    "lc_ui_tap": tool_ui_tap,
    "lc_ui_tab": tool_ui_tab,
    "lc_guest_logs": tool_guest_logs,
    "lc_guest_logs_clear": tool_guest_logs_clear,
    "lc_ui_text": tool_ui_text,
    "lc_jobs": tool_jobs,
    "lc_keepalive": tool_keepalive,
    "lc_log_push": tool_log_push,
    "lc_logs": tool_logs,
}


# -- JSON-RPC / MCP loop --───────────────────────────────────────────────────
def reply(msg_id, result=None, error=None):
    out = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        out["error"] = error
    else:
        out["result"] = result
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def handle(msg):
    method = msg.get("method")
    msg_id = msg.get("id")
    params = msg.get("params") or {}

    if method == "initialize":
        return reply(msg_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        })
    if method in ("notifications/initialized", "initialized"):
        return
    if method == "ping":
        return reply(msg_id, {})
    if method == "tools/list":
        return reply(msg_id, {"tools": TOOLS})
    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        fn = HANDLERS.get(name)
        if fn is None:
            return reply(msg_id, error={"code": -32601, "message": f"unknown tool {name}"})
        try:
            result = fn(args)
            text = json.dumps(result, ensure_ascii=False, indent=2)
            return reply(msg_id, {"content": [{"type": "text", "text": text}],
                                  "isError": False})
        except Exception as exc:  # noqa: BLE001
            return reply(msg_id, {"content": [{"type": "text", "text": f"{exc}"}],
                                  "isError": True})
    if msg_id is not None:
        return reply(msg_id, error={"code": -32601, "message": f"unknown method {method}"})


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        handle(msg)


if __name__ == "__main__":
    main()
