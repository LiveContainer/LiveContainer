#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$(mktemp "${TMPDIR:-/tmp}/lc-backup-policy-tests.XXXXXX")
trap 'rm -f "$test_binary"' EXIT

xcrun --sdk macosx clang \
    -fobjc-arc \
    -framework Foundation \
    -I "$repo_root/LiveContainer" \
    "$repo_root/LiveContainer/LCBackupPolicyManager.m" \
    "$repo_root/Tests/LCBackupPolicyManagerTests.m" \
    -o "$test_binary"

"$test_binary"
