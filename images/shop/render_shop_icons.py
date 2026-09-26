"""Renders the Shop's tab icons (Controllers/ShopController TABS) as PNGs.

Same badge as the element icons (images/elements): a coloured disc in a
metallic rim with a white glyph - it reuses that script's render(), so the two
sets can never drift apart. Each tab keeps the colour it already has in
ShopController (iconColor). Output: <TabId>.png (512px) and _preview.png.
"""
import importlib.util
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "element_icons", os.path.join(HERE, "..", "elements", "render_element_icons.py"))
E = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(E)

p, path, circle, WHITE, CLEAR, S, OUT = E.p, E.path, E.circle, E.WHITE, E.CLEAR, E.S, E.OUT


def turned(points, angle, cx=0.5, cy=0.5):
    c, s = math.cos(angle), math.sin(angle)
    return [p(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in points]


def glyph_egg(d):
    """Dragons: a spotted egg."""
    d.polygon(path((0.50, 0.19), [
        ((0.65, 0.19), (0.73, 0.44), (0.73, 0.56)),
        ((0.73, 0.72), (0.63, 0.81), (0.50, 0.81)),
        ((0.37, 0.81), (0.27, 0.72), (0.27, 0.56)),
        ((0.27, 0.44), (0.35, 0.19), (0.50, 0.19)),
    ]), fill=WHITE)
    circle(d, 0.44, 0.39, 0.045, CLEAR)
    circle(d, 0.59, 0.52, 0.065, CLEAR)
    circle(d, 0.42, 0.64, 0.05, CLEAR)
    circle(d, 0.58, 0.31, 0.03, CLEAR)


def glyph_lair(d):
    """Habitats: a craggy rock with a cave mouth, on the ground."""
    d.polygon([p(x, y) for x, y in [
        (0.17, 0.75), (0.19, 0.55), (0.25, 0.44), (0.30, 0.45), (0.35, 0.32), (0.43, 0.26),
        (0.49, 0.30), (0.56, 0.21), (0.65, 0.30), (0.69, 0.40), (0.75, 0.43), (0.80, 0.56), (0.83, 0.75),
    ]], fill=WHITE)
    d.polygon(path((0.38, 0.75), [
        ((0.38, 0.58), (0.43, 0.49), (0.51, 0.49)),
        ((0.59, 0.49), (0.64, 0.58), (0.64, 0.75)),
        ((0.55, 0.75), (0.47, 0.75), (0.38, 0.75)),
    ]), fill=CLEAR)
    # facets: a couple of notches that make it read as rock
    d.polygon([p(0.27, 0.56), p(0.34, 0.50), p(0.33, 0.54)], fill=CLEAR)
    d.polygon([p(0.66, 0.42), p(0.73, 0.50), p(0.69, 0.49)], fill=CLEAR)
    d.rounded_rectangle([p(0.14, 0.74), p(0.86, 0.81)], radius=0.035 * S, fill=WHITE)


def glyph_hammer(d):
    """Buildings: a builder's hammer, handle down-left."""
    a = math.radians(35)
    d.polygon(turned([(0.46, 0.34), (0.54, 0.34), (0.54, 0.85), (0.46, 0.85)], a), fill=WHITE)
    d.polygon(turned([(0.26, 0.24), (0.62, 0.24), (0.62, 0.38), (0.26, 0.38)], a), fill=WHITE)
    d.polygon(turned([(0.60, 0.18), (0.76, 0.18), (0.76, 0.44), (0.60, 0.44)], a), fill=WHITE)


def glyph_flower(d):
    """Decorations: a flower on its stem."""
    cx, cy, ring, petal = 0.50, 0.42, 0.15, 0.105
    d.rectangle([p(0.482, cy), p(0.518, 0.82)], fill=WHITE)
    d.polygon(path((0.50, 0.74), [
        ((0.58, 0.66), (0.70, 0.64), (0.74, 0.66)),
        ((0.70, 0.74), (0.60, 0.77), (0.50, 0.74)),
    ]), fill=WHITE)
    for i in range(5):
        ang = -math.pi / 2 + i * 2 * math.pi / 5
        circle(d, cx + ring * math.cos(ang), cy + ring * math.sin(ang), petal, WHITE)
    circle(d, cx, cy, 0.075, CLEAR)
    circle(d, cx, cy, 0.05, WHITE)


def shade(color, factor):
    return tuple(max(0, min(255, round(v * factor))) for v in color)


# TabId: (ShopController iconColor, glyph)
TABS = {
    "Dragons": ((242, 130, 59), glyph_egg),
    "Habitats": ((107, 158, 110), glyph_lair),
    "Buildings": ((206, 74, 58), glyph_hammer),
    "Decorations": ((214, 124, 170), glyph_flower),
}


def main():
    icons = []
    for name, (color, glyph) in TABS.items():
        icon = E.render(name, shade(color, 1.12), shade(color, 0.72), glyph, None)
        icon.save(os.path.join(HERE, f"{name}.png"))
        icons.append(icon)
    sheet = Image.new("RGBA", (4 * 276 + 20, 276 + 20 + 60), (34, 36, 41, 255))
    for i, icon in enumerate(icons):
        x = 20 + i * 276
        sheet.alpha_composite(icon.resize((256, 256), Image.LANCZOS), (x, 20))
        sheet.alpha_composite(icon.resize((34, 34), Image.LANCZOS), (x + 60, 290))
        sheet.alpha_composite(icon.resize((48, 48), Image.LANCZOS), (x + 110, 283))
    sheet.convert("RGB").save(os.path.join(HERE, "_preview.png"))
    print("ok", len(icons))


if __name__ == "__main__":
    main()
