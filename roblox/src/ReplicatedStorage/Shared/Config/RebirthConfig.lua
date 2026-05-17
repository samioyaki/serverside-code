local RebirthConfig = {
	BaseCost = 10000000,
	CostGrowth = 3,
	PassiveIncomePerRebirthBps = 4000,
	PassiveLuckPerRebirthBps = 1250,
	RewardShardsPerRebirth = 5,
}

return table.freeze(RebirthConfig)
