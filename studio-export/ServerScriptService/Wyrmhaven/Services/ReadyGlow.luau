-- Golden sparkles over something whose timer is over and that only waits for
-- the player's final tap (a finished construction, a cleared obstacle, a
-- grown crop).
-- The attachment and its emitter are both named ReadyGlow (PlacementController
-- keeps that emitter on while hiding a habitat's other effects).
local ReadyGlow = {}

local NAME = "ReadyGlow"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- part: where the sparkles go; offset: studs above the part's center, or a
-- Vector3 offset from it.
function ReadyGlow.Set(part, on, offset)
	local existing = part:FindFirstChild(NAME)
	if not on then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = NAME
	attachment.Position = typeof(offset) == "Vector3" and offset or Vector3.new(0, offset or 3, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = NAME
	emitter.Texture = SPARKLE
	emitter.Rate = 5
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1.5, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -1.5, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 236, 150), Color3.fromRGB(255, 196, 70))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = attachment
	attachment.Parent = part
end

return ReadyGlow
