-- Farm option bar (OptionBar), one farm at a time. Being built: the countdown
-- and Speed up (Gems), then Finish. Empty: one button per crop the farm's
-- level unlocks (FarmCrops) with its Coin price on top, the Food it gives and
-- its growth time - tapping one pays and plants it. Growing: the countdown
-- and Speed up (Gems ripen it at once). Grown: Collect. Plus Upgrade (UpgradeScreen: the farm with its next
-- crop; its works then show as a countdown with Speed up, then Finish),
-- Move, and Sell for an empty farm when the player owns another one.
-- The server pushes FarmStatusUpdated on request and after every action; the
-- countdowns tick locally in between.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementController = require(script.Parent.PlacementController)

local UI = script.Parent.Parent.UI
local OptionBar = require(UI.OptionBar)
local Toast = require(UI.Toast)
local UIKit = require(UI.UIKit)
local UITheme = require(UI.UITheme)
local UpgradeScreen = require(UI.UpgradeScreen)

local Config = ReplicatedStorage.Wyrmhaven.Config
local FarmCrops = require(Config.FarmCrops)
local FarmDefs = require(Config.FarmDefs)
local GemSpeedUp = require(Config.GemSpeedUp)

local FarmPanelController = {}

local READY_COLOR = Color3.fromRGB(120, 200, 140)
local PLANT_ERRORS = {
	InsufficientCoins = "Not enough Coins",
	Busy = "A crop is already growing",
	Building = "The farm is being built",
	Locked = "Upgrade the farm for that crop",
}
local UPGRADE_ERRORS = {
	InsufficientCoins = "Not enough Coins",
	Building = "The farm is being built",
	MaxLevel = "Every crop is unlocked",
	Busy = "Works are already under way",
}

local assets = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets")
local buildingTemplates = assets:FindFirstChild("Buildings")
local farmTemplate = buildingTemplates and buildingTemplates:FindFirstChild("Farm")
local cropTemplates = assets:FindFirstChild("FarmCrops")

local function findCrop(cropId)
	for _, crop in ipairs(FarmCrops) do
		if crop.Id == cropId then
			return crop
		end
	end
	return nil
end

local function barOwner(farmId)
	return "Farm:" .. tostring(farmId)
end

function FarmPanelController.Init(remotesFolder, hudController)
	local requestCollectFarm = remotesFolder:WaitForChild("RequestCollectFarm")
	local requestPlantCrop = remotesFolder:WaitForChild("RequestPlantCrop")
	local requestFinishFarm = remotesFolder:WaitForChild("RequestFinishFarm")
	local requestSpeedUpFarm = remotesFolder:WaitForChild("RequestSpeedUpFarm")
	local requestSpeedUpCrop = remotesFolder:WaitForChild("RequestSpeedUpCrop")
	local requestSellFarm = remotesFolder:WaitForChild("RequestSellFarm")
	local requestUpgradeFarm = remotesFolder:WaitForChild("RequestUpgradeFarm")
	local farmStatusUpdated = remotesFolder:WaitForChild("FarmStatusUpdated")
	local updateHud = remotesFolder:WaitForChild("UpdateHud")

	local status = nil -- last push for the farm whose bar is open
	local receivedAt = 0
	local coins, gems = 0, 0
	local upgradeStatus = nil -- status of the farm whose upgrade window is open
	local knownLevels = {} -- [farmId] = level last pushed, to announce a new crop

	-- The upgrade window: the farm with its next crop ripe on the field.
	local function upgradeSpec(farmStatus)
		local upgrade = farmStatus.upgrade
		local crop = findCrop(upgrade.cropId)
		return {
			key = barOwner(farmStatus.farmId),
			previewKey = upgrade.level,
			title = string.format("Upgrade the farm to level %d", upgrade.level),
			description = crop and string.format("New crop: %s (+%s Food)\nWorks: %s",
				crop.DisplayName or crop.Id, UIKit.formatNumber(FarmDefs.FoodFor(crop, farmStatus.foodMultiplier)),
				UIKit.formatShortDuration(upgrade.duration or crop.Duration)) or "",
			makeTemplate = function()
				if not farmTemplate then
					return nil
				end
				local template = farmTemplate:Clone()
				-- Crop models are laid out for the template's spot already.
				local cropModel = cropTemplates and cropTemplates:FindFirstChild(upgrade.cropId)
				if cropModel then
					cropModel:Clone().Parent = template:FindFirstChild("Visual") or template
				end
				return template
			end,
			stats = {
				{ label = "Crops available", icon = "Food", from = farmStatus.level, to = upgrade.level },
			},
			currency = "Coin",
			price = upgrade.cost,
			buttonText = "Upgrade",
			canAfford = coins >= upgrade.cost,
			blockedMessage = "Not enough Coins",
			onConfirm = function()
				requestUpgradeFarm:FireServer(farmStatus.farmId)
			end,
		}
	end

	-- Seconds left on a countdown the server sent at receivedAt.
	local function remaining(seconds)
		return math.max(0, seconds - (os.clock() - receivedAt))
	end

	local function isShowing()
		return status ~= nil and OptionBar.IsShowing(barOwner(status.farmId))
	end

	local function constructionItems(farmId)
		local secondsLeft = remaining(status.buildSecondsLeft)
		if secondsLeft <= 0 then
			return {
				{
					key = "Finish",
					icon = "Check",
					palette = "Confirm",
					top = "Ready",
					topColor = READY_COLOR,
					label = "Finish",
					onClick = function()
						requestFinishFarm:FireServer(farmId)
					end,
				},
			}
		end
		local cost = GemSpeedUp(secondsLeft)
		return {
			{
				key = "Building",
				icon = "Axe",
				top = UIKit.formatDuration(secondsLeft),
				label = "Construction",
				onClick = function()
					Toast.Show("Built in " .. UIKit.formatShortDuration(secondsLeft))
				end,
			},
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
						requestSpeedUpFarm:FireServer(farmId)
					end
				end,
			},
		}
	end

	local function cropItems(farmId)
		local items = {}
		for index, crop in ipairs(FarmCrops) do
			if index > (status.level or 1) then
				break -- the farm's next levels unlock the rest
			end
			local affordable = coins >= crop.Price
			table.insert(items, {
				key = "Crop:" .. crop.Id,
				icon = "Food",
				top = UIKit.formatNumber(crop.Price),
				topIcon = "Coin",
				-- With the player's Food bonus, exactly as the server locks it in at
				-- planting - never the bare value from FarmCrops.
				label = "+" .. UIKit.formatNumber(FarmDefs.FoodFor(crop, status.foodMultiplier)),
				detail = UIKit.formatShortDuration(crop.Duration),
				dimmed = not affordable,
				onClick = function()
					if affordable then
						requestPlantCrop:FireServer(farmId, crop.Id)
					else
						Toast.Show("Not enough Coins")
					end
				end,
			})
		end
		return items
	end

	local function buildSpec()
		local farmId = status.farmId
		local planted = status.planted
		local items, subtitle
		if status.buildSecondsLeft then
			subtitle = remaining(status.buildSecondsLeft) > 0 and "Under construction" or "Construction done"
			items = constructionItems(farmId)
		elseif not planted then
			subtitle = "Pick a crop"
			items = cropItems(farmId)
		elseif remaining(planted.secondsLeft) > 0 then
			subtitle = "Growing"
			local secondsLeft = remaining(planted.secondsLeft)
			local cost = GemSpeedUp(secondsLeft)
			items = {
				{
					key = "Growing",
					icon = "Food",
					top = UIKit.formatDuration(secondsLeft),
					label = "+" .. UIKit.formatNumber(planted.food),
					detail = "In progress",
					onClick = function()
						Toast.Show("Harvest in " .. UIKit.formatShortDuration(secondsLeft))
					end,
				},
				{
					key = "CropSpeedUp",
					icon = "Gem",
					top = UIKit.formatNumber(cost),
					topIcon = "Gem",
					label = "Speed up",
					dimmed = gems < cost,
					onClick = function()
						if gems < cost then
							Toast.Show("Not enough Gems")
						else
							requestSpeedUpCrop:FireServer(farmId)
						end
					end,
				},
			}
		else
			subtitle = "Harvest ready"
			items = {
				{
					key = "Harvest",
					icon = "Food",
					palette = "Confirm",
					top = "Ready",
					label = "+" .. UIKit.formatNumber(planted.food),
					detail = "Collect",
					onClick = function()
						requestCollectFarm:FireServer(farmId)
					end,
				},
			}
		end

		if not status.buildSecondsLeft then
			subtitle = string.format("Level %d · %s", status.level or 1, subtitle)
			-- A Food bonus (the Starter Pack) is worth saying out loud: it is the
			-- reason a crop gives more than the number written in FarmCrops.
			if (status.foodMultiplier or 1) > 1 then
				subtitle = subtitle .. string.format(" - Food x%s", status.foodMultiplier)
			end
			local worksLeft = status.upgradeSecondsLeft and remaining(status.upgradeSecondsLeft)
			if worksLeft and worksLeft > 0 then
				-- Upgrade works: countdown and Gem speed-up (the farm keeps farming).
				local cost = GemSpeedUp(worksLeft)
				table.insert(items, {
					key = "Upgrading",
					icon = "Axe",
					top = UIKit.formatDuration(worksLeft),
					label = "Works",
					onClick = function()
						Toast.Show(string.format("Level %d in %s", (status.level or 1) + 1, UIKit.formatShortDuration(worksLeft)))
					end,
				})
				table.insert(items, {
					key = "UpgradeSpeedUp",
					icon = "Gem",
					top = UIKit.formatNumber(cost),
					topIcon = "Gem",
					label = "Speed up",
					dimmed = gems < cost,
					onClick = function()
						if gems < cost then
							Toast.Show("Not enough Gems")
						else
							requestSpeedUpFarm:FireServer(farmId)
						end
					end,
				})
			elseif worksLeft then
				table.insert(items, {
					key = "UpgradeFinish",
					icon = "Check",
					palette = "Confirm",
					top = "Ready",
					topColor = READY_COLOR,
					label = "Finish",
					onClick = function()
						requestFinishFarm:FireServer(farmId)
					end,
				})
			elseif status.upgrade then
				table.insert(items, {
					key = "Upgrade",
					icon = "ArrowUp",
					top = "Lv " .. tostring(status.upgrade.level),
					topColor = UITheme.Colors.Accent,
					label = "Upgrade",
					onClick = function()
						upgradeStatus = status
						OptionBar.Close()
						UpgradeScreen.Open(upgradeSpec(status))
					end,
				})
			else
				table.insert(items, {
					key = "Upgrade",
					icon = "ArrowUp",
					top = "Lv MAX",
					topColor = UITheme.Colors.Accent,
					label = "Upgrade",
					dimmed = true,
					onClick = function()
						Toast.Show("Every crop is unlocked")
					end,
				})
			end
		end
		table.insert(items, {
			key = "Move",
			icon = "Move",
			label = "Move",
			onClick = function()
				PlacementController.StartMove("Farm", farmId, "FarmId", farmId)
			end,
		})
		if status.canSell then
			table.insert(items, {
				key = "Sell",
				icon = "Coin",
				palette = "Danger",
				top = "+" .. UIKit.formatNumber(status.sellValue or 0),
				label = "Sell",
				onClick = function()
					requestSellFarm:FireServer(farmId)
					-- The farm stops existing once sold, so no refresh will ever come.
					OptionBar.Close()
				end,
			})
		end
		return {
			title = FarmDefs.DisplayName,
			subtitle = subtitle,
			anchor = { attribute = "FarmId", value = farmId },
			items = items,
		}
	end

	farmStatusUpdated.OnClientEvent:Connect(function(newStatus)
		if newStatus.speedUpError == "NotEnoughGems" then
			Toast.Show("Not enough Gems")
		end
		if newStatus.plantError and PLANT_ERRORS[newStatus.plantError] then
			Toast.Show(PLANT_ERRORS[newStatus.plantError])
		end
		if newStatus.upgradeError and UPGRADE_ERRORS[newStatus.upgradeError] then
			Toast.Show(UPGRADE_ERRORS[newStatus.upgradeError])
		end
		local previousLevel = knownLevels[newStatus.farmId]
		knownLevels[newStatus.farmId] = newStatus.level
		local upgradeOwner = barOwner(newStatus.farmId)
		if previousLevel and newStatus.level and newStatus.level > previousLevel then
			UpgradeScreen.Close()
			local crop = FarmCrops[newStatus.level]
			Toast.Show(string.format("New crop unlocked: %s", crop and (crop.DisplayName or crop.Id) or ""))
		elseif UpgradeScreen.IsOpen(upgradeOwner) then
			if newStatus.upgradeSecondsLeft then
				UpgradeScreen.Close()
				Toast.Show("Upgrade works started")
			elseif newStatus.upgrade then
				upgradeStatus = newStatus
				UpgradeScreen.Update(upgradeSpec(newStatus))
			else
				UpgradeScreen.Close()
			end
		end

		local owner = barOwner(newStatus.farmId)
		if newStatus.openRequest then
			status, receivedAt = newStatus, os.clock()
			OptionBar.Open(owner, buildSpec())
		elseif OptionBar.IsShowing(owner) then
			status, receivedAt = newStatus, os.clock()
			-- Before the update, which removes the Collect button the icons fly from.
			if newStatus.collected and newStatus.collected > 0 then
				hudController.PlayCollect("Food", "Food", OptionBar.GetItemButton("Harvest"), newStatus.collected)
			end
			OptionBar.Update(owner, buildSpec())
		end
	end)

	-- Prices grey out or light up as the balances change.
	updateHud.OnClientEvent:Connect(function(data)
		local newCoins = data.Coins or coins
		if newCoins ~= coins and upgradeStatus and upgradeStatus.upgrade and UpgradeScreen.IsOpen(barOwner(upgradeStatus.farmId)) then
			coins = newCoins
			UpgradeScreen.Update(upgradeSpec(upgradeStatus))
		end
		coins = newCoins
		gems = data.Gems or gems
		if isShowing() then
			OptionBar.Update(barOwner(status.farmId), buildSpec())
		end
	end)

	-- Countdowns between server pushes (and the switch to Finish / Collect at zero).
	task.spawn(function()
		while true do
			task.wait(1)
			if isShowing() and (status.buildSecondsLeft or status.upgradeSecondsLeft or status.planted) then
				OptionBar.Update(barOwner(status.farmId), buildSpec())
			end
		end
	end)
end

return FarmPanelController
