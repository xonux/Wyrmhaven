"""UV-unwraps the decimated mesh, bakes the color field into a texture and
exports GLB + OBJ for Roblox Studio (File > Import 3D). Run build_dragon.py first."""
import os

import numpy as np
import trimesh
import xatlas
from PIL import Image, ImageFilter

from build_dragon import build_parts, colors_at

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = 1024
NAME = "BabyFireDragon"


def bake(parts, verts, faces, uvs):
    """For every texel covered by a UV triangle, evaluate the color field at
    the matching 3D point."""
    px_all, pos_all = [], []
    for f in faces:
        uv = uvs[f] * (TEX - 1)
        uv[:, 1] = (TEX - 1) - uv[:, 1]
        x0, x1 = int(np.floor(uv[:, 0].min())), int(np.ceil(uv[:, 0].max()))
        y0, y1 = int(np.floor(uv[:, 1].min())), int(np.ceil(uv[:, 1].max()))
        px, py = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        px, py = px.ravel(), py.ravel()
        (ax, ay), (bx, by), (cx, cy) = uv
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        w0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        w1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        w2 = 1 - w0 - w1
        eps = 0.02  # a little outside the triangle too, then dilate below
        inside = (w0 >= -eps) & (w1 >= -eps) & (w2 >= -eps)
        if not inside.any():
            continue
        W = np.clip(np.stack([w0[inside], w1[inside], w2[inside]], 1), 0, None)
        W /= W.sum(1, keepdims=True)
        px_all.append(np.stack([px[inside], py[inside]], 1))
        pos_all.append(W @ verts[f])
    px_all = np.concatenate(px_all)
    pos_all = np.concatenate(pos_all)
    ok = (px_all[:, 0] >= 0) & (px_all[:, 0] < TEX) & (px_all[:, 1] >= 0) & (px_all[:, 1] < TEX)
    px_all, pos_all = px_all[ok], pos_all[ok]
    cols = np.empty((len(pos_all), 3))
    for i in range(0, len(pos_all), 200_000):
        cols[i:i + 200_000] = colors_at(parts, pos_all[i:i + 200_000])
    img = np.zeros((TEX, TEX, 3), np.uint8)
    filled = np.zeros((TEX, TEX), bool)
    img[px_all[:, 1], px_all[:, 0]] = cols.astype(np.uint8)
    filled[px_all[:, 1], px_all[:, 0]] = True
    # dilate the islands so mip-mapping never pulls in the empty background
    im = Image.fromarray(img)
    mask = Image.fromarray(filled.astype(np.uint8) * 255)
    for _ in range(8):
        grown = im.filter(ImageFilter.MaxFilter(3))
        im = Image.composite(im, grown, mask)
        mask = mask.filter(ImageFilter.MaxFilter(3))
    return im


def main():
    mesh = trimesh.load(os.path.join(HERE, "_raw.ply"), process=False)
    vmap, faces, uvs = xatlas.parametrize(mesh.vertices, mesh.faces)
    verts = mesh.vertices[vmap]
    print("unwrapped:", len(verts), "verts,", len(faces), "faces")
    tex = bake(build_parts(), verts, faces, uvs)
    material = trimesh.visual.material.PBRMaterial(name=NAME, baseColorTexture=tex, metallicFactor=0.0, roughnessFactor=0.8)
    out = trimesh.Trimesh(verts, faces, visual=trimesh.visual.TextureVisuals(uv=uvs, material=material), process=False)
    out.export(os.path.join(HERE, f"{NAME}.glb"))
    out.visual.material = trimesh.visual.material.SimpleMaterial(name=NAME, image=tex)
    out.export(os.path.join(HERE, f"{NAME}.obj"), mtl_name=f"{NAME}.mtl")
    # full diffuse so importers don't darken the texture
    mtl = os.path.join(HERE, f"{NAME}.mtl")
    with open(mtl) as f:
        text = f.read().replace("Kd 0.40000000 0.40000000 0.40000000", "Kd 1.00000000 1.00000000 1.00000000")
    with open(mtl, "w") as f:
        f.write(text)
    print("exported")


if __name__ == "__main__":
    main()
