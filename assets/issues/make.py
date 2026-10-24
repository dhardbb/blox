"""Draws the eight issue symbols (docs/DESIGN.md D-076).

Run from the repository root:  python3 assets/issues/make.py [--preview DIR]
Needs Pillow (PIL; a user install is fine, so no -I). Writes, next to this
script, one 256x256 PNG per issue in Sim/Issues.luau, named after the issue in
lower case (jobs.png, health.png, ...): a white symbol on transparent, drawn
8x larger and scaled down for smooth edges. The game tints them with
ImageColor3 (Kit.issueIcon).

They are drawn on the same 24-unit grid as the Lucide UI icons (assets/icons),
with round caps and joins, but a heavier line (2.5 units, not 2) and a filled
core in each, so they still read at 16 px on the map:

  jobs         a briefcase with a clasp band
  health       a heart with a pulse line cut through it (no cross emblem)
  schools      a graduation cap with a tassel
  environment  a leaf with a vein and a stem
  safety       a shield with a check mark
  transit      a bus seen from the front
  technology   a microchip: a square with a solid core and two pins a side
  farms        a stalk of wheat

All original drawings: no logos, flags, party or campaign symbols.
--preview DIR also writes DIR/issues-preview.png: every symbol at 16, 20, 24,
32 and 48 px, white and tinted, on the game's navy.
"""

from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = 256  # px, the shipped size
SS = 8  # supersampling factor
W = OUT * SS
U = W / 24  # px per grid unit
LINE = 2.5  # units, the stroke width

Point = "tuple[float, float]"

NAMES = ("jobs", "health", "schools", "environment", "safety", "transit", "technology", "farms")


# ---------------------------------------------------------------- geometry (grid units)


def px(points: list[Point]) -> list[Point]:
    return [(x * U, y * U) for x, y in points]


def cubic(p0: Point, p1: Point, p2: Point, p3: Point, n: int = 32) -> list[Point]:
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


def arc(cx: float, cy: float, r: float, a0: float, a1: float, n: int = 32) -> list[Point]:
    """Points on a circle from angle a0 to a1 (degrees, y down, 0 = +x)."""
    return [
        (cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
        for i in range(n + 1)
    ]


def ellipse(cx: float, cy: float, rx: float, ry: float, angle: float, n: int = 48) -> list[Point]:
    """An ellipse turned by `angle` degrees, as a polygon."""
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        out.append((cx + x * c - y * s, cy + x * s + y * c))
    return out


def rounded_rect(x0: float, y0: float, x1: float, y1: float, r: float) -> list[Point]:
    pts: list[Point] = []
    pts += arc(x1 - r, y0 + r, r, -90, 0, 12)
    pts += arc(x1 - r, y1 - r, r, 0, 90, 12)
    pts += arc(x0 + r, y1 - r, r, 90, 180, 12)
    pts += arc(x0 + r, y0 + r, r, 180, 270, 12)
    return pts


# ---------------------------------------------------------------- pen


class Pen:
    """Draws on an L mask in grid units: 255 paints, 0 cuts."""

    def __init__(self) -> None:
        self.mask = Image.new("L", (W, W), 0)
        self.draw = ImageDraw.Draw(self.mask)

    def fill(self, points: list[Point], on: bool = True) -> None:
        self.draw.polygon(px(points), fill=255 if on else 0)

    def dot(self, x: float, y: float, r: float, on: bool = True) -> None:
        self.draw.ellipse(((x - r) * U, (y - r) * U, (x + r) * U, (y + r) * U), fill=255 if on else 0)

    def line(self, points: list[Point], width: float = LINE, on: bool = True, closed: bool = False) -> None:
        """A polyline with round caps and joins."""
        pts = list(points) + ([points[0]] if closed else [])
        value = 255 if on else 0
        self.draw.line(px(pts), fill=value, width=round(width * U), joint="curve")
        for x, y in pts:
            self.dot(x, y, width / 2, on)

    def image(self) -> Image.Image:
        small = self.mask.resize((OUT, OUT), Image.Resampling.LANCZOS)
        out = Image.new("RGBA", (OUT, OUT), (255, 255, 255, 0))
        out.putalpha(small)
        return out


# ---------------------------------------------------------------- the symbols


def jobs(p: Pen) -> None:
    # The handle, then the case, then a band across it with a clasp.
    p.line([(8.5, 6.5), (8.5, 4.8)] + arc(10.2, 4.8, 1.7, 180, 270, 8) + arc(13.8, 4.8, 1.7, 270, 360, 8) + [(15.5, 6.5)])
    p.line(rounded_rect(2.5, 6.5, 21.5, 20.5, 2.6), closed=True)
    p.line([(2.5, 12.6), (21.5, 12.6)], width=2.0)
    p.fill(rounded_rect(10.0, 10.6, 14.0, 15.4, 1.0))


def heart_outline() -> list[Point]:
    pts: list[Point] = [(12, 21.0)]
    pts += cubic((12, 21.0), (6.0, 16.6), (1.6, 13.0), (1.9, 8.2))
    pts += cubic((1.9, 8.2), (2.2, 3.4), (8.6, 1.6), (12, 6.4))
    pts += cubic((12, 6.4), (15.4, 1.6), (21.8, 3.4), (22.1, 8.2))
    pts += cubic((22.1, 8.2), (22.4, 13.0), (18.0, 16.6), (12, 21.0))
    return pts


def health(p: Pen) -> None:
    # A solid heart with a pulse line cut through it.
    p.fill(heart_outline())
    pulse = [(0.0, 11.6), (7.0, 11.6), (9.0, 8.4), (12.0, 15.4), (14.8, 9.0), (16.4, 11.6), (24.0, 11.6)]
    p.line(pulse, width=1.9, on=False)


def schools(p: Pen) -> None:
    # A mortarboard (solid), the cap under it, and a tassel on the right.
    p.fill([(12, 3.2), (23.2, 8.6), (12, 14.0), (0.8, 8.6)])
    p.line([(5.8, 11.6), (5.8, 16.2)] + cubic((5.8, 16.2), (8.0, 19.6), (16.0, 19.6), (18.2, 16.2)) + [(18.2, 11.6)])
    p.line([(21.2, 9.4), (21.2, 16.0)], width=2.0)
    p.dot(21.2, 17.3, 1.5)


def environment(p: Pen) -> None:
    # A solid leaf pointing up and right, its vein cut out, and a stem.
    tip, base = (20.6, 3.4), (5.0, 19.0)
    leaf = [base]
    leaf += cubic(base, (0.6, 9.6), (9.0, 2.6), tip)
    leaf += cubic(tip, (21.4, 11.0), (14.4, 23.4), base)
    p.fill(leaf)
    p.line([(7.2, 16.8), (14.6, 9.4)], width=1.7, on=False)
    p.line([(5.6, 18.4), (2.8, 21.2)], width=2.4)


def safety(p: Pen) -> None:
    # A shield outline with a check mark inside.
    shield: list[Point] = [(12, 2.4)]
    shield += cubic((12, 2.4), (14.6, 4.4), (17.4, 5.2), (20.2, 5.4))
    shield += [(20.2, 11.2)]
    shield += cubic((20.2, 11.2), (20.2, 16.4), (16.6, 19.6), (12, 21.6))
    shield += cubic((12, 21.6), (7.4, 19.6), (3.8, 16.4), (3.8, 11.2))
    shield += [(3.8, 5.4)]
    shield += cubic((3.8, 5.4), (6.6, 5.2), (9.4, 4.4), (12, 2.4))
    p.line(shield, closed=True)
    p.line([(8.2, 12.0), (11.0, 14.8), (16.0, 9.2)])


def transit(p: Pen) -> None:
    # A bus from the front: body, solid windshield, headlights, wheels, mirrors.
    p.line(rounded_rect(4.4, 2.6, 19.6, 18.6, 2.6), closed=True)
    p.fill(rounded_rect(6.6, 5.4, 17.4, 11.4, 1.0))
    p.dot(8.4, 15.0, 1.35)
    p.dot(15.6, 15.0, 1.35)
    p.line([(7.6, 18.8), (7.6, 21.2)], width=2.8)
    p.line([(16.4, 18.8), (16.4, 21.2)], width=2.8)
    p.line([(4.4, 7.0), (2.2, 7.0), (2.2, 10.4)], width=2.0)
    p.line([(19.6, 7.0), (21.8, 7.0), (21.8, 10.4)], width=2.0)


def technology(p: Pen) -> None:
    # A chip: the package, a solid core, two pins on each side.
    p.line(rounded_rect(5.0, 5.0, 19.0, 19.0, 2.0), closed=True)
    p.fill(rounded_rect(9.0, 9.0, 15.0, 15.0, 1.0))
    for k in (9.4, 14.6):
        p.line([(k, 1.6), (k, 4.0)], width=2.2)
        p.line([(k, 20.0), (k, 22.4)], width=2.2)
        p.line([(1.6, k), (4.0, k)], width=2.2)
        p.line([(20.0, k), (22.4, k)], width=2.2)


def farms(p: Pen) -> None:
    # A wheat stalk: a stem, three pairs of solid grains and one on top.
    p.line([(12, 22.0), (12, 7.0)], width=2.0)
    for y in (17.0, 12.6, 8.2):
        p.fill(ellipse(8.8, y, 3.3, 1.9, 40))
        p.fill(ellipse(15.2, y, 3.3, 1.9, -40))
    p.fill(ellipse(12, 3.7, 1.8, 3.0, 0))


DRAW = {
    "jobs": jobs,
    "health": health,
    "schools": schools,
    "environment": environment,
    "safety": safety,
    "transit": transit,
    "technology": technology,
    "farms": farms,
}


def render(name: str) -> Image.Image:
    pen = Pen()
    DRAW[name](pen)
    return pen.image()


# ---------------------------------------------------------------- preview


NAVY = (11, 16, 34)
SURFACE = (22, 30, 55)
TINTS = [(240, 243, 250), (34, 98, 228), (246, 190, 8)]


def tinted(icon: Image.Image, size: int, color: tuple[int, int, int]) -> Image.Image:
    small = icon.resize((size, size), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (size, size), color + (0,))
    out.putalpha(small.getchannel("A"))
    return out


def preview(icons: dict[str, Image.Image], path: str) -> None:
    sizes = (16, 20, 24, 32, 48)
    cell = 56
    sheet = Image.new("RGB", (cell * len(sizes) * len(TINTS) + 16, cell * len(icons) + 16), NAVY)
    for row, name in enumerate(NAMES):
        for t, tint in enumerate(TINTS):
            for k, size in enumerate(sizes):
                x = 8 + (t * len(sizes) + k) * cell + (cell - size) // 2
                y = 8 + row * cell + (cell - size) // 2
                small = tinted(icons[name], size, tint)
                sheet.paste(small, (x, y), small)
    sheet.save(path)
    print(f"wrote {path}")


def main() -> None:
    icons = {}
    for name in NAMES:
        icons[name] = render(name)
        path = os.path.join(HERE, f"{name}.png")
        icons[name].save(path)
        print(f"wrote {os.path.relpath(path)}")
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        preview(icons, os.path.join(out, "issues-preview.png"))


if __name__ == "__main__":
    main()
