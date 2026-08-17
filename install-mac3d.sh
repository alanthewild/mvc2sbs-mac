#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
# ---------------------------------------------------------------------------
# install-mac3d.sh
#
# Installs everything mvc2sbs needs on an Apple Silicon Mac:
#   - Homebrew packages: ffmpeg, mkvtoolnix, x264, cmake
#   - edge264-mvc, a native arm64 H.264/MVC decoder (this is the piece that
#     replaces AviSynth + H264MVCSource on Windows)
#
# Usage:  ./install-mac3d.sh [--prefix DIR] [--rebuild] [--scripts-only]
# Default install prefix is ~/.local/bin
#
# --scripts-only installs just the scripts, skipping Homebrew
# and the decoder build. That is what you want after unpacking a new release:
# it takes a second rather than several minutes.
# ---------------------------------------------------------------------------
set -euo pipefail

# Resolve this before anything else. The decoder build does `cd "$SRCDIR"`, and
# when the script is invoked as ./install-mac3d.sh, BASH_SOURCE is relative, so
# computing this afterwards resolves "." to wherever the last cd landed. That
# silently installed nothing and reported success: the files it looked for were
# not in the edge264 source tree, and every copy step was wrapped in
# `if [[ -f ... ]]`, so all of them were skipped without a word.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREFIX="${HOME}/.local/bin"
SRCDIR="${HOME}/.local/src/edge264-mvc"
REPO="https://github.com/cbusillo/edge264-mvc.git"
REBUILD=0
SCRIPTS_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)  PREFIX="$2"; shift 2 ;;
    --src)     SRCDIR="$2"; shift 2 ;;
    --rebuild) REBUILD=1; shift ;;
    --scripts-only) SCRIPTS_ONLY=1; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- sanity ---------------------------------------------------------------
# MAC3D_TEST=1 lets the test suite exercise the script-installing path on a
# build machine. It skips the platform and toolchain checks and nothing else.
if [[ "${MAC3D_TEST:-0}" != "1" ]]; then
[[ "$(uname -s)" == "Darwin" ]] || die "this installer is for macOS"
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "WARNING: not Apple Silicon. The decoder will still build for x86_64 but slower."
fi

if ! xcode-select -p >/dev/null 2>&1; then
  say "Installing Xcode Command Line Tools (a GUI dialog will appear)"
  xcode-select --install || true
  die "Re-run this script once the Command Line Tools finish installing."
fi

if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew not found. Install it from https://brew.sh then re-run."
fi
fi

# --- brew deps ------------------------------------------------------------
if [[ $SCRIPTS_ONLY -eq 0 ]]; then
say "Installing Homebrew packages"
brew install ffmpeg mkvtoolnix x264 || true

for t in ffmpeg ffprobe mkvmerge mkvpropedit; do
  command -v "$t" >/dev/null 2>&1 || die "$t missing after brew install"
done

# --- edge264-mvc ----------------------------------------------------------
say "Fetching edge264-mvc (native MVC decoder)"
mkdir -p "$(dirname "$SRCDIR")"
if [[ -d "$SRCDIR/.git" ]]; then
  git -C "$SRCDIR" fetch --depth 1 origin HEAD
  git -C "$SRCDIR" reset --hard FETCH_HEAD
else
  git clone --depth 1 "$REPO" "$SRCDIR"
fi

say "Building edge264_test"
cd "$SRCDIR"
[[ $REBUILD -eq 1 ]] && make clean >/dev/null 2>&1 || true
make STATIC=yes -j"$(sysctl -n hw.ncpu)"

[[ -x "$SRCDIR/edge264_test" ]] || die "build produced no edge264_test binary"

mkdir -p "$PREFIX"
install -m 0755 "$SRCDIR/edge264_test" "$PREFIX/edge264_test"

# macOS Gatekeeper: a locally compiled binary needs no notarisation, but strip
# any quarantine attribute that may have come along with the source tarball.
xattr -d com.apple.quarantine "$PREFIX/edge264_test" 2>/dev/null || true

say "Installed: $PREFIX/edge264_test"
fi

# --- mvc2sbs --------------------------------------------------------------

# Refuse to quietly install an older build over a newer one. macOS unpacks a
# second copy of an archive as "name 2" rather than replacing "name", so it is
# easy to keep running the installer out of a stale folder and wonder why
# nothing changed.
# Under `set -e` with pipefail, a grep that matches nothing, or a file that is
# not there, fails the whole pipeline and kills the script. On a clean machine
# there is no previous install to read, which is exactly when the installer
# most needs to work.
ver_of() {
  [[ -r "$1" ]] || return 0
  grep -m1 '^VERSION="' "$1" 2>/dev/null | cut -d'"' -f2 || true
}
NEWV="$(ver_of "$HERE/mvc2sbs" || true)"
OLDV="$(ver_of "$PREFIX/mvc2sbs" || true)"
# Compare versions without sort -V. BSD sort, which is what macOS ships, has
# not always had it, and an unknown option there exits 2 and takes the whole
# script with it under set -e.
newer_than() {  # 0 if $1 is a later version than $2
  local a b i
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for ((i = 0; i < 4; i++)); do
    local x="${a[i]:-0}" y="${b[i]:-0}"
    x="${x//[^0-9]/}"; y="${y//[^0-9]/}"
    (( 10#${x:-0} > 10#${y:-0} )) && return 0
    (( 10#${x:-0} < 10#${y:-0} )) && return 1
  done
  return 1
}
if [[ -n "$NEWV" && -n "$OLDV" && "$NEWV" != "$OLDV" ]]; then
  if newer_than "$OLDV" "$NEWV"; then
    printf '\033[1;33mWARN:\033[0m %s\n' "you are installing mvc2sbs $NEWV over $OLDV,
      which is newer. You are probably running this from an older unpacked copy.
      This folder: $HERE
      Press Ctrl-C to stop, or wait 5 seconds to downgrade anyway."
    sleep 5
  fi
fi
# --scripts-only skips the decoder section, which is where the prefix used to
# get created, so on a clean machine there was nowhere to install to.
mkdir -p "$PREFIX"
say "Installing mvc2sbs ${NEWV:-unknown} from $HERE"
# Not conditional. These sit beside this script in the release, so if any is
# missing something is wrong and saying so beats installing three quarters of a
# toolchain and reporting success.
for f in mvc2sbs pgs3d.py mkvdiff subs3d mkvshrink; do
  [[ -f "$HERE/$f" ]] || die "$f is not next to this script.
      Looked in: $HERE
      Run the installer from the folder you unpacked, not a copy of it."
  install -m 0755 "$HERE/$f" "$PREFIX/$f"
done

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) echo
     echo "Add this to your ~/.zshrc:"
     echo "    export PATH=\"$PREFIX:\$PATH\""
     ;;
esac

# --- verify ---------------------------------------------------------------
# A stale copy earlier on PATH is the single most confusing failure this
# project has: the tool runs, and rejects options it has never heard of, or
# prints help with no version in it. Say so here rather than let it surface as
# a mysterious error hours later.
echo
for t in mvc2sbs mkvdiff subs3d mkvshrink; do
  [[ -x "$PREFIX/$t" ]] || continue
  FOUND="$(command -v "$t" 2>/dev/null || true)"
  MINE="$("$PREFIX/$t" --version 2>/dev/null | head -1 || true)"
  [[ -n "$MINE" ]] || MINE="$("$PREFIX/$t" --help 2>/dev/null | head -1 || true)"
  say "Installed: $PREFIX/$t  (${MINE:-version unknown})"
  if [[ -n "$FOUND" && "$FOUND" != "$PREFIX/$t" ]]; then
    printf '\033[1;33mWARN:\033[0m %s\n' "another $t is earlier on your PATH: $FOUND
      That one will run instead of the copy just installed. Remove it, or put
      $PREFIX ahead of it in PATH."
  fi
done

echo
say "Done. Verify with:  mvc2sbs --help | head -1"
