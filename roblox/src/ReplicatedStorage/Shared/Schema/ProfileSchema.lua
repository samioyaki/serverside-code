local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local PlayerUpgradeConfig = require(script.Parent.Parent.Config.PlayerUpgradeConfig)
local RarityConfig = require(script.Parent.Parent.Config.RarityConfig)
local RebirthUpgradeConfig = require(script.Parent.Parent.Config.RebirthUpgradeConfig)
local RodComponentConfig = require(script.Parent.Parent.Config.RodComponentConfig)
local RodConfig = require(script.Parent.Parent.Config.RodConfig)

local ProfileSchema = {}

local function createCaughtByRarity()
	local caughtByRarity = {}

	for _, rarityId in ipairs(RarityConfig.Order) do
		caughtByRarity[rarityId] = 0
	end

	return caughtByRarity
end

function ProfileSchema.CreateDefaultRodComponents()
	local rodComponents = {}

	for _, rodId in ipairs(RodConfig.Order) do
		rodComponents[rodId] = {}

		for _, componentName in ipairs(RodComponentConfig.Components) do
			rodComponents[rodId][componentName] = 1
		end
	end

	return rodComponents
end

local function createUpgradeLevels(config)
	local levels = {}

	for _, upgradeId in ipairs(config.Order) do
		levels[upgradeId] = 0
	end

	return levels
end

function ProfileSchema.CreateDefaultPlayerUpgrades()
	return createUpgradeLevels(PlayerUpgradeConfig)
end

function ProfileSchema.CreateDefaultRebirthUpgrades()
	return createUpgradeLevels(RebirthUpgradeConfig)
end

function ProfileSchema.CreateDefault(now)
	return {
		Meta = {
			DataVersion = 6,
			CreatedAt = now,
			UpdatedAt = now,
			LastSessionEndedAt = now,
			LastSavedAt = now,
			JoinCount = 0,
		},
		Wallet = {
			Coins = 0,
			UnclaimedCoins = 0,
			RebirthShards = 0,
			FusionShards = 0,
		},
		Progression = {
			RebirthCount = 0,
			EquippedRodId = "StarterRod",
			PlotSlots = 10,
			PlotExpansionPurchases = 0,
			SecretIncomeBonusBps = 0,
			SecretLuckBonusBps = 0,
			ChainBonus = 0,
		},
		Inventory = {
			Baddies = {},
			Order = {},
			Crates = {},
		},
		PlayerUpgrades = ProfileSchema.CreateDefaultPlayerUpgrades(),
		RebirthUpgrades = ProfileSchema.CreateDefaultRebirthUpgrades(),
		RodComponents = ProfileSchema.CreateDefaultRodComponents(),
		Unlocks = {
			Rods = {
				StarterRod = true,
			},
			ShopEntries = {},
		},
		Placements = {},
		Dex = {
			Rarities = {},
			Templates = {},
			Milestones = {},
		},
		Boosts = {
			Income = {},
			Luck = {},
		},
		Premium = {
			OwnedPasses = {},
			Products = {},
			ClaimedProducts = {},
			Effects = {},
		},
		Stats = {
			LifetimeCaught = 0,
			SuccessfulCatches = 0,
			FailedCatches = 0,
			CaughtByRarity = createCaughtByRarity(),
			LifetimeClaimedCoins = 0,
			LifetimeSpentCoins = 0,
			CratesOpened = 0,
			SecretsConverted = 0,
		},
		Receipts = {
			Processed = {},
			Order = {},
		},
		Settings = {
			MusicEnabled = true,
			SfxEnabled = true,
		},
	}
end

local function clampUpgradeLevels(levels, config)
	for _, upgradeId in ipairs(config.Order) do
		local definition = config.Definitions[upgradeId]
		local level = levels[upgradeId]
		if type(level) ~= "number" then
			level = 0
		end

		levels[upgradeId] = math.clamp(math.floor(level), 0, definition.MaxLevel)
	end
end

function ProfileSchema.Migrate(rawProfile, now)
	local defaultProfile = ProfileSchema.CreateDefault(now)

	if rawProfile == nil then
		return defaultProfile
	end

	local migrated = TableUtil.DeepCopy(rawProfile)
	TableUtil.AssignMissing(migrated, defaultProfile)
	migrated.Meta.DataVersion = defaultProfile.Meta.DataVersion
	migrated.Receipts.Order = migrated.Receipts.Order or {}
	migrated.Quests = nil
	if migrated.Stats then
		migrated.Stats.QuestsCompleted = nil
		migrated.Stats.CaughtByRarity = migrated.Stats.CaughtByRarity or createCaughtByRarity()
	end
	if migrated.Premium and migrated.Premium.OwnedPasses then
		migrated.Premium.OwnedPasses.DoubleSecretConversion = nil
	end
	if migrated.Premium and migrated.Premium.Products then
		if migrated.Premium.Products.ExtraSlots2 and migrated.Premium.Products.ExtraSlots2 > 1 then
			migrated.Premium.Products.ExtraSlots2 = 1
		end
		migrated.Premium.Products.RebirthBundle = nil
	end

	migrated.PlayerUpgrades = migrated.PlayerUpgrades or ProfileSchema.CreateDefaultPlayerUpgrades()
	migrated.RebirthUpgrades = migrated.RebirthUpgrades or ProfileSchema.CreateDefaultRebirthUpgrades()
	clampUpgradeLevels(migrated.PlayerUpgrades, PlayerUpgradeConfig)
	clampUpgradeLevels(migrated.RebirthUpgrades, RebirthUpgradeConfig)

	for _, rodId in ipairs(RodConfig.Order) do
		migrated.RodComponents[rodId] = migrated.RodComponents[rodId] or {}
		for _, componentName in ipairs(RodComponentConfig.Components) do
			local tier = migrated.RodComponents[rodId][componentName]
			if type(tier) ~= "number" then
				tier = 1
			end
			migrated.RodComponents[rodId][componentName] = math.clamp(math.floor(tier), 1, RodComponentConfig.MaxTier)
		end
	end

	return migrated
end

return ProfileSchema
