"""Renders Wyrmhaven attribute icons (passive traits) in the status icon
style, on a blue tile. "...Ward" attributes protect against a status or a
family of statuses: the status glyph with a small gold shield in the corner.
Uses the tile/glyph kit of images/elements/render_status_icons.py.
Output: <Attribute>.png (256px) next to this script.
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "elements"))
import render_status_icons as K  # noqa: E402
from render_status_icons import Layer, bezier, fit, star  # noqa: E402

WARDED = (0.8, -0.06, -0.06)  # glyph scale / shift leaving room for the ward badge


def g_debuffs():
    """Any debuff: a big down arrow."""
    return [Layer().poly(K.arrow_pts(0.5, 0.16, 0.84, 0.56, up=False))]


def g_dots():
    """Every damage-over-time: flame, drop and skull together."""
    out = []
    for glyph, scale, dx, dy in ((K.g_flame, 0.55, -0.18, -0.16), (K.g_bleed, 0.5, 0.18, -0.16), (K.g_skull, 0.55, 0.0, 0.17)):
        for lay in glyph():
            lay.img = fit(lay.img, scale, dx, dy)
            out.append(lay)
    return out


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


def g_lifesteal():
    """Fangs dripping a drop."""
    f = Layer()
    f.line(bezier([(0.16, 0.26), (0.36, 0.4), (0.64, 0.4), (0.84, 0.26)]), 0.07)
    for x in (0.34, 0.66):
        f.poly([(x - 0.07, 0.36), (x + 0.07, 0.36), (x, 0.6)])
    K.drop(f, 0.66, 0.74, 0.07, 0.56)
    return [f]


def g_counter():
    """Sword with a return arrow."""
    arc = Layer().arc(0.5, 0.52, 0.32, 200, 330, 0.055)
    e = math.radians(200)
    end = (0.5 + 0.32 * math.cos(e), 0.52 + 0.32 * math.sin(e))
    tan = (math.sin(e), -math.cos(e))  # travel direction at the start, going backwards
    nrm = (math.cos(e), math.sin(e))
    arc.poly([(end[0] + tan[0] * 0.1, end[1] + tan[1] * 0.1), (end[0] + nrm[0] * 0.075, end[1] + nrm[1] * 0.075),
              (end[0] - nrm[0] * 0.075, end[1] - nrm[1] * 0.075)])
    sw = K.g_sword()
    for lay in sw:
        lay.img = fit(lay.img, 0.8, 0.02, 0.08)
    return [arc] + sw


ATTRIBUTES = {
    # name: (glyph, warded)
    "Taunt": (K.g_target, False),
    "Thorns": (K.g_thorns, False),
    "Regen": (K.g_regen, False),
    "Evade": (K.g_evade, False),
    "Revive": (K.g_revive, False),
    "Lifesteal": (g_lifesteal, False),
    "Counter": (g_counter, False),
    # damage over time
    "BurnWard": (K.g_flame, True),
    "PoisonWard": (K.g_skull, True),
    "BleedWard": (K.g_bleed, True),
    "DotWard": (g_dots, True),
    # controls
    "StunWard": (K.g_stun, True),
    "FreezeWard": (K.g_freeze, True),
    "SleepWard": (K.g_sleep, True),
    "SilenceWard": (K.g_silence, True),
    "BlindWard": (K.g_blind, True),
    "ConfuseWard": (K.g_confuse, True),
    "ControlWard": (g_chain, True),
    # stat debuffs
    "SlowWard": (K.g_ffwd, True),
    "WeakenWard": (K.g_sword, True),
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
