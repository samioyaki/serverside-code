local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)

local localPlayer = Players.LocalPlayer

local AudioController = {
	Replica = nil,
	Sounds = {},
	ActiveFishingId = nil,
}

local function makeSound(name, definition)
	if type(definition.AssetId) ~= "string" or definition.AssetId == "" then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = definition.AssetId
	sound.Volume = definition.Volume or 0.5
	sound.Parent = SoundService
	return sound
end

function AudioController:Play(name, playbackSpeed)
	local settings = self.Replica and self.Replica.Settings
	if settings and settings.SfxEnabled == false then
		return
	end

	local sound = self.Sounds[name]
	if not sound then
		return
	end
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.TimePosition = 0
	sound:Play()
end

function AudioController:_syncFishing(replica)
	local fishing = replica and replica.Fishing
	local fishingId = fishing and fishing.Id or nil
	if fishingId == self.ActiveFishingId then
		return
	end

	self.ActiveFishingId = fishingId
	if not fishingId then
		return
	end

	self:Play("BobberDip", 1.05)
	local biteDelay = math.max(0.05, (fishing.CastDurationSeconds or 1) * (fishing.SweetSpot or 0.5))
	task.delay(biteDelay, function()
		if self.ActiveFishingId == fishingId then
			self:Play("FishBite", 1.15)
		end
	end)
end

function AudioController:_handleNotification(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.Code == "CatchSuccess" then
		local rarity = payload.Context and payload.Context.RarityId
		local pitch = rarity == "Secret" and 1.55 or (rarity == "Mythic" and 1.35 or 1.1)
		self:Play("TimingSuccessPing", pitch)
	elseif payload.Code == "CatchFail" then
		self:Play("TimingFailPing", 1)
	elseif payload.Code == "IncomeClaimed" then
		self:Play("IncomeSmall", 1.1)
	elseif payload.Code == "BaddieHeld" or payload.Code == "BaddiePickedUp" then
		self:Play("BaddiePickup", 1.1)
	elseif payload.Code == "BaddiePlaced" then
		self:Play("BaddiePlacement", 1)
	elseif
		payload.Code == "UpgradePurchased"
		or payload.Code == "ComponentUpgraded"
		or payload.Code == "DateComplete"
		or payload.Code == "PurchaseSuccess"
		or payload.Code == "TraitRerolled"
		or payload.Code == "TraitUpgraded"
	then
		self:Play("UpgradeLevelUp", payload.Code == "DateComplete" and 1.35 or 1.1)
	elseif payload.Type == "Error" then
		self:Play("PurchaseFail", 0.95)
	end
end

function AudioController:_bindButton(button)
	if not button:IsA("GuiButton") or button:GetAttribute("FishABaddieAudioBound") then
		return
	end
	button:SetAttribute("FishABaddieAudioBound", true)
	button.Activated:Connect(function()
		self:Play("UIClick", 1.08)
	end)
end

function AudioController:Init(replicaClient)
	for name, definition in pairs(AudioConfig.Manifest) do
		local sound = makeSound(name, definition)
		if sound then
			self.Sounds[name] = sound
		end
	end

	self.Replica = replicaClient:Get()
	self:_syncFishing(self.Replica)
	replicaClient:Subscribe(function(replica)
		self.Replica = replica
		self:_syncFishing(replica)
	end)
	replicaClient:SubscribeNotifications(function(payload)
		self:_handleNotification(payload)
	end)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		self:_bindButton(descendant)
	end
	playerGui.DescendantAdded:Connect(function(descendant)
		self:_bindButton(descendant)
	end)
end

return AudioController
