-- Choosing, on the island itself, the habitat a dragon moves into: a
-- hatchling leaving the Incubator (IncubatorController) or a dragon changing
-- habitat (HabitatUIController). Bouncing arrows point at every habitat it
-- can live in (a hybrid: of either of its two elements) with room, a persistent bar shows the dragon with Cancel, and
-- taps on the island go to the choice. It ends on a tap on a pointed habitat,
-- Cancel, Escape / right-click, or when its bar gives way (the Shop opened,
-- another building tapped...).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local InteractionController = require(script.Parent.InteractionController)

local UI = script.Parent.Parent.UI
local OptionBar = require(UI.OptionBar)
local Toast = require(UI.Toast)
local WorldArrow = require(UI.WorldArrow)

local HabitatDefs = require(ReplicatedStorage.Wyrmhaven.Config.HabitatDefs)

local HabitatPicker = {}

local OWNER = "PlaceDragon"
local HINT = "Tap a habitat with an arrow over it"

local choice = nil -- { targets = { [habitatId] = true }, onChosen } while choosing

-- The island part of each of the local player's habitats, by habitat id.
local function findHabitatParts()
	local parts = {}
	local islands = Workspace:FindFirstChild("Islands")
	local island = islands and islands:FindFirstChild(tostring(Players.LocalPlayer.UserId))
	if island then
		for _, child in ipairs(island:GetChildren()) do
			local habitatId = child:IsA("BasePart") and child:GetAttribute("HabitatId")
			if habitatId then
				parts[habitatId] = child
			end
		end
	end
	return parts
end

function HabitatPicker.Cancel()
	if not choice then
		return
	end
	choice = nil
	WorldArrow.Clear()
	InteractionController.SetTapHandler(nil)
	if OptionBar.IsShowing(OWNER) then
		OptionBar.Close()
	end
end

local function onTap(attribute, value)
	if attribute == "HabitatId" and choice.targets[value] then
		local onChosen = choice.onChosen
		HabitatPicker.Cancel()
		onChosen(value)
	else
		Toast.Show(HINT)
	end
end

-- options: habitatElements (the HabitatDefs keys the dragon can live in; or
-- habitatElement, a single one), habitats (HabitatService.GetHabitatSummaries
-- rows), fromHabitatId (the habitat it
-- leaves, never offered - nil from the Incubator), item (OptionBar item
-- showing the dragon), extraItems (more OptionBar items before Cancel, e.g.
-- a hatchling's Sell), onChosen(habitatId). When no habitat can take the
-- dragon a toast says why, and it returns false - unless there are
-- extraItems: the bar then opens anyway, without arrows.
function HabitatPicker.Start(options)
	HabitatPicker.Cancel()
	local elements = options.habitatElements or { options.habitatElement }
	local names = {}
	for _, element in ipairs(elements) do
		local def = HabitatDefs[element]
		table.insert(names, def and def.DisplayName or element)
	end
	local habitatName = table.concat(names, " ou ")
	local parts = findHabitatParts()
	local targets, targetParts, candidates, building = {}, {}, 0, 0
	for _, habitat in ipairs(options.habitats or {}) do
		if table.find(elements, habitat.element) and habitat.id ~= options.fromHabitatId then
			candidates += 1
			if habitat.building then
				building += 1
			elseif habitat.used < habitat.capacity and parts[habitat.id] then
				targets[habitat.id] = true
				table.insert(targetParts, parts[habitat.id])
			end
		end
	end
	local noTarget = #targetParts == 0
	if noTarget then
		if building > 0 then
			Toast.Show(string.format("Wait for the construction to finish (%s)", habitatName))
		elseif candidates > 0 then
			Toast.Show(string.format("No room left (%s)", habitatName))
		elseif options.fromHabitatId then
			Toast.Show(string.format("You need another %s: buy one in the Shop", habitatName))
		else
			Toast.Show(string.format("You need a %s: buy one in the Shop", habitatName))
		end
		if not options.extraItems then
			return false
		end
	end

	choice = { targets = targets, onChosen = options.onChosen }
	WorldArrow.Show(targetParts)
	InteractionController.SetTapHandler(onTap)
	local item = table.clone(options.item)
	item.onClick = function()
		Toast.Show(HINT)
	end
	local items = { item }
	for _, extra in ipairs(options.extraItems or {}) do
		table.insert(items, extra)
	end
	table.insert(items, {
		key = "Cancel",
		icon = "Close",
		palette = "Danger",
		label = "Cancel",
		onClick = HabitatPicker.Cancel,
	})
	OptionBar.Open(OWNER, {
		persistent = true,
		items = items,
	})
	if not noTarget then
		Toast.Show("Tap the habitat to place your dragon in")
	end
	return true
end

function HabitatPicker.Init()
	RunService.Heartbeat:Connect(function()
		if choice and not OptionBar.IsShowing(OWNER) then
			HabitatPicker.Cancel()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if choice and not gameProcessedEvent
			and (input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2) then
			HabitatPicker.Cancel()
		end
	end)
end

return HabitatPicker
