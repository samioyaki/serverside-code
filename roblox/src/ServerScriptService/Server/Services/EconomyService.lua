local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlayerUpgradeConfig = require(Shared.Config.PlayerUpgradeConfig)
local RebirthUpgradeConfig = require(Shared.Config.RebirthUpgradeConfig)
local RodConfig = require(Shared.Config.RodConfig)

local EconomyService = {}
EconomyService.__index = EconomyService

local function fail(code)
	error(code, 0)
end

function EconomyService.new(registry)
	return setmetatable({
		Registry = registry,
	}, EconomyService)
end

function EconomyService:AddCoins(profile, amount)
	profile.Wallet.Coins += amount
end

function EconomyService:AddUnclaimedCoins(profile, amount)
	profile.Wallet.UnclaimedCoins += amount
end

function EconomyService:ClaimUnclaimed(profile)
	local amount = profile.Wallet.UnclaimedCoins
	profile.Wallet.UnclaimedCoins = 0
	profile.Wallet.Coins += amount
	return amount
end

function EconomyService:ApplyStartingMomentum(profile)
	local definition = RebirthUpgradeConfig.Definitions.StartingMomentum
	local level = profile.RebirthUpgrades and profile.RebirthUpgrades.StartingMomentum or 0
	if type(level) ~= "number" or level <= 0 then
		return
	end

	local bestRodId = nil
	for index = 1, math.min(math.floor(level), definition.MaxLevel) do
		local rodId = definition.UnlockRodByLevel[index]
		if rodId and RodConfig.Definitions[rodId] then
			profile.Unlocks.Rods[rodId] = true
			bestRodId = rodId
		end
	end

	if not bestRodId then
		return
	end

	local equippedIndex = table.find(RodConfig.Order, profile.Progression.EquippedRodId) or 1
	local bestIndex = table.find(RodConfig.Order, bestRodId) or equippedIndex
	if equippedIndex < bestIndex or not profile.Unlocks.Rods[profile.Progression.EquippedRodId] then
		profile.Progression.EquippedRodId = bestRodId
	end
end

function EconomyService:RemoveCoins(profile, amount)
	if profile.Wallet.Coins < amount then
		fail("NotEnoughCoins")
	end

	profile.Wallet.Coins -= amount
	profile.Stats.LifetimeSpentCoins += amount
end

function EconomyService:ResetForRebirth(profile)
	profile.Wallet.Coins = 0
	profile.Wallet.UnclaimedCoins = 0
	profile.Progression.EquippedRodId = "StarterRod"
	profile.Progression.PlotSlots = 10
	profile.Progression.PlotExpansionPurchases = 0
	profile.Progression.ChainBonus = 0
	profile.Inventory.Baddies = {}
	profile.Inventory.Order = {}
	profile.Inventory.Crates = {}
	profile.Placements = {}
	profile.Boosts = {
		Income = {},
		Luck = {},
	}
	for _, upgradeId in ipairs(PlayerUpgradeConfig.Order) do
		profile.PlayerUpgrades[upgradeId] = 0
	end
	profile.Unlocks.Rods = {
		StarterRod = true,
	}
	self:ApplyStartingMomentum(profile)
end

return EconomyService
