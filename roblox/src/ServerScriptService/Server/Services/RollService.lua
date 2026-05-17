local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BaddieConfig = require(Shared.Config.BaddieConfig)
local FishingConfig = require(Shared.Config.FishingConfig)
local RodConfig = require(Shared.Config.RodConfig)
local TraitConfig = require(Shared.Config.TraitConfig)
local FormulaUtil = require(Shared.Util.FormulaUtil)
local WeightedRandom = require(Shared.Util.WeightedRandom)

local RollService = {}
RollService.__index = RollService

function RollService.new(registry)
	return setmetatable({
		Registry = registry,
		Random = Random.new(),
	}, RollService)
end

local function getTraitQualityTier(traitId)
	local definition = TraitConfig.Definitions[traitId]
	return definition and definition.QualityTier or 0
end

function RollService:_buildTraitWeights(profile, filterFn)
	local weights = {}
	local traitLuckBps = math.floor(
		(profile.Premium.Effects.TraitLuckBps or 10000)
			* (10000 + FormulaUtil.GetComponentTraitLuckBonusBps(profile))
			/ 10000
	)

	for traitId, definition in pairs(TraitConfig.Definitions) do
		if not filterFn or filterFn(definition, traitId) then
			local weight = definition.Weight
			if traitId ~= "None" then
				weight = math.floor(weight * traitLuckBps / 10000)
			end
			weights[traitId] = weight
		end
	end

	return weights
end

function RollService:_rollTrait(profile, options)
	options = options or {}

	local traitId = WeightedRandom.Roll(self:_buildTraitWeights(profile), self.Random) or "None"
	if not options.ApplyRodPassives then
		return traitId
	end

	local rod = RodConfig.Definitions[profile.Progression.EquippedRodId] or RodConfig.Definitions.StarterRod
	local traitQualityTier = getTraitQualityTier(traitId)

	if
		rod.AvoidBadTraitChanceBps
		and traitQualityTier <= 0
		and self.Random:NextInteger(1, 10000) <= rod.AvoidBadTraitChanceBps
	then
		traitId = WeightedRandom.Roll(
			self:_buildTraitWeights(profile, function(definition)
				return (definition.QualityTier or 0) > 0
			end),
			self.Random
		) or traitId
		traitQualityTier = getTraitQualityTier(traitId)
	end

	if
		rod.GoodTraitRollChanceBps
		and traitQualityTier < 2
		and self.Random:NextInteger(1, 10000) <= rod.GoodTraitRollChanceBps
	then
		traitId = WeightedRandom.Roll(
			self:_buildTraitWeights(profile, function(definition)
				return (definition.QualityTier or 0) >= 2
			end),
			self.Random
		) or traitId
	end

	return traitId
end

function RollService:RollFreshTrait(profile)
	return self:_rollTrait(profile, { ApplyRodPassives = false })
end

function RollService:RollFilteredTrait(profile, minQualityTier, maxQualityTier)
	minQualityTier = minQualityTier or 0
	maxQualityTier = maxQualityTier or math.huge

	return WeightedRandom.Roll(
		self:_buildTraitWeights(profile, function(definition)
			local qualityTier = definition.QualityTier or 0
			return qualityTier >= minQualityTier and qualityTier <= maxQualityTier
		end),
		self.Random
	) or "None"
end

function RollService:RollCatch(profile, skillMultiplierBps)
	local adjustedWeights =
		FormulaUtil.ApplyLuckToWeights(FishingConfig.RarityWeights, profile, skillMultiplierBps, self.Random)
	local rarityId = WeightedRandom.Roll(adjustedWeights, self.Random) or "Common"
	local templates = BaddieConfig.ByRarity[rarityId] or BaddieConfig.ByRarity.Common
	local templateId = templates[self.Random:NextInteger(1, #templates)]

	return {
		TemplateId = templateId,
		RarityId = rarityId,
		TraitId = self:_rollTrait(profile, { ApplyRodPassives = true }),
	}
end

return RollService
