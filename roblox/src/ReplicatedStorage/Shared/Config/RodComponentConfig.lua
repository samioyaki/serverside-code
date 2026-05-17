local RodComponentConfig = {
	Components = { "Line", "Hook", "Reel" },
	MaxTier = 5,

	-- Cost multiplier applied per rod price tier (so upgrading Eclipse components costs more)
	RodCostTiers = {
		StarterRod = 1,
		BreezeRod = 1,
		SurgeRod = 1.5,
		CoralRod = 2,
		FluxRod = 3,
		VoidlineRod = 4,
		LuminRod = 5,
		AurexRod = 7,
		DepthcoreRod = 10,
		EclipseRod = 15,
		PoseidonRod = 12,
		AbyssRod = 18,
		GodRod = 25,
	},

	-- Line: improves sweet spot window size
	Line = {
		{ Name = "Fiber Line", WindowBonusBps = 0, Cost = 0 },
		{ Name = "Nylon Line", WindowBonusBps = 300, Cost = 2000 },
		{ Name = "Braided Line", WindowBonusBps = 700, Cost = 15000 },
		{ Name = "Carbon Line", WindowBonusBps = 1300, Cost = 80000 },
		{ Name = "Void Filament", WindowBonusBps = 2200, Cost = 500000 },
	},

	-- Hook: improves luck and trait quality
	Hook = {
		{ Name = "Rusty Hook", LuckBonusBps = 0, TraitLuckBonusBps = 0, Cost = 0 },
		{ Name = "Iron Hook", LuckBonusBps = 500, TraitLuckBonusBps = 300, Cost = 3000 },
		{ Name = "Steel Hook", LuckBonusBps = 1200, TraitLuckBonusBps = 800, Cost = 20000 },
		{ Name = "Crystal Hook", LuckBonusBps = 2200, TraitLuckBonusBps = 1500, Cost = 120000 },
		{ Name = "Abyssal Hook", LuckBonusBps = 3800, TraitLuckBonusBps = 2500, Cost = 800000 },
	},

	-- Reel: improves cast speed and chain income bonus
	Reel = {
		{ Name = "Wooden Reel", CastSpeedBonusBps = 0, ChainIncomeBonusBps = 0, Cost = 0 },
		{ Name = "Basic Reel", CastSpeedBonusBps = 500, ChainIncomeBonusBps = 500, Cost = 2500 },
		{ Name = "Precision Reel", CastSpeedBonusBps = 1200, ChainIncomeBonusBps = 1200, Cost = 18000 },
		{ Name = "Expert Reel", CastSpeedBonusBps = 2000, ChainIncomeBonusBps = 2200, Cost = 100000 },
		{ Name = "Godlike Reel", CastSpeedBonusBps = 3500, ChainIncomeBonusBps = 3500, Cost = 600000 },
	},
}

return table.freeze(RodComponentConfig)
