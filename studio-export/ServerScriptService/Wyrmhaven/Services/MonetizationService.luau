-- Real-money monetization (Developer Products + Game Pass). See
-- docs/design/phase2-monetization.md for the proposed prices/contents -
-- NOT yet confirmed with the user. Every id below is a placeholder; do not
-- create the real Developer Products/Game Pass without explicit user
-- confirmation of pricing, and swap these ids for the real ones once they
-- exist on the Roblox game page.
--
-- Purchase idempotency is kept in its own DataStore rather than folded
-- into SaveService's player blob - shop-habitats.md is restructuring that
-- schema (habitatId) in parallel, so this avoids touching a file two
-- agents would otherwise be editing at once.
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local MonetizationService = {}

local EconomyService
local FarmService

local purchaseStore = DataStoreService:GetDataStore("Wyrmhaven_Purchases_v1")

-- TODO: replace with the real Developer Product ids once created on the
-- Roblox game page (amounts match docs/design/phase2-monetization.md).
local GEM_PACK_PRODUCTS = {
	[100001] = 100, -- "Small" pack
	[100002] = 550, -- "Medium" pack
	[100003] = 1200, -- "Large" pack
	[100004] = 2600, -- "Mega" pack
}

-- TODO: replace with the real Game Pass id once created on the Roblox game page.
local STARTER_PACK_GAMEPASS_ID = 900001
local STARTER_PACK_GEMS = 500
local STARTER_PACK_FARM_MULTIPLIER = 2

local cache = {} -- [userId] = purchase record, loaded once per session to avoid a DataStore round trip per receipt

local function loadPurchaseRecord(player)
	local ok, result = pcall(function()
		return purchaseStore:GetAsync(tostring(player.UserId))
	end)
	if not ok then
		warn("[MonetizationService] Failed to load purchase record for " .. player.Name .. ": " .. tostring(result))
		return { ProcessedPurchaseIds = {}, StarterPackGranted = false }
	end
	return result or { ProcessedPurchaseIds = {}, StarterPackGranted = false }
end

local function savePurchaseRecord(player, record)
	local ok, err = pcall(function()
		purchaseStore:SetAsync(tostring(player.UserId), record)
	end)
	if not ok then
		warn("[MonetizationService] Failed to save purchase record for " .. player.Name .. ": " .. tostring(err))
	end
end

function MonetizationService.Init(economyServiceRef, farmServiceRef)
	EconomyService = economyServiceRef
	FarmService = farmServiceRef
end

function MonetizationService.LoadPlayer(player)
	local record = loadPurchaseRecord(player)
	cache[player.UserId] = record
	if record.StarterPackGranted then
		FarmService.SetFoodRateMultiplier(player, STARTER_PACK_FARM_MULTIPLIER)
	end
end

function MonetizationService.RemovePlayer(player)
	cache[player.UserId] = nil
end

local function grantStarterPack(player)
	local record = cache[player.UserId]
	if not record or record.StarterPackGranted then return end

	EconomyService.AddGems(player, STARTER_PACK_GEMS)
	FarmService.SetFoodRateMultiplier(player, STARTER_PACK_FARM_MULTIPLIER)
	-- TODO: once shop-decorations.md exists, also grant one Small decoration here.

	record.StarterPackGranted = true
	savePurchaseRecord(player, record)
end

-- Checked on PlayerAdded (see Server.script) so a Game Pass bought outside
-- the current session is still honored on the next join.
function MonetizationService.CheckStarterPack(player)
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, STARTER_PACK_GAMEPASS_ID)
	end)
	if not ok then
		warn("[MonetizationService] UserOwnsGamePassAsync failed for " .. player.Name .. ": " .. tostring(owns))
		return
	end
	if owns then
		grantStarterPack(player)
	end
end

function MonetizationService.ProcessReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player left before the receipt arrived; Roblox will retry ProcessReceipt later.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not cache[player.UserId] then
		MonetizationService.LoadPlayer(player)
	end
	local record = cache[player.UserId]

	if record.ProcessedPurchaseIds[receiptInfo.PurchaseId] then
		-- Already credited (Roblox replayed the receipt) - grant without re-crediting.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local gems = GEM_PACK_PRODUCTS[receiptInfo.ProductId]
	if not gems then
		warn("[MonetizationService] Unknown ProductId: " .. tostring(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	EconomyService.AddGems(player, gems)
	record.ProcessedPurchaseIds[receiptInfo.PurchaseId] = true
	savePurchaseRecord(player, record)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = MonetizationService.ProcessReceipt

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased or gamePassId ~= STARTER_PACK_GAMEPASS_ID then return end
	if not cache[player.UserId] then
		MonetizationService.LoadPlayer(player)
	end
	grantStarterPack(player)
end)

return MonetizationService
