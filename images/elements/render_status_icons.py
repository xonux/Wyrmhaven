"""Renders new Wyrmhaven status icons in the style of the existing ones in
this folder (Burn.png, Guard.png...): rounded-square tile with a dark edge,
silver rim, gloss band and inner shadow; green for buffs, crimson for
debuffs; a white glyph with a thin dark outline; optional modifiers in the
bottom-right corner (yellow tier diamonds, green up / red down arrows).
Drawn at 4x and downsampled. Output: <Status>.png (256px).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

K = 4  # supersampling
T = 256  # output size
S = T * K
HERE = os.path.dirname(os.path.abspath(__file__))
CLEAR = (0, 0, 0, 0)
WHITE = (255, 255, 255, 255)
INK = (24, 18, 28)

# base fill color at y=120 and its change per pixel going down (measured on the originals)
FILLS = {
    "buff": ((47, 152, 98), (-0.21, -0.33, -0.21)),
    "debuff": ((153, 40, 62), (-0.38, -0.14, -0.13)),
}
YELLOW = (252, 206, 72)
GREEN_ARROW = (70, 214, 96)
RED_ARROW = (236, 56, 56)


def q(v):
    """Tile pixels (0..256) -> working pixels."""
    return v * K


def P(x, y):
    """Unit coords (0..1 across the tile) -> working pixels."""
    return (x * S, y * S)


def solid(color, alpha):
    return Image.merge("RGBA", (*[Image.new("L", (S, S), c) for c in color[:3]], alpha))


def rrect_mask(box, r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([q(v) for v in box], radius=q(r), fill=255)
    return m


# ------------------------------------------------------------------ tile
def tile(kind):
    img = Image.new("RGBA", (S, S), CLEAR)
    img.paste(Image.new("RGBA", (S, S), (30, 24, 34, 255)), (0, 0), rrect_mask((3, 3, 252, 252), 48))
    rim = Image.linear_gradient("L").resize((S, S))
    rim_img = Image.composite(Image.new("RGBA", (S, S), (152, 158, 170, 255)), Image.new("RGBA", (S, S), (250, 252, 255, 255)), rim)
    img.paste(rim_img, (0, 0), rrect_mask((9, 9, 246, 246), 42))

    base, slope = FILLS[kind]
    fill = Image.new("RGBA", (S, S))
    rows = []
    for y in range(S):
        py = y / K - 120
        rows.append(tuple(max(0, min(255, round(base[i] + slope[i] * py))) for i in range(3)) + (255,))
    col = Image.new("RGBA", (1, S))
    col.putdata(rows)
    fill = col.resize((S, S))
    fmask = rrect_mask((21, 21, 234, 234), 32)
    img.paste(fill, (0, 0), fmask)

    # inner shadow along the fill edge, stronger toward the bottom
    ring = Image.eval(fmask.filter(ImageFilter.GaussianBlur(q(5))), lambda v: 255 - v)
    ring = Image.composite(ring, Image.new("L", (S, S), 0), fmask)
    bottom = Image.linear_gradient("L").resize((S, S)).point(lambda v: 0.4 + v / 255 * 0.35)
    alpha = Image.eval(ring, lambda v: v)
    alpha = Image.merge("L", [alpha]).point(lambda v: v * 0.6)
    img.alpha_composite(solid((10, 6, 14), alpha))

    # gloss band on the top half
    g = rrect_mask((29, 28, 227, 121), 26).filter(ImageFilter.GaussianBlur(q(0.8)))
    fade = Image.linear_gradient("L").resize((S, S)).point(lambda v: 95 - v * 0.2)
    img.alpha_composite(solid((255, 255, 255), Image.composite(fade, Image.new("L", (S, S), 0), g)))
    return img


# ------------------------------------------------------------------ glyph helpers
def bezier(pts, n=40):
    out = []
    for i in range(n + 1):
        t = i / n
        tmp = [tuple(c) for c in pts]
        while len(tmp) > 1:
            tmp = [(tmp[j][0] + (tmp[j + 1][0] - tmp[j][0]) * t, tmp[j][1] + (tmp[j + 1][1] - tmp[j][1]) * t) for j in range(len(tmp) - 1)]
        out.append(tmp[0])
    return out


def path(start, segs):
    """segs: list of point lists (control points after the current point)."""
    pts, cur = [start], start
    for seg in segs:
        pts += bezier([cur] + seg)[1:]
        cur = seg[-1]
    return pts


def heart(cx, cy, s):
    pts = []
    for i in range(120):
        t = i / 120 * math.tau
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * s / 17, cy - y * s / 17))
    return pts


def shield(cx=0.5, top=0.17, w=0.46, bottom=0.84):
    l, r = cx - w / 2, cx + w / 2
    return path((cx, top), [
        [(cx - w * 0.2, top + 0.05), (l, top + 0.06)],
        [(l, top + 0.25)],
        [(l, top + 0.45), (cx - w * 0.2, bottom - 0.08), (cx, bottom)],
        [(cx + w * 0.2, bottom - 0.08), (r, top + 0.45), (r, top + 0.25)],
        [(r, top + 0.06)],
        [(cx + w * 0.2, top + 0.05), (cx, top)],
    ])


def star(cx, cy, ro, ri, n=4, rot=-math.pi / 2):
    return [(cx + (ro if i % 2 == 0 else ri) * math.cos(rot + i * math.pi / n),
             cy + (ro if i % 2 == 0 else ri) * math.sin(rot + i * math.pi / n)) for i in range(2 * n)]


class Layer:
    """One white shape (with holes) that gets its own dark outline."""

    def __init__(self):
        self.img = Image.new("RGBA", (S, S), CLEAR)
        self.d = ImageDraw.Draw(self.img)

    def poly(self, pts, hole=False):
        self.d.polygon([P(*v) for v in pts], fill=CLEAR if hole else WHITE)
        return self

    def line(self, pts, w, hole=False, joint="curve", caps=True):
        c = CLEAR if hole else WHITE
        self.d.line([P(*v) for v in pts], fill=c, width=int(w * S), joint=joint)
        if caps:
            for v in (pts[0], pts[-1]):
                self.circle(v[0], v[1], w / 2, hole)
        return self

    def circle(self, cx, cy, r, hole=False):
        self.d.ellipse([P(cx - r, cy - r), P(cx + r, cy + r)], fill=CLEAR if hole else WHITE)
        return self

    def ellipse(self, box, hole=False):
        self.d.ellipse([P(box[0], box[1]), P(box[2], box[3])], fill=CLEAR if hole else WHITE)
        return self

    def arc(self, cx, cy, r, a0, a1, w, hole=False):
        pts = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
               for a in [a0 + (a1 - a0) * i / 60 for i in range(61)]]
        return self.line(pts, w, hole)


def stamp(img, layers):
    """Composite glyph layers: drop shadow, dark outline, white fill each."""
    for lay in layers:
        a = lay.img.getchannel("A")
        outline = a.filter(ImageFilter.MaxFilter(q(6) | 1))
        shadow = outline.filter(ImageFilter.GaussianBlur(q(2))).point(lambda v: v * 0.35)
        img.alpha_composite(solid((0, 0, 0), shadow), (0, q(2)))
        img.alpha_composite(solid(INK, outline))
        img.alpha_composite(lay.img)


# ------------------------------------------------------------------ modifiers
def outlined(img, pts, color):
    """Modifier shape: dark outline, white ring, flat color (like the originals)."""
    cx = sum(v[0] for v in pts) / len(pts)
    cy = sum(v[1] for v in pts) / len(pts)
    base = Image.new("L", (S, S), 0)
    ImageDraw.Draw(base).polygon([P(*v) for v in pts], fill=255)
    ring = base.filter(ImageFilter.MaxFilter(q(5) | 1))
    dark = ring.filter(ImageFilter.MaxFilter(q(6) | 1))
    shadow = dark.filter(ImageFilter.GaussianBlur(q(2))).point(lambda v: v * 0.35)
    img.alpha_composite(solid((0, 0, 0), shadow), (0, q(2)))
    img.alpha_composite(solid(INK, dark))
    img.alpha_composite(solid((255, 255, 255), ring))
    img.alpha_composite(solid(color, base))


def diamonds(img, n):
    xs = {1: [0.785], 2: [0.66, 0.79], 3: [0.535, 0.66, 0.785]}[n]
    for x in xs:
        outlined(img, [(x, 0.735), (x + 0.055, 0.8), (x, 0.865), (x - 0.055, 0.8)], YELLOW)


def arrow_pts(cx, top, bottom, w, up=True):
    hw, sw = w / 2, w * 0.24
    head = top + (bottom - top) * 0.5
    pts = [(cx, top), (cx + hw, head), (cx + sw, head), (cx + sw, bottom), (cx - sw, bottom), (cx - sw, head), (cx - hw, head)]
    if not up:
        mid = (top + bottom) / 2
        pts = [(x, 2 * mid - y) for x, y in pts]
    return pts


def arrows(img, n, up):
    color = GREEN_ARROW if up else RED_ARROW
    if n == 1:
        outlined(img, arrow_pts(0.775, 0.595, 0.895, 0.25, up), color)
    else:
        for cx in (0.7, 0.845):
            outlined(img, arrow_pts(cx, 0.62, 0.895, 0.2, up), color)


# ------------------------------------------------------------------ glyphs
def g_regen():
    cx, cy, r, a0, a1 = 0.5, 0.5, 0.3, 160, 395
    ring = Layer().arc(cx, cy, r, a0, a1, 0.06)
    e = math.radians(a1)
    end = (cx + r * math.cos(e), cy + r * math.sin(e))
    tan = (-math.sin(e), math.cos(e))  # direction of travel (clockwise on screen)
    nrm = (math.cos(e), math.sin(e))
    ring.poly([(end[0] + tan[0] * 0.1, end[1] + tan[1] * 0.1),
               (end[0] + nrm[0] * 0.08, end[1] + nrm[1] * 0.08),
               (end[0] - nrm[0] * 0.08, end[1] - nrm[1] * 0.08)])
    h = Layer().poly(heart(0.5, 0.5, 0.17))
    h.poly([(0.475, 0.4), (0.525, 0.4), (0.525, 0.455), (0.58, 0.455), (0.58, 0.505), (0.525, 0.505), (0.525, 0.56),
            (0.475, 0.56), (0.475, 0.505), (0.42, 0.505), (0.42, 0.455), (0.475, 0.455)], hole=True)
    return [ring, h]


def g_vigor():
    return [Layer().poly(heart(0.45, 0.46, 0.3))]


def g_thorns():
    sh = Layer().poly(shield(top=0.2, w=0.5, bottom=0.82))
    # thorns pointing straight out from the shield's center
    for x, y in [(0.5, 0.21), (0.26, 0.26), (0.74, 0.26), (0.25, 0.47), (0.75, 0.47), (0.33, 0.69), (0.67, 0.69)]:
        dx, dy = x - 0.5, y - 0.5
        ln = math.hypot(dx, dy)
        dx, dy = dx / ln, dy / ln
        sh.poly([(x + dx * 0.1, y + dy * 0.1), (x - dy * 0.05 - dx * 0.03, y + dx * 0.05 - dy * 0.03),
                 (x + dy * 0.05 - dx * 0.03, y - dx * 0.05 - dy * 0.03)])
    sh.poly(shield(top=0.3, w=0.28, bottom=0.68), hole=True)
    return [sh]


def g_evade():
    f = Layer()
    outline = path((0.72, 0.16), [
        [(0.5, 0.2), (0.3, 0.42), (0.3, 0.62)],
        [(0.3, 0.7), (0.34, 0.74)],
        [(0.5, 0.74), (0.72, 0.5), (0.72, 0.16)],
    ])
    f.poly(outline)
    f.line(bezier([(0.34, 0.74), (0.5, 0.52), (0.62, 0.34), (0.7, 0.2)]), 0.018, hole=True, caps=False)
    for a, b in [((0.33, 0.47), (0.43, 0.52)), ((0.4, 0.33), (0.5, 0.4)), ((0.65, 0.5), (0.56, 0.52))]:
        f.line([a, b], 0.02, hole=True, caps=False)
    f.line([(0.34, 0.74), (0.22, 0.86)], 0.035)
    wind = Layer()
    for y, x0, x1 in [(0.58, 0.72, 0.86), (0.7, 0.64, 0.84), (0.46, 0.76, 0.86)]:
        wind.line([(x0, y), (x1, y)], 0.035)
    return [wind, f]


def g_immune():
    sh = Layer().poly(shield(top=0.15, w=0.54, bottom=0.86))
    sh.line([(0.37, 0.5), (0.47, 0.61), (0.66, 0.37)], 0.07, hole=True, joint="curve")
    return [sh]


def g_revive():
    wings = Layer()
    for sgn in (-1, 1):
        root = (0.5 + sgn * 0.1, 0.44)
        for ang, ln, w in ((35, 0.3, 0.075), (15, 0.28, 0.07), (-5, 0.23, 0.065), (-25, 0.17, 0.06)):
            a = math.radians(ang)
            tip = (root[0] + sgn * ln * math.cos(a), root[1] - ln * math.sin(a))
            wings.line([root, tip], w)
    h = Layer().poly(heart(0.5, 0.52, 0.2))
    return [wings, h]


def g_freeze():
    f = Layer()
    for i in range(6):
        a = math.radians(90 + i * 60)
        ca, sa = math.cos(a), math.sin(a)
        end = (0.5 + 0.33 * ca, 0.5 - 0.33 * sa)
        f.line([(0.5, 0.5), end], 0.055)
        for d in (0.17, 0.26):
            b = (0.5 + d * ca, 0.5 - d * sa)
            for side in (-1, 1):
                a2 = a + side * math.radians(45)
                f.line([b, (b[0] + 0.08 * math.cos(a2), b[1] - 0.08 * math.sin(a2))], 0.045)
    return [f]


def g_sleep():
    def z(x, y, sz, w):
        return [(x, y), (x + sz, y), (x + sz, y + w), (x + w * 1.6, y + sz - w), (x + sz, y + sz - w), (x + sz, y + sz),
                (x, y + sz), (x, y + sz - w), (x + sz - w * 1.6, y + w), (x, y + w)]
    return [Layer().poly(z(0.16, 0.5, 0.32, 0.075)), Layer().poly(z(0.5, 0.33, 0.22, 0.06)), Layer().poly(z(0.7, 0.18, 0.15, 0.05))]


def g_silence():
    b = Layer()
    b.d.rounded_rectangle([P(0.17, 0.2), P(0.83, 0.64)], radius=int(0.12 * S), fill=WHITE)
    b.poly([(0.3, 0.6), (0.44, 0.6), (0.26, 0.8)])
    for x in (0.35, 0.5, 0.65):
        b.circle(x, 0.42, 0.045, hole=True)
    slash = Layer().line([(0.2, 0.84), (0.82, 0.16)], 0.07)
    return [b, slash]


def g_blind():
    e = Layer()
    top = bezier([(0.14, 0.5), (0.32, 0.22), (0.68, 0.22), (0.86, 0.5)])
    bot = bezier([(0.86, 0.5), (0.68, 0.78), (0.32, 0.78), (0.14, 0.5)])
    e.poly(top + bot)
    e.circle(0.5, 0.5, 0.13, hole=True)
    pupil = Layer().circle(0.5, 0.5, 0.07)
    slash = Layer().line([(0.2, 0.82), (0.8, 0.18)], 0.07)
    return [e, pupil, slash]


def g_expose():
    sh = Layer().poly(shield(top=0.15, w=0.54, bottom=0.86))
    sh.line([(0.5, 0.13), (0.45, 0.3), (0.56, 0.42), (0.44, 0.57), (0.53, 0.7), (0.5, 0.88)], 0.045, hole=True, joint=None, caps=False)
    return [sh]


def g_confuse():
    sp = Layer()
    pts = []
    for i in range(200):
        t = i / 199 * 2.6 * math.tau
        r = 0.035 + 0.3 * t / (2.6 * math.tau)
        pts.append((0.5 + r * math.cos(t), 0.5 + r * math.sin(t)))
    sp.line(pts, 0.06)
    return [sp]


STATUSES = {
    # name: (kind, glyph, modifier)  - modifier: ("diamonds", n) / ("up", n) / ("down", n) / None
    "Regen": ("buff", g_regen, None),
    "Vigor": ("buff", g_vigor, ("up", 1)),
    "Thorns": ("buff", g_thorns, None),
    "Evade": ("buff", g_evade, None),
    "Immune": ("buff", g_immune, None),
    "Revive": ("buff", g_revive, None),
    "Freeze": ("debuff", g_freeze, None),
    "Sleep": ("debuff", g_sleep, None),
    "Silence": ("debuff", g_silence, None),
    "Blind": ("debuff", g_blind, None),
    "Expose": ("debuff", g_expose, None),
    "Confuse": ("debuff", g_confuse, None),
}


def render(kind, glyph, mod):
    img = tile(kind)
    stamp(img, glyph())
    if mod:
        if mod[0] == "diamonds":
            diamonds(img, mod[1])
        else:
            arrows(img, mod[1], mod[0] == "up")
    return img.resize((T, T), Image.LANCZOS)


def main():
    icons = {name: render(*spec) for name, spec in STATUSES.items()}
    for name, icon in icons.items():
        icon.save(os.path.join(HERE, f"{name}.png"))
    print("ok", len(icons))


if __name__ == "__main__":
    main()
