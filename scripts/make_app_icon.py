#!/usr/bin/env python3
"""Write the icon of the app: the vector, and each slot of the icon set.

    python3 scripts/make_app_icon.py
    python3 scripts/make_app_icon.py --master PATH
    python3 scripts/make_app_icon.py --check

The icon is the Plateworks mark, pinched at the waist (design 17.3). The four
contours of the mark are drawn as lines, in the accent of the app. Each one
is pressed in at its own middle height, as an anamorphic lens squeezes a
photo, and it keeps its true width above and below.

It writes, from one set of constants, so the files cannot differ:

  App/AppIcon.svg
      The icon as a vector. The app does not load it.
  App/PlateworksDesqueeze/Assets.xcassets/AppIcon.appiconset/
      Ten PNG files: 16, 32, 128, 256 and 512 points, each at 1x and 2x.

It stops, and writes nothing, when Contents.json of the icon set names other
files than these ten.

--master PATH  The file of the master mark, `plateworks-mark.svg`. The
               script stops when its four contours differ from the ones
               below. The master is kept outside this repo, so with no
               path the script says that it did not compare.
--check        Write nothing. Exit 1 when a file on disk differs from what
               the script would write.

Each size is drawn from the vector, and no size is a smaller copy of
another. Standard library only: zlib writes the PNG files. The same
constants give the same bytes.

Change a color here only after it changed in design 17.1. The values come
from the Plateworks color standard, and `AccentAndIconTests` holds the same
accent value for the window.
"""
import argparse
import json
import math
import os
import re
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_SET = os.path.join("App", "PlateworksDesqueeze", "Assets.xcassets", "AppIcon.appiconset")
SVG_OUT = os.path.join("App", "AppIcon.svg")

# ---------------------------------------------------------------------------
# Colors (design 17.3).
GROUND = "EAEEE9"     # Halite, the light ground of the color standard
RINGS = "157BA6"      # the Chalcanthite fill, the accent of the app

# ---------------------------------------------------------------------------
# Geometry. The master mark has a box of 100 units. The icon has a grid of
# 200 units.
GRID = 200.0

# The four closed contours of the master, the outer one first, verbatim.
MARK = [
    "M49 8C62 5 79 12 87 26C95 40 93 57 85 70C77 83 62 91 47 91C32 91 17 83 11 68"
    "C5 54 8 36 17 24C26 12 38 9 49 8Z",
    "M46 22C32 23 21 33 19 47C17 61 23 75 36 81C49 87 64 84 73 74C82 64 82 49 76 38"
    "C70 27 57 21 46 22Z",
    "M53 37C43 36 36 42 34 50C32 58 36 67 44 72C52 77 62 74 68 67C74 60 74 49 69 43"
    "C64 37 59 36 53 37Z",
    "M53 51C49 51 46 54 46 57C46 60 49 63 53 63C57 63 60 60 60 57C60 54 57 51 53 51Z",
]
# The center of the ink of the mark, in mark units. It goes onto the center
# of the tile.
INK_CENTER = (50.0, 49.2)
# One mark unit is this many grid units: 1.8 on a tile that fills the grid,
# so 1.8 times the part of the grid that the tile fills.
MARK_SCALE = 1.8 * 824 / 1024
# The pinch. Each point of a contour moves toward the vertical line through
# the center of that contour:
#
#     x' = cx + (x - cx) * (1 - PINCH * exp(-((y - cy) / PINCH_HEIGHT) ** 2))
#
# y does not change. So a contour has 1 - PINCH of its width at its own
# middle height, and its true width far above and below. CENTERS has the
# center of the box of each contour, the outer one first, in mark units.
PINCH = 0.42
PINCH_HEIGHT = 16.0
CENTERS = [(49.99, 49.16), (49.40, 52.99), (53.06, 55.57), (53.0, 57.0)]
# The line width in mark units. The three outer contours are lines, and the
# core is filled. A line is drawn after the pinch, so it has one width all
# the way around.
LINE = 4.5

# The tile, in grid units: how far its edge is from the edge of the grid,
# and the radius of its corners. It is the shape of a Mac icon since macOS
# 11: at 1024 pixels, a square of 824 with corners of 185.4, and nothing
# around it. macOS 14 and 15 draw an icon as it is given, so a tile that
# filled the grid would be a hard square there. macOS 26 and later give
# each icon their own shape, and this tile fits it (design 17.3).
TILE_INSET = 100 * GRID / 1024
TILE_RADIUS = 185.4 * GRID / 1024

# (file name, pixels). The names are those of Contents.json.
SLOTS = [
    ("icon-16.png", 16), ("icon-16@2x.png", 32),
    ("icon-32.png", 32), ("icon-32@2x.png", 64),
    ("icon-128.png", 128), ("icon-128@2x.png", 256),
    ("icon-256.png", 256), ("icon-256@2x.png", 512),
    ("icon-512.png", 512), ("icon-512@2x.png", 1024),
]

SUBROWS = 16  # sample rows for each row of pixels


def rgb(hex6):
    return tuple(int(hex6[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------------------
# The master.

def check_master(path):
    """Stop when the contours above differ from those of the master."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    found = []
    for d in re.findall(r'\sd="([^"]*)"', text):
        found += ["".join(c.split()) for c in re.findall(r"M[^M]*Z", d.replace("&#xA;", " "))]
    ours = ["".join(c.split()) for c in MARK]
    if found != ours:
        sys.exit("make_app_icon.py: the contours in this script differ from the master, %s" % path)
    print("The four contours are those of the master.")


# ---------------------------------------------------------------------------
# From a contour to polygons, in mark units.

def parse(d):
    """A path of M, C and Z with absolute numbers, as (op, points)."""
    tokens = d.replace("M", " M ").replace("C", " C ").replace("Z", " Z ").split()
    segments, i = [], 0
    while i < len(tokens):
        op = tokens[i]
        i += 1
        if op == "Z":
            continue
        points = []
        for _ in range(1 if op == "M" else 3):
            points.append((float(tokens[i]), float(tokens[i + 1])))
            i += 2
        segments.append((op, points))
    return segments


def flatten(d, steps=60):
    """One closed contour as a polygon. The last point is not the first."""
    points, current = [], None
    for op, ps in parse(d):
        if op == "M":
            current = ps[0]
            points.append(current)
            continue
        p1, p2, p3 = ps
        for k in range(1, steps + 1):
            s = k / steps
            a, b, c, e = (1 - s) ** 3, 3 * (1 - s) ** 2 * s, 3 * (1 - s) * s * s, s ** 3
            points.append((a * current[0] + b * p1[0] + c * p2[0] + e * p3[0],
                           a * current[1] + b * p1[1] + c * p2[1] + e * p3[1]))
        current = p3
    if points[-1] == points[0]:
        points.pop()
    return points


def offset(polygon, distance):
    """The polygon moved along its normals. A positive distance and a
    negative one give the two edges of a line with round joins: at the one
    corner of a contour, where it starts, the point lies on the bisector."""
    n = len(polygon)
    out = []
    for i in range(n):
        (x0, y0), (x1, y1), (x2, y2) = polygon[i - 1], polygon[i], polygon[(i + 1) % n]
        ax, ay = x1 - x0, y1 - y0
        bx, by = x2 - x1, y2 - y1
        la, lb = math.hypot(ax, ay), math.hypot(bx, by)
        nx, ny = ay / la + by / lb, -ax / la - bx / lb
        ln = math.hypot(nx, ny)
        out.append((x1 + distance * nx / ln, y1 + distance * ny / ln))
    return out


def area(polygon):
    return abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(polygon, polygon[1:] + polygon[:1]))) / 2


def pinch(polygon, center):
    cx, cy = center
    return [(cx + (x - cx) * (1 - PINCH * math.exp(-((y - cy) / PINCH_HEIGHT) ** 2)), y)
            for x, y in polygon]


def pinched():
    """The four contours after the pinch, as polygons in mark units."""
    return [pinch(flatten(d), center) for d, center in zip(MARK, CENTERS)]


def to_grid(polygon):
    c = GRID / 2
    return [(c + (x - INK_CENTER[0]) * MARK_SCALE, c + (y - INK_CENTER[1]) * MARK_SCALE)
            for x, y in polygon]


def layers():
    """What is painted over the ground, in order: (color, add, subtract).
    Each is a list of polygons in grid units. A line is the area between
    its two edges."""
    contours = pinched()
    out = []
    for contour in contours[:3]:
        # The contours do not all turn the same way, so the sign of the
        # distance does not say which edge is the outer one. The area does.
        edges = sorted((offset(contour, LINE / 2), offset(contour, -LINE / 2)), key=area)
        out.append((rgb(RINGS), [to_grid(edges[1])], [to_grid(edges[0])]))
    out.append((rgb(RINGS), [to_grid(contours[3])], []))
    return out


def tile():
    """The outline of the tile, in grid units."""
    lo, hi, r = TILE_INSET, GRID - TILE_INSET, TILE_RADIUS
    if r == 0:
        return [(lo, lo), (hi, lo), (hi, hi), (lo, hi)]
    points = []
    for cx, cy, start in ((hi - r, lo + r, -90), (hi - r, hi - r, 0), (lo + r, hi - r, 90), (lo + r, lo + r, 180)):
        for k in range(25):
            a = math.radians(start + 90 * k / 24)
            points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return points


def reach():
    """How far the ink is from the center of the tile, at its farthest."""
    c = GRID / 2
    return max(math.hypot(x - c, y - c) for _, add, _ in layers() for poly in add for x, y in poly)


# ---------------------------------------------------------------------------
# From polygons to pixels. For each row of pixels, SUBROWS sample rows, and
# on each one the exact part of each pixel that the polygon covers.

def coverage(polygon, size):
    """Rows of the part of each pixel inside the polygon, 0 to 1."""
    unit = size / GRID
    poly = [(x * unit, y * unit) for x, y in polygon]
    edges = [(x0, y0, x1, y1) for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]) if y0 != y1]
    buckets = [[] for _ in range(size)]
    for e in edges:
        lo, hi = min(e[1], e[3]), max(e[1], e[3])
        for row in range(max(0, int(lo)), min(size - 1, int(hi)) + 1):
            buckets[row].append(e)
    w = 1.0 / SUBROWS
    rows = []
    for row in range(size):
        if not buckets[row]:
            rows.append(None)
            continue
        a = [0.0] * (size + 1)
        d = [0.0] * (size + 2)
        for k in range(SUBROWS):
            ys = row + (k + 0.5) / SUBROWS
            xs = sorted(x0 + (ys - y0) * (x1 - x0) / (y1 - y0)
                        for x0, y0, x1, y1 in buckets[row]
                        if (y0 <= ys < y1) or (y1 <= ys < y0))
            for j in range(0, len(xs) - 1, 2):
                xa = min(max(xs[j], 0.0), size)
                xb = min(max(xs[j + 1], 0.0), size)
                ia, ib = int(xa), int(xb)
                if ia == ib:
                    a[ia] += (xb - xa) * w
                else:
                    a[ia] += (ia + 1 - xa) * w
                    d[ia + 1] += w
                    d[ib] -= w
                    a[ib] += (xb - ib) * w
        run = 0.0
        for x in range(size):
            run += d[x]
            a[x] = min(1.0, max(0.0, a[x] + run))
        rows.append(a)
    return rows


def render(size):
    """Rows of RGBA bytes."""
    ground = rgb(GROUND)
    alpha = coverage(tile(), size)
    image = [[list(ground) for _ in range(size)] for _ in range(size)]
    for color, add, subtract in layers():
        plus = [coverage(p, size) for p in add]
        minus = [coverage(p, size) for p in subtract]
        for y in range(size):
            rows_plus = [r[y] for r in plus if r[y] is not None]
            if not rows_plus:
                continue
            rows_minus = [r[y] for r in minus if r[y] is not None]
            line = image[y]
            for x in range(size):
                part = sum(r[x] for r in rows_plus) - sum(r[x] for r in rows_minus)
                if part <= 0.0:
                    continue
                part = min(1.0, part)
                px = line[x]
                px[0] += (color[0] - px[0]) * part
                px[1] += (color[1] - px[1]) * part
                px[2] += (color[2] - px[2]) * part
    rows = []
    for y in range(size):
        out = bytearray()
        cover = alpha[y]
        for x in range(size):
            px = image[y][x]
            a = cover[x] if cover is not None else 0.0
            out += bytes((int(round(px[0])), int(round(px[1])), int(round(px[2])), int(round(255 * a))))
        rows.append(bytes(out))
    return rows


def png(rows):
    """The bytes of a PNG with 8 bits for each of red, green, blue, alpha."""
    height, width = len(rows), len(rows[0]) // 4
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"sRGB", b"\x00")
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# The vector.

def number(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def svg():
    """The icon as a vector. The pinch is no transform of SVG, so the file
    holds points, in grid units. A line is a filled band between its two
    edges, the same polygons that the PNG files are drawn from. A stroke
    would be shorter, but two renderers drew a hairline gap across it."""
    def path(polygon):
        return "M" + "L".join("%s %s" % (number(x), number(y)) for x, y in polygon) + "Z"

    lines = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 %s %s" '
        'role="img" aria-label="Plateworks Desqueeze">' % (number(GRID), number(GRID)),
        '  <!-- The icon of Plateworks Desqueeze. scripts/make_app_icon.py writes this',
        '       file: run it again, and never edit this file by hand. The four contours',
        '       of the Plateworks mark as lines, each pinched at its middle height. -->',
        '  <rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="#%s"/>'
        % (number(TILE_INSET), number(TILE_INSET), number(GRID - 2 * TILE_INSET),
           number(GRID - 2 * TILE_INSET), number(TILE_RADIUS), GROUND),
    ]
    for color, add, subtract in layers():
        d = " ".join(path(polygon) for polygon in add + subtract)
        lines.append('  <path fill="#%02X%02X%02X" fill-rule="evenodd" d="%s"/>' % (color + (d,)))
    lines.append('</svg>')
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------

def check_contents():
    """Contents.json must name the ten files of SLOTS, and no other."""
    path = os.path.join(ROOT, ICON_SET, "Contents.json")
    with open(path, encoding="utf-8") as f:
        images = json.load(f)["images"]
    named = sorted(i.get("filename", "") for i in images)
    ours = sorted(name for name, _ in SLOTS)
    if named != ours:
        sys.exit("make_app_icon.py: %s names %s, and the script writes %s"
                 % (os.path.join(ICON_SET, "Contents.json"), named, ours))


def main():
    parser = argparse.ArgumentParser(description="Write the icon of the app.")
    parser.add_argument("--master", help="the file plateworks-mark.svg, to compare the contours")
    parser.add_argument("--check", action="store_true", help="write nothing, and fail for a file that differs")
    args = parser.parse_args()

    if args.master:
        check_master(args.master)
    else:
        print("The contours were not compared with the master. Give its file with --master.")
    check_contents()

    half = GRID / 2 - TILE_INSET
    print("The ink is %.1f grid units from the center at its farthest. The tile has %.1f to its edge."
          % (reach(), half))
    if reach() > half:
        sys.exit("make_app_icon.py: the ink leaves the tile")

    files = {SVG_OUT: svg().encode("utf-8")}
    cache = {}
    for name, size in SLOTS:
        if size not in cache:
            cache[size] = png(render(size))
        files[os.path.join(ICON_SET, name)] = cache[size]

    differ = []
    for rel, data in files.items():
        path = os.path.join(ROOT, rel)
        if args.check:
            if not os.path.exists(path) or open(path, "rb").read() != data:
                differ.append(rel)
            continue
        with open(path, "wb") as f:
            f.write(data)
        print("Wrote %s" % rel)
    if differ:
        sys.exit("make_app_icon.py: these files differ from what the script writes: %s" % ", ".join(differ))
    if args.check:
        print("Each file is what the script writes.")


if __name__ == "__main__":
    main()
