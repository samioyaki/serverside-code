local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FormulaUtil = require(Shared.Util.FormulaUtil)
local RodComponentConfig = require(Shared.Config.RodComponentConfig)
local RodConfig = require(Shared.Config.RodConfig)

local RodComponentService = {}
RodComponentService.__index = RodComponentService

local function fail(code)
	error(code, 0)
end

function RodComponentService.new(registry)
	return setmetatable({
		Registry = registry,
	}, RodComponentService)
end

function RodComponentService:_assertComponent(componentName)
	if not RodComponentConfig[componentName] then
		fail("UnknownComponent")
	end
end

function RodComponentService:_resolveRodId(profile, rodId, allowFallback)
	rodId = rodId or profile.Progression.EquippedRodId
	if RodConfig.Definitions[rodId] and self.Registry:Get("MonetizationService"):PlayerOwnsRod(profile, rodId) then
		return rodId
	end

	if allowFallback then
		return profile.Progression.EquippedRodId
	end

	fail("UnknownRodForComponent")
	return nil
end

function RodComponentService:EnsureRodComponents(profile, rodId)
	profile.RodComponents = profile.RodComponents or {}
	profile.RodComponents[rodId] = profile.RodComponents[rodId] or {}

	for _, componentName in ipairs(RodComponentConfig.Components) do
		local tier = profile.RodComponents[rodId][componentName]
		if type(tier) ~= "number" or tier < 1 then
			tier = 1
		end

		profile.RodComponents[rodId][componentName] = math.clamp(math.floor(tier), 1, RodComponentConfig.MaxTier)
	end

	return profile.RodComponents[rodId]
end

function RodComponentService:ResetProfileComponents(profile)
	profile.RodComponents = {}

	for _, rodId in ipairs(RodConfig.Order) do
		self:EnsureRodComponents(profile, rodId)
	end
end

function RodComponentService:GetComponentBonuses(profile, rodId)
	rodId = self:_resolveRodId(profile, rodId, true)
	local components = self:EnsureRodComponents(profile, rodId)

	return {
		RodId = rodId,
		Line = components.Line,
		Hook = components.Hook,
		Reel = components.Reel,
		WindowBonusBps = FormulaUtil.GetComponentRecord(rodId, "Line", components.Line).WindowBonusBps or 0,
		LuckBonusBps = FormulaUtil.GetComponentRecord(rodId, "Hook", components.Hook).LuckBonusBps or 0,
		TraitLuckBonusBps = FormulaUtil.GetComponentRecord(rodId, "Hook", components.Hook).TraitLuckBonusBps or 0,
		CastSpeedBonusBps = FormulaUtil.GetComponentRecord(rodId, "Reel", components.Reel).CastSpeedBonusBps or 0,
		ChainIncomeBonusBps = FormulaUtil.GetComponentRecord(rodId, "Reel", components.Reel).ChainIncomeBonusBps or 0,
	}
end

function RodComponentService:UpgradeComponent(player, rodId, componentName)
	self:_assertComponent(componentName)

	local newTier = nil
	local spent = 0

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "UpgradeRodComponent", {
		"Wallet",
		"RodComponents",
		"Leaderstats",
	}, function(_, profile)
		local resolvedRodId = self:_resolveRodId(profile, rodId, false)
		local components = self:EnsureRodComponents(profile, resolvedRodId)
		local currentTier = components[componentName]
		if currentTier >= RodComponentConfig.MaxTier then
			fail("ComponentMaxTier")
		end

		local cost = FormulaUtil.GetComponentUpgradeCost(resolvedRodId, componentName, currentTier)
		if not cost then
			fail("ComponentMaxTier")
		end

		self.Registry:Get("EconomyService"):RemoveCoins(profile, cost)
		components[componentName] = currentTier + 1
		newTier = components[componentName]
		spent = cost
	end)

	return newTier, spent
end

function RodComponentService:MaxComponentForProfile(profile, rodId, componentName)
	self:_assertComponent(componentName)

	local resolvedRodId = self:_resolveRodId(profile, rodId, true)
	local components = self:EnsureRodComponents(profile, resolvedRodId)
	components[componentName] = RodComponentConfig.MaxTier

	return resolvedRodId, componentName, RodComponentConfig.MaxTier
end

function RodComponentService:MaxAllComponentsForProfile(profile, rodId)
	local resolvedRodId = self:_resolveRodId(profile, rodId, true)
	local components = self:EnsureRodComponents(profile, resolvedRodId)

	for _, componentName in ipairs(RodComponentConfig.Components) do
		components[componentName] = RodComponentConfig.MaxTier
	end

	return resolvedRodId, RodComponentConfig.MaxTier
end

return RodComponentService
