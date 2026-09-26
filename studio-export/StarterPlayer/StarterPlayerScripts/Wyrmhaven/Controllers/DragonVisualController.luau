-- The dragons' 3D models on the island. DragonService keeps every dragon as
-- an anchor Part (tag "Dragon"; attributes DragonId, Element, Stage and
-- HabitatId / IncubatorId / NurseryId) at its slot, invisible when its stage
-- has a rigged model (Config.DragonModels). This controller hangs a
-- client-only DragonRig named "DragonVisual" under each such anchor and
-- animates it: in a habitat the dragon strolls around its slot and pauses
-- (walk / idle), at the Nursery or in the Incubator it idles in place.
-- InteractionController maps taps on the rig back to its anchor. Purely
-- cosmetic: the server never sees where a dragon strolled.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DragonModels = require(ReplicatedStorage.Wyrmhaven.Config.DragonModels)
local DragonRig = require(script.Parent.Parent.UI.DragonRig)

local DragonVisualController = {}

local TAG = "Dragon"
local VISUAL_NAME = "DragonVisual"
local ANIMATE_DISTANCE = 250 -- studs from the camera; farther rigs hold their pose
local FACE_CAMERA_YAW = math.pi -- the island camera looks toward -Z, so facing +Z faces it
local TURN_SPEED = math.rad(150) -- radians per second
local WALK_FACING = math.rad(35) -- turns in place until the target is this close to straight ahead
local PAUSE_MIN, PAUSE_MAX = 3, 8 -- seconds standing still between strolls
local EDGE_MARGIN = 1.5 -- studs kept between a stroll target and the habitat's edge
local DECOR_STEP = 0.35 -- ground this much above the slot is decor, not walkable
local SLOT_SHARE = 0.42 -- stroll radius cap, as a share of the distance to the nearest other slot
local BY_STAGE = {
	Adult = { radius = 2.6, speed = 1.7 },
	Baby = { radius = 1.8, speed = 1.2 },
}

local states = {} -- [anchor] = state

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function wrapAngle(angle)
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Yaw that turns a model (facing -Z) toward a horizontal direction.
local function yawToward(direction)
	return math.atan2(-direction.X, -direction.Z)
end

local function turnToward(from, to, maxStep)
	local diff = wrapAngle(to - from)
	return from + math.clamp(diff, -maxStep, maxStep), math.abs(diff)
end

local function randomPause()
	return PAUSE_MIN + math.random() * (PAUSE_MAX - PAUSE_MIN)
end

local function stageTuning(state)
	return BY_STAGE[state.stage] or BY_STAGE.Adult
end

-- A dragon strolls only while it lives in a habitat (not at the Nursery's
-- tree, not waiting in the Incubator).
local function canStroll(state)
	return state.anchor:GetAttribute("HabitatId") ~= nil and state.anchor.Parent ~= nil
end

-- How far it may stroll from its slot: its stage's radius, cut short so it
-- keeps clear of the habitat's other slots.
local function strollRadius(state)
	local radius = stageTuning(state).radius
	local habitat = state.anchor.Parent
	if habitat then
		for _, child in ipairs(habitat:GetChildren()) do
			if child:IsA("Attachment") and child.Name:match("^Slot%d+$") then
				local offset = child.WorldPosition - state.home
				local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				if distance > 0.5 then
					radius = math.min(radius, distance * SLOT_SHARE)
				end
			end
		end
	end
	return radius
end

-- On the habitat's platform, away from its edge, and not on its decor
-- (rocks, trees, the volcano...: ground clearly above the slot's).
local function walkable(habitat, point, groundY)
	if not habitat:IsA("BasePart") then
		return true
	end
	local localPoint = habitat.CFrame:PointToObjectSpace(point)
	if math.abs(localPoint.X) > habitat.Size.X / 2 - EDGE_MARGIN or math.abs(localPoint.Z) > habitat.Size.Z / 2 - EDGE_MARGIN then
		return false
	end
	local visual = habitat:FindFirstChild("Visual")
	if visual then
		rayParams.FilterDescendantsInstances = { visual }
		local hit = Workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -12, 0), rayParams)
		if hit and hit.Position.Y > groundY + DECOR_STEP then
			return false
		end
	end
	return true
end

local function pickTarget(state)
	local habitat = state.anchor.Parent
	for _ = 1, 8 do
		local angle = math.random() * 2 * math.pi
		local distance = state.radius * math.sqrt(math.random())
		local point = state.home + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if (point - state.pos).Magnitude > 0.6
			and walkable(habitat, point, state.home.Y)
			and walkable(habitat, (point + state.pos) / 2, state.home.Y)
		then
			return point
		end
	end
	return nil
end

-- Back on its slot, facing the camera give or take: after spawning, and
-- whenever the server moves its anchor (moved habitat, Nursery, placing).
local function rehome(state)
	local anchor = state.anchor
	state.home = anchor.Position - Vector3.new(0, anchor.Size.Y / 2, 0)
	state.pos = state.home
	state.yaw = FACE_CAMERA_YAW + (math.random() - 0.5) * 1.2
	state.restYaw = nil
	state.mode = "Idle"
	state.target = nil
	state.timer = randomPause() * 0.5
	state.radius = strollRadius(state)
end

local function place(state, now)
	local rig = state.rig
	rig:Apply(CFrame.new(state.pos) * CFrame.Angles(0, state.yaw, 0), rig:Pose(now - state.t0, state.walk, state.phase))
end

local function rebuild(state)
	if state.rig then
		state.rig:Destroy()
		state.rig = nil
	end
	local anchor = state.anchor
	state.stage = anchor:GetAttribute("Stage")
	local template = DragonModels.Get(anchor:GetAttribute("Element"), state.stage)
	if not template then
		return -- an egg, or an element without a model: the anchor's ball shows
	end
	local rig = DragonRig.new(template)
	rig.model.Name = VISUAL_NAME
	state.rig = rig
	rehome(state)
	place(state, os.clock())
	rig.model.Parent = anchor
end

local function track(anchor)
	if states[anchor] or not anchor:IsA("BasePart") then
		return
	end
	local state = { anchor = anchor, t0 = math.random() * 100, walk = 0, phase = 0, connections = {} }
	states[anchor] = state
	local function onModelChanged()
		rebuild(state)
	end
	table.insert(state.connections, anchor:GetAttributeChangedSignal("Stage"):Connect(onModelChanged))
	table.insert(state.connections, anchor:GetAttributeChangedSignal("Element"):Connect(onModelChanged))
	-- Moved by the server (habitat moved, off to the Nursery, out of the
	-- Incubator): its parent decides which slots bound its strolls.
	local function onMoved()
		if state.rig and anchor.Parent then
			rehome(state)
		end
	end
	table.insert(state.connections, anchor:GetPropertyChangedSignal("CFrame"):Connect(onMoved))
	table.insert(state.connections, anchor:GetPropertyChangedSignal("Parent"):Connect(onMoved))
	rebuild(state)
end

local function untrack(anchor)
	local state = states[anchor]
	if not state then
		return
	end
	states[anchor] = nil
	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	if state.rig then
		state.rig:Destroy()
	end
end

-- Idle: waits out its pause (turning toward its resting direction), then
-- picks a spot to stroll to. Walk: turns toward the spot, walks once facing
-- it, and pauses on arrival - half the time turned back toward the camera.
local function update(state, dt, now)
	local tuning = stageTuning(state)
	local walking = false
	if state.mode == "Walk" and state.target and canStroll(state) then
		local offset = state.target - state.pos
		offset = Vector3.new(offset.X, 0, offset.Z)
		local distance = offset.Magnitude
		if distance < 0.05 then
			state.mode = "Idle"
			state.target = nil
			state.timer = randomPause()
			state.restYaw = math.random() < 0.5 and FACE_CAMERA_YAW + (math.random() - 0.5) * 1.2 or nil
		else
			local gap
			state.yaw, gap = turnToward(state.yaw, yawToward(offset), TURN_SPEED * dt)
			if gap < WALK_FACING then
				state.pos += offset.Unit * math.min(distance, tuning.speed * dt)
			end
			walking = true
		end
	else
		state.mode = "Idle"
		if state.restYaw then
			state.yaw = turnToward(state.yaw, state.restYaw, TURN_SPEED * 0.5 * dt)
		end
		state.timer -= dt
		if state.timer <= 0 then
			state.timer = randomPause()
			if canStroll(state) then
				state.target = pickTarget(state)
				if state.target then
					state.mode = "Walk"
					state.restYaw = nil
				end
			end
		end
	end
	state.walk += ((walking and 1 or 0) - state.walk) * math.min(1, dt * 5)
	state.phase = (state.phase + 2 * math.pi * state.rig:CycleRate(tuning.speed) * state.walk * dt) % (2 * math.pi)
	place(state, now)
end

function DragonVisualController.Init()
	task.spawn(function()
		-- The models must have replicated before the first rig is built.
		ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):WaitForChild("Dragons", 15)
		CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
		CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)
		for _, anchor in ipairs(CollectionService:GetTagged(TAG)) do
			track(anchor)
		end
		RunService.RenderStepped:Connect(function(dt)
			local camera = Workspace.CurrentCamera
			local cameraPosition = camera and camera.CFrame.Position or Vector3.zero
			local now = os.clock()
			dt = math.min(dt, 0.1)
			for _, state in pairs(states) do
				if state.rig and (state.pos - cameraPosition).Magnitude < ANIMATE_DISTANCE then
					update(state, dt, now)
				end
			end
		end)
	end)
end

return DragonVisualController
