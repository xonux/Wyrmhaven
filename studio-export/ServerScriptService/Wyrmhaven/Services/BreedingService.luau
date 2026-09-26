-- Nurserys: pair two Adult dragons, wait (DragonRules.BreedingSeconds: by the
-- rarity of the egg they'll give; Gems skip it - SpeedUpWithGems), collect the
-- resulting egg. Every player has one Nursery and can buy a second one in the
-- Shop (BuyNursery: GameConstants.NurseryMax, NurseryGemPrice); each runs one
-- pairing at a time. A running pairing is saved with its absolute ready time
-- (GetSaveState / RestorePairing), so it keeps going while the player is
-- offline.
--
-- The model is a pink heart-shaped tree: Assets.Buildings.Nursery (trunk in
-- the back-right corner) for the first, NurseryMirror (back-left) for the
-- second. While a pairing runs, both parents leave their habitats and stand
-- at its foot (Parent1/Parent2 attachments, see DragonService.SetBreeding),
-- pink sparkles rise (its Love emitter), and golden ones say the egg is ready.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)
local DragonRules = require(Config.DragonRules)
local GemSpeedUp = require(Config.GemSpeedUp)

local ReadyGlow = require(script.Parent.ReadyGlow)

local BreedingService = {}

local HabitatService
local DragonService
local IncubatorService
local EconomyService
local breedingStatusUpdated

-- [userId] = { [nurseryId] = { id, part, gridX, gridZ, pairing? } }, with
-- pairing = { dragonIdA, dragonIdB, resultElement (the egg's species),
-- readyAt, ready }. Nursery
-- ids count from 1 per player; the NurseryId attribute on their parts routes
-- taps.
local playerNurserys = {}

local assets = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets")
local buildingTemplates = assets:FindFirstChild("Buildings")
local TEMPLATE_NAMES = { "Nursery", "NurseryMirror" } -- by nursery id
local READY_GLOW_OFFSET = Vector3.new(0, 6, 1.5)

local function getNursery(player, nurseryId)
	local list = playerNurserys[player.UserId]
	return list and list[nurseryId]
end

local function countNurserys(list)
	local count = 0
	for _ in pairs(list) do
		count += 1
	end
	return count
end

-- Where the two parents stand, in front of the tree.
local function parentSpots(nursery)
	local spots = {}
	for i, fallbackX in ipairs({ -3, 3 }) do
		local attachment = nursery.part:FindFirstChild("Parent" .. i)
		spots[i] = attachment and CFrame.new(attachment.WorldPosition)
			or CFrame.new(nursery.part.Position + Vector3.new(fallbackX, nursery.part.Size.Y / 2, 2.5))
	end
	return spots
end

-- Puts the pairing's parents at the tree (again, after a move).
local function seatParents(nursery)
	local pairing = nursery.pairing
	if not pairing then return end
	local spots = parentSpots(nursery)
	DragonService.SetBreeding(pairing.dragonIdA, true, spots[1], nursery.part)
	DragonService.SetBreeding(pairing.dragonIdB, true, spots[2], nursery.part)
end

-- Pink sparkles while the pairing runs, golden ones once its egg is ready.
local function refreshLook(nursery)
	local pairing = nursery.pairing
	local love = nursery.part:FindFirstChild("Love")
	local emitter = love and love:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter.Enabled = pairing ~= nil and not pairing.ready
	end
	ReadyGlow.Set(nursery.part, pairing ~= nil and pairing.ready, READY_GLOW_OFFSET)
end

-- What the Nursery UI shows for a dragon (name, level, element).
local function dragonCard(dragonId)
	local info = DragonService.GetDragonInfo(dragonId)
	if not info then return nil end
	return { id = dragonId, element = info.element, name = info.name, level = info.level }
end

-- Species of the egg a pair produces, drawn by DragonRules.BreedingOutcomes
-- (two Commons of different elements give their Rare hybrid, otherwise one
-- parent's species). Rolled once when the pairing starts, so the egg is
-- decided before it's ready; the Nursery screen shows the chances.
local function rollResultElement(speciesA, speciesB)
	return DragonRules.RollBreeding(speciesA, speciesB)
end

local function buildStatus(player, nursery)
	local pairing = nursery.pairing
	if pairing then
		return {
			nurseryId = nursery.id,
			pairing = {
				ready = pairing.ready,
				secondsLeft = math.max(0, pairing.readyAt - os.time()),
				dragonA = dragonCard(pairing.dragonIdA),
				dragonB = dragonCard(pairing.dragonIdB),
				resultElement = pairing.resultElement,
			},
		}
	end

	local available = {}
	for _, dragon in ipairs(DragonService.GetPlayerDragons(player)) do
		if dragon.stage == "Adult" and not dragon.isBreeding and dragon.breedable ~= false then
			table.insert(available, dragonCard(dragon.id))
		end
	end
	table.sort(available, function(a, b) return a.id < b.id end)
	return { nurseryId = nursery.id, availableDragons = available }
end

-- openRequest tells the client to force the UI open (only true for an
-- explicit click on the Nursery) - the tick loop/action results also push
-- fresh content but must never yank it back open after the player closes it.
-- extra: optional fields merged into the push (e.g. { collectError = reason }).
local function pushStatus(player, nursery, openRequest, extra)
	local status = buildStatus(player, nursery)
	status.openRequest = openRequest or false
	for key, value in pairs(extra or {}) do
		status[key] = value
	end
	breedingStatusUpdated:FireClient(player, status)
end

function BreedingService.Init(habitatServiceRef, dragonServiceRef, incubatorServiceRef, remotesFolder, economyServiceRef)
	HabitatService = habitatServiceRef
	DragonService = dragonServiceRef
	IncubatorService = incubatorServiceRef
	EconomyService = economyServiceRef

	breedingStatusUpdated = remotesFolder:FindFirstChild("BreedingStatusUpdated")
	if not breedingStatusUpdated then
		breedingStatusUpdated = Instance.new("RemoteEvent")
		breedingStatusUpdated.Name = "BreedingStatusUpdated"
		breedingStatusUpdated.Parent = remotesFolder
	end
end

-- Default grid spot (tiles 18-20, 18-20, in the island's starting area) for a
-- new player, reserved on HabitatService's placement grid before any Habitat
-- is placed. The player can move the Nursery afterwards (MoveNursery); its
-- spot is saved.
local GRID_X, GRID_Z = 18, 18
local GRID_TILES = GameConstants.StructureTiles.Nursery

local function createNursery(player, list, nurseryId, gridX, gridZ)
	local center = HabitatService.GridCenterFor(player, gridX, gridZ, GRID_TILES, GRID_TILES)
	HabitatService.OccupyArea(player, gridX, gridZ, GRID_TILES, GRID_TILES)

	local template = buildingTemplates and buildingTemplates:FindFirstChild(TEMPLATE_NAMES[nurseryId] or TEMPLATE_NAMES[1])
	local part
	if template then
		part = template:Clone()
		HabitatService.PivotTree(part, CFrame.new(center + Vector3.new(0, part.Size.Y / 2, 0)))
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(10, 1, 10)
		part.Color = Color3.fromRGB(219, 180, 217)
		part.Material = Enum.Material.SmoothPlastic
		part.Position = center + Vector3.new(0, part.Size.Y / 2, 0)
	end
	part.Name = "Nursery " .. nurseryId
	part.Anchored = true
	part.CanCollide = false
	-- On every piece, so a tap on the tree opens the Nursery too.
	part:SetAttribute("NurseryId", nurseryId)
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("NurseryId", nurseryId)
		end
	end
	part.Parent = HabitatService.GetIslandModel(player)

	local nursery = { id = nurseryId, part = part, gridX = gridX, gridZ = gridZ }
	list[nurseryId] = nursery
	return nursery
end

-- The save's Nursery entry as a list of { gridX, gridZ, pairing? }, one per
-- Nursery: older saves hold their only Nursery's fields at the top level.
local function savedNurserys(saveState)
	if not saveState then
		return {}
	end
	if saveState.nurseries and #saveState.nurseries > 0 then
		return saveState.nurseries
	end
	return { saveState }
end

-- saveState: the save's Nursery entry ({ nurseries = { {gridX, gridZ,
-- pairing?}, ... } }), or nil for a new player: one Nursery at the default
-- spot. Pairings come back later (RestorePairing), once the dragons exist.
function BreedingService.LoadPlayer(player, saveState)
	HabitatService.EnsureIsland(player)
	local list = {}
	playerNurserys[player.UserId] = list
	local saved = savedNurserys(saveState)
	if #saved == 0 then
		saved = { {} }
	end
	for nurseryId = 1, math.min(#saved, GameConstants.NurseryMax) do
		local gridX, gridZ = saved[nurseryId].gridX or GRID_X, saved[nurseryId].gridZ or GRID_Z
		if not HabitatService.IsAreaFree(player, gridX, gridZ, GRID_TILES, GRID_TILES) then
			gridX, gridZ = HabitatService.FindFreeGridSlot(player, GRID_TILES, GRID_TILES)
		end
		if gridX then
			createNursery(player, list, nurseryId, gridX, gridZ)
		end
	end
end

-- { nurseries = { {gridX, gridZ, pairing?}, ... } } in nursery id order.
-- Dragon ids don't survive a reload, so a pairing points at its parents by
-- habitat and slot.
function BreedingService.GetSaveState(player)
	local list = playerNurserys[player.UserId]
	if not list then return nil end
	local nurseries = {}
	for nurseryId = 1, GameConstants.NurseryMax do
		local nursery = list[nurseryId]
		if nursery then
			local state = { gridX = nursery.gridX, gridZ = nursery.gridZ }
			local pairing = nursery.pairing
			local infoA = pairing and DragonService.GetDragonInfo(pairing.dragonIdA)
			local infoB = pairing and DragonService.GetDragonInfo(pairing.dragonIdB)
			if infoA and infoB then
				state.pairing = {
					habitatIdA = infoA.habitatId,
					slotIndexA = infoA.slotIndex,
					habitatIdB = infoB.habitatId,
					slotIndexB = infoB.slotIndex,
					resultElement = pairing.resultElement,
					readyAt = pairing.readyAt,
				}
			end
			table.insert(nurseries, state)
		end
	end
	return { nurseries = nurseries }
end

-- Puts back the saved pairings once the player's dragons are spawned. One is
-- dropped if a parent can't be found any more.
function BreedingService.RestorePairing(player, saveState)
	local list = playerNurserys[player.UserId]
	if not list then return end
	for nurseryId, nurserySave in ipairs(savedNurserys(saveState)) do
		local nursery = list[nurseryId]
		local saved = nurserySave.pairing
		if nursery and saved and saved.resultElement and saved.readyAt then
			local dragonIdA = DragonService.FindDragonAt(player, saved.habitatIdA, saved.slotIndexA)
			local dragonIdB = DragonService.FindDragonAt(player, saved.habitatIdB, saved.slotIndexB)
			local infoA = dragonIdA and DragonService.GetDragonInfo(dragonIdA)
			local infoB = dragonIdB and DragonService.GetDragonInfo(dragonIdB)
			if infoA and infoB and dragonIdA ~= dragonIdB and not infoA.isBreeding and not infoB.isBreeding then
				nursery.pairing = {
					dragonIdA = dragonIdA,
					dragonIdB = dragonIdB,
					resultElement = saved.resultElement,
					readyAt = saved.readyAt,
					ready = os.time() >= saved.readyAt,
				}
				seatParents(nursery)
				refreshLook(nursery)
			end
		end
	end
end

function BreedingService.GetNurseryCount(player)
	local list = playerNurserys[player.UserId]
	return list and countNurserys(list) or 0
end

-- The second Nursery, bought in the Shop's Buildings tab with Gems and
-- placed on the grid, ready at once. Checks the spot before spending, so a
-- refused placement never charges. Returns true, or false plus a reason for
-- the Shop's toast ("MaxNurserys", "TilesOccupied", "InsufficientGems").
function BreedingService.BuyNursery(player, gridX, gridZ)
	local list = playerNurserys[player.UserId]
	if not list then return false, "NotFound" end
	local nurseryId = nil
	for id = 1, GameConstants.NurseryMax do
		if not list[id] then
			nurseryId = id
			break
		end
	end
	if not nurseryId then return false, "MaxNurserys" end
	if not HabitatService.IsAreaFree(player, gridX, gridZ, GRID_TILES, GRID_TILES) then
		return false, "TilesOccupied"
	end
	if not EconomyService.TrySpendGems(player, GameConstants.NurseryGemPrice) then
		return false, "InsufficientGems"
	end
	createNursery(player, list, nurseryId, gridX, gridZ)
	return true
end

function BreedingService.MoveNursery(player, nurseryId, gridX, gridZ)
	local nursery = getNursery(player, nurseryId)
	if not nursery then return false end
	if not HabitatService.TryMoveArea(player, nursery.gridX, nursery.gridZ, gridX, gridZ, GRID_TILES, GRID_TILES) then
		return false
	end
	local center = HabitatService.GridCenterFor(player, gridX, gridZ, GRID_TILES, GRID_TILES)
	HabitatService.PivotTree(nursery.part, CFrame.new(center + Vector3.new(0, nursery.part.Size.Y / 2, 0)))
	nursery.gridX, nursery.gridZ = gridX, gridZ
	seatParents(nursery)
	return true
end

function BreedingService.RequestInfo(player, nurseryId)
	local nursery = getNursery(player, nurseryId)
	if nursery then
		pushStatus(player, nursery, true)
	end
end

function BreedingService.StartBreeding(player, nurseryId, dragonIdA, dragonIdB)
	local nursery = getNursery(player, nurseryId)
	if not nursery or nursery.pairing then return end -- one pairing per Nursery
	if dragonIdA == dragonIdB then return end

	local infoA = DragonService.GetDragonInfo(dragonIdA)
	local infoB = DragonService.GetDragonInfo(dragonIdB)
	if not infoA or not infoB then return end
	if infoA.ownerUserId ~= player.UserId or infoB.ownerUserId ~= player.UserId then return end
	if infoA.stage ~= "Adult" or infoB.stage ~= "Adult" then return end
	if infoA.isBreeding or infoB.isBreeding then return end
	-- A species can opt out of breeding (DragonDefs Breedable = false). None
	-- does since the Shop exclusive was removed, but a dragon with no habitat
	-- to place its egg into would softlock the Nursery forever, so the check
	-- stays. See breeding-exclusive-dragon-softlock.md.
	if infoA.breedable == false or infoB.breedable == false then return end

	local result = rollResultElement(infoA.element, infoB.element)
	nursery.pairing = {
		dragonIdA = dragonIdA,
		dragonIdB = dragonIdB,
		resultElement = result,
		readyAt = os.time() + DragonRules.BreedingSeconds(result),
		ready = false,
	}
	-- Both parents go to the tree until the egg is collected.
	seatParents(nursery)
	refreshLook(nursery)

	pushStatus(player, nursery)
end

-- Skips the rest of a pairing for Gems, by the time left (Config/GemSpeedUp):
-- its egg is ready at once. A refusal is pushed back as speedUpError.
function BreedingService.SpeedUpWithGems(player, nurseryId)
	local nursery = getNursery(player, nurseryId)
	local pairing = nursery and nursery.pairing
	if not pairing or pairing.ready then return false end
	local secondsLeft = pairing.readyAt - os.time()
	if secondsLeft > 0 and not EconomyService.TrySpendGems(player, GemSpeedUp(secondsLeft)) then
		pushStatus(player, nursery, false, { speedUpError = "NotEnoughGems" })
		return false
	end
	pairing.readyAt = os.time()
	pairing.ready = true
	refreshLook(nursery)
	pushStatus(player, nursery)
	return true
end

function BreedingService.CollectEgg(player, nurseryId)
	local nursery = getNursery(player, nurseryId)
	local pairing = nursery and nursery.pairing
	if not pairing or not pairing.ready then return end

	local resultElement = pairing.resultElement

	-- The resulting egg goes through the Incubator like any other egg (see
	-- IncubatorService) - not straight into a Habitat.
	if not IncubatorService.AddEgg(player, resultElement) then
		pushStatus(player, nursery, false, { collectError = "IncubatorFull" }) -- still ready, the player retries later
		return
	end

	-- Back home to their habitats.
	DragonService.SetBreeding(pairing.dragonIdA, false)
	DragonService.SetBreeding(pairing.dragonIdB, false)

	nursery.pairing = nil
	refreshLook(nursery)
	pushStatus(player, nursery)
end

function BreedingService.StartStatusLoop(getPlayers)
	task.spawn(function()
		while true do
			task.wait(GameConstants.BreedingTickSeconds)
			for _, player in ipairs(getPlayers()) do
				for _, nursery in pairs(playerNurserys[player.UserId] or {}) do
					local pairing = nursery.pairing
					if pairing then
						if not pairing.ready and os.time() >= pairing.readyAt then
							pairing.ready = true
							refreshLook(nursery)
						end
						pushStatus(player, nursery)
					end
				end
			end
		end
	end)
end

function BreedingService.RemovePlayer(player)
	playerNurserys[player.UserId] = nil
end

return BreedingService
