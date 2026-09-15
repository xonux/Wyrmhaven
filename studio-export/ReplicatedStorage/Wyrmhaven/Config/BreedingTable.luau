-- [elementA][elementB] -> resulting element. Filled in both directions so
-- BreedingService can do a single lookup without worrying about argument
-- order. Same-element pairs (Fire+Fire, etc.) aren't listed here on purpose -
-- BreedingService falls back to "same element" when a lookup is missing and
-- elemA == elemB, per docs/design/phase2-breeding.md.
local pairs_ = {
	{"Fire", "Water", "Water"},
	{"Fire", "Nature", "Fire"},
	{"Fire", "Lightning", "Lightning"},
	{"Fire", "Earth", "Earth"},
	{"Water", "Nature", "Nature"},
	{"Water", "Lightning", "Water"},
	{"Water", "Earth", "Earth"},
	{"Nature", "Lightning", "Nature"},
	{"Nature", "Earth", "Nature"},
	{"Lightning", "Earth", "Earth"},
}

local BreedingTable = {}
for _, entry in ipairs(pairs_) do
	local elementA, elementB, result = entry[1], entry[2], entry[3]
	BreedingTable[elementA] = BreedingTable[elementA] or {}
	BreedingTable[elementA][elementB] = result
	BreedingTable[elementB] = BreedingTable[elementB] or {}
	BreedingTable[elementB][elementA] = result
end

return BreedingTable
