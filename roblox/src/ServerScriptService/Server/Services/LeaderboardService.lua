local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

local BOARD_DEFINITIONS = {
	{
		Key = "FishCaught",
		Title = "Fish Caught",
		StoreName = "FishABaddie_LB_FishCaught_v1",
		GetValue = function(profile)
			return profile.Stats.LifetimeCaught or 0
		end,
	},
	{
		Key = "SecretsCaught",
		Title = "Secrets Caught",
		StoreName = "FishABaddie_LB_SecretsCaught_v1",
		GetValue = function(profile)
			return (profile.Stats.CaughtByRarity and profile.Stats.CaughtByRarity.Secret) or 0
		end,
	},
	{
		Key = "Rebirths",
		Title = "Rebirths",
		StoreName = "FishABaddie_LB_Rebirths_v1",
		GetValue = function(profile)
			return profile.Progression.RebirthCount or 0
		end,
	},
	{
		Key = "Coins",
		Title = "Coins",
		StoreName = "FishABaddie_LB_Coins_v1",
		GetValue = function(profile)
			return math.floor(profile.Wallet.Coins or 0)
		end,
	},
}

function LeaderboardService.new(registry)
	return setmetatable({
		Registry = registry,
		Stores = {},
		LastWrittenValues = {},
		NameCache = {},
		PollIntervalSeconds = 30,
		MaxWritesPerPass = 40,
	}, LeaderboardService)
end

function LeaderboardService:Init()
	if RunService:IsStudio() then
		return
	end

	for _, definition in ipairs(BOARD_DEFINITIONS) do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(definition.StoreName)
		end)

		if ok then
			self.Stores[definition.Key] = store
		end
	end
end

function LeaderboardService:Start()
	task.spawn(function()
		task.wait(5)

		while true do
			self:RefreshLeaderboards()
			task.wait(self.PollIntervalSeconds)
		end
	end)
end

function LeaderboardService:_getOnlineFallback(definition)
	local rows = {}
	local playerDataService = self.Registry:Get("PlayerDataService")

	for _, player in ipairs(Players:GetPlayers()) do
		local session = playerDataService:FindSession(player)
		if session then
			table.insert(rows, {
				UserId = player.UserId,
				Name = player.DisplayName,
				Value = definition.GetValue(session.Profile),
			})
		end
	end

	table.sort(rows, function(a, b)
		return a.Value > b.Value
	end)

	while #rows > 10 do
		table.remove(rows)
	end

	return rows
end

function LeaderboardService:_writeOnlineStats()
	local writesRemaining = self.MaxWritesPerPass
	local playerDataService = self.Registry:Get("PlayerDataService")

	for _, player in ipairs(Players:GetPlayers()) do
		local session = playerDataService:FindSession(player)
		if session then
			for _, definition in ipairs(BOARD_DEFINITIONS) do
				if writesRemaining <= 0 then
					return
				end

				local store = self.Stores[definition.Key]
				local value = definition.GetValue(session.Profile)
				local writeKey = string.format("%s:%d", definition.Key, player.UserId)

				if store and self.LastWrittenValues[writeKey] ~= value then
					local ok = pcall(function()
						store:SetAsync(tostring(player.UserId), value)
					end)

					if ok then
						self.LastWrittenValues[writeKey] = value
						writesRemaining = writesRemaining - 1
					end
				end
			end
		end
	end
end

function LeaderboardService:_readRows(definition)
	local store = self.Stores[definition.Key]
	if not store then
		return self:_getOnlineFallback(definition)
	end

	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)

	if not ok or not pages then
		return self:_getOnlineFallback(definition)
	end

	local rows = {}
	for rank, entry in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(entry.key) or 0
		local name = self.NameCache[userId] or string.format("User %d", userId)

		if not self.NameCache[userId] then
			local nameOk, resolvedName = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)

			if nameOk and resolvedName then
				name = resolvedName
				self.NameCache[userId] = resolvedName
			end
		end

		table.insert(rows, {
			Rank = rank,
			UserId = userId,
			Name = name,
			Value = entry.value or 0,
		})
	end

	return rows
end

function LeaderboardService:_writeBoard(definition, rows)
	local board = self.Registry:Get("WorldService"):GetLeaderboardBoard(definition.Key)
	if not board then
		return
	end

	board:SetAttribute("LeaderboardTitle", definition.Title)
	board:SetAttribute("LastUpdatedAt", os.time())

	local surfaceGui = board:FindFirstChild("SurfaceGui")
	if not surfaceGui then
		return
	end

	local title = surfaceGui:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = definition.Title
	end

	for index = 1, 10 do
		local row = surfaceGui:FindFirstChild("Row_" .. index)
		if row and row:IsA("TextLabel") then
			local data = rows[index]
			if data then
				row.Text = string.format(
					"#%d  %s  %s",
					index,
					data.Name or ("User " .. tostring(data.UserId)),
					tostring(data.Value or 0)
				)
			else
				row.Text = string.format("#%d  ---", index)
			end
		end

		local avatar = surfaceGui:FindFirstChild("Avatar_" .. index)
		if avatar and avatar:IsA("ImageLabel") then
			local data = rows[index]
			avatar.Image = data and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100", data.UserId or 0)
				or ""
		end
	end
end

function LeaderboardService:RefreshLeaderboards()
	self:_writeOnlineStats()

	for _, definition in ipairs(BOARD_DEFINITIONS) do
		self:_writeBoard(definition, self:_readRows(definition))
	end
end

return LeaderboardService
