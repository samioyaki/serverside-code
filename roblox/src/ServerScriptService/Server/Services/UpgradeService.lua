local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormulaUtil = require(ReplicatedStorage.Shared.Util.FormulaUtil)

local UpgradeService = {}
UpgradeService.__index = UpgradeService

local function fail(code)
	error(code, 0)
end

function UpgradeService.new(registry)
	return setmetatable({
		Registry = registry,
	}, UpgradeService)
end

function UpgradeService:_upgradeBaddieInProfile(profile, baddieId, requestedLevels, freeLevels)
	local levelsBought = 0
	local totalCost = 0
	local now = os.time()
	local baddie = self.Registry:Get("InventoryService"):AssertBaddie(profile, baddieId)
	local targetLevels = requestedLevels or 1
	local freeRemaining = freeLevels or 0

	while levelsBought < targetLevels do
		local maxLevel = FormulaUtil.GetMaxLevelForRarity(baddie.RarityId)
		if baddie.Level >= maxLevel then
			break
		end

		local levelCost = FormulaUtil.GetBaddieUpgradeCost(baddie, baddie.RarityId)
		if freeRemaining > 0 then
			freeRemaining -= 1
		else
			if profile.Wallet.Coins < levelCost then
				break
			end

			self.Registry:Get("EconomyService"):RemoveCoins(profile, levelCost)
			totalCost += levelCost
		end

		baddie.Level += 1
		baddie.UpdatedAt = now
		levelsBought += 1
	end

	if levelsBought <= 0 then
		fail("UpgradeMaxLevel")
	end

	return levelsBought, totalCost
end

function UpgradeService:UpgradeBaddie(player, baddieId, requestedLevels, freeLevels)
	local levelsBought = 0
	local totalCost = 0

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "UpgradeBaddie", {
		"Wallet",
		"Inventory",
		"Leaderstats",
	}, function(_, profile)
		levelsBought, totalCost = self:_upgradeBaddieInProfile(profile, baddieId, requestedLevels, freeLevels)
	end)

	return levelsBought, totalCost
end

function UpgradeService:ApplyUpgradePack(player, baddieId)
	local levelsBought = 0
	local totalCost = 0

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "ApplyUpgradePack", {
		"Wallet",
		"Inventory",
		"Premium",
		"Leaderstats",
	}, function(_, profile)
		local currentPacks = profile.Premium.Products.InstantUpgradePack or 0
		if currentPacks <= 0 then
			fail("NotEnoughUpgradePacks")
		end

		levelsBought, totalCost = self:_upgradeBaddieInProfile(profile, baddieId, 10, 10)
		profile.Premium.Products.InstantUpgradePack = currentPacks - 1
	end)

	return levelsBought, totalCost
end

return UpgradeService
