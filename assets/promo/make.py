"""Draws the experience page art: the icon (three variants) and the thumbnails.

Run from the repository root:  python3 assets/promo/make.py [--sheet PATH]
Needs Pillow 11 (PIL). On a Mac it also uses `lune` (tests/ui/snap.luau) and
`qlmanage` for the gameplay thumbnails: they are the game's own headless UI
snapshots (desktop, 1280x720), rendered again at 2x so they stay sharp, with
the snapshot-only marks (the Roblox top-bar stand-ins and the "+N px below"
scroll markers) taken out. Nothing is downloaded.

Writes, next to this script:
  icon-map.png, icon-faceoff.png, icon-stamp.png   512x512 icon variants
  icon.png                                         the recommended one (a copy)
  thumb-1-hero.png      the two candidates over an election-night map
  thumb-2-campaign.png  a real campaign week, "Race to 270 in 12 weeks"
  thumb-3-debate.png    a real debate round, "Live debates"
  thumb-4-landslide.png the win: "Win by a LANDSLIDE"
--sheet PATH also writes a contact sheet: every icon at 512, 150 and 50 px and
every thumbnail at full width and at Home-page card size.

Roblox's rules (create.roblox.com, checked Oct 24, 2026): icon square, at
least 512x512, shown as small as about 150x150; thumbnails 16:9, 1920x1080,
PNG or JPG, under 3 MB for Home-page uploads, up to 10, keep nothing that
matters at the bottom (the player count covers it). Everything here is
fictional: the two candidates are the game's own (assets/portraits), the map
is the game's map with a made-up result, and the only words are the game's.

The palette is copied from src/shared/UI/Colors.luau and the wordmark follows
Kit.wordmark (D-064): keep them in sync. Fonts: Fredoka One (the game's
display face, SIL OFL) and Builder Sans, read from the Roblox Studio app (or
assets/promo/fonts/ if someone drops them there); without them the script
falls back to Arial Rounded Bold and Helvetica.
"""

from __future__ import annotations

import importlib.util
import math
import os
import random
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(ROOT, "build", "promo")  # scratch (gitignored)

# ---------------------------------------------------------------- palette
# From src/shared/UI/Colors.luau (keep in sync).
BACKGROUND = (11, 16, 34)
FIELD = (16, 23, 44)
SURFACE = (22, 30, 55)
SURFACE_TOP = (29, 38, 68)
RAISED = (36, 47, 80)
RAISED_TOP = (44, 56, 93)
LINE = (68, 81, 124)
TEXT = (240, 243, 250)
MUTED = (156, 168, 204)
ACCENT_EDGE = (196, 204, 224)
ACCENT_LIP = (110, 122, 158)
NEUTRAL = (70, 78, 104)
GOOD = (80, 212, 96)
GOOD_EDGE = (50, 140, 66)
GLOW = (40, 60, 136)
COBALT = (34, 98, 228)
CRIMSON = (212, 28, 66)
WORDMARK_BOTTOM = (232, 236, 248)  # Kit WORDMARK_BOTTOM
PLATE_TOP = (104, 118, 156)  # Kit.portrait's plate
PLATE_BOTTOM = (66, 76, 108)

BLUE, RED = COBALT, CRIMSON  # the two default player colors (D-055)


def tint(base, color, t):
    return tuple(int(round(b + (c - b) * t)) for b, c in zip(base, color))


def band(color, share):
    """Colors.bandFill: neutral, then 60 / 82 / 100 % of the leader's color."""
    return tint(NEUTRAL, color, share)


def lighter(color, t):
    return tint(color, (255, 255, 255), t)


def darker(color, t):
    return tint(color, (0, 0, 0), t)


# ---------------------------------------------------------------- fonts

STUDIO_FONTS = "/Applications/RobloxStudio.app/Contents/Resources/content/fonts"
FONT_FILES = {
    "display": [
        os.path.join(HERE, "fonts", "FredokaOne-Regular.ttf"),
        os.path.join(STUDIO_FONTS, "FredokaOne-Regular.ttf"),
        "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
    ],
    "bold": [
        os.path.join(HERE, "fonts", "BuilderSans-ExtraBold.otf"),
        os.path.join(STUDIO_FONTS, "BuilderSans-ExtraBold.otf"),
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ],
}
_fonts: dict = {}


def font(kind: str, px: float) -> ImageFont.FreeTypeFont:
    key = (kind, int(px))
    if key not in _fonts:
        for path in FONT_FILES[kind]:
            if os.path.exists(path):
                _fonts[key] = ImageFont.truetype(path, int(px))
                break
        else:
            raise SystemExit(f"no font for {kind}: tried {FONT_FILES[kind]}")
    return _fonts[key]


def font_used(kind: str) -> str:
    return next(p for p in FONT_FILES[kind] if os.path.exists(p))


# ---------------------------------------------------------------- basics


def solid(size, color, alpha=255):
    return Image.new("RGBA", size, tuple(color) + (alpha,))


def vgrad(size, top, bottom):
    w, h = size
    g = Image.linear_gradient("L").resize((max(1, w), max(1, h)))
    return Image.composite(solid(size, bottom), solid(size, top), g)


def with_alpha(img: Image.Image, mask: Image.Image) -> Image.Image:
    out = img.copy()
    out.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return out


def scale_alpha(img: Image.Image, k: float) -> Image.Image:
    out = img.copy()
    out.putalpha(img.getchannel("A").point(lambda v: int(v * k)))
    return out


def colored(mask: Image.Image, color, alpha=1.0) -> Image.Image:
    """A layer of `color` shaped by the L mask."""
    layer = solid(mask.size, color)
    layer.putalpha(mask.point(lambda v: int(v * alpha)) if alpha < 1 else mask)
    return layer


def radial(size, center, radius, color, alpha):
    """A soft round glow (alpha at the center, fading to 0 at `radius`)."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = int(radius * 2)
    if d < 2:
        return layer
    # PIL's radial gradient is 0 at the center and 255 in the corners (181 at
    # the middle of each edge): rescale so the glow ends inside the square.
    g = Image.radial_gradient("L").resize((d, d))
    a = g.point(lambda v: int(max(0.0, 1 - v / 180) ** 1.6 * 255 * alpha))
    blob = solid((d, d), color)
    blob.putalpha(a)
    layer.alpha_composite(blob, (int(center[0] - radius), int(center[1] - radius)))
    return layer


def paste(base: Image.Image, img: Image.Image, center, anchor=(0.5, 0.5)):
    x = int(round(center[0] - img.width * anchor[0]))
    y = int(round(center[1] - img.height * anchor[1]))
    base.alpha_composite(img, (x, y)) if x >= 0 and y >= 0 else _paste_clip(base, img, x, y)


def _paste_clip(base, img, x, y):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(img, (x, y))
    base.alpha_composite(layer)


def shadow_of(img: Image.Image, blur, alpha, color=(0, 0, 0), grow=0) -> Image.Image:
    pad = int(blur * 3 + grow)
    a = img.getchannel("A")
    canvas = Image.new("L", (img.width + 2 * pad, img.height + 2 * pad), 0)
    canvas.paste(a, (pad, pad))
    if grow:
        canvas = canvas.filter(ImageFilter.MaxFilter(int(grow) * 2 + 1))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    return colored(canvas, color, alpha)


def rounded(size, radius, fill) -> Image.Image:
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=tuple(fill) + (255,))
    return img


def rounded_mask(size, radius) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return m


def finish(img: Image.Image, size) -> Image.Image:
    """Down to the shipped size (the supersampled drawing gives clean edges)."""
    return img.resize(size, Image.Resampling.LANCZOS)


# ---------------------------------------------------------------- type


def text_mask(text: str, f: ImageFont.FreeTypeFont, stroke=0) -> Image.Image:
    """The text (with an outer stroke of `stroke` px) as an L mask, tightly cropped
    to the font's line box so different words line up."""
    asc, desc = f.getmetrics()
    w = int(f.getlength(text)) + 2 * stroke + 4
    h = asc + desc + 2 * stroke
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).text((stroke + 2, stroke), text, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
    return m


def label(text, kind, px, color, outline=0, outline_color=BACKGROUND, shadow=0) -> Image.Image:
    """Plain display text, optionally outlined and with a drop shadow."""
    f = font(kind, px)
    pad = outline + shadow * 3
    fill = text_mask(text, f, outline)
    img = Image.new("RGBA", (fill.width + 2 * pad, fill.height + 2 * pad + shadow), (0, 0, 0, 0))
    if shadow:
        sh = Image.new("L", img.size, 0)
        sh.paste(fill if outline else text_mask(text, f, 0), (pad, pad + shadow))
        img.alpha_composite(colored(sh.filter(ImageFilter.GaussianBlur(shadow)), (0, 0, 0), 0.55))
    if outline:
        img.alpha_composite(colored(_place(fill, img.size, pad), outline_color))
    inner = text_mask(text, f, 0)
    m = Image.new("L", img.size, 0)
    m.paste(inner, (pad + outline, pad + outline))
    img.alpha_composite(colored(m, color))
    return img


def _place(mask, size, at):
    m = Image.new("L", size, 0)
    m.paste(mask, (at, at))
    return m


def trim(img: Image.Image, pad=0) -> Image.Image:
    box = img.getchannel("A").getbbox()
    if not box:
        return img
    x0, y0, x1, y1 = box
    return img.crop((max(0, x0 - pad), max(0, y0 - pad), min(img.width, x1 + pad), min(img.height, y1 + pad)))


def wordmark(px: float, tagline=True, ribbon_scale=0.34, glow=True) -> Image.Image:
    """Kit.wordmark drawn large: "LANDSLIDE" in Fredoka One, lit from the top
    (text -> WORDMARK_BOTTOM), an accentLip outline, a `line` drop under it and a
    soft white glow; the "RACE TO 270" ribbon split Cobalt | Crimson, tilted -3°."""
    f = font("display", px)
    stroke = max(2, int(px * 0.055))
    drop = max(3, int(px * 0.085))
    outer = text_mask("LANDSLIDE", f, stroke)
    inner = text_mask("LANDSLIDE", f, 0)
    pad = int(px * 0.9)
    W = outer.width + 2 * pad
    H = outer.height + drop + 2 * pad + (int(px * 0.6) if tagline else 0)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ox, oy = pad, pad
    if glow:
        # An oval glow that fades out inside the canvas (no hard edge when trimmed).
        oval = radial((H, H), (H / 2, H / 2), H / 2, (255, 255, 255), 0.18).resize((W, H), Image.Resampling.BICUBIC)
        img.alpha_composite(oval)
    # The drop: the whole outlined word again, `drop` px lower, in `line`.
    img.alpha_composite(colored(_at(outer, (W, H), ox, oy + drop), LINE))
    img.alpha_composite(colored(_at(outer, (W, H), ox, oy), ACCENT_LIP))
    face = vgrad((W, H), TEXT, TEXT)
    asc, _ = f.getmetrics()
    lit = vgrad((W, int(asc * 0.9)), TEXT, WORDMARK_BOTTOM)
    face.paste(lit, (0, oy + stroke))
    face.paste(solid((W, H), WORDMARK_BOTTOM).crop((0, 0, W, H - (oy + stroke + lit.height))), (0, oy + stroke + lit.height))
    img.alpha_composite(with_alpha(face, _at(inner, (W, H), ox + stroke, oy + stroke)))
    if tagline:
        rib = ribbon("RACE TO 270", px * ribbon_scale)
        cy = oy + asc * 1.02 + stroke + rib.height * 0.3
        sh = shadow_of(rib, px * 0.05, 0.5)
        paste(img, sh, (W / 2, cy + px * 0.05))
        paste(img, rib, (W / 2, cy))
    return trim(img, int(px * 0.05))


def _at(mask, size, x, y):
    m = Image.new("L", size, 0)
    m.paste(mask, (int(x), int(y)))
    return m


def ribbon(text: str, px: float, tilt=3.0, left=BLUE, right=RED) -> Image.Image:
    """The tagline ribbon: a rounded plate split left | right, a navy edge,
    white Fredoka with a navy outline (Kit.wordmark's Ribbon)."""
    f = font("display", px)
    edge = max(2, int(px * 0.1))
    tw = f.getlength(text)
    asc, desc = f.getmetrics()
    w = int(tw + px * 1.5)
    h = int(px * 1.55)
    r = int(px * 0.4)
    plate = Image.new("RGBA", (w + 2 * edge, h + 2 * edge), (0, 0, 0, 0))
    plate.alpha_composite(rounded(plate.size, r + edge, BACKGROUND))
    face = Image.new("RGBA", (w, h))
    face.paste(vgrad((w // 2, h), lighter(left, 0.12), darker(left, 0.1)), (0, 0))
    face.paste(vgrad((w - w // 2, h), lighter(right, 0.12), darker(right, 0.1)), (w // 2, 0))
    plate.alpha_composite(with_alpha(face, rounded_mask((w, h), r)), (edge, edge))
    t = label(text, "display", px, TEXT, outline=max(2, int(px * 0.07)), outline_color=BACKGROUND)
    # Center the glyphs' cap height in the plate.
    paste(plate, t, (plate.width / 2, plate.height / 2 + (desc - (asc - px * 0.72)) * 0.0 + px * 0.06))
    return plate.rotate(tilt, resample=Image.Resampling.BICUBIC, expand=True)


def stamp(text: str, color, px: float, tilt=6.0, text_color=TEXT) -> Image.Image:
    """Kit.stamp: a plate in `color`, an edge a little darker, Fredoka text with
    an outline in the edge color, tilted -6°."""
    f = font("display", px)
    edge_c = darker(color, 0.3)
    edge = max(3, int(px * 0.07))
    tw = f.getlength(text)
    w = int(tw + px * 0.9)
    h = int(px * 1.35)
    r = int(px * 0.28)
    plate = Image.new("RGBA", (w + 2 * edge, h + 2 * edge), (0, 0, 0, 0))
    plate.alpha_composite(rounded(plate.size, r + edge, edge_c))
    plate.alpha_composite(with_alpha(vgrad((w, h), lighter(color, 0.14), darker(color, 0.08)), rounded_mask((w, h), r)), (edge, edge))
    t = label(text, "display", px, text_color, outline=max(2, int(px * 0.05)), outline_color=edge_c)
    paste(plate, t, (plate.width / 2, plate.height / 2 + px * 0.04))
    return plate.rotate(tilt, resample=Image.Resampling.BICUBIC, expand=True)


# ---------------------------------------------------------------- the map


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(path))
    spec.loader.exec_module(mod)
    sys.path.pop(0)
    return mod


_states = None


def states():
    """{id: [[outer, hole...], ...]} in the map generator's frame (Albers, 975x610
    units, Alaska and Hawaii moved under the West as in the game), and the order."""
    global _states
    if _states is None:
        mapgen = _load_module("mapgen_make", os.path.join(ROOT, "scripts", "mapgen", "make.py"))
        shapes, order, _borders = mapgen.load_states()
        _states = (shapes, order)
    return _states


def land_bbox(ids=None):
    shapes, order = states()
    pts = [p for sid in (ids or order) for poly in shapes[sid] for p in poly[0]]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def centroid(sid):
    shapes, _ = states()
    ring = max((poly[0] for poly in shapes[sid]), key=lambda r: abs(_area(r)))
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return sum(xs) / len(xs), sum(ys) / len(ys)


def _area(ring):
    return sum(ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1] for i in range(len(ring) - 1)) / 2


def draw_map(width: int, fills: dict, border_px: float, border=BACKGROUND, outlines=None, skip=(), light=0.16):
    """The US map `width` px wide: every state filled from `fills` (id -> RGB),
    borders in `border`, a top light like the game's Depth gradient, optional
    `outlines` (id -> (RGB, px)) drawn on top. Returns (image, project) where
    project(x, y) maps frame units to image px."""
    shapes, order = states()
    ids = [s for s in order if s not in skip]
    x0, y0, x1, y1 = land_bbox(ids)
    pad = border_px * 2 + 4
    k = (width - 2 * pad) / (x1 - x0)
    height = int((y1 - y0) * k + 2 * pad)

    def project(x, y):
        return (x - x0) * k + pad, (y - y0) * k + pad

    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    land = Image.new("L", (width, height), 0)
    dl = ImageDraw.Draw(land)
    for sid in ids:
        for poly in shapes[sid]:
            pts = [project(x, y) for x, y in poly[0]]
            d.polygon(pts, fill=tuple(fills.get(sid, NEUTRAL)) + (255,))
            dl.polygon(pts, fill=255)
    if light:
        sheen = vgrad((width, height), (255, 255, 255), (255, 255, 255))
        a = Image.linear_gradient("L").resize((width, height)).point(lambda v: int((1 - v / 255) * 255 * light))
        sheen.putalpha(ImageChops.multiply(a, land))
        img.alpha_composite(sheen)
    for sid in ids:
        for poly in shapes[sid]:
            pts = [project(x, y) for x, y in poly[0]]
            d.line(pts + [pts[0]], fill=tuple(border) + (255,), width=max(1, int(round(border_px))), joint="curve")
    for sid, (color, px) in (outlines or {}).items():
        for poly in shapes[sid]:
            pts = [project(x, y) for x, y in poly[0]]
            d.line(pts + [pts[0]], fill=tuple(color) + (255,), width=int(px), joint="curve")
    return img, project


def map_glow(m: Image.Image, color, blur, alpha, grow=0):
    return shadow_of(m, blur, alpha, color, grow)


def result_fills(seed: int, blue_share: float, keep=None):
    """A made-up night: each state goes blue or red with a lean / likely / safe
    shade (stepped like Colors.bandFill); `keep` fixes some (still counting)."""
    rng = random.Random(seed)
    _, order = states()
    fills = {}
    for sid in order:
        if keep and sid in keep:
            fills[sid] = keep[sid]
            continue
        color = BLUE if rng.random() < blue_share else RED
        fills[sid] = band(color, rng.choice((0.6, 0.82, 1.0, 1.0)))
    return fills


def split_fills(tilt=0.35, shares=(1.0, 0.82)):
    """Blue west, red east, along a slanted line through the middle (the race,
    not a real result)."""
    _, order = states()
    x0, y0, x1, y1 = land_bbox([s for s in order if s not in ("AK", "HI")])
    mid = (x0 + x1) / 2
    fills = {}
    for sid in order:
        cx, cy = centroid(sid)
        if sid in ("AK", "HI"):
            side = sid == "AK"
        else:
            side = cx + (cy - (y0 + y1) / 2) * tilt < mid
        dist = abs(cx + (cy - (y0 + y1) / 2) * tilt - mid) / (x1 - x0)
        share = shares[0] if dist > 0.12 else shares[1]
        fills[sid] = band(BLUE if side else RED, share)
    return fills


# ---------------------------------------------------------------- people

_busts: dict = {}


def bust(cid: str) -> Image.Image:
    """The candidate's portrait (assets/portraits/make.py) at full drawing
    resolution (1744 px square, transparent, shoulders run off the bottom)."""
    if cid not in _busts:
        mod = _load_module("portraits_make", os.path.join(ROOT, "assets", "portraits", "make.py"))

        def full(self):
            x0, y0, side = mod.CROP
            return self.img.crop((int(mod.s(x0)), int(mod.s(y0)), int(mod.s(x0 + side)), int(mod.s(y0 + side))))

        mod.Canvas.result = full
        _busts[cid] = mod.PORTRAITS[cid]()
    return _busts[cid]


def rim_bust(cid: str, size: int, color, rim: float) -> Image.Image:
    """A bust `size` px wide with a `rim` px outline in `color` (a sticker edge,
    so dark hair reads on the navy stage) and a white inner hairline."""
    b = bust(cid).resize((size, size), Image.Resampling.LANCZOS)
    pad = int(rim * 2)
    out = Image.new("RGBA", (size + 2 * pad, size + 2 * pad), (0, 0, 0, 0))
    a = Image.new("L", out.size, 0)
    a.paste(b.getchannel("A"), (pad, pad))
    grow = a.filter(ImageFilter.MaxFilter(int(rim) * 2 + 1)).filter(ImageFilter.GaussianBlur(rim * 0.15))
    out.alpha_composite(colored(grow, color))
    out.alpha_composite(b, (pad, pad))
    # Cut the bottom flat (the shoulders end at the image's bottom edge).
    cut = Image.new("L", out.size, 255)
    ImageDraw.Draw(cut).rectangle((0, pad + size - 2, out.width, out.height), fill=0)
    out.putalpha(ImageChops.multiply(out.getchannel("A"), cut))
    return out


def plate(cid: str, d: int, color, ring_k=0.06) -> Image.Image:
    """Kit.portrait at size `d`: the bust on a round plate tinted toward the
    player's color, a ring in that color and a thin navy edge."""
    ring = int(d * ring_k)
    edge = max(2, int(d * 0.018))
    full = d + 2 * edge
    img = Image.new("RGBA", (full, full), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((0, 0, full - 1, full - 1), fill=BACKGROUND + (255,))
    ImageDraw.Draw(img).ellipse((edge, edge, edge + d - 1, edge + d - 1), fill=color + (255,))
    inner = d - 2 * ring
    disc = Image.new("L", (inner, inner), 0)
    ImageDraw.Draw(disc).ellipse((0, 0, inner - 1, inner - 1), fill=255)
    bg = vgrad((inner, inner), tint(PLATE_TOP, color, 0.25), tint(PLATE_BOTTOM, color, 0.3))
    face = bust(cid).resize((inner, inner), Image.Resampling.LANCZOS)
    bg.alpha_composite(face)
    img.alpha_composite(with_alpha(bg, disc), (edge + ring, edge + ring))
    # A soft top light on the ring.
    hl = Image.new("L", (full, full), 0)
    ImageDraw.Draw(hl).arc((edge, edge, edge + d - 1, edge + d - 1), 200, 340, fill=110, width=max(2, ring // 2))
    img.alpha_composite(colored(hl.filter(ImageFilter.GaussianBlur(ring * 0.3)), (255, 255, 255)))
    return img


# ---------------------------------------------------------------- pieces


def race_bar(w: int, h: int, left: float, right: float, total=538, tick=270):
    """Kit.raceBar: a rounded track, blue from the left and red from the right
    (they never meet), the white 270 tick overhanging it."""
    over = int(h * 0.45)
    img = Image.new("RGBA", (w, h + 2 * over), (0, 0, 0, 0))
    track = with_alpha(vgrad((w, h), RAISED_TOP, RAISED), rounded_mask((w, h), h // 2))
    img.alpha_composite(track, (0, over))
    lw = int(w * left / total)
    rw = int(w * right / total)
    if lw > h:
        img.alpha_composite(with_alpha(vgrad((lw, h), lighter(BLUE, 0.15), darker(BLUE, 0.12)), rounded_mask((lw, h), h // 2)), (0, over))
    if rw > h:
        img.alpha_composite(with_alpha(vgrad((rw, h), lighter(RED, 0.15), darker(RED, 0.12)), rounded_mask((rw, h), h // 2)), (w - rw, over))
    tx = int(w * tick / total)
    tw = max(4, int(h * 0.28))
    ImageDraw.Draw(img).rounded_rectangle((tx - tw // 2, 0, tx + tw // 2, h + 2 * over), radius=tw // 2, fill=TEXT + (255,))
    return img


def confetti(size, n, seed, area=None, colors=(BLUE, RED, TEXT), scale=1.0, avoid=()):
    """Paper confetti in the players' colors and white; none lands in `avoid`
    (boxes x0, y0, x1, y1), so it never sits on the type."""
    rng = random.Random(seed)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    x0, y0, x1, y1 = area or (0, 0, size[0], size[1])
    for _ in range(n):
        w = int(rng.uniform(10, 22) * scale)
        h = int(rng.uniform(22, 40) * scale)
        piece = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        c = rng.choice(colors)
        ImageDraw.Draw(piece).rounded_rectangle((0, 0, w - 1, h - 1), radius=max(1, w // 4), fill=c + (255,))
        piece = piece.rotate(rng.uniform(0, 360), resample=Image.Resampling.BICUBIC, expand=True)
        if rng.random() < 0.4:
            piece = scale_alpha(piece, 0.7)
        x, y = int(rng.uniform(x0, x1)), int(rng.uniform(y0, y1))
        if any(a <= x + piece.width / 2 <= c and b <= y + piece.height / 2 <= d for a, b, c, d in avoid):
            continue
        layer.alpha_composite(piece, (x, y))
    return layer


def stage(size, glow_center, glow_r, glow_alpha=0.75, vignette=0.4):
    """The navy stage: background, the map's backdrop glow, a dark vignette."""
    w, h = size
    img = vgrad(size, tint(BACKGROUND, GLOW, 0.12), BACKGROUND)
    img.alpha_composite(radial(size, glow_center, glow_r, GLOW, glow_alpha))
    if vignette:
        v = Image.radial_gradient("L").resize((w, h))
        a = v.point(lambda x: int(max(0, (x / 255 - 0.55) / 0.45) ** 1.5 * 255 * vignette))
        img.alpha_composite(colored(a, (0, 0, 0)))
    return img


# ---------------------------------------------------------------- snapshots


def snapshot(name: str, k=2) -> Image.Image:
    """The game's own UI snapshot `name` (tests/ui/snap.luau, desktop 1280x720),
    rendered at k x with qlmanage. Snapshot-only marks are removed first: the two
    dim circles standing in for the Roblox top bar, and the purple "+N px below"
    scroll markers (Studio shows neither)."""
    svg = os.path.join(ROOT, "build", "snaps", "desktop", f"{name}.svg")
    # Draw it fresh from the current UI code (lune needs to be on PATH; see
    # CLAUDE.md). Without lune, an earlier build/snaps copy is used.
    if shutil.which("lune"):
        subprocess.run(
            ["lune", "run", "tests/ui/snap.luau", "--", name, "--size", "desktop", "--no-png"],
            cwd=ROOT,
            check=True,
            capture_output=True,
        )
    assert os.path.exists(svg), f"no snapshot {svg}: install lune (rokit install) and run again"
    src = open(svg, encoding="utf-8").read()
    src = re.sub(r'<rect x="(12|64)" y="[^"]*" width="44" height="44" rx="22" fill="#000000" fill-opacity="0.45"/>\n?', "", src)
    src = re.sub(r'<rect [^>]*fill="#6b5cff"[^>]*/>\n?', "", src)
    src = re.sub(r"<text [^>]*>\+\d+ px below ▼</text>\n?", "", src)
    m = re.match(r'<svg[^>]*width="(\d+)" height="(\d+)"[^>]*>', src)
    w, h = int(m.group(1)), int(m.group(2))
    side = max(w, h)
    head = (
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'width="{side * k}" height="{side * k}" viewBox="0 {-(side - h) / 2} {side} {side}">'
    )
    src = src.replace(m.group(0), head, 1)
    os.makedirs(WORK, exist_ok=True)
    tmp = os.path.join(WORK, f"{name}-sq.svg")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(src)
    subprocess.run(["qlmanage", "-t", "-s", str(side * k), "-o", WORK, tmp], check=True, capture_output=True)
    sq = Image.open(tmp + ".png").convert("RGBA")
    top = (sq.height - h * k) // 2
    return sq.crop((0, top, w * k, top + h * k))


def screen_card(shot: Image.Image, width: int, radius: int) -> Image.Image:
    """A screenshot as a floating card: rounded corners, a hairline edge lit from
    the top (Kit.bevel), no device frame."""
    h = int(shot.height * width / shot.width)
    img = shot.resize((width, h), Image.Resampling.LANCZOS)
    edge = max(2, radius // 8)
    card = Image.new("RGBA", (width + 2 * edge, h + 2 * edge), (0, 0, 0, 0))
    rim = vgrad(card.size, lighter(LINE, 0.55), LINE)
    card.alpha_composite(with_alpha(rim, rounded_mask(card.size, radius + edge)))
    card.alpha_composite(with_alpha(img, rounded_mask((width, h), radius)), (edge, edge))
    return card


# ---------------------------------------------------------------- icons

ICON = 512
S = 4  # icon supersampling


def icon_backdrop(n):
    img = stage((n, n), (n * 0.5, n * 0.42), n * 0.62, 0.9, vignette=0.55)
    return img


def icon_map() -> Image.Image:
    """The US split blue | red under a big "270", "LANDSLIDE" on the ribbon."""
    n = ICON * S
    img = icon_backdrop(n)
    m, _ = draw_map(int(n * 0.94), split_fills(), border_px=n * 0.006, skip=("AK", "HI"), light=0.2)
    paste(img, map_glow(m, (120, 150, 255), n * 0.03, 0.55, grow=n * 0.004), (n * 0.5, n * 0.36))
    paste(img, shadow_of(m, n * 0.012, 0.6), (n * 0.5, n * 0.375))
    paste(img, m, (n * 0.5, n * 0.36))
    big = numeral("270", n * 0.40)
    paste(img, big, (n * 0.5, n * 0.6))
    rib = ribbon("LANDSLIDE", n * 0.085, tilt=3)
    paste(img, shadow_of(rib, n * 0.01, 0.6), (n * 0.5, n * 0.86 + n * 0.012))
    paste(img, rib, (n * 0.5, n * 0.86))
    return finish(img, (ICON, ICON))


def numeral(text: str, px: float) -> Image.Image:
    """Big Fredoka white numerals with the wordmark's outline, drop and light."""
    f = font("display", px)
    stroke = max(3, int(px * 0.06))
    drop = int(px * 0.07)
    outer = text_mask(text, f, stroke)
    inner = text_mask(text, f, 0)
    W, H = outer.width + 8, outer.height + drop + 8
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    img.alpha_composite(colored(_at(outer, (W, H), 4, 4 + drop), BACKGROUND, 0.9))
    img.alpha_composite(colored(_at(outer, (W, H), 4, 4 + drop * 0.55), LINE))
    img.alpha_composite(colored(_at(outer, (W, H), 4, 4), ACCENT_LIP))
    face = vgrad((W, H), (255, 255, 255), WORDMARK_BOTTOM)
    img.alpha_composite(with_alpha(face, _at(inner, (W, H), 4 + stroke, 4 + stroke)))
    return trim(img)


def icon_faceoff() -> Image.Image:
    """Two candidates face off on plates, blue and red, with "270" between."""
    n = ICON * S
    img = icon_backdrop(n)
    img.alpha_composite(radial((n, n), (n * 0.2, n * 0.4), n * 0.5, BLUE, 0.55))
    img.alpha_composite(radial((n, n), (n * 0.8, n * 0.4), n * 0.5, RED, 0.55))
    d = int(n * 0.52)
    left = plate("okafor", d, BLUE)
    right = plate("calloway", d, RED)
    paste(img, shadow_of(left, n * 0.015, 0.6), (n * 0.29, n * 0.40 + n * 0.015))
    paste(img, left, (n * 0.29, n * 0.40))
    paste(img, shadow_of(right, n * 0.015, 0.6), (n * 0.71, n * 0.40 + n * 0.015))
    paste(img, right, (n * 0.71, n * 0.40))
    big = numeral("270", n * 0.30)
    paste(img, big, (n * 0.5, n * 0.75))
    rib = ribbon("LANDSLIDE", n * 0.075, tilt=3)
    paste(img, shadow_of(rib, n * 0.01, 0.6), (n * 0.5, n * 0.915 + n * 0.01))
    paste(img, rib, (n * 0.5, n * 0.915))
    return finish(img, (ICON, ICON))


def icon_stamp() -> Image.Image:
    """The game's lockup over the split map: "LANDSLIDE" with "RACE TO 270"."""
    n = ICON * S
    img = icon_backdrop(n)
    m, _ = draw_map(int(n * 1.02), split_fills(), border_px=n * 0.006, skip=("AK", "HI"), light=0.2)
    paste(img, map_glow(m, (120, 150, 255), n * 0.03, 0.5, grow=n * 0.004), (n * 0.5, n * 0.42))
    paste(img, m, (n * 0.5, n * 0.42))
    shade = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    shade.alpha_composite(radial((n, n), (n * 0.5, n * 0.5), n * 0.62, BACKGROUND, 0.55))
    img.alpha_composite(shade)
    wm = wordmark(n * 0.19, ribbon_scale=0.42, glow=False)
    wm = wm.resize((int(n * 0.94), int(wm.height * n * 0.94 / wm.width)), Image.Resampling.LANCZOS)
    paste(img, shadow_of(wm, n * 0.02, 0.7), (n * 0.5, n * 0.52 + n * 0.012))
    paste(img, wm, (n * 0.5, n * 0.52))
    return finish(img, (ICON, ICON))


# ---------------------------------------------------------------- thumbnails

TW, TH = 1920, 1080
T = 2  # thumbnail supersampling
SAFE_X = 96  # px: text and faces stay inside this side margin
SAFE_BOTTOM = 150  # px: nothing that matters in the bottom strip (player count)


def caption(text: str, px: float) -> Image.Image:
    return label(text, "display", px * T, TEXT, outline=int(px * T * 0.06), outline_color=BACKGROUND, shadow=int(px * T * 0.05))


def thumb_hero() -> Image.Image:
    """Two candidates face off over an election-night map; the lockup on top."""
    w, h = TW * T, TH * T
    img = stage((w, h), (w * 0.5, h * 0.6), w * 0.5, 0.95)
    img.alpha_composite(radial((w, h), (w * 0.1, h * 0.8), w * 0.34, BLUE, 0.7))
    img.alpha_composite(radial((w, h), (w * 0.9, h * 0.8), w * 0.34, RED, 0.7))
    # Election night: most states called, a few still counting, one deciding.
    decider = "MO"
    counting = {s: NEUTRAL for s in ("MO", "WI", "NV", "NC", "NH")}
    fills = result_fills(270, 0.5, keep=counting)
    m, project = draw_map(int(w * 0.62), fills, border_px=3 * T, outlines={decider: (TEXT, 6 * T)}, light=0.18)
    cx, cy = w * 0.5, h * 0.6
    paste(img, map_glow(m, (110, 140, 255), 40 * T, 0.45, grow=4 * T), (cx, cy))
    paste(img, shadow_of(m, 10 * T, 0.6), (cx, cy + 10 * T))
    paste(img, m, (cx, cy))
    px, py = project(*centroid(decider))
    mx, my = cx - m.width / 2, cy - m.height / 2
    img.alpha_composite(radial((w, h), (mx + px, my + py), 150 * T, (255, 255, 255), 0.3))
    # The candidates rise from the bottom corners, facing the map.
    size = int(h * 0.64)
    left = rim_bust("okafor", size, BLUE, 7 * T)
    right = rim_bust("calloway", size, RED, 7 * T)
    paste(img, shadow_of(left, 24 * T, 0.6), (w * 0.135, h + 20 * T), (0.5, 1))
    paste(img, left, (w * 0.13, h + 2), (0.5, 1))
    paste(img, shadow_of(right, 24 * T, 0.6), (w * 0.865, h + 20 * T), (0.5, 1))
    paste(img, right, (w * 0.87, h + 2), (0.5, 1))
    wm = wordmark(150 * T, ribbon_scale=0.36)
    paste(img, wm, (w * 0.5, 34 * T), (0.5, 0))
    return finish(img, (TW, TH))


def framed_shot(shot_name: str, text: str, sub_glow=BLUE, crop=None) -> Image.Image:
    """A real screen from the game on the stage, a short caption above it and
    the lockup in the corner."""
    w, h = TW * T, TH * T
    img = stage((w, h), (w * 0.5, h * 0.62), w * 0.55, 0.9, vignette=0.35)
    img.alpha_composite(radial((w, h), (w * 0.05, h * 0.0), w * 0.35, sub_glow, 0.35))
    shot = snapshot(shot_name)
    if crop:
        shot = shot.crop(crop)
    card = screen_card(shot, int(w * 0.8), 22 * T)
    top = 236 * T
    paste(img, map_glow(card, (110, 140, 255), 50 * T, 0.35), (w * 0.5, top), (0.5, 0))
    paste(img, shadow_of(card, 22 * T, 0.7), (w * 0.5, top + 16 * T), (0.5, 0))
    paste(img, card, (w * 0.5, top), (0.5, 0))
    cap = caption(text, 92)
    paste(img, cap, (SAFE_X * T - 12 * T, 58 * T), (0, 0))
    wm = wordmark(64 * T, ribbon_scale=0.4)
    paste(img, wm, (w - (SAFE_X - 10) * T, 34 * T), (1, 0))
    return finish(img, (TW, TH))


def thumb_campaign() -> Image.Image:
    # Drop the empty top inset (the Roblox top bar's strip, 58 px at 1x).
    return framed_shot("10a-campaign-planned", "Race to 270 in 12 weeks", crop=(0, 116, 2560, 1440))


def thumb_debate() -> Image.Image:
    return framed_shot("08a-debate-round", "Win the live debates", sub_glow=RED, crop=(0, 116, 2560, 1440))


def thumb_landslide() -> Image.Image:
    """The win: the map gone blue, the winner, "Win by a LANDSLIDE"."""
    w, h = TW * T, TH * T
    img = stage((w, h), (w * 0.62, h * 0.55), w * 0.5, 0.9)
    img.alpha_composite(radial((w, h), (w * 0.18, h * 0.75), w * 0.4, BLUE, 0.75))
    fills = result_fills(386, 0.84)
    m, _ = draw_map(int(w * 0.6), fills, border_px=3 * T, light=0.18)
    cx = w * 0.64
    paste(img, map_glow(m, (90, 130, 255), 40 * T, 0.45, grow=4 * T), (cx, h * 0.66))
    paste(img, scale_alpha(m, 0.8), (cx, h * 0.66))
    # Darken the map under the type so the stamp and the bar stand out.
    img.alpha_composite(radial((w, h), (cx, h * 0.4), w * 0.4, BACKGROUND, 0.8))
    img.alpha_composite(confetti(
            (w, h),
            110,
            7,
            area=(w * 0.0, -h * 0.05, w * 0.98, h * 0.62),
            scale=T,
            avoid=[(cx - w * 0.29, 30 * T, cx + w * 0.29, 700 * T)],
        ))
    size = int(h * 0.74)
    winner = rim_bust("okafor", size, BLUE, 7 * T)
    paste(img, shadow_of(winner, 24 * T, 0.6), (w * 0.185, h + 20 * T), (0.5, 1))
    paste(img, winner, (w * 0.18, h + 2), (0.5, 1))
    eyebrow = caption("Win by a", 80)
    paste(img, eyebrow, (cx, 64 * T), (0.5, 0))
    st = stamp("LANDSLIDE", BLUE, 150 * T)
    sy = 330 * T
    paste(img, radial((st.width * 2, st.height * 3), (st.width, st.height * 1.5), st.width * 0.7, (120, 160, 255), 0.45), (cx, sy))
    paste(img, shadow_of(st, 18 * T, 0.7), (cx, sy + 14 * T))
    paste(img, st, (cx, sy))
    bw = int(w * 0.44)
    bar = race_bar(bw, 26 * T, 386, 152)
    by = 560 * T
    paste(img, shadow_of(bar, 10 * T, 0.6), (cx, by + 6 * T))
    paste(img, bar, (cx, by))
    nl = label("386", "display", 80 * T, lighter(BLUE, 0.4), outline=5 * T, shadow=4 * T)
    nr = label("152", "display", 80 * T, lighter(RED, 0.35), outline=5 * T, shadow=4 * T)
    paste(img, nl, (cx - bw / 2, by + 84 * T), (0, 0.5))
    paste(img, nr, (cx + bw / 2, by + 84 * T), (1, 0.5))
    tick = label("270 TO WIN", "display", 34 * T, TEXT, outline=4 * T)
    paste(img, tick, (cx - bw / 2 + int(bw * 270 / 538), by + 84 * T), (0.5, 0.5))
    return finish(img, (TW, TH))


# ---------------------------------------------------------------- sheet


def contact_sheet(icons: dict, thumbs: dict, path: str):
    pad = 32
    card_w = 384  # about a Home-page card
    cols_w = 512 + 150 + 50 + 4 * pad
    sheet_w = max(cols_w + 960, 960 + card_w + 3 * pad + 200)
    y = pad
    sheet = Image.new("RGBA", (sheet_w, pad + len(icons) * (34 + 512 + pad) + len(thumbs) * (34 + 540 + pad)), BACKGROUND + (255,))
    d = ImageDraw.Draw(sheet)
    small = font("bold", 22)
    for name, ic in icons.items():
        d.text((pad, y), name, font=small, fill=MUTED)
        y += 34
        x = pad
        for px in (512, 150, 50):
            im = ic.resize((px, px), Image.Resampling.LANCZOS)
            mask = rounded_mask((px, px), max(4, px // 8))
            sheet.paste(im, (x, y + 512 - px), mask)
            x += px + pad
        y += 512 + pad
    for name, th in thumbs.items():
        d.text((pad, y), name, font=small, fill=MUTED)
        y += 34
        big = th.resize((960, 540), Image.Resampling.LANCZOS)
        sheet.paste(big, (pad, y))
        card = th.resize((card_w, card_w * 9 // 16), Image.Resampling.LANCZOS)
        sheet.paste(card, (pad * 2 + 960, y))
        tiny = th.resize((192, 108), Image.Resampling.LANCZOS)
        sheet.paste(tiny, (pad * 2 + 960, y + card_w * 9 // 16 + pad))
        y += 540 + pad
    sheet = sheet.crop((0, 0, sheet_w, y))
    sheet.convert("RGB").save(path)


# ---------------------------------------------------------------- main


def save(img: Image.Image, name: str):
    path = os.path.join(HERE, name)
    img.convert("RGB").save(path, optimize=True)
    kb = os.path.getsize(path) / 1024
    print(f"  assets/promo/{name}  {img.width}x{img.height}  {kb:.0f} KB")
    assert kb < 3 * 1024, f"{name} is over 3 MB"


RECOMMENDED = "icon-map.png"  # reads at 50 px: the map, two colors, "270"


def main():
    print(f"display font: {font_used('display')}")
    print(f"text font:    {font_used('bold')}")
    icons = {
        "icon-map.png": icon_map(),
        "icon-faceoff.png": icon_faceoff(),
        "icon-stamp.png": icon_stamp(),
    }
    for name, img in icons.items():
        save(img, name)
    shutil.copyfile(os.path.join(HERE, RECOMMENDED), os.path.join(HERE, "icon.png"))
    print(f"  assets/promo/icon.png  = {RECOMMENDED}")
    thumbs = {
        "thumb-1-hero.png": thumb_hero(),
        "thumb-2-campaign.png": thumb_campaign(),
        "thumb-3-debate.png": thumb_debate(),
        "thumb-4-landslide.png": thumb_landslide(),
    }
    for name, img in thumbs.items():
        save(img, name)
    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        contact_sheet(icons, thumbs, path)
        print(f"  sheet: {path}")


if __name__ == "__main__":
    main()
