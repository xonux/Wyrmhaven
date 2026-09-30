"""Renders the Wyrmhaven rarity badges (round colored disc + white letter) as PNGs.

Same badge look as images/elements (dark edge, silver rim, gradient disc,
gloss), with the rarity's initial in place of the glyph.
Drawn at 4x and downsampled for smooth edges. Output: <Rarity>.png (512px).
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2048  # working size
OUT = 512
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

CLEAR = (0, 0, 0, 0)
WHITE = (255, 255, 255, 255)

RARITIES = {
    # name: (letter, disc top, disc bottom, letter outline)
    "Common": ("C", (178, 184, 194), (104, 110, 122), (58, 62, 72)),
    "Rare": ("R", (78, 168, 246), (22, 88, 196), (12, 48, 118)),
    "Epic": ("E", (184, 104, 246), (104, 34, 180), (58, 14, 108)),
    "Legendary": ("L", (255, 206, 72), (222, 126, 14), (130, 66, 4)),
}


def p(x, y):
    return (x * S, y * S)


def vertical_gradient(top, bottom):
    mask = Image.linear_gradient("L").resize((S, S))
    return Image.composite(Image.new("RGBA", (S, S), bottom), Image.new("RGBA", (S, S), top), mask)


def disc_mask(radius):
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([p(0.5 - radius, 0.5 - radius), p(0.5 + radius, 0.5 + radius)], fill=255)
    return mask


def solid(color, alpha):
    return Image.merge("RGBA", (*[Image.new("L", (S, S), c) for c in color[:3]], alpha))


def render(letter, top, bottom, outline):
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
    img = Image.alpha_composite(img, solid((0, 0, 0), shade.point(lambda v: v * 0.5)))

    # glossy highlight on the upper half
    gloss_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss_mask).ellipse([p(0.16, 0.10), p(0.84, 0.52)], fill=255)
    fade = Image.linear_gradient("L").resize((S, S)).point(lambda v: max(0, 70 - v * 0.28))
    gloss_alpha = Image.composite(fade, Image.new("L", (S, S), 0), gloss_mask)
    gloss_alpha = Image.composite(gloss_alpha, Image.new("L", (S, S), 0), disc_mask(0.43))
    img = Image.alpha_composite(img, solid((255, 255, 255), gloss_alpha))

    # letter: centered on its ink box, colored outline + soft drop shadow
    font = ImageFont.truetype(FONT, int(S * 0.50))
    stroke = int(S * 0.022)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    l, t, r, b = probe.textbbox((0, 0), letter, font=font, stroke_width=stroke)
    x, y = (S - (r - l)) / 2 - l, (S - (b - t)) / 2 - t
    ink = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ink).text((x, y), letter, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
    shadow = ink.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: v * 0.4)
    img.alpha_composite(solid((0, 0, 0), shadow), (0, int(S * 0.016)))
    img = Image.alpha_composite(img, solid(outline, ink))
    face = Image.new("L", (S, S), 0)
    ImageDraw.Draw(face).text((x, y), letter, font=font, fill=255)
    img = Image.alpha_composite(img, solid(WHITE, face))

    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    icons = [render(*spec) for spec in RARITIES.values()]
    for name, icon in zip(RARITIES, icons):
        icon.save(os.path.join(HERE, f"{name}.png"))
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
