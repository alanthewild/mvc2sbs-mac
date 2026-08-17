#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""subs3d writes each subtitle twice, once per eye, in the right place.

The whole point of the tool is placement, and placement is the one thing you
cannot see by reading the file: a wrong \\pos looks exactly like a right one.
So this renders the result with libass, the same library VLC, mpv and Kodi use,
and measures where the ink actually landed.

Falls back to checking the generated text when there is no ffmpeg.
"""
import os
import struct
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUBS3D = ROOT / "subs3d"

failures = []


def check(ok, msg):
    print(("  ok   " if ok else "  FAIL ") + msg)
    if not ok:
        failures.append(msg)


def have(tool):
    return subprocess.run(["which", tool], capture_output=True).returncode == 0


SRT = """1
00:00:44,000 --> 00:00:47,500
I see you.

2
00:00:50,000 --> 00:00:54,000
<i>Everything is backwards now.</i>
Like out there is the true world.
"""

SRC_ASS = """[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding
Style: Main,DejaVu Sans,48,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,30,30,40,1

[Events]
Format: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text
Dialogue: 0,0:00:45.00,0:00:48.00,Main,,0,0,0,,{\\pos(300,200)}Already positioned.
Dialogue: 0,0:00:50.00,0:00:52.00,Main,,0,0,0,,{\\an8}Top aligned line.
"""


def read_sup(data):
    """(kind, payload) per segment."""
    H = struct.Struct(">2sIIBH")
    out, pos = [], 0
    while pos + H.size <= len(data):
        magic, _pts, _dts, kind, size = H.unpack_from(data, pos)
        if magic != b"PG":
            break
        pos += H.size
        out.append((kind, data[pos:pos + size]))
        pos += size
    return out


def rle_colours(body):
    """Palette indices a PGS object actually draws with.

    Written independently of the encoder in subs3d, so a matching pair of bugs
    cannot make this pass.
    """
    d = body[4:]          # skip width and height
    used, i = set(), 0
    while i < len(d):
        b = d[i]
        if b:
            used.add(b); i += 1; continue
        if i + 1 >= len(d):
            break
        f = d[i + 1]
        if f == 0:
            i += 2; continue
        k = f & 0xC0
        if k == 0x00:
            i += 2
        elif k == 0x40:
            i += 3
        elif k == 0x80:
            used.add(d[i + 2]); i += 3
        else:
            used.add(d[i + 3]); i += 4
    return used


def dialogue_lines(text):
    return [l for l in text.splitlines() if l.startswith("Dialogue:")]


def ink_blocks(png, width, height):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", png, "-pix_fmt", "gray", "-f", "rawvideo", "-"],
        capture_output=True).stdout
    if len(raw) < width * height:
        return []
    cols = [x for x in range(width)
            if any(raw[y * width + x] > 8 for y in range(height))]
    if not cols:
        return []
    blocks, start = [], cols[0]
    for i in range(1, len(cols)):
        if cols[i] - cols[i - 1] > 40:
            blocks.append((start, cols[i - 1]))
            start = cols[i]
    blocks.append((start, cols[-1]))
    return blocks


def main():
    with tempfile.TemporaryDirectory() as tmp:
        srt = os.path.join(tmp, "d.srt")
        open(srt, "w").write(SRT)
        out = os.path.join(tmp, "d.3d.ass")
        stem = os.path.join(tmp, "d.3d")

        r = subprocess.run([str(SUBS3D), srt, "-o", out, "--depth", "20",
                            "--format", "ass"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stderr)
            check(False, "subs3d ran")
            return 1

        text = open(out).read()
        lines = dialogue_lines(text)
        check(len(lines) == 4, "2 cues became 4 lines (got %d)" % len(lines))
        check("PlayResX: 3840" in text, "canvas is the full frame width")
        check(text.count("\\i1") == 2, "SRT italics became ASS italics, in both copies")

        xs = [int(m) for m in re.findall(r"\\pos\((\d+),", text)]
        check(len(set(xs)) == 2, "two distinct x positions (got %s)" % sorted(set(xs)))
        if len(set(xs)) == 2:
            lo, hi = sorted(set(xs))
            check(hi - lo == 1920 - 20,
                  "depth 20 gives 20px of crossed disparity (got %d)" % (hi - lo))

        print("existing ASS")
        src = os.path.join(tmp, "s.ass")
        open(src, "w").write(SRC_ASS)
        out2 = os.path.join(tmp, "s.3d.ass")
        r = subprocess.run([str(SUBS3D), src, "-o", out2, "--depth", "40",
                            "--format", "ass"],
                           capture_output=True, text=True)
        check(r.returncode == 0, "subs3d accepts an ASS as input")
        text2 = open(out2).read()
        check(len(dialogue_lines(text2)) == 4, "2 cues became 4 lines")
        check("Style: Main," in text2, "the original style survives")
        # A \pos or \an that came in would fight the one this tool writes.
        bodies = [l.split(",,", 1)[1] for l in dialogue_lines(text2)]
        check(all(b.count("\\pos") == 1 for b in bodies),
              "exactly one \\pos per line, the one subs3d wrote")
        check(all("\\an8" not in b for b in bodies),
              "the original alignment override is gone")

        if not (have("ffmpeg") and have("ffprobe")):
            print("no ffmpeg, skipping the render")
            return 1 if failures else 0

        print("rendered with libass")
        # Arial is not on a CI box. The point of the test is placement.
        placed = open(out).read().replace("Default,Arial,", "Default,DejaVu Sans,")
        render_src = os.path.join(tmp, "r.ass")
        open(render_src, "w").write(placed)
        frames = os.path.join(tmp, "fr%03d.png")
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-f", "lavfi", "-i", "color=c=black:s=3840x1080:r=1:d=60",
             "-vf", "ass=" + render_src, "-frames:v", "60", "-f", "image2", frames],
            capture_output=True)
        frame = os.path.join(tmp, "fr046.png")
        if not os.path.exists(frame):
            print("  ffmpeg drew no frames, skipping")
            return 1 if failures else 0

        blocks = ink_blocks(frame, 3840, 1080)
        check(len(blocks) == 2, "libass drew two copies (got %d)" % len(blocks))
        if len(blocks) == 2:
            centres = [(a + b) // 2 for a, b in blocks]
            check(abs(centres[0] - 970) <= 4,
                  "left copy centred in the left eye (got %d)" % centres[0])
            check(abs(centres[1] - 2870) <= 4,
                  "right copy centred in the right eye (got %d)" % centres[1])
            check(abs((centres[1] - centres[0]) - 1900) <= 4,
                  "20px of disparity on screen (got %d)" % (centres[1] - centres[0]))
            check(blocks[0][0] >= 0 and blocks[0][1] < 1920,
                  "left copy stays inside the left eye")
            check(blocks[1][0] >= 1920 and blocks[1][1] < 3840,
                  "right copy stays inside the right eye")


        print("PGS bitmaps")
        # The format that actually direct plays on a Shield. Everything here is
        # measured from the bytes the tool wrote, not from what it printed.
        pgs_stem = os.path.join(tmp, "p")
        r = subprocess.run([str(SUBS3D), srt, "-o", pgs_stem, "--depth", "20",
                            "--format", "pgs", "--font", "DejaVu Sans"],
                           capture_output=True, text=True)
        sup = pgs_stem + ".sup"
        check(r.returncode == 0 and os.path.exists(sup),
              "rendered a .sup" + ("" if r.returncode == 0 else ":\n" + r.stderr))
        if os.path.exists(sup):
            segs = read_sup(open(sup, "rb").read())

            counts, first_obj = [], []
            objects = {}
            pend = []
            for kind, payload in segs:
                pend.append((kind, payload))
                if kind != 0x80:
                    continue
                pcs = next((p for k, p in pend if k == 0x16), None)
                if pcs and len(pcs) >= 11:
                    n = pcs[10]
                    if n:
                        counts.append(n)
                        for k, p in pend:
                            if k == 0x15 and p[3] & 0x80:
                                ow, oh = struct.unpack_from(">HH", p, 7)
                                first_obj.append((struct.unpack_from(">H", pcs, 15)[0], ow))
                pend = []

            check(counts and all(c == 1 for c in counts),
                  "one composition object per display set (got %s)" % sorted(set(counts)))
            if first_obj:
                x, w = first_obj[0]
                check(x < 1920 and x + w > 1920,
                      "the single bitmap spans both eyes (x=%d w=%d)" % (x, w))

            used = set()
            for kind, payload in segs:
                if kind == 0x15 and payload[3] & 0x80:
                    used |= rle_colours(payload[11:])
            fill = [u for u in used if 1 <= u <= 127]
            line = [u for u in used if u >= 128]
            check(len(fill) > 10,
                  "the fill keeps its antialiasing (%d shades)" % len(fill))
            check(len(line) > 10,
                  "the outline keeps its antialiasing (%d shades)" % len(line))

            if have("ffprobe"):
                times = subprocess.run(
                    ["ffprobe", "-v", "error", "-show_entries", "packet=pts_time",
                     "-of", "csv=p=0", sup], capture_output=True, text=True).stdout
                stamps = sorted({round(float(t), 2) for t in times.split() if t.strip()})
                check(stamps[:4] == [44.0, 47.5, 50.0, 54.0],
                      "timings match the source cues (got %s)" % stamps[:4])

    if failures:
        print("\n%d check(s) failed" % len(failures))
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
