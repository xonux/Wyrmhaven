-- Incubator option bar (OptionBar): one button per egg with its hatch
-- countdown, a + opening the Shop's dragons while a nest is free, and
-- Upgrade until the rock has all its nests: it opens UpgradeScreen, which
-- shows the rock with one more nest and sells it for Gems.
-- Tapping an egg still hatching offers the Gem speed-up. Tapping a hatched
-- one starts choosing its home (HabitatPicker): arrows point at every
-- habitat it can live in with room, and tapping one of those habitats moves
-- the baby dragon there - or Sell sells it instead (DragonSale window; its
-- hatching XP comes all the same). The server pushes IncubatorStatusUpdated on
-- request, on hatch and after every action; the countdown ticks locally in
-- between.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HabitatPicker = require(script.Parent.HabitatPicker)
local PlacementController = require(script.Parent.PlacementController)
local ShopController = require(script.Parent.ShopController)

local UI = script.Parent.Parent.UI
local DragonSale = require(UI.DragonSale)
local OptionBar = require(UI.OptionBar)
local Toast = require(UI.Toast)
local UIKit = require(UI.UIKit)
local UpgradeScreen = require(UI.UpgradeScreen)

local IncubatorController = {}

local OWNER = "Incubator"
local UPGRADE_KEY = "Incubator"
local READY_COLOR = Color3.fromRGB(120, 200, 140)

local GemSpeedUp = require(ReplicatedStorage.Wyrmhaven.Config.GemSpeedUp)

local buildingTemplates = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Buildings")
local incubatorTemplate = buildingTemplates and buildingTemplates:FindFirstChild("Incubator")

function IncubatorController.Init(remotesFolder)
	local requestPlaceEggInHabitat = remotesFolder:WaitForChild("RequestPlaceEggInHabitat")
	local requestSpeedUpEgg = remotesFolder:WaitForChild("RequestSpeedUpEgg")
	local requestUpgradeIncubator = remotesFolder:WaitForChild("RequestUpgradeIncubator")
	local requestSellDragon = remotesFolder:WaitForChild("RequestSellDragon")
	local incubatorStatusUpdated = remotesFolder:WaitForChild("IncubatorStatusUpdated")
	local updateHud = remotesFolder:WaitForChild("UpdateHud")
	local incubatorId = Players.LocalPlayer.UserId -- one Incubator per player, see IncubatorService
	local anchor = { attribute = "IncubatorId", value = incubatorId }

	local status = nil
	local receivedAt = 0
	local selectedDragonId = nil -- hatching egg whose speed-up is shown; nil = the egg list
	local placingDragonId = nil -- sent to a habitat, waiting for the server's answer
	local gems, coins = 0, 0
	local buildSpec

	local function findSlot(dragonId)
		for _, slot in ipairs(status.slots) do
			if not slot.empty and slot.dragonId == dragonId then
				return slot
			end
		end
		return nil
	end

	local function showSelection(dragonId)
		selectedDragonId = dragonId
		OptionBar.Open(OWNER, buildSpec())
	end

	local function eggItem(slot, onClick)
		local secondsLeft = slot.secondsLeft - (os.clock() - receivedAt)
		return {
			key = "Egg" .. slot.dragonId,
			dragonId = slot.dragonId,
			top = slot.ready and "Hatched" or UIKit.formatDuration(secondsLeft),
			topColor = slot.ready and READY_COLOR or nil,
			label = slot.displayName,
			onClick = onClick,
		}
	end

	-- The upgrade window for the next nest: the rock as it will look, the nest
	-- count going up, the Gem price.
	local function upgradeSpec()
		local nests = status.nests or 1
		local price = status.nestPrice or 0
		return {
			key = UPGRADE_KEY,
			previewKey = nests + 1,
			title = string.format("Upgrade the Incubator to level %d", nests + 1),
			description = "Your dragon eggs hatch here, one per nest.",
			makeTemplate = function()
				if not incubatorTemplate then
					return nil
				end
				local template = incubatorTemplate:Clone()
				for i = nests + 2, status.maxNests or 4 do
					local nest = template.Visual:FindFirstChild("Nest" .. i)
					if nest then
						nest:Destroy()
					end
				end
				return template
			end,
			stats = {
				{ label = "Nests", icon = "Nest", from = nests, to = nests + 1 },
			},
			currency = "Gem",
			price = price,
			buttonText = "Upgrade",
			canAfford = gems >= price,
			blockedMessage = "Not enough Gems",
			onConfirm = function()
				requestUpgradeIncubator:FireServer()
			end,
		}
	end

	-- Sell, next to the arrows: sells the hatchling once confirmed.
	local function sellItem(slot)
		return {
			key = "Sell",
			icon = "Coin",
			palette = "Danger",
			top = "+" .. UIKit.formatNumber(slot.sellPrice),
			label = "Sell",
			onClick = function()
				UpgradeScreen.Open(DragonSale.Spec({
					dragonId = slot.dragonId,
					species = slot.element,
					stage = "Baby",
					name = slot.displayName,
					price = slot.sellPrice,
					coins = coins,
					note = "You still get its experience.",
					onConfirm = function()
						UpgradeScreen.Close()
						HabitatPicker.Cancel()
						requestSellDragon:FireServer(slot.dragonId)
					end,
				}))
			end,
		}
	end

	-- Hatched dragon tapped: arrows over the habitats it can move into, and
	-- Sell.
	local function startChoice(slot)
		HabitatPicker.Start({
			habitatElement = slot.habitatElement,
			habitatElements = slot.habitatElements,
			habitats = status.habitats,
			item = eggItem(slot, nil),
			extraItems = slot.sellPrice and { sellItem(slot) } or nil,
			onChosen = function(habitatId)
				placingDragonId = slot.dragonId
				requestPlaceEggInHabitat:FireServer(slot.dragonId, habitatId)
			end,
		})
	end

	local function buildListSpec()
		local items = {}
		for _, slot in ipairs(status.slots) do
			if not slot.empty then
				table.insert(items, eggItem(slot, function()
					if slot.ready then
						startChoice(slot)
					else
						showSelection(slot.dragonId)
					end
				end))
			end
		end
		local eggCount = #items
		if eggCount < #status.slots then
			table.insert(items, {
				key = "Buy",
				icon = "Plus",
				label = "Buy",
				onClick = function()
					ShopController.Open("Dragons")
				end,
			})
		end
		local price = status.nestPrice
		if price then
			table.insert(items, {
				key = "Upgrade",
				icon = "ArrowUp",
				top = UIKit.formatNumber(price),
				topIcon = "Gem",
				label = "Upgrade",
				detail = string.format("Nest %d / %d", (status.nests or 1) + 1, status.maxNests or 4),
				onClick = function()
					OptionBar.Close()
					UpgradeScreen.Open(upgradeSpec())
				end,
			})
		end
		table.insert(items, {
			key = "Move",
			icon = "Move",
			label = "Move",
			onClick = function()
				PlacementController.StartMove("Incubator", incubatorId, "IncubatorId", incubatorId)
			end,
		})
		return {
			title = "Incubator",
			subtitle = string.format("%d / %d eggs", eggCount, #status.slots),
			anchor = anchor,
			items = items,
		}
	end

	-- Still hatching: countdown and the Gem speed-up (priced by the time left).
	local function buildHatchingSpec(slot)
		local cost = GemSpeedUp(slot.secondsLeft - (os.clock() - receivedAt))
		return {
			title = slot.displayName,
			subtitle = "Hatching",
			anchor = anchor,
			items = {
				{
					key = "Back",
					icon = "Back",
					label = "Back",
					onClick = function()
						showSelection(nil)
					end,
				},
				eggItem(slot, nil),
				{
					key = "SpeedUp",
					icon = "Gem",
					top = UIKit.formatNumber(cost),
					topIcon = "Gem",
					label = "Speed up",
					dimmed = gems < cost,
					onClick = function()
						if gems < cost then
							Toast.Show("Not enough Gems")
						else
							requestSpeedUpEgg:FireServer(slot.dragonId)
						end
					end,
				},
			},
		}
	end

	buildSpec = function()
		local slot = selectedDragonId and findSlot(selectedDragonId)
		if not slot or slot.ready then
			selectedDragonId = nil
			return buildListSpec()
		end
		return buildHatchingSpec(slot)
	end

	incubatorStatusUpdated.OnClientEvent:Connect(function(newStatus)
		local previousNests = status and status.nests
		status = newStatus
		receivedAt = os.clock()

		if previousNests and newStatus.nests and newStatus.nests > previousNests then
			UpgradeScreen.Close()
			Toast.Show("New nest: one more egg can hatch")
		elseif UpgradeScreen.IsOpen(UPGRADE_KEY) then
			if newStatus.nestPrice then
				UpgradeScreen.Update(upgradeSpec())
			else
				UpgradeScreen.Close()
			end
		end
		if newStatus.upgradeError == "NotEnoughGems" then
			Toast.Show("Not enough Gems")
		end

		if newStatus.placeError then
			placingDragonId = nil
			Toast.Show("That habitat is full")
		elseif placingDragonId and not findSlot(placingDragonId) then
			placingDragonId = nil
			Toast.Show("Your dragon moved into its habitat")
		end

		if newStatus.openRequest then
			HabitatPicker.Cancel()
			selectedDragonId = nil
			OptionBar.Open(OWNER, buildSpec())
		elseif OptionBar.IsShowing(OWNER) then
			OptionBar.Update(OWNER, buildSpec())
		end

		if newStatus.speedUpError == "NotEnoughGems" then
			Toast.Show("Not enough Gems")
		end
	end)

	-- The upgrade window's price button greys out or lights up as the Gem
	-- balance changes.
	updateHud.OnClientEvent:Connect(function(data)
		coins = data.Coins or coins
		local newGems = data.Gems or gems
		if newGems ~= gems then
			gems = newGems
			if status and status.nestPrice and UpgradeScreen.IsOpen(UPGRADE_KEY) then
				UpgradeScreen.Update(upgradeSpec())
			end
		end
	end)

	-- Countdown between server pushes.
	task.spawn(function()
		while true do
			task.wait(1)
			if status and OptionBar.IsShowing(OWNER) then
				OptionBar.Update(OWNER, buildSpec())
			end
		end
	end)
end

return IncubatorController
