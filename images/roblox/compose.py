"""Builds the final Roblox images from the 3D renders of the game's own
models (render3d.cjs: scene3d.html -> _Icon_raw.png, _Thumbnail_raw.png):
- Icon.png 512x512, Thumbnail_Clean.png 1920x1080 (no text),
- Thumbnail.png: the same with the white logo (../logo/Logo_White.png) top
  centred at the top, with a soft dark shadow so it reads on the light sky,
- _preview_icon.png: the icon with Roblox's rounded corners at 512/150/50 px.
Needs `npm i three playwright-core` here."""
import os
import subprocess

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))


def render():
    subprocess.run(["node", os.path.join(HERE, "render3d.cjs")], check=True)


def raw(name):
    path = os.path.join(HERE, f"_{name}_raw.png")
    img = Image.open(path).convert("RGBA")
    os.remove(path)
    return img


def main():
    render()
    icon = raw("Icon").convert("RGB").resize((512, 512), Image.LANCZOS)
    icon.save(os.path.join(HERE, "Icon.png"))

    thumb = raw("Thumbnail")
    thumb.convert("RGB").save(os.path.join(HERE, "Thumbnail_Clean.png"))
    logo = Image.open(os.path.join(HERE, "..", "logo", "Logo_White.png")).convert("RGBA")
    w = 760
    logo = logo.resize((w, int(logo.height * w / logo.width)), Image.LANCZOS)
    pos = ((thumb.width - w) // 2, 40)
    shadow = Image.new("L", thumb.size, 0)
    shadow.paste(logo.getchannel("A"), pos)
    shadow = shadow.filter(ImageFilter.GaussianBlur(18)).point(lambda v: min(255, int(v * 1.1)))
    thumb.alpha_composite(Image.merge("RGBA", (Image.new("L", thumb.size, 16), Image.new("L", thumb.size, 34),
                                                Image.new("L", thumb.size, 58), shadow)))
    thumb.alpha_composite(logo, pos)
    thumb.convert("RGB").save(os.path.join(HERE, "Thumbnail.png"))

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
