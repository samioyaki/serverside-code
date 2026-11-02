local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BaddieConfig = require(Shared.Config.BaddieConfig)
local PlotConfig = require(Shared.Config.PlotConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local BaddieState = require(Shared.Enums.BaddieState)
local GridUtil = require(Shared.Util.GridUtil)
local PlaceholderFactory = require(Shared.Util.PlaceholderFactory)

local PlacementService = {}
PlacementService.__index = PlacementService

local ALLOWED_ROTATIONS = {
	[0] = true,
	[90] = true,
	[180] = true,
	[270] = true,
}
local HELD_TOOL_ATTRIBUTE = "FishABaddieHeldBaddieTool"

local function fail(code)
	error(code, 0)
end

function PlacementService.new(registry)
	return setmetatable({
		Registry = registry,
		OccupiedCellsByUserId = {},
	}, PlacementService)
end

function PlacementService:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:ClearHeldBaddie(player, true)
		self.OccupiedCellsByUserId[player.UserId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_bindCharacterCleanup(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_bindCharacterCleanup(player)
	end)
end

function PlacementService:_bindCharacterCleanup(player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			self:ClearHeldBaddie(player)
		end)
	end)
end

function PlacementService:RebuildOccupancy(player)
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local occupied = {}

	for baddieId, placement in pairs(session.Profile.Placements) do
		occupied[GridUtil.GetCellKey(placement.GridX, placement.GridY)] = baddieId
	end

	self.OccupiedCellsByUserId[player.UserId] = occupied
	return occupied
end

function PlacementService:_getCharacterRoot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not character or not root or (humanoid and humanoid.Health <= 0) then
		fail("FishingNoCharacter")
	end

	return root
end

function PlacementService:_assertNearCell(player, gridX, gridY)
	local root = self:_getCharacterRoot(player)
	local cellPosition = self.Registry:Get("PlotService"):GetCellWorldPosition(player, gridX, gridY)
	local distance = (root.Position - cellPosition).Magnitude
	if distance > PlotConfig.InteractionDistance then
		fail("PlacementTooFar")
	end
end

function PlacementService:_assertPlacementAvailable(player, profile, baddieId, gridX, gridY)
	local plot = self.Registry:Get("PlotService"):GetAssignedPlot(player)
	if not plot then
		fail("PlotNotAssigned")
	end

	local gridWidth, gridHeight = self.Registry:Get("PlotService"):GetGridDimensions(profile)
	if not GridUtil.IsInsideBounds(gridX, gridY, gridWidth, gridHeight) then
		fail("PlacementOutOfBounds")
	end

	if not self.Registry:Get("PlotService"):IsCellUnlocked(profile, gridX, gridY) then
		fail("PlacementOutOfBounds")
	end

	local occupied = self.OccupiedCellsByUserId[player.UserId] or {}
	local cellKey = GridUtil.GetCellKey(gridX, gridY)
	local currentBaddieId = occupied[cellKey]
	if currentBaddieId and currentBaddieId ~= baddieId then
		fail("PlacementOccupied")
	end
end

function PlacementService:_getPlacedBaddieIdAtCell(player, profile, gridX, gridY)
	local occupied = self.OccupiedCellsByUserId[player.UserId] or self:RebuildOccupancy(player)
	local cellKey = GridUtil.GetCellKey(gridX, gridY)
	local baddieId = occupied[cellKey]
	if baddieId and profile.Placements[baddieId] then
		return baddieId
	end

	for currentBaddieId, placement in pairs(profile.Placements) do
		if placement.GridX == gridX and placement.GridY == gridY then
			occupied[cellKey] = currentBaddieId
			return currentBaddieId
		end
	end

	return nil
end

function PlacementService:_findHeldTool(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute(HELD_TOOL_ATTRIBUTE) == true then
					return child
				end
			end
		end
	end

	return nil
end

function PlacementService:_clearHeldTool(player)
	local tool = self:_findHeldTool(player)
	if tool then
		tool:Destroy()
	end
end

function PlacementService:_getBaddieAsset(templateId)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local baddieAssets = assets and assets:FindFirstChild("Baddies")
	return baddieAssets and baddieAssets:FindFirstChild(templateId)
end

function PlacementService:_createToolHandle(tool, templateId, color)
	local asset = self:_getBaddieAsset(templateId)
	if asset and asset:IsA("Model") then
		local visual = asset:Clone()
		for _, descendant in ipairs(visual:GetDescendants()) do
			if descendant:IsA("LuaSourceContainer") then
				descendant:Destroy()
			end
		end
		local handle = visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart", true)
		if handle then
			local size = visual:GetExtentsSize()
			local longest = math.max(size.X, size.Y, size.Z)
			if longest > 2.8 then
				visual:ScaleTo(2.8 / longest)
			end
			visual:PivotTo(CFrame.new(0, 1.15, 0))
			visual.Name = "HeldBaddieVisual"
			visual.Parent = tool
			handle.Name = "Handle"
			handle.Parent = tool

			for _, descendant in ipairs(visual:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = false
					descendant.CanCollide = false
					descendant.CanTouch = false
					descendant.CanQuery = false
					descendant.Massless = true

					local weld = Instance.new("WeldConstraint")
					weld.Name = "HeldBaddieWeld"
					weld.Part0 = handle
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
			handle.Anchored = false
			handle.CanCollide = false
			handle.CanTouch = false
			handle.CanQuery = false
			handle.Massless = true
			return handle
		end
		visual:Destroy()
	elseif asset and asset:IsA("BasePart") then
		local handle = asset:Clone()
		handle.Name = "Handle"
		handle.Anchored = false
		handle.CanCollide = false
		handle.CanTouch = false
		handle.CanQuery = false
		handle.Massless = true
		handle.Parent = tool
		return handle
	end

	do
		local placeholder = PlaceholderFactory.CreateBaddie(templateId, color, false)
		placeholder:ScaleTo(0.48)
		local handle = placeholder.PrimaryPart
		handle.Name = "Handle"
		for _, child in ipairs(placeholder:GetChildren()) do
			child.Parent = tool
		end
		placeholder:Destroy()
		return handle
	end
end

function PlacementService:_createHeldTool(player, baddie)
	self:_clearHeldTool(player)

	local definition = BaddieConfig.Definitions[baddie.TemplateId]
	local displayName = definition and definition.DisplayName or baddie.TemplateId
	local color = (definition and definition.DisplayColor)
		or RarityConfig.RewardColors[baddie.RarityId]
		or Color3.new(1, 1, 1)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = displayName
	tool.ToolTip = "Place on your plot"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute(HELD_TOOL_ATTRIBUTE, true)
	tool:SetAttribute("BaddieId", baddie.Id)
	tool:SetAttribute("TemplateId", baddie.TemplateId)
	tool:SetAttribute("RarityId", baddie.RarityId)
	self:_createToolHandle(tool, baddie.TemplateId, color)
	tool.Parent = backpack

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			humanoid:EquipTool(tool)
		end)
	end
end

function PlacementService:_removePlacementFromProfile(player, profile, baddieId)
	local placement = profile.Placements[baddieId]
	if not placement then
		return
	end

	profile.Placements[baddieId] = nil
	local occupied = self.OccupiedCellsByUserId[player.UserId]
	if occupied then
		occupied[GridUtil.GetCellKey(placement.GridX, placement.GridY)] = nil
	end
end

function PlacementService:_setHeldBaddie(player, session, baddie)
	session.Runtime.HeldBaddieId = baddie.Id
	self:_createHeldTool(player, baddie)
end

function PlacementService:Place(player, baddieId, gridX, gridY, rotation)
	rotation = rotation or 0
	if not ALLOWED_ROTATIONS[rotation] then
		fail("InvalidPlacementAction")
	end
	self:_assertNearCell(player, gridX, gridY)

	self.Registry:Get("IncomeService"):Accrue(player, "BeforePlacement")

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "PlaceBaddie", {
		"Inventory",
		"Plot",
		"Wallet",
	}, function(_, profile)
		self.OccupiedCellsByUserId[player.UserId] = self.OccupiedCellsByUserId[player.UserId] or {}
		local baddie = self.Registry:Get("InventoryService"):AssertBaddie(profile, baddieId)
		if baddie.State ~= BaddieState.Inventory and baddie.State ~= BaddieState.Placed then
			fail("BaddieNotPlaceable")
		end

		self:_assertPlacementAvailable(player, profile, baddieId, gridX, gridY)

		local previousPlacement = profile.Placements[baddieId]
		if previousPlacement then
			self.OccupiedCellsByUserId[player.UserId][GridUtil.GetCellKey(
				previousPlacement.GridX,
				previousPlacement.GridY
			)] =
				nil
		end

		profile.Placements[baddieId] = {
			BaddieId = baddieId,
			GridX = gridX,
			GridY = gridY,
			Rotation = rotation,
		}

		self.Registry:Get("InventoryService"):SetState(profile, baddieId, BaddieState.Placed)
		self.OccupiedCellsByUserId[player.UserId][GridUtil.GetCellKey(gridX, gridY)] = baddieId
	end)
end

function PlacementService:HoldBaddie(player, baddieId)
	local heldBaddie = nil
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local profile = session.Profile
	local baddie = self.Registry:Get("InventoryService"):AssertBaddie(profile, baddieId)
	if baddie.State ~= BaddieState.Inventory and baddie.State ~= BaddieState.Placed then
		fail("BaddieNotPlaceable")
	end

	local placement = profile.Placements[baddieId]
	if placement then
		self:_assertNearCell(player, placement.GridX, placement.GridY)
		self.Registry:Get("IncomeService"):Accrue(player, "BeforeHoldBaddie")
		self.Registry:Get("PlayerDataService"):MutateProfile(player, "HoldBaddie", {
			"Inventory",
			"Plot",
			"Wallet",
		}, function(runtimeSession, innerProfile)
			local innerBaddie = self.Registry:Get("InventoryService"):AssertBaddie(innerProfile, baddieId)
			self:_removePlacementFromProfile(player, innerProfile, baddieId)
			self.Registry:Get("InventoryService"):SetState(innerProfile, baddieId, BaddieState.Inventory)
			heldBaddie = innerBaddie
			self:_setHeldBaddie(player, runtimeSession, innerBaddie)
		end)
	else
		self:_setHeldBaddie(player, session, baddie)
		self.Registry:Get("PlayerDataService"):PublishRuntime(player, "HoldBaddie", { "Plot" })
		heldBaddie = baddie
	end

	return heldBaddie
end

function PlacementService:ClearHeldBaddie(player, silent)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	self:_clearHeldTool(player)
	if not session or not session.Runtime.HeldBaddieId then
		return
	end

	session.Runtime.HeldBaddieId = nil
	if not silent then
		self.Registry:Get("PlayerDataService"):PublishRuntime(player, "ClearHeldBaddie", { "Plot" })
	end
end

function PlacementService:PlaceHeld(player, gridX, gridY)
	self:_assertNearCell(player, gridX, gridY)

	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local baddieId = session.Runtime.HeldBaddieId
	if not baddieId then
		fail("NoHeldBaddie")
	end

	self:Place(player, baddieId, gridX, gridY, 0)
	self:ClearHeldBaddie(player)
	return baddieId
end

function PlacementService:PickupCell(player, gridX, gridY)
	self:_assertNearCell(player, gridX, gridY)
	self.Registry:Get("IncomeService"):Accrue(player, "BeforePickupCell")

	local pickedBaddie = nil
	self.Registry:Get("PlayerDataService"):MutateProfile(player, "PickupCell", {
		"Inventory",
		"Plot",
		"Wallet",
	}, function(session, profile)
		local baddieId = self:_getPlacedBaddieIdAtCell(player, profile, gridX, gridY)
		if not baddieId then
			fail("PlacementCellEmpty")
		end

		local baddie = self.Registry:Get("InventoryService"):AssertBaddie(profile, baddieId)
		self:_removePlacementFromProfile(player, profile, baddieId)
		self.Registry:Get("InventoryService"):SetState(profile, baddieId, BaddieState.Inventory)
		self:_setHeldBaddie(player, session, baddie)
		pickedBaddie = baddie
	end)

	return pickedBaddie
end

function PlacementService:Remove(player, baddieId)
	self.Registry:Get("IncomeService"):Accrue(player, "BeforeRemove")

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "RemoveBaddie", {
		"Inventory",
		"Plot",
		"Wallet",
	}, function(_, profile)
		self.Registry:Get("InventoryService"):AssertBaddie(profile, baddieId)
		local placement = profile.Placements[baddieId]
		if not placement then
			fail("BaddieNotPlaced")
		end

		profile.Placements[baddieId] = nil
		self.Registry:Get("InventoryService"):SetState(profile, baddieId, BaddieState.Inventory)

		local occupied = self.OccupiedCellsByUserId[player.UserId]
		if occupied then
			occupied[GridUtil.GetCellKey(placement.GridX, placement.GridY)] = nil
		end
	end)
end

return PlacementService
