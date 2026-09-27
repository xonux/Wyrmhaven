"""Software renderer for previews: orthographic, z-buffer, smooth shading
with a key light, fill light and rim light over a sky/grass backdrop."""
import math

import numpy as np
from PIL import Image


def look(yaw_deg, pitch_deg):
    y, p = math.radians(yaw_deg), math.radians(pitch_deg)
    fwd = np.array([-math.cos(p) * math.sin(y), -math.sin(p), -math.cos(p) * math.cos(y)])  # camera looks along fwd
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    return right, up, fwd


def render(verts, faces, vcolors, vnormals, yaw, pitch, size=800, scale=None, center=None, bg=True, texture=None):
    """vcolors: per-vertex RGB, or per-vertex UV when texture (HxWx3 array) is given."""
    right, up, fwd = look(yaw, pitch)
    X, Y, Z = verts @ right, verts @ up, verts @ fwd
    if center is None:
        center = np.array([(X.min() + X.max()) / 2, (Y.min() + Y.max()) / 2])
    if scale is None:
        scale = 0.86 * size / max(X.max() - X.min(), Y.max() - Y.min())
    sx = (X - center[0]) * scale + size / 2
    sy = size / 2 - (Y - center[1]) * scale
    zbuf = np.full((size, size), np.inf)
    img_c = np.zeros((size, size, vcolors.shape[1]))
    img_n = np.zeros((size, size, 3))
    mask = np.zeros((size, size), bool)
    for f in faces:
        x, y, z = sx[f], sy[f], Z[f]
        x0, x1 = max(int(x.min()), 0), min(int(x.max()) + 1, size - 1)
        y0, y1 = max(int(y.min()), 0), min(int(y.max()) + 1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
        if abs(den) < 1e-12:
            continue
        px, py = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((y[1] - y[2]) * (px - x[2]) + (x[2] - x[1]) * (py - y[2])) / den
        w1 = ((y[2] - y[0]) * (px - x[2]) + (x[0] - x[2]) * (py - y[2])) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        depth = w0 * z[0] + w1 * z[1] + w2 * z[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        win = inside & (depth < sub)
        if not win.any():
            continue
        sub[win] = depth[win]
        W = np.stack([w0[win], w1[win], w2[win]], axis=1)
        img_c[y0:y1 + 1, x0:x1 + 1][win] = W @ vcolors[f]
        img_n[y0:y1 + 1, x0:x1 + 1][win] = W @ vnormals[f]
        mask[y0:y1 + 1, x0:x1 + 1][win] = True

    if texture is not None:
        th, tw = texture.shape[:2]
        u = np.clip((img_c[..., 0] * (tw - 1)).astype(int), 0, tw - 1)
        v = np.clip(((1 - img_c[..., 1]) * (th - 1)).astype(int), 0, th - 1)
        img_c = texture[v, u].astype(float)
    n = img_n / np.maximum(np.linalg.norm(img_n, axis=-1, keepdims=True), 1e-9)
    key = np.array([0.35, 0.8, 0.5]); key /= np.linalg.norm(key)
    key = key[0] * right + key[1] * up - key[2] * fwd
    fill = -fwd
    diff = np.clip(n @ key, 0, 1)
    wrap = np.clip((n @ fill + 0.4) / 1.4, 0, 1)
    rim = np.clip(1 - np.abs(n @ fwd), 0, 1) ** 3
    spec = np.clip(n @ ((key - fwd) / np.linalg.norm(key - fwd)), 0, 1) ** 30
    col = img_c / 255.0
    shade = col * (0.38 + 0.55 * diff[..., None] + 0.2 * wrap[..., None]) + 0.18 * rim[..., None] + 0.18 * spec[..., None]
    shade = np.clip(shade, 0, 1)

    if bg:
        t = np.linspace(0, 1, size)[:, None, None]
        sky = np.array([0.55, 0.78, 0.95]) * (1 - t) + np.array([0.86, 0.94, 0.98]) * t
        back = np.broadcast_to(sky, (size, size, 3)).copy()
        ground_y = size / 2 - (0 * up[1] - center[1]) * scale  # rough horizon
        back[int(min(max(size * 0.72, 0), size)):] = [0.42, 0.66, 0.26]
    else:
        back = np.full((size, size, 3), 0.95)
    out = np.where(mask[..., None], shade, back)
    return Image.fromarray((out * 255).astype(np.uint8))
