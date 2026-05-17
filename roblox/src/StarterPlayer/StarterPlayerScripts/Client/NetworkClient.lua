local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local RemoteContracts = require(Shared.Contracts.RemoteContracts)

local NetworkClient = {
	Initialized = false,
	Remotes = {},
}

function NetworkClient:Init()
	if self.Initialized then
		return
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	for _, remoteName in pairs(RemoteContracts) do
		self.Remotes[remoteName] = remotesFolder:WaitForChild(remoteName)
	end

	self.Initialized = true
end

function NetworkClient:Bootstrap()
	return self.Remotes[RemoteContracts.BootstrapRF]:InvokeServer()
end

function NetworkClient:BindStateDelta(listener)
	return self.Remotes[RemoteContracts.StateDeltaRE].OnClientEvent:Connect(listener)
end

function NetworkClient:BindNotification(listener)
	return self.Remotes[RemoteContracts.NotificationRE].OnClientEvent:Connect(listener)
end

function NetworkClient:BindRareCatchBroadcast(listener)
	return self.Remotes[RemoteContracts.RareCatchBroadcastRE].OnClientEvent:Connect(listener)
end

function NetworkClient:SendFishing(payload)
	self.Remotes[RemoteContracts.FishingRequestRE]:FireServer(payload)
end

function NetworkClient:SendPlacement(payload)
	self.Remotes[RemoteContracts.PlacementRequestRE]:FireServer(payload)
end

function NetworkClient:SendClaim(payload)
	self.Remotes[RemoteContracts.ClaimRequestRE]:FireServer(payload)
end

function NetworkClient:SendUpgrade(payload)
	self.Remotes[RemoteContracts.UpgradeRequestRE]:FireServer(payload)
end

function NetworkClient:SendRebirth(payload)
	self.Remotes[RemoteContracts.RebirthRequestRE]:FireServer(payload)
end

function NetworkClient:SendShop(payload)
	self.Remotes[RemoteContracts.ShopRequestRE]:FireServer(payload)
end

function NetworkClient:SendFusion(payload)
	self.Remotes[RemoteContracts.FusionRequestRE]:FireServer(payload)
end

function NetworkClient:SendCrate(payload)
	self.Remotes[RemoteContracts.CrateRequestRE]:FireServer(payload)
end

function NetworkClient:SendTrait(payload)
	self.Remotes[RemoteContracts.TraitRequestRE]:FireServer(payload)
end

function NetworkClient:SendRodComponent(payload)
	self.Remotes[RemoteContracts.RodComponentRequestRE]:FireServer(payload)
end

return NetworkClient
