local TableUtil = {}

function TableUtil.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, innerValue in pairs(value) do
		copy[key] = TableUtil.DeepCopy(innerValue)
	end

	return copy
end

function TableUtil.AssignMissing(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = TableUtil.DeepCopy(value)
		elseif type(target[key]) == "table" and type(value) == "table" then
			TableUtil.AssignMissing(target[key], value)
		end
	end
end

function TableUtil.GetPath(root, path)
	local cursor = root
	for _, key in ipairs(path) do
		if cursor == nil then
			return nil
		end
		cursor = cursor[key]
	end

	return cursor
end

function TableUtil.SetPath(root, path, value)
	local cursor = root
	for index = 1, #path - 1 do
		local key = path[index]
		cursor[key] = cursor[key] or {}
		cursor = cursor[key]
	end

	cursor[path[#path]] = value
end

function TableUtil.ShallowMerge(into, other)
	for key, value in pairs(other) do
		into[key] = value
	end

	return into
end

return TableUtil
