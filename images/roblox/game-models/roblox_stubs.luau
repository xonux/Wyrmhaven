-- Minimal Vector3 / CFrame / Color3 for running DragonBuilder outside Roblox
-- (geometry only: nothing here builds Instances).
local V3 = {}
V3.__index = function(v, k)
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); return Vector3.new(v.X / m, v.Y / m, v.Z / m) end
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	return V3[k]
end
V3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
function V3:Dot(o) return self.X * o.X + self.Y * o.Y + self.Z * o.Z end
function V3:Cross(o) return Vector3.new(self.Y * o.Z - self.Z * o.Y, self.Z * o.X - self.X * o.Z, self.X * o.Y - self.Y * o.X) end
function V3:Lerp(o, t) return self + (o - self) * t end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end }
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.xAxis, Vector3.yAxis, Vector3.zAxis = Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)

local CF = {}
CF.__index = CF
CF.__mul = function(cf, v)
	if getmetatable(v) == V3 then
		return cf.p + cf.x * v.X + cf.y * v.Y + cf.z * v.Z
	end
	error("CFrame * CFrame not needed")
end
CFrame = {
	fromMatrix = function(p, x, y, z) z = z or x:Cross(y); return setmetatable({ p = p, x = x, y = y, z = z }, CF) end,
	new = function(x, y, z)
		local p = type(x) == "number" and Vector3.new(x, y, z) or x
		return setmetatable({ p = p, x = Vector3.xAxis, y = Vector3.yAxis, z = Vector3.zAxis }, CF)
	end,
}

local C3 = {}
C3.__index = C3
function C3:Lerp(o, t) return setmetatable({ R = self.R + (o.R - self.R) * t, G = self.G + (o.G - self.G) * t, B = self.B + (o.B - self.B) * t }, C3) end
Color3 = { fromRGB = function(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, C3) end }
Enum = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return 0 end }) end })
