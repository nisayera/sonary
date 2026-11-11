#!/bin/bash
# Signs Sonary.app from the inside out with one identity, the way Apple and Sparkle ask for it,
# instead of `codesign --deep` (which signs nested code with the outer bundle's options and
# entitlements and is documented as unsuitable for signing).
#
#   scripts/sign_app.sh APP IDENTITY [KEYCHAIN]
#
# Order: helper bundles inside the frameworks (Sparkle's Installer.xpc, Downloader.xpc and
# Updater.app), loose helper executables (Sparkle's Autoupdate), the frameworks and dylibs, then
# the app. Every piece keeps its own identifier and entitlements and gets the hardened runtime.
set -euo pipefail

APP="${1:?usage: sign_app.sh APP IDENTITY [KEYCHAIN]}"
IDENTITY="${2:?usage: sign_app.sh APP IDENTITY [KEYCHAIN]}"
KEYCHAIN="${3:-}"
FRAMEWORKS="$APP/Contents/Frameworks"

ARGS=(--force --sign "$IDENTITY" --options runtime --timestamp=none)
if [ -n "$KEYCHAIN" ]; then ARGS+=(--keychain "$KEYCHAIN"); fi

sign() {
  echo "Signing ${1#"$APP"/}"
  codesign "${ARGS[@]}" --preserve-metadata=identifier,entitlements "$1"
}

if [ -d "$FRAMEWORKS" ]; then
  # 1. Bundles nested in frameworks, deepest first. `find` does not follow the Versions/Current
  #    symlink, so each one is signed once, at its real path.
  while IFS= read -r bundle; do sign "$bundle"; done < <(
    find "$FRAMEWORKS" \( -name "*.xpc" -o -name "*.app" \) -type d -prune -print |
      awk '{ print gsub("/", "/"), $0 }' | sort -rn | cut -d' ' -f2-)

  # 2. Loose executables inside a framework version (Sparkle's Autoupdate), not the framework's
  #    own binary, which is signed with the framework.
  while IFS= read -r tool; do
    framework_name=$(basename "$(dirname "$(dirname "$(dirname "$tool")")")" .framework)
    [ "$(basename "$tool")" = "$framework_name" ] && continue
    file -b "$tool" | grep -q "Mach-O" || continue
    sign "$tool"
  done < <(find "$FRAMEWORKS" -path "$FRAMEWORKS/*.framework/Versions/*" ! -path "$FRAMEWORKS/*/Versions/Current/*" \
             ! -path "$FRAMEWORKS/*.xpc/*" ! -path "$FRAMEWORKS/*.app/*" -type f -perm -0100)

  # 3. Frameworks and dylibs.
  while IFS= read -r library; do sign "$library"; done < <(
    find "$FRAMEWORKS" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print)
fi

# 4. The app, with the entitlements and flags Xcode gave it.
echo "Signing $(basename "$APP")"
codesign "${ARGS[@]}" --preserve-metadata=identifier,entitlements,flags "$APP"

codesign --verify --strict --deep --verbose=2 "$APP"
