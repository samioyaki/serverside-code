local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local DataStoreAdapter = require(script.Parent.Parent.Adapters.DataStoreAdapter)
local SessionLockAdapter = require(script.Parent.Parent.Adapters.SessionLockAdapter)
local ProfileSchema = require(Shared.Schema.ProfileSchema)

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

local RECEIPT_HISTORY_LIMIT = 128

local function fail(code)
	error(code, 0)
end

local function hasPath(paths, target)
	for _, path in ipairs(paths or {}) do
		if path == target then
			return true
		end
	end

	return false
end

local function hasAnyPath(paths, targets)
	for _, target in ipairs(targets) do
		if hasPath(paths, target) then
			return true
		end
	end

	return false
end

function PlayerDataService.new(registry)
	return setmetatable({
		Registry = registry,
		SessionsByPlayer = {},
		OpeningByPlayer = {},
		Random = Random.new(),
		AutoSaveMinIntervalSeconds = 120,
		AutoSaveMaxIntervalSeconds = 180,
		SaveScanIntervalSeconds = 2,
		MaxAutoSavesPerPass = 96,
		WriteBudgetReserve = 5,
		LockRenewMinIntervalSeconds = 90,
		LockRenewMaxIntervalSeconds = 120,
		LockRenewScanIntervalSeconds = 2,
		MaxLockRenewsPerPass = 160,
	}, PlayerDataService)
end

function PlayerDataService:Init()
	self.ProfileStore = DataStoreAdapter.new("FishABaddie_PlayerProfile_v3")
	self.SessionLocks = SessionLockAdapter.new("FishABaddie_PlayerSessionLocks_v3", 240)

	game:BindToClose(function()
		self:FlushAll()
	end)
end

function PlayerDataService:Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local ok, err = pcall(function()
				self:OpenSession(player)
			end)

			if not ok and player.Parent then
				warn(err)
				player:Kick("Data failed to load")
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:CloseSession(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			local ok, err = pcall(function()
				self:OpenSession(player)
			end)

			if not ok and player.Parent then
				warn(err)
				player:Kick("Data failed to load")
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(self.SaveScanIntervalSeconds)
			self:FlushDirty()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(self.LockRenewScanIntervalSeconds)
			self:RenewLocks()
		end
	end)
end

function PlayerDataService:_rollInterval(minSeconds, maxSeconds)
	if maxSeconds <= minSeconds then
		return minSeconds
	end

	return self.Random:NextNumber(minSeconds, maxSeconds)
end

function PlayerDataService:_scheduleNextAutoSave(session, delaySeconds)
	session.Runtime.NextAutoSaveAt = os.clock() + (delaySeconds or self:_rollInterval(self.AutoSaveMinIntervalSeconds, self.AutoSaveMaxIntervalSeconds))
end

function PlayerDataService:_scheduleNextLockRenew(session, delaySeconds)
	session.Runtime.NextLockRenewAt = os.clock() + (delaySeconds or self:_rollInterval(self.LockRenewMinIntervalSeconds, self.LockRenewMaxIntervalSeconds))
end

function PlayerDataService:_bringForwardAutoSave(session, maxDelaySeconds)
	local requestedAt = os.clock() + maxDelaySeconds
	if not session.Runtime.NextAutoSaveAt or session.Runtime.NextAutoSaveAt > requestedAt then
		session.Runtime.NextAutoSaveAt = requestedAt
	end
end

function PlayerDataService:_compactBoostBucket(bucket, now)
	local writeIndex = 1

	for _, boost in ipairs(bucket) do
		if type(boost) == "table"
			and type(boost.MultiplierBps) == "number"
			and type(boost.ExpiresAt) == "number"
			and boost.MultiplierBps >= 10000
			and boost.ExpiresAt > now
		then
			bucket[writeIndex] = boost
			writeIndex += 1
		end
	end

	for index = #bucket, writeIndex, -1 do
		bucket[index] = nil
	end
end

function PlayerDataService:_compactProfile(profile, now)
	profile.Meta.LastSavedAt = now
	profile.Meta.UpdatedAt = now
	profile.Quests = nil
	if profile.Premium and profile.Premium.OwnedPasses then
		profile.Premium.OwnedPasses.DoubleSecretConversion = nil
	end
	if profile.Premium and profile.Premium.Products then
		if profile.Premium.Products.ExtraSlots2 and profile.Premium.Products.ExtraSlots2 > 1 then
			profile.Premium.Products.ExtraSlots2 = 1
		end
		profile.Premium.Products.RebirthBundle = nil
	end
	if profile.Stats then
		profile.Stats.QuestsCompleted = nil
	end

	self:_compactBoostBucket(profile.Boosts.Income, now)
	self:_compactBoostBucket(profile.Boosts.Luck, now)

	local compactedOrder = {}
	for _, baddieId in ipairs(profile.Inventory.Order) do
		if profile.Inventory.Baddies[baddieId] then
			table.insert(compactedOrder, baddieId)
		end
	end
	profile.Inventory.Order = compactedOrder

	for baddieId in pairs(profile.Placements) do
		if not profile.Inventory.Baddies[baddieId] then
			profile.Placements[baddieId] = nil
		end
	end

	for crateId, amount in pairs(profile.Inventory.Crates) do
		if amount == nil or amount <= 0 then
			profile.Inventory.Crates[crateId] = nil
		end
	end

	local receiptOrder = profile.Receipts.Order or {}
	local compactedReceipts = {}
	local compactedOrder = {}

	for _, purchaseId in ipairs(receiptOrder) do
		if profile.Receipts.Processed[purchaseId] and not compactedReceipts[purchaseId] then
			compactedReceipts[purchaseId] = true
			table.insert(compactedOrder, purchaseId)
		end
	end

	if #compactedOrder == 0 then
		for purchaseId in pairs(profile.Receipts.Processed) do
			table.insert(compactedOrder, purchaseId)
		end
	end

	while #compactedOrder > RECEIPT_HISTORY_LIMIT do
		table.remove(compactedOrder, 1)
	end

	local boundedReceipts = {}
	for _, purchaseId in ipairs(compactedOrder) do
		boundedReceipts[purchaseId] = true
	end

	profile.Receipts.Order = compactedOrder
	profile.Receipts.Processed = boundedReceipts
end

function PlayerDataService:_collectDueSessions(predicate, sortAccessor)
	local dueSessions = {}

	for _, session in pairs(self.SessionsByPlayer) do
		if predicate(session) then
			table.insert(dueSessions, session)
		end
	end

	table.sort(dueSessions, function(a, b)
		return sortAccessor(a) < sortAccessor(b)
	end)

	return dueSessions
end

function PlayerDataService:OpenSession(player)
	if self.SessionsByPlayer[player] then
		return self.SessionsByPlayer[player]
	end

	if self.OpeningByPlayer[player] then
		return self:WaitForSession(player)
	end

	self.OpeningByPlayer[player] = true

	if not self.SessionLocks:AcquireLock(player.UserId) then
		self.OpeningByPlayer[player] = nil
		fail("ProfileAlreadyLoaded")
	end

	local now = os.time()
	local ok, rawProfile = pcall(function()
		return self.ProfileStore:GetAsync(player.UserId)
	end)

	if not ok then
		self.SessionLocks:ReleaseLock(player.UserId)
		self.OpeningByPlayer[player] = nil
		error(rawProfile, 0)
	end

	local profile = ProfileSchema.Migrate(rawProfile, now)
	profile.Meta.JoinCount += 1
	profile.Meta.UpdatedAt = now

	local session = {
		Player = player,
		UserId = player.UserId,
		Profile = profile,
		Revision = 0,
		Dirty = false,
		Runtime = {
			Plot = nil,
			Fishing = nil,
			LastIncomeAccruedAt = now,
			LastPersistedAt = now,
			SaveFailures = 0,
			SaveInProgress = false,
		},
	}
	self:_scheduleNextAutoSave(session)
	self:_scheduleNextLockRenew(session)

	self.SessionsByPlayer[player] = session
	if rawProfile == nil then
		session.Dirty = true
		self:_bringForwardAutoSave(session, 30)
	end

	local setupOk, setupErr = pcall(function()
		self.Registry:Get("MonetizationService"):RefreshOwnership(player, profile)
		session.Runtime.Plot = self.Registry:Get("PlotService"):AssignPlot(player)
		self.Registry:Get("PlacementService"):RebuildOccupancy(player)
		self.Registry:Get("LeaderstatsService"):Ensure(player)
		self.Registry:Get("RodToolService"):EnsureTool(player)
	end)

	self.OpeningByPlayer[player] = nil

	if not setupOk then
		self.SessionsByPlayer[player] = nil
		pcall(function()
			self.SessionLocks:ReleaseLock(player.UserId)
		end)
		error(setupErr, 0)
	end

	self.Registry:Get("ReplicaService"):PushFull(player)
	return session
end

function PlayerDataService:WaitForSession(player)
	local timeoutAt = os.clock() + 15

	while os.clock() < timeoutAt do
		local session = self.SessionsByPlayer[player]
		if session then
			return session
		end

		if not self.OpeningByPlayer[player] then
			break
		end

		task.wait()
	end

	if player.Parent then
		return self:OpenSession(player)
	end

	fail("SessionUnavailable")
end

function PlayerDataService:FindSession(player)
	return self.SessionsByPlayer[player]
end

function PlayerDataService:GetSession(player)
	return self.SessionsByPlayer[player] or self:WaitForSession(player)
end

function PlayerDataService:_publish(player, paths, reason)
	local session = self.SessionsByPlayer[player]
	if not session then
		return
	end

	session.Dirty = true
	session.Revision += 1
	session.Profile.Meta.UpdatedAt = os.time()
	self:_bringForwardAutoSave(session, self.AutoSaveMinIntervalSeconds)

	if hasAnyPath(paths, { "Premium", "Boosts", "Progression", "PlayerUpgrades", "RebirthUpgrades" }) then
		self.Registry:Get("MonetizationService"):RecomputeEffects(session.Profile)
	end

	if hasAnyPath(paths, { "Wallet", "Progression", "Leaderstats" }) then
		self.Registry:Get("LeaderstatsService"):Refresh(player)
	end

	if hasAnyPath(paths, { "Inventory", "Plot", "Progression" }) then
		self.Registry:Get("PlotService"):RefreshVisuals(player)
	end

	if hasAnyPath(paths, { "Progression", "Premium", "Unlocks", "RodComponents", "PlayerUpgrades", "RebirthUpgrades" }) then
		self.Registry:Get("RodToolService"):RefreshTool(player)
	end

	self.Registry:Get("ReplicaService"):Publish(player, paths, reason)
end

function PlayerDataService:MutateProfile(player, reason, publishedPaths, callback)
	local session = self:GetSession(player)
	local results = table.pack(callback(session, session.Profile))
	self:_publish(player, publishedPaths, reason)
	return table.unpack(results, 1, results.n)
end

function PlayerDataService:MutateProfileIfChanged(player, reason, publishedPaths, callback)
	local session = self:GetSession(player)
	local results = table.pack(callback(session, session.Profile))
	local changed = results[1] == true

	if changed then
		self:_publish(player, publishedPaths, reason)
	end

	return changed, table.unpack(results, 2, results.n)
end

function PlayerDataService:PublishRuntime(player, reason, publishedPaths)
	local session = self:FindSession(player)
	if not session then
		return
	end

	session.Revision += 1
	self.Registry:Get("ReplicaService"):Publish(player, publishedPaths, reason)
end

function PlayerDataService:_saveSession(session, saveContext)
	if session.Runtime.SaveInProgress then
		if saveContext == "Auto" then
			return
		end

		local timeoutAt = os.clock() + 10
		while session.Runtime.SaveInProgress and os.clock() < timeoutAt do
			task.wait()
		end

		if session.Runtime.SaveInProgress then
			return
		end
	end

	if session.Runtime.SaveInProgress then
		return
	end

	session.Runtime.SaveInProgress = true
	local now = os.time()
	local ok, err = pcall(function()
		self:_compactProfile(session.Profile, now)

		if saveContext == "Close" or saveContext == "Shutdown" then
			session.Profile.Meta.LastSessionEndedAt = now
		end

		self.ProfileStore:SetAsync(session.UserId, session.Profile)
	end)
	session.Runtime.SaveInProgress = false

	if not ok then
		error(err, 0)
	end

	session.Dirty = false
	session.Runtime.SaveFailures = 0
	session.Runtime.LastPersistedAt = now
	self:_scheduleNextAutoSave(session)
end

function PlayerDataService:CloseSession(player)
	local session = self.SessionsByPlayer[player]
	if not session then
		return
	end

	pcall(function()
		self.Registry:Get("IncomeService"):Accrue(player, "Leave")
	end)

	pcall(function()
		self.Registry:Get("FishingService"):CancelCast(player, true)
	end)

	pcall(function()
		self:_saveSession(session, "Close")
	end)

	pcall(function()
		self.SessionLocks:ReleaseLock(player.UserId)
	end)

	self.Registry:Get("PlotService"):ReleasePlot(player)
	self.SessionsByPlayer[player] = nil
	self.OpeningByPlayer[player] = nil
end

function PlayerDataService:FlushDirty()
	local writeBudget = self.ProfileStore:GetWriteBudget()
	local maxWrites = self.MaxAutoSavesPerPass

	if writeBudget ~= math.huge then
		maxWrites = math.max(0, math.min(maxWrites, writeBudget - self.WriteBudgetReserve))
	end

	if maxWrites <= 0 then
		return
	end

	local now = os.clock()
	local dueSessions = self:_collectDueSessions(function(session)
		return session.Dirty and not session.Runtime.SaveInProgress and now >= (session.Runtime.NextAutoSaveAt or 0)
	end, function(session)
		return session.Runtime.NextAutoSaveAt or math.huge
	end)

	for index = 1, math.min(#dueSessions, maxWrites) do
		local session = dueSessions[index]
		local ok, err = pcall(function()
			self:_saveSession(session, "Auto")
		end)

		if not ok then
			session.Runtime.SaveFailures = (session.Runtime.SaveFailures or 0) + 1
			self:_scheduleNextAutoSave(session, math.min(60, 5 * (2 ^ math.min(session.Runtime.SaveFailures, 3))))
			warn(err)
		end
	end
end

function PlayerDataService:FlushAll()
	for _, session in pairs(self.SessionsByPlayer) do
		local ok, err = pcall(function()
			self:_saveSession(session, "Shutdown")
		end)

		if not ok then
			warn(err)
		end
	end
end

function PlayerDataService:RenewLocks()
	local now = os.clock()
	local dueSessions = self:_collectDueSessions(function(session)
		return now >= (session.Runtime.NextLockRenewAt or 0)
	end, function(session)
		return session.Runtime.NextLockRenewAt or math.huge
	end)

	for index = 1, math.min(#dueSessions, self.MaxLockRenewsPerPass) do
		local session = dueSessions[index]
		local ok, renewed = pcall(function()
			return self.SessionLocks:RenewLock(session.UserId)
		end)

		if not ok then
			warn(renewed)
			self:_scheduleNextLockRenew(session, 10)
		elseif not renewed and session.Player.Parent then
			session.Player:Kick("Session lock lost")
		else
			self:_scheduleNextLockRenew(session)
		end
	end
end

return PlayerDataService
