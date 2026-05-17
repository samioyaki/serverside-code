local WeightedRandom = {}

function WeightedRandom.Roll(weightMap, randomObject)
	local totalWeight = 0
	for _, weight in pairs(weightMap) do
		totalWeight += weight
	end

	if totalWeight <= 0 then
		return nil
	end

	local randomSource = randomObject or Random.new()
	local roll = randomSource:NextNumber(0, totalWeight)
	local running = 0

	for key, weight in pairs(weightMap) do
		running += weight
		if roll <= running then
			return key
		end
	end

	return next(weightMap)
end

return WeightedRandom
