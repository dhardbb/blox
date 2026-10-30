"""A review sheet of the whiteboard art (docs/proposals/whiteboard.md).

Run from the repository root after the generators:
  python3 assets/sheet.py [PATH]      (default build/art-sheet.png, gitignored)
Needs Pillow. Reads the PNGs already written by assets/ui/make.py,
assets/icons/make.py, assets/portraits/make.py and assets/promo/make.py and
lays them out on the board color: the UI props tinted as the game tints them
(and each at its real size), every icon at 96, 48, 24 and 20 px in ink, the
eight portraits as UI/Board.photo shows them, then the promo icons and
thumbnails. People only; nothing here ships.
"""

from __future__ import annotations

import importlib.util
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BOARD = (243, 241, 234)
INK = (29, 29, 31)
STICKY = (255, 242, 168)
RED = (200, 20, 70)
BLUE = (31, 91, 208)
WIDTH = 1800
PAD = 32


def load(*parts) -> Image.Image:
    return Image.open(os.path.join(ROOT, *parts)).convert("RGBA")


def colored(img: Image.Image, color) -> Image.Image:
    rgb = ImageChops.multiply(img.convert("RGB"), Image.new("RGB", img.size, color))
    out = rgb.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out


def module(name, *parts):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, *parts))
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(os.path.join(ROOT, *parts)))
    spec.loader.exec_module(mod)
    sys.path.pop(0)
    return mod


class Sheet:
    def __init__(self):
        self.parts: list[tuple[str, Image.Image]] = []

    def add(self, title: str, img: Image.Image):
        self.parts.append((title, img))

    def save(self, path: str):
        f = ImageFont.truetype(os.path.join(ROOT, "tests", "lib", "fonts", "PatrickHand-Regular.ttf"), 30)
        h = PAD + sum(44 + img.height + PAD for _, img in self.parts)
        out = Image.new("RGBA", (WIDTH, h), BOARD + (255,))
        d = ImageDraw.Draw(out)
        y = PAD
        for title, img in self.parts:
            d.text((PAD, y), title, font=f, fill=INK)
            y += 44
            out.alpha_composite(img, (PAD, y))
            y += img.height + PAD
        os.makedirs(os.path.dirname(path), exist_ok=True)
        out.convert("RGB").save(path)


def row(images, gap=PAD, height=None) -> Image.Image:
    height = height or max(i.height for i in images)
    w = sum(i.width for i in images) + gap * (len(images) - 1)
    out = Image.new("RGBA", (w, height), (0, 0, 0, 0))
    x = 0
    for i in images:
        out.alpha_composite(i, (x, height - i.height))
        x += i.width + gap
    return out


def ui_props() -> Image.Image:
    tile = load("assets", "ui", "board.png")
    board = Image.new("RGBA", (512, 512))
    board.alpha_composite(tile)
    note = colored(load("assets", "ui", "sticky.png"), STICKY)
    box = colored(load("assets", "ui", "marker-box.png"), INK)
    box_half = box.resize((64, 64), Image.Resampling.LANCZOS)  # SliceScale 0.5
    mag = [colored(load("assets", "ui", "magnet.png"), c) for c in (RED, BLUE)]
    circ = colored(load("assets", "ui", "scribble-circle.png"), RED)
    tape = load("assets", "ui", "tape.png")
    return row([board, note, box, box_half, mag[0], mag[1].resize((28, 28), Image.Resampling.LANCZOS), circ, tape])


def icons() -> Image.Image:
    names = sorted(f[:-4] for f in os.listdir(os.path.join(ROOT, "assets", "icons")) if f.endswith(".png"))
    cells = []
    for name in names:
        img = load("assets", "icons", f"{name}.png")
        cells.append(row([colored(img.resize((s, s), Image.Resampling.LANCZOS), INK) for s in (96, 48, 24, 20)], gap=10))
    per = 4
    rows = [row(cells[i : i + per], gap=48) for i in range(0, len(cells), per)]
    h = sum(r.height for r in rows) + 24 * (len(rows) - 1)
    out = Image.new("RGBA", (max(r.width for r in rows), h), (0, 0, 0, 0))
    y = 0
    for r in rows:
        out.alpha_composite(r, (0, y))
        y += r.height + 24
    return out


def fit(img: Image.Image, w: int) -> Image.Image:
    if img.width <= w:
        return img
    return img.resize((w, round(img.height * w / img.width)), Image.Resampling.LANCZOS)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "art-sheet.png")
    sheet = Sheet()
    sheet.add("assets/ui: board (tile), sticky (yellow), marker-box (2x and at SliceScale 0.5), magnet (128 and 28 px), scribble-circle, tape", fit(ui_props(), WIDTH - 2 * PAD))
    sheet.add("assets/icons: marker doodles at 96, 48, 24 and 20 px", fit(icons(), WIDTH - 2 * PAD))
    portraits = module("portraits_make", "assets", "portraits", "make.py")
    faces = {cid: load("assets", "portraits", f"{cid}.png") for cid in portraits.PORTRAITS}
    sheet.add("assets/portraits via Board.photo at 48, 72, 96 px (top) vs a baked 512 polaroid (below, not used)", fit(portraits.photo_sheet(faces), WIDTH - 2 * PAD))
    promo_icons = [load("assets", "promo", n) for n in ("icon-map.png", "icon-faceoff.png", "icon-stamp.png")]
    small = [i.resize((150, 150), Image.Resampling.LANCZOS) for i in promo_icons] + [i.resize((50, 50), Image.Resampling.LANCZOS) for i in promo_icons]
    sheet.add("assets/promo: icon-map (= icon.png), icon-faceoff, icon-stamp at 512, 150 and 50 px", fit(row([*promo_icons, *small], gap=20), WIDTH - 2 * PAD))
    thumbs = [load("assets", "promo", n).resize((840, 473), Image.Resampling.LANCZOS) for n in ("thumb-1-hero.png", "thumb-2-campaign.png", "thumb-3-debate.png", "thumb-4-landslide.png")]
    sheet.add("assets/promo: thumbnails 1 and 2", row(thumbs[:2]))
    sheet.add("assets/promo: thumbnails 3 and 4", row(thumbs[2:]))
    sheet.save(path)
    print(f"wrote {os.path.relpath(path)}")


if __name__ == "__main__":
    main()
