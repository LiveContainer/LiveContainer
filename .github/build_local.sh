#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[build] %s\n' "$*"
}

sdk_version_from_path() {
  local sdk_path="$1"
  local name
  local version
  name="$(basename "$sdk_path")"
  version="${name#iPhoneOS}"
  version="${version%.sdk}"
  if [[ "$version" == "$name" || -z "$version" ]]; then
    version="0"
  fi
  printf '%s' "$version"
}

detect_local_sdk() {
  local root="$1"
  local best_path=""
  local best_version="0"
  local candidate
  local version

  while IFS= read -r candidate; do
    version="$(sdk_version_from_path "$candidate")"
    if [[ "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -n1)" == "$version" ]]; then
      best_version="$version"
      best_path="$candidate"
    fi
  done < <(find "$root" -maxdepth 4 -type d -name 'iPhoneOS*.sdk' | sort)

  printf '%s' "$best_path"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

download_file() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$out"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return
  fi
  echo "missing required downloader (curl or wget)" >&2
  exit 1
}

plist_try() {
  local cmd="$1"
  local file="$2"
  /usr/libexec/PlistBuddy -c "$cmd" "$file" >/dev/null 2>&1 || true
}

sign_if_possible() {
  local bin="$1"
  local ent="${2:-}"
  if ! command -v ldid >/dev/null 2>&1; then
    log "ldid not found, skipping signature update for $bin"
    return
  fi
  if [[ -n "$ent" ]]; then
    ldid -S"$ent" "$bin"
  else
    ldid -S"" "$bin"
  fi
}

need_cmd unzip
need_cmd zip
need_cmd mv
need_cmd cp
need_cmd find

scheme="${scheme:-LiveContainer}"
archive_path="${archive_path:-archive}"
base_ipa_path="${BASE_IPA_PATH:-}"
sidestore_ipa_url="${SIDESTORE_IPA_URL:-https://github.com/LiveContainer/SideStore/releases/download/nightly/SideStore.ipa}"
dylibify_url="${DYLIBIFY_URL:-https://github.com/LiveContainer/SideStore/releases/download/dylibify/dylibify}"
# default behavior: build current local project sources
source_build="${SOURCE_BUILD:-1}"
local_sdk_path="${LOCAL_SDK_PATH:-}"
work_dir="${PWD}"
build_root="$work_dir/.build_no_xcode_$(date +%s)"
payload_root="$build_root/Payload"
app_root="$payload_root/LiveContainer.app"
tmp_root="$build_root/tmp"

cleanup_build_root() {
  if [[ -d "$build_root" ]]; then
    log "removing build cache: $build_root"
    rm -r "$build_root"
  fi
}

trap cleanup_build_root EXIT

while IFS= read -r old_build_dir; do
  if [[ -z "$old_build_dir" ]]; then
    continue
  fi
  log "removing previous build cache: $old_build_dir"
  rm -r "$old_build_dir"
done < <(find "$work_dir" -maxdepth 1 -type d -name '.build_no_xcode_*' ! -path "$build_root" | sort)

mkdir -p "$build_root" "$tmp_root"
log "build root: $build_root"

detected_sdk_path=""
if [[ -n "$local_sdk_path" ]]; then
  if [[ ! -d "$local_sdk_path" ]]; then
    echo "LOCAL_SDK_PATH does not exist: $local_sdk_path" >&2
    exit 1
  fi
  detected_sdk_path="$local_sdk_path"
else
  detected_sdk_path="$(detect_local_sdk "$work_dir")"
fi

if [[ -n "$detected_sdk_path" ]]; then
  log "detected local SDK: $(basename "$detected_sdk_path") at $detected_sdk_path"
  export SDKROOT="$detected_sdk_path"
else
  log "no local iPhoneOS*.sdk found under project path"
fi

if [[ "$source_build" == "1" ]]; then
  if [[ -z "$detected_sdk_path" ]]; then
    echo "SOURCE_BUILD=1 requested but no local iPhoneOS SDK was detected" >&2
    exit 1
  fi
  if ! xcodebuild -version >/dev/null 2>&1; then
    echo "SOURCE_BUILD=1 requested but xcodebuild is unavailable (full Xcode required)." >&2
    exit 1
  fi

  filetype_parameter=""
  file_to_build=""
  if ls -A | grep -qi '\.xcworkspace$'; then
    filetype_parameter="workspace"
    file_to_build="$(ls -A | grep -i '\.xcworkspace$' | head -n1)"
  else
    filetype_parameter="project"
    file_to_build="$(ls -A | grep -i '\.xcodeproj$' | head -n1)"
  fi

  if [[ -z "$file_to_build" ]]; then
    echo "SOURCE_BUILD=1 requested but no .xcodeproj or .xcworkspace found" >&2
    exit 1
  fi

  log "SOURCE_BUILD=1 using auto-detected SDK target: $detected_sdk_path"
  xcodebuild archive \
    -archivePath "$archive_path" \
    -scheme "$scheme" \
    -"$filetype_parameter" "$file_to_build" \
    -sdk "$detected_sdk_path" \
    -arch arm64 \
    -configuration Release
fi

if [[ -d "$work_dir/Payload/LiveContainer.app" ]]; then
  log "using existing Payload directory"
  cp -R "$work_dir/Payload" "$payload_root"
elif [[ -d "$archive_path.xcarchive/Products/Applications" ]]; then
  log "using app bundle from $archive_path.xcarchive"
  cp -R "$archive_path.xcarchive/Products/Applications" "$payload_root"
elif [[ -n "$base_ipa_path" && -f "$base_ipa_path" ]]; then
  log "using local base ipa: $base_ipa_path"
  unzip -q "$base_ipa_path" -d "$build_root"
else
  echo "no local app bundle found for packaging." >&2
  echo "expected one of:" >&2
  echo "  - SOURCE_BUILD=1 archive output at $archive_path.xcarchive/Products/Applications" >&2
  echo "  - Payload/LiveContainer.app in project root" >&2
  echo "  - BASE_IPA_PATH=/path/to/local.ipa" >&2
  echo "remote base ipa download is disabled in build_local.sh." >&2
  exit 1
fi

if [[ ! -d "$app_root" ]]; then
  echo "missing app bundle at $app_root" >&2
  exit 1
fi

if [[ -d "$app_root/Frameworks/SideStore.framework" ]]; then
  mv "$app_root/Frameworks/SideStore.framework" "$tmp_root/SideStore.framework"
fi

log "creating ${scheme}.ipa"
(
  cd "$build_root"
  zip -qry "$work_dir/${scheme}.ipa" Payload -x "._*" -x ".DS_Store" -x "__MACOSX"
)

if [[ -d "$tmp_root/SideStore.framework" ]]; then
  mv "$tmp_root/SideStore.framework" "$app_root/Frameworks/SideStore.framework"
fi

info_plist="$app_root/Info.plist"
settings_plist="$app_root/Settings.bundle/Root.plist"

plist_try 'Add :ALTAppGroups array' "$info_plist"
plist_try 'Add :ALTAppGroups:0 string group.com.SideStore.SideStore' "$info_plist"
plist_try 'Add :CFBundleURLTypes:1 dict' "$info_plist"
plist_try 'Add :CFBundleURLTypes:1:CFBundleURLName string com.kdt.livecontainer.sidestoreurlscheme' "$info_plist"
plist_try 'Add :CFBundleURLTypes:1:CFBundleURLSchemes array' "$info_plist"
plist_try 'Add :CFBundleURLTypes:1:CFBundleURLSchemes:0 string sidestore' "$info_plist"
plist_try 'Add :CFBundleURLTypes:2 dict' "$info_plist"
plist_try 'Add :CFBundleURLTypes:2:CFBundleURLName string com.kdt.livecontainer.sidestorebackupurlscheme' "$info_plist"
plist_try 'Add :CFBundleURLTypes:2:CFBundleURLSchemes array' "$info_plist"
plist_try 'Add :CFBundleURLTypes:2:CFBundleURLSchemes:0 string sidestore-com.kdt.livecontainer' "$info_plist"
plist_try 'Add :INIntentsSupported array' "$info_plist"
plist_try 'Add :INIntentsSupported:0 string RefreshAllIntent' "$info_plist"
plist_try 'Add :INIntentsSupported:1 string ViewAppIntent' "$info_plist"
plist_try 'Add :NSUserActivityTypes array' "$info_plist"
plist_try 'Add :NSUserActivityTypes:0 string RefreshAllIntent' "$info_plist"
plist_try 'Add :NSUserActivityTypes:1 string ViewAppIntent' "$info_plist"

if [[ -f "$settings_plist" ]]; then
  plist_try 'Add :PreferenceSpecifiers:3:Type string PSToggleSwitchSpecifier' "$settings_plist"
  plist_try 'Add :PreferenceSpecifiers:3:Title string Open SideStore' "$settings_plist"
  plist_try 'Add :PreferenceSpecifiers:3:Key string LCOpenSideStore' "$settings_plist"
  plist_try 'Add :PreferenceSpecifiers:3:DefaultValue bool false' "$settings_plist"
fi

local_sidestore_ipa="$tmp_root/SideStore.ipa"
local_dylibify="$tmp_root/dylibify"

log "downloading sidestore ipa: $sidestore_ipa_url"
download_file "$sidestore_ipa_url" "$local_sidestore_ipa"

log "downloading dylibify helper: $dylibify_url"
download_file "$dylibify_url" "$local_dylibify"
chmod +x "$local_dylibify"

unzip -q "$local_sidestore_ipa" -d "$tmp_root/sidestore_unpack"

sidestore_app="$tmp_root/sidestore_unpack/Payload/SideStore.app"
sidestore_framework="$app_root/Frameworks/SideStoreApp.framework"

if [[ ! -d "$sidestore_app" ]]; then
  echo "missing SideStore.app in downloaded ipa" >&2
  exit 1
fi

mv "$sidestore_app" "$sidestore_framework"

"$local_dylibify" "$sidestore_framework/SideStore" "$sidestore_framework/SideStore.dylib"
mv "$sidestore_framework/SideStore.dylib" "$sidestore_framework/SideStore"
sign_if_possible "$sidestore_framework/SideStore"

if [[ -f ".github/sidelc/LCAppInfo.plist" ]]; then
  cp ".github/sidelc/LCAppInfo.plist" "$sidestore_framework/"
fi

if [[ -f "$sidestore_framework/Intents.intentdefinition" ]]; then
  cp "$sidestore_framework/Intents.intentdefinition" "$app_root/"
fi
if [[ -f "$sidestore_framework/ViewApp.intentdefinition" ]]; then
  cp "$sidestore_framework/ViewApp.intentdefinition" "$app_root/"
fi
if [[ -d "$sidestore_framework/Metadata.appintents" ]]; then
  cp -R "$sidestore_framework/Metadata.appintents" "$app_root/Metadata.appintents"
fi

if [[ -d "$sidestore_framework/PlugIns/AltWidgetExtension.appex" ]]; then
  widget_root="$app_root/PlugIns/LiveWidgetExtension.appex"
  mv "$sidestore_framework/PlugIns/AltWidgetExtension.appex" "$widget_root"
  if [[ -d "$sidestore_framework/Frameworks" ]]; then
    cp -R "$sidestore_framework/Frameworks" "$widget_root"
  fi
  plist_try 'Set :CFBundleIdentifier com.kdt.livecontainer.LiveWidget' "$widget_root/Info.plist"
  plist_try 'Set :CFBundleExecutable LiveWidgetExtension' "$widget_root/Info.plist"
  if [[ -f "$widget_root/AltWidgetExtension" ]]; then
    mv "$widget_root/AltWidgetExtension" "$widget_root/LiveWidgetExtension"
  fi
  if [[ -f "$widget_root/LiveWidgetExtension" && -f ".github/sidelc/LiveWidgetExtension_adhoc.xml" ]]; then
    sign_if_possible "$widget_root/LiveWidgetExtension" ".github/sidelc/LiveWidgetExtension_adhoc.xml"
  fi
fi

if command -v ldid >/dev/null 2>&1; then
  while IFS= read -r -d '' bin; do
    sign_if_possible "$bin"
  done < <(find "$payload_root" -type f -perm -111 -print0)
fi

log "creating ${scheme}+SideStore.ipa"
(
  cd "$build_root"
  zip -qry "$work_dir/${scheme}+SideStore.ipa" Payload -x "._*" -x ".DS_Store" -x "__MACOSX"
)

log "done: $work_dir/${scheme}.ipa"
log "done: $work_dir/${scheme}+SideStore.ipa"
