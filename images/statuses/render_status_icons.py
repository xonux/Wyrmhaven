"""Renders the Wyrmhaven combat status icons (Config/StatusDefs) as PNGs.

Inspired by Monster Legends' status icons: a rounded square badge whose
colour says whether the status is good or bad news, a white glyph for what it
touches (a sword for Attack, ...) and a corner arrow for which way it goes.
The badge is square on purpose, so it never reads as an element disc
(images/elements).

Drawn at 4x and downsampled for smooth edges. Output: <StatusId>.png (256px),
plus _preview.png showing each icon at the sizes the battle screen uses.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 1024  # working size
OUT = 256
HERE = os.path.dirname(os.path.abspath(__file__))

CLEAR = (0, 0, 0, 0)
WHITE = (255, 255, 255, 255)
DARK = (30, 24, 34, 255)

# Background by what the status means for whoever carries it.
BAD = ((196, 58, 78), (104, 20, 44))
GOOD = ((72, 188, 120), (20, 110, 72))
ARROW_DOWN = (236, 56, 56, 255)
ARROW_UP = (70, 214, 96, 255)


def p(x, y):
    return (x * S, y * S)


def rotate(points, angle, cx=0.5, cy=0.5, scale=1.0, dx=0.0, dy=0.0):
    """Rotates (and scales) unit-space points around (cx, cy), then shifts them
    by (dx, dy); returns working-space points."""
    c, s = math.cos(angle) * scale, math.sin(angle) * scale
    return [p(cx + dx + (x - cx) * c - (y - cy) * s, cy + dy + (x - cx) * s + (y - cy) * c) for x, y in points]


def vertical_gradient(top, bottom):
    mask = Image.linear_gradient("L").resize((S, S))
    return Image.composite(Image.new("RGBA", (S, S), bottom), Image.new("RGBA", (S, S), top), mask)


def rounded_mask(inset, radius):
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([p(inset, inset), p(1 - inset, 1 - inset)], radius=radius * S, fill=255)
    return mask


def solid(color, alpha):
    return Image.merge("RGBA", (*[Image.new("L", (S, S), v) for v in color[:3]], alpha))


# --- glyphs: white shapes on a transparent layer, in unit coords ---

def glyph_sword(d):
    """A broad sword pointing up-right, drawn upright then turned 45 degrees and
    pushed toward the top-left corner, leaving the bottom-right to the arrow."""
    def turn(points):
        return rotate(points, math.radians(45), scale=1.12, dx=-0.07, dy=-0.06)

    blade = [(0.44, 0.60), (0.44, 0.24), (0.50, 0.11), (0.56, 0.24), (0.56, 0.60)]
    guard = [(0.33, 0.595), (0.67, 0.595), (0.67, 0.675), (0.33, 0.675)]
    grip = [(0.463, 0.675), (0.537, 0.675), (0.537, 0.80), (0.463, 0.80)]
    for shape in (blade, guard, grip):
        d.polygon(turn(shape), fill=WHITE)
    (px, py), = turn([(0.50, 0.835)])
    r = 0.062 * S
    d.ellipse([px - r, py - r, px + r, py + r], fill=WHITE)


def arrow_shape(down, cx, cy, size):
    """A chunky arrow centred on (cx, cy), in unit coords."""
    w, h = size, size * 1.15
    head, shaft = 0.55 * h, 0.26 * w
    pts = [(0, -h / 2), (w / 2, -h / 2 + head), (shaft, -h / 2 + head), (shaft, h / 2),
           (-shaft, h / 2), (-shaft, -h / 2 + head), (-w / 2, -h / 2 + head)]
    if down:
        pts = [(x, -y) for x, y in pts]
    return [p(cx + x, cy + y) for x, y in pts]


# StatusId: (good?, glyph, arrow: None | ("up"|"down", count))
STATUSES = {
    "Weaken": (False, glyph_sword, ("down", 1)),
}


def render(good, glyph, arrow):
    top, bottom = GOOD if good else BAD
    img = Image.new("RGBA", (S, S), CLEAR)

    # dark outer edge, light metallic rim, coloured face - same build as the element discs
    img.paste(Image.new("RGBA", (S, S), DARK), (0, 0), rounded_mask(0.01, 0.20))
    img.paste(vertical_gradient((242, 244, 248, 255), (150, 156, 168, 255)), (0, 0), rounded_mask(0.035, 0.18))
    face = rounded_mask(0.085, 0.14)
    img.paste(vertical_gradient(top + (255,), bottom + (255,)), (0, 0), face)

    # soft inner shadow along the face's edge
    shade = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shade).rounded_rectangle([p(0.085, 0.085), p(0.915, 0.915)], radius=0.14 * S, outline=160,
                                            width=int(0.04 * S))
    shade = shade.filter(ImageFilter.GaussianBlur(S * 0.015))
    shade = Image.composite(shade, Image.new("L", (S, S), 0), face).point(lambda v: v * 0.5)
    img = Image.alpha_composite(img, solid((0, 0, 0), shade))

    # glossy band on the upper half
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).rounded_rectangle([p(0.12, 0.11), p(0.88, 0.48)], radius=0.12 * S, fill=255)
    fade = Image.linear_gradient("L").resize((S, S)).point(lambda v: max(0, 64 - v * 0.26))
    gloss = Image.composite(fade, Image.new("L", (S, S), 0), gloss)
    img = Image.alpha_composite(img, solid((255, 255, 255), gloss))

    # glyph, with a dark outline and a drop shadow so it holds up at 24px
    layer = Image.new("RGBA", (S, S), CLEAR)
    glyph(ImageDraw.Draw(layer))
    alpha = layer.getchannel("A")
    outline = alpha.filter(ImageFilter.MaxFilter(int(S * 0.022) | 1))
    shadow = outline.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: v * 0.45)
    img.alpha_composite(solid((0, 0, 0), shadow), (0, int(S * 0.014)))
    img = Image.alpha_composite(img, solid(DARK, outline))
    img = Image.alpha_composite(img, layer)

    # corner arrow(s): which way the stat goes, two for the strong version
    if arrow:
        direction, count = arrow
        fill = ARROW_UP if direction == "up" else ARROW_DOWN
        size = 0.28 if count == 1 else 0.22
        centres = [(0.74, 0.735)] if count == 1 else [(0.64, 0.76), (0.80, 0.76)]
        arrows = Image.new("L", (S, S), 0)
        ad = ImageDraw.Draw(arrows)
        for cx, cy in centres:
            ad.polygon(arrow_shape(direction == "down", cx, cy, size), fill=255)
        white_ring = arrows.filter(ImageFilter.MaxFilter(int(S * 0.03) | 1))
        dark_ring = white_ring.filter(ImageFilter.MaxFilter(int(S * 0.018) | 1))
        shadow = dark_ring.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: v * 0.45)
        img.alpha_composite(solid((0, 0, 0), shadow), (0, int(S * 0.012)))
        img = Image.alpha_composite(img, solid(DARK, dark_ring))
        img = Image.alpha_composite(img, solid(WHITE, white_ring))
        img = Image.alpha_composite(img, solid(fill, arrows))

    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    icons = {}
    for name, (good, glyph, arrow) in STATUSES.items():
        icons[name] = render(good, glyph, arrow)
        icons[name].save(os.path.join(HERE, f"{name}.png"))
    # preview on the UI's dark grey: full size, then the small sizes the battle bar uses
    sizes = [OUT, 64, 32, 24]
    width = sum(sizes) + 20 * (len(sizes) + 1)
    sheet = Image.new("RGBA", (width, (OUT + 20) * len(icons) + 20), (34, 36, 41, 255))
    for row, icon in enumerate(icons.values()):
        x = 20
        for size in sizes:
            y = 20 + row * (OUT + 20) + (OUT - size) // 2
            sheet.alpha_composite(icon.resize((size, size), Image.LANCZOS), (x, y))
            x += size + 20
    sheet.convert("RGB").save(os.path.join(HERE, "_preview.png"))
    print("ok", len(icons))


if __name__ == "__main__":
    main()
