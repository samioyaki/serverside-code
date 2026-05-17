local FishingConfig = require(script.Parent.Parent.Config.FishingConfig)
local PlayerUpgradeConfig = require(script.Parent.Parent.Config.PlayerUpgradeConfig)
local RebirthConfig = require(script.Parent.Parent.Config.RebirthConfig)
local RebirthUpgradeConfig = require(script.Parent.Parent.Config.RebirthUpgradeConfig)
local RarityConfig = require(script.Parent.Parent.Config.RarityConfig)
local RodComponentConfig = require(script.Parent.Parent.Config.RodComponentConfig)
local RodConfig = require(script.Parent.Parent.Config.RodConfig)
local TraitConfig = require(script.Parent.Parent.Config.TraitConfig)

local FormulaUtil = {}

local function getBoostMultiplierBps(boostEntries, now)
	local multiplierBps = 10000

	for _, boost in ipairs(boostEntries) do
		if boost.ExpiresAt > now then
			multiplierBps = math.max(multiplierBps, boost.MultiplierBps)
		end
	end

	return math.max(multiplierBps, 0)
end

local function getUpgradeLevel(levels, upgradeId)
	local level = levels and levels[upgradeId] or 0
	if type(level) ~= "number" then
		return 0
	end

	return math.max(0, math.floor(level))
end

function FormulaUtil.GetPlayerUpgradeLevel(profile, upgradeId)
	return getUpgradeLevel(profile.PlayerUpgrades, upgradeId)
end

function FormulaUtil.GetRebirthUpgradeLevel(profile, upgradeId)
	return getUpgradeLevel(profile.RebirthUpgrades, upgradeId)
end

function FormulaUtil.GetUpgradeCost(definition, currentLevel)
	if not definition or currentLevel >= definition.MaxLevel then
		return nil
	end

	return math.floor(definition.BaseCost * (definition.CostGrowth ^ currentLevel) + 0.5)
end

function FormulaUtil.GetPlayerUpgradeCost(upgradeId, currentLevel)
	return FormulaUtil.GetUpgradeCost(PlayerUpgradeConfig.Definitions[upgradeId], currentLevel)
end

function FormulaUtil.GetRebirthUpgradeCost(upgradeId, currentLevel)
	return FormulaUtil.GetUpgradeCost(RebirthUpgradeConfig.Definitions[upgradeId], currentLevel)
end

function FormulaUtil.GetPlayerUpgradeBonusBps(profile, upgradeId, field)
	local definition = PlayerUpgradeConfig.Definitions[upgradeId]
	return definition and (definition[field] or 0) * FormulaUtil.GetPlayerUpgradeLevel(profile, upgradeId) or 0
end

function FormulaUtil.GetRebirthUpgradeBonusBps(profile, upgradeId, field)
	local definition = RebirthUpgradeConfig.Definitions[upgradeId]
	return definition and (definition[field] or 0) * FormulaUtil.GetRebirthUpgradeLevel(profile, upgradeId) or 0
end

function FormulaUtil.GetBoostDurationSeconds(profile, baseDurationSeconds)
	local durationBonusBps = FormulaUtil.GetRebirthUpgradeBonusBps(profile, "BoostDuration", "DurationBonusBps")
	return math.max(1, math.floor(baseDurationSeconds * (10000 + durationBonusBps) / 10000 + 0.5))
end

function FormulaUtil.GetChainBonusGainBps(profile)
	return 100 + FormulaUtil.GetPlayerUpgradeBonusBps(profile, "ChainFocus", "ChainGainBps")
end

function FormulaUtil.GetChainBonusCapBps(profile)
	return 1500 + FormulaUtil.GetPlayerUpgradeBonusBps(profile, "ChainFocus", "ChainCapBps")
end

function FormulaUtil.GetTraitIncomeMultiplierBps(baddieRecord)
	local multiplierBps = 10000

	for _, traitId in ipairs(baddieRecord.TraitIds or {}) do
		local definition = TraitConfig.Definitions[traitId]
		if definition then
			multiplierBps = math.floor(multiplierBps * definition.IncomeMultiplierBps / 10000)
		end
	end

	return multiplierBps
end

function FormulaUtil.GetTraitLuckMultiplierBps(baddieRecord)
	local multiplierBps = 10000

	for _, traitId in ipairs(baddieRecord.TraitIds or {}) do
		local definition = TraitConfig.Definitions[traitId]
		if definition then
			multiplierBps = math.floor(multiplierBps * definition.LuckMultiplierBps / 10000)
		end
	end

	return multiplierBps
end

function FormulaUtil.GetBaddieIncomePerSecond(baddieRecord, profile)
	local rarity = RarityConfig.Definitions[baddieRecord.RarityId]
	if not rarity then
		return 0
	end

	local levelMultiplier = math.floor(10000 * (1 + (baddieRecord.Level - 1) * 0.15))
	local income = rarity.BaseIncomePerSecond
	income = income * levelMultiplier / 10000
	income = income * FormulaUtil.GetTraitIncomeMultiplierBps(baddieRecord) / 10000
	income = income * (10000 + (profile.Progression.RebirthCount * RebirthConfig.PassiveIncomePerRebirthBps)) / 10000
	income = income * (10000 + FormulaUtil.GetRebirthUpgradeBonusBps(profile, "GlobalIncome", "IncomeBonusBps")) / 10000
	income = income * (10000 + profile.Progression.SecretIncomeBonusBps) / 10000
	income = income * (10000 + FormulaUtil.GetComponentChainIncomeBonusBps(profile)) / 10000
	income = income * getBoostMultiplierBps(profile.Boosts.Income, os.time()) / 10000
	income = income * ((profile.Premium.Effects.IncomeMultiplierBps or 10000) / 10000)

	return income
end

function FormulaUtil.GetBaddieUpgradeCost(baddieRecord, rarityId)
	local rarity = RarityConfig.Definitions[rarityId]
	if not rarity then
		return 0
	end

	return math.floor(rarity.BaseIncomePerSecond * (1.35 ^ math.max(0, baddieRecord.Level - 1)) * 100)
end

function FormulaUtil.GetMaxLevelForRarity(rarityId)
	local rarity = RarityConfig.Definitions[rarityId]
	return rarity and rarity.MaxLevel or 10
end

function FormulaUtil.GetRebirthCost(rebirthCount)
	return math.floor(RebirthConfig.BaseCost * (RebirthConfig.CostGrowth ^ rebirthCount))
end

function FormulaUtil.GetRodCastDuration(profile)
	local rod = RodConfig.Definitions[profile.Progression.EquippedRodId] or RodConfig.Definitions.StarterRod
	local castDuration = rod.CastDurationSeconds
	local castSpeedMultiplierBps = (profile.Premium.Effects.CastSpeedMultiplierBps or 10000)
		+ FormulaUtil.GetComponentCastSpeedBonusBps(profile)
		+ FormulaUtil.GetPlayerUpgradeBonusBps(profile, "CastSpeed", "CastSpeedBonusBps")
		+ FormulaUtil.GetRebirthUpgradeBonusBps(profile, "RebirthCastSpeed", "CastSpeedBonusBps")
	local tensionBuildMultiplierBps = rod.TensionBuildMultiplierBps or 10000

	return castDuration * 100000000 / (castSpeedMultiplierBps * tensionBuildMultiplierBps)
end

function FormulaUtil.GetFishingWindowHalfWidth(profile)
	local rod = RodConfig.Definitions[profile.Progression.EquippedRodId] or RodConfig.Definitions.StarterRod
	local windowMultiplierBps = rod.WindowMultiplierBps or 10000
	local componentBonus = FormulaUtil.GetComponentWindowBonusBps(profile)
		+ FormulaUtil.GetPlayerUpgradeBonusBps(profile, "TimingWindow", "WindowBonusBps")

	return math.max(0.02, FishingConfig.SweetSpotWindow * (windowMultiplierBps + componentBonus) / 10000)
end

function FormulaUtil.BuildLuckMultiplierBps(profile, skillMultiplierBps)
	local rod = RodConfig.Definitions[profile.Progression.EquippedRodId] or RodConfig.Definitions.StarterRod
	local multiplierBps = 10000

	multiplierBps = math.floor(multiplierBps * rod.LuckMultiplierBps / 10000)
	multiplierBps = math.floor(multiplierBps * (10000 + FormulaUtil.GetComponentLuckBonusBps(profile)) / 10000)
	multiplierBps = math.floor(multiplierBps * (10000 + FormulaUtil.GetPlayerUpgradeBonusBps(profile, "LuckTraining", "LuckBonusBps")) / 10000)
	multiplierBps = math.floor(multiplierBps * (profile.Premium.Effects.LuckMultiplierBps or 10000) / 10000)
	multiplierBps = math.floor(multiplierBps * (10000 + (profile.Progression.RebirthCount * RebirthConfig.PassiveLuckPerRebirthBps)) / 10000)
	multiplierBps = math.floor(multiplierBps * (10000 + FormulaUtil.GetRebirthUpgradeBonusBps(profile, "GlobalLuck", "LuckBonusBps")) / 10000)
	multiplierBps = math.floor(multiplierBps * (10000 + profile.Progression.SecretLuckBonusBps) / 10000)
	multiplierBps = math.floor(multiplierBps * getBoostMultiplierBps(profile.Boosts.Luck, os.time()) / 10000)
	multiplierBps = math.floor(multiplierBps * skillMultiplierBps / 10000)

	return multiplierBps
end

function FormulaUtil.ApplyLuckToWeights(weightMap, profile, skillMultiplierBps, randomObject)
	local rod = RodConfig.Definitions[profile.Progression.EquippedRodId] or RodConfig.Definitions.StarterRod
	local adjusted = {}
	local luckMultiplierBps = FormulaUtil.BuildLuckMultiplierBps(profile, skillMultiplierBps)
	local rarityOrder = RarityConfig.Order
	local bonusFloorApplied = false
	local randomSource = randomObject or Random.new()

	if rod.BonusMinRarityIndex and rod.BonusMinRarityChanceBps and rod.BonusMinRarityChanceBps > 0 then
		bonusFloorApplied = randomSource:NextInteger(1, 10000) <= rod.BonusMinRarityChanceBps
	end

	for rarityId, weight in pairs(weightMap) do
		local bonusBps = luckMultiplierBps
		if rarityId == "Mythic" then
			bonusBps += rod.MythicBonusBps or 0
		elseif rarityId == "Secret" then
			bonusBps = math.floor(bonusBps * (rod.SecretWeightMultiplierBps or 10000) / 10000)
		end

		local rarityIndex = table.find(rarityOrder, rarityId) or 1
		if rod.MinimumRarityIndex and rarityIndex < rod.MinimumRarityIndex then
			adjusted[rarityId] = 0
		elseif bonusFloorApplied and rarityIndex < rod.BonusMinRarityIndex then
			adjusted[rarityId] = 0
		else
			adjusted[rarityId] = math.max(1, math.floor(weight * bonusBps / 10000))
		end
	end

	if rod.SecretGuaranteeChanceBps and rod.SecretGuaranteeChanceBps > 0 then
		if randomSource:NextInteger(1, 10000) <= rod.SecretGuaranteeChanceBps then
			adjusted.Secret = 10 ^ 12
		end
	end

	return adjusted
end

-- Returns the component record for a given rod and slot (tier 1-based)
function FormulaUtil.GetComponentRecord(rodId, componentName, tier)
	local def = RodComponentConfig[componentName]
	if not def then return nil end
	return def[math.clamp(tier or 1, 1, RodComponentConfig.MaxTier)]
end

-- Single generic lookup used by all component bonus getters.
-- Caches the rodId and components table once so callers that chain multiple
-- getters in the same frame don't repeatedly navigate profile.RodComponents.
local function getComponentBonus(profile, componentSlot, field)
	local rodId = profile.Progression.EquippedRodId
	local components = profile.RodComponents and profile.RodComponents[rodId]
	local tier = components and components[componentSlot] or 1
	local rec = FormulaUtil.GetComponentRecord(rodId, componentSlot, tier)
	return rec and rec[field] or 0
end

function FormulaUtil.GetComponentWindowBonusBps(profile)
	return getComponentBonus(profile, "Line", "WindowBonusBps")
end

function FormulaUtil.GetComponentLuckBonusBps(profile)
	return getComponentBonus(profile, "Hook", "LuckBonusBps")
end

function FormulaUtil.GetComponentTraitLuckBonusBps(profile)
	return getComponentBonus(profile, "Hook", "TraitLuckBonusBps")
end

function FormulaUtil.GetComponentCastSpeedBonusBps(profile)
	return getComponentBonus(profile, "Reel", "CastSpeedBonusBps")
end

function FormulaUtil.GetComponentChainIncomeBonusBps(profile)
	return getComponentBonus(profile, "Reel", "ChainIncomeBonusBps")
end

-- Returns the upgrade cost for a component tier, scaled by rod cost tier.
-- Returns nil when componentName is invalid or the component is already max tier.
function FormulaUtil.GetComponentUpgradeCost(rodId, componentName, currentTier)
	local def = RodComponentConfig[componentName]
	if not def then return nil end
	local nextTier = currentTier + 1
	if nextTier > RodComponentConfig.MaxTier then return nil end
	local baseCost = def[nextTier].Cost
	local costMult = RodComponentConfig.RodCostTiers[rodId] or 1
	return math.floor(baseCost * costMult + 0.5)
end

return FormulaUtil
