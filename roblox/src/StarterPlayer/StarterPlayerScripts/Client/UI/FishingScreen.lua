local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BaddieConfig = require(Shared.Config.BaddieConfig)
local FishingConfig = require(Shared.Config.FishingConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local RodConfig = require(Shared.Config.RodConfig)
local PlaceholderFactory = require(Shared.Util.PlaceholderFactory)

local localPlayer = Players.LocalPlayer

local FishingScreen = {
	Network = nil,
	ReplicaClient = nil,
	Replica = nil,
	Gui = nil,
	ActiveSessionId = nil,
	LocalCastStartedAt = nil,
	RevealToken = 0,
	ToastToken = 0,
	CatchQueue = {},
}

local ERROR_TEXT = {
	FishingAlreadyActive = "You already have a line in the water.",
	FishingCooldown = "Give the reel a moment.",
	FishingNoCharacter = "Your character is not ready yet.",
	FishingNoWater = "The fishing water is unavailable.",
	FishingNotActive = "Cast your line first.",
	FishingTargetInvalid = "Face the water before casting.",
	FishingTargetTooClose = "Stand back and cast farther.",
	FishingTargetTooFar = "That cast is out of range.",
	FishingValidationFailed = "That cast could not be verified.",
	FishingRateLimited = "Slow down for a moment.",
	NotEnoughCoins = "You need more coins.",
	NotEnoughFusionShards = "Fuse more duplicate baddies for fusion shards.",
	NotEnoughTraitCredits = "Buy a trait credit at the Trait Lab first.",
	TraitAlreadyMaxTier = "That trait is already max tier.",
	TraitSlotLocked = "That trait slot is locked.",
	PlacementOccupied = "That plot slot is occupied.",
	PlacementTooFar = "Move closer to your plot.",
	BaddieMustBePlaced = "Place this baddie before taking them on a date.",
	DateCooldown = "They need a minute before another date.",
	AffectionMaxed = "Chemistry is already maxed!",
	FuseRequirementNotMet = "You need five unplaced duplicates to fuse.",
	UpgradeMaxLevel = "That upgrade is already maxed, or you need more coins.",
	PremiumProductUnavailable = "This premium item is not configured yet.",
	RequestFailed = "Something went wrong. Try again.",
}

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function addCorner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function addStroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color or Color3.fromRGB(80, 103, 132),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
	}, parent)
end

local function addGradient(parent, first, second, rotation)
	return create("UIGradient", {
		Color = ColorSequence.new(first, second),
		Rotation = rotation or 0,
	}, parent)
end

local function formatNumber(value)
	value = math.floor(tonumber(value) or 0)
	local absolute = math.abs(value)
	if absolute >= 1e12 then
		return string.format("%.2fT", value / 1e12)
	elseif absolute >= 1e9 then
		return string.format("%.2fB", value / 1e9)
	elseif absolute >= 1e6 then
		return string.format("%.2fM", value / 1e6)
	elseif absolute >= 1e3 then
		return string.format("%.1fK", value / 1e3)
	end
	return tostring(value)
end

local function makeText(parent, text, size, bold)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = Color3.fromRGB(244, 249, 255),
		TextSize = size,
		TextWrapped = true,
	}, parent)
end

local function createCatchVisual(definition, fallbackColor)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local baddieAssets = assets and assets:FindFirstChild("Baddies")
	local source = baddieAssets and baddieAssets:FindFirstChild(definition.Id)
	local visual = source and source:Clone()

	if not visual or (not visual:IsA("Model") and not visual:IsA("BasePart")) then
		if visual then
			visual:Destroy()
		end
		visual = PlaceholderFactory.CreateBaddie(definition.Id, definition.DisplayColor or fallbackColor, true)
	end

	if visual:IsA("Model") then
		for _, descendant in ipairs(visual:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
		visual:PivotTo(CFrame.new(0, 0.15, 0) * CFrame.Angles(0, math.rad(18), 0))
	else
		visual.Anchored = true
		visual.CanCollide = false
		visual.CFrame = CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.rad(18), 0)
	end

	return visual
end

function FishingScreen:_buildTopHud(gui)
	local hud = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(13, 24, 38),
		BackgroundTransparency = 0.08,
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.new(0.7, 0, 0, 68),
	}, gui)
	self.Hud = hud
	addCorner(hud, 16)
	addStroke(hud, Color3.fromRGB(86, 177, 229), 1.5, 0.25)
	addGradient(hud, Color3.fromRGB(15, 31, 50), Color3.fromRGB(18, 48, 68), 0)
	create("UISizeConstraint", { MaxSize = Vector2.new(760, 68), MinSize = Vector2.new(280, 62) }, hud)

	local title = makeText(hud, "FISH A BADDIE", 19, true)
	title.Position = UDim2.fromOffset(18, 8)
	title.Size = UDim2.new(0.35, 0, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(113, 224, 255)

	self.RodLabel = makeText(hud, "Starter Rod", 12, false)
	self.RodLabel.Position = UDim2.fromOffset(18, 34)
	self.RodLabel.Size = UDim2.new(0.38, 0, 0, 21)
	self.RodLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.RodLabel.TextColor3 = Color3.fromRGB(180, 201, 218)

	self.CoinLabel = makeText(hud, "0 coins", 17, true)
	self.CoinLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.CoinLabel.Position = UDim2.new(0.57, 0, 0, 12)
	self.CoinLabel.Size = UDim2.new(0.24, 0, 0, 22)
	self.CoinLabel.TextColor3 = Color3.fromRGB(255, 220, 90)

	self.CaughtLabel = makeText(hud, "0 caught", 12, false)
	self.CaughtLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.CaughtLabel.Position = UDim2.new(0.57, 0, 0, 37)
	self.CaughtLabel.Size = UDim2.new(0.24, 0, 0, 18)
	self.CaughtLabel.TextColor3 = Color3.fromRGB(180, 201, 218)

	self.ClaimButton = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(36, 185, 116),
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(136, 44),
		Text = "CLAIM  0",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 13,
	}, hud)
	addCorner(self.ClaimButton, 12)
	addStroke(self.ClaimButton, Color3.fromRGB(138, 255, 193), 1, 0.35)
	self.ClaimButton.Activated:Connect(function()
		self.Network:SendClaim({ Action = "ClaimIncome" })
	end)
end

function FishingScreen:_buildFishingPanel(gui)
	local panel = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(10, 20, 33),
		BackgroundTransparency = 0.05,
		Position = UDim2.new(0.5, 0, 1, -34),
		Size = UDim2.new(0.62, 0, 0, 148),
	}, gui)
	self.FishingPanel = panel
	addCorner(panel, 18)
	addStroke(panel, Color3.fromRGB(75, 166, 220), 1.5, 0.2)
	create("UISizeConstraint", { MaxSize = Vector2.new(650, 148), MinSize = Vector2.new(280, 138) }, panel)

	self.StatusLabel = makeText(panel, "FACE THE WATER", 18, true)
	self.StatusLabel.Position = UDim2.new(0, 18, 0, 10)
	self.StatusLabel.Size = UDim2.new(1, -36, 0, 24)
	self.StatusLabel.TextColor3 = Color3.fromRGB(127, 224, 255)

	self.SubtitleLabel = makeText(panel, "Equip your rod or press F to cast", 12, false)
	self.SubtitleLabel.Position = UDim2.new(0, 18, 0, 35)
	self.SubtitleLabel.Size = UDim2.new(1, -36, 0, 18)
	self.SubtitleLabel.TextColor3 = Color3.fromRGB(174, 195, 214)

	local meterBack = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(30, 42, 56),
		ClipsDescendants = true,
		Position = UDim2.new(0, 18, 0, 61),
		Size = UDim2.new(1, -166, 0, 48),
	}, panel)
	self.MeterBack = meterBack
	addCorner(meterBack, 12)
	addStroke(meterBack, Color3.fromRGB(103, 126, 151), 1, 0.3)

	self.MeterFill = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(42, 135, 235),
		Size = UDim2.fromScale(0, 1),
	}, meterBack)
	addGradient(self.MeterFill, Color3.fromRGB(45, 130, 235), Color3.fromRGB(86, 205, 255), 0)

	self.SweetSpot = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(70, 235, 139),
		BackgroundTransparency = 0.12,
		Position = UDim2.fromScale(0.35, 0),
		Size = UDim2.fromScale(0.13, 1),
		Visible = false,
	}, meterBack)
	addStroke(self.SweetSpot, Color3.fromRGB(215, 255, 225), 2, 0.05)

	self.Marker = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(5, 42),
		Visible = false,
	}, meterBack)
	addCorner(self.Marker, 3)

	self.ActionButton = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(28, 150, 225),
		Font = Enum.Font.GothamBlack,
		Position = UDim2.new(1, -18, 0, 61),
		Size = UDim2.fromOffset(120, 48),
		Text = "CAST",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 19,
	}, panel)
	addCorner(self.ActionButton, 12)
	addStroke(self.ActionButton, Color3.fromRGB(167, 232, 255), 1.5, 0.2)
	self.ActionButton.Activated:Connect(function()
		self:ToggleFishing()
	end)

	self.ChainLabel = makeText(panel, "Perfect catches build a luck chain", 11, false)
	self.ChainLabel.Position = UDim2.new(0, 18, 1, -27)
	self.ChainLabel.Size = UDim2.new(1, -36, 0, 17)
	self.ChainLabel.TextColor3 = Color3.fromRGB(151, 174, 195)
end

function FishingScreen:_buildToast(gui)
	self.Toast = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(19, 31, 45),
		BackgroundTransparency = 0.04,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0.9, 0, 0, 48),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 14,
		TextWrapped = true,
		Visible = false,
		ZIndex = 20,
	}, gui)
	addCorner(self.Toast, 12)
	self.ToastStroke = addStroke(self.Toast, Color3.fromRGB(101, 205, 255), 1.5, 0.1)
	create("UISizeConstraint", { MaxSize = Vector2.new(440, 48), MinSize = Vector2.new(260, 48) }, self.Toast)
end

function FishingScreen:_buildReveal(gui)
	local shade = create("Frame", {
		Active = true,
		BackgroundColor3 = Color3.fromRGB(2, 7, 13),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
	}, gui)
	self.RevealShade = shade

	local card = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(17, 28, 42),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(390, 430),
		ZIndex = 31,
	}, shade)
	self.RevealCard = card
	self.RevealScale = create("UIScale", { Scale = 1 }, card)
	addCorner(card, 22)
	self.RevealStroke = addStroke(card, Color3.fromRGB(106, 205, 255), 3, 0)

	self.RevealKicker = makeText(card, "YOU CAUGHT", 14, true)
	self.RevealKicker.ZIndex = 32
	self.RevealKicker.Position = UDim2.new(0, 20, 0, 18)
	self.RevealKicker.Size = UDim2.new(1, -40, 0, 20)
	self.RevealKicker.TextColor3 = Color3.fromRGB(165, 205, 228)

	self.RevealName = makeText(card, "Baddie", 32, true)
	self.RevealName.ZIndex = 32
	self.RevealName.Position = UDim2.new(0, 20, 0, 41)
	self.RevealName.Size = UDim2.new(1, -40, 0, 42)

	local viewport = create("ViewportFrame", {
		Ambient = Color3.fromRGB(190, 205, 225),
		BackgroundColor3 = Color3.fromRGB(11, 42, 62),
		LightColor = Color3.fromRGB(255, 249, 225),
		LightDirection = Vector3.new(-1, -1, -1),
		Position = UDim2.fromOffset(30, 94),
		Size = UDim2.new(1, -60, 0, 245),
		ZIndex = 32,
	}, card)
	self.RevealViewport = viewport
	addCorner(viewport, 18)
	addGradient(viewport, Color3.fromRGB(12, 51, 76), Color3.fromRGB(20, 24, 48), 90)

	self.RevealRarity = makeText(card, "COMMON", 18, true)
	self.RevealRarity.ZIndex = 32
	self.RevealRarity.Position = UDim2.new(0, 20, 0, 350)
	self.RevealRarity.Size = UDim2.new(1, -40, 0, 24)

	self.RevealDetails = makeText(card, "Added to your Baddies inventory", 12, false)
	self.RevealDetails.ZIndex = 32
	self.RevealDetails.Position = UDim2.new(0, 20, 0, 379)
	self.RevealDetails.Size = UDim2.new(1, -40, 0, 20)
	self.RevealDetails.TextColor3 = Color3.fromRGB(174, 195, 214)

	local continue = create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -40, 0, 24),
		Text = "click anywhere to continue",
		TextColor3 = Color3.fromRGB(145, 170, 193),
		TextSize = 11,
		ZIndex = 33,
	}, card)
	continue.Activated:Connect(function()
		self:HideReveal()
	end)
	shade.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self:HideReveal()
		end
	end)
end

function FishingScreen:BuildGui()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local oldGui = playerGui:FindFirstChild("FishABaddieMain")
	if oldGui then
		oldGui:Destroy()
	end

	local gui = create("ScreenGui", {
		Name = "FishABaddieMain",
		DisplayOrder = 5,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	self.Gui = gui

	self:_buildTopHud(gui)
	self:_buildFishingPanel(gui)
	self:_buildToast(gui)
	self:_buildReveal(gui)
	self:ApplyResponsiveLayout()
end

function FishingScreen:ApplyResponsiveLayout()
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local narrow = viewport.X < 540
	self.Hud.Size = UDim2.new(narrow and 0.96 or 0.7, 0, 0, 68)
	self.ClaimButton.Size = UDim2.fromOffset(narrow and 96 or 136, 44)
	self.ClaimButton.TextSize = narrow and 11 or 13
	self.RodLabel.Visible = not narrow
	self.RevealScale.Scale = math.min(1, (viewport.X - 20) / 390, (viewport.Y - 20) / 430)
end

function FishingScreen:ToggleFishing()
	if self.Replica and self.Replica.Fishing then
		self.Network:SendFishing({ Action = "ReleaseCast" })
	else
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		if humanoid and backpack then
			for _, child in ipairs(backpack:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("FishABaddieRodTool") == true then
					humanoid:EquipTool(child)
					break
				end
			end
		end
		self.Network:SendFishing({ Action = "BeginCast", Source = "HUD" })
	end
end

function FishingScreen:RenderHud()
	local replica = self.Replica
	if not replica then
		return
	end

	local wallet = replica.Wallet or {}
	local progression = replica.Progression or {}
	local stats = replica.Stats or {}
	local rod = RodConfig.Definitions[progression.EquippedRodId or "StarterRod"] or RodConfig.Definitions.StarterRod
	self.RodLabel.Text = string.format("%s  •  %.2fx luck", rod.DisplayName, (rod.LuckMultiplierBps or 10000) / 10000)
	self.CoinLabel.Text = formatNumber(wallet.Coins) .. " coins"
	self.CaughtLabel.Text = formatNumber(stats.LifetimeCaught) .. " caught"
	self.ClaimButton.Text = "CLAIM  " .. formatNumber(wallet.UnclaimedCoins)
	self.ClaimButton.BackgroundColor3 = (wallet.UnclaimedCoins or 0) > 0 and Color3.fromRGB(36, 185, 116)
		or Color3.fromRGB(62, 82, 94)

	local chainBonus = progression.ChainBonus or 0
	if chainBonus > 0 then
		self.ChainLabel.Text = string.format("Luck chain  +%.0f%%", chainBonus / 100)
		self.ChainLabel.TextColor3 = Color3.fromRGB(255, 219, 98)
	else
		self.ChainLabel.Text = "Perfect catches build a luck chain"
		self.ChainLabel.TextColor3 = Color3.fromRGB(151, 174, 195)
	end

	local fishing = replica.Fishing
	if fishing then
		self.StatusLabel.Text = "HOLD... RELEASE IN THE GREEN!"
		self.SubtitleLabel.Text = "Release your click, tap REEL, or press F"
		self.ActionButton.Text = "REEL!"
		self.ActionButton.BackgroundColor3 = Color3.fromRGB(244, 117, 56)
		self.SweetSpot.Visible = true
		self.Marker.Visible = true
		local maxRatio = FishingConfig.MaxHoldRatio or 1.25
		local left = math.clamp((fishing.SweetSpot - fishing.WindowHalfWidth) / maxRatio, 0, 1)
		local right = math.clamp((fishing.SweetSpot + fishing.WindowHalfWidth) / maxRatio, 0, 1)
		self.SweetSpot.Position = UDim2.fromScale(left, 0)
		self.SweetSpot.Size = UDim2.fromScale(right - left, 1)
	else
		self.StatusLabel.Text = "READY TO FISH"
		self.StatusLabel.TextColor3 = Color3.fromRGB(127, 224, 255)
		self.SubtitleLabel.Text = UserInputService.TouchEnabled and "Face the water, then tap CAST"
			or "Face the water • hold your tool or press F"
		self.ActionButton.Text = "CAST"
		self.ActionButton.BackgroundColor3 = Color3.fromRGB(28, 150, 225)
		self.SweetSpot.Visible = false
		self.Marker.Visible = false
		self.MeterFill.Size = UDim2.fromScale(0, 1)
	end
end

function FishingScreen:_syncFishingSession(replica)
	local fishing = replica and replica.Fishing
	local newId = fishing and fishing.Id or nil
	if newId == self.ActiveSessionId then
		return
	end

	self.ActiveSessionId = newId
	self.LocalCastStartedAt = newId and os.clock() or nil
	if newId then
		self.FishingPanel.Size = UDim2.new(0.62, 0, 0, 148)
		TweenService:Create(
			self.FishingPanel,
			TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0.65, 0, 0, 154) }
		):Play()
	end
end

function FishingScreen:UpdateMeter()
	local fishing = self.Replica and self.Replica.Fishing
	if not fishing or not self.LocalCastStartedAt then
		return
	end

	local elapsed
	if type(fishing.StartedAtServer) == "number" then
		elapsed = Workspace:GetServerTimeNow() - fishing.StartedAtServer
	else
		elapsed = os.clock() - self.LocalCastStartedAt
	end

	local ratio = math.max(0, elapsed) / math.max(0.1, fishing.CastDurationSeconds or 1)
	local displayRatio = math.clamp(ratio / (FishingConfig.MaxHoldRatio or 1.25), 0, 1)
	self.MeterFill.Size = UDim2.fromScale(displayRatio, 1)
	self.Marker.Position = UDim2.fromScale(displayRatio, 0.5)

	local inWindow = math.abs(ratio - (fishing.SweetSpot or 0.5)) <= (fishing.WindowHalfWidth or 0.08)
	self.Marker.BackgroundColor3 = inWindow and Color3.fromRGB(255, 239, 95) or Color3.fromRGB(255, 255, 255)
	if inWindow then
		self.StatusLabel.Text = "NOW! REEL IT IN!"
		self.StatusLabel.TextColor3 = Color3.fromRGB(112, 255, 157)
	else
		self.StatusLabel.Text = ratio > 1 and "TOO LATE — REEL!" or "HOLD... RELEASE IN THE GREEN!"
		self.StatusLabel.TextColor3 = ratio > 1 and Color3.fromRGB(255, 115, 115) or Color3.fromRGB(127, 224, 255)
	end
end

function FishingScreen:ShowToast(text, color)
	self.ToastToken = self.ToastToken + 1
	local token = self.ToastToken
	if self.ToastTween then
		self.ToastTween:Cancel()
		self.ToastTween = nil
	end
	self.Toast.Text = text
	self.Toast.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	self.Toast.TextTransparency = 0
	self.ToastStroke.Color = color or Color3.fromRGB(101, 205, 255)
	self.Toast.Visible = true
	self.Toast.Position = UDim2.new(0.5, 0, 0, 82)
	self.Toast.BackgroundTransparency = 0.04
	TweenService:Create(self.Toast, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, 96) })
		:Play()

	task.delay(2.6, function()
		if token ~= self.ToastToken or not self.Toast.Parent then
			return
		end
		local tween =
			TweenService:Create(self.Toast, TweenInfo.new(0.25), { BackgroundTransparency = 1, TextTransparency = 1 })
		self.ToastTween = tween
		tween:Play()
		tween.Completed:Wait()
		if token == self.ToastToken then
			self.Toast.Visible = false
			self.Toast.TextTransparency = 0
			self.ToastTween = nil
		end
	end)
end

function FishingScreen:HideReveal()
	if not self.RevealShade.Visible then
		return
	end
	self.RevealToken = self.RevealToken + 1
	self.RevealShade.Visible = false
	self.RevealViewport:ClearAllChildren()
	local nextCatch = table.remove(self.CatchQueue, 1)
	if nextCatch then
		task.defer(function()
			self:ShowCatch(nextCatch)
		end)
	end
end

function FishingScreen:ShowCatch(context)
	context = context or {}
	if self.RevealShade.Visible then
		table.insert(self.CatchQueue, context)
		return
	end
	local definition = BaddieConfig.Definitions[context.TemplateId]
	if not definition then
		return
	end

	self.RevealToken = self.RevealToken + 1
	local token = self.RevealToken
	local rarityId = context.RarityId or definition.RarityId or "Common"
	local rarityColor = RarityConfig.RewardColors[rarityId] or Color3.fromRGB(255, 255, 255)
	self.RevealKicker.Text = context.BonusCatch and "DOUBLE CATCH!" or "YOU CAUGHT"
	self.RevealName.Text = definition.DisplayName .. " Baddie"
	self.RevealName.TextColor3 = rarityColor
	self.RevealRarity.Text = string.upper(rarityId)
	self.RevealRarity.TextColor3 = rarityColor
	self.RevealStroke.Color = rarityColor
	local traits = context.TraitIds or {}
	local traitText = (#traits > 0 and traits[1] ~= "None") and ("Trait: " .. table.concat(traits, ", "))
		or "Added to your Baddies inventory"
	self.RevealDetails.Text = traitText

	self.RevealViewport:ClearAllChildren()
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = self.RevealViewport
	local visual = createCatchVisual(definition, rarityColor)
	visual.Parent = worldModel
	local focusPosition = Vector3.new(0, 0.7, 0)
	local largestSize = 4.5
	if visual:IsA("Model") then
		local boundsCFrame, boundsSize = visual:GetBoundingBox()
		focusPosition = boundsCFrame.Position
		largestSize = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z)
	else
		focusPosition = visual.Position
		largestSize = math.max(visual.Size.X, visual.Size.Y, visual.Size.Z)
	end
	local camera = Instance.new("Camera")
	camera.CFrame =
		CFrame.lookAt(focusPosition + Vector3.new(0, largestSize * 0.08, -largestSize * 2.35), focusPosition)
	camera.FieldOfView = 35
	camera.Parent = self.RevealViewport
	self.RevealViewport.CurrentCamera = camera

	self.RevealShade.BackgroundTransparency = 1
	self.RevealShade.Visible = true
	self.RevealCard.Size = UDim2.fromOffset(300, 335)
	TweenService:Create(self.RevealShade, TweenInfo.new(0.22), { BackgroundTransparency = 0.35 }):Play()
	TweenService:Create(
		self.RevealCard,
		TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(390, 430) }
	):Play()

	task.delay(4.5, function()
		if token == self.RevealToken then
			self:HideReveal()
		end
	end)
end

function FishingScreen:HandleNotification(payload)
	if type(payload) ~= "table" then
		return
	end

	local context = payload.Context or {}
	if payload.Code == "CatchSuccess" then
		self:ShowCatch(context)
	elseif payload.Code == "CatchFail" then
		self:ShowToast("The baddie got away — hit the green zone!", Color3.fromRGB(255, 125, 125))
	elseif payload.Code == "IncomeClaimed" then
		self:ShowToast("Claimed " .. formatNumber(context.Amount) .. " coins!", Color3.fromRGB(104, 255, 166))
	elseif payload.Code == "DateComplete" then
		self:ShowToast(
			string.format(
				"Date complete! Chemistry %d/5  +%s coins",
				context.Affection or 1,
				formatNumber(context.CoinReward)
			),
			Color3.fromRGB(255, 126, 192)
		)
	elseif payload.Code == "BaddiePlaced" then
		self:ShowToast("Baddie placed — passive income started!", Color3.fromRGB(104, 255, 166))
	elseif payload.Code == "BaddieHeld" or payload.Code == "BaddiePickedUp" then
		self:ShowToast("Baddie picked up. Walk to an open plot cell.", Color3.fromRGB(116, 210, 255))
	elseif payload.Code == "UpgradePurchased" then
		self:ShowToast("Upgrade complete!", Color3.fromRGB(255, 220, 92))
	elseif payload.Code == "PurchaseSuccess" then
		self:ShowToast("Purchase complete!", Color3.fromRGB(104, 255, 166))
	elseif payload.Code == "TraitRerolled" or payload.Code == "TraitUpgraded" then
		self:ShowToast("Trait updated!", Color3.fromRGB(194, 116, 255))
	elseif payload.Code == "FusionComplete" then
		self:ShowToast("Fusion complete — shards earned!", Color3.fromRGB(194, 116, 255))
	elseif payload.Code == "SecretConverted" then
		self:ShowToast("Secret converted into permanent power!", Color3.fromRGB(255, 82, 112))
	elseif payload.Code == "CrateOpened" then
		self:ShowToast("Crate opened!", Color3.fromRGB(255, 220, 92))
	elseif payload.Type == "Error" then
		self:ShowToast(
			ERROR_TEXT[payload.Code] or tostring(payload.Code or "Request failed"),
			Color3.fromRGB(255, 132, 132)
		)
	elseif payload.Code == "RareCatchBroadcast" or payload.Code == "SecretCaughtBroadcast" then
		local catcher = context.CatcherName or "Someone"
		local baddieName = context.BaddieName or "a rare baddie"
		self:ShowToast(catcher .. " caught " .. baddieName .. "!", Color3.fromRGB(255, 211, 89))
	end
end

function FishingScreen:BindInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.RevealShade.Visible then
			return
		end

		if input.KeyCode == Enum.KeyCode.F then
			self:ToggleFishing()
		end
	end)
end

function FishingScreen:Init(network, replicaClient)
	self.Network = network
	self.ReplicaClient = replicaClient
	self:BuildGui()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:ApplyResponsiveLayout()
		end)
	end
	self.Replica = replicaClient:Get()
	self:_syncFishingSession(self.Replica)
	self:RenderHud()

	replicaClient:Subscribe(function(replica)
		self.Replica = replica
		self:_syncFishingSession(replica)
		self:RenderHud()
	end)
	replicaClient:SubscribeNotifications(function(payload)
		self:HandleNotification(payload)
	end)
	RunService.RenderStepped:Connect(function()
		self:UpdateMeter()
	end)
	self:BindInput()
end

return FishingScreen
