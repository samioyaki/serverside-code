local LeaderstatsService = {}
LeaderstatsService.__index = LeaderstatsService

function LeaderstatsService.new(registry)
	return setmetatable({
		Registry = registry,
	}, LeaderstatsService)
end

function LeaderstatsService:Ensure(player)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end

	for _, statName in ipairs({ "Coins", "Rebirths", "Caught" }) do
		local value = folder:FindFirstChild(statName)
		if not value then
			value = Instance.new("IntValue")
			value.Name = statName
			value.Parent = folder
		end
	end

	self:Refresh(player)
end

function LeaderstatsService:Refresh(player)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	local folder = player:FindFirstChild("leaderstats")
	if not session or not folder then
		return
	end

	folder.Coins.Value = math.floor(session.Profile.Wallet.Coins)
	folder.Rebirths.Value = session.Profile.Progression.RebirthCount
	folder.Caught.Value = session.Profile.Stats.LifetimeCaught
end

return LeaderstatsService
