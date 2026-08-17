#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""Every JobSettings property must be handled by the custom Codable decoder.

Swift's synthesised decoder throws on a missing key even when the property has
a default value. That makes adding one setting silently wipe every saved
default the user has, so JobSettings has a hand written init(from:). A hand
written decoder is only correct while somebody remembers to update it, which is
what this test is for.

It also checks that every setting the app can change is actually passed to the
script, because a control that changes nothing is worse than no control.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL = (ROOT / "app/Sources/Model.swift").read_text()
RUNNER = (ROOT / "app/Sources/Runner.swift").read_text()

failures = []


def section(text, start, end):
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


# --- properties declared on JobSettings ------------------------------------
struct = section(MODEL, "struct JobSettings", "\n    static let presets")
# Stored properties only. A computed property (`var x: T { ... }`) is not
# encoded, cannot be decoded, and is not a setting.
declared = [
    name for name, rest in re.findall(r"^    var (\w+):([^\n]*)", struct, re.M)
    if "{" not in rest
]

# --- properties the decoder assigns ----------------------------------------
decoder = section(MODEL, "    init(from decoder: Decoder) throws {", "\n    }\n}")
assigned = set(re.findall(r"^        (\w+) = ", decoder, re.M))

missing = [p for p in declared if p not in assigned]
if missing:
    failures.append(
        "JobSettings.init(from:) does not decode: " + ", ".join(missing)
        + "\n  Upgrading users would lose every saved default."
    )

extra = sorted(assigned - set(declared))
if extra:
    failures.append("decoder assigns properties that do not exist: " + ", ".join(extra))

# --- properties the runner actually uses -----------------------------------
# outputFolder and outputName feed outputURL; schema is bookkeeping about which
# generation of recommended defaults a saved blob came from. None of the three
# is an argument to the script.
NOT_ARGUMENTS = {"outputFolder", "outputName", "schema"}
unused = [
    p for p in declared
    if p not in NOT_ARGUMENTS and not re.search(r"\bs\.%s\b" % p, RUNNER)
]
if unused:
    failures.append(
        "Runner never reads: " + ", ".join(unused)
        + "\n  The control exists in the app but changes nothing."
    )

print("JobSettings properties: %d" % len(declared))
print("decoded:                %d" % len(assigned & set(declared)))
print("read by Runner:         %d" % (len(declared) - len(unused) - len(NOT_ARGUMENTS)))

if failures:
    print()
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)

print("\nok")
