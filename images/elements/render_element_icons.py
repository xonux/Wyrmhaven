"""Renders the Wyrmhaven element badges (round colored disc + white glyph) as PNGs.

Drawn at 4x and downsampled for smooth edges. Output: element_icons/<Element>.png (512px).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # working size
OUT = 512
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = HERE

CLEAR = (0, 0, 0, 0)
WHITE = (255, 255, 255, 255)


def p(x, y):
    return (x * S, y * S)


def bezier(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def path(start, curves):
    """curves: list of (c1, c2, end) in unit coords, chained from start."""
    pts = []
    current = start
    for c1, c2, end in curves:
        pts.extend(bezier(p(*current), p(*c1), p(*c2), p(*end)))
        current = end
    return pts


def circle(draw, cx, cy, r, fill):
    draw.ellipse([p(cx - r, cy - r), p(cx + r, cy + r)], fill=fill)


def vertical_gradient(top, bottom):
    mask = Image.linear_gradient("L").resize((S, S))
    return Image.composite(Image.new("RGBA", (S, S), bottom), Image.new("RGBA", (S, S), top), mask)


def disc_mask(radius):
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([p(0.5 - radius, 0.5 - radius), p(0.5 + radius, 0.5 + radius)], fill=255)
    return mask


# --- glyphs: draw white shapes on a transparent RGBA layer; CLEAR punches holes ---

def glyph_fire(d):
    outer = path((0.50, 0.76), [
        ((0.67, 0.76), (0.73, 0.60), (0.67, 0.47)),
        ((0.63, 0.38), (0.55, 0.33), (0.55, 0.23)),
        ((0.47, 0.29), (0.42, 0.35), (0.44, 0.44)),
        ((0.40, 0.42), (0.38, 0.38), (0.39, 0.33)),
        ((0.30, 0.43), (0.28, 0.56), (0.33, 0.65)),
        ((0.37, 0.73), (0.43, 0.76), (0.50, 0.76)),
    ])
    d.polygon(outer, fill=WHITE)
    inner = path((0.50, 0.71), [
        ((0.58, 0.71), (0.61, 0.63), (0.58, 0.57)),
        ((0.55, 0.52), (0.51, 0.50), (0.51, 0.44)),
        ((0.47, 0.51), (0.41, 0.56), (0.42, 0.63)),
        ((0.43, 0.68), (0.46, 0.71), (0.50, 0.71)),
    ])
    d.polygon(inner, fill=CLEAR)


def glyph_water(d):
    cx, cy, r, tip = 0.50, 0.59, 0.16, 0.22
    dist = cy - tip
    theta = math.acos(r / dist)
    left = (cx - r * math.sin(theta), cy - r * math.cos(theta))
    right = (cx + r * math.sin(theta), cy - r * math.cos(theta))
    d.polygon([p(cx, tip), p(*right), p(cx, cy), p(*left)], fill=WHITE)
    circle(d, cx, cy, r, WHITE)
    # thin highlight arc inside the drop
    hr = 0.10
    d.arc([p(cx - hr, cy - hr), p(cx + hr, cy + hr)], start=120, end=195, fill=CLEAR, width=int(0.022 * S))


def glyph_nature(d):
    leaf = path((0.30, 0.72), [
        ((0.25, 0.42), (0.45, 0.25), (0.73, 0.27)),
        ((0.75, 0.52), (0.58, 0.73), (0.30, 0.72)),
    ])
    d.polygon(leaf, fill=WHITE)
    rib = bezier(p(0.35, 0.67), p(0.45, 0.55), p(0.55, 0.43), p(0.66, 0.34), n=32)
    d.line(rib, fill=CLEAR, width=int(0.022 * S), joint="curve")
    d.line([p(0.31, 0.71), p(0.25, 0.78)], fill=WHITE, width=int(0.03 * S))


def glyph_electric(d):
    d.polygon([p(0.53, 0.20), p(0.68, 0.20), p(0.57, 0.45), p(0.67, 0.45),
               p(0.39, 0.81), p(0.48, 0.53), p(0.37, 0.53)], fill=WHITE)


def glyph_earth(d):
    d.polygon([p(0.22, 0.71), p(0.39, 0.45), p(0.45, 0.53), p(0.58, 0.29),
               p(0.66, 0.43), p(0.70, 0.40), p(0.80, 0.71)], fill=WHITE)
    ridge = [p(0.58, 0.29), p(0.55, 0.42), p(0.59, 0.50), p(0.55, 0.60)]
    d.line(ridge, fill=CLEAR, width=int(0.02 * S), joint="curve")


def glyph_light(d):
    circle(d, 0.5, 0.5, 0.12, WHITE)
    for i in range(10):
        angle = i * math.tau / 10
        inner, outer, half = 0.155, 0.25, math.radians(8)
        a = (0.5 + inner * math.cos(angle - half), 0.5 + inner * math.sin(angle - half))
        b = (0.5 + outer * math.cos(angle), 0.5 + outer * math.sin(angle))
        c = (0.5 + inner * math.cos(angle + half), 0.5 + inner * math.sin(angle + half))
        d.polygon([p(*a), p(*b), p(*c)], fill=WHITE)


def glyph_dark(d):
    circle(d, 0.47, 0.52, 0.21, WHITE)
    circle(d, 0.56, 0.45, 0.18, CLEAR)


def glyph_metal(d):
    top = [p(0.36, 0.32), p(0.64, 0.32), p(0.72, 0.47), p(0.28, 0.47)]
    front = [p(0.28, 0.47), p(0.72, 0.47), p(0.79, 0.69), p(0.21, 0.69)]
    d.polygon(front, fill=(232, 235, 240, 255))
    d.polygon(top, fill=WHITE)
    d.line([p(0.28, 0.47), p(0.72, 0.47)], fill=CLEAR, width=int(0.024 * S))


ELEMENTS = {
    # name: (disc top, disc bottom, glyph, glyph outline or None)
    "Fire": ((242, 104, 62), (190, 44, 26), glyph_fire, None),
    "Water": ((72, 164, 238), (24, 94, 182), glyph_water, None),
    "Nature": ((146, 210, 74), (66, 146, 38), glyph_nature, None),
    "Electric": ((252, 216, 64), (208, 156, 16), glyph_electric, (150, 108, 10)),
    "Earth": ((172, 118, 62), (108, 66, 28), glyph_earth, None),
    "Light": ((248, 236, 196), (214, 186, 116), glyph_light, (176, 138, 52)),
    "Dark": ((76, 76, 86), (18, 18, 22), glyph_dark, None),
    "Metal": ((176, 182, 192), (98, 104, 116), glyph_metal, (70, 74, 84)),
}


def render(name, top, bottom, glyph, outline):
    img = Image.new("RGBA", (S, S), CLEAR)

    # dark outer edge, light metallic rim, colored disc
    img.paste(Image.new("RGBA", (S, S), (34, 36, 42, 230)), (0, 0), disc_mask(0.495))
    img.paste(vertical_gradient((242, 244, 248, 255), (150, 156, 168, 255)), (0, 0), disc_mask(0.482))
    img.paste(vertical_gradient(top + (255,), bottom + (255,)), (0, 0), disc_mask(0.43))

    # soft inner shadow at the disc edge
    shade = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shade).ellipse([p(0.07, 0.07), p(0.93, 0.93)], outline=150, width=int(0.03 * S))
    shade = shade.filter(ImageFilter.GaussianBlur(S * 0.012))
    shade = Image.composite(shade, Image.new("L", (S, S), 0), disc_mask(0.43))
    img = Image.alpha_composite(img, Image.merge("RGBA", (*[Image.new("L", (S, S), 0)] * 3, shade.point(lambda v: v * 0.5))))

    # glossy highlight on the upper half
    gloss_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss_mask).ellipse([p(0.16, 0.10), p(0.84, 0.52)], fill=255)
    fade = Image.linear_gradient("L").resize((S, S)).point(lambda v: max(0, 70 - v * 0.28))
    gloss_alpha = Image.composite(fade, Image.new("L", (S, S), 0), gloss_mask)
    gloss_alpha = Image.composite(gloss_alpha, Image.new("L", (S, S), 0), disc_mask(0.43))
    img = Image.alpha_composite(img, Image.merge("RGBA", (*[Image.new("L", (S, S), 255)] * 3, gloss_alpha)))

    # glyph with a soft drop shadow (and an outline where white needs contrast)
    layer = Image.new("RGBA", (S, S), CLEAR)
    glyph(ImageDraw.Draw(layer))
    alpha = layer.getchannel("A")
    shadow = alpha.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: v * 0.35)
    shadow_img = Image.merge("RGBA", (*[Image.new("L", (S, S), 0)] * 3, shadow))
    img.alpha_composite(shadow_img, (0, int(S * 0.012)))
    if outline:
        ring = alpha.filter(ImageFilter.MaxFilter(int(S * 0.012) | 1))
        img = Image.alpha_composite(img, Image.merge("RGBA", (
            Image.new("L", (S, S), outline[0]), Image.new("L", (S, S), outline[1]), Image.new("L", (S, S), outline[2]), ring)))
    img = Image.alpha_composite(img, layer)

    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    previews = []
    for name, (top, bottom, glyph, outline) in ELEMENTS.items():
        icon = render(name, top, bottom, glyph, outline)
        icon.save(os.path.join(OUT_DIR, f"{name}.png"))
        previews.append(icon)
    # contact sheet on the UI's dark grey to check contrast
    sheet = Image.new("RGBA", (OUT * 4 + 50, OUT * 2 + 30), (34, 36, 41, 255))
    for i, icon in enumerate(previews):
        sheet.alpha_composite(icon, (10 + (i % 4) * (OUT + 10), 10 + (i // 4) * (OUT + 10)))
    sheet.convert("RGB").resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS).save(os.path.join(HERE, "_preview_sheet.png"))
    print("ok", len(previews))


if __name__ == "__main__":
    main()
