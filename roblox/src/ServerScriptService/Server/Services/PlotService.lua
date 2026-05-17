local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BaddieConfig = require(Shared.Config.BaddieConfig)
local FormulaUtil = require(Shared.Util.FormulaUtil)
local PlotConfig = require(Shared.Config.PlotConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local GridUtil = require(Shared.Util.GridUtil)
local TableUtil = require(Shared.Util.TableUtil)

local PlotService = {}
PlotService.__index = PlotService

local function fail(code)
	error(code, 0)
end

function PlotService.new(registry)
	return setmetatable({
		Registry = registry,
		AssignedPlotsByPlayer = {},
		AssignedPlayersByPlotId = {},
	}, PlotService)
end

function PlotService:Init()
	local worldService = self.Registry:Get("WorldService")
	self.PlotModelsFolder = worldService.PlotModelsFolder
end

function PlotService:_getEffectivePlotSlots(profile)
	return profile.Progression.PlotSlots + (profile.Premium.Effects.ExtraSlots or 0)
end

function PlotService:GetUnlockedGridDimensions(profile)
	local effectiveSlots = self:_getEffectivePlotSlots(profile)
	local gridHeight = PlotConfig.DefaultGridHeight
	local gridWidth = math.max(PlotConfig.DefaultGridWidth, math.ceil(effectiveSlots / gridHeight))
	return gridWidth, gridHeight, effectiveSlots
end

function PlotService:GetGridDimensions(profile)
	local effectiveSlots = self:_getEffectivePlotSlots(profile)
	local gridHeight = PlotConfig.DefaultGridHeight
	local displaySlots = effectiveSlots + (PlotConfig.LockedPreviewSlots or 0)
	local gridWidth = math.max(PlotConfig.DefaultGridWidth, math.ceil(displaySlots / gridHeight))
	return gridWidth, gridHeight, effectiveSlots
end

function PlotService:IsCellUnlocked(profile, gridX, gridY)
	local gridWidth, gridHeight, effectiveSlots = self:GetUnlockedGridDimensions(profile)
	if not GridUtil.IsInsideBounds(gridX, gridY, gridWidth, gridHeight) then
		return false
	end

	local cellIndex = (gridY - 1) * gridWidth + gridX
	return cellIndex >= 1 and cellIndex <= effectiveSlots
end

function PlotService:AssignPlot(player)
	if self.AssignedPlotsByPlayer[player] then
		return self.AssignedPlotsByPlayer[player]
	end

	local worldService = self.Registry:Get("WorldService")
	local selectedAnchor = nil

	for _, anchor in ipairs(worldService:GetPlotAnchors()) do
		local plotId = anchor:GetAttribute("PlotId")
		if not self.AssignedPlayersByPlotId[plotId] then
			selectedAnchor = anchor
			break
		end
	end

	if not selectedAnchor then
		selectedAnchor = worldService:GetOrCreatePlotAnchor(#worldService:GetPlotAnchors() + 1)
	end

	local plotId = selectedAnchor:GetAttribute("PlotId")
	local modelFolder = self.PlotModelsFolder:FindFirstChild(plotId)
	if not modelFolder then
		modelFolder = Instance.new("Folder")
		modelFolder.Name = plotId
		modelFolder.Parent = self.PlotModelsFolder
	end

	local plot = {
		PlotId = plotId,
		Anchor = selectedAnchor,
		ModelFolder = modelFolder,
	}

	self.AssignedPlotsByPlayer[player] = plot
	self.AssignedPlayersByPlotId[plotId] = player
	selectedAnchor:SetAttribute("OwnerUserId", player.UserId)
	selectedAnchor:SetAttribute("OwnerName", player.DisplayName)
	modelFolder:SetAttribute("OwnerUserId", player.UserId)
	modelFolder:SetAttribute("OwnerName", player.DisplayName)
	modelFolder:SetAttribute("PlotId", plotId)
	worldService:SetPlotOwnerText(plotId, string.format("%s's Plot", player.DisplayName))
	self:RefreshVisuals(player)

	return plot
end

function PlotService:ReleasePlot(player)
	local plot = self.AssignedPlotsByPlayer[player]
	if not plot then
		return
	end

	self.AssignedPlotsByPlayer[player] = nil
	self.AssignedPlayersByPlotId[plot.PlotId] = nil
	plot.Anchor:SetAttribute("OwnerUserId", nil)
	plot.Anchor:SetAttribute("OwnerName", nil)
	self.Registry:Get("WorldService"):SetPlotOwnerText(plot.PlotId, "Open Plot")

	if plot.ModelFolder then
		plot.ModelFolder:SetAttribute("OwnerUserId", nil)
		plot.ModelFolder:SetAttribute("OwnerName", nil)
		plot.ModelFolder:ClearAllChildren()
	end
end

function PlotService:GetAssignedPlot(player)
	return self.AssignedPlotsByPlayer[player]
end

function PlotService:GetCellWorldPosition(player, gridX, gridY)
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local plot = self:GetAssignedPlot(player)
	if not plot then
		fail("PlotNotAssigned")
	end

	local gridWidth, gridHeight = self:GetUnlockedGridDimensions(session.Profile)
	local cellSize = PlotConfig.CellSize
	local localX = ((gridX - 0.5) - gridWidth / 2) * cellSize
	local localZ = ((gridY - 0.5) - gridHeight / 2) * cellSize
	local worldPosition = (plot.Anchor.CFrame * CFrame.new(localX, 1.5, localZ)).Position

	return worldPosition
end

function PlotService:_getRarityIndex(rarityId)
	return table.find(RarityConfig.Order, rarityId) or 0
end

function PlotService:_createGridVisuals(player, plot, gridWidth, gridHeight)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	local cellSize = PlotConfig.CellSize
	local unlockedGridWidth = session and select(1, self:GetUnlockedGridDimensions(session.Profile)) or gridWidth
	local totalWidth = gridWidth * cellSize
	local totalHeight = gridHeight * cellSize
	local lineThickness = 0.08

	local gridFolder = Instance.new("Folder")
	gridFolder.Name = "GridLines"
	gridFolder.Parent = plot.ModelFolder

	for x = 0, gridWidth do
		local line = Instance.new("Part")
		line.Name = "GridLineX_" .. x
		line.Anchored = true
		line.CanCollide = false
		line.CanTouch = false
		line.CanQuery = false
		line.Size = Vector3.new(lineThickness, lineThickness, totalHeight)
		line.CFrame = plot.Anchor.CFrame * CFrame.new((x - (unlockedGridWidth / 2)) * cellSize, 1.03, 0)
		line.Color = Color3.fromRGB(255, 235, 178)
		line.Material = Enum.Material.Neon
		line.Transparency = 0.35
		line.Parent = gridFolder
	end

	for y = 0, gridHeight do
		local line = Instance.new("Part")
		line.Name = "GridLineY_" .. y
		line.Anchored = true
		line.CanCollide = false
		line.CanTouch = false
		line.CanQuery = false
		line.Size = Vector3.new(totalWidth, lineThickness, lineThickness)
		line.CFrame = plot.Anchor.CFrame * CFrame.new(((gridWidth / 2) - (unlockedGridWidth / 2)) * cellSize, 1.04, (y - (gridHeight / 2)) * cellSize)
		line.Color = Color3.fromRGB(255, 235, 178)
		line.Material = Enum.Material.Neon
		line.Transparency = 0.35
		line.Parent = gridFolder
	end
end

function PlotService:_createCellVisuals(player, plot, gridWidth, gridHeight)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	if not session then
		return
	end

	local profile = session.Profile
	local cellSize = PlotConfig.CellSize
	local occupiedCells = {}
	for baddieId, placement in pairs(profile.Placements) do
		occupiedCells[GridUtil.GetCellKey(placement.GridX, placement.GridY)] = baddieId
	end

	local cellsFolder = Instance.new("Folder")
	cellsFolder.Name = "Cells"
	cellsFolder.Parent = plot.ModelFolder

	for y = 1, gridHeight do
		for x = 1, gridWidth do
			local cellKey = GridUtil.GetCellKey(x, y)
			local occupiedBaddieId = occupiedCells[cellKey]
			local unlocked = self:IsCellUnlocked(profile, x, y)

			local cell = Instance.new("Part")
			cell.Name = "Cell_" .. cellKey
			cell.Anchored = true
			cell.CanCollide = false
			cell.CanTouch = false
			cell.CanQuery = true
			cell.Size = Vector3.new(cellSize - 0.35, 0.18, cellSize - 0.35)
			cell.Position = self:GetCellWorldPosition(player, x, y) - Vector3.new(0, 0.72, 0)
			cell.Material = Enum.Material.SmoothPlastic
			cell.Transparency = unlocked and 0.42 or 0.18
			cell.Color = unlocked and (occupiedBaddieId and Color3.fromRGB(91, 140, 93) or Color3.fromRGB(72, 128, 85)) or Color3.fromRGB(80, 84, 92)
			cell:SetAttribute("IsPlotCell", true)
			cell:SetAttribute("PlotId", plot.PlotId)
			cell:SetAttribute("OwnerUserId", player.UserId)
			cell:SetAttribute("OwnerName", player.DisplayName)
			cell:SetAttribute("CellKey", cellKey)
			cell:SetAttribute("GridX", x)
			cell:SetAttribute("GridY", y)
			cell:SetAttribute("Unlocked", unlocked)
			cell:SetAttribute("OccupiedBaddieId", occupiedBaddieId)
			cell.Parent = cellsFolder
		end
	end
end

function PlotService:_getBaddieAsset(templateId)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local baddieAssets = assets and assets:FindFirstChild("Baddies")
	return baddieAssets and baddieAssets:FindFirstChild(templateId)
end

function PlotService:_getEffectPart(visual)
	if visual:IsA("BasePart") then
		return visual
	end

	if visual:IsA("Model") then
		return visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

function PlotService:_buildTraitSummary(baddie)
	local values = {}
	for _, traitId in ipairs(baddie.TraitIds or {}) do
		if traitId and traitId ~= "None" then
			table.insert(values, traitId)
		end
	end

	if #values == 0 then
		return "No trait"
	end

	return table.concat(values, ", ")
end

function PlotService:_writeBaddieAttributes(visual, owner, baddie, definition, incomePerSecond)
	local attributes = {
		BaddieId = baddie.Id,
		TemplateId = definition.Id,
		BaddieName = definition.DisplayName,
		RarityId = baddie.RarityId,
		Level = baddie.Level,
		OwnerUserId = owner.UserId,
		OwnerName = owner.DisplayName,
		TraitSummary = self:_buildTraitSummary(baddie),
		IncomePerSecond = incomePerSecond,
	}

	for key, value in pairs(attributes) do
		visual:SetAttribute(key, value)
	end

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			for key, value in pairs(attributes) do
				descendant:SetAttribute(key, value)
			end
		end
	end
end

function PlotService:_createBaddieBillboard(visual, baddie, definition, incomePerSecond)
	local effectPart = self:_getEffectPart(visual)
	if not effectPart then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BaddieLabel"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Size = UDim2.fromOffset(210, 72)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	billboard.Parent = effectPart

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	label.BackgroundTransparency = 0.18
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = RarityConfig.RewardColors[baddie.RarityId] or Color3.new(1, 1, 1)
	label.TextSize = 13
	label.TextWrapped = true
	label.Size = UDim2.fromScale(1, 1)
	label.Text = string.format("%s\n%s  Lv.%d\n%.1f coins/s", definition.DisplayName, baddie.RarityId, baddie.Level, incomePerSecond)
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
end

function PlotService:_applyRarityEffects(visual, rarityId)
	local effectPart = self:_getEffectPart(visual)
	if not effectPart then
		return
	end

	local color = RarityConfig.RewardColors[rarityId] or Color3.new(1, 1, 1)
	local rarityIndex = self:_getRarityIndex(rarityId)

	if rarityIndex >= self:_getRarityIndex("Rare") then
		local light = Instance.new("PointLight")
		light.Name = "RarityGlow"
		light.Color = color
		light.Range = rarityId == "Secret" and 24 or 14
		light.Brightness = rarityId == "Secret" and 4 or 1.5
		light.Parent = effectPart
	end

	if rarityIndex >= self:_getRarityIndex("Epic") then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "RarityAura"
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 0.7
		emitter.Lifetime = NumberRange.new(1, rarityId == "Secret" and 2.5 or 1.6)
		emitter.Rate = rarityIndex >= self:_getRarityIndex("Mythic") and 18 or 8
		emitter.Speed = NumberRange.new(0.7, rarityId == "Secret" and 2.2 or 1.2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = effectPart
	end
end

function PlotService:_playIdleAnimation(visual)
	if not visual:IsA("Model") then
		return
	end

	local humanoid = visual:FindFirstChildOfClass("Humanoid")
	local idleAnimation = visual:FindFirstChild("IdleAnimation", true)
	if not humanoid or not idleAnimation or not idleAnimation:IsA("Animation") then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	local ok, track = pcall(function()
		return animator:LoadAnimation(idleAnimation)
	end)

	if ok and track then
		track.Looped = true
		track:Play()
	end
end

function PlotService:_createPlacedBaddieVisual(player, baddie, definition, placement)
	local position = self:GetCellWorldPosition(player, placement.GridX, placement.GridY)
	local rotationCFrame = CFrame.Angles(0, math.rad(placement.Rotation or 0), 0)
	local asset = self:_getBaddieAsset(definition.Id)
	local visual = nil

	if asset then
		visual = asset:Clone()
		visual.Name = baddie.Id

		if visual:IsA("Model") then
			visual:PivotTo(CFrame.new(position) * rotationCFrame)
			for _, descendant in ipairs(visual:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
				end
			end
		elseif visual:IsA("BasePart") then
			visual.Anchored = true
			visual.CanCollide = false
			visual.CFrame = CFrame.new(position) * rotationCFrame
		end
	else
		visual = Instance.new("Part")
		visual.Name = baddie.Id
		visual.Anchored = true
		visual.Size = Vector3.new(3.5, 3.5, 3.5)
		visual.Position = position
		visual.Material = Enum.Material.Neon
		visual.Color = definition.DisplayColor or (RarityConfig.RewardColors[baddie.RarityId] or Color3.new(1, 1, 1))
	end

	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	local incomePerSecond = session and FormulaUtil.GetBaddieIncomePerSecond(baddie, session.Profile) or 0
	self:_writeBaddieAttributes(visual, player, baddie, definition, incomePerSecond)
	visual.Parent = self:GetAssignedPlot(player).ModelFolder

	self:_applyRarityEffects(visual, baddie.RarityId)
	self:_createBaddieBillboard(visual, baddie, definition, incomePerSecond)
	self:_playIdleAnimation(visual)
end

function PlotService:BuildReplicaPlotState(player)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	local plot = self:GetAssignedPlot(player)
	if not session or not plot then
		return {
			PlotId = nil,
			GridWidth = 0,
			GridHeight = 0,
			EffectiveSlots = 0,
			HeldBaddieId = nil,
			Cells = {},
			Placements = {},
			OccupiedCells = {},
		}
	end

	local gridWidth, gridHeight = self:GetGridDimensions(session.Profile)
	local _, _, effectiveSlots = self:GetGridDimensions(session.Profile)
	local occupiedCells = {}
	for baddieId, placement in pairs(session.Profile.Placements) do
		occupiedCells[GridUtil.GetCellKey(placement.GridX, placement.GridY)] = baddieId
	end
	local cells = {}
	for y = 1, gridHeight do
		for x = 1, gridWidth do
			local cellKey = GridUtil.GetCellKey(x, y)
			cells[cellKey] = {
				GridX = x,
				GridY = y,
				Unlocked = self:IsCellUnlocked(session.Profile, x, y),
				OccupiedBaddieId = occupiedCells[cellKey],
			}
		end
	end

	return {
		PlotId = plot.PlotId,
		GridWidth = gridWidth,
		GridHeight = gridHeight,
		EffectiveSlots = effectiveSlots,
		HeldBaddieId = session.Runtime.HeldBaddieId,
		Cells = cells,
		Placements = TableUtil.DeepCopy(session.Profile.Placements),
		OccupiedCells = occupiedCells,
	}
end

function PlotService:RefreshVisuals(player)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	local plot = self:GetAssignedPlot(player)
	if not session or not plot or not plot.ModelFolder then
		return
	end

	plot.ModelFolder:ClearAllChildren()
	local gridWidth, gridHeight = self:GetGridDimensions(session.Profile)
	self:_createCellVisuals(player, plot, gridWidth, gridHeight)
	self:_createGridVisuals(player, plot, gridWidth, gridHeight)

	for baddieId, placement in pairs(session.Profile.Placements) do
		local baddie = session.Profile.Inventory.Baddies[baddieId]
		local definition = baddie and BaddieConfig.Definitions[baddie.TemplateId]
		if baddie and definition then
			self:_createPlacedBaddieVisual(player, baddie, definition, placement)
		end
	end
end

return PlotService
