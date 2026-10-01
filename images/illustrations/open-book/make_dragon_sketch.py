"""Ink drawing of the baby fire dragon for the book's left page: the 3D test
model (models/baby-fire-dragon) rendered as sepia line art - outlines where
depth or surface direction jumps, hatching in the shadows.
Output: DragonSketch.png (transparent, ink only)."""
import math
import os

import numpy as np
import trimesh
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "..", "..", "..", "models", "baby-fire-dragon", "BabyFireDragon.glb")
SIZE = 1400
INK = (62, 38, 22)


def raster(verts, faces, uv, yaw, pitch, size):
    y, p = math.radians(yaw), math.radians(pitch)
    fwd = np.array([-math.cos(p) * math.sin(y), -math.sin(p), -math.cos(p) * math.cos(y)])
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    X, Y, Z = verts @ right, verts @ up, verts @ fwd
    scale = 0.9 * size / max(X.max() - X.min(), Y.max() - Y.min())
    sx = (X - (X.min() + X.max()) / 2) * scale + size / 2
    sy = size / 2 - (Y - (Y.min() + Y.max()) / 2) * scale
    fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    zbuf = np.full((size, size), np.inf)
    nbuf = np.zeros((size, size, 3))
    uvbuf = np.zeros((size, size, 2))
    for i, f in enumerate(faces):
        x, yy, z = sx[f], sy[f], Z[f]
        x0, x1 = max(int(x.min()), 0), min(int(x.max()) + 1, size - 1)
        y0, y1 = max(int(yy.min()), 0), min(int(yy.max()) + 1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        den = (yy[1] - yy[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (yy[0] - yy[2])
        if abs(den) < 1e-12:
            continue
        px, py = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((yy[1] - yy[2]) * (px - x[2]) + (x[2] - x[1]) * (py - yy[2])) / den
        w1 = ((yy[2] - yy[0]) * (px - x[2]) + (x[0] - x[2]) * (py - yy[2])) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        depth = w0 * z[0] + w1 * z[1] + w2 * z[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        win = inside & (depth < sub)
        if not win.any():
            continue
        sub[win] = depth[win]
        nbuf[y0:y1 + 1, x0:x1 + 1][win] = fn[i]
        W = np.stack([w0[win], w1[win], w2[win]], axis=1)
        uvbuf[y0:y1 + 1, x0:x1 + 1][win] = W @ uv[f]
    return zbuf, nbuf, uvbuf, (right, up, fwd)


def main():
    m = trimesh.load(MODEL, force="mesh", process=False)
    uv = np.asarray(m.visual.uv)
    tex = np.asarray(m.visual.material.baseColorTexture.convert("RGB")).astype(float)
    zbuf, nbuf, uvbuf, (right, up, fwd) = raster(m.vertices, m.faces, uv, 35, 10, SIZE)
    mask = np.isfinite(zbuf)
    z = np.where(mask, zbuf, zbuf[mask].max() + 1)

    # outlines: silhouette + depth jumps + creases (normal changes)
    def jump(a, axis):
        return np.abs(np.diff(a, axis=axis, append=np.take(a, [-1], axis=axis)))
    dz = np.maximum(jump(z, 0), jump(z, 1))
    n = nbuf
    dn = np.maximum(np.linalg.norm(np.diff(n, axis=0, append=n[-1:]), axis=-1),
                    np.linalg.norm(np.diff(n, axis=1, append=n[:, -1:]), axis=-1))
    inner = np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(5))) > 0
    sil = mask & ~inner
    # the texture's colors: their edges (eye, belly plates) become lines too,
    # and the darkest parts (pupils) are filled with ink
    th, tw = tex.shape[:2]
    tu = np.clip((uvbuf[..., 0] * (tw - 1)).astype(int), 0, tw - 1)
    tv = np.clip(((1 - uvbuf[..., 1]) * (th - 1)).astype(int), 0, th - 1)
    lum = tex[tv, tu] @ np.array([0.3, 0.59, 0.11])
    lum = np.asarray(Image.fromarray(np.clip(lum, 0, 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5))).astype(float)
    dl = np.maximum(jump(lum, 0), jump(lum, 1))
    pupil = mask & (lum < 70)
    lines = sil | (dz > 0.06) | ((dn > 0.9) & mask) | (mask & (dl > 38)) | pupil
    line_img = Image.fromarray((lines * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))

    # light from the upper left: hatch the shadows, cross-hatch the deep ones
    light = np.array([0.4, 0.8, 0.45]); light /= np.linalg.norm(light)
    lw = light[0] * right + light[1] * up - light[2] * fwd
    lam = np.clip(n @ lw, 0, 1)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    hatch1 = ((xx + yy) % 12) < 2
    hatch2 = ((xx - yy) % 12) < 2
    shade = (mask & (lam < 0.22) & hatch1) | (mask & (lam < 0.08) & hatch2)
    shade_img = Image.fromarray((shade * 150).astype(np.uint8))

    ink = Image.composite(line_img, shade_img, line_img)
    ink = ink.filter(ImageFilter.GaussianBlur(0.7))
    out = Image.new("RGBA", (SIZE, SIZE), INK + (0,))
    out.putalpha(ink)
    out = out.crop(out.getbbox())
    out.save(os.path.join(HERE, "DragonSketch.png"))
    print("sketch", out.size)


if __name__ == "__main__":
    main()
