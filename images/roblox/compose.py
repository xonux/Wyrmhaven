"""Final Roblox images from the scene.html renders (run render.cjs first):
- Icon.png: 512x512 (Roblox game icon), from Icon_raw.png (1024).
- Thumbnail.png: 1920x1080 (16:9 game thumbnail) with the white logo
  (../logo/Logo_White.png) top left, a soft dark shadow under it so it reads
  on the light sky; Thumbnail_Clean.png: the same without text.
- _preview_icon.png: the icon as Roblox shows it (rounded corners) at 512,
  150 and 50 px, to check it still reads small."""
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    icon = Image.open(os.path.join(HERE, "Icon_raw.png")).convert("RGB").resize((512, 512), Image.LANCZOS)
    icon.save(os.path.join(HERE, "Icon.png"))

    thumb = Image.open(os.path.join(HERE, "Thumbnail_raw.png")).convert("RGBA")
    thumb.convert("RGB").save(os.path.join(HERE, "Thumbnail_Clean.png"))
    logo = Image.open(os.path.join(HERE, "..", "logo", "Logo_White.png")).convert("RGBA")
    w = 700
    logo = logo.resize((w, int(logo.height * w / logo.width)), Image.LANCZOS)
    pos = (70, 46)
    shadow = Image.new("L", thumb.size, 0)
    shadow.paste(logo.getchannel("A"), pos)
    shadow = shadow.filter(ImageFilter.GaussianBlur(16)).point(lambda v: min(255, int(v * 0.85)))
    thumb.alpha_composite(Image.merge("RGBA", (Image.new("L", thumb.size, 16), Image.new("L", thumb.size, 34),
                                                Image.new("L", thumb.size, 58), shadow)))
    thumb.alpha_composite(logo, pos)
    thumb.convert("RGB").save(os.path.join(HERE, "Thumbnail.png"))

    # icon as shown on Roblox (rounded square) at three sizes
    sheet = Image.new("RGB", (512 + 150 + 50 + 80, 532), (25, 27, 31))
    x = 20
    for size in (512, 150, 50):
        im = icon.resize((size, size), Image.LANCZOS)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.12), fill=255)
        sheet.paste(im, (x, 10), mask)
        x += size + 20
    sheet.save(os.path.join(HERE, "_preview_icon.png"))
    print("ok")


if __name__ == "__main__":
    main()
