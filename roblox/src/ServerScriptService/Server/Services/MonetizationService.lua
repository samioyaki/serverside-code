local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ProductConfig = require(Shared.Config.ProductConfig)
local RodComponentConfig = require(Shared.Config.RodComponentConfig)
local RodConfig = require(Shared.Config.RodConfig)
local FormulaUtil = require(Shared.Util.FormulaUtil)

local MonetizationService = {}
MonetizationService.__index = MonetizationService

local MAX_RECEIPT_HISTORY = 128
local POLICY_CACHE_SECONDS = 600

function MonetizationService.new(registry)
	return setmetatable({
		Registry = registry,
		ProductKeysById = {},
		PendingProductContexts = {},
		PolicyCacheByUserId = {},
	}, MonetizationService)
end

function MonetizationService:Init()
	for productKey, definition in pairs(ProductConfig.DeveloperProducts) do
		if definition.ProductId and definition.ProductId > 0 then
			self.ProductKeysById[definition.ProductId] = productKey
		end
	end
end

function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:ProcessReceipt(receiptInfo)
	end

	Players.PlayerRemoving:Connect(function(player)
		self.PendingProductContexts[player.UserId] = nil
		self.PolicyCacheByUserId[player.UserId] = nil
	end)
end

function MonetizationService:GetEffectivePlotSlots(profile)
	return profile.Progression.PlotSlots + (profile.Premium.Effects.ExtraSlots or 0)
end

function MonetizationService:GetPolicyInfo(player)
	local cached = self.PolicyCacheByUserId[player.UserId]
	local now = os.clock()
	if cached and cached.ExpiresAt > now then
		return cached.Info
	end

	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if not ok or type(info) ~= "table" then
		info = {
			ArePaidRandomItemsRestricted = false,
			LookupFailed = true,
		}
	end

	self.PolicyCacheByUserId[player.UserId] = {
		Info = info,
		ExpiresAt = now + POLICY_CACHE_SECONDS,
	}
	return info
end

function MonetizationService:ArePaidRandomItemsRestricted(player)
	local policyInfo = self:GetPolicyInfo(player)
	return policyInfo.ArePaidRandomItemsRestricted == true
end

function MonetizationService:AssertPaidRandomItemsAllowed(player)
	if self:ArePaidRandomItemsRestricted(player) then
		error("PaidRandomItemsRestricted", 0)
	end
end

function MonetizationService:ResolveProductKey(player, productKey)
	if productKey ~= "InstantRebirth" then
		return productKey
	end

	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	local rebirthCount = session and session.Profile.Progression.RebirthCount or 0
	if rebirthCount <= 1 then
		return "InstantRebirthLow"
	elseif rebirthCount <= 4 then
		return "InstantRebirthMid"
	end

	return "InstantRebirthHigh"
end

function MonetizationService:GrantTimedBoost(profile, kind, multiplierBps, baseDurationSeconds)
	local target = profile.Boosts[kind]
	if not target then
		error("InvalidShopAction", 0)
	end

	local now = os.time()
	local durationSeconds = FormulaUtil.GetBoostDurationSeconds(profile, baseDurationSeconds)
	local matchingBoost = nil
	local writeIndex = 1

	for _, boost in ipairs(target) do
		if boost.ExpiresAt > now then
			if boost.MultiplierBps == multiplierBps then
				matchingBoost = boost
			end

			if boost.MultiplierBps >= multiplierBps then
				target[writeIndex] = boost
				writeIndex += 1
			end
		end
	end

	for index = #target, writeIndex, -1 do
		target[index] = nil
	end

	if matchingBoost then
		matchingBoost.ExpiresAt = math.max(matchingBoost.ExpiresAt, now) + durationSeconds
	else
		table.insert(target, {
			MultiplierBps = multiplierBps,
			ExpiresAt = now + durationSeconds,
		})
	end
end

function MonetizationService:PlayerOwnsRod(profile, rodId)
	if profile.Unlocks.Rods[rodId] then
		return true
	end

	local rodDefinition = RodConfig.Definitions[rodId]
	if not rodDefinition or not rodDefinition.ProductKey then
		return false
	end

	return (profile.Premium.Products[rodDefinition.ProductKey] or 0) > 0
end

function MonetizationService:RecomputeEffects(profile)
	local effects = {
		IncomeMultiplierBps = 10000,
		LuckMultiplierBps = 10000,
		TraitLuckBps = 10000,
		CastSpeedMultiplierBps = 10000,
		SecretConversionMultiplierBps = 10000,
		ExtraSlots = 0,
		AutoCatch = false,
		AutoCollect = false,
	}

	-- Gamepasses
	for key, definition in pairs(ProductConfig.GamePasses) do
		if profile.Premium.OwnedPasses[key] then
			if definition.IncomeMultiplierBps then
				effects.IncomeMultiplierBps = math.floor(effects.IncomeMultiplierBps * definition.IncomeMultiplierBps / 10000)
			end
			if definition.LuckMultiplierBps then
				effects.LuckMultiplierBps = math.floor(effects.LuckMultiplierBps * definition.LuckMultiplierBps / 10000)
			end
			if definition.TraitLuckBps then
				effects.TraitLuckBps = math.floor(effects.TraitLuckBps * definition.TraitLuckBps / 10000)
			end
			if definition.CastSpeedMultiplierBps then
				effects.CastSpeedMultiplierBps = math.floor(effects.CastSpeedMultiplierBps * definition.CastSpeedMultiplierBps / 10000)
			end
			if definition.SecretConversionMultiplierBps then
				effects.SecretConversionMultiplierBps = math.floor(effects.SecretConversionMultiplierBps * definition.SecretConversionMultiplierBps / 10000)
			end
			if definition.ExtraSlots then
				effects.ExtraSlots += definition.ExtraSlots
			end
			if definition.AutoCatch then
				effects.AutoCatch = true
			end
			if definition.AutoCollect then
				effects.AutoCollect = true
			end
		end
	end

	-- Repeatable developer products
	effects.LuckMultiplierBps = math.floor(effects.LuckMultiplierBps * (30000 ^ (profile.Premium.Products.X3LuckStack or 0)) / (10000 ^ (profile.Premium.Products.X3LuckStack or 0)))
	effects.ExtraSlots += math.min(profile.Premium.Products.ExtraSlots2 or 0, 1) * 2

	profile.Premium.Effects = effects
	return effects
end

function MonetizationService:RefreshOwnership(player, profile)
	for key, definition in pairs(ProductConfig.GamePasses) do
		if definition.GamePassId and definition.GamePassId > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, definition.GamePassId)
			end)

			if ok then
				profile.Premium.OwnedPasses[key] = owns
			end
		end
	end

	self:RecomputeEffects(profile)
end

function MonetizationService:_rememberProductContext(player, productKey, context)
	if type(context) ~= "table" then
		return
	end

	self.PendingProductContexts[player.UserId] = self.PendingProductContexts[player.UserId] or {}
	self.PendingProductContexts[player.UserId][productKey] = {
		Context = {
			RodId = type(context.RodId) == "string" and context.RodId or nil,
			ComponentName = type(context.ComponentName) == "string" and context.ComponentName or nil,
		},
		ExpiresAt = os.clock() + 300,
	}
end

function MonetizationService:_sanitizeProductContext(context)
	if type(context) ~= "table" then
		return nil
	end

	return {
		RodId = type(context.RodId) == "string" and context.RodId or nil,
		ComponentName = type(context.ComponentName) == "string" and context.ComponentName or nil,
	}
end

function MonetizationService:_takeProductContext(player, productKey)
	local playerContexts = self.PendingProductContexts[player.UserId]
	local entry = playerContexts and playerContexts[productKey]
	if not entry then
		return nil
	end

	playerContexts[productKey] = nil
	if os.clock() > entry.ExpiresAt then
		return nil
	end

	return entry.Context
end

function MonetizationService:PromptProduct(player, productKey, context)
	productKey = self:ResolveProductKey(player, productKey)
	local sanitizedContext = self:_sanitizeProductContext(context)
	local definition = ProductConfig.DeveloperProducts[productKey]
	if definition and definition.ProductId and definition.ProductId > 0 then
		if definition.GrantCrateId then
			self:AssertPaidRandomItemsAllowed(player)
		end

		local session = self.Registry:Get("PlayerDataService"):FindSession(player)
		if definition.Repeatable == false and session and (session.Profile.Premium.Products[productKey] or 0) > 0 then
			error("PremiumAlreadyOwned", 0)
		end

		self:_rememberProductContext(player, productKey, sanitizedContext)
		MarketplaceService:PromptProductPurchase(player, definition.ProductId)

		self.Registry:Get("RemoteRouterService"):Notify(player, "PromptPurchase", productKey, {
			IsGamePass = false,
			ProductId = definition.ProductId,
			Context = sanitizedContext,
		})
		return true
	end

	local passDefinition = ProductConfig.GamePasses[productKey]
	if passDefinition and passDefinition.GamePassId and passDefinition.GamePassId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, passDefinition.GamePassId)

		self.Registry:Get("RemoteRouterService"):Notify(player, "PromptPurchase", productKey, {
			IsGamePass = true,
			ProductId = passDefinition.GamePassId,
		})
		return true
	end

	error("PremiumProductUnavailable", 0)
end

function MonetizationService:_storeProductOwnership(profile, productKey, definition)
	local ownedCount = profile.Premium.Products[productKey] or 0
	if definition.Repeatable == false then
		if ownedCount > 0 then
			return false
		end

		profile.Premium.Products[productKey] = 1
	else
		profile.Premium.Products[productKey] = ownedCount + 1
	end

	return true
end

function MonetizationService:_grantProduct(profile, productKey, context)
	local definition = ProductConfig.DeveloperProducts[productKey]
	if not definition then
		error("UnknownProduct", 0)
	end

	if definition.GrantCrateId then
		self.Registry:Get("CrateService"):GrantCrateTickets(profile, definition.GrantCrateId, 1)
	elseif definition.GrantBoost then
		local boost = definition.GrantBoost
		self:GrantTimedBoost(profile, boost.Kind, boost.MultiplierBps, boost.DurationSeconds)
	elseif productKey == "InstantMaxComponent" then
		local componentName = context and context.ComponentName or "Hook"
		if not RodComponentConfig[componentName] then
			componentName = "Hook"
		end
		local rodId = context and context.RodId or profile.Progression.EquippedRodId
		self.Registry:Get("RodComponentService"):MaxComponentForProfile(profile, rodId, componentName)
	elseif productKey == "InstantMaxAllComponents" then
		local rodId = context and context.RodId or profile.Progression.EquippedRodId
		self.Registry:Get("RodComponentService"):MaxAllComponentsForProfile(profile, rodId)
	elseif definition.ProductId ~= nil then
		if not self:_storeProductOwnership(profile, productKey, definition) then
			return false
		end
	end

	if productKey == "PoseidonRod" or productKey == "AbyssRod" or productKey == "GodRod" then
		local rodId = productKey
		profile.Progression.EquippedRodId = rodId
	end

	if definition.GrantRebirthShards then
		profile.Wallet.RebirthShards += definition.GrantRebirthShards
	end

	return true
end

function MonetizationService:HasProcessedReceipt(profile, purchaseId)
	return profile.Receipts.Processed[purchaseId] == true
end

function MonetizationService:MarkReceiptProcessed(profile, purchaseId)
	if self:HasProcessedReceipt(profile, purchaseId) then
		return false
	end

	profile.Receipts.Processed[purchaseId] = true
	table.insert(profile.Receipts.Order, purchaseId)

	while #profile.Receipts.Order > MAX_RECEIPT_HISTORY do
		local oldestPurchaseId = table.remove(profile.Receipts.Order, 1)
		profile.Receipts.Processed[oldestPurchaseId] = nil
	end

	return true
end

function MonetizationService:ProcessReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productKey = self.ProductKeysById[receiptInfo.ProductId]
	if not productKey then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok = pcall(function()
		local didGrant = false

		self.Registry:Get("PlayerDataService"):MutateProfile(player, "ProcessReceipt", {
			"Wallet",
			"Inventory",
			"Premium",
			"Progression",
			"Unlocks",
			"Boosts",
			"RodComponents",
			"Leaderstats",
		}, function(_, profile)
			if self:HasProcessedReceipt(profile, receiptInfo.PurchaseId) then
				return
			end

			didGrant = self:_grantProduct(profile, productKey, self:_takeProductContext(player, productKey)) ~= false
			self:MarkReceiptProcessed(profile, receiptInfo.PurchaseId)
		end)

		local definition = ProductConfig.DeveloperProducts[productKey]
		if didGrant and definition.GrantInstantRebirth then
			self.Registry:Get("RebirthService"):GrantPaidRebirths(player, 1)
		end
	end)

	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return MonetizationService
