"""Renders the Wyrmhaven rarity badges (faceted gem, one cut per rarity) as PNGs.

Each rarity gets its own silhouette so they stay readable at small sizes and
without relying on color alone: Common = rhombus, Rare = hexagon,
Epic = brilliant-cut gem, Legendary = star with a golden glow.
Drawn at 4x and downsampled for smooth edges. Output: <Rarity>.png (512px).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # working size
OUT = 512
HERE = os.path.dirname(os.path.abspath(__file__))

CLEAR = (0, 0, 0, 0)
LIGHT = (-0.55, -0.83)  # light comes from the top-left (screen coords, y down)


def p(x, y):
    return (x * S, y * S)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def scale_about(points, center, k):
    cx, cy = center
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in points]


def star(cx, cy, r_out, r_in, n):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = -math.pi / 2 + i * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def regular(cx, cy, r, n, rot=-math.pi / 2):
    return [(cx + r * math.cos(rot + i * math.tau / n), cy + r * math.sin(rot + i * math.tau / n)) for i in range(n)]


def sparkle(d, cx, cy, r, fill=(255, 255, 255, 255)):
    w = r * 0.22
    d.polygon([p(cx, cy - r), p(cx + w, cy - w), p(cx + r, cy), p(cx + w, cy + w),
               p(cx, cy + r), p(cx - w, cy + w), p(cx - r, cy), p(cx - w, cy - w)], fill=fill)


def gem(outer, center, table_k, light, dark, edge):
    """Faceted gem: flat table in the middle, one shaded facet per outer edge."""
    img = Image.new("RGBA", (S, S), CLEAR)
    inner = scale_about(outer, center, table_k)
    n = len(outer)

    # dark outline + drop shadow under the whole silhouette
    sil = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sil).polygon([p(*v) for v in outer], fill=255)
    grown = sil.filter(ImageFilter.MaxFilter(int(S * 0.028) | 1))
    shadow = grown.filter(ImageFilter.GaussianBlur(S * 0.014)).point(lambda v: v * 0.45)
    img.alpha_composite(Image.merge("RGBA", (*[Image.new("L", (S, S), 0)] * 3, shadow)), (0, int(S * 0.016)))
    img.alpha_composite(Image.merge("RGBA", (*[Image.new("L", (S, S), c) for c in edge], grown)))

    layer = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(layer)
    for i in range(n):
        a, b = outer[i], outer[(i + 1) % n]
        ia, ib = inner[i], inner[(i + 1) % n]
        mx, my = (a[0] + b[0]) / 2 - center[0], (a[1] + b[1]) / 2 - center[1]
        length = math.hypot(mx, my) or 1
        t = 0.5 + 0.5 * (mx * LIGHT[0] + my * LIGHT[1]) / length
        d.polygon([p(*a), p(*b), p(*ib), p(*ia)], fill=lerp(dark, light, t) + (255,))
    # table: vertical gradient from light to mid
    table_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(table_mask).polygon([p(*v) for v in inner], fill=255)
    grad = Image.linear_gradient("L").resize((S, S))
    table = Image.composite(Image.new("RGBA", (S, S), lerp(light, dark, 0.45) + (255,)),
                            Image.new("RGBA", (S, S), lerp(light, (255, 255, 255), 0.25) + (255,)), grad)
    layer.paste(table, (0, 0), table_mask)

    # thin bright lines along the facet seams
    seam = lerp(light, (255, 255, 255), 0.6) + (150,)
    wid = int(S * 0.006)
    for i in range(n):
        d.line([p(*outer[i]), p(*inner[i])], fill=seam, width=wid)
    d.line([p(*v) for v in inner + [inner[0]]], fill=seam, width=wid, joint="curve")
    img.alpha_composite(layer)

    # gloss streak across the upper-left of the table
    gloss = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(gloss)
    gd.polygon([p(center[0] - 0.14, center[1] - 0.02), p(center[0] - 0.02, center[1] - 0.14),
                p(center[0] + 0.03, center[1] - 0.11), p(center[0] - 0.11, center[1] + 0.01)], fill=110)
    gloss = Image.composite(gloss, Image.new("L", (S, S), 0), table_mask).filter(ImageFilter.GaussianBlur(S * 0.004))
    img.alpha_composite(Image.merge("RGBA", (*[Image.new("L", (S, S), 255)] * 3, gloss)))
    return img


def glow(color, radius, strength, rays=0):
    g = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(g)
    gd.ellipse([p(0.5 - radius, 0.5 - radius), p(0.5 + radius, 0.5 + radius)], fill=int(255 * strength))
    for i in range(rays):
        a = i * math.tau / rays - math.pi / 2
        half = math.radians(5)
        gd.polygon([p(0.5, 0.5), p(0.5 + 0.38 * math.cos(a - half), 0.5 + 0.38 * math.sin(a - half)),
                    p(0.5 + 0.38 * math.cos(a + half), 0.5 + 0.38 * math.sin(a + half))], fill=int(200 * strength))
    # blur stays well inside the canvas so the glow never shows a square cut
    g = g.filter(ImageFilter.GaussianBlur(S * 0.03))
    return Image.merge("RGBA", (*[Image.new("L", (S, S), c) for c in color], g))


def common():
    outer = [(0.50, 0.14), (0.78, 0.50), (0.50, 0.86), (0.22, 0.50)]
    return gem(outer, (0.5, 0.5), 0.5, (214, 220, 228), (92, 100, 114), (38, 42, 50))


def rare():
    outer = regular(0.5, 0.5, 0.37, 6)
    return gem(outer, (0.5, 0.5), 0.52, (132, 206, 255), (18, 78, 186), (12, 34, 84))


def epic():
    outer = [(0.28, 0.35), (0.38, 0.20), (0.62, 0.20), (0.72, 0.35), (0.50, 0.84)]
    center = (0.5, 0.40)
    img = glow((186, 96, 255), 0.30, 0.55)
    img.alpha_composite(gem(outer, center, 0.5, (224, 158, 255), (86, 26, 168), (40, 10, 80)))
    return img


def legendary():
    outer = star(0.5, 0.52, 0.40, 0.19, 5)
    img = glow((255, 196, 60), 0.30, 0.8, rays=10)
    img.alpha_composite(gem(outer, (0.5, 0.52), 0.45, (255, 236, 130), (206, 118, 8), (96, 50, 4)))
    return img


RARITIES = {
    # (render, sparkles as (x, y, r))
    "Common": (common, []),
    "Rare": (rare, [(0.74, 0.24, 0.07)]),
    "Epic": (epic, [(0.76, 0.22, 0.075), (0.25, 0.66, 0.045)]),
    "Legendary": (legendary, [(0.80, 0.20, 0.085), (0.19, 0.30, 0.055), (0.78, 0.80, 0.05)]),
}


def render(fn, sparkles):
    img = fn()
    # sparkles get a soft dark halo so they still read on light backgrounds
    layer = Image.new("RGBA", (S, S), CLEAR)
    d = ImageDraw.Draw(layer)
    for x, y, r in sparkles:
        sparkle(d, x, y, r)
    halo = layer.getchannel("A").filter(ImageFilter.GaussianBlur(S * 0.006)).point(lambda v: v * 0.5)
    img.alpha_composite(Image.merge("RGBA", (*[Image.new("L", (S, S), 40)] * 3, halo)))
    img.alpha_composite(layer)
    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    icons = []
    for name, (fn, sparkles) in RARITIES.items():
        icon = render(fn, sparkles)
        icon.save(os.path.join(HERE, f"{name}.png"))
        icons.append(icon)
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
