"""Writes the rarity badges (Common, Rare, Epic, Legendary) as SVGs, in the
same plain flat style as images/ui/Combat.svg: a hexagon in the rarity's
colour, split in a light and a shaded half, with its initial in white.
Render each one with ../ui/svg2png.cjs (then downscale to 512px)."""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# id: (letter, light half, shaded half)
RARITIES = {
    "Common": ("C", "#a7b0ba", "#8a949f"),
    "Rare": ("R", "#4d9be6", "#3a7fc6"),
    "Epic": ("E", "#a466dc", "#8a4cc2"),
    "Legendary": ("L", "#f2ae2e", "#dc931a"),
}


def hexagon(r, cx=256, cy=256):
    pts = [(cx + r * math.sin(math.pi / 3 * i), cy - r * math.cos(math.pi / 3 * i)) for i in range(6)]
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)


def svg(letter, light, shade):
    # the shaded half is the right-hand side, as on the sword blades
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <clipPath id="right"><rect x="256" y="0" width="256" height="512"/></clipPath>
  <polygon points="{hexagon(236)}" fill="{light}" stroke="{light}" stroke-width="28" stroke-linejoin="round"/>
  <polygon points="{hexagon(236)}" fill="{shade}" stroke="{shade}" stroke-width="28" stroke-linejoin="round" clip-path="url(#right)"/>
  <text x="256" y="256" dy="0.35em" text-anchor="middle" font-family="Liberation Sans, Arial, sans-serif"
        font-weight="700" font-size="300" fill="#ffffff">{letter}</text>
</svg>
"""


for name, (letter, light, shade) in RARITIES.items():
    with open(os.path.join(HERE, f"{name}.svg"), "w") as f:
        f.write(svg(letter, light, shade))
print("ok", len(RARITIES))
