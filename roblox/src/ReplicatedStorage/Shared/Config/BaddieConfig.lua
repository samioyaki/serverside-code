local function createBaddie(templateId, displayName, rarityId, color)
	return {
		Id = templateId,
		DisplayName = displayName,
		RarityId = rarityId,
		DisplayColor = color,
		Footprint = {
			Width = 1,
			Height = 1,
		},
	}
end

local definitions = {
	Foam = createBaddie("Foam", "Foam", "Common", Color3.fromRGB(191, 238, 255)),
	Ripple = createBaddie("Ripple", "Ripple", "Common", Color3.fromRGB(130, 195, 255)),
	Bay = createBaddie("Bay", "Bay", "Common", Color3.fromRGB(168, 214, 212)),
	Shoal = createBaddie("Shoal", "Shoal", "Common", Color3.fromRGB(184, 188, 195)),
	Jetty = createBaddie("Jetty", "Jetty", "Common", Color3.fromRGB(148, 163, 184)),
	Harbor = createBaddie("Harbor", "Harbor", "Uncommon", Color3.fromRGB(67, 210, 162)),
	Drift = createBaddie("Drift", "Drift", "Uncommon", Color3.fromRGB(87, 201, 113)),
	Delta = createBaddie("Delta", "Delta", "Uncommon", Color3.fromRGB(48, 196, 168)),
	Kelp = createBaddie("Kelp", "Kelp", "Uncommon", Color3.fromRGB(90, 181, 93)),
	Lagoon = createBaddie("Lagoon", "Lagoon", "Rare", Color3.fromRGB(44, 139, 255)),
	Coral = createBaddie("Coral", "Coral", "Rare", Color3.fromRGB(95, 120, 255)),
	Current = createBaddie("Current", "Current", "Rare", Color3.fromRGB(55, 171, 255)),
	Anchor = createBaddie("Anchor", "Anchor", "Rare", Color3.fromRGB(63, 84, 191)),
	Reef = createBaddie("Reef", "Reef", "Epic", Color3.fromRGB(175, 74, 255)),
	Splash = createBaddie("Splash", "Splash", "Epic", Color3.fromRGB(221, 84, 255)),
	Pearl = createBaddie("Pearl", "Pearl", "Epic", Color3.fromRGB(255, 127, 245)),
	Brine = createBaddie("Brine", "Brine", "Epic", Color3.fromRGB(197, 87, 255)),
	Marina = createBaddie("Marina", "Marina", "Legendary", Color3.fromRGB(255, 187, 46)),
	Wave = createBaddie("Wave", "Wave", "Legendary", Color3.fromRGB(255, 142, 44)),
	Nautie = createBaddie("Nautie", "Nautie", "Legendary", Color3.fromRGB(255, 215, 55)),
	Trench = createBaddie("Trench", "Trench", "Mythic", Color3.fromRGB(255, 57, 119)),
	Abyss = createBaddie("Abyss", "Abyss", "Mythic", Color3.fromRGB(223, 55, 116)),
	Maris = createBaddie("Maris", "Maris", "Mythic", Color3.fromRGB(255, 89, 159)),
	Siren = createBaddie("Siren", "Siren", "Secret", Color3.fromRGB(255, 69, 69)),
	Tide = createBaddie("Tide", "Tide", "Secret", Color3.fromRGB(255, 27, 27)),
}

-- Preserve old inventory records created before the supplied Nautie model was imported.
definitions.Nautic = createBaddie("Nautic", "Nautie", "Legendary", Color3.fromRGB(255, 215, 55))
definitions.Nautic.LegacyAlias = true

local byRarity = {}

for templateId, definition in pairs(definitions) do
	if not definition.LegacyAlias then
		byRarity[definition.RarityId] = byRarity[definition.RarityId] or {}
		table.insert(byRarity[definition.RarityId], templateId)
	end
end

local BaddieConfig = {
	Definitions = definitions,
	ByRarity = byRarity,
}

return table.freeze(BaddieConfig)
