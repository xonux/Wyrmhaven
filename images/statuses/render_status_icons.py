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
PIP = (252, 206, 72, 255)


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


# --- glyphs ---------------------------------------------------------------
# Each glyph is drawn in unit coords centred on (0.5, 0.5), in white on a
# transparent layer (CLEAR punches holes), through a Transform: when the icon
# carries a corner marker (arrow or pips) the glyph shrinks a little and moves
# toward the top-left corner to leave it room.


class Transform:
    def __init__(self, scale=1.0, dx=0.0, dy=0.0):
        self.scale, self.dx, self.dy = scale, dx, dy

    def pts(self, points, angle=0.0, extra=1.0):
        c, s_ = math.cos(angle), math.sin(angle)
        k = self.scale * extra
        return [p(0.5 + self.dx + ((x - 0.5) * c - (y - 0.5) * s_) * k,
                  0.5 + self.dy + ((x - 0.5) * s_ + (y - 0.5) * c) * k) for x, y in points]

    def pt(self, x, y, angle=0.0, extra=1.0):
        return self.pts([(x, y)], angle, extra)[0]

    def circle(self, d, x, y, r, fill, angle=0.0, extra=1.0):
        cx, cy = self.pt(x, y, angle, extra)
        rr = r * S * self.scale * extra
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=fill)


def bezier(p0, p1, p2, p3, n=40):
    out = []
    for i in range(n + 1):
        t = i / n
        a, b, c, e = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1]))
    return out


def curve(start, curves):
    """A closed outline from chained cubic curves (c1, c2, end), unit coords."""
    out, current = [], start
    for c1, c2, end in curves:
        out.extend(bezier(current, c1, c2, end))
        current = end
    return out


def star(cx, cy, outer, inner, points):
    out = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = -math.pi / 2 + i * math.pi / points
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def glyph_sword(d, T):
    """A broad sword pointing up-right."""
    a, k = math.radians(45), 1.12
    blade = [(0.44, 0.60), (0.44, 0.24), (0.50, 0.11), (0.56, 0.24), (0.56, 0.60)]
    guard = [(0.33, 0.595), (0.67, 0.595), (0.67, 0.675), (0.33, 0.675)]
    grip = [(0.463, 0.675), (0.537, 0.675), (0.537, 0.80), (0.463, 0.80)]
    for shape in (blade, guard, grip):
        d.polygon(T.pts(shape, a, k), fill=WHITE)
    T.circle(d, 0.50, 0.835, 0.062, WHITE, a, k)


def glyph_speed(d, T):
    """Fast-forward: two chevron-like wedges."""
    d.polygon(T.pts([(0.16, 0.26), (0.50, 0.50), (0.16, 0.74)]), fill=WHITE)
    d.polygon(T.pts([(0.46, 0.26), (0.80, 0.50), (0.46, 0.74)]), fill=WHITE)


HEART = curve((0.50, 0.82), [
    ((0.34, 0.68), (0.14, 0.54), (0.16, 0.36)),
    ((0.18, 0.20), (0.40, 0.14), (0.50, 0.30)),
    ((0.60, 0.14), (0.82, 0.20), (0.84, 0.36)),
    ((0.86, 0.54), (0.66, 0.68), (0.50, 0.82)),
])


def glyph_heart(d, T):
    d.polygon(T.pts(HEART), fill=WHITE)


def glyph_heal(d, T):
    """A heart with a cross punched through it."""
    d.polygon(T.pts(HEART), fill=WHITE)
    d.polygon(T.pts([(0.455, 0.30), (0.545, 0.30), (0.545, 0.42), (0.665, 0.42), (0.665, 0.51),
                     (0.545, 0.51), (0.545, 0.63), (0.455, 0.63), (0.455, 0.51), (0.335, 0.51),
                     (0.335, 0.42), (0.455, 0.42)]), fill=CLEAR)


FLAME = curve((0.50, 0.84), [
    ((0.71, 0.84), (0.78, 0.64), (0.71, 0.48)),
    ((0.66, 0.37), (0.56, 0.31), (0.56, 0.16)),
    ((0.46, 0.24), (0.40, 0.32), (0.42, 0.43)),
    ((0.37, 0.40), (0.35, 0.35), (0.36, 0.29)),
    ((0.25, 0.41), (0.22, 0.57), (0.28, 0.69)),
    ((0.33, 0.79), (0.41, 0.84), (0.50, 0.84)),
])
FLAME_CORE = curve((0.50, 0.78), [
    ((0.60, 0.78), (0.64, 0.68), (0.60, 0.61)),
    ((0.56, 0.55), (0.51, 0.52), (0.51, 0.45)),
    ((0.46, 0.53), (0.39, 0.59), (0.40, 0.68)),
    ((0.41, 0.74), (0.45, 0.78), (0.50, 0.78)),
])


def glyph_flame(d, T):
    d.polygon(T.pts(FLAME), fill=WHITE)
    d.polygon(T.pts(FLAME_CORE), fill=CLEAR)


def glyph_skull(d, T):
    T.circle(d, 0.50, 0.43, 0.26, WHITE)
    d.rounded_rectangle([T.pt(0.34, 0.52), T.pt(0.66, 0.80)], radius=0.06 * S * T.scale, fill=WHITE)
    T.circle(d, 0.40, 0.45, 0.075, CLEAR)
    T.circle(d, 0.60, 0.45, 0.075, CLEAR)
    d.polygon(T.pts([(0.50, 0.54), (0.545, 0.63), (0.455, 0.63)]), fill=CLEAR)
    for x in (0.44, 0.50, 0.56):
        d.rectangle([T.pt(x - 0.012, 0.70), T.pt(x + 0.012, 0.80)], fill=CLEAR)


def drop(d, T, cx, cy, r, fill=WHITE):
    """A drop: a circle with a pointed top."""
    T.circle(d, cx, cy, r, fill)
    d.polygon(T.pts([(cx - r * 0.92, cy - r * 0.38), (cx, cy - r * 2.3), (cx + r * 0.92, cy - r * 0.38)]), fill=fill)


def glyph_bleed(d, T):
    """A big drop and two splashes."""
    drop(d, T, 0.44, 0.60, 0.20)
    drop(d, T, 0.74, 0.40, 0.08)
    drop(d, T, 0.72, 0.70, 0.055)


def glyph_poison(d, T):
    glyph_skull(d, T)


def glyph_stun(d, T):
    """Dizzy stars circling over an orbit."""
    d.ellipse([T.pt(0.14, 0.50), T.pt(0.86, 0.80)], outline=WHITE, width=int(0.045 * S * T.scale))
    d.polygon(T.pts(star(0.50, 0.40, 0.24, 0.10, 5)), fill=WHITE)
    d.polygon(T.pts(star(0.20, 0.64, 0.10, 0.045, 5)), fill=WHITE)
    d.polygon(T.pts(star(0.80, 0.64, 0.10, 0.045, 5)), fill=WHITE)


def glyph_taunt(d, T):
    """A bullseye: every single-target hit comes here."""
    T.circle(d, 0.50, 0.50, 0.33, WHITE)
    T.circle(d, 0.50, 0.50, 0.245, CLEAR)
    T.circle(d, 0.50, 0.50, 0.165, WHITE)
    T.circle(d, 0.50, 0.50, 0.085, CLEAR)
    T.circle(d, 0.50, 0.50, 0.045, WHITE)


def shield_outline(scale):
    def at(x, y):
        return (0.5 + (x - 0.5) * scale, 0.5 + (y - 0.5) * scale)
    return curve(at(0.50, 0.14), [
        (at(0.60, 0.20), at(0.72, 0.22), at(0.80, 0.22)),
        (at(0.80, 0.52), at(0.72, 0.72), at(0.50, 0.86)),
        (at(0.28, 0.72), at(0.20, 0.52), at(0.20, 0.22)),
        (at(0.28, 0.22), at(0.40, 0.20), at(0.50, 0.14)),
    ])


def glyph_shield(d, T):
    d.polygon(T.pts(shield_outline(1.0)), fill=WHITE)
    d.polygon(T.pts(shield_outline(0.74)), fill=CLEAR)
    d.polygon(T.pts(shield_outline(0.56)), fill=WHITE)


def glyph_drain(d, T):
    """A bite: an upper jaw with two fangs, a drop under them."""
    d.rounded_rectangle([T.pt(0.20, 0.22), T.pt(0.80, 0.37)], radius=0.075 * S * T.scale, fill=WHITE)
    d.polygon(T.pts([(0.25, 0.33), (0.43, 0.33), (0.34, 0.62)]), fill=WHITE)
    d.polygon(T.pts([(0.57, 0.33), (0.75, 0.33), (0.66, 0.62)]), fill=WHITE)
    drop(d, T, 0.50, 0.74, 0.095)


def glyph_cleanse(d, T):
    """Sparkles: clean again."""
    d.polygon(T.pts(star(0.42, 0.54, 0.32, 0.075, 4)), fill=WHITE)
    d.polygon(T.pts(star(0.74, 0.26, 0.14, 0.035, 4)), fill=WHITE)
    d.polygon(T.pts(star(0.76, 0.76, 0.10, 0.028, 4)), fill=WHITE)


def arrow_shape(down, cx, cy, size):
    """A chunky arrow centred on (cx, cy), in unit coords."""
    w, h = size, size * 1.15
    head, shaft = 0.55 * h, 0.26 * w
    pts = [(0, -h / 2), (w / 2, -h / 2 + head), (shaft, -h / 2 + head), (shaft, h / 2),
           (-shaft, h / 2), (-shaft, -h / 2 + head), (-w / 2, -h / 2 + head)]
    if down:
        pts = [(x, -y) for x, y in pts]
    return [p(cx + x, cy + y) for x, y in pts]


# Every status in Config/StatusDefs: (good?, glyph, corner marker).
# The corner marker is one of:
#   ("up" | "down", n)  arrows - a stat going up or down, two for the strong one
#   ("tier", n)          pips - the same effect in a bigger dose (Singe < Burn)
#   None                 nothing, the glyph is centred
STATUSES = {
    # damage over time
    "Singe": (False, glyph_flame, ("tier", 1)),
    "Burn": (False, glyph_flame, ("tier", 2)),
    "Poison": (False, glyph_poison, None),
    "Bleed": (False, glyph_bleed, None),
    # debuffs
    "Weaken": (False, glyph_sword, ("down", 1)),
    "Cripple": (False, glyph_sword, ("down", 2)),
    "Slow": (False, glyph_speed, ("down", 1)),
    "Root": (False, glyph_speed, ("down", 2)),
    "Wither": (False, glyph_heart, ("down", 1)),
    "Stun": (False, glyph_stun, None),
    # buffs
    "Focus": (True, glyph_sword, ("up", 1)),
    "Rage": (True, glyph_sword, ("up", 2)),
    "Quicken": (True, glyph_speed, ("up", 1)),
    "Haste": (True, glyph_speed, ("up", 2)),
    "Taunt": (True, glyph_taunt, None),
    # shields
    "Guard": (True, glyph_shield, ("tier", 1)),
    "Barrier": (True, glyph_shield, ("tier", 2)),
    "Bulwark": (True, glyph_shield, ("tier", 3)),
    # healing
    "Mend": (True, glyph_heal, ("tier", 1)),
    "Renewal": (True, glyph_heal, ("tier", 2)),
    "Drain": (True, glyph_drain, None),
    "Cleanse": (True, glyph_cleanse, None),
}


def outlined(img, shapes, fill, ring=0.03, dark=0.018):
    """Paints a mask `shapes` in `fill`, with a white ring, a dark ring and a shadow."""
    white_ring = shapes.filter(ImageFilter.MaxFilter(int(S * ring) | 1))
    dark_ring = white_ring.filter(ImageFilter.MaxFilter(int(S * dark) | 1))
    shadow = dark_ring.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: v * 0.45)
    img.alpha_composite(solid((0, 0, 0), shadow), (0, int(S * 0.012)))
    img = Image.alpha_composite(img, solid(DARK, dark_ring))
    img = Image.alpha_composite(img, solid(WHITE, white_ring))
    return Image.alpha_composite(img, solid(fill, shapes))


def render(good, glyph, marker):
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
    T = Transform() if marker is None else Transform(0.86, -0.06, -0.06)
    layer = Image.new("RGBA", (S, S), CLEAR)
    glyph(ImageDraw.Draw(layer), T)
    alpha = layer.getchannel("A")
    outline = alpha.filter(ImageFilter.MaxFilter(int(S * 0.022) | 1))
    shadow = outline.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: v * 0.45)
    img.alpha_composite(solid((0, 0, 0), shadow), (0, int(S * 0.014)))
    img = Image.alpha_composite(img, solid(DARK, outline))
    img = Image.alpha_composite(img, layer)

    if marker:
        kind, count = marker
        shapes = Image.new("L", (S, S), 0)
        sd = ImageDraw.Draw(shapes)
        if kind == "tier":
            # gold pips along the bottom-right corner, one per dose
            r = 0.068
            for i in range(count):
                cx, cy = 0.79 - i * 0.17, 0.78
                sd.polygon([p(cx, cy - r * 1.25), p(cx + r, cy), p(cx, cy + r * 1.25), p(cx - r, cy)], fill=255)
            img = outlined(img, shapes, PIP, ring=0.022, dark=0.016)
        else:
            # which way the stat goes, two arrows for the strong version
            size = 0.28 if count == 1 else 0.22
            centres = [(0.74, 0.735)] if count == 1 else [(0.64, 0.76), (0.80, 0.76)]
            for cx, cy in centres:
                sd.polygon(arrow_shape(kind == "down", cx, cy, size), fill=255)
            img = outlined(img, shapes, ARROW_UP if kind == "up" else ARROW_DOWN)

    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    icons = {}
    for name, (good, glyph, marker) in STATUSES.items():
        icons[name] = render(good, glyph, marker)
        icons[name].save(os.path.join(HERE, f"{name}.png"))
    # contact sheet on the UI's dark grey: each icon at 128px, then at 40 and
    # 24px (about what the battle screen's Health bar will show), and its name
    cols, cell_w, cell_h = 6, 230, 180
    rows = (len(icons) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_w + 20, rows * cell_h + 20), (34, 36, 41, 255))
    draw = ImageDraw.Draw(sheet)
    for i, (name, icon) in enumerate(icons.items()):
        x, y = 20 + (i % cols) * cell_w, 16 + (i // cols) * cell_h
        sheet.alpha_composite(icon.resize((128, 128), Image.LANCZOS), (x, y))
        sheet.alpha_composite(icon.resize((40, 40), Image.LANCZOS), (x + 140, y + 20))
        sheet.alpha_composite(icon.resize((24, 24), Image.LANCZOS), (x + 148, y + 80))
        draw.text((x + 4, y + 136), name, fill=(230, 232, 236, 255))
    sheet.convert("RGB").save(os.path.join(HERE, "_preview.png"))
    print("ok", len(icons))


if __name__ == "__main__":
    main()
