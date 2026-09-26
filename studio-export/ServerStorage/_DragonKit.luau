-- Temporary dragon builder (loadstring'd from the command bar). Same faceted
-- low-poly look as the island and the habitats: everything is drawn as
-- triangles (pairs of WedgeParts) and each body segment is then merged into a
-- single union - which is what makes the dragon animatable, since a Motor6D
-- joins two parts.
--
-- The rig (one set of animations fits every dragon):
--   Root -> Torso -> Neck -> Head -> Jaw
--   Torso -> TailA -> TailB -> TailC
--   Torso -> (Left|Right)Shoulder -> Elbow, (Left|Right)Hip -> Knee
--   Torso -> (Left|Right)Wing -> WingTip
-- Only the HumanoidRootPart is anchored; the other parts are massless and held
-- by the joints. Dragons are built facing -Z, standing on y = 0.
local Kit = {}

local V = Vector3.new
local SMOOTH = Enum.Material.SmoothPlastic

Kit.model = nil
Kit.group = nil -- the segment being drawn
Kit.thickness = 0.12

function Kit.rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function prep(part, color, props)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = SMOOTH
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	if props then
		for key, value in pairs(props) do
			part[key] = value
		end
	end
	part.Parent = Kit.group
	return part
end

function Kit.block(size, cframe, color, props)
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	return prep(part, color, props)
end

-- Flat triangle a-b-c as two wedges. `inside`: a point inside the volume, so
-- the slab is pushed inwards and the outer face stays exact.
function Kit.tri(a, b, c, color, thickness, inside, props)
	thickness = thickness or Kit.thickness
	local normal = (b - a):Cross(c - a)
	if normal.Magnitude < 1e-4 then
		return
	end
	if inside then
		normal = normal.Unit
		local centroid = (a + b + c) / 3
		if normal:Dot(inside - centroid) < 0 then
			normal = -normal
		end
		local shift = normal * (thickness / 2)
		a, b, c = a + shift, b + shift, c + shift
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
	if height < 0.004 then
		return
	end
	for _, spec in ipairs({
		{ (a + b) / 2, right, back, math.abs(ab:Dot(back)) },
		{ (a + c) / 2, -right, -back, math.abs(ac:Dot(back)) },
	}) do
		if spec[4] > 0.004 then
			local wedge = Instance.new("WedgePart")
			wedge.Size = V(thickness, height, spec[4])
			wedge.CFrame = CFrame.fromMatrix(spec[1], spec[2], up, spec[3])
			prep(wedge, color, props)
		end
	end
end

function Kit.quad(a, b, c, d, color, thickness, inside, props)
	Kit.tri(a, b, c, color, thickness, inside, props)
	Kit.tri(a, c, d, color, thickness, inside, props)
end

-- Flat polygon (list of 3D points in one plane), `thickness` thick: wings,
-- fins, leaves, plates.
function Kit.poly(points, color, thickness, props)
	local center = Vector3.zero
	for _, point in ipairs(points) do
		center += point
	end
	center /= #points
	for index = 1, #points do
		Kit.tri(center, points[index], points[index % #points + 1], color, thickness, nil, props)
	end
end

-- Ring of vertices around `center`, in the plane whose normal is `axis`.
local function ring(center, axis, right, radiusX, radiusY, sides, start)
	local up = axis:Cross(right).Unit
	local points = {}
	for index = 1, sides do
		local angle = (start or 0) + (index - 1) / sides * math.pi * 2
		points[index] = center + right * (math.cos(angle) * radiusX) + up * (math.sin(angle) * radiusY)
	end
	return points
end

-- Faceted volume along the line from `from` to `to`: `profile` gives the
-- half-width at each step { t, width, height }, so one call makes a body, a
-- neck, a tail segment or a limb. colorFn(band, side) picks each facet color.
function Kit.hull(from, to, profile, sides, colorFn, opts)
	opts = opts or {}
	local axis = (to - from)
	local length = axis.Magnitude
	axis = axis.Unit
	local hint = math.abs(axis:Dot(V(0, 1, 0))) > 0.9 and V(0, 0, -1) or V(0, 1, 0)
	local right = axis:Cross(hint).Unit
	local inside = (from + to) / 2
	local rings = {}
	for index, step in ipairs(profile) do
		local center = from + axis * (length * step[1]) + (step[4] or Vector3.zero)
		rings[index] = ring(center, axis, right, step[2], step[3] or step[2], sides, opts.start or 0)
	end
	for band = 1, #rings - 1 do
		for side = 1, sides do
			local nextSide = side % sides + 1
			Kit.quad(rings[band][side], rings[band][nextSide], rings[band + 1][nextSide], rings[band + 1][side], colorFn(band, side), opts.thickness, inside, opts.props)
		end
	end
	-- Caps
	if opts.capStart ~= false then
		local center = from + (profile[1][4] or Vector3.zero) - axis * (opts.capStartRise or 0)
		for side = 1, sides do
			Kit.tri(center, rings[1][side], rings[1][side % sides + 1], colorFn(0, side), opts.thickness, inside, opts.props)
		end
	end
	if opts.capEnd ~= false then
		local last = #rings
		local center = from + axis * (length * profile[last][1]) + (profile[last][4] or Vector3.zero) + axis * (opts.capEndRise or 0)
		for side = 1, sides do
			Kit.tri(center, rings[last][side], rings[last][side % sides + 1], colorFn(last, side), opts.thickness, inside, opts.props)
		end
	end
	return rings
end

-- Faceted egg/ellipsoid along Z: the workhorse for heads, chests and rumps.
-- opts.taper thins the back end (0 = none, 0.5 = half as wide).
function Kit.egg(center, size, sides, colorFn, opts)
	opts = opts or {}
	local bands = opts.bands or 3
	local profile = {}
	for index = 0, bands do
		local t = index / bands
		local radius = math.max(math.sin(t * math.pi), 0.14)
		local squash = opts.taper and (1 - opts.taper * t) or 1
		table.insert(profile, { t, size.X / 2 * radius * squash, size.Y / 2 * radius * squash })
	end
	return Kit.hull(center - V(0, 0, size.Z / 2), center + V(0, 0, size.Z / 2), profile, sides, colorFn, {
		thickness = opts.thickness, props = opts.props, capStartRise = size.Z * 0.14, capEndRise = size.Z * 0.14, start = opts.start,
	})
end

-- Faceted cone/spike from `base` along `direction`.
function Kit.spike(base, direction, length, width, color, sides, props)
	sides = sides or 5
	local axis = direction.Unit
	local tip = base + axis * length
	local hint = math.abs(axis:Dot(V(0, 1, 0))) > 0.9 and V(0, 0, -1) or V(0, 1, 0)
	local right = axis:Cross(hint).Unit
	local points = ring(base, axis, right, width / 2, width / 2, sides)
	for index = 1, sides do
		local nextIndex = index % sides + 1
		Kit.tri(points[index], points[nextIndex], tip, color, Kit.thickness, base + axis * length * 0.3, props)
		Kit.tri(base, points[index], points[nextIndex], color, Kit.thickness, base + axis * length * 0.3, props)
	end
	return tip
end

-- Tapered faceted tube (limbs, horns, whiskers) following a slight curve.
function Kit.tube(from, to, startWidth, endWidth, color, sides, bend, props)
	sides = sides or 5
	local steps = bend and 3 or 2
	local points = {}
	for index = 0, steps do
		local t = index / steps
		local curve = bend and bend * math.sin(t * math.pi) or Vector3.zero
		points[index] = from:Lerp(to, t) + curve
	end
	for index = 0, steps - 1 do
		local a, b = points[index], points[index + 1]
		local t0, t1 = index / steps, (index + 1) / steps
		Kit.hull(a, b, {
			{ 0, startWidth + (endWidth - startWidth) * t0 },
			{ 1, startWidth + (endWidth - startWidth) * t1 },
		}, sides, function()
			return color
		end, { capStart = index == 0, capEnd = index == steps - 1, props = props })
	end
	return points[steps]
end

-- Facet shading: same color with a light/dark tweak per facet, so the flat
-- faces read like the island's rocks.
function Kit.shade(color, amount)
	return function(band, side)
		local shift = (((band or 0) + (side or 0)) % 3 - 1) * (amount or 0.05)
		return color:Lerp(shift > 0 and Color3.new(1, 1, 1) or Color3.new(0, 0, 0), math.abs(shift))
	end
end

function Kit.begin(name)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = workspace._DragonBuild
	Kit.model = model
	return model
end

-- Starts a body segment; every part drawn until endSegment goes into it.
function Kit.segment(name)
	local group = Instance.new("Model")
	group.Name = name
	group.Parent = Kit.model
	Kit.group = group
	return group
end

-- Merges the segment into one part (colors kept) so a Motor6D can drive it.
-- If CSG refuses, the pieces are welded to the biggest one instead.
function Kit.endSegment()
	local group = Kit.group
	local parts = {}
	for _, child in ipairs(group:GetDescendants()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	local result
	if #parts >= 2 then
		local first = parts[1]
		local rest = table.move(parts, 2, #parts, 1, {})
		local ok, union = pcall(function()
			return first:UnionAsync(rest, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
		end)
		if ok and union then
			union.UsePartColor = false
			union.SmoothingAngle = 0
			result = union
		else
			warn("segment union failed: " .. group.Name .. " " .. tostring(union))
		end
	end
	if not result then
		-- Fallback: the biggest piece carries the others
		local biggest, volume = nil, -1
		for _, part in ipairs(group:GetDescendants()) do
			if part:IsA("BasePart") then
				local size = part.Size.X * part.Size.Y * part.Size.Z
				if size > volume then
					biggest, volume = part, size
				end
			end
		end
		result = biggest
		for _, part in ipairs(group:GetDescendants()) do
			if part:IsA("BasePart") and part ~= biggest then
				part.Parent = Kit.model
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = biggest
				weld.Part1 = part
				weld.Parent = biggest
				part.Anchored = false
				part.Massless = true
			end
		end
	end
	result.Name = group.Name
	result.Anchored = false
	result.Massless = true
	result.CanCollide = false
	result.CanTouch = false
	result.CanQuery = false
	result.Parent = Kit.model
	group:Destroy()
	Kit.group = Kit.model
	return result
end

-- Where every joint sits, per stage. The baby keeps the same rig with a big
-- head, a short neck, stubby legs and a short tail.
local SKELETON = {
	Adult = {
		legY = 2.7,
		torso = { center = V(0, 2.7, 0.4), size = V(2.5, 2.4, 4.2) },
		belly = { center = V(0, 2.0, 0.35), size = V(2.0, 1.2, 3.7), plates = 4 },
		neckBase = V(0, 3.5, -1.6),
		neckTop = V(0, 5.1, -2.7),
		neckWidth = 1.4,
		headCenter = V(0, 5.65, -3.3),
		headSize = V(1.9, 1.75, 2.2),
		snoutTip = V(0, 5.35, -4.6),
		snoutWidth = 1.1,
		headScale = 1,
		eyeScale = 1,
		tail = {
			{ pivot = V(0, 2.7, 2.1), from = V(0, 2.7, 2.1), to = V(0, 2.6, 4.1), width = 1.6, endWidth = 1.2 },
			{ pivot = V(0, 2.6, 4.1), from = V(0, 2.6, 4.1), to = V(0, 2.3, 5.8), width = 1.2, endWidth = 0.85 },
			{ pivot = V(0, 2.3, 5.8), from = V(0, 2.3, 5.8), to = V(0, 2.0, 7.3), width = 0.85, endWidth = 0.4 },
		},
		tailEnd = V(0, 2.0, 7.3),
		front = { shoulder = V(0.95, 2.6, -1.3), elbow = V(1.0, 1.45, -1.05), foot = V(1.0, 0.3, -1.4), width = 0.95 },
		back = { hip = V(1.05, 2.65, 1.6), knee = V(1.15, 1.4, 2.05), foot = V(1.05, 0.3, 1.4), width = 1.3 },
		wing = { root = V(0.8, 3.6, -0.5), elbow = V(1.9, 5.7, 0.5), tip = V(2.3, 4.3, 2.6) },
	},
	Baby = {
		legY = 1.8,
		torso = { center = V(0, 1.8, 0.35), size = V(2.3, 2.2, 2.6) },
		belly = { center = V(0, 1.25, 0.35), size = V(1.85, 1.1, 2.3), plates = 3 },
		neckBase = V(0, 2.4, -0.8),
		neckTop = V(0, 2.95, -1.25),
		neckWidth = 1.3,
		headCenter = V(0, 3.5, -1.85),
		headSize = V(2.6, 2.45, 2.7),
		snoutTip = V(0, 3.25, -3.05),
		snoutWidth = 1.25,
		headScale = 1.35,
		eyeScale = 1.5,
		tail = {
			{ pivot = V(0, 1.75, 1.2), from = V(0, 1.75, 1.2), to = V(0, 1.65, 2.3), width = 1.2, endWidth = 0.9 },
			{ pivot = V(0, 1.65, 2.3), from = V(0, 1.65, 2.3), to = V(0, 1.5, 3.2), width = 0.9, endWidth = 0.6 },
			{ pivot = V(0, 1.5, 3.2), from = V(0, 1.5, 3.2), to = V(0, 1.35, 4.0), width = 0.6, endWidth = 0.3 },
		},
		tailEnd = V(0, 1.35, 4.0),
		front = { shoulder = V(0.72, 1.7, -0.7), elbow = V(0.74, 1.0, -0.6), foot = V(0.74, 0.28, -0.8), width = 0.8 },
		back = { hip = V(0.8, 1.72, 0.9), knee = V(0.84, 0.95, 1.15), foot = V(0.8, 0.28, 0.75), width = 1.0 },
		wing = { root = V(0.62, 2.4, -0.1), elbow = V(1.25, 3.6, 0.5), tip = V(1.5, 2.8, 1.5) },
	},
}

function Kit.skeleton(stage)
	return SKELETON[stage]
end

-- The shared faceted body. `style` brings the palette and the decorations
-- (crest, horns, wings, tail tip); this makes the parts and the joints.
function Kit.buildBody(style, stage)
	local s = SKELETON[stage]
	local palette = style.palette
	local main, shadow, belly = palette.main, palette.shadow, palette.belly
	local mainShade, bellyShade = Kit.shade(main, 0.06), Kit.shade(belly, 0.05)
	local sides = 7
	local hs = s.headScale

	local rig = { stage = stage, skeleton = s, palette = palette, headCenter = s.headCenter, headSize = s.headSize, headScale = hs, neckBase = s.neckBase, neckTop = s.neckTop, tailEnd = s.tailEnd, torsoCenter = s.torso.center, torsoSize = s.torso.size, legY = s.legY }

	-- Root
	Kit.segment("HumanoidRootPart")
	local root = Kit.block(V(1.8, 1.8, 1.8), CFrame.new(0, s.legY, 0), main, { Transparency = 1 })
	Kit.endSegment()
	root.Anchored = true
	rig.root = root

	-- Torso, with the belly plates of the reference
	Kit.segment("Torso")
	Kit.egg(s.torso.center, s.torso.size, sides, mainShade, { bands = 4 })
	Kit.egg(s.belly.center, s.belly.size, sides, bellyShade, { bands = 3 })
	for index = 1, s.belly.plates do
		local t = (index - 0.5) / s.belly.plates
		local z = s.belly.center.Z - s.belly.size.Z * 0.42 + t * s.belly.size.Z * 0.84
		Kit.egg(V(0, s.belly.center.Y - 0.12, z), V(s.belly.size.X * 0.92, s.belly.size.Y * 0.62, s.belly.size.Z / s.belly.plates * 0.82), 6, Kit.shade(palette.bellyPlate or belly, 0.08), { bands = 2 })
	end
	if style.torso then
		style.torso(rig, palette)
	end
	local torso = Kit.endSegment()
	rig.torso = torso

	-- Neck (with its own belly plates)
	Kit.segment("Neck")
	Kit.tube(s.neckBase + V(0, -0.35, 0.3), s.neckTop, s.neckWidth, s.neckWidth * 0.78, main, 6)
	for index = 1, 3 do
		local at = s.neckBase:Lerp(s.neckTop, (index - 0.5) / 3)
		local forward = (s.neckTop - s.neckBase).Unit
		local outward = V(0, forward.Z, -forward.Y).Unit
		Kit.egg(at + outward * s.neckWidth * 0.33, V(s.neckWidth * 0.62, 0.42, s.neckWidth * 0.5), 5, Kit.shade(palette.bellyPlate or belly, 0.08), { bands = 2 })
	end
	if style.neck then
		style.neck(rig, palette)
	end
	local neck = Kit.endSegment()
	rig.neck = neck

	-- Head: skull, snout, brows, eyes
	Kit.segment("Head")
	Kit.egg(s.headCenter, s.headSize, sides, mainShade, { bands = 4 })
	Kit.hull(s.headCenter + V(0, -0.05 * hs, -s.headSize.Z * 0.3), s.snoutTip, {
		{ 0, s.snoutWidth * 0.62, s.snoutWidth * 0.55 },
		{ 0.55, s.snoutWidth * 0.5, s.snoutWidth * 0.42 },
		{ 1, s.snoutWidth * 0.34, s.snoutWidth * 0.3 },
	}, 6, mainShade, { capEndRise = 0.2 })
	for _, side in ipairs({ -1, 1 }) do
		local eye = s.headCenter + V(side * s.headSize.X * 0.34, s.headSize.Y * 0.1, -s.headSize.Z * 0.26)
		local scale = s.eyeScale
		-- Almond eye: amber iris, dark pupil, small glint
		Kit.egg(eye, V(0.34, 0.66 * scale, 0.78 * scale), 6, Kit.shade(palette.eye, 0.04), { bands = 3 })
		Kit.egg(eye + V(side * 0.1, 0, -0.06), V(0.3, 0.34 * scale, 0.2 * scale), 5, Kit.shade(palette.pupil or Kit.rgb(24, 16, 14), 0), { bands = 2 })
		Kit.egg(eye + V(side * 0.12, 0.16 * scale, -0.2 * scale), V(0.22, 0.18 * scale, 0.16 * scale), 4, Kit.shade(Kit.rgb(255, 255, 255), 0), { bands = 2 })
		-- Brow ridge
		Kit.egg(eye + V(side * 0.05, 0.42 * scale, 0.05), V(0.55, 0.36, 1.0), 5, Kit.shade(shadow, 0.05), { bands = 2 })
		local nostril = s.snoutTip + V(side * s.snoutWidth * 0.18, 0.12, 0.25)
		Kit.egg(nostril, V(0.2, 0.16, 0.2), 4, Kit.shade(palette.pupil or Kit.rgb(24, 16, 14), 0), { bands = 2 })
	end
	if style.head then
		style.head(rig, palette)
	end
	local head = Kit.endSegment()
	rig.head = head

	-- Jaw
	Kit.segment("Jaw")
	local jawBack = s.headCenter + V(0, -0.36 * hs, -s.headSize.Z * 0.15)
	local jawTip = s.snoutTip + V(0, -0.25 * hs, 0.1)
	Kit.hull(jawBack, jawTip, {
		{ 0, s.headSize.X * 0.38, 0.28 * hs },
		{ 1, s.snoutWidth * 0.32, 0.2 * hs },
	}, 5, Kit.shade(shadow, 0.05), {})
	Kit.egg(jawBack:Lerp(jawTip, 0.55) + V(0, -0.12 * hs, 0), V(s.snoutWidth * 0.7, 0.3 * hs, (jawTip - jawBack).Magnitude * 0.7), 5, bellyShade, { bands = 2 })
	local jaw = Kit.endSegment()
	rig.jaw = jaw

	-- Tail
	rig.tail = {}
	for index, segment in ipairs(s.tail) do
		Kit.segment("Tail" .. index)
		Kit.tube(segment.from, segment.to, segment.width, segment.endWidth, main, 6)
		if index < 3 then
			local middle = segment.from:Lerp(segment.to, 0.5)
			Kit.egg(middle + V(0, -segment.width * 0.3, 0), V(segment.width * 0.66, segment.width * 0.4, (segment.to - segment.from).Magnitude * 0.8), 5, bellyShade, { bands = 2 })
		end
		if style.tail then
			style.tail(rig, palette, index, segment)
		end
		rig.tail[index] = Kit.endSegment()
	end

	-- Legs
	rig.legs = {}
	for _, side in ipairs({ -1, 1 }) do
		local name = side < 0 and "Left" or "Right"
		local legData = {}
		for _, pair in ipairs({ { "Front", s.front, "shoulder", "elbow" }, { "Back", s.back, "hip", "knee" } }) do
			local key, data, topName, midName = pair[1], pair[2], pair[3], pair[4]
			local function mirror(point)
				return V(side * point.X, point.Y, point.Z)
			end
			local top, mid, foot = mirror(data[topName]), mirror(data[midName]), mirror(data.foot)

			Kit.segment(name .. key .. "Upper")
			Kit.tube(top + (mid - top).Unit * -0.25, mid, data.width, data.width * 0.78, main, 5)
			local upper = Kit.endSegment()

			Kit.segment(name .. key .. "Lower")
			Kit.tube(mid, foot, data.width * 0.72, data.width * 0.55, main, 5)
			Kit.egg(foot + V(0, -0.02, -data.width * 0.22), V(data.width * 0.95, 0.5, data.width * 1.3), 5, Kit.shade(shadow, 0.05), { bands = 2 })
			for claw = -1, 1 do
				Kit.spike(foot + V(claw * data.width * 0.3, -0.1, -data.width * 0.62), V(0, -0.25, -1), 0.5, 0.28, palette.claw, 4)
			end
			local lower = Kit.endSegment()

			legData[key] = { upper = upper, lower = lower, top = top, mid = mid, foot = foot }
		end
		rig.legs[name] = legData
	end

	-- Wings (style decides what hangs on the two wing joints)
	rig.wing = function(side)
		local w = s.wing
		return V(side * w.root.X, w.root.Y, w.root.Z), V(side * w.elbow.X, w.elbow.Y, w.elbow.Z), V(side * w.tip.X, w.tip.Y, w.tip.Z)
	end
	rig.wings = {}
	for _, side in ipairs({ -1, 1 }) do
		local name = side < 0 and "Left" or "Right"
		local root2, elbow, tip = rig.wing(side)
		Kit.segment(name .. "WingUpper")
		style.wingUpper(rig, palette, side, root2, elbow, tip)
		local upper = Kit.endSegment()
		Kit.segment(name .. "WingLower")
		style.wingLower(rig, palette, side, root2, elbow, tip)
		local lower = Kit.endSegment()
		rig.wings[name] = { upper = upper, lower = lower, root = root2, elbow = elbow, tip = tip }
	end

	-- Joints
	Kit.joint("Root", root, torso, V(0, s.legY, 0))
	Kit.joint("Neck", torso, neck, s.neckBase)
	Kit.joint("Head", neck, head, s.neckTop)
	Kit.joint("Jaw", head, jaw, jawBack)
	Kit.joint("TailA", torso, rig.tail[1], s.tail[1].pivot)
	Kit.joint("TailB", rig.tail[1], rig.tail[2], s.tail[2].pivot)
	Kit.joint("TailC", rig.tail[2], rig.tail[3], s.tail[3].pivot)
	for _, name in ipairs({ "Left", "Right" }) do
		local leg = rig.legs[name]
		Kit.joint(name .. "Shoulder", torso, leg.Front.upper, leg.Front.top)
		Kit.joint(name .. "Elbow", leg.Front.upper, leg.Front.lower, leg.Front.mid)
		Kit.joint(name .. "Hip", torso, leg.Back.upper, leg.Back.top)
		Kit.joint(name .. "Knee", leg.Back.upper, leg.Back.lower, leg.Back.mid)
		local wing = rig.wings[name]
		Kit.joint(name .. "Wing", torso, wing.upper, wing.root)
		Kit.joint(name .. "WingTip", wing.upper, wing.lower, wing.elbow)
	end

	return rig
end

-- Motor6D at the world point `pivot`, so animations only have to rotate it.
function Kit.joint(name, part0, part1, pivot)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	local pivotCF = CFrame.new(pivot)
	motor.C0 = part0.CFrame:Inverse() * pivotCF
	motor.C1 = part1.CFrame:Inverse() * pivotCF
	motor.Parent = part0
	return motor
end

function Kit.finish(model, root)
	local controller = Instance.new("AnimationController")
	local animator = Instance.new("Animator")
	animator.Parent = controller
	controller.Parent = model
	model.PrimaryPart = root
	root.CanQuery = true -- the invisible root is the tap target
	return model
end

function Kit.fitLength(model, targetLength)
	local _, size = model:GetBoundingBox()
	local scale = targetLength / math.max(size.Z, 0.001)
	model:ScaleTo(scale)
	return scale
end

-- Feet on `position`, facing +Z (towards the game camera).
function Kit.place(model, position)
	model:PivotTo(CFrame.new(model:GetPivot().Position) * CFrame.Angles(0, math.pi, 0))
	local cf, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + V(position.X - cf.X, position.Y - (cf.Y - size.Y / 2), position.Z - cf.Z))
end

return Kit
