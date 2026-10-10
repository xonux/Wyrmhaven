"""Rank badges (Bronze, Silver, Gold, Diamond, Master): a metal heater shield
with an embossed dragon head, getting richer with each rank - wings from
Silver, laurels and a star from Gold, a crystal shield from Diamond, a crown
and flames for Master - and a ribbon with 1 to 5 stars. SVG -> PNG through
headless Chromium (render_svg.cjs). Output: <Rank>.png (512, transparent),
_preview.png."""
import math
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
NODE_PATH = os.path.join(HERE, "..", "roblox", "node_modules")

RANKS = [
    # name, metal (light, mid, dark), field (light, dark), gem, ribbon
    ("Bronze", ("#ffd9b0", "#c9803f", "#6a3612"), ("#7a4524", "#3e1d0b"), None, "#8a4a22"),
    ("Silver", ("#ffffff", "#bcc6d2", "#56657a"), ("#3f5470", "#1a2638"), "#5fb4ff", "#4e6a8e"),
    ("Gold", ("#fff6c0", "#f2b632", "#8a5408"), ("#a4321c", "#4e0f08"), "#ff4a3a", "#b32a1c"),
    ("Diamond", ("#f2feff", "#7fdcf7", "#1d5f9e"), ("#1c5aa8", "#0a1f4a"), "#e8fbff", "#1f6fc0"),
    ("Master", ("#fff6c0", "#f2b632", "#8a5408"), ("#6a2aa8", "#240a40"), "#ff3f8e", "#6a1f9e"),
]


def metal(id_, light, mid, dark):
    return (f'<linearGradient id="{id_}" x1="0" y1="0" x2="0.25" y2="1">'
            f'<stop offset="0" stop-color="{light}"/><stop offset="0.42" stop-color="{mid}"/>'
            f'<stop offset="0.5" stop-color="{dark}"/><stop offset="0.62" stop-color="{mid}"/>'
            f'<stop offset="1" stop-color="{dark}"/></linearGradient>')


SHIELD = "M126 128 Q256 84 386 128 L386 238 Q386 368 256 430 Q126 368 126 238 Z"


def scaled(path, k, cx=256, cy=256):
    """Scale an absolute M/Q/L/Z path about (cx, cy)."""
    out, nums = [], path.replace("M", " M ").replace("Q", " Q ").replace("L", " L ").replace("Z", " Z ").split()
    i = 0
    toks = []
    for t in nums:
        toks.append(t)
    res = []
    coord = []
    for t in toks:
        if t in "MQLZ":
            res.append(t)
        else:
            coord.append(float(t))
            if len(coord) == 2:
                x, y = coord
                res.append(f"{cx + (x - cx) * k:.1f} {cy + (y - cy) * k:.1f}")
                coord = []
    return " ".join(res)


def blade(root, ctrl, tip, w):
    """A tapering curved feather (wing blade) as a filled path."""
    pts_l, pts_r = [], []
    n = 30
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * root[0] + 2 * (1 - t) * t * ctrl[0] + t * t * tip[0]
        y = (1 - t) ** 2 * root[1] + 2 * (1 - t) * t * ctrl[1] + t * t * tip[1]
        dx = 2 * (1 - t) * (ctrl[0] - root[0]) + 2 * t * (tip[0] - ctrl[0])
        dy = 2 * (1 - t) * (ctrl[1] - root[1]) + 2 * t * (tip[1] - ctrl[1])
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        ww = w * (1 - t) ** 0.9 * min(1, 0.4 + t * 4)
        pts_l.append((x + nx * ww / 2, y + ny * ww / 2))
        pts_r.append((x - nx * ww / 2, y - ny * ww / 2))
    pts = pts_l + pts_r[::-1]
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"


def wings(fill, line, big):
    """Wing fans behind the shield: 3 feathers (Silver) to 5 (Diamond, Master)."""
    o = []
    feathers = [((150, 170), (60, 120), (8, 40), 46), ((140, 215), (50, 190), (10, 140), 40), ((145, 260), (70, 270), (30, 235), 34)]
    if big:
        feathers = [((150, 150), (70, 80), (4, 6), 52)] + feathers + [((160, 300), (100, 330), (70, 318), 28)]
    for side in (-1, 1):
        for root, ctrl, tip, w in reversed(feathers):
            m = lambda p: (256 + side * (256 - p[0]) * -1, p[1]) if side == 1 else p
            r, c, t = (m(root), m(ctrl), m(tip)) if side == 1 else (root, ctrl, tip)
            if side == 1:
                r, c, t = ((512 - root[0], root[1]), (512 - ctrl[0], ctrl[1]), (512 - tip[0], tip[1]))
            o.append(f'<path d="{blade(r, c, t, w)}" fill="{fill}" stroke="{line}" stroke-width="5" stroke-linejoin="round"/>')
    return "".join(o)


def dragon_head(fill, line):
    """Embossed dragon head facing right: two swept horns, spikes down the
    neck, open jaw with fangs."""
    head = ("M200 336 C196 292 205 256 226 232 L236 214 C252 199 276 194 296 199 L330 209 L364 222 "
            "C372 226 373 237 366 241 L330 247 L314 249 L342 263 C332 273 302 276 286 269 "
            "C271 290 259 312 254 340 Z")
    horns = ("M238 214 C220 190 202 168 174 148 C206 158 230 180 252 205 Z",
             "M260 204 C247 178 232 156 206 130 C238 146 258 172 272 200 Z")
    spikes = ((224, 238, 196, 232, 214, 256), (212, 270, 184, 270, 207, 289), (205, 302, 178, 306, 202, 320))
    o = ""
    for d in (head,) + horns:  # embossed shadow
        o += f'<path d="{d}" fill="{line}" opacity="0.45" transform="translate(4 6)"/>'
    for x0, y0, x1, y1, x2, y2 in spikes:
        o += f'<polygon points="{x0},{y0} {x1},{y1} {x2},{y2}" fill="{fill}" stroke="{line}" stroke-width="4" stroke-linejoin="round"/>'
    for d in horns:
        o += f'<path d="{d}" fill="{fill}" stroke="{line}" stroke-width="4.5" stroke-linejoin="round"/>'
    o += f'<path d="{head}" fill="{fill}" stroke="{line}" stroke-width="5" stroke-linejoin="round"/>'
    for x in (318, 332, 346):  # upper fangs
        o += f'<polygon points="{x - 5},247 {x},{259} {x + 5},246" fill="#fff8e6" stroke="{line}" stroke-width="2.5" stroke-linejoin="round"/>'
    o += f'<polygon points="300,258 305,250 310,261" fill="#fff8e6" stroke="{line}" stroke-width="2.5"/>'
    o += f'<path d="M286 216 Q298 205 314 213 Q302 223 286 216 Z" fill="{line}"/>'  # eye
    o += f'<circle cx="303" cy="213" r="2.5" fill="#fff"/>'
    o += f'<path d="M282 206 Q298 196 318 205" fill="none" stroke="{line}" stroke-width="4" stroke-linecap="round"/>'  # brow
    o += f'<ellipse cx="356" cy="229" rx="4" ry="2.5" fill="{line}"/>'  # nostril
    o += f'<path d="M226 252 C236 274 240 296 236 318" fill="none" stroke="{line}" stroke-width="3.5" opacity="0.55"/>'
    return o


def star(cx, cy, r, fill, line):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.45
        pts.append(f"{cx + rr * math.cos(a):.1f},{cy + rr * math.sin(a):.1f}")
    return f'<polygon points="{" ".join(pts)}" fill="{fill}" stroke="{line}" stroke-width="3" stroke-linejoin="round"/>'


def laurels(fill, line):
    """Two laurel branches climbing the shield's sides from the ribbon."""
    o = []
    for side in (-1, 1):
        p0, c, p1 = (256 + side * 70, 418), (256 + side * 215, 405), (256 + side * 176, 205)
        pts = []
        for k in range(41):
            t = k / 40
            pts.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
                        (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]))
        o.append('<path d="M' + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + f'" fill="none" stroke="{line}" stroke-width="7" stroke-linecap="round"/>')
        o.append('<path d="M' + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + f'" fill="none" stroke="{fill}" stroke-width="3.5" stroke-linecap="round"/>')
        for k in range(4, 41, 5):
            (x0, y0), (x1, y1) = pts[k - 1], pts[k]
            ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
            for off in (-38, 38):
                a = math.radians(ang + off * side)
                lx, ly = x1 + 15 * math.cos(a), y1 + 15 * math.sin(a)
                o.append(f'<ellipse cx="{lx:.1f}" cy="{ly:.1f}" rx="17" ry="7" fill="{fill}" stroke="{line}" stroke-width="2.5" '
                         f'transform="rotate({ang + off * side:.1f} {lx:.1f} {ly:.1f})"/>')
        tip = pts[-1]
        o.append(f'<ellipse cx="{tip[0]:.1f}" cy="{tip[1] - 12:.1f}" rx="7" ry="17" fill="{fill}" stroke="{line}" stroke-width="2.5"/>')
    return "".join(o)


def crown(fill, line, gem):
    d = "M196 92 L206 40 L232 72 L256 26 L280 72 L306 40 L316 92 Z"
    o = f'<path d="{d}" fill="{fill}" stroke="{line}" stroke-width="5" stroke-linejoin="round"/>'
    o += f'<rect x="192" y="88" width="128" height="16" rx="5" fill="{fill}" stroke="{line}" stroke-width="5"/>'
    for x, y in ((206, 40), (256, 26), (306, 40)):
        o += f'<circle cx="{x}" cy="{y}" r="8" fill="{gem}" stroke="{line}" stroke-width="3"/>'
    return o


def flames(outer, inner):
    """A crown of flame tongues rising behind the whole badge (Master)."""
    o = []
    cx, cy = 256, 250
    for k in range(13):
        a = math.radians(192 + k * 13)
        r0, r1 = 120, 225 + 35 * math.sin(k * 1.7) ** 2
        w = 0.17
        bx1, by1 = cx + r0 * math.cos(a - w), cy + r0 * math.sin(a - w)
        bx2, by2 = cx + r0 * math.cos(a + w), cy + r0 * math.sin(a + w)
        tx, ty = cx + r1 * math.cos(a + 0.08), cy + r1 * math.sin(a + 0.08)
        mx, my = cx + (r0 + r1) / 2 * math.cos(a - 0.12), cy + (r0 + r1) / 2 * math.sin(a - 0.12)
        d = f"M{bx1:.1f} {by1:.1f} Q{mx:.1f} {my:.1f} {tx:.1f} {ty:.1f} Q{(bx2 + tx) / 2 + 6:.1f} {(by2 + ty) / 2:.1f} {bx2:.1f} {by2:.1f} Z"
        o.append(f'<path d="{d}" fill="{outer}"/>')
        o.append(f'<path d="{d}" fill="{inner}" transform="translate({cx} {cy}) scale(0.8) translate({-cx} {-cy})"/>')
    return f'<g opacity="0.95">{"".join(o)}</g>'


def ribbon(color, line, stars, starfill):
    o = (f'<path d="M110 412 L170 404 L170 466 L110 474 L128 443 Z" fill="{color}" stroke="{line}" stroke-width="5" stroke-linejoin="round" filter="url(#dim)"/>'
         f'<path d="M402 412 L342 404 L342 466 L402 474 L384 443 Z" fill="{color}" stroke="{line}" stroke-width="5" stroke-linejoin="round" filter="url(#dim)"/>'
         f'<path d="M150 396 Q256 380 362 396 L362 456 Q256 440 150 456 Z" fill="{color}" stroke="{line}" stroke-width="5" stroke-linejoin="round"/>'
         f'<path d="M150 404 Q256 388 362 404" fill="none" stroke="#fff" stroke-width="3" opacity="0.3"/>')
    for k in range(stars):
        x = 256 + (k - (stars - 1) / 2) * 38
        y = 425 - 4 * (1 - abs(k - (stars - 1) / 2) / 3)
        o += star(x, y, 16, starfill, line)
    return o


def badge(i, name, met, field, gem, rib):
    light, mid, dark = met
    line = "#2a1608" if name != "Diamond" else "#0c2448"
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 512 512"><defs>',
         metal("met", light, mid, dark), metal("met2", light, mid, dark),
         f'<radialGradient id="field" cx="0.45" cy="0.35" r="0.75"><stop offset="0" stop-color="{field[0]}"/><stop offset="1" stop-color="{field[1]}"/></radialGradient>',
         '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="6" stdDeviation="7" flood-opacity="0.45"/></filter>',
         '<filter id="dim"><feColorMatrix type="matrix" values="0.75 0 0 0 0  0 0.75 0 0 0  0 0 0.75 0 0  0 0 0 1 0"/></filter>',
         '<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fff" stop-opacity="0.55"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>',
         '</defs><g filter="url(#shadow)">']
    if name == "Master":
        o.append(flames("#ff7a2a", "#ffd04a"))
    if name in ("Gold", "Master"):
        o.append(laurels("url(#met)", line))
    if name != "Bronze":
        o.append(wings("url(#met)", line, big=name in ("Diamond", "Master")))
    # shield: outer metal rim, inner dark line, field, inner rim highlight
    o.append(f'<path d="{SHIELD}" fill="url(#met)" stroke="{line}" stroke-width="6" stroke-linejoin="round"/>')
    inner = scaled(SHIELD, 0.84, 256, 250)
    if name == "Diamond":
        # crystal field: facets fanning from the centre
        o.append(f'<path d="{inner}" fill="url(#field)" stroke="{line}" stroke-width="4"/>')
        o.append(f'<clipPath id="fc"><path d="{inner}"/></clipPath><g clip-path="url(#fc)">')
        for k in range(12):
            a0, a1 = k * math.pi / 6, (k + 1) * math.pi / 6
            op = 0.05 + 0.12 * ((k * 7) % 5) / 4
            o.append(f'<polygon points="256,250 {256 + 260 * math.cos(a0):.0f},{250 + 260 * math.sin(a0):.0f} {256 + 260 * math.cos(a1):.0f},{250 + 260 * math.sin(a1):.0f}" fill="#fff" opacity="{op:.2f}"/>')
        o.append('</g>')
    else:
        o.append(f'<path d="{inner}" fill="url(#field)" stroke="{line}" stroke-width="4"/>')
    o.append(f'<path d="{scaled(SHIELD, 0.84, 256, 250)}" fill="none" stroke="{light}" stroke-width="2" opacity="0.6" transform="translate(0 3)"/>')
    # rivets on the rim
    for x, y in ((146, 142), (366, 142), (140, 236), (372, 236), (190, 352), (322, 352)):
        o.append(f'<circle cx="{x}" cy="{y}" r="6" fill="url(#met)" stroke="{line}" stroke-width="2.5"/>')
    o.append('<ellipse cx="236" cy="200" rx="90" ry="60" fill="url(#glow)" opacity="0.5"/>')
    o.append(dragon_head("url(#met)", line))
    # top ornament
    if name == "Master":
        o.append(crown("url(#met)", line, gem))
    elif name == "Bronze":
        o.append(f'<path d="M232 112 L256 70 L280 112 Z" fill="url(#met)" stroke="{line}" stroke-width="5" stroke-linejoin="round"/>'
                 f'<circle cx="256" cy="72" r="10" fill="url(#met)" stroke="{line}" stroke-width="4"/>')
    elif gem:
        r = 26 if name == "Diamond" else 18
        if name == "Diamond":
            o.append(f'<polygon points="256,{108 - r * 1.5} {256 + r},{108 - r * 0.3} 256,{108 + r * 1.2} {256 - r},{108 - r * 0.3}" fill="{gem}" stroke="{line}" stroke-width="4"/>'
                     f'<polygon points="256,{108 - r * 1.5} {256 + r},{108 - r * 0.3} 256,{108 - r * 0.1}" fill="#a8ecff"/>')
        else:
            o.append(f'<circle cx="256" cy="104" r="{r}" fill="{gem}" stroke="{line}" stroke-width="4"/>'
                     f'<circle cx="{256 - r * 0.35}" cy="{104 - r * 0.35}" r="{r * 0.35}" fill="#fff" opacity="0.6"/>')
        if name == "Gold":
            o.append(star(256, 58, 26, "url(#met)", line))
    o.append(ribbon(rib, line, i + 1, "url(#met)"))
    o.append('</g></svg>')
    return "".join(o)


def main():
    env = dict(os.environ, NODE_PATH=NODE_PATH)
    for i, rank in enumerate(RANKS):
        svg = os.path.join(HERE, f"_{rank[0]}.svg")
        open(svg, "w").write(badge(i, *rank))
        png = os.path.join(HERE, f"_{rank[0]}_raw.png")
        subprocess.run(["node", os.path.join(HERE, "render_svg.cjs"), svg, png], check=True, env=env)
        from PIL import Image
        Image.open(png).convert("RGBA").resize((512, 512), Image.LANCZOS).save(os.path.join(HERE, f"{rank[0]}.png"))
        os.remove(png)
        os.remove(svg)
    from PIL import Image, ImageDraw
    sheet = Image.new("RGBA", (5 * 300 + 40, 480), (30, 32, 38, 255))
    ImageDraw.Draw(sheet).rectangle([0, 340, sheet.width, 680], fill=(236, 232, 220, 255))
    for i, rank in enumerate(RANKS):
        im = Image.open(os.path.join(HERE, f"{rank[0]}.png")).resize((280, 280), Image.LANCZOS)
        sheet.alpha_composite(im, (20 + i * 300, 30))
        sheet.alpha_composite(im.resize((96, 96), Image.LANCZOS), (20 + i * 300, 360))
        sheet.alpha_composite(im.resize((48, 48), Image.LANCZOS), (140 + i * 300, 384))
    sheet.convert("RGB").save(os.path.join(HERE, "_preview.png"))
    print("ok")


if __name__ == "__main__":
    main()
