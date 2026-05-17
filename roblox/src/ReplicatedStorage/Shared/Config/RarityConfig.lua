local RarityConfig = {
	Order = {
		"Common",
		"Uncommon",
		"Rare",
		"Epic",
		"Legendary",
		"Mythic",
		"Secret",
	},
	Definitions = {
		Common = {
			Id = "Common",
			BaseWeight = 685000,
			BaseIncomePerSecond = 1,
			MaxLevel = 10,
		},
		Uncommon = {
			Id = "Uncommon",
			BaseWeight = 236000,
			BaseIncomePerSecond = 3,
			MaxLevel = 20,
		},
		Rare = {
			Id = "Rare",
			BaseWeight = 64000,
			BaseIncomePerSecond = 8,
			MaxLevel = 30,
		},
		Epic = {
			Id = "Epic",
			BaseWeight = 13000,
			BaseIncomePerSecond = 20,
			MaxLevel = 40,
		},
		Legendary = {
			Id = "Legendary",
			BaseWeight = 1700,
			BaseIncomePerSecond = 55,
			MaxLevel = 50,
		},
		Mythic = {
			Id = "Mythic",
			BaseWeight = 299,
			BaseIncomePerSecond = 150,
			MaxLevel = 75,
		},
		Secret = {
			Id = "Secret",
			BaseWeight = 1,
			BaseIncomePerSecond = 450,
			MaxLevel = 100,
		},
	},
	RewardColors = {
		Common = Color3.fromRGB(215, 215, 215),
		Uncommon = Color3.fromRGB(93, 214, 87),
		Rare = Color3.fromRGB(70, 165, 255),
		Epic = Color3.fromRGB(219, 76, 255),
		Legendary = Color3.fromRGB(255, 184, 28),
		Mythic = Color3.fromRGB(255, 79, 131),
		Secret = Color3.fromRGB(255, 58, 58),
	},
}

return table.freeze(RarityConfig)
