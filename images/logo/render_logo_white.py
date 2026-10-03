"""Monochrome Wyrmhaven logo, white on transparent:
- an emblem: a small diamond between two stylised wings, each three
  tapering blades sweeping up and out;
- the name in Cinzel SemiBold capitals, widely tracked;
- a hairline rule with a small diamond under it.
Outputs: Logo_White.png (emblem + name), Logo_White_Wordmark.png (name and
rule only), and *_preview.png on a dark backdrop. Drawn at 2x, downsampled."""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "fonts", "Cinzel-SemiBold.ttf")
NAME = "WYRMHAVEN"
SS = 2  # supersampling
WHITE = (255, 255, 255, 255)


def blade(d, root, ctrl, tip, wmax, s=1.0):
    """A tapering curved blade along a quadratic curve root -> tip."""
    n = 40
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * root[0] + 2 * (1 - t) * t * ctrl[0] + t * t * tip[0]
        y = (1 - t) ** 2 * root[1] + 2 * (1 - t) * t * ctrl[1] + t * t * tip[1]
        dx = 2 * (1 - t) * (ctrl[0] - root[0]) + 2 * t * (tip[0] - ctrl[0])
        dy = 2 * (1 - t) * (ctrl[1] - root[1]) + 2 * t * (tip[1] - ctrl[1])
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        w = wmax * (1 - t) ** 0.85 * min(1.0, 0.35 + t * 5)
        left.append(((x + nx * w / 2) * s, (y + ny * w / 2) * s))
        right.append(((x - nx * w / 2) * s, (y - ny * w / 2) * s))
    d.polygon(left + right[::-1], fill=WHITE)


def emblem(d, cx, cy, s):
    """Diamond + two wings, centred on (cx, cy); s = scale (1 = 1000 px wide)."""
    def P(x, y):
        return (cx + x * s, cy + y * s)
    d.polygon([P(0, -78), P(34, 0), P(0, 78), P(-34, 0)], fill=WHITE)
    for side in (-1, 1):
        for root, ctrl, tip, w in (((58, -30), (200, -90), (470, -300), 58),
                                   ((62, 10), (240, -10), (480, -150), 48),
                                   ((58, 48), (230, 60), (420, -20), 38)):
            blade(d, (cx + side * root[0] * s, cy + root[1] * s), (cx + side * ctrl[0] * s, cy + ctrl[1] * s),
                  (cx + side * tip[0] * s, cy + tip[1] * s), w * s)


def wordmark(d, cx, top, size, tracking=0.2):
    """The name, letter-spaced, centred on cx; returns its bottom y."""
    font = ImageFont.truetype(FONT, size)
    widths = [d.textlength(ch, font=font) for ch in NAME]
    gap = size * tracking
    total = sum(widths) + gap * (len(NAME) - 1)
    x = cx - total / 2
    asc = font.getbbox("W")
    for ch, w in zip(NAME, widths):
        d.text((x, top - asc[1]), ch, font=font, fill=WHITE)
        x += w + gap
    bottom = top + (asc[3] - asc[1])
    # hairline rule with a small diamond in the middle
    ry = bottom + size * 0.32
    half = total * 0.42
    lw = max(2, int(size * 0.018))
    dm = size * 0.07
    d.line([(cx - half, ry), (cx - dm * 2.2, ry)], fill=WHITE, width=lw)
    d.line([(cx + dm * 2.2, ry), (cx + half, ry)], fill=WHITE, width=lw)
    d.polygon([(cx, ry - dm), (cx + dm, ry), (cx, ry + dm), (cx - dm, ry)], fill=WHITE)
    return ry + dm


def render(with_emblem):
    W, H = 2400 * SS, 1200 * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = W / 2
    top = 120 * SS
    if with_emblem:
        emblem(d, cx, top + 230 * SS, 1.15 * SS)
        top += 450 * SS
    wordmark(d, cx, top, 250 * SS)
    img = img.crop(img.getbbox())
    pad = 40 * SS
    out = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    out.paste(img, (pad, pad))
    return out.resize((out.width // SS, out.height // SS), Image.LANCZOS)


def main():
    for name, emb in (("Logo_White", True), ("Logo_White_Wordmark", False)):
        logo = render(emb)
        logo.save(os.path.join(HERE, f"{name}.png"))
        prev = Image.new("RGBA", logo.size, (26, 28, 34, 255))
        prev.alpha_composite(logo)
        prev.convert("RGB").resize((logo.width // 2, logo.height // 2), Image.LANCZOS).save(os.path.join(HERE, f"{name}_preview.png"))
        print(name, logo.size)


if __name__ == "__main__":
    main()
