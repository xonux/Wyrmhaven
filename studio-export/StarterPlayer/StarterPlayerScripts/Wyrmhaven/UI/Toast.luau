-- Short message pill shared by every screen (e.g. why a button can't be used
-- right now). One at a time: a new message replaces the one showing.
local Players = game:GetService("Players")

local UITheme = require(script.Parent.UITheme)
local UIKit = require(script.Parent.UIKit)

local Toast = {}

local DISPLAY_SECONDS = 2.2

local frame, label
local token = 0

local function ensureGui()
	if frame then
		return
	end
	local gui = UIKit.new("ScreenGui", {
		Name = "ToastGui",
		ResetOnSpawn = false,
		DisplayOrder = 100,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	frame = UIKit.new("Frame", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 46),
		BackgroundColor3 = UITheme.Colors.Toast,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = gui,
	})
	UIKit.corner(frame, UDim.new(1, 0))
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22), Parent = frame })
	label = UIKit.text(frame, {
		Name = "Message",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextSize = 22,
		TextColor3 = UITheme.Colors.TextLight,
	})
end

function Toast.Show(message)
	ensureGui()
	token += 1
	local myToken = token
	label.Text = message
	label.TextTransparency = 0
	frame.BackgroundTransparency = 0.1
	frame.Visible = true

	task.delay(DISPLAY_SECONDS, function()
		if myToken ~= token then
			return
		end
		UIKit.tween(frame, UITheme.Tweens.Fade, { BackgroundTransparency = 1 })
		UIKit.tween(label, UITheme.Tweens.Fade, { TextTransparency = 1 }).Completed:Wait()
		if myToken == token then
			frame.Visible = false
		end
	end)
end

return Toast
