local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FormulaUtil = require(Shared.Util.FormulaUtil)
local RodConfig = require(Shared.Config.RodConfig)

local RodToolService = {}
RodToolService.__index = RodToolService

local TOOL_ATTRIBUTE = "FishABaddieRodTool"

function RodToolService.new(registry)
	return setmetatable({
		Registry = registry,
		ConnectionsByPlayer = {},
	}, RodToolService)
end

function RodToolService:Start()
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
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute(TOOL_ATTRIBUTE, true)
	tool.Parent = backpack

	self:_trackConnection(
		player,
		tool.Activated:Connect(function()
			self:_activate(player)
		end)
	)

	self:_trackConnection(
		player,
		tool.Deactivated:Connect(function()
			self:_deactivate(player)
		end)
	)

	self:_trackConnection(
		player,
		tool.Unequipped:Connect(function()
			self:_cancel(player)
		end)
	)

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

	tool.Name = rod.DisplayName
	tool.ToolTip = rod.PassiveText or "Fishing rod"
	tool:SetAttribute("RodId", rod.Id)
	tool:SetAttribute("LuckMultiplierBps", rod.LuckMultiplierBps or 10000)
	tool:SetAttribute("CastDurationSeconds", FormulaUtil.GetRodCastDuration(session.Profile))
	tool:SetAttribute("FishingWindowHalfWidth", FormulaUtil.GetFishingWindowHalfWidth(session.Profile))
end

return RodToolService
