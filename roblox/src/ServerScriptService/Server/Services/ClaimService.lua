local ClaimService = {}
ClaimService.__index = ClaimService

function ClaimService.new(registry)
	return setmetatable({
		Registry = registry,
	}, ClaimService)
end

function ClaimService:ClaimIncome(player)
	self.Registry:Get("IncomeService"):Accrue(player, "BeforeClaim")

	local claimedAmount = 0
	self.Registry:Get("PlayerDataService"):MutateProfile(player, "ClaimIncome", {
		"Wallet",
		"Leaderstats",
	}, function(_, profile)
		claimedAmount = self.Registry:Get("EconomyService"):ClaimUnclaimed(profile)
		if claimedAmount > 0 then
			profile.Stats.LifetimeClaimedCoins += claimedAmount
		end
	end)

	return claimedAmount
end

return ClaimService
