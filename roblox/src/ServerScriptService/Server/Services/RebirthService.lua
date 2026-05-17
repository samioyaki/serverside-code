local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FormulaUtil = require(Shared.Util.FormulaUtil)
local RebirthConfig = require(Shared.Config.RebirthConfig)

local RebirthService = {}
RebirthService.__index = RebirthService

local function fail(code)
	error(code, 0)
end

function RebirthService.new(registry)
	return setmetatable({
		Registry = registry,
	}, RebirthService)
end

function RebirthService:CanRebirth(player)
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	return session.Profile.Wallet.Coins >= FormulaUtil.GetRebirthCost(session.Profile.Progression.RebirthCount)
end

function RebirthService:_executeInternal(player, ignoreRequirement)
	if self.Registry:Get("FishingService"):HasActiveSession(player) then
		fail("FishingAlreadyActive")
	end

	self.Registry:Get("IncomeService"):Accrue(player, "BeforeRebirth")
	self.Registry:Get("PlacementService"):ClearHeldBaddie(player, true)
	self.Registry:Get("PlacementService").OccupiedCellsByUserId[player.UserId] = {}

	local newRebirthCount = 0
	self.Registry:Get("PlayerDataService"):MutateProfile(player, "Rebirth", {
		"Wallet",
		"Progression",
		"Inventory",
		"Plot",
		"Boosts",
		"Unlocks",
		"Leaderstats",
		"RodComponents",
		"Stats",
		"PlayerUpgrades",
		"RebirthUpgrades",
	}, function(session, profile)
		local requiredCoins = FormulaUtil.GetRebirthCost(profile.Progression.RebirthCount)
		if not ignoreRequirement and profile.Wallet.Coins < requiredCoins then
			fail("RebirthRequirementNotMet")
		end

		local secretIds = {}
		for baddieId, baddie in pairs(profile.Inventory.Baddies) do
			if baddie.RarityId == "Secret" then
				table.insert(secretIds, baddieId)
			end
		end

		for _, baddieId in ipairs(secretIds) do
			self.Registry:Get("FusionService"):ConvertSecretFromProfile(profile, baddieId)
		end

		profile.Progression.RebirthCount += 1
		profile.Wallet.RebirthShards += RebirthConfig.RewardShardsPerRebirth
		newRebirthCount = profile.Progression.RebirthCount
		self.Registry:Get("EconomyService"):ResetForRebirth(profile)
		self.Registry:Get("RodComponentService"):ResetProfileComponents(profile)
		session.Runtime.LastIncomeAccruedAt = os.time()
	end)

	return newRebirthCount
end

function RebirthService:Execute(player)
	return self:_executeInternal(player, false)
end

function RebirthService:GrantPaidRebirths(player, amount)
	local finalCount = 0

	for _ = 1, amount do
		finalCount = self:_executeInternal(player, true)
	end

	return finalCount
end

return RebirthService
