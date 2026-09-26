-- Incubator (Hatchery): every egg (starter or bred) lands here first and
-- hatches on a timer set by its dragon's rarity (DragonRules.HatchSeconds,
-- speedable with Gems) instead of being fed directly in a Habitat. Once
-- hatched (Baby stage) the player moves it into a free Habitat slot it can
-- live in (see DragonService.MoveToHabitat) - or sells it (SellHatchling).
-- One Incubator per player, same pattern as FarmService/BreedingService.
-- Its model (Assets.Buildings.Incubator) is a rock with a nest at each
-- height, one egg per nest (Slot1..Slot4 attachments). A new player has
-- GameConstants.IncubatorStartNests nests and buys the next ones with Gems
-- (UpgradeNests), up to IncubatorCapacity.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)
local DragonDefs = require(Config.DragonDefs)
local DragonRules = require(Config.DragonRules)
local GemSpeedUp = require(Config.GemSpeedUp)

local LevelService = require(script.Parent.LevelService)

local IncubatorService = {}

local HabitatService
local DragonService
local EconomyService
local incubatorStatusUpdated

-- [userId] = { part, nests, slots = { [slotIndex] = {dragonId, element, hatchAt, ready, xpPaid} }, slotCFrames, gridX, gridZ }
local incubators = {}

local assets = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets")
local buildingTemplates = assets:FindFirstChild("Buildings")
local incubatorTemplate = buildingTemplates and buildingTemplates:FindFirstChild("Incubator")

-- The egg becomes a baby dragon. Its XP comes later, when the player places
-- it in a habitat (PlaceInHabitat).
local function hatch(player, slot)
	slot.ready = true
	DragonService.SetHatched(slot.dragonId)
end

-- XP for a hatchling placed in a habitat, by its rarity (DragonDefs Rarity,
-- Common until rarities exist) - once per egg.
local function payHatchXp(player, slot)
	if slot.xpPaid then
		return
	end
	slot.xpPaid = true
	local def = DragonDefs[slot.element]
	local xpByRarity = GameConstants.HatchXpByRarity
	LevelService.AddXp(player, xpByRarity[def and def.Rarity or "Common"] or xpByRarity.Common)
end

-- Where each egg sits: the model's Slot1..Slot4 attachments (in its nests),
-- else a 2x2 grid on top of the plain part.
local function computeSlotCFrames(part)
	local fromModel = {}
	for i = 1, GameConstants.IncubatorCapacity do
		local attachment = part:FindFirstChild("Slot" .. i)
		if attachment and attachment:IsA("Attachment") then
			fromModel[i] = CFrame.new(attachment.WorldPosition)
		end
	end
	if #fromModel == GameConstants.IncubatorCapacity then
		return fromModel
	end

	local top = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
	local offsets = {
		Vector3.new(-3, 0, -3),
		Vector3.new(3, 0, -3),
		Vector3.new(-3, 0, 3),
		Vector3.new(3, 0, 3),
	}
	local cframes = {}
	for i, offset in ipairs(offsets) do
		cframes[i] = CFrame.new(top + offset)
	end
	return cframes
end

-- Shows the nests the player has (Visual.Nest1..NestN) and leaves the
-- others out of the model.
local function refreshNests(record)
	local visual = record.part:FindFirstChild("Visual")
	local templateVisual = incubatorTemplate and incubatorTemplate:FindFirstChild("Visual")
	if not visual or not templateVisual then
		return
	end
	for i = 1, GameConstants.IncubatorCapacity do
		local name = "Nest" .. i
		local nest = visual:FindFirstChild(name)
		if i > record.nests and nest then
			nest:Destroy()
		elseif i <= record.nests and not nest then
			local source = templateVisual:FindFirstChild(name)
			if source then
				nest = source:Clone()
				nest.CFrame = record.part.CFrame * incubatorTemplate.CFrame:ToObjectSpace(source.CFrame)
				nest:SetAttribute("IncubatorId", record.part:GetAttribute("IncubatorId"))
				nest.Parent = visual
			end
		end
	end
end

local function buildStatus(player)
	local record = incubators[player.UserId]
	if not record then return { slots = {} } end

	local slots = {}
	for i = 1, record.nests do
		local slot = record.slots[i]
		if not slot then
			slots[i] = { empty = true }
		else
			local def = DragonDefs[slot.element]
			local secondsLeft = math.max(0, slot.hatchAt - os.time())
			local duration = DragonRules.HatchSeconds(slot.element)
			slots[i] = {
				empty = false,
				dragonId = slot.dragonId,
				element = slot.element,
				-- where the hatchling can live (a hybrid: either of its two)
				habitatElement = DragonRules.Elements(slot.element)[1],
				habitatElements = DragonRules.Elements(slot.element),
				displayName = def.DisplayName,
				color = def.StageColors.Egg,
				ready = slot.ready,
				secondsLeft = secondsLeft,
				progressPercent = math.floor(100 * (1 - math.min(1, secondsLeft / duration))),
				sellPrice = DragonRules.SellPrice(slot.element), -- a hatchling can be sold instead of placed
			}
		end
	end
	-- habitats: where a hatchling can go (the client filters by element/room).
	-- nestPrice: Gems for the next nest, nil once they're all there.
	return {
		slots = slots,
		habitats = HabitatService.GetHabitatSummaries(player),
		nests = record.nests,
		maxNests = GameConstants.IncubatorCapacity,
		nestPrice = record.nests < GameConstants.IncubatorCapacity and GameConstants.IncubatorNestGemPrices[record.nests] or nil,
	}
end

-- openRequest tells the client to force the panel open (only true for an
-- explicit click on the Incubator) - same rule as BreedingService/pushStatus.
-- extra: optional fields merged into the push (e.g. { speedUpError = reason }).
local function pushStatus(player, openRequest, extra)
	local status = buildStatus(player)
	status.openRequest = openRequest or false
	for key, value in pairs(extra or {}) do
		status[key] = value
	end
	incubatorStatusUpdated:FireClient(player, status)
end

function IncubatorService.Init(habitatServiceRef, dragonServiceRef, economyServiceRef, remotesFolder)
	HabitatService = habitatServiceRef
	DragonService = dragonServiceRef
	EconomyService = economyServiceRef

	incubatorStatusUpdated = remotesFolder:FindFirstChild("IncubatorStatusUpdated")
	if not incubatorStatusUpdated then
		incubatorStatusUpdated = Instance.new("RemoteEvent")
		incubatorStatusUpdated.Name = "IncubatorStatusUpdated"
		incubatorStatusUpdated.Parent = remotesFolder
	end
end

-- Default grid spot (tiles 7-9, 18-20, in the island's starting area) for a new
-- player, reserved on HabitatService's placement grid before any Habitat is
-- placed, mirroring Farm/Nursery. The player can move it afterwards
-- (MoveIncubator); its spot is saved separately from the eggs (GetGridState).
local GRID_X, GRID_Z = 7, 18
local GRID_TILES = GameConstants.StructureTiles.Incubator

-- gridState: { gridX, gridZ, nests } from GetGridState, or nil for a new
-- player (default spot, IncubatorStartNests nests).
function IncubatorService.CreateIncubator(player, gridState)
	HabitatService.EnsureIsland(player)
	local islandModel = HabitatService.GetIslandModel(player)

	local gridX = (gridState and gridState.gridX) or GRID_X
	local gridZ = (gridState and gridState.gridZ) or GRID_Z
	local center = HabitatService.GridCenterFor(player, gridX, gridZ, GRID_TILES, GRID_TILES)
	HabitatService.OccupyArea(player, gridX, gridZ, GRID_TILES, GRID_TILES)

	local part
	if incubatorTemplate then
		part = incubatorTemplate:Clone()
		HabitatService.PivotTree(part, CFrame.new(center + Vector3.new(0, part.Size.Y / 2, 0)))
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(10, 1, 10)
		part.Color = Color3.fromRGB(230, 210, 150)
		part.Material = Enum.Material.SmoothPlastic
		part.Position = center + Vector3.new(0, part.Size.Y / 2, 0)
	end
	part.Name = "Incubator"
	part.Anchored = true
	part.CanCollide = false
	-- On every piece, so a tap on the rock or a nest opens the Incubator too.
	part:SetAttribute("IncubatorId", player.UserId)
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("IncubatorId", player.UserId)
		end
	end

	local record = {
		part = part,
		nests = math.clamp((gridState and gridState.nests) or GameConstants.IncubatorStartNests, 1, GameConstants.IncubatorCapacity),
		slots = {},
		slotCFrames = computeSlotCFrames(part),
		gridX = gridX,
		gridZ = gridZ,
	}
	refreshNests(record)
	part.Parent = islandModel
	incubators[player.UserId] = record
	return record
end

function IncubatorService.GetGridState(player)
	local record = incubators[player.UserId]
	return record and { gridX = record.gridX, gridZ = record.gridZ, nests = record.nests } or nil
end

-- Buys the next nest with Gems. Returns true, or false plus a reason
-- ("MaxNests", "NotEnoughGems" - the latter pushed back as upgradeError).
function IncubatorService.UpgradeNests(player)
	local record = incubators[player.UserId]
	if not record then return false, "NotFound" end
	local price = GameConstants.IncubatorNestGemPrices[record.nests]
	if record.nests >= GameConstants.IncubatorCapacity or not price then return false, "MaxNests" end
	if not EconomyService.TrySpendGems(player, price) then
		pushStatus(player, false, { upgradeError = "NotEnoughGems" })
		return false, "NotEnoughGems"
	end
	record.nests += 1
	refreshNests(record)
	pushStatus(player, false)
	return true
end

-- Moves the Incubator and the eggs sitting in it.
function IncubatorService.MoveIncubator(player, gridX, gridZ)
	local record = incubators[player.UserId]
	if not record then return false end
	if not HabitatService.TryMoveArea(player, record.gridX, record.gridZ, gridX, gridZ, GRID_TILES, GRID_TILES) then
		return false
	end
	local center = HabitatService.GridCenterFor(player, gridX, gridZ, GRID_TILES, GRID_TILES)
	HabitatService.PivotTree(record.part, CFrame.new(center + Vector3.new(0, record.part.Size.Y / 2, 0)))
	record.gridX, record.gridZ = gridX, gridZ
	record.slotCFrames = computeSlotCFrames(record.part)
	DragonService.RefreshSlotPositions(record)
	return true
end

function IncubatorService.RequestInfo(player, incubatorId)
	if incubatorId ~= player.UserId then return end
	pushStatus(player, true)
end

-- Lets purchase flows (ShopService.BuyDragonEgg) refuse before charging.
function IncubatorService.HasFreeSlot(player)
	local record = incubators[player.UserId]
	if not record then return false end
	for i = 1, record.nests do
		if not record.slots[i] then
			return true
		end
	end
	return false
end

-- Finds a free slot and spawns a fresh egg with a full-length hatch timer.
-- Used for the starter egg and every breeding-produced egg. False if the
-- Incubator is full - callers keep whatever they were holding and let the
-- player retry later (same pattern as BreedingService.CollectEgg used to
-- use for a full Habitat).
function IncubatorService.AddEgg(player, element)
	local record = incubators[player.UserId]
	if not record then return false end

	local slotIndex = nil
	for i = 1, record.nests do
		if not record.slots[i] then
			slotIndex = i
			break
		end
	end
	if not slotIndex then return false end

	local dragon = DragonService.SpawnEgg(player, record, slotIndex, element)
	record.slots[slotIndex] = {
		dragonId = dragon.id,
		element = element,
		hatchAt = os.time() + DragonRules.HatchSeconds(element),
		ready = false,
		xpPaid = false,
	}
	pushStatus(player, false) -- refreshes the Incubator bar if it's open
	return true
end

-- Recreates a saved egg at its saved slot with its saved hatchAt (an
-- absolute unix timestamp), so remaining hatch time survives a server
-- restart correctly instead of resetting. hatched: it had already hatched
-- when saved; one that hatched while the player was away hatches now.
-- xpPaid: its XP was already given - saves from before the XP moved to the
-- placement don't have it, and their hatched eggs got it at hatching.
function IncubatorService.RestoreEgg(player, slotIndex, element, hatchAt, hatched, xpPaid)
	local record = incubators[player.UserId]
	if not record then return end
	if record.slots[slotIndex] or slotIndex > GameConstants.IncubatorCapacity then return end
	if slotIndex > record.nests then
		-- Saved before nests had to be bought (4 for everyone): its egg keeps its nest.
		record.nests = slotIndex
		refreshNests(record)
	end

	local dragon = DragonService.SpawnEgg(player, record, slotIndex, element)
	local slot = {
		dragonId = dragon.id,
		element = element,
		hatchAt = hatchAt,
		ready = false,
		xpPaid = if xpPaid ~= nil then xpPaid else hatched == true,
	}
	record.slots[slotIndex] = slot
	if hatched then
		slot.ready = true
		DragonService.SetHatched(dragon.id)
	elseif os.time() >= hatchAt then
		hatch(player, slot)
	end
end

-- Moves a hatched egg into the chosen Habitat (habitatId), or the first free
-- Habitat slot matching its element when none is given, and gives its hatching
-- XP. False (no-op) if it isn't ready yet or the Habitat has no room / the
-- wrong element - the egg just keeps waiting in the Incubator, and the client
-- is told (placeError).
function IncubatorService.PlaceInHabitat(player, dragonId, habitatId)
	local record = incubators[player.UserId]
	if not record then return false end

	local slotIndex, slot
	for i = 1, GameConstants.IncubatorCapacity do
		if record.slots[i] and record.slots[i].dragonId == dragonId then
			slotIndex, slot = i, record.slots[i]
			break
		end
	end
	if not slot or not slot.ready then return false end

	local habitatElements = DragonRules.Elements(slot.element)
	local habitatRecord, habitatSlotIndex
	if habitatId then
		habitatRecord, habitatSlotIndex = HabitatService.FindFreeSlotInHabitat(player, habitatId, habitatElements)
	else
		habitatRecord, habitatSlotIndex = HabitatService.FindFreeSlotForElement(player, habitatElements)
	end
	if not habitatRecord or not DragonService.MoveToHabitat(player, dragonId, habitatRecord, habitatSlotIndex) then
		pushStatus(player, false, { placeError = "NoRoom" })
		return false
	end

	record.slots[slotIndex] = nil
	payHatchXp(player, slot)
	pushStatus(player, false)
	return true
end

-- Sells a hatchling instead of placing it (the Incubator's Sell, at the
-- moment it would be placed): its rarity's price in Coins, and its hatching
-- XP all the same. Returns true, coins - or false, reason ("NotFound",
-- "NotHatched", "NotForSale").
function IncubatorService.SellHatchling(player, dragonId)
	local record = incubators[player.UserId]
	if not record then return false, "NotFound" end
	local slotIndex, slot
	for i = 1, GameConstants.IncubatorCapacity do
		if record.slots[i] and record.slots[i].dragonId == dragonId then
			slotIndex, slot = i, record.slots[i]
			break
		end
	end
	if not slot then return false, "NotFound" end
	if not slot.ready then return false, "NotHatched" end
	local price = DragonRules.SellPrice(slot.element)
	if not price then return false, "NotForSale" end
	if not DragonService.RemoveHatchling(player, dragonId) then return false, "NotFound" end

	record.slots[slotIndex] = nil
	payHatchXp(player, slot)
	EconomyService.AddCoins(player, price)
	pushStatus(player, false)
	return true, price
end

-- Skips the rest of an egg's hatching for Gems, by the time left
-- (Config/GemSpeedUp).
function IncubatorService.SpeedUpWithGems(player, dragonId)
	local record = incubators[player.UserId]
	if not record then return false end

	local slot
	for i = 1, GameConstants.IncubatorCapacity do
		if record.slots[i] and record.slots[i].dragonId == dragonId then
			slot = record.slots[i]
			break
		end
	end
	if not slot or slot.ready then return false end

	if not EconomyService.TrySpendGems(player, GemSpeedUp(slot.hatchAt - os.time())) then
		pushStatus(player, false, { speedUpError = "NotEnoughGems" })
		return false
	end

	slot.hatchAt = os.time()
	hatch(player, slot)
	pushStatus(player, false)
	return true
end

function IncubatorService.StartTickLoop(getPlayers)
	task.spawn(function()
		while true do
			task.wait(GameConstants.IncubatorTickSeconds)
			for _, player in ipairs(getPlayers()) do
				local record = incubators[player.UserId]
				if record then
					local changed = false
					for i = 1, GameConstants.IncubatorCapacity do
						local slot = record.slots[i]
						if slot and not slot.ready and os.time() >= slot.hatchAt then
							hatch(player, slot)
							changed = true
						end
					end
					if changed then
						pushStatus(player, false)
					end
				end
			end
		end
	end)
end

function IncubatorService.GetSaveState(player)
	local record = incubators[player.UserId]
	if not record then return {} end

	local list = {}
	for i = 1, GameConstants.IncubatorCapacity do
		local slot = record.slots[i]
		if slot then
			table.insert(list, { slotIndex = i, element = slot.element, hatchAt = slot.hatchAt, hatched = slot.ready, xpPaid = slot.xpPaid })
		end
	end
	return list
end

function IncubatorService.RemovePlayer(player)
	incubators[player.UserId] = nil
end

return IncubatorService
