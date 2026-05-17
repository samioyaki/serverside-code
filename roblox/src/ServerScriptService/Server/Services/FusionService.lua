local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FusionConfig = require(Shared.Config.FusionConfig)

local FusionService = {}
FusionService.__index = FusionService

local function fail(code)
	error(code, 0)
end

function FusionService.new(registry)
	return setmetatable({
		Registry = registry,
	}, FusionService)
end

function FusionService:FuseTemplate(player, templateId)
	local removedCount = 0

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "FuseTemplate", {
		"Inventory",
		"Wallet",
		"Dex",
		"Plot",
	}, function(_, profile)
		local duplicateIds = self.Registry:Get("InventoryService"):GetTemplateDuplicateIds(profile, templateId, FusionConfig.RequiredDuplicates, false)
		if not duplicateIds then
			fail("FuseRequirementNotMet")
		end

		for index = 1, FusionConfig.RequiredDuplicates do
			self.Registry:Get("InventoryService"):RemoveBaddie(profile, duplicateIds[index])
			removedCount += 1
		end

		profile.Wallet.FusionShards += FusionConfig.RewardFusionShards
	end)

	return removedCount
end

function FusionService:ConvertSecretFromProfile(profile, baddieId)
	local baddie = self.Registry:Get("InventoryService"):AssertBaddie(profile, baddieId)
	if baddie.RarityId ~= "Secret" then
		fail("SecretConversionNotAllowed")
	end

	local multiplierBps = profile.Premium.Effects.SecretConversionMultiplierBps or 10000
	profile.Progression.SecretIncomeBonusBps += math.floor(FusionConfig.ConvertSecretIncomeBps * multiplierBps / 10000)
	profile.Progression.SecretLuckBonusBps += math.floor(FusionConfig.ConvertSecretLuckBps * multiplierBps / 10000)
	profile.Stats.SecretsConverted += 1
	self.Registry:Get("InventoryService"):RemoveBaddie(profile, baddieId)
end

function FusionService:ConvertSecret(player, baddieId)
	self.Registry:Get("PlayerDataService"):MutateProfile(player, "ConvertSecret", {
		"Inventory",
		"Progression",
		"Wallet",
		"Plot",
	}, function(_, profile)
		self:ConvertSecretFromProfile(profile, baddieId)
	end)
end

return FusionService
