-- Builds the scenery and every obstacle the way IslandService does on a
-- fresh island (base at the origin), then prints each visible part:
-- "p <shape> sx sy sz px py pz m1..m9 r g b"
local IslandService = require(node("ServerScriptService/Wyrmhaven/Services/IslandService"))
local IslandObstacles = require(node("ReplicatedStorage/Wyrmhaven/Config/IslandObstacles"))
local ObstacleDefs = require(node("ReplicatedStorage/Wyrmhaven/Config/ObstacleDefs"))
local GameConstants = require(node("ReplicatedStorage/Wyrmhaven/Config/GameConstants"))

local TILE = GameConstants.GridTileSize
local HALF = TILE * GameConstants.GridTilesPerSide / 2
-- the grass plate itself (HabitatService.getOrCreateIsland)
local base = Instance.new("Part")
base.Size = Vector3.new(HALF * 2, 2, HALF * 2)
base.CFrame = CFrame.new(0, 2, 0)
base.Position = Vector3.new(0, 2, 0)
base.Color = Color3.fromRGB(126, 196, 86)
local island = Instance.new("Folder")
IslandService._buildScenery(island, base)
local folder = Instance.new("Folder")
for _, obstacle in ipairs(IslandObstacles) do
	local tiles = ObstacleDefs[obstacle.Kind].Tiles
	local center = Vector3.new(-HALF + obstacle.GridX * TILE + tiles * TILE / 2, 3, -HALF + obstacle.GridZ * TILE + tiles * TILE / 2)
	IslandService._buildObstacle(folder, obstacle, center)
end
for _, p in ipairs(PARTS) do
	if (p.Transparency or 0) < 1 and p.Size and p.CFrame then
		local s, c, m, col = p.Size, p.CFrame.p, p.CFrame.m, p.Color
		print(string.format("p %s %.3f %.3f %.3f %.3f %.3f %.3f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.3f %.3f %.3f",
			tostring(p.Shape or "PartType.Block"), s.X, s.Y, s.Z, c.X, c.Y, c.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], col.R, col.G, col.B))
	end
end
