local ReplicaSchema = {}

function ReplicaSchema.CreateEmpty()
	return {
		Revision = 0,
		ServerTime = 0,
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
			SecretIncomeBonusBps = 0,
			SecretLuckBonusBps = 0,
		},
		Inventory = {
			Order = {},
			Baddies = {},
			Crates = {},
		},
		PlayerUpgrades = {},
		RebirthUpgrades = {},
		RodComponents = {},
		Unlocks = {
			Rods = {},
			ShopEntries = {},
		},
		Plot = {
			PlotId = nil,
			GridWidth = 0,
			GridHeight = 0,
			EffectiveSlots = 0,
			HeldBaddieId = nil,
			Cells = {},
			Placements = {},
			OccupiedCells = {},
		},
		Fishing = nil,
		Dex = {
			Rarities = {},
			Templates = {},
			Milestones = {},
		},
		Stats = {
			CaughtByRarity = {},
		},
		Boosts = {
			Income = {},
			Luck = {},
		},
		Premium = {
			OwnedPasses = {},
			Products = {},
			Effects = {},
		},
		Leaderstats = {
			Coins = 0,
			Rebirths = 0,
			Caught = 0,
		},
		Settings = {
			MusicEnabled = true,
			SfxEnabled = true,
		},
	}
end

return ReplicaSchema
