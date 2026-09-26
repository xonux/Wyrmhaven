local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = ReplicatedStorage.Wyrmhaven.Config
local DragonDefs = require(Config.DragonDefs)
local DragonModels = require(Config.DragonModels)
local DragonLevels = require(Config.DragonLevels)
local DragonRules = require(Config.DragonRules)
local SkillRules = require(Config.SkillRules)
local GameConstants = require(Config.GameConstants)

-- Every dragon/egg part carries it; the client's DragonVisualController
-- draws the rigged model of those that have one.
local DRAGON_TAG = "Dragon"

local DragonService = {}

local HabitatService
local EconomyService
local FarmService

local dragons = {} -- [dragonId] = record
local nextDragonId = 1

local dragonStatusUpdated

local MAX_NICKNAME_LENGTH = 20 -- DragonScreen (client) caps typing at the same length
local RENAME_COOLDOWN_SECONDS = 2 -- TextService filtering is rate limited

-- No BillboardGui here on purpose (Phase 3 UI rework): a dragon's status is
-- shown in the click-driven UI (HabitatBar / DragonScreen / IncubatorController)
-- instead of a floating label per dragon, which used to clutter the screen
-- once a player had several habitats.
local function refreshVisual(record)
	local def = DragonDefs[record.element]
	local size = def.StageSizes[record.stage]
	record.part.Name = string.format("%s (%s)", def.DisplayName, record.stage)
	record.part.Size = size
	record.part.Color = def.StageColors[record.stage]
	-- A breeding dragon stands at the Nursery's tree, not in its habitat slot.
	local base = record.breedingSpot or record.slotTopCFrame
	record.part.CFrame = base + Vector3.new(0, size.Y / 2, 0)
	-- A stage with a rigged model (Config.DragonModels) is drawn and animated
	-- client-side around this part (DragonVisualController), which then only
	-- anchors it: invisible and out of raycasts. Eggs and elements without a
	-- model keep the ball.
	local modeled = DragonModels.Get(record.element, record.stage) ~= nil
	record.part.Transparency = modeled and 1 or 0
	record.part.CanQuery = not modeled
	record.part.CastShadow = not modeled
	record.part:SetAttribute("Element", record.element)
	-- Read by the client to pick the model (and rebuild it on hatching or
	-- growing up).
	record.part:SetAttribute("Stage", record.stage)
end

-- A dragon's level drives its stage: Baby below DragonLevels.AdultLevel,
-- Adult from there on (see setLevel / Feed).
local function setLevel(record, level)
	record.level = DragonLevels.Clamp(level)
	record.stage = DragonLevels.StageForLevel(record.level)
end

-- The level a saved dragon comes back at. Saves written before dragons had
-- levels (2026-09-20) hold `growth` points and a stage instead: an Adult was
-- fully grown, so it comes back at AdultLevel, and a Baby keeps one level per
-- feeding it had had (25 growth each), just short of Adult.
local function savedLevel(state)
	if not state then
		return 1
	end
	if state.level then
		return DragonLevels.Clamp(state.level)
	end
	if state.stage == "Adult" then
		return DragonLevels.AdultLevel
	end
	local feeds = math.floor((state.growth or 0) / 25)
	return math.clamp(1 + feeds, 1, DragonLevels.AdultLevel - 1)
end

function DragonService.Init(habitatServiceRef, economyServiceRef, farmServiceRef)
	HabitatService = habitatServiceRef
	EconomyService = economyServiceRef
	FarmService = farmServiceRef
end

function DragonService.InitRemotes(remotesFolder)
	dragonStatusUpdated = remotesFolder:FindFirstChild("DragonStatusUpdated")
	if not dragonStatusUpdated then
		dragonStatusUpdated = Instance.new("RemoteEvent")
		dragonStatusUpdated.Name = "DragonStatusUpdated"
		dragonStatusUpdated.Parent = remotesFolder
	end
end

function DragonService.SpawnDragon(player, habitatRecord, slotIndex, element, initialState)
	local def = DragonDefs[element]
	assert(def, "Unknown dragon element: " .. tostring(element))

	local dragonId = nextDragonId
	nextDragonId += 1

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = habitatRecord.model
	part:SetAttribute("DragonId", dragonId)
	part:SetAttribute("HabitatId", habitatRecord.id)

	local record = {
		id = dragonId,
		ownerUserId = player.UserId,
		element = element,
		-- Habitats only ever receive hatched (Baby+) dragons - see
		-- SpawnEgg/MoveToHabitat. The stage follows the level (setLevel below).
		stage = "Baby",
		level = 1,
		nickname = initialState and initialState.nickname,
		isBreeding = false,
		part = part,
		location = "Habitat",
		habitatRecord = habitatRecord,
		habitatId = habitatRecord.id,
		slotIndex = slotIndex,
		slotTopCFrame = HabitatService.GetSlotCFrame(habitatRecord, slotIndex),
	}
	setLevel(record, savedLevel(initialState))
	dragons[dragonId] = record
	HabitatService.OccupySlot(habitatRecord, slotIndex, dragonId)
	-- Saves from before habitats stored the Coins: what the dragon held goes
	-- into its habitat.
	if initialState and initialState.pendingIncome then
		HabitatService.StoreCoins(habitatRecord, initialState.pendingIncome)
	end

	refreshVisual(record)
	CollectionService:AddTag(part, DRAGON_TAG)

	return record
end

-- Spawns an egg into an Incubator slot (see IncubatorService) instead of a
-- Habitat - it grows/hatches on a timer there, not by feeding, and only
-- moves into a Habitat afterwards via MoveToHabitat.
function DragonService.SpawnEgg(player, incubatorRecord, slotIndex, element)
	local def = DragonDefs[element]
	assert(def, "Unknown dragon element: " .. tostring(element))

	local dragonId = nextDragonId
	nextDragonId += 1

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = incubatorRecord.part
	part:SetAttribute("DragonId", dragonId)
	part:SetAttribute("IncubatorId", player.UserId)

	local record = {
		id = dragonId,
		ownerUserId = player.UserId,
		element = element,
		stage = "Egg", -- no level yet: it hatches into a level 1 Baby (SetHatched)
		level = 1,
		isBreeding = false,
		part = part,
		location = "Incubator",
		incubatorRecord = incubatorRecord,
		incubatorSlot = slotIndex,
		slotTopCFrame = incubatorRecord.slotCFrames[slotIndex],
	}
	dragons[dragonId] = record

	refreshVisual(record)
	CollectionService:AddTag(part, DRAGON_TAG)

	return record
end

-- Re-seats every dragon/egg standing on a building that just moved
-- (HabitatService.MoveHabitat / IncubatorService.MoveIncubator): its record
-- already carries the new slot CFrames.
function DragonService.RefreshSlotPositions(structureRecord)
	for _, record in pairs(dragons) do
		if record.habitatRecord == structureRecord then
			record.slotTopCFrame = HabitatService.GetSlotCFrame(structureRecord, record.slotIndex)
			refreshVisual(record)
		elseif record.incubatorRecord == structureRecord then
			record.slotTopCFrame = structureRecord.slotCFrames[record.incubatorSlot]
			refreshVisual(record)
		end
	end
end

-- Flips an incubating egg to Baby once its hatch timer elapses (called by
-- IncubatorService) - it still physically sits in the Incubator slot until
-- the player moves it into a Habitat.
function DragonService.SetHatched(dragonId)
	local record = dragons[dragonId]
	if not record then return end
	setLevel(record, 1)
	refreshVisual(record)
end

-- Moves a hatched (Baby) dragon out of its Incubator slot and into a free
-- Habitat slot. Returns false without side effects if the dragon isn't a
-- hatched egg owned by this player (IncubatorService.PlaceInHabitat is the
-- only caller and re-validates the habitat slot is actually free).
function DragonService.MoveToHabitat(player, dragonId, habitatRecord, slotIndex)
	local record = dragons[dragonId]
	if not record then return false end
	if record.ownerUserId ~= player.UserId then return false end
	if record.location ~= "Incubator" then return false end
	if record.stage ~= "Baby" then return false end -- not hatched yet

	record.part.Parent = habitatRecord.model
	record.part:SetAttribute("IncubatorId", nil)
	record.part:SetAttribute("HabitatId", habitatRecord.id)

	record.location = "Habitat"
	record.habitatRecord = habitatRecord
	record.habitatId = habitatRecord.id
	record.slotIndex = slotIndex
	record.incubatorRecord = nil
	record.incubatorSlot = nil
	record.slotTopCFrame = HabitatService.GetSlotCFrame(habitatRecord, slotIndex)

	HabitatService.OccupySlot(habitatRecord, slotIndex, dragonId)
	refreshVisual(record)
	return true
end

-- Moves a dragon from its habitat into a free slot of another habitat it can
-- live in (DragonRules.Elements: a hybrid, either of its two elements -
-- DragonScreen's Move). Returns true, or false plus a reason:
-- "Breeding" (it's at the Nursery, whose pairing points at it), "NoRoom"
-- (full, wrong element or still being built), "NotFound".
function DragonService.MoveToOtherHabitat(player, dragonId, habitatId)
	local record = dragons[dragonId]
	if not record or record.ownerUserId ~= player.UserId or record.location ~= "Habitat" then return false, "NotFound" end
	if record.isBreeding then return false, "Breeding" end
	if record.habitatId == habitatId then return false, "NoRoom" end
	local habitatRecord, slotIndex = HabitatService.FindFreeSlotInHabitat(player, habitatId, DragonRules.Elements(record.element))
	if not habitatRecord then return false, "NoRoom" end

	HabitatService.FreeSlot(record.habitatRecord, record.slotIndex)
	record.part.Parent = habitatRecord.model
	record.part:SetAttribute("HabitatId", habitatRecord.id)
	record.habitatRecord = habitatRecord
	record.habitatId = habitatRecord.id
	record.slotIndex = slotIndex
	record.slotTopCFrame = HabitatService.GetSlotCFrame(habitatRecord, slotIndex)
	HabitatService.OccupySlot(habitatRecord, slotIndex, dragonId)
	refreshVisual(record)
	return true
end

-- Sells a dragon living in a habitat (DragonScreen's Sell) for its
-- rarity's price (DragonRules.SellPrice); its slot frees up. Returns true,
-- coins, habitatId - or false, reason ("NotFound", "Breeding", "NotForSale").
function DragonService.Sell(player, dragonId)
	local record = dragons[dragonId]
	if not record or record.ownerUserId ~= player.UserId or record.location ~= "Habitat" then return false, "NotFound" end
	if record.isBreeding then return false, "Breeding" end
	local price = DragonRules.SellPrice(record.element)
	if not price then return false, "NotForSale" end

	HabitatService.FreeSlot(record.habitatRecord, record.slotIndex)
	dragons[dragonId] = nil
	record.part:Destroy()
	EconomyService.AddCoins(player, price)
	return true, price, record.habitatId
end

-- Drops a hatchling still waiting in the Incubator (IncubatorService, which
-- frees its nest and pays for it). True if it was there.
function DragonService.RemoveHatchling(player, dragonId)
	local record = dragons[dragonId]
	if not record or record.ownerUserId ~= player.UserId or record.location ~= "Incubator" then return false end
	dragons[dragonId] = nil
	record.part:Destroy()
	return true
end

-- One feeding = one level, for the Food that level costs
-- (DragonLevels.FoodToNextLevel). Returns true, or false plus a reason the
-- Dragon screen can explain ("NotEnoughFood", "MaxLevel"); the others are
-- states its button already disables.
function DragonService.Feed(player, dragonId)
	local record = dragons[dragonId]
	if not record then return false, "NotFound" end
	if record.ownerUserId ~= player.UserId then return false, "NotFound" end
	if record.location ~= "Habitat" then return false, "NotInHabitat" end -- eggs/unplaced hatchlings live in the Incubator and hatch on a timer, not by feeding
	if record.isBreeding then return false, "Breeding" end
	local cost = DragonLevels.FoodToNextLevel(record.level)
	if not cost then return false, "MaxLevel" end
	if not FarmService.TrySpendFood(player, cost) then return false, "NotEnoughFood" end

	local wasStage = record.stage
	setLevel(record, record.level + 1)
	refreshVisual(record)
	-- True as the second value when this feeding grew it into an Adult.
	return true, wasStage ~= "Adult" and record.stage == "Adult"
end

-- Save-relevant snapshot of every Habitat-placed dragon this player owns
-- (order doesn't matter - SaveService reconstructs slots from slotIndex).
-- Incubator eggs are saved separately by IncubatorService.GetSaveState.
function DragonService.GetPlayerDragons(player)
	local result = {}
	for _, record in pairs(dragons) do
		if record.ownerUserId == player.UserId and record.location == "Habitat" then
			table.insert(result, {
				id = record.id, -- live-session id, used by BreedingService; meaningless across a save/load (ids aren't persisted as stable identity)
				habitatId = record.habitatId,
				slotIndex = record.slotIndex,
				element = record.element,
				stage = record.stage,
				level = record.level,
				nickname = record.nickname,
				isBreeding = record.isBreeding,
				breedable = DragonDefs[record.element].Breedable ~= false,
			})
		end
	end
	return result
end

-- Per-dragon detail for the Habitat bar (HabitatBar on the client), ordered
-- by slot so its portraits don't shuffle between refreshes.
function DragonService.GetHabitatDragons(player, habitatId)
	local list = {}
	for _, record in pairs(dragons) do
		if record.ownerUserId == player.UserId and record.location == "Habitat" and record.habitatId == habitatId then
			local def = DragonDefs[record.element]
			table.insert(list, {
				id = record.id,
				slotIndex = record.slotIndex,
				element = record.element,
				displayName = record.nickname or def.DisplayName,
				stage = record.stage,
				color = def.StageColors[record.stage],
				level = record.level,
				maxLevel = DragonLevels.MaxLevel,
				isBreeding = record.isBreeding,
			})
		end
	end
	table.sort(list, function(a, b) return a.slotIndex < b.slotIndex end)
	return list
end

-- Its three skills as the Dragon screen shows them: name, generated
-- description and cooldown, with the numbers this dragon's stats give
-- (SkillRules.Amounts). Empty for a species that has none yet.
local function buildSkills(record)
	local stats = DragonRules.Stats(record.element, record.level)
	local list = {}
	for _, skillId in ipairs(SkillRules.SkillsOf(record.element)) do
		local skill = SkillRules.Get(skillId)
		if skill then
			table.insert(list, {
				id = skillId,
				name = skill.DisplayName,
				class = skill.Class,
				cooldown = skill.Cooldown or 0,
				description = SkillRules.Describe(skillId),
				amounts = SkillRules.Amounts(skillId, stats),
			})
		end
	end
	return list
end

-- Dragon screen status (DragonScreen on the client). Only Habitat-placed
-- dragons have one; Incubator eggs use the Incubator panel instead.
local function buildStatus(record)
	local def = DragonDefs[record.element]
	return {
		id = record.id,
		habitatId = record.habitatId,
		element = record.element, -- its species (DragonDefs id)
		-- the habitat it lives in (DragonScreen's backdrop), and those it can
		-- move to (Move)
		habitatElement = record.habitatRecord and record.habitatRecord.element or DragonRules.Elements(record.element)[1],
		habitatElements = DragonRules.Elements(record.element),
		name = record.nickname or def.DisplayName,
		speciesName = def.DisplayName,
		rarity = DragonRules.Rarity(record.element),
		incomePerMinute = DragonRules.IncomePerMinute(record.element, record.stage), -- halved while it is a Baby
		sellPrice = DragonRules.SellPrice(record.element), -- nil: can't be sold
		stage = record.stage,
		color = def.StageColors[record.stage],
		-- Combat role, stats and skills, worked out from its class, rarity and
		-- level (see Config/DragonRules and Config/SkillRules).
		class = DragonRules.Class(record.element),
		className = DragonRules.ClassName(record.element),
		stats = DragonRules.Stats(record.element, record.level),
		skills = buildSkills(record),
		level = record.level,
		maxLevel = DragonLevels.MaxLevel,
		adultLevel = DragonLevels.AdultLevel, -- the level it turns Adult at
		feedCost = DragonLevels.FoodToNextLevel(record.level), -- nil at max level
		isBreeding = record.isBreeding,
	}
end

-- extra: optional fields merged into the push (e.g. { feedError = reason }).
local function pushStatus(player, dragonId, openRequest, extra)
	local record = dragons[dragonId]
	if not record or record.ownerUserId ~= player.UserId or record.location ~= "Habitat" then return end
	local status = buildStatus(record)
	status.openRequest = openRequest
	-- Where it could move to (DragonScreen's Move, HabitatPicker).
	status.habitats = HabitatService.GetHabitatSummaries(player)
	for key, value in pairs(extra or {}) do
		status[key] = value
	end
	dragonStatusUpdated:FireClient(player, status)
end

-- Explicit click on a dragon: forces its popup open on the client.
function DragonService.RequestInfo(player, dragonId)
	pushStatus(player, dragonId, true)
end

-- Silent refresh after an action - never reopens a popup the player closed.
function DragonService.RefreshStatus(player, dragonId, extra)
	pushStatus(player, dragonId, false, extra)
end

-- Sets (or, with a blank name, clears) a dragon's nickname. Filtered through
-- TextService like any user-typed text; refuses silently on any failure, the
-- caller's RefreshStatus then restores the current name in the popup.
function DragonService.Rename(player, dragonId, rawName)
	local record = dragons[dragonId]
	if not record or record.ownerUserId ~= player.UserId or record.location ~= "Habitat" then return false end

	local now = os.clock()
	if record.lastRenameAt and now - record.lastRenameAt < RENAME_COOLDOWN_SECONDS then return false end
	record.lastRenameAt = now

	local name = rawName:gsub("%c", ""):match("^%s*(.-)%s*$")
	local length = utf8.len(name)
	if not length or length > MAX_NICKNAME_LENGTH then return false end
	if length == 0 then
		record.nickname = nil
		return true
	end

	local ok, filtered = pcall(function()
		return TextService:FilterStringAsync(name, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		warn("[Wyrmhaven] Dragon name filtering failed: " .. tostring(filtered))
		return false
	end
	record.nickname = filtered
	return true
end

-- Ownership-checked habitatId lookup so RequestFeedDragon's handler can
-- refresh the right panel without trusting a client-supplied habitatId.
function DragonService.GetDragonHabitatId(player, dragonId)
	local record = dragons[dragonId]
	if not record or record.ownerUserId ~= player.UserId then return nil end
	return record.habitatId
end

-- Read-only snapshot for other services (e.g. BreedingService) to validate
-- against without reaching into the internal `dragons` table directly.
function DragonService.GetDragonInfo(dragonId)
	local record = dragons[dragonId]
	if not record then return nil end
	local def = DragonDefs[record.element]
	return {
		ownerUserId = record.ownerUserId,
		element = record.element,
		name = record.nickname or def.DisplayName,
		level = record.level, -- a real level since the rework; `stage` follows from it
		stage = record.stage,
		habitatId = record.habitatId,
		slotIndex = record.slotIndex,
		isBreeding = record.isBreeding,
		breedable = def.Breedable ~= false, -- defaults to true when the field is absent (base elements)
	}
end

-- Id of the player's dragon in that habitat slot, or nil. Dragon ids only live
-- for a session, so saves point at dragons by habitat and slot instead.
function DragonService.FindDragonAt(player, habitatId, slotIndex)
	for dragonId, record in pairs(dragons) do
		if record.ownerUserId == player.UserId and record.location == "Habitat"
			and record.habitatId == habitatId and record.slotIndex == slotIndex then
			return dragonId
		end
	end
	return nil
end

-- A breeding dragon leaves its habitat for the Nursery's tree: spotCFrame is
-- where it stands there, nurseryPart the building it's parented to (a tap on
-- it opens the Nursery). Its habitat slot stays reserved for its return, and
-- it earns, eats and moves nothing until the pairing ends (isBreeding false).
-- Called again with a new spot when the Nursery moves.
function DragonService.SetBreeding(dragonId, isBreeding, spotCFrame, nurseryPart)
	local record = dragons[dragonId]
	if not record or record.location ~= "Habitat" then return end
	record.isBreeding = isBreeding
	if isBreeding and spotCFrame and nurseryPart then
		record.breedingSpot = spotCFrame
		record.part.Parent = nurseryPart
		record.part:SetAttribute("HabitatId", nil)
		record.part:SetAttribute("NurseryId", nurseryPart:GetAttribute("NurseryId"))
	elseif not isBreeding then
		record.breedingSpot = nil
		record.part.Parent = record.habitatRecord.model
		record.part:SetAttribute("NurseryId", nil)
		record.part:SetAttribute("HabitatId", record.habitatId)
	end
	refreshVisual(record)
end

-- Drops this player's dragon records; the Parts themselves are destroyed via
-- HabitatService.RemovePlayer (they're parented under the habitat/island).
function DragonService.RemovePlayerDragons(player)
	for dragonId, record in pairs(dragons) do
		if record.ownerUserId == player.UserId then
			dragons[dragonId] = nil
		end
	end
end

-- The Coins a dragon makes in `seconds` (by its rarity and stage, DragonRules:
-- a Baby earns half an Adult's rate) go into its habitat's storage, which caps
-- them (HabitatService.StoreCoins). Fractions add up across ticks. One at the
-- Nursery makes none; what its habitat already stored stays there to harvest.
local function accrueIncome(record, seconds)
	if record.location ~= "Habitat" or record.isBreeding then
		return
	end
	HabitatService.StoreCoins(record.habitatRecord, DragonRules.IncomePerSecond(record.element, record.stage) * seconds)
end

-- Coins the player's dragons earned while they were offline, stored once when
-- their island loads (same rates and storage cap as the online income loop).
function DragonService.AccrueOfflineIncome(player, seconds)
	if seconds <= 0 then
		return
	end
	for _, record in pairs(dragons) do
		if record.ownerUserId == player.UserId then
			accrueIncome(record, seconds)
		end
	end
end

function DragonService.StartIncomeLoop()
	task.spawn(function()
		while true do
			task.wait(GameConstants.IncomeTickSeconds)
			for _, record in pairs(dragons) do
				accrueIncome(record, GameConstants.IncomeTickSeconds)
			end
		end
	end)
end

return DragonService
