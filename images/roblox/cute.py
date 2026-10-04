"""Glossy 2D 'key art' pieces (SVG strings): a chibi baby dragon in any
element's colours (DragonDefs StageColors), an egg shell, a pile of coins,
and the defs (gradients, blur filters) they use. Shapes are drawn around a
local origin (feet at y = 0) and placed with transform="translate scale"."""


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def hexc(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(v))) for v in c)


def tone(h, k):
    """k > 1 lighter (towards white), k < 1 darker."""
    r, g, b = rgb(h)
    if k >= 1:
        t = k - 1
        return hexc((r + (255 - r) * t, g + (255 - g) * t, b + (255 - b) * t))
    return hexc((r * k, g * k, b * k))


# element palettes for babies (main from DragonDefs StageColors.Baby)
PALETTES = {
    "Fire": dict(main="#f2823b", belly="#ffd892", crest="#e2402a", crest2="#ffc84c", horn="#fff0d0", eye="#ffb830"),
    "Water": dict(main="#2e86d9", belly="#bfe6ff", crest="#1b5a9e", crest2="#6fd0ff", horn="#eaf6ff", eye="#ffcf3a"),
    "Nature": dict(main="#4caf50", belly="#e4f7b0", crest="#2e7d32", crest2="#a6e05a", horn="#fff6d6", eye="#ffb830"),
    "Electric": dict(main="#f0c428", belly="#fff6c8", crest="#c89614", crest2="#ffffff", horn="#fffbe8", eye="#4ab0ff"),
}
EGG = {"Fire": "#e8442a", "Water": "#1b5a9e", "Nature": "#2e7d32", "Electric": "#c89614"}


def grad(id_, c, light=1.35, dark=0.72, angle=(0.3, 0, 0.7, 1)):
    x1, y1, x2, y2 = angle
    return (f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
            f'<stop offset="0" stop-color="{tone(c, light)}"/><stop offset="0.55" stop-color="{c}"/>'
            f'<stop offset="1" stop-color="{tone(c, dark)}"/></linearGradient>')


def defs(element_list=("Fire",)):
    out = ['<defs>',
           '<filter id="blur8" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>',
           '<filter id="blur20" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="20"/></filter>',
           '<filter id="blur40" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="40"/></filter>',
           '<filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3"/></filter>',
           grad("gold", "#f7c234", 1.45, 0.7), grad("goldDark", "#d9951a", 1.2, 0.65)]
    for e in element_list:
        p = PALETTES[e]
        out += [grad(f"{e}Main", p["main"]), grad(f"{e}Belly", p["belly"], 1.25, 0.85), grad(f"{e}Crest", p["crest"], 1.3, 0.75),
                grad(f"{e}Egg", EGG[e], 1.5, 0.6),
                f'<radialGradient id="{e}Eye" cx="0.45" cy="0.6" r="0.6"><stop offset="0" stop-color="{tone(p["eye"], 1.5)}"/>'
                f'<stop offset="0.6" stop-color="{p["eye"]}"/><stop offset="1" stop-color="{tone(p["eye"], 0.55)}"/></radialGradient>']
    out.append('</defs>')
    return "".join(out)


def _p(d, fill, line, w=5, extra=""):
    return f'<path d="{d}" fill="{fill}" stroke="{line}" stroke-width="{w}" stroke-linejoin="round" {extra}/>'


def baby(e, flying=False):
    """Chibi baby facing a little to the right; feet at y = 0, ~520 tall."""
    p = PALETTES[e]
    line = tone(p["main"], 0.45)
    M, B, CR = f"url(#{e}Main)", f"url(#{e}Belly)", f"url(#{e}Crest)"
    o = []
    # wings (behind)
    wing_up = -60 if flying else 0
    for sx, x0 in ((-1, -60), (1, 70)):
        tipx = x0 + sx * (190 if flying else 120)
        o.append(_p(f"M{x0} -250 C{x0 + sx * 40} {-330 + wing_up} {tipx - sx * 30} {-380 + wing_up} {tipx} {-370 + wing_up} "
                    f"C{tipx - sx * 10} {-330 + wing_up} {tipx - sx * 5} {-300 + wing_up} {tipx - sx * 20} {-270 + wing_up / 2} "
                    f"C{tipx - sx * 45} {-280 + wing_up / 2} {tipx - sx * 55} {-260} {tipx - sx * 70} {-235} "
                    f"C{x0 + sx * 50} -240 {x0 + sx * 20} -220 {x0} -210 Z", CR, line))
    # tail curling round to the front
    o.append(_p("M-90 -70 C-180 -60 -200 0 -150 25 C-100 45 -10 30 40 10 C0 20 -110 25 -140 0 C-165 -25 -140 -55 -80 -45 Z", M, line))
    o.append(_p("M40 10 l22 -26 l4 34 Z", CR, line, 4))
    # body
    o.append(_p("M-115 -150 C-125 -240 -60 -270 10 -268 C90 -266 135 -220 125 -140 C118 -60 80 -10 5 -8 C-75 -6 -110 -60 -115 -150 Z", M, line))
    o.append(_p("M-55 -200 C-30 -235 50 -235 75 -195 C95 -140 85 -55 15 -35 C-50 -35 -75 -120 -55 -200 Z", B, line, 4))
    for y in (-185, -150, -115, -80):
        o.append(f'<path d="M{-50 + abs(y + 130) * 0.15} {y} Q15 {y + 14} {78 - abs(y + 130) * 0.2} {y}" fill="none" stroke="{tone(p["belly"], 0.7)}" stroke-width="4" stroke-linecap="round"/>')
    # feet with toes
    for fx, fy in ((-70, -18), (75, -14)):
        o.append(_p(f"M{fx - 48} {fy + 10} C{fx - 50} {fy - 40} {fx + 45} {fy - 42} {fx + 48} {fy + 8} C{fx + 30} {fy + 22} {fx - 30} {fy + 24} {fx - 48} {fy + 10} Z", M, line))
        for k in (-28, 0, 28):
            o.append(f'<ellipse cx="{fx + k}" cy="{fy + 14}" rx="11" ry="8" fill="{p["horn"]}" stroke="{line}" stroke-width="3"/>')
    # arms
    for ax, ay, r in ((-60, -150, -25), (70, -150, 25)):
        o.append(_p(f"M{ax} {ay - 25} C{ax + 30} {ay - 20} {ax + 32} {ay + 30} {ax + 5} {ay + 40} C{ax - 25} {ay + 35} {ax - 30} {ay - 10} {ax} {ay - 25} Z", M, line, 4))
    # head
    o.append(_p("M-150 -360 C-160 -470 -60 -540 40 -535 C150 -530 210 -460 205 -390 C235 -380 260 -350 250 -310 "
                "C240 -270 200 -255 160 -258 C110 -245 40 -240 -20 -248 C-110 -258 -145 -300 -150 -360 Z", M, line))
    # snout / chin light
    o.append(_p("M70 -300 C120 -305 200 -300 245 -320 C250 -290 230 -265 190 -262 C140 -255 90 -258 70 -275 Z", B, line, 4))
    o.append(f'<path d="M110 -282 Q170 -268 225 -290" fill="none" stroke="{line}" stroke-width="5" stroke-linecap="round"/>')
    o.append(f'<ellipse cx="222" cy="-338" rx="7" ry="5" fill="{line}"/>')
    # horns + crest
    for d in ("M-60 -505 C-80 -560 -110 -585 -140 -590 C-120 -560 -110 -530 -100 -490 Z",
              "M10 -530 C10 -590 -5 -625 -30 -645 C-15 -610 -15 -575 -25 -528 Z"):
        o.append(_p(d, p["horn"], line, 4))
    for d in ("M-140 -420 C-200 -440 -220 -500 -210 -540 C-185 -500 -160 -480 -125 -470 Z",
              "M-120 -470 C-170 -520 -170 -575 -150 -610 C-140 -560 -115 -530 -90 -510 Z"):
        o.append(_p(d, CR, line, 4))
    # cheek blush
    o.append(f'<ellipse cx="150" cy="-300" rx="26" ry="14" fill="#ff7a7a" opacity="0.35"/>')
    # eyes: big glossy (near one big, far one narrower)
    for cx, cy, rx, ry in ((40, -395, 52, 62), (160, -400, 32, 56)):
        o.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx + 6}" ry="{ry + 6}" fill="#fff" stroke="{line}" stroke-width="5"/>')
        o.append(f'<ellipse cx="{cx + rx * 0.12}" cy="{cy + 6}" rx="{rx * 0.92}" ry="{ry * 0.92}" fill="url(#{e}Eye)"/>')
        o.append(f'<ellipse cx="{cx + rx * 0.2}" cy="{cy + 10}" rx="{rx * 0.52}" ry="{ry * 0.6}" fill="#2a1408"/>')
        o.append(f'<ellipse cx="{cx - rx * 0.25}" cy="{cy - ry * 0.35}" rx="{rx * 0.32}" ry="{ry * 0.26}" fill="#fff"/>')
        o.append(f'<circle cx="{cx + rx * 0.4}" cy="{cy + ry * 0.4}" r="{rx * 0.13}" fill="#fff"/>')
    o.append(f'<path d="M-5 -470 Q40 -490 90 -468" fill="none" stroke="{line}" stroke-width="7" stroke-linecap="round"/>')
    # gloss on the head
    o.append('<ellipse cx="-40" cy="-470" rx="70" ry="30" fill="#fff" opacity="0.28" transform="rotate(-20 -40 -470)"/>')
    return "".join(o)


def egg_shell_back(e, w=330):
    """Back half of a broken egg (drawn behind the baby)."""
    line = tone(EGG[e], 0.4)
    h = w * 0.62
    return _p(f"M{-w / 2} 0 C{-w / 2} {-h * 0.9} {-w * 0.3} {-h * 1.25} 0 {-h * 1.28} C{w * 0.3} {-h * 1.25} {w / 2} {-h * 0.9} {w / 2} 0 Z",
              f"url(#{e}Egg)", line, 5) + f'<path d="M{-w / 2 + 25} {-h * 0.7} L{w / 2 - 25} {-h * 0.7}" stroke="{tone(EGG[e], 0.6)}" stroke-width="0"/>'


def egg_shell_front(e, w=360):
    """Front half of the broken egg: jagged top edge, spots, gloss."""
    line = tone(EGG[e], 0.4)
    h = w * 0.55
    jag = []
    n = 9
    for i in range(n + 1):
        x = -w / 2 + w * i / n
        y = -h * (0.55 if i % 2 else 0.85) - (0 if i in (0, n) else 0)
        jag.append(f"L{x:.1f} {y:.1f}")
    d = (f"M{-w / 2} {-h * 0.7} " + " ".join(jag) +
         f" L{w / 2} {-h * 0.7} C{w / 2} {-h * 0.1} {w * 0.3} {h * 0.25} 0 {h * 0.28} C{-w * 0.3} {h * 0.25} {-w / 2} {-h * 0.1} {-w / 2} {-h * 0.7} Z")
    o = _p(d, f"url(#{e}Egg)", line, 6)
    for x, y, r in ((-90, -60, 22), (60, -30, 18), (-20, 20, 14), (110, -95, 12), (-130, -110, 10)):
        o += f'<circle cx="{x}" cy="{y}" r="{r}" fill="{tone(EGG[e], 1.5)}" opacity="0.55"/>'
    o += f'<path d="M{-w * 0.36} {-h * 0.3} Q{-w * 0.3} {h * 0.05} {-w * 0.1} {h * 0.16}" fill="none" stroke="#fff" stroke-width="10" opacity="0.35" stroke-linecap="round"/>'
    return o


def coins(cx, cy, n=60, spread=430, seed=3):
    """A heap of gold coins: ellipses stacked in a mound, back to front."""
    import random
    r = random.Random(seed)
    items = []
    for _ in range(n):
        u = r.uniform(-1, 1)
        x = cx + u * spread / 2
        y = cy - (1 - u * u) * 150 + r.uniform(-15, 25)
        items.append((y, x, r.uniform(-25, 25), 0))
    items.sort()
    o = []
    for y, x, rot, edge in items:
        if edge:  # a coin seen edge-on
            o.append(f'<g transform="translate({x:.1f} {y:.1f}) rotate({rot + 60:.1f})"><rect x="-38" y="-9" width="76" height="18" rx="9" fill="url(#goldDark)" stroke="#8a5a10" stroke-width="3"/></g>')
        else:
            o.append(f'<g transform="translate({x:.1f} {y:.1f}) rotate({rot:.1f})">'
                     f'<ellipse cx="0" cy="5" rx="42" ry="20" fill="#b07818" stroke="#8a5a10" stroke-width="3"/>'
                     f'<ellipse cx="0" cy="0" rx="42" ry="20" fill="url(#gold)" stroke="#8a5a10" stroke-width="3"/>'
                     f'<ellipse cx="0" cy="0" rx="28" ry="12" fill="none" stroke="#fff3b0" stroke-width="3" opacity="0.7"/></g>')
    return "".join(o)


def bokeh(w, h, n=26, seed=9, colors=("#ffffff", "#c8f0ff", "#9fe3ff")):
    import random
    r = random.Random(seed)
    return "".join(f'<circle cx="{r.uniform(0, w):.0f}" cy="{r.uniform(0, h):.0f}" r="{r.uniform(20, 90):.0f}" '
                   f'fill="{r.choice(colors)}" opacity="{r.uniform(0.12, 0.35):.2f}" filter="url(#blur8)"/>' for _ in range(n))


def sparkle(x, y, s, color="#fff"):
    return (f'<path d="M{x} {y - 30 * s} Q{x + 4 * s} {y - 4 * s} {x + 30 * s} {y} Q{x + 4 * s} {y + 4 * s} {x} {y + 30 * s} '
            f'Q{x - 4 * s} {y + 4 * s} {x - 30 * s} {y} Q{x - 4 * s} {y - 4 * s} {x} {y - 30 * s} Z" fill="{color}" opacity="0.9"/>')
