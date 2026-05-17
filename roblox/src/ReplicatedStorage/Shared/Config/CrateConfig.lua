local CrateConfig = {
	Order = {
		"BasicCrate",
		"PremiumCrate",
		"GodCrate",
		"AbyssCrate",
	},
	Definitions = {
		BasicCrate = {
			Id = "BasicCrate",
			DisplayName = "Basic Crate",
			ProductKey = "BasicCrate",
			RewardWeights = {
				Rare = 6000,
				Epic = 2500,
				Legendary = 1200,
				Mythic = 250,
				Secret = 50,
			},
		},
		PremiumCrate = {
			Id = "PremiumCrate",
			DisplayName = "Premium Crate",
			ProductKey = "PremiumCrate",
			RewardWeights = {
				Epic = 7000,
				Legendary = 2400,
				Mythic = 500,
				Secret = 100,
			},
		},
		GodCrate = {
			Id = "GodCrate",
			DisplayName = "God Crate",
			ProductKey = "GodCrate",
			RewardWeights = {
				Legendary = 8500,
				Mythic = 1400,
				Secret = 100,
			},
		},
		AbyssCrate = {
			Id = "AbyssCrate",
			DisplayName = "Abyss Crate",
			ProductKey = "AbyssCrate",
			RewardWeights = {
				Mythic = 9500,
				Secret = 500,
			},
		},
	},
}

return table.freeze(CrateConfig)
