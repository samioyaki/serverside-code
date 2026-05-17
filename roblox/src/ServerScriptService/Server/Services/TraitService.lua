local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local TraitConfig = require(Shared.Config.TraitConfig)

local TraitService = {}
TraitService.__index = TraitService

local DEFAULT_SLOT = 1

local function fail(code)
	error(code, 0)
end

function TraitService.new(registry)
	return setmetatable({
		Registry = registry,
	}, TraitService)
end

local function getMaxQualityTier()
	local maxTier = 0

	for _, definition in pairs(TraitConfig.Definitions) do
		maxTier = math.max(maxTier, definition.QualityTier or 0)
	end

	return maxTier
end

local function getTraitQualityTier(traitId)
	local definition = TraitConfig.Definitions[traitId]
	if not definition then
		fail("UnknownTrait")
	end

	return definition.QualityTier or 0
end

local function normalizeSlot(slotIndex)
	slotIndex = slotIndex or DEFAULT_SLOT
	if type(slotIndex) ~= "number" or slotIndex % 1 ~= 0 or slotIndex < 1 or slotIndex > 3 then
		fail("TraitSlotInvalid")
	end

	return slotIndex
end

function TraitService:_getTraitSlot(profile, baddieId, slotIndex)
	local baddie = self.Registry:Get("InventoryService"):AssertBaddie(profile, baddieId)
	slotIndex = normalizeSlot(slotIndex)

	baddie.TraitIds = baddie.TraitIds or {}
	baddie.TraitLocks = baddie.TraitLocks or {}
	baddie.TraitIds[slotIndex] = baddie.TraitIds[slotIndex] or "None"
	baddie.TraitLocks[slotIndex] = baddie.TraitLocks[slotIndex] == true

	return baddie, slotIndex
end

function TraitService:_consumeCredit(profile, productKey)
	local currentCredits = profile.Premium.Products[productKey] or 0
	if currentCredits <= 0 then
		fail("NotEnoughTraitCredits")
	end

	profile.Premium.Products[productKey] = currentCredits - 1
end

function TraitService:_setTrait(profile, baddieId, slotIndex, traitId)
	local baddie, normalizedSlot = self:_getTraitSlot(profile, baddieId, slotIndex)
	if baddie.TraitLocks[normalizedSlot] then
		fail("TraitSlotLocked")
	end

	baddie.TraitIds[normalizedSlot] = traitId
	baddie.UpdatedAt = os.time()

	return baddie, traitId, normalizedSlot
end

function TraitService:RerollTrait(player, baddieId, slotIndex)
	local rolledTraitId = nil

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "RerollTrait", {
		"Inventory",
		"Premium",
	}, function(_, profile)
		local baddie, normalizedSlot = self:_getTraitSlot(profile, baddieId, slotIndex)
		if baddie.TraitLocks[normalizedSlot] then
			fail("TraitSlotLocked")
		end

		self:_consumeCredit(profile, "TraitReroll")
		rolledTraitId = self.Registry:Get("RollService"):RollFreshTrait(profile)
		baddie.TraitIds[normalizedSlot] = rolledTraitId
		baddie.UpdatedAt = os.time()
	end)

	return rolledTraitId
end

function TraitService:TargetedTraitRoll(player, baddieId, slotIndex)
	local rolledTraitId = nil

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "TargetedTraitRoll", {
		"Inventory",
		"Premium",
	}, function(_, profile)
		local baddie, normalizedSlot = self:_getTraitSlot(profile, baddieId, slotIndex)
		if baddie.TraitLocks[normalizedSlot] then
			fail("TraitSlotLocked")
		end

		self:_consumeCredit(profile, "TargetedTraitRoll")
		rolledTraitId = self.Registry:Get("RollService"):RollFilteredTrait(profile, 2)
		baddie.TraitIds[normalizedSlot] = rolledTraitId
		baddie.UpdatedAt = os.time()
	end)

	return rolledTraitId
end

function TraitService:GodTierRoll(player, baddieId, slotIndex)
	local rolledTraitId = nil

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "GodTierRoll", {
		"Inventory",
		"Premium",
	}, function(_, profile)
		local baddie, normalizedSlot = self:_getTraitSlot(profile, baddieId, slotIndex)
		if baddie.TraitLocks[normalizedSlot] then
			fail("TraitSlotLocked")
		end

		self:_consumeCredit(profile, "GodTierTraitRoll")
		rolledTraitId = self.Registry:Get("RollService"):RollFilteredTrait(profile, getMaxQualityTier())
		baddie.TraitIds[normalizedSlot] = rolledTraitId
		baddie.UpdatedAt = os.time()
	end)

	return rolledTraitId
end

function TraitService:LockTraitSlot(player, baddieId, slotIndex)
	local normalizedSlot = nil

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "LockTraitSlot", {
		"Inventory",
		"Premium",
	}, function(_, profile)
		local baddie
		baddie, normalizedSlot = self:_getTraitSlot(profile, baddieId, slotIndex)
		if baddie.TraitLocks[normalizedSlot] then
			fail("TraitSlotLocked")
		end

		self:_consumeCredit(profile, "LockTraitSlot")
		baddie.TraitLocks[normalizedSlot] = true
		baddie.UpdatedAt = os.time()
	end)

	return normalizedSlot
end

function TraitService:UpgradeTraitTier(player, baddieId, slotIndex)
	local rolledTraitId = nil

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "UpgradeTraitTier", {
		"Inventory",
		"Premium",
	}, function(_, profile)
		local baddie, normalizedSlot = self:_getTraitSlot(profile, baddieId, slotIndex)
		if baddie.TraitLocks[normalizedSlot] then
			fail("TraitSlotLocked")
		end

		local currentTier = getTraitQualityTier(baddie.TraitIds[normalizedSlot])
		local maxTier = getMaxQualityTier()
		if currentTier >= maxTier then
			fail("TraitAlreadyMaxTier")
		end

		self:_consumeCredit(profile, "TraitUpgradePack")
		rolledTraitId = self.Registry:Get("RollService"):RollFilteredTrait(profile, currentTier + 1, currentTier + 1)
		self:_setTrait(profile, baddieId, normalizedSlot, rolledTraitId)
	end)

	return rolledTraitId
end

return TraitService
