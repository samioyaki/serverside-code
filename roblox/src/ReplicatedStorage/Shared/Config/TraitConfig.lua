local TraitConfig = {
	Order = {
		"None",
		"Greedy",
		"Lucky",
		"Swift",
		"Golden",
		"Divine",
	},
	Definitions = {
		None = {
			Id = "None",
			Weight = 6000,
			QualityTier = 0,
			IncomeMultiplierBps = 10000,
			LuckMultiplierBps = 10000,
		},
		Greedy = {
			Id = "Greedy",
			Weight = 2200,
			QualityTier = 1,
			IncomeMultiplierBps = 11500,
			LuckMultiplierBps = 10000,
		},
		Lucky = {
			Id = "Lucky",
			Weight = 1400,
			QualityTier = 1,
			IncomeMultiplierBps = 10000,
			LuckMultiplierBps = 11250,
		},
		Swift = {
			Id = "Swift",
			Weight = 250,
			QualityTier = 2,
			IncomeMultiplierBps = 10800,
			LuckMultiplierBps = 12250,
		},
		Golden = {
			Id = "Golden",
			Weight = 120,
			QualityTier = 2,
			IncomeMultiplierBps = 14500,
			LuckMultiplierBps = 12500,
		},
		Divine = {
			Id = "Divine",
			Weight = 30,
			QualityTier = 3,
			IncomeMultiplierBps = 18000,
			LuckMultiplierBps = 15000,
		},
	},
}

return table.freeze(TraitConfig)
