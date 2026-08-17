#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
# ---------------------------------------------------------------------------
# The installer has broken twice, both times in the same way: a guard added to
# make it safer stopped it doing its job. The second time it exited before
# installing anything, on a clean machine, which is the one case that has to
# work. Both are cheap to test and neither was tested.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

check() {  # $1 = description, $2 = 0 for pass
  if [[ "$2" -eq 0 ]]; then
    printf '  ok    %s\n' "$1"
  else
    printf '  FAIL  %s\n' "$1"
    FAILED=1
  fi
}

run_install() {  # $1 = prefix
  MAC3D_TEST=1 "$ROOT/install-mac3d.sh" --scripts-only --prefix "$1" >"$TMP/log" 2>&1
  echo $?
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

VERSION="$(grep -m1 '^VERSION="' "$ROOT/mvc2sbs" | cut -d'"' -f2)"
echo "testing install of $VERSION"
echo

# --- clean machine, nothing installed yet ----------------------------------
PREFIX="$TMP/clean"
RC="$(run_install "$PREFIX")"
check "clean install exits 0" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"
[[ "$RC" -eq 0 ]] || { echo "--- installer output ---"; cat "$TMP/log"; }
for f in mvc2sbs mkvdiff pgs3d.py subs3d mkvshrink; do
  check "clean install wrote $f" "$([[ -x "$PREFIX/$f" || -f "$PREFIX/$f" ]] && echo 0 || echo 1)"
done
GOT="$("$PREFIX/mvc2sbs" --version 2>/dev/null || true)"
check "installed mvc2sbs reports $VERSION" \
  "$([[ "$GOT" == "mvc2sbs $VERSION" ]] && echo 0 || echo 1)"

# --- upgrade over an existing install --------------------------------------
PREFIX2="$TMP/upgrade"
mkdir -p "$PREFIX2"
sed 's/^VERSION=.*/VERSION="0.1"/' "$ROOT/mvc2sbs" > "$PREFIX2/mvc2sbs"
chmod +x "$PREFIX2/mvc2sbs"
RC="$(run_install "$PREFIX2")"
check "upgrade over an older install exits 0" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"
GOT="$("$PREFIX2/mvc2sbs" --version 2>/dev/null || true)"
check "upgrade replaced the old copy" \
  "$([[ "$GOT" == "mvc2sbs $VERSION" ]] && echo 0 || echo 1)"

# --- downgrade is warned about, not silent ---------------------------------
PREFIX3="$TMP/downgrade"
mkdir -p "$PREFIX3"
sed 's/^VERSION=.*/VERSION="99.0"/' "$ROOT/mvc2sbs" > "$PREFIX3/mvc2sbs"
chmod +x "$PREFIX3/mvc2sbs"
RC="$(run_install "$PREFIX3")"
check "downgrade still exits 0" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"
check "downgrade printed a warning" \
  "$(grep -q "which is newer" "$TMP/log" && echo 0 || echo 1)"

# --- HERE must be resolved before anything changes directory ---------------
# It was not. The decoder build does `cd "$SRCDIR"`, and HERE was computed after
# that from a relative BASH_SOURCE, so "." resolved to the edge264 source tree.
# Every copy step was wrapped in `if [[ -f ... ]]`, so all of them were skipped
# in silence and the script reported success.
HERE_LINE="$(grep -n '^HERE=' "$ROOT/install-mac3d.sh" | head -1 | cut -d: -f1)"
CD_LINE="$(grep -vn '^[[:space:]]*#' "$ROOT/install-mac3d.sh" \
           | grep -n '^[0-9]*:[[:space:]]*cd ' | head -1 | cut -d: -f1)"
if [[ -z "$HERE_LINE" ]]; then
  check "HERE is assigned somewhere" 1
elif [[ -z "$CD_LINE" ]]; then
  check "HERE resolved before any cd" 0
else
  check "HERE resolved before any cd" "$([[ "$HERE_LINE" -lt "$CD_LINE" ]] && echo 0 || echo 1)"
fi

# --- invoked by a relative path, the way a person actually runs it ----------
PREFIX4="$TMP/relative"
( cd "$ROOT" && MAC3D_TEST=1 ./install-mac3d.sh --scripts-only --prefix "$PREFIX4" ) \
  >"$TMP/log4" 2>&1
check "relative invocation exits 0" "$([[ $? -eq 0 ]] && echo 0 || echo 1)"
GOT="$("$PREFIX4/mvc2sbs" --version 2>/dev/null || true)"
check "relative invocation installed the right version" \
  "$([[ "$GOT" == "mvc2sbs $VERSION" ]] && echo 0 || echo 1)"

# --- a missing source file must fail loudly --------------------------------
FAKE="$TMP/fake"
mkdir -p "$FAKE"
cp "$ROOT/install-mac3d.sh" "$FAKE/"
MAC3D_TEST=1 "$FAKE/install-mac3d.sh" --scripts-only --prefix "$TMP/nowhere" \
  >"$TMP/log5" 2>&1
check "missing source files is an error, not a silent success" \
  "$([[ $? -ne 0 ]] && echo 0 || echo 1)"
check "and it says where it looked" \
  "$(grep -q "Looked in" "$TMP/log5" && echo 0 || echo 1)"

# --- the installer must not depend on tools that vary between platforms -----
# It died on a Mac at exactly this point with an existing install present. Any
# non-portable command in the version comparison takes the whole script with it
# under set -e, before anything is copied.
if grep -v '^[[:space:]]*#' "$ROOT/install-mac3d.sh" | grep -q 'sort -V'; then
  check "no sort -V (not portable to BSD sort)" 1
else
  check "no sort -V (not portable to BSD sort)" 0
fi

echo
if [[ "$FAILED" -ne 0 ]]; then
  echo "FAILED"
  exit 1
fi
echo "ok"
