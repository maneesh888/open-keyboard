#!/bin/bash
set -euo pipefail

# Stamp each built app/extension after Xcode processes its Info.plist. A dirty build
# retains the base commit but is explicitly marked as not an exact source snapshot.
revision="$(git -C "$SRCROOT" rev-parse --verify HEAD)"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || exit 1
if [[ -n "$(git -C "$SRCROOT" status --porcelain --untracked-files=no)" ]]; then
  revision="${revision}+dirty"
fi

plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
[[ -f "$plist" ]] || { echo "Processed Info.plist is unavailable for source stamping" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :OpenKeyboardSourceRevision $revision" "$plist" >/dev/null 2>&1 ||
  /usr/libexec/PlistBuddy -c "Add :OpenKeyboardSourceRevision string $revision" "$plist"
