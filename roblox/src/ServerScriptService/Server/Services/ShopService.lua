local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FormulaUtil = require(Shared.Util.FormulaUtil)
local PlayerUpgradeConfig = require(Shared.Config.PlayerUpgradeConfig)
local RebirthUpgradeConfig = require(Shared.Config.RebirthUpgradeConfig)
local ShopCatalog = require(Shared.Config.ShopCatalog)
local RodConfig = require(Shared.Config.RodConfig)
local RodUtil = require(Shared.Util.RodUtil)

local ShopService = {}
ShopService.__index = ShopService

local function fail(code)
	error(code, 0)
end

local function getLevel(container, upgradeId)
	local level = container and container[upgradeId] or 0
	if type(level) ~= "number" then
		return 0
	end

	return math.max(0, math.floor(level))
end

function ShopService.new(registry)
	return setmetatable({
		Registry = registry,
	}, ShopService)
end

function ShopService:Purchase(player, entryId, quantity)
	local entry = ShopCatalog.Definitions[entryId]
	if not entry then
		fail("UnknownShopEntry")
	end

	quantity = quantity or 1
	if quantity < 1 then
		fail("InvalidShopAction")
	end

	local totalCost = (entry.Price or 0) * quantity

	local publishedPaths = {
		"Wallet",
		"Progression",
		"Inventory",
		"Unlocks",
		"Boosts",
		"Plot",
		"Leaderstats",
		"PlayerUpgrades",
		"RebirthUpgrades",
	}

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "PurchaseShopEntry", publishedPaths, function(_, profile)
		if entry.Type == "Rod" then
			if quantity ~= 1 then
				fail("InvalidShopAction")
			end

			if profile.Unlocks.Rods[entry.RodId] then
				profile.Progression.EquippedRodId = entry.RodId
				return
			end

			if not RodUtil.MeetsUnlockRequirements(profile, entry.RodId) then
				fail("RodRequirementNotMet")
			end

			self.Registry:Get("EconomyService"):RemoveCoins(profile, entry.Price)
			profile.Unlocks.Rods[entry.RodId] = true
			profile.Progression.EquippedRodId = entry.RodId
			profile.Unlocks.ShopEntries[entryId] = true
		elseif entry.Type == "PlotSlot" then
			self.Registry:Get("EconomyService"):RemoveCoins(profile, totalCost)
			profile.Progression.PlotSlots += entry.Amount * quantity
		elseif entry.Type == "Boost" then
			self.Registry:Get("EconomyService"):RemoveCoins(profile, totalCost)
			for _ = 1, quantity do
				self.Registry:Get("MonetizationService"):GrantTimedBoost(
					profile,
					entry.BoostKind,
					entry.MultiplierBps,
					entry.DurationSeconds
				)
			end
		elseif entry.Type == "CrateTicket" then
			self.Registry:Get("MonetizationService"):AssertPaidRandomItemsAllowed(player)
			self.Registry:Get("EconomyService"):RemoveCoins(profile, totalCost)
			profile.Inventory.Crates[entry.CrateId] = (profile.Inventory.Crates[entry.CrateId] or 0) + (entry.Quantity * quantity)
		elseif entry.Type == "PlayerUpgrade" then
			if quantity ~= 1 then
				fail("InvalidShopAction")
			end

			local definition = PlayerUpgradeConfig.Definitions[entry.UpgradeId]
			if not definition then
				fail("UnknownShopEntry")
			end

			local currentLevel = getLevel(profile.PlayerUpgrades, entry.UpgradeId)
			if currentLevel >= definition.MaxLevel then
				fail("UpgradeMaxLevel")
			end

			local cost = FormulaUtil.GetPlayerUpgradeCost(entry.UpgradeId, currentLevel)
			self.Registry:Get("EconomyService"):RemoveCoins(profile, cost)
			profile.PlayerUpgrades[entry.UpgradeId] = currentLevel + 1
		elseif entry.Type == "RebirthUpgrade" then
			if quantity ~= 1 then
				fail("InvalidShopAction")
			end

			local definition = RebirthUpgradeConfig.Definitions[entry.UpgradeId]
			if not definition then
				fail("UnknownShopEntry")
			end

			local currentLevel = getLevel(profile.RebirthUpgrades, entry.UpgradeId)
			if currentLevel >= definition.MaxLevel then
				fail("UpgradeMaxLevel")
			end

			local cost = FormulaUtil.GetRebirthUpgradeCost(entry.UpgradeId, currentLevel)
			if profile.Wallet.RebirthShards < cost then
				fail("NotEnoughRebirthShards")
			end

			profile.Wallet.RebirthShards -= cost
			profile.RebirthUpgrades[entry.UpgradeId] = currentLevel + 1
			if entry.UpgradeId == "StartingMomentum" then
				self.Registry:Get("EconomyService"):ApplyStartingMomentum(profile)
			end
		else
			fail("InvalidShopAction")
		end
	end)
end

function ShopService:EquipRod(player, rodId)
	local rodDefinition = RodConfig.Definitions[rodId]
	if not rodDefinition then
		fail("UnknownRod")
	end

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "EquipRod", {
		"Progression",
	}, function(_, profile)
		if not self.Registry:Get("MonetizationService"):PlayerOwnsRod(profile, rodId) then
			fail("UnknownRod")
		end

		profile.Progression.EquippedRodId = rodId
	end)
end

return ShopService
