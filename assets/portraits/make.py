"""Paints the candidates' portraits as campaign-trail snapshots (docs/DESIGN.md
D-068; names of D-097; the whiteboard of D-102 tapes them up as instant photos).

Run from the repository root:
    python3 assets/portraits/make.py [--preview DIR] [--photos PATH] [--review PATH]
Needs Pillow 11 (PIL). Writes, next to this script, one 512x512 PNG per
candidate in Sim/Candidates.luau, named by candidate id (okafor.png, ...),
painted 4x larger and scaled down. It also writes sheet.png, a labeled contact
sheet of all eight in Kit.portrait's round crop. --preview DIR writes that
sheet without labels to DIR/portraits-preview.png. --photos PATH writes how
UI/Board.photo tapes each one to the board at 48, 72 and 96 px. --review PATH
writes the review sheet: each at 512 with its name and genre, a 32/48/72 px
strip in color and in greyscale, and the round and square crops.

They are photographs, not marker drawings: the board's instant-photo card
(UI/Board.photo) frames them, so each is a full-bleed square snapshot with no
outlines. Form comes from soft light from one side; the setting behind each
person is out of focus; a color grade, a vignette and a little film grain
finish it. Kit.portrait clips the same square to a circle, so the face sits in
the middle of the inscribed circle.

Each is a believable person. The genre of politician is carried by the
setting, the light and the pose, never by a gag:
  okafor    Goldie Pennywhistle  The Fundraiser   gala ballroom, warm bokeh; leaning in, hand out to shake
  calloway  Buster Cannonball    The Barnstormer  outdoor rally, bunting stripes, crowd; mid-speech, fist up
  venkat    Mavis Glimmer        The Ad Wizard    TV studio, teal rim light; a camera-ready smile
  hale      Percy Quibble        The Debater      debate stage lights; squared to the lectern, finger raised
  alvarado  Opal Crumpet         The Insider      wood-panel hallway, a marble column; half in shadow
  reyes     Dash Kickflip        The Insurgent    a street at night, flash; off-axis, a hand-lettered sign
  strand    Esme Moonbeam        The Pollster     an office wall of crosstabs; glasses, cool fluorescent
  begay     Gus Bramble          The Organizer    a leafy street, panning blur; clipboard and lanyard

All eight are fictional. Faces differ through ordinary features (face shape,
hair, age, glasses, clothes, expression); no real person, party, flag, seal,
logo or slogan appears. Every random choice comes from a random.Random seeded
by the id, so the same code always paints the same pictures.
"""

from __future__ import annotations

import contextlib
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "..", "..", "tests", "lib", "fonts")

OUT = 512  # px, the shipped size
SS = 4  # supersampling factor
W = OUT * SS
CX = 256

WHITE = (255, 255, 255)
SCLERA = (232, 226, 218)
MOUTH_IN = (70, 26, 30)
TEETH = (236, 230, 220)


# ---------------------------------------------------------------- geometry


def cubic(p0, p1, p2, p3, n: int = 24) -> list:
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


def path(start, *segs) -> list:
    """An outline: segments are (x, y) lines or ((c1), (c2), (end)) cubics."""
    pts = [start]
    for seg in segs:
        if isinstance(seg[0], tuple):
            pts.extend(cubic(pts[-1], seg[0], seg[1], seg[2]))
        else:
            pts.append(seg)
    return pts


def ell(cx, cy, rx, ry, a0=0.0, a1=360.0, n=96) -> list:
    return [
        (cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
        for i in range(n + 1)
    ]


def rect(x0, y0, x1, y1) -> list:
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def rrect(x0, y0, x1, y1, r) -> list:
    pts = []
    for cx, cy, a in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        pts += ell(cx, cy, r, r, a, a + 90, 12)
    return pts


def turn(pts, deg, about) -> list:
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    ox, oy = about
    return [(ox + (x - ox) * c - (y - oy) * s, oy + (x - ox) * s + (y - oy) * c) for x, y in pts]


def head_outline(cx, cy, rx, ry, jaw=0.0, taper=0.0, n=120) -> list:
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


# ---------------------------------------------------------------- color


def shade(c, k: float):
    """k < 1 darkens, k > 1 lightens toward white."""
    if k <= 1:
        return tuple(int(v * k) for v in c[:3])
    t = k - 1
    return tuple(int(v + (255 - v) * t) for v in c[:3])


def mix(a, b, t: float):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ---------------------------------------------------------------- masks


def blur(m: Image.Image, r: float) -> Image.Image:
    """Gaussian blur of an L mask by `r` drawing units (fast for big radii)."""
    px = r * SS
    if px <= 0:
        return m
    if px < 10:
        return m.filter(ImageFilter.GaussianBlur(px))
    small = m.resize((W // 4, W // 4), Image.Resampling.BILINEAR).filter(ImageFilter.GaussianBlur(px / 4))
    return small.resize((W, W), Image.Resampling.BICUBIC)


def moved(m: Image.Image, dx: float, dy: float) -> Image.Image:
    out = Image.new("L", m.size, 0)
    out.paste(m, (int(dx * SS), int(dy * SS)))
    return out


def scale_mask(m: Image.Image, k: float) -> Image.Image:
    return m.point(lambda v: int(v * k)) if k < 1 else m


# ---------------------------------------------------------------- the brush


class Brush:
    """A 512-unit picture painted at 4x: soft-edged fills, light and shadow
    that follow each shape's form, soft strokes. `rotated` turns everything
    painted inside it about a point (a head's tilt); `layer` paints onto a
    fresh transparent sheet."""

    def __init__(self, seed: str, light=(-0.7, -0.7)):
        self.rng = random.Random(seed)
        self.img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        self.light = light  # unit-ish vector toward the key light (screen coords)
        self._rot: tuple[float, tuple[float, float]] | None = None

    @contextlib.contextmanager
    def rotated(self, deg: float, about):
        old = self._rot
        self._rot = (deg, about)
        try:
            yield
        finally:
            self._rot = old

    @contextlib.contextmanager
    def layer(self):
        old = self.img
        self.img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        box: list[Image.Image] = []
        try:
            yield box
        finally:
            box.append(self.img)
            self.img = old

    def tf(self, pts) -> list:
        if self._rot is None:
            return list(pts)
        return turn(pts, self._rot[0], self._rot[1])

    @staticmethod
    def big(pts) -> list:
        return [(x * SS, y * SS) for x, y in pts]

    def mask(self, pts, soft: float = 0.0) -> Image.Image:
        m = Image.new("L", (W, W), 0)
        ImageDraw.Draw(m).polygon(self.big(self.tf(pts)), fill=255)
        return blur(m, soft) if soft else m

    def line_mask(self, pts, w: float, soft: float = 0.0, taper: float = 0.0) -> Image.Image:
        m = Image.new("L", (W, W), 0)
        d = ImageDraw.Draw(m)
        p = self.big(self.tf(pts))
        n = len(p)
        for i, (a, b) in enumerate(zip(p, p[1:])):
            ww = w
            if taper:
                u = i / max(n - 2, 1)
                edge = min(u, 1 - u) / 0.3
                if edge < 1:
                    ww = w * (1 - taper + taper * edge)
            r = ww * SS / 2
            d.line((a, b), fill=255, width=max(1, int(ww * SS)))
            d.ellipse((b[0] - r, b[1] - r, b[0] + r, b[1] + r), fill=255)
        return blur(m, soft) if soft else m

    def paint(self, m: Image.Image, color, alpha: float = 1.0, clip: Image.Image | None = None):
        if clip is not None:
            m = ImageChops.multiply(m, clip)
        if alpha < 1:
            m = scale_mask(m, alpha)
        box = m.getbbox()
        if box is None:
            return
        part = m.crop(box)
        sheet = Image.new("RGBA", part.size, tuple(color[:3]) + (255,))
        sheet.putalpha(part)
        self.img.alpha_composite(sheet, box[:2])

    def fill(self, pts, color, alpha: float = 1.0, clip=None, soft: float = 0.5) -> Image.Image:
        m = self.mask(pts, soft)
        self.paint(m, color, alpha, clip)
        return m

    def form(self, m: Image.Image, color, depth: float = 30.0, dark: float = 0.62, lite: float = 1.22, dk_a: float = 0.85, lt_a: float = 0.45, light=None):
        """Light and shade on a shape already painted with mask `m`: the side
        away from the light falls into shadow over about `depth` units, the
        side toward it catches a soft highlight."""
        lx, ly = light or self.light
        away = ImageChops.subtract(m, moved(m, lx * depth, ly * depth))
        self.paint(blur(away, depth * 0.55), shade(color, dark), dk_a, clip=m)
        toward = ImageChops.subtract(m, moved(m, -lx * depth * 0.6, -ly * depth * 0.6))
        self.paint(blur(toward, depth * 0.45), shade(color, lite), lt_a, clip=m)

    def solid(self, pts, color, depth=30.0, soft=0.6, **kw) -> Image.Image:
        """A filled shape with its form shading."""
        m = self.fill(pts, color, soft=soft)
        self.form(m, color, depth, **kw)
        return m

    def stroke(self, pts, w: float, color, alpha: float = 1.0, soft: float = 0.6, taper: float = 0.0, clip=None):
        self.paint(self.line_mask(pts, w, soft, taper), color, alpha, clip)

    def blob(self, x, y, rx, ry, color, alpha=1.0, soft=6.0, clip=None):
        self.paint(self.mask(ell(x, y, rx, ry, n=48), soft), color, alpha, clip)

    def text(self, xy, s: str, size: float, color, angle=0.0, font="PermanentMarker-Regular.ttf", alpha=1.0, soft=0.3):
        f = ImageFont.truetype(os.path.join(FONTS, font), int(size * SS))
        sheet = Image.new("L", (W, W), 0)
        ImageDraw.Draw(sheet).text((xy[0] * SS, xy[1] * SS), s, font=f, fill=255, anchor="mm")
        if angle:
            sheet = sheet.rotate(-angle, center=(xy[0] * SS, xy[1] * SS), resample=Image.Resampling.BICUBIC)
        self.paint(blur(sheet, soft), color, alpha)

    def under(self, sheet: Image.Image, r: float):
        """Composites `sheet` (a finished layer) blurred by `r` units."""
        if r:
            small = sheet.resize((W // 4, W // 4), Image.Resampling.BILINEAR).filter(ImageFilter.GaussianBlur(r))
            sheet = small.resize((W, W), Image.Resampling.BICUBIC)
        self.img.alpha_composite(sheet)


def gradient(c_top, c_bottom, angle=90.0) -> Image.Image:
    """A full-frame RGBA linear gradient (angle 90 = top to bottom)."""
    g = Image.linear_gradient("L").resize((W, W))
    if angle != 90:
        g = g.rotate(90 - angle, resample=Image.Resampling.BICUBIC, expand=False, fillcolor=255)
    top = Image.new("RGBA", (W, W), tuple(c_top) + (255,))
    bot = Image.new("RGBA", (W, W), tuple(c_bottom) + (255,))
    return Image.composite(bot, top, g)


def radial(b: Brush, x, y, r, color, alpha=1.0):
    """A soft round glow."""
    b.paint(blur(b.mask(ell(x, y, r * 0.5, r * 0.5, n=48)), r * 0.45), color, alpha)


def bokeh(b: Brush, rng: random.Random, n, box, rmin, rmax, colors, alpha=(0.25, 0.6)):
    """Out-of-focus lights: soft disks with a slightly brighter rim."""
    x0, y0, x1, y1 = box
    for _ in range(n):
        x, y, r = rng.uniform(x0, x1), rng.uniform(y0, y1), rng.uniform(rmin, rmax)
        c = rng.choice(colors)
        a = rng.uniform(*alpha)
        b.paint(b.mask(ell(x, y, r, r, n=40), r * 0.12), c, a * 0.75)
        ring = ImageChops.subtract(b.mask(ell(x, y, r, r, n=40)), b.mask(ell(x, y, r * 0.86, r * 0.86, n=40)))
        b.paint(blur(ring, r * 0.06), shade(c, 1.2), a * 0.5)


def finish(img: Image.Image, seed: str, tint=(1.0, 1.0, 1.0), lift=0, contrast=1.06, vignette=0.32, grain=7.0) -> Image.Image:
    """Down to 512 and made into a snapshot: grade, vignette, film grain."""
    small = img.resize((OUT, OUT), Image.Resampling.LANCZOS).convert("RGB")
    r, g, bch = small.split()

    def curve(k):
        return lambda v: max(0, min(255, int(((v / 255 - 0.5) * contrast + 0.5) * 255 * k + lift)))

    small = Image.merge("RGB", (r.point(curve(tint[0])), g.point(curve(tint[1])), bch.point(curve(tint[2]))))
    # Vignette: darker toward the corners.
    v = Image.radial_gradient("L").resize((OUT, OUT), Image.Resampling.BICUBIC)
    v = v.point(lambda p: int(255 * max(0.0, (p / 255 - 0.55) / 0.45) ** 1.6 * vignette))
    small = Image.composite(Image.new("RGB", (OUT, OUT), (12, 10, 14)), small, v)
    # Grain: seeded noise, a touch stronger in the shadows.
    rng = random.Random(f"grain:{seed}")
    noise = Image.new("L", (OUT, OUT))
    noise.putdata([max(0, min(255, int(128 + rng.gauss(0, grain)))) for _ in range(OUT * OUT)])
    noise = noise.filter(ImageFilter.GaussianBlur(0.45))
    out = ImageChops.add(small, Image.merge("RGB", (noise,) * 3), 1.0, -128)
    return out.convert("RGBA")


# ---------------------------------------------------------------- a person


class Face:
    """Where a head sits; features are laid out from it. `look` turns the face
    a little toward the viewer's right (+) or left (-): features slide over and
    the far eye narrows."""

    def __init__(self, hx=256.0, hy=214.0, rx=80.0, ry=100.0, jaw=0.2, taper=0.18, look=0.0):
        self.hx, self.hy, self.rx, self.ry = hx, hy, rx, ry
        self.jaw, self.taper, self.look = jaw, taper, look
        self.outline = head_outline(hx, hy, rx, ry, jaw, taper)

    def x(self, off: float) -> float:
        return self.hx + off + self.look * self.rx * 0.22

    @property
    def top(self):
        return self.hy - self.ry

    @property
    def chin(self):
        return self.hy + self.ry * (1 - 0.06 * self.jaw)

    @property
    def eye_y(self):
        return self.hy + self.ry * 0.04

    @property
    def eye_dx(self):
        return self.rx * 0.39

    @property
    def nose_y(self):
        return self.hy + self.ry * 0.38

    @property
    def mouth_y(self):
        return self.hy + self.ry * 0.6

    def far(self, side: int) -> float:
        if self.look == 0:
            return 1.0
        return 1 - 0.22 * abs(self.look) if side * self.look > 0 else 1.0

    def ex(self, side: int) -> float:
        k = self.far(side)
        return self.x(side * self.eye_dx * (k if side * self.look > 0 else 1))


def neck(b: Brush, f: Face, skin, half=30.0, bottom=420.0, dx=0.0) -> Image.Image:
    top = f.chin - 50
    pts = [(f.hx - half + dx * 0.3, top), (f.hx + half + dx * 0.3, top), (f.hx + half + 8 + dx, bottom), (f.hx - half - 8 + dx, bottom)]
    m = b.solid(pts, shade(skin, 0.92), depth=18)
    # The chin's cast shadow.
    cast = b.mask(head_outline(f.hx + b.light[0] * -8, f.hy + 26, f.rx * 0.95, f.ry, f.jaw, f.taper), 6)
    b.paint(cast, shade(skin, 0.55), 0.75, clip=m)
    return m


def ears(b: Brush, f: Face, skin):
    y = f.eye_y + 14
    for side in (-1, 1):
        if f.far(side) < 1:
            continue
        x = f.hx + side * (f.rx - 6) + f.look * f.rx * 0.1
        m = b.solid(ell(x, y, 15, 25), skin, depth=10)
        b.blob(x - side * 2, y + 2, 6, 13, shade(skin, 0.62), 0.7, 3, clip=m)


def head(b: Brush, f: Face, skin) -> Image.Image:
    """Skin with its form: shadow side, lit side, eye sockets, cheeks."""
    m = b.fill(f.outline, skin, soft=0.6)
    b.form(m, skin, depth=f.rx * 0.6, dark=0.58, lite=1.22, dk_a=0.9, lt_a=0.45)
    lx = b.light[0]
    # Skin's sheen where the light lands: forehead, the lit cheekbone, the chin.
    b.blob(f.x(lx * 22), f.hy - f.ry * 0.5, 30, 16, shade(skin, 1.3), 0.35, 10, clip=m)
    b.blob(f.x(lx * 50), f.eye_y + 26, 16, 10, shade(skin, 1.3), 0.35, 7, clip=m)
    b.blob(f.x(0), f.chin - 14, 16, 8, shade(skin, 1.2), 0.25, 6, clip=m)
    for side in (-1, 1):
        x = f.ex(side)
        b.blob(x, f.eye_y - 4, 26 * f.far(side), 16, shade(skin, 0.7), 0.5, 7, clip=m)
        b.blob(f.x(side * 46), f.mouth_y - 22, 20, 13, mix(skin, (210, 90, 90), 0.4), 0.22, 9, clip=m)
    # Under the jaw and the temple.
    b.blob(f.hx, f.chin + 10, f.rx * 0.8, 20, shade(skin, 0.6), 0.5, 10, clip=m)
    return m


def eyes(b: Brush, f: Face, skin, iris=(78, 52, 34), w=30.0, h=11.0, look=(0.0, 0.0), lid=0.0, lash=(28, 20, 20), crinkle=0, bags=False):
    y = f.eye_y
    line = shade(skin, 0.42)
    for side in (-1, 1):
        k = f.far(side)
        x = f.ex(side)
        ww, hh = w * k, h
        up = [(x - ww / 2, y + 1)] + cubic((x - ww / 2, y + 1), (x - ww / 4, y - hh * 1.25), (x + ww / 4, y - hh * 1.3), (x + ww / 2, y - 1), 16)
        lo = cubic((x + ww / 2, y - 1), (x + ww / 4, y + hh * 0.85), (x - ww / 4, y + hh * 0.85), (x - ww / 2, y + 1), 16)
        almond = up + lo
        clip = b.mask(almond, 0.3)
        b.paint(clip, SCLERA)
        ix, iy, r = x + look[0], y - hh * 0.1 + look[1], hh * 0.98
        b.fill(ell(ix, iy, r, r, n=32), iris, clip=clip, soft=0.4)
        b.fill(ell(ix, iy, r * 0.62, r * 0.62, n=32), shade(iris, 1.25), alpha=0.35, clip=clip, soft=1.2)
        b.fill(ell(ix, iy, r * 0.42, r * 0.42, n=24), (14, 12, 12), clip=clip, soft=0.3)
        # The lid's shadow over the top of the eye.
        top_shadow = b.mask(rect(x - ww, y - hh * 2, x + ww, y - hh * 0.35), 2.2)
        b.paint(top_shadow, shade(skin, 0.45), 0.45, clip=clip)
        if lid > 0:
            lowered = [(px, py + lid * hh * 1.5 * (1 - abs(px - x) / (ww / 2 + 1)) + lid * 2) for px, py in up]
            b.fill(lowered + [(x + ww / 2 + 2, y - hh * 2), (x - ww / 2 - 2, y - hh * 2)], shade(skin, 0.92), clip=clip, soft=0.5)
            up = lowered
        b.fill(ell(ix + r * 0.35, iy - r * 0.38, r * 0.22, r * 0.22, n=16), WHITE, clip=clip, soft=0.2)
        b.stroke(up, 3.4, lash, soft=0.5, taper=0.5)
        b.stroke(lo[3:-3], 1.4, line, 0.6, soft=0.6, taper=0.6)
        b.stroke(cubic((x - ww * 0.42, y - hh * 1.15), (x - ww * 0.2, y - hh * 1.85), (x + ww * 0.2, y - hh * 1.9), (x + ww * 0.45, y - hh * 1.2), 10), 1.8, line, 0.45, soft=1.0, taper=0.5)
        for c in range(crinkle):
            ox = x + side * (ww / 2 + 5)
            b.stroke([(ox, y - 2 + c * 6), (ox + side * 10, y - 5 + c * 8)], 1.4, line, 0.4, soft=0.8, taper=0.5)
        if bags:
            b.stroke(cubic((x - ww * 0.3, y + hh * 1.3), (x - ww * 0.1, y + hh * 1.8), (x + ww * 0.15, y + hh * 1.8), (x + ww * 0.35, y + hh * 1.25), 8), 1.6, line, 0.35, soft=1, taper=0.5)


def brows(b: Brush, f: Face, color, w=6.0, lift=(0.0, 0.0), arch=6.0, inner=(0.0, 0.0), length=1.0, alpha=0.9):
    y = f.eye_y - f.ry * 0.22
    for k, side in enumerate((-1, 1)):
        sc = f.far(side)
        x = f.ex(side)
        half = 19 * length * sc
        a = (x - side * half, y + 3 + inner[k] - lift[k] * 0.4)
        e = (x + side * half * 1.05, y + 4 - lift[k] * 0.6)
        pts = [a] + cubic(a, (x - side * half * 0.3, y - arch - lift[k]), (x + side * half * 0.5, y - arch - lift[k]), e, 14)
        b.stroke(pts, w, color, alpha, soft=1.0, taper=0.6)
        b.stroke(pts, w * 0.5, shade(color, 0.7), alpha * 0.6, soft=0.6, taper=0.7)


def nose(b: Brush, f: Face, skin, size=1.0, clip=None):
    y = f.nose_y
    x = f.x(f.look * 6)
    lx = b.light[0]
    s = -1 if lx > 0 else 1  # the shadow side
    side_shadow = [(x + s * 3, f.eye_y + 4), (x + s * 13 * size, y - 6), (x + s * 18 * size, y + 4), (x + s * 2, y + 4)]
    b.fill(side_shadow, shade(skin, 0.68), 0.55, clip=clip, soft=4)
    b.stroke([(x - s * 4, f.eye_y + 10), (x - s * 3, y - 10)], 5 * size, shade(skin, 1.22), 0.45, soft=2.5)
    b.blob(x, y + 13, 16 * size, 4, shade(skin, 0.7), 0.3, 4, clip=clip)
    for side in (-1, 1):
        b.blob(x + side * 8 * size, y + 6, 3.6 * size, 2.2, shade(skin, 0.45), 0.5, 1.2)
    b.blob(x - s * 2, y + 1, 10 * size, 7, shade(skin, 1.15), 0.35, 3)


def mouth(b: Brush, f: Face, skin, kind="smile", w=40.0, lips=None, open_=1.0, tilt=0.0, dy=0.0):
    """kind: smile, grin, speech, composed, smirk, set."""
    y = f.mouth_y + dy
    x = f.x(f.look * 8)
    lips = lips or mix(skin, (150, 60, 70), 0.3)
    dark = shade(lips, 0.5)
    L, R = (x - w / 2, y - tilt), (x + w / 2, y + tilt)
    if kind in ("grin", "speech"):
        depth = (17 if kind == "grin" else 24) * open_
        top_dip = 3 if kind == "grin" else -2
        lift = -5 if kind == "grin" else 0
        L, R = (L[0], L[1] + lift), (R[0], R[1] + lift)
        top = cubic(L, (x - w / 4, y + top_dip), (x + w / 4, y + top_dip), R, 14)
        bot = cubic(R, (x + w / 3, y + depth), (x - w / 3, y + depth), L, 14)
        pts = [L] + top + bot
        # Lips around the opening.
        b.fill([L] + cubic(L, (x - w / 4, y - 9), (x + w / 4, y - 9), R, 14) + list(reversed(top)), lips, soft=1.0)
        b.fill([R] + cubic(R, (x + w / 3, y + depth + 10), (x - w / 3, y + depth + 10), L, 14) + list(reversed(bot)), shade(lips, 1.08), soft=1.0)
        clip = b.mask(pts, 0.4)
        b.paint(clip, MOUTH_IN)
        b.fill(rect(x - w, y - 20, x + w, y + top_dip + 5), TEETH, clip=clip, soft=0.4)
        b.fill(rect(x - w, y - 20, x + w, y + top_dip - 2), (180, 172, 164), 0.6, clip=clip, soft=1.5)
        b.blob(x, y + depth * 0.95, w * 0.28, depth * 0.36, (160, 80, 84), 0.9, 2, clip=clip)
        b.blob(x, y + depth + 8, w * 0.22, 3, shade(lips, 1.3), 0.35, 2)
    else:
        if kind == "composed":
            seam = [L] + cubic(L, (x - w / 4, y + 3), (x + w / 4, y + 3), R, 14)
            top_h, bot_h = 9, 12
        elif kind == "smile":
            ctrl = 8 * open_
            seam = [(L[0], L[1] - 3)] + cubic((L[0], L[1] - 3), (x - w / 4, y + ctrl), (x + w / 4, y + ctrl), (R[0], R[1] - 3), 14)
            top_h, bot_h = 6, 10
        elif kind == "smirk":
            seam = [(L[0], L[1] + 1)] + cubic((L[0], L[1] + 1), (x - w / 4, y + 3), (x + w / 4, y + 3), (R[0] + 3, R[1] - 7), 14)
            top_h, bot_h = 6, 10
        else:
            seam = [(L[0], L[1] + 2)] + cubic((L[0], L[1] + 2), (x - w / 4, y - 2), (x + w / 4, y - 2), (R[0], R[1] + 2), 14)
            top_h, bot_h = 5, 9
        a, e = seam[0], seam[-1]
        upper = seam + list(reversed([a] + cubic(a, (x - w / 4, y - top_h - 2), (x - 2, y - top_h), (x, y - top_h + 3), 8) + cubic((x, y - top_h + 3), (x + 2, y - top_h), (x + w / 4, y - top_h - 2), e, 8)))
        lower = seam + list(reversed([a] + cubic(a, (x - w / 4, y + bot_h + 4), (x + w / 4, y + bot_h + 4), e, 14)))
        b.fill(lower, shade(lips, 1.06), soft=1.0)
        b.fill(upper, shade(lips, 0.88), soft=0.8)
        b.blob(x + 4, y + bot_h * 0.5, w * 0.16, 2.6, shade(lips, 1.4), 0.4, 1.5)
        b.stroke(seam, 2.2, dark, 0.9, soft=0.6, taper=0.4)
        for side in (-1, 1):
            cx = (a if side < 0 else e)[0]
            cy = (a if side < 0 else e)[1]
            b.blob(cx + side * 2, cy - 1, 3.5, 3.5, shade(skin, 0.6), 0.5, 1.5)
    b.blob(x, y + 24, w * 0.32, 6, shade(skin, 0.7), 0.4, 4)


def torso(b: Brush, color, top=372.0, half=210.0, neck_half=52.0, drop=58.0, cx=CX, tilt=0.0, depth=60.0) -> Image.Image:
    """Shoulders: a wide rounded bell from the neck down past the bottom edge.
    `tilt` drops the right shoulder (+) or the left (-)."""
    pts = []
    for side in (-1, 1):
        t = top + tilt * side
        pts.append(path(
            (cx + side * neck_half, t - 4),
            ((cx + side * (neck_half + 50), t), (cx + side * (half - 18), t + drop - 26), (cx + side * half, t + drop + 26)),
            (cx + side * (half + 14), 560),
        ))
    outline = pts[0] + list(reversed(pts[1]))
    return b.solid(outline, color, depth=depth, dark=0.55, lite=1.25)


def lapels(b: Brush, cx, top, jacket, shirt, spread=46, depth=96):
    """A jacket's opening: the shirt as a V and two lapels over it."""
    b.solid([(cx - spread + 4, top - 6), (cx + spread - 4, top - 6), (cx, top + depth)], shirt, depth=14)
    for side in (-1, 1):
        flap = [(cx + side * spread, top - 8), (cx + side * 8, top + depth + 6), (cx + side * 30, top + depth + 34), (cx + side * (spread + 52), top + 30)]
        b.solid(flap, shade(jacket, 1.08), depth=12)
        b.stroke([flap[0], flap[1]], 2.4, shade(jacket, 0.5), 0.7, soft=1.2)


def hand(b: Brush, x, y, skin, sleeve, cuff=None, open_palm=True, scale=1.0, angle=0.0, rolled=False):
    """A forearm rising from the bottom edge to a hand at (x, y): an open palm
    held up (`open_palm`, "a point of order") or a fist."""
    s = scale
    line = shade(skin, 0.55)
    with b.rotated(angle, (x, y + 60 * s)):
        if rolled:
            b.solid([(x - 46 * s, y + 130 * s), (x + 44 * s, y + 130 * s), (x + 62 * s, 600), (x - 64 * s, 600)], sleeve, depth=24)
            b.solid([(x - 28 * s, y + 30 * s), (x + 26 * s, y + 30 * s), (x + 34 * s, y + 136 * s), (x - 36 * s, y + 136 * s)], skin, depth=16)
            b.solid(rrect(x - 48 * s, y + 116 * s, x + 46 * s, y + 150 * s, 14 * s), shade(sleeve, 1.12), depth=10)
        else:
            b.solid([(x - 34 * s, y + 52 * s), (x + 30 * s, y + 52 * s), (x + 50 * s, 600), (x - 52 * s, 600)], sleeve, depth=22)
            if cuff:
                b.solid(rect(x - 34 * s, y + 44 * s, x + 30 * s, y + 60 * s), cuff, depth=6)
        if open_palm:
            # Four fingers together, the thumb out to the side, palm to the camera.
            for k, (dx, top) in enumerate(((-24, -40), (-10, -50), (4, -48), (17, -36))):
                b.solid(rrect(x + dx * s, y + top * s, x + (dx + 13) * s, y + 10 * s, 6.5 * s), skin, depth=6)
            b.solid(rrect(x - 26 * s, y - 6 * s, x + 30 * s, y + 52 * s, 16 * s), skin, depth=14)
            for k in range(3):
                b.stroke([(x + (-11 + k * 14) * s, y - 30 * s), (x + (-11 + k * 14) * s, y - 4 * s)], 1.3, line, 0.45, soft=1)
            b.stroke(cubic((x - 10 * s, y + 40 * s), (x - 4 * s, y + 20 * s), (x + 4 * s, y + 10 * s), (x + 20 * s, y + 4 * s), 10), 1.4, line, 0.4, soft=1.2)
            with b.rotated(angle - 35, (x - 24 * s, y + 30 * s)):
                b.solid(rrect(x - 36 * s, y - 6 * s, x - 20 * s, y + 40 * s, 8 * s), skin, depth=6)
        else:
            b.solid(rrect(x - 32 * s, y - 16 * s, x + 28 * s, y + 50 * s, 18 * s), skin, depth=16)
            for k in range(4):
                fx = x - 30 * s + k * 15 * s
                b.stroke(ell(fx + 7 * s, y - 10 * s, 7 * s, 9 * s, 180, 360, 10), 1.6, line, 0.55, soft=1)
            for k in range(3):
                fx = x - 16 * s + k * 15 * s
                b.stroke([(fx, y - 16 * s), (fx, y + 4 * s)], 1.6, line, 0.55, soft=1)
            b.solid(rrect(x - 46 * s, y + 4 * s, x - 22 * s, y + 40 * s, 11 * s), skin, depth=8)


def rim(b: Brush, sheet: Image.Image, color, direction=(1.0, 0.0), width=6.0, alpha=0.8):
    """A back light catching the edge of everything on `sheet` on the side
    `direction` points to."""
    a = sheet.getchannel("A")
    edge = ImageChops.subtract(a, moved(a, direction[0] * width, direction[1] * width))
    b.paint(blur(edge, width * 0.4), color, alpha, clip=a)


def motion(sheet: Image.Image, r: float) -> Image.Image:
    """A horizontal blur of about `r` units: the background of a panning shot."""
    k = max(1, int(r * SS / 3))
    return sheet.resize((max(8, W // k), W), Image.Resampling.BOX).resize((W, W), Image.Resampling.BICUBIC)


def strands(b: Brush, rng, clip, curves, color, alpha=0.22, w=1.1, n=3):
    for pts in curves:
        for _ in range(n):
            dx = rng.uniform(-5, 5)
            jitter = [(px + dx + rng.uniform(-1.5, 1.5), py + rng.uniform(-1.5, 1.5)) for px, py in pts]
            b.stroke(jitter, w * rng.uniform(0.7, 1.3), color, alpha * rng.uniform(0.6, 1), soft=0.5, taper=0.6, clip=clip)


# ---------------------------------------------------------------- the eight


def okafor() -> Image.Image:
    """Goldie Pennywhistle, The Fundraiser: a gala ballroom's warm bokeh,
    leaning in with a big welcoming smile, a hand already out to shake."""
    b = Brush("portrait:okafor", light=(-0.6, -0.8))
    rng = random.Random("okafor")
    skin, hair = (122, 74, 50), (30, 22, 24)
    gown, gold = (104, 36, 62), (214, 168, 84)
    with b.layer() as bg:
        b.img.alpha_composite(gradient((58, 34, 30), (120, 74, 44)))
        radial(b, 120, 60, 260, (250, 200, 120), 0.55)
        radial(b, 430, 120, 160, (236, 170, 96), 0.4)
        bokeh(b, rng, 30, (0, 0, 512, 330), 14, 40, [(255, 214, 140), (250, 190, 110), (255, 236, 190)], (0.3, 0.75))
        b.fill(rect(0, 330, 512, 512), (70, 40, 34), 0.5, soft=30)
    b.under(bg[0], 5)
    f = Face(hx=272, hy=222, rx=82, ry=106, jaw=0.05, taper=0.28)
    tilt = 8
    torso(b, gown, top=366, half=204, neck_half=62, cx=274, tilt=-6)
    b.solid([(228, 358), (320, 358), (288, 446), (262, 450)], shade(skin, 0.95), depth=16)
    neck(b, f, skin, half=34, bottom=380)
    b.stroke(cubic((238, 374), (248, 412), (302, 412), (310, 374), 20), 3.2, gold, soft=0.6)
    b.blob(274, 414, 7, 9, gold, 1, 1)
    b.blob(272, 411, 3, 3, (255, 240, 200), 0.8, 1)
    with b.rotated(tilt, (f.hx, f.chin + 20)):
        back = path((f.hx - 88, f.hy + 10), ((f.hx - 102, f.hy - 80), (f.hx - 60, f.top - 26), (f.hx, f.top - 28)),
                    ((f.hx + 64, f.top - 26), (f.hx + 102, f.hy - 80), (f.hx + 90, f.hy + 6)))
        b.solid(back, hair, depth=30, lite=1.6, lt_a=0.35)
        bun = ell(f.hx - 4, f.top - 48, 64, 48)
        bm = b.solid(bun, hair, depth=26, lite=1.7, lt_a=0.4)
        strands(b, rng, bm, [cubic((f.hx - 4 + k * 7, f.top - 96 + abs(k) * 1.5), (f.hx - 4 + k * 9, f.top - 70), (f.hx - 4 + k * 9, f.top - 30), (f.hx - 4 + k * 8, f.top - 2), 10) for k in range(-8, 9)], shade(hair, 2.0), 0.16, 2.0, 1)
        ears(b, f, skin)
        for side in (-1, 1):
            hx = f.hx + side * (f.rx - 4)
            b.stroke(ell(hx, f.eye_y + 50, 11, 15, n=30), 3, gold, soft=0.5)
        head(b, f, skin)
        cap = path((f.hx - f.rx - 4, f.hy + 6), ((f.hx - f.rx - 8, f.top - 60), (f.hx + f.rx + 8, f.top - 60), (f.hx + f.rx + 4, f.hy + 6)),
                   ((f.hx + f.rx * 0.8, f.hy - 46), (f.hx + 20, f.top + 22), (f.hx - 6, f.top + 22)),
                   ((f.hx - 40, f.top + 22), (f.hx - f.rx * 0.8, f.hy - 46), (f.hx - f.rx - 4, f.hy + 6)))
        cm = b.solid(cap, hair, depth=24, lite=1.7, lt_a=0.35)
        strands(b, rng, cm, [cubic((f.hx + k * 18, f.top + 20), (f.hx + k * 22, f.top), (f.hx + k * 12, f.top - 14), (f.hx + k * 6, f.top - 22), 8) for k in range(-4, 5)], shade(hair, 2.2), 0.22, 2.0)
        drop = path((f.hx - 84, f.hy - 10), ((f.hx - 104, f.hy + 60), (f.hx - 100, f.hy + 140), (f.hx - 92, f.hy + 172)), (f.hx - 62, f.hy + 172),
                    ((f.hx - 70, f.hy + 120), (f.hx - 72, f.hy + 50), (f.hx - 66, f.hy)))
        dm = b.solid(drop, hair, depth=14, lite=1.6, lt_a=0.35)
        strands(b, rng, dm, [cubic((f.hx - 92 + k * 9, f.hy + 6), (f.hx - 98 + k * 9, f.hy + 70), (f.hx - 92 + k * 9, f.hy + 120), (f.hx - 88 + k * 9, f.hy + 168), 10) for k in range(4)], shade(hair, 2.2), 0.25, 2.2)
        eyes(b, f, skin, iris=(60, 36, 24), w=30, h=11, look=(-2, 0), crinkle=2)
        brows(b, f, hair, w=5.5, lift=(6, 6), arch=7)
        nose(b, f, skin, 1.05)
        mouth(b, f, skin, "grin", w=50, lips=(112, 54, 56))
    return finish(b.img, "okafor", tint=(1.07, 1.0, 0.88), lift=2, contrast=1.1, vignette=0.4)


def calloway() -> Image.Image:
    """Buster Cannonball, The Barnstormer: an outdoor rally under striped
    bunting, the crowd behind him; mid-speech, collar open, sleeves rolled,
    a fist up."""
    b = Brush("portrait:calloway", light=(0.7, -0.7))
    rng = random.Random("calloway")
    skin, hair = (236, 186, 152), (170, 88, 50)
    shirt = (112, 140, 172)
    red, cream = (222, 158, 58), (244, 236, 216)  # county-fair mustard and cream
    with b.layer() as bg:
        b.img.alpha_composite(gradient((132, 178, 222), (226, 228, 222)))
        radial(b, 470, 20, 300, (255, 250, 230), 0.6)
        # Bunting: striped swags draped between nails along the top.
        for k in range(4):
            x0, x1 = -60 + k * 180, 120 + k * 180
            for band, col in enumerate((red, cream, red)):
                top_ = [(x, 4 + band * 18 + 50 * math.sin(math.pi * (x - x0) / (x1 - x0))) for x in [x0 + t * (x1 - x0) / 24 for t in range(25)]]
                bot_ = [(x, y + 20) for x, y in top_]
                m = b.fill(top_ + list(reversed(bot_)), col, soft=0.8)
                b.form(m, col, 10, dark=0.72, lite=1.1, light=(0, -1))
            b.blob(x1, 8, 6, 6, (90, 80, 70), 0.9, 1)
        # The crowd: heads and raised arms, a sea of shirts.
        b.fill(rect(0, 300, 512, 512), (120, 112, 104), soft=10)
        for row, (y0, rr) in enumerate(((290, 22), (330, 26), (380, 30))):
            for k in range(14):
                x = k * 40 + rng.uniform(-14, 14) + row * 13
                y = y0 + rng.uniform(-8, 8)
                tone = rng.choice([(236, 190, 156), (190, 130, 92), (130, 84, 58), (96, 62, 44), (220, 170, 130)])
                shirt_c = rng.choice([(200, 70, 60), (240, 236, 226), (70, 110, 160), (230, 190, 80), (90, 140, 100), (40, 44, 52)])
                b.fill(ell(x, y + rr * 2.4, rr * 1.5, rr * 1.4), shirt_c, soft=2)
                b.fill(ell(x, y, rr * 0.75, rr * 0.9), tone, soft=2)
                b.fill(ell(x, y - rr * 0.5, rr * 0.8, rr * 0.55, 180, 360), rng.choice([(40, 30, 26), (120, 80, 50), (200, 170, 120), (60, 44, 36)]), soft=2)
                if rng.random() < 0.25:
                    b.stroke([(x + rr, y + rr), (x + rr * 1.4, y - rr * 1.6)], rr * 0.5, tone, soft=2)
    b.under(bg[0], 4.5)
    f = Face(hx=266, hy=218, rx=88, ry=106, jaw=0.55, taper=0.08)
    torso(b, shirt, top=372, half=214, neck_half=60, cx=264, tilt=4)
    b.solid([(222, 366), (306, 366), (264, 440)], (236, 230, 220), depth=14)
    neck(b, f, skin, half=36, bottom=396)
    for side in (-1, 1):
        b.solid([(264, 440), (264 + side * 54, 358), (264 + side * 70, 398), (264 + side * 16, 452)], shade(shirt, 1.12), depth=10)
    hand(b, 110, 236, skin, shirt, open_palm=False, scale=0.95, angle=-8, rolled=True)
    with b.rotated(-5, (f.hx, f.chin + 20)):
        ears(b, f, skin)
        head(b, f, skin)
        mop = path((f.hx - f.rx - 4, f.hy + 4), ((f.hx - f.rx - 16, f.top - 8), (f.hx - 30, f.top - 34), (f.hx + 20, f.top - 26)),
                   ((f.hx + 70, f.top - 30), (f.hx + f.rx + 14, f.top + 4), (f.hx + f.rx + 4, f.hy + 4)),
                   ((f.hx + f.rx - 6, f.hy - 30), (f.hx + 50, f.top + 24), (f.hx + 10, f.top + 30)),
                   ((f.hx - 10, f.top + 44), (f.hx - 40, f.top + 34), (f.hx - 54, f.top + 26)),
                   ((f.hx - 70, f.hy - 40), (f.hx - f.rx + 6, f.hy - 20), (f.hx - f.rx - 4, f.hy + 4)))
        hm = b.solid(mop, hair, depth=26, lite=1.35, lt_a=0.5)
        strands(b, rng, hm, [cubic((f.hx - 60 + k * 12, f.top - 20), (f.hx - 50 + k * 13, f.top), (f.hx - 40 + k * 13, f.top + 14), (f.hx - 34 + k * 13, f.top + 30), 8) for k in range(10)], shade(hair, 1.5), 0.35, 2.2, 2)
        eyes(b, f, skin, iris=(70, 110, 138), w=29, h=11.5, look=(0, -2))
        brows(b, f, shade(hair, 0.9), w=6.5, lift=(10, 8), arch=8)
        nose(b, f, skin, 1.0)
        mouth(b, f, skin, "speech", w=46, open_=1.1, dy=4, lips=(196, 110, 104))
        for _ in range(26):
            side = rng.choice((-1, 1))
            b.blob(f.x(side * rng.uniform(22, 58)), f.nose_y - rng.uniform(-6, 22), 2.2, 2.0, (186, 120, 88), 0.55, 0.8)
    return finish(b.img, "calloway", tint=(1.03, 1.0, 0.96), contrast=1.08, vignette=0.25)


def venkat() -> Image.Image:
    """Mavis Glimmer, The Ad Wizard: a TV studio, a teal back light tracing
    her edge, every hair in place and a smile held for the camera."""
    b = Brush("portrait:venkat", light=(-0.3, -0.9))
    rng = random.Random("venkat")
    skin, hair = (184, 120, 84), (28, 22, 28)
    jacket, teal = (176, 96, 116), (110, 220, 214)
    with b.layer() as bg:
        b.img.alpha_composite(gradient((12, 30, 44), (24, 56, 70)))
        radial(b, 256, 230, 380, (40, 110, 124), 0.85)
        for x, y, w_, h_ in ((-20, 70, 150, 92), (380, 50, 160, 100), (-10, 300, 110, 74), (420, 280, 120, 80)):
            b.fill(rrect(x, y, x + w_, y + h_, 6), (60, 150, 190), 0.55, soft=2)
            b.fill(rrect(x + 8, y + 8, x + w_ - 8, y + h_ - 8, 4), (140, 210, 236), 0.4, soft=2)
        bokeh(b, rng, 12, (0, 0, 512, 160), 8, 18, [(200, 240, 255), (255, 255, 255)], (0.3, 0.6))
    b.under(bg[0], 5)
    f = Face(hx=256, hy=216, rx=82, ry=108, jaw=0.1, taper=0.3)
    with b.layer() as fig:
        back = path((f.hx - 92, f.top + 20), ((f.hx - 132, f.hy + 60), (f.hx - 128, f.hy + 160), (f.hx - 116, f.hy + 186)), ((f.hx - 60, f.hy + 206), (f.hx + 60, f.hy + 206), (f.hx + 116, f.hy + 186)),
                    ((f.hx + 128, f.hy + 160), (f.hx + 132, f.hy + 60), (f.hx + 92, f.top + 20)))
        b.solid(back, hair, depth=30, lite=1.8, lt_a=0.3)
        torso(b, jacket, top=370, half=200, neck_half=56)
        b.solid([(212, 362), (300, 362), (256, 436)], (244, 236, 226), depth=14)
        neck(b, f, skin, half=32, bottom=392)
        lapels(b, 256, 368, jacket, (244, 236, 226), spread=48, depth=82)
        ears(b, f, skin)
        for side in (-1, 1):
            b.blob(f.hx + side * (f.rx - 2), f.eye_y + 44, 4.5, 4.5, (240, 240, 246), 1, 0.5)
        head(b, f, skin)
        front = path((f.hx + 26, f.top - 4), ((f.hx - 60, f.top - 14), (f.hx - f.rx - 26, f.hy - 60), (f.hx - f.rx - 16, f.hy + 40)),
                     ((f.hx - f.rx - 26, f.hy + 120), (f.hx - f.rx - 34, f.hy + 170), (f.hx - f.rx - 36, f.hy + 190)), ((f.hx - f.rx - 30, f.hy + 206), (f.hx - f.rx, f.hy + 200), (f.hx - f.rx + 6, f.hy + 180)),
                     ((f.hx - f.rx + 10, f.hy + 120), (f.hx - f.rx + 6, f.hy + 30), (f.hx - f.rx + 12, f.hy - 20)),
                     ((f.hx - 50, f.top + 34), (f.hx + 30, f.top + 26), (f.hx + f.rx - 2, f.hy - 20)),
                     ((f.hx + f.rx + 4, f.hy + 30), (f.hx + f.rx + 8, f.hy + 120), (f.hx + f.rx + 10, f.hy + 180)), ((f.hx + f.rx + 14, f.hy + 200), (f.hx + f.rx + 36, f.hy + 206), (f.hx + f.rx + 40, f.hy + 190)),
                     ((f.hx + f.rx + 36, f.hy + 160), (f.hx + f.rx + 30, f.hy + 60), (f.hx + f.rx + 14, f.hy - 40)),
                     ((f.hx + 70, f.top - 14), (f.hx + 50, f.top - 6), (f.hx + 26, f.top - 4)))
        fm = b.solid(front, hair, depth=24, lite=1.9, lt_a=0.3)
        # The glossy band of a blow-dry.
        b.stroke(cubic((f.hx - 30, f.top + 6), (f.hx - 80, f.top + 20), (f.hx - 104, f.hy - 30), (f.hx - 104, f.hy + 60), 16), 9, (150, 140, 156), 0.55, soft=3, clip=fm)
        b.stroke(cubic((f.hx + 50, f.top + 2), (f.hx + 86, f.top + 24), (f.hx + 102, f.hy - 20), (f.hx + 104, f.hy + 60), 16), 7, (150, 140, 156), 0.45, soft=3, clip=fm)
        strands(b, rng, fm, [cubic((f.hx + 20, f.top - 2), (f.hx - 60 - k * 6, f.top + 6), (f.hx - 100 - k * 3, f.hy), (f.hx - 110 - k * 3, f.hy + 180), 16) for k in range(5)], (90, 84, 96), 0.3, 1.4, 2)
        eyes(b, f, skin, iris=(50, 32, 24), w=31, h=11, lash=(14, 10, 12))
        brows(b, f, hair, w=5.2, lift=(3, 3), arch=8, length=1.05)
        nose(b, f, skin, 0.95)
        mouth(b, f, skin, "composed", w=48, lips=(156, 64, 80))
    figure = fig[0]
    b.img.alpha_composite(figure)
    rim(b, figure, teal, (1.0, -0.2), 7, 0.85)
    rim(b, figure, teal, (-1.0, -0.2), 5, 0.6)
    return finish(b.img, "venkat", tint=(0.95, 1.0, 1.05), contrast=1.1, vignette=0.4)


def hale() -> Image.Image:
    """Percy Quibble, The Debater: under the debate stage's lights, squared
    up to the lectern, one finger raised on the point he is about to make."""
    b = Brush("portrait:hale", light=(-0.5, -0.85))
    rng = random.Random("hale")
    skin, hair = (150, 96, 64), (36, 28, 26)
    suit, wood = (46, 50, 62), (136, 90, 56)
    with b.layer() as bg:
        b.img.alpha_composite(gradient((92, 108, 134), (150, 162, 180)))
        b.fill(rect(150, 0, 362, 512), (176, 188, 206), 0.55, soft=6)
        for k in range(7):
            x = 20 + k * 79
            radial(b, x, 18, 120, (220, 232, 255), 0.6)
            b.blob(x, 18, 16, 14, (255, 255, 255), 0.9, 4)
        bokeh(b, rng, 10, (0, 60, 512, 300), 10, 24, [(180, 200, 255), (255, 255, 255)], (0.15, 0.35))
    b.under(bg[0], 4)
    f = Face(hx=248, hy=220, rx=88, ry=108, jaw=0.65, taper=0.04)
    torso(b, suit, top=374, half=206, neck_half=58, cx=248)
    b.solid([(208, 368), (288, 368), (248, 446)], (240, 238, 234), depth=14)
    neck(b, f, skin, half=36, bottom=392)
    b.solid([(240, 404), (256, 404), (262, 470), (248, 486), (234, 470)], (118, 40, 50), depth=8)
    b.solid(rrect(236, 390, 260, 410, 4), (118, 40, 50), depth=6)
    lapels(b, 248, 370, suit, (240, 238, 234), spread=44, depth=80)
    hand(b, 404, 262, skin, suit, cuff=(240, 238, 234), open_palm=True, scale=0.92, angle=8)
    ears(b, f, skin)
    head(b, f, skin)
    cap = path((f.hx - f.rx - 4, f.hy - 4), ((f.hx - f.rx - 14, f.top - 44), (f.hx + f.rx + 14, f.top - 44), (f.hx + f.rx + 4, f.hy - 4)),
               ((f.hx + f.rx - 4, f.hy - 40), (f.hx + 50, f.top + 20), (f.hx - 26, f.top + 18)),
               ((f.hx - 50, f.top + 26), (f.hx - f.rx + 8, f.hy - 40), (f.hx - f.rx - 2, f.hy - 4)))
    hm = b.solid(cap, hair, depth=20, lite=1.8, lt_a=0.35)
    strands(b, rng, hm, [cubic((f.hx - 26 + k * 4, f.top + 18), (f.hx - 10 + k * 14, f.top - 10), (f.hx + 40 + k * 8, f.top - 6), (f.hx + 70 + k * 3, f.hy - 40), 10) for k in range(6)], (120, 110, 104), 0.3, 1.4, 2)
    for side in (-1, 1):
        b.blob(f.hx + side * (f.rx - 2), f.hy - 14, 7, 16, (150, 146, 140), 0.8, 3)
    eyes(b, f, skin, iris=(56, 36, 26), w=29, h=10, look=(-3, 0))
    brows(b, f, hair, w=7, lift=(-2, 12), arch=5, inner=(5, 0), length=1.05)
    nose(b, f, skin, 1.1)
    mouth(b, f, skin, "speech", w=36, open_=0.6, dy=8, lips=(120, 72, 62))
    stache = path((f.x(-4), f.nose_y + 10), ((f.x(-24), f.nose_y + 6), (f.x(-38), f.nose_y + 16), (f.x(-36), f.nose_y + 30)),
                  ((f.x(-24), f.nose_y + 24), (f.x(-10), f.nose_y + 24), (f.x(0), f.nose_y + 22)),
                  ((f.x(10), f.nose_y + 24), (f.x(24), f.nose_y + 24), (f.x(36), f.nose_y + 30)),
                  ((f.x(38), f.nose_y + 16), (f.x(24), f.nose_y + 6), (f.x(4), f.nose_y + 10)))
    sm = b.solid(stache, hair, depth=8, lite=1.8, lt_a=0.3)
    strands(b, rng, sm, [[(f.x(k * 6), f.nose_y + 10), (f.x(k * 7.5), f.nose_y + 26)] for k in range(-5, 6)], (110, 100, 96), 0.4, 1.2, 1)
    # The lectern's edge across the bottom, and its microphone.
    b.stroke(cubic((300, 446), (300, 412), (296, 394), (284, 382), 12), 4, (30, 30, 34), soft=0.6)
    b.solid(rrect(268, 364, 294, 390, 9), (52, 52, 58), depth=8)
    b.solid([(-10, 452), (522, 452), (522, 540), (-10, 540)], wood, depth=30, light=(0, -1))
    b.solid([(-10, 438), (522, 438), (522, 456), (-10, 456)], shade(wood, 1.2), depth=8, light=(0, -1))
    for k in range(6):
        y = 470 + k * 9
        b.stroke([(-10, y + rng.uniform(-2, 2)), (180, y + rng.uniform(-3, 3)), (360, y + rng.uniform(-3, 3)), (522, y)], 1.4, shade(wood, 0.7), 0.4, soft=1)
    return finish(b.img, "hale", tint=(0.98, 1.0, 1.04), contrast=1.08, vignette=0.35)


def alvarado() -> Image.Image:
    """Opal Crumpet, The Insider: a wood-panelled hallway and a marble
    column she has stood beside for decades; side light, half her face in
    shadow, a knowing look."""
    b = Brush("portrait:alvarado", light=(-1.0, -0.35))
    rng = random.Random("alvarado")
    skin, hair = (220, 170, 128), (190, 184, 202)
    jacket, marble, panel = (84, 62, 92), (232, 228, 220), (112, 70, 42)
    with b.layer() as bg:
        b.img.alpha_composite(gradient((84, 52, 32), (60, 36, 24)))
        for k in range(6):
            x = 150 + k * 80
            b.fill(rect(x + 8, 40, x + 70, 250), shade(panel, 1.12), soft=1.5)
            b.fill(rect(x + 8, 280, x + 70, 520), shade(panel, 1.12), soft=1.5)
            b.stroke([(x + 8, 40), (x + 8, 250)], 3, shade(panel, 0.6), 0.7, soft=1)
            b.stroke([(x + 8, 280), (x + 8, 520)], 3, shade(panel, 0.6), 0.7, soft=1)
        radial(b, 470, 120, 140, (255, 210, 140), 0.6)
        b.blob(470, 120, 14, 22, (255, 236, 196), 0.9, 4)
    b.under(bg[0], 4)
    with b.layer() as colm:
        cm = b.fill(rect(-10, 0, 140, 520), marble, soft=0.8)
        for k in range(6):
            x = 4 + k * 24
            b.stroke([(x, 0), (x, 520)], 6, shade(marble, 0.78), 0.6, soft=2.5, clip=cm)
            b.stroke([(x + 6, 0), (x + 6, 520)], 3, shade(marble, 1.1), 0.6, soft=1.5, clip=cm)
        for _ in range(5):
            y = rng.uniform(40, 480)
            b.stroke([(0, y), (40, y + rng.uniform(-30, 30)), (90, y + rng.uniform(-30, 30)), (140, y + rng.uniform(-40, 40))], 1.4, (170, 164, 160), 0.5, soft=1, clip=cm)
        b.form(cm, marble, 50, dark=0.55, lite=1.1, light=(-1, 0))
    b.under(colm[0], 1.5)
    f = Face(hx=270, hy=226, rx=82, ry=104, jaw=0.15, taper=0.22)
    with b.layer() as fig:
        torso(b, jacket, top=372, half=200, neck_half=58, cx=270)
        b.solid([(232, 366), (308, 366), (270, 428)], (232, 222, 214), depth=12)
        neck(b, f, skin, half=32, bottom=392)
        for k in range(15):
            a = math.radians(20 + k * 10)
            px, py = 270 + 50 * math.cos(a), 366 + 34 * math.sin(a)
            b.blob(px, py, 5.5, 5.5, (240, 236, 230), 1, 0.6)
            b.blob(px - 1.5, py - 1.5, 2, 2, WHITE, 0.9, 0.5)
        lapels(b, 270, 370, jacket, (232, 222, 214), spread=46, depth=70)
        b.blob(334, 418, 8, 8, (218, 176, 84), 1, 0.6)
        b.blob(332, 416, 3, 3, (255, 240, 200), 0.9, 0.6)
        ears(b, f, skin)
        for side in (-1, 1):
            b.blob(f.hx + side * (f.rx - 4), f.eye_y + 42, 6, 6, (240, 236, 230), 1, 0.6)
        head(b, f, skin)
        # A short, swept-back silver cut: volume on top, ears clear, a side part.
        cut = path((f.hx - f.rx - 4, f.hy + 6), ((f.hx - f.rx - 26, f.top - 20), (f.hx - 30, f.top - 62), (f.hx + 24, f.top - 60)),
                   ((f.hx + 80, f.top - 56), (f.hx + f.rx + 22, f.top - 6), (f.hx + f.rx + 4, f.hy + 6)),
                   ((f.hx + f.rx - 4, f.hy - 24), (f.hx + f.rx - 20, f.top + 26), (f.hx + 30, f.top + 22)),
                   ((f.hx, f.top + 20), (f.hx - 26, f.top + 26), (f.hx - 34, f.top + 34)),
                   ((f.hx - 56, f.top + 34), (f.hx - f.rx + 6, f.hy - 34), (f.hx - f.rx - 4, f.hy + 6)))
        cm = b.solid(cut, hair, depth=30, dark=0.5, lite=1.25, dk_a=0.9)
        waves = []
        for k in range(14):
            t = k / 13
            sx = f.hx - f.rx + 4 + t * (2 * f.rx - 8)
            sy = f.top + 40 - math.sin(t * math.pi) * 26
            waves.append(cubic((sx, sy), (sx - 6 + t * 12, sy - 30), (f.hx - 20 + t * 60, f.top - 50), (f.hx + 10 + t * 70, f.top - 56 + t * 20), 14))
        strands(b, rng, cm, waves, shade(hair, 0.55), 0.5, 1.8, 2)
        strands(b, rng, cm, waves, shade(hair, 1.35), 0.4, 1.4, 2)
        eyes(b, f, skin, iris=(78, 58, 42), w=29, h=10.5, lid=0.45, crinkle=2, look=(2, 1))
        brows(b, f, (130, 118, 128), w=4.5, lift=(2, 8), arch=9, length=1.05)
        nose(b, f, skin, 1.0)
        mouth(b, f, skin, "smirk", w=40, lips=(176, 84, 96))
        for side in (-1, 1):
            b.stroke(cubic((f.x(side * 30), f.nose_y + 4), (f.x(side * 40), f.nose_y + 20), (f.x(side * 40), f.mouth_y), (f.x(side * 34), f.mouth_y + 10), 8), 1.6, shade(skin, 0.6), 0.45, soft=1.2, taper=0.5)
    figure = fig[0]
    b.img.alpha_composite(figure)
    # The far half in the column's shadow.
    with b.layer() as sh:
        b.fill([(f.hx + 6, 0), (560, 0), (560, 560), (f.hx + 40, 560)], (255, 255, 255), soft=10)
    b.paint(sh[0].getchannel("A"), (34, 22, 26), 0.55, clip=figure.getchannel("A"))
    return finish(b.img, "alvarado", tint=(1.06, 1.0, 0.9), contrast=1.12, vignette=0.42)


def reyes() -> Image.Image:
    """Dash Kickflip, The Insurgent: a street at night caught in a camera
    flash, off-axis and in a hurry, a hand-lettered sign pushing into frame."""
    b = Brush("portrait:reyes", light=(0.2, -0.95))
    rng = random.Random("reyes")
    skin, hair = (198, 138, 98), (32, 26, 24)
    hood, kraft = (92, 100, 70), (204, 170, 120)
    with b.layer() as bg:
        b.img.alpha_composite(gradient((22, 26, 34), (48, 44, 46)))
        for row in range(14):
            for k in range(10):
                x = k * 56 + (28 if row % 2 else 0)
                y = row * 30 + 140
                b.fill(rect(x + 2, y + 2, x + 54, y + 28), rng.choice([(70, 44, 38), (86, 52, 42), (62, 40, 36)]), 0.7, soft=1)
        bokeh(b, rng, 16, (0, 0, 512, 260), 10, 34, [(255, 176, 80), (255, 210, 140), (120, 200, 255), (255, 90, 80)], (0.3, 0.8))
    b.under(bg[0], 6)
    f = Face(hx=214, hy=232, rx=80, ry=104, jaw=0.3, taper=0.3, look=0.55)
    torso(b, hood, top=380, half=200, neck_half=64, cx=214, tilt=-8)
    b.solid(path((136, 372), ((146, 336), (282, 336), (292, 372)), ((280, 400), (148, 400), (136, 372))), shade(hood, 0.8), depth=14)
    neck(b, f, skin, half=34, bottom=392, dx=4)
    for x in (196, 240):
        b.stroke([(x, 392), (x - 2, 452)], 3, (226, 222, 210), soft=0.6)
    with b.rotated(-6, (f.hx, f.chin + 20)):
        ears(b, f, skin)
        b.stroke(ell(f.hx - f.rx + 2, f.eye_y + 46, 6, 8, n=20), 2.2, (210, 210, 218), soft=0.4)
        hm = head(b, f, skin)
        for side in (-1,):
            b.fill(ell(f.hx + side * (f.rx - 14), f.hy - 30, 24, 44), mix(skin, hair, 0.7), 0.55, clip=hm, soft=6)
        top = path((f.hx - f.rx + 4, f.hy - 36), ((f.hx - f.rx - 8, f.top - 30), (f.hx - 10, f.top - 56), (f.hx + 50, f.top - 48)),
                   ((f.hx + 90, f.top - 44), (f.hx + 120, f.top - 6), (f.hx + 108, f.top + 8)),
                   ((f.hx + 90, f.top + 4), (f.hx + 70, f.top + 18), (f.hx + 60, f.top + 30)),
                   ((f.hx + 30, f.top + 24), (f.hx, f.top + 26), (f.hx - 30, f.top + 34)),
                   ((f.hx - 56, f.top + 40), (f.hx - f.rx + 10, f.hy - 50), (f.hx - f.rx + 4, f.hy - 36)))
        tm = b.solid(top, hair, depth=24, lite=2.0, lt_a=0.35)
        strands(b, rng, tm, [cubic((f.hx - 50 + k * 10, f.top + 26), (f.hx - 20 + k * 12, f.top - 20), (f.hx + 30 + k * 10, f.top - 36), (f.hx + 70 + k * 7, f.top - 26 + k * 3), 12) for k in range(8)], (120, 110, 104), 0.35, 1.4, 2)
        eyes(b, f, skin, iris=(58, 38, 26), w=28, h=10, look=(6, 0))
        brows(b, f, hair, w=6.5, lift=(0, 2), arch=3, inner=(7, 7))
        nose(b, f, skin, 1.0)
        mouth(b, f, skin, "set", w=38, lips=(156, 90, 80))
    # The sign, nearer the camera: cardboard on a stick, hand-lettered.
    with b.layer() as fg:
        sign = turn(rect(300, 14, 580, 200), 12, (440, 108))
        b.solid([(424, 196), (444, 196), (432, 600), (412, 600)], (160, 120, 78), depth=8)
        sm = b.solid(sign, kraft, depth=40, dark=0.7, lite=1.12, light=(-0.6, -0.8))
        for _ in range(4):
            y = rng.uniform(30, 190)
            b.stroke(turn([(300, y), (580, y + rng.uniform(-6, 6))], 12, (440, 108)), 1.2, shade(kraft, 0.82), 0.5, soft=1, clip=sm)
        b.text((424, 92), "HEAR", 60, (24, 22, 26), angle=12)
        b.text((410, 156), "US!", 60, (24, 22, 26), angle=12)
    b.under(fg[0], 1.2)
    return finish(b.img, "reyes", tint=(0.98, 1.0, 1.04), lift=-2, contrast=1.16, vignette=0.45, grain=9)


def strand() -> Image.Image:
    """Esme Moonbeam, The Pollster: an office wall papered with crosstabs and
    trend lines under cool fluorescent light; reading the numbers over her
    glasses."""
    b = Brush("portrait:strand", light=(0.3, -0.95))
    rng = random.Random("strand")
    skin, hair = (240, 206, 182), (232, 230, 224)
    card = (52, 98, 106)
    with b.layer() as bg:
        b.img.alpha_composite(gradient((200, 210, 214), (170, 180, 186)))
        for _ in range(16):
            x, y = rng.uniform(-40, 470), rng.uniform(-30, 420)
            w_, h_ = rng.uniform(70, 110), rng.uniform(90, 130)
            a = rng.uniform(-6, 6)
            sheet = turn(rect(x, y, x + w_, y + h_), a, (x, y))
            m = b.fill(sheet, (246, 246, 242), soft=0.6)
            kind = rng.random()
            if kind < 0.45:
                for r_ in range(1, 9):
                    b.stroke(turn([(x + 6, y + r_ * h_ / 9), (x + w_ - 6, y + r_ * h_ / 9)], a, (x, y)), 1.4, (110, 130, 160), 0.7, soft=0.5, clip=m)
                for c_ in range(1, 4):
                    b.stroke(turn([(x + c_ * w_ / 4, y + 6), (x + c_ * w_ / 4, y + h_ - 6)], a, (x, y)), 1.2, (110, 130, 160), 0.6, soft=0.5, clip=m)
            elif kind < 0.75:
                for c_ in range(4):
                    bh = rng.uniform(0.2, 0.7) * h_
                    b.fill(turn(rect(x + 10 + c_ * (w_ - 20) / 4, y + h_ - 10 - bh, x + 8 + (c_ + 0.7) * (w_ - 20) / 4, y + h_ - 10), a, (x, y)), rng.choice([(70, 120, 190), (230, 140, 60)]), clip=m)
            else:
                pts = [(x + 8 + k * (w_ - 16) / 6, y + h_ * 0.8 - k * h_ * 0.1 + rng.uniform(-10, 10)) for k in range(7)]
                b.stroke(turn(pts, a, (x, y)), 2.4, (200, 70, 60), 0.9, soft=0.5, clip=m)
            b.blob(x + w_ / 2, y + 6, 4, 4, rng.choice([(220, 60, 60), (60, 120, 220), (240, 200, 60)]), 1, 0.6)
        radial(b, 256, 0, 400, (230, 246, 250), 0.5)
    b.under(bg[0], 3.5)
    f = Face(hx=256, hy=230, rx=84, ry=106, jaw=0.2, taper=0.2)
    torso(b, card, top=376, half=202, neck_half=60)
    b.solid(path((204, 372), ((214, 352), (298, 352), (308, 372)), (308, 404), (204, 404)), (64, 66, 92), depth=12)
    neck(b, f, skin, half=34, bottom=380)
    for side in (-1, 1):
        b.solid([(CX + side * 56, 380), (CX + side * 6, 560), (CX + side * 28, 560), (CX + side * 96, 392)], shade(card, 0.85), depth=10)
    for k in range(3):
        b.blob(CX + 20, 432 + k * 30, 5, 5, (226, 222, 210), 1, 0.6)
    ears(b, f, skin)
    head(b, f, skin)
    bob = path((f.hx - f.rx - 12, f.hy + 50), ((f.hx - f.rx - 26, f.top - 10), (f.hx - 30, f.top - 40), (f.hx + 10, f.top - 34)),
               ((f.hx + 60, f.top - 36), (f.hx + f.rx + 26, f.top - 10), (f.hx + f.rx + 12, f.hy + 50)),
               ((f.hx + f.rx + 6, f.hy + 62), (f.hx + f.rx - 4, f.hy + 60), (f.hx + f.rx - 8, f.hy + 40)),
               ((f.hx + f.rx - 6, f.hy - 30), (f.hx + 40, f.top + 34), (f.hx - 20, f.top + 28)),
               ((f.hx - 40, f.top + 48), (f.hx - f.rx + 4, f.hy - 34), (f.hx - f.rx + 8, f.hy + 40)),
               ((f.hx - f.rx + 4, f.hy + 60), (f.hx - f.rx - 6, f.hy + 62), (f.hx - f.rx - 12, f.hy + 50)))
    bm = b.solid(bob, hair, depth=26, dark=0.7, lite=1.1)
    strands(b, rng, bm, [cubic((f.hx - 70 + k * 16, f.top + 34), (f.hx - 60 + k * 15, f.top), (f.hx - 40 + k * 13, f.top - 22), (f.hx - 10 + k * 10, f.top - 30), 8) for k in range(9)], (170, 168, 164), 0.35, 1.4, 2)
    # A pencil tucked behind her ear.
    b.solid(turn(rect(f.hx + f.rx - 30, f.eye_y - 8, f.hx + f.rx + 60, f.eye_y + 4), -28, (f.hx + f.rx, f.eye_y)), (232, 182, 70), depth=4)
    eyes(b, f, skin, iris=(92, 112, 122), w=28, h=10, look=(3, 3), crinkle=2, bags=True)
    for side in (-1, 1):
        x = f.x(side * f.eye_dx)
        b.fill(ell(x, f.eye_y, 25, 22, n=48), (220, 236, 244), 0.18, soft=1)
        b.stroke(ell(x, f.eye_y, 25, 22, n=48), 2.6, (150, 120, 70), soft=0.4)
        b.stroke(ell(x, f.eye_y, 18, 15, 200, 250, 10), 3, WHITE, 0.6, soft=1)
        b.stroke([(f.x(side * (f.eye_dx + 25)), f.eye_y - 4), (f.hx + side * (f.rx - 2), f.eye_y - 10)], 2.2, (150, 120, 70), soft=0.4)
    b.stroke(cubic((f.x(-f.eye_dx + 25), f.eye_y - 4), (f.x(-8), f.eye_y - 12), (f.x(8), f.eye_y - 12), (f.x(f.eye_dx - 25), f.eye_y - 4), 8), 2.4, (150, 120, 70), soft=0.4)
    for side in (-1, 1):
        b.blob(f.x(side * f.eye_dx), f.eye_y + 30, 18, 6, shade(skin, 0.6), 0.25, 4)
    brows(b, f, (190, 184, 176), w=4.5, lift=(10, 4), arch=6)
    nose(b, f, skin, 1.0)
    mouth(b, f, skin, "smile", w=36, open_=0.6, lips=(196, 124, 128))
    return finish(b.img, "strand", tint=(0.97, 1.01, 1.03), lift=4, contrast=1.05, vignette=0.28)


def begay() -> Image.Image:
    """Gus Bramble, The Organizer: a leafy street at golden hour, the camera
    panning to keep up; clipboard in hand, lanyard swinging."""
    b = Brush("portrait:begay", light=(0.8, -0.55))
    rng = random.Random("begay")
    skin, hair = (170, 108, 72), (236, 234, 228)
    jacket, cap = (62, 96, 72), (46, 60, 94)
    with b.layer() as bg:
        b.img.alpha_composite(gradient((150, 176, 120), (110, 120, 90)))
        b.fill(rect(150, 120, 400, 420), (176, 190, 204), soft=2)
        for k in range(10):
            b.stroke([(150, 130 + k * 28), (400, 130 + k * 28)], 2, (140, 152, 166), 0.8, soft=1)
        b.fill(rect(230, 200, 310, 420), (120, 54, 46), soft=2)
        b.fill(rect(0, 360, 512, 520), (120, 112, 100), soft=4)
        for _ in range(26):
            x, y, r = rng.uniform(-40, 552), rng.uniform(-20, 220), rng.uniform(30, 80)
            b.fill(ell(x, y, r, r * 0.8), rng.choice([(70, 110, 50), (100, 140, 60), (60, 90, 44), (130, 160, 70)]), 0.9, soft=6)
        bokeh(b, rng, 14, (200, 0, 512, 200), 10, 26, [(255, 236, 170), (255, 220, 140)], (0.35, 0.7))
    b.img.alpha_composite(motion(bg[0], 26))
    f = Face(hx=262, hy=224, rx=84, ry=106, jaw=0.35, taper=0.12)
    tilt = 7
    torso(b, jacket, top=380, half=208, neck_half=62, cx=258, tilt=6)
    neck(b, f, skin, half=36, bottom=392)
    b.stroke([(258, 392), (258, 560)], 3.5, (36, 40, 36), soft=0.6)
    b.stroke([(228, 382), (220, 440), (214, 470)], 5, (50, 74, 118), soft=0.5)
    b.stroke([(294, 382), (296, 420), (292, 440)], 5, (50, 74, 118), soft=0.5)
    b.solid(turn(rrect(190, 462, 238, 520, 6), -6, (214, 490)), (244, 244, 238), depth=8)
    b.stroke(turn([(198, 480), (230, 480)], -6, (214, 490)), 4, (50, 74, 118), soft=0.4)
    b.stroke(turn([(198, 496), (224, 496)], -6, (214, 490)), 2, (140, 140, 150), soft=0.4)
    with b.rotated(-12, (370, 450)):
        b.solid(rrect(300, 360, 446, 560, 10), (150, 108, 70), depth=20)
        pm = b.solid(rect(314, 384, 432, 560), (246, 244, 238), depth=16, dark=0.85)
        for k in range(6):
            y = 410 + k * 22
            b.stroke(rect(324, y - 6, 336, y + 6) + [(324, y - 6)], 1.4, (120, 120, 130), 0.9, soft=0.4, clip=pm)
            b.stroke([(344, y + 2), (418, y + 2)], 1.4, (150, 150, 160), 0.8, soft=0.4, clip=pm)
            if k < 3:
                b.stroke([(322, y - 1), (328, y + 5), (340, y - 10)], 2.4, (50, 74, 118), soft=0.4)
        b.solid(rrect(348, 350, 398, 378, 6), (170, 172, 176), depth=6, lite=1.5)
        b.solid(rrect(280, 438, 318, 482, 13), skin, depth=10)
    with b.rotated(tilt, (f.hx, f.chin + 20)):
        ears(b, f, skin)
        head(b, f, skin)
        beard = path((f.hx - f.rx + 2, f.hy + 6), ((f.hx - f.rx + 6, f.hy + 80), (f.hx - 44, f.chin + 26), (f.hx, f.chin + 30)),
                     ((f.hx + 44, f.chin + 26), (f.hx + f.rx - 6, f.hy + 80), (f.hx + f.rx - 2, f.hy + 6)),
                     ((f.hx + f.rx - 22, f.hy + 30), (f.hx + 50, f.mouth_y - 14), (f.x(16), f.nose_y + 16)),
                     ((f.x(0), f.nose_y + 10), (f.x(-10), f.nose_y + 10), (f.x(-16), f.nose_y + 16)),
                     ((f.hx - 50, f.mouth_y - 14), (f.hx - f.rx + 22, f.hy + 30), (f.hx - f.rx + 2, f.hy + 6)))
        bm = b.solid(beard, hair, depth=24, dark=0.62, lite=1.1, soft=1.2)
        strands(b, rng, bm, [cubic((f.hx + k * 12, f.hy + 30 + abs(k) * -2), (f.hx + k * 13, f.hy + 60), (f.hx + k * 11, f.chin), (f.hx + k * 9, f.chin + 24), 10) for k in range(-6, 7)], (150, 146, 140), 0.35, 1.3, 2)
        mouth(b, f, skin, "grin", w=38, dy=-2, lips=(140, 80, 70))
        crown = path((f.hx - f.rx - 6, f.hy - 18), ((f.hx - f.rx - 4, f.top - 40), (f.hx + f.rx + 4, f.top - 40), (f.hx + f.rx + 6, f.hy - 18)))
        b.solid(crown, cap, depth=30)
        b.stroke(cubic((f.hx, f.top - 18), (f.hx + 2, f.top - 6), (f.hx + 4, f.hy - 40), (f.hx + 4, f.hy - 22), 8), 2, shade(cap, 0.6), 0.7, soft=0.8)
        brim = path((f.hx - f.rx - 8, f.hy - 22), ((f.hx - 40, f.hy - 34), (f.hx + 60, f.hy - 34), (f.hx + f.rx + 30, f.hy - 18)),
                    ((f.hx + f.rx + 20, f.hy - 4), (f.hx + 40, f.hy - 10), (f.hx - f.rx - 8, f.hy - 12)))
        b.blob(f.hx, f.hy - 4, f.rx * 0.9, 10, shade(skin, 0.5), 0.55, 6)
        b.solid(brim, shade(cap, 0.85), depth=10)
        for side in (-1, 1):
            b.fill(ell(f.hx + side * (f.rx - 4), f.hy - 6, 10, 18), hair, soft=2)
        eyes(b, f, skin, iris=(60, 40, 28), w=27, h=10, look=(4, 0), crinkle=3, lid=0.15)
        brows(b, f, hair, w=7, lift=(6, 6), arch=6)
        nose(b, f, skin, 1.1)
        stache = path((f.x(-4), f.nose_y + 10), ((f.x(-24), f.nose_y + 6), (f.x(-40), f.nose_y + 18), (f.x(-34), f.nose_y + 30)),
                      ((f.x(-22), f.nose_y + 22), (f.x(-10), f.nose_y + 22), (f.x(0), f.nose_y + 20)),
                      ((f.x(10), f.nose_y + 22), (f.x(22), f.nose_y + 22), (f.x(34), f.nose_y + 30)),
                      ((f.x(40), f.nose_y + 18), (f.x(24), f.nose_y + 6), (f.x(4), f.nose_y + 10)))
        b.solid(stache, hair, depth=8, dark=0.65)
    return finish(b.img, "begay", tint=(1.06, 1.02, 0.9), contrast=1.08, vignette=0.32)


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
    """`img` as Kit.portrait shows it, `px` wide: on the round plate, clipped
    to the circle (for the sheets only)."""
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
    face.putalpha(ImageChops.multiply(face.getchannel("A"), circle))
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

GENRES = {
    "okafor": "The Fundraiser",
    "calloway": "The Barnstormer",
    "venkat": "The Ad Wizard",
    "hale": "The Debater",
    "alvarado": "The Insider",
    "reyes": "The Insurgent",
    "strand": "The Pollster",
    "begay": "The Organizer",
}


def preview(images: dict[str, Image.Image], labels: bool = False) -> Image.Image:
    """Every portrait in Kit.portrait's round crop at 40, 80 and 160 px, two to a row."""
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
TILTS = (-3.0, 2.0, -1.5, 3.0, -2.5, 1.5, -2.0, 2.5)


def load_tape() -> Image.Image | None:
    tape_path = os.path.join(HERE, "..", "ui", "tape.png")
    return Image.open(tape_path).convert("RGBA") if os.path.exists(tape_path) else None


def photo(img: Image.Image, px: int, tilt: float, tape: Image.Image | None) -> Image.Image:
    """`img` as UI/Board.photo draws it, `px` wide (for the sheets only)."""
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


def photo_sheet(images: dict[str, Image.Image]) -> Image.Image:
    """Each face taped to the board as a photo at 48, 72 and 96 px."""
    tape = load_tape()
    sizes = (48, 72, 96)
    cell = 130
    sheet = Image.new("RGBA", (cell * len(images) + 20, 130 * len(sizes) + 20), BOARD + (255,))
    for i, img in enumerate(images.values()):
        y = 10
        for px in sizes:
            shot = photo(img, px, TILTS[i], tape)
            sheet.alpha_composite(shot, (10 + i * cell + (cell - shot.width) // 2, y))
            y += 130
    return sheet


def review(images: dict[str, Image.Image]) -> Image.Image:
    """The review sheet: all eight at 512 with name and genre; each at 32, 48
    and 72 px in color and in greyscale; each in Kit.portrait's round crop and
    as Board.photo's taped square, on the board."""
    hand = ImageFont.truetype(os.path.join(FONTS, "PatrickHand-Regular.ttf"), 30)
    small = ImageFont.truetype(os.path.join(FONTS, "PatrickHand-Regular.ttf"), 22)
    head_f = ImageFont.truetype(os.path.join(FONTS, "PermanentMarker-Regular.ttf"), 34)
    ink = (29, 29, 31)
    gap, label = 24, 70
    cols = 4
    grid_w = cols * OUT + (cols + 1) * gap
    grid_h = 2 * (OUT + label + gap) + gap
    strip_cell = 32 + 48 + 72 + 4 * 12
    strip_h = 72 + 60
    crop_cell = 250
    crop_h = 150 + 60
    total_h = 70 + grid_h + 2 * strip_h + crop_h + 40
    sheet = Image.new("RGBA", (grid_w, total_h), BOARD + (255,))
    d = ImageDraw.Draw(sheet)
    d.text((gap, 18), "Landslide candidate portraits: review", font=head_f, fill=ink)
    y0 = 70
    for i, (name, img) in enumerate(images.items()):
        x = gap + (i % cols) * (OUT + gap)
        y = y0 + gap + (i // cols) * (OUT + label + gap)
        sheet.alpha_composite(img, (x, y))
        d.text((x, y + OUT + 6), f"{NAMES[name]}  ({name})", font=hand, fill=ink)
        d.text((x, y + OUT + 38), GENRES[name], font=small, fill=(87, 84, 76))
    y = y0 + grid_h
    for grey in (False, True):
        d.text((gap, y), "32 / 48 / 72 px" + (", greyscale" if grey else ""), font=hand, fill=ink)
        for i, img in enumerate(images.values()):
            x = gap + i * (strip_cell + 8)
            for px in (32, 48, 72):
                t = img.resize((px, px), Image.Resampling.LANCZOS)
                if grey:
                    t = t.convert("L").convert("RGBA")
                sheet.alpha_composite(t, (x, y + 44 + 72 - px))
                x += px + 12
        y += strip_h
    d.text((gap, y), "Kit.portrait (round, 96 px) and Board.photo (taped, 96 px)", font=hand, fill=ink)
    tape = load_tape()
    for i, img in enumerate(images.values()):
        x = gap + i * crop_cell
        sheet.alpha_composite(plated(img, 96), (x, y + 60))
        shot = photo(img, 96, TILTS[i], tape)
        sheet.alpha_composite(shot, (x + 108, y + 50))
    return sheet


def main():
    images = {}
    for name, draw in PORTRAITS.items():
        img = draw()
        img.convert("RGB").save(os.path.join(HERE, f"{name}.png"), optimize=True)  # a full-bleed photo: no alpha
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
    if "--review" in sys.argv:
        target = sys.argv[sys.argv.index("--review") + 1]
        os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
        review(images).save(target)
        print(f"wrote {target}")
    print(f"wrote {len(images)} portraits and sheet.png to {HERE}")


if __name__ == "__main__":
    main()
