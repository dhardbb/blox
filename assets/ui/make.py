"""Generates the UI's decoration images (docs/DESIGN.md D-056).

Run from the repository root:  python3 assets/ui/make.py
Needs Pillow (PIL; a user install is fine, so no -I). Writes, next to this script:

  ui-shadow.png  96x96, a soft black rounded rect for a 9-slice drop shadow
                 (SliceCenter = Rect(40, 40, 56, 56), SliceScale 1)
  ui-glow.png    256x256, a white radial glow, alpha (1 - d)^2.2, tinted in game
  ui-dots.png    64x64, one 2 px white dot, tiled behind the map (optional)

The ids go in src/client/UI/Assets.luau after the upload (assets/ui/README.md).
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))


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


def main() -> None:
    for name, make in (("ui-shadow.png", shadow), ("ui-glow.png", glow), ("ui-dots.png", dots)):
        path = os.path.join(HERE, name)
        make().save(path)
        print(f"wrote {os.path.relpath(path)}")


if __name__ == "__main__":
    main()
