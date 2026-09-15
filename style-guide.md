# Style Guide — RobloxManagement (Dragon Mania Legends-style creatures)

This file is the shared "memory" for every 3D asset generated for this project. Read it before
building anything, and update it deliberately (not silently) when the user asks to shift
direction.

## Art style
Stylized "collectible mascot" creatures in the vein of Dragon Mania Legends — chibi-leaning but
not a formless blob: big expressive head/eyes, yet a real, readable silhouette with dynamic
posture (slight arch/lean rather than a static symmetrical stack) and visible joints
(elbows/knees) rather than smooth uniform tubes. Glossy "vinyl toy" material finish (low
roughness ~0.25-0.35, non-metallic) so colors read vivid and saturated. Small geometric details
(dorsal plates, angular wing edges, blade/flame-shaped tail tip) are suggested through actual
mesh faceting, not just texture — don't smooth everything into perfect spheres.

## Color palette
Per-element (species/type) palette, built from a shared "hot/cool accent + pale belly" formula:

**Fire type** (current default for dragons unless told otherwise; revised against
`references/dragon_target.jpg`):
- Body main (back/flanks): #F2823B
- Body shadow/secondary (tail, flame-crest base, brow ridge, wing ribs): #E8442A
- Belly / lower jaw / inner wing membrane / claws: #FFEFB0
- Flame-crest tips: gold #FFC94D (crest base uses the body-shadow orange-red above, so each
  spike reads as a base->tip gradient, not a separate "horn" material)
- Dark accents (nostrils, mouth line, pupils): near-black (#0D0808)
- Eye iris: WARM amber/gold (#F5B942), not a cool contrasting color — this species' reference
  has a same-temperature amber eye against the warm body (unlike the cool-blue-iris convention
  used for other creatures); keep the dark pupil for contrast instead.

Future types should follow the same slot structure (main / shadow / belly-pale / horn-dark /
accent-dark / contrasting iris) so new elements stay visually consistent with each other.

## Proportions & scale
1 Blender unit ≈ 1 Roblox stud, dragon stands roughly 1.8-2.0 units tall overall.
- Head ≈ 35% of total standing height, with a defined, slightly elongated snout rather than a
  perfect round ball.
- Compact torso with a slight forward/upward arch (active stance), not a single round mass.
- Limbs short but two-segment with a visible joint bend (elbow/knee), not straight tapered
  tubes.
- Wings small relative to body, angular/membranous edge rather than a rounded fan.
- Tail tapers to a defined point (flame- or blade-shaped tip), not a rounded blob end.

**Baby/chibi variant** (e.g. `baby_dragon_fire.py`, matched against `references/dragon_target.jpg`):
overrides the general proportions above for young/mascot-baby creatures specifically —
- SHORT, rounded snout (not elongated) — the head should read as one big round mass with only
  a small forward nose bump, not a defined muzzle.
- Squat, egg-like torso: vertically compressed relative to the general adult proportions above
  (roughly as wide as tall) rather than an upright arched stance — achieved in the script via a
  `cz()` pivot-squash helper applied to every spine/limb/feature z-coordinate, so the whole
  build stays proportionally consistent when tuned.
- Short stubby limbs (minimal joint articulation) rather than the general guide's visible
  elbow/knee bend.
- Short, small rounded tail tip rather than a flame/blade point.
- Distinctive flame-shaped crest (see palette above) replaces plain horns/dorsal plates: several
  asymmetric flame-tongue spikes from forehead to nape, each a tapering bezier (base color)
  capped with a small gold cone (tip color) for the gradient.

## Edges & corners
Mix of smooth-shaded organic volumes (torso, head, limbs) and deliberately kept-faceted low-poly
accents (dorsal plates, wing membrane, tail tip) for a bit of graphic "toy" hardness against the
soft body — don't apply shade_smooth indiscriminately to every part.

## Materials
- Body/skin: Principled BSDF, roughness ~0.3, metallic 0, glossy vinyl-toy look.
- Eyes: sclera roughness ~0.15 (near white), iris/pupil roughness ~0.15-0.2, small separate
  glint part for a catch-light.
- Horns/spikes/claws: roughness ~0.25, slightly glossier than the body to read as harder
  material.
- No image textures by default — flat stylized color per part is enough at this scale; only
  reach for a generated/procedural texture if a specific asset calls for surface pattern (e.g.
  scale pattern, fabric saddle).

## Anything else worth remembering
- Reference concept image: `images/Fire_Dragon.png`.
- Scripts live in `blender_scripts/`, one file per creature/prop, importing shared helpers from
  `blender_scripts/bpy_helpers.py`.
- Organic creature bodies should prefer `skin_mesh_from_edges` / bezier curves for the
  torso/tail over stacking many separate ellipsoids — the latter tends to read as a "beach
  ball"/snowman pile rather than one dynamic creature; ellipsoids are fine for small discrete
  add-ons (eyes, horns, plates) but not for the main body mass.
