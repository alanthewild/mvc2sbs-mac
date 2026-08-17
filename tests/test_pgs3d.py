#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""
End to end test for the PGS subtitle transform.

Builds a synthetic PGS subtitle stream from scratch, runs pgs3d.py over it, then
decodes the result with FFmpeg's own PGS decoder and checks that the subtitle
really does appear twice, exactly half a frame apart.

Needs ffmpeg and ffprobe on PATH. Run it from anywhere:

    python3 tests/test_pgs3d.py
"""

import importlib.util
import os
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

spec = importlib.util.spec_from_file_location("pgs3d", os.path.join(ROOT, "pgs3d.py"))
pgs3d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pgs3d)

HEADER = struct.Struct(">2sIIBH")
FAILURES = []


def check(condition, message):
    print(("  ok   " if condition else "  FAIL ") + message)
    if not condition:
        FAILURES.append(message)


# --------------------------------------------------------------------------
# Build a minimal but valid PGS stream: one white rectangle, then a clear.
# --------------------------------------------------------------------------

def segment(pts, kind, payload):
    return HEADER.pack(b"PG", pts, 0, kind, len(payload)) + payload


def rle_rect(w, h, colour=1):
    out = bytearray()
    for _ in range(h):
        remaining = w
        while remaining > 0:
            run = min(remaining, 16383)
            if run < 64:
                out += bytes([0x00, 0x80 | run, colour])
            else:
                out += bytes([0x00, 0xC0 | (run >> 8), run & 0xFF, colour])
            remaining -= run
        out += b"\x00\x00"
    return bytes(out)


def build_pcs(w, h, num, state, objects):
    p = struct.pack(">HHBHBBBB", w, h, 0x10, num, state, 0, 0, len(objects))
    for obj_id, win_id, x, y in objects:
        p += struct.pack(">HBBHH", obj_id, win_id, 0, x, y)
    return p


def build_wds(windows):
    p = bytes([len(windows)])
    for win_id, x, y, w, h in windows:
        p += struct.pack(">BHHHH", win_id, x, y, w, h)
    return p


def build_pds():
    # Index 0 transparent, index 1 opaque white, plus an anti-aliasing ramp so
    # the brightness control has something to act on.
    p = bytes([0, 0])
    p += bytes([0, 16, 128, 128, 0])
    p += bytes([1, 235, 128, 128, 255])
    p += bytes([2, 110, 128, 128, 255])
    return p


def build_ods(obj_id, w, h, data):
    return (struct.pack(">HBB", obj_id, 0, 0xC0)
            + (len(data) + 4).to_bytes(3, "big")
            + struct.pack(">HH", w, h) + data)


def synthetic_sup(path, rect=(400, 60), pos=(760, 900), frame=(1920, 1080)):
    w, h = rect
    x, y = pos
    fw, fh = frame
    body = bytearray()
    pts = 90000
    body += segment(pts, 0x16, build_pcs(fw, fh, 0, 0x80, [(0, 0, x, y)]))
    body += segment(pts, 0x17, build_wds([(0, x, y, w, h)]))
    body += segment(pts, 0x14, build_pds())
    body += segment(pts, 0x15, build_ods(0, w, h, rle_rect(w, h)))
    body += segment(pts, 0x80, b"")
    pts2 = pts + 90000 * 3
    body += segment(pts2, 0x16, build_pcs(fw, fh, 1, 0x00, []))
    body += segment(pts2, 0x17, build_wds([(0, x, y, w, h)]))
    body += segment(pts2, 0x80, b"")
    with open(path, "wb") as fh_:
        fh_.write(bytes(body))
    return x, y, w, h


# --------------------------------------------------------------------------

def rendered_blocks(sup_path, width, height, workdir):
    """Decode with FFmpeg and return the horizontal extents of what it drew."""
    pattern = os.path.join(workdir, "f%03d.png")
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-f", "sup", "-i", sup_path,
         "-filter_complex", "[0:s]null[v]", "-map", "[v]", "-r", "2", pattern],
        check=False, capture_output=True)

    for name in sorted(os.listdir(workdir)):
        if not name.endswith(".png"):
            continue
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", os.path.join(workdir, name),
             "-pix_fmt", "gray", "-f", "rawvideo", "-"],
            capture_output=True).stdout
        if len(raw) < width * height:
            continue
        rows = [raw[r * width:(r + 1) * width] for r in range(height)]
        cols = [c for c in range(width) if any(row[c] > 8 for row in rows)]
        if not cols:
            continue
        blocks, start = [], cols[0]
        for i in range(1, len(cols)):
            if cols[i] != cols[i - 1] + 1:
                blocks.append((start, cols[i - 1]))
                start = cols[i]
        blocks.append((start, cols[-1]))
        return blocks
    return []


def decode_rle(rle, width, height):
    """A second, independent RLE decoder, so the test does not simply agree
    with the code it is testing."""
    rows, row, x = [], bytearray(), 0
    pos, n = 0, len(rle)
    while pos < n and len(rows) < height:
        b = rle[pos]
        if b:
            row.append(b); pos += 1; x += 1; continue
        if pos + 1 >= n:
            break
        f = rle[pos + 1]
        if f == 0:
            row += bytes(max(0, width - x))
            rows.append(bytes(row[:width])); row = bytearray(); x = 0; pos += 2
            continue
        kind = f & 0xC0
        if kind == 0x00:
            run, col, pos = f & 0x3F, 0, pos + 2
        elif kind == 0x40:
            run, col, pos = ((f & 0x3F) << 8) | rle[pos + 2], 0, pos + 3
        elif kind == 0x80:
            run, col, pos = f & 0x3F, rle[pos + 2], pos + 3
        else:
            run, col, pos = ((f & 0x3F) << 8) | rle[pos + 3 - 1], rle[pos + 3], pos + 4
        row += bytes([col]) * run
        x += run
    return rows


def exoplayer_view(data):
    """(leftmost, rightmost, plane_width) of the single bitmap ExoPlayer draws."""
    segs = pgs3d.read_segments(data)
    plane = px = py = None
    for s in segs:
        if s.kind == pgs3d.PCS:
            f = pgs3d.parse_pcs(s.payload)
            if f["objects"]:
                plane = f["width"]
                px, py = f["objects"][0][3], f["objects"][0][4]
                break
    if px is None:
        return None
    chunks, ow, oh = bytearray(), None, None
    started = False
    for s in segs:
        if s.kind != pgs3d.ODS:
            continue
        p = s.payload
        if p[3] & 0x80:
            if started:
                break
            started = True
            ow, oh = struct.unpack_from(">HH", p, 7)
            chunks += p[11:]
        elif started:
            chunks += p[4:]
        if started and p[3] & 0x40:
            break
    if ow is None:
        return None
    rows = decode_rle(bytes(chunks), ow, oh)
    cols = [c for c in range(ow) if any(r[c] for r in rows)]
    if not cols:
        return None
    return px + cols[0], px + cols[-1], plane


def main():
    for tool in ("ffmpeg", "ffprobe"):
        if subprocess.run(["which", tool], capture_output=True).returncode != 0:
            print(f"{tool} not found on PATH")
            return 1

    with tempfile.TemporaryDirectory() as tmp:
        src_path = os.path.join(tmp, "in.sup")
        x, y, w, h = synthetic_sup(src_path)

        print("side by side")
        out = os.path.join(tmp, "sbs.sup")
        data, stats = pgs3d.convert(open(src_path, "rb").read(), 3840, 0)
        open(out, "wb").write(data)

        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-f", "sup",
             "-show_entries", "stream=width,height", "-of", "csv=p=0", out],
            capture_output=True, text=True).stdout.strip()
        check(probe.startswith("3840,1080"), f"canvas is 3840x1080 (got {probe})")

        render_dir = os.path.join(tmp, "sbs")
        os.makedirs(render_dir)
        blocks = rendered_blocks(out, 3840, 1080, render_dir)
        check(len(blocks) == 2, f"two copies rendered (got {len(blocks)})")
        if len(blocks) == 2:
            check(blocks[0][0] == x, f"left copy at x={x} (got {blocks[0][0]})")
            check(blocks[1][0] == x + 1920,
                  f"right copy at x={x + 1920} (got {blocks[1][0]})")
            check(blocks[0][1] - blocks[0][0] == w - 1, "left copy keeps its width")

        print("one composition object, as strict decoders require")
        counts = []
        for seg in pgs3d.read_segments(data):
            if seg.kind == pgs3d.PCS:
                fields = pgs3d.parse_pcs(seg.payload)
                if fields["objects"]:
                    counts.append(len(fields["objects"]))
        check(counts and all(c == 1 for c in counts),
              "every display set has exactly 1 composition object (got %s)" % counts)

        print("what ExoPlayer would draw")
        # ExoPlayer's PgsParser skips a fixed 11 bytes past the object count and
        # reads the x/y of composition object 0 only, then build() returns a
        # single Cue. Anything after the first object is dropped. That is the
        # decoder Jellyfin's Android TV client uses, so this is the test that
        # matters: the one bitmap it draws must contain both eyes.
        spans = exoplayer_view(data)
        check(spans is not None, "a single object and position could be read")
        if spans:
            lo, hi, plane = spans
            check(lo < 1920, "ink in the left eye (leftmost at %d)" % lo)
            check(hi >= 1920, "ink in the right eye (rightmost at %d)" % hi)
            check(plane == 3840, "plane width 3840 (got %d)" % plane)

        print("depth offset")
        data, _ = pgs3d.convert(open(src_path, "rb").read(), 3840, 20)
        render_dir = os.path.join(tmp, "depth")
        os.makedirs(render_dir)
        tmp_sup = os.path.join(tmp, "depth.sup")
        open(tmp_sup, "wb").write(data)
        blocks = rendered_blocks(tmp_sup, 3840, 1080, render_dir)
        check(len(blocks) == 2, "depth run still renders two copies (got %d)" % len(blocks))
        if len(blocks) == 2:
            disparity = blocks[0][0] - (blocks[1][0] - 1920)
            check(disparity == 20, "depth 20 gives 20px of disparity (got %d)" % disparity)

        print("top and bottom")
        data, _ = pgs3d.convert(open(src_path, "rb").read(), 1920, 0,
                                stack=True, out_height=2160)
        rows_seen = []
        for seg in pgs3d.read_segments(data):
            if seg.kind == pgs3d.ODS:
                p = seg.payload
                if p[3] & 0x80:
                    oh = struct.unpack_from(">H", p, 9)[0]
                    rows_seen.append(oh)
        pcs_y = None
        for seg in pgs3d.read_segments(data):
            if seg.kind == pgs3d.PCS:
                fields = pgs3d.parse_pcs(seg.payload)
                if fields["objects"]:
                    pcs_y = fields["objects"][0][4]
                    break
        check(pcs_y == y, "stacked object starts at the original y (got %s)" % pcs_y)
        check(rows_seen and rows_seen[0] == 1080 + h,
              "stacked object spans both halves (height %s, wanted %d)"
              % (rows_seen, 1080 + h))

        print("palette styling")
        data, _ = pgs3d.convert(open(src_path, "rb").read(), 3840, 0,
                                gamma=0.7, colour="yellow")
        entries = []
        for seg in pgs3d.read_segments(data):
            if seg.kind == pgs3d.PDS:
                body = seg.payload[2:]
                entries = [tuple(body[i:i + 5]) for i in range(0, len(body) - 4, 5)]
                break
        mid = next((e for e in entries if e[0] == 2), None)
        check(mid is not None and mid[1] > 110, f"gamma lifts the midtone (got {mid})")
        check(mid is not None and (mid[2], mid[3]) == pgs3d.ycbcr_for("yellow"),
              "midtone is recoloured yellow")
        black = next((e for e in entries if e[0] == 0), None)
        check(black is not None and black[1] == 16, "transparent black is untouched")

    # --- a cropped flag with no crop rectangle -----------------------------
    # Seen on a real disc: the object_cropped_flag bit is set but the segment
    # ends without the 8 byte crop rectangle. The old parser read past the end,
    # which took out the whole subtitle track and fell the entire film back to
    # flat 2D subtitles.
    print("malformed crop flag")
    pcs = struct.pack(">HHBHBBBB", 1920, 1080, 0x10, 0, 0x80, 0, 0, 1)
    pcs += struct.pack(">HBB", 0, 0, 0x40) + struct.pack(">HH", 100, 900)
    check(len(pcs) == 19, "test fixture really does end after the flag")

    wds = bytes([1]) + struct.pack(">BHHHH", 0, 0, 880, 1920, 100)
    pds = bytes([0, 0]) + bytes([1, 235, 128, 128, 255])
    ods = (struct.pack(">HBB", 0, 0, 0xC0) + struct.pack(">I", 4)[1:]
           + struct.pack(">HH", 40, 20) + b"\x00\x00")

    def seg(kind, payload, pts=0):
        return HEADER.pack(b"PG", pts, 0, kind, len(payload)) + payload

    data = (seg(0x16, pcs) + seg(0x17, wds) + seg(0x14, pds)
            + seg(0x15, ods) + seg(0x80, b""))
    try:
        out, st = pgs3d.convert(data, 3840, 0)
        check(st["display_sets"] == 1 and st["objects"] == 1,
              f"converts instead of crashing (got {st})")
        check(not st.get("passed_through"), "converted rather than passed through")
        parsed = pgs3d.parse_pcs(
            next(s for s in pgs3d.read_segments(out) if s.kind == 0x16).payload)
        # One composition object now, holding both eyes in a single bitmap.
        check(len(parsed["objects"]) == 1, "one composition object")
        merged_w = None
        for sg in pgs3d.read_segments(out):
            if sg.kind == 0x15 and sg.payload[3] & 0x80:
                merged_w = struct.unpack_from(">H", sg.payload, 7)[0]
                break
        check(merged_w == 1920 + 40,
              "merged object spans both eyes (width %s, wanted 1960)" % merged_w)
        check(all(o[5] is None and not (o[2] & 0x40) for o in parsed["objects"]),
              "the cropped bit is cleared, since no crop rectangle exists")
    except Exception as exc:
        check(False, f"crashed on a cropped flag with no crop data: {exc}")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} check(s) failed")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

