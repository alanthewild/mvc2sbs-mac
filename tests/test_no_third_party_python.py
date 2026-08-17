#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""No tool may import a module that is not in the standard library.

A stock macOS python3 has no numpy. `mkvdiff --eyes` shipped depending on it and
failed on the first real machine it met, after passing every test here, because
this container happens to have it installed. The tools have to run on a Mac with
nothing but Homebrew ffmpeg and mkvtoolnix.

Tests may use whatever they like; they run in CI, not on a user's machine.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ["mvc2sbs", "mkvdiff", "pgs3d.py", "subs3d", "mkvshrink",
         "install-mac3d.sh"]

# The standard library modules these tools legitimately use.
ALLOWED = {
    "argparse", "array", "base64", "binascii", "collections", "csv", "ctypes",
    "datetime", "glob", "gzip", "hashlib", "io", "itertools", "json", "math",
    "os", "pathlib", "plistlib", "random", "re", "shutil", "statistics",
    "shlex", "string", "struct", "subprocess", "sys", "tempfile",
    "textwrap", "time",
    "typing", "unicodedata", "xml", "zlib",
}

# Modules that ship in this repository alongside the tools. subs3d imports
# pgs3d for the RLE writer and the side-by-side duplication rather than owning
# a second copy of either. Both are installed together, so this is not a
# dependency on anything the user has to have.
SIBLINGS = {Path(t).stem for t in TOOLS} | {"pgs3d"}
ALLOWED |= SIBLINGS

failures = []
for name in TOOLS:
    path = ROOT / name
    if not path.exists():
        continue
    text = path.read_text()
    # Real import syntax only. These files are shell scripts with embedded
    # Python and a lot of prose, and "from around 52% to around 90%" in a help
    # string matched the loose version of this pattern.
    pattern = (r"^[ \t]*import[ \t]+([A-Za-z_][\w.]*)[ \t]*(?:,[^\n]*)?(?:#[^\n]*)?$"
               r"|^[ \t]*from[ \t]+([A-Za-z_][\w.]*)[ \t]+import[ \t]")
    for m in re.finditer(pattern, text, re.M):
        mod = (m.group(1) or m.group(2)).split(".")[0]
        if mod not in ALLOWED:
            line = text[:m.start()].count("\n") + 1
            failures.append("%s:%d imports %s, which is not in the standard library"
                            % (name, line, mod))
    for m in re.finditer(r"^[ \t]*import[ \t]+([A-Za-z_][\w., \t]*)$", text, re.M):
        for mod in [p.strip().split(".")[0] for p in m.group(1).split(",")]:
            if mod and mod not in ALLOWED:
                line = text[:m.start()].count("\n") + 1
                failures.append("%s:%d imports %s, which is not in the standard library"
                                % (name, line, mod))

print("checked %d tools" % len(TOOLS))
if failures:
    print()
    for f in sorted(set(failures)):
        print("FAIL " + f)
    print()
    print("These run on a user's Mac, where python3 is whatever Apple ships.")
    sys.exit(1)
print("ok")
