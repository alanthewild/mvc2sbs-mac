#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""The automatic output name, checked against real filenames.

`cleanName` in Model.swift strips 3D and MVC markers from a source filename to
produce the default output name. It originally stripped suffixes only, so
"Avatar- Fire and Ash (2025).3D.MVC.Disc 1" kept its markers because they sit in
the middle.

Nothing here can run Swift, so this tests a Python transcription of the rule and
checks the Swift still uses the same pattern. That catches a changed pattern and
a wrong rule; it cannot catch a Swift typo elsewhere in the function.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL = (ROOT / "app/Sources/Model.swift").read_text()

PATTERN = r"[._-](?:3D[._-]MVC|MVC[._-]3D|3D-MVC|MVC|3D)(?=[._-]|$)"

CASES = [
    # the one that prompted this
    ("Avatar- Fire and Ash (2025).3D.MVC.Disc 1", "Avatar- Fire and Ash (2025).Disc 1"),
    # markers at the end, which always worked
    ("Gravity_2022.3D.MVC", "Gravity_2022"),
    ("Avatar.2009.3D.MVC", "Avatar.2009"),
    ("Live Die Repeat- Edge of Tomorrow.3D.MVC", "Live Die Repeat- Edge of Tomorrow"),
    ("Movie.MVC.3D", "Movie"),
    ("Movie-3D", "Movie"),
    # markers in the middle
    ("Title.3D-MVC.1080p", "Title.1080p"),
    ("Something.MVC.Disc 2", "Something.Disc 2"),
    # must survive untouched
    ("Spy Kids 3D", "Spy Kids 3D"),          # a real film, space delimited
    ("Plain Movie", "Plain Movie"),
    ("3D.Movie", "3D.Movie"),                # leading, nothing before it to strip
]


def clean(name):
    previous = None
    while previous != name:
        previous = name
        name = re.sub(PATTERN, "", name, flags=re.I)
    name = re.sub(r"[._-]{2,}", ".", name)
    return name.strip(" ._-") or name


failures = []
for src, want in CASES:
    got = clean(src)
    if got != want:
        failures.append("%-44s -> %-38s expected %s" % (src, got, want))

# The Swift must use the same pattern, or this file is testing nothing.
swift_pattern = re.search(r'let pattern = "([^"]+)"', MODEL)
if not swift_pattern:
    failures.append("no pattern found in Model.swift cleanName")
elif swift_pattern.group(1) != PATTERN:
    failures.append(
        "Model.swift uses a different pattern:\n     Swift: %s\n     here:  %s"
        % (swift_pattern.group(1), PATTERN)
    )

print("checked %d filenames" % len(CASES))
if failures:
    print()
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("ok")
