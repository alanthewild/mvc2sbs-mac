#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""The MKVShrink GUI must only ask mkvshrink for things it accepts.

Nothing here can compile Swift, so the app's correctness cannot be proved. What
can be proved is the interface between the two, which is where a GUI driving a
command line tool actually breaks: a flag renamed in the script, or invented in
the app, produces a usage error at the moment the user presses Start, after
they have chosen folders and waited.

Three things are checked:

- every flag the app passes is one the script parses
- every flag the app passes that takes a value is given one
- the defaults the app ships match the ones the script documents, so the two
  do not quietly disagree about what "default" means

The first of these already caught three invented flags while the app was being
written: --vt, --10bit and --replace-folder. VideoToolbox and 10-bit and the
_replaced folder are all defaults with no flag to request them.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = (ROOT / "mkvshrink").read_text()
MODEL = (ROOT / "app/shrink/Sources/ShrinkModel.swift").read_text()
RUNNER = (ROOT / "app/shrink/Sources/ShrinkRunner.swift").read_text()
VIEW = (ROOT / "app/shrink/Sources/ShrinkView.swift").read_text()

failures = []

# --- what the script accepts ----------------------------------------------
# The argument parser is a case statement of the form:  --flag)  or  -x|--flag)
accepted = set()
for m in re.finditer(r"^\s{4}((?:-[\w-]+\|)*-[\w-]+)\)", SCRIPT, re.M):
    for alt in m.group(1).split("|"):
        accepted.add(alt)

if len(accepted) < 20:
    print("FAIL only found %d flags in mkvshrink's parser, the pattern must be wrong"
          % len(accepted))
    sys.exit(1)

# Flags that take a value, spotted by the shift 2 that follows them.
takes_value = set()
for m in re.finditer(r"^\s{4}((?:-[\w-]+\|)*-[\w-]+)\)(.*)$", SCRIPT, re.M):
    if "shift 2" in m.group(2):
        for alt in m.group(1).split("|"):
            takes_value.add(alt)

# --- what the app passes ---------------------------------------------------
block = re.search(r"var arguments: \[String\] \{(.*?)\n    \}", MODEL, re.S)
if not block:
    print("FAIL cannot find ShrinkSettings.arguments in ShrinkModel.swift")
    sys.exit(1)
body = block.group(1)

# Every flag literal in the file, not just the ones in this block: the
# replacement policy builds its own, and scanning only `arguments` meant
# --in-situ and --keep-originals were never checked at all.
used = sorted(set(re.findall(r'"(--[\w-]+)"', MODEL + RUNNER)))
if not used:
    failures.append("the app passes no flags at all, which cannot be right")

for flag in used:
    if flag not in accepted:
        failures.append(
            "the app passes %s, which mkvshrink does not accept.\n"
            "     Pressing Start would fail with a usage error." % flag)

# A flag needing a value must be followed by one in the same array literal.
for flag in used:
    if flag not in takes_value:
        continue
    # Either ["--flag", value] or a += ["--flag", value] form. Searched across
    # both files: the runner builds --plan, --apply and --tracks itself.
    if not re.search(r'"%s",\s*\S' % re.escape(flag), body + RUNNER):
        failures.append(
            "%s takes a value and the app appends it alone" % flag)

# The reverse direction is informational: flags the tool has and the GUI does
# not expose. Not a failure, but worth printing so the gap is visible.
INTERNAL = {"-h", "--help", "-V", "--version", "--machine", "--plan", "--apply",
            "--calibrate", "--calibrate-at", "--calibrate-len", "--keep-clips",
            "--luma", "--luma-samples", "--no-darkest", "-n", "--dry-run",
            "-i", "--interactive", "--audio", "--subs", "--replaced-dir",
            "--verify-quality", "-q", "-p", "--in-place", "--jobs", "--yes"}
unexposed = sorted(f for f in accepted
                   if f.startswith("--") and f not in INTERNAL and f not in used)

# --- the plan file is a positional interface -------------------------------
# The GUI reads a plan mkvshrink wrote and writes one mkvshrink reads back.
# Both sides address the columns by number, so adding a column to one side and
# not the other does not fail: it puts a size where a PSNR was and carries on.
header = re.search(r"printf '#action\\t([^']*?)\\n'", SCRIPT)
if not header:
    failures.append("cannot find the plan header line in mkvshrink")
else:
    cols = ["action"] + [c for c in header.group(1).split("\\t") if c]
    cols = [c.replace("%%", "%") for c in cols]

    row = re.search(r"printf '((?:%s\\t)+%s)\\n'", SCRIPT)
    if not row:
        failures.append("cannot find plan_row's printf in mkvshrink")
    elif row.group(1).count("%s") != len(cols):
        failures.append(
            "mkvshrink's plan header has %d columns and plan_row prints %d"
            % (len(cols), row.group(1).count("%s")))

    tsv = re.search(r"var tsv: String \{\s*\[(.*?)\]\.joined", MODEL, re.S)
    if not tsv:
        failures.append("cannot find PlanRow.tsv in ShrinkModel.swift")
    else:
        # Count top level commas in the array literal, ignoring those inside
        # the format calls.
        depth, fields = 0, 1
        for ch in tsv.group(1):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "," and depth == 0:
                fields += 1
        if fields != len(cols):
            failures.append(
                "the plan has %d columns (%s) and PlanRow.tsv writes %d.\n"
                "     The script reads them by position, so this does not fail "
                "loudly: it puts one column's number under another's name."
                % (len(cols), ",".join(cols), fields))

    if "f.count >= %d" % len(cols) not in MODEL:
        failures.append(
            "PlanFile.parse does not have a branch for %d column rows, which is "
            "what mkvshrink now writes" % len(cols))

    # And the script must still read the shape it used to write, or every plan
    # saved before the columns were added silently reads one column short.
    if "${#f[@]} -ge %d" % len(cols) not in SCRIPT:
        failures.append(
            "apply_plan does not branch on the %d column shape it now writes"
            % len(cols))

# --- the @@ events are an interface too ------------------------------------
# Film paths contain spaces. Any event field that can contain one has to be
# last, and the reader has to stop splitting before it. "@@done PATH SAVED"
# looked fine in the docs and broke every completed row in the table: the path
# split at the first space, matched no row, and the file kept showing whatever
# stage it had been in three steps earlier.
done_events = re.findall(r'mach "@@done ([^"]*)"', SCRIPT)
if not done_events:
    failures.append("mkvshrink emits no @@done event")
for ev in done_events:
    fields = ev.split()
    if not fields[-1].startswith("$"):
        failures.append(
            "@@done ends with %r, which is not the path.\n"
            "     A path contains spaces, so it has to be the last field."
            % fields[-1])
    for f in fields[:-1]:
        if f.startswith("$") and "path" in f.lower() or f in ("$src", "$keepat"):
            failures.append(
                "@@done has %s before the last field, and a path there splits "
                "on its own spaces" % f)

m = re.search(r'case "done":(.*?)case "', RUNNER, re.S)
if not m:
    failures.append("cannot find the done event handler in ShrinkRunner.swift")
elif "maxSplits" not in m.group(1):
    failures.append(
        "the done handler splits the whole event on spaces.\n"
        "     The path is the last field and contains spaces, so it needs "
        "maxSplits.")

# Every stage the script emits should have a label in the table, or a row
# shows a bare event name from a shell script to somebody watching a film
# encode.
stages = set(re.findall(r'mach "@@stage (\w+)', SCRIPT))
for st in sorted(stages):
    if '"%s"' % st not in VIEW:
        failures.append(
            "mkvshrink emits stage %r and the table has no label for it" % st)

# --- defaults must agree ---------------------------------------------------
def script_default(var):
    m = re.search(r'^%s=([^\s#]+)' % var, SCRIPT, re.M)
    return m.group(1).strip('"') if m else None


def swift_default(prop):
    m = re.search(r"var %s: \w+ = ([^\n]+)" % prop, MODEL)
    return m.group(1).strip().rstrip(",") if m else None


PAIRS = [
    ("VTQUALITY", "vtQuality"),
    ("CRF", "crf"),
    ("MINSAVING", "minSavingPct"),
    ("MINPSNR", "minPSNR"),
    ("PROBECOUNT", "probeCount"),
    ("PROBELEN", "probeLen"),
]
for var, prop in PAIRS:
    a, b = script_default(var), swift_default(prop)
    if a is None or b is None:
        failures.append("cannot compare default %s against %s" % (var, prop))
    elif a != b:
        failures.append(
            "default disagreement: mkvshrink %s=%s, the app uses %s = %s.\n"
            "     One of them is lying about what happens if you change nothing."
            % (var, a, prop, b))

# Replacement is the deliberate exception, and the app has to say so.
if "defaults to keeping originals" not in \
        (ROOT / "app/shrink/Sources/ShrinkSettingsView.swift").read_text():
    failures.append(
        "the app defaults to keeping originals where the script defaults to the "
        "_replaced folder, and no longer says so in Settings")

print("flags mkvshrink accepts:  %d" % len(accepted))
print("flags the app passes:     %d" % len(used))
print("defaults compared:        %d" % len(PAIRS))
if unexposed:
    print("\nnot exposed by the GUI (informational, not a failure):")
    print("  " + ", ".join(unexposed))

if failures:
    print()
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("\nok")
