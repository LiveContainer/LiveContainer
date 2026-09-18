#!/usr/bin/env python3
"""Merge SideStore's App Intents metadata into LiveContainer's.

An app bundle has exactly one Metadata.appintents slot, and both LiveContainer
(App Shortcuts for guest apps) and the grafted SideStore now want it. Copying
one over the other loses the loser, so merge instead.

An app may also declare only one AppShortcutsProvider, since the format carries
a single autoShortcutProviderMangledName. LiveContainer's wins because its
shortcut has a dynamic entity parameter that needs updateAppShortcutParameters();
SideStore's two are static refresh actions, so they lose their Siri phrases but
keep their actions in the Shortcuts app.

Only the actions SideStoreSupport.framework actually implements are imported,
with their module names rewritten. InstallIPAIntent exists in SideStore.app but
not in SideStoreSupport, so importing it would advertise an action that cannot
resolve.

Usage: merge_appintents_metadata.py <app-root actionsdata> <sidestore actionsdata>
"""
import json
import sys

MINE, THEIRS = sys.argv[1], sys.argv[2]

RENAMES = {
    "9SideStore20RefreshAllAppsIntentV": "16SideStoreSupport20RefreshAllAppsIntentV",
    "9SideStore26RefreshAllAppsWidgetIntentV": "16SideStoreSupport26RefreshAllAppsWidgetIntentV",
}
IMPORT_ACTIONS = {"RefreshAllIntent", "RefreshAllAppsWidgetIntent"}


def rewrite(obj):
    if isinstance(obj, str):
        for old, new in RENAMES.items():
            obj = obj.replace(old, new)
        return obj
    if isinstance(obj, list):
        return [rewrite(x) for x in obj]
    if isinstance(obj, dict):
        return {k: rewrite(v) for k, v in obj.items()}
    return obj


mine = json.load(open(MINE))
theirs = json.load(open(THEIRS))

imported = []
for name, action in theirs.get("actions", {}).items():
    if name not in IMPORT_ACTIONS or name in mine["actions"]:
        continue
    mine["actions"][name] = rewrite(action)
    imported.append(name)

json.dump(mine, open(MINE, "w"), separators=(",", ":"))
print(f"merged SideStore actions into app metadata: {sorted(imported)}")
print(f"kept App Shortcut provider: {sorted(mine['actions'])}")
