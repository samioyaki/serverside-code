local CollectionService = {}
CollectionService.__index = CollectionService

local TEMPLATE_THRESHOLDS = {
	[5] = 2500,
	[10] = 7500,
	[15] = 15000,
	[20] = 30000,
}

local RARITY_REWARDS = {
	Common = 100,
	Uncommon = 500,
	Rare = 1500,
	Epic = 5000,
	Legendary = 12000,
	Mythic = 30000,
	Secret = 100000,
}

function CollectionService.new(registry)
	return setmetatable({
		Registry = registry,
	}, CollectionService)
end

function CollectionService:RegisterBaddie(profile, baddieRecord)
	local changed = false
	local rarityId = baddieRecord.RarityId
	local templateId = baddieRecord.TemplateId

	if not profile.Dex.Rarities[rarityId] then
		profile.Dex.Rarities[rarityId] = true
		profile.Wallet.Coins += RARITY_REWARDS[rarityId] or 0
		changed = true
	end

	if not profile.Dex.Templates[templateId] then
		profile.Dex.Templates[templateId] = true
		changed = true

		local totalTemplates = 0
		for _ in pairs(profile.Dex.Templates) do
			totalTemplates += 1
		end

		if TEMPLATE_THRESHOLDS[totalTemplates] and not profile.Dex.Milestones[tostring(totalTemplates)] then
			profile.Dex.Milestones[tostring(totalTemplates)] = true
			profile.Wallet.Coins += TEMPLATE_THRESHOLDS[totalTemplates]
		end
	end

	return changed
end

return CollectionService
