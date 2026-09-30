"""Renders the Wyrmhaven rarity star: a faceted 4-pointed star, one arm per
rarity (clockwise from the top: Common, Rare, Epic, Legendary), in the same
angular crystal style and colors as images/rarity-shards.
Drawn at 4x and downsampled for smooth edges. Output: RarityStar.png (512px).
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "rarity-shards"))
from render_shard_icons import CLEAR, LIGHT, OUT, RARITIES, S, lerp, miter_offset, p, solid  # noqa: E402

CENTER = (0.5, 0.5)
TIP = 0.43  # center -> arm tip
SHOULDER = 0.14  # center -> the notch between two arms
EDGE = (34, 36, 42)
ORDER = ["Common", "Rare", "Epic", "Legendary"]  # clockwise from the top


def at(angle, r):
    return (CENTER[0] + r * math.cos(angle), CENTER[1] + r * math.sin(angle))


def shade(a, b, light, dark):
    """Facet color from the direction its outer edge faces."""
    mx, my = (a[0] + b[0]) / 2 - CENTER[0], (a[1] + b[1]) / 2 - CENTER[1]
    ln = math.hypot(mx, my) or 1
    t = 0.5 + 0.5 * (mx * LIGHT[0] + my * LIGHT[1]) / ln
    return lerp(dark, light, 0.12 + 0.8 * t) + (255,)


def render():
    arms = []
    for i, name in enumerate(ORDER):
        a = -math.pi / 2 + i * math.pi / 2
        arms.append((name, at(a - math.pi / 4, SHOULDER), at(a, TIP), at(a + math.pi / 4, SHOULDER)))
    outline = []
    for _, left, tip, _ in arms:
        outline += [left, tip]

    img = Image.new("RGBA", (S, S), CLEAR)
    grown = Image.new("L", (S, S), 0)
    ImageDraw.Draw(grown).polygon([p(*v) for v in miter_offset(outline, 0.014, cap=6)], fill=255)
    shadow = grown.filter(ImageFilter.GaussianBlur(S * 0.014)).point(lambda v: v * 0.45)
    img.alpha_composite(solid((0, 0, 0), shadow), (0, int(S * 0.016)))
    img.alpha_composite(solid(EDGE, grown))

    layer = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(layer)
    for name, left, tip, right in arms:
        light, dark, _ = RARITIES[name]
        d.polygon([p(*CENTER), p(*left), p(*tip)], fill=shade(left, tip, light, dark))
        d.polygon([p(*CENTER), p(*tip), p(*right)], fill=shade(tip, right, light, dark))
        seam = lerp(light, (255, 255, 255), 0.6) + (140,)
        d.line([p(*CENTER), p(*tip)], fill=seam, width=int(S * 0.005))
    # dark seams between the arms so each color reads as its own branch
    for _, left, _, _ in arms:
        d.line([p(*CENTER), p(*left)], fill=EDGE + (255,), width=int(S * 0.012))
    img.alpha_composite(layer)
    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    icon = render()
    icon.save(os.path.join(HERE, "RarityStar.png"))
    sheet = Image.new("RGBA", (OUT * 2 + 30, OUT + 110), (34, 36, 41, 255))
    ImageDraw.Draw(sheet).rectangle([OUT + 20, 0, sheet.width, OUT + 20], fill=(236, 232, 220, 255))
    sheet.alpha_composite(icon, (10, 10))
    sheet.alpha_composite(icon, (OUT + 20, 10))
    sheet.alpha_composite(icon.resize((64, 64), Image.LANCZOS), (10, OUT + 30))
    sheet.alpha_composite(icon.resize((32, 32), Image.LANCZOS), (90, OUT + 46))
    sheet.convert("RGB").save(os.path.join(HERE, "_preview_sheet.png"))
    print("ok")


if __name__ == "__main__":
    main()
