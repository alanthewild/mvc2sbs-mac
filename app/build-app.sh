#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
# ---------------------------------------------------------------------------
# Builds MVC2SBS.app from the Swift sources using the Command Line Tools.
# No Xcode project and no Xcode install required.
#
#   ./build-app.sh                 build into ./build
#   ./build-app.sh --install       also copy the app into /Applications
#   ./build-app.sh --skip-decoder  do not build or bundle edge264_test
#
# Builds the MVC decoder automatically if it is not already present, so this
# works on a Mac that has never run install-mac3d.sh.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="MVC2SBS"
BUNDLE_ID="local.mvc2sbs.app"
BUILD="$HERE/build"
APP="$BUILD/$NAME.app"
INSTALL=0
SKIP_DECODER=0
EDGE_SRC="$HOME/.local/src/edge264-mvc"
for arg in "$@"; do
  case "$arg" in
    --install)        INSTALL=1 ;;
    --skip-decoder)   SKIP_DECODER=1 ;;
    -h|--help)        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only"
command -v swiftc >/dev/null 2>&1 || die "swiftc not found. Run: xcode-select --install"

ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"

say "Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

say "Compiling for $TARGET"
swiftc \
  -parse-as-library \
  -O \
  -target "$TARGET" \
  -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
  -o "$APP/Contents/MacOS/$NAME" \
  "$HERE"/Sources/*.swift

# --- bundle the tools we build ourselves ---------------------------------
# mvc2sbs is a shell script, pgs3d.py is Python, and edge264_test is built
# static, so all three drop straight into the bundle with no dylib juggling.
# FFmpeg is the exception: the Homebrew build links against a tree of dylibs
# under /opt/homebrew, so bundling it means relocating install names. Left as
# an external dependency on purpose.
REPO="$(cd "$HERE/.." && pwd)"

# The app version IS the bundled tool version. That way any mismatch between
# the app and the mvc2sbs inside it is detectable at runtime.
TOOL_VERSION="$(grep -m1 '^VERSION=' "$REPO/mvc2sbs" 2>/dev/null | cut -d'"' -f2)"
[[ -n "$TOOL_VERSION" ]] || TOOL_VERSION="0.0"
say "Bundling mvc2sbs $TOOL_VERSION"
TOOLDIR="$APP/Contents/Resources"
bundled=0

for tool in mvc2sbs pgs3d.py mkvdiff subs3d; do
  if [[ -f "$REPO/$tool" ]]; then
    install -m 0755 "$REPO/$tool" "$TOOLDIR/$tool"
    bundled=$((bundled + 1))
  else
    say "warning: $tool not found at $REPO/$tool, the app will fall back to PATH"
  fi
done

find_edge() {
  local c
  for c in "$HOME/.local/bin/edge264_test" "$EDGE_SRC/edge264_test" \
           "$(command -v edge264_test 2>/dev/null || true)"; do
    [[ -n "$c" && -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

EDGE="$(find_edge || true)"

# The decoder is the one piece the app cannot work without, and it is cheap to
# build, so build it rather than shipping a broken bundle. Needs only git, make
# and the Command Line Tools, which are already present if swiftc ran.
if [[ -z "$EDGE" && $SKIP_DECODER -eq 0 ]]; then
  say "edge264_test not found, building it (about a minute)"
  mkdir -p "$(dirname "$EDGE_SRC")"
  if [[ -d "$EDGE_SRC/.git" ]]; then
    git -C "$EDGE_SRC" fetch --depth 1 origin HEAD && git -C "$EDGE_SRC" reset --hard FETCH_HEAD
  else
    git clone --depth 1 https://github.com/cbusillo/edge264-mvc.git "$EDGE_SRC"
  fi
  ( cd "$EDGE_SRC" && make STATIC=yes -j"$(sysctl -n hw.ncpu)" ) || \
    die "edge264 build failed. Run install-mac3d.sh for a fuller setup."
  EDGE="$(find_edge || true)"
fi

if [[ -n "$EDGE" ]]; then
  install -m 0755 "$EDGE" "$TOOLDIR/edge264_test"
  bundled=$((bundled + 1))
elif [[ $SKIP_DECODER -eq 1 ]]; then
  say "warning: skipping the decoder, the app will not be able to convert anything"
else
  die "edge264_test is missing and could not be built. The app cannot decode MVC without it."
fi
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
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeName</key><string>Matroska Video</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSItemContentTypes</key><array><string>org.matroska.mkv</string></array>
      </dict>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad hoc signature. Not notarised, but it stops Gatekeeper complaining about a
# completely unsigned binary and survives being moved around.
say "Ad hoc signing"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "  (codesign failed, the app will still run but may warn on first launch)"

if [[ $INSTALL -eq 1 ]]; then
  # Replacing a running app is not safe, and one failure mode is specific to
  # this design: the app runs mvc2sbs out of its own Resources folder, and bash
  # reads a script lazily by byte offset. Overwrite it mid-encode and the shell
  # carries on reading the new file from the old position, which can skip whole
  # blocks without erroring. Refuse rather than risk it.
  # Ask who has the installed binary open, rather than matching process names
  # or command lines. `pgrep -x MVC2SBS` matches anything on the system with
  # that name, and `pgrep -f` matches this script's own command line because the
  # pattern appears in it. lsof answers the actual question: is the file we are
  # about to replace in use?
  TARGET_BIN="/Applications/$NAME.app/Contents/MacOS/$NAME"
  RUNNING=""
  if [[ -x "$TARGET_BIN" ]] && command -v lsof >/dev/null 2>&1; then
    RUNNING="$(lsof -t "$TARGET_BIN" 2>/dev/null | tr '\n' ' ' | xargs || true)"
  fi
  if [[ -n "$RUNNING" ]]; then
    printf '\033[1;33mWARN:\033[0m %s\n' "$NAME is running as PID $RUNNING.
      Installing over it replaces the mvc2sbs it is executing, and bash reads a
      running script by byte offset, so an encode in progress can silently skip
      whole sections. Quit the app first.
      Check with:  ps -p $RUNNING -o pid,comm
      Set FORCE_INSTALL=1 to override."
    if [[ "${FORCE_INSTALL:-0}" != "1" ]]; then
      die "not installing over a running $NAME"
    fi
  fi
  say "Installing to /Applications"
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" /Applications/
  # Icon caches are sticky; nudge the Dock so the new icon shows immediately.
  touch "/Applications/$NAME.app"
  # Earlier names, so a rename does not leave duplicates in /Applications.
  for old in MakeSBS3D 3DSBSMaker; do
    if [[ -d "/Applications/$old.app" ]]; then
      say "Removing the old $old.app left over from before the rename"
      rm -rf "/Applications/$old.app"
    fi
  done
  say "Installed: /Applications/$NAME.app"
else
  say "Built: $APP"
  echo
  echo "Run it with:  open \"$APP\""
  echo "Install with: ./build-app.sh --install"
fi
