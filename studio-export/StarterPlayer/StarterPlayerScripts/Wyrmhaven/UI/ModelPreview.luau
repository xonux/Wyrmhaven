-- 3D preview of a template (a Part or a Model) in a ViewportFrame, framed to
-- fit: slowly turning, or still from a chosen side. For things that don't
-- exist on the island yet, like Shop products - DragonViewport shows the
-- player's own dragons instead.
local RunService = game:GetService("RunService")

local UIKit = require(script.Parent.UIKit)

local ModelPreview = {}

local FOV = 35
local FILL = 0.7 -- share of the frame height the object covers
local RISE = 0.5 -- camera height relative to its distance (looks slightly down)
local SPIN_SPEED = 0.6 -- radians per second

-- The template is cloned; the caller keeps (and destroys) the original.
-- opts (optional): Spin (default true: the camera circles the object; false
-- = a still view), Yaw (degrees around the object from its +Z side where the
-- camera starts or stays, e.g. 90 = its +X side: a dragon's profile, head to
-- the right), Rise (camera height per unit of distance), Fill (share of the
-- frame the object's bounds cover; unions report loose bounds, so a rigged
-- dragon can take more).
function ModelPreview.new(parent, template, opts)
	opts = opts or {}
	local spin = opts.Spin ~= false
	local yaw = math.rad(opts.Yaw or 0)
	local rise = opts.Rise or RISE
	local fill = opts.Fill or FILL
	local viewport = UIKit.new("ViewportFrame", {
		Name = "ModelPreview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.fromRGB(255, 248, 235),
		LightDirection = Vector3.new(0.3, -1, -0.8),
		Parent = parent,
	})
	local camera = UIKit.new("Camera", { FieldOfView = FOV, Parent = viewport })
	viewport.CurrentCamera = camera

	local model = Instance.new("Model")
	local subject = template:Clone()
	-- The world renders a Ball at its smallest dimension, a ViewportFrame at its full Size.
	if subject:IsA("Part") and subject.Shape == Enum.PartType.Ball then
		subject.Size = Vector3.one * math.min(subject.Size.X, subject.Size.Y, subject.Size.Z)
	end
	if subject:IsA("BasePart") then
		subject.Anchored = true
	end
	subject.Parent = model

	-- Spin around the object's middle, placed at the origin. The pivot is set
	-- to the world axes first: by default it takes the orientation of one of the
	-- model's parts, and a tilted part (e.g. a union) tilted the whole preview.
	model.WorldPivot = CFrame.new()
	local boxCFrame, size = model:GetBoundingBox()
	local center = boxCFrame.Position
	-- Unions report loose bounds; a PreviewSize attribute on a model's base
	-- part (its footprint and height from the ground) frames it exactly.
	local previewSize = subject:GetAttribute("PreviewSize")
	if typeof(previewSize) == "Vector3" and subject:IsA("BasePart") then
		size = previewSize
		center = subject.Position + Vector3.new(0, previewSize.Y / 2 - subject.Size.Y / 2, 0)
	end
	model:PivotTo(CFrame.new(-center))
	model.Parent = viewport

	-- Radius: turning, its horizontal diagonal or its height; still, only the
	-- width it shows the camera, or its height.
	local radius
	if spin then
		radius = math.max(Vector2.new(size.X, size.Z).Magnitude, size.Y) / 2
	else
		local width = math.abs(size.X * math.cos(yaw)) + math.abs(size.Z * math.sin(yaw))
		radius = math.max(width, size.Y) / 2
	end
	local distance = radius / math.tan(math.rad(FOV / 2)) / fill
	local direction = (CFrame.Angles(0, yaw, 0) * Vector3.new(0, rise, 1)).Unit
	local cameraStart = CFrame.lookAt(direction * distance, Vector3.zero)
	camera.CFrame = cameraStart

	-- The camera circles the object: much cheaper than moving every part of a
	-- detailed model each frame. A still view is lit from the camera's side.
	local connection = nil
	if spin then
		local angle = 0
		connection = RunService.RenderStepped:Connect(function(deltaTime)
			angle += deltaTime * SPIN_SPEED
			camera.CFrame = CFrame.Angles(0, -angle, 0) * cameraStart
		end)
	else
		viewport.LightDirection = (-direction + Vector3.new(0.3, -1, 0)).Unit
	end

	local api = { Instance = viewport }

	function api.Destroy()
		if connection then
			connection:Disconnect()
		end
		viewport:Destroy()
	end

	return api
end

return ModelPreview
