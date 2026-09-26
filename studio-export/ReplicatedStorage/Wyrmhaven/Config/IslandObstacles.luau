-- Where obstacles stand on every player's island: the ring of tiles around
-- the 15x15 starting area, with a dense tree line along the back edge. Built
-- from a fixed seed, so every island and every session get the same layout.
-- Ids are "<Kind>_<gridX>_<gridZ>" and are what saves remember as cleared -
-- changing the seed or the counts reshuffles every player's obstacles.
local GameConstants = require(script.Parent.GameConstants)
local ObstacleDefs = require(script.Parent.ObstacleDefs)

local SIDE = GameConstants.GridTilesPerSide
-- Always free: the whole island before it grew to 30x30 (old saves' buildings
-- are shifted into it, see SaveService).
local START_MIN, START_MAX = 7, 21
local SEED = 20260917

local taken = {}
local obstacles = {}
local random = Random.new(SEED)

local function fits(gridX, gridZ, tiles)
	if gridX < 0 or gridZ < 0 or gridX + tiles > SIDE or gridZ + tiles > SIDE then
		return false
	end
	for x = gridX, gridX + tiles - 1 do
		for z = gridZ, gridZ + tiles - 1 do
			if taken[x .. "," .. z] or (x >= START_MIN and x <= START_MAX and z >= START_MIN and z <= START_MAX) then
				return false
			end
		end
	end
	return true
end

-- Tries random spots until `count` obstacles of `kind` are placed.
-- maxZ limits how far from the back edge they may go.
local function scatter(kind, count, attempts, maxZ)
	local tiles = ObstacleDefs[kind].Tiles
	local placed = 0
	for _ = 1, attempts do
		if placed >= count then
			break
		end
		local gridX = random:NextInteger(0, SIDE - tiles)
		local gridZ = random:NextInteger(0, math.min(maxZ or SIDE, SIDE) - tiles)
		if fits(gridX, gridZ, tiles) then
			for x = gridX, gridX + tiles - 1 do
				for z = gridZ, gridZ + tiles - 1 do
					taken[x .. "," .. z] = true
				end
			end
			table.insert(obstacles, { Id = string.format("%s_%d_%d", kind, gridX, gridZ), Kind = kind, GridX = gridX, GridZ = gridZ })
			placed += 1
		end
	end
end

-- Biggest first, so they still find room.
scatter("BigRock", 8, 600)
scatter("Tree", 24, 1000, START_MIN)
scatter("Tree", 44, 3000)
scatter("Rock", 50, 4000)

return obstacles
