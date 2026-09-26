-- A gold coin floating and spinning over each of the player's habitats whose
-- Coin storage is full (HabitatService sets the habitat's CoinsFull
-- attribute - never during an upgrade's works, when its Coins can't be
-- harvested). Client-side only. The coin carries its habitat's HabitatId, so
-- tapping it opens (and harvests) the habitat like tapping the habitat.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HabitatCoinController = {}

local COIN_SIZE = 4.5 -- studs across (the GoldCoin model is 10)
local HOVER = 3.5 -- studs above the habitat's TitleHeight
local SPIN_SPEED = 2 -- radians per second
local BOB_SPEED = 2.5
local BOB_HEIGHT = 0.35
local SCAN_SECONDS = 0.2 -- how often full habitats are looked for

local coins = {} -- [habitat part] = its coin Model

function HabitatCoinController.Init()
	local icons = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Icons")
	local template = icons and icons:FindFirstChild("GoldCoin")
	if not template then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "HabitatCoins"
	folder.Parent = Workspace

	local function makeCoin(habitatId)
		local coin = template:Clone()
		coin:ScaleTo(COIN_SIZE / 10)
		for _, part in ipairs(coin:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CastShadow = false
				part:SetAttribute("HabitatId", habitatId)
			end
		end
		coin.Parent = folder
		return coin
	end

	-- Habitats needing a coin: full, and not hidden while being moved.
	local function scan()
		local islands = Workspace:FindFirstChild("Islands")
		local island = islands and islands:FindFirstChild(tostring(Players.LocalPlayer.UserId))
		local wanted = {}
		if island then
			for _, habitat in ipairs(island:GetChildren()) do
				local habitatId = habitat:IsA("BasePart") and habitat:GetAttribute("HabitatId")
				if habitatId and habitat:GetAttribute("CoinsFull") and habitat.LocalTransparencyModifier < 1 then
					wanted[habitat] = true
					if not coins[habitat] then
						coins[habitat] = makeCoin(habitatId)
					end
				end
			end
		end
		for habitat, coin in pairs(coins) do
			if not wanted[habitat] then
				coin:Destroy()
				coins[habitat] = nil
			end
		end
	end

	local sinceScan = SCAN_SECONDS
	RunService.RenderStepped:Connect(function(deltaTime)
		sinceScan += deltaTime
		if sinceScan >= SCAN_SECONDS then
			sinceScan = 0
			scan()
		end
		local t = os.clock()
		for habitat, coin in pairs(coins) do
			local height = (habitat:GetAttribute("TitleHeight") or 6) + HOVER + math.sin(t * BOB_SPEED) * BOB_HEIGHT
			coin:PivotTo(CFrame.new(habitat.Position + Vector3.new(0, height, 0)) * CFrame.Angles(0, t * SPIN_SPEED, 0))
		end
	end)
end

return HabitatCoinController
