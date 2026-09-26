-- Runtime for the rigged dragon models (Config.DragonModels). A rig is a
-- clone of the template whose parts are all anchored and placed every frame
-- by forward kinematics from the template's Motor6D offsets - the same math
-- as a Motor6D (Part1 = Part0 * C0 * Transform * C1:Inverse()) - so it works
-- in the world and inside a ViewportFrame (where joints don't run) alike.
-- Poses are procedural, no uploaded animation needed: Idle (breathing,
-- looking around, tail sway, the odd wing stretch or yawn) and Walk (a trot:
-- diagonal legs together), blended by a 0..1 walk weight.
-- Joint axes follow the model's (it faces -Z): +X pitch lifts the front of a
-- part, +Y turns it left, WingL +Z / WingR -Z flap down, Jaw -X opens.
local Workspace = game:GetService("Workspace")

local DragonRig = {}
DragonRig.__index = DragonRig

local IDENTITY = CFrame.identity
local PI = math.pi
local rad, sin, cos, max = math.rad, math.sin, math.cos, math.max

-- Studs covered by one full walk cycle, by stage.
local STRIDE = { Adult = 1.3, Baby = 0.8 }

local function angles(x, y, z)
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

function DragonRig.new(template)
	local model = template:Clone()
	local root = model.PrimaryPart
	assert(root, "Dragon model without a PrimaryPart: " .. template:GetFullName())

	local byParent = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			byParent[descendant.Part0] = byParent[descendant.Part0] or {}
			table.insert(byParent[descendant.Part0], {
				name = descendant.Name,
				part0 = descendant.Part0,
				part1 = descendant.Part1,
				c0 = descendant.C0,
				c1Inv = descendant.C1:Inverse(),
			})
		end
	end
	-- Joints parents first, from the root down.
	local order, parts, queue, head = {}, { root }, { root }, 1
	while queue[head] do
		local part = queue[head]
		head += 1
		for _, joint in ipairs(byParent[part] or {}) do
			table.insert(order, joint)
			table.insert(parts, joint.part1)
			table.insert(queue, joint.part1)
		end
	end
	-- The rig places every part itself: live joints or an Animator would
	-- drag the parts back.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("JointInstance") or descendant:IsA("AnimationController") then
			descendant:Destroy()
		end
	end
	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
	end

	local stage = model:GetAttribute("Stage")
	return setmetatable({
		model = model,
		root = root,
		order = order,
		parts = parts,
		cframes = table.create(#parts, IDENTITY),
		world = {},
		-- the root part from the model's pivot (its feet)
		rootOffset = model:GetPivot():ToObjectSpace(root.CFrame),
		size = stage == "Baby" and 0.55 or 1, -- scales the bobbing
		stride = STRIDE[stage] or STRIDE.Adult,
		seed = math.random() * 100, -- desyncs dragons idling side by side
	}, DragonRig)
end

-- Walk cycles per second at `speed` studs per second.
function DragonRig:CycleRate(speed)
	return speed / self.stride
end

local function idlePose(t, s, k)
	local breathe = sin(t * 1.8 + s)
	local look = sin(t * 0.45 + s * 2)
	local yawn = max(0, sin(t * 0.23 + s)) ^ 14
	local stretch = max(0, sin(t * 0.17 + s * 0.7)) ^ 12
	local tail = t + s
	local wing = 2 + breathe * 2 - stretch * 28
	local tip = breathe * 2 + stretch * 10
	return {
		Torso = CFrame.new(0, breathe * 0.02 * k, 0) * angles(breathe * 0.8, 0, 0),
		Neck = angles(sin(t * 0.8 + s) * 3, look * 7, 0),
		Head = angles(sin(t * 0.9 + s * 1.3) * 4 - 1, sin(t * 0.45 + s * 2 - 0.6) * 10, sin(t * 0.6 + s) * 3),
		Jaw = angles(-yawn * 20, 0, 0),
		WingL = angles(0, 0, wing),
		WingR = angles(0, 0, -wing),
		WingLTip = angles(tip, 0, 0),
		WingRTip = angles(-tip, 0, 0),
		Tail1 = angles(0, sin(tail) * 6, 0),
		Tail2 = angles(0, sin(tail - 0.8) * 9, 0),
		Tail3 = angles(sin(t * 0.7 + s) * 4, sin(tail - 1.6) * 14, 0),
	}
end

-- Trot: the front-left and back-right legs swing together, then the other
-- pair. A leg swings forward (+X) while its lower part folds to lift the
-- paw (front: +X, back: -X, their lower segments point opposite ways).
local function walkPose(p, k)
	local a, b = sin(p), sin(p + PI)
	local liftA, liftB = max(0, cos(p)), max(0, cos(p + PI))
	local bounce = sin(p * 2)
	return {
		Torso = CFrame.new(0, (1 - math.abs(cos(p))) * 0.05 * k, 0) * angles(1, 0, a * 2),
		Neck = angles(-3 + bounce * 2, a * 3, 0),
		Head = angles(2 - bounce * 2, -a * 3, 0),
		Jaw = IDENTITY,
		FrontLegL = angles(a * 22, 0, 0),
		FrontFootL = angles(liftA * 35, 0, 0),
		BackLegR = angles(a * 20, 0, 0),
		BackFootR = angles(-liftA * 35, 0, 0),
		FrontLegR = angles(b * 22, 0, 0),
		FrontFootR = angles(liftB * 35, 0, 0),
		BackLegL = angles(b * 20, 0, 0),
		BackFootL = angles(-liftB * 35, 0, 0),
		WingL = angles(0, 0, -6 + bounce * 3),
		WingR = angles(0, 0, 6 - bounce * 3),
		WingLTip = IDENTITY,
		WingRTip = IDENTITY,
		Tail1 = angles(0, sin(p - 0.5) * 8, 0),
		Tail2 = angles(0, sin(p - 1.1) * 12, 0),
		Tail3 = angles(0, sin(p - 1.7) * 16, 0),
	}
end

-- Joint transforms at time t (seconds), walk weight 0 (idle) .. 1 (walking)
-- and walk cycle phase (radians).
function DragonRig:Pose(t, walk, phase)
	local pose = idlePose(t, self.seed, self.size)
	if walk > 0.001 then
		local walking = walkPose(phase, self.size)
		for name, transform in pairs(walking) do
			local still = pose[name] or IDENTITY
			pose[name] = walk >= 0.999 and transform or still:Lerp(transform, walk)
		end
	end
	return pose
end

-- Places the rig with its feet at `pivot` (facing its LookVector) in `pose`.
function DragonRig:Apply(pivot, pose)
	local world, cframes = self.world, self.cframes
	local rootCFrame = pivot * self.rootOffset
	world[self.root] = rootCFrame
	cframes[1] = rootCFrame
	for index, joint in ipairs(self.order) do
		local cframe = world[joint.part0] * joint.c0 * (pose[joint.name] or IDENTITY) * joint.c1Inv
		world[joint.part1] = cframe
		cframes[index + 1] = cframe
	end
	if self.model:IsDescendantOf(Workspace) then
		Workspace:BulkMoveTo(self.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for index, part in ipairs(self.parts) do
			part.CFrame = cframes[index]
		end
	end
end

function DragonRig:Destroy()
	self.model:Destroy()
end

return DragonRig
