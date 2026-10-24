"""Draws the candidates' portraits (docs/DESIGN.md D-062).

Run from the repository root:  python3 assets/portraits/make.py [--preview DIR]
Needs Pillow 11 (PIL). Writes, next to this script, one 512x512 PNG per
candidate in Sim/Candidates.luau, named by candidate id (okafor.png, ...):
a flat vector-style head-and-shoulders bust on a transparent background,
drawn 4x larger and scaled down for smooth edges.

The game shows each one inside a round plate (Kit.portrait), so every bust is
centered and fits a circle of the image's full width: the head sits in the
upper middle and the shoulders run off the bottom edge. --preview DIR also
writes DIR/portraits-preview.png: every portrait on a plate at 40, 80 and 160 px.

All eight are fictional people. Each gets its own face shape, skin tone, hair,
outfit and one prop that hints at the perk:
  okafor    The Fundraiser   gold coin earrings and a coin brooch
  calloway  The Barnstormer  a straw boater hat, rolled sleeves, braces
  venkat    The Ad Wizard    a headset microphone
  hale      The Debater      a bow tie and a full beard
  alvarado  The Insider      an access badge on a lanyard, pearls
  reyes     The Insurgent    a lightning-bolt pin, curly mop, bomber jacket
  strand    The Pollster     round glasses, a pencil behind the ear, a bun
  begay     The Organizer    a field cap, a mustache, a work vest
"""

from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

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


# ---------------------------------------------------------------- the eight


def okafor() -> Image.Image:
    """Dana Okafor, The Fundraiser: a rounded natural puff, gold coin jewelry."""
    c = Canvas()
    skin = (122, 74, 50)
    hair = (40, 28, 30)
    face = Face(cy=226, rx=86, ry=104, jaw=0.15, taper=0.12)
    # Hair: a big round puff behind the head.
    c.ellipse((CX - 128, 56, CX + 128, 262), hair)
    c.line(arc_pts(CX, 160, 100, 88, 200, 262, 20), shade(hair, 2.2), 7, alpha=0.5)
    jacket = (230, 172, 52)  # mustard blazer
    t = torso(c, 372, 430, jacket)
    neck(c, face, skin)
    lapels(c, 378, jacket, (250, 244, 232), depth=100)
    # Coin brooch on the left lapel.
    bx, by = CX - 92, 436
    c.ellipse((bx - 17, by - 17, bx + 17, by + 17), (186, 126, 26))
    c.ellipse((bx - 13, by - 13, bx + 13, by + 13), (255, 214, 92))
    c.ellipse((bx - 6, by - 6, bx + 6, by + 6), (214, 158, 40))
    ears(c, face, skin)
    # Coin earrings.
    for side in (-1, 1):
        x, y = CX + side * (face.rx - 4), face.eye_y() + 52
        c.ellipse((x - 13, y - 13, x + 13, y + 13), (186, 126, 26))
        c.ellipse((x - 10, y - 10, x + 10, y + 10), (255, 214, 92))
    head(c, face, skin)
    # Hairline: a soft crown over the forehead.
    crown = path(
        (CX - face.rx - 2, face.cy - 10),
        ((CX - face.rx, face.top - 30), (CX + face.rx, face.top - 30), (CX + face.rx + 2, face.cy - 10)),
        ((CX + face.rx * 0.6, face.top + 10), (CX - face.rx * 0.2, face.top + 4), (CX - face.rx - 2, face.cy - 10)),
    )
    c.poly(crown, hair)
    eyes(c, face, lashes=True)
    brows(c, face, hair, lift=(2, 2), width=8)
    nose(c, face, skin)
    cheeks(c, face, (200, 80, 80), 0.22)
    smile(c, face, width=50, lips=(96, 40, 44))
    return c.result()


def calloway() -> Image.Image:
    """Rex Calloway, The Barnstormer: a straw boater, rolled sleeves and braces."""
    c = Canvas()
    skin = (240, 192, 158)
    hair = (150, 96, 52)
    face = Face(cy=236, rx=94, ry=106, jaw=0.85)
    shirt = (246, 242, 230)
    torso(c, 376, 452, shirt)
    neck(c, face, skin, width=76)
    # Open collar points and a loosened tie.
    for side in (-1, 1):
        c.poly([(CX + side * 4, 376), (CX + side * 50, 368), (CX + side * 30, 418)], shade(shirt, 0.88))
    tie = (54, 132, 120)
    c.poly([(CX - 14, 384), (CX + 14, 384), (CX + 8, 400), (CX - 8, 400)], shade(tie, 0.8))
    c.poly([(CX - 9, 398), (CX + 9, 398), (CX + 24, 500), (CX, 528), (CX - 22, 500)], tie)
    # Braces.
    for side in (-1, 1):
        c.poly([(CX + side * 112, 388), (CX + side * 136, 392), (CX + side * 114, 530), (CX + side * 90, 530)], (120, 72, 44))
    ears(c, face, skin)
    head(c, face, skin)
    # Short sandy hair with a side sweep, under the hat.
    sweep = path(
        (CX - face.rx - 4, face.cy - 6),
        ((CX - face.rx - 8, face.top - 30), (CX + face.rx + 8, face.top - 30), (CX + face.rx + 4, face.cy - 6)),
        ((CX + face.rx * 0.7, face.top + 20), (CX - face.rx * 0.1, face.top + 44), (CX - face.rx * 0.5, face.top + 28)),
        ((CX - face.rx * 0.8, face.top + 40), (CX - face.rx * 0.9, face.cy - 30), (CX - face.rx - 4, face.cy - 6)),
    )
    c.poly(sweep, hair)
    # Freckles.
    for fx, fy in ((-46, 38), (-34, 46), (-54, 50), (46, 38), (34, 46), (54, 50)):
        c.ellipse((CX + fx - 3, face.eye_y() + fy - 3, CX + fx + 3, face.eye_y() + fy + 3), (198, 128, 92))
    eyes(c, face)
    brows(c, face, shade(hair, 0.8), lift=(6, 6), width=10)
    nose(c, face, skin, 1.1)
    cheeks(c, face)
    smile(c, face, width=62, y_off=2)
    # The boater: a flat crown on a wide brim, tilted a touch.
    straw = (238, 206, 132)
    brim_y = face.top + 30
    c.ellipse((CX - 150, brim_y - 22, CX + 150, brim_y + 22), shade(straw, 0.8))
    c.ellipse((CX - 146, brim_y - 24, CX + 146, brim_y + 16), straw)
    crown = [(CX - 92, brim_y - 2), (CX - 86, brim_y - 76), (CX + 86, brim_y - 76), (CX + 92, brim_y - 2)]
    c.poly(crown, straw)
    c.ellipse((CX - 86, brim_y - 90, CX + 86, brim_y - 62), shade(straw, 1.12))
    band = [(CX - 91, brim_y - 30), (CX + 91, brim_y - 30), (CX + 92, brim_y - 4), (CX - 92, brim_y - 4)]
    c.poly(band, (54, 132, 120))
    # Straw weave lines.
    for k in range(3):
        y = brim_y - 44 - k * 12
        c.line([(CX - 86, y), (CX + 86, y)], shade(straw, 0.88), 2.5, caps=False)
    return c.result()


def venkat() -> Image.Image:
    """Priya Venkat, The Ad Wizard: long hair, a plum blazer, a headset mic."""
    c = Canvas()
    skin = (184, 120, 84)
    hair = (36, 26, 30)
    face = Face(cy=222, rx=84, ry=106, taper=0.32)
    # Long hair behind the head and shoulders.
    back = symmetric(
        path(
            (CX, 90),
            ((CX - 90, 88), (CX - 132, 150), (CX - 128, 250)),
            ((CX - 126, 330), (CX - 150, 400), (CX - 132, 470)),
            (CX - 60, 470),
        )
    )
    c.poly(back, hair)
    jacket = (132, 58, 116)
    torso(c, 372, 420, jacket)
    neck(c, face, skin, width=60)
    lapels(c, 378, jacket, (36, 36, 44), depth=96)
    # Hair falling over the shoulders, in front of the jacket.
    for side in (-1, 1):
        strand = path(
            (CX + side * 80, 300),
            ((CX + side * 110, 360), (CX + side * 120, 420), (CX + side * 112, 480)),
            (CX + side * 146, 478),
            ((CX + side * 150, 400), (CX + side * 130, 320), (CX + side * 112, 280)),
        )
        c.poly(strand, hair)
    ears(c, face, skin)
    head(c, face, skin)
    # A side part: the hair sweeps from the left over the forehead.
    fringe = path(
        (CX - face.rx - 6, face.cy + 20),
        ((CX - face.rx - 14, face.top - 40), (CX + face.rx + 20, face.top - 40), (CX + face.rx + 6, face.cy + 30)),
        ((CX + face.rx * 0.9, face.cy - 40), (CX + face.rx * 0.4, face.top + 30), (CX - face.rx * 0.35, face.top + 22)),
        ((CX - face.rx * 0.7, face.top + 40), (CX - face.rx * 0.8, face.cy - 10), (CX - face.rx - 6, face.cy + 20)),
    )
    c.poly(fringe, hair)
    c.line(cubic((CX - 30, face.top + 6), (CX + 10, face.top - 6), (CX + 50, face.top + 6), (CX + 74, face.top + 30), 14), shade(hair, 1.9), 5, alpha=0.6)
    eyes(c, face, lashes=True, look=2)
    brows(c, face, hair, lift=(0, 6), width=7, length=0.9)
    nose(c, face, skin, 0.9)
    cheeks(c, face, (220, 90, 100), 0.22)
    smile(c, face, width=44, lips=(150, 50, 70))
    # Headset: a band over the head, an ear cup and a boom to the mouth.
    band = arc_pts(CX, face.cy - 6, face.rx + 12, face.ry + 8, 200, 340, 40)
    c.line(band, (44, 48, 60), 10)
    ex, ey = CX + face.rx + 2, face.eye_y() + 8
    c.ellipse((ex - 22, ey - 30, ex + 22, ey + 30), (44, 48, 60))
    c.ellipse((ex - 12, ey - 18, ex + 12, ey + 18), (240, 246, 252))
    boom = cubic((ex - 6, ey + 20), (ex - 10, ey + 70), (CX + 70, face.eye_y() + 86), (CX + 38, face.eye_y() + 82), 18)
    c.line([(ex - 6, ey + 20)] + boom, (44, 48, 60), 7)
    c.ellipse((CX + 22, face.eye_y() + 72, CX + 44, face.eye_y() + 92), (44, 48, 60))
    c.ellipse((CX + 26, face.eye_y() + 76, CX + 36, face.eye_y() + 86), (90, 230, 210))
    return c.result()


def hale() -> Image.Image:
    """Marcus Hale, The Debater: a close fade, full beard, charcoal suit, bow tie."""
    c = Canvas()
    skin = (150, 96, 64)
    hair = (34, 26, 26)
    face = Face(cy=222, rx=96, ry=110, jaw=0.6)
    suit = (66, 70, 84)
    torso(c, 376, 462, suit)
    neck(c, face, skin, width=80)
    lapels(c, 382, suit, (246, 246, 250), depth=110, spread=80)
    # Bow tie.
    bow = (40, 168, 156)
    by = 392
    c.poly([(CX, by), (CX - 46, by - 22), (CX - 50, by + 24)], bow)
    c.poly([(CX, by), (CX + 46, by - 22), (CX + 50, by + 24)], bow)
    c.ellipse((CX - 13, by - 13, CX + 13, by + 13), shade(bow, 0.78))
    # Pocket square.
    c.poly([(CX + 98, 470), (CX + 140, 466), (CX + 136, 480), (CX + 100, 484)], (246, 246, 250))
    ears(c, face, skin)
    clip = head(c, face, skin)
    # The fade: a short cap of hair.
    cap = path(
        (CX - face.rx, face.cy - 2),
        ((CX - face.rx - 4, face.top - 26), (CX + face.rx + 4, face.top - 26), (CX + face.rx, face.cy - 2)),
        ((CX + face.rx * 0.9, face.top + 30), (CX - face.rx * 0.9, face.top + 30), (CX - face.rx, face.cy - 2)),
    )
    c.poly(cap, hair)
    # Beard: around the jaw and chin, open at the mouth.
    beard = head_outline(CX, face.cy + 8, face.rx + 2, face.ry + 6, face.jaw, 0)
    beard_mask = c.mask(beard)
    cut = head_outline(CX, face.cy - 26, face.rx * 0.98, face.ry * 0.9, 0.3, 0)
    m = ImageChops.subtract(beard_mask, c.mask(cut))
    layer = c.layer()
    ImageDraw.Draw(layer).rectangle((0, 0, W, W), fill=hair)
    c.put(layer, ImageChops.multiply(m, clip))
    # Mustache.
    my = face.eye_y() + 60
    c.poly(path((CX - 40, my + 12), ((CX - 30, my - 8), (CX + 30, my - 8), (CX + 40, my + 12)), (CX, my + 4)), hair)
    eyes(c, face, size=0.95)
    brows(c, face, hair, lift=(0, 10), width=11, length=1.05)
    nose(c, face, skin, 1.15)
    smile(c, face, width=40, open_=False, y_off=4, lips=(70, 30, 34))
    return c.result()


def alvarado() -> Image.Image:
    """June Alvarado, The Insider: a sleek bob, black blazer, pearls, a VIP badge."""
    c = Canvas()
    skin = (220, 170, 128)
    hair = (104, 46, 34)
    face = Face(cy=222, rx=82, ry=108, taper=0.18)
    bob = symmetric(
        path(
            (CX, 94),
            ((CX - 96, 92), (CX - 122, 160), (CX - 118, 240)),
            ((CX - 116, 290), (CX - 112, 322), (CX - 100, 336)),
            (CX - 40, 330),
        )
    )
    c.poly(bob, hair)
    jacket = (44, 46, 58)
    torso(c, 372, 424, jacket)
    neck(c, face, skin, width=58)
    lapels(c, 378, jacket, (236, 232, 240), depth=96)
    # Pearls.
    for k in range(-5, 6):
        a = math.radians(90 + k * 12)
        x, y = CX + 52 * math.cos(a), 360 + 40 * math.sin(a)
        c.ellipse((x - 7, y - 7, x + 7, y + 7), (250, 248, 240))
        c.ellipse((x - 4, y - 5, x, y - 1), WHITE)
    # Lanyard and badge.
    lan = (240, 140, 40)
    c.line([(CX - 60, 382), (CX - 18, 470)], lan, 9)
    c.line([(CX + 60, 382), (CX + 18, 470)], lan, 9)
    c.poly([(CX - 40, 462), (CX + 40, 462), (CX + 40, 530), (CX - 40, 530)], (250, 250, 252))
    c.poly([(CX - 40, 462), (CX + 40, 462), (CX + 40, 484), (CX - 40, 484)], (240, 140, 40))
    c.ellipse((CX - 14, 492, CX + 14, 520), (180, 186, 204))
    ears(c, face, skin)
    head(c, face, skin)
    # Blunt bangs and the bob's front.
    for side in (-1, 1):
        c.poly(
            [(CX + side * (face.rx + 2), face.cy - 40), (CX + side * (face.rx + 30), face.cy), (CX + side * (face.rx + 28), 334), (CX + side * (face.rx - 14), 330), (CX + side * (face.rx - 6), face.cy + 40)],
            hair,
        )
    bangs = path(
        (CX - face.rx - 8, face.cy - 10),
        ((CX - face.rx - 10, face.top - 34), (CX + face.rx + 10, face.top - 34), (CX + face.rx + 8, face.cy - 10)),
        (CX + face.rx - 4, face.top + 50),
        ((CX + 30, face.top + 58), (CX - 30, face.top + 58), (CX - face.rx + 4, face.top + 50)),
    )
    c.poly(bangs, hair)
    c.line(cubic((CX - 50, face.top - 4), (CX - 10, face.top - 14), (CX + 30, face.top - 14), (CX + 60, face.top - 2), 14), shade(hair, 1.5), 5, alpha=0.55)
    eyes(c, face, lashes=True, look=-2)
    brows(c, face, shade(hair, 0.7), lift=(2, 6), width=7)
    nose(c, face, skin, 0.9)
    cheeks(c, face, (230, 110, 110), 0.2)
    smile(c, face, width=40, open_=False, tilt=4, lips=(176, 70, 84))
    return c.result()


def reyes() -> Image.Image:
    """Tomas Reyes, The Insurgent: a curly mop, stubble, a bomber and a bolt pin."""
    c = Canvas()
    skin = (198, 138, 98)
    hair = (52, 34, 28)
    face = Face(cy=234, rx=82, ry=114, jaw=0.35, taper=0.1)
    jacket = (98, 116, 66)
    torso(c, 380, 440, jacket)
    neck(c, face, skin, width=64)
    # White tee and the bomber's ribbed collar.
    c.poly(symmetric(path((CX - 50, 380), ((CX - 46, 430), (CX - 20, 440), (CX, 440)))), (244, 244, 240))
    for side in (-1, 1):
        c.poly([(CX + side * 46, 374), (CX + side * 66, 372), (CX + side * 40, 530), (CX + side * 18, 530)], shade(jacket, 0.75))
    # Lightning-bolt pin.
    px, py = CX - 104, 448
    bolt = [(px + 6, py - 26), (px - 12, py + 2), (px, py + 2), (px - 6, py + 26), (px + 14, py - 6), (px + 2, py - 6), (px + 10, py - 26)]
    c.ellipse((px - 24, py - 30, px + 24, py + 30), (30, 34, 46))
    c.poly(bolt, (255, 214, 64))
    ears(c, face, skin)
    clip = head(c, face, skin)
    # Stubble along the jaw.
    stub = head_outline(CX, face.cy + 14, face.rx + 2, face.ry, face.jaw, face.taper)
    m = ImageChops.subtract(c.mask(stub), c.mask(head_outline(CX, face.cy - 30, face.rx, face.ry * 0.92, 0.3, 0)))
    layer = c.layer()
    ImageDraw.Draw(layer).rectangle((0, 0, W, W), fill=shade(skin, 0.72))
    c.put(layer, ImageChops.multiply(m, clip), alpha=0.55)
    # The curly mop: overlapping round curls over the top.
    curls = [
        (-96, -64, 40), (-70, -96, 44), (-30, -116, 46), (16, -120, 46), (58, -104, 44), (92, -76, 40),
        (-100, -24, 30), (100, -30, 30), (-50, -80, 36), (0, -88, 38), (46, -78, 36),
    ]
    for dx, dy, r in curls:
        x, y = CX + dx, face.cy + dy
        c.ellipse((x - r, y - r, x + r, y + r), hair)
    for dx, dy, r in curls[:6]:
        x, y = CX + dx - r * 0.25, face.cy + dy - r * 0.3
        c.ellipse((x - r * 0.4, y - r * 0.32, x + r * 0.4, y + r * 0.32), shade(hair, 1.35), alpha=0.6)
    for dx in (-40, 0, 40):
        x, y = CX + dx, face.top + 40
        c.ellipse((x - 26, y - 22, x + 26, y + 22), hair)
    eyes(c, face, size=0.95)
    brows(c, face, hair, lift=(8, 2), width=10, tilt=-2)
    nose(c, face, skin)
    smile(c, face, width=56, y_off=2, tilt=4)
    return c.result()


def strand() -> Image.Image:
    """Helen Strand, The Pollster: a silver bun, round glasses, a pencil."""
    c = Canvas()
    skin = (246, 212, 188)
    hair = (214, 218, 230)
    face = Face(cy=228, rx=92, ry=104, jaw=0.2)
    # The bun on top.
    c.ellipse((CX - 58, 52, CX + 58, 150), shade(hair, 0.85))
    c.ellipse((CX - 50, 56, CX + 50, 140), hair)
    c.line(arc_pts(CX, 98, 34, 26, 200, 340), shade(hair, 0.8), 5)
    cardigan = (62, 148, 132)
    torso(c, 376, 440, cardigan)
    neck(c, face, skin, width=66)
    # Shirt collar points over the cardigan's V.
    c.poly([(CX - 52, 374), (CX + 52, 374), (CX, 470)], (248, 244, 236))
    for side in (-1, 1):
        c.poly([(CX + side * 4, 378), (CX + side * 54, 370), (CX + side * 40, 414)], (232, 228, 222))
        c.poly([(CX + side * 52, 374), (CX + side * 4, 474), (CX + side * 12, 530), (CX + side * 70, 400)], shade(cardigan, 0.8))
    for k in range(3):
        c.ellipse((CX - 26 - 7, 470 + k * 26, CX - 26 + 7, 484 + k * 26), (246, 230, 190))
    ears(c, face, skin)
    head(c, face, skin)
    # Swept-back silver hair.
    sweep = path(
        (CX - face.rx - 6, face.cy + 6),
        ((CX - face.rx - 10, face.top - 36), (CX + face.rx + 10, face.top - 36), (CX + face.rx + 6, face.cy + 6)),
        ((CX + face.rx * 0.8, face.top + 20), (CX + face.rx * 0.2, face.top + 14), (CX, face.top + 24)),
        ((CX - face.rx * 0.3, face.top + 10), (CX - face.rx * 0.9, face.top + 26), (CX - face.rx - 6, face.cy + 6)),
    )
    c.poly(sweep, hair)
    c.line(cubic((CX - 60, face.top - 2), (CX - 30, face.top - 14), (CX + 20, face.top - 14), (CX + 54, face.top), 14), shade(hair, 0.82), 4, alpha=0.8)
    # Pencil behind the right ear.
    ex, ey = CX + face.rx, face.eye_y() - 4
    c.poly(thick((ex - 30, ey - 34), (ex + 36, ey + 30), 14), (250, 196, 48))
    c.poly(thick((ex + 30, ey + 24), (ex + 44, ey + 38), 14), (232, 190, 160))
    c.poly(thick((ex - 30, ey - 34), (ex - 22, ey - 26), 14), (232, 120, 140))
    eyes(c, face, size=0.9)
    brows(c, face, shade(hair, 0.7), lift=(4, 4), width=7)
    nose(c, face, skin, 0.9)
    cheeks(c, face, (240, 120, 130), 0.35)
    smile(c, face, width=46, lips=(190, 90, 100))
    # Round glasses.
    y = face.eye_y()
    frame = (56, 52, 70)
    for side in (-1, 1):
        x = CX + side * face.eye_dx()
        c.ellipse((x - 30, y - 28, x + 30, y + 28), (220, 236, 255), alpha=0.25)
        ring = arc_pts(x, y, 29, 27, 0, 360, 48)
        c.line(ring, frame, 7, caps=False)
    c.line(cubic((CX - 14, y - 6), (CX - 6, y - 14), (CX + 6, y - 14), (CX + 14, y - 6), 8), frame, 6)
    for side in (-1, 1):
        c.line([(CX + side * (face.eye_dx() + 28), y - 6), (CX + side * (face.rx - 2), y - 10)], frame, 6)
    return c.result()


def begay() -> Image.Image:
    """Walt Begay, The Organizer: a field cap, gray mustache, flannel and vest."""
    c = Canvas()
    skin = (170, 108, 72)
    hair = (176, 176, 184)
    face = Face(cy=236, rx=96, ry=104, jaw=0.75)
    flannel = (196, 132, 52)
    t = torso(c, 378, 456, flannel)
    # Flannel checks, clipped to the shirt.
    clip = c.mask(t)
    for k in range(-6, 7):
        x = CX + k * 34
        c.poly([(x - 5, 360), (x + 5, 360), (x + 5, 530), (x - 5, 530)], shade(flannel, 0.72), clip=clip, alpha=0.7)
    for k in range(5):
        y = 396 + k * 34
        c.poly([(0, y - 5), (512, y - 5), (512, y + 5), (0, y + 5)], shade(flannel, 0.72), clip=clip, alpha=0.7)
    neck(c, face, skin, width=80)
    c.poly([(CX - 46, 380), (CX + 46, 380), (CX, 440)], shade(skin, 0.8))
    for side in (-1, 1):
        c.poly([(CX + side * 2, 386), (CX + side * 54, 372), (CX + side * 44, 424)], shade(flannel, 1.1))
    # Work vest with a pocket.
    vest = (92, 104, 82)
    for side in (-1, 1):
        c.poly([(CX + side * 70, 380), (CX + side * 200, 410), (CX + side * 214, 530), (CX + side * 50, 530), (CX + side * 40, 440)], vest)
        c.poly([(CX + side * 80, 460), (CX + side * 136, 462), (CX + side * 134, 500), (CX + side * 82, 498)], shade(vest, 0.8))
    ears(c, face, skin, y_off=4)
    head(c, face, skin)
    # Gray hair at the temples, under the cap.
    for side in (-1, 1):
        c.poly([(CX + side * (face.rx + 4), face.cy - 50), (CX + side * (face.rx - 16), face.cy - 50), (CX + side * (face.rx - 10), face.cy + 8), (CX + side * (face.rx + 6), face.cy + 4)], hair)
    # Smile lines.
    for side in (-1, 1):
        x = CX + side * 38
        c.line(cubic((x, face.eye_y() + 42), (x + side * 8, face.eye_y() + 58), (x + side * 8, face.eye_y() + 74), (x + side * 2, face.eye_y() + 86), 10), shade(skin, 0.8), 4)
    eyes(c, face, size=0.9)
    brows(c, face, hair, lift=(2, 2), width=11)
    nose(c, face, skin, 1.2)
    smile(c, face, width=48, y_off=8)
    # Mustache.
    my = face.eye_y() + 66
    c.poly(path((CX - 50, my + 18), ((CX - 40, my - 12), (CX + 40, my - 12), (CX + 50, my + 18)), ((CX + 20, my + 4), (CX - 20, my + 4), (CX - 50, my + 18))), hair)
    # The field cap: a dome and a bill.
    cap = (236, 112, 44)
    dome = path(
        (CX - face.rx - 8, face.top + 58),
        ((CX - face.rx - 10, face.top - 54), (CX + face.rx + 10, face.top - 54), (CX + face.rx + 8, face.top + 58)),
    )
    c.poly(dome, cap)
    c.poly(path((CX - face.rx - 8, face.top + 58), ((CX - 30, face.top + 40), (CX + 30, face.top + 40), (CX + face.rx + 8, face.top + 58)), (CX - face.rx - 8, face.top + 58)), shade(cap, 0.8))
    bill = path(
        (CX - face.rx + 6, face.top + 50),
        ((CX - 40, face.top + 30), (CX + 60, face.top + 30), (CX + face.rx + 40, face.top + 56)),
        ((CX + 70, face.top + 80), (CX - 40, face.top + 80), (CX - face.rx + 6, face.top + 50)),
    )
    c.poly(bill, shade(cap, 0.72))
    c.ellipse((CX - 7, face.top - 30, CX + 7, face.top - 16), shade(cap, 0.75))
    # A white patch with a star on it.
    px, py = CX, face.top + 12
    c.ellipse((px - 26, py - 22, px + 26, py + 22), (250, 246, 236))
    star = []
    for k in range(10):
        r = 16 if k % 2 == 0 else 7
        a = math.radians(-90 + k * 36)
        star.append((px + r * math.cos(a), py + 2 + r * math.sin(a)))
    c.poly(star, shade(cap, 0.85))
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


def preview(images: dict[str, Image.Image], out_dir: str):
    sizes = (40, 80, 160)
    pad = 16
    col_w = sum(sizes) + pad * (len(sizes) + 1)
    sheet = Image.new("RGBA", (col_w * 2, (160 + pad) * 4 + pad), STAGE + (255,))
    for i, (name, img) in enumerate(images.items()):
        ox = (i % 2) * col_w + pad
        oy = (i // 2) * (160 + pad) + pad
        x = ox
        for px in sizes:
            sheet.alpha_composite(plated(img, px), (x, oy + 160 - px))
            x += px + pad
    os.makedirs(out_dir, exist_ok=True)
    sheet.save(os.path.join(out_dir, "portraits-preview.png"))


def main():
    images = {}
    for name, draw in PORTRAITS.items():
        img = draw()
        img.save(os.path.join(HERE, f"{name}.png"), optimize=True)
        images[name] = img
    if "--preview" in sys.argv:
        preview(images, sys.argv[sys.argv.index("--preview") + 1])
    print(f"wrote {len(images)} portraits to {HERE}")


if __name__ == "__main__":
    main()
