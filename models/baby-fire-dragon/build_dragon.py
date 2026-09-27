"""Test: a smooth baby fire dragon modeled after references/dragon_baby.jpg.

The shape is a signed distance field (spheres, ellipsoids and round cones
blended with smooth unions), meshed with marching cubes, decimated for
Roblox (< 20k triangles), UV-unwrapped and its colors baked into a texture.
Outputs (next to this script): BabyFireDragon.glb, BabyFireDragon.obj/.mtl,
BabyFireDragon_color.png and preview_*.png.

Model space: Y up, ground at Y = 0, the dragon faces +X, its left side is +Z.
"""
import math
import os
import sys

import numpy as np
import trimesh
from skimage import measure

HERE = os.path.dirname(os.path.abspath(__file__))
V = lambda *a: np.array(a, dtype=np.float64)

# ------------------------------------------------------------------ colors
ORANGE = V(238, 112, 34)
ORANGE_LIGHT = V(252, 150, 58)
ORANGE_DARK = V(206, 78, 22)
CREAM = V(255, 204, 128)
CREAM_LINE = V(236, 160, 84)
HORN0 = V(232, 98, 28)
HORN1 = V(255, 176, 72)
IRIS = V(255, 170, 30)
IRIS_DARK = V(214, 104, 10)
PUPIL = V(40, 18, 10)
RIM = V(120, 40, 12)
GLINT = V(255, 250, 235)
CLAW = V(255, 226, 180)


# ------------------------------------------------------------------ SDF primitives
def length(v):
    return np.sqrt(np.sum(v * v, axis=-1))


def sd_sphere(p, c, r):
    return length(p - c) - r


def sd_ellipsoid(p, c, r, rot=None):
    q = p - c
    if rot is not None:
        q = q @ rot  # columns of rot = local axes in world space
    k0 = length(q / r)
    k1 = length(q / (r * r))
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_round_cone(p, a, b, r1, r2):
    """Inigo Quilez's round cone between a (radius r1) and b (radius r2).
    Also returns t, the position along a->b in [0, 1]."""
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    w = pa * l2 - np.outer(y, ba)
    x2 = np.sum(w * w, axis=-1)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d_b = np.sqrt(x2 + z2) * il2 - r2
    d_a = np.sqrt(x2 + y2) * il2 - r1
    d_m = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
    d = np.where(np.sign(z) * a2 * z2 > k, d_b, np.where(np.sign(y) * a2 * y2 < k, d_a, d_m))
    return d, np.clip(y * il2, 0, 1)


def bezier(ctrl, t):
    pts = [np.asarray(c, float) for c in ctrl]
    while len(pts) > 1:
        pts = [pts[i] + (pts[i + 1] - pts[i]) * t for i in range(len(pts) - 1)]
    return pts[0]


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


# ------------------------------------------------------------------ the model
class Part:
    """One primitive: sdf(p) -> (d, t) and color(p, t) -> rgb."""

    def __init__(self, sdf, color, blend=0.12, carve=False, group="skin"):
        self.sdf, self.color, self.blend, self.carve, self.group = sdf, color, blend, carve, group


def const(c):
    return lambda p, t: np.tile(c, (len(p), 1))


def grad(c0, c1, power=1.0):
    return lambda p, t: c0 + np.outer(t ** power, c1 - c0)


def sphere(c, r, color, **kw):
    return Part(lambda p: (sd_sphere(p, c, r), None), color, **kw)


def ellipsoid(c, r, color, rot=None, **kw):
    return Part(lambda p: (sd_ellipsoid(p, c, np.asarray(r, float), rot), None), color, **kw)


def cone(a, b, r1, r2, color, **kw):
    return Part(lambda p: sd_round_cone(p, a, b, r1, r2), color, **kw)


def chain(ctrl, r0, r1, color, steps=8, taper=1.0, **kw):
    """Tapered tube along a Bezier curve; t runs 0 -> 1 from base to tip."""
    ts = np.linspace(0, 1, steps + 1)
    pts = [bezier(ctrl, t) for t in ts]
    rad = [r1 + (r0 - r1) * (1 - t) ** taper for t in ts]

    def sdf(p):
        best_d, best_t = None, None
        for i in range(steps):
            d, t = sd_round_cone(p, pts[i], pts[i + 1], rad[i], rad[i + 1])
            t = (i + t) / steps
            if best_d is None:
                best_d, best_t = d, t
            else:
                m = d < best_d
                best_d = np.minimum(best_d, d)
                best_t = np.where(m, t, best_t)
        return best_d, best_t

    return Part(sdf, color, **kw)


def flat_chain(ctrl, r0, r1, color, flat_axis, flat=0.45, **kw):
    """A chain squashed along flat_axis (flame tongues, fins)."""
    n = flat_axis / np.linalg.norm(flat_axis)
    S = np.eye(3) + (1 / flat - 1) * np.outer(n, n)  # stretch space along n
    c = [np.asarray(q, float) for q in ctrl]
    ctr = sum(c) / len(c)
    inner = chain([ctr + (q - ctr) @ S for q in c], r0, r1, color, **kw)

    def sdf(p):
        d, t = inner.sdf(ctr + (p - ctr) @ S)
        return d * flat, t

    return Part(sdf, color, blend=kw.get("blend", 0.12), group=kw.get("group", "skin"))


def frame(fwd, up):
    f = fwd / np.linalg.norm(fwd)
    u = up - f * (up @ f)
    u /= np.linalg.norm(u)
    return np.stack([f, u, np.cross(f, u)], axis=1)  # columns: fwd, up, side


def eye_part(c, r, normal, up, glint_dir):
    n = normal / np.linalg.norm(normal)
    u = up - n * (up @ n)
    u /= np.linalg.norm(u)
    g = glint_dir / np.linalg.norm(glint_dir)

    def color(p, t):
        d = p - c
        d /= np.maximum(length(d), 1e-9)[:, None]
        ang = np.degrees(np.arccos(np.clip(d @ n, -1, 1)))
        vert = d @ u  # top of the iris darker, bottom lighter
        iris = IRIS + np.outer(np.clip(vert * 1.6, 0, 1), IRIS_DARK - IRIS)
        out = np.where((ang < 13)[:, None], PUPIL, iris)
        out = np.where(((ang > 43) & (ang < 50))[:, None], RIM, out)
        out = np.where((ang >= 50)[:, None], ORANGE, out)
        glint = np.degrees(np.arccos(np.clip(d @ g, -1, 1))) < 9
        return np.where(glint[:, None], GLINT, out)

    return Part(lambda p: (sd_sphere(p, c, r), None), color, blend=0.0, group="eye")


def belly_color(axis_a, axis_b, bands):
    """Cream with darker lines across it (belly plates)."""
    a, b = np.asarray(axis_a, float), np.asarray(axis_b, float)
    ab = b - a

    def color(p, t):
        s = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
        k = np.clip((0.3 - np.abs(np.sin(s * bands * math.pi))) / 0.15, 0, 1)
        return CREAM + np.outer(k, CREAM_LINE - CREAM)

    return color


def build_parts():
    P = []
    add = P.append

    # --- head (cranium center H, snout pointing forward-down); drawn at
    # unit size and scaled by HS about H so its size is one knob
    H, HS = V(1.25, 2.3, 0), 1.18

    def h(x, y, z):
        return H + HS * V(x, y, z)

    add(ellipsoid(H + HS * V(-0.08, 0.05, 0), HS * np.array([0.66, 0.74, 0.6]), const(ORANGE), blend=0.2))
    # long muzzle angled down-forward, chin tucked
    add(cone(h(0.15, -0.25, 0), h(0.72, -0.86, 0), 0.5 * HS, 0.27 * HS, const(ORANGE), blend=0.28))
    add(sphere(h(0.78, -0.9, 0), 0.22 * HS, const(ORANGE_LIGHT), blend=0.2))  # nose tip
    for s in (-1, 1):
        add(sphere(h(0.08, -0.45, 0.32 * s), 0.36 * HS, const(ORANGE), blend=0.25))  # cheeks
    add(cone(h(-0.08, -0.62, 0), h(0.5, -1.05, 0), 0.3 * HS, 0.18 * HS, const(ORANGE_LIGHT), blend=0.18))  # jaw
    add(flat_chain([h(0.35, -1.1, 0), h(0.25, -1.2, 0), h(0.12, -1.24, 0)], 0.13 * HS, 0.06,
                   grad(ORANGE_LIGHT, ORANGE), V(0, 0, 1), flat=0.6, steps=4, blend=0.12))  # chin plate
    for s in (-1, 1):
        add(chain([h(0.05, -0.66, 0.4 * s), h(0.4, -0.84, 0.3 * s), h(0.7, -1.0, 0.14 * s), h(0.86, -1.07, 0.0)],
                  0.028, 0.02, const(ORANGE_DARK), steps=6, blend=0.04, carve=True))  # mouth
        add(sphere(h(0.93, -0.75, 0.12 * s), 0.035, const(ORANGE_DARK), blend=0.04, carve=True))  # nostrils

    # --- almond eyes: heavy upper lid, thin lower lid, a fan of leaf scales
    leaf = grad(ORANGE_LIGHT, ORANGE, 1.0)
    for s in (-1, 1):
        n = V(0.6, 0.05, 0.8 * s)
        n /= np.linalg.norm(n)
        ec = h(0.3, 0.02, 0.45 * s)
        er = 0.29 * HS
        add(eye_part(ec, er, n, V(0, 1, 0), n + V(0.25, 0.55, 0)))
        fwd = np.cross(V(0, 1, 0), n) * -s  # along the eye, toward the snout
        fwd /= np.linalg.norm(fwd)
        R = frame(fwd + V(0, -0.2, 0), V(0, 1, 0))
        add(ellipsoid(ec + HS * V(0, 0.17, 0) + n * 0.02, HS * np.array([0.36, 0.13, 0.26]), const(ORANGE_LIGHT), rot=R, blend=0.06))
        R2 = frame(fwd + V(0, 0.2, 0), V(0, 1, 0))
        add(ellipsoid(ec + HS * V(0, -0.24, 0) + n * 0.0, HS * np.array([0.34, 0.08, 0.26]), const(ORANGE), rot=R2, blend=0.06))
        up = V(0, 1, 0)
        for ang, ln, rr in ((95, 0.42, 0.14), (135, 0.5, 0.15), (175, 0.44, 0.13)):
            a = math.radians(ang)
            d = fwd * math.cos(a) + up * math.sin(a)
            base = ec + d * er * 0.95 * HS - n * 0.02
            tip = base + (d * 0.85 - fwd * 0.4) * ln * HS
            add(flat_chain([base, (base + tip) / 2 + n * 0.05, tip], rr * HS, 0.05, leaf, n, flat=0.6, steps=5, blend=0.07))

    # --- crest: a few wide, flat, wavy flame lobes sweeping back
    horn = grad(HORN0, HORN1, 1.4)
    add(flat_chain([h(-0.05, 0.5, 0), h(-0.1, 1.15, 0), h(-0.6, 1.4, 0), h(-0.42, 2.05, 0)],
                   0.44 * HS, 0.08, horn, V(0, 0, 1), flat=0.32, steps=14, taper=0.6, blend=0.2))
    for s in (-1, 1):
        add(flat_chain([h(-0.4, 0.45, 0.22 * s), h(-0.85, 0.95, 0.28 * s), h(-1.35, 0.85, 0.32 * s), h(-1.5, 1.4, 0.34 * s)],
                       0.38 * HS, 0.07, horn, V(0.1, -0.1, 1 * s), flat=0.32, steps=14, taper=0.6, blend=0.2))
        add(flat_chain([h(-0.55, 0.05, 0.32 * s), h(-1.0, 0.3, 0.4 * s), h(-1.55, 0.1, 0.44 * s), h(-1.9, 0.5, 0.46 * s)],
                       0.32 * HS, 0.06, horn, V(0.1, -0.2, 1 * s), flat=0.32, steps=14, taper=0.6, blend=0.2))
        add(flat_chain([h(-0.35, -0.4, 0.44 * s), h(-0.8, -0.4, 0.52 * s), h(-1.1, -0.25, 0.56 * s), h(-1.28, 0.08, 0.58 * s)],
                       0.2 * HS, 0.05, horn, V(0.1, -0.2, 1 * s), flat=0.35, steps=10, taper=0.7, blend=0.15))  # cheek fins

    # --- neck with belly plates
    add(cone(V(0.95, 1.75, 0), V(0.45, 0.95, 0), 0.3, 0.38, const(ORANGE), blend=0.25))
    add(cone(V(1.18, 1.55, 0), V(0.72, 0.72, 0), 0.24, 0.32,
             belly_color(V(1.18, 1.55, 0), V(0.72, 0.72, 0), 5), blend=0.1))

    # --- body, chest and belly
    add(ellipsoid(V(-0.1, 0.62, 0), (0.72, 0.38, 0.44), const(ORANGE), blend=0.3))
    add(sphere(V(0.45, 0.72, 0), 0.4, const(ORANGE), blend=0.3))  # chest
    add(ellipsoid(V(0.1, 0.46, 0), (0.62, 0.24, 0.33), belly_color(V(0.7, 0.5, 0), V(-0.6, 0.45, 0), 4), blend=0.08))
    for x in (0.1, -0.35):  # little back ridges
        add(flat_chain([V(x, 0.92, 0), V(x - 0.12, 1.12, 0), V(x - 0.25, 1.2, 0)], 0.1, 0.02, horn, V(0, 0, 1),
                       flat=0.5, steps=4, blend=0.08))

    # --- legs (front: thin and straight, back: big haunch), 3 claws per paw
    def paw(heel, fwd_x, s, size):
        add(ellipsoid(heel + V(0.1 * size, 0.07 * size, 0), (0.22 * size, 0.1 * size, 0.15 * size), const(ORANGE), blend=0.08))
        for k in (-1, 0, 1):
            base = heel + V(0.28 * size, 0.05 * size, k * 0.1 * size)
            add(cone(base, base + V(0.12 * size, -0.03 * size, k * 0.03 * size), 0.05 * size, 0.012, const(CLAW), blend=0.02))

    for s in (-1, 1):
        # front legs
        add(cone(V(0.5, 0.75, 0.28 * s), V(0.62, 0.35, 0.33 * s), 0.16, 0.12, const(ORANGE), blend=0.15))
        add(cone(V(0.62, 0.35, 0.33 * s), V(0.66, 0.08, 0.36 * s), 0.12, 0.1, const(ORANGE), blend=0.08))
        paw(V(0.62, 0.0, 0.36 * s), 1, s, 0.9)
        # back legs
        add(ellipsoid(V(-0.5, 0.58, 0.32 * s), (0.34, 0.3, 0.2), const(ORANGE), blend=0.2))
        add(cone(V(-0.45, 0.4, 0.38 * s), V(-0.28, 0.1, 0.4 * s), 0.15, 0.11, const(ORANGE), blend=0.1))
        paw(V(-0.3, 0.0, 0.4 * s), 1, s, 1.0)

    # --- small raised wings: an arm, a rounded membrane and flame-tipped edge
    for s in (-1, 1):
        sh = V(0.25, 0.9, 0.3 * s)
        el = V(-0.1, 1.3, 0.42 * s)
        add(cone(sh, el, 0.1, 0.07, const(ORANGE), blend=0.08))
        R = frame(V(-1, 0.25, 0), V(0, 1, 0.15 * s))
        add(ellipsoid(V(-0.45, 1.2, 0.44 * s), (0.42, 0.2, 0.05), grad(ORANGE, HORN1), rot=R, blend=0.06))
        add(flat_chain([el, V(-0.45, 1.46, 0.45 * s), V(-0.8, 1.42, 0.44 * s), V(-0.98, 1.58, 0.44 * s)], 0.12, 0.03,
                       grad(ORANGE, HORN1, 1.5), V(0, 0.25, 1 * s), flat=0.45, steps=8, blend=0.08))
        add(flat_chain([V(-0.5, 1.12, 0.44 * s), V(-0.75, 1.1, 0.43 * s), V(-0.95, 1.22, 0.43 * s)], 0.1, 0.03,
                       grad(ORANGE, HORN1, 1.5), V(0, 0.3, 1 * s), flat=0.45, steps=6, blend=0.08))

    # --- long thin tail with a flame tip
    tail_ctrl = [V(-0.7, 0.65, 0), V(-1.35, 0.55, 0.15), V(-1.8, 0.45, 0.45), V(-2.35, 0.62, 0.55)]
    add(chain(tail_ctrl, 0.28, 0.06, const(ORANGE), steps=12, taper=0.8, blend=0.2))
    add(flat_chain([V(-2.3, 0.6, 0.55), V(-2.55, 0.72, 0.58), V(-2.7, 0.95, 0.6), V(-2.65, 1.2, 0.62)], 0.13, 0.02,
                   horn, V(0.2, 0, 1), flat=0.5, steps=6, blend=0.06))
    return P


# ------------------------------------------------------------------ evaluation
def field(parts, p):
    d = None
    for part in parts:
        di, _ = part.sdf(p)
        if part.carve:
            d = smax(d, -di, part.blend)
        elif d is None:
            d = di
        else:
            d = smin(d, di, part.blend)
    return d


def colors_at(parts, p):
    """Blend each part's color by how close its surface is."""
    ds, cs = [], []
    for part in parts:
        di, ti = part.sdf(p)
        if part.carve:
            di = np.abs(di) - 0.01  # the groove itself gets the carve color
        ds.append(di)
        cs.append(part.color(p, ti if ti is not None else np.zeros(len(p))))
    ds = np.stack(ds)
    dmin = ds.min(axis=0)
    w = np.exp(-(ds - dmin) / 0.03)
    # eyes never bleed into the skin and vice versa
    for i, part in enumerate(parts):
        if part.group == "eye":
            w[i] = np.where(ds[i] <= dmin + 1e-6, 1e3, 0)
    w /= w.sum(axis=0)
    out = np.einsum("ij,ijk->jk", w, np.stack(cs))
    return np.clip(out, 0, 255)


def build_mesh(parts, res=0.022):
    lo, hi = V(-3.1, -0.08, -1.3), V(3.0, 5.3, 1.3)
    xs, ys, zs = (np.arange(lo[i], hi[i] + res, res) for i in range(3))
    grid = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), axis=-1).reshape(-1, 3)
    vals = np.empty(len(grid), dtype=np.float32)
    chunk = 400_000
    for i in range(0, len(grid), chunk):
        vals[i:i + chunk] = field(parts, grid[i:i + chunk])
    vol = vals.reshape(len(xs), len(ys), len(zs))
    verts, faces, _, _ = measure.marching_cubes(vol, 0.0, spacing=(res, res, res))
    verts += lo
    mesh = trimesh.Trimesh(verts, faces[:, ::-1], process=True)
    mesh.update_faces(mesh.nondegenerate_faces())
    # keep the main body only (drop stray specks)
    parts_ = mesh.split(only_watertight=False)
    mesh = max(parts_, key=lambda m: len(m.faces))
    return mesh


def decimate(mesh, target):
    import fast_simplification
    ratio = 1 - target / len(mesh.faces)
    v, f = fast_simplification.simplify(mesh.vertices.astype(np.float32), mesh.faces.astype(np.int32), ratio)
    m = trimesh.Trimesh(v, f, process=True)
    if m.volume < 0:
        m.invert()
    return m


if __name__ == "__main__":
    parts = build_parts()
    res = float(sys.argv[1]) if len(sys.argv) > 1 else 0.024
    mesh = build_mesh(parts, res)
    print("marching cubes:", len(mesh.faces), "faces")
    mesh = decimate(mesh, 19000)
    print("decimated:", len(mesh.faces), "faces")
    mesh.export(os.path.join(HERE, "_raw.ply"))
    np.save(os.path.join(HERE, "_raw_colors.npy"), colors_at(parts, mesh.vertices))
