#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""VERSION in mvc2sbs must match the newest heading in CHANGELOG.md.

Shipping several different builds under one version number makes the version
useless for the only job it has: telling you which build produced a given file.
That happened repeatedly, so the rule is enforced here rather than remembered.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

script = (ROOT / "mvc2sbs").read_text()
m = re.search(r'^VERSION="([^"]+)"', script, re.M)
if not m:
    print("FAIL no VERSION= line in mvc2sbs")
    sys.exit(1)
version = m.group(1)

diff = (ROOT / "mkvdiff").read_text()
md = re.search(r'^VERSION="([^"]+)"', diff, re.M)
if not md:
    print("FAIL no VERSION= line in mkvdiff")
    sys.exit(1)
diff_version = md.group(1)

subs = (ROOT / "subs3d").read_text()
ms = re.search(r'^VERSION = "([^"]+)"', subs, re.M)
if not ms:
    print("FAIL no VERSION= line in subs3d")
    sys.exit(1)
subs_version = ms.group(1)

# mkvshrink is versioned on its own. It is a separate pipeline with its own
# release cadence, and forcing it to share a number would mean bumping it every
# time the 3D tools changed and vice versa, which makes the number useless for
# the one job it has. What is checked here is that it HAS a version and a build
# number and stamps both into its output, since that is the property that
# matters: being able to tell which script wrote a given file.
shrink = (ROOT / "mkvshrink").read_text()
for field in ("VERSION", "BUILD"):
    if not re.search(r'^%s="[^"]+"' % field, shrink, re.M):
        print("FAIL no %s= line in mkvshrink" % field)
        sys.exit(1)
sv = re.search(r'^VERSION="([^"]+)"', shrink, re.M).group(1)
sb = re.search(r'^BUILD="([^"]+)"', shrink, re.M).group(1)
if "MKVSHRINK_VERSION" not in shrink:
    print("FAIL mkvshrink does not stamp MKVSHRINK_VERSION into its output")
    sys.exit(1)

changelog = (ROOT / "CHANGELOG.md").read_text()
h = re.search(r'^## +([0-9]+\.[0-9]+)', changelog, re.M)
if not h:
    print("FAIL no '## X.Y' heading in CHANGELOG.md")
    sys.exit(1)
newest = h.group(1)

print("mvc2sbs VERSION   %s" % version)
print("mkvdiff VERSION   %s" % diff_version)
print("subs3d VERSION    %s" % subs_version)
print("mkvshrink         %s build %s  (versioned separately)" % (sv, sb))
print("CHANGELOG newest  %s" % newest)

if version != newest or diff_version != newest or subs_version != newest:
    print()
    print("FAIL these must match. Bump VERSION in mvc2sbs, mkvdiff and subs3d,")
    print("     add a")
    print("     heading to CHANGELOG.md, or a released file cannot be traced to")
    print("     the build that made it.")
    sys.exit(1)

print("\nok")
