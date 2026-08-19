#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
# ---------------------------------------------------------------------------
# Builds MKVShrink.app from the Swift sources using the Command Line Tools.
# No Xcode project and no Xcode install required.
#
#   ./build-shrink.sh              build into ./build
#   ./build-shrink.sh --install    also copy the app into /Applications
#
# A separate bundle from MVC2SBS on purpose. That app converts one disc rip at
# a time and never touches your originals; this one sweeps a library and can
# move or replace files. Putting a destructive bulk tool in the same window as
# a safe single-file one is how somebody eventually clicks the wrong Start.
#
# Tools.swift is compiled into both apps from one copy, so tool discovery
# cannot drift between them.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="MKVShrink"
BUNDLE_ID="local.mkvshrink.app"
BUILD="$HERE/build"
APP="$BUILD/$NAME.app"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install)  INSTALL=1 ;;
    -h|--help)  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only"
command -v swiftc >/dev/null 2>&1 || die "swiftc not found. Run: xcode-select --install"

ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"
REPO="$(cd "$HERE/.." && pwd)"

say "Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

say "Compiling for $TARGET"
# Tools.swift comes from the other app's sources deliberately: one copy of the
# tool discovery logic, compiled into both bundles.
swiftc \
  -parse-as-library \
  -O \
  -target "$TARGET" \
  -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
  -o "$APP/Contents/MacOS/$NAME" \
  "$HERE"/shrink/Sources/*.swift \
  "$HERE"/Sources/Tools.swift

TOOL_VERSION="$(grep -m1 '^VERSION=' "$REPO/mkvshrink" 2>/dev/null | cut -d'"' -f2)"
TOOL_BUILD="$(grep -m1 '^BUILD=' "$REPO/mkvshrink" 2>/dev/null | cut -d'"' -f2)"
[[ -n "$TOOL_VERSION" ]] || TOOL_VERSION="0.0"
say "Bundling mkvshrink ${TOOL_VERSION} build ${TOOL_BUILD:-?}"

TOOLDIR="$APP/Contents/Resources"
bundled=0
# mkvdiff goes in because mkvshrink looks for it beside itself. FFmpeg and
# MKVToolNix stay external: the Homebrew builds link against a tree of dylibs
# under /opt/homebrew, so bundling them means relocating install names.
for tool in mkvshrink mkvdiff; do
  if [[ -f "$REPO/$tool" ]]; then
    install -m 0755 "$REPO/$tool" "$TOOLDIR/$tool"
    bundled=$((bundled + 1))
  else
    say "warning: $tool not found at $REPO/$tool, the app will fall back to PATH"
  fi
done
say "Bundled $bundled tool(s) into the app"

if [[ -f "$HERE/$NAME.icns" ]]; then
  cp "$HERE/$NAME.icns" "$APP/Contents/Resources/$NAME.icns"
else
  say "No icon found, regenerate with: python3 make-icon.py"
fi

say "Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$NAME</string>
    <key>CFBundleDisplayName</key>       <string>$NAME</string>
    <key>CFBundleExecutable</key>        <string>$NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$TOOL_VERSION</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>CFBundleIconFile</key>          <string>$NAME</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

# Unsigned builds are quarantined on first run. Ad-hoc signing avoids the
# "damaged and should be moved to the Bin" dialogue that a plain copy gets.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    say "warning: ad-hoc signing failed, the first launch may need a right click and Open"
fi

say "Built $APP"

if [[ $INSTALL -eq 1 ]]; then
  if pgrep -x "$NAME" >/dev/null 2>&1; then
    die "$NAME is running. Quit it first, or the copy will fail halfway."
  fi
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" /Applications/
  say "Installed /Applications/$NAME.app"
fi
