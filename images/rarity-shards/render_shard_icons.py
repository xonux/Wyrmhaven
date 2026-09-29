"""Renders the Wyrmhaven rarity shards (a broken, faceted crystal shard plus
a small chip) as PNGs, one per rarity, in the colors of the rarity badges
(images/rarities). Higher rarities get a glow and more sparkles.
Drawn at 4x and downsampled for smooth edges. Output: <Rarity>.png (512px).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # working size
OUT = 512
HERE = os.path.dirname(os.path.abspath(__file__))
CLEAR = (0, 0, 0, 0)
LIGHT = (-0.6, -0.8)  # light from the top-left (screen coords, y down)

RARITIES = {
    # name: (light, dark, outline, glow or None, sparkles as (x, y, r))
    # light/dark match the rarity badge disc top/bottom colors
    "Common": ((200, 206, 216), (96, 102, 114), (48, 52, 62), None, []),
    "Rare": ((110, 190, 255), (20, 80, 188), (12, 42, 108), None, [(0.74, 0.2, 0.06)]),
    "Epic": ((206, 138, 255), (96, 30, 170), (52, 12, 98), (186, 96, 255), [(0.76, 0.2, 0.065), (0.24, 0.6, 0.045)]),
    "Legendary": ((255, 222, 110), (214, 118, 8), (118, 58, 4), (255, 190, 60),
                  [(0.77, 0.18, 0.075), (0.22, 0.3, 0.05), (0.8, 0.62, 0.045)]),
}

# Main shard: tall, leaning, with a jagged broken base. Core = where facets meet.
SHARD = [(0.55, 0.08), (0.67, 0.28), (0.71, 0.5), (0.65, 0.72), (0.6, 0.83), (0.55, 0.77), (0.49, 0.87),
         (0.42, 0.79), (0.36, 0.84), (0.31, 0.7), (0.31, 0.48), (0.4, 0.26)]
SHARD_CORE = (0.5, 0.66)
# Small chip lying at its foot
CHIP = [(0.69, 0.7), (0.8, 0.73), (0.83, 0.86), (0.73, 0.91), (0.66, 0.84)]
CHIP_CORE = (0.74, 0.8)


def p(x, y):
    return (x * S, y * S)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def solid(color, alpha):
    return Image.merge("RGBA", (*[Image.new("L", (S, S), c) for c in color], alpha))


def crystal(outline_pts, core, light, dark, edge):
    img = Image.new("RGBA", (S, S), CLEAR)
    sil = Image.new("L", (S, S), 0)
    pts = [p(*v) for v in outline_pts]
    ImageDraw.Draw(sil).polygon(pts, fill=255)
    # outline: the silhouette plus a thick stroke along its edge
    grown = sil.copy()
    ImageDraw.Draw(grown).line(pts + [pts[0], pts[1]], fill=255, width=int(S * 0.026), joint="curve")
    shadow = grown.filter(ImageFilter.GaussianBlur(S * 0.014)).point(lambda v: v * 0.45)
    img.alpha_composite(solid((0, 0, 0), shadow), (0, int(S * 0.016)))
    img.alpha_composite(solid(edge, grown))

    layer = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(layer)
    n = len(outline_pts)
    for i in range(n):
        a, b = outline_pts[i], outline_pts[(i + 1) % n]
        mx, my = (a[0] + b[0]) / 2 - core[0], (a[1] + b[1]) / 2 - core[1]
        ln = math.hypot(mx, my) or 1
        t = 0.5 + 0.5 * (mx * LIGHT[0] + my * LIGHT[1]) / ln
        t = min(1, max(0, t * 0.9 + (0.08 if i % 2 else 0)))  # alternate facets a little
        d.polygon([p(*core), p(*a), p(*b)], fill=lerp(dark, light, t) + (255,))
    seam = lerp(light, (255, 255, 255), 0.6) + (140,)
    for v in outline_pts:
        d.line([p(*core), p(*v)], fill=seam, width=int(S * 0.005))
    img.alpha_composite(layer)
    return img, sil


def render(light, dark, edge, glow, sparkles):
    img = Image.new("RGBA", (S, S), CLEAR)
    if glow:
        g = Image.new("L", (S, S), 0)
        ImageDraw.Draw(g).polygon([p(*v) for v in SHARD], fill=190)
        g = g.filter(ImageFilter.GaussianBlur(S * 0.05)).point(lambda v: min(255, v * 1.6))
        img.alpha_composite(solid(glow, g))
    chip, _ = crystal(CHIP, CHIP_CORE, light, dark, edge)
    img.alpha_composite(chip)
    shard, sil = crystal(SHARD, SHARD_CORE, light, dark, edge)
    img.alpha_composite(shard)

    # gloss streak on the upper left face + a bright edge along the top
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).polygon([p(0.41, 0.3), p(0.5, 0.17), p(0.52, 0.22), p(0.43, 0.38)], fill=150)
    gloss = Image.composite(gloss, Image.new("L", (S, S), 0), sil).filter(ImageFilter.GaussianBlur(S * 0.004))
    img.alpha_composite(solid((255, 255, 255), gloss))

    # sparkles with a soft dark halo so they read on light backgrounds too
    sp = Image.new("RGBA", (S, S), CLEAR)
    sd = ImageDraw.Draw(sp)
    for x, y, r in sparkles:
        w = r * 0.22
        sd.polygon([p(x, y - r), p(x + w, y - w), p(x + r, y), p(x + w, y + w),
                    p(x, y + r), p(x - w, y + w), p(x - r, y), p(x - w, y - w)], fill=(255, 255, 255, 255))
    halo = sp.getchannel("A").filter(ImageFilter.GaussianBlur(S * 0.006)).point(lambda v: v * 0.5)
    img.alpha_composite(solid((40, 40, 40), halo))
    img.alpha_composite(sp)
    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    icons = [render(*spec) for spec in RARITIES.values()]
    for name, icon in zip(RARITIES, icons):
        icon.save(os.path.join(HERE, f"{name}.png"))
    # contact sheet: UI dark grey on top, light background below, plus a 64px row
    sheet = Image.new("RGBA", (OUT * 4 + 50, OUT * 2 + 130), (34, 36, 41, 255))
    ImageDraw.Draw(sheet).rectangle([0, OUT + 20, sheet.width, OUT * 2 + 40], fill=(236, 232, 220, 255))
    for i, icon in enumerate(icons):
        sheet.alpha_composite(icon, (10 + i * (OUT + 10), 10))
        sheet.alpha_composite(icon, (10 + i * (OUT + 10), OUT + 30))
        sheet.alpha_composite(icon.resize((64, 64), Image.LANCZOS), (10 + i * 80, OUT * 2 + 50))
    sheet.convert("RGB").save(os.path.join(HERE, "_preview_sheet.png"))
    print("ok", len(icons))


if __name__ == "__main__":
    main()
