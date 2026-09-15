local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotesFolder = ReplicatedStorage.Wyrmhaven:WaitForChild("Remotes")

local Controllers = script.Parent.Controllers
local CameraController = require(Controllers.CameraController)
local InteractionController = require(Controllers.InteractionController)
local HudController = require(Controllers.HudController)
local ShopController = require(Controllers.ShopController)
local NurseryController = require(Controllers.NurseryController)

CameraController.Init(remotesFolder)
InteractionController.Init(remotesFolder, CameraController)
HudController.Init(remotesFolder)
ShopController.Init(remotesFolder)
NurseryController.Init(remotesFolder)
