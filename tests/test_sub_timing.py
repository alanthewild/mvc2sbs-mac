#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""Subtitles must keep the timestamps they came in with.

FFmpeg rebases every input file so that its own first timestamp becomes zero.
The rebuilt subtitle .sup files are separate inputs, so a film whose first
subtitle is 44 seconds in had its entire subtitle track shifted 44 seconds
early. Nothing about the resulting file looks wrong under any check: the
container is valid, the track is present, the count is right. It was found by
watching the film.

Two halves:

1. If FFmpeg is available, build a synthetic .sup whose first display set is at
   44s, mux it, and check where it lands. This proves the behaviour still
   exists and that -itsoffset still counters it. Skipped without FFmpeg, since
   CI may not have it.
2. Always: the script must pass -itsoffset for each subtitle input. A test that
   only runs with FFmpeg installed would silently stop guarding anything.
"""
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = (ROOT / "mvc2sbs").read_text()

failures = []

# --- half one: the script must ask for the offset ---------------------------
block = re.search(
    r"SUBIN=\(\); SUBMETA=\(\)(.*?)\nelif \[\[ \$NOSUBS", SCRIPT, re.S)
if not block:
    failures.append("cannot find the SUB3D input block in mvc2sbs")
else:
    # Comments here explain the fix and mention it by name, so a check that
    # counted them would pass on a version where the code had been removed.
    body = "\n".join(
        l for l in block.group(1).splitlines() if not l.lstrip().startswith("#"))
    if "-itsoffset" not in body:
        failures.append(
            "mvc2sbs no longer passes -itsoffset for the rebuilt subtitle inputs.\n"
            "     FFmpeg will rebase them to zero and the whole track will be early."
        )
    if "start_time" not in body:
        failures.append(
            "the offset is not read from the .sup's own start_time.\n"
            "     A fixed number would be wrong for every other film."
        )

# --- half two: prove it against FFmpeg, when there is one -------------------


def seg(kind, payload, pts):
    return b"PG" + struct.pack(">IIBH", int(pts * 90000), 0, kind, len(payload)) + payload


def display_set(pts, dur):
    out = b""
    pcs = struct.pack(">HHBHBBBB", 1920, 1080, 0x10, 0, 0x80, 0, 0, 1)
    pcs += struct.pack(">HBBHH", 0, 0, 0, 100, 900)
    out += seg(0x16, pcs, pts)
    out += seg(0x17, struct.pack(">BBHHHH", 1, 0, 100, 900, 16, 2), pts)
    out += seg(0x14, struct.pack(">BB", 0, 0) + struct.pack(">BBBBB", 1, 235, 128, 128, 255), pts)
    body = struct.pack(">HH", 16, 2) + b"\x00\x50\x01\x00\x00" * 2
    out += seg(0x15, struct.pack(">HB", 0, 0) + b"\xc0" + len(body).to_bytes(3, "big") + body, pts)
    out += seg(0x80, b"", pts)
    pcs2 = struct.pack(">HHBHBBBB", 1920, 1080, 0x10, 1, 0x00, 0, 0, 0)
    out += seg(0x16, pcs2, pts + dur)
    out += seg(0x17, struct.pack(">BBHHHH", 1, 0, 100, 900, 16, 2), pts + dur)
    out += seg(0x80, b"", pts + dur)
    return out


def have(tool):
    return subprocess.run(["which", tool], capture_output=True).returncode == 0


def first_sub_pts(path):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "s", "-show_entries",
         "packet=pts_time", "-of", "default=nw=1:nk=1", path],
        capture_output=True, text=True)
    for line in r.stdout.splitlines():
        line = line.strip()
        if line:
            return float(line)
    return None


if have("ffmpeg") and have("ffprobe"):
    with tempfile.TemporaryDirectory() as tmp:
        sup = os.path.join(tmp, "t.sup")
        open(sup, "wb").write(display_set(44.0, 3.0) + display_set(50.0, 3.0))

        def mux(out, extra):
            subprocess.run(
                ["ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                 "-i", "color=black:s=320x240:d=60:r=24"] + extra +
                ["-f", "sup", "-i", sup, "-map", "0:v", "-map", "1:s",
                 "-c:v", "libx264", "-preset", "ultrafast", "-c:s", "copy", out],
                capture_output=True)
            return first_sub_pts(out)

        plain = mux(os.path.join(tmp, "plain.mkv"), [])
        fixed = mux(os.path.join(tmp, "fixed.mkv"), ["-itsoffset", "44"])

        print("first subtitle without -itsoffset: %s" % plain)
        print("first subtitle with -itsoffset 44: %s" % fixed)

        if plain is None or fixed is None:
            print("ffmpeg produced no subtitle packets, skipping the live half")
        else:
            if abs(plain - 44.0) < 0.5:
                print("note: this FFmpeg does not rebase .sup inputs. The offset "
                      "is harmless here, and still needed on the versions that do.")
            elif abs(plain) > 0.5:
                failures.append(
                    "unmuxed subtitle landed at %.3fs, expected 0 or 44" % plain)
            if abs(fixed - 44.0) > 0.5:
                failures.append(
                    "-itsoffset 44 put the first subtitle at %.3fs, wanted 44.000. "
                    "The fix in mvc2sbs no longer works on this FFmpeg." % fixed)
else:
    print("no ffmpeg, checking the script only")

if failures:
    print()
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("\nok")
