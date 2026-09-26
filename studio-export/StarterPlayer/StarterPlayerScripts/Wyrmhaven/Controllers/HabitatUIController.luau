-- Habitat option bar (OptionBar) and DragonScreen, wired to the server:
-- HabitatStatusUpdated / DragonStatusUpdated pushes open or refresh them, and
-- their buttons fire the matching Request* remotes. Display only - every state
-- change comes back from the server as a new status push. The DragonScreen's
-- Move sends the dragon to another habitat of its element, chosen on the
-- island (HabitatPicker), like a hatchling leaving the Incubator; its Sell
-- sells the dragon once confirmed (DragonSale window). The bar's
-- Upgrade opens UpgradeScreen (the next level's cost, storage and
-- dragons); its works then show in the bar (countdown, Speed up, Finish),
-- and Collect shows the Coins stored against the habitat's storage. Tapping
-- the habitat harvests them (the server sends `collected` with the push that
-- opens the bar), except during an upgrade's works.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HabitatPicker = require(script.Parent.HabitatPicker)
local PlacementController = require(script.Parent.PlacementController)

local UI = script.Parent.Parent.UI
local OptionBar = require(UI.OptionBar)
local DragonSale = require(UI.DragonSale)
local DragonScreen = require(UI.DragonScreen)
local Toast = require(UI.Toast)
local UIKit = require(UI.UIKit)
local UITheme = require(UI.UITheme)
local UpgradeScreen = require(UI.UpgradeScreen)

local HabitatDefs = require(ReplicatedStorage.Wyrmhaven.Config.HabitatDefs)
local GemSpeedUp = require(ReplicatedStorage.Wyrmhaven.Config.GemSpeedUp)

local HabitatUIController = {}

local LIVE_REFRESH_SECONDS = 1 -- matches GameConstants.IncomeTickSeconds
local READY_COLOR = Color3.fromRGB(120, 200, 140)
local MOVE_ERRORS = {
	NoRoom = "That habitat is full",
	Breeding = "This dragon is at the Nursery",
}
local SELL_ERRORS = {
	Breeding = "This dragon is at the Nursery",
	NotForSale = "This dragon can't be sold",
}
local UPGRADE_ERRORS = {
	InsufficientCoins = "Not enough Coins",
	Busy = "Works are already under way",
	Building = "The habitat is still being built",
	MaxLevel = "Maximum level reached",
}

local habitatTemplates = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Habitats")

local function barOwner(habitatId)
	return "Habitat:" .. tostring(habitatId)
end

function HabitatUIController.Init(remotesFolder, hudController)
	local habitatStatusUpdated = remotesFolder:WaitForChild("HabitatStatusUpdated")
	local dragonStatusUpdated = remotesFolder:WaitForChild("DragonStatusUpdated")
	local updateHud = remotesFolder:WaitForChild("UpdateHud")
	local requestInteractHabitat = remotesFolder:WaitForChild("RequestInteractHabitat")
	local requestInteractDragon = remotesFolder:WaitForChild("RequestInteractDragon")
	local requestCollectHabitatIncome = remotesFolder:WaitForChild("RequestCollectHabitatIncome")
	local requestSellHabitat = remotesFolder:WaitForChild("RequestSellHabitat")
	local requestFeedDragon = remotesFolder:WaitForChild("RequestFeedDragon")
	local requestRenameDragon = remotesFolder:WaitForChild("RequestRenameDragon")
	local requestFinishHabitat = remotesFolder:WaitForChild("RequestFinishHabitat")
	local requestSpeedUpHabitat = remotesFolder:WaitForChild("RequestSpeedUpHabitat")
	local requestMoveDragon = remotesFolder:WaitForChild("RequestMoveDragon")
	local requestUpgradeHabitat = remotesFolder:WaitForChild("RequestUpgradeHabitat")
	local requestSellDragon = remotesFolder:WaitForChild("RequestSellDragon")
	local dragonSold = remotesFolder:WaitForChild("DragonSold")

	local gems, coins = 0, 0
	local shownHabitatId = nil
	local movingDragonId = nil -- sent to another habitat, waiting for the server's answer
	local upgradeStatus = nil -- status of the habitat whose upgrade window is open
	local knownLevels = {} -- [habitatId] = level last pushed, to celebrate a new one

	-- The upgrade window for the habitat's next level.
	local function upgradeSpec(status)
		local def = HabitatDefs[status.element]
		local upgrade = status.upgrade
		local stats = {
			{ label = "Max Coin storage", icon = "Coin", from = UIKit.formatNumber(status.storage), to = UIKit.formatNumber(upgrade.storage) },
		}
		if upgrade.dragons > status.capacity then
			table.insert(stats, 1, { label = "Dragons max", icon = "Egg", from = status.capacity, to = upgrade.dragons })
		end
		return {
			key = barOwner(status.habitatId),
			previewKey = upgrade.level,
			title = string.format("Upgrade the habitat to level %d", upgrade.level),
			description = string.format("%s\nWorks: %s", def and def.DisplayName or status.element, UIKit.formatShortDuration(upgrade.duration)),
			makeTemplate = function()
				local template = habitatTemplates and habitatTemplates:FindFirstChild(status.element)
				return template and template:Clone()
			end,
			stats = stats,
			currency = "Coin",
			price = upgrade.cost,
			buttonText = "Upgrade",
			canAfford = coins >= upgrade.cost,
			blockedMessage = "Not enough Coins",
			onConfirm = function()
				requestUpgradeHabitat:FireServer(status.habitatId)
			end,
		}
	end

	updateHud.OnClientEvent:Connect(function(data)
		gems = data.Gems or gems
		local newCoins = data.Coins or coins
		if newCoins ~= coins then
			coins = newCoins
			-- The window's price button greys out or lights up with the balance.
			if upgradeStatus and upgradeStatus.upgrade and UpgradeScreen.IsOpen(barOwner(upgradeStatus.habitatId)) then
				UpgradeScreen.Update(upgradeSpec(upgradeStatus))
			end
		end
	end)

	-- Arrows over the other habitats the dragon can live in, with room. False
	-- (and a toast saying why) when there's none.
	local function startMove(data)
		return HabitatPicker.Start({
			habitatElement = data.habitatElement,
			habitatElements = data.habitatElements,
			habitats = data.habitats,
			fromHabitatId = data.habitatId,
			item = {
				key = "Dragon" .. data.id,
				dragonId = data.id,
				top = "Lv " .. tostring(data.level or 1),
				topColor = UITheme.Colors.Accent,
				label = data.name,
			},
			onChosen = function(habitatId)
				movingDragonId = data.id
				requestMoveDragon:FireServer(data.id, habitatId)
			end,
		})
	end

	local function buildSpec(status)
		local def = HabitatDefs[status.element]

		-- Under construction: countdown and Gem speed-up (refreshed every second
		-- by the live refresh below), then Finish - the player's final tap.
		if status.buildSecondsLeft then
			local secondsLeft = status.buildSecondsLeft
			local items
			if secondsLeft > 0 then
				local cost = GemSpeedUp(secondsLeft)
				items = {
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
								requestSpeedUpHabitat:FireServer(status.habitatId)
							end
						end,
					},
				}
			else
				items = {
					{
						key = "Finish",
						icon = "Check",
						palette = "Confirm",
						top = "Ready",
						topColor = READY_COLOR,
						label = "Finish",
						onClick = function()
							requestFinishHabitat:FireServer(status.habitatId)
						end,
					},
				}
			end
			table.insert(items, {
				key = "Move",
				icon = "Move",
				label = "Move",
				onClick = function()
					PlacementController.StartMove("Habitat", status.habitatId, "HabitatId", status.habitatId)
				end,
			})
			return {
				title = def and def.DisplayName or status.element,
				subtitle = secondsLeft > 0 and "Under construction" or "Construction done",
				anchor = { attribute = "HabitatId", value = status.habitatId },
				items = items,
			}
		end
		local items = {}
		local upgradeLeft = status.upgradeSecondsLeft
		if upgradeLeft and upgradeLeft > 0 then
			-- Upgrade works: countdown and Gem speed-up (the habitat keeps working).
			local cost = GemSpeedUp(upgradeLeft)
			table.insert(items, {
				key = "Upgrading",
				icon = "Axe",
				top = UIKit.formatDuration(upgradeLeft),
				label = "Works",
				onClick = function()
					Toast.Show(string.format("Level %d in %s", (status.level or 1) + 1, UIKit.formatShortDuration(upgradeLeft)))
				end,
			})
			table.insert(items, {
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
						requestSpeedUpHabitat:FireServer(status.habitatId)
					end
				end,
			})
		elseif upgradeLeft then
			table.insert(items, {
				key = "Finish",
				icon = "Check",
				palette = "Confirm",
				top = "Ready",
				topColor = READY_COLOR,
				label = "Finish",
				onClick = function()
					requestFinishHabitat:FireServer(status.habitatId)
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
					Toast.Show("Maximum level reached")
				end,
			})
		end
		table.insert(items, {
			key = "Move",
			icon = "Move",
			label = "Move",
			onClick = function()
				PlacementController.StartMove("Habitat", status.habitatId, "HabitatId", status.habitatId)
			end,
		})

		for _, info in ipairs(status.dragons) do
			table.insert(items, {
				key = "Dragon" .. info.id,
				dragonId = info.id,
				top = "Lv " .. tostring(info.level or 1),
				topColor = UITheme.Colors.Accent,
				label = info.displayName,
				badge = info.isBreeding and "Nursery" or nil,
				onClick = function()
					requestInteractDragon:FireServer(info.id)
				end,
			})
		end

		-- Coins stored in the habitat, out of what it can hold (locked during
		-- an upgrade's works, while they keep piling up).
		local stored = status.storedCoins or 0
		local upgrading = status.upgradeSecondsLeft ~= nil
		table.insert(items, {
			key = "Coins",
			icon = "Coin",
			top = UIKit.formatNumber(stored),
			topColor = stored >= (status.storage or math.huge) and READY_COLOR or nil,
			label = "Collect",
			detail = "max " .. UIKit.formatNumber(status.storage or 0),
			dimmed = upgrading,
			onClick = function()
				if upgrading then
					Toast.Show("Can't collect during the works")
				elseif stored > 0 then
					requestCollectHabitatIncome:FireServer(status.habitatId)
				else
					Toast.Show("Nothing to collect yet")
				end
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
					requestSellHabitat:FireServer(status.habitatId)
					-- The habitat stops existing once sold, so no refresh will ever come.
					OptionBar.Close()
				end,
			})
		end

		return {
			title = def and def.DisplayName or status.element,
			subtitle = string.format("Level %d · %d / %d dragons", status.level or 1, #status.dragons, status.capacity),
			anchor = { attribute = "HabitatId", value = status.habitatId },
			items = items,
		}
	end

	DragonScreen.Init({
		onFeed = function(dragonId)
			requestFeedDragon:FireServer(dragonId)
		end,
		onRename = function(dragonId, newName)
			requestRenameDragon:FireServer(dragonId, newName)
		end,
		-- The screen stays open when no habitat can take the dragon.
		onMove = function(data)
			if startMove(data) then
				DragonScreen.Close()
			end
		end,
		onBack = function(habitatId)
			DragonScreen.Close()
			if habitatId then
				requestInteractHabitat:FireServer(habitatId)
			end
		end,
		-- Confirmed in a window; then the screen closes and the server opens
		-- the habitat's bar again.
		onSell = function(data)
			UpgradeScreen.Open(DragonSale.Spec({
				dragonId = data.id,
				species = data.element,
				stage = data.stage,
				name = data.name,
				price = data.sellPrice,
				coins = coins,
				onConfirm = function()
					UpgradeScreen.Close()
					DragonScreen.Close()
					requestSellDragon:FireServer(data.id)
				end,
			}))
		end,
	}, updateHud)

	-- Any sale (here or a hatchling from the Incubator), confirmed by the server.
	dragonSold.OnClientEvent:Connect(function(_, soldFor)
		Toast.Show(string.format("Dragon sold: +%s Coins", UIKit.formatNumber(soldFor or 0)))
	end)

	habitatStatusUpdated.OnClientEvent:Connect(function(status)
		if status.speedUpError == "NotEnoughGems" then
			Toast.Show("Not enough Gems")
		end
		if status.upgradeError and UPGRADE_ERRORS[status.upgradeError] then
			Toast.Show(UPGRADE_ERRORS[status.upgradeError])
		end
		if status.collectError == "Upgrading" then
			Toast.Show("Can't collect during the works")
		end
		local previousLevel = knownLevels[status.habitatId]
		knownLevels[status.habitatId] = status.level
		if previousLevel and status.level and status.level > previousLevel then
			Toast.Show(string.format("Habitat upgraded: level %d", status.level))
		end
		-- The upgrade window follows its habitat: closed once the works start.
		if UpgradeScreen.IsOpen(barOwner(status.habitatId)) then
			if status.upgradeSecondsLeft then
				UpgradeScreen.Close()
				Toast.Show("Upgrade works started")
			elseif status.upgrade then
				upgradeStatus = status
				UpgradeScreen.Update(upgradeSpec(status))
			else
				UpgradeScreen.Close()
			end
		end
		-- A moved dragon arrived: the server opens its new habitat's bar.
		if movingDragonId and status.openRequest then
			for _, info in ipairs(status.dragons or {}) do
				if info.id == movingDragonId then
					movingDragonId = nil
					Toast.Show("Your dragon moved into its new habitat")
					break
				end
			end
		end
		local owner = barOwner(status.habitatId)
		if status.openRequest then
			shownHabitatId = status.habitatId
			OptionBar.Open(owner, buildSpec(status))
			-- The tap that opened the bar harvested the habitat's Coins.
			if status.collected and status.collected > 0 then
				hudController.PlayCollect("Coins", "Coin", OptionBar.GetItemButton("Coins"), status.collected)
			end
		elseif OptionBar.IsShowing(owner) then
			OptionBar.Update(owner, buildSpec(status))
			if status.collected and status.collected > 0 then
				hudController.PlayCollect("Coins", "Coin", OptionBar.GetItemButton("Coins"), status.collected)
			end
		end
	end)

	dragonStatusUpdated.OnClientEvent:Connect(function(status)
		if status.moveError then
			movingDragonId = nil
			Toast.Show(MOVE_ERRORS[status.moveError] or "Can't move that dragon")
		end
		if status.sellError then
			Toast.Show(SELL_ERRORS[status.sellError] or "Can't sell that dragon")
		end
		if status.openRequest then
			OptionBar.Close()
			DragonScreen.Open(status)
		else
			DragonScreen.Update(status)
		end
	end)

	-- Keeps pending Coins moving while the bar/screen stays open. The `true`
	-- asks for a silent push, which never reopens something the player closed
	-- while the request was in flight.
	task.spawn(function()
		while true do
			task.wait(LIVE_REFRESH_SECONDS)
			local dragonId = DragonScreen.GetCurrent()
			if dragonId then
				requestInteractDragon:FireServer(dragonId, true)
			elseif shownHabitatId and OptionBar.IsShowing(barOwner(shownHabitatId)) then
				requestInteractHabitat:FireServer(shownHabitatId, true)
			end
		end
	end)
end

return HabitatUIController
