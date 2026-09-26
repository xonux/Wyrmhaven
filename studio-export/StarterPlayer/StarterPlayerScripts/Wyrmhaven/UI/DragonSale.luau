-- The window confirming a dragon's sale (an UpgradeScreen spec): the dragon,
-- still, its species and rarity, and the player's Coins before -> after, with
-- a red Sell button. Used by the Dragon screen (HabitatUIController) and by
-- the Incubator, where a hatchling can be sold instead of placed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local DragonDefs = require(Config.DragonDefs)
local DragonModels = require(Config.DragonModels)
local DragonRules = require(Config.DragonRules)

local UIKit = require(script.Parent.UIKit)

local DragonSale = {}

local PREVIEW = { Spin = false, Yaw = 150, Rise = 0.35, Fill = 0.86 } -- as the Shop's dragon cards

-- opts: dragonId, species (DragonDefs id), stage, name, price, coins (the
-- player's balance), note (extra line, optional), onConfirm.
function DragonSale.Spec(opts)
	local def = DragonDefs[opts.species]
	local species = def and def.DisplayName or tostring(opts.species)
	local description = string.format("%s · %s\nIt will leave your island for good.", species, DragonRules.RarityName(opts.species))
	if opts.note then
		description ..= "\n" .. opts.note
	end
	return {
		key = "SellDragon:" .. tostring(opts.dragonId),
		previewKey = opts.stage,
		title = string.format("Sell %s?", opts.name or species),
		description = description,
		makeTemplate = function()
			local model = DragonModels.Get(opts.species, opts.stage)
			if model then
				return model:Clone()
			end
			-- No model yet: its placeholder ball.
			local size = def and def.StageSizes[opts.stage] or Vector3.new(3.5, 3.5, 4.5)
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.one * math.min(size.X, size.Y, size.Z)
			ball.Color = def and def.StageColors[opts.stage] or Color3.fromRGB(150, 155, 166)
			ball.Material = Enum.Material.SmoothPlastic
			return ball
		end,
		previewOptions = PREVIEW,
		statsTitle = "Sale",
		stats = {
			{ label = "Your Coins", icon = "Coin", from = UIKit.formatNumber(opts.coins or 0), to = UIKit.formatNumber((opts.coins or 0) + opts.price) },
		},
		currency = "Coin",
		price = opts.price,
		priceText = "+" .. UIKit.formatNumber(opts.price),
		buttonText = "Sell",
		buttonVariant = "Danger",
		onConfirm = opts.onConfirm,
	}
end

return DragonSale
