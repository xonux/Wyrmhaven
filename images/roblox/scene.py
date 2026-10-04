"""2D (flat vector) Roblox icon and thumbnail, coherent with the game:
Fire dragons in DragonBuilder's Fire palette (dragons.py), habitat platforms
in HabitatDefs.PlatformColor, eggs in DragonDefs egg colours, baby / adult /
egg sizes in the game's ratios (3.65 / 5.5 / 2.6 studs tall).
Writes Thumbnail.svg (1920x1080) and Icon.svg (1024x1024); render.sh turns
them into PNGs."""
import math
import os
import random

import dragons as D

HERE = os.path.dirname(os.path.abspath(__file__))
PLATFORM = {"Fire": "#d6794c", "Water": "#5e8aa8", "Nature": "#6b9e6e", "Electric": "#c4ac5a"}
EGG = {"Water": "#1b5a9e", "Nature": "#2e7d32", "Electric": "#c89614", "Dark": "#3a2456", "Light": "#dccea0"}
LINE = "#3e2a1e"
rnd = random.Random(5)


def shade(hexc, k):
    r, g, b = (int(hexc[i:i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(v * k))) for v in (r, g, b))


def poly(pts, fill, stroke=LINE, sw=4):
    return f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in pts)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round"/>'


def platform(cx, cy, w, color):
    """An isometric slab: top diamond + two side faces."""
    h, t = w * 0.42, w * 0.07
    top = [(cx, cy - h / 2), (cx + w / 2, cy), (cx, cy + h / 2), (cx - w / 2, cy)]
    left = [(cx - w / 2, cy), (cx, cy + h / 2), (cx, cy + h / 2 + t), (cx - w / 2, cy + t)]
    right = [(cx + w / 2, cy), (cx, cy + h / 2), (cx, cy + h / 2 + t), (cx + w / 2, cy + t)]
    return poly(left, shade(color, 0.72)) + poly(right, shade(color, 0.58)) + poly(top, color)


def rock(x, y, s, color="#8a8478"):
    pts = [(x - 40 * s, y), (x - 30 * s, y - 30 * s), (x, y - 42 * s), (x + 32 * s, y - 28 * s), (x + 42 * s, y)]
    return poly(pts, color) + poly([(x, y - 42 * s), (x + 32 * s, y - 28 * s), (x + 42 * s, y), (x + 5 * s, y)], shade(color, 0.8), sw=0)


def tree(x, y, s):
    out = poly([(x - 9 * s, y), (x - 6 * s, y - 70 * s), (x + 6 * s, y - 70 * s), (x + 9 * s, y)], "#6b4a2e")
    for dx, dy, r, c in ((-28, -95, 46, "#3f9a3a"), (26, -100, 42, "#358a34"), (0, -135, 48, "#4fb046")):
        pts = [(x + (dx + r * math.cos(a)) * s, y + (dy + r * math.sin(a)) * s) for a in [k * math.pi / 4 + 0.2 for k in range(8)]]
        out += poly(pts, c)
    return out


def volcano(x, y, s):
    out = poly([(x - 120 * s, y), (x - 35 * s, y - 190 * s), (x + 35 * s, y - 190 * s), (x + 120 * s, y)], "#5a3a32")
    out += poly([(x, y - 190 * s), (x + 35 * s, y - 190 * s), (x + 120 * s, y), (x + 10 * s, y)], "#4a2e28", sw=0)
    out += poly([(x - 35 * s, y - 190 * s), (x + 35 * s, y - 190 * s), (x + 22 * s, y - 175 * s), (x - 22 * s, y - 175 * s)], "#ff8a1e")
    out += f'<circle cx="{x}" cy="{y - 205 * s}" r="{60 * s}" fill="#ffb347" opacity="0.25"/>'
    return out


def crystal(x, y, h, w):
    return (poly([(x, y - h), (x + w, y - h * 0.5), (x, y), (x - w, y - h * 0.5)], "#ffe14a")
            + poly([(x, y - h), (x + w, y - h * 0.5), (x, y)], "#e0b820", sw=0))


def egg(x, y, s, color):
    d = (f"M{x} {y - 130 * s} C{x + 62 * s} {y - 130 * s} {x + 78 * s} {y - 40 * s} {x + 70 * s} {y - 15 * s} "
         f"C{x + 60 * s} {y + 12 * s} {x - 60 * s} {y + 12 * s} {x - 70 * s} {y - 15 * s} "
         f"C{x - 78 * s} {y - 40 * s} {x - 62 * s} {y - 130 * s} {x} {y - 130 * s} Z")
    out = f'<path d="{d}" fill="{color}" stroke="{LINE}" stroke-width="4"/>'
    out += f'<clipPath id="e{x:.0f}"><path d="{d}"/></clipPath><rect x="{x}" y="{y - 140 * s}" width="{90 * s}" height="{160 * s}" fill="#000" opacity="0.18" clip-path="url(#e{x:.0f})"/>'
    for dx, dy, r in ((-25, -80, 11), (20, -55, 9), (-10, -35, 7), (28, -95, 6)):
        out += f'<circle cx="{x + dx * s}" cy="{y + dy * s}" r="{r * s}" fill="#fff" opacity="0.35"/>'
    out += f'<path d="{d}" fill="none" stroke="{LINE}" stroke-width="4"/>'
    return out


def cloud(x, y, s):
    return "".join(f'<ellipse cx="{x + dx * s}" cy="{y + dy * s}" rx="{rx * s}" ry="{ry * s}" fill="#ffffff" opacity="0.92"/>'
                   for dx, dy, rx, ry in ((0, 0, 90, 38), (-70, 12, 60, 28), (75, 10, 66, 30), (20, -28, 60, 34)))


def sky_defs(top, bottom):
    return (f'<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/>'
            f'<stop offset="1" stop-color="{bottom}"/></linearGradient>'
            f'<linearGradient id="sea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4cc6dc"/>'
            f'<stop offset="1" stop-color="#1e8fbf"/></linearGradient>'
            f'<radialGradient id="sun" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fff6c8"/>'
            f'<stop offset="1" stop-color="#fff6c8" stop-opacity="0"/></radialGradient></defs>')


def thumbnail():
    W, H = 1920, 1080
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', sky_defs("#57b3ea", "#cdeefa")]
    o.append(f'<rect width="{W}" height="{H}" fill="url(#sky)"/>')
    o.append(f'<circle cx="1640" cy="170" r="260" fill="url(#sun)"/>')
    for x, y, s in ((1180, 140, 1.0), (1560, 300, 0.75), (860, 250, 0.6), (1820, 110, 0.6)):
        o.append(cloud(x, y, s))
    # sea + far waves
    o.append(f'<rect y="520" width="{W}" height="{H - 520}" fill="url(#sea)"/>')
    for k in range(10):
        y = 545 + k * 22
        x = (k * 337) % 1700
        o.append(f'<path d="M{x} {y} q30 -10 60 0" stroke="#bdf0f6" stroke-width="4" fill="none" stroke-linecap="round" opacity="0.7"/>')
    # mountains behind the island (right, keeping the sky top-left free for the logo)
    for pts, c in (([(980, 600), (1240, 330), (1470, 600)], "#8f8778"), ([(1300, 610), (1520, 400), (1760, 610)], "#7f786c")):
        o.append(poly(pts, c))
        o.append(poly([pts[1], pts[2], ((pts[1][0] + pts[2][0]) / 2 - 40, pts[2][1])], shade(c, 0.82), sw=0))
    # island: sand rim, grass plateau, cliff front visible on the sides
    shore = [(-50, 640), (200, 600), (520, 585), (900, 575), (1300, 590), (1650, 600), (1980, 630), (1980, 1100), (-50, 1100)]
    o.append(poly([(x, y - 22) for x, y in shore], "#e8d39a", sw=0))
    o.append(poly(shore, "#6cbf4a", sw=0))
    o.append(f'<path d="M-50 640 L200 600 L520 585 L900 575 L1300 590 L1650 600 L1980 630" stroke="#4f9a36" stroke-width="6" fill="none"/>')
    # back row of habitats
    o.append(platform(420, 690, 300, PLATFORM["Water"]))
    o.append(f'<ellipse cx="420" cy="690" rx="105" ry="40" fill="#2f8fd6" stroke="{LINE}" stroke-width="4"/>')
    for a in range(0, 360, 45):
        o.append(rock(420 + 120 * math.cos(math.radians(a)), 700 + 48 * math.sin(math.radians(a)), 0.32, "#9aa6ae"))
    o.append(platform(800, 650, 260, PLATFORM["Nature"]))
    o.append(tree(760, 660, 0.7) + tree(840, 640, 0.6))
    o.append(platform(1560, 700, 300, PLATFORM["Electric"]))
    o.append(crystal(1520, 700, 120, 26) + crystal(1580, 690, 160, 32) + crystal(1630, 715, 90, 22))
    # farm on the left
    o.append(platform(250, 860, 330, "#7a5232"))
    for r in range(3):
        for c in range(4):
            x = 250 + (c - r) * 38
            y = 860 + (c + r - 2.5) * 16
            o.append(poly([(x, y - 30), (x + 14, y), (x - 14, y)], "#8ccf3c" if (r + c) % 2 else "#f2b632", sw=3))
    # trees around
    for x, y, s in ((110, 700, 0.9), (1080, 640, 0.75), (1830, 760, 0.95), (1750, 980, 1.1)):
        o.append(tree(x, y, s))
    # Fire habitat up front with its volcano, then the dragons
    o.append(platform(1130, 905, 820, PLATFORM["Fire"]))
    for x0, y0, x1, y1 in ((960, 930, 1060, 960), (1250, 880, 1350, 900), (1150, 990, 1230, 1010)):
        o.append(f'<path d="M{x0} {y0} L{x1} {y1}" stroke="#ff8a1e" stroke-width="7" stroke-linecap="round"/>')
    o.append(volcano(1310, 800, 1.15))
    o.append(rock(860, 900, 0.55, "#4a3530") + rock(1440, 930, 0.5, "#4a3530"))
    o.append(f'<g transform="translate(1010 960) scale(0.72)">{D.adult("ta")}</g>')
    o.append(f'<g transform="translate(1420 1000) scale(0.74)">{D.baby("tb")}</g>')
    # nest of eggs of other elements, front left
    o.append(f'<ellipse cx="560" cy="1010" rx="175" ry="52" fill="#b08a52" stroke="{LINE}" stroke-width="4"/>')
    o.append(f'<ellipse cx="560" cy="1002" rx="140" ry="32" fill="#8a6a3a"/>')
    # an egg is ~2.6 studs tall against the adult's 5.5: about half its height
    for x, y, c in ((468, 1000, "Water"), (652, 1000, "Electric"), (560, 1018, "Nature")):
        o.append(egg(x, y, 0.72, EGG[c]))
    o.append('</svg>')
    return "".join(o)


def icon():
    S = 1024
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">', sky_defs("#3fa6e6", "#bfe9ff")]
    o.append(f'<rect width="{S}" height="{S}" fill="url(#sky)"/>')
    o.append(f'<circle cx="640" cy="330" r="420" fill="url(#sun)"/>')
    o.append(cloud(200, 180, 1.0) + cloud(880, 120, 0.7))
    o.append(poly([(-20, 760), (300, 700), (700, 690), (1050, 730), (1050, 1050), (-20, 1050)], "#6cbf4a", sw=0))
    o.append(platform(560, 900, 1150, PLATFORM["Fire"]))
    o.append(f'<g transform="translate(240 1050) scale(1.58)">{D.adult("ia")}</g>')
    o.append('</svg>')
    return "".join(o)


def main():
    open(os.path.join(HERE, "Thumbnail.svg"), "w").write(thumbnail())
    open(os.path.join(HERE, "Icon.svg"), "w").write(icon())
    print("svg ok")


if __name__ == "__main__":
    main()
