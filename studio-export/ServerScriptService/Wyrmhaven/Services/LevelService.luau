-- Player level. Shop purchases give no XP by themselves. XP comes from: Coins
-- spent clearing obstacles (IslandService), crops (the Coins they cost, when
-- their Food is harvested - FarmService), habitats (their price, when their
-- construction ends - HabitatService) and hatched dragons (by rarity, when
-- placed in a habitat - IncubatorService, GameConstants.HatchXpByRarity). Callers add it with AddXp
-- once the action succeeded. Leftover XP carries over to the next level,
-- and a big gain can go up several levels at once. Required XP per level: see
-- GameConstants.XpBaseRequired / XpGrowth. Every level gained gives
-- GameConstants.LevelUpGems.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Wyrmhaven.Config.GameConstants)

local LevelService = {}

local progress = {} -- [userId] = { level, xp } (xp gathered towards the next level)
local EconomyService

function LevelService.Init(economyServiceRef)
	EconomyService = economyServiceRef
end

-- XP needed to go from `level` to the next one.
function LevelService.XpRequired(level)
	return math.floor(GameConstants.XpBaseRequired * GameConstants.XpGrowth ^ (level - 1) + 0.5)
end

-- saved: { level, xp } from GetSaveState, or nil for a new player.
function LevelService.InitPlayer(player, saved)
	progress[player.UserId] = {
		level = (saved and saved.level) or 1,
		xp = (saved and saved.xp) or 0,
	}
end

function LevelService.AddXp(player, amount)
	local record = progress[player.UserId]
	if not record or not amount or amount <= 0 then
		return
	end
	record.xp += math.floor(amount)
	local gained = 0
	while record.xp >= LevelService.XpRequired(record.level) do
		record.xp -= LevelService.XpRequired(record.level)
		record.level += 1
		gained += 1
	end
	if gained > 0 and EconomyService then
		EconomyService.AddGems(player, GameConstants.LevelUpGems * gained)
	end
end

-- level, xp towards the next level, xp that next level needs.
function LevelService.GetProgress(player)
	local record = progress[player.UserId]
	local level = record and record.level or 1
	return level, record and record.xp or 0, LevelService.XpRequired(level)
end

function LevelService.GetSaveState(player)
	local record = progress[player.UserId]
	return record and { level = record.level, xp = record.xp } or nil
end

function LevelService.RemovePlayer(player)
	progress[player.UserId] = nil
end

return LevelService
