"""Preview sheet of the exported (textured) model."""
import os, sys
import numpy as np, trimesh
from PIL import Image
from render_preview import render
HERE = os.path.dirname(os.path.abspath(__file__))
m = trimesh.load(os.path.join(HERE, "BabyFireDragon.glb"), force="mesh", process=False)
tex = np.asarray(m.visual.material.baseColorTexture.convert("RGB"))
uv = np.asarray(m.visual.uv)
views = [(35, 10), (0, 5), (90, 5), (-145, 20)]  # 3/4 like the reference, side, front, back 3/4
imgs = [render(m.vertices, m.faces, uv, m.vertex_normals, y, p, size=600, texture=tex) for y, p in views]
sheet = Image.new("RGB", (1200, 1200))
for i, im in enumerate(imgs):
    sheet.paste(im, ((i % 2) * 600, (i // 2) * 600))
sheet.save(os.path.join(HERE, "preview_views.png"))

# hero shot next to the reference
ref = Image.open(os.path.join(HERE, "..", "..", "references", "dragon_baby.jpg")).convert("RGB")
hero = render(m.vertices, m.faces, uv, m.vertex_normals, 35, 10, size=900, texture=tex)
ref = ref.resize((int(ref.width * 900 / ref.height), 900), Image.LANCZOS)
cmp_ = Image.new("RGB", (ref.width + 900, 900))
cmp_.paste(ref, (0, 0))
cmp_.paste(hero, (ref.width, 0))
cmp_.save(os.path.join(HERE, "preview_comparison.png"))
