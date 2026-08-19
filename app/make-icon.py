#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alan Wild
"""
Generates MVC2SBS.icns and MKVShrink.icns. Regenerate with:
    python3 make-icon.py

MVC2SBS: the motif is the stereo pair itself, two offset frames, the left eye
cool and the right eye warm, overlapping in the middle the way a stereo pair
converges.

MKVShrink: the same two frames, but one of them has become small. Same
background, same corner radius, same frame language, so the two read as a set
in the Dock without reading as the same app. The small frame is cut out of the
large one rather than blended over it, because two translucent overlapping
rectangles turn into one grey shape at 16px.

Both are two shapes and nothing else, which is the only reason they survive
being 16 pixels wide.
"""

import struct
from PIL import Image, ImageDraw

BG_TOP = (22, 27, 38)
BG_BOTTOM = (12, 15, 22)
LEFT = (86, 204, 242)      # cyan, left eye
RIGHT = (240, 98, 146)     # warm pink, right eye
SMALL = (94, 214, 148)     # green, the file after it has shrunk

# icns type -> pixel size. PNG payloads are accepted for all of these.
TYPES = [
    (b"ic11", 32), (b"ic12", 64), (b"ic07", 128), (b"ic13", 256),
    (b"ic08", 256), (b"ic14", 512), (b"ic09", 512), (b"ic10", 1024),
]


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius, fill=255)
    return m


def background(s):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bg = Image.new("RGBA", (s, s))
    d = ImageDraw.Draw(bg)
    for y in range(s):
        t = y / max(1, s - 1)
        d.line([(0, y), (s, y)], fill=tuple(
            int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,))
    img.paste(bg, (0, 0))
    return img


def render(size):
    s = size * 4                       # supersample, then downscale
    img = background(s)

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


def render_shrink(size):
    """MKVShrink: a frame, and the same frame after it has shrunk."""
    s = size * 4
    img = background(s)
    c = s // 2
    lw = max(2, int(s * 0.024))

    # The original. Outline only, so the small one can sit in front of it.
    bw = int(s * 0.56)
    bh = int(bw * 9 / 16)
    bx, by = c - int(s * 0.07), c - int(s * 0.06)
    sw = int(s * 0.30)
    sh = int(sw * 9 / 16)
    sx, sy = c + int(s * 0.15), c + int(s * 0.13)

    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(
        [bx - bw // 2, by - bh // 2, bx + bw // 2, by + bh // 2],
        int(s * 0.04), fill=LEFT + (42,), outline=LEFT + (255,), width=lw)

    # Punch the small frame's outline out of the large one before compositing,
    # rather than painting a dark patch over it. Without the gap the two
    # translucent rectangles blend into one grey shape wherever they overlap,
    # and at 16px that is the whole icon. Erasing to transparent lets the
    # background gradient show through, so the gap cannot be a slightly wrong
    # shade of the thing behind it.
    pad = int(lw * 1.6)
    d.rounded_rectangle(
        [sx - sw // 2 - pad, sy - sh // 2 - pad,
         sx + sw // 2 + pad, sy + sh // 2 + pad],
        int(s * 0.045), fill=(0, 0, 0, 0))
    img.alpha_composite(layer)

    # The result. Filled, not outlined: at 16px an outlined 4px rectangle is a
    # smudge, and this is the shape carrying the whole idea.
    small = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(small).rounded_rectangle(
        [sx - sw // 2, sy - sh // 2, sx + sw // 2, sy + sh // 2],
        int(s * 0.035), fill=SMALL + (190,), outline=SMALL + (255,), width=lw)
    img.alpha_composite(small)

    img.putalpha(rounded_mask(s, int(s * 0.22)))
    return img.resize((size, size), Image.LANCZOS)


def write_icns(name, renderer):
    import io
    entries = []
    cache = {}
    for kind, size in TYPES:
        if size not in cache:
            buf = io.BytesIO()
            renderer(size).save(buf, format="PNG")
            cache[size] = buf.getvalue()
        data = cache[size]
        entries.append(kind + struct.pack(">I", len(data) + 8) + data)

    body = b"".join(entries)
    with open(name + ".icns", "wb") as fh:
        fh.write(b"icns" + struct.pack(">I", len(body) + 8) + body)
    return len(body) + 8


def main():
    n = write_icns("MVC2SBS", render)
    render(512).save("icon-preview.png")
    print(f"wrote MVC2SBS.icns ({n} bytes) and icon-preview.png")

    n = write_icns("MKVShrink", render_shrink)
    render_shrink(512).save("shrink-icon-preview.png")
    print(f"wrote MKVShrink.icns ({n} bytes) and shrink-icon-preview.png")


if __name__ == "__main__":
    main()
