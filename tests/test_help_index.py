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
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = (ROOT / "app/Sources/ContentView.swift").read_text()

failures = []

block = re.search(r"let helpSections: \[HelpSection\] = \[(.*?)\n\]\n", SRC, re.S)
if not block:
    print("FAIL no helpSections array in ContentView.swift")
    sys.exit(1)
body = block.group(1)

sections = re.findall(r'HelpSection\(title: "((?:[^"\\]|\\.)*)"', body)
if not sections:
    failures.append("helpSections is empty")

dupes = [t for t in set(sections) if sections.count(t) > 1]
if dupes:
    failures.append(
        "duplicate section titles: %s\n"
        "     The index keys selection on the title, so one page is unreachable."
        % ", ".join(sorted(dupes)))

# Rows, grouped by the section they sit in.
per_section = re.split(r'HelpSection\(title: "', body)[1:]
rows_total = 0
for chunk in per_section:
    title = chunk[:chunk.index('"')]
    headings = re.findall(r'HelpRow\(heading: "((?:[^"\\]|\\.)*)"', chunk)
    rows_total += len(headings)
    if not headings:
        failures.append("section %r has no rows" % title)
    d = [h for h in set(headings) if headings.count(h) > 1]
    if d:
        failures.append(
            "section %r has duplicate row headings: %s\n"
            "     ForEach keys on the heading, so one row would not render."
            % (title, ", ".join(sorted(d))))

# The same heading with the same body in two different sections is not a
# deliberate cross-reference, it is an edit that replaced more than it meant to.
# That happened: a str.replace on a prefix shared by two rows put the subs3d
# entries into both "What is in the box" and "Credits". A heading reused with
# DIFFERENT text is fine and deliberate, so only exact pairs are flagged.
seen = {}
for m in re.finditer(r'HelpRow\(heading: "((?:[^"\\]|\\.)*)", body: "((?:[^"\\]|\\.)*)"', body):
    key = (m.group(1), m.group(2))
    seen[key] = seen.get(key, 0) + 1
for (heading, _b), n in sorted(seen.items()):
    if n > 1:
        failures.append(
            "row %r appears %d times with identical text.\n"
            "     Almost certainly an edit that replaced more than one match."
            % (heading, n))

# A command has to start its own line to be picked out as one.
for m in re.finditer(r'HelpRow\(heading: "((?:[^"\\]|\\.)*)", body: "((?:[^"\\]|\\.)*)"', body):
    heading, text = m.group(1), m.group(2)
    if "$ " in text and "\\n$ " not in text:
        failures.append(
            "row %r has a command that does not start a line, so it renders as "
            "prose with no copy button" % heading)

print("help sections: %d" % len(sections))
print("help rows:     %d" % rows_total)

if failures:
    print()
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("\nok")
