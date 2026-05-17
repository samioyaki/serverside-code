local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BaddieConfig = require(Shared.Config.BaddieConfig)
local CrateConfig = require(Shared.Config.CrateConfig)
local WeightedRandom = require(Shared.Util.WeightedRandom)

local CrateService = {}
CrateService.__index = CrateService

local function fail(code)
	error(code, 0)
end

function CrateService.new(registry)
	return setmetatable({
		Registry = registry,
		Random = Random.new(),
	}, CrateService)
end

function CrateService:GrantCrateTickets(profile, crateId, amount)
	profile.Inventory.Crates[crateId] = (profile.Inventory.Crates[crateId] or 0) + amount
end

function CrateService:_rollCrateReward(crateId, profile)
	local crate = CrateConfig.Definitions[crateId]
	if not crate then
		fail("UnknownCrate")
	end

	local rarityId = WeightedRandom.Roll(crate.RewardWeights, self.Random)
	local templates = BaddieConfig.ByRarity[rarityId]
	local templateId = templates[self.Random:NextInteger(1, #templates)]
	local traitId = self.Registry:Get("RollService"):RollFreshTrait(profile)

	return {
		TemplateId = templateId,
		RarityId = rarityId,
		TraitId = traitId,
	}
end

function CrateService:OpenOwnedCrate(player, crateId)
	local granted = nil
	self.Registry:Get("MonetizationService"):AssertPaidRandomItemsAllowed(player)

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "OpenCrate", {
		"Inventory",
		"Wallet",
		"Dex",
		"Leaderstats",
	}, function(_, profile)
		if (profile.Inventory.Crates[crateId] or 0) <= 0 then
			fail("CrateTicketMissing")
		end

		profile.Inventory.Crates[crateId] -= 1
		granted = self:_rollCrateReward(crateId, profile)
		local baddie = self.Registry:Get("InventoryService"):AddBaddie(
			profile,
			granted.TemplateId,
			granted.RarityId,
			granted.TraitId,
			"Crate",
			os.time()
		)

		self.Registry:Get("CollectionService"):RegisterBaddie(profile, baddie)
		profile.Stats.CratesOpened += 1
		granted.BaddieId = baddie.Id
	end)

	return granted
end

return CrateService
