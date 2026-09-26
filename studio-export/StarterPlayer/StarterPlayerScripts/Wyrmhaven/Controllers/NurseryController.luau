-- Nurserys (up to two, one pairing each): clicking one opens its option bar
-- (OptionBar) with a single button - Breed, the running pairing's
-- countdown (with Speed up: Gems make the egg ready at once), or Collect
-- once the egg is ready. Breed and the countdown
-- open BreedingScreen to pick or watch the two dragons, who wait at that
-- Nursery's tree (earning nothing) until the egg is collected. The server
-- pushes BreedingStatusUpdated (tagged with its nurseryId) on request, every
-- tick while a pairing runs, and after each action.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementController = require(script.Parent.PlacementController)
local DragonDefs = require(ReplicatedStorage.Wyrmhaven.Config.DragonDefs)
local GemSpeedUp = require(ReplicatedStorage.Wyrmhaven.Config.GemSpeedUp)

local UI = script.Parent.Parent.UI
local OptionBar = require(UI.OptionBar)
local BreedingScreen = require(UI.BreedingScreen)
local Toast = require(UI.Toast)
local UIKit = require(UI.UIKit)
local UITheme = require(UI.UITheme)

local NurseryController = {}

local function barOwner(nurseryId)
	return "Nursery:" .. tostring(nurseryId)
end

function NurseryController.Init(remotesFolder)
	local requestStartBreeding = remotesFolder:WaitForChild("RequestStartBreeding")
	local requestCollectEgg = remotesFolder:WaitForChild("RequestCollectEgg")
	local breedingStatusUpdated = remotesFolder:WaitForChild("BreedingStatusUpdated")
	local requestSpeedUpBreeding = remotesFolder:WaitForChild("RequestSpeedUpBreeding")
	local updateHud = remotesFolder:WaitForChild("UpdateHud")

	local statuses = {} -- [nurseryId] = its last push
	local screenNurseryId = nil -- the Nursery BreedingScreen shows
	local gems = 0

	-- Gems for the rest of a pairing (toast when short).
	local function speedUp(nurseryId, cost)
		if gems < cost then
			Toast.Show("Not enough Gems")
		else
			requestSpeedUpBreeding:FireServer(nurseryId)
		end
	end

	BreedingScreen.Init({
		onBreed = function(dragonIdA, dragonIdB)
			requestStartBreeding:FireServer(dragonIdA, dragonIdB, screenNurseryId)
		end,
		onCollect = function()
			requestCollectEgg:FireServer(screenNurseryId)
		end,
		onSpeedUp = function(cost)
			speedUp(screenNurseryId, cost)
		end,
	})

	local function openScreen(nurseryId)
		OptionBar.Close()
		screenNurseryId = nurseryId
		BreedingScreen.Open(statuses[nurseryId])
	end

	local function buildSpec(status)
		local nurseryId = status.nurseryId
		local pairing = status.pairing
		local item, subtitle, extra
		if pairing and pairing.ready then
			subtitle = "The egg is ready"
			item = {
				key = "Collect",
				icon = "Egg",
				-- the egg's own color (a hybrid has no single element color)
				iconColor = DragonDefs[pairing.resultElement] and DragonDefs[pairing.resultElement].StageColors.Egg
					or UITheme.GetElement(pairing.resultElement).Main,
				palette = "Confirm",
				top = "Ready",
				label = "Collect",
				onClick = function()
					requestCollectEgg:FireServer(nurseryId)
				end,
			}
		elseif pairing then
			subtitle = "Breeding in progress"
			item = {
				key = "Pairing",
				icon = "Heart",
				top = UIKit.formatDuration(pairing.secondsLeft or 0),
				label = "In progress",
				onClick = function()
					openScreen(nurseryId)
				end,
			}
			local cost = GemSpeedUp(pairing.secondsLeft or 0)
			extra = {
				key = "SpeedUp",
				icon = "Gem",
				top = UIKit.formatNumber(cost),
				topIcon = "Gem",
				label = "Speed up",
				dimmed = gems < cost,
				onClick = function()
					speedUp(nurseryId, cost)
				end,
			}
		else
			subtitle = "Breed two adult dragons"
			item = {
				key = "Breed",
				icon = "Heart",
				label = "Breed",
				onClick = function()
					openScreen(nurseryId)
				end,
			}
		end
		local items = { item }
		if extra then
			table.insert(items, extra)
		end
		table.insert(items, {
			key = "Move",
			icon = "Move",
			label = "Move",
			onClick = function()
				PlacementController.StartMove("Nursery", nurseryId, "NurseryId", nurseryId)
			end,
		})
		return {
			title = "Nursery",
			subtitle = subtitle,
			anchor = { attribute = "NurseryId", value = nurseryId },
			items = items,
		}
	end

	breedingStatusUpdated.OnClientEvent:Connect(function(newStatus)
		local nurseryId = newStatus.nurseryId
		local previous = statuses[nurseryId]
		local hadReadyEgg = previous ~= nil and previous.pairing ~= nil and previous.pairing.ready
		-- Only a pairing started from the Breeding screen, not one restored at join.
		local startedPairing = previous ~= nil and previous.pairing == nil and newStatus.pairing ~= nil and not newStatus.openRequest
		statuses[nurseryId] = newStatus
		if startedPairing then
			Toast.Show("Your dragons stay at the Nursery until you collect the egg")
		end

		local owner = barOwner(nurseryId)
		if newStatus.openRequest then
			OptionBar.Open(owner, buildSpec(newStatus))
		elseif OptionBar.IsShowing(owner) then
			OptionBar.Update(owner, buildSpec(newStatus))
		end
		if BreedingScreen.IsOpen() and screenNurseryId == nurseryId then
			BreedingScreen.Update(newStatus)
		end

		if newStatus.speedUpError == "NotEnoughGems" then
			Toast.Show("Not enough Gems")
		end
		if newStatus.collectError == "IncubatorFull" then
			Toast.Show("Incubator full: place your hatchlings first")
		elseif hadReadyEgg and not newStatus.pairing then
			Toast.Show("The egg went to the Incubator")
		end
	end)

	-- Speed up greys out or lights up with the Gem balance.
	updateHud.OnClientEvent:Connect(function(data)
		local newGems = data.Gems or gems
		if newGems == gems then
			return
		end
		gems = newGems
		BreedingScreen.SetGems(gems)
		for nurseryId, status in pairs(statuses) do
			if status.pairing and OptionBar.IsShowing(barOwner(nurseryId)) then
				OptionBar.Update(barOwner(nurseryId), buildSpec(status))
			end
		end
	end)
end

return NurseryController
