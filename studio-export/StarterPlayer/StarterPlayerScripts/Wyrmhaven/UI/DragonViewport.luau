-- Live 3D view of one of the local player's dragons: its rigged model
-- (Config.DragonModels, posed by DragonRig) when its element and stage have
-- one, else a clone of its world placeholder. Framing "Head" fills a round
-- portrait, "Body" shows the whole dragon standing in front of its habitat's
-- model when given one (nothing around it but the sky: scale the habitat up
-- to fill the view), else on a ground disc. Rebuilds itself when the dragon
-- changes stage.
-- Two renderers:
-- * a ViewportFrame (portraits, the Nursery screen). A rigged dragon stays
--   still there: moving parts in a ViewportFrame makes Roblox rebuild all of
--   its geometry every frame, tens of ms with the dragons' unions. Bump
--   jolts the camera instead, which is cheap.
-- * opts.World (the full-screen Dragon screen): the scene is built in the
--   Workspace far away from the islands and the camera is lent to it
--   (CameraController.Hold) until Destroy. The world moves parts cheaply, so
--   the dragon idles there, and hops on Bump.
-- Portraits zoom on the model's "Head" part and only clone the head end of
-- it; the placeholder balls have none, so they're framed whole.
-- ViewportFrame views are built one per frame (a habitat's bar opens several
-- at once): each first draw of a dragon's unions costs a few ms.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local DragonModels = require(ReplicatedStorage.Wyrmhaven.Config.DragonModels)
local DragonRig = require(script.Parent.DragonRig)
local UIKit = require(script.Parent.UIKit)

local DragonViewport = {}

-- World mode's stage: at ground level (the Atmosphere changes with altitude)
-- but far behind the islands (around the origin), and the lent camera looks
-- away from them (-Z): it sees nothing but the stage and the sky.
local WORLD_STAGE_ORIGIN = Vector3.new(0, 0, -20000)
local HOP_HEIGHT = 1.5 -- World mode Bump: hop height per unit of bump, in half heights
local JOLT = 0.25 -- ViewportFrame Bump: camera push per unit of bump, in camera distances

-- fov: camera field of view; fill: share of the frame height the subject
-- covers; yaw/rise: where the camera sits around the dragon's face (3/4 view).
local FRAMINGS = {
	Head = { fov = 30, fill = 0.8, yaw = 25, rise = 0.25 },
	Body = { fov = 40, fill = 0.5, yaw = 35, rise = 0.45 },
	-- Body in front of its habitat: farther and lower, so the habitat fills
	-- the background behind the dragon.
	Stage = { fov = 40, fill = 0.42, yaw = 15, rise = 0.3 },
}

-- How far in front of its habitat's center the dragon stands (Stage), in
-- island-size habitat studs.
local STAGE_OFFSET_Z = 4.8

local habitatTemplates = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Habitats")

-- Extras that must not follow a model into the view (e.g. a BillboardGui).
-- A ViewportFrame can't draw effects either; the world keeps them (the
-- volcano's smoke, the lights).
local STRIPPED_CLASSES = { "LayerCollector", "LuaSourceContainer", "Sound", "ParticleEmitter", "Trail", "Beam", "Highlight" }
local WORLD_STRIPPED_CLASSES = { "LayerCollector", "LuaSourceContainer", "Sound", "Highlight" }

-- A portrait (Head framing) only needs these parts of the rigged model.
local PORTRAIT_PARTS = { "Head", "Jaw", "Neck" }

local BUMP_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local IDLE_BOB_SPEED = 2.2
local IDLE_BOB_HEIGHT = 0.05 -- fraction of the dragon's height

local function findDragon(dragonId)
	local islands = Workspace:FindFirstChild("Islands")
	local island = islands and islands:FindFirstChild(tostring(Players.LocalPlayer.UserId))
	if not island then
		return nil
	end
	for _, instance in ipairs(island:GetDescendants()) do
		if instance:GetAttribute("DragonId") == dragonId then
			return instance
		end
	end
	return nil
end

-- world: the clone goes to the Workspace (keeps its effects, every part
-- anchored and out of the way of clicks and collisions).
local function cloneVisual(source, world)
	local clone = source:Clone()
	if not clone then
		return nil
	end
	local stripped = world and WORLD_STRIPPED_CLASSES or STRIPPED_CLASSES
	for _, descendant in ipairs(clone:GetDescendants()) do
		for _, className in ipairs(stripped) do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end
	if world then
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		if clone:IsA("BasePart") then
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanQuery = false
			clone.CanTouch = false
		end
	end
	-- The world renders a Ball at its smallest dimension, but a ViewportFrame
	-- stretches it to the full Size - make it a real sphere.
	if clone:IsA("Part") and clone.Shape == Enum.PartType.Ball then
		clone.Size = Vector3.one * math.min(clone.Size.X, clone.Size.Y, clone.Size.Z)
	end
	return clone
end

-- Moves a part and every part under it by `offset` (none are welded).
local function translateTree(root, offset)
	root.CFrame += offset
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame += offset
		end
	end
end

-- The head end of a rigged model, still (a portrait): the other parts - most
-- of its triangles - would be cloned and drawn only to fall outside the frame.
local function portraitClone(template)
	local model = Instance.new("Model")
	model.Name = template.Name
	local function copy(part)
		local clone = part:Clone()
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("JointInstance") then
				descendant:Destroy()
			end
		end
		clone.Anchored = true
		clone.Parent = model
		return clone
	end
	for _, name in ipairs(PORTRAIT_PARTS) do
		local part = template:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			copy(part)
		end
	end
	if template.PrimaryPart then
		model.PrimaryPart = copy(template.PrimaryPart) -- the pivot, at the feet
	end
	return model
end

-- ViewportFrame views waiting to be built, one per frame.
local buildQueue = {}
local queueConnection = nil

local function queueBuild(build)
	table.insert(buildQueue, build)
	if queueConnection then
		return
	end
	queueConnection = RunService.Heartbeat:Connect(function()
		local nextBuild = table.remove(buildQueue, 1)
		if nextBuild then
			nextBuild()
		end
		if #buildQueue == 0 then
			queueConnection:Disconnect()
			queueConnection = nil
		end
	end)
end

local function getExtents(instance)
	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end
	return instance:GetBoundingBox()
end

-- Where the dragon stands in front of a habitat model (scaled by `scale`):
-- ahead of its center (its front faces +Z, the island camera's side), at the
-- height its dragons stand on (its Slot attachments).
local function stagePoint(habitat, scale)
	local total, count = 0, 0
	for _, child in ipairs(habitat:GetChildren()) do
		if child:IsA("Attachment") and child.Name:match("^Slot%d+$") then
			total += child.WorldPosition.Y
			count += 1
		end
	end
	local y = count > 0 and total / count or habitat.Position.Y + habitat.Size.Y / 2
	return Vector3.new(habitat.Position.X, y, habitat.Position.Z + STAGE_OFFSET_Z * scale)
end

-- Grows a habitat clone about its base's center (its effects and slots too).
local function scaleHabitat(habitat, scale)
	if scale == 1 then
		return
	end
	local holder = Instance.new("Model")
	holder.WorldPivot = habitat.CFrame
	habitat.Parent = holder
	holder:ScaleTo(scale)
	habitat.Parent = nil
	holder:Destroy()
end

-- opts: Framing ("Head" | "Body"), Stage (emoji fallback when the dragon's
-- world model can't be found), Size / Position / AnchorPoint, Yaw (degrees
-- the camera turns around the dragon's face; positive = dragon looks toward
-- screen-left). Body only: Animate (idle; a ball bobs), GroundColor,
-- ReferenceRadius (frame as if the dragon were at least this big, e.g. its
-- Adult size, so younger stages look small), Habitat (HabitatDefs key: the
-- dragon stands in front of that habitat's model, facing the camera),
-- HabitatScale (that habitat drawn this much bigger than on the island, the
-- dragon keeping its size: e.g. so it fills the view), World (render in the
-- Workspace with the lent camera instead of a ViewportFrame; `parent` is then
-- unused - for full-screen views only).
function DragonViewport.new(parent, dragonId, opts)
	local framingName = opts.Framing or "Head"
	local habitatTemplate = framingName == "Body" and opts.Habitat and habitatTemplates and habitatTemplates:FindFirstChild(opts.Habitat)
	local framing = habitatTemplate and FRAMINGS.Stage or FRAMINGS[framingName]
	local world = opts.World == true
	local origin = world and WORLD_STAGE_ORIGIN or Vector3.zero

	local container, camera, viewport
	if world then
		container = Instance.new("Folder")
		container.Name = "DragonStage"
		container.Parent = Workspace
	else
		viewport = UIKit.new("ViewportFrame", {
			Name = "DragonViewport",
			BackgroundTransparency = 1,
			Size = opts.Size or UDim2.fromScale(1, 1),
			Position = opts.Position or UDim2.new(),
			AnchorPoint = opts.AnchorPoint or Vector2.zero,
			Ambient = Color3.fromRGB(170, 170, 170),
			LightColor = Color3.fromRGB(255, 248, 235),
			Parent = parent,
		})
		if framingName == "Head" then
			UIKit.corner(viewport, UDim.new(1, 0))
		end
		camera = UIKit.new("Camera", { FieldOfView = framing.fov, Parent = viewport })
		viewport.CurrentCamera = camera
		container = viewport
	end

	local source = findDragon(dragonId)
	local subject, rig, basePivot, baseSize, halfHeight, baseCamera, cameraDistance
	local alive = true
	local lastScale = 1
	local bump = Instance.new("NumberValue")
	bump.Value = 1
	local connections = {}

	local function build()
		for _, child in ipairs(container:GetChildren()) do
			if child ~= camera and not child:IsA("UICorner") then
				child:Destroy()
			end
		end
		subject = nil
		rig = nil

		local template = source and DragonModels.Get(source:GetAttribute("Element"), source:GetAttribute("Stage"))
		local clone
		if template and framingName == "Head" then
			clone = portraitClone(template)
		elseif template then
			rig = DragonRig.new(template)
			clone = rig.model
		else
			clone = source and source.Parent and cloneVisual(source, world)
		end
		if not clone then
			if viewport then
				UIKit.portraitImage(viewport, opts.Stage or "Adult", 0.8)
			end
			return
		end
		-- Facing -Z at the origin, whatever its orientation on the island.
		clone:PivotTo(CFrame.new(origin))
		local subjectCF, subjectSize = getExtents(clone)
		halfHeight = subjectSize.Y / 2
		local stage = origin
		if habitatTemplate then
			local habitatScale = opts.HabitatScale or 1
			local habitat = cloneVisual(habitatTemplate, world)
			scaleHabitat(habitat, habitatScale)
			translateTree(habitat, origin)
			habitat.Parent = container
			stage = stagePoint(habitat, habitatScale)
		end
		if framingName == "Body" then
			-- Feet on the ground (the stage, or the ground disc), whatever the
			-- stage's size; in front of a habitat it turns to face the camera.
			local turn = habitatTemplate and CFrame.Angles(0, math.pi, 0) or CFrame.identity
			if rig then
				-- Its pivot is at its feet (unions report loose bounds).
				clone:PivotTo(CFrame.new(stage) * turn)
			else
				clone:PivotTo(CFrame.new(stage.X, stage.Y + halfHeight - (subjectCF.Position.Y - origin.Y), stage.Z) * turn)
			end
			subjectCF, subjectSize = getExtents(clone)
		end
		clone.Parent = container
		subject = clone
		basePivot = clone:GetPivot()
		baseSize = clone:IsA("BasePart") and clone.Size or nil
		lastScale = 1

		local focusCF, focusSize = subjectCF, subjectSize
		local head = clone:FindFirstChild("Head", true)
		if framingName == "Head" and head and head:IsA("BasePart") then
			focusCF, focusSize = head.CFrame, head.Size
		end

		local radius = math.max(focusSize.X, focusSize.Y, focusSize.Z) / 2
		local focus = focusCF.Position
		if framingName == "Body" then
			radius = math.max(radius, opts.ReferenceRadius or 0)
			if not habitatTemplate then
				UIKit.new("Part", {
					Name = "Ground",
					Shape = Enum.PartType.Cylinder,
					Anchored = true,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					Material = Enum.Material.SmoothPlastic,
					Color = opts.GroundColor or Color3.fromRGB(120, 200, 120),
					Size = Vector3.new(0.6, radius * 2.5, radius * 2.5),
					CFrame = CFrame.new(origin + Vector3.new(0, -0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					Parent = container,
				})
			end
			-- Aim at the full-size dragon's middle, so it stands in the lower half.
			focus = stage + Vector3.new(0, radius, 0)
		end

		local yaw = math.rad(opts.Yaw or framing.yaw)
		local direction = (subjectCF.LookVector * math.cos(yaw) + subjectCF.RightVector * math.sin(yaw) + Vector3.yAxis * framing.rise).Unit
		cameraDistance = radius / math.tan(math.rad(framing.fov / 2)) / framing.fill
		baseCamera = CFrame.lookAt(focus + direction * cameraDistance, focus)
		if world then
			CameraController.Hold(baseCamera, framing.fov)
		else
			camera.CFrame = baseCamera
			-- Light from the camera's upper side so the face isn't in shadow.
			viewport.LightDirection = (-direction + Vector3.new(0.3, -1, 0)).Unit
		end
	end

	if source then
		table.insert(connections, source:GetAttributeChangedSignal("Stage"):Connect(build))
	end
	if world then
		build()
	else
		queueBuild(function()
			if alive then
				build()
			end
		end)
	end

	if opts.Animate then
		table.insert(connections, RunService.RenderStepped:Connect(function()
			if not subject then
				return
			end
			local scale = bump.Value
			if rig and world then
				-- Idles, and hops instead of squashing.
				rig:Apply(basePivot + Vector3.new(0, (scale - 1) * halfHeight * HOP_HEIGHT, 0), rig:Pose(os.clock(), 0, 0))
				return
			end
			if rig then
				-- Still in a ViewportFrame (see the header): only the camera moves.
				if scale ~= lastScale then
					lastScale = scale
					camera.CFrame = baseCamera * CFrame.new(0, 0, -(scale - 1) * JOLT * cameraDistance)
				end
				return
			end
			if scale ~= lastScale then
				lastScale = scale
				if baseSize then
					subject.Size = baseSize * scale
				else
					subject:ScaleTo(scale)
				end
			end
			local bob = (math.sin(os.clock() * IDLE_BOB_SPEED) + 1) / 2 * halfHeight * 2 * IDLE_BOB_HEIGHT
			-- Keeps the feet on the ground while bump-scaling.
			subject:PivotTo(basePivot + Vector3.new(0, (scale - 1) * halfHeight + bob, 0))
		end))
	end

	local api = { Instance = container }

	-- Reaction, e.g. after eating (Animate views only): a hop in World mode, a
	-- camera jolt for a rigged dragon in a ViewportFrame, a squash for a ball.
	function api.Bump()
		bump.Value = 1.3
		TweenService:Create(bump, BUMP_TWEEN, { Value = 1 }):Play()
	end

	function api.Destroy()
		alive = false
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		bump:Destroy()
		container:Destroy()
		if world then
			CameraController.Release()
		end
	end

	return api
end

return DragonViewport
