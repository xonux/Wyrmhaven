-- Bouncing low-poly 3D arrows pointing down at parts of the island (e.g. the
-- habitats a hatchling can move into). Client-only, never tappable. The arrow
-- tip hovers above the part's TitleHeight when it has one (habitat models),
-- otherwise above its top.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldArrow = {}

local COLOR = Color3.fromRGB(255, 206, 72)
local SHADE = Color3.fromRGB(226, 160, 40)
local HEAD_WIDTH = 3.2
local HEAD_HEIGHT = 2.4
local SHAFT_WIDTH = 1.2
local SHAFT_HEIGHT = 2.6
local CLEARANCE = 1.5 -- studs between the part's top and the lowest point of the tip
local BOB_STUDS = 0.8
local BOB_SPEED = 3
local SPIN_SPEED = 1.2

local folder = nil
local connection = nil
local arrows = {} -- { model, target, phase }

local function prep(part, color, parent)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Parent = parent
	return part
end

-- Flat triangle a-b-c made of two wedges.
local function triangle(parent, a, b, c, color, thickness)
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
	for _, spec in ipairs({
		{ (a + b) / 2, right, back, math.abs(ab:Dot(back)) },
		{ (a + c) / 2, -right, -back, math.abs(ac:Dot(back)) },
	}) do
		local wedge = Instance.new("WedgePart")
		wedge.Size = Vector3.new(thickness, height, spec[4])
		wedge.CFrame = CFrame.fromMatrix(spec[1], spec[2], up, spec[3])
		prep(wedge, color, parent)
	end
end

-- Square pyramid pointing down with a shaft on top; the tip is the pivot.
local function buildArrow(parent)
	local model = Instance.new("Model")
	model.Name = "Arrow"
	local tip = Vector3.zero
	local h = HEAD_WIDTH / 2
	local corners = {
		Vector3.new(-h, HEAD_HEIGHT, -h),
		Vector3.new(h, HEAD_HEIGHT, -h),
		Vector3.new(h, HEAD_HEIGHT, h),
		Vector3.new(-h, HEAD_HEIGHT, h),
	}
	for i = 1, 4 do
		triangle(model, tip, corners[i], corners[i % 4 + 1], i % 2 == 0 and COLOR or SHADE, 0.1)
	end
	local cap = Instance.new("Part")
	cap.Size = Vector3.new(HEAD_WIDTH, 0.1, HEAD_WIDTH)
	cap.CFrame = CFrame.new(0, HEAD_HEIGHT, 0)
	prep(cap, SHADE, model)
	local shaft = Instance.new("Part")
	shaft.Size = Vector3.new(SHAFT_WIDTH, SHAFT_HEIGHT, SHAFT_WIDTH)
	shaft.CFrame = CFrame.new(0, HEAD_HEIGHT + SHAFT_HEIGHT / 2, 0)
	prep(shaft, COLOR, model)
	model.WorldPivot = CFrame.new()
	model.Parent = parent
	return model
end

local function update()
	local t = os.clock()
	for _, arrow in ipairs(arrows) do
		local target = arrow.target
		if target.Parent then
			local top = target.Position.Y + (target:GetAttribute("TitleHeight") or target.Size.Y / 2)
			local y = top + CLEARANCE + (math.sin(t * BOB_SPEED + arrow.phase) + 1) * BOB_STUDS
			arrow.model:PivotTo(CFrame.new(target.Position.X, y, target.Position.Z) * CFrame.Angles(0, t * SPIN_SPEED + arrow.phase, 0))
		end
	end
end

-- One arrow over each part in `targets` (replaces the arrows shown).
function WorldArrow.Show(targets)
	WorldArrow.Clear()
	folder = Instance.new("Folder")
	folder.Name = "WorldArrows"
	for index, target in ipairs(targets) do
		table.insert(arrows, { model = buildArrow(folder), target = target, phase = index * 0.9 })
	end
	update()
	folder.Parent = Workspace
	connection = RunService.RenderStepped:Connect(update)
end

function WorldArrow.Clear()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	arrows = {}
end

return WorldArrow
