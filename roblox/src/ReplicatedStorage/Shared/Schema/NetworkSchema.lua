local function setFromArray(values)
	local mapped = {}

	for _, value in ipairs(values) do
		mapped[value] = true
	end

	return table.freeze(mapped)
end

local NetworkSchema = {
	RateLimits = {
		Bootstrap = { MaxCalls = 4, WindowSeconds = 6 },
		FishingRequest = { MaxCalls = 12, WindowSeconds = 3 },
		PlacementRequest = { MaxCalls = 20, WindowSeconds = 3 },
		ClaimRequest = { MaxCalls = 6, WindowSeconds = 3 },
		UpgradeRequest = { MaxCalls = 8, WindowSeconds = 3 },
		RebirthRequest = { MaxCalls = 3, WindowSeconds = 5 },
		ShopRequest = { MaxCalls = 8, WindowSeconds = 3 },
		FusionRequest = { MaxCalls = 8, WindowSeconds = 3 },
		CrateRequest = { MaxCalls = 8, WindowSeconds = 3 },
		TraitRequest = { MaxCalls = 6, WindowSeconds = 3 },
		RodComponentRequest = { MaxCalls = 10, WindowSeconds = 3 },
		DatingRequest = { MaxCalls = 4, WindowSeconds = 3 },
	},
	FishingRequest = {
		AllowedActions = setFromArray({ "BeginCast", "ResolveCatch", "ReleaseCast", "CancelCast" }),
		MaxSessionIdLength = 64,
		ValidationLeewaySeconds = 0.35,
	},
	PlacementRequest = {
		AllowedActions = setFromArray({
			"Place",
			"Move",
			"Remove",
			"HoldBaddie",
			"ClearHeldBaddie",
			"PlaceHeld",
			"PickupCell",
			"VisitPlot",
			"VisitDock",
		}),
		AllowedRotations = setFromArray({ 0, 90, 180, 270 }),
		MinGrid = 1,
		MaxGrid = 64,
		MaxBaddieIdLength = 64,
	},
	ClaimRequest = {
		AllowedActions = setFromArray({ "ClaimIncome" }),
	},
	UpgradeRequest = {
		AllowedActions = setFromArray({ "UpgradeBaddie", "UpgradeTen", "MaxBaddie" }),
		MaxBaddieIdLength = 64,
	},
	RebirthRequest = {
		AllowedActions = setFromArray({ "Execute" }),
	},
	ShopRequest = {
		AllowedActions = setFromArray({ "Purchase", "EquipRod", "PromptProduct" }),
		MaxEntryIdLength = 64,
		MaxQuantity = 99,
	},
	FusionRequest = {
		AllowedActions = setFromArray({ "FuseTemplate", "ConvertSecret" }),
		MaxTemplateIdLength = 64,
		MaxBaddieIdLength = 64,
	},
	CrateRequest = {
		AllowedActions = setFromArray({ "OpenOwnedCrate" }),
		MaxCrateIdLength = 64,
	},
	TraitRequest = {
		AllowedActions = setFromArray({
			"RerollTrait",
			"TargetedTraitRoll",
			"GodTierRoll",
			"LockTraitSlot",
			"UpgradeTraitTier",
			"ApplyUpgradePack",
		}),
		MaxBaddieIdLength = 64,
	},
	RodComponentRequest = {
		AllowedActions = setFromArray({ "UpgradeComponent", "InstantMaxComponent", "InstantMaxAllComponents" }),
		MaxRodIdLength = 64,
		AllowedComponents = setFromArray({ "Line", "Hook", "Reel" }),
	},
	DatingRequest = {
		AllowedActions = setFromArray({ "DateBaddie" }),
		MaxBaddieIdLength = 64,
	},
}

return table.freeze(NetworkSchema)
