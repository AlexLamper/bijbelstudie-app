"""Regenerate the iOS app icon set from the website's brand mark.

The icon is `C:\\Projects\\bijbelstudie\\public\\icon.svg` — a dark slate square,
a white page with three text rules, and a gold check. It is redrawn here with
PIL rather than rasterised with an SVG library, because cairosvg needs a native
libcairo that does not exist on this machine, and the mark is four primitives.

Two deliberate differences from the SVG:

  * The 96px corner radius is dropped. iOS applies its own corner mask to app
    icons; baking one in leaves dark wedges in the corners of the masked result.
    The square is filled edge to edge.
  * Output is RGB with no alpha. App Store Connect rejects a marketing icon that
    carries an alpha channel.

Run:  python tools/make_app_icon.py
"""

from __future__ import annotations

import json
import pathlib

from PIL import Image, ImageDraw

# ── The mark, in the SVG's 512-unit coordinate space ─────────────────────────
VIEWBOX = 512
SLATE = (0x26, 0x26, 0x26)
PAPER = (0xF8, 0xFA, 0xFC)
GOLD = (0xC7, 0x9A, 0x3B)

PAGE = (140, 112, 372, 400)  # x0, y0, x1, y1
PAGE_RADIUS = 22

RULES = [  # (x0, y0, x1, y1)
    (190, 188, 322, 188),
    (190, 244, 322, 244),
    (190, 300, 282, 300),
]
RULE_WIDTH = 18

CHECK = [(334, 318), (370, 352), (426, 296)]
CHECK_WIDTH = 20

# Drawn at 8x then reduced, which is cheaper and sharper than anti-aliasing by
# hand and keeps the small sizes legible.
SUPERSAMPLE = 8

ICON_DIR = pathlib.Path(__file__).resolve().parents[1] / (
    "bijbelstudie_mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
)


def render(size: int) -> Image.Image:
    canvas = size * SUPERSAMPLE
    k = canvas / VIEWBOX

    def s(v: float) -> float:
        return v * k

    img = Image.new("RGB", (canvas, canvas), SLATE)
    draw = ImageDraw.Draw(img)

    draw.rounded_rectangle(
        [s(PAGE[0]), s(PAGE[1]), s(PAGE[2]), s(PAGE[3])],
        radius=s(PAGE_RADIUS),
        fill=PAPER,
    )

    for x0, y0, x1, y1 in RULES:
        draw.line([s(x0), s(y0), s(x1), s(y1)], fill=SLATE, width=round(s(RULE_WIDTH)))
        # PIL has no round line caps; a disc at each end supplies them.
        r = s(RULE_WIDTH) / 2
        for x, y in ((x0, y0), (x1, y1)):
            draw.ellipse([s(x) - r, s(y) - r, s(x) + r, s(y) + r], fill=SLATE)

    r = s(CHECK_WIDTH) / 2
    for (x0, y0), (x1, y1) in zip(CHECK, CHECK[1:]):
        draw.line([s(x0), s(y0), s(x1), s(y1)], fill=GOLD, width=round(s(CHECK_WIDTH)))
    for x, y in CHECK:  # caps and the joint
        draw.ellipse([s(x) - r, s(y) - r, s(x) + r, s(y) + r], fill=GOLD)

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    contents = json.loads((ICON_DIR / "Contents.json").read_text(encoding="utf-8"))

    wanted: dict[str, int] = {}
    for entry in contents["images"]:
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        wanted[entry["filename"]] = round(base * scale)

    # The set on disk carries a few legacy names Contents.json no longer lists.
    for stray in ICON_DIR.glob("Icon-App-*.png"):
        if stray.name not in wanted:
            base, _, scale = stray.stem.removeprefix("Icon-App-").partition("@")
            wanted[stray.name] = round(float(base.split("x")[0]) * int(scale.rstrip("x")))

    for name, px in sorted(wanted.items(), key=lambda kv: kv[1]):
        render(px).save(ICON_DIR / name, "PNG", optimize=True)
        print(f"{name:34} {px}x{px}")


if __name__ == "__main__":
    main()
