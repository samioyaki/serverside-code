local Players = game:GetService("Players")
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FormulaUtil = require(Shared.Util.FormulaUtil)
local PlaceholderFactory = require(Shared.Util.PlaceholderFactory)
local ExternalAssetConfig = require(Shared.Config.ExternalAssetConfig)
local RodConfig = require(Shared.Config.RodConfig)

local RodToolService = {}
RodToolService.__index = RodToolService

local TOOL_ATTRIBUTE = "FishABaddieRodTool"

function RodToolService.new(registry)
	return setmetatable({
		Registry = registry,
		ConnectionsByPlayer = {},
		ToolConnectionsByPlayer = {},
	}, RodToolService)
end

function RodToolService:_loadExternalRodTemplate()
	local definition = ExternalAssetConfig.FishingRod
	local ok, loaded = pcall(function()
		return AssetService:LoadAssetAsync(definition.AssetId)
	end)
	if not ok or not loaded then
		warn("Fish A Baddie: free Creator Store rod unavailable; using procedural rod fallback")
		return
	end

	for _, descendant in ipairs(loaded:GetDescendants()) do
		if
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("Sound")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
			or descendant:IsA("RemoteEvent")
			or descendant:IsA("RemoteFunction")
			or descendant:IsA("BindableEvent")
			or descendant:IsA("BindableFunction")
			or descendant:IsA("Humanoid")
			or descendant:IsA("AnimationController")
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	if not loaded:FindFirstChildWhichIsA("BasePart", true) then
		loaded:Destroy()
		warn("Fish A Baddie: Creator Store rod contained no usable parts; using procedural rod fallback")
		return
	end

	loaded.Name = "SanitizedFishingRod"
	loaded.Parent = nil
	self.ExternalRodTemplate = loaded
end

function RodToolService:_createExternalRodParts(tool, rodId)
	local visual = self.ExternalRodTemplate and self.ExternalRodTemplate:Clone()
	if not visual then
		return false
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Transparency = 1
	handle.Size = Vector3.new(0.35, 1.2, 0.35)
	handle.Parent = tool

	visual.Name = "CreatorStoreRodVisual"
	visual.Parent = tool
	local size = visual:GetExtentsSize()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0.01 then
		visual:ScaleTo(ExternalAssetConfig.FishingRod.TargetLengthStuds / longest)
	end

	local boundsCFrame, boundsSize = visual:GetBoundingBox()
	local orientation = CFrame.new()
	if boundsSize.X >= boundsSize.Y and boundsSize.X >= boundsSize.Z then
		orientation = CFrame.Angles(0, 0, math.rad(90))
	elseif boundsSize.Z >= boundsSize.X and boundsSize.Z >= boundsSize.Y then
		orientation = CFrame.Angles(math.rad(90), 0, 0)
	end
	local targetBounds = CFrame.new(0, 2.9, 0) * orientation
	visual:PivotTo(targetBounds * boundsCFrame:Inverse() * visual:GetPivot())
	local rodColor = PlaceholderFactory.GetRodColor(rodId)
	local rodIndex = table.find(RodConfig.Order, rodId) or 1

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.Color = descendant.Color:Lerp(rodColor, math.clamp(0.22 + (rodIndex * 0.025), 0.22, 0.5))
			if rodIndex >= 6 and descendant.Material == Enum.Material.SmoothPlastic then
				descendant.Material = Enum.Material.Metal
			end

			local weld = Instance.new("WeldConstraint")
			weld.Name = "RodVisualWeld"
			weld.Part0 = handle
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	return true
end

function RodToolService:_createRodParts(tool, rodId)
	if not self:_createExternalRodParts(tool, rodId) then
		PlaceholderFactory.CreateRodParts(tool, rodId)
	end
end

function RodToolService:Start()
	-- Loading a Creator Store asset may yield, so never block game startup on it.
	task.spawn(function()
		self:_loadExternalRodTemplate()
		if self.ExternalRodTemplate then
			for _, player in ipairs(Players:GetPlayers()) do
				local tool = self:_findTool(player)
				if tool then
					tool:SetAttribute("VisualRodId", nil)
					self:RefreshTool(player)
				end
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:_bindPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_disconnectPlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_bindPlayer(player)
	end
end

function RodToolService:_trackConnection(player, connection)
	self.ConnectionsByPlayer[player] = self.ConnectionsByPlayer[player] or {}
	table.insert(self.ConnectionsByPlayer[player], connection)
end

function RodToolService:_disconnectPlayer(player)
	for _, connection in ipairs(self.ConnectionsByPlayer[player] or {}) do
		connection:Disconnect()
	end

	self.ConnectionsByPlayer[player] = nil
	self:_disconnectToolConnections(player)
end

function RodToolService:_disconnectToolConnections(player)
	for _, connection in ipairs(self.ToolConnectionsByPlayer[player] or {}) do
		connection:Disconnect()
	end
	self.ToolConnectionsByPlayer[player] = nil
end

function RodToolService:_bindPlayer(player)
	self:_trackConnection(
		player,
		player.CharacterAdded:Connect(function()
			task.defer(function()
				self:EnsureTool(player)
			end)
		end)
	)

	task.defer(function()
		self:EnsureTool(player)
	end)
end

function RodToolService:_findTool(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute(TOOL_ATTRIBUTE) == true then
					return child
				end
			end
		end
	end

	return nil
end

function RodToolService:_notifyError(player, err)
	local router = self.Registry:Get("RemoteRouterService")
	router:Notify(player, "Error", router:_normalizeError(err))
end

function RodToolService:_notifyFishingResult(player, results)
	local router = self.Registry:Get("RemoteRouterService")
	router:NotifyFishingResult(player, results[2], results[3], results[4])
end

function RodToolService:_activate(player)
	if not player.Parent or self.Registry:Get("FishingService"):HasActiveSession(player) then
		return
	end

	local ok, err = pcall(function()
		self.Registry:Get("FishingService"):BeginCast(player, {
			Source = "Tool",
		})
	end)

	if not ok then
		self:_notifyError(player, err)
	end
end

function RodToolService:_deactivate(player)
	if not player.Parent or not self.Registry:Get("FishingService"):HasActiveSession(player) then
		return
	end

	local results = table.pack(pcall(function()
		return self.Registry:Get("FishingService"):ResolveActiveCast(player)
	end))

	if results[1] then
		self:_notifyFishingResult(player, results)
	else
		self:_notifyError(player, results[2])
	end
end

function RodToolService:_cancel(player)
	if player.Parent and self.Registry:Get("FishingService"):HasActiveSession(player) then
		self.Registry:Get("FishingService"):CancelCast(player)
	end
end

function RodToolService:_createTool(player)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute(TOOL_ATTRIBUTE, true)
	self:_createRodParts(tool, "StarterRod")
	tool:SetAttribute("VisualRodId", "StarterRod")
	tool.Grip = CFrame.new(0, -1.25, 0) * CFrame.Angles(0, 0, math.rad(-12))
	tool.Parent = backpack
	self:_disconnectToolConnections(player)

	self.ToolConnectionsByPlayer[player] = {
		tool.Activated:Connect(function()
			self:_activate(player)
		end),
		tool.Deactivated:Connect(function()
			self:_deactivate(player)
		end),
		tool.Unequipped:Connect(function()
			self:_cancel(player)
		end),
	}

	return tool
end

function RodToolService:EnsureTool(player)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	if not session or not player.Parent then
		return nil
	end

	local tool = self:_findTool(player) or self:_createTool(player)
	if not tool then
		return nil
	end

	self:RefreshTool(player)
	return tool
end

function RodToolService:RefreshTool(player)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	local tool = self:_findTool(player)
	if not session or not tool then
		return
	end

	local rodId = session.Profile.Progression.EquippedRodId
	local rod = RodConfig.Definitions[rodId] or RodConfig.Definitions.StarterRod
	local existingVisualRodId = tool:GetAttribute("VisualRodId")
	if existingVisualRodId ~= rod.Id then
		for _, child in ipairs(tool:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Model") then
				child:Destroy()
			end
		end
		self:_createRodParts(tool, rod.Id)
		tool:SetAttribute("VisualRodId", rod.Id)
	end

	tool.Name = rod.DisplayName
	tool.ToolTip = rod.PassiveText or "Fishing rod"
	tool:SetAttribute("RodId", rod.Id)
	tool:SetAttribute("LuckMultiplierBps", rod.LuckMultiplierBps or 10000)
	tool:SetAttribute("CastDurationSeconds", FormulaUtil.GetRodCastDuration(session.Profile))
	tool:SetAttribute("FishingWindowHalfWidth", FormulaUtil.GetFishingWindowHalfWidth(session.Profile))
end

return RodToolService
