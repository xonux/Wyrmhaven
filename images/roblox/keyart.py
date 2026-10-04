"""Glossy 2D key art for the Roblox page, in the spirit of the reference
mobile-game art, with Wyrmhaven's own content. Writes Icon.svg (1024) and
Thumbnail.svg (1920x1080); compose.py renders them and adds the logo."""
import os

import cute as K

HERE = os.path.dirname(os.path.abspath(__file__))


def icon():
    S = 1024
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">', K.defs(("Fire",)),
         '<radialGradient id="bg" cx="0.5" cy="0.42" r="0.75"><stop offset="0" stop-color="#bff0ff"/>'
         '<stop offset="0.45" stop-color="#4bb8f0"/><stop offset="1" stop-color="#1a5fb8"/></radialGradient>']
    o.append(f'<rect width="{S}" height="{S}" fill="url(#bg)"/>')
    o.append(K.bokeh(S, S, 30))
    o.append('<circle cx="512" cy="430" r="330" fill="#fff6c8" opacity="0.45" filter="url(#blur40)"/>')
    for x, y, s in ((170, 210, 1.0), (860, 300, 0.8), (800, 140, 0.55), (230, 520, 0.6)):
        o.append(K.sparkle(x, y, s))
    # coins, egg back, baby, egg front
    o.append(K.coins(512, 1000, 90, 1000, seed=4))
    o.append('<g transform="translate(512 820)">' + K.egg_shell_back("Fire", 500) + '</g>')
    o.append('<g transform="translate(498 830) scale(1.3)">' + K.baby("Fire") + '</g>')
    o.append('<g transform="translate(512 850)">' + K.egg_shell_front("Fire", 560) + '</g>')
    o.append(K.coins(512, 1060, 40, 1150, seed=7))
    o.append('</svg>')
    return "".join(o)


def glossy_adult(uid):
    """The adult Fire dragon of dragons.py, flat fills swapped for the glossy
    gradients (and its hard shade halves blended away)."""
    import dragons as D
    svg = D.adult(uid)
    for flat, g in (("#f2823b", "url(#FireMain)"), ("#c9502a", "url(#FireMain)"), ("#ffd892", "url(#FireBelly)"),
                    ("#f0bb6e", "url(#FireBelly)"), ("#e85e30", "url(#FireCrest)"), ("#b8401f", "url(#FireCrest)")):
        svg = svg.replace(f'fill="{flat}"', f'fill="{g}"')
    return svg


def whole_egg(x, y, s, e):
    line = K.tone(K.EGG[e], 0.4)
    d = (f"M{x} {y - 150 * s} C{x + 75 * s} {y - 150 * s} {x + 95 * s} {y - 50 * s} {x + 85 * s} {y - 15 * s} "
         f"C{x + 72 * s} {y + 18 * s} {x - 72 * s} {y + 18 * s} {x - 85 * s} {y - 15 * s} "
         f"C{x - 95 * s} {y - 50 * s} {x - 75 * s} {y - 150 * s} {x} {y - 150 * s} Z")
    o = f'<ellipse cx="{x}" cy="{y + 8 * s}" rx="{80 * s}" ry="{16 * s}" fill="#2a5a1a" opacity="0.3" filter="url(#soft)"/>'
    o += f'<path d="{d}" fill="url(#{e}Egg)" stroke="{line}" stroke-width="5"/>'
    for dx, dy, r in ((-30, -95, 14), (25, -60, 11), (-15, -35, 9), (35, -110, 7)):
        o += f'<circle cx="{x + dx * s}" cy="{y + dy * s}" r="{r * s}" fill="{K.tone(K.EGG[e], 1.5)}" opacity="0.6"/>'
    o += f'<ellipse cx="{x - 30 * s}" cy="{y - 105 * s}" rx="{16 * s}" ry="{30 * s}" fill="#fff" opacity="0.35" transform="rotate(20 {x - 30 * s} {y - 105 * s})"/>'
    return o


def blob_tree(x, y, s, c="#4fae3e"):
    o = f'<ellipse cx="{x}" cy="{y + 4}" rx="{70 * s}" ry="{14 * s}" fill="#2a5a1a" opacity="0.3" filter="url(#soft)"/>'
    o += f'<rect x="{x - 9 * s}" y="{y - 70 * s}" width="{18 * s}" height="{72 * s}" rx="6" fill="#7a5232"/>'
    for dx, dy, r in ((-40, -100, 55), (40, -105, 52), (0, -150, 62)):
        o += f'<circle cx="{x + dx * s}" cy="{y + dy * s}" r="{r * s}" fill="url(#leaf)"/>'
    o += f'<circle cx="{x - 20 * s}" cy="{y - 175 * s}" r="{22 * s}" fill="#fff" opacity="0.18"/>'
    return o


def cloud(x, y, s):
    return "".join(f'<ellipse cx="{x + dx * s}" cy="{y + dy * s}" rx="{rx * s}" ry="{ry * s}" fill="#fff" opacity="0.95"/>'
                   for dx, dy, rx, ry in ((0, 0, 160, 70), (-130, 25, 110, 55), (140, 20, 120, 58), (40, -60, 110, 70), (-60, -40, 80, 50)))


def thumbnail():
    W, H = 1920, 1080
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         K.defs(("Fire", "Water", "Nature")),
         '<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4fb2ee"/>'
         '<stop offset="0.7" stop-color="#bfe8fb"/><stop offset="1" stop-color="#e8f8ff"/></linearGradient>'
         '<linearGradient id="hill1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a8de78"/><stop offset="1" stop-color="#6cbf4a"/></linearGradient>'
         '<linearGradient id="hill2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8ccf5a"/><stop offset="1" stop-color="#4a9a34"/></linearGradient>'
         '<linearGradient id="mount" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a9c9e2"/><stop offset="1" stop-color="#cfe6f4"/></linearGradient>'
         '<radialGradient id="leaf" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#9fe06a"/><stop offset="1" stop-color="#3f8f30"/></radialGradient></defs>']
    o.append(f'<rect width="{W}" height="{H}" fill="url(#sky)"/>')
    o.append(f'<g filter="url(#blur8)">{cloud(260, 170, 1.0)}{cloud(1640, 230, 1.1)}{cloud(980, 120, 0.7)}</g>')
    # far mountains with snow, in haze
    for x, h, w in ((560, 360, 520), (900, 300, 460), (1300, 380, 560)):
        o.append(f'<path d="M{x - w / 2} 760 L{x - w * 0.08} {760 - h} L{x + w * 0.06} {760 - h + 20} L{x + w / 2} 760 Z" fill="url(#mount)"/>')
        o.append(f'<path d="M{x - w * 0.18} {760 - h * 0.62} L{x - w * 0.08} {760 - h} L{x + w * 0.06} {760 - h + 20} L{x + w * 0.16} {760 - h * 0.6} '
                 f'L{x + w * 0.02} {760 - h * 0.7} Z" fill="#fff" opacity="0.9"/>')
    # rolling hills
    o.append(f'<path d="M0 760 C300 690 600 720 900 740 C1200 700 1500 690 1920 740 L1920 1080 L0 1080 Z" fill="url(#hill1)"/>')
    for x, y, s in ((120, 790, 0.7), (760, 770, 0.55), (1150, 760, 0.6), (1820, 790, 0.75), (1560, 780, 0.5)):
        o.append(blob_tree(x, y, s))
    o.append(f'<path d="M0 900 C400 840 800 880 1100 900 C1400 870 1700 860 1920 890 L1920 1080 L0 1080 Z" fill="url(#hill2)"/>')
    o.append(K.bokeh(W, 600, 14, seed=2, colors=("#ffffff",)))
    # adult Fire dragon on the left, Water baby on the right (2/3 of the adult's height, as in game)
    o.append('<ellipse cx="420" cy="1040" rx="330" ry="40" fill="#1e4a12" opacity="0.35" filter="url(#blur8)"/>')
    o.append(f'<g transform="translate(470 1040) scale(1.25)">{glossy_adult("ta")}</g>')
    o.append('<ellipse cx="1470" cy="1030" rx="200" ry="34" fill="#1e4a12" opacity="0.35" filter="url(#blur8)"/>')
    o.append(f'<g transform="translate(1470 1030) scale(0.74)">{K.baby("Water")}</g>')
    o.append(whole_egg(1760, 1040, 0.95, "Fire"))
    o.append(whole_egg(1180, 1050, 0.7, "Nature"))
    # a Nature baby flying top right
    o.append(f'<g transform="translate(1640 560) rotate(-12) scale(0.42)">{K.baby("Nature", flying=True)}</g>')
    for x, y, s in ((1250, 420, 0.8), (1820, 380, 0.6), (330, 380, 0.6), (1080, 640, 0.5)):
        o.append(K.sparkle(x, y, s))
    # grass tufts in front
    import random
    r = random.Random(3)
    for _ in range(40):
        x, y = r.uniform(0, W), r.uniform(1010, 1085)
        o.append(f'<path d="M{x - 12} {y} Q{x - 6} {y - 34} {x} {y - 40} Q{x + 4} {y - 20} {x + 12} {y} Z" fill="#3f8f2c"/>')
    o.append('</svg>')
    return "".join(o)


def main():
    open(os.path.join(HERE, "Icon.svg"), "w").write(icon())
    open(os.path.join(HERE, "Thumbnail.svg"), "w").write(thumbnail())
    print("ok")


if __name__ == "__main__":
    main()
