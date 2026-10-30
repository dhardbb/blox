"""Redraws the game's icons as marker doodles (docs/proposals/whiteboard.md).

Run from the repository root:  python3 assets/icons/make.py [--sheet PATH]
Needs Pillow (PIL). Reads each Lucide SVG in assets/icons/src/ (unchanged,
ISC license, docs/CREDITS.md), follows its paths, and draws them again as a
hand with a marker would: every line wobbles a little, closed shapes overshoot
where they meet, circles are loose loops, and each part sits a hair off its
place. The wobble is seeded by the icon's name, so a rerun draws the same
image. Writes <name>.png next to this script: 256x256, white on transparent
(the game tints it with ImageColor3), the same names and sizes as before.

The stroke is a bit heavier than Lucide's (2.2 of 24 instead of 2) and the
wobble small (about 0.25 of 24), so each icon still reads at 20 to 24 px.
--sheet PATH also writes a preview: each icon at 256, 48, 24 and 20 px in ink
on the board color.
"""

from __future__ import annotations

import math
import os
import random
import re
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "ui"))

import marker  # noqa: E402  (assets/ui/marker.py)

SIZE = 256  # px, each PNG
K = 4  # supersampling
UNIT = SIZE * K / 24  # Lucide's 24-unit view box
WIDTH = 2.2  # units, the marker's line
AMP = 0.26  # units, how far a line wobbles
WAVE = 5.0  # units between wobbles
OVERSHOOT = 0.9  # units a closed shape runs past its start
NUDGE = 0.22  # units each part may sit off its place
TURN = 2.0  # degrees each part may turn

Point = tuple[float, float]

NUMBER = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def _cubic(p0, p1, p2, p3, n=16):
    out = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        out.append(
            (
                u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
            )
        )
    return out


def _arc(p0, rx, ry, phi_deg, large, sweep, p1):
    """SVG elliptical arc (endpoint form) as points, per the SVG spec's F.6.5."""
    if rx == 0 or ry == 0:
        return [p1]
    phi = math.radians(phi_deg)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1, y1 = cp * dx + sp * dy, -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    co = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large == sweep:
        co = -co
    cx1, cy1 = co * rx * y1 / ry, -co * ry * x1 / rx
    cx = cp * cx1 - sp * cy1 + (p0[0] + p1[0]) / 2
    cy = sp * cx1 + cp * cy1 + (p0[1] + p1[1]) / 2

    def angle(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    dt = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if not sweep and dt > 0:
        dt -= math.tau
    elif sweep and dt < 0:
        dt += math.tau
    n = max(4, int(abs(dt) / math.tau * 48))
    out = []
    for i in range(1, n + 1):
        t = t1 + dt * i / n
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        out.append((cp * ex - sp * ey + cx, sp * ex + cp * ey + cy))
    return out


def parse_path(d: str) -> list[tuple[list[Point], bool]]:
    """SVG path data -> [(points, closed)] in view-box units."""
    tokens = TOKEN.findall(d)
    i = 0
    cmd = None
    cur = (0.0, 0.0)
    start = cur
    last_ctrl = None
    subpaths: list[tuple[list[Point], bool]] = []
    pts: list[Point] = []

    def num():
        nonlocal i
        v = float(tokens[i])
        i += 1
        return v

    def flush(closed):
        nonlocal pts
        if len(pts) > 1:
            subpaths.append((pts, closed))
        pts = []

    while i < len(tokens):
        if re.fullmatch(r"[A-Za-z]", tokens[i]):
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                if pts:
                    flush(True)
                cur = start
                last_ctrl = None
                continue
        rel = cmd.islower()
        ox, oy = cur if rel else (0.0, 0.0)
        c = cmd.upper()
        if c == "M":
            flush(False)
            cur = (ox + num(), oy + num())
            start = cur
            pts = [cur]
            cmd = "l" if rel else "L"  # later pairs are lines
            last_ctrl = None
        elif c == "L":
            cur = (ox + num(), oy + num())
            pts.append(cur)
            last_ctrl = None
        elif c == "H":
            cur = ((cur[0] if rel else 0.0) + num(), cur[1])
            pts.append(cur)
            last_ctrl = None
        elif c == "V":
            cur = (cur[0], (cur[1] if rel else 0.0) + num())
            pts.append(cur)
            last_ctrl = None
        elif c == "C":
            p1 = (ox + num(), oy + num())
            p2 = (ox + num(), oy + num())
            p3 = (ox + num(), oy + num())
            pts.extend(_cubic(cur, p1, p2, p3))
            cur, last_ctrl = p3, p2
        elif c == "S":
            p1 = (2 * cur[0] - last_ctrl[0], 2 * cur[1] - last_ctrl[1]) if last_ctrl else cur
            p2 = (ox + num(), oy + num())
            p3 = (ox + num(), oy + num())
            pts.extend(_cubic(cur, p1, p2, p3))
            cur, last_ctrl = p3, p2
        elif c == "A":
            rx, ry, phi = num(), num(), num()
            large, sweep = int(num()), int(num())
            p = (ox + num(), oy + num())
            pts.extend(_arc(cur, rx, ry, phi, large, sweep, p))
            cur = p
            last_ctrl = None
        else:
            raise ValueError(f"unsupported path command {cmd}")
    flush(False)
    return subpaths


def _attrs(tag: str) -> dict[str, str]:
    return dict(re.findall(r'([\w-]+)="([^"]*)"', tag))


def parse_svg(text: str) -> list[tuple[list[Point], bool]]:
    """Every drawn element of a Lucide SVG as [(points, closed)]. A circle comes
    back as ([center, (r, r)], "circle") so it can be drawn as a loop."""
    parts = []
    for tag in re.findall(r"<(path|circle|rect|polyline|line)\b([^>]*)/?>", text):
        kind, rest = tag
        a = _attrs(rest)
        if kind == "path":
            parts.extend(parse_path(a["d"]))
        elif kind == "circle":
            cx, cy, r = float(a["cx"]), float(a["cy"]), float(a["r"])
            parts.append(([(cx, cy), (r, r)], "circle"))
        elif kind == "rect":
            x, y = float(a.get("x", 0)), float(a.get("y", 0))
            w, h = float(a["width"]), float(a["height"])
            r = float(a.get("rx", 0))
            pts = []
            for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
                for j in range(7):
                    t = math.radians(a0 + 90 * j / 6)
                    pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
            parts.append((pts, True))
        elif kind == "polyline":
            nums = [float(v) for v in NUMBER.findall(a["points"])]
            parts.append((list(zip(nums[::2], nums[1::2])), False))
        elif kind == "line":
            parts.append(([(float(a["x1"]), float(a["y1"])), (float(a["x2"]), float(a["y2"]))], False))
    return parts


def _nudge(pts: list[Point], rng: random.Random) -> list[Point]:
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    t = math.radians(rng.uniform(-TURN, TURN))
    dx, dy = rng.uniform(-NUDGE, NUDGE), rng.uniform(-NUDGE, NUDGE)
    c, s = math.cos(t), math.sin(t)
    return [(cx + (x - cx) * c - (y - cy) * s + dx, cy + (x - cx) * s + (y - cy) * c + dy) for x, y in pts]


def _close(pts: list[Point]) -> list[Point]:
    """A closed shape drawn in one go: back to the start and a little past it."""
    ring = pts + [pts[0]]
    extra = [ring[0]]
    walked = 0.0
    for a, b in zip(ring, ring[1:]):
        walked += math.hypot(b[0] - a[0], b[1] - a[1])
        extra.append(b)
        if walked >= OVERSHOOT:
            break
    return ring + extra[1:]


def doodle(name: str, text: str) -> Image.Image:
    rng = random.Random(f"icon:{name}")
    image = Image.new("L", (SIZE * K, SIZE * K), 0)
    draw = ImageDraw.Draw(image)
    for pts, closed in parse_svg(text):
        if closed == "circle":
            (cx, cy), (r, _) = pts
            cx += rng.uniform(-NUDGE, NUDGE)
            cy += rng.uniform(-NUDGE, NUDGE)
            line = marker.loop(cx, cy, r, r * rng.uniform(0.95, 1.0), rng, 1.07, rng.uniform(-0.3, 0.3))
        else:
            pts = _nudge(pts, rng)
            if closed:
                line = _close(pts)
            else:
                line = marker.extend(pts, 0.15, 0.25)
        line = marker.wobble(marker.resample(line, 0.25), rng, AMP, WAVE)
        marker.stroke(draw, [(x * UNIT, y * UNIT) for x, y in line], WIDTH * UNIT, 255, taper=0.15)
    mask = image.resize((SIZE, SIZE), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def names() -> list[str]:
    return sorted(f[:-4] for f in os.listdir(os.path.join(HERE, "src")) if f.endswith(".svg"))


def sheet(images: dict[str, Image.Image], path: str) -> None:
    board, ink = (243, 241, 234), (29, 29, 31)
    sizes = (128, 48, 24, 20)
    cell = sum(sizes) + 16 * len(sizes)
    out = Image.new("RGB", (cell * 2 + 16, (128 + 16) * ((len(images) + 1) // 2) + 16), board)
    for i, (name, img) in enumerate(images.items()):
        x0 = 16 + (i % 2) * cell
        y0 = 16 + (i // 2) * (128 + 16)
        x = x0
        for s in sizes:
            small = img.resize((s, s), Image.LANCZOS)
            out.paste(Image.new("RGB", (s, s), ink), (x, y0), small)
            x += s + 16
    out.save(path)


def main() -> None:
    images = {}
    for name in names():
        with open(os.path.join(HERE, "src", f"{name}.svg"), encoding="utf-8") as f:
            images[name] = doodle(name, f.read())
        path = os.path.join(HERE, f"{name}.png")
        images[name].save(path)
        print(f"wrote {os.path.relpath(path)}")
    if "--sheet" in sys.argv:
        target = sys.argv[sys.argv.index("--sheet") + 1]
        sheet(images, target)
        print(f"wrote {target}")


if __name__ == "__main__":
    main()
