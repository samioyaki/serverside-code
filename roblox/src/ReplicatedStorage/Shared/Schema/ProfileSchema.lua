local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local BaddieConfig = require(script.Parent.Parent.Config.BaddieConfig)
local PlayerUpgradeConfig = require(script.Parent.Parent.Config.PlayerUpgradeConfig)
local PlotConfig = require(script.Parent.Parent.Config.PlotConfig)
local RarityConfig = require(script.Parent.Parent.Config.RarityConfig)
local RebirthUpgradeConfig = require(script.Parent.Parent.Config.RebirthUpgradeConfig)
local RodComponentConfig = require(script.Parent.Parent.Config.RodComponentConfig)
local RodConfig = require(script.Parent.Parent.Config.RodConfig)

local ProfileSchema = {}

local function finiteNumber(value, fallback, minimum, maximum)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end

	return math.clamp(value, minimum or -math.huge, maximum or math.huge)
end

local function sanitizeBoosts(bucket, now)
	local sanitized = {}
	for _, boost in ipairs(type(bucket) == "table" and bucket or {}) do
		if type(boost) == "table" then
			local multiplier = finiteNumber(boost.MultiplierBps, 10000, 10000, 1000000)
			local expiresAt = finiteNumber(boost.ExpiresAt, 0, 0)
			if expiresAt > now then
				table.insert(sanitized, { MultiplierBps = math.floor(multiplier), ExpiresAt = math.floor(expiresAt) })
			end
		end
	end
	return sanitized
end

local function sanitizeInventory(profile, now)
	local sanitizedBaddies = {}
	for baddieId, record in pairs(profile.Inventory.Baddies) do
		if type(baddieId) == "string" and type(record) == "table" then
			local templateId = record.TemplateId == "Nautic" and "Nautie" or record.TemplateId
			local template = type(templateId) == "string" and BaddieConfig.Definitions[templateId]
			if template and not template.LegacyAlias then
				record.Id = baddieId
				record.TemplateId = templateId
				record.RarityId = template.RarityId
				record.Level = math.max(1, math.floor(finiteNumber(record.Level, 1, 1, 100)))
				record.TraitIds = type(record.TraitIds) == "table" and record.TraitIds or { "None" }
				record.TraitLocks = type(record.TraitLocks) == "table" and record.TraitLocks or { false }
				record.Affection = math.floor(finiteNumber(record.Affection, 0, 0, 5))
				record.LastDatedAt = math.floor(finiteNumber(record.LastDatedAt, 0, 0, now))
				record.State = record.State == "Placed" and "Placed" or "Inventory"
				record.CreatedAt = math.floor(finiteNumber(record.CreatedAt, now, 0, now))
				record.UpdatedAt = math.floor(finiteNumber(record.UpdatedAt, now, 0, now))
				sanitizedBaddies[baddieId] = record
			end
		end
	end
	profile.Inventory.Baddies = sanitizedBaddies

	local order = {}
	local seen = {}
	for _, baddieId in ipairs(profile.Inventory.Order) do
		if sanitizedBaddies[baddieId] and not seen[baddieId] then
			seen[baddieId] = true
			table.insert(order, baddieId)
		end
	end
	for baddieId in pairs(sanitizedBaddies) do
		if not seen[baddieId] then
			table.insert(order, baddieId)
		end
	end
	profile.Inventory.Order = order

	local crates = {}
	for crateId, amount in pairs(profile.Inventory.Crates) do
		if type(crateId) == "string" and type(amount) == "number" and amount > 0 then
			crates[crateId] = math.min(10000, math.floor(amount))
		end
	end
	profile.Inventory.Crates = crates

	local placements = {}
	local occupied = {}
	for baddieId, placement in pairs(profile.Placements) do
		if sanitizedBaddies[baddieId] and type(placement) == "table" then
			local gridX = finiteNumber(placement.GridX, 0, 1, 64)
			local gridY = finiteNumber(placement.GridY, 0, 1, 64)
			if gridX % 1 == 0 and gridY % 1 == 0 then
				local key = string.format("%d:%d", gridX, gridY)
				if not occupied[key] then
					occupied[key] = true
					placements[baddieId] = {
						BaddieId = baddieId,
						GridX = gridX,
						GridY = gridY,
						Rotation = table.find({ 0, 90, 180, 270 }, placement.Rotation) and placement.Rotation or 0,
					}
					sanitizedBaddies[baddieId].State = "Placed"
				end
			end
		end
	end
	profile.Placements = placements
end

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
			DataVersion = 7,
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

	for key in pairs(migrated.Wallet) do
		migrated.Wallet[key] = finiteNumber(migrated.Wallet[key], defaultProfile.Wallet[key] or 0, 0, 10 ^ 15)
	end
	migrated.Progression.PlotSlots = math.floor(
		finiteNumber(
			migrated.Progression.PlotSlots,
			defaultProfile.Progression.PlotSlots,
			defaultProfile.Progression.PlotSlots,
			PlotConfig.MaxBaseSlots
		)
	)
	migrated.Progression.RebirthCount = math.floor(finiteNumber(migrated.Progression.RebirthCount, 0, 0, 10000))
	migrated.Progression.ChainBonus = math.floor(finiteNumber(migrated.Progression.ChainBonus, 0, 0, 100000))
	if not RodConfig.Definitions[migrated.Progression.EquippedRodId] then
		migrated.Progression.EquippedRodId = "StarterRod"
	end

	sanitizeInventory(migrated, now)
	migrated.Boosts.Income = sanitizeBoosts(migrated.Boosts.Income, now)
	migrated.Boosts.Luck = sanitizeBoosts(migrated.Boosts.Luck, now)
	for productKey, amount in pairs(migrated.Premium.Products) do
		migrated.Premium.Products[productKey] = math.floor(finiteNumber(amount, 0, 0, 10000))
	end
	for passKey, owned in pairs(migrated.Premium.OwnedPasses) do
		migrated.Premium.OwnedPasses[passKey] = owned == true
	end
	for _, rarityId in ipairs(RarityConfig.Order) do
		migrated.Stats.CaughtByRarity[rarityId] =
			math.floor(finiteNumber(migrated.Stats.CaughtByRarity[rarityId], 0, 0, 10 ^ 9))
	end
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
