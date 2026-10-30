"""Draws the candidates' portraits (docs/DESIGN.md D-068, reskinned in D-097).

Run from the repository root:  python3 assets/portraits/make.py [--preview DIR]
Needs Pillow 11 (PIL). Writes, next to this script, one 512x512 PNG per
candidate in Sim/Candidates.luau, named by candidate id (okafor.png, ...):
a flat vector-style head-and-shoulders bust on a transparent background,
drawn 4x larger and scaled down for smooth edges. It also writes sheet.png,
a labeled contact sheet of all eight. --preview DIR writes the same sheet
without labels to DIR/portraits-preview.png.

The whiteboard look (docs/proposals/whiteboard.md) keeps these same images:
UI/Board.photo puts a face in a white instant-photo card, tilts it and tapes
it to the board at run time (assets/portraits/README.md says why). --photos
PATH writes a review sheet of that look at 48, 72 and 96 px, next to a
baked-in polaroid for comparison; nothing it draws ships.

The game shows each one inside a round plate (Kit.portrait), so every bust is
centered and fits a circle of the image's full width: the head sits in the
upper middle and the shoulders run off the bottom edge. Each sheet row shows
one portrait on a plate at 40, 80 and 160 px.

All eight are fictional people. The file names are the candidate ids, which
never change (D-097); the looks are the current display names'. Each gets its
own face, hair, outfit and a big headwear silhouette, plus a prop for the perk:
  okafor    Goldie Pennywhistle  The Fundraiser   tricorn, doubloon earrings and pendant
  calloway  Buster Cannonball    The Barnstormer  stunt helmet with goggles, epaulettes
  venkat    Mavis Glimmer        The Ad Wizard    top hat, high-collared cape, sparkles
  hale      Percy Quibble        The Debater      beret, monocle, handlebar mustache, quill
  alvarado  Opal Crumpet         The Insider      lilac beehive, cat-eye glasses, gold key
  reyes     Dash Kickflip        The Insurgent    teal-tipped spikes, sweatband, bolt pin
  strand    Esme Moonbeam        The Pollster     starry headscarf, round glasses, crystal ball
  begay     Gus Bramble          The Organizer    ranger hat, bushy beard, neckerchief, badges
"""

from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = 512  # px, the shipped size
SS = 4  # supersampling factor
W = OUT * SS
CROP = (38, 34, 436)  # x, y, side (in the 512 drawing grid) of the part that ships

Point = "tuple[float, float]"


# ---------------------------------------------------------------- geometry


def s(v: float) -> float:
    return v * SS


def sp(pts: list[Point]) -> list[Point]:
    return [(x * SS, y * SS) for x, y in pts]


def cubic(p0: Point, p1: Point, p2: Point, p3: Point, n: int = 28) -> list[Point]:
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


def path(start: Point, *segs) -> list[Point]:
    """A closed outline: segments are (x, y) lines or ((c1), (c2), (end)) cubics."""
    pts = [start]
    for seg in segs:
        if isinstance(seg[0], tuple):
            pts.extend(cubic(pts[-1], seg[0], seg[1], seg[2]))
        else:
            pts.append(seg)
    return pts


def mirror(pts: list[Point], cx: float = 256) -> list[Point]:
    return [(2 * cx - x, y) for x, y in pts]


def symmetric(half: list[Point], cx: float = 256) -> list[Point]:
    """`half` runs down the left side (top to bottom); returns the whole outline."""
    return half + list(reversed(mirror(half, cx)))


def head_outline(cx, cy, rx, ry, jaw=0.0, taper=0.0, n=120) -> list[Point]:
    """An egg: an ellipse whose lower half squares off (`jaw`) or narrows (`taper`)."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, sn = math.cos(t), math.sin(t)
        x, y = c, sn
        if sn > 0:
            e = 2 / (2 + jaw * 2.5)
            x = math.copysign(abs(c) ** e, c)
            y = math.copysign(abs(sn) ** e, sn) * (1 - 0.06 * jaw)
            x *= 1 - taper * sn**2
        pts.append((cx + rx * x, cy + ry * y))
    return pts


def thick(a: Point, b: Point, w: float) -> list[Point]:
    dx, dy = b[0] - a[0], b[1] - a[1]
    d = math.hypot(dx, dy) or 1
    nx, ny = -dy / d * w / 2, dx / d * w / 2
    return [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny), (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]


def arc_pts(cx, cy, rx, ry, a0, a1, n=40) -> list[Point]:
    return [
        (cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
        for i in range(n + 1)
    ]


# ---------------------------------------------------------------- color


def shade(c, k: float):
    """k < 1 darkens, k > 1 lightens toward white."""
    if k <= 1:
        return tuple(int(v * k) for v in c[:3])
    t = k - 1
    return tuple(int(v + (255 - v) * t) for v in c[:3])


def mix(a, b, t: float):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ---------------------------------------------------------------- canvas


class Canvas:
    def __init__(self):
        self.img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    def layer(self) -> Image.Image:
        return Image.new("RGBA", (W, W), (0, 0, 0, 0))

    def put(self, layer: Image.Image, clip: Image.Image | None = None, alpha: float = 1.0):
        if clip is not None or alpha < 1:
            a = layer.getchannel("A")
            if clip is not None:
                a = ImageChops.multiply(a, clip)
            if alpha < 1:
                a = a.point(lambda v: int(v * alpha))
            layer.putalpha(a)
        self.img.alpha_composite(layer)

    def poly(self, pts, fill, clip=None, alpha=1.0):
        layer = self.layer()
        ImageDraw.Draw(layer).polygon(sp(pts), fill=fill)
        self.put(layer, clip, alpha)

    def ellipse(self, box, fill, clip=None, alpha=1.0):
        layer = self.layer()
        ImageDraw.Draw(layer).ellipse([s(v) for v in box], fill=fill)
        self.put(layer, clip, alpha)

    def line(self, pts, fill, width, clip=None, alpha=1.0, caps=True):
        layer = self.layer()
        d = ImageDraw.Draw(layer)
        d.line(sp(pts), fill=fill, width=int(s(width)), joint="curve")
        if caps:
            r = s(width) / 2
            for x, y in (pts[0], pts[-1]):
                d.ellipse((s(x) - r, s(y) - r, s(x) + r, s(y) + r), fill=fill)
        self.put(layer, clip, alpha)

    def mask(self, pts) -> Image.Image:
        m = Image.new("L", (W, W), 0)
        ImageDraw.Draw(m).polygon(sp(pts), fill=255)
        return m

    def ellipse_mask(self, box) -> Image.Image:
        m = Image.new("L", (W, W), 0)
        ImageDraw.Draw(m).ellipse([s(v) for v in box], fill=255)
        return m

    def soft_shadow(self, pts, fill, clip, blur=6, alpha=1.0):
        layer = self.layer()
        ImageDraw.Draw(layer).polygon(sp(pts), fill=fill)
        layer = layer.filter(ImageFilter.GaussianBlur(s(blur)))
        self.put(layer, clip, alpha)

    def result(self) -> Image.Image:
        # Zoom in on the bust (the art is laid out on a 512 grid with room to
        # spare), so the face fills the plate and still reads at 40 px.
        x0, y0, side = CROP
        box = (int(s(x0)), int(s(y0)), int(s(x0 + side)), int(s(y0 + side)))
        return self.img.crop(box).resize((OUT, OUT), Image.Resampling.LANCZOS)


# ---------------------------------------------------------------- shared parts

CX = 256
INK = (38, 30, 36)  # eyes, lashes
MOUTH = (122, 42, 54)
TEETH = (255, 252, 246)
WHITE = (255, 255, 255)


class Face:
    """The head's placement, so features can be laid out relative to it."""

    def __init__(self, cy=216, rx=92, ry=112, jaw=0.0, taper=0.0):
        self.cy, self.rx, self.ry, self.jaw, self.taper = cy, rx, ry, jaw, taper
        self.outline = head_outline(CX, cy, rx, ry, jaw, taper)

    @property
    def top(self):
        return self.cy - self.ry

    @property
    def chin(self):
        return self.cy + self.ry * (1 - 0.06 * self.jaw)

    def eye_y(self):
        return self.cy + self.ry * 0.06

    def eye_dx(self):
        return self.rx * 0.40


def torso(c: Canvas, top: float, width: float, color, shoulder_drop=42):
    """Shoulders: a wide rounded bell from the neck down past the bottom edge."""
    half_neck = 44
    half = [
        (CX - half_neck, top),
        ((CX - half_neck - 40, top + 4), (CX - width / 2 + 10, top + shoulder_drop - 26), (CX - width / 2, top + shoulder_drop + 20)),
        (CX - width / 2 - 10, 530),
    ]
    pts = symmetric(path(*half))
    c.poly(pts, color)
    # Shade toward the outer edges of the shoulders (lit from the front).
    clip = c.mask(pts)
    inner = [(CX + (x - CX) * 0.86, y + 6) for x, y in pts]
    rim = ImageChops.subtract(clip, c.mask(inner)).filter(ImageFilter.GaussianBlur(s(4)))
    layer = c.layer()
    ImageDraw.Draw(layer).rectangle((0, 0, W, W), fill=shade(color, 0.8))
    c.put(layer, ImageChops.multiply(rim, clip), alpha=0.7)
    return pts


def neck(c: Canvas, face: Face, skin, width=66, bottom=392):
    top = face.chin - 40
    pts = [(CX - width / 2, top), (CX + width / 2, top), (CX + width / 2 + 4, bottom), (CX - width / 2 - 4, bottom)]
    c.poly(pts, skin)
    # The chin's shadow on the neck.
    shadow = head_outline(CX, face.cy + 18, face.rx * 0.9, face.ry, face.jaw, face.taper)
    c.poly(shadow, shade(skin, 0.78), clip=c.mask(pts))


def ears(c: Canvas, face: Face, skin, y_off=0.0):
    y = face.eye_y() + 10 + y_off
    for side in (-1, 1):
        x = CX + side * (face.rx - 6)
        c.ellipse((x - 20, y - 28, x + 20, y + 28), skin)
        c.ellipse((x - 9 + side * 3, y - 14, x + 9 + side * 3, y + 14), shade(skin, 0.82))


def head(c: Canvas, face: Face, skin):
    c.poly(face.outline, skin)
    clip = c.mask(face.outline)
    # A soft shade down one side, so the face has a lit side (flat, two tones).
    lit = head_outline(CX - face.rx * 0.16, face.cy - 6, face.rx * 0.98, face.ry * 1.02, face.jaw, face.taper)
    m = ImageChops.subtract(clip, c.mask(lit)).filter(ImageFilter.GaussianBlur(s(2)))
    layer = c.layer()
    ImageDraw.Draw(layer).rectangle((0, 0, W, W), fill=shade(skin, 0.86))
    c.put(layer, ImageChops.multiply(m, clip), alpha=0.8)
    return clip


def eyes(c: Canvas, face: Face, look=0.0, size=1.0, lashes=False, lid=None):
    y = face.eye_y()
    dx = face.eye_dx()
    for side in (-1, 1):
        x = CX + side * dx
        rw, rh = 11 * size, 14 * size
        c.ellipse((x - rw + look, y - rh, x + rw + look, y + rh), INK)
        c.ellipse((x - 4 * size + look + 3, y - 8 * size, x + 2 * size + look + 3, y - 2 * size), WHITE)
        if lid is not None:
            # A relaxed upper lid in skin color over the top of the eye.
            c.ellipse((x - rw - 3, y - rh - 10, x + rw + 3, y - rh * 0.25), lid)
        if lashes:
            c.line([(x + side * (rw - 2), y - rh * 0.6), (x + side * (rw + 7), y - rh * 0.95)], INK, 4.5)


def brows(c: Canvas, face: Face, color, lift=(0, 0), width=9, tilt=0.0, length=1.0):
    y = face.eye_y() - 34
    dx = face.eye_dx()
    for k, side in enumerate((-1, 1)):
        x = CX + side * dx
        ly = y - lift[k]
        half = 22 * length
        pts = cubic(
            (x - side * half, ly + 6 + side * tilt * -1),
            (x - side * half * 0.4, ly - 4),
            (x + side * half * 0.4, ly - 6),
            (x + side * half, ly + 2 + side * tilt),
            12,
        )
        c.line([(x - side * half, ly + 6)] + pts, color, width)


def nose(c: Canvas, face: Face, skin, size=1.0):
    y = face.eye_y() + 40 * size
    col = shade(skin, 0.8)
    c.ellipse((CX - 13 * size, y - 9 * size, CX + 13 * size, y + 9 * size), col)
    c.ellipse((CX - 10 * size, y - 14 * size, CX + 6 * size, y + 2 * size), shade(skin, 1.06), alpha=0.6)


def smile(c: Canvas, face: Face, width=44, open_=True, y_off=0.0, tilt=0.0, lips=None):
    y = face.eye_y() + 72 + y_off
    if open_:
        top = [(CX - width / 2, y - 2 - tilt), (CX + width / 2, y - 2 + tilt)]
        pts = [top[0]] + cubic(top[0], (CX - width / 2 + 6, y + 30), (CX + width / 2 - 6, y + 30), top[1]) + [top[1]]
        c.poly(pts, MOUTH)
        clip = c.mask(pts)
        c.poly([(CX - width / 2, y - 6), (CX + width / 2, y - 6), (CX + width / 2, y + 7), (CX - width / 2, y + 7)], TEETH, clip=clip)
        c.ellipse((CX - width / 4, y + 12, CX + width / 4, y + 34), (214, 96, 104), clip=clip)
        if lips:
            c.line([top[0], (CX, y - 4), top[1]], lips, 4)
    else:
        pts = cubic((CX - width / 2, y - tilt), (CX - width / 4, y + 14), (CX + width / 4, y + 14), (CX + width / 2, y - 4 + tilt), 16)
        c.line([(CX - width / 2, y - tilt)] + pts, lips or MOUTH, 7)


def cheeks(c: Canvas, face: Face, color=(240, 120, 120), alpha=0.28):
    y = face.eye_y() + 44
    dx = face.eye_dx() + 14
    for side in (-1, 1):
        x = CX + side * dx
        c.ellipse((x - 18, y - 10, x + 18, y + 10), color, alpha=alpha)


def collar_v(c: Canvas, top: float, color, depth=70, width=40):
    pts = [(CX - width, top - 4), (CX + width, top - 4), (CX, top + depth)]
    c.poly(pts, color)


def lapels(c: Canvas, top: float, jacket, inner, depth=118, spread=74):
    """A jacket opening: the inner shirt as a V and two lapel flaps."""
    v = [(CX - 46, top - 6), (CX + 46, top - 6), (CX + 16, top + depth), (CX - 16, top + depth)]
    c.poly([(CX - 44, top - 6), (CX + 44, top - 6), (CX, top + depth)], inner)
    edge = shade(jacket, 0.78)
    for side in (-1, 1):
        flap = [
            (CX + side * 46, top - 8),
            (CX + side * 12, top + depth - 6),
            (CX + side * 28, top + depth + 26),
            (CX + side * (spread + 20), top + 34),
        ]
        c.poly(flap, edge)
        c.poly([(x - side * 3, y - 3) for x, y in flap], jacket)
    return v


def star_pts(x: float, y: float, outer: float, inner: float, points: int = 5, turn: float = -90) -> list[Point]:
    pts = []
    for k in range(points * 2):
        r = outer if k % 2 == 0 else inner
        a = math.radians(turn + k * 180 / points)
        pts.append((x + r * math.cos(a), y + r * math.sin(a)))
    return pts


def sparkle(c: Canvas, x: float, y: float, r: float, color):
    """A four-point twinkle."""
    c.poly(star_pts(x, y, r, r * 0.28, 4), color)


def rot_ellipse(cx, cy, rx, ry, angle, n=72) -> list[Point]:
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return pts


def ring(c: Canvas, x, y, r, color, width, clip=None, alpha=1.0):
    c.line(arc_pts(x, y, r, r, 0, 360, 48), color, width, clip=clip, alpha=alpha, caps=False)


def coin(c: Canvas, x, y, r):
    c.ellipse((x - r, y - r, x + r, y + r), (186, 126, 26))
    c.ellipse((x - r * 0.78, y - r * 0.78, x + r * 0.78, y + r * 0.78), (255, 214, 92))
    c.poly(star_pts(x, y, r * 0.42, r * 0.18), (214, 158, 40))


GOLD = (244, 194, 64)
GOLD_DARK = (186, 126, 26)


# ---------------------------------------------------------------- the eight


def okafor() -> Image.Image:
    """Goldie Pennywhistle, The Fundraiser: a gold-trimmed tricorn, locs, doubloons."""
    c = Canvas()
    skin = (122, 74, 50)
    hair = (40, 28, 30)
    face = Face(cy=236, rx=86, ry=104, jaw=0.15, taper=0.12)
    # Long locs behind the head and down past the shoulders.
    back = symmetric(
        path(
            (CX, 130),
            ((CX - 100, 128), (CX - 126, 190), (CX - 124, 270)),
            ((CX - 122, 330), (CX - 130, 390), (CX - 122, 440)),
            (CX - 50, 440),
        )
    )
    c.poly(back, hair)
    clip = c.mask(back)
    for k in range(-5, 6):
        x = CX + k * 22
        c.line([(x, 200), (x + 2, 440)], shade(hair, 1.7), 3, clip=clip, alpha=0.5, caps=False)
    coat = (34, 82, 110)  # sea-blue captain's coat
    torso(c, 382, 440, coat)
    neck(c, face, skin)
    lapels(c, 388, coat, (250, 244, 232), depth=96)
    # Gold buttons down both sides of the coat.
    for side in (-1, 1):
        for k in range(2):
            x, y = CX + side * 70, 470 + k * 32
            c.ellipse((x - 9, y - 9, x + 9, y + 9), GOLD_DARK)
            c.ellipse((x - 6, y - 6, x + 6, y + 6), GOLD)
    # A chain with a big doubloon.
    c.line(arc_pts(CX, 386, 46, 50, 10, 170, 30), GOLD, 4)
    coin(c, CX, 446, 24)
    ears(c, face, skin)
    # Doubloon earrings.
    for side in (-1, 1):
        coin(c, CX + side * (face.rx - 4), face.eye_y() + 56, 14)
    head(c, face, skin)
    crown = path(
        (CX - face.rx - 2, face.cy - 10),
        ((CX - face.rx, face.top - 30), (CX + face.rx, face.top - 30), (CX + face.rx + 2, face.cy - 10)),
        ((CX + face.rx * 0.6, face.top + 10), (CX - face.rx * 0.2, face.top + 4), (CX - face.rx - 2, face.cy - 10)),
    )
    c.poly(crown, hair)
    eyes(c, face, lashes=True, look=2)
    brows(c, face, hair, lift=(2, 8), width=8)
    nose(c, face, skin)
    cheeks(c, face, (200, 80, 80), 0.22)
    smile(c, face, width=52, lips=(96, 40, 44))
    # The tricorn: a round crown behind a brim turned up into a gold-trimmed wall.
    hat = (36, 40, 58)
    by = face.top + 36
    c.ellipse((CX - 80, by - 104, CX + 80, by - 4), hat)
    top_edge = cubic((CX - 156, by - 78), (CX - 100, by - 30), (CX - 40, by - 30), (CX, by - 44), 20) + cubic(
        (CX, by - 44), (CX + 40, by - 30), (CX + 100, by - 30), (CX + 156, by - 78), 20
    )
    bottom = cubic((CX + 156, by - 78), (CX + 130, by + 10), (CX + 60, by + 24), (CX, by + 22), 20) + cubic(
        (CX, by + 22), (CX - 60, by + 24), (CX - 130, by + 10), (CX - 156, by - 78), 20
    )
    brim = [(CX - 156, by - 78)] + top_edge + bottom
    c.poly(brim, shade(hat, 1.25))
    c.poly([(x, y + 10) for x, y in bottom], shade(hat, 0.8), clip=c.mask(brim))
    c.line([(CX - 156, by - 78)] + top_edge, GOLD, 8)
    coin(c, CX, by - 14, 20)
    return c.result()


def calloway() -> Image.Image:
    """Buster Cannonball, The Barnstormer: a striped stunt helmet, goggles, a showman's suit."""
    c = Canvas()
    skin = (240, 192, 158)
    hair = (196, 96, 46)
    face = Face(cy=244, rx=94, ry=102, jaw=0.85)
    suit = (44, 92, 196)  # royal blue
    torso(c, 384, 452, suit)
    neck(c, face, skin, width=76)
    # A white stand-up collar, a gold-buttoned front and a star on the chest.
    c.poly([(CX - 54, 378), (CX + 54, 378), (CX + 46, 408), (CX - 46, 408)], (250, 248, 240))
    c.line([(CX, 410), (CX, 530)], shade(suit, 0.75), 6, caps=False)
    for k in range(3):
        y = 432 + k * 32
        for side in (-1, 1):
            c.ellipse((CX + side * 20 - 7, y - 7, CX + side * 20 + 7, y + 7), GOLD)
    c.poly(star_pts(CX - 112, 456, 28, 12), (255, 222, 90))
    # Gold epaulettes.
    for side in (-1, 1):
        x = CX + side * 168
        c.ellipse((x - 44, 404, x + 44, 440), GOLD_DARK)
        c.ellipse((x - 40, 402, x + 40, 432), GOLD)
    ears(c, face, skin)
    head(c, face, skin)
    # Ginger sideburns.
    for side in (-1, 1):
        x = CX + side * face.rx
        c.poly([(x, face.cy - 40), (x - side * 16, face.cy - 40), (x - side * 12, face.eye_y() + 30), (x + side * 2, face.eye_y() + 24)], hair)
    for fx, fy in ((-46, 38), (-34, 46), (-54, 50), (46, 38), (34, 46), (54, 50)):
        c.ellipse((CX + fx - 3, face.eye_y() + fy - 3, CX + fx + 3, face.eye_y() + fy + 3), (198, 128, 92))
    eyes(c, face, size=1.05)
    brows(c, face, shade(hair, 0.85), lift=(12, 12), width=10)
    nose(c, face, skin, 1.1)
    cheeks(c, face)
    smile(c, face, width=68, y_off=2)
    # The stunt helmet: a white dome with flaps over the ears and a red stripe.
    helm = (222, 56, 64)
    y_flap = face.eye_y() + 26
    dome = path(
        (CX - face.rx - 12, y_flap),
        ((CX - face.rx - 18, face.top - 74), (CX + face.rx + 18, face.top - 74), (CX + face.rx + 12, y_flap)),
        (CX + face.rx - 14, y_flap),
        ((CX + face.rx - 10, face.top + 30), (CX - face.rx + 10, face.top + 30), (CX - face.rx + 14, y_flap)),
    )
    c.poly(dome, helm)
    dm = c.mask(dome)
    c.poly([(CX - 22, 0), (CX + 22, 0), (CX + 22, 400), (CX - 22, 400)], (250, 248, 240), clip=dm)
    rim = ImageChops.subtract(dm, c.mask([(CX + (x - CX) * 0.9, y + 6) for x, y in dome]))
    layer = c.layer()
    ImageDraw.Draw(layer).rectangle((0, 0, W, W), fill=shade(helm, 0.8))
    c.put(layer, rim, alpha=0.7)
    # Goggles pushed up on the helmet.
    gy = face.top + 6
    c.line([(CX - face.rx - 14, gy + 6), (CX + face.rx + 14, gy + 6)], (70, 52, 44), 12, clip=dm, caps=False)
    for side in (-1, 1):
        x = CX + side * 38
        c.ellipse((x - 32, gy - 30, x + 32, gy + 30), (150, 104, 44))
        c.ellipse((x - 23, gy - 21, x + 23, gy + 21), (140, 210, 236))
        c.ellipse((x - 14, gy - 15, x - 2, gy - 5), WHITE, alpha=0.8)
    return c.result()


def venkat() -> Image.Image:
    """Mavis Glimmer, The Ad Wizard: a tall top hat, a cape with a high collar, sparkles."""
    c = Canvas()
    skin = (184, 120, 84)
    hair = (36, 26, 30)
    face = Face(cy=246, rx=84, ry=104, taper=0.32)
    back = symmetric(
        path(
            (CX, 120),
            ((CX - 90, 118), (CX - 130, 180), (CX - 126, 270)),
            ((CX - 124, 340), (CX - 140, 400), (CX - 126, 460)),
            (CX - 60, 460),
        )
    )
    c.poly(back, hair)
    cape = (84, 44, 140)
    lining = (222, 70, 150)
    # The cape's stand-up collar, flaring out behind the head.
    for side in (-1, 1):
        wing = [(CX + side * 56, 392), (CX + side * 150, 262), (CX + side * 196, 286), (CX + side * 170, 410)]
        c.poly(wing, shade(lining, 0.8))
        c.poly([(CX + side * 64, 392), (CX + side * 152, 274), (CX + side * 186, 292), (CX + side * 162, 404)], lining)
    torso(c, 384, 440, cape)
    neck(c, face, skin, width=60)
    lapels(c, 390, cape, (246, 244, 250), depth=92)
    c.poly([(CX, 404), (CX - 26, 392), (CX - 28, 418)], lining)
    c.poly([(CX, 404), (CX + 26, 392), (CX + 28, 418)], lining)
    c.ellipse((CX - 7, 397, CX + 7, 411), shade(lining, 0.7))
    c.poly(star_pts(CX - 98, 452, 18, 8), GOLD)
    for side in (-1, 1):
        lock = path(
            (CX + side * 80, 310),
            ((CX + side * 108, 370), (CX + side * 118, 430), (CX + side * 110, 490)),
            (CX + side * 144, 488),
            ((CX + side * 148, 410), (CX + side * 128, 330), (CX + side * 112, 290)),
        )
        c.poly(lock, hair)
    ears(c, face, skin)
    head(c, face, skin)
    fringe = path(
        (CX - face.rx - 6, face.cy + 20),
        ((CX - face.rx - 14, face.top - 40), (CX + face.rx + 20, face.top - 40), (CX + face.rx + 6, face.cy + 30)),
        ((CX + face.rx * 0.9, face.cy - 40), (CX + face.rx * 0.4, face.top + 30), (CX - face.rx * 0.35, face.top + 22)),
        ((CX - face.rx * 0.7, face.top + 40), (CX - face.rx * 0.8, face.cy - 10), (CX - face.rx - 6, face.cy + 20)),
    )
    c.poly(fringe, hair)
    eyes(c, face, lashes=True, look=-2)
    brows(c, face, hair, lift=(10, 2), width=7, length=0.9, tilt=2)
    nose(c, face, skin, 0.9)
    cheeks(c, face, (220, 90, 100), 0.22)
    smile(c, face, width=46, open_=False, tilt=6, lips=(150, 50, 70))
    # The top hat, a touch tall, with a magenta band and a gold star.
    hat = (32, 30, 42)
    by = face.top + 26
    c.ellipse((CX - 120, by - 20, CX + 120, by + 20), shade(hat, 0.7))
    c.ellipse((CX - 116, by - 22, CX + 116, by + 14), hat)
    c.poly([(CX - 70, by - 2), (CX - 78, by - 104), (CX + 78, by - 104), (CX + 70, by - 2)], hat)
    c.ellipse((CX - 78, by - 114, CX + 78, by - 94), shade(hat, 1.35))
    c.poly([(CX - 71, by - 34), (CX + 71, by - 34), (CX + 70, by - 6), (CX - 70, by - 6)], lining)
    c.poly(star_pts(CX + 40, by - 20, 13, 6), GOLD)
    c.line([(CX - 60, by - 90), (CX - 64, by - 44)], shade(hat, 1.6), 5, alpha=0.6)
    sparkle(c, CX + 124, by - 66, 20, (255, 236, 150))
    sparkle(c, CX - 130, by - 30, 15, WHITE)
    sparkle(c, CX + 148, by + 10, 10, WHITE)
    return c.result()


def hale() -> Image.Image:
    """Percy Quibble, The Debater: a tilted beret, a monocle, a curly handlebar mustache."""
    c = Canvas()
    skin = (150, 96, 64)
    hair = (34, 26, 26)
    face = Face(cy=236, rx=96, ry=106, jaw=0.6)
    jacket = (132, 96, 62)  # tweed
    t = torso(c, 384, 462, jacket)
    tclip = c.mask(t)
    for k in range(-8, 9):
        x = CX + k * 28
        c.line([(x, 380), (x + 60, 540)], shade(jacket, 0.82), 3, clip=tclip, alpha=0.5, caps=False)
    # A patch on the shoulder.
    px, py = CX - 168, 462
    c.ellipse((px - 30, py - 24, px + 30, py + 24), (92, 128, 84))
    for k in range(10):
        a = math.radians(k * 36)
        x, y = px + 24 * math.cos(a), py + 18 * math.sin(a)
        c.ellipse((x - 2.5, y - 2.5, x + 2.5, y + 2.5), (220, 224, 196))
    neck(c, face, skin, width=80)
    lapels(c, 390, jacket, (244, 236, 220), depth=100, spread=80)
    # A quill in the breast pocket.
    c.poly(rot_ellipse(CX - 118, 436, 46, 12, -70), (250, 248, 240))
    c.line([(CX - 104, 476), (CX - 132, 396)], (200, 196, 186), 3)
    # A long striped scarf.
    mustard, teal = (236, 180, 52), (40, 150, 140)
    c.poly([(CX - 66, 372), (CX + 66, 372), (CX + 72, 406), (CX - 72, 406)], mustard)
    tail = [(CX + 24, 396), (CX + 66, 396), (CX + 84, 530), (CX + 40, 530)]
    c.poly(tail, mustard)
    tm = c.mask(tail)
    for k in range(4):
        y = 420 + k * 34
        c.poly([(0, y), (512, y), (512, y + 14), (0, y + 14)], teal, clip=tm)
    for x in (CX - 40, CX - 4, CX + 32):
        c.poly([(x, 372), (x + 12, 372), (x + 12, 406), (x, 406)], teal)
    ears(c, face, skin)
    head(c, face, skin)
    # A short cap of hair under the beret.
    cap = path(
        (CX - face.rx, face.cy - 2),
        ((CX - face.rx - 4, face.top - 26), (CX + face.rx + 4, face.top - 26), (CX + face.rx, face.cy - 2)),
        ((CX + face.rx * 0.9, face.top + 30), (CX - face.rx * 0.9, face.top + 30), (CX - face.rx, face.cy - 2)),
    )
    c.poly(cap, hair)
    # Goatee.
    gy = face.eye_y() + 92
    c.poly(path((CX - 16, gy), ((CX - 14, gy + 26), (CX + 14, gy + 26), (CX + 16, gy)), (CX, gy - 6)), hair)
    eyes(c, face, size=0.95)
    brows(c, face, hair, lift=(0, 14), width=11, length=1.05, tilt=-3)
    nose(c, face, skin, 1.15)
    smile(c, face, width=36, open_=False, y_off=6, tilt=5, lips=(70, 30, 34))
    # The handlebar mustache, curled up at both ends.
    my = face.eye_y() + 64
    for side in (-1, 1):
        sweep = cubic((CX, my), (CX + side * 24, my - 12), (CX + side * 56, my + 6), (CX + side * 70, my - 6), 16)
        c.line([(CX, my)] + sweep, hair, 17)
        curl = arc_pts(CX + side * 70, my - 20, 14, 14, 90, 90 - side * 270, 24)
        c.line(curl, hair, 9)
    # Monocle on the right eye, its chain down to the lapel.
    mx, myy = CX + face.eye_dx(), face.eye_y()
    c.ellipse((mx - 26, myy - 26, mx + 26, myy + 26), (220, 236, 255), alpha=0.25)
    ring(c, mx, myy, 26, GOLD, 6)
    c.line(cubic((mx + 14, myy + 22), (mx + 40, myy + 80), (mx + 60, myy + 120), (CX + 96, 404), 18), GOLD, 3)
    # The beret, tilted to the left.
    beret = (196, 52, 62)
    top = face.top
    c.poly(rot_ellipse(CX - 26, top + 2, 136, 52, -8), shade(beret, 0.8))
    c.poly(rot_ellipse(CX - 26, top - 4, 132, 48, -8), beret)
    c.line([(CX - 18, top - 52), (CX - 14, top - 66)], shade(beret, 0.8), 9)
    c.line(arc_pts(CX - 40, top - 20, 80, 22, 200, 300, 16), shade(beret, 1.2), 5, alpha=0.6)
    return c.result()


def alvarado() -> Image.Image:
    """Opal Crumpet, The Insider: a lilac beehive, cat-eye glasses, pearls, a gold key."""
    c = Canvas()
    skin = (220, 170, 128)
    hair = (186, 160, 222)
    face = Face(cy=248, rx=82, ry=104, taper=0.18)
    # The beehive and its side volume.
    c.ellipse((CX - 84, 52, CX + 84, 206), hair)
    c.ellipse((CX - 112, 150, CX + 112, 300), hair)
    c.line(arc_pts(CX + 6, 120, 52, 52, 200, 330, 24), shade(hair, 0.82), 6)
    c.line(arc_pts(CX - 6, 150, 34, 30, 180, 320, 20), shade(hair, 0.82), 5)
    c.line(arc_pts(CX - 20, 104, 40, 34, 210, 280, 16), shade(hair, 1.25), 5, alpha=0.7)
    dress = (40, 150, 140)
    torso(c, 384, 424, dress)
    neck(c, face, skin, width=58)
    # A scalloped lace collar.
    for k in range(-4, 5):
        x, y = CX + k * 20, 392 + abs(k) * 5
        c.ellipse((x - 16, y - 12, x + 16, y + 16), (252, 250, 244))
    for k in range(-5, 6):
        a = math.radians(90 + k * 12)
        x, y = CX + 52 * math.cos(a), 362 + 40 * math.sin(a)
        c.ellipse((x - 7, y - 7, x + 7, y + 7), (250, 248, 240))
        c.ellipse((x - 4, y - 5, x, y - 1), WHITE)
    # A big gold key on a ribbon.
    rib = (204, 60, 120)
    c.line([(CX - 60, 400), (CX - 8, 462)], rib, 8)
    c.line([(CX + 60, 400), (CX + 8, 462)], rib, 8)
    ring(c, CX, 472, 15, GOLD_DARK, 9)
    ring(c, CX, 472, 15, GOLD, 5)
    c.poly([(CX - 6, 486), (CX + 6, 486), (CX + 6, 530), (CX - 6, 530)], GOLD)
    c.poly([(CX + 6, 506), (CX + 22, 506), (CX + 22, 514), (CX + 6, 514)], GOLD)
    c.poly([(CX + 6, 520), (CX + 18, 520), (CX + 18, 528), (CX + 6, 528)], GOLD)
    ears(c, face, skin)
    head(c, face, skin)
    # A soft swoop of fringe.
    bangs = path(
        (CX - face.rx - 8, face.cy - 6),
        ((CX - face.rx - 10, face.top - 34), (CX + face.rx + 10, face.top - 34), (CX + face.rx + 8, face.cy - 6)),
        ((CX + face.rx * 0.6, face.top + 16), (CX + face.rx * 0.1, face.top + 30), (CX - face.rx * 0.3, face.top + 44)),
        ((CX - face.rx * 0.7, face.top + 40), (CX - face.rx * 0.9, face.cy - 30), (CX - face.rx - 8, face.cy - 6)),
    )
    c.poly(bangs, hair)
    eyes(c, face, lashes=True, look=-2)
    brows(c, face, shade(hair, 0.6), lift=(10, 10), width=7)
    nose(c, face, skin, 0.9)
    cheeks(c, face, (230, 110, 110), 0.3)
    smile(c, face, width=40, open_=False, tilt=4, lips=(196, 60, 110))
    # Cat-eye glasses, swept up at the outer corners.
    y = face.eye_y()
    frame = (196, 52, 120)
    for side in (-1, 1):
        x = CX + side * face.eye_dx()
        outer = [
            (x - side * 30, y - 12), (x + side * 18, y - 20), (x + side * 44, y - 40),
            (x + side * 34, y + 4), (x + side * 18, y + 22), (x - side * 16, y + 24), (x - side * 30, y + 6),
        ]
        c.poly(outer, frame)
        inner = [(x + (px - x) * 0.72, y + (py - y) * 0.72) for px, py in outer]
        c.poly(inner, (226, 238, 252), alpha=0.85)
    eyes(c, face, lashes=True, look=-2, size=0.85)
    c.line([(CX - 22, y - 8), (CX + 22, y - 8)], frame, 6)
    return c.result()


def reyes() -> Image.Image:
    """Dash Kickflip, The Insurgent: teal-tipped spikes, a sweatband, a bomber, a bolt pin."""
    c = Canvas()
    skin = (198, 138, 98)
    hair = (36, 32, 44)
    tips = (52, 206, 196)
    face = Face(cy=246, rx=82, ry=108, jaw=0.35, taper=0.1)
    # Spikes: triangles fanned over the top of the head, each with a teal tip.
    hx, hy = CX, face.cy - 20
    for a in (198, 218, 240, 262, 284, 306, 326, 344):
        r0x, r0y = face.rx * 1.02, face.ry * 0.92
        b1 = (hx + r0x * math.cos(math.radians(a - 12)), hy + r0y * math.sin(math.radians(a - 12)))
        b2 = (hx + r0x * math.cos(math.radians(a + 12)), hy + r0y * math.sin(math.radians(a + 12)))
        tip = (hx + r0x * 1.6 * math.cos(math.radians(a)), hy + r0y * 1.62 * math.sin(math.radians(a)))
        c.poly([b1, tip, b2, (hx, hy)], hair)
        k = 0.62
        m1 = (b1[0] + (tip[0] - b1[0]) * k, b1[1] + (tip[1] - b1[1]) * k)
        m2 = (b2[0] + (tip[0] - b2[0]) * k, b2[1] + (tip[1] - b2[1]) * k)
        c.poly([m1, tip, m2], tips)
    jacket = (98, 116, 66)
    collar = (240, 128, 40)
    torso(c, 388, 440, jacket)
    neck(c, face, skin, width=64)
    c.poly(symmetric(path((CX - 50, 388), ((CX - 46, 438), (CX - 20, 448), (CX, 448)))), (244, 244, 240))
    for side in (-1, 1):
        c.poly([(CX + side * 46, 382), (CX + side * 68, 380), (CX + side * 42, 530), (CX + side * 18, 530)], collar)
    px, py = CX - 110, 456
    bolt = [(px + 6, py - 26), (px - 12, py + 2), (px, py + 2), (px - 6, py + 26), (px + 14, py - 6), (px + 2, py - 6), (px + 10, py - 26)]
    c.ellipse((px - 24, py - 30, px + 24, py + 30), (30, 34, 46))
    c.poly(bolt, (255, 214, 64))
    ears(c, face, skin)
    clip = head(c, face, skin)
    crown = path(
        (CX - face.rx - 2, face.cy - 20),
        ((CX - face.rx, face.top - 34), (CX + face.rx, face.top - 34), (CX + face.rx + 2, face.cy - 20)),
        ((CX + face.rx * 0.5, face.top + 56), (CX - face.rx * 0.5, face.top + 56), (CX - face.rx - 2, face.cy - 20)),
    )
    c.poly(crown, hair)
    # A red sweatband with a white stripe.
    big = c.mask(head_outline(CX, face.cy, face.rx + 6, face.ry + 6, face.jaw, face.taper))
    by = face.top + 46
    c.poly([(0, by - 14), (512, by - 14), (512, by + 14), (0, by + 14)], (222, 58, 66), clip=big)
    c.poly([(0, by - 3), (512, by - 3), (512, by + 3), (0, by + 3)], WHITE, clip=big)
    eyes(c, face, size=0.95, look=3)
    brows(c, face, hair, lift=(10, 2), width=10, tilt=-2)
    nose(c, face, skin)
    smile(c, face, width=58, y_off=2, tilt=6)
    # A plaster on the cheek.
    c.poly(rot_ellipse(CX - 52, face.eye_y() + 42, 22, 9, -24), (238, 204, 160))
    c.poly(rot_ellipse(CX - 52, face.eye_y() + 42, 8, 8, 0), (222, 182, 136))
    return c.result()


def strand() -> Image.Image:
    """Esme Moonbeam, The Pollster: a starry headscarf, round glasses, hoops, a crystal ball."""
    c = Canvas()
    skin = (246, 212, 188)
    hair = (214, 218, 230)
    face = Face(cy=240, rx=92, ry=102, jaw=0.2)
    # Silver curls peeking out under the scarf.
    for side in (-1, 1):
        for k in range(3):
            x, y = CX + side * (face.rx + 12 - k * 2), face.cy - 10 + k * 34
            c.ellipse((x - 28, y - 28, x + 28, y + 28), hair)
    blouse = (122, 62, 140)
    shawl = (40, 148, 150)
    torso(c, 384, 450, blouse)
    neck(c, face, skin, width=66)
    for side in (-1, 1):
        drape = [(CX + side * 38, 384), (CX + side * 120, 376), (CX + side * 236, 430), (CX + side * 236, 530), (CX + side * 12, 530)]
        c.poly(drape, shawl)
        dm = c.mask(drape)
        for k in range(8):
            x, y = CX + side * (60 + (k % 4) * 40), 430 + (k // 4) * 50 + (k % 2) * 18
            c.ellipse((x - 5, y - 5, x + 5, y + 5), GOLD, clip=dm)
        for k in range(7):
            x0 = CX + side * (14 + k * 4)
            y0 = 520 - k * 18
            c.line([(x0, y0), (x0 - side * 14, y0 + 8)], shade(shawl, 0.7), 3)
    # A crystal ball on a gold chain.
    c.line([(CX - 40, 384), (CX, 440)], GOLD, 3)
    c.line([(CX + 40, 384), (CX, 440)], GOLD, 3)
    c.poly([(CX - 22, 482), (CX + 22, 482), (CX + 14, 496), (CX - 14, 496)], GOLD_DARK)
    c.ellipse((CX - 28, 432, CX + 28, 488), (150, 196, 246))
    c.ellipse((CX - 18, 440, CX - 2, 456), WHITE, alpha=0.85)
    sparkle(c, CX + 10, 468, 8, WHITE)
    ears(c, face, skin)
    for side in (-1, 1):
        ring(c, CX + side * (face.rx - 2), face.eye_y() + 64, 18, GOLD, 6)
    head(c, face, skin)
    eyes(c, face, size=0.9)
    brows(c, face, shade(hair, 0.7), lift=(4, 4), width=7)
    nose(c, face, skin, 0.9)
    cheeks(c, face, (240, 120, 130), 0.35)
    smile(c, face, width=46, lips=(190, 90, 100))
    y = face.eye_y()
    frame = (150, 104, 44)
    for side in (-1, 1):
        x = CX + side * face.eye_dx()
        c.ellipse((x - 30, y - 28, x + 30, y + 28), (220, 236, 255), alpha=0.25)
        c.line(arc_pts(x, y, 29, 27, 0, 360, 48), frame, 7, caps=False)
    c.line(cubic((CX - 14, y - 6), (CX - 6, y - 14), (CX + 6, y - 14), (CX + 14, y - 6), 8), frame, 6)
    # The headscarf, knotted at the side, scattered with stars.
    scarf = (70, 52, 150)
    sy = face.cy + 4
    cover = path(
        (CX - face.rx - 14, sy),
        ((CX - face.rx - 22, face.top - 66), (CX + face.rx + 22, face.top - 66), (CX + face.rx + 14, sy)),
        (CX + face.rx - 8, sy - 6),
        ((CX + face.rx - 10, face.top + 40), (CX - face.rx + 10, face.top + 40), (CX - face.rx + 8, sy - 6)),
    )
    c.poly(cover, scarf)
    cm = c.mask(cover)
    for sx, syy, r in ((-60, -30, 11), (-10, -54, 13), (44, -26, 10), (78, 8, 9), (-82, 16, 9), (10, -4, 8)):
        c.poly(star_pts(CX + sx, face.top + syy + 20, r, r * 0.45), GOLD, clip=cm)
    kx, ky = CX + face.rx + 12, face.top + 50
    c.poly([(kx - 4, ky + 10), (kx + 56, ky + 92), (kx + 30, ky + 104), (kx - 14, ky + 24)], shade(scarf, 0.82))
    c.poly([(kx + 2, ky + 6), (kx + 70, ky + 58), (kx + 54, ky + 76), (kx - 8, ky + 22)], scarf)
    c.ellipse((kx - 22, ky - 18, kx + 22, ky + 26), shade(scarf, 1.2))
    sparkle(c, CX - 140, face.top - 6, 14, (200, 230, 255))
    return c.result()


def begay() -> Image.Image:
    """Gus Bramble, The Organizer: a ranger hat, a big white beard, a neckerchief, badges."""
    c = Canvas()
    skin = (170, 108, 72)
    beard = (238, 238, 242)
    face = Face(cy=242, rx=94, ry=100, jaw=0.7)
    shirt = (196, 176, 116)
    torso(c, 386, 456, shirt)
    for side in (-1, 1):
        x = CX + side * 108
        c.poly([(x - 34, 446), (x + 34, 446), (x + 32, 500), (x - 32, 500)], shade(shirt, 0.88))
        c.poly([(x - 36, 440), (x + 36, 440), (x + 36, 458), (x - 36, 458)], shade(shirt, 0.78))
    for k, col in enumerate(((230, 90, 60), (60, 140, 210), (244, 200, 60))):
        x = CX - 136 + k * 28
        c.ellipse((x - 12, 404 - 12, x + 12, 404 + 12), shade(col, 0.75))
        c.ellipse((x - 9, 404 - 9, x + 9, 404 + 9), col)
    neck(c, face, skin, width=80)
    # The neckerchief and its woggle.
    kerchief = (226, 92, 52)
    c.poly([(CX - 84, 384), (CX + 84, 384), (CX + 20, 488), (CX - 20, 488)], kerchief)
    c.poly([(CX - 84, 384), (CX + 84, 384), (CX + 70, 400), (CX - 70, 400)], shade(kerchief, 0.8))
    ring(c, CX, 436, 14, (120, 82, 50), 9)
    ears(c, face, skin, y_off=4)
    head(c, face, skin)
    # A big bushy beard that runs from the ears to below the chin.
    outline = head_outline(CX, face.cy + 34, face.rx + 12, face.ry + 30, face.jaw, 0.05)
    cut = head_outline(CX, face.cy - 28, face.rx * 0.96, face.ry * 0.9, 0.3, 0)
    m = ImageChops.subtract(c.mask(outline), c.mask(cut))
    layer = c.layer()
    ImageDraw.Draw(layer).rectangle((0, 0, W, W), fill=beard)
    c.put(layer, m)
    for k in range(-4, 5):
        x = CX + k * 24
        y = face.chin + 28 - abs(k) * 7
        c.ellipse((x - 20, y - 18, x + 20, y + 18), beard)
    for k in range(-3, 4):
        x = CX + k * 26
        c.line([(x, face.chin + 4), (x + 4, face.chin + 30)], shade(beard, 0.86), 3)
    # The mouth sits in an open patch of the beard.
    my = face.eye_y() + 78
    c.ellipse((CX - 34, my - 18, CX + 34, my + 22), skin)
    smile(c, face, width=40, y_off=6)
    c.poly(path((CX - 58, my - 2), ((CX - 46, my - 34), (CX + 46, my - 34), (CX + 58, my - 2)), ((CX + 20, my - 14), (CX - 20, my - 14), (CX - 58, my - 2))), beard)
    eyes(c, face, size=0.9)
    brows(c, face, beard, lift=(4, 4), width=15, length=1.15)
    nose(c, face, skin, 1.25)
    cheeks(c, face, (200, 90, 80), 0.25)
    # The ranger hat: a wide flat brim and a pinched crown.
    felt = (176, 132, 72)
    by = face.top + 40
    c.ellipse((CX - 162, by - 24, CX + 162, by + 22), shade(felt, 0.72))
    c.ellipse((CX - 158, by - 28, CX + 158, by + 14), felt)
    crown = [(CX - 82, by - 6), (CX - 66, by - 80), (CX, by - 108), (CX + 66, by - 80), (CX + 82, by - 6)]
    c.poly(crown, shade(felt, 1.08))
    for side in (-1, 1):
        c.line([(CX + side * 4, by - 100), (CX + side * 38, by - 50)], shade(felt, 0.8), 5)
    c.poly([(CX - 80, by - 30), (CX + 80, by - 30), (CX + 82, by - 8), (CX - 82, by - 8)], (96, 64, 40))
    return c.result()


PORTRAITS = {
    "okafor": okafor,
    "calloway": calloway,
    "venkat": venkat,
    "hale": hale,
    "alvarado": alvarado,
    "reyes": reyes,
    "strand": strand,
    "begay": begay,
}

PLATE_TOP = (104, 118, 156)  # Kit.portrait's neutral plate (top of its gradient)
PLATE_BOTTOM = (66, 76, 108)
STAGE = (24, 30, 48)  # Colors.surface


def plated(img: Image.Image, px: int) -> Image.Image:
    """`img` on Kit.portrait's round plate, `px` wide (for the preview only)."""
    big = px * 4
    plate = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    grad = Image.new("RGBA", (big, big))
    for y in range(big):
        col = mix(PLATE_TOP, PLATE_BOTTOM, y / big)
        ImageDraw.Draw(grad).line([(0, y), (big, y)], fill=col + (255,))
    circle = Image.new("L", (big, big), 0)
    ImageDraw.Draw(circle).ellipse((0, 0, big - 1, big - 1), fill=255)
    plate.paste(grad, (0, 0), circle)
    face = img.resize((big, big), Image.Resampling.LANCZOS)
    a = ImageChops.multiply(face.getchannel("A"), circle)
    face.putalpha(a)
    plate.alpha_composite(face)
    return plate.resize((px, px), Image.Resampling.LANCZOS)


NAMES = {
    "okafor": "Goldie Pennywhistle",
    "calloway": "Buster Cannonball",
    "venkat": "Mavis Glimmer",
    "hale": "Percy Quibble",
    "alvarado": "Opal Crumpet",
    "reyes": "Dash Kickflip",
    "strand": "Esme Moonbeam",
    "begay": "Gus Bramble",
}


def preview(images: dict[str, Image.Image], labels: bool = False) -> Image.Image:
    """Every portrait on its plate at 40, 80 and 160 px, two to a row."""
    sizes = (40, 80, 160)
    pad = 16
    label_h = 26 if labels else 0
    col_w = sum(sizes) + pad * (len(sizes) + 1)
    row_h = 160 + pad + label_h
    sheet = Image.new("RGBA", (col_w * 2, row_h * 4 + pad), STAGE + (255,))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=18) if labels else None
    for i, (name, img) in enumerate(images.items()):
        ox = (i % 2) * col_w + pad
        oy = (i // 2) * row_h + pad
        x = ox
        for px in sizes:
            sheet.alpha_composite(plated(img, px), (x, oy + 160 - px))
            x += px + pad
        if labels:
            draw.text((ox, oy + 166), f"{NAMES.get(name, name)}  ({name})", fill=(236, 240, 250), font=font)
    return sheet


# The whiteboard photo (UI/Board.photo; keep in sync): a paper card px wide,
# a 7% border at the sides and top, a 20% chin, the face in a square window on
# the raised color, tape across the top, the whole card turned `tilt` degrees.
BOARD = (243, 241, 234)  # Colors.background
CARD = (255, 254, 250)  # Colors.surfaceTop
WINDOW = (236, 232, 222)  # Colors.raised
EDGE = (143, 139, 128, 102)  # Colors.line at 0.6 transparency
PHOTO_MARGIN, PHOTO_CHIN, TAPE_W = 0.07, 0.2, 0.55


def photo(img: Image.Image, px: int, tilt: float, tape: Image.Image | None) -> Image.Image:
    """`img` as UI/Board.photo draws it, `px` wide (for the preview only)."""
    k = 4
    m = round(px * PHOTO_MARGIN)
    win = px - 2 * m
    chin = round(px * PHOTO_CHIN)
    w, h = px * k, (m + win + chin) * k
    pad = px * k // 2
    card = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rectangle((pad, pad, pad + w - 1, pad + h - 1), fill=CARD + (255,), outline=EDGE, width=k)
    d.rectangle((pad + m * k, pad + m * k, pad + (m + win) * k - 1, pad + (m + win) * k - 1), fill=WINDOW + (255,))
    face = img.resize((win * k, win * k), Image.Resampling.LANCZOS)
    card.alpha_composite(face, (pad + m * k, pad + m * k))
    if tape is not None:
        tw = round(px * TAPE_W) * k
        strip = tape.resize((tw, round(tw * tape.height / tape.width)), Image.Resampling.LANCZOS)
        strip = strip.rotate(4, expand=True, resample=Image.Resampling.BICUBIC)
        card.alpha_composite(strip, (pad + (w - strip.width) // 2, pad - strip.height // 2))
    card = card.rotate(-tilt, expand=False, resample=Image.Resampling.BICUBIC)
    card = card.crop(card.getbbox())
    return card.resize((max(1, card.width // k), max(1, card.height // k)), Image.Resampling.LANCZOS)


def baked(img: Image.Image, tape: Image.Image | None) -> Image.Image:
    """The alternative not taken: the photo drawn into a 512x512 image."""
    shot = photo(img, 400, 4.0, tape)
    out = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    out.alpha_composite(shot, ((512 - shot.width) // 2, (512 - shot.height) // 2))
    return out


def photo_sheet(images: dict[str, Image.Image]) -> Image.Image:
    """Each face as a run-time photo at 48, 72 and 96 px (top of each pair of
    rows) and as a baked 512 image shown at the same sizes (below)."""
    tape_path = os.path.join(HERE, "..", "ui", "tape.png")
    tape = Image.open(tape_path).convert("RGBA") if os.path.exists(tape_path) else None
    sizes = (48, 72, 96)
    tilts = (-3.0, 2.0, -1.5, 3.0, -2.5, 1.5, -2.0, 2.5)
    cell = 130
    sheet = Image.new("RGBA", (cell * len(images) + 20, 130 * len(sizes) + 24 + sum(sizes) + 12 * len(sizes) + 10), BOARD + (255,))
    for i, (name, img) in enumerate(images.items()):
        y = 10
        for px in sizes:
            shot = photo(img, px, tilts[i], tape)
            sheet.alpha_composite(shot, (10 + i * cell + (cell - shot.width) // 2, y))
            y += 130
        y += 24
        for px in sizes:
            shot = baked(img, tape).resize((px, px), Image.Resampling.LANCZOS)
            sheet.alpha_composite(shot, (10 + i * cell + (cell - px) // 2, y))
            y += px + 12
    return sheet


def main():
    images = {}
    for name, draw in PORTRAITS.items():
        img = draw()
        img.save(os.path.join(HERE, f"{name}.png"), optimize=True)
        images[name] = img
    # The contact sheet that ships next to the portraits, with names.
    preview(images, labels=True).save(os.path.join(HERE, "sheet.png"), optimize=True)
    if "--preview" in sys.argv:
        out_dir = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(out_dir, exist_ok=True)
        preview(images).save(os.path.join(out_dir, "portraits-preview.png"))
    if "--photos" in sys.argv:
        target = sys.argv[sys.argv.index("--photos") + 1]
        photo_sheet(images).save(target)
        print(f"wrote {target}")
    print(f"wrote {len(images)} portraits and sheet.png to {HERE}")


if __name__ == "__main__":
    main()
