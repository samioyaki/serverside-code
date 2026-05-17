local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local RemoteContracts = require(Shared.Contracts.RemoteContracts)
local ReplicaSchema = require(Shared.Schema.ReplicaSchema)
local TableUtil = require(Shared.Util.TableUtil)

local ReplicaService = {}
ReplicaService.__index = ReplicaService

function ReplicaService.new(registry)
	return setmetatable({
		Registry = registry,
	}, ReplicaService)
end

function ReplicaService:Init()
	self.RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	self.StateDeltaRemote = self.RemotesFolder:FindFirstChild(RemoteContracts.StateDeltaRE)
	if not self.StateDeltaRemote then
		self.StateDeltaRemote = Instance.new("RemoteEvent")
		self.StateDeltaRemote.Name = RemoteContracts.StateDeltaRE
		self.StateDeltaRemote.Parent = self.RemotesFolder
	end
end

function ReplicaService:_buildLeaderstats(profile)
	return {
		Coins = math.floor(profile.Wallet.Coins),
		Rebirths = profile.Progression.RebirthCount,
		Caught = profile.Stats.LifetimeCaught,
	}
end

function ReplicaService:_buildPremium(profile)
	return {
		OwnedPasses = TableUtil.DeepCopy(profile.Premium.OwnedPasses),
		Products = TableUtil.DeepCopy(profile.Premium.Products),
		Effects = TableUtil.DeepCopy(profile.Premium.Effects),
	}
end

function ReplicaService:_buildFishing(session)
	if not session.Runtime.Fishing then
		return nil
	end

	return TableUtil.DeepCopy(session.Runtime.Fishing.Public)
end

function ReplicaService:_buildValue(player, path)
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local profile = session.Profile

	if path == "ServerTime" then
		return os.time()
	elseif path == "Wallet" then
		return TableUtil.DeepCopy(profile.Wallet)
	elseif path == "Progression" then
		local progression = TableUtil.DeepCopy(profile.Progression)
		progression.PlotSlots = self.Registry:Get("MonetizationService"):GetEffectivePlotSlots(profile)
		return progression
	elseif path == "Inventory" then
		return TableUtil.DeepCopy(profile.Inventory)
	elseif path == "PlayerUpgrades" then
		return TableUtil.DeepCopy(profile.PlayerUpgrades)
	elseif path == "RebirthUpgrades" then
		return TableUtil.DeepCopy(profile.RebirthUpgrades)
	elseif path == "Unlocks" then
		return TableUtil.DeepCopy(profile.Unlocks)
	elseif path == "Plot" then
		return self.Registry:Get("PlotService"):BuildReplicaPlotState(player)
	elseif path == "Fishing" then
		return self:_buildFishing(session)
	elseif path == "Dex" then
		return TableUtil.DeepCopy(profile.Dex)
	elseif path == "Stats" then
		return TableUtil.DeepCopy(profile.Stats)
	elseif path == "Boosts" then
		return TableUtil.DeepCopy(profile.Boosts)
	elseif path == "Premium" then
		return self:_buildPremium(profile)
	elseif path == "Leaderstats" then
		return self:_buildLeaderstats(profile)
	elseif path == "Settings" then
		return TableUtil.DeepCopy(profile.Settings)
	elseif path == "RodComponents" then
		return TableUtil.DeepCopy(profile.RodComponents)
	end

	return nil
end

function ReplicaService:BuildFullReplica(player)
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local replica = ReplicaSchema.CreateEmpty()

	replica.Revision = session.Revision
	replica.ServerTime = os.time()
	replica.Wallet = self:_buildValue(player, "Wallet")
	replica.Progression = self:_buildValue(player, "Progression")
	replica.Inventory = self:_buildValue(player, "Inventory")
	replica.PlayerUpgrades = self:_buildValue(player, "PlayerUpgrades")
	replica.RebirthUpgrades = self:_buildValue(player, "RebirthUpgrades")
	replica.Unlocks = self:_buildValue(player, "Unlocks")
	replica.Plot = self:_buildValue(player, "Plot")
	replica.Fishing = self:_buildValue(player, "Fishing")
	replica.Dex = self:_buildValue(player, "Dex")
	replica.Stats = self:_buildValue(player, "Stats")
	replica.Boosts = self:_buildValue(player, "Boosts")
	replica.Premium = self:_buildValue(player, "Premium")
	replica.Leaderstats = self:_buildValue(player, "Leaderstats")
	replica.Settings = self:_buildValue(player, "Settings")
	replica.RodComponents = self:_buildValue(player, "RodComponents")

	return replica
end

function ReplicaService:PushFull(player)
	self.StateDeltaRemote:FireClient(player, {
		Full = true,
		State = self:BuildFullReplica(player),
	})
end

function ReplicaService:Publish(player, paths, reason)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	if not session then
		return
	end

	local ops = {}
	local seen = {}

	for _, path in ipairs(paths or {}) do
		if not seen[path] then
			seen[path] = true
			table.insert(ops, {
				Op = "Replace",
				Path = path,
				Value = self:_buildValue(player, path),
			})
		end
	end

	if not seen.ServerTime then
		table.insert(ops, {
			Op = "Replace",
			Path = "ServerTime",
			Value = os.time(),
		})
	end

	if #ops == 0 then
		return
	end

	self.StateDeltaRemote:FireClient(player, {
		Reason = reason,
		Revision = session.Revision,
		Ops = ops,
	})
end

return ReplicaService
