local RodConfig = require(script.Parent.Parent.Config.RodConfig)

local RodUtil = {}

function RodUtil.GetCaughtCount(state, rarityId)
	local stats = state and state.Stats
	local caughtByRarity = stats and stats.CaughtByRarity
	return caughtByRarity and (caughtByRarity[rarityId] or 0) or 0
end

function RodUtil.MeetsUnlockRequirements(state, rodId)
	local definition = RodConfig.Definitions[rodId]
	if not definition then
		return false
	end

	local requirements = definition.UnlockRequirements
	if not requirements then
		return true
	end

	local rebirthCount = state and state.Progression and state.Progression.RebirthCount or 0
	if rebirthCount < (requirements.RebirthCount or 0) then
		return false
	end

	for _, requirement in ipairs(requirements.CatchRequirements or {}) do
		if RodUtil.GetCaughtCount(state, requirement.RarityId) < requirement.Count then
			return false
		end
	end

	local anyCatchRequirements = requirements.AnyCatchRequirements or {}
	if #anyCatchRequirements > 0 then
		for _, requirement in ipairs(anyCatchRequirements) do
			if RodUtil.GetCaughtCount(state, requirement.RarityId) >= requirement.Count then
				return true
			end
		end

		return false
	end

	return true
end

function RodUtil.BuildRequirementText(state, rodId)
	local definition = RodConfig.Definitions[rodId]
	if not definition then
		return ""
	end

	local requirements = definition.UnlockRequirements
	if not requirements then
		return definition.UnlockDescription or "Unlock: Free"
	end

	local segments = {}

	if requirements.RebirthCount and requirements.RebirthCount > 0 then
		local rebirthCount = state and state.Progression and state.Progression.RebirthCount or 0
		table.insert(
			segments,
			string.format("Rebirth %d/%d", math.min(rebirthCount, requirements.RebirthCount), requirements.RebirthCount)
		)
	end

	for _, requirement in ipairs(requirements.CatchRequirements or {}) do
		local current = RodUtil.GetCaughtCount(state, requirement.RarityId)
		table.insert(
			segments,
			string.format(
				"Catch %s %d/%d",
				requirement.RarityId,
				math.min(current, requirement.Count),
				requirement.Count
			)
		)
	end

	local anyCatchRequirements = requirements.AnyCatchRequirements or {}
	if #anyCatchRequirements > 0 then
		local anySegments = {}

		for _, requirement in ipairs(anyCatchRequirements) do
			local current = RodUtil.GetCaughtCount(state, requirement.RarityId)
			table.insert(
				anySegments,
				string.format(
					"Catch %s %d/%d",
					requirement.RarityId,
					math.min(current, requirement.Count),
					requirement.Count
				)
			)
		end

		table.insert(segments, "(" .. table.concat(anySegments, " or ") .. ")")
	end

	return table.concat(segments, " | ")
end

return table.freeze(RodUtil)
