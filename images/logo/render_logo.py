"""Wyrmhaven logo: the name in arched, fire-gold letters with a cream inner
line and a thick dark outline, over a pair of spread dragon wings. Fonts (OFL, in fonts/): Cinzel Decorative Black, Luckiest Guy.
Output (transparent PNGs + previews on a sky backdrop): Logo.png (Luckiest
Guy, the round mobile-game look) and Logo_Fantasy.png (Cinzel Decorative)."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = {
    "cinzel": os.path.join(HERE, "fonts", "CinzelDecorative-Black.ttf"),
    "luckiest": os.path.join(HERE, "fonts", "LuckiestGuy-Regular.ttf"),
}
NAME = "WYRMHAVEN"
W, H = 2600, 1200
CX, BASE_Y = W / 2, 700  # text centre line
ARCH = 70  # how much the middle rises above the ends
OUTLINE = (52, 18, 10)
CREAM = (255, 244, 205)


def dilate(mask, r):
    """Fast round dilation: blur then threshold."""
    return mask.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 20 else 0).filter(ImageFilter.GaussianBlur(1.2))


def solid(color, alpha):
    return Image.merge("RGBA", (*[Image.new("L", alpha.size, c) for c in color], alpha))


def letter_image(ch, font):
    """One letter: fire-gold gradient, light top bevel. Returns RGBA, tight box."""
    l, t, r, b = font.getbbox(ch)
    w, h = r - l + 40, b - t + 40
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((20 - l, 20 - t), ch, font=font, fill=255)
    ys = np.linspace(0, 1, h)[:, None]
    stops = [(0.0, (255, 240, 150)), (0.45, (255, 182, 52)), (0.75, (238, 112, 26)), (1.0, (186, 54, 16))]
    grad = np.zeros((h, w, 3))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        k = np.clip((ys - p0) / (p1 - p0), 0, 1)
        sel = (ys >= p0) & (ys <= p1)
        for i in range(3):
            grad[..., i] = np.where(sel, c0[i] + (c1[i] - c0[i]) * k, grad[..., i])
    img = Image.fromarray(grad.astype(np.uint8)).convert("RGBA")
    img.putalpha(mask)
    # bevel: a soft light band along the upper part of each stroke
    inner = mask.filter(ImageFilter.GaussianBlur(max(2, h * 0.02)))
    shifted = Image.new("L", (w, h), 0)
    shifted.paste(inner, (0, int(h * 0.03)))
    hi = Image.eval(Image.fromarray(np.clip(np.asarray(inner, int) - np.asarray(shifted, int), 0, 255).astype(np.uint8)), lambda v: min(255, v * 3))
    img.alpha_composite(solid((255, 255, 235), Image.fromarray((np.asarray(hi) * (np.asarray(mask) / 255) * 0.8).astype(np.uint8))))
    return img


def layout(font_path):
    """Letters placed along a gentle arch, the initial bigger."""
    big = ImageFont.truetype(font_path, 330)
    small = ImageFont.truetype(font_path, 250)
    imgs = [letter_image(ch, big if i == 0 else small) for i, ch in enumerate(NAME)]
    gap = -14
    total = sum(im.width for im in imgs) + gap * (len(imgs) - 1)
    scale = min(1.0, (W * 0.86) / total)
    imgs = [im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS) for im in imgs]
    total = sum(im.width for im in imgs) + gap * (len(imgs) - 1)
    x = CX - total / 2
    placed = []
    for i, im in enumerate(imgs):
        mid = x + im.width / 2
        u = (mid - CX) / (total / 2)  # -1 .. 1
        rise = ARCH * (1 - u * u)
        angle = math.degrees(math.atan(2 * ARCH * u / (total / 2)))  # tangent of the arch
        rot = im.rotate(angle, resample=Image.BICUBIC, expand=True)
        cy = BASE_Y - rise - (im.height - imgs[-1].height) * 0.35  # the big initial sits a bit lower
        placed.append((rot, (int(mid - rot.width / 2), int(cy - rot.height / 2))))
        x += im.width + gap
    return placed


def qcurve(p0, c, p1, n=24):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]) for t in [i / n for i in range(n + 1)]]


def wings():
    """Two dragon wings spread behind the name: curved leading edge, a
    scalloped membrane between the fingers, panels in alternating tones."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    mask = Image.new("L", (W, H), 0)
    top = BASE_Y - 280
    panels, bones = [], []
    for s in (-1, 1):
        def P(dx, y):
            return (CX + s * dx, top + y)
        shoulder, wrist, tip = P(120, 190), P(560, -170), P(1130, -60)
        fingers = [tip, P(990, 170), P(780, 250), P(540, 290), P(200, 280)]
        lead = qcurve(shoulder, P(260, -150), wrist) + qcurve(wrist, P(860, -210), tip)[1:]
        trail = []
        for a, b in zip(fingers, fingers[1:]):
            mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            ctrl = (mid[0] + (wrist[0] - mid[0]) * 0.32, mid[1] + (wrist[1] - mid[1]) * 0.32)
            seg = qcurve(a, ctrl, b)
            trail += seg[1:] if trail else seg
            panels.append([wrist] + seg)
        outline_pts = lead + trail + [shoulder]
        ImageDraw.Draw(mask).polygon(outline_pts, fill=255)
        panels[-1] = panels[-1] + [shoulder]
        for f in fingers[:-1]:
            mid = ((wrist[0] + f[0]) / 2, (wrist[1] + f[1]) / 2 - 25)
            bones.append((qcurve(wrist, mid, f), 15))
        bones.append((qcurve(shoulder, P(300, -40), wrist), 30))
    img.alpha_composite(solid(OUTLINE, dilate(mask, 11)))
    img.alpha_composite(solid((140, 30, 28), mask))  # base membrane under the panels
    d = ImageDraw.Draw(img)
    tones = [(150, 34, 30), (128, 26, 26), (142, 30, 28), (118, 22, 24)]
    for i, poly in enumerate(panels):
        d.polygon(poly, fill=tones[i % 4] + (255,))
    # darker toward the bottom of the membrane
    shade = Image.linear_gradient("L").resize((W, H)).point(lambda v: v * 0.45)
    img.alpha_composite(solid((40, 6, 10), Image.composite(shade, Image.new("L", (W, H), 0), mask)))
    for pts, width in bones:
        d.line(pts, fill=(204, 82, 56, 255), width=width, joint="curve")
        d.ellipse([pts[-1][0] - width / 2, pts[-1][1] - width / 2, pts[-1][0] + width / 2, pts[-1][1] + width / 2],
                  fill=(204, 82, 56, 255))
    # claw on each wrist
    for s in (-1, 1):
        wx, wy = CX + s * 560, top - 170
        d.polygon([(wx - s * 10, wy - 6), (wx + s * 34, wy - 70), (wx + s * 24, wy + 4)], fill=(245, 226, 190, 255),
                  outline=OUTLINE + (255,))
    return img


def render(font_key):
    placed = layout(FONTS[font_key])
    text = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for im, pos in placed:
        text.alpha_composite(im, pos)
    mask = text.getchannel("A")
    cream = dilate(mask, 7)
    dark = dilate(mask, 20)
    shadow = dark.filter(ImageFilter.GaussianBlur(14)).point(lambda v: v * 0.55)

    logo = wings()
    logo.alpha_composite(solid((0, 0, 0), shadow), (0, 14))
    logo.alpha_composite(solid(OUTLINE, dark))
    logo.alpha_composite(solid(CREAM, cream))
    logo.alpha_composite(solid((120, 40, 14), dilate(mask, 2)))
    logo.alpha_composite(text)
    box = logo.getbbox()
    pad = 30
    return logo.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad))


def main():
    for key, name in (("luckiest", "Logo"), ("cinzel", "Logo_Fantasy")):
        logo = render(key)
        logo.save(os.path.join(HERE, f"{name}.png"))
        prev = Image.new("RGBA", logo.size, (110, 160, 205, 255))
        prev.alpha_composite(logo)
        prev.convert("RGB").resize((logo.width // 2, logo.height // 2), Image.LANCZOS).save(os.path.join(HERE, f"{name}_preview.png"))
        print(name, logo.size)


if __name__ == "__main__":
    main()
