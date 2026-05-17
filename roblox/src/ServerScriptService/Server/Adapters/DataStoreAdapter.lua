local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local TableUtil = require(game:GetService("ReplicatedStorage").Shared.Util.TableUtil)

local memoryStores = {}
local requestConfigByMethod = {
	GetAsync = {
		RequestType = Enum.DataStoreRequestType.GetAsync,
		BudgetWaitSeconds = 10,
		MaxRetries = 5,
		InitialBackoffSeconds = 0.5,
	},
	SetAsync = {
		RequestType = Enum.DataStoreRequestType.UpdateAsync,
		BudgetWaitSeconds = 15,
		MaxRetries = 6,
		InitialBackoffSeconds = 1,
	},
	UpdateAsync = {
		RequestType = Enum.DataStoreRequestType.UpdateAsync,
		BudgetWaitSeconds = 15,
		MaxRetries = 6,
		InitialBackoffSeconds = 1,
	},
}

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

function DataStoreAdapter.new(name)
	local self = setmetatable({
		Name = name,
		Memory = memoryStores[name] or {},
		Store = nil,
	}, DataStoreAdapter)

	memoryStores[name] = self.Memory

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)

	if ok then
		self.Store = store
	end

	return self
end

function DataStoreAdapter:_waitForBudget(requestType, timeoutSeconds)
	if not self.Store then
		return true
	end

	local deadlineAt = os.clock() + timeoutSeconds

	while os.clock() < deadlineAt do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)

		if ok and budget > 0 then
			return true
		end

		task.wait(0.25)
	end

	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)

	return ok and budget > 0
end

function DataStoreAdapter:_runWithRetry(methodName, operation)
	local config = requestConfigByMethod[methodName]
	local lastError = nil

	for attempt = 1, config.MaxRetries do
		if self.Store then
			self:_waitForBudget(config.RequestType, config.BudgetWaitSeconds)
		end

		local ok, result = pcall(operation)
		if ok then
			return true, result
		end

		lastError = result

		if attempt < config.MaxRetries then
			local backoff = config.InitialBackoffSeconds * (2 ^ (attempt - 1))
			task.wait(backoff + math.random() * 0.5)
		end
	end

	return false, lastError
end

function DataStoreAdapter:GetBudget(requestType)
	if not self.Store then
		return math.huge
	end

	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)

	if ok then
		return budget
	end

	return 0
end

function DataStoreAdapter:GetWriteBudget()
	return self:GetBudget(Enum.DataStoreRequestType.UpdateAsync)
end

function DataStoreAdapter:GetReadBudget()
	return self:GetBudget(Enum.DataStoreRequestType.GetAsync)
end

function DataStoreAdapter:GetAsync(key)
	local normalizedKey = tostring(key)

	if self.Store then
		local ok, result = self:_runWithRetry("GetAsync", function()
			return self.Store:GetAsync(normalizedKey)
		end)

		if ok then
			self.Memory[normalizedKey] = TableUtil.DeepCopy(result)
			return result
		end

		if not RunService:IsStudio() then
			error(result, 0)
		end
	end

	return TableUtil.DeepCopy(self.Memory[normalizedKey])
end

function DataStoreAdapter:UpdateAsync(key, transform)
	local normalizedKey = tostring(key)

	if self.Store then
		local storedValue = nil
		local ok, err = self:_runWithRetry("UpdateAsync", function()
			return self.Store:UpdateAsync(normalizedKey, function(currentValue)
				local nextValue = transform(TableUtil.DeepCopy(currentValue))
				storedValue = TableUtil.DeepCopy(nextValue)
				return nextValue
			end)
		end)

		if ok then
			self.Memory[normalizedKey] = TableUtil.DeepCopy(storedValue)
			return TableUtil.DeepCopy(storedValue)
		end

		if not RunService:IsStudio() then
			error(err, 0)
		end
	end

	local nextValue = transform(TableUtil.DeepCopy(self.Memory[normalizedKey]))
	self.Memory[normalizedKey] = TableUtil.DeepCopy(nextValue)
	return TableUtil.DeepCopy(nextValue)
end

function DataStoreAdapter:SetAsync(key, value)
	local clonedValue = TableUtil.DeepCopy(value)

	self:UpdateAsync(key, function()
		return TableUtil.DeepCopy(clonedValue)
	end)
end

return DataStoreAdapter
