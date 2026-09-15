-- Nursery: pair two Adult dragons, wait BreedingDurationSeconds, collect the
-- resulting egg. One Nursery + one active pairing per player (Phase 2 scope,
-- see docs/design/phase2-breeding.md). Known gap accepted by the design: an
-- in-progress pairing is NOT persisted by SaveService - a server restart
-- during breeding loses it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)
local BreedingTable = require(Config.BreedingTable)

local BreedingService = {}

local HabitatService
local DragonService
local breedingStatusUpdated

-- One Nursery per player, so NurseryId (read by the client raycast) is just
-- the owning player's UserId - same pattern as FarmId.
local nurseries = {} -- [userId] = { part, label }
local pairings = {} -- [userId] = { dragonIdA, dragonIdB, elementA, elementB, readyAt, ready }

local function refreshVisual(userId)
	local nursery = nurseries[userId]
	if not nursery then return end

	local pairing = pairings[userId]
	if not pairing then
		nursery.label.Text = "Nursery\n(Select 2 Adults)"
	elseif pairing.ready then
		nursery.label.Text = "Nursery\nEgg ready! (Collect)"
	else
		local secondsLeft = math.max(0, pairing.readyAt - os.time())
		nursery.label.Text = string.format("Nursery\nBreeding... %ds left", secondsLeft)
	end
end

local function buildStatus(player)
	local pairing = pairings[player.UserId]
	if pairing then
		return {
			pairing = {
				ready = pairing.ready,
				secondsLeft = math.max(0, pairing.readyAt - os.time()),
			},
		}
	end

	local available = {}
	for _, dragon in ipairs(DragonService.GetPlayerDragons(player)) do
		if dragon.stage == "Adult" and not dragon.isBreeding then
			table.insert(available, { id = dragon.id, element = dragon.element })
		end
	end
	return { availableDragons = available }
end

-- openRequest tells the client to force the panel open (only true for an
-- explicit click on the Nursery) - the tick loop/action results also push
-- fresh content but must never yank the panel back open after the player
-- closes it.
local function pushStatus(player, openRequest)
	local status = buildStatus(player)
	status.openRequest = openRequest or false
	breedingStatusUpdated:FireClient(player, status)
end

function BreedingService.Init(habitatServiceRef, dragonServiceRef, remotesFolder)
	HabitatService = habitatServiceRef
	DragonService = dragonServiceRef

	breedingStatusUpdated = remotesFolder:FindFirstChild("BreedingStatusUpdated")
	if not breedingStatusUpdated then
		breedingStatusUpdated = Instance.new("RemoteEvent")
		breedingStatusUpdated.Name = "BreedingStatusUpdated"
		breedingStatusUpdated.Parent = remotesFolder
	end
end

function BreedingService.CreateNursery(player)
	local islandModel = HabitatService.GetIslandModel(player)
	local islandBasePosition = HabitatService.GetIslandBasePosition(player)

	local size = Vector3.new(10, 1, 10)
	local part = Instance.new("Part")
	part.Name = "Nursery"
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.Color = Color3.fromRGB(219, 180, 217)
	part.Material = Enum.Material.SmoothPlastic
	-- Habitats cluster in a growing 2x2+ grid centered near the island origin
	-- (X in {-18..-2, 2..18}, Z growing from -18 upward - see HabitatService),
	-- and the Farm sits at (15,15) (see FarmService). Tucking the Nursery into
	-- the far corner (well outside both, near the island edge) avoids overlap
	-- for a realistic number of habitats - a real layout system is out of
	-- scope here (Farm/Habitat already make the same simplification).
	part.Position = islandBasePosition + Vector3.new(-24, 1 + size.Y / 2, 24)
	part.Parent = islandModel
	part:SetAttribute("NurseryId", player.UserId)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	nurseries[player.UserId] = { part = part, label = label }
	refreshVisual(player.UserId)
end

function BreedingService.RequestInfo(player, nurseryId)
	if nurseryId ~= player.UserId then return end
	pushStatus(player, true)
end

function BreedingService.StartBreeding(player, dragonIdA, dragonIdB)
	if dragonIdA == dragonIdB then return end
	if pairings[player.UserId] then return end -- capacity: 1 pairing at a time

	local infoA = DragonService.GetDragonInfo(dragonIdA)
	local infoB = DragonService.GetDragonInfo(dragonIdB)
	if not infoA or not infoB then return end
	if infoA.ownerUserId ~= player.UserId or infoB.ownerUserId ~= player.UserId then return end
	if infoA.stage ~= "Adult" or infoB.stage ~= "Adult" then return end
	if infoA.isBreeding or infoB.isBreeding then return end

	DragonService.SetBreeding(dragonIdA, true)
	DragonService.SetBreeding(dragonIdB, true)

	pairings[player.UserId] = {
		dragonIdA = dragonIdA,
		dragonIdB = dragonIdB,
		elementA = infoA.element,
		elementB = infoB.element,
		readyAt = os.time() + GameConstants.BreedingDurationSeconds,
		ready = false,
	}

	refreshVisual(player.UserId)
	pushStatus(player)
end

function BreedingService.CollectEgg(player)
	local pairing = pairings[player.UserId]
	if not pairing or not pairing.ready then return end

	local resultElement = nil
	local row = BreedingTable[pairing.elementA]
	if row then
		resultElement = row[pairing.elementB]
	end
	if not resultElement and pairing.elementA == pairing.elementB then
		resultElement = pairing.elementA -- same-element fallback, see docs/design/phase2-breeding.md
	end
	if not resultElement then
		warn("[Wyrmhaven] No BreedingTable result for " .. pairing.elementA .. " + " .. pairing.elementB)
		return
	end

	local habitatRecord, slotIndex = HabitatService.FindFreeSlotForElement(player, resultElement)
	if not habitatRecord then
		pushStatus(player) -- still ready; client shows "no room" via its own retry
		return
	end

	DragonService.SpawnDragon(player, habitatRecord, slotIndex, resultElement)
	DragonService.SetBreeding(pairing.dragonIdA, false)
	DragonService.SetBreeding(pairing.dragonIdB, false)

	pairings[player.UserId] = nil
	refreshVisual(player.UserId)
	pushStatus(player)
end

function BreedingService.StartStatusLoop(getPlayers)
	task.spawn(function()
		while true do
			task.wait(GameConstants.BreedingTickSeconds)
			for _, player in ipairs(getPlayers()) do
				local pairing = pairings[player.UserId]
				if pairing then
					if not pairing.ready and os.time() >= pairing.readyAt then
						pairing.ready = true
						refreshVisual(player.UserId)
					end
					pushStatus(player)
				end
			end
		end
	end)
end

function BreedingService.RemovePlayer(player)
	nurseries[player.UserId] = nil
	pairings[player.UserId] = nil
end

return BreedingService
