local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormulaUtil = require(ReplicatedStorage.Shared.Util.FormulaUtil)

local IncomeService = {}
IncomeService.__index = IncomeService

function IncomeService.new(registry)
	return setmetatable({
		Registry = registry,
		RefreshIntervalSeconds = 10,
		MaxAccrualSeconds = 900,
	}, IncomeService)
end

function IncomeService:Start()
	task.spawn(function()
		while true do
			task.wait(self.RefreshIntervalSeconds)
			self:RefreshAllPlayers()
		end
	end)
end

function IncomeService:GetIncomePerSecond(profile)
	local income = 0

	for baddieId in pairs(profile.Placements) do
		local baddie = profile.Inventory.Baddies[baddieId]
		if baddie then
			income += FormulaUtil.GetBaddieIncomePerSecond(baddie, profile)
		end
	end

	return income
end

function IncomeService:RefreshAllPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		self:Accrue(player, "PassiveRefresh")
	end
end

function IncomeService:Accrue(player, reason)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	if not session then
		return 0
	end

	local accrued = 0

	self.Registry:Get("PlayerDataService"):MutateProfileIfChanged(player, reason or "PassiveRefresh", {
		"Wallet",
		"Leaderstats",
	}, function(runtimeSession, profile)
		local now = os.time()
		local lastAccruedAt = runtimeSession.Runtime.LastIncomeAccruedAt or now
		local elapsedSeconds = math.clamp(now - lastAccruedAt, 0, self.MaxAccrualSeconds)
		runtimeSession.Runtime.LastIncomeAccruedAt = now

		if elapsedSeconds < 1 then
			return false, 0
		end

		local incomePerSecond = self:GetIncomePerSecond(profile)
		if incomePerSecond <= 0 then
			return false, 0
		end

		accrued = incomePerSecond * elapsedSeconds
		if accrued <= 0 then
			return false, 0
		end

		if profile.Premium.Effects.AutoCollect then
			profile.Wallet.Coins += accrued
		else
			self.Registry:Get("EconomyService"):AddUnclaimedCoins(profile, accrued)
		end

		return true, accrued
	end)

	return accrued
end

return IncomeService
