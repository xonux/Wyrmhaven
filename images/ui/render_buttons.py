"""Two small UI icons, drawn at 4x and downsampled (512px, transparent):
- Plus.png: a white plus on a green rounded square (an "add" button: lighter
  top, darker lip at the bottom, soft gloss, like the + buttons of the HUD);
- ArrowUp.png: a green arrow pointing up, in the style of the up arrows on
  the status icons (green fill, white ring, dark outline)."""
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = 512
K = 4
S = OUT * K
CLEAR = (0, 0, 0, 0)
INK = (24, 18, 28)
GREEN = (70, 214, 96)  # same green as the status arrows


def P(x, y):
    return (x * S, y * S)


def solid(color, alpha):
    return Image.merge("RGBA", (*[Image.new("L", (S, S), c) for c in color], alpha))


def rrect(box, r, fill=255):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([P(box[0], box[1]), P(box[2], box[3])], radius=int(r * S), fill=fill)
    return m


def vgrad(top, bottom):
    g = Image.linear_gradient("L").resize((S, S))
    return Image.composite(Image.new("RGBA", (S, S), bottom + (255,)), Image.new("RGBA", (S, S), top + (255,)), g)


def plus():
    img = Image.new("RGBA", (S, S), CLEAR)
    box = (0.08, 0.08, 0.92, 0.92)
    # soft drop shadow, dark edge, darker lip at the bottom, then the face
    shadow = rrect((0.08, 0.1, 0.92, 0.95), 0.16).filter(ImageFilter.GaussianBlur(S * 0.015))
    img.alpha_composite(solid((0, 0, 0), shadow.point(lambda v: v * 0.35)))
    img.alpha_composite(solid((26, 70, 24), rrect((0.07, 0.07, 0.93, 0.93), 0.17)))
    img.paste(vgrad((60, 150, 40), (36, 110, 30)), (0, 0), rrect(box, 0.16))
    img.paste(vgrad((128, 222, 78), (66, 178, 46)), (0, 0), rrect((0.08, 0.08, 0.92, 0.86), 0.16))
    gloss = rrect((0.13, 0.12, 0.87, 0.45), 0.11).filter(ImageFilter.GaussianBlur(S * 0.004))
    img.alpha_composite(solid((255, 255, 255), gloss.point(lambda v: v * 0.22)))
    # white plus with a soft shadow under it
    bar = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(bar)
    w, l = 0.085, 0.27
    cx, cy = 0.5, 0.47
    d.rounded_rectangle([P(cx - l, cy - w), P(cx + l, cy + w)], radius=int(0.035 * S), fill=255)
    d.rounded_rectangle([P(cx - w, cy - l), P(cx + w, cy + l)], radius=int(0.035 * S), fill=255)
    sh = bar.filter(ImageFilter.GaussianBlur(S * 0.01)).point(lambda v: v * 0.35)
    img.alpha_composite(solid((10, 50, 10), sh), (0, int(S * 0.015)))
    img.alpha_composite(solid((255, 255, 255), bar))
    return img.resize((OUT, OUT), Image.LANCZOS)


def arrow_up():
    img = Image.new("RGBA", (S, S), CLEAR)
    cx, top, bottom, w = 0.5, 0.1, 0.9, 0.7
    hw, sw = w / 2, w * 0.22
    head = top + (bottom - top) * 0.48
    pts = [(cx, top), (cx + hw, head), (cx + sw, head), (cx + sw, bottom), (cx - sw, bottom), (cx - sw, head), (cx - hw, head)]
    base = Image.new("L", (S, S), 0)
    ImageDraw.Draw(base).polygon([P(*v) for v in pts], fill=255)
    ring = base.filter(ImageFilter.MaxFilter(int(S * 0.03) | 1))
    dark = ring.filter(ImageFilter.MaxFilter(int(S * 0.03) | 1))
    shadow = dark.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: v * 0.35)
    img.alpha_composite(solid((0, 0, 0), shadow), (0, int(S * 0.012)))
    img.alpha_composite(solid(INK, dark))
    img.alpha_composite(solid((255, 255, 255), ring))
    img.alpha_composite(solid(GREEN, base))
    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    plus().save(os.path.join(HERE, "Plus.png"))
    arrow_up().save(os.path.join(HERE, "ArrowUp.png"))
    print("ok")


if __name__ == "__main__":
    main()
