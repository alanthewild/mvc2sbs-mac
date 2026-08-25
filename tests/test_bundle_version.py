#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""The bundle version has to name the build, not a constant.

Both build scripts hardcoded CFBundleVersion to 1, so every app ever built
reported "3.72 (1)" and the About box could not answer the one question a
build number exists for: which binary is this. That is not a compile error and
the app looks right, so it is checked here.

MKVShrink carries mkvshrink's BUILD, which increments on every build handed
over. MVC2SBS has no BUILD of its own because it ships one binary per version,
so it carries the version with the dot removed, which still increases with
every release.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
failures = []

CASES = [
    ("app/build-app.sh", "${TOOL_VERSION//./}"),
    ("app/build-shrink.sh", "${TOOL_BUILD:-1}"),
]

for path, expected in CASES:
    text = (ROOT / path).read_text()
    m = re.search(r"<key>CFBundleVersion</key>\s*<string>([^<]*)</string>", text)
    if not m:
        failures.append("%s: no CFBundleVersion in the Info.plist it writes" % path)
        continue
    got = m.group(1)
    if got != expected:
        failures.append(
            "%s: CFBundleVersion is %r, expected %r.\n"
            "     A constant there means every build reports the same number."
            % (path, got, expected))
    # And the value it interpolates has to be set before the plist is written.
    var = re.match(r"\$\{(\w+)", expected).group(1)
    if not re.search(r"^%s=" % var, text, re.M):
        failures.append("%s: CFBundleVersion uses %s, which is never set"
                        % (path, var))

if failures:
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("bundle versions name the build in %d script(s)\n\nok" % len(CASES))
