local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DatingConfig = require(Shared.Config.DatingConfig)

local DatingService = {}
DatingService.__index = DatingService

local function fail(code)
	error(code, 0)
end

function DatingService.new(registry)
	return setmetatable({ Registry = registry }, DatingService)
end

function DatingService:DateBaddie(player, baddieId)
	local affection = 0
	local reward = 0

	self.Registry:Get("IncomeService"):Accrue(player, "BeforeDate")
	self.Registry:Get("PlayerDataService"):MutateProfile(player, "DateBaddie", {
		"Inventory",
		"Plot",
		"Wallet",
		"Leaderstats",
	}, function(_, profile)
		local baddie = self.Registry:Get("InventoryService"):AssertBaddie(profile, baddieId)
		local placement = profile.Placements[baddieId]
		if not placement then
			fail("BaddieMustBePlaced")
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			fail("FishingNoCharacter")
		end
		local position = self.Registry:Get("PlotService"):GetCellWorldPosition(player, placement.GridX, placement.GridY)
		if (root.Position - position).Magnitude > DatingConfig.InteractionDistance then
			fail("PlacementTooFar")
		end

		local now = os.time()
		local current = math.clamp(math.floor(tonumber(baddie.Affection) or 0), 0, DatingConfig.MaxAffection)
		if current >= DatingConfig.MaxAffection then
			fail("AffectionMaxed")
		end
		if now - (tonumber(baddie.LastDatedAt) or 0) < DatingConfig.CooldownSeconds then
			fail("DateCooldown")
		end

		affection = current + 1
		reward = DatingConfig.CoinRewardPerHeart * affection
		baddie.Affection = affection
		baddie.LastDatedAt = now
		baddie.UpdatedAt = now
		profile.Wallet.Coins += reward
	end)

	return affection, reward
end

return DatingService
