local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CrateConfig = require(Shared.Config.CrateConfig)
local FormulaUtil = require(Shared.Util.FormulaUtil)
local PlayerUpgradeConfig = require(Shared.Config.PlayerUpgradeConfig)
local ProductConfig = require(Shared.Config.ProductConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local RebirthUpgradeConfig = require(Shared.Config.RebirthUpgradeConfig)
local RodComponentConfig = require(Shared.Config.RodComponentConfig)
local RodConfig = require(Shared.Config.RodConfig)
local RodUtil = require(Shared.Util.RodUtil)
local ShopCatalog = require(Shared.Config.ShopCatalog)

local localPlayer = Players.LocalPlayer

local ShopScreen = {
	Network = nil,
	ReplicaClient = nil,
	Replica = nil,
	CurrentTab = "Rods",
	PaidRandomRestricted = false,
	PromptCooldowns = {},
	SessionPromptCount = 0,
	CatchFailStreak = 0,
	LegendaryPrompted = false,
	SecretPrompted = false,
}

local TABS = {
	{ Id = "Rods", Name = "Rods" },
	{ Id = "PlayerUpgrades", Name = "Player Upgrades" },
	{ Id = "Rebirth", Name = "Rebirth" },
	{ Id = "Boosts", Name = "Boosts / Crates" },
	{ Id = "Premium", Name = "Premium" },
}

local SHOP_TAB_BY_ID = {
	RodShop = "Rods",
	ComponentForge = "Rods",
	PlayerUpgradeShop = "PlayerUpgrades",
	PlotShop = "PlayerUpgrades",
	RebirthAltar = "Rebirth",
	BoostShop = "Boosts",
	CrateShop = "Boosts",
	PremiumShop = "Premium",
	TraitLab = "Premium",
}

local PLAYER_UPGRADE_ENTRY_BY_ID = {
	CastSpeed = "PlayerUpgradeCastSpeed",
	LuckTraining = "PlayerUpgradeLuckTraining",
	TimingWindow = "PlayerUpgradeTimingWindow",
	ChainFocus = "PlayerUpgradeChainFocus",
}

local REBIRTH_UPGRADE_ENTRY_BY_ID = {
	GlobalIncome = "RebirthUpgradeGlobalIncome",
	GlobalLuck = "RebirthUpgradeGlobalLuck",
	RebirthCastSpeed = "RebirthUpgradeRebirthCastSpeed",
	BoostDuration = "RebirthUpgradeBoostDuration",
	StartingMomentum = "RebirthUpgradeStartingMomentum",
}

local GAMEPASS_ORDER = { "X2Income", "X2Luck", "AutoCatch", "AutoCollect", "VIP", "VIPPlus" }
local PREMIUM_PRODUCT_ORDER = {
	"PoseidonRod",
	"AbyssRod",
	"GodRod",
	"ExtraSlots2",
	"X3LuckStack",
	"InstantUpgradePack",
	"IncomeBoost2xRobux",
	"IncomeBoost5x",
	"LuckBoost2xRobux",
	"LuckBoost5x",
	"CurrencyPack100",
	"CurrencyPack1000",
	"InstantMaxComponent",
	"InstantMaxAllComponents",
	"TraitReroll",
	"TargetedTraitRoll",
	"GodTierTraitRoll",
	"LockTraitSlot",
	"TraitUpgradePack",
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
	create("UICorner", {
		CornerRadius = UDim.new(0, radius or 6),
	}, parent)
end

local function addStroke(parent, color, transparency)
	create("UIStroke", {
		Color = color or Color3.fromRGB(72, 84, 102),
		Transparency = transparency or 0,
		Thickness = 1,
	}, parent)
end

local function formatNumber(value)
	value = math.floor(tonumber(value) or 0)
	local text = tostring(value)
	local left, num, right = string.match(text, "^([^%d]*%d)(%d*)(.-)$")
	return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

local function formatRobux(price)
	return tostring(price or 0) .. "R"
end

local function clearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function getLevel(levels, id)
	local level = levels and levels[id] or 0
	return type(level) == "number" and math.max(0, math.floor(level)) or 0
end

local function getProductDefinition(productKey)
	return ProductConfig.DeveloperProducts[productKey] or ProductConfig.GamePasses[productKey]
end

local function isProductOwned(replica, productKey)
	local pass = ProductConfig.GamePasses[productKey]
	if pass then
		return replica.Premium and replica.Premium.OwnedPasses and replica.Premium.OwnedPasses[productKey] == true
	end

	local product = ProductConfig.DeveloperProducts[productKey]
	if product and product.Repeatable == false then
		return (replica.Premium and replica.Premium.Products and (replica.Premium.Products[productKey] or 0) or 0) > 0
	end

	return false
end

function ShopScreen:GetInstantRebirthKey()
	local replica = self.Replica or {}
	local rebirthCount = replica.Progression and replica.Progression.RebirthCount or 0
	if rebirthCount <= 1 then
		return "InstantRebirthLow"
	elseif rebirthCount <= 4 then
		return "InstantRebirthMid"
	end

	return "InstantRebirthHigh"
end

function ShopScreen:GetProductPrice(productKey)
	if productKey == "InstantRebirth" then
		productKey = self:GetInstantRebirthKey()
	end

	local definition = getProductDefinition(productKey)
	return definition and definition.PriceRobux or 0
end

function ShopScreen:MakeText(parent, text, size, color, bold)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		Text = text,
		TextColor3 = color or Color3.fromRGB(233, 238, 245),
		TextSize = size or 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 20),
	}, parent)
end

function ShopScreen:MakeButton(parent, text, disabled, callback)
	local button = create("TextButton", {
		AutoButtonColor = not disabled,
		BackgroundColor3 = disabled and Color3.fromRGB(63, 70, 82) or Color3.fromRGB(41, 132, 255),
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = disabled and Color3.fromRGB(168, 176, 188) or Color3.fromRGB(255, 255, 255),
		TextSize = 13,
		TextWrapped = true,
		Size = UDim2.fromOffset(126, 34),
	}, parent)
	addCorner(button, 6)

	if not disabled and callback then
		button.Activated:Connect(callback)
	end

	return button
end

function ShopScreen:MakeSection(parent, title, subtitle)
	local frame = create("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	}, parent)
	create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	self:MakeText(frame, title, 18, Color3.fromRGB(255, 255, 255), true)
	if subtitle and subtitle ~= "" then
		self:MakeText(frame, subtitle, 13, Color3.fromRGB(168, 183, 204), false)
	end
	return frame
end

function ShopScreen:MakeRow(parent, title, body, priceText, buttonText, disabled, callback)
	local row = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(31, 38, 50),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	}, parent)
	addCorner(row, 6)
	addStroke(row, Color3.fromRGB(57, 68, 84), 0.1)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
	}, row)

	local line = create("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	}, row)

	local layout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, line)

	local textColumn = create("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -270, 0, 0),
	}, line)
	create("UIListLayout", {
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, textColumn)
	self:MakeText(textColumn, title, 15, Color3.fromRGB(245, 248, 252), true)
	self:MakeText(textColumn, body, 13, Color3.fromRGB(176, 187, 201), false)

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = priceText,
		TextColor3 = Color3.fromRGB(255, 218, 92),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(116, 28),
	}, line)

	self:MakeButton(line, buttonText, disabled, callback)
	return row
end

function ShopScreen:BuildGui()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = create("ScreenGui", {
		Name = "FishABaddieShop",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Enabled = false,
	}, playerGui)
	self.Gui = gui

	local shade = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(5, 8, 12),
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
	}, gui)

	local root = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 25, 34),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0.9, 0, 0.82, 0),
	}, shade)
	root.ClipsDescendants = true
	addCorner(root, 8)
	addStroke(root, Color3.fromRGB(74, 88, 108), 0)

	local topBar = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(25, 32, 43),
		Size = UDim2.new(1, 0, 0, 58),
	}, root)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
	}, topBar)

	self.TitleLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Shop",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.45, 0, 1, -10),
	}, topBar)
	self.WalletLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.new(1, -48, 0, 0),
		Text = "",
		TextColor3 = Color3.fromRGB(186, 198, 214),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.5, -60, 1, -10),
	}, topBar)
	local close = self:MakeButton(topBar, "X", false, function()
		self:Close()
	end)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(34, 34)

	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
	}, root)

	local sidebar = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(23, 29, 39),
		Size = UDim2.new(0, 172, 1, 0),
	}, body)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 12),
	}, sidebar)
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, sidebar)

	self.TabButtons = {}
	for _, tab in ipairs(TABS) do
		local tabButton = self:MakeButton(sidebar, tab.Name, false, function()
			self:SetTab(tab.Id)
		end)
		tabButton.Size = UDim2.new(1, 0, 0, 38)
		tabButton.TextXAlignment = Enum.TextXAlignment.Left
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
		}, tabButton)
		self.TabButtons[tab.Id] = tabButton
	end

	self.Content = create("ScrollingFrame", {
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Position = UDim2.fromOffset(172, 0),
		ScrollBarImageColor3 = Color3.fromRGB(92, 110, 136),
		ScrollBarThickness = 6,
		Size = UDim2.new(1, -172, 1, 0),
	}, body)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 18),
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 18),
	}, self.Content)
	create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, self.Content)

	self:BuildPrompt(gui)
end

function ShopScreen:BuildPrompt(gui)
	local shade = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, gui)
	self.PromptShade = shade

	local modal = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(22, 29, 39),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 210),
	}, shade)
	addCorner(modal, 8)
	addStroke(modal, Color3.fromRGB(83, 101, 128), 0)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		PaddingTop = UDim.new(0, 16),
	}, modal)
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, modal)
	self.PromptTitle = self:MakeText(modal, "", 19, Color3.fromRGB(255, 255, 255), true)
	self.PromptBody = self:MakeText(modal, "", 14, Color3.fromRGB(183, 196, 214), false)
	local actions = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 38),
	}, modal)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, actions)
	self:MakeButton(actions, "Later", false, function()
		self.PromptShade.Visible = false
	end)
	self.PromptBuyButton = self:MakeButton(actions, "Buy", false, function()
		if self.PromptProductKey then
			self.Network:SendShop({
				Action = "PromptProduct",
				EntryId = self.PromptProductKey,
			})
		end
		self.PromptShade.Visible = false
	end)
end

function ShopScreen:RefreshPolicy()
	task.spawn(function()
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(localPlayer)
		end)
		self.PaidRandomRestricted = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == true
		if self.Gui and self.Gui.Enabled then
			self:Render()
		end
	end)
end

function ShopScreen:Init(network, replicaClient)
	self.Network = network
	self.ReplicaClient = replicaClient
	self:BuildGui()
	self:RefreshPolicy()

	self.Replica = replicaClient:Get()
	replicaClient:Subscribe(function(replica)
		self.Replica = replica
		if self.Gui.Enabled then
			self:Render()
		end
	end)

	replicaClient:SubscribeNotifications(function(payload)
		self:HandleNotification(payload)
	end)
end

function ShopScreen:OpenForShop(shopId, displayName)
	self.CurrentTab = SHOP_TAB_BY_ID[shopId] or self.CurrentTab or "Rods"
	self.TitleLabel.Text = displayName or "Shop"
	self.Gui.Enabled = true
	self:Render()
end

function ShopScreen:Close()
	self.Gui.Enabled = false
end

function ShopScreen:SetTab(tabId)
	self.CurrentTab = tabId
	self:Render()
end

function ShopScreen:Render()
	local replica = self.Replica
	if not replica then
		return
	end

	local wallet = replica.Wallet or {}
	self.WalletLabel.Text = string.format(
		"Coins %s   Shards %s   Rebirth %s",
		formatNumber(wallet.Coins or 0),
		formatNumber(wallet.RebirthShards or 0),
		formatNumber((replica.Progression and replica.Progression.RebirthCount) or 0)
	)

	for tabId, button in pairs(self.TabButtons) do
		local active = tabId == self.CurrentTab
		button.BackgroundColor3 = active and Color3.fromRGB(41, 132, 255) or Color3.fromRGB(35, 43, 56)
	end

	clearChildren(self.Content)
	if self.CurrentTab == "Rods" then
		self:RenderRods()
	elseif self.CurrentTab == "PlayerUpgrades" then
		self:RenderPlayerUpgrades()
	elseif self.CurrentTab == "Rebirth" then
		self:RenderRebirth()
	elseif self.CurrentTab == "Boosts" then
		self:RenderBoostsAndCrates()
	elseif self.CurrentTab == "Premium" then
		self:RenderPremium()
	end
end

function ShopScreen:RenderRods()
	local replica = self.Replica
	self:MakeSection(self.Content, "Rod Shop", "Buy, equip, and tune rods. Coin rods reset on rebirth; premium rods persist.")

	for _, rodId in ipairs(RodConfig.Order) do
		local rod = RodConfig.Definitions[rodId]
		if rod and rod.UnlockType ~= "Product" then
			local owned = replica.Unlocks and replica.Unlocks.Rods and replica.Unlocks.Rods[rodId] == true
			local equipped = replica.Progression and replica.Progression.EquippedRodId == rodId
			local meetsRequirements = RodUtil.MeetsUnlockRequirements(replica, rodId)
			local requirementText = RodUtil.BuildRequirementText(replica, rodId)
			local price = rod.PriceCoins or (ShopCatalog.Definitions[rodId] and ShopCatalog.Definitions[rodId].Price) or 0
			local body = string.format(
				"Luck %.2fx | Cast %.2fs | %s | %s",
				(rod.LuckMultiplierBps or 10000) / 10000,
				rod.CastDurationSeconds or 0,
				rod.PassiveText or "Passive: None",
				requirementText
			)
			local buttonText = "Buy"
			local disabled = false
			local callback = function()
				self.Network:SendShop({ Action = "Purchase", EntryId = rodId, Quantity = 1 })
			end

			if equipped then
				buttonText = "Equipped"
				disabled = true
			elseif owned then
				buttonText = "Equip"
				callback = function()
					self.Network:SendShop({ Action = "EquipRod", EntryId = rodId })
				end
			elseif not meetsRequirements then
				buttonText = "Locked"
				disabled = true
			end

			self:MakeRow(self.Content, rod.DisplayName, body, formatNumber(price) .. " coins", buttonText, disabled, callback)
		end
	end

	self:RenderRodComponents(replica.Progression and replica.Progression.EquippedRodId or "StarterRod")
end

function ShopScreen:RenderRodComponents(rodId)
	local components = self.Replica.RodComponents and self.Replica.RodComponents[rodId]
	if not components then
		return
	end

	self:MakeSection(self.Content, "Equipped Rod Components", "Line improves timing, Hook improves luck, and Reel improves speed plus chain income.")
	for _, componentName in ipairs(RodComponentConfig.Components) do
		local tier = components[componentName] or 1
		local current = FormulaUtil.GetComponentRecord(rodId, componentName, tier)
		local nextCost = FormulaUtil.GetComponentUpgradeCost(rodId, componentName, tier)
		local maxed = tier >= RodComponentConfig.MaxTier
		local body = string.format("Tier %d/%d | %s", tier, RodComponentConfig.MaxTier, current and current.Name or componentName)
		self:MakeRow(self.Content, componentName, body, nextCost and (formatNumber(nextCost) .. " coins") or "Max", maxed and "Maxed" or "Upgrade", maxed, function()
			self.Network:SendRodComponent({
				Action = "UpgradeComponent",
				RodId = rodId,
				ComponentName = componentName,
			})
		end)

		self:MakeRow(self.Content, "Instant Max " .. componentName, "Robux shortcut for the selected rod component.", formatRobux(self:GetProductPrice("InstantMaxComponent")), maxed and "Maxed" or "Buy", maxed, function()
			self.Network:SendRodComponent({
				Action = "InstantMaxComponent",
				RodId = rodId,
				ComponentName = componentName,
			})
		end)
	end
end

function ShopScreen:RenderPlayerUpgrades()
	local replica = self.Replica
	self:MakeSection(self.Content, "Player Upgrades", "Coin upgrades are strong fishing optimizations and reset when you rebirth.")

	local plotSlots = replica.Progression and replica.Progression.PlotSlots or 10
	self:MakeRow(self.Content, "+2 Baddie Slots", "Current effective slots: " .. tostring(plotSlots), "10,000 coins", "Buy", false, function()
		self.Network:SendShop({ Action = "Purchase", EntryId = "PlotSlot1", Quantity = 1 })
	end)

	for _, upgradeId in ipairs(PlayerUpgradeConfig.Order) do
		local definition = PlayerUpgradeConfig.Definitions[upgradeId]
		local level = getLevel(replica.PlayerUpgrades, upgradeId)
		local cost = FormulaUtil.GetPlayerUpgradeCost(upgradeId, level)
		local maxed = level >= definition.MaxLevel
		local entryId = PLAYER_UPGRADE_ENTRY_BY_ID[upgradeId]
		self:MakeRow(
			self.Content,
			definition.DisplayName,
			string.format("Level %d/%d | %s", level, definition.MaxLevel, definition.Description),
			cost and (formatNumber(cost) .. " coins") or "Max",
			maxed and "Maxed" or "Upgrade",
			maxed,
			function()
				self.Network:SendShop({ Action = "Purchase", EntryId = entryId, Quantity = 1 })
			end
		)
	end
end

function ShopScreen:RenderRebirth()
	local replica = self.Replica
	local wallet = replica.Wallet or {}
	local progression = replica.Progression or {}
	local rebirthCount = progression.RebirthCount or 0
	local requiredCoins = FormulaUtil.GetRebirthCost(rebirthCount)
	local progress = math.clamp((wallet.Coins or 0) / math.max(1, requiredCoins), 0, 1)

	self:MakeSection(
		self.Content,
		"Rebirth",
		string.format(
			"Progress: %s / %s coins (%d%%). Rebirth grants 5 Prestige Shards and resets coin-cycle power.",
			formatNumber(wallet.Coins or 0),
			formatNumber(requiredCoins),
			math.floor(progress * 100)
		)
	)

	local secretCount = 0
	for _, baddie in pairs((replica.Inventory and replica.Inventory.Baddies) or {}) do
		if baddie.RarityId == "Secret" then
			secretCount += 1
		end
	end
	local conversionMultiplier = (replica.Premium and replica.Premium.Effects and replica.Premium.Effects.SecretConversionMultiplierBps) or 10000
	local incomeBps = math.floor(secretCount * 200 * conversionMultiplier / 10000)
	local luckBps = math.floor(secretCount * 100 * conversionMultiplier / 10000)

	self:MakeRow(
		self.Content,
		"Execute Rebirth",
		string.format("Secret preview: %d Secrets convert to +%.1f%% income and +%.1f%% luck permanently.", secretCount, incomeBps / 100, luckBps / 100),
		formatNumber(requiredCoins) .. " coins",
		"Rebirth",
		(wallet.Coins or 0) < requiredCoins,
		function()
			self.Network:SendRebirth({ Action = "Execute" })
		end
	)

	self:MakeRow(
		self.Content,
		"Instant Rebirth",
		"Skip the current coin requirement and take the next rebirth reward now.",
		formatRobux(self:GetProductPrice("InstantRebirth")),
		"Buy",
		false,
		function()
			self.Network:SendShop({ Action = "PromptProduct", EntryId = "InstantRebirth" })
		end
	)

	self:MakeSection(self.Content, "Rebirth Shop", "Spend Prestige Shards on permanent optimizer upgrades.")
	for _, upgradeId in ipairs(RebirthUpgradeConfig.Order) do
		local definition = RebirthUpgradeConfig.Definitions[upgradeId]
		local level = getLevel(replica.RebirthUpgrades, upgradeId)
		local cost = FormulaUtil.GetRebirthUpgradeCost(upgradeId, level)
		local maxed = level >= definition.MaxLevel
		local entryId = REBIRTH_UPGRADE_ENTRY_BY_ID[upgradeId]
		self:MakeRow(
			self.Content,
			definition.DisplayName,
			string.format("Level %d/%d | %s", level, definition.MaxLevel, definition.Description),
			cost and (formatNumber(cost) .. " shards") or "Max",
			maxed and "Maxed" or "Upgrade",
			maxed or (wallet.RebirthShards or 0) < (cost or 0),
			function()
				self.Network:SendShop({ Action = "Purchase", EntryId = entryId, Quantity = 1 })
			end
		)
	end

	self:MakeSection(self.Content, "Shard Packs", "Robux shard packs accelerate the permanent optimizer tree.")
	for _, productKey in ipairs({ "CurrencyPack100", "CurrencyPack1000" }) do
		local product = ProductConfig.DeveloperProducts[productKey]
		self:MakeRow(self.Content, product.DisplayName, "Prestige Shards for the Rebirth Shop.", formatRobux(product.PriceRobux), "Buy", false, function()
			self.Network:SendShop({ Action = "PromptProduct", EntryId = productKey })
		end)
	end
end

function ShopScreen:GetCrateOddsText(crateId)
	local crate = CrateConfig.Definitions[crateId]
	if not crate then
		return ""
	end

	local total = 0
	for _, weight in pairs(crate.RewardWeights) do
		total += weight
	end

	local segments = {}
	for _, rarityId in ipairs(RarityConfig.Order) do
		local weight = crate.RewardWeights[rarityId]
		if weight and weight > 0 then
			table.insert(segments, string.format("%s %.2f%%", rarityId, weight * 100 / total))
		end
	end

	return table.concat(segments, " | ")
end

function ShopScreen:RenderBoostsAndCrates()
	local replica = self.Replica
	self:MakeSection(self.Content, "Boosts", "Same boosts extend duration. Stronger active boosts win instead of multiplying together.")

	for _, entryId in ipairs({ "IncomeBoost2x", "IncomeBoost5x", "LuckBoost2x", "LuckBoost5x" }) do
		local entry = ShopCatalog.Definitions[entryId]
		local duration = FormulaUtil.GetBoostDurationSeconds(replica, entry.DurationSeconds)
		self:MakeRow(
			self.Content,
			entry.DisplayName,
			string.format("%dx %s for %d minutes.", entry.MultiplierBps / 10000, entry.BoostKind, math.floor(duration / 60)),
			formatNumber(entry.Price) .. " coins",
			"Buy",
			false,
			function()
				self.Network:SendShop({ Action = "Purchase", EntryId = entryId, Quantity = 1 })
			end
		)
	end

	local restrictedText = self.PaidRandomRestricted and "Paid random items are unavailable for this player." or "Crate odds are shown before every crate purchase."
	self:MakeSection(self.Content, "Crates", restrictedText)
	local basicEntry = ShopCatalog.Definitions.BasicCrateTicket
	self:MakeRow(
		self.Content,
		basicEntry.DisplayName,
		"Odds: " .. self:GetCrateOddsText("BasicCrate"),
		formatNumber(basicEntry.Price) .. " coins",
		self.PaidRandomRestricted and "Unavailable" or "Buy",
		self.PaidRandomRestricted,
		function()
			self.Network:SendShop({ Action = "Purchase", EntryId = "BasicCrateTicket", Quantity = 1 })
		end
	)

	for _, crateId in ipairs(CrateConfig.Order) do
		local crate = CrateConfig.Definitions[crateId]
		local owned = replica.Inventory and replica.Inventory.Crates and (replica.Inventory.Crates[crateId] or 0) or 0
		local product = ProductConfig.DeveloperProducts[crate.ProductKey]
		self:MakeRow(
			self.Content,
			crate.DisplayName,
			string.format("Owned: %d | Odds: %s", owned, self:GetCrateOddsText(crateId)),
			formatRobux(product and product.PriceRobux or 0),
			owned > 0 and "Open" or "Buy",
			self.PaidRandomRestricted,
			function()
				if owned > 0 then
					self.Network:SendCrate({ Action = "OpenOwnedCrate", CrateId = crateId })
				else
					self.Network:SendShop({ Action = "PromptProduct", EntryId = crate.ProductKey })
				end
			end
		)
	end
end

function ShopScreen:RenderPremium()
	local replica = self.Replica
	self:MakeSection(self.Content, "Gamepasses", "Permanent acceleration and convenience.")
	for _, productKey in ipairs(GAMEPASS_ORDER) do
		local pass = ProductConfig.GamePasses[productKey]
		local owned = isProductOwned(replica, productKey)
		self:MakeRow(
			self.Content,
			pass.DisplayName,
			owned and "Owned permanently." or "Permanent account upgrade.",
			formatRobux(pass.PriceRobux),
			owned and "Owned" or "Buy",
			owned,
			function()
				self.Network:SendShop({ Action = "PromptProduct", EntryId = productKey })
			end
		)
	end

	self:MakeSection(self.Content, "Developer Products", "Repeatable acceleration, skips, premium rods, and optimization tools.")
	for _, productKey in ipairs(PREMIUM_PRODUCT_ORDER) do
		local product = ProductConfig.DeveloperProducts[productKey]
		local owned = isProductOwned(replica, productKey)
		self:MakeRow(
			self.Content,
			product.DisplayName,
			owned and "Already owned." or "Robux acceleration item.",
			formatRobux(product.PriceRobux),
			owned and "Owned" or "Buy",
			owned,
			function()
				self.Network:SendShop({ Action = "PromptProduct", EntryId = productKey })
			end
		)
	end
end

function ShopScreen:ShowPremiumPrompt(category, productKey, title, body)
	local now = os.clock()
	if self.SessionPromptCount >= 3 then
		return
	end
	if self.PromptCooldowns[category] and now - self.PromptCooldowns[category] < 300 then
		return
	end

	self.PromptCooldowns[category] = now
	self.SessionPromptCount += 1
	self.PromptProductKey = productKey
	self.PromptTitle.Text = title
	self.PromptBody.Text = body
	self.PromptBuyButton.Text = "Buy " .. formatRobux(self:GetProductPrice(productKey))
	self.PromptShade.Visible = true
end

function ShopScreen:HandleNotification(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.Code == "ShopOpened" then
		local context = payload.Context or {}
		self:OpenForShop(context.ShopId, context.DisplayName)
		return
	end

	if payload.Code == "CatchFail" then
		self.CatchFailStreak += 1
		if self.CatchFailStreak >= 3 then
			self.CatchFailStreak = 0
			self:ShowPremiumPrompt("AutoCatch", "AutoCatch", "Perfect every cast", "Auto Catch turns timing failures into clean catches.")
		end
		return
	end

	if payload.Code == "CatchSuccess" then
		self.CatchFailStreak = 0
		local rarityId = payload.Context and payload.Context.RarityId
		local rarityIndex = table.find(RarityConfig.Order, rarityId) or 0
		local legendaryIndex = table.find(RarityConfig.Order, "Legendary") or 0
		if rarityId == "Secret" and not self.SecretPrompted then
			self.SecretPrompted = true
			self:ShowPremiumPrompt("SecretCatch", "VIPPlus", "Lock in secret momentum", "VIP+ improves income, luck, cast speed, slots, and Secret conversion value.")
		elseif rarityIndex >= legendaryIndex and not self.LegendaryPrompted then
			self.LegendaryPrompted = true
			self:ShowPremiumPrompt("LegendaryCatch", "X2Luck", "Push the next jackpot", "x2 Luck keeps rare rolls closer after a big catch.")
		end
	end
end

return ShopScreen
