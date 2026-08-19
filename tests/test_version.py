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

# mkvshrink shares the release line with the other three. It was developed
# against its own numbering and arrived at 3.26 while this repository was at
# 3.67, which is exactly the ambiguity a version is supposed to remove. Its own
# PROJECTSTATUS.md says VERSION is the repository release, and BUILD already
# answers the finer question of which script wrote a given file, so there is no
# reason for a second numbering scheme.
shrink = (ROOT / "mkvshrink").read_text()
ms2 = re.search(r'^VERSION="([^"]+)"', shrink, re.M)
mb = re.search(r'^BUILD="([^"]+)"', shrink, re.M)
if not ms2 or not mb:
    print("FAIL mkvshrink needs both a VERSION and a BUILD line")
    sys.exit(1)
shrink_version, shrink_build = ms2.group(1), mb.group(1)
if "MKVSHRINK_VERSION" not in shrink:
    print("FAIL mkvshrink does not stamp MKVSHRINK_VERSION into its output")
    sys.exit(1)

changelog = (ROOT / "CHANGELOG.md").read_text()
# An "## Unreleased" heading is allowed to sit above the newest version, so
# work can accumulate between releases without the scripts claiming a number
# that nothing has been built under. The rule that matters is unchanged: every
# archive handed over carries a version, and that version names a real section.
h = re.search(r'^## +([0-9]+\.[0-9]+)', changelog, re.M)
if not h:
    print("FAIL no '## X.Y' heading in CHANGELOG.md")
    sys.exit(1)
newest = h.group(1)

print("mvc2sbs VERSION   %s" % version)
print("mkvdiff VERSION   %s" % diff_version)
print("subs3d VERSION    %s" % subs_version)
print("mkvshrink VERSION %s build %s" % (shrink_version, shrink_build))
print("CHANGELOG newest  %s" % newest)
if re.search(r"^## +Unreleased", changelog, re.M):
    print("CHANGELOG also has an Unreleased section, which is fine between ships")

if newest not in (version, diff_version, subs_version, shrink_version) or \
        len({version, diff_version, subs_version, shrink_version}) != 1:
    print()
    print("FAIL these must match. Bump VERSION in mvc2sbs, mkvdiff, subs3d and")
    print("     mkvshrink, and add a")
    print("     heading to CHANGELOG.md, or a released file cannot be traced to")
    print("     the build that made it.")
    sys.exit(1)

print("\nok")
