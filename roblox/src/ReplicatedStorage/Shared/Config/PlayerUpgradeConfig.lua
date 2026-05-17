local PlayerUpgradeConfig = {
	Order = {
		"CastSpeed",
		"LuckTraining",
		"TimingWindow",
		"ChainFocus",
	},
	Definitions = {
		CastSpeed = {
			Id = "CastSpeed",
			DisplayName = "Cast Speed",
			Description = "+2% cast speed per level",
			MaxLevel = 10,
			BaseCost = 1000,
			CostGrowth = 2.2,
			CastSpeedBonusBps = 200,
		},
		LuckTraining = {
			Id = "LuckTraining",
			DisplayName = "Luck Training",
			Description = "+1.5% rarity luck per level",
			MaxLevel = 10,
			BaseCost = 1500,
			CostGrowth = 2.25,
			LuckBonusBps = 150,
		},
		TimingWindow = {
			Id = "TimingWindow",
			DisplayName = "Timing Window",
			Description = "+2% sweet-spot window per level",
			MaxLevel = 8,
			BaseCost = 2000,
			CostGrowth = 2.2,
			WindowBonusBps = 200,
		},
		ChainFocus = {
			Id = "ChainFocus",
			DisplayName = "Chain Focus",
			Description = "+25 bps chain gain and +75 bps chain cap per level",
			MaxLevel = 8,
			BaseCost = 2500,
			CostGrowth = 2.3,
			ChainGainBps = 25,
			ChainCapBps = 75,
		},
	},
}

return table.freeze(PlayerUpgradeConfig)
