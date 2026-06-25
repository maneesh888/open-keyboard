#!/usr/bin/env bash
set -euo pipefail

# Deterministically seed Simulator keyboard preferences so UI tests can select the
# real OpenKeyboard keyboard extension instead of relying on fragile Settings UI
# navigation. This script only changes the targeted Simulator's preferences.

SIMULATOR_UDID="${1:-booted}"
OPEN_KEYBOARD_INPUT_MODE="${OPEN_KEYBOARD_INPUT_MODE:-com.maneesh.openkeyboard.keyboard}"
BASE_KEYBOARD="${OPEN_KEYBOARD_BASE_KEYBOARD:-en_US@sw=QWERTY;hw=Automatic}"
EMOJI_KEYBOARD="${OPEN_KEYBOARD_EMOJI_KEYBOARD:-emoji@sw=Emoji;hw=Automatic}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found; run this on a macOS host with Xcode installed" >&2
  exit 127
fi

# The relevant domains are the same ones observed in historical successful
# real-extension proof artifacts. Keep the base and emoji keyboards present so
# normal simulator text input remains usable, then add OpenKeyboard and map en_US
# to it for host text fields whose preferred input mode is en-US.
xcrun simctl spawn "$SIMULATOR_UDID" defaults write .GlobalPreferences AppleKeyboards \
  -array "$BASE_KEYBOARD" "$EMOJI_KEYBOARD" "$OPEN_KEYBOARD_INPUT_MODE"
xcrun simctl spawn "$SIMULATOR_UDID" defaults write .GlobalPreferences AppleKeyboardsExpanded -bool true

xcrun simctl spawn "$SIMULATOR_UDID" defaults write keyboard.preferences KeyboardsCurrentAndNext \
  -array "$BASE_KEYBOARD" "$BASE_KEYBOARD" "$OPEN_KEYBOARD_INPUT_MODE"
xcrun simctl spawn "$SIMULATOR_UDID" defaults write keyboard.preferences KeyboardLastUsed "$OPEN_KEYBOARD_INPUT_MODE"
xcrun simctl spawn "$SIMULATOR_UDID" defaults write keyboard.preferences KeyboardLastUsedForLanguage \
  -dict ASCIICapable "$BASE_KEYBOARD" en_US "$OPEN_KEYBOARD_INPUT_MODE"

# Echo compact verification without dumping unrelated simulator preferences.
echo "Seeded OpenKeyboard simulator input mode preferences for ${SIMULATOR_UDID}:"
echo "  AppleKeyboards:"
xcrun simctl spawn "$SIMULATOR_UDID" defaults read .GlobalPreferences AppleKeyboards
echo "  KeyboardLastUsed:"
xcrun simctl spawn "$SIMULATOR_UDID" defaults read keyboard.preferences KeyboardLastUsed
echo "  KeyboardLastUsedForLanguage:"
xcrun simctl spawn "$SIMULATOR_UDID" defaults read keyboard.preferences KeyboardLastUsedForLanguage
