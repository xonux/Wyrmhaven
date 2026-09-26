-- Decoration option bar (OptionBar): Move and Sell for the tapped
-- decoration. The server pushes DecorationStatusUpdated when one is tapped
-- (DecorationService.RequestInfo).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementController = require(script.Parent.PlacementController)

local UI = script.Parent.Parent.UI
local OptionBar = require(UI.OptionBar)
local UIKit = require(UI.UIKit)

local DecorationDefs = require(ReplicatedStorage.Wyrmhaven.Config.DecorationDefs)

local DecorationController = {}

function DecorationController.Init(remotesFolder)
	local decorationStatusUpdated = remotesFolder:WaitForChild("DecorationStatusUpdated")
	local requestSellDecoration = remotesFolder:WaitForChild("RequestSellDecoration")

	decorationStatusUpdated.OnClientEvent:Connect(function(status)
		if not status.openRequest then
			return
		end
		local def = DecorationDefs[status.defId]
		local id = status.decorationId
		OptionBar.Open("Decoration:" .. tostring(id), {
			title = def and def.DisplayName or "Decoration",
			subtitle = "Decoration",
			anchor = { attribute = "DecorationId", value = id },
			items = {
				{
					key = "Move",
					icon = "Move",
					label = "Move",
					onClick = function()
						PlacementController.StartMove("Decoration", id, "DecorationId", id, def and def.TilesX or 1, def and def.TilesZ or 1)
					end,
				},
				{
					key = "Sell",
					icon = "Coin",
					palette = "Danger",
					top = "+" .. UIKit.formatNumber(status.sellValue or 0),
					label = "Sell",
					onClick = function()
						requestSellDecoration:FireServer(id)
						-- The decoration stops existing once sold, so no refresh will come.
						OptionBar.Close()
					end,
				},
			},
		})
	end)
end

return DecorationController
