-- Stand-ins for the Roblox API pieces IslandService touches, so its scenery
-- and obstacle builders run under standalone Luau. Every Part created is
-- recorded in PARTS (nothing is drawn).
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
function V3:Lerp(o, t) return self + (o - self) * t end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end }

-- CFrame: position p + row-major rotation m (world = p + m * local)
local CF = {}
local function mm(a, b)
	local r = {}
	for i = 0, 2 do for j = 0, 2 do
		r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
	end end
	return r
end
local function mv(m, v)
	return Vector3.new(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z)
end
local function cf(p, m) return setmetatable({ p = p, m = m }, CF) end
CF.__index = function(c, k)
	if k == "Position" then return c.p end
	return CF[k]
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then return cf(a.p + mv(a.m, b.p), mm(a.m, b.m)) end
	return a.p + mv(a.m, b)
end
local I = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
CFrame = {
	new = function(x, y, z)
		if type(x) == "number" then return cf(Vector3.new(x, y, z), I) end
		return cf(x or Vector3.new(), I)
	end,
	Angles = function(rx, ry, rz)
		local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
		local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
		local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
		local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
		return cf(Vector3.new(), mm(mm(X, Y), Z))
	end,
}

local C3 = {}
C3.__index = C3
function C3:Lerp(o, t) return Color3.new(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t) end
Color3 = {
	new = function(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3) end,
	fromRGB = function(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, C3) end,
}

Enum = setmetatable({}, { __index = function(_, a)
	return setmetatable({}, { __index = function(_, b) return a .. "." .. b end })
end })
TweenInfo = { new = function() return {} end }

local function mkRandom(seed)
	local s = (seed or 1) % 2147483647
	if s <= 0 then s += 2147483646 end
	local r = {}
	function r:NextNumber(a, b)
		s = (s * 16807) % 2147483647
		local x = s / 2147483647
		if a then return a + (b - a) * x end
		return x
	end
	function r:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end
	return r
end
Random = { new = mkRandom }

PARTS = {}
local INST = {}
INST.__index = function(o, k)
	local v = rawget(o, "_props")[k]
	if v ~= nil then return v end
	return INST[k]
end
INST.__newindex = function(o, k, v)
	if k == "Parent" then
		local old = rawget(o, "_props").Parent
		if old then old._children[o] = nil end
		if v then rawget(v, "_children")[o] = true end
	end
	rawget(o, "_props")[k] = v
end
function INST:SetAttribute() end
function INST:GetAttribute() return nil end
function INST:FindFirstChild() return nil end
function INST:GetDescendants()
	local out = {}
	local function walk(n)
		for c in pairs(rawget(n, "_children")) do table.insert(out, c); walk(c) end
	end
	walk(self)
	return out
end
function INST:IsA(cls) return cls == "BasePart" and (self.ClassName == "Part" or self.ClassName == "WedgePart") or cls == self.ClassName end
Instance = { new = function(cls)
	local o = setmetatable({ _props = { ClassName = cls, Transparency = 0 }, _children = {} }, INST)
	if cls == "Part" or cls == "WedgePart" then table.insert(PARTS, o) end
	return o
end }
