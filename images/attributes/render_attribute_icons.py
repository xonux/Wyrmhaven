"""Renders Wyrmhaven attribute icons (passive traits) in the status icon
style, on a blue tile. "...Ward" attributes protect against a status or a
family of statuses: the status glyph with a small gold shield in the corner.
Every ward matches a bad status of Config/StatusDefs (keep the two in step);
DotWard / ControlWard / DebuffWard cover a whole family, future ones included.
Uses the tile/glyph kit of images/statuses/render_status_icons.py.
Output: <Attribute>.png (256px) next to this script.
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "statuses"))
import render_status_icons as K  # noqa: E402
from render_status_icons import Layer, bezier, fit, star  # noqa: E402

WARDED = (0.8, -0.06, -0.06)  # glyph scale / shift leaving room for the ward badge


def g_debuffs():
    """Any debuff: a big down arrow."""
    return [Layer().poly(K.arrow_pts(0.5, 0.16, 0.84, 0.56, up=False))]


def g_dots():
    """Any damage over time, present or future: a jagged hit with clock hands
    (damage that ticks). Deliberately tied to no element or status."""
    hit = Layer().poly(K.star(0.5, 0.5, 0.36, 0.25, n=9, rot=-math.pi / 2))
    hit.circle(0.5, 0.5, 0.17, hole=True)
    hands = Layer().line([(0.5, 0.5), (0.5, 0.39)], 0.045).line([(0.5, 0.5), (0.58, 0.55)], 0.045)
    return [hit, hands]


def g_wither():
    return [Layer().poly(K.heart(0.5, 0.5, 0.3))]


def g_chain():
    """Broken chain: free from every control."""
    c = Layer()

    def link(cx, cy, rx, ry, w, ang):
        a = math.radians(ang)
        for r_x, r_y, hole in ((rx, ry, False), (rx - w, ry - w, True)):
            pts = []
            for i in range(64):
                t = i / 64 * math.tau
                x, y = r_x * math.cos(t), r_y * math.sin(t)
                pts.append((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)))
            c.poly(pts, hole)

    link(0.31, 0.69, 0.21, 0.135, 0.08, -45)
    link(0.69, 0.31, 0.21, 0.135, 0.08, -45)
    sparks = Layer()
    for (x0, y0, x1, y1) in ((0.44, 0.44, 0.36, 0.36), (0.56, 0.56, 0.64, 0.64)):
        sparks.line([(x0, y0), (x1, y1)], 0.04)
    return [c, sparks]


ATTRIBUTES = {
    # name: (glyph, warded)
    "Taunt": (K.g_target, False),
    "Thorns": (K.g_thorns, False),
    "Regen": (K.g_regen, False),
    "Evade": (K.g_evade, False),
    "Revive": (K.g_revive, False),
    "Lifesteal": (K.g_lifesteal, False),
    "Counter": (K.g_counter, False),
    # damage over time (DotWard's generic glyph covers every Dot, future ones included)
    "BurnWard": (K.g_flame, True),  # Singe + Burn
    "PoisonWard": (K.g_skull, True),
    "BleedWard": (K.g_bleed, True),
    "DotWard": (g_dots, True),
    # controls (StatusDefs.Controls) - ControlWard covers them all
    "StunWard": (K.g_stun, True),
    "FreezeWard": (K.g_freeze, True),
    "SleepWard": (K.g_sleep, True),
    "ControlWard": (g_chain, True),
    # hindrances
    "SilenceWard": (K.g_silence, True),
    "BlindWard": (K.g_blind, True),
    "ConfuseWard": (K.g_confuse, True),
    "ExposeWard": (K.g_expose, True),
    # stat debuffs: Weaken/Cripple (Attack), Slow/Root (Speed), Wither (Health)
    "WeakenWard": (K.g_sword, True),
    "SlowWard": (K.g_ffwd, True),
    "WitherWard": (g_wither, True),
    "DebuffWard": (g_debuffs, True),
}


def render(glyph, warded):
    img = K.tile("attribute")
    K.stamp(img, glyph(), WARDED if warded else None)
    if warded:
        K.ward(img)
    return img.resize((K.T, K.T), Image.LANCZOS)


def main():
    for name, spec in ATTRIBUTES.items():
        render(*spec).save(os.path.join(HERE, f"{name}.png"))
    print("ok", len(ATTRIBUTES))


if __name__ == "__main__":
    main()
