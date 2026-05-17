local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")

local localLocks = {}
local MAX_RETRIES = 5
local INITIAL_BACKOFF_SECONDS = 0.5

local SessionLockAdapter = {}
SessionLockAdapter.__index = SessionLockAdapter

function SessionLockAdapter.new(name, ttlSeconds)
	local self = setmetatable({
		Name = name,
		TTLSeconds = ttlSeconds,
		Map = nil,
	}, SessionLockAdapter)

	local ok, map = pcall(function()
		return MemoryStoreService:GetHashMap(name)
	end)

	if ok then
		self.Map = map
	end

	return self
end

function SessionLockAdapter:_runWithRetry(operation)
	local lastError = nil

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end

		lastError = result

		if attempt < MAX_RETRIES then
			local backoff = INITIAL_BACKOFF_SECONDS * (2 ^ (attempt - 1))
			task.wait(backoff + math.random() * 0.5)
		end
	end

	return false, lastError
end

function SessionLockAdapter:_buildPayload()
	return {
		JobId = game.JobId,
		ExpiresAt = os.time() + self.TTLSeconds,
	}
end

function SessionLockAdapter:AcquireLock(userId)
	local key = tostring(userId)
	local now = os.time()

	if self.Map then
		local ok, result = self:_runWithRetry(function()
			return self.Map:UpdateAsync(key, function(current)
				if current and current.ExpiresAt and current.ExpiresAt > now and current.JobId ~= game.JobId then
					return current
				end

				return self:_buildPayload()
			end, self.TTLSeconds + 5)
		end)

		if ok then
			return result ~= nil and result.JobId == game.JobId
		end

		if not RunService:IsStudio() then
			error(result, 0)
		end
	end

	local current = localLocks[key]
	if current and current.ExpiresAt > now and current.JobId ~= game.JobId then
		return false
	end

	localLocks[key] = self:_buildPayload()
	return true
end

function SessionLockAdapter:RenewLock(userId)
	local key = tostring(userId)
	local payload = self:_buildPayload()

	if self.Map then
		local ok, result = self:_runWithRetry(function()
			return self.Map:UpdateAsync(key, function(current)
				if current and current.JobId == game.JobId then
					return payload
				end

				return current
			end, self.TTLSeconds + 5)
		end)

		if ok then
			return result ~= nil and result.JobId == game.JobId
		end

		if not RunService:IsStudio() then
			error(result, 0)
		end
	end

	if localLocks[key] and localLocks[key].JobId == game.JobId then
		localLocks[key] = payload
		return true
	end

	return false
end

function SessionLockAdapter:ReleaseLock(userId)
	local key = tostring(userId)

	if self.Map then
		local ok, result = self:_runWithRetry(function()
			self.Map:RemoveAsync(key)
		end)

		if not ok and not RunService:IsStudio() then
			error(result, 0)
		end
	end

	localLocks[key] = nil
end

return SessionLockAdapter
