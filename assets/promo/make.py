"""Draws the experience page art in the whiteboard look: the icon (three
variants) and the four thumbnails (docs/proposals/whiteboard.md).

Run from the repository root:  python3 assets/promo/make.py [--sheet PATH]
Needs Pillow 11 (PIL). Everything is drawn here; nothing is downloaded and
no snapshot is taken. Run assets/ui/make.py and assets/icons/make.py first:
this reads their PNGs (the board, sticky note, magnet, tape, circle and the
marker icons) as well as the portraits (assets/portraits/<id>.png) and the
real map's shapes and marker ink from scripts/mapgen (states colored in with
the game's own scribble, slanted / for blue and \\ for red like the seats).

Writes, next to this script:
  icon-map.png, icon-faceoff.png, icon-stamp.png   512x512 icon variants
  icon.png                                         the recommended one (a copy)
  thumb-1-hero.png      the two candidates taped up either side of the map
  thumb-2-campaign.png  the week's plan on sticky notes, "Race to 270 in 12 weeks"
  thumb-3-debate.png    a debate round on the board, "Win the live debates"
  thumb-4-landslide.png the win: the map gone blue, "Win by a LANDSLIDE"
--sheet PATH also writes a contact sheet: every icon at 512, 150 and 50 px and
every thumbnail at full width and at Home-page card size.

Roblox's rules (create.roblox.com, checked Oct 24, 2026): icon square, at
least 512x512, shown as small as about 150x150; thumbnails 16:9, 1920x1080,
PNG or JPG, under 3 MB, keep nothing that matters at the bottom (the player
count covers it). Everything is fictional: the candidates are the game's own,
the map shows a made-up result, the issue is one of the game's neutral eight,
and the only words are the game's.

Fonts (in tests/lib/fonts; Permanent Marker is Apache 2.0, Patrick Hand SIL OFL): Permanent Marker for the wordmark and
headings, Patrick Hand for hand-lettered labels (the game's two whiteboard
fonts). Colors copy src/shared/UI/Colors.luau (keep in sync).
"""

from __future__ import annotations

import importlib.util
import math
import os
import random
import shutil
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
UI = os.path.join(ROOT, "assets", "ui")
sys.path.insert(0, UI)

import marker  # noqa: E402  (assets/ui/marker.py)

# ---------------------------------------------------------------- palette
# From src/shared/UI/Colors.luau (keep in sync).
BOARD = (243, 241, 234)  # background
CARD = (255, 254, 250)  # surfaceTop: photo paper
RAISED = (236, 232, 222)  # raised: behind a face
LINE = (143, 139, 128)  # line
INK = (29, 29, 31)  # text: black marker
MUTED = (87, 84, 76)  # pencil grey
STICKY = (255, 242, 168)  # sticky
HIGHLIGHT = (255, 227, 71)  # highlighter
BLUE = (31, 91, 208)  # Cobalt
RED = (200, 20, 70)  # Crimson
NOTE_BLUE = (205, 228, 255)  # a second sticky color (promo only)
NOTE_GREEN = (214, 240, 200)  # a third (promo only)
NOTE_PINK = (255, 214, 226)  # a fourth (promo only)

NAMES = {"okafor": "Goldie", "calloway": "Buster", "hale": "Percy", "venkat": "Mavis"}  # display first names

FONT_DIR = os.path.join(ROOT, "tests", "lib", "fonts")
FONT_FILES = {"marker": "PermanentMarker-Regular.ttf", "hand": "PatrickHand-Regular.ttf"}


def font(kind: str, px: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(os.path.join(FONT_DIR, FONT_FILES[kind]), max(1, int(px)))


def tint(base, color, t):
    return tuple(round(b + (c - b) * t) for b, c in zip(base, color))


# ---------------------------------------------------------------- image helpers


def load(path: str) -> Image.Image:
    return Image.open(path).convert("RGBA")


def colored(img: Image.Image, color) -> Image.Image:
    """`img` multiplied by `color` (ImageColor3), alpha kept."""
    rgb = ImageChops.multiply(img.convert("RGB"), Image.new("RGB", img.size, tuple(color)))
    out = rgb.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out


def solid(mask: Image.Image, color, alpha=1.0) -> Image.Image:
    out = Image.new("RGBA", mask.size, tuple(color) + (0,))
    out.putalpha(mask.point(lambda v: int(v * alpha)) if alpha != 1.0 else mask)
    return out


def paste(base: Image.Image, img: Image.Image, at, anchor=(0.5, 0.5)):
    x = int(round(at[0] - img.width * anchor[0]))
    y = int(round(at[1] - img.height * anchor[1]))
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(img, (x, y))
    base.alpha_composite(layer)


def shadow(img: Image.Image, blur: float, alpha: float, dx=0.0, dy=0.0) -> Image.Image:
    pad = int(blur * 3)
    out = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    mask = Image.new("L", out.size, 0)
    mask.paste(img.getchannel("A"), (pad + int(dx), pad + int(dy)))
    mask = mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * alpha))
    out.putalpha(mask)
    return out


def with_shadow(img: Image.Image, blur: float, alpha: float, dx: float, dy: float) -> Image.Image:
    sh = shadow(img, blur, alpha, dx, dy)
    pad = (sh.width - img.width) // 2
    sh.alpha_composite(img, (pad, pad))
    return sh


def rotated(img: Image.Image, degrees: float) -> Image.Image:
    return img.rotate(degrees, expand=True, resample=Image.Resampling.BICUBIC)


def trim(img: Image.Image) -> Image.Image:
    box = img.getchannel("A").getbbox()
    return img.crop(box) if box else img


def board(w: int, h: int, scale: float) -> Image.Image:
    """The board texture (assets/ui/board.png) tiled at `scale`, with a soft
    light from the upper left so it reads as a real surface."""
    tile = load(os.path.join(UI, "board.png")).convert("RGB")
    n = max(1, int(round(512 * scale)))
    tile = tile.resize((n, n), Image.Resampling.LANCZOS)
    out = Image.new("RGB", (w, h))
    for x in range(0, w, n):
        for y in range(0, h, n):
            out.paste(tile, (x, y))
    light = Image.radial_gradient("L").resize((w * 2, h * 2)).crop((int(w * 0.6), int(h * 0.6), int(w * 1.6), int(h * 1.6)))
    shade = Image.new("RGB", (w, h), (205, 200, 188))
    out = Image.composite(shade, out, light.point(lambda v: int(v * 0.10)))
    return out.convert("RGBA")


# ---------------------------------------------------------------- marker drawing


def text(s: str, kind: str, px: float, color, tilt: float = 0.0) -> Image.Image:
    f = font(kind, px)
    x0, y0, x1, y1 = f.getbbox(s)
    pad = int(px * 0.2)
    img = Image.new("RGBA", (x1 - x0 + 2 * pad, y1 - y0 + 2 * pad), tuple(color) + (0,))
    ImageDraw.Draw(img).text((pad - x0, pad - y0), s, font=f, fill=tuple(color) + (255,))
    return trim(rotated(img, tilt)) if tilt else trim(img)


def line_img(size, pts, width, color, seed, amp=None, taper=0.4) -> Image.Image:
    rng = random.Random(seed)
    mask = Image.new("L", size, 0)
    path = marker.wobble(pts, rng, amp if amp is not None else width * 0.25, width * 8)
    marker.stroke(ImageDraw.Draw(mask), path, width, 255, taper=taper)
    return solid(mask, color)


def underline(w: float, width: float, color, seed: str, rise=0.06) -> Image.Image:
    """A fast marker swoosh `w` long, rising a little to the right."""
    h = int(w * rise + width * 4)
    pts = [(width * 2, h - width * 2), (w * 0.5, h - width * 2 - w * rise * 0.35), (w - width * 2, width * 2)]
    pts = marker.resample(pts, width * 0.5)
    return line_img((int(w), h), pts, width, color, seed, amp=width * 0.15, taper=0.7)


def arrow(size, pts, width, color, seed) -> Image.Image:
    """A hand-drawn arrow along `pts` with an open head at the end."""
    img = line_img(size, marker.resample(pts, width * 0.5), width, color, seed, taper=0.2)
    (ax, ay), (bx, by) = pts[-2], pts[-1]
    a = math.atan2(by - ay, bx - ax)
    d = ImageDraw.Draw(img)
    for turn in (2.55, -2.55):
        tip = (bx + math.cos(a + turn) * width * 5, by + math.sin(a + turn) * width * 5)
        marker.stroke(d, marker.resample([(bx, by), tip], width * 0.5), width, tuple(color) + (255,), taper=0.3)
    return img


def circled(w: int, h: int, color) -> Image.Image:
    """scribble-circle.png stretched to w x h and tinted."""
    return colored(load(os.path.join(UI, "scribble-circle.png")).resize((w, h), Image.Resampling.LANCZOS), color)


def highlight(w: int, h: int, seed: str) -> Image.Image:
    """A highlighter band: flat, translucent yellow, slightly uneven ends."""
    rng = random.Random(seed)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(
        [(rng.uniform(0, h * 0.3), 0), (w - rng.uniform(0, h * 0.3), rng.uniform(0, h * 0.1)), (w - rng.uniform(0, h * 0.2), h), (rng.uniform(0, h * 0.2), h - rng.uniform(0, h * 0.1))],
        fill=200,
    )
    return solid(mask, HIGHLIGHT)


def wordmark(px: float, tagline: bool = True) -> Image.Image:
    """LANDSLIDE in red marker, a blue swoosh under it, and "RACE TO 270"
    hand-lettered under the swoosh's right end."""
    word = text("LANDSLIDE", "marker", px, RED)
    swoosh = underline(word.width * 1.02, px * 0.11, BLUE, "wordmark-underline")
    tag = text("RACE TO 270", "hand", px * 0.42, INK) if tagline else None
    w = int(word.width * 1.06)
    sy = int(word.height * 0.98 - swoosh.height * 0.35)  # the swoosh's top
    ty = int(word.height + px * 0.12)  # the tagline's top: just under the swoosh's right end
    h = max(sy + swoosh.height, ty + (tag.height if tag else 0))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(word, ((w - word.width) // 2, 0))
    out.alpha_composite(swoosh, ((w - swoosh.width) // 2, sy))
    if tag:
        out.alpha_composite(tag, (w - tag.width - int(px * 0.15), ty))
    return trim(out)


# ---------------------------------------------------------------- props


def nine_slice(img: Image.Image, center, w: int, h: int, scale: float) -> Image.Image:
    """A PIL 9-slice like ImageLabel ScaleType.Slice with SliceScale `scale`."""
    l, t, r, b = center
    iw, ih = img.size
    cols = [(0, l), (l, r), (r, iw)]
    rows = [(0, t), (t, b), (b, ih)]
    out_cols = [int(l * scale), w - int(l * scale) - int((iw - r) * scale), int((iw - r) * scale)]
    out_rows = [int(t * scale), h - int(t * scale) - int((ih - b) * scale), int((ih - b) * scale)]
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = 0
    for (y0, y1), oh in zip(rows, out_rows):
        x = 0
        for (x0, x1), ow in zip(cols, out_cols):
            if ow > 0 and oh > 0:
                out.paste(img.crop((x0, y0, x1, y1)).resize((ow, oh), Image.Resampling.LANCZOS), (x, y))
            x += ow
        y += oh
    return out


def sticky(w: int, h: int, color, lines=(), px: float = 0, tilt: float = 0.0, ink=INK, kind="hand") -> Image.Image:
    """A sticky note (assets/ui/sticky.png, tinted) w x h of paper, with
    hand-lettered `lines`, turned `tilt` degrees."""
    s = h / 112 * 0.6  # the slice's corners grow with the note
    pad_l, pad_t, pad_r, pad_b = 4 * s, 4 * s, 12 * s, 12 * s
    note = nine_slice(load(os.path.join(UI, "sticky.png")), (32, 32, 88, 88), int(w + pad_l + pad_r), int(h + pad_t + pad_b), s)
    note = colored(note, color)
    if lines:
        size = px or h * 0.22
        imgs = [text(line, kind, size, ink) for line in lines]
        gap = size * 0.25
        total = sum(i.height for i in imgs) + gap * (len(imgs) - 1)
        y = pad_t + (h - total) / 2
        for img in imgs:
            note.alpha_composite(img, (int(pad_l + (w - img.width) / 2), int(y)))
            y += img.height + gap
    return rotated(note, tilt) if tilt else note


def magnet(px: int, color) -> Image.Image:
    return colored(load(os.path.join(UI, "magnet.png")).resize((px, px), Image.Resampling.LANCZOS), color)


def tape(w: int, tilt: float) -> Image.Image:
    t = load(os.path.join(UI, "tape.png"))
    return rotated(t.resize((w, int(w * t.height / t.width)), Image.Resampling.LANCZOS), tilt)


def icon(name: str, px: int, color) -> Image.Image:
    return colored(load(os.path.join(ROOT, "assets", "icons", f"{name}.png")).resize((px, px), Image.Resampling.LANCZOS), color)


def photo(cid: str, px: int, tilt: float, ink=None, label: str | None = None) -> Image.Image:
    """A candidate's portrait as UI/Board.photo draws it: a paper card, the face
    in a square window, a thick chin (here with the name in the player's ink),
    tape on top, turned `tilt` degrees, with a soft shadow."""
    m = round(px * 0.07)
    win = px - 2 * m
    chin = round(px * 0.2)
    w, h = px, m + win + chin
    top = int(px * 0.12)  # room for the tape
    card = Image.new("RGBA", (w, h + top), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rectangle((0, top, w - 1, top + h - 1), fill=CARD + (255,), outline=LINE + (102,), width=max(1, px // 160))
    d.rectangle((m, top + m, m + win - 1, top + m + win - 1), fill=RAISED + (255,))
    face = load(os.path.join(ROOT, "assets", "portraits", f"{cid}.png")).resize((win, win), Image.Resampling.LANCZOS)
    card.alpha_composite(face, (m, top + m))
    if label:
        name = text(label, "marker", chin * 0.62, ink or INK)
        card.alpha_composite(name, ((w - name.width) // 2, top + m + win + (chin - m - name.height) // 2 + m // 2))
    strip = tape(int(px * 0.55), 4)
    card.alpha_composite(strip, ((w - strip.width) // 2, max(0, top - strip.height // 2)))
    out = rotated(card, tilt)
    return with_shadow(out, px * 0.02, 0.28, px * 0.012, px * 0.025)


# ---------------------------------------------------------------- the map


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(path))
    spec.loader.exec_module(mod)
    sys.path.pop(0)
    return mod


_mapgen = None
_loaded = None


def mapgen():
    global _mapgen, _loaded
    if _mapgen is None:
        _mapgen = _load_module("mapgen_make", os.path.join(ROOT, "scripts", "mapgen", "make.py"))
        _loaded = _mapgen.load_states()
    return _mapgen, _loaded


LOWER48_SKIP = ("AK", "HI")


def centroid(sid):
    _, (shapes, _order, _b, _i) = mapgen()
    ring = max((poly[0] for poly in shapes[sid]), key=lambda r: abs(_area(r)))
    return sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring)


def _area(ring):
    return sum(ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1] for i in range(len(ring) - 1)) / 2


def draw_map(width: int, fills: dict, ink_scale: float = 1.0):
    """The lower 48 on the board, `width` px wide: each state in `fills`
    (id -> (color, strength 0..1, slant "/" or "\\")) colored in with the
    game's scribble (scripts/mapgen scribble, at this size), every border in
    the game's wobbly marker ink. Returns (image, project) where project(x, y)
    maps map units to image px."""
    mg, (shapes, order, _borders, ink_lines) = mapgen()
    pts = [p for line, _ in ink_lines for p in line]
    x0, y0 = min(p[0] for p in pts), min(p[1] for p in pts)
    x1, y1 = max(p[0] for p in pts), max(p[1] for p in pts)
    pad = 8
    k = (width - 2 * pad) / (x1 - x0)
    height = int((y1 - y0) * k + 2 * pad)

    def project(x, y):
        return (x - x0) * k + pad, (y - y0) * k + pad

    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    # The scribble at this scale: the game's hatch pitch is in atlas px at
    # RES 1.3; keep the same look relative to the map.
    f = k / 1.3
    mg.RES = k
    mg.HATCH_PITCH, mg.HATCH_W, mg.HATCH_WOBBLE = 9.0 * f * 0.75, 6.2 * f * 0.75, 0.7 * f
    for sid in order:
        if sid in LOWER48_SKIP or sid not in fills:
            continue
        color, strength, slant = fills[sid]
        polys = shapes[sid]
        sp = [p for poly in polys for ring in poly for p in ring]
        sx0, sy0 = min(p[0] for p in sp), min(p[1] for p in sp)
        sx1, sy1 = max(p[0] for p in sp), max(p[1] for p in sp)
        w, h = int(math.ceil((sx1 - sx0) * k)) + 4, int(math.ceil((sy1 - sy0) * k)) + 4
        sprite = mg.mask(polys, sx0 - 2 / k, sy0 - 2 / k, w, h)
        hatch = mg.scribble(sprite, slant, sid)
        layer = colored(hatch, tint(BOARD, color, strength))
        px, py = project(sx0 - 2 / k, sy0 - 2 / k)
        img.alpha_composite(layer, (int(round(px)), int(round(py))))
    # Line widths as in map-ink.png, whose scale fits the lower 48 (plus the
    # ink's pad) in mapgen.ATLAS px.
    span = max(x1 - x0, y1 - y0) + 2 * mg.INK_PAD
    native = mg.ATLAS / span
    big = 2
    mask = Image.new("L", (width * big, height * big), 0)
    d = ImageDraw.Draw(mask)
    for index, (line, coast) in enumerate(ink_lines):
        rng = random.Random(f"ink:{index}")
        bent = mg.wobbly(line, rng)
        base = (mg.INK_COAST_PX if coast else mg.INK_INNER_PX) / native * k * ink_scale
        for start in range(0, len(bent) - 1, 12):
            piece = bent[start : start + 13]
            if len(piece) < 2:
                continue
            wpx = max(1, round(base * rng.uniform(0.85, 1.15) * big))
            value = int(255 * rng.uniform(0.9, 1.0))
            d.line([((x - x0) * k * big + pad * big, (y - y0) * k * big + pad * big) for x, y in piece], fill=value, width=wpx, joint="curve")
    mask = mask.resize((width, height), Image.Resampling.LANCZOS)
    img.alpha_composite(solid(mask, INK))
    return img, project


def lower48():
    _, (_shapes, order, _b, _i) = mapgen()
    return [s for s in order if s not in LOWER48_SKIP]


def split_fills(tilt=0.35, blank=()):
    """Blue west, red east along a slanted line (the race, not a real result);
    states near the line are leans, `blank` ones toss-ups (no fill)."""
    ids = lower48()
    cs = {sid: centroid(sid) for sid in ids}
    xs = [c[0] for c in cs.values()]
    ys = [c[1] for c in cs.values()]
    mid, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(xs) - min(xs)
    fills = {}
    for sid in ids:
        if sid in blank:
            continue
        cx, cy = cs[sid]
        v = cx + (cy - my) * tilt - mid
        side = v < 0
        strength = 1.0 if abs(v) > span * 0.12 else 0.6
        fills[sid] = (BLUE, strength, "/") if side else (RED, strength, "\\")
    return fills


def result_fills(seed: int, blue_share: float, blank=()):
    """A made-up result: each state blue or red, safe or lean."""
    rng = random.Random(seed)
    fills = {}
    for sid in lower48():
        roll = rng.random()
        strength = rng.choice((0.6, 0.85, 1.0, 1.0))
        if sid in blank:
            continue
        fills[sid] = (BLUE, strength, "/") if roll < blue_share else (RED, strength, "\\")
    return fills


# ---------------------------------------------------------------- icons

ICON = 512
S = 4  # icon supersampling


def finish(img: Image.Image, size) -> Image.Image:
    return img.convert("RGB").resize(size, Image.Resampling.LANCZOS)


def icon_map() -> Image.Image:
    """The US scribbled blue | red, a big "270" circled in red marker under it."""
    n = ICON * S
    img = board(n, n, S)
    m, _ = draw_map(int(n * 0.94), split_fills(), ink_scale=1.6)
    paste(img, m, (n * 0.5, n * 0.33))
    big = text("270", "marker", n * 0.36, INK, tilt=-3)
    ring = circled(int(big.width * 1.55), int(big.height * 1.6), RED)
    paste(img, ring, (n * 0.5, n * 0.74))
    paste(img, big, (n * 0.5, n * 0.74))
    return finish(img, (ICON, ICON))


def icon_faceoff() -> Image.Image:
    """Two candidates taped up, blue and red magnets, "VS" between them."""
    n = ICON * S
    img = board(n, n, S)
    left = photo("okafor", int(n * 0.44), 5, BLUE, None)
    right = photo("calloway", int(n * 0.44), -4, RED, None)
    paste(img, left, (n * 0.27, n * 0.42))
    paste(img, right, (n * 0.73, n * 0.46))
    paste(img, with_shadow(magnet(int(n * 0.11), BLUE), n * 0.006, 0.3, 0, n * 0.006), (n * 0.27, n * 0.16))
    paste(img, with_shadow(magnet(int(n * 0.11), RED), n * 0.006, 0.3, 0, n * 0.006), (n * 0.73, n * 0.2))
    vs = text("VS", "marker", n * 0.16, INK, tilt=-6)
    paste(img, vs, (n * 0.5, n * 0.5))
    tag = text("270", "marker", n * 0.2, INK, tilt=-2)
    paste(img, underline(tag.width * 1.4, n * 0.022, RED, "icon-faceoff-underline"), (n * 0.5, n * 0.93))
    paste(img, tag, (n * 0.5, n * 0.84))
    return finish(img, (ICON, ICON))


def icon_stamp() -> Image.Image:
    """The wordmark over a faded scribbled map."""
    n = ICON * S
    img = board(n, n, S)
    m, _ = draw_map(int(n * 1.0), split_fills(), ink_scale=1.4)
    faded = m.copy()
    faded.putalpha(m.getchannel("A").point(lambda v: int(v * 0.45)))
    paste(img, faded, (n * 0.5, n * 0.5))
    wm = wordmark(n * 0.2)
    wm = wm.resize((int(n * 0.92), int(wm.height * n * 0.92 / wm.width)), Image.Resampling.LANCZOS)
    paste(img, wm, (n * 0.5, n * 0.5))
    return finish(img, (ICON, ICON))


# ---------------------------------------------------------------- thumbnails

TW, TH = 1920, 1080
T = 2  # thumbnail supersampling
SAFE_X = 96  # px: text and faces stay inside this side margin
SAFE_BOTTOM = 150  # px: nothing that matters in the bottom strip (player count)


def heading(s: str, px: float, color=INK, tilt=-2.0) -> Image.Image:
    return text(s, "marker", px * T, color, tilt=tilt)


def thumb_hero() -> Image.Image:
    """The two candidates taped up either side of the scribbled map, the
    wordmark on top, a sticky note pointing at the deciding state."""
    w, h = TW * T, TH * T
    img = board(w, h, T)
    decider = "MO"
    blank = ("MO", "WI", "NV", "NC", "PA")
    m, project = draw_map(int(w * 0.5), result_fills(270, 0.5, blank=blank))
    cx, cy = w * 0.5, h * 0.56
    paste(img, m, (cx, cy))
    mx, my = cx - m.width / 2, cy - m.height / 2
    px, py = project(*centroid(decider))
    ring = circled(int(150 * T), int(120 * T), INK)
    paste(img, ring, (mx + px, my + py))
    note = sticky(250 * T, 150 * T, STICKY, ["Swing state!", "10 votes"], px=40 * T, tilt=4)
    nx, ny = w * 0.62, h * 0.84 - SAFE_BOTTOM * T * 0.4
    paste(img, with_shadow(note, 4 * T, 0.15, 0, 3 * T), (nx, ny))
    paste(img, arrow((w, h), [(nx - 120 * T, ny - 50 * T), (nx - 170 * T, ny - 110 * T), (mx + px + 60 * T, my + py + 50 * T)], 6 * T, INK, "hero-arrow"), (w / 2, h / 2))
    size = int(380 * T)
    paste(img, photo("okafor", size, 4, BLUE, NAMES["okafor"]), (SAFE_X * T + size * 0.58, h * 0.53))
    paste(img, photo("calloway", size, -3, RED, NAMES["calloway"]), (w - SAFE_X * T - size * 0.58, h * 0.55))
    paste(img, with_shadow(magnet(54 * T, BLUE), 2 * T, 0.3, 0, 3 * T), (SAFE_X * T + size * 0.58, h * 0.53 - size * 0.62))
    paste(img, with_shadow(magnet(54 * T, RED), 2 * T, 0.3, 0, 3 * T), (w - SAFE_X * T - size * 0.58, h * 0.55 - size * 0.62))
    wm = wordmark(170 * T)
    paste(img, wm, (w * 0.5, 40 * T), (0.5, 0))
    return finish(img, (TW, TH))


def tracker(rows, w: int, title="TRACKER") -> Image.Image:
    """A hand-ruled table: a title, then (label, value, color) rows."""
    row_h = int(w * 0.2)
    h = row_h * (len(rows) + 1) + int(w * 0.06)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    t = text(title, "marker", row_h * 0.62, INK)
    img.alpha_composite(t, (int(w * 0.04), int(row_h * 0.15)))
    lw = max(2, w // 110)
    d = ImageDraw.Draw(img)
    rng = random.Random(f"tracker:{title}:{w}")
    for i in range(len(rows) + 1):
        y = row_h * (i + 1)
        pts = marker.wobble([(w * 0.02, y), (w * 0.98, y)], rng, lw * 0.4, w * 0.3)
        marker.stroke(d, pts, lw, INK + (255,), taper=0.3)
    split = w * 0.58
    pts = marker.wobble([(split, row_h * 1.05), (split, h - lw * 2)], rng, lw * 0.4, w * 0.3)
    marker.stroke(d, pts, lw, INK + (255,), taper=0.3)
    for i, (label, value, color) in enumerate(rows):
        y = row_h * (i + 1)
        a = text(label, "hand", row_h * 0.6, color)
        b = text(value, "hand", row_h * 0.72, color)
        img.alpha_composite(a, (int(w * 0.05), int(y + (row_h - a.height) / 2)))
        img.alpha_composite(b, (int(split + (w - split - b.width) / 2), int(y + (row_h - b.height) / 2)))
    return img


def thumb_campaign() -> Image.Image:
    """A campaign week planned on the board: the actions on sticky notes with
    their marker icons, arrows to the states, the tracker, the heading."""
    w, h = TW * T, TH * T
    img = board(w, h, T)
    blank = ("MO", "WI", "NV", "NC", "PA", "GA", "AZ", "MI", "VA", "NH")
    fills = result_fills(12, 0.5, blank=blank)
    for sid in list(fills):
        if fills[sid][1] == 1.0 and random.Random(sid).random() < 0.2:
            del fills[sid]  # still open this early
    m, project = draw_map(int(w * 0.5), fills)
    cx, cy = w * 0.6, h * 0.6
    paste(img, m, (cx, cy))
    mx, my = cx - m.width / 2, cy - m.height / 2
    title = heading("Race to 270", 120)
    hl = highlight(int(title.width * 0.36), int(title.height * 0.62), "campaign-hl")
    tx, ty = SAFE_X * T, 50 * T
    paste(img, hl, (tx + title.width * 0.82, ty + title.height * 0.58))
    paste(img, title, (tx, ty), (0, 0))
    sub = text("in 12 weeks", "hand", 72 * T, MUTED, tilt=-2)
    paste(img, sub, (tx + title.width + 30 * T, ty + title.height * 0.75), (0, 0.5))
    plans = [
        ("megaphone", "Rally", STICKY, "MO", 3),
        ("coins", "Fundraise", NOTE_GREEN, None, -3),
        ("tv", "TV ad", NOTE_BLUE, None, 2),
        ("footprints", "Ground game", NOTE_PINK, "GA", -2),
    ]
    nw, nh = 380 * T, 140 * T
    for i, (name, label, color, target, tilt) in enumerate(plans):
        note = sticky(nw, nh, color)
        doodle = icon(name, int(72 * T), INK)
        word = text(label, "hand", 50 * T, INK)
        bx = int(nw * 0.08)
        note.alpha_composite(doodle, (bx, (nh - doodle.height) // 2))
        note.alpha_composite(word, (bx + doodle.width + int(18 * T), (nh - word.height) // 2))
        note = rotated(note, tilt)
        x, y = SAFE_X * T + nw * 0.5, 300 * T + i * 158 * T
        paste(img, with_shadow(note, 4 * T, 0.15, 0, 3 * T), (x, y))
        if target:
            px, py = project(*centroid(target))
            ex, ey = mx + px, my + py
            sx, sy = x + nw * 0.55, y
            dx, dy = ex - sx, ey - sy
            dist = math.hypot(dx, dy)
            end = (ex - dx / dist * 60 * T, ey - dy / dist * 60 * T)
            mid = ((sx + end[0]) / 2, (sy + end[1]) / 2 - 70 * T)
            pts = [(sx, sy), mid, end]
            curve = [((1 - t) ** 2 * pts[0][0] + 2 * (1 - t) * t * pts[1][0] + t * t * pts[2][0], (1 - t) ** 2 * pts[0][1] + 2 * (1 - t) * t * pts[1][1] + t * t * pts[2][1]) for t in (i / 24 for i in range(25))]
            paste(img, arrow((w, h), curve, 5 * T, INK, f"campaign-{name}"), (w / 2, h / 2))
            paste(img, circled(int(96 * T), int(80 * T), INK), (ex, ey))
    tr = tracker([("Blue", "212", BLUE), ("Red", "196", RED), ("Week", "7 / 12", INK)], int(320 * T))
    paste(img, with_shadow(sticky(int(360 * T), int(tr.height + 30 * T), CARD), 4 * T, 0.12, 0, 3 * T), (w - SAFE_X * T, 30 * T), (1, 0))
    paste(img, tr, (w - SAFE_X * T - 25 * T, 45 * T), (1, 0))
    return finish(img, (TW, TH))


def thumb_debate() -> Image.Image:
    """A debate round: the two candidates, the question on a big note, the
    three moves on sticky notes with one circled, a tally of rounds."""
    w, h = TW * T, TH * T
    img = board(w, h, T)
    title = heading("Win the live debates", 112)
    paste(img, title, (w / 2, 44 * T), (0.5, 0))
    paste(img, underline(title.width * 0.5, 9 * T, BLUE, "debate-underline"), (w / 2 + title.width * 0.2, 44 * T + title.height + 10 * T))
    size = int(360 * T)
    paste(img, photo("hale", size, -4, BLUE, NAMES["hale"]), (SAFE_X * T + size * 0.56, h * 0.5))
    paste(img, photo("venkat", size, 3, RED, NAMES["venkat"]), (w - SAFE_X * T - size * 0.56, h * 0.52))
    q = sticky(640 * T, 230 * T, CARD, ["Roads & Transit:", "what's your plan?"], px=62 * T, tilt=-1)
    paste(img, with_shadow(q, 5 * T, 0.15, 0, 4 * T), (w / 2, h * 0.39))
    paste(img, with_shadow(magnet(46 * T, INK), 2 * T, 0.3, 0, 3 * T), (w / 2, h * 0.39 - 125 * T))
    moves = [("DEFEND", NOTE_BLUE, -4), ("ATTACK", NOTE_PINK, 3), ("PIVOT", NOTE_GREEN, -2)]
    for i, (word, color, tilt) in enumerate(moves):
        note = sticky(250 * T, 130 * T, color, [word], px=48 * T, tilt=tilt, kind="marker")
        x, y = w / 2 + (i - 1) * 285 * T, h * 0.66
        paste(img, with_shadow(note, 4 * T, 0.15, 0, 3 * T), (x, y))
        if word == "ATTACK":
            paste(img, circled(int(330 * T), int(210 * T), RED), (x, y))
    tally = text("Round 2 of 3", "hand", 54 * T, MUTED, tilt=-2)
    paste(img, tally, (w / 2, h * 0.8), (0.5, 0.5))
    return finish(img, (TW, TH))


def stars(img: Image.Image, n: int, seed: str, area, colors, size, avoid=None):
    """Little marker stars and dashes (hand-drawn celebration), none inside the
    ellipses in `avoid` ((cx, cy, rx, ry), ...)."""
    rng = random.Random(seed)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = area
    placed = 0
    while placed < n:
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if any(((x - ax) / rx) ** 2 + ((y - ay) / ry) ** 2 < 1.15 for ax, ay, rx, ry in avoid or ()):
            continue
        placed += 1
        color = rng.choice(colors) + (255,)
        r = size * rng.uniform(0.7, 1.2)
        if rng.random() < 0.5:
            for a in range(3):
                t = a * math.pi / 3 + rng.uniform(-0.2, 0.2)
                pts = [(x - math.cos(t) * r, y - math.sin(t) * r), (x + math.cos(t) * r, y + math.sin(t) * r)]
                marker.stroke(d, marker.resample(pts, size * 0.1), size * 0.22, color, taper=0.4)
        else:
            t = rng.uniform(0, math.tau)
            pts = [(x, y), (x + math.cos(t) * r * 1.4, y + math.sin(t) * r * 1.4)]
            marker.stroke(d, marker.resample(pts, size * 0.1), size * 0.22, color, taper=0.5)


def thumb_landslide() -> Image.Image:
    """The win: the map scribbled almost all blue, the winner taped up,
    LANDSLIDE circled, the tally 386 to 152 on a note under the photo."""
    w, h = TW * T, TH * T
    img = board(w, h, T)
    m, _ = draw_map(int(w * 0.48), result_fills(386, 0.84))
    cx = w * 0.64
    paste(img, m, (cx, h * 0.64))
    size = int(360 * T)
    px, py = SAFE_X * T + size * 0.6, h * 0.4
    paste(img, photo("okafor", size, -4, BLUE, NAMES["okafor"]), (px, py))
    paste(img, with_shadow(magnet(54 * T, BLUE), 2 * T, 0.3, 0, 3 * T), (px, py - size * 0.66))
    note = sticky(int(420 * T), int(130 * T), STICKY, tilt=2)
    ny = py + size * 0.82
    paste(img, with_shadow(note, 4 * T, 0.15, 0, 3 * T), (px, ny))
    paste(img, text("386", "marker", 88 * T, BLUE, tilt=-2), (px - 120 * T, ny - 6 * T))
    paste(img, text("to", "hand", 56 * T, MUTED), (px + 10 * T, ny))
    paste(img, text("152", "marker", 66 * T, RED, tilt=-2), (px + 125 * T, ny - 2 * T))
    word = text("LANDSLIDE!", "marker", 140 * T, BLUE, tilt=-3)
    wy = 250 * T
    ring = (int(word.width * 1.2), int(word.height * 2.0))
    eyebrow = text("Win by a", "hand", 76 * T, INK, tilt=-3)
    ex, ey = cx - word.width * 0.32, wy - ring[1] / 2 - 10 * T
    paste(img, eyebrow, (ex, ey), (0.5, 0.5))
    avoid = ((cx, wy, ring[0] * 0.56, ring[1] * 0.56), (ex, ey, eyebrow.width * 0.75, eyebrow.height * 0.9))
    stars(img, 26, "landslide-stars", (w * 0.36, 20 * T, w - SAFE_X * T, wy + ring[1] * 0.6), (BLUE, RED, INK), 20 * T, avoid=avoid)
    paste(img, circled(*ring, RED), (cx, wy))
    paste(img, word, (cx, wy))
    return finish(img, (TW, TH))


# ---------------------------------------------------------------- sheet and main


def contact_sheet(icons: dict, thumbs: dict, path: str):
    pad = 32
    card_w = 384  # about a Home-page card
    sheet_w = 960 + card_w + 3 * pad
    rows = len(icons) * (34 + 512 + pad) + len(thumbs) * (34 + 540 + pad) + pad
    sheet = Image.new("RGB", (sheet_w, rows), (60, 60, 64))
    d = ImageDraw.Draw(sheet)
    small = font("hand", 26)
    y = pad
    for name, ic in icons.items():
        d.text((pad, y), name, font=small, fill=(230, 230, 230))
        y += 34
        x = pad
        for px in (512, 150, 50):
            sheet.paste(ic.resize((px, px), Image.Resampling.LANCZOS), (x, y + 512 - px))
            x += px + pad
        y += 512 + pad
    for name, th in thumbs.items():
        d.text((pad, y), name, font=small, fill=(230, 230, 230))
        y += 34
        sheet.paste(th.resize((960, 540), Image.Resampling.LANCZOS), (pad, y))
        sheet.paste(th.resize((card_w, card_w * 9 // 16), Image.Resampling.LANCZOS), (pad * 2 + 960, y))
        y += 540 + pad
    sheet.save(path)


def save(img: Image.Image, name: str):
    path = os.path.join(HERE, name)
    img.save(path, optimize=True)
    kb = os.path.getsize(path) / 1024
    print(f"  assets/promo/{name}  {img.width}x{img.height}  {kb:.0f} KB")
    assert kb < 3 * 1024, f"{name} is over 3 MB"


RECOMMENDED = "icon-map.png"  # reads at 50 px: the scribbled map in two colors and a circled "270"


def build():
    icons = {
        "icon-map.png": icon_map(),
        "icon-faceoff.png": icon_faceoff(),
        "icon-stamp.png": icon_stamp(),
    }
    thumbs = {
        "thumb-1-hero.png": thumb_hero(),
        "thumb-2-campaign.png": thumb_campaign(),
        "thumb-3-debate.png": thumb_debate(),
        "thumb-4-landslide.png": thumb_landslide(),
    }
    return icons, thumbs


def main():
    icons, thumbs = build()
    for name, img in icons.items():
        save(img, name)
    shutil.copyfile(os.path.join(HERE, RECOMMENDED), os.path.join(HERE, "icon.png"))
    print(f"  assets/promo/icon.png  = {RECOMMENDED}")
    for name, img in thumbs.items():
        save(img, name)
    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        contact_sheet(icons, thumbs, path)
        print(f"  sheet: {path}")


if __name__ == "__main__":
    main()
