-- Wires the exploration map (UI/PveMapScreen) to the server: the Adventure
-- button in the top bar asks for the map, the screen sends back the team the
-- player picks and the stage they attack, and a fight's outcome comes back as
-- its own push.
local Players = game:GetService("Players")

local UIKit = require(script.Parent.Parent.UI.UIKit)
local Toast = require(script.Parent.Parent.UI.Toast)
local OptionBar = require(script.Parent.Parent.UI.OptionBar)
local PveMapScreen = require(script.Parent.Parent.UI.PveMapScreen)
local BattleScreen = require(script.Parent.Parent.UI.BattleScreen)

local PveController = {}

-- Why the server turned a fight down, in the player's words.
local FIGHT_ERRORS = {
	Locked = "Clear the stage before it first.",
	NoTeam = "No Adult dragon free to fight.",
	TooFast = "Let your dragons catch their breath.",
	Busy = "That fight is already under way.",
	Failed = "The fight could not be played out.",
	NotReady = "The map isn't ready yet.",
	NoSuchStage = "That stage doesn't exist.",
}

function PveController.Init(remotesFolder)
	local requestPveInfo = remotesFolder:WaitForChild("RequestPveInfo")
	local requestPveTeam = remotesFolder:WaitForChild("RequestPveTeam")
	local requestPveFight = remotesFolder:WaitForChild("RequestPveFight")
	local requestPveAction = remotesFolder:WaitForChild("RequestPveAction")
	local pveStatusUpdated = remotesFolder:WaitForChild("PveStatusUpdated")
	local pveBattleStarted = remotesFolder:WaitForChild("PveBattleStarted")
	local pveBattleUpdate = remotesFolder:WaitForChild("PveBattleUpdate")
	local pveBattleResult = remotesFolder:WaitForChild("PveBattleResult")

	PveMapScreen.Init({
		onFight = function(levelId)
			requestPveFight:FireServer(levelId)
		end,
		onTeam = function(dragonIds)
			requestPveTeam:FireServer(dragonIds)
		end,
	})

	BattleScreen.Init({
		onAction = function(token, skillId, targetKey)
			requestPveAction:FireServer(token, skillId, targetKey)
		end,
		-- Leaving the fight comes back to the map, with the stage that was just
		-- cleared marked as such.
		onClose = function()
			requestPveInfo:FireServer()
		end,
	})

	-- The fight takes the screen (and the camera) from the map.
	pveBattleStarted.OnClientEvent:Connect(function(info)
		PveMapScreen.Close()
		BattleScreen.Start(info)
	end)

	pveBattleUpdate.OnClientEvent:Connect(function(push)
		BattleScreen.Update(push)
	end)

	pveStatusUpdated.OnClientEvent:Connect(function(status)
		PveMapScreen.SetStatus(status)
		if status.openRequest then
			PveMapScreen.Open()
		end
		if status.fightError then
			Toast.Show(FIGHT_ERRORS[status.fightError] or "That fight can't start.")
		end
	end)

	pveBattleResult.OnClientEvent:Connect(function(result)
		if BattleScreen.IsOpen() then
			BattleScreen.Finish(result)
		else
			-- The fight was watched from the map (it can't normally happen, but
			-- a fight that ends while the screen is closed still has to land).
			PveMapScreen.ShowResult(result)
		end
	end)

	-- Next to the Shop button, at the right end of Roblox's top bar row.
	local buttonGui = UIKit.new("ScreenGui", {
		Name = "AdventureButtonGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local holder = UIKit.new("Frame", {
		Name = "AdventureButtonHolder",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(170, 44),
		BackgroundTransparency = 1,
		Parent = buttonGui,
	})
	UIKit.placeInTopbar(holder, 170) -- 12 + the Shop button's 150, plus a gap
	local button = UIKit.button(holder, { Name = "AdventureButton", Variant = "Danger", Text = "Adventure", TextSize = 24 })
	button.OnActivated(function()
		OptionBar.Close()
		requestPveInfo:FireServer()
	end)
end

return PveController
