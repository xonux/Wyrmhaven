-- Wooden scaffold around a building under construction (a habitat or a farm
-- bought in the Shop). Its beams carry the building's id attribute, so a tap
-- on the scaffold opens the building too.
local Scaffold = {}

local NAME = "Scaffold"
local WOOD = Color3.fromRGB(162, 118, 74)
local WOOD_DARK = Color3.fromRGB(128, 90, 56)
local HEIGHT = 6
local ID_ATTRIBUTES = { "HabitatId", "FarmId" }

-- platform: the building's base part, whose footprint the scaffold surrounds.
function Scaffold.Set(platform, on)
	local scaffold = platform:FindFirstChild(NAME)
	if not on then
		if scaffold then
			scaffold:Destroy()
		end
		return
	end
	if scaffold then
		return
	end
	scaffold = Instance.new("Model")
	scaffold.Name = NAME
	local ground = CFrame.new(platform.Position - Vector3.new(0, platform.Size.Y / 2, 0))
	local half = platform.Size.X / 2 - 1
	local function beam(size, offset, color)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = size
		part.CFrame = ground * offset
		part.Color = color
		for _, attribute in ipairs(ID_ATTRIBUTES) do
			part:SetAttribute(attribute, platform:GetAttribute(attribute))
		end
		part.Parent = scaffold
	end
	for _, corner in ipairs({ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) }) do
		beam(Vector3.new(0.5, HEIGHT, 0.5), CFrame.new(corner.X * half, HEIGHT / 2, corner.Y * half), WOOD_DARK)
	end
	local span = half * 2 + 0.5
	for _, y in ipairs({ HEIGHT * 0.45, HEIGHT - 0.2 }) do
		beam(Vector3.new(span, 0.35, 0.35), CFrame.new(0, y, -half), WOOD)
		beam(Vector3.new(span, 0.35, 0.35), CFrame.new(0, y, half), WOOD)
		beam(Vector3.new(0.35, 0.35, span), CFrame.new(-half, y, 0), WOOD)
		beam(Vector3.new(0.35, 0.35, span), CFrame.new(half, y, 0), WOOD)
	end
	-- Diagonal braces on the left and right sides
	local rise = HEIGHT * 0.45
	local braceLength = math.sqrt((half * 2) ^ 2 + rise ^ 2)
	local braceAngle = math.atan2(rise, half * 2)
	for _, x in ipairs({ -half, half }) do
		beam(Vector3.new(0.3, 0.3, braceLength), CFrame.new(x, rise / 2, 0) * CFrame.Angles(braceAngle, 0, 0), WOOD_DARK)
	end
	scaffold.Parent = platform
end

return Scaffold
