local FishingConfig = {
	ResolveGraceSeconds = 3,
	CooldownSeconds = 0.3,
	MinCastDistance = 8,
	DefaultCastDistance = 55,
	MaxCastDistance = 90,
	MaxHoldRatio = 1.25,
	WaterBoundsMargin = 2,
	BobberSize = 1.25,
	LineThickness = 0.08,
	SweetSpotMin = 0.2,
	SweetSpotMax = 0.7,
	SweetSpotWindow = 0.08,
	MaxSkillBonusBps = 11500,
	MissChainReset = true,
	RarityWeights = {
		Common = 685000,
		Uncommon = 236000,
		Rare = 64000,
		Epic = 13000,
		Legendary = 1700,
		Mythic = 299,
		Secret = 1,
	},
}

return table.freeze(FishingConfig)
