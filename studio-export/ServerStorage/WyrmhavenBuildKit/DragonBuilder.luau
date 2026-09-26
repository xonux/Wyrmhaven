-- DragonBuilder: edit-time generator for Wyrmhaven's low-poly dragon models.
-- Run it from the Studio MCP (execute_luau, Edit datamodel):
--   local B = loadstring(game.ServerStorage.WyrmhavenBuildKit.DragonBuilder.Source)()
--   local model = B.Build("Fire", "Adult")
-- Same technique as the habitat models: every face is a triangle made of two
-- WedgePart halves, and each body segment is unioned into one UnionOperation
-- (UsePartColor = false keeps the per-face colors, SmoothingAngle 0 keeps
-- the facets). Segments are joined by Motor6Ds hanging off an anchored,
-- invisible HumanoidRootPart, and the model has an AnimationController + Animator, so
-- it can be animated with the Animation Editor or by driving
-- Motor6D.Transform from code. Baby and Adult share the same part names and
-- joint tree, so an animation made for one plays on the other.
-- Model space: ground at Y = 0, the dragon faces -Z (Roblox LookVector), its
-- left side is -X. Left-side parts are built once and mirrored.

local Builder = {}

local V = Vector3.new
local C = Color3.fromRGB

local SHELL = 0.06 -- thickness of a closed surface's wedges (grows inward)
local PLATE = 0.07 -- thickness of two-sided plates (wing membranes)

local function bezier(pts, t)
	local tmp = table.clone(pts)
	for level = #tmp - 1, 1, -1 do
		for i = 1, level do
			tmp[i] = tmp[i]:Lerp(tmp[i + 1], t)
		end
	end
	return tmp[1]
end

local function toward(p, target, k)
	return p + (target - p) * k
end

local function mx(v)
	return V(-v.X, v.Y, v.Z)
end

-- Ring frame: X = right, Y = dorsal side, Z = -tangent (the loft runs along
-- the frame's LookVector).
local function frameAt(p, t, dorsal)
	local up = dorsal - t * dorsal:Dot(t)
	if up.Magnitude < 0.05 then
		local alt = math.abs(t.Y) < 0.9 and Vector3.yAxis or Vector3.zAxis
		up = alt - t * alt:Dot(t)
	end
	up = up.Unit
	local back = -t
	return CFrame.fromMatrix(p, up:Cross(back), up, back)
end

------------------------------------------------------------------ Seg
-- A body segment: a list of triangles that becomes one union.

local Seg = {}
Seg.__index = Seg

function Seg.new(name)
	return setmetatable({ name = name, tris = {} }, Seg)
end

-- Shell triangle: the outer face lies on a-b-c and the thickness grows
-- toward `interior` (a point inside the closed volume).
function Seg:tri(a, b, c, color, interior, thickness)
	table.insert(self.tris, { a, b, c, color, interior, false, thickness })
end

-- Two-sided plate centered on a-b-c.
function Seg:plate(a, b, c, color, thickness)
	table.insert(self.tris, { a, b, c, color, nil, thickness or PLATE })
end

function Seg:quad(a, b, c, d, color, interior, thickness)
	self:tri(a, b, c, color, interior, thickness)
	self:tri(a, c, d, color, interior, thickness)
end

-- Plate polygon fanned from points[anchor] (or from the centroid).
function Seg:platePoly(points, color, thickness, anchor)
	if anchor then
		local a = points[anchor]
		local n = #points
		for k = 1, n - 2 do
			local i = (anchor + k - 1) % n + 1
			local j = (anchor + k) % n + 1
			self:plate(a, points[i], points[j], color, thickness)
		end
		return
	end
	local ctr = Vector3.zero
	for _, p in ipairs(points) do
		ctr += p
	end
	ctr /= #points
	for k = 1, #points do
		self:plate(ctr, points[k], points[k % #points + 1], color, thickness)
	end
end

-- Low-poly tube through cross-section rings.
-- ring: { p, t? (tangent), rx, ry, ryb? (lower half-height), up? (dorsal
--   hint), c? / cb? / ct? (band colors from this ring to the next) }
-- o: sides, rot (angle of the first vertex; default puts a face on top),
--   dorsal, main, belly + bellyAt (sin threshold), top + topAt, capStart /
--   capEnd (false = open), tipStart / tipEnd (pointed caps), capColor.
function Seg:loft(rings, o)
	o = o or {}
	local n = o.sides or 8
	local rot = o.rot or (math.pi / 2 + math.pi / n)
	local dorsal = o.dorsal or Vector3.yAxis
	local verts, centroids, minR = {}, {}, {}
	for i, r in ipairs(rings) do
		local t = r.t
		if not t then
			t = rings[math.min(i + 1, #rings)].p - rings[math.max(i - 1, 1)].p
		end
		local f = frameAt(r.p, t.Unit, r.up or dorsal)
		local vs, sum = {}, Vector3.zero
		for k = 1, n do
			local ang = rot + 2 * math.pi * (k - 1) / n
			local cs, sn = math.cos(ang), math.sin(ang)
			local ry = sn >= 0 and r.ry or (r.ryb or r.ry)
			vs[k] = f * V(r.rx * cs, ry * sn, 0)
			sum += vs[k]
		end
		verts[i] = vs
		centroids[i] = sum / n
		minR[i] = math.min(r.rx, r.ry, r.ryb or r.ry)
	end
	local function shellFor(i, j)
		local r = math.max(math.min(minR[i], minR[j]), math.max(minR[i], minR[j]) * 0.5)
		return math.clamp(r * 0.45, 0.012, SHELL)
	end
	local function colorFor(i, ang)
		local r = rings[i]
		local sn = math.sin(ang)
		if o.belly and sn < -(o.bellyAt or 0.5) then
			return r.cb or o.belly
		end
		if o.top and sn > (o.topAt or 0.9) then
			return r.ct or o.top
		end
		return r.c or o.main
	end
	for i = 1, #rings - 1 do
		local interior = (centroids[i] + centroids[i + 1]) / 2
		local sh = shellFor(i, i + 1)
		for k = 1, n do
			local k2 = k % n + 1
			local ang = rot + 2 * math.pi * (k - 0.5) / n
			self:quad(verts[i][k], verts[i][k2], verts[i + 1][k2], verts[i + 1][k], colorFor(i, ang), interior, sh)
		end
	end
	local function cap(i, j, tip)
		local apex = tip or centroids[i]
		local interior = centroids[j]
		local color = o.capColor or rings[i].c or o.main
		local sh = shellFor(i, j)
		for k = 1, n do
			self:tri(apex, verts[i][k], verts[i][k % n + 1], color, interior, sh)
		end
	end
	if #rings >= 2 then
		if o.capStart ~= false then
			cap(1, 2, o.tipStart)
		end
		if o.capEnd ~= false then
			cap(#rings, #rings - 1, o.tipEnd)
		end
	elseif o.tipEnd then
		-- single ring + tip (claws, fangs): a pyramid
		local c = centroids[1]
		local interior = c - (o.tipEnd - c) * 0.25
		for k = 1, n do
			self:tri(o.tipEnd, verts[1][k], verts[1][k % n + 1], o.capColor or o.main, interior, shellFor(1, 1))
		end
	end
end

-- Tube through points with one radius per point. o: loft options plus
-- rxs / rys / rybs (radius multipliers) and tangents (explicit per point).
function Seg:tube(pts, radii, o)
	o = o or {}
	local rings = {}
	for i, p in ipairs(pts) do
		local r = radii[i]
		rings[i] = {
			p = p,
			t = o.tangents and o.tangents[i],
			rx = r * (o.rxs or 1),
			ry = r * (o.rys or 1),
			ryb = o.rybs and r * o.rybs or nil,
		}
	end
	self:loft(rings, o)
end

-- Tapered spike along a Bezier curve (horns, crest flames, claws, spines).
-- o: r (base radius), steps (1 = a pyramid), sides, rxs / rys, up (dorsal
-- hint), c0 (base color), c1 (tip color), taper (radius exponent), capStart
-- (off by default: the base sits inside the body).
function Seg:spike(ctrl, o)
	local steps = math.max(o.steps or 3, 1)
	local rings = {}
	for s = 0, steps - 1 do
		local t = s / steps
		local p = bezier(ctrl, t)
		local tan = bezier(ctrl, math.min(t + 0.02, 1)) - bezier(ctrl, math.max(t - 0.02, 0))
		local r = o.r * (1 - t) ^ (o.taper or 1)
		rings[s + 1] = { p = p, t = tan, rx = r * (o.rxs or 1), ry = r * (o.rys or 1), c = o.c0:Lerp(o.c1, t) }
	end
	self:loft(rings, {
		sides = o.sides or 4,
		rot = o.rot,
		dorsal = o.up or Vector3.yAxis,
		main = o.c0,
		tipEnd = ctrl[#ctrl],
		capColor = o.c1,
		capStart = o.capStart == true,
	})
end

-- Eye on a head surface: a low dome (rim + iris), a pupil plate and a
-- catch-light, all facing `normal`. o: rx, ry, iris, rim, pupil, pupilW,
-- pupilH, glint, glintSize, glintDir (world direction the catch-light sits
-- toward), depth, lid (upper eyelid color, nil = none), lidAt / lidSize
-- (lid center height and half-height, in fractions of ry: 0.62 / 0.55
-- covers the top half = heavy-lidded look).
function Seg:eye(center, normal, up, o)
	local back = normal.Unit
	local upv = (up - back * up:Dot(back)).Unit
	local right = upv:Cross(back)
	local f = CFrame.fromMatrix(center, right, upv, back)
	local front = o.depth or 0.06
	self:loft({
		{ p = f * V(0, 0, -0.14), rx = o.rx, ry = o.ry },
		{ p = f * V(0, 0, 0), rx = o.rx, ry = o.ry },
		{ p = f * V(0, 0, front), rx = o.rx * 0.84, ry = o.ry * 0.84 },
	}, { sides = o.sides or 8, rot = 0, dorsal = upv, main = o.rim, capColor = o.iris, capStart = false })
	local z = front + 0.02
	local pw, ph = o.pupilW, o.pupilH
	local ctr = f * V(0, 0, z)
	local pts = { V(0, ph, z), V(pw, ph * 0.45, z), V(pw, -ph * 0.45, z), V(0, -ph, z), V(-pw, -ph * 0.45, z), V(-pw, ph * 0.45, z) }
	for k = 1, #pts do
		self:plate(ctr, f * pts[k], f * pts[k % #pts + 1], o.pupil, 0.02)
	end
	local g = o.glintDir or V(0, 0.6, -1)
	g = (g - back * g:Dot(back)).Unit
	local gx, gy = g:Dot(right), g:Dot(upv)
	local gd = math.min(o.rx, o.ry) * 0.45
	local gs = o.glintSize
	local gz = front + 0.045
	local gc = V(gx * gd, gy * gd, gz)
	self:platePoly({
		f * (gc + V(0, gs, 0)),
		f * (gc + V(gs * 0.7, 0, 0)),
		f * (gc + V(0, -gs, 0)),
		f * (gc + V(-gs * 0.7, 0, 0)),
	}, o.glint, 0.02)
	if o.lid then
		local lr = o.ry * (o.lidSize or 0.55)
		local c = V(0, o.ry * (o.lidAt or 0.62), 0)
		self:loft({
			{ p = f * (c + V(0, 0, -0.12)), rx = o.rx * 1.14, ry = lr },
			{ p = f * (c + V(0, 0, front + 0.05)), rx = o.rx * 1.08, ry = lr * 0.92 },
			{ p = f * (c + V(0, 0, front + 0.09)), rx = o.rx * 0.92, ry = lr * 0.7 },
		}, { sides = 8, rot = 0, dorsal = upv, main = o.lid, capStart = false })
	end
end

-- Small flat diamond laid on a surface (nostrils).
function Seg:decal(center, normal, up, w, h, color)
	local back = normal.Unit
	local upv = (up - back * up:Dot(back)).Unit
	local right = upv:Cross(back)
	local c = center + back * 0.012
	self:platePoly({ c + upv * h, c + right * w, c - upv * h, c - right * w }, color, 0.02)
end

-- Nearest hit of a ray (dir: unit) on this segment's triangles, and the
-- face normal turned toward the ray origin. Used to seat eyes and nostrils
-- exactly on a faceted head.
function Seg:raycast(origin, dir)
	local best, bestN
	for _, t in ipairs(self.tris) do
		local a, b, c = t[1], t[2], t[3]
		local e1, e2 = b - a, c - a
		local p = dir:Cross(e2)
		local det = e1:Dot(p)
		if math.abs(det) > 1e-9 then
			local inv = 1 / det
			local s = origin - a
			local u = s:Dot(p) * inv
			if u >= 0 and u <= 1 then
				local q = s:Cross(e1)
				local v = dir:Dot(q) * inv
				if v >= 0 and u + v <= 1 then
					local dist = e2:Dot(q) * inv
					if dist > 0 and (not best or dist < best) then
						best, bestN = dist, e1:Cross(e2).Unit
					end
				end
			end
		end
	end
	if not best then
		return nil
	end
	if bestN:Dot(dir) > 0 then
		bestN = -bestN
	end
	return origin + dir * best, bestN
end

-- Moves every point through fn (used to rescale a finished head).
function Seg:map(fn)
	for _, t in ipairs(self.tris) do
		t[1], t[2], t[3] = fn(t[1]), fn(t[2]), fn(t[3])
		if t[5] then
			t[5] = fn(t[5])
		end
	end
end

function Seg:mirrored(name)
	local s = Seg.new(name)
	for _, t in ipairs(self.tris) do
		table.insert(s.tris, { mx(t[1]), mx(t[2]), mx(t[3]), t[4], t[5] and mx(t[5]), t[6], t[7] })
	end
	return s
end

------------------------------------------------------------------ wedges

local function wedge(color, size, cf, folder, out)
	if size.Y < 0.003 or size.Z < 0.003 then
		return
	end
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CanTouch = false
	w.Material = Enum.Material.SmoothPlastic
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Color = color
	w.Size = size
	w.CFrame = cf
	w.Parent = folder
	table.insert(out, w)
end

local function emitTriangle(t, folder, out)
	local a, b, c, color, interior, plate, shell = t[1], t[2], t[3], t[4], t[5], t[6], t[7]
	local n = (b - a):Cross(c - a)
	if n.Magnitude < 1e-5 then
		return
	end
	n = n.Unit
	local thickness, offset
	if plate then
		thickness, offset = plate, Vector3.zero
	else
		if interior and n:Dot((a + b + c) / 3 - interior) < 0 then
			n = -n
		end
		thickness = shell or SHELL
		offset = -n * (thickness / 2)
	end
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	wedge(color, V(thickness, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2 + offset, right, up, back), folder, out)
	wedge(color, V(thickness, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2 + offset, -right, up, -back), folder, out)
end

function Seg:build(folder)
	local parts = {}
	for _, t in ipairs(self.tris) do
		emitTriangle(t, folder, parts)
	end
	local first = table.remove(parts, 1)
	local union = first:UnionAsync(parts)
	for _, p in ipairs(parts) do
		p:Destroy()
	end
	first:Destroy()
	union.UsePartColor = false
	union.SmoothingAngle = 0
	union.RenderFidelity = Enum.RenderFidelity.Precise
	union.CollisionFidelity = Enum.CollisionFidelity.Box
	union.Material = Enum.Material.SmoothPlastic
	union.Name = self.name
	return union, #parts + 1
end

------------------------------------------------------------------ specs

local PALETTES = {
	Fire = {
		main = C(242, 130, 59), -- DragonDefs.Fire.StageColors.Adult
		dark = C(224, 84, 44), -- dorsal stripe, brows
		belly = C(255, 216, 146),
		membrane = C(232, 94, 48),
		flame0 = C(228, 72, 40), -- horn / spike base (StageColors.Egg)
		flame1 = C(255, 200, 76), -- horn / spike tip
		claw = C(255, 238, 206),
		iris = C(255, 188, 56),
		irisRim = C(176, 70, 30),
		pupil = C(36, 16, 12),
		glint = C(255, 255, 246),
	},
}

local function sideName(name)
	return (name:gsub("L$", "R"):gsub("LTip$", "RTip"))
end

local function newSpec()
	local spec = { segs = {}, joints = {} }
	function spec.seg(name)
		local s = Seg.new(name)
		table.insert(spec.segs, s)
		return s
	end
	-- axis: optional X axis of the joint frame (default: model axes)
	function spec.joint(name, parent, pos, axis)
		table.insert(spec.joints, { name, parent, pos, axis })
	end
	-- Mirrors every left-side segment and joint (names ending in L / LTip).
	function spec.mirrorSides()
		local segs, joints = {}, {}
		for _, s in ipairs(spec.segs) do
			if sideName(s.name) ~= s.name then
				table.insert(segs, s:mirrored(sideName(s.name)))
			end
		end
		for _, j in ipairs(spec.joints) do
			if sideName(j[1]) ~= j[1] then
				table.insert(joints, { sideName(j[1]), sideName(j[2]), mx(j[3]), j[4] and mx(j[4]) })
			end
		end
		for _, s in ipairs(segs) do
			table.insert(spec.segs, s)
		end
		for _, j in ipairs(joints) do
			table.insert(spec.joints, j)
		end
	end
	return spec
end

-- Flame tongue rising from `base` along `out`, curling toward `curl`.
local function flame(seg, base, out, curl, len, r, P, o)
	o = o or {}
	out = out.Unit
	curl = curl.Unit
	seg:spike({
		base - out * r * 0.6,
		base + out * len * 0.45,
		base + out * len * 0.75 + curl * len * 0.25,
		base + out * len * 0.9 + curl * len * 0.6,
	}, {
		r = r,
		steps = o.steps or 3,
		sides = o.sides or 4,
		rxs = o.rxs,
		rys = o.rys,
		up = o.up,
		c0 = o.c0 or P.flame0,
		c1 = o.c1 or P.flame1,
		taper = o.taper or 0.9,
	})
end

-- Paw: a flattened wedge of a foot pointing along `dir` with 3 claws
-- (heights scale with the width, 0.33 = adult).
local function paw(seg, heel, dir, len, width, P)
	dir = V(dir.X, 0, dir.Z).Unit
	local s = width / 0.33
	local side = dir:Cross(Vector3.yAxis)
	local toe = heel + dir * len
	seg:loft({
		{ p = heel + V(0, 0.2 * s, 0), rx = width * 0.8, ry = 0.18 * s, ryb = 0.16 * s },
		{ p = heel + dir * len * 0.55 + V(0, 0.15 * s, 0), rx = width, ry = 0.14 * s, ryb = 0.13 * s },
		{ p = toe + V(0, 0.1 * s, 0), rx = width * 0.85, ry = 0.08 * s, ryb = 0.08 * s },
	}, { sides = 6, main = P.main, capStart = false })
	for _, k in ipairs({ -1, 0, 1 }) do
		local base = toe + side * (k * width * 0.55) + V(0, 0.08 * s, 0)
		seg:spike({ base - dir * 0.05 * s, base + dir * 0.08 * s + side * (k * 0.02 * s), base + dir * 0.16 * s + V(0, -0.07 * s, 0) + side * (k * 0.04 * s) }, {
			r = width * 0.24,
			steps = 1,
			sides = 3,
			c0 = P.claw,
			c1 = P.claw,
		})
	end
end

-- Tail split into 3 segments; pts/radii are 7 points, joints at 3 and 5.
-- Adjacent segments share their joint ring (same tangent) so the seam is
-- closed at rest. Returns the 3 segs.
local function tail(spec, pts, radii, P, top)
	local tangents = {}
	for i = 1, #pts do
		tangents[i] = pts[math.min(i + 1, #pts)] - pts[math.max(i - 1, 1)]
	end
	local ranges = { { 1, 3 }, { 3, 5 }, { 5, 7 } }
	local segs = {}
	for s, range in ipairs(ranges) do
		local seg = spec.seg("Tail" .. s)
		local p, r, t = {}, {}, {}
		for i = range[1], range[2] do
			table.insert(p, pts[i])
			table.insert(r, radii[i])
			table.insert(t, tangents[i])
		end
		seg:tube(p, r, { sides = 8, tangents = t, rybs = 0.92, main = P.main, belly = P.belly, bellyAt = 0.8, top = top })
		segs[s] = seg
	end
	spec.joint("Tail1", "Torso", pts[1])
	spec.joint("Tail2", "Tail1", pts[3])
	spec.joint("Tail3", "Tail2", pts[5])
	return segs
end

-- Bat wing: arm S-E-W, fingers W-T1 / W-T2 / W-T3, body attach point B.
-- WingL holds the arm, the T3 finger and the inner membrane; WingLTip holds
-- the T1/T2 fingers and the outer membrane, hinged on the W-T3 line (so
-- folding it keeps the shared edge closed).
local function wing(spec, S, E, W, T1, T2, T3, B, r, P)
	local inner = spec.seg("WingL")
	local outer = spec.seg("WingLTip")
	local function scallop(a, b, k)
		return toward((a + b) / 2, W, k)
	end
	local M12, M23, M3B = scallop(T1, T2, 0.3), scallop(T2, T3, 0.3), toward((T3 + B) / 2, W, 0.22)
	inner:tube({ S, E, W }, { r, r * 0.8, r * 0.62 }, { sides = 5, main = P.main })
	inner:spike({ W, T3 }, { r = r * 0.5, steps = 3, sides = 4, c0 = P.main, c1 = P.dark, taper = 0.7 })
	inner:platePoly({ S, E, W, T3, M3B, B }, P.membrane, nil, 3)
	inner:spike({ W, W + V(0, r * 1.2, -r * 0.8), W + V(r * 0.2, r * 2.4, -r * 1.8) }, { r = r * 0.45, steps = 1, sides = 3, c0 = P.claw, c1 = P.claw })
	outer:spike({ W, T1 }, { r = r * 0.55, steps = 3, sides = 4, c0 = P.main, c1 = P.dark, taper = 0.7 })
	outer:spike({ W, T2 }, { r = r * 0.5, steps = 3, sides = 4, c0 = P.main, c1 = P.dark, taper = 0.7 })
	outer:platePoly({ W, T1, M12, T2, M23, T3 }, P.membrane, nil, 1)
	spec.joint("WingL", "Torso", S)
	spec.joint("WingLTip", "WingL", W, T3 - W)
end

-- Flame-shaped tail tip: a big tongue curling up plus two smaller ones.
-- The tail must end pointing roughly along +X (s: size factor, 1 = adult).
local function tailFlame(seg, tip, s, P)
	seg:spike({ tip - V(0.12, 0, 0) * s, tip + V(0.45, 0.12, 0.02) * s, tip + V(0.8, 0.5, -0.05) * s, tip + V(0.95, 1.05, 0.15) * s }, {
		r = 0.28 * s, steps = 4, sides = 4, rys = 0.5, c0 = P.flame0, c1 = P.flame1, up = Vector3.zAxis,
	})
	seg:spike({ tip, tip + V(0.2, 0.3, 0.12) * s, tip + V(0.25, 0.62, 0.35) * s, tip + V(0.18, 0.8, 0.62) * s }, {
		r = 0.17 * s, steps = 3, sides = 4, rys = 0.5, c0 = P.flame0, c1 = P.flame1, up = Vector3.xAxis,
	})
	seg:spike({ tip, tip + V(0.4, -0.05, 0.18) * s, tip + V(0.65, 0.08, 0.45) * s, tip + V(0.78, 0.28, 0.72) * s }, {
		r = 0.17 * s, steps = 3, sides = 4, rys = 0.5, c0 = P.flame0, c1 = P.flame1,
	})
end

local SPECS = {}

-- Adult: slender and low (like the reference art): the belly hangs under a
-- stud above the ground on short, thin, bent legs (elbows back, forearms
-- forward, flat paws), a long thin S-neck carries a big horned head.
function SPECS.Adult(P)
	local spec = newSpec()

	-- Torso + dorsal flames
	local torso = spec.seg("Torso")
	torso:loft({
		{ p = V(0, 1.95, -1.55), rx = 0.42, ry = 0.42 },
		{ p = V(0, 1.82, -1.15), rx = 0.78, ry = 0.7, ryb = 0.8 },
		{ p = V(0, 1.62, -0.35), rx = 0.86, ry = 0.68, ryb = 0.78 },
		{ p = V(0, 1.8, 0.45), rx = 0.74, ry = 0.6, ryb = 0.6 },
		{ p = V(0, 2.1, 1.15), rx = 0.66, ry = 0.58, ryb = 0.52 },
		{ p = V(0, 2.12, 1.7), rx = 0.4, ry = 0.4 },
	}, { sides = 8, main = P.main, belly = P.belly, bellyAt = 0.6, top = P.dark })
	for _, d in ipairs({ { V(0, 2.4, -0.9), 0.22, 0.7 }, { V(0, 2.22, -0.2), 0.2, 0.6 }, { V(0, 2.37, 0.55), 0.17, 0.5 }, { V(0, 2.64, 1.2), 0.14, 0.4 } }) do
		flame(torso, d[1], V(0, 1, 0.35), V(0, 0, 1), d[3], d[2], P, { rxs = 0.45, up = Vector3.zAxis })
	end
	spec.joint("Torso", "Root", V(0, 1.6, 0))

	-- Neck
	local neck = spec.seg("Neck")
	neck:loft({
		{ p = V(0, 1.9, -1.3), rx = 0.46, ry = 0.46 },
		{ p = V(0, 2.45, -1.68), rx = 0.4, ry = 0.38 },
		{ p = V(0, 3.0, -1.85), rx = 0.35, ry = 0.34 },
		{ p = V(0, 3.45, -1.82), rx = 0.33, ry = 0.32 },
		{ p = V(0, 3.85, -1.78), rx = 0.31, ry = 0.3 },
	}, { sides = 8, dorsal = V(0, 0.35, 1).Unit, main = P.main, belly = P.belly, bellyAt = 0.6, top = P.dark, capStart = false, capEnd = false })
	for _, d in ipairs({ { V(0, 2.6, -1.35), 0.12, 0.36 }, { V(0, 3.02, -1.52), 0.11, 0.33 }, { V(0, 3.45, -1.5), 0.1, 0.3 } }) do
		flame(neck, d[1], V(0, 0.35, 1), V(0, 1, 0), d[3], d[2], P, { rxs = 0.45, up = Vector3.yAxis })
	end
	spec.joint("Neck", "Torso", V(0, 1.95, -1.3))

	-- Head: skull + snout, eyes, brows, horns, crest, frills, fangs
	local head = spec.seg("Head")
	head:loft({
		{ p = V(0, 5.28, -1.8), rx = 0.36, ry = 0.34 },
		{ p = V(0, 5.38, -2.15), rx = 0.58, ry = 0.5, ryb = 0.44 },
		{ p = V(0, 5.33, -2.6), rx = 0.56, ry = 0.46, ryb = 0.4 },
		{ p = V(0, 5.18, -3.05), rx = 0.4, ry = 0.33, ryb = 0.3 },
		{ p = V(0, 5.08, -3.45), rx = 0.3, ry = 0.25, ryb = 0.23 },
	}, { sides = 8, main = P.main, top = P.dark, tipEnd = V(0, 5.05, -3.62) })
	for _, sx in ipairs({ -1, 1 }) do
		local hit, n = head:raycast(V(0.12 * sx, 6, -3.1), V(0.1 * sx, -1, -0.25).Unit)
		if hit then
			head:decal(hit, n, -Vector3.zAxis, 0.035, 0.075, P.pupil)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		head:eye(V(0.47 * sx, 5.52, -2.55), V(sx, 0.45, -0.5), Vector3.yAxis, {
			rx = 0.2, ry = 0.14, iris = P.iris, rim = P.irisRim, pupil = P.pupil, pupilW = 0.045, pupilH = 0.12,
			glint = P.glint, glintSize = 0.045,
		})
		head:spike({ V(0.3 * sx, 5.66, -2.78), V(0.46 * sx, 5.74, -2.5), V(0.52 * sx, 5.78, -2.2), V(0.55 * sx, 5.9, -1.95) }, {
			r = 0.1, steps = 3, sides = 4, c0 = P.dark, c1 = P.dark,
		})
		head:spike({ V(0.28 * sx, 5.62, -2.0), V(0.42 * sx, 6.05, -1.65), V(0.5 * sx, 6.0, -1.05), V(0.6 * sx, 6.55, -0.65) }, {
			r = 0.19, steps = 5, sides = 4, rys = 0.75, c0 = P.flame0, c1 = P.flame1, taper = 0.9,
		})
		head:spike({ V(0.42 * sx, 5.45, -1.9), V(0.66 * sx, 5.65, -1.55), V(0.75 * sx, 5.55, -1.15), V(0.92 * sx, 5.9, -0.9) }, {
			r = 0.13, steps = 4, sides = 4, rys = 0.75, c0 = P.flame0, c1 = P.flame1, taper = 0.9,
		})
		head:spike({ V(0.45 * sx, 5.1, -2.25), V(0.72 * sx, 5.1, -2.05), V(0.85 * sx, 5.05, -1.8), V(1.0 * sx, 5.25, -1.6) }, {
			r = 0.1, steps = 3, sides = 4, rys = 0.6, c0 = P.flame0, c1 = P.flame1,
		})
		head:spike({ V(0.2 * sx, 5.0, -3.15), V(0.21 * sx, 4.85, -3.18), V(0.22 * sx, 4.72, -3.2) }, {
			r = 0.05, steps = 1, sides = 3, c0 = P.claw, c1 = P.claw, up = -Vector3.zAxis,
		})
	end
	head:spike({ V(0, 5.72, -2.45), V(0, 6.05, -2.2), V(0, 5.95, -1.9), V(0, 6.25, -1.7) }, {
		r = 0.13, steps = 4, sides = 4, rxs = 0.5, up = Vector3.zAxis, c0 = P.flame0, c1 = P.flame1,
	})
	-- The head is drawn small and high: scale it (and the jaw) up about its
	-- joint, then move that joint onto the top of the neck.
	local HEAD_PIVOT, HEAD_SCALE, HEAD_SHIFT = V(0, 5.1, -2.05), 1.15, V(0, -1.27, 0.27)
	local function headSpace(p)
		return HEAD_PIVOT + (p - HEAD_PIVOT) * HEAD_SCALE + HEAD_SHIFT
	end
	head:map(headSpace)
	spec.joint("Head", "Neck", headSpace(V(0, 5.1, -2.05)))

	local jaw = spec.seg("Jaw")
	jaw:loft({
		{ p = V(0, 5.0, -2.0), rx = 0.36, ry = 0.18 },
		{ p = V(0, 4.9, -2.45), rx = 0.44, ry = 0.2, ryb = 0.24 },
		{ p = V(0, 4.9, -2.95), rx = 0.33, ry = 0.16, ryb = 0.2 },
		{ p = V(0, 4.93, -3.32), rx = 0.22, ry = 0.12, ryb = 0.14 },
	}, { sides = 8, main = P.main, belly = P.belly, bellyAt = 0.3, capStart = false })
	jaw:map(headSpace)
	spec.joint("Jaw", "Head", headSpace(V(0, 5.0, -2.0)))

	-- Left wing (mirrored below), raised and spread so it reads from the
	-- game's high camera
	wing(spec, V(-0.55, 2.4, -0.85), V(-1.43, 3.19, -0.54), V(-2.05, 3.76, 0.07), V(-2.4, 4.47, -0.06), V(-2.66, 3.54, 1.13), V(-2.0, 2.66, 1.75), V(-0.46, 2.4, 0.73), 0.14, P)

	-- Left legs: short and thin, elbow back / knee forward
	local fl = spec.seg("FrontLegL")
	fl:tube({ V(-0.55, 1.75, -1.1), V(-0.66, 1.3, -0.95), V(-0.7, 0.9, -0.85) }, { 0.3, 0.24, 0.18 }, { sides = 6, dorsal = -Vector3.zAxis, main = P.main, capStart = false })
	spec.joint("FrontLegL", "Torso", V(-0.55, 1.7, -1.1))
	local ff = spec.seg("FrontFootL")
	ff:tube({ V(-0.7, 0.95, -0.86), V(-0.7, 0.55, -1.12), V(-0.7, 0.28, -1.32) }, { 0.18, 0.14, 0.13 }, { sides = 6, dorsal = -Vector3.zAxis, main = P.main, capEnd = false })
	paw(ff, V(-0.7, 0, -1.25), V(0, 0, -1), 0.45, 0.22, P)
	spec.joint("FrontFootL", "FrontLegL", V(-0.7, 0.92, -0.86))

	local bl = spec.seg("BackLegL")
	-- hind legs taller and thicker than the front ones: the hindquarters
	-- stand slightly higher than the chest
	bl:tube({ V(-0.58, 2.18, 0.95), V(-0.78, 1.6, 0.7), V(-0.82, 1.1, 0.45) }, { 0.54, 0.5, 0.28 }, { sides = 6, dorsal = -Vector3.zAxis, main = P.main, capStart = false })
	spec.joint("BackLegL", "Torso", V(-0.58, 2.12, 0.95))
	local bf = spec.seg("BackFootL")
	bf:tube({ V(-0.82, 1.15, 0.45), V(-0.82, 0.58, 0.92), V(-0.8, 0.26, 0.8) }, { 0.28, 0.19, 0.17 }, { sides = 6, dorsal = -Vector3.zAxis, main = P.main, capEnd = false })
	paw(bf, V(-0.8, 0, 0.86), V(0, 0, -1), 0.52, 0.27, P)
	spec.joint("BackFootL", "BackLegL", V(-0.82, 1.13, 0.46))

	-- Long thin tail curling to the dragon's right, ending in a flame
	local tpts = { V(0, 2.1, 1.4), V(0, 1.78, 2.15), V(0.1, 1.25, 2.85), V(0.35, 0.78, 3.5), V(0.8, 0.5, 4.0), V(1.35, 0.45, 4.3), V(1.9, 0.55, 4.4) }
	local tsegs = tail(spec, tpts, { 0.42, 0.36, 0.3, 0.25, 0.2, 0.15, 0.11 }, P, P.dark)
	flame(tsegs[1], V(0, 2.1, 2.1), V(0, 1, 0.4), V(0, 0, 1), 0.36, 0.12, P, { rxs = 0.45, up = Vector3.zAxis })
	flame(tsegs[2], V(0.22, 1.24, 3.2), V(0.1, 1, 0.5), V(0.3, 0, 1), 0.3, 0.1, P, { rxs = 0.45, up = Vector3.zAxis })
	tailFlame(tsegs[3], tpts[7], 0.9, P)

	spec.mirrorSides()
	return spec
end

-- Baby: big round head (eyes about a third of its width), short snout, a
-- crest of flame tongues instead of horns, a small slim body crouched low on
-- thin bent legs, a thin neck, small raised wings, a thin curled tail.
-- Plain orange (no dorsal stripe).
function SPECS.Baby(P)
	local spec = newSpec()

	local torso = spec.seg("Torso")
	torso:loft({
		{ p = V(0, 1.12, -0.72), rx = 0.32, ry = 0.32 },
		{ p = V(0, 1.0, -0.45), rx = 0.5, ry = 0.46, ryb = 0.5 },
		{ p = V(0, 0.95, 0.0), rx = 0.56, ry = 0.48, ryb = 0.5 },
		{ p = V(0, 1.08, 0.42), rx = 0.52, ry = 0.44, ryb = 0.42 },
		{ p = V(0, 1.16, 0.78), rx = 0.32, ry = 0.3 },
	}, { sides = 8, main = P.main, belly = P.belly, bellyAt = 0.6 })
	for _, d in ipairs({ { V(0, 1.4, -0.1), 0.12, 0.3 }, { V(0, 1.5, 0.35), 0.1, 0.25 } }) do
		flame(torso, d[1], V(0, 1, 0.35), V(0, 0, 1), d[3], d[2], P, { rxs = 0.5, up = Vector3.zAxis })
	end
	spec.joint("Torso", "Root", V(0, 0.9, 0))

	local neck = spec.seg("Neck")
	neck:loft({
		{ p = V(0, 1.05, -0.55), rx = 0.3, ry = 0.3 },
		{ p = V(0, 1.5, -0.78), rx = 0.26, ry = 0.26 },
		{ p = V(0, 1.95, -0.84), rx = 0.25, ry = 0.25 },
	}, { sides = 8, dorsal = V(0, 0.35, 1).Unit, main = P.main, belly = P.belly, bellyAt = 0.6, capStart = false, capEnd = false })
	spec.joint("Neck", "Torso", V(0, 1.08, -0.55))

	local head = spec.seg("Head")
	head:loft({
		{ p = V(0, 2.5, -0.35), rx = 0.5, ry = 0.5 },
		{ p = V(0, 2.6, -0.62), rx = 0.8, ry = 0.76, ryb = 0.66 },
		{ p = V(0, 2.6, -1.02), rx = 0.84, ry = 0.74, ryb = 0.62 },
		{ p = V(0, 2.45, -1.42), rx = 0.64, ry = 0.54, ryb = 0.48 },
		{ p = V(0, 2.32, -1.7), rx = 0.44, ry = 0.36, ryb = 0.34 },
	}, { sides = 8, main = P.main, tipEnd = V(0, 2.28, -1.86) })
	local eyes, nostrils = {}, {}
	for _, sx in ipairs({ -1, 1 }) do
		-- on the side of the head so they read in profile (the usual view)
		eyes[sx] = { head:raycast(V(2 * sx, 2.85, -1.02), V(-sx, 0, 0)) }
		nostrils[sx] = { head:raycast(V(0.15 * sx, 3.4, -2.1), V(0.05 * sx, -1, 0.3).Unit) }
	end
	for _, sx in ipairs({ -1, 1 }) do
		local hit, n = eyes[sx][1], eyes[sx][2]
		local normal = (n + V(0.15 * sx, 0.05, -0.25)).Unit
		head:eye(hit, normal, Vector3.yAxis, {
			rx = 0.27, ry = 0.29, iris = P.iris, rim = P.irisRim, pupil = P.pupil, pupilW = 0.1, pupilH = 0.17,
			glint = P.glint, glintSize = 0.075,
		})
		if nostrils[sx][1] then
			head:decal(nostrils[sx][1], nostrils[sx][2], -Vector3.zAxis, 0.035, 0.06, P.pupil)
		end
		-- eyelid ridge: an arc hugging the top of the eye, thick at the front
		local up = (Vector3.yAxis - normal * normal.Y).Unit
		local fwd = (-Vector3.zAxis - normal * -normal.Z - up * -up.Z).Unit
		head:spike({
			hit + up * 0.3 + fwd * 0.25 + normal * 0.03,
			hit + up * 0.4 + normal * 0.06,
			hit + up * 0.3 - fwd * 0.3 + normal * 0.02,
		}, { r = 0.1, steps = 3, sides = 4, c0 = P.dark, c1 = P.main, capStart = true })
		-- crest flames: side, back, cheek
		head:spike({ V(0.35 * sx, 3.15, -0.95), V(0.52 * sx, 3.55, -0.75), V(0.55 * sx, 3.4, -0.4), V(0.72 * sx, 3.75, -0.15) }, {
			r = 0.19, steps = 4, sides = 4, rys = 0.7, c0 = P.flame0, c1 = P.flame1,
		})
		head:spike({ V(0.5 * sx, 2.95, -0.6), V(0.78 * sx, 3.2, -0.4), V(0.82 * sx, 3.05, -0.12), V(1.0 * sx, 3.3, 0.05) }, {
			r = 0.15, steps = 3, sides = 4, rys = 0.7, c0 = P.flame0, c1 = P.flame1,
		})
		head:spike({ V(0.65 * sx, 2.35, -0.75), V(0.92 * sx, 2.35, -0.55), V(1.02 * sx, 2.3, -0.35), V(1.15 * sx, 2.5, -0.2) }, {
			r = 0.11, steps = 3, sides = 4, rys = 0.6, c0 = P.flame0, c1 = P.flame1,
		})
	end
	head:spike({ V(0, 3.2, -1.2), V(0, 3.65, -1.0), V(0, 3.55, -0.6), V(0, 3.95, -0.3) }, {
		r = 0.22, steps = 4, sides = 4, rxs = 0.5, up = Vector3.zAxis, c0 = P.flame0, c1 = P.flame1,
	})
	-- The head is drawn for a taller body: settle it (and the jaw) onto the
	-- top of the neck.
	local HEAD_SHIFT = V(0, -0.3, 0.04)
	local function headSpace(p)
		return p + HEAD_SHIFT
	end
	head:map(headSpace)
	spec.joint("Head", "Neck", headSpace(V(0, 2.2, -0.86)))

	local jaw = spec.seg("Jaw")
	jaw:loft({
		{ p = V(0, 2.15, -0.55), rx = 0.46, ry = 0.16 },
		{ p = V(0, 2.02, -0.95), rx = 0.56, ry = 0.18, ryb = 0.24 },
		{ p = V(0, 2.04, -1.4), rx = 0.42, ry = 0.14, ryb = 0.18 },
		{ p = V(0, 2.1, -1.7), rx = 0.26, ry = 0.1, ryb = 0.12 },
	}, { sides = 8, main = P.main, belly = P.belly, bellyAt = 0.3, capStart = false })
	jaw:map(headSpace)
	spec.joint("Jaw", "Head", headSpace(V(0, 2.18, -0.55)))

	wing(spec, V(-0.33, 1.4, -0.3), V(-0.7, 1.8, -0.15), V(-0.95, 2.1, 0.15), V(-1.1, 2.45, 0.05), V(-1.28, 1.95, 0.62), V(-0.92, 1.55, 0.85), V(-0.28, 1.4, 0.35), 0.09, P)

	-- Thin bent legs of a crouching hatchling
	local fl = spec.seg("FrontLegL")
	fl:tube({ V(-0.34, 0.95, -0.45), V(-0.42, 0.72, -0.4), V(-0.44, 0.55, -0.4) }, { 0.2, 0.17, 0.14 }, { sides = 6, dorsal = -Vector3.zAxis, main = P.main, capStart = false })
	spec.joint("FrontLegL", "Torso", V(-0.34, 0.92, -0.45))
	local ff = spec.seg("FrontFootL")
	ff:tube({ V(-0.44, 0.58, -0.4), V(-0.45, 0.38, -0.52), V(-0.46, 0.2, -0.62) }, { 0.14, 0.12, 0.11 }, { sides = 6, dorsal = -Vector3.zAxis, main = P.main, capEnd = false })
	paw(ff, V(-0.46, 0, -0.56), V(0, 0, -1), 0.34, 0.17, P)
	spec.joint("FrontFootL", "FrontLegL", V(-0.44, 0.56, -0.4))

	local bl = spec.seg("BackLegL")
	-- hind legs taller and thicker than the front ones: the hindquarters
	-- stand slightly higher than the chest
	bl:tube({ V(-0.36, 1.18, 0.42), V(-0.52, 0.82, 0.3), V(-0.55, 0.55, 0.16) }, { 0.38, 0.36, 0.19 }, { sides = 6, dorsal = -Vector3.zAxis, main = P.main, capStart = false })
	spec.joint("BackLegL", "Torso", V(-0.36, 1.13, 0.42))
	local bf = spec.seg("BackFootL")
	bf:tube({ V(-0.55, 0.59, 0.17), V(-0.55, 0.29, 0.52), V(-0.54, 0.15, 0.45) }, { 0.18, 0.14, 0.13 }, { sides = 6, dorsal = -Vector3.zAxis, main = P.main, capEnd = false })
	paw(bf, V(-0.54, 0, 0.5), V(0, 0, -1), 0.4, 0.21, P)
	spec.joint("BackFootL", "BackLegL", V(-0.55, 0.57, 0.17))

	local tpts = { V(0, 1.14, 0.62), V(0, 0.92, 1.05), V(0.06, 0.62, 1.45), V(0.25, 0.35, 1.82), V(0.6, 0.3, 2.08), V(0.95, 0.36, 2.18), V(1.25, 0.55, 2.15) }
	local tsegs = tail(spec, tpts, { 0.28, 0.24, 0.2, 0.17, 0.14, 0.11, 0.08 }, P)
	tailFlame(tsegs[3], tpts[7], 0.55, P)

	spec.mirrorSides()
	return spec
end

------------------------------------------------------------------ build

local function jointFrame(p, axisX)
	if axisX then
		local x = axisX.Unit
		local up = (Vector3.yAxis - x * x.Y).Unit
		return CFrame.fromMatrix(p, x, up, x:Cross(up))
	end
	return CFrame.new(p)
end

-- Builds the model (unparented, pivot at the origin). Returns the model and
-- a per-segment triangle count summary.
function Builder.Build(element, stage)
	local P = assert(PALETTES[element], "No palette for " .. tostring(element))
	local spec = assert(SPECS[stage], "No spec for " .. tostring(stage))(P)
	local work = Instance.new("Folder")
	work.Name = "_DragonBuild"
	work.Parent = workspace

	local model = Instance.new("Model")
	model.Name = stage
	-- Named like a character's root so the Animation Editor picks the rig up.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V(1, 0.4, 1)
	root.CFrame = CFrame.new(0, 0.2, 0)
	root.PivotOffset = CFrame.new(0, -0.2, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local parts, stats = { Root = root }, {} -- specs call the root "Root"
	for _, seg in ipairs(spec.segs) do
		local u, count = seg:build(work)
		u.Anchored = false
		u.CanCollide = false
		u.CanTouch = false
		u.Massless = true
		u.Parent = model
		parts[seg.name] = u
		table.insert(stats, seg.name .. "=" .. count)
	end
	for _, j in ipairs(spec.joints) do
		local p0, p1 = assert(parts[j[2]], j[2]), assert(parts[j[1]], j[1])
		local frame = jointFrame(j[3], j[4])
		local m = Instance.new("Motor6D")
		m.Name = j[1]
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = p0.CFrame:ToObjectSpace(frame)
		m.C1 = p1.CFrame:ToObjectSpace(frame)
		m.Parent = p1
	end
	local controller = Instance.new("AnimationController")
	controller.Parent = model
	Instance.new("Animator").Parent = controller
	model:SetAttribute("Element", element)
	model:SetAttribute("Stage", stage)
	work:Destroy()
	return model, table.concat(stats, " ")
end

Builder.Seg = Seg
Builder.Palettes = PALETTES
Builder.Specs = SPECS

return Builder
