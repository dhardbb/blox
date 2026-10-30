"""Generates the UI's decoration images (docs/DESIGN.md D-056).

Run from the repository root:  python3 assets/ui/make.py
Needs Pillow (PIL; a user install is fine, so no -I). Writes, next to this script:

  ui-shadow.png  96x96, a soft black rounded rect for a 9-slice drop shadow
                 (SliceCenter = Rect(40, 40, 56, 56), SliceScale 1)
  ui-glow.png    256x256, a white radial glow, alpha (1 - d)^2.2, tinted in game
  ui-dots.png    64x64, one 2 px white dot, tiled behind the map (optional)

The whiteboard set (docs/proposals/whiteboard.md; strokes from marker.py):

  board.png            512x512, the board itself in full color: off-white with
                       faint erased-marker ghosts; tiles seamlessly
  sticky.png           128x128, a 9-slice sticky note in white and grey (tinted
                       to the note color), curled lower-right corner, soft
                       shadow. SliceCenter = Rect(32, 32, 88, 88); the note's
                       paper runs from 4 to 116 on both axes
  marker-box.png       128x128, a 9-slice wobbly marker rectangle, white on
                       transparent (tinted to the ink), drawn at 2x for
                       SliceScale 0.5. SliceCenter = Rect(40, 40, 88, 88); the
                       lines run about 14 px in from each edge
  magnet.png           128x128, a round glossy magnet in greys (tinted)
  scribble-circle.png  256x256, a loose hand-drawn circle, white (tinted)
  tape.png             128x48, a strip of masking tape in full color,
                       translucent, with torn ends

The ids go in src/client/UI/Assets.luau after the upload (assets/ui/README.md).
"""

import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import marker  # noqa: E402  (assets/ui/marker.py, next to this script)

S = 4  # supersampling for the hand-drawn images

BOARD = (243, 241, 234)  # Colors.background
GHOST = (228, 225, 216)  # Colors.ghost: erased marker
TAPE = (226, 212, 172)  # masking tape, cream

STICKY_SLICE = (32, 32, 88, 88)  # sticky.png SliceCenter (keep in sync with Board.luau)
BOX_SLICE = (40, 40, 88, 88)  # marker-box.png SliceCenter (keep in sync with Board.luau)


def shadow() -> Image.Image:
    size, rect, radius, blur = 96, 56, 20, 12
    mask = Image.new("L", (size, size), 0)
    inset = (size - rect) // 2
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, inset + rect - 1, inset + rect - 1), radius=radius, fill=255
    )
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    image.putalpha(mask)
    return image


def glow() -> Image.Image:
    size = 256
    radius = size / 2
    image = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            d = math.hypot(x + 0.5 - radius, y + 0.5 - radius) / radius
            a = max(0.0, 1.0 - d) ** 2.2
            pixels[x, y] = (255, 255, 255, round(a * 255))
    return image


def dots() -> Image.Image:
    image = Image.new("RGBA", (64, 64), (255, 255, 255, 0))
    ImageDraw.Draw(image).ellipse((31, 31, 32, 32), fill=(255, 255, 255, 255))
    return image


def noise(rng: random.Random, w: int, h: int, sigma: float) -> Image.Image:
    """Seeded grey noise around 128 (Image.effect_noise is not seeded)."""
    data = bytes(max(0, min(255, round(128 + rng.gauss(0, sigma)))) for _ in range(w * h))
    return Image.frombytes("L", (w, h), data)


def _wrap_draw(size: int):
    """A mask and a function that draws a stroke on it at every wrap offset,
    so a tile's edges meet."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)

    def put(points, width, value, taper=0.0):
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                marker.stroke(draw, [(x + ox, y + oy) for x, y in points], width, value, taper)

    return mask, put


def _wrap_blur(mask: Image.Image, radius: float) -> Image.Image:
    size = mask.width
    big = Image.new("L", (size * 3, size * 3))
    for i in range(3):
        for j in range(3):
            big.paste(mask, (i * size, j * size))
    big = big.filter(ImageFilter.GaussianBlur(radius))
    return big.crop((size, size, size * 2, size * 2))


def _handwriting(rng: random.Random, x: float, y: float, length: float, height: float) -> list:
    """A cursive-looking line of loops (an erased word), left to right."""
    pts = []
    t = 0.0
    while t < length:
        a = t / height * 2.2
        pts.append((x + t + math.sin(a) * height * 0.35, y - abs(math.sin(a * 0.5)) * height * rng.uniform(0.6, 1.0)))
        t += 1.5
    return pts


def board() -> Image.Image:
    """The board: off-white, faint ghosts of erased words, circles, arrows and
    eraser wipes. Seamless (every mark is drawn at all wrap offsets and blurred
    on a 3x3 tiling). Luminance stays within a few levels of the board color so
    ink on it keeps its contrast."""
    size = 512
    rng = random.Random("board:1")
    words, put_word = _wrap_draw(size)
    for _ in range(9):
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        put_word(marker.wobble(_handwriting(rng, x, y, rng.uniform(60, 170), rng.uniform(10, 18)), rng, 1.5, 30), 3, rng.randint(90, 150))
    for _ in range(3):
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        r = rng.uniform(26, 60)
        put_word(marker.loop(cx, cy, r, r * rng.uniform(0.7, 1.0), rng, 1.05, rng.uniform(-0.5, 0.5)), 4, rng.randint(80, 130))
    for _ in range(3):
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        a = rng.uniform(-0.6, 0.6)
        n = rng.uniform(60, 120)
        line = [(x, y), (x + math.cos(a) * n, y + math.sin(a) * n)]
        put_word(marker.wobble(line, rng, 2, 40), 4, rng.randint(80, 120))
        hx, hy = line[1]
        for turn in (2.6, -2.6):
            put_word([(hx, hy), (hx + math.cos(a + turn) * 14, hy + math.sin(a + turn) * 14)], 4, 100)
    words = _wrap_blur(words, 1.6)
    # Eraser wipes: wide soft bands with streaks along them.
    wipes, put_wipe = _wrap_draw(size)
    for _ in range(6):
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        a = rng.uniform(-0.25, 0.25)
        n = rng.uniform(140, 300)
        line = [(x, y), (x + math.cos(a) * n, y + math.sin(a) * n)]
        for k in range(5):
            off = (k - 2) * 7
            path = [(px - math.sin(a) * off, py + math.cos(a) * off) for px, py in line]
            put_wipe(marker.wobble(path, rng, 3, 90), rng.uniform(3, 8), rng.randint(25, 60), 1.0)
    wipes = _wrap_blur(wipes, 3.5)
    ghost = ImageChops.add(words, wipes)
    # Fine grain: the board's own sheen, +-1 level.
    grain = noise(rng, size, size, 18).filter(ImageFilter.GaussianBlur(0.6))
    image = Image.new("RGB", (size, size), BOARD)
    ghost_layer = Image.new("RGB", (size, size), GHOST)
    image = Image.composite(ghost_layer, image, ghost.point(lambda v: int(v * 0.55)))
    pixels = image.load()
    g = grain.load()
    for y in range(size):
        for x in range(size):
            d = (g[x, y] - 128) / 128 * 1.5
            r, gg, b = pixels[x, y]
            pixels[x, y] = (round(r + d), round(gg + d), round(b + d))
    return image


def sticky() -> Image.Image:
    """A sticky note (128x128, 9-slice): white paper from 4 to 116, a soft grey
    shadow below and right, and the lower-right corner folded up (its underside
    a light grey, a darker shadow under the lifted corner). Tinted with
    ImageColor3 to the note's color."""
    size, k = 128, S
    x0, y0, x1, y1 = 4 * k, 4 * k, 116 * k, 116 * k
    curl = 22 * k
    big = size * k
    a = (x1, y1 - curl)  # where the fold meets the right edge
    b = (x1 - curl, y1)  # ... and the bottom edge
    # Shadow: the note's shape, offset and blurred; the lifted corner throws a
    # little more.
    shade = Image.new("L", (big, big), 0)
    sd = ImageDraw.Draw(shade)
    sd.polygon([(x0 + 2 * k, y0 + 4 * k), (x1 + 2 * k, y0 + 4 * k), (a[0] + 3 * k, a[1] + 4 * k), (b[0] + 3 * k, b[1] + 4 * k), (x0 + 2 * k, y1 + 3 * k)], fill=95)
    sd.polygon([(a[0] - 2 * k, a[1] + 2 * k), (x1 + 1 * k, y1 - curl * 0.35), (b[0] + curl * 0.6, b[1] + 1 * k), (b[0] + 2 * k, b[1] - 2 * k)], fill=120)
    shade = shade.filter(ImageFilter.GaussianBlur(3.5 * k))
    image = Image.new("RGBA", (big, big), (70, 70, 70, 0))
    image.putalpha(shade)
    # The paper, with the corner folded away along the chord a-b.
    body = Image.new("L", (big, big), 0)
    ImageDraw.Draw(body).polygon([(x0, y0), (x1, y0), a, b, (x0, y1)], fill=255)
    image.paste(Image.new("RGBA", (big, big), (255, 255, 255, 255)), (0, 0), body)
    # The flap: the corner reflected over the fold, its edges bowed a little
    # (paper curls), shaded light to slightly darker toward the fold.
    tip = (x1 - curl * 0.94, y1 - curl * 0.94)
    flap_pts = [a]
    for i in range(1, 12):
        u = i / 12
        px, py = a[0] + (tip[0] - a[0]) * u, a[1] + (tip[1] - a[1]) * u
        bow = math.sin(u * math.pi) * curl * 0.08
        flap_pts.append((px + bow, py + bow))
    flap_pts.append(tip)
    for i in range(1, 12):
        u = i / 12
        px, py = tip[0] + (b[0] - tip[0]) * u, tip[1] + (b[1] - tip[1]) * u
        bow = math.sin(u * math.pi) * curl * 0.08
        flap_pts.append((px + bow, py + bow))
    flap_pts.append(b)
    flap = Image.new("L", (big, big), 0)
    ImageDraw.Draw(flap).polygon(flap_pts, fill=255)
    grad = Image.new("RGBA", (big, big))
    gd = ImageDraw.Draw(grad)
    for i in range(-curl, curl + 1):
        # distance from the fold line, 0 at the fold, 1 at the tip
        t = max(0.0, min(1.0, -i / curl))
        v = round(226 + 26 * t)
        gd.line((x1 + i, y1 - curl * 2, x1 + i - curl * 2, y1), fill=(v, v, v, 255), width=2)
    image.paste(grad, (0, 0), flap)
    ImageDraw.Draw(image).line([a, *flap_pts[1:-1], b], fill=(205, 205, 205, 255), width=k)
    return image.resize((size, size), Image.LANCZOS)


def marker_box() -> Image.Image:
    """Four marker swipes forming a box (128x128, 9-slice, drawn at 2x for
    SliceScale 0.5): each side a separate slightly tilted stroke that runs a
    little past the corners. White on transparent."""
    size, k = 128, S
    rng = random.Random("marker-box:1")
    image = Image.new("L", (size * k, size * k), 0)
    draw = ImageDraw.Draw(image)
    lo, hi = 14, 114
    sides = [((lo, lo), (hi, lo)), ((hi, lo), (hi, hi)), ((hi, hi), (lo, hi)), ((lo, hi), (lo, lo))]
    for (ax, ay), (bx, by) in sides:
        j = lambda: rng.uniform(-1.4, 1.4)  # noqa: E731
        a = (ax + j(), ay + j())
        b = (bx + j(), by + j())
        pts = marker.extend([a, b], rng.uniform(-1, 2), rng.uniform(6, 11))
        pts = marker.wobble(pts, rng, 1.4, 40)
        marker.stroke(draw, [(x * k, y * k) for x, y in pts], 6 * k, 255, taper=0.35)
    mask = image.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def magnet() -> Image.Image:
    """A round plastic magnet (128x128): a light body, a darker rim toward the
    lower right, a bright gloss at the upper left and a soft shadow. Greys, so
    ImageColor3 makes it any color."""
    size, k = 128, S
    big = size * k
    cx, cy, r = 62 * k, 60 * k, 50 * k
    shade = Image.new("L", (big, big), 0)
    ImageDraw.Draw(shade).ellipse((cx - r + 3 * k, cy - r + 7 * k, cx + r + 3 * k, cy + r + 7 * k), fill=150)
    shade = shade.filter(ImageFilter.GaussianBlur(5 * k))
    image = Image.new("RGBA", (big, big), (40, 40, 40, 0))
    image.putalpha(shade)
    body = Image.new("RGBA", (big, big))
    px = body.load()
    for y in range(cy - r - 2, cy + r + 2, 1):
        for x in range(cx - r - 2, cx + r + 2, 1):
            dx, dy = (x - cx) / r, (y - cy) / r
            d = math.hypot(dx, dy)
            if d > 1:
                continue
            light = 0.5 - 0.5 * (dx * 0.55 + dy * 0.75)  # 1 at the upper left
            rim = max(0.0, (d - 0.82) / 0.18)
            v = 0.86 + 0.1 * light - 0.28 * rim * (1 - light * 0.6)
            g = round(255 * max(0.0, min(1.0, v)))
            px[x, y] = (g, g, g, 255)
    image.alpha_composite(body)
    gloss = Image.new("L", (big, big), 0)
    ImageDraw.Draw(gloss).ellipse((cx - r * 0.62, cy - r * 0.72, cx + r * 0.08, cy - r * 0.22), fill=230)
    gloss = gloss.filter(ImageFilter.GaussianBlur(5 * k))
    image.alpha_composite(Image.merge("RGBA", (*[Image.new("L", (big, big), 255)] * 3, gloss)))
    return image.resize((size, size), Image.LANCZOS)


def scribble_circle() -> Image.Image:
    """A loose circle drawn in one go (256x256), a bit more than a full turn,
    thinning where the marker lands and lifts. White on transparent."""
    size, k = 256, S
    rng = random.Random("scribble-circle:3")
    image = Image.new("L", (size * k, size * k), 0)
    pts = marker.loop(128, 128, 108, 98, rng, 1.16, -0.12)
    marker.stroke(ImageDraw.Draw(image), [(x * k, y * k) for x, y in pts], 10 * k, 255, taper=0.6)
    mask = image.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def tape() -> Image.Image:
    """A strip of masking tape (128x48) in full color: cream, about 80% opaque,
    with torn zigzag ends, faint fibers along it and slightly darker edges."""
    w, h, k = 128, 48, S
    rng = random.Random("tape:1")
    mask = Image.new("L", (w * k, h * k), 0)
    top, bottom = 6 * k, (h - 6) * k
    left = [(rng.uniform(3, 9) * k, top + (bottom - top) * i / 8) for i in range(9)]
    right = [((w - rng.uniform(3, 9)) * k, bottom - (bottom - top) * i / 8) for i in range(9)]
    ImageDraw.Draw(mask).polygon([*left, *right], fill=205)
    fibers = noise(rng, w * k, 4, 60).resize((w * k, h * k), Image.BILINEAR)
    fibers = fibers.filter(ImageFilter.GaussianBlur((2 * k, 0)))
    color = Image.new("RGB", (w * k, h * k), TAPE)
    dark = Image.new("RGB", (w * k, h * k), (200, 188, 150))
    color = Image.composite(dark, color, fibers.point(lambda v: max(0, v - 128) // 3))
    edge = Image.new("L", (w * k, h * k), 0)
    ImageDraw.Draw(edge).rectangle((0, top, w * k, top + k), fill=90)
    ImageDraw.Draw(edge).rectangle((0, bottom - k, w * k, bottom), fill=90)
    color = Image.composite(dark, color, edge.filter(ImageFilter.GaussianBlur(k)))
    out = color.convert("RGBA")
    out.putalpha(mask)
    return out.resize((w, h), Image.LANCZOS)


IMAGES = (
    ("ui-shadow.png", shadow),
    ("ui-glow.png", glow),
    ("ui-dots.png", dots),
    ("board.png", board),
    ("sticky.png", sticky),
    ("marker-box.png", marker_box),
    ("magnet.png", magnet),
    ("scribble-circle.png", scribble_circle),
    ("tape.png", tape),
)


def main() -> None:
    for name, make in IMAGES:
        path = os.path.join(HERE, name)
        make().save(path)
        print(f"wrote {os.path.relpath(path)}")


if __name__ == "__main__":
    main()
