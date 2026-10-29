"""Generates the real-shape US map (docs/DESIGN.md D-070).

Run from the repository root:  python3 scripts/mapgen/make.py
Needs Pillow (PIL 11; a user install is fine). Reads
scripts/mapgen/data/states-albers-10m.json (us-atlas 3.0.1, ISC, LICENSE-us-atlas
next to it; US Census Bureau cartographic boundaries, public domain): the 50
states and DC, already projected (Albers USA) into a 975x610 frame with Alaska
and Hawaii moved under the West. Writes:

  assets/map/map-states-<k>.png  white state fill masks on transparent, packed
                                 into atlases of at most 1024x1024 (Roblox's
                                 upload limit), drawn 4x supersampled for soft
                                 edges; tinted in game with ImageColor3
  assets/map/map-states-<k>a.png  the same atlases (same packing, same rects)
  assets/map/map-states-<k>b.png  as marker scribble: white hatch strokes on
                                 transparent, slanted / (a, seat 1) or \ (b,
                                 seat 2), so the map reads without color;
                                 tinted in game like the flat ones
  assets/map/map-borders.png     the inner state borders as white lines on
                                 transparent (at most 1024 wide), tinted dark
  assets/map/map-ink.png         the whiteboard's map in marker: every border
                                 and the coast of the lower 48 as slightly
                                 wobbly white lines (Alaska and Hawaii move
                                 into insets in game, so they are left out),
                                 tinted ink
  src/shared/UI/MapShapeData.luau  per state: where its sprite sits in the map
                                 box, its atlas rect, a label anchor (the
                                 middle of the biggest circle inside it), how
                                 roomy it is, and simplified outlines for tap
                                 hit tests and the headless snapshots; the
                                 nine small Northeast states' callout chips

The map box keeps MapLayout.ASPECT (1.6) so the screens size it as before. All
coordinates in the Luau module are fractions of the box: x of its width, y of
its height.
"""

import heapq
import math
import os
import random
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import topo  # noqa: E402  (sibling module)

DATA = os.path.join(HERE, "data", "states-albers-10m.json")
STATE_DATA = os.path.join(ROOT, "src", "shared", "Sim", "StateData.luau")
OUT_ASSETS = os.path.join(ROOT, "assets", "map")
OUT_LUAU = os.path.join(ROOT, "src", "shared", "UI", "MapShapeData.luau")

ASPECT = 1.6  # box width / height; must equal MapLayout.ASPECT
PHONE_WIDTH = 360  # px, MapLayout.PHONE_WIDTH: the narrowest map
CHIP_COLUMN_PX = 40  # px at PHONE_WIDTH: the callout column (a 36 px tap target and a gap)
PAD = 6  # units of margin around everything (the frame is 975 units wide)
GAP = 10  # units between the coast and the callout column
LEGEND = 0.085  # share of the box height kept free under the map for a legend row
LADDER = ["VT", "NH", "MA", "RI", "CT", "NJ", "DE", "MD", "DC"]  # MapLayout.LADDER

RES = 1.3  # atlas px per unit (the US is ~1240 px wide in the atlas: sharp on a 1000 px iPad map)
SUPER = 4  # supersampling for anti-aliased edges
SPRITE_PAD = 2  # transparent px around each sprite in its atlas
ATLAS = 1024  # px, the largest image Roblox keeps at full size
BORDER_PX = 2.2  # border line width in the overlay, px at its own scale
HATCH_PITCH = 9.0  # atlas px between scribble strokes (about 2 px on a phone's map, 6 on an iPad's)
HATCH_W = 6.2  # atlas px, a stroke's width (the rest of the pitch is the white gap)
HATCH_WOBBLE = 0.7  # atlas px, how far a stroke drifts off its line
HATCH_TURN = 0.05  # radians, how far a stroke may turn off the slant (about 3 degrees)
HATCH_SUPER = 2  # supersampling for the strokes
HATCH_GRAIN = 6  # atlas px per cell of the ink's grain (pressure noise)
HATCH_SLANTS = {"a": "/", "b": "\\"}  # file suffix -> stroke slant (seat 1, seat 2)
INK_INNER_PX = 2.4  # ink overlay: a border between two states, px at its own scale
INK_COAST_PX = 3.0  # ... the coast (the land's outline), a little heavier
INK_WOBBLE = 0.45  # units, how far a marker line strays from the true border
INK_STEP = 1.5  # units between the wobbly line's points
INK_PAD = 3.0  # units of margin around the lower 48 in the ink overlay (a coast line's half width fits)
INK_LEFT_OUT = ("AK", "HI")  # drawn in their insets in game, not where the overlay has them
SIMPLIFY = 0.6  # units, Douglas-Peucker tolerance for the outlines
MIN_RING = 3.0  # square units: smaller islands are left out of the outlines
EDGE_SIMPLIFY = 1.5  # units, the coarser outline the game draws around a selected state
EDGE_MIN_RING = 30.0  # square units: islands drawn in that outline

# Alaska and Hawaii: scale about their own centers, then move (units). The
# frame's Alaska reaches past its left edge; this tucks it in under California.
INSETS = {
    "AK": {"scale": 0.82, "dx": 49.0, "dy": 7.0},
    "HI": {"scale": 1.0, "dx": 8.0, "dy": -8.0},
}

# Label anchors where the middle of the biggest inner circle reads badly (units,
# in the frame after INSETS). Checked against the snapshots.
ANCHOR = {
}

# Room (the inner circle's diameter, units) where the sea around a state is free
# for its label and value: Hawaii's islands are tiny, its inset is not.
ROOM = {
    "HI": 60.0,
}


# ---------------------------------------------------------------- geometry


def ring_area(ring):
    a = 0.0
    for i in range(len(ring) - 1):
        x1, y1 = ring[i]
        x2, y2 = ring[i + 1]
        a += x1 * y2 - x2 * y1
    return a / 2.0


def transform(poly, center, scale, dx, dy):
    cx, cy = center
    return [[((x - cx) * scale + cx + dx, (y - cy) * scale + cy + dy) for x, y in ring] for ring in poly]


def bbox(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def simplify(points, tolerance):
    """Douglas-Peucker on an open or closed polyline."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        best, index = -1.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            if length == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / length
            if d > best:
                best, index = d, i
        if best > tolerance and index > 0:
            keep[index] = True
            stack.append((a, index))
            stack.append((index, b))
    return [p for p, k in zip(points, keep) if k]


def point_in_rings(x, y, rings):
    inside = False
    for ring in rings:
        n = len(ring)
        j = n - 1
        for i in range(n):
            xi, yi = ring[i]
            xj, yj = ring[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
    return inside


def segment_distance(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def signed_distance(x, y, rings):
    """Distance to the outline, positive inside."""
    d = min(
        segment_distance(x, y, *ring[i], *ring[i + 1]) for ring in rings for i in range(len(ring) - 1)
    )
    return d if point_in_rings(x, y, rings) else -d


def polylabel(rings, precision=0.5):
    """The point inside `rings` farthest from its outline (Mapbox's polylabel)."""
    x0, y0, x1, y1 = bbox(rings[0])
    size = min(x1 - x0, y1 - y0)
    h = size / 2
    if h == 0:
        return x0, y0, 0.0
    queue = []

    def push(cx, cy, half):
        d = signed_distance(cx, cy, rings)
        heapq.heappush(queue, (-(d + half * math.sqrt(2)), d, cx, cy, half))

    x = x0
    while x < x1:
        y = y0
        while y < y1:
            push(x + h, y + h, h)
            y += size
        x += size
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    best = (signed_distance(cx, cy, rings), cx, cy)
    while queue:
        _, d, cx, cy, half = heapq.heappop(queue)
        if d > best[0]:
            best = (d, cx, cy)
        if d + half * math.sqrt(2) - best[0] <= precision:
            continue
        half /= 2
        for sx in (-1, 1):
            for sy in (-1, 1):
                push(cx + sx * half, cy + sy * half, half)
    return best[1], best[2], best[0]


# ---------------------------------------------------------------- input


def state_ids():
    """Name -> id, and the id order, from Sim/StateData.luau."""
    text = open(STATE_DATA, encoding="utf-8").read()
    pairs = re.findall(r'id = "([A-Z]{2})",\s*name = "([^"]+)"', text)
    return {name: sid for sid, name in pairs}, [sid for sid, _ in pairs]


def load_states():
    data = topo.load(DATA)
    arcs = topo.decode_arcs(data)
    by_name, order = state_ids()
    states = {}
    for g in data["objects"]["states"]["geometries"]:
        sid = by_name[g["properties"]["name"]]
        poly_list = topo.polygons(arcs, g)
        if sid in INSETS:
            pts = [p for poly in poly_list for ring in poly for p in ring]
            x0, y0, x1, y1 = bbox(pts)
            t = INSETS[sid]
            poly_list = [
                transform(poly, ((x0 + x1) / 2, (y0 + y1) / 2), t["scale"], t["dx"], t["dy"])
                for poly in poly_list
            ]
        states[sid] = poly_list
    missing = [sid for sid in order if sid not in states]
    assert not missing, f"no shape for {missing}"
    borders = [arcs[i] for i in topo.shared_arcs(data, "states")]
    # The ink overlay's lines: every arc of the lower 48 and DC, inner or coast.
    owners = {}
    for g in data["objects"]["states"]["geometries"]:
        sid = by_name[g["properties"]["name"]]
        kind = g["type"]
        groups = [g["arcs"]] if kind == "Polygon" else g["arcs"] if kind == "MultiPolygon" else []
        for group in groups:
            for ring in group:
                for index in ring:
                    owners.setdefault(index if index >= 0 else ~index, set()).add(sid)
    ink = []
    for i in sorted(owners):
        if owners[i] & set(INK_LEFT_OUT):
            continue
        ink.append((arcs[i], len(owners[i]) == 1))  # (points, is the coast)
    return states, order, borders, ink


# ---------------------------------------------------------------- layout


def layout(states):
    """The map box in units: (left, top, width, height) and the callout column."""
    pts = [p for sid, polys in states.items() for poly in polys for ring in poly for p in ring]
    gx0, gy0, gx1, gy1 = bbox(pts)
    # Box width W units holds the land, the gap and a column CHIP_COLUMN_PX wide at PHONE_WIDTH:
    # W = land + GAP + 2 PAD + W * CHIP_COLUMN_PX / PHONE_WIDTH.
    share = CHIP_COLUMN_PX / PHONE_WIDTH
    width = ((gx1 - gx0) + GAP + 2 * PAD) / (1 - share)
    height = width / ASPECT
    need = (gy1 - gy0) + 2 * PAD
    assert need <= height * (1 - LEGEND), f"land {need} taller than the box {height}"
    left = gx0 - PAD
    top = gy0 - PAD
    column = (gx1 + GAP, width * share)  # x of the column's left edge (units), its width
    return {"left": left, "top": top, "width": width, "height": height, "column": column, "land": (gx0, gy0, gx1, gy1)}


# ---------------------------------------------------------------- raster


def mask(polys, x0, y0, w, h):
    """A white-on-transparent sprite of `polys` with its top-left at units (x0, y0)."""
    big = Image.new("L", (w * SUPER, h * SUPER), 0)
    draw = ImageDraw.Draw(big)
    k = RES * SUPER
    for poly in polys:
        for index, ring in enumerate(poly):
            pts = [((x - x0) * k, (y - y0) * k) for x, y in ring]
            if len(pts) >= 3:
                draw.polygon(pts, fill=255 if index == 0 else 0)
    alpha = big.resize((w, h), Image.Resampling.BOX)
    sprite = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    sprite.putalpha(alpha)
    return sprite


def pack(sprites):
    """Shelf-packs {id: image} into atlases of at most ATLAS px square."""
    order = sorted(sprites, key=lambda sid: (-sprites[sid].size[1], sid))
    atlases = [[]]  # per atlas: list of (sid, x, y)
    x = y = shelf = 0
    for sid in order:
        w, h = sprites[sid].size
        assert w <= ATLAS and h <= ATLAS, f"{sid} sprite {w}x{h} is over {ATLAS}"
        if x + w > ATLAS:
            x, y, shelf = 0, y + shelf, 0
        if y + h > ATLAS:
            atlases.append([])
            x = y = shelf = 0
        atlases[-1].append((sid, x, y))
        x += w
        shelf = max(shelf, h)
    places = {}
    for k, placed in enumerate(atlases):
        for sid, px, py in placed:
            places[sid] = (k + 1, px, py)
    return compose(sprites, places), places


def compose(sprites, places):
    """The atlas images for `sprites` at `places` ({id: (atlas, x, y)}), so
    another set of sprites the same sizes lands on the same rects."""
    count = max(k for k, _, _ in places.values())
    images = []
    for k in range(1, count + 1):
        placed = [(sid, px, py) for sid, (a, px, py) in places.items() if a == k]
        used_h = max(py + sprites[sid].size[1] for sid, _, py in placed)
        used_w = max(px + sprites[sid].size[0] for sid, px, _ in placed)
        image = Image.new("RGBA", (used_w, used_h), (255, 255, 255, 0))
        for sid, px, py in sorted(placed):
            image.paste(sprites[sid], (px, py))
        images.append(image)
    return images


def grain(rng, w, h, low, high):
    """Smooth pressure noise in [low, high] over a w x h image (L, 0 to 255)."""
    gw, gh = max(2, int(w / HATCH_GRAIN) + 2), max(2, int(h / HATCH_GRAIN) + 2)
    small = Image.new("L", (gw, gh))
    small.putdata([int(255 * rng.uniform(low, high)) for _ in range(gw * gh)])
    return small.resize((w, h), Image.Resampling.BICUBIC)


def scribble(sprite, slant, seed):
    """`sprite` (a white state mask) colored in with marker: dense strokes at
    `slant` ("/" or "\\"), each a little wobbly and uneven in pressure, with
    small white gaps between them and where the pen lifts. White on
    transparent; the alpha carries the texture. Seeded, so it never changes."""
    w, h = sprite.size
    rng = random.Random(f"{slant}:{seed}")
    k = HATCH_SUPER
    big = Image.new("L", (w * k, h * k), 0)
    draw = ImageDraw.Draw(big)
    r = math.sqrt(0.5)
    sx, sy = (r, -r) if slant == "/" else (r, r)  # along a stroke (y down)
    cx, cy = w / 2, h / 2
    reach = math.hypot(w, h) / 2 + HATCH_PITCH  # every stroke runs from -reach to reach about the middle
    o = -reach + HATCH_PITCH * rng.random()
    while o < reach:
        # Each stroke a hair off the slant and off its place, its own width and pressure.
        turn = rng.uniform(-HATCH_TURN, HATCH_TURN)
        dx, dy = sx * math.cos(turn) - sy * math.sin(turn), sx * math.sin(turn) + sy * math.cos(turn)
        nx, ny = -dy, dx  # across the strokes
        off = o + rng.uniform(-0.9, 0.9)
        width = max(1, round(HATCH_W * rng.uniform(0.75, 1.2) * k))
        pressure = rng.uniform(0.75, 1.0)
        phase, freq = rng.uniform(0, 2 * math.pi), rng.uniform(0.03, 0.08)
        t = -reach - rng.uniform(0, 12)
        while t < reach:
            run = rng.uniform(30, 120)
            end = min(t + run, reach)
            pts = []
            u = t
            while True:
                wob = HATCH_WOBBLE * math.sin(u * freq + phase)
                pts.append(((cx + u * dx + (off + wob) * nx) * k, (cy + u * dy + (off + wob) * ny) * k))
                if u >= end:
                    break
                u = min(u + 4, end)
            value = int(255 * pressure * rng.uniform(0.86, 1.0))
            draw.line(pts, fill=value, width=width, joint="curve")
            # Mostly one stroke after another; now and then the pen lifts.
            t = end + (rng.uniform(2.0, 5.0) if rng.random() < 0.3 else -1.0)
        o += HATCH_PITCH * rng.uniform(0.9, 1.1)
    strokes = big.resize((w, h), Image.Resampling.BOX)
    strokes = ImageChops.multiply(strokes, grain(rng, w, h, 0.8, 1.0))
    alpha = ImageChops.multiply(strokes, sprite.getchannel("A"))
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def borders_image(lines, land):
    gx0, gy0, gx1, gy1 = land
    scale = min(ATLAS / (gx1 - gx0), ATLAS / (gy1 - gy0)) * 0.999
    w, h = int(math.ceil((gx1 - gx0) * scale)), int(math.ceil((gy1 - gy0) * scale))
    big = Image.new("L", (w * SUPER, h * SUPER), 0)
    draw = ImageDraw.Draw(big)
    k = scale * SUPER
    width = max(1, round(BORDER_PX * SUPER))
    for line in lines:
        pts = [((x - gx0) * k, (y - gy0) * k) for x, y in line]
        draw.line(pts, fill=255, width=width, joint="curve")
    alpha = big.resize((w, h), Image.Resampling.BOX)
    image = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    image.putalpha(alpha)
    return image, scale


def wobbly(line, rng):
    """`line` (units) resampled every INK_STEP and nudged sideways by a slow,
    seeded wobble that is zero at both ends (so joined lines stay joined)."""
    pts = []
    for i in range(len(line) - 1):
        (x1, y1), (x2, y2) = line[i], line[i + 1]
        n = max(1, int(math.hypot(x2 - x1, y2 - y1) / INK_STEP))
        for j in range(n):
            pts.append((x1 + (x2 - x1) * j / n, y1 + (y2 - y1) * j / n))
    pts.append(line[-1])
    lengths = [0.0]
    for i in range(1, len(pts)):
        lengths.append(lengths[-1] + math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
    total = lengths[-1]
    p1, p2 = rng.uniform(0, 2 * math.pi), rng.uniform(0, 2 * math.pi)
    f1, f2 = rng.uniform(0.08, 0.16), rng.uniform(0.25, 0.45)
    out = []
    for i, (x, y) in enumerate(pts):
        a, b = pts[max(0, i - 1)], pts[min(len(pts) - 1, i + 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        tl = math.hypot(tx, ty) or 1.0
        s = lengths[i]
        taper = min(1.0, s / 6.0, (total - s) / 6.0)
        d = INK_WOBBLE * taper * (0.7 * math.sin(s * f1 + p1) + 0.3 * math.sin(s * f2 + p2))
        out.append((x - ty / tl * d, y + tx / tl * d))
    return out


def ink_image(lines):
    """The ink overlay: `lines` [(points, coast)] as wobbly marker strokes,
    uneven in pressure, over the lower 48 plus INK_PAD; returns the image and
    its rect in units (x0, y0, x1, y1)."""
    pts = [p for line, _ in lines for p in line]
    x0, y0, x1, y1 = bbox(pts)
    x0, y0, x1, y1 = x0 - INK_PAD, y0 - INK_PAD, x1 + INK_PAD, y1 + INK_PAD
    scale = min(ATLAS / (x1 - x0), ATLAS / (y1 - y0)) * 0.999
    w, h = int(math.ceil((x1 - x0) * scale)), int(math.ceil((y1 - y0) * scale))
    big = Image.new("L", (w * SUPER, h * SUPER), 0)
    draw = ImageDraw.Draw(big)
    k = scale * SUPER
    for index, (line, coast) in enumerate(lines):
        rng = random.Random(f"ink:{index}")
        bent = wobbly(line, rng)
        base = INK_COAST_PX if coast else INK_INNER_PX
        # In pieces of about 12 points: each its own pressure, so the line
        # thickens and thins like a marker.
        for start in range(0, len(bent) - 1, 12):
            piece = bent[start : start + 13]
            if len(piece) < 2:
                continue
            width = max(1, round(base * rng.uniform(0.85, 1.15) * SUPER))
            value = int(255 * rng.uniform(0.9, 1.0))
            draw.line([((x - x0) * k, (y - y0) * k) for x, y in piece], fill=value, width=width, joint="curve")
    alpha = big.resize((w, h), Image.Resampling.BOX)
    image = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    image.putalpha(alpha)
    return image, (x0, y0, x1, y1)


# ---------------------------------------------------------------- output


def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main():
    states, order, border_lines, ink_lines = load_states()
    box = layout(states)
    left, top, bw, bh = box["left"], box["top"], box["width"], box["height"]

    def fx(x):
        return (x - left) / bw

    def fy(y):
        return (y - top) / bh

    sprites, rects, info = {}, {}, {}
    for sid in order:
        polys = states[sid]
        pts = [p for poly in polys for ring in poly for p in ring]
        x0, y0, x1, y1 = bbox(pts)
        px0 = math.floor(x0 * RES) - SPRITE_PAD
        py0 = math.floor(y0 * RES) - SPRITE_PAD
        px1 = math.ceil(x1 * RES) + SPRITE_PAD
        py1 = math.ceil(y1 * RES) + SPRITE_PAD
        w, h = px1 - px0, py1 - py0
        sprites[sid] = mask(polys, px0 / RES, py0 / RES, w, h)
        rects[sid] = (px0 / RES, py0 / RES, w / RES, h / RES)

        # Outlines for hit tests: every ring that is not a speck, simplified.
        rings = []
        for poly in polys:
            outer = poly[0]
            if abs(ring_area(outer)) >= MIN_RING:
                rings.append(simplify(outer, SIMPLIFY))
        biggest = max((poly[0] for poly in polys), key=lambda r: abs(ring_area(r)))
        if not rings:
            rings.append(simplify(biggest, SIMPLIFY / 4))
        lx, ly, room = polylabel([biggest])
        if sid in ANCHOR:
            ax, ay = ANCHOR[sid]
            d = signed_distance(ax, ay, [biggest])
            assert d > 0, f"{sid} anchor override is outside the state"
            lx, ly, room = ax, ay, d
        edges = [simplify(poly[0], EDGE_SIMPLIFY) for poly in polys if abs(ring_area(poly[0])) >= EDGE_MIN_RING]
        if not edges:
            edges = [simplify(biggest, EDGE_SIMPLIFY / 4)]
        diameter = ROOM.get(sid, 2 * room)
        info[sid] = {"rings": rings, "edges": edges, "label": (lx, ly), "room": diameter}

    images, places = pack(sprites)
    os.makedirs(OUT_ASSETS, exist_ok=True)
    for name in os.listdir(OUT_ASSETS):
        if name.startswith("map-states-") and name.endswith(".png"):
            os.remove(os.path.join(OUT_ASSETS, name))  # generated files only: stale atlases
    atlas_files = []
    for k, image in enumerate(images):
        name = f"map-states-{k + 1}.png"
        image.save(os.path.join(OUT_ASSETS, name), optimize=True)
        atlas_files.append((name, image.size))
    # The scribbled sets: the same sprite sizes on the same rects.
    hatch_files = []
    for suffix, slant in HATCH_SLANTS.items():
        scribbled = {sid: scribble(sprites[sid], slant, sid) for sid in order}
        for k, image in enumerate(compose(scribbled, places)):
            assert image.size == images[k].size, "a scribbled atlas is not the flat one's size"
            name = f"map-states-{k + 1}{suffix}.png"
            image.save(os.path.join(OUT_ASSETS, name), optimize=True)
            hatch_files.append((name, image.size))
    border, _ = borders_image(border_lines, box["land"])
    border.save(os.path.join(OUT_ASSETS, "map-borders.png"), optimize=True)
    ink, ink_rect = ink_image(ink_lines)
    ink.save(os.path.join(OUT_ASSETS, "map-ink.png"), optimize=True)

    # Callout chips: one column right of the coast, north to south, evenly spaced.
    col_x, col_w = box["column"]
    usable_top = top + PAD
    usable_h = bh - 2 * PAD
    pitch = usable_h / len(LADDER)

    lines = []
    out = lines.append
    out("--!strict")
    out("-- GENERATED by scripts/mapgen/make.py: do not edit; change the script and run it")
    out("-- again (python3 scripts/mapgen/make.py). Source: us-atlas 3.0.1")
    out("-- states-albers-10m (ISC, scripts/mapgen/data/LICENSE-us-atlas), from US Census")
    out("-- Bureau cartographic boundaries (public domain). Read through Shared/UI/MapShape.")
    out("--")
    out("-- Every x is a fraction of the map box's width and every y of its height; the box")
    out("-- is shown at ASPECT. A state's sprite is the rect (x, y, w, h); in its atlas image")
    out("-- it is ImageRectOffset (ox, oy) and ImageRectSize (ow, oh). (lx, ly) is the label")
    out("-- anchor; room is the diameter of the biggest circle inside the state, in box")
    out("-- widths. rings: simplified outlines (x1, y1, x2, y2, ...), specks left out, for hit")
    out("-- tests and snapshots; edges: coarser outlines of the bigger islands, drawn in game.")
    out("-- chip: the callout rect of the small Northeast states.")
    out("")
    out("export type Rect = { x: number, y: number, w: number, h: number }")
    out("")
    out("export type Shape = {")
    out("\tid: string,")
    out("\tx: number,")
    out("\ty: number,")
    out("\tw: number,")
    out("\th: number,")
    out("\tatlas: number,")
    out("\tox: number,")
    out("\toy: number,")
    out("\tow: number,")
    out("\toh: number,")
    out("\tlx: number,")
    out("\tly: number,")
    out("\troom: number,")
    out("\trings: { { number } },")
    out("\tedges: { { number } },")
    out("\tchip: Rect?,")
    out("}")
    out("")
    out("export type Data = {")
    out("\tASPECT: number,")
    out("\tatlases: { { file: string, w: number, h: number } },")
    out("\tborders: Rect & { file: string, pw: number, ph: number },")
    out("\tink: Rect & { file: string, pw: number, ph: number },")
    out("\tlegend: Rect,")
    out("\tshapes: { Shape },")
    out("}")
    out("")
    out("-- stylua: ignore")
    out("local data: Data = {")
    out(f"\tASPECT = {fmt(ASPECT)},")
    out("\tatlases = {")
    for name, (w, h) in atlas_files:
        out(f'\t\t{{ file = "assets/map/{name}", w = {w}, h = {h} }},')
    out("\t},")
    gx0, gy0, gx1, gy1 = box["land"]
    out(
        f'\tborders = {{ file = "assets/map/map-borders.png", x = {fmt(fx(gx0))}, y = {fmt(fy(gy0))}, '
        f"w = {fmt((gx1 - gx0) / bw)}, h = {fmt((gy1 - gy0) / bh)}, pw = {border.size[0]}, ph = {border.size[1]} }},"
    )
    ix0, iy0, ix1, iy1 = ink_rect
    out(
        f'\tink = {{ file = "assets/map/map-ink.png", x = {fmt(fx(ix0))}, y = {fmt(fy(iy0))}, '
        f"w = {fmt((ix1 - ix0) / bw)}, h = {fmt((iy1 - iy0) / bh)}, pw = {ink.size[0]}, ph = {ink.size[1]} }},"
    )
    # The legend strip: under all the land (Alaska and Hawaii end above it), left of the chips.
    legend_top = gy1 + PAD / 2
    out(
        f"\tlegend = {{ x = {fmt(fx(gx0))}, y = {fmt(fy(legend_top))}, "
        f"w = {fmt((col_x - GAP - gx0) / bw)}, h = {fmt((top + bh - PAD / 2 - legend_top) / bh)} }},"
    )
    out("\tshapes = {")
    for sid in order:
        x, y, w, h = rects[sid]
        k, ox, oy = places[sid]
        sw, sh = sprites[sid].size
        lx, ly = info[sid]["label"]
        out("\t\t{")
        out(f'\t\t\tid = "{sid}",')
        out(f"\t\t\tx = {fmt(fx(x))},")
        out(f"\t\t\ty = {fmt(fy(y))},")
        out(f"\t\t\tw = {fmt(w / bw)},")
        out(f"\t\t\th = {fmt(h / bh)},")
        out(f"\t\t\tatlas = {k},")
        out(f"\t\t\tox = {ox},")
        out(f"\t\t\toy = {oy},")
        out(f"\t\t\tow = {sw},")
        out(f"\t\t\toh = {sh},")
        out(f"\t\t\tlx = {fmt(fx(lx))},")
        out(f"\t\t\tly = {fmt(fy(ly))},")
        out(f"\t\t\troom = {fmt(info[sid]['room'] / bw)},")
        out("\t\t\trings = {")
        for ring in info[sid]["rings"]:
            flat = ", ".join(f"{fmt(fx(px))}, {fmt(fy(py))}" for px, py in ring)
            out(f"\t\t\t\t{{ {flat} }},")
        out("\t\t\t},")
        out("\t\t\tedges = {")
        for ring in info[sid]["edges"]:
            flat = ", ".join(f"{fmt(fx(px))}, {fmt(fy(py))}" for px, py in ring)
            out(f"\t\t\t\t{{ {flat} }},")
        out("\t\t\t},")
        if sid in LADDER:
            i = LADDER.index(sid)
            cy = usable_top + pitch * i
            out(
                f"\t\t\tchip = {{ x = {fmt(fx(col_x))}, y = {fmt(fy(cy))}, "
                f"w = {fmt(col_w / bw)}, h = {fmt(pitch / bh)} }},"
            )
        out("\t\t},")
    out("\t},")
    out("}")
    out("")
    out("return data")
    with open(OUT_LUAU, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    formatter = shutil.which("stylua")
    if formatter:
        subprocess.run([formatter, OUT_LUAU], check=True, cwd=ROOT)
    else:
        print("stylua not on PATH: run `stylua src/shared/UI/MapShapeData.luau` before committing")

    print(f"box {bw:.1f} x {bh:.1f} units; phone scale {PHONE_WIDTH / bw:.3f} px/unit")
    for name, size in atlas_files:
        print(f"  assets/map/{name}  {size[0]}x{size[1]}")
    for name, size in hatch_files:
        print(f"  assets/map/{name}  {size[0]}x{size[1]}")
    print(f"  assets/map/map-borders.png  {border.size[0]}x{border.size[1]}")
    print(f"  assets/map/map-ink.png  {ink.size[0]}x{ink.size[1]}")
    narrow = sorted(
        (info[s]["room"] * PHONE_WIDTH / bw, s) for s in order if s not in LADDER
    )
    print("  roomiest-circle diameter at phone width (px), smallest first:")
    print("   ", ", ".join(f"{s} {d:.0f}" for d, s in narrow[:14]))


if __name__ == "__main__":
    main()
