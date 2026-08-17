#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""
pgs3d - turn a 2D PGS subtitle stream into a side-by-side 3D one.

A PGS display set places bitmap objects on screen using composition objects,
each of which is an object id plus an x/y position. The format allows several,
so the obvious way to build an SBS track is to place the same bitmap twice.

That does not work. ExoPlayer, which is what Jellyfin's Android TV client
decodes PGS with, reads the position of composition object 0 and ignores every
one after it, so the right eye stays empty on the exact device these files are
made for. FFmpeg draws both, which is why VLC looks correct and the fault
survives every check short of watching the film on a Shield.

So the two copies are spliced into ONE bitmap, emitted as one object with one
composition object and one window. The splice happens at run boundaries in the
RLE, not at pixel level: rows are cut apart, transparent runs are inserted
between the copies, and the original bytes are replayed verbatim. No pixel is
decoded or re-encoded, nothing is lost, and a three hour film converts in a
couple of seconds.

Usage:
    pgs3d.py in.sup out.sup [--width 3840] [--depth 0]

--depth shifts the two copies towards or away from the viewer, in pixels of
disparity. Positive moves the subtitles in front of the screen plane, which is
usually what you want so they do not collide with objects popping out.
"""

import argparse
import struct
import sys

MAGIC = b"PG"
PDS, ODS, PCS, WDS, END = 0x14, 0x15, 0x16, 0x17, 0x80
HEADER = struct.Struct(">2sIIBH")   # magic, pts, dts, type, size


class Segment:
    __slots__ = ("pts", "dts", "kind", "payload")

    def __init__(self, pts, dts, kind, payload):
        self.pts, self.dts, self.kind, self.payload = pts, dts, kind, payload

    def pack(self):
        return HEADER.pack(MAGIC, self.pts, self.dts, self.kind,
                           len(self.payload)) + self.payload


def read_segments(data):
    segments, pos, n = [], 0, len(data)
    while pos + HEADER.size <= n:
        magic, pts, dts, kind, size = HEADER.unpack_from(data, pos)
        if magic != MAGIC:
            raise ValueError(f"bad segment magic at byte {pos}: {magic!r}")
        pos += HEADER.size
        if pos + size > n:
            raise ValueError(f"truncated segment at byte {pos}")
        segments.append(Segment(pts, dts, kind, data[pos:pos + size]))
        pos += size
    if pos != n:
        sys.stderr.write(f"warning: {n - pos} trailing bytes ignored\n")
    return segments


# --- PCS ------------------------------------------------------------------

def parse_pcs(p):
    width, height, rate, num, state, pal_flag, pal_id, count = \
        struct.unpack_from(">HHBHBBBB", p, 0)
    pos = 11
    objects = []
    for _ in range(count):
        obj_id, win_id, cropped = struct.unpack_from(">HBB", p, pos)
        pos += 4
        x, y = struct.unpack_from(">HH", p, pos)
        pos += 4
        crop = None
        if cropped & 0x40:
            # A real disc has been seen with the cropped bit set and no crop
            # rectangle following it. Trust the buffer over the flag: reading
            # past the end would take out the whole subtitle track, and the
            # flag is rewritten from `crop` on the way out, so dropping it here
            # keeps the segment self-consistent.
            if pos + 8 <= len(p):
                crop = struct.unpack_from(">HHHH", p, pos)
                pos += 8
            else:
                cropped &= ~0x40
        objects.append([obj_id, win_id, cropped, x, y, crop])
    return dict(width=width, height=height, rate=rate, num=num, state=state,
                pal_flag=pal_flag, pal_id=pal_id, objects=objects)


def build_pcs(f):
    out = struct.pack(">HHBHBBBB", f["width"], f["height"], f["rate"], f["num"],
                      f["state"], f["pal_flag"], f["pal_id"], len(f["objects"]))
    for obj_id, win_id, cropped, x, y, crop in f["objects"]:
        out += struct.pack(">HBB", obj_id, win_id, cropped)
        out += struct.pack(">HH", x, y)
        if crop is not None:
            out += struct.pack(">HHHH", *crop)
    return out


# --- WDS ------------------------------------------------------------------

def parse_wds(p):
    count = p[0]
    pos, windows = 1, []
    for _ in range(count):
        win_id, x, y, w, h = struct.unpack_from(">BHHHH", p, pos)
        pos += 9
        windows.append([win_id, x, y, w, h])
    return windows


def build_wds(windows):
    out = bytes([len(windows)])
    for win_id, x, y, w, h in windows:
        out += struct.pack(">BHHHH", win_id, x, y, w, h)
    return out


# --- PDS ------------------------------------------------------------------
# Palettes live in their own segments, so colour, brightness and opacity can all
# be changed without touching a single pixel of the RLE bitmaps.

def ycbcr_for(name):
    """Chroma pair for a named colour, BT.709 limited range."""
    rgb = {
        "white":  (1.0, 1.0, 1.0),
        "yellow": (1.0, 1.0, 0.0),
        "cyan":   (0.0, 1.0, 1.0),
        "green":  (0.0, 1.0, 0.0),
        "amber":  (1.0, 0.75, 0.0),
    }.get(name)
    if rgb is None:
        return None
    r, g, b = rgb
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    cb = 128 + 224 * 0.5 * (b - y) / (1 - 0.0722)
    cr = 128 + 224 * 0.5 * (r - y) / (1 - 0.2126)
    return int(round(max(0, min(255, cr)))), int(round(max(0, min(255, cb))))


def adjust_palette(payload, gamma, chroma, opacity):
    """Rewrite a PDS. gamma < 1 brightens the anti-aliased edges, which is what
    goes grey when a player squeezes the subtitle plane horizontally."""
    if len(payload) < 2:
        return payload
    out = bytearray(payload[:2])
    body = payload[2:]
    for i in range(0, len(body) - 4, 5):
        idx, y, cr, cb, a = body[i:i + 5]
        if a > 0:
            if gamma != 1.0:
                # Work in the 16..235 studio range so black stays black.
                t = max(0.0, min(1.0, (y - 16) / 219.0))
                y = int(round(16 + 219 * (t ** gamma)))
            if chroma is not None and y > 80:
                # Only recolour the text itself; outlines are near black and
                # tinting them would just muddy the edge.
                cr, cb = chroma
            if opacity != 1.0:
                a = int(round(a * opacity))
        out += bytes([idx, max(0, min(255, y)), max(0, min(255, cr)),
                      max(0, min(255, cb)), max(0, min(255, a))])
    out += body[len(body) - (len(body) % 5):] if len(body) % 5 else b""
    return bytes(out)


# --- ODS ------------------------------------------------------------------

def ods_dimensions(p):
    """Object width and height, present only on the first fragment."""
    if len(p) < 11:
        return None
    obj_id = struct.unpack_from(">H", p, 0)[0]
    seq = p[3]
    if not (seq & 0x80):          # not the first fragment, no dimensions
        return None
    w, h = struct.unpack_from(">HH", p, 7)
    return obj_id, w, h


# --- RLE ------------------------------------------------------------------
# PGS run length coding, one line at a time:
#
#   CC                  one pixel of colour CC        (CC != 0)
#   00 00               end of line
#   00 00LLLLLL         L pixels of colour 0
#   00 01LLLLLL LLLLLLLL  L pixels of colour 0, 14 bit length
#   00 10LLLLLL CC      L pixels of colour CC
#   00 11LLLLLL LLLLLLLL CC   L pixels of colour CC, 14 bit length
#
# A line may stop early; the decoder pads the rest with colour 0. Nothing here
# decodes to pixels. Rows are split at run boundaries and spliced back together
# with transparent runs between them, so a three hour film stays quick.

MAX_SEG = 65515       # largest ODS payload a decoder is required to accept


def split_rle_rows(rle):
    """[(row_bytes, pixel_count)] per line, terminators removed.

    row_bytes replays exactly pixel_count pixels, which may be fewer than the
    object width if the encoder stopped the line early.
    """
    rows = []
    n = len(rle)
    pos = start = 0
    pixels = 0
    while pos < n:
        b = rle[pos]
        if b:
            pos += 1
            pixels += 1
            continue
        if pos + 1 >= n:
            pos = n
            break
        f = rle[pos + 1]
        if f == 0:
            rows.append((bytes(rle[start:pos]), pixels))
            pos += 2
            start = pos
            pixels = 0
            continue
        kind = f & 0xC0
        if kind == 0x00:
            run, pos = f & 0x3F, pos + 2
        elif kind == 0x40:
            run, pos = ((f & 0x3F) << 8) | rle[pos + 2], pos + 3
        elif kind == 0x80:
            run, pos = f & 0x3F, pos + 3
        else:
            run, pos = ((f & 0x3F) << 8) | rle[pos + 2], pos + 4
        pixels += run
    if pos > start or pixels:
        rows.append((bytes(rle[start:pos]), pixels))
    return rows


def blank_run(count, colour=0):
    """RLE for `count` pixels of one colour."""
    out = bytearray()
    while count > 0:
        n = min(count, 0x3FFF)
        if colour == 0:
            if n <= 0x3F:
                out += bytes((0, n))
            else:
                out += bytes((0, 0x40 | (n >> 8), n & 0xFF))
        else:
            if n <= 0x3F:
                out += bytes((0, 0x80 | n, colour))
            else:
                out += bytes((0, 0xC0 | (n >> 8), n & 0xFF, colour))
        count -= n
    return bytes(out)


def build_ods(obj_id, version, width, height, rle):
    """One object, split across as many segments as it needs."""
    body = struct.pack(">HH", width, height) + rle
    head = struct.pack(">HB", obj_id, version)
    first = MAX_SEG - (len(head) + 1 + 3)
    if len(body) <= first:
        return [head + bytes((0xC0,)) + struct.pack(">I", len(body))[1:] + body]
    out = [head + bytes((0x80,)) + struct.pack(">I", len(body))[1:] + body[:first]]
    rest = body[first:]
    step = MAX_SEG - (len(head) + 1)
    while rest:
        chunk, rest = rest[:step], rest[step:]
        out.append(head + bytes((0x40 if not rest else 0x00,)) + chunk)
    return out


def compose_rows(placements, width, height, fill):
    """Splice several placed objects into the rows of one wider object.

    placements is [(x, y, rows, obj_width)] in canvas coordinates. Rows are the
    byte slices from split_rle_rows, replayed verbatim, so no pixel is decoded
    or re-encoded and nothing is lost.
    """
    ordered = sorted(placements, key=lambda p: p[0])
    out = []
    for y in range(height):
        parts, cursor = [], 0
        for px, py, rows, ow in ordered:
            if not (py <= y < py + len(rows)):
                continue
            row, npix = rows[y - py]
            if px < cursor:
                raise ValueError("objects overlap at row %d" % y)
            if px > cursor:
                parts.append(blank_run(px - cursor, fill))
            parts.append(row)
            cursor = px + npix
            if npix < ow:
                parts.append(blank_run(ow - npix, fill))
                cursor = px + ow
        out.append(b"".join(parts) + b"\x00\x00")
    return b"".join(out)


# --- transform ------------------------------------------------------------

def convert(data, out_width, depth, stack=False, out_height=0,
            gamma=1.0, colour=None, opacity=1.0):
    segments = read_segments(data)

    src_width = None
    for s in segments:
        if s.kind == PCS:
            src_width = parse_pcs(s.payload)["width"]
            break
    if src_width is None:
        raise ValueError("no PCS found, this does not look like a PGS stream")
    if not stack and (out_width % src_width != 0 or out_width // src_width != 2):
        sys.stderr.write(
            f"warning: source is {src_width} wide and target is {out_width}; "
            "expected exactly double\n")

    half = out_width // 2
    half_h = out_height // 2
    # Positive depth moves the subtitle towards the viewer: the left eye copy
    # goes right, the right eye copy goes left (crossed disparity).
    shift_l, shift_r = depth // 2, -(depth - depth // 2)

    chroma = ycbcr_for(colour) if colour and colour != "source" else None
    if colour and colour != "source" and chroma is None:
        raise ValueError(f"unknown colour: {colour}")
    restyle = gamma != 1.0 or chroma is not None or opacity != 1.0
    if restyle:
        for seg in segments:
            if seg.kind == PDS:
                seg.payload = adjust_palette(seg.payload, gamma, chroma, opacity)

    stats = {"display_sets": 0, "objects": 0, "clamped": 0}
    out = []
    pending = []       # segments of the current display set

    # Objects survive across display sets within an epoch, so a set that only
    # moves a subtitle carries no ODS of its own. Track them as we go rather
    # than in one pass up front: the same object id is reused all film long,
    # and a pre-pass would hand every display set the last definition.
    objects = {}       # id -> (width, height, rows)
    alpha = {}         # palette index -> alpha, for picking a transparent fill

    def absorb_ods(segs):
        buf, meta = bytearray(), None
        for s in segs:
            p = s.payload
            if len(p) < 4:
                continue
            obj_id, version, seq = struct.unpack_from(">HBB", p, 0)
            if seq & 0x80:
                w, h = struct.unpack_from(">HH", p, 7)
                meta = (obj_id, w, h)
                buf = bytearray(p[11:])
            else:
                buf += p[4:]
            if seq & 0x40 and meta is not None:
                objects[meta[0]] = (meta[1], meta[2], split_rle_rows(buf))
                meta, buf = None, bytearray()

    def absorb_pds(segs):
        for s in segs:
            body = s.payload[2:]
            for i in range(0, len(body) - 4, 5):
                alpha[body[i]] = body[i + 4]

    def transparent_index():
        """A palette index that draws nothing.

        Index 0 is transparent in every stream seen, but nothing in the format
        requires it, and filling the gap between the two eyes with an opaque
        colour would put a bar across the screen. An index the palette never
        defines decodes as transparent in both FFmpeg and ExoPlayer.
        """
        if alpha.get(0, 0) == 0:
            return 0
        for i in range(1, 256):
            if alpha.get(i, 0) == 0:
                return i
        return 0

    def flush():
        if not pending:
            return
        pcs_idx = next((i for i, s in enumerate(pending) if s.kind == PCS), None)
        if pcs_idx is None:
            out.extend(pending)
            pending.clear()
            return

        absorb_pds([s for s in pending if s.kind == PDS])
        absorb_ods([s for s in pending if s.kind == ODS])

        f = parse_pcs(pending[pcs_idx].payload)
        f["width"] = out_width
        if stack:
            f["height"] = out_height

        placements = []
        for obj_id, _win, cropped, x, y, crop in f["objects"]:
            if obj_id not in objects:
                raise ValueError("object %d was never defined" % obj_id)
            w, h, rows = objects[obj_id]
            # Cropping is ignored, as it is by FFmpeg, so the whole object is
            # drawn. A disc has already been seen setting the flag with no
            # rectangle behind it.
            if stack:
                for ny, sh in ((y, shift_l), (y + half_h, shift_r)):
                    nx = x + sh
                    if nx < 0 or nx + w > out_width:
                        stats["clamped"] += 1
                    placements.append((max(0, min(nx, max(0, out_width - w))), ny, rows, w, h))
            else:
                for nx in (x + shift_l, x + half + shift_r):
                    if nx < 0 or nx + w > out_width:
                        stats["clamped"] += 1
                    placements.append((max(0, min(nx, max(0, out_width - w))), y, rows, w, h))
            stats["objects"] += 1

        if placements:
            # One object, one composition object, one window. ExoPlayer, which
            # is what Jellyfin's Android TV client decodes PGS with, reads the
            # position of composition object 0 and ignores every one after it.
            # Two composition objects therefore render in the left eye only, on
            # the exact device these files are made for, while FFmpeg based
            # players show both and everything looks fine.
            x0 = min(p[0] for p in placements)
            y0 = min(p[1] for p in placements)
            x1 = max(p[0] + p[3] for p in placements)
            y1 = max(p[1] + p[4] for p in placements)
            fill = transparent_index()
            rle = compose_rows(
                [(p[0] - x0, p[1] - y0, p[2], p[3]) for p in placements],
                x1 - x0, y1 - y0, fill)
            merged = build_ods(0, 0, x1 - x0, y1 - y0, rle)

            f["objects"] = [[0, 0, 0, x0, y0, None]]
            pending[pcs_idx].payload = build_pcs(f)
            window = [[0, x0, y0, max(1, x1 - x0), max(1, y1 - y0)]]

            rebuilt = [pending[pcs_idx]]
            wds = next((s for s in pending if s.kind == WDS), None)
            if wds is not None:
                wds.payload = build_wds(window)
                rebuilt.append(wds)
            rebuilt += [s for s in pending if s.kind == PDS]
            pts = pending[pcs_idx].pts
            dts = pending[pcs_idx].dts
            rebuilt += [Segment(pts, dts, ODS, payload) for payload in merged]
            rebuilt += [s for s in pending if s.kind == END]
            pending[:] = rebuilt
        else:
            pending[pcs_idx].payload = build_pcs(f)
            wds_idx = next((i for i, s in enumerate(pending) if s.kind == WDS), None)
            if wds_idx is not None:
                # A display set that clears the screen still carries a WDS.
                old = parse_wds(pending[wds_idx].payload)
                pending[wds_idx].payload = build_wds(
                    [[0, 0, old[0][2] if old else 0, out_width,
                      old[0][4] if old else 1]])

        stats["display_sets"] += 1
        out.extend(pending)
        pending.clear()

    for s in segments:
        pending.append(s)
        if s.kind == END:
            try:
                flush()
            except Exception as exc:
                # Pass this display set through untouched rather than losing
                # every subtitle in the film. It will render in the left eye
                # only, which is worse than 3D and far better than nothing.
                stats["passed_through"] = stats.get("passed_through", 0) + 1
                if stats["passed_through"] == 1:
                    sys.stderr.write("pgs3d: display set %d could not be converted "
                                     "(%s), passing it through unchanged\n"
                                     % (stats["display_sets"] + 1, exc))
                out.extend(pending)
                pending.clear()
    try:
        flush()
    except Exception as exc:
        stats["passed_through"] = stats.get("passed_through", 0) + 1
        sys.stderr.write("pgs3d: final display set could not be converted (%s)\n" % exc)
        out.extend(pending)
        pending.clear()

    return b"".join(s.pack() for s in out), stats


def main():
    ap = argparse.ArgumentParser(description="Convert a 2D PGS subtitle stream to side-by-side 3D")
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--width", type=int, default=3840,
                    help="output frame width (default 3840)")
    ap.add_argument("--depth", type=int, default=0,
                    help="disparity in pixels, positive moves subtitles towards the viewer")
    ap.add_argument("--brightness", type=float, default=1.0,
                    help="gamma on subtitle luminance; below 1 brightens the "
                         "anti-aliased edges that go grey when a player scales "
                         "the subtitle plane (try 0.7)")
    ap.add_argument("--colour", "--color", dest="colour", default="source",
                    help="source, white, yellow, cyan, green or amber")
    ap.add_argument("--opacity", type=float, default=1.0,
                    help="multiplier on subtitle alpha, 1.0 leaves it alone")
    ap.add_argument("--stack", action="store_true",
                    help="top-and-bottom layout instead of side-by-side")
    ap.add_argument("--height", type=int, default=2160,
                    help="output frame height, only used with --stack")
    args = ap.parse_args()

    with open(args.input, "rb") as fh:
        data = fh.read()
    if not data:
        sys.stderr.write("input is empty\n")
        return 1

    result, stats = convert(data, args.width, args.depth,
                            stack=args.stack, out_height=args.height,
                            gamma=args.brightness, colour=args.colour,
                            opacity=args.opacity)

    with open(args.output, "wb") as fh:
        fh.write(result)

    sys.stderr.write(
        f"pgs3d: {stats['display_sets']} display sets, "
        f"{stats['objects']} objects merged into both eyes, width -> {args.width}"
        + (f", {stats['clamped']} clamped to frame\n" if stats["clamped"] else "\n"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
