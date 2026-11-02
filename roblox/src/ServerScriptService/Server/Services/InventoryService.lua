local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BaddieState = require(Shared.Enums.BaddieState)
local IdUtil = require(Shared.Util.IdUtil)

local InventoryService = {}
InventoryService.__index = InventoryService

local function fail(code)
	error(code, 0)
end

function InventoryService.new(registry)
	return setmetatable({
		Registry = registry,
	}, InventoryService)
end

function InventoryService:AssertBaddie(profile, baddieId)
	local baddie = profile.Inventory.Baddies[baddieId]
	if not baddie then
		fail("UnknownBaddie")
	end

	return baddie
end

function InventoryService:AddBaddie(profile, templateId, rarityId, traitId, source, now)
	local baddieId = IdUtil.GenerateGuid()
	local record = {
		Id = baddieId,
		TemplateId = templateId,
		RarityId = rarityId,
		Level = 1,
		TraitIds = { traitId or "None" },
		TraitLocks = { false },
		Affection = 0,
		LastDatedAt = 0,
		State = BaddieState.Inventory,
		Source = source,
		CreatedAt = now,
		UpdatedAt = now,
	}

	profile.Inventory.Baddies[baddieId] = record
	table.insert(profile.Inventory.Order, 1, baddieId)

	return record
end

function InventoryService:RemoveBaddie(profile, baddieId)
	self:AssertBaddie(profile, baddieId)
	profile.Inventory.Baddies[baddieId] = nil
	profile.Placements[baddieId] = nil

	for index, currentId in ipairs(profile.Inventory.Order) do
		if currentId == baddieId then
			table.remove(profile.Inventory.Order, index)
			break
		end
	end
end

function InventoryService:SetState(profile, baddieId, state)
	local baddie = self:AssertBaddie(profile, baddieId)
	baddie.State = state
	baddie.UpdatedAt = os.time()
end

function InventoryService:ResetAllToInventory(profile)
	for baddieId, baddie in pairs(profile.Inventory.Baddies) do
		baddie.State = BaddieState.Inventory
		profile.Placements[baddieId] = nil
	end
end

function InventoryService:GetTemplateDuplicateIds(profile, templateId, minimumCount, allowPlaced)
	local duplicateIds = {}

	for _, baddieId in ipairs(profile.Inventory.Order) do
		local baddie = profile.Inventory.Baddies[baddieId]
		if baddie and baddie.TemplateId == templateId then
			local isPlaced = profile.Placements[baddieId] ~= nil
			if allowPlaced or not isPlaced then
				table.insert(duplicateIds, baddieId)
			end
		end
	end

	if minimumCount and #duplicateIds < minimumCount then
		return nil
	end

	return duplicateIds
end

return InventoryService
