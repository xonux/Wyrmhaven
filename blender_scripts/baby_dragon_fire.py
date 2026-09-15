"""Baby fire dragon — Dragon Mania Legends-style mascot creature.

Chibi redesign, matched against references/dragon_target.jpg: a QUADRUPED stance (horizontal
round body on four short legs, neck rising up to a big head looking at the viewer) — not an
upright bipedal "teddy bear" pose. Round trapu body, SHORT rounded snout (not elongated), short
chubby stub legs, a short tail, small folded wings, and the single most distinctive feature of
the reference — a flame-shaped crest of asymmetric pointed spikes running from the forehead
back along the top of the neck, gradient orange-red at the base to gold at the tips. Eyes are
big with a warm amber iris and a small brow ridge for a curious/alert look.
"""
import math
import os
import sys

import mathutils

sys.path.append(os.path.dirname(__file__))
from bpy_helpers import (
    clear_scene, create_ellipsoid, create_cone, create_mesh_from_data,
    skin_mesh_from_edges, create_bezier_curve, convert_curve_to_mesh, join_objects,
    create_armature, bind_mesh_to_armature,
    make_principled_material, assign_material, hex_to_rgba,
    shade_smooth, export_glb, render_preview,
)

import bpy

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_DIR = os.path.join(PROJECT_DIR, "output")

clear_scene()

# --- Fire palette materials, matched to references/dragon_target.jpg ---
mat_body = make_principled_material("FireBody", base_color=hex_to_rgba("F2823B"), roughness=0.3)
mat_body_dark = make_principled_material("FireBodyDark", base_color=hex_to_rgba("E8442A"), roughness=0.3)
mat_belly = make_principled_material("FireBelly", base_color=hex_to_rgba("FFEFB0"), roughness=0.32)
mat_crest_gold = make_principled_material("CrestGold", base_color=hex_to_rgba("FFC94D"), roughness=0.25)
mat_dark_accent = make_principled_material("DarkAccent", base_color=hex_to_rgba("0D0808"), roughness=0.35)
mat_eye_white = make_principled_material("EyeWhite", base_color=(0.98, 0.98, 0.95, 1.0), roughness=0.15)
mat_eye_iris = make_principled_material("EyeIris", base_color=hex_to_rgba("F5B942"), roughness=0.18)
mat_eye_pupil = make_principled_material("EyePupil", base_color=(0.02, 0.02, 0.02, 1.0), roughness=0.2)
mat_eye_glint = make_principled_material("EyeGlint", base_color=(1.0, 1.0, 1.0, 1.0), roughness=0.1)


def add_scale_bump(mat, scale=90.0, strength=0.03):
    """Subtle procedural scale relief (Voronoi -> Bump -> Normal) — approximates the small
    scale pattern visible on the reference's cheeks/neck without needing an image texture."""
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    voronoi = nodes.new('ShaderNodeTexVoronoi')
    voronoi.inputs["Scale"].default_value = scale
    bump = nodes.new('ShaderNodeBump')
    bump.inputs["Strength"].default_value = strength
    links.new(voronoi.outputs["Distance"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


add_scale_bump(mat_body)
add_scale_bump(mat_body_dark)


def side_label(side):
    return "L" if side < 0 else "R"


def mirror_x(point):
    x, y, z = point
    return (-x, y, z)


parts = []


def track(obj):
    parts.append(obj)
    return obj


# ============================================================================
# CORE BODY — one continuous skinned spine, QUADRUPED layout: the torso runs
# mostly horizontal (tail -> hip -> round belly -> chest), then the neck
# rises up to a big round head held high, looking forward — matching the
# reference's stance rather than an upright bipedal pose.
# ============================================================================
CORE_POINTS = [
    (0.00, -0.30, 0.42),   # 0 TailBase
    (0.00, -0.15, 0.44),   # 1 Hip        (haunch, back legs attach here)
    (0.00,  0.02, 0.46),   # 2 Belly      (round belly bulge, widest point)
    (0.00,  0.17, 0.50),   # 3 Chest      (front legs attach here)
    (0.00,  0.28, 0.62),   # 4 NeckBase   (pinched neck starts)
    (0.00,  0.32, 0.88),   # 5 NeckMid    (neck rises)
    (0.00,  0.30, 1.08),   # 6 HeadCenter (big round head, held high)
    (0.00,  0.46, 1.05),   # 7 SnoutTip   (short, rounded — not elongated)
]
CORE_RADII = [0.13, 0.28, 0.34, 0.29, 0.17, 0.15, 0.40, 0.17]
CORE_EDGES = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7)]

body = skin_mesh_from_edges("DragonCore", CORE_POINTS, CORE_EDGES, radii=CORE_RADII, subsurf_levels=3)
assign_material(body, mat_body)
track(body)

# ============================================================================
# FOUR LEGS — short, chubby stub legs (chibi), each its own small skinned
# chain rooted well inside the torso to hide the seam. Front pair under the
# chest, back pair under the hip, all four feet at the same ground height.
# ============================================================================
FRONT_LEG_TEMPLATE = [(0.15, 0.15, 0.46), (0.19, 0.22, 0.28), (0.17, 0.18, 0.13)]
BACK_LEG_TEMPLATE = [(0.16, -0.13, 0.40), (0.20, -0.05, 0.24), (0.18, -0.08, 0.13)]
LEG_RADII = [0.145, 0.15, 0.125]

CLAW_OFFSETS = [(-0.05, 0.03, 0.0), (0.0, 0.05, 0.0), (0.05, 0.03, 0.0)]

for template, tag in ((FRONT_LEG_TEMPLATE, "Front"), (BACK_LEG_TEMPLATE, "Back")):
    for side in (-1, 1):
        leg_pts = [(side * x, y, z) for x, y, z in template]
        leg = skin_mesh_from_edges(f"Leg{tag}_{side_label(side)}", leg_pts, [(0, 1), (1, 2)], radii=LEG_RADII, subsurf_levels=3)
        assign_material(leg, mat_body)
        track(leg)

        foot = leg_pts[-1]
        for i, (dx, dy, dz) in enumerate(CLAW_OFFSETS):
            claw = create_ellipsoid(f"Claw{tag}_{side_label(side)}_{i}", radii=(0.032, 0.045, 0.028),
                                     location=(foot[0] + dx, foot[1] + dy + 0.02, foot[2] - 0.08 + dz))
            assign_material(claw, mat_belly)
            shade_smooth(claw)
            track(claw)

# --- Belly patch (pale, contrast accent) — a long patch along the underside of the torso ---
belly = create_ellipsoid("Belly", radii=(0.17, 0.26, 0.15), location=(0, -0.02, 0.20))
assign_material(belly, mat_belly)
shade_smooth(belly)
track(belly)

# --- Lower jaw patch (pale, matches belly per reference) ---
jaw = create_ellipsoid("LowerJaw", radii=(0.11, 0.11, 0.06), location=(0, 0.40, 0.80))
assign_material(jaw, mat_belly)
shade_smooth(jaw)
track(jaw)

# ============================================================================
# EYES (grands, expressifs — iris ambre chaud contrastant avec la pupille sombre)
# ============================================================================
for side in (-1, 1):
    sclera = create_ellipsoid(f"EyeWhite_{side_label(side)}", radii=(0.115, 0.075, 0.115), location=(side * 0.185, 0.40, 1.14))
    assign_material(sclera, mat_eye_white); shade_smooth(sclera); track(sclera)
    iris = create_ellipsoid(f"EyeIris_{side_label(side)}", radii=(0.065, 0.04, 0.065), location=(side * 0.185, 0.46, 1.15))
    assign_material(iris, mat_eye_iris); shade_smooth(iris); track(iris)
    pupil = create_ellipsoid(f"EyePupil_{side_label(side)}", radii=(0.033, 0.025, 0.033), location=(side * 0.185, 0.49, 1.15))
    assign_material(pupil, mat_eye_pupil); shade_smooth(pupil); track(pupil)
    glint = create_ellipsoid(f"EyeGlint_{side_label(side)}", radii=(0.013, 0.011, 0.013), location=(side * 0.16, 0.50, 1.17))
    assign_material(glint, mat_eye_glint); shade_smooth(glint); track(glint)

    # Brow ridge — small wedge hugging the top of the eye, angled down toward the nose for an
    # alert/curious frown.
    brow = create_ellipsoid(f"Brow_{side_label(side)}", radii=(0.075, 0.028, 0.022), location=(side * 0.185, 0.40, 1.225))
    brow.rotation_euler = (math.radians(-14), 0, side * math.radians(-10))
    assign_material(brow, mat_body_dark); shade_smooth(brow); track(brow)

# --- Nostrils + mouth line, pulled inside the short snout mass ---
for side in (-1, 1):
    nostril = create_ellipsoid(f"Nostril_{side_label(side)}", radii=(0.016, 0.014, 0.016), location=(side * 0.045, 0.48, 1.06))
    assign_material(nostril, mat_dark_accent); shade_smooth(nostril); track(nostril)
mouth_line = create_ellipsoid("MouthLine", radii=(0.07, 0.015, 0.015), location=(0, 0.43, 0.93))
assign_material(mouth_line, mat_dark_accent); shade_smooth(mouth_line); track(mouth_line)

# ============================================================================
# FLAME CREST — the reference's single most distinctive feature: asymmetric
# stylized flame-tongue spikes running from the forehead back along the top
# of the neck, each built as a tapering bezier "flame base" (uniform deep
# orange-red) capped with a small cone "flame tip" (gold) for the base->tip
# color gradient. Sizes shrink from the tall frontal spike toward the neck.
# ============================================================================
FLAME_SPIKES = [
    # (root, mid, orange_tip, gold_tip, bevel_depth) — root pulled inward from the nominal
    # forehead/neck-top surface toward the spine, since the Skin+Subsurf modifier stack shrinks
    # the actual mesh surface noticeably inside the raw control radius; embedding the root
    # deeper avoids a floating gap between the crest and the head/neck.
    ((0.00, 0.37, 1.21), (0.00, 0.42, 1.55), (0.00, 0.36, 1.66), (0.00, 0.32, 1.72), 0.050),
    ((0.02, 0.35, 1.20), (0.09, 0.35, 1.48), (0.10, 0.30, 1.56), (0.11, 0.27, 1.61), 0.038),
    ((-0.03, 0.33, 1.18), (-0.10, 0.31, 1.41), (-0.11, 0.26, 1.47), (-0.12, 0.23, 1.51), 0.030),
    ((0.01, 0.28, 0.95), (0.04, 0.16, 1.15), (0.04, 0.11, 1.22), (0.05, 0.08, 1.26), 0.025),
    ((-0.01, 0.21, 0.71), (-0.02, 0.04, 0.92), (-0.02, 0.00, 0.97), (-0.02, -0.03, 1.00), 0.018),
]

for i, (root, mid, tip, gold_tip, bevel) in enumerate(FLAME_SPIKES):
    flame = create_bezier_curve(f"FlameCrest_{i}", [root, mid, tip], bevel_depth=bevel, bevel_resolution=4)
    assign_material(flame, mat_body_dark)
    radii = [0.65, 1.0, 0.18]
    for j, r in enumerate(radii):
        flame.data.splines[0].bezier_points[j].radius = r
    convert_curve_to_mesh(flame)
    track(flame)

    direction = (gold_tip[0] - tip[0], gold_tip[1] - tip[1], gold_tip[2] - tip[2])
    length = math.sqrt(sum(c * c for c in direction))
    tip_cone = create_cone(f"FlameCrestTip_{i}", radius1=bevel * 0.75, radius2=0.006, depth=length,
                            location=((tip[0] + gold_tip[0]) / 2, (tip[1] + gold_tip[1]) / 2, (tip[2] + gold_tip[2]) / 2),
                            vertices=6)
    pitch = math.atan2(math.sqrt(direction[0] ** 2 + direction[1] ** 2), direction[2])
    yaw = math.atan2(direction[1], direction[0])
    tip_cone.rotation_euler = (0, pitch, yaw - math.radians(90))
    assign_material(tip_cone, mat_crest_gold)
    track(tip_cone)

# ============================================================================
# TAIL — short, tapering bezier ending in a small rounded tip, extending
# backward roughly level with the hip (not a long bladed tail).
# ============================================================================
tail_pts = [
    (0.00, -0.30, 0.42),
    (0.00, -0.46, 0.36),
    (0.00, -0.58, 0.32),
]
tail = create_bezier_curve("Tail", tail_pts, bevel_depth=0.13, bevel_resolution=5)
assign_material(tail, mat_body_dark)
tail_radii = [1.0, 0.75, 0.4]
for i, r in enumerate(tail_radii):
    tail.data.splines[0].bezier_points[i].radius = r
convert_curve_to_mesh(tail)
track(tail)

tail_tip = create_ellipsoid("TailTip", radii=(0.06, 0.07, 0.06), location=(0, -0.64, 0.30))
assign_material(tail_tip, mat_belly)
shade_smooth(tail_tip)
track(tail_tip)

# ============================================================================
# WINGS — small relative to the body, folded along the back over the haunch,
# with thin rib lines suggesting the finger structure under the pale
# membrane.
# ============================================================================
WING_OUTLINE = [
    (0.00, 0.00),
    (0.04, 0.20),
    (0.14, 0.30),
    (0.255, 0.255),
    (0.215, 0.14),
    (0.28, 0.065),
    (0.19, -0.013),
    (0.09, -0.033),
]
WING_DEPTH = 0.013
WING_RIB_TARGETS = [2, 3, 5]  # outline indices the rib lines fan out to
for side in (-1, 1):
    n = len(WING_OUTLINE)
    front = [(side * x, WING_DEPTH, z) for x, z in WING_OUTLINE]
    back = [(side * x, -WING_DEPTH, z) for x, z in WING_OUTLINE]
    verts = front + back
    faces = [list(range(n)), [n + i for i in reversed(range(n))]]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    wing_loc = (side * 0.17, 0.02, 0.58)
    wing = create_mesh_from_data(f"Wing_{side_label(side)}", verts, faces, location=wing_loc)
    assign_material(wing, mat_belly)
    wing.rotation_euler = (math.radians(35), 0, side * math.radians(12))
    track(wing)

    for ti in WING_RIB_TARGETS:
        tx, tz = WING_OUTLINE[ti]
        rib = create_bezier_curve(f"WingRib_{side_label(side)}_{ti}", [(0.0, 0.0, 0.0), (side * tx, 0.0, tz)],
                                   bevel_depth=0.011, bevel_resolution=2, location=wing_loc)
        rib.rotation_euler = wing.rotation_euler
        assign_material(rib, mat_body_dark)
        convert_curve_to_mesh(rib)
        track(rib)

# ============================================================================
# JOIN into a single mesh, then a basic animation-ready armature.
# ============================================================================
for obj in parts:
    if obj.type != 'MESH' or obj.modifiers:
        convert_curve_to_mesh(obj)

dragon = join_objects("BabyFireDragon", parts)

bones = [
    ("Hip", CORE_POINTS[1], CORE_POINTS[3], None),
    ("Neck", CORE_POINTS[3], CORE_POINTS[6], "Hip"),
    ("Head", CORE_POINTS[6], CORE_POINTS[7], "Neck"),
    ("Tail", CORE_POINTS[1], tail_pts[-1], "Hip"),
    ("LegFrontR", FRONT_LEG_TEMPLATE[0], FRONT_LEG_TEMPLATE[2], "Hip"),
    ("LegFrontL", mirror_x(FRONT_LEG_TEMPLATE[0]), mirror_x(FRONT_LEG_TEMPLATE[2]), "Hip"),
    ("LegBackR", BACK_LEG_TEMPLATE[0], BACK_LEG_TEMPLATE[2], "Hip"),
    ("LegBackL", mirror_x(BACK_LEG_TEMPLATE[0]), mirror_x(BACK_LEG_TEMPLATE[2]), "Hip"),
]
armature = create_armature("BabyFireDragonRig", bones)
bind_mesh_to_armature(dragon, armature)

# --- Custom 3/4 front-elevated camera (the face points toward +Y, so the camera needs to sit
# on the +Y side looking back toward the dragon, not the render_preview() default) ---
cam_data = bpy.data.cameras.new("PreviewCam")
cam_obj = bpy.data.objects.new("PreviewCam", cam_data)
bpy.context.collection.objects.link(cam_obj)
cam_obj.location = (2.5, 3.05, 1.35)
direction = mathutils.Vector((0.0, -0.05, 0.8)) - cam_obj.location
cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
bpy.context.scene.camera = cam_obj

light_data = bpy.data.lights.new("PreviewLight", type='SUN')
light_data.energy = 3.0
light_obj = bpy.data.objects.new("PreviewLight", light_data)
bpy.context.collection.objects.link(light_obj)
light_obj.rotation_euler = (math.radians(55), 0, math.radians(35))

os.makedirs(OUTPUT_DIR, exist_ok=True)
render_preview(os.path.join(OUTPUT_DIR, "baby_dragon_fire_preview.png"))
export_glb(os.path.join(OUTPUT_DIR, "baby_dragon_fire.glb"))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTPUT_DIR, "baby_dragon_fire.blend"))
