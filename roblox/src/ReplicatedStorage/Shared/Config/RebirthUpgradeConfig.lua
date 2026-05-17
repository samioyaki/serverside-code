local RebirthUpgradeConfig = {
	Order = {
		"GlobalIncome",
		"GlobalLuck",
		"RebirthCastSpeed",
		"BoostDuration",
		"StartingMomentum",
	},
	Definitions = {
		GlobalIncome = {
			Id = "GlobalIncome",
			DisplayName = "Global Income",
			Description = "+7.5% income per level",
			MaxLevel = 12,
			BaseCost = 5,
			CostGrowth = 1.6,
			IncomeBonusBps = 750,
		},
		GlobalLuck = {
			Id = "GlobalLuck",
			DisplayName = "Global Luck",
			Description = "+3% rarity luck per level",
			MaxLevel = 12,
			BaseCost = 5,
			CostGrowth = 1.65,
			LuckBonusBps = 300,
		},
		RebirthCastSpeed = {
			Id = "RebirthCastSpeed",
			DisplayName = "Cast Mastery",
			Description = "+2% cast speed per level",
			MaxLevel = 8,
			BaseCost = 6,
			CostGrowth = 1.65,
			CastSpeedBonusBps = 200,
		},
		BoostDuration = {
			Id = "BoostDuration",
			DisplayName = "Longer Boosts",
			Description = "+10% new boost duration per level",
			MaxLevel = 8,
			BaseCost = 8,
			CostGrowth = 1.7,
			DurationBonusBps = 1000,
		},
		StartingMomentum = {
			Id = "StartingMomentum",
			DisplayName = "Starting Momentum",
			Description = "Start each rebirth cycle with stronger rods unlocked",
			MaxLevel = 5,
			BaseCost = 10,
			CostGrowth = 2,
			UnlockRodByLevel = {
				"BreezeRod",
				"SurgeRod",
				"CoralRod",
				"FluxRod",
				"VoidlineRod",
			},
		},
	},
}

return table.freeze(RebirthUpgradeConfig)
