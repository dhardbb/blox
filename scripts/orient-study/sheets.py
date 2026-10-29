#!/usr/bin/env python3
"""Orientation study (branch orient-study): contact sheets and the measurements table.

Run from the repo root after the snapshots:
  lune run tests/ui/snap.luau -- --size phone-land --measure
  lune run tests/ui/snap.luau -- --size phone-port --measure
  for s in stroke tint badge halo; do for z in phone-land phone-port ipad; do
    lune run tests/ui/snap.luau -- 09 --size $z --key-style $s; done; done
  python3 scripts/orient-study/sheets.py <out_dir>

Writes into <out_dir>: NN-screen-land.png, NN-screen-port.png, NN-screen-pair.png
(both at the same scale, 1 px = 1 pt, labelled), measurements.md, and the
key-state outline sheets outline-<option>-<size>.png and outline-compare.png.
Needs Pillow.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SNAPS = "build/snaps"

# (number, screen, shot name)
SCREENS = [
    ("01", "lobby", "01-lobby"),
    ("02", "select", "03-select-candidate"),
    ("03", "issues", "04-select-issues"),
    ("04", "draft", "06-draft"),
    ("05", "stance", "07-decision-stance"),
    ("06", "campaign-plan", "09-campaign-plan"),
    ("07", "state-card", "10-campaign-state-card"),
    ("08", "money-map", "14-lens-money"),
    ("09", "key-states", "09k-campaign-key-tip"),
    ("10", "week-reveal", "16c-resolve-mid"),
    ("11", "debate-round", "08a-debate-round"),
    ("12", "debate-verdict", "20-debate-verdict"),
    ("13", "election-night", "22-election-late"),
    ("14", "results", "23-results"),
]

OPTIONS = [
    ("dashed", "today (D-088): soft glow + dashed white outline"),
    ("stroke", "A: solid gold stroke inside the state's border"),
    ("tint", "B: gold wash over the state, no outline"),
    ("badge", "C: gold target badge on the label + chips"),
    ("halo", "D: bright gold halo glow, no dashes"),
]
OUTLINE_SHOTS = ["09-campaign-plan", "09k-campaign-key-tip", "09l-campaign-key-tapped"]
OUTLINE_SIZES = ["phone-land", "phone-port", "ipad"]

BG = (24, 24, 28)
FG = (240, 240, 240)
MUTED = (160, 160, 170)


def font(size):
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def labelled(images, labels, title, pad=16, gap=24):
    """Side by side, top-aligned, same scale, with a label over each and a title."""
    head, sub = 40, 66
    w = pad * 2 + sum(i.width for i in images) + gap * (len(images) - 1)
    h = pad * 2 + head + sub + max(i.height for i in images)
    sheet = Image.new("RGB", (w, h), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((pad, pad), title, fill=FG, font=font(24))
    x = pad
    for img, label in zip(images, labels):
        draw.multiline_text((x, pad + head), label, fill=MUTED, font=font(15), spacing=3)
        sheet.paste(img, (x, pad + head + sub))
        draw.rectangle(
            [x - 1, pad + head + sub - 1, x + img.width, pad + head + sub + img.height], outline=(90, 90, 100)
        )
        x += img.width + gap
    return sheet


def read_measure(size):
    rows = {}
    path = f"{SNAPS}/{size}/measure.tsv"
    with open(path) as f:
        header = f.readline().rstrip("\n").split("\t")
        for line in f:
            cells = line.rstrip("\n").split("\t")
            cells += [""] * (len(header) - len(cells))
            rows[cells[0]] = dict(zip(header, cells))
    return rows


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    measures = {size: read_measure(size) for size in ("phone-land", "phone-port")}

    for num, screen, shot in SCREENS:
        land = Image.open(f"{SNAPS}/phone-land/{shot}.png").convert("RGB")
        port = Image.open(f"{SNAPS}/phone-port/{shot}.png").convert("RGB")
        land.save(f"{out}/{num}-{screen}-land.png")
        port.save(f"{out}/{num}-{screen}-port.png")
        ml, mp = measures["phone-land"][shot], measures["phone-port"][shot]

        def note(m):
            return f"map {m['mapW']}x{m['mapH']} · min text {m['minText']}\nbelow fold {m['belowFold']} px"

        sheet = labelled(
            [land, port],
            [f"LANDSCAPE 844x390 (shipping) · {note(ml)}", f"PORTRAIT 390x844 (old layout)\n{note(mp)}"],
            f"{num} {screen}  ({shot})",
        )
        sheet.save(f"{out}/{num}-{screen}-pair.png")

    # measurements.md
    lines = [
        "# Orientation study: measurements",
        "",
        "Headless snapshots (`tests/ui/snap.luau --measure`, Snapshot.measure), 1 px = 1 pt.",
        "phone-land: 844x390 with a 58 pt top bar, 47 pt notch insets left and right, 21 pt home bar",
        "(game area 750x311). phone-port: 390x844 with 47 pt notch + 58 pt top bar (105) and a 34 pt",
        "home bar (game area 390x705). Layout and text widths are the renderer's approximation.",
        "",
        "- **Map**: the drawn map (\"NodeMap\", aspect-fitted), w x h px; `-` = no map on screen.",
        "- **Min text**: the smallest visible text's drawn size (TextScaled resolved).",
        "- **Taps <44**: visible buttons off the map under 44 px in either direction; map hit boxes",
        "  are on a 36 px floor by design (Kit.MAP_NODE_MIN) and counted separately.",
        "- **Below fold**: px the tallest scrolling frame holds past its visible bottom (or content",
        "  past the screen's bottom), i.e. what needs a scroll.",
        "",
        "| # | Screen | Map land | Map port | Min text land / port | Taps <44 land / port | Map taps <44 land / port | Below fold land | Below fold port |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    detail = ["", "## Small tap targets and scroll owners", ""]
    for num, screen, shot in SCREENS:
        ml, mp = measures["phone-land"][shot], measures["phone-port"][shot]

        def mapcell(m):
            return "-" if m["mapW"] == "0" else f"{m['mapW']}x{m['mapH']}"

        lines.append(
            f"| {num} | {screen} | {mapcell(ml)} | {mapcell(mp)} | {ml['minText']} / {mp['minText']} | "
            f"{ml['smallTaps']} / {mp['smallTaps']} | {ml['smallMapTaps']} / {mp['smallMapTaps']} | "
            f"{ml['belowFold']} ({ml['belowName'] or '-'}) | {mp['belowFold']} ({mp['belowName'] or '-'}) |"
        )
        for size, m in (("land", ml), ("port", mp)):
            if m["taps"]:
                detail.append(f"- {num} {screen} {size}: {m['taps']}")
    with open(f"{out}/measurements.md", "w") as f:
        f.write("\n".join(lines + detail) + "\n")

    # outline sheets
    have = os.path.isdir(f"{SNAPS}/phone-land-key-stroke")
    if not have:
        print("no --key-style snapshots; skipping the outline sheets")
        return
    rows = []
    for name, desc in OPTIONS:
        for size in OUTLINE_SIZES:
            folder = f"{SNAPS}/{size}" if name == "dashed" else f"{SNAPS}/{size}-key-{name}"
            imgs = [Image.open(f"{folder}/{shot}.png").convert("RGB") for shot in OUTLINE_SHOTS]
            sheet = labelled(imgs, OUTLINE_SHOTS, f"{name}: {desc} — {size}")
            sheet.save(f"{out}/outline-{name}-{size}.png")
        rows.append((name, desc))
    # compare: one row per option; columns: phone-land plan, phone-port plan (scaled), ipad plan; key tip land
    cols = [("phone-land", "09k-campaign-key-tip"), ("phone-port", "09k-campaign-key-tip"), ("ipad", "09-campaign-plan")]
    scale = {"phone-land": 1.0, "phone-port": 0.6, "ipad": 0.6}
    tiles = []
    for name, desc in OPTIONS:
        row = []
        for size, shot in cols:
            folder = f"{SNAPS}/{size}" if name == "dashed" else f"{SNAPS}/{size}-key-{name}"
            img = Image.open(f"{folder}/{shot}.png").convert("RGB")
            k = scale[size]
            row.append(img.resize((int(img.width * k), int(img.height * k)), Image.LANCZOS))
        tiles.append((name, desc, row))
    pad, gap, head = 16, 16, 30
    rowh = max(max(i.height for i in r) for _, _, r in tiles)
    roww = sum(i.width for i in tiles[0][2]) + gap * (len(cols) - 1)
    sheet = Image.new("RGB", (pad * 2 + roww, pad + len(tiles) * (head + rowh + gap) + 40), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text(
        (pad, pad),
        "Key-state outline options — phone-land key tip (1:1), phone-port key tip (0.6x), iPad plan (0.6x)",
        fill=FG,
        font=font(22),
    )
    y = pad + 40
    for name, desc, row in tiles:
        draw.text((pad, y), f"{name}: {desc}", fill=FG, font=font(18))
        x = pad
        for img in row:
            sheet.paste(img, (x, y + head))
            x += img.width + gap
        y += head + rowh + gap
    sheet.save(f"{out}/outline-compare.png")
    print("ok")


if __name__ == "__main__":
    main()
