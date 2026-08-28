#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""The length check must measure the picture, not the container.

A Matroska container is as long as its longest stream. Plenty of releases carry
an audio or subtitle track that runs past the end of the picture, and dropping
one of those makes the output legitimately shorter than the source. Comparing
containers calls that drift and rejects the file.

It happened on a real remux: Evangelion Death (True)² failed verification at
-1.87s on a strip-only pass, where the video was never touched at all. The
finished file was thrown away and the run counted a failure.

This builds the same shape of file, sixty seconds of picture with a Spanish
track running to sixty-two, strips the Spanish track, and checks the length
test passes. Then it checks the container measurement really would have failed,
so the test cannot quietly stop testing anything.

Needs ffmpeg, ffprobe and mkvmerge. Skips if they are missing.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHRINK = ROOT / "mkvshrink"

for tool in ("ffmpeg", "ffprobe", "mkvmerge"):
    if not shutil.which(tool):
        print("skipped: %s not installed" % tool)
        sys.exit(0)


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


failures = []
tmp = tempfile.mkdtemp(prefix="mkvshrink-len-")
src = os.path.join(tmp, "film.mkv")

# 60s of picture, 60s of English, 62s of Spanish. The container is 62s.
r = run(["ffmpeg", "-v", "error",
         "-f", "lavfi", "-i", "testsrc=size=320x240:rate=24:duration=60",
         "-f", "lavfi", "-i", "sine=frequency=400:duration=60",
         "-f", "lavfi", "-i", "sine=frequency=900:duration=62",
         "-map", "0:v", "-map", "1:a", "-map", "2:a",
         "-c:v", "libx264", "-g", "48", "-c:a", "aac",
         "-metadata:s:a:0", "language=eng",
         "-metadata:s:a:1", "language=spa",
         "-y", src])
if r.returncode != 0 or not os.path.exists(src):
    print("skipped: could not build the fixture\n" + r.stderr[-400:])
    sys.exit(0)


def probe(path, args):
    out = run(["ffprobe", "-v", "error"] + args
              + ["-of", "default=nw=1:nk=1", path]).stdout.strip().splitlines()
    return out[0] if out else ""


container = float(probe(src, ["-show_entries", "format=duration"]) or 0)
if container < 61.5:
    print("skipped: the fixture's container is %.2fs, so the long track did "
          "not survive muxing and there is nothing to test" % container)
    sys.exit(0)

# Strip only, keeping English. --force skips the size and saving gates; the
# point here is the verification step, not the decision.
env = dict(os.environ, MKVSHRINK_LOG_DIR="none")
r = run([str(SHRINK), "--force", "--min-size", "0", "--min-psnr", "0",
         "--min-saving", "0", "--no-risk", "--keep-originals",
         "--audio-langs", "eng", "--x265", src], env=env)
log = r.stdout + r.stderr

m = re.search(r"Length check \(([^)]+)\): source ([\d.]+)s,? (?:but )?output "
              r"([\d.]+)s \(([+-][\d.]+)s\)", log)
if not m:
    failures.append("no length check line in the output:\n"
                    + "\n".join(log.splitlines()[-15:]))
else:
    basis, s, o, drift = m.group(1), float(m.group(2)), float(m.group(3)), m.group(4)
    if basis != "video track":
        failures.append(
            "the length check measured the %s. A container is as long as its "
            "longest stream, so dropping a track that runs past the picture "
            "reads as drift." % basis)
    if abs(float(drift)) > 1.0:
        failures.append(
            "the remux was rejected for %ss of drift, on a file whose video "
            "was copied untouched. Source read as %.2fs, output as %.2fs."
            % (drift, s, o))
    # The whole point: the video is 60s and the container is 62s. If the check
    # reports 62 it is reading the wrong thing even when it happens to pass.
    if s > 61.0:
        failures.append(
            "the source measured %.2fs, which is the container's length, not "
            "the picture's 60s" % s)

if "failed verification" in log:
    failures.append("the file was rejected:\n"
                    + "\n".join(l for l in log.splitlines()
                                if "verification" in l or "Length check" in l))

shutil.rmtree(tmp, ignore_errors=True)

print("container %.2fs, picture 60.00s, one dropped track running 2s long"
      % container)

if failures:
    print()
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)
print("\nok")
