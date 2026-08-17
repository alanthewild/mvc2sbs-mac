#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""
Generates MVC2SBS.icns. Regenerate with:  python3 make-icon.py

The motif is the stereo pair itself: two offset frames, the left eye cool and
the right eye warm, overlapping in the middle the way a stereo pair converges.
Readable down to 16px because it is two shapes and nothing else.
"""

import struct
from PIL import Image, ImageDraw

BG_TOP = (22, 27, 38)
BG_BOTTOM = (12, 15, 22)
LEFT = (86, 204, 242)      # cyan, left eye
RIGHT = (240, 98, 146)     # warm pink, right eye

# icns type -> pixel size. PNG payloads are accepted for all of these.
TYPES = [
    (b"ic11", 32), (b"ic12", 64), (b"ic07", 128), (b"ic13", 256),
    (b"ic08", 256), (b"ic14", 512), (b"ic09", 512), (b"ic10", 1024),
]


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius, fill=255)
    return m


def render(size):
    s = size * 4                       # supersample, then downscale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    bg = Image.new("RGBA", (s, s))
    d = ImageDraw.Draw(bg)
    for y in range(s):
        t = y / max(1, s - 1)
        d.line([(0, y), (s, y)], fill=tuple(
            int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,))
    img.paste(bg, (0, 0))

    # Two frames, offset horizontally: the stereo pair.
    fw, fh = int(s * 0.44), int(s * 0.34)
    cy = s // 2
    gap = int(s * 0.085)
    r = int(s * 0.045)
    lw = max(2, int(s * 0.022))

    def frame(cx, colour):
        layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        dd = ImageDraw.Draw(layer)
        box = [cx - fw // 2, cy - fh // 2, cx + fw // 2, cy + fh // 2]
        dd.rounded_rectangle(box, r, fill=colour + (46,), outline=colour + (255,), width=lw)
        return layer

    left = frame(s // 2 - gap, LEFT)
    right = frame(s // 2 + gap, RIGHT)
    img.alpha_composite(right)
    img.alpha_composite(left)

    img.putalpha(rounded_mask(s, int(s * 0.22)))
    return img.resize((size, size), Image.LANCZOS)


def main():
    entries = []
    cache = {}
    for kind, size in TYPES:
        if size not in cache:
            import io
            buf = io.BytesIO()
            render(size).save(buf, format="PNG")
            cache[size] = buf.getvalue()
        data = cache[size]
        entries.append(kind + struct.pack(">I", len(data) + 8) + data)

    body = b"".join(entries)
    with open("MVC2SBS.icns", "wb") as fh:
        fh.write(b"icns" + struct.pack(">I", len(body) + 8) + body)

    render(512).save("icon-preview.png")
    print(f"wrote MVC2SBS.icns ({len(body) + 8} bytes) and icon-preview.png")


if __name__ == "__main__":
    main()
