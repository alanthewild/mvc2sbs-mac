#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""The help is an index and a page, so its identities have to be unique.

`HelpSection.id` is its title and `HelpRow.id` is its heading. SwiftUI keys
selection and ForEach on those. Two sections sharing a title makes the index
select the wrong page; two rows in one section sharing a heading makes ForEach
drop one silently. Neither is a compile error and neither looks wrong in the
source, so it is checked here.

Also checks that every documented command is reachable: a row whose body
contains "$ " but not "\\n$ " will render the command as prose, without the
monospaced block or the copy button, which is the thing that made the commands
useless before.

Both apps are checked. MKVShrink's help grew to the size of the other one's
while nothing was looking at it at all.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SOURCES = [
    ("app/Sources/ContentView.swift",
     r"let helpSections: \[HelpSection\] = \[(.*?)\n\]\n", "Help"),
    ("app/shrink/Sources/ShrinkSettingsView.swift",
     r"let shrinkHelpSections: \[ShrinkHelpSection\] = \[(.*?)\n\]\n", "ShrinkHelp"),
]

failures = []
STR = r'"((?:[^"\\]|\\.)*)"'


def check(path, body, prefix):
    """Returns (sections, rows) counted, appending to failures as it goes."""
    sec_re = prefix + r"Section\(title: " + STR
    row_re = prefix + r"Row\(heading: " + STR
    pair_re = prefix + r"Row\(heading: " + STR + r", body: " + STR

    sections = re.findall(sec_re, body)
    if not sections:
        failures.append("%s: the help array is empty" % path)

    dupes = [t for t in set(sections) if sections.count(t) > 1]
    if dupes:
        failures.append(
            "%s: duplicate section titles: %s\n"
            "     The index keys selection on the title, so one page is "
            "unreachable." % (path, ", ".join(sorted(dupes))))

    # Rows, grouped by the section they sit in.
    rows_total = 0
    for chunk in re.split(prefix + r'Section\(title: "', body)[1:]:
        title = chunk[:chunk.index('"')]
        headings = re.findall(row_re, chunk)
        rows_total += len(headings)
        if not headings:
            failures.append("%s: section %r has no rows" % (path, title))
        d = [h for h in set(headings) if headings.count(h) > 1]
        if d:
            failures.append(
                "%s: section %r has duplicate row headings: %s\n"
                "     ForEach keys on the heading, so one row would not render."
                % (path, title, ", ".join(sorted(d))))

    # The same heading with the same body in two different sections is not a
    # deliberate cross-reference, it is an edit that replaced more than it
    # meant to. That happened: a str.replace on a prefix shared by two rows put
    # the subs3d entries into both "What is in the box" and "Credits". A
    # heading reused with DIFFERENT text is fine and deliberate, so only exact
    # pairs are flagged.
    seen = {}
    for m in re.finditer(pair_re, body):
        key = (m.group(1), m.group(2))
        seen[key] = seen.get(key, 0) + 1
    for (heading, _b), n in sorted(seen.items()):
        if n > 1:
            failures.append(
                "%s: row %r appears %d times with identical text.\n"
                "     Almost certainly an edit that replaced more than one "
                "match." % (path, heading, n))

    # A command has to start its own line to be picked out as one.
    for m in re.finditer(pair_re, body):
        heading, text = m.group(1), m.group(2)
        if "$ " in text and "\\n$ " not in text:
            failures.append(
                "%s: row %r has a command that does not start a line, so it "
                "renders as prose with no copy button" % (path, heading))

    return len(sections), rows_total


for path, pattern, prefix in SOURCES:
    text = (ROOT / path).read_text()
    m = re.search(pattern, text, re.S)
    if not m:
        print("FAIL no help array in %s" % path)
        sys.exit(1)
    s, r = check(path, m.group(1), prefix)
    print("%-46s %2d sections, %3d rows" % (path, s, r))

if failures:
    print()
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("\nok")
