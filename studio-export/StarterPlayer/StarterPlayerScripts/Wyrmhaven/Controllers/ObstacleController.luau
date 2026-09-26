-- Obstacle option bar (OptionBar): the trees and rocks on the island's outer
-- tiles. Clear pays the Coin price and starts the timer, which Gems can skip
-- (Speed up). Once it's over the obstacle waits for the player's final tap on
-- Finish: then it disappears, its tiles become buildable and the player
-- gets XP (IslandService). One clearing at a time, until that tap. The
-- countdown ticks locally between server pushes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent.UI
local OptionBar = require(UI.OptionBar)
local Toast = require(UI.Toast)
local UIKit = require(UI.UIKit)

local Config = ReplicatedStorage.Wyrmhaven.Config
local ObstacleDefs = require(Config.ObstacleDefs)
local GemSpeedUp = require(Config.GemSpeedUp)

local ObstacleController = {}

local OWNER_PREFIX = "Obstacle:"
local READY_COLOR = Color3.fromRGB(120, 200, 140)
local ERRORS = {
	InsufficientCoins = "Not enough Coins",
	NotEnoughGems = "Not enough Gems",
	Busy = "Finish the clearing already under way",
}

function ObstacleController.Init(remotesFolder)
	local requestClearObstacle = remotesFolder:WaitForChild("RequestClearObstacle")
	local requestFinishObstacle = remotesFolder:WaitForChild("RequestFinishObstacle")
	local requestSpeedUpObstacle = remotesFolder:WaitForChild("RequestSpeedUpObstacle")
	local obstacleStatusUpdated = remotesFolder:WaitForChild("ObstacleStatusUpdated")
	local updateHud = remotesFolder:WaitForChild("UpdateHud")

	local status = nil -- the obstacle whose bar is (or was last) shown
	local receivedAt = 0
	local coins, gems = 0, 0

	local function owner()
		return OWNER_PREFIX .. status.obstacleId
	end

	local function isShowing()
		return status ~= nil and OptionBar.IsShowing(owner())
	end

	local function secondsLeft()
		return math.max(0, (status.secondsLeft or 0) - (os.clock() - receivedAt))
	end

	-- This obstacle is being cleared: countdown and speed-up, then Finish.
	local function clearingItems()
		local remaining = secondsLeft()
		if remaining <= 0 then
			return "Clearing done", {
				{
					key = "Finish",
					icon = "Check",
					palette = "Confirm",
					top = "Ready",
					topColor = READY_COLOR,
					label = "Finish",
					onClick = function()
						requestFinishObstacle:FireServer(status.obstacleId)
					end,
				},
			}
		end
		local cost = GemSpeedUp(remaining)
		return "Clearing", {
			{
				key = "Clearing",
				icon = "Axe",
				top = UIKit.formatDuration(remaining),
				label = "In progress",
				onClick = function()
					Toast.Show("Cleared in " .. UIKit.formatShortDuration(remaining))
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
						Toast.Show(ERRORS.NotEnoughGems)
					else
						requestSpeedUpObstacle:FireServer(status.obstacleId)
					end
				end,
			},
		}
	end

	local function buildSpec()
		local def = ObstacleDefs[status.kind]
		local subtitle, items
		if status.clearingId == status.obstacleId then
			subtitle, items = clearingItems()
		else
			local busy = status.clearingId ~= nil
			local affordable = coins >= status.price
			subtitle = "Clear it to build here"
			items = {
				{
					key = "Clear",
					icon = "Axe",
					top = UIKit.formatNumber(status.price),
					topIcon = "Coin",
					label = "Clear",
					detail = UIKit.formatShortDuration(status.duration),
					dimmed = busy or not affordable,
					onClick = function()
						if busy then
							Toast.Show(ERRORS.Busy)
						elseif not affordable then
							Toast.Show(ERRORS.InsufficientCoins)
						else
							requestClearObstacle:FireServer(status.obstacleId)
						end
					end,
				},
			}
		end
		return {
			title = def and def.DisplayName or "Obstacle",
			subtitle = subtitle,
			anchor = { attribute = "ObstacleId", value = status.obstacleId },
			items = items,
		}
	end

	obstacleStatusUpdated.OnClientEvent:Connect(function(newStatus)
		if newStatus.openRequest then
			status = newStatus
			receivedAt = os.clock()
			OptionBar.Open(owner(), buildSpec())
		elseif status and newStatus.obstacleId == status.obstacleId then
			status = newStatus
			receivedAt = os.clock()
			if isShowing() then
				if newStatus.cleared then
					OptionBar.Close()
				else
					OptionBar.Update(owner(), buildSpec())
				end
			end
		elseif isShowing() then
			-- Another obstacle started or finished clearing: this one's Clear
			-- lights up or greys out.
			status.clearingId = newStatus.clearingId
			OptionBar.Update(owner(), buildSpec())
		end

		if newStatus.clearError and ERRORS[newStatus.clearError] then
			Toast.Show(ERRORS[newStatus.clearError])
		end
	end)

	-- Prices grey out or light up as the balances change.
	updateHud.OnClientEvent:Connect(function(data)
		coins = data.Coins or coins
		gems = data.Gems or gems
		if isShowing() then
			OptionBar.Update(owner(), buildSpec())
		end
	end)

	-- Countdown between server pushes, and the switch to Finish at zero.
	task.spawn(function()
		while true do
			task.wait(1)
			if isShowing() and status.clearingId == status.obstacleId then
				OptionBar.Update(owner(), buildSpec())
			end
		end
	end)
end

return ObstacleController
