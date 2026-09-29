"""Renders the Wyrmhaven rarity shards (a broken, faceted crystal shard plus
a small chip) as PNGs, one per rarity, in the colors of the rarity badges
(images/rarities). Straight edges and sharp corners, no glow or sparkles.
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
    # name: (light, dark, outline) - light/dark match the rarity badge disc
    "Common": ((200, 206, 216), (96, 102, 114), (48, 52, 62)),
    "Rare": ((110, 190, 255), (20, 80, 188), (12, 42, 108)),
    "Epic": ((206, 138, 255), (96, 30, 170), (52, 12, 98)),
    "Legendary": ((255, 222, 110), (214, 118, 8), (118, 58, 4)),
}

# Main shard: tall, leaning, with a jagged broken base. Core = where facets meet.
SHARD = [(0.56, 0.07), (0.71, 0.38), (0.66, 0.8), (0.58, 0.73), (0.51, 0.89), (0.44, 0.76), (0.34, 0.84),
         (0.29, 0.42)]
SHARD_CORE = (0.5, 0.6)
# Small chip lying at its foot
CHIP = [(0.71, 0.66), (0.86, 0.77), (0.77, 0.92), (0.66, 0.85)]
CHIP_CORE = (0.75, 0.8)


def p(x, y):
    return (x * S, y * S)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def miter_offset(pts, w):
    """Polygon grown outward by w with sharp (mitered) corners."""
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    sign = 1 if area > 0 else -1  # outward side of each edge
    normals = []
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
        ex, ey = bx - ax, by - ay
        ln = math.hypot(ex, ey)
        normals.append((-ey / ln * -sign, ex / ln * -sign))
    out = []
    for i, (x, y) in enumerate(pts):
        n1, n2 = normals[i - 1], normals[i]
        k = 1 + n1[0] * n2[0] + n1[1] * n2[1]
        mx, my = (n1[0] + n2[0]) / k, (n1[1] + n2[1]) / k
        m = math.hypot(mx, my)
        if m > 3:  # cap very sharp spikes
            mx, my = mx * 3 / m, my * 3 / m
        out.append((x + mx * w, y + my * w))
    return out


def solid(color, alpha):
    return Image.merge("RGBA", (*[Image.new("L", (S, S), c) for c in color], alpha))


def crystal(outline_pts, core, light, dark, edge):
    img = Image.new("RGBA", (S, S), CLEAR)
    sil = Image.new("L", (S, S), 0)
    pts = [p(*v) for v in outline_pts]
    ImageDraw.Draw(sil).polygon(pts, fill=255)
    # outline: the silhouette pushed outward with mitered (sharp) corners
    grown = Image.new("L", (S, S), 0)
    ImageDraw.Draw(grown).polygon([p(*v) for v in miter_offset(outline_pts, 0.013)], fill=255)
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


def render(light, dark, edge):
    img = Image.new("RGBA", (S, S), CLEAR)
    chip, _ = crystal(CHIP, CHIP_CORE, light, dark, edge)
    img.alpha_composite(chip)
    shard, sil = crystal(SHARD, SHARD_CORE, light, dark, edge)
    img.alpha_composite(shard)

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
