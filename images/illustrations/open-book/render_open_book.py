"""An open book seen from above at a slight angle: leather cover, page
block, two pages curving down into the spine. Left page: the ink drawing of
the baby fire dragon (DragonSketch.png, from make_dragon_sketch.py) in a
frame with its caption; right page: a heading and lines of handwriting.
Output: OpenBook.png (transparent background) and OpenBook_preview.png."""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 2400, 1600  # canvas
PW, PH = 1000, 1300  # flat page texture
PAPER = (244, 232, 204)
INK = (62, 38, 22)
SERIF_B = "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf"
SERIF_I = "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf"
random.seed(4)


def paper():
    """Aged paper: flat colour with soft blotches and a darker rim."""
    rng = np.random.default_rng(3)
    noise = Image.fromarray((rng.random((PH // 20, PW // 20)) * 255).astype(np.uint8)).resize((PW, PH), Image.BICUBIC)
    noise = noise.filter(ImageFilter.GaussianBlur(25))
    base = Image.new("RGB", (PW, PH), PAPER)
    dark = Image.new("RGB", (PW, PH), (226, 207, 170))
    img = Image.composite(dark, base, noise.point(lambda v: max(0, v - 110) * 0.9))
    rim = Image.new("L", (PW, PH), 0)
    ImageDraw.Draw(rim).rectangle([0, 0, PW, PH], outline=255, width=60)
    rim = rim.filter(ImageFilter.GaussianBlur(40))
    return Image.composite(Image.new("RGB", (PW, PH), (214, 190, 148)), img, rim.point(lambda v: v * 0.6)).convert("RGBA")


def left_page():
    img = paper()
    d = ImageDraw.Draw(img)
    # double frame
    d.rectangle([90, 90, PW - 90, PH - 90], outline=INK + (200,), width=4)
    d.rectangle([104, 104, PW - 104, PH - 104], outline=INK + (140,), width=2)
    sketch = Image.open(os.path.join(HERE, "DragonSketch.png"))
    s = min(700 / sketch.width, 830 / sketch.height)
    sketch = sketch.resize((int(sketch.width * s), int(sketch.height * s)), Image.LANCZOS)
    img.alpha_composite(sketch, ((PW - sketch.width) // 2, 170))
    font = ImageFont.truetype(SERIF_I, 52)
    cap = "Fire Dragon, hatchling"
    w = d.textlength(cap, font=font)
    d.text(((PW - w) / 2, 1065), cap, font=font, fill=INK + (230,))
    d.line([(PW / 2 - 160, 1140), (PW / 2 + 160, 1140)], fill=INK + (160,), width=2)
    return img


def scribble_line(d, x0, x1, y):
    """A line of 'handwriting': words as small wavy strokes."""
    x = x0
    while x < x1 - 40:
        wl = random.randint(30, 110)
        wl = min(wl, x1 - x)
        pts = []
        for i in range(0, wl, 6):
            pts.append((x + i, y + 7 * math.sin(i * 0.55 + random.random()) + random.uniform(-3, 3)))
        if len(pts) > 1:
            d.line(pts, fill=INK + (200,), width=3, joint="curve")
        x += wl + random.randint(14, 24)


def right_page():
    img = paper()
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(SERIF_B, 78)
    title = "Fire Dragon"
    w = d.textlength(title, font=font)
    d.text(((PW - w) / 2, 150), title, font=font, fill=INK + (235,))
    d.line([(PW / 2 - 220, 262), (PW / 2 + 220, 262)], fill=INK + (170,), width=3)
    d.ellipse([PW / 2 - 9, 253, PW / 2 + 9, 271], fill=INK + (200,))
    # drop cap + paragraphs
    cap = ImageFont.truetype(SERIF_B, 120)
    d.text((140, 320), "T", font=cap, fill=(150, 50, 24, 235))
    y = 345
    for para in range(4):
        lines = random.randint(4, 6)
        for i in range(lines):
            x0 = 240 if (para == 0 and i < 2) else 140
            x1 = PW - 140 if i < lines - 1 else random.randint(450, 760)
            scribble_line(d, x0, x1, y)
            y += 52
        y += 38
        if y > PH - 220:
            break
    # little flame flourish at the bottom
    d.text((PW / 2 - 12, PH - 175), "~", font=ImageFont.truetype(SERIF_B, 60), fill=INK + (160,))
    return img


# ------------------------------------------------------------------ book shape
SPINE_X = W / 2
PAGE_SPAN = 950  # spine -> outer edge on screen


def top_edge(t):
    """t = 0 at the spine, 1 at the outer edge: pages rise out of the gutter."""
    return 330 - 105 * math.sin(math.pi * min(1, t) * 0.62) + 18 * t


def bottom_edge(t):
    return top_edge(t) + 1040 + 30 * t


def warp_page(tex, side):
    """Maps the flat page texture onto the curved page; side -1 left, +1 right."""
    out = np.zeros((H, W, 4), np.uint8)
    src = np.asarray(tex)
    xs = np.arange(W)
    t = (xs - SPINE_X) * side / PAGE_SPAN
    valid = (t >= 0) & (t <= 1)
    xs, t = xs[valid], t[valid]
    # the page bends down into the gutter: its inner part is foreshortened
    u = np.clip(t ** 0.8, 0, 1)
    u = u if side > 0 else 1 - u
    tops = np.array([top_edge(v) for v in t])
    bots = np.array([bottom_edge(v) for v in t])
    for col, x in enumerate(xs):
        y0, y1 = int(tops[col]), int(bots[col])
        ys = np.arange(y0, y1)
        v = (ys - tops[col]) / (bots[col] - tops[col])
        sy = np.clip((v * (PH - 1)).astype(int), 0, PH - 1)
        sx = int(np.clip(u[col] * (PW - 1), 0, PW - 1))
        out[y0:y1, x] = src[sy, sx]
    img = Image.fromarray(out, "RGBA")
    # gutter shadow and a soft light on the curve
    shade = np.zeros((H, W), np.uint8)
    tt = np.clip((np.arange(W) - SPINE_X) * side / PAGE_SPAN, 0, 1)
    col_shade = (np.clip(1 - tt / 0.22, 0, 1) ** 1.8 * 150).astype(np.uint8)
    shade[:] = col_shade[None, :]
    shade = Image.fromarray(shade)
    shade = Image.composite(shade, Image.new("L", (W, H), 0), img.getchannel("A"))
    img.alpha_composite(Image.merge("RGBA", (*[Image.new("L", (W, H), 40)] * 2, Image.new("L", (W, H), 20), shade)))
    return img


def page_outline(side, dy=0, grow=0):
    pts = []
    for i in range(41):
        t = i / 40
        pts.append((SPINE_X + side * t * (PAGE_SPAN + grow), top_edge(t) + dy - grow * 0.3))
    for i in range(40, -1, -1):
        t = i / 40
        pts.append((SPINE_X + side * t * (PAGE_SPAN + grow), bottom_edge(t) + dy + grow * 0.6))
    return pts


def main():
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # soft shadow on whatever the book lies on
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).ellipse([SPINE_X - 1000, 1180, SPINE_X + 1000, 1500], fill=120)
    sh = sh.filter(ImageFilter.GaussianBlur(45))
    canvas.alpha_composite(Image.merge("RGBA", (*[Image.new("L", (W, H), 20)] * 3, sh)))

    # leather cover, a little bigger than the pages, with a darker rim
    cover = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cover)
    for side in (-1, 1):
        cd.polygon(page_outline(side, dy=46, grow=34), fill=(92, 34, 24, 255))
        cd.line(page_outline(side, dy=46, grow=34) + [page_outline(side, dy=46, grow=34)[0]], fill=(58, 20, 14, 255), width=6)
    cd.rectangle([SPINE_X - 40, top_edge(0) + 60, SPINE_X + 40, bottom_edge(0) + 70], fill=(80, 28, 20, 255))
    canvas.alpha_composite(cover)
    # gold tooling along the cover's outer edges
    gd = ImageDraw.Draw(canvas)
    for side in (-1, 1):
        ol = page_outline(side, dy=46, grow=18)
        n = len(ol) // 2
        gd.line(ol[n - 6:n + 6], fill=(198, 156, 72, 255), width=3)

    # page block: stacked sheets visible on the outer and bottom edges
    for k in range(9, 0, -1):
        tone = 236 - k * 5
        for side in (-1, 1):
            gd.polygon(page_outline(side, dy=4 * k, grow=1.4 * k), fill=(tone, tone - 14, tone - 44, 255))
            gd.line(page_outline(side, dy=4 * k, grow=1.4 * k)[41:], fill=(tone - 40, tone - 55, tone - 85, 255), width=1)

    canvas.alpha_composite(warp_page(left_page(), -1))
    canvas.alpha_composite(warp_page(right_page(), 1))
    # the gutter line itself
    gd.line([(SPINE_X, top_edge(0) + 2), (SPINE_X, bottom_edge(0) - 2)], fill=(120, 92, 60, 255), width=3)

    canvas = canvas.filter(ImageFilter.SMOOTH)  # soften the column-sampled edges a touch
    canvas.save(os.path.join(HERE, "OpenBook.png"))
    prev = Image.new("RGBA", (W, H), (126, 160, 196, 255))
    prev.alpha_composite(canvas)
    prev.convert("RGB").resize((W // 2, H // 2), Image.LANCZOS).save(os.path.join(HERE, "OpenBook_preview.png"))
    print("ok", canvas.size)


if __name__ == "__main__":
    main()
