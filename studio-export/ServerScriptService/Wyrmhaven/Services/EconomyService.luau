local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)

local EconomyService = {}

local balances = {} -- [userId] = { Coins = n, Gems = n }

local function getRecord(player)
	return balances[player.UserId]
end

local function refreshDebugAttributes(player)
	-- Lightweight visibility for testing/HUD until a proper HUD reads GetBalance via RemoteEvent.
	local record = getRecord(player)
	if not record then return end
	player:SetAttribute("Coins", record.Coins)
	player:SetAttribute("Gems", record.Gems)
end

function EconomyService.InitPlayer(player, coinsOverride, gemsOverride)
	balances[player.UserId] = {
		Coins = coinsOverride or GameConstants.StartingCoins,
		Gems = gemsOverride or GameConstants.StartingGems,
	}
	refreshDebugAttributes(player)
end

function EconomyService.RemovePlayer(player)
	balances[player.UserId] = nil
end

function EconomyService.GetBalance(player)
	local record = getRecord(player)
	if not record then return { Coins = 0, Gems = 0 } end
	return { Coins = record.Coins, Gems = record.Gems }
end

function EconomyService.AddCoins(player, amount)
	local record = getRecord(player)
	if not record then return end
	record.Coins += amount
	refreshDebugAttributes(player)
end

function EconomyService.AddGems(player, amount)
	local record = getRecord(player)
	if not record then return end
	record.Gems += amount
	refreshDebugAttributes(player)
end

function EconomyService.TrySpendCoins(player, amount)
	local record = getRecord(player)
	if not record or record.Coins < amount then return false end
	record.Coins -= amount
	refreshDebugAttributes(player)
	return true
end

function EconomyService.TrySpendGems(player, amount)
	local record = getRecord(player)
	if not record or record.Gems < amount then return false end
	record.Gems -= amount
	refreshDebugAttributes(player)
	return true
end

return EconomyService
