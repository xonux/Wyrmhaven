-- Chat commands for testing. Only the place's creator can use them - or
-- anyone in a Studio test session.
--   /resetdata              deletes the sender's save (SaveService.ResetPlayer)
--                           and kicks them: the next join is a brand new
--                           island. Purchase records (MonetizationService's own
--                           DataStore) are left alone.
--   /give <what> <amount>   coins | gems | food | xp, e.g.
--                           "/give coins 5000". Amount defaults to 1000.
--   /give egg <species>     an egg of that DragonDefs species in the
--                           Incubator, e.g. "/give egg FireWater".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local DragonDefs = require(ReplicatedStorage.Wyrmhaven.Config.DragonDefs)

local DevCommands = {}

local KICK_MESSAGE = "Data wiped: rejoin to start from scratch."
local DEFAULT_AMOUNT = 1000
local RESOURCE_NAMES = {
	coins = "Coins", coin = "Coins", gold = "Coins",
	gems = "Gems", gem = "Gems",
	food = "Food",
	xp = "Xp", exp = "Xp",
	egg = "Egg", eggs = "Egg",
}

local function isAllowed(player)
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

-- A species id typed in any case ("firewater" -> "FireWater").
local function findSpecies(name)
	if not name then
		return nil
	end
	local wanted = string.lower(name)
	for id in pairs(DragonDefs) do
		if string.lower(id) == wanted then
			return id
		end
	end
	return nil
end

local function addCommand(name, alias, handler)
	local command = Instance.new("TextChatCommand")
	command.Name = name
	command.PrimaryAlias = alias
	command.Parent = TextChatService
	command.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if player and isAllowed(player) then
			handler(player, string.split(string.lower(unfilteredText or ""), " "))
		end
	end)
end

-- services: SaveService, EconomyService, FarmService, LevelService,
-- IncubatorService, HudService.
function DevCommands.Init(services)
	addCommand("WyrmhavenResetData", "/resetdata", function(player)
		if services.SaveService.ResetPlayer(player) then
			player:Kick(KICK_MESSAGE)
		end
	end)

	addCommand("WyrmhavenGive", "/give", function(player, words)
		local what = RESOURCE_NAMES[words[2] or ""]
		if what == "Egg" then
			local species = findSpecies(words[3])
			if not species or not services.IncubatorService.AddEgg(player, species) then
				warn("[Wyrmhaven] /give egg: unknown species or Incubator full: " .. tostring(words[3]))
			end
			return
		end
		local amount = math.floor(tonumber(words[3]) or DEFAULT_AMOUNT)
		if not what or amount <= 0 then
			warn("[Wyrmhaven] usage: /give coins|gems|food|xp <amount>, or /give egg <species>")

			return
		end
		if what == "Coins" then
			services.EconomyService.AddCoins(player, amount)
		elseif what == "Gems" then
			services.EconomyService.AddGems(player, amount)
		elseif what == "Food" then
			services.FarmService.AddFood(player, amount)
		elseif what == "Xp" then
			services.LevelService.AddXp(player, amount)
		end
		services.HudService.PushUpdate(player)
	end)
end

return DevCommands
