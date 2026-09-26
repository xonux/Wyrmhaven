-- Grid placement: buying a Habitat, a farm, a Nursery or a decoration (Shop) or moving any building or decoration
-- (Move in its option bar). While active, the island's tile grid is drawn with taken
-- tiles shaded, and a see-through copy of the building follows the mouse (or
-- jumps where the player taps) above a green/red footprint. The option bar
-- switches to Cancel / Confirm: nothing is bought or moved before Confirm,
-- and Cancel leaves a moved building where it was. The server re-validates
-- everything (ShopService.PlaceHabitat, FarmService.Place, BreedingService.BuyNursery, RequestMoveStructure).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UI = script.Parent.Parent.UI
local OptionBar = require(UI.OptionBar)
local Toast = require(UI.Toast)
local UIKit = require(UI.UIKit)

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)
local HabitatDefs = require(Config.HabitatDefs)
local DecorationDefs = require(Config.DecorationDefs)
local FarmDefs = require(Config.FarmDefs)

local PlacementController = {}

local assets = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets")
local habitatTemplates = assets:FindFirstChild("Habitats")
local decorationTemplates = assets:FindFirstChild("Decorations")
local buildingTemplates = assets:FindFirstChild("Buildings")

-- Particles and lights keep going on hidden or see-through parts.
local function setEffectsEnabled(root, enabled)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Light") or descendant:IsA("Beam") then
			descendant.Enabled = enabled
		end
	end
end

-- Same grid as HabitatService (GameConstants).
local TILE_SIZE = GameConstants.GridTileSize
local GRID_TILES_PER_SIDE = GameConstants.GridTilesPerSide
local ISLAND_HALF_SIZE = TILE_SIZE * GRID_TILES_PER_SIDE / 2

local OWNER = "Placement"
local GHOST_TRANSPARENCY = 0.5
local VALID_COLOR = Color3.fromRGB(80, 200, 110)
local INVALID_COLOR = Color3.fromRGB(220, 70, 70)
local GRID_LINE_COLOR = Color3.fromRGB(255, 255, 255)
local TAKEN_TILE_COLOR = Color3.fromRGB(20, 21, 25)
local UNHIDE_TIMEOUT_SECONDS = 2 -- a moved building reappears once the server moved it, or after this

local islandBasePosition = Vector3.zero
local occupied = {} -- ["x,z"] = true, from UpdateHud's OccupiedTiles
local occupiedSignature = ""
local pendingReveals = {} -- [moved part] = token, see endSession
local hiddenEffects = {} -- [hidden part] = { [effect] = its Enabled before hiding }

-- Active placement, or nil: { kind ("Buy" a habitat, "BuyFarm", "BuyNursery", "BuyDecoration", or what
-- RequestMoveStructure moves), id, element / defId, price, tilesX / tilesZ
-- (footprint), source (moved part), homeX/homeZ, ghost, footprint,
-- overlay, gridX/gridZ, valid, locked, barState }
local session = nil
local requestPlaceHabitat, requestPlaceFarm, requestPlaceNursery, requestPlaceDecoration, requestMoveStructure
local confirm

local function tileKey(x, z)
	return x .. "," .. z
end

local function islandOrigin()
	return islandBasePosition.X - ISLAND_HALF_SIZE, islandBasePosition.Z - ISLAND_HALF_SIZE
end

local function surfaceY()
	return islandBasePosition.Y + 1 -- IslandBase top surface (Size.Y/2)
end

-- The moved building's own tiles count as free.
local function isHomeTile(x, z)
	return session.homeX ~= nil
		and x >= session.homeX and x < session.homeX + session.tilesX
		and z >= session.homeZ and z < session.homeZ + session.tilesZ
end

local function isAreaValid(gridX, gridZ)
	local tilesX, tilesZ = session.tilesX, session.tilesZ
	if gridX < 0 or gridZ < 0 or gridX + tilesX > GRID_TILES_PER_SIDE or gridZ + tilesZ > GRID_TILES_PER_SIDE then
		return false
	end
	for x = gridX, gridX + tilesX - 1 do
		for z = gridZ, gridZ + tilesZ - 1 do
			if occupied[tileKey(x, z)] and not isHomeTile(x, z) then
				return false
			end
		end
	end
	return true
end

-- Grid spot whose footprint center is nearest to a world position.
local function worldToGrid(worldPos)
	local originX, originZ = islandOrigin()
	local gridX = math.floor((worldPos.X - originX) / TILE_SIZE - session.tilesX / 2 + 0.5)
	local gridZ = math.floor((worldPos.Z - originZ) / TILE_SIZE - session.tilesZ / 2 + 0.5)
	return gridX, gridZ
end

-- Footprint center, on the island surface.
local function gridCenterWorld(gridX, gridZ)
	local originX, originZ = islandOrigin()
	return Vector3.new(
		originX + (gridX + session.tilesX / 2) * TILE_SIZE,
		surfaceY(),
		originZ + (gridZ + session.tilesZ / 2) * TILE_SIZE
	)
end

-- Where the pointer meets the island's top surface. Intersecting that plane
-- (instead of raycasting) keeps the ghost under the cursor even when the
-- pointer is over a dragon or another building standing above the ground.
local function pointerToIslandSurface(screenPos)
	local camera = Workspace.CurrentCamera
	-- InputObject positions exclude the top-bar GUI inset; ScreenPointToRay accounts for it.
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local distance = (surfaceY() - ray.Origin.Y) / ray.Direction.Y
	if distance <= 0 then
		return nil
	end
	return ray.Origin + ray.Direction * distance
end

-- True while the pointer is over the option bar (Cancel / Confirm).
local function isOverOptionBar(position)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return false
	end
	local barGui = OptionBar.GetGui()
	for _, object in ipairs(playerGui:GetGuiObjectsAtPosition(position.X, position.Y)) do
		if object:IsDescendantOf(barGui) then
			return true
		end
	end
	return false
end

local function findIslandPart(attribute, value)
	local islands = Workspace:FindFirstChild("Islands")
	local island = islands and islands:FindFirstChild(tostring(Players.LocalPlayer.UserId))
	if not island then
		return nil
	end
	for _, child in ipairs(island:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute(attribute) == value then
			return child
		end
	end
	return nil
end

local function newPreviewPart(parent, size, position, color, transparency)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.Position = position
	part.Color = color
	part.Transparency = transparency
	part.Parent = parent
	return part
end

-- Tile grid lines over the island, plus a dark square on every taken tile.
local function buildGridOverlay()
	if session.overlay then
		session.overlay:Destroy()
	end
	local overlay = Instance.new("Folder")
	overlay.Name = "PlacementGrid"

	local originX, originZ = islandOrigin()
	local y = surfaceY() + 0.04
	local length = GRID_TILES_PER_SIDE * TILE_SIZE
	for i = 0, GRID_TILES_PER_SIDE do
		local offset = i * TILE_SIZE
		newPreviewPart(overlay, Vector3.new(length, 0.05, 0.12), Vector3.new(originX + length / 2, y, originZ + offset), GRID_LINE_COLOR, 0.55)
		newPreviewPart(overlay, Vector3.new(0.12, 0.05, length), Vector3.new(originX + offset, y, originZ + length / 2), GRID_LINE_COLOR, 0.55)
	end
	for key in pairs(occupied) do
		local x, z = key:match("(-?%d+),(-?%d+)")
		x, z = tonumber(x), tonumber(z)
		if x and z and not isHomeTile(x, z) then
			local center = Vector3.new(originX + (x + 0.5) * TILE_SIZE, y, originZ + (z + 0.5) * TILE_SIZE)
			newPreviewPart(overlay, Vector3.new(TILE_SIZE - 0.4, 0.04, TILE_SIZE - 0.4), center, TAKEN_TILE_COLOR, 0.55)
		end
	end

	overlay.Parent = Workspace
	session.overlay = overlay
end

-- See-through copy of `sourcePart` and whatever stands on it (dragons, eggs),
-- wrapped in a Model so PivotTo carries them along. It lives outside the
-- island folder, so nothing treats it as the real building.
local function makeGhost(sourcePart)
	local model = Instance.new("Model")
	model.Name = "PlacementGhost"
	local copy = sourcePart:Clone()
	copy.Parent = model
	model.PrimaryPart = copy
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.LocalTransparencyModifier = 0
			descendant.Transparency = math.max(descendant.Transparency, GHOST_TRANSPARENCY)
		end
	end
	setEffectsEnabled(model, false)
	model.Parent = Workspace
	return model
end

-- Client-only hide of the real building while its ghost is being moved.
local function setHidden(part, hidden)
	local modifier = hidden and 1 or 0
	part.LocalTransparencyModifier = modifier
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = modifier
		end
	end
	-- Effects go quiet while hidden, then back to what they were: a habitat
	-- under construction keeps its own off, the Nursery's pairing sparkles
	-- follow its pairing.
	if hidden then
		local saved = hiddenEffects[part] or {}
		for _, descendant in ipairs(part:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") or descendant:IsA("Light") or descendant:IsA("Beam") then
				if saved[descendant] == nil then
					saved[descendant] = descendant.Enabled
				end
				descendant.Enabled = false
			end
		end
		hiddenEffects[part] = saved
	else
		local saved = hiddenEffects[part] or {}
		hiddenEffects[part] = nil
		for effect, enabled in pairs(saved) do
			if effect.Parent then
				effect.Enabled = enabled
			end
		end
	end
end

-- Cancel / Confirm (Confirm greyed out while the spot is taken). Only
-- re-rendered when that state flips, not on every mouse move.
local function refreshBar()
	local canConfirm = session.valid == true
	if session.barState == canConfirm then
		return
	end
	session.barState = canConfirm
	OptionBar.Open(OWNER, {
		persistent = true,
		items = {
			{
				key = "Cancel",
				icon = "Close",
				palette = "Danger",
				label = "Cancel",
				onClick = function()
					PlacementController.Cancel()
				end,
			},
			{
				key = "Confirm",
				icon = "Check",
				palette = "Confirm",
				top = session.price and UIKit.formatNumber(session.price) or nil,
				topIcon = session.price and (session.currency or "Coin") or nil,
				label = "Confirm",
				dimmed = not canConfirm,
				onClick = function()
					confirm()
				end,
			},
		},
	})
end

local function showAt(gridX, gridZ)
	session.gridX, session.gridZ = gridX, gridZ
	session.valid = isAreaValid(gridX, gridZ)

	local center = gridCenterWorld(gridX, gridZ)
	local ghostPart = session.ghost.PrimaryPart
	session.ghost:PivotTo(CFrame.new(center + Vector3.new(0, ghostPart.Size.Y / 2, 0)))
	session.footprint.Position = center + Vector3.new(0, 0.1, 0)
	session.footprint.Color = session.valid and VALID_COLOR or INVALID_COLOR
	refreshBar()
end

local function startSession(fields, sourcePart)
	if session then
		PlacementController.Cancel()
	end
	session = fields
	session.ghost = makeGhost(sourcePart)
	-- A bit wider than the building so its edge shows
	local size = Vector3.new(session.tilesX * TILE_SIZE + 0.6, 0.06, session.tilesZ * TILE_SIZE + 0.6)
	session.footprint = newPreviewPart(Workspace, size, Vector3.zero, VALID_COLOR, 0.45)
	session.footprint.Name = "PlacementFootprint"
	buildGridOverlay()
end

-- waitForServerMove: keep a moved building hidden until the server has
-- actually moved it, so it doesn't flash back at its old spot.
local function endSession(waitForServerMove)
	local ended = session
	session = nil
	ended.ghost:Destroy()
	ended.footprint:Destroy()
	if ended.overlay then
		ended.overlay:Destroy()
	end
	if OptionBar.IsShowing(OWNER) then
		OptionBar.Close()
	end

	local source = ended.source
	if not source then
		return
	end
	if not waitForServerMove then
		setHidden(source, false)
		return
	end

	local token = {}
	pendingReveals[source] = token
	local connection
	local function reveal()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if pendingReveals[source] ~= token then
			return
		end
		pendingReveals[source] = nil
		setHidden(source, false)
	end
	connection = source:GetPropertyChangedSignal("CFrame"):Connect(function()
		task.defer(reveal) -- lets the dragons standing on it be re-seated first
	end)
	task.delay(UNHIDE_TIMEOUT_SECONDS, reveal)
end

confirm = function()
	if not session then
		return
	end
	if not session.valid then
		Toast.Show("Spot taken")
		return
	end
	if session.kind == "Buy" then
		requestPlaceHabitat:FireServer(session.element, session.gridX, session.gridZ)
		endSession(false)
	elseif session.kind == "BuyFarm" then
		requestPlaceFarm:FireServer(session.gridX, session.gridZ)
		endSession(false)
	elseif session.kind == "BuyNursery" then
		requestPlaceNursery:FireServer(session.gridX, session.gridZ)
		endSession(false)
	elseif session.kind == "BuyDecoration" then
		requestPlaceDecoration:FireServer(session.defId, session.gridX, session.gridZ)
		endSession(false)
	elseif session.gridX == session.homeX and session.gridZ == session.homeZ then
		endSession(false) -- put back where it was
	else
		requestMoveStructure:FireServer(session.kind, session.id, session.gridX, session.gridZ)
		endSession(true)
	end
end

function PlacementController.IsActive()
	return session ~= nil
end

-- Leaves everything as it was: nothing bought, a moved building stays put.
function PlacementController.Cancel()
	if session then
		endSession(false)
	end
end

-- Shop: preview of a new habitat of `element`; `price` is shown on Confirm.
function PlacementController.StartHabitatPlacement(element, price)
	local def = HabitatDefs[element]
	if not def then
		return
	end
	local template = habitatTemplates and habitatTemplates:FindFirstChild(element)
	local preview
	if template then
		preview = template:Clone()
	else
		preview = Instance.new("Part")
		preview.Size = def.PlatformSize
		preview.Color = def.PlatformColor
		preview.Material = Enum.Material.SmoothPlastic
	end
	preview.Name = def.DisplayName
	local tiles = GameConstants.StructureTiles.Habitat
	startSession({ kind = "Buy", element = element, price = price, tilesX = tiles, tilesZ = tiles }, preview)
	preview:Destroy()

	local viewportCenter = Workspace.CurrentCamera.ViewportSize / 2
	showAt(worldToGrid(pointerToIslandSurface(viewportCenter) or islandBasePosition))
	Toast.Show("Pick a spot, then Confirm")
end

-- Shop: preview of a new farm; `price` is shown on Confirm.
function PlacementController.StartFarmPlacement(price)
	local tiles = GameConstants.StructureTiles.Farm
	local template = buildingTemplates and buildingTemplates:FindFirstChild("Farm")
	local preview
	if template then
		preview = template:Clone()
	else
		preview = Instance.new("Part")
		preview.Size = Vector3.new(tiles * TILE_SIZE, 1, tiles * TILE_SIZE)
		preview.Color = Color3.fromRGB(196, 164, 92)
		preview.Material = Enum.Material.SmoothPlastic
	end
	preview.Name = FarmDefs.DisplayName
	startSession({ kind = "BuyFarm", price = price, tilesX = tiles, tilesZ = tiles }, preview)
	preview:Destroy()

	local viewportCenter = Workspace.CurrentCamera.ViewportSize / 2
	showAt(worldToGrid(pointerToIslandSurface(viewportCenter) or islandBasePosition))
	Toast.Show("Pick a spot, then Confirm")
end

-- Shop: preview of the second Nursery (the mirrored tree); its Gem `price`
-- is shown on Confirm.
function PlacementController.StartNurseryPlacement(price)
	local tiles = GameConstants.StructureTiles.Nursery
	local template = buildingTemplates and buildingTemplates:FindFirstChild("NurseryMirror")
	local preview
	if template then
		preview = template:Clone()
	else
		preview = Instance.new("Part")
		preview.Size = Vector3.new(tiles * TILE_SIZE, 1, tiles * TILE_SIZE)
		preview.Color = Color3.fromRGB(219, 180, 217)
		preview.Material = Enum.Material.SmoothPlastic
	end
	preview.Name = "Nursery"
	startSession({ kind = "BuyNursery", price = price, currency = "Gem", tilesX = tiles, tilesZ = tiles }, preview)
	preview:Destroy()

	local viewportCenter = Workspace.CurrentCamera.ViewportSize / 2
	showAt(worldToGrid(pointerToIslandSurface(viewportCenter) or islandBasePosition))
	Toast.Show("Pick a spot, then Confirm")
end

-- Shop: preview of a decoration; `price` is shown on Confirm.
function PlacementController.StartDecorationPlacement(defId, price)
	local def = DecorationDefs[defId]
	if not def then
		return
	end
	local template = decorationTemplates and decorationTemplates:FindFirstChild(defId)
	local preview
	if template then
		preview = template:Clone()
	else
		preview = Instance.new("Part")
		preview.Size = Vector3.new(def.TilesX * TILE_SIZE, 1, def.TilesZ * TILE_SIZE)
		preview.Color = def.AccentColor
		preview.Material = Enum.Material.SmoothPlastic
	end
	preview.Name = def.DisplayName
	startSession({ kind = "BuyDecoration", defId = defId, price = price, tilesX = def.TilesX, tilesZ = def.TilesZ }, preview)
	preview:Destroy()

	local viewportCenter = Workspace.CurrentCamera.ViewportSize / 2
	showAt(worldToGrid(pointerToIslandSurface(viewportCenter) or islandBasePosition))
	Toast.Show("Pick a spot, then Confirm")
end

-- Option bar "Move": kind is what RequestMoveStructure expects (a
-- GameConstants.StructureTiles key or "Decoration"), id its id,
-- attribute/value find the building's part; tilesX/tilesZ override the
-- footprint (decorations have their own).
function PlacementController.StartMove(kind, id, attribute, value, tilesX, tilesZ)
	local part = findIslandPart(attribute, value)
	tilesX = tilesX or GameConstants.StructureTiles[kind]
	tilesZ = tilesZ or tilesX
	if not part or not tilesX then
		return
	end
	-- Current spot, from where the part stands (buildings are always grid-aligned).
	local originX, originZ = islandOrigin()
	local homeX = math.floor((part.Position.X - originX) / TILE_SIZE - tilesX / 2 + 0.5)
	local homeZ = math.floor((part.Position.Z - originZ) / TILE_SIZE - tilesZ / 2 + 0.5)

	pendingReveals[part] = nil
	startSession({ kind = kind, id = id, tilesX = tilesX, tilesZ = tilesZ, source = part, homeX = homeX, homeZ = homeZ }, part)
	setHidden(part, true)
	showAt(homeX, homeZ)
	Toast.Show("Pick the new spot, then Confirm")
end

-- A click/tap on the island (from InteractionController) drops the building
-- there; from then on the mouse no longer drags it around.
function PlacementController.PointerTap(screenPos)
	if not session then
		return
	end
	local hit = pointerToIslandSurface(screenPos)
	if not hit then
		return
	end
	session.locked = true
	showAt(worldToGrid(hit))
end

function PlacementController.Init(remotesFolder)
	requestPlaceHabitat = remotesFolder:WaitForChild("RequestPlaceHabitat")
	requestPlaceFarm = remotesFolder:WaitForChild("RequestPlaceFarm")
	requestPlaceNursery = remotesFolder:WaitForChild("RequestPlaceNursery")
	requestPlaceDecoration = remotesFolder:WaitForChild("RequestPlaceDecoration")
	requestMoveStructure = remotesFolder:WaitForChild("RequestMoveStructure")

	local setCameraTarget = remotesFolder:WaitForChild("SetCameraTarget")
	setCameraTarget.OnClientEvent:Connect(function(center)
		islandBasePosition = center
	end)

	local updateHud = remotesFolder:WaitForChild("UpdateHud")
	updateHud.OnClientEvent:Connect(function(data)
		if not data.OccupiedTiles then
			return
		end
		local fresh, keys = {}, {}
		for _, tile in ipairs(data.OccupiedTiles) do
			local key = tileKey(tile[1], tile[2])
			fresh[key] = true
			table.insert(keys, key)
		end
		occupied = fresh

		table.sort(keys)
		local signature = table.concat(keys, ";")
		if signature ~= occupiedSignature then
			occupiedSignature = signature
			if session then
				buildGridOverlay()
				showAt(session.gridX, session.gridZ) -- the spot may have been taken meanwhile
			end
		end
	end)

	-- Mouse hover drags the ghost until the player clicks a spot. Touch only
	-- moves it on tap (PointerTap), since touch movement pans the camera.
	UserInputService.InputChanged:Connect(function(input)
		if not session or session.locked or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		-- Heading for Confirm must not drag the building to the spot under the bar.
		if isOverOptionBar(input.Position) then
			return
		end
		local hit = pointerToIslandSurface(Vector2.new(input.Position.X, input.Position.Y))
		if not hit then
			return
		end
		local gridX, gridZ = worldToGrid(hit)
		if gridX ~= session.gridX or gridZ ~= session.gridZ then
			showAt(gridX, gridZ)
		end
	end)

	-- Right-click or Escape cancels, same as Cancel.
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if not session or gameProcessedEvent then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape then
			PlacementController.Cancel()
		end
	end)
end

return PlacementController
