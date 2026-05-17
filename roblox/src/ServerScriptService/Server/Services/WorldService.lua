local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NotificationCode = require(ReplicatedStorage.Shared.Enums.NotificationCode)
local PlotConfig = require(ReplicatedStorage.Shared.Config.PlotConfig)

local WorldService = {}
WorldService.__index = WorldService

local LEADERBOARD_DEFINITIONS = {
	{ Key = "FishCaught", Title = "Fish Caught", Position = Vector3.new(-30, 6, 30) },
	{ Key = "SecretsCaught", Title = "Secrets Caught", Position = Vector3.new(-10, 6, 34) },
	{ Key = "Rebirths", Title = "Rebirths", Position = Vector3.new(10, 6, 34) },
	{ Key = "Coins", Title = "Coins", Position = Vector3.new(30, 6, 30) },
}

local SHOP_DEFINITIONS = {
	{
		Id = "RodShop",
		DisplayName = "Rod Shop",
		Position = Vector3.new(-24, 3, 10),
		Entries = {
			"BreezeRod",
			"SurgeRod",
			"CoralRod",
			"FluxRod",
			"VoidlineRod",
			"LuminRod",
			"AurexRod",
			"DepthcoreRod",
			"EclipseRod",
		},
	},
	{
		Id = "BoostShop",
		DisplayName = "Boosts & Crates",
		Position = Vector3.new(-14, 3, 16),
		Entries = { "LuckBoost2x", "LuckBoost5x", "IncomeBoost2x", "IncomeBoost5x", "BasicCrateTicket" },
	},
	{
		Id = "CrateShop",
		DisplayName = "Crate Shop",
		Position = Vector3.new(-4, 3, 20),
		Entries = { "BasicCrateTicket", "BasicCrate", "PremiumCrate", "GodCrate", "AbyssCrate" },
	},
	{
		Id = "PlayerUpgradeShop",
		DisplayName = "Player Upgrades",
		Position = Vector3.new(4, 3, 20),
		Entries = {
			"PlotSlot1",
			"PlayerUpgradeCastSpeed",
			"PlayerUpgradeLuckTraining",
			"PlayerUpgradeTimingWindow",
			"PlayerUpgradeChainFocus",
		},
	},
	{
		Id = "PremiumShop",
		DisplayName = "Premium Shop",
		Position = Vector3.new(12, 3, 20),
		Entries = { "X2Income", "X2Luck", "AutoCatch", "AutoCollect", "VIP", "VIPPlus", "ExtraSlots2", "X3LuckStack" },
	},
	{
		Id = "TraitLab",
		DisplayName = "Trait Lab",
		Position = Vector3.new(18, 3, 16),
		Entries = { "TraitReroll", "TargetedTraitRoll", "GodTierTraitRoll", "LockTraitSlot", "TraitUpgradePack" },
	},
	{
		Id = "ComponentForge",
		DisplayName = "Component Forge",
		Position = Vector3.new(28, 3, 10),
		Entries = { "Line", "Hook", "Reel", "InstantMaxComponent", "InstantMaxAllComponents" },
	},
	{
		Id = "FusionShrine",
		DisplayName = "Fusion Shrine",
		Position = Vector3.new(18, 3, 0),
		Entries = { "FuseTemplate", "ConvertSecret" },
	},
	{
		Id = "RebirthAltar",
		DisplayName = "Rebirth Altar",
		Position = Vector3.new(-18, 3, 0),
		Entries = {
			"Execute",
			"InstantRebirth",
			"RebirthUpgradeGlobalIncome",
			"RebirthUpgradeGlobalLuck",
			"RebirthUpgradeRebirthCastSpeed",
			"RebirthUpgradeBoostDuration",
			"RebirthUpgradeStartingMomentum",
		},
	},
	{
		Id = "PlotShop",
		DisplayName = "Plot Shop",
		Position = Vector3.new(0, 3, 8),
		Entries = { "PlotSlot1", "ExtraSlots2" },
	},
}

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensurePart(parent, name, properties)
	local part = parent:FindFirstChild(name)
	if not part then
		part = Instance.new("Part")
		part.Name = name
		part.Parent = parent
	end

	for key, value in pairs(properties) do
		part[key] = value
	end

	return part
end

function WorldService.new(registry)
	return setmetatable({
		Registry = registry,
		PlotAnchors = {},
		LeaderboardBoards = {},
	}, WorldService)
end

function WorldService:Init()
	self.GameFolder = ensureFolder(Workspace, "Game")
	self.PlotsFolder = ensureFolder(self.GameFolder, "Plots")
	self.PlotModelsFolder = ensureFolder(self.GameFolder, "PlotModels")
	self.FishingCastsFolder = ensureFolder(self.GameFolder, "FishingCasts")
	self.LeaderboardsFolder = ensureFolder(self.GameFolder, "Leaderboards")
	self.ShopNPCsFolder = ensureFolder(self.GameFolder, "ShopNPCs")
	self.EventEffectsFolder = ensureFolder(self.GameFolder, "EventEffects")
	self.FishingCastsFolder:ClearAllChildren()
	self.EventEffectsFolder:ClearAllChildren()

	local legacyFishingZonesFolder = self.GameFolder:FindFirstChild("FishingZones")
	if legacyFishingZonesFolder then
		legacyFishingZonesFolder:Destroy()
	end

	self:_buildWorld()
end

function WorldService:_buildWorld()
	ensurePart(Workspace, "Baseplate", {
		Anchored = true,
		Size = Vector3.new(512, 8, 512),
		Position = Vector3.new(0, -4, 0),
		Color = Color3.fromRGB(188, 187, 181),
		Material = Enum.Material.Concrete,
	})

	local spawn = Workspace:FindFirstChild("SpawnLocation")
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Name = "SpawnLocation"
		spawn.Parent = Workspace
	end
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 1, 52)
	spawn.Neutral = true
	spawn.CanCollide = true

	ensurePart(self.GameFolder, "HarborPad", {
		Anchored = true,
		Size = Vector3.new(48, 1, 48),
		Position = Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(140, 110, 70),
		Material = Enum.Material.WoodPlanks,
	})

	ensurePart(self.GameFolder, "CentralIsland", {
		Anchored = true,
		Size = Vector3.new(72, 2, 52),
		Position = Vector3.new(0, 0.75, 12),
		Color = Color3.fromRGB(219, 187, 118),
		Material = Enum.Material.Sand,
	})

	self.WaterPart = ensurePart(self.GameFolder, "Water", {
		Anchored = true,
		Size = Vector3.new(86, 1, 120),
		Position = Vector3.new(0, 0, -44),
		Color = Color3.fromRGB(46, 147, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
	})

	for index = 1, PlotConfig.AnchorCount do
		self:GetOrCreatePlotAnchor(index)
	end

	self:_buildLeaderboardBoards()
	self:_buildShopNPCs()
end

function WorldService:_ensureSurfaceText(surfaceGui, name, position, size, textSize)
	local label = surfaceGui:FindFirstChild(name)
	if not label then
		label = Instance.new("TextLabel")
		label.Name = name
		label.Parent = surfaceGui
	end

	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 248, 220)
	label.TextStrokeTransparency = 0.35
	label.TextScaled = false
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left

	return label
end

function WorldService:_ensureSurfaceImage(surfaceGui, name, position, size)
	local image = surfaceGui:FindFirstChild(name)
	if not image then
		image = Instance.new("ImageLabel")
		image.Name = name
		image.Parent = surfaceGui
	end

	image.BackgroundTransparency = 1
	image.Position = position
	image.Size = size
	image.Image = ""

	return image
end

function WorldService:_buildLeaderboardBoards()
	self.LeaderboardBoards = {}

	for _, definition in ipairs(LEADERBOARD_DEFINITIONS) do
		local board = ensurePart(self.LeaderboardsFolder, definition.Key, {
			Anchored = true,
			Size = Vector3.new(16, 10, 1),
			Position = definition.Position,
			Color = Color3.fromRGB(32, 48, 68),
			Material = Enum.Material.SmoothPlastic,
		})
		board.CFrame = CFrame.lookAt(definition.Position, Vector3.new(0, definition.Position.Y, 8))
		board:SetAttribute("LeaderboardKey", definition.Key)
		self.LeaderboardBoards[definition.Key] = board

		local surfaceGui = board:FindFirstChild("SurfaceGui")
		if not surfaceGui then
			surfaceGui = Instance.new("SurfaceGui")
			surfaceGui.Name = "SurfaceGui"
			surfaceGui.Parent = board
		end

		surfaceGui.Face = Enum.NormalId.Front
		surfaceGui.CanvasSize = Vector2.new(900, 600)
		surfaceGui.LightInfluence = 0

		local title =
			self:_ensureSurfaceText(surfaceGui, "Title", UDim2.fromOffset(24, 12), UDim2.fromOffset(850, 54), 36)
		title.Text = definition.Title
		title.TextXAlignment = Enum.TextXAlignment.Center

		for index = 1, 10 do
			self:_ensureSurfaceImage(
				surfaceGui,
				"Avatar_" .. index,
				UDim2.fromOffset(42, 74 + ((index - 1) * 49)),
				UDim2.fromOffset(42, 42)
			)
			local row = self:_ensureSurfaceText(
				surfaceGui,
				"Row_" .. index,
				UDim2.fromOffset(96, 76 + ((index - 1) * 49)),
				UDim2.fromOffset(756, 42),
				27
			)
			row.Text = string.format("#%d  ---", index)
		end
	end
end

function WorldService:_openShop(player, shopDefinition)
	local router = self.Registry:Get("RemoteRouterService")
	router:Notify(player, "Shop", NotificationCode.ShopOpened, {
		ShopId = shopDefinition.Id,
		DisplayName = shopDefinition.DisplayName,
		Entries = shopDefinition.Entries,
	})
end

function WorldService:_buildShopNPCs()
	for _, definition in ipairs(SHOP_DEFINITIONS) do
		local shopDefinition = definition
		local npc = ensurePart(self.ShopNPCsFolder, definition.Id, {
			Anchored = true,
			Size = Vector3.new(3, 6, 3),
			Position = definition.Position,
			Color = Color3.fromRGB(78, 125, 178),
			Material = Enum.Material.SmoothPlastic,
		})
		npc:SetAttribute("ShopId", definition.Id)
		npc:SetAttribute("DisplayName", definition.DisplayName)

		local prompt = npc:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = npc
		end

		prompt.Name = "OpenShopPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = definition.DisplayName
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12

		if prompt:GetAttribute("FishABaddieBound") ~= true then
			prompt:SetAttribute("FishABaddieBound", true)
			prompt.Triggered:Connect(function(player)
				self:_openShop(player, shopDefinition)
			end)
		end
	end
end

function WorldService:GetOrCreatePlotAnchor(index)
	local anchor = self.PlotAnchors[index]
	if anchor and anchor.Parent then
		return anchor
	end

	local angle = (index - 1) / PlotConfig.AnchorCount * math.pi * 2
	local radius = 115
	local position = Vector3.new(math.cos(angle) * radius, 0.5, math.sin(angle) * radius)

	anchor = ensurePart(self.PlotsFolder, string.format("PlotAnchor_%02d", index), {
		Anchored = true,
		Size = Vector3.new(PlotConfig.CellSize * 7, 1, PlotConfig.CellSize * 4),
		Position = position,
		Color = Color3.fromRGB(96, 168, 86),
		Material = Enum.Material.Grass,
	})
	anchor:SetAttribute("PlotId", string.format("Plot_%02d", index))

	local direction = CFrame.lookAt(position + Vector3.new(0, 0, 0), Vector3.new(0, 0.5, 0))
	anchor.CFrame = direction
	self.PlotAnchors[index] = anchor
	anchor:SetAttribute("OwnerText", "Open Plot")
	self:SetPlotOwnerText(anchor:GetAttribute("PlotId"), "Open Plot")

	return anchor
end

function WorldService:SetPlotOwnerText(plotId, text)
	for _, anchor in ipairs(self.PlotAnchors) do
		if anchor:GetAttribute("PlotId") == plotId then
			anchor:SetAttribute("OwnerText", text)
			local billboard = anchor:FindFirstChild("OwnerBillboard")
			if not billboard then
				billboard = Instance.new("BillboardGui")
				billboard.Name = "OwnerBillboard"
				billboard.AlwaysOnTop = true
				billboard.LightInfluence = 0
				billboard.MaxDistance = 120
				billboard.Size = UDim2.fromOffset(240, 42)
				billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
				billboard.Parent = anchor
			end

			local label = billboard:FindFirstChild("Label")
			if not label then
				label = Instance.new("TextLabel")
				label.Name = "Label"
				label.BackgroundColor3 = Color3.fromRGB(28, 36, 28)
				label.BackgroundTransparency = 0.12
				label.BorderSizePixel = 0
				label.Font = Enum.Font.GothamBold
				label.TextColor3 = Color3.fromRGB(241, 255, 230)
				label.TextSize = 18
				label.TextWrapped = true
				label.Size = UDim2.fromScale(1, 1)
				label.Parent = billboard

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 6)
				corner.Parent = label
			end
			label.Text = text
			return
		end
	end
end

function WorldService:GetPlotAnchors()
	return self.PlotAnchors
end

function WorldService:GetFishingWaterPart()
	return self.WaterPart
end

function WorldService:GetFishingCastsFolder()
	return self.FishingCastsFolder
end

function WorldService:GetLeaderboardBoard(boardKey)
	return self.LeaderboardBoards[boardKey]
end

function WorldService:GetWaterSurfaceY()
	local water = self:GetFishingWaterPart()
	if not water then
		return nil
	end

	return water.Position.Y + (water.Size.Y / 2)
end

function WorldService:IsPointInFishingWater(point, margin)
	local water = self:GetFishingWaterPart()
	if not water then
		return false
	end

	margin = margin or 0
	local localPoint = water.CFrame:PointToObjectSpace(point)
	local halfSize = water.Size / 2

	return math.abs(localPoint.X) <= halfSize.X + margin and math.abs(localPoint.Z) <= halfSize.Z + margin
end

function WorldService:SpawnRareCatchBurst(player, rarityId)
	if rarityId ~= "Secret" and rarityId ~= "Mythic" then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local effectPart = Instance.new("Part")
	effectPart.Name = rarityId .. "CatchBurst"
	effectPart.Anchored = true
	effectPart.CanCollide = false
	effectPart.CanTouch = false
	effectPart.CanQuery = false
	effectPart.Transparency = 1
	effectPart.Size = Vector3.new(1, 1, 1)
	effectPart.Position = root.Position + Vector3.new(0, 4, 0)
	effectPart.Parent = self.EventEffectsFolder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Burst"
	emitter.Color =
		ColorSequence.new(rarityId == "Secret" and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 60, 140))
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(1.2, 1.8)
	emitter.Speed = NumberRange.new(22, 38)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = effectPart
	emitter:Emit(rarityId == "Secret" and 240 or 120)

	task.delay(3, function()
		if effectPart.Parent then
			effectPart:Destroy()
		end
	end)
end

function WorldService:Start()
	Players.CharacterAutoLoads = true
end

return WorldService
