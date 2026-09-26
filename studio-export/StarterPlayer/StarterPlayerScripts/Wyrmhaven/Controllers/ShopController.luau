-- Shop: the Shop button opens ShopScreen with four tabs - Dragons (a
-- Common egg per element for Coins, then the Rare hybrids' eggs for Gems),
-- Habitats (starts grid
-- placement; Coins are only spent on Confirm), Buildings (farms, and the
-- second Nursery for Gems, placed the same way) and Decorations (purely
-- decorative, placed the same way too). Cards follow the server's UpdateHud
-- pushes (balances, player level, habitats, farms and nurseries owned), and
-- ShopPurchaseResult reports each dragon/farm/nursery/decoration purchase
-- with a toast. An element's dragons and habitats show locked (padlock +
-- level) until the player reaches its HabitatDefs.UnlockLevel (a hybrid:
-- both its elements', DragonRules.UnlockLevel).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local DecorationDefs = require(Config.DecorationDefs)
local DragonDefs = require(Config.DragonDefs)
local DragonModels = require(Config.DragonModels)
local DragonRules = require(Config.DragonRules)
local FarmDefs = require(Config.FarmDefs)
local GameConstants = require(Config.GameConstants)
local HabitatDefs = require(Config.HabitatDefs)
local HabitatLevels = require(Config.HabitatLevels)

local UI = script.Parent.Parent.UI
local OptionBar = require(UI.OptionBar)
local ShopScreen = require(UI.ShopScreen)
local Toast = require(UI.Toast)
local UIKit = require(UI.UIKit)

local ShopController = {}

local TABS = {
	{ id = "Dragons", label = "Dragons", icon = "Egg", iconColor = Color3.fromRGB(242, 130, 59) },
	{ id = "Habitats", label = "Habitats", icon = "Swatch", iconColor = Color3.fromRGB(107, 158, 110) },
	{ id = "Buildings", label = "Buildings", icon = "Axe", iconColor = Color3.fromRGB(206, 74, 58) },
	{ id = "Decorations", label = "Decorations", icon = "Dot", iconColor = Color3.fromRGB(214, 124, 170) },
}

-- ShopPurchaseResult toasts: success by purchase kind, failure by reason.
local SUCCESS_MESSAGES = {
	Dragon = "Egg added to the Incubator",
	Farm = "Farm under construction",
	Nursery = "New Nursery ready",
	Decoration = "Decoration placed",
}
local FAILURE_MESSAGES = {
	IncubatorFull = "Incubator full: place your hatchlings first",
	InsufficientCoins = "Not enough Coins",
	InsufficientGems = "Not enough Gems",
	TilesOccupied = "Spot taken",
	MaxNurserys = "You already own every Nursery",
	Locked = "Your level is too low for that element",
}

local assets = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets")
local habitatTemplates = assets:FindFirstChild("Habitats")
local decorationTemplates = assets:FindFirstChild("Decorations")
local buildingTemplates = assets:FindFirstChild("Buildings")

-- Dragon cards: still, facing the camera (the dragon faces -Z), seen
-- slightly from above.
local DRAGON_PREVIEW = { Spin = false, Yaw = 150, Rise = 0.35, Fill = 0.86 }

local latestBalance = { Coins = 0, Gems = 0 }
local latestLevel = 1
local latestHabitatCounts = {} -- [element] = count, pushed via UpdateHud (see HudService)
local latestFarmCount = 1
local latestNurseryCount = 1

-- Defs as { id, def } pairs, by SortOrder, then price, then id.
local function sortedDefs(defs)
	local list = {}
	for id, def in pairs(defs) do
		table.insert(list, { id = id, def = def })
	end
	table.sort(list, function(a, b)
		local orderA, orderB = a.def.SortOrder or math.huge, b.def.SortOrder or math.huge
		if orderA ~= orderB then
			return orderA < orderB
		end
		local priceA, priceB = a.def.Price or 0, b.def.Price or 0
		if priceA ~= priceB then
			return priceA < priceB
		end
		return a.id < b.id
	end)
	return list
end

-- Placeholder look of a product without a model yet, built like the server
-- builds the real thing (e.g. DragonService's ball).
local function templatePart(size, color, material, shape)
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	return part
end

-- The level `element` unlocks at if the player hasn't reached it yet, else nil.
local function lockedLevel(element)
	local def = HabitatDefs[element]
	local needed = def and def.UnlockLevel or 1
	return latestLevel < needed and needed or nil
end

local function unlockMessage(level)
	return string.format("Unlocked at level %d", level)
end

-- Every dragon's egg, Commons first then the Rares (DragonDefs SortOrder).
local function dragonCards(requestBuyDragon)
	local cards = {}
	for _, entry in ipairs(sortedDefs(DragonDefs)) do
		local def = entry.def
		local usesGems = def.GemPrice ~= nil
		local price = usesGems and def.GemPrice or def.EggPrice
		if price then
			local balance = usesGems and latestBalance.Gems or latestBalance.Coins
			local needed = DragonRules.UnlockLevel(entry.id)
			local locked = latestLevel < needed and needed or nil
			local kind = DragonRules.RarityName(entry.id)
			table.insert(cards, {
				key = "Dragon:" .. entry.id,
				title = def.DisplayName,
				subtitle = string.format("Income: %d Coins/min", DragonRules.IncomePerMinute(entry.id)),
				footer = locked and unlockMessage(locked) or (kind .. " · comes as an egg"),
				element = entry.id, -- its species: a hybrid's badge shows both elements
				currency = usesGems and "Gem" or "Coin",
				price = price,
				lockedLevel = locked,
				canAfford = balance >= price,
				blockedMessage = locked and unlockMessage(locked) or (usesGems and "Not enough Gems" or "Not enough Coins"),
				-- The baby that hatches from the egg, still, facing the camera.
				makeTemplate = function()
					local model = DragonModels.Get(entry.id, "Baby")
					if model then
						return model:Clone()
					end
					return templatePart(def.StageSizes.Baby, def.StageColors.Baby, nil, Enum.PartType.Ball)
				end,
				preview = DRAGON_PREVIEW,
				onBuy = function()
					requestBuyDragon:FireServer(entry.id)
				end,
			})
		end
	end
	return cards
end

-- A habitat always costs its ShopBaseCost (ShopService.GetHabitatPrice); the
-- card shows what it holds at level 1.
local function habitatCards(placementController)
	local cards = {}
	for _, entry in ipairs(sortedDefs(HabitatDefs)) do
		local def = entry.def
		local owned = latestHabitatCounts[entry.id] or 0
		local price = def.ShopBaseCost or 0
		local locked = lockedLevel(entry.id)
		table.insert(cards, {
			key = "Habitat:" .. entry.id,
			title = def.DisplayName,
			subtitle = string.format("%d dragons · %s Coins max", HabitatLevels.Dragons(1), UIKit.formatNumber(HabitatLevels.Storage(entry.id, 1))),
			footer = locked and unlockMessage(locked) or (owned > 0 and string.format("Owned: %d", owned) or ""),
			element = entry.id,
			currency = "Coin",
			price = price,
			lockedLevel = locked,
			canAfford = latestBalance.Coins >= price,
			blockedMessage = locked and unlockMessage(locked) or "Not enough Coins",
			makeTemplate = function()
				local template = habitatTemplates and habitatTemplates:FindFirstChild(entry.id)
				return template and template:Clone() or templatePart(def.PlatformSize, def.PlatformColor)
			end,
			onBuy = function()
				ShopScreen.Close()
				placementController.StartHabitatPlacement(entry.id, price)
			end,
		})
	end
	return cards
end

-- The second Nursery (BreedingService.BuyNursery): Gems, placed on the grid,
-- ready at once. The card stays, greyed out, once the player has them all.
local function nurseryCard(placementController)
	local price = GameConstants.NurseryGemPrice
	local full = latestNurseryCount >= GameConstants.NurseryMax
	return {
		key = "Building:Nursery",
		title = "Nursery",
		subtitle = "One more pairing at a time",
		footer = string.format("Owned: %d / %d", latestNurseryCount, GameConstants.NurseryMax),
		accentColor = Color3.fromRGB(255, 132, 168),
		currency = "Gem",
		price = price,
		canAfford = not full and latestBalance.Gems >= price,
		blockedMessage = full and "You already own every Nursery" or "Not enough Gems",
		makeTemplate = function()
			local template = buildingTemplates and buildingTemplates:FindFirstChild("NurseryMirror")
			return template and template:Clone() or templatePart(Vector3.new(12, 1, 12), Color3.fromRGB(219, 180, 217))
		end,
		onBuy = function()
			ShopScreen.Close()
			placementController.StartNurseryPlacement(price)
		end,
	}
end

-- Same price as FarmService.Place charges (FarmDefs.GetPrice); buying starts
-- grid placement, like habitats.
local function buildingCards(placementController)
	local price = FarmDefs.GetPrice(latestFarmCount)
	return {
		{
			key = "Building:Farm",
			title = FarmDefs.DisplayName,
			subtitle = "Grows your dragons' Food",
			footer = string.format("Owned: %d", latestFarmCount),
			accentColor = Color3.fromRGB(206, 74, 58),
			currency = "Coin",
			price = price,
			canAfford = latestBalance.Coins >= price,
			blockedMessage = "Not enough Coins",
			makeTemplate = function()
				local template = buildingTemplates and buildingTemplates:FindFirstChild("Farm")
				return template and template:Clone() or templatePart(Vector3.new(12, 1, 12), Color3.fromRGB(196, 164, 92))
			end,
			onBuy = function()
				ShopScreen.Close()
				placementController.StartFarmPlacement(price)
			end,
		},
		nurseryCard(placementController),
	}
end

-- Buying starts grid placement, like habitats: Coins are spent on Confirm.
local function decorationCards(placementController)
	local cards = {}
	for _, entry in ipairs(sortedDefs(DecorationDefs)) do
		local def = entry.def
		local price = def.Price or 0
		table.insert(cards, {
			key = "Decoration:" .. entry.id,
			title = def.DisplayName or entry.id,
			subtitle = (def.TilesX * def.TilesZ > 1) and string.format("%d × %d tiles", def.TilesX, def.TilesZ) or "1 tile",
			footer = "Decorative",
			accentColor = def.AccentColor,
			currency = "Coin",
			price = price,
			canAfford = latestBalance.Coins >= price,
			blockedMessage = "Not enough Coins",
			makeTemplate = function()
				local template = decorationTemplates and decorationTemplates:FindFirstChild(entry.id)
				return template and template:Clone() or templatePart(Vector3.new(def.TilesX * 4, 1, def.TilesZ * 4), def.AccentColor)
			end,
			onBuy = function()
				ShopScreen.Close()
				placementController.StartDecorationPlacement(entry.id, price)
			end,
		})
	end
	return cards
end

function ShopController.Init(remotesFolder, placementController)
	local requestBuyDragon = remotesFolder:WaitForChild("RequestBuyDragon")
	local shopPurchaseResult = remotesFolder:WaitForChild("ShopPurchaseResult")
	local updateHud = remotesFolder:WaitForChild("UpdateHud")

	local function refresh()
		if not ShopScreen.IsOpen() then
			return
		end
		ShopScreen.SetBalance(latestBalance.Coins, latestBalance.Gems)
		local tab = ShopScreen.GetTab()
		if tab == "Dragons" then
			ShopScreen.SetCards(dragonCards(requestBuyDragon))
		elseif tab == "Habitats" then
			ShopScreen.SetCards(habitatCards(placementController))
		elseif tab == "Buildings" then
			ShopScreen.SetCards(buildingCards(placementController))
		elseif tab == "Decorations" then
			ShopScreen.SetCards(decorationCards(placementController))
		end
	end

	ShopScreen.Init({
		tabs = TABS,
		onTabChanged = refresh,
	})

	-- Shop button, at the right end of Roblox's top bar row.
	local buttonGui = UIKit.new("ScreenGui", {
		Name = "ShopButtonGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local buttonHolder = UIKit.new("Frame", {
		Name = "ShopButtonHolder",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(150, 44),
		BackgroundTransparency = 1,
		Parent = buttonGui,
	})
	UIKit.placeInTopbar(buttonHolder, 12)
	-- Opens the Shop on `tabId`, or the tab shown last time (e.g. the
	-- Incubator's + opens the dragons).
	function ShopController.Open(tabId)
		OptionBar.Close()
		ShopScreen.Open(tabId)
		refresh()
	end

	local shopButton = UIKit.button(buttonHolder, { Name = "ShopButton", Variant = "Info", Text = "Shop", TextSize = 24 })
	shopButton.OnActivated(function()
		ShopController.Open()
	end)

	updateHud.OnClientEvent:Connect(function(data)
		latestBalance.Coins = data.Coins or latestBalance.Coins
		latestBalance.Gems = data.Gems or latestBalance.Gems
		latestLevel = data.Level or latestLevel
		latestHabitatCounts = data.HabitatCounts or latestHabitatCounts
		latestFarmCount = data.FarmCount or latestFarmCount
		latestNurseryCount = data.NurseryCount or latestNurseryCount
		refresh()
	end)

	shopPurchaseResult.OnClientEvent:Connect(function(ok, reason, kind)
		local message = ok and SUCCESS_MESSAGES[kind] or FAILURE_MESSAGES[reason]
		if message then
			Toast.Show(message)
		end
		refresh()
	end)
end

return ShopController
