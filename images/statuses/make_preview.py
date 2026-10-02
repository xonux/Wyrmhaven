"""Contact sheet of every status icon in this folder, good ones (green)
then bad ones (crimson), labelled. Output: _preview.png."""
import glob
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
FONT_B = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 24)
T, COLS, PAD = 128, 9, 20
CELL_W, CELL_H = T + 26, T + 30


def is_good(im):
    """Green tile or crimson one: vote over a strip of the fill along the left
    edge, skipping white / dark pixels (glyph, outline)."""
    green = red = 0
    for y in range(130, 230, 4):
        for x in range(24, 34, 3):
            r, g, b, _ = im.getpixel((x, y))
            if max(r, g, b) - min(r, g, b) < 40:
                continue
            if g > r:
                green += 1
            else:
                red += 1
    return green > red


def main():
    icons = []
    for f in sorted(glob.glob(os.path.join(HERE, "*.png"))):
        name = os.path.basename(f)[:-4]
        if name.startswith("_"):
            continue
        im = Image.open(f).convert("RGBA")
        icons.append((name, im))
    good = [i for i in icons if is_good(i[1])]
    bad = [i for i in icons if not is_good(i[1])]
    rows = lambda n: (n + COLS - 1) // COLS
    height = PAD + 40 + rows(len(good)) * CELL_H + 30 + 40 + rows(len(bad)) * CELL_H + PAD
    sheet = Image.new("RGB", (PAD * 2 + COLS * CELL_W, height), (34, 36, 41))
    d = ImageDraw.Draw(sheet)
    y = PAD
    for title, group in ((f"Buffs ({len(good)})", good), (f"Debuffs ({len(bad)})", bad)):
        d.text((PAD, y), title, font=FONT_B, fill=(240, 240, 240))
        y += 40
        for k, (name, im) in enumerate(group):
            x = PAD + (k % COLS) * CELL_W
            yy = y + (k // COLS) * CELL_H
            sheet.paste(im.resize((T, T), Image.LANCZOS), (x + 13, yy), im.resize((T, T), Image.LANCZOS))
            w = d.textlength(name, font=FONT)
            d.text((x + 13 + (T - w) / 2, yy + T + 4), name, font=FONT, fill=(225, 225, 225))
        y += rows(len(group)) * CELL_H + 30
    sheet.save(os.path.join(HERE, "_preview.png"))
    print("good", len(good), "bad", len(bad))


if __name__ == "__main__":
    main()
