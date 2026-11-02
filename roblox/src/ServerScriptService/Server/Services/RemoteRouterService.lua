local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ErrorCode = require(Shared.Enums.ErrorCode)
local NetworkSchema = require(Shared.Schema.NetworkSchema)
local NotificationCode = require(Shared.Enums.NotificationCode)
local BaddieConfig = require(Shared.Config.BaddieConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local RemoteContracts = require(Shared.Contracts.RemoteContracts)

local RemoteRouterService = {}
RemoteRouterService.__index = RemoteRouterService

function RemoteRouterService.new(registry)
	return setmetatable({
		Registry = registry,
		Remotes = {},
		RateBuckets = {},
	}, RemoteRouterService)
end

function RemoteRouterService:Init()
	self.RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	for _, remoteName in pairs(RemoteContracts) do
		if string.sub(remoteName, -2) == "RF" then
			self.Remotes[remoteName] = self:_ensureRemote(remoteName, "RemoteFunction")
		else
			self.Remotes[remoteName] = self:_ensureRemote(remoteName, "RemoteEvent")
		end
	end
end

function RemoteRouterService:Start()
	Players.PlayerRemoving:Connect(function(player)
		local prefix = tostring(player.UserId) .. ":"
		for key in pairs(self.RateBuckets) do
			if string.sub(key, 1, #prefix) == prefix then
				self.RateBuckets[key] = nil
			end
		end
	end)

	self.Remotes[RemoteContracts.BootstrapRF].OnServerInvoke = function(player)
		if not self:_checkRateLimit(player, "Bootstrap") then
			return nil
		end

		return self.Registry:Get("ReplicaService"):BuildFullReplica(player)
	end

	self.Remotes[RemoteContracts.FishingRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateFishingPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			if payload.Action == "BeginCast" then
				self.Registry:Get("FishingService"):BeginCast(player, payload)
			elseif payload.Action == "ResolveCatch" then
				local baddie, success, bonusBaddie = self.Registry:Get("FishingService"):ResolveCatch(player, payload.SessionId, payload.HoldDurationSeconds)
				self:NotifyFishingResult(player, baddie, success, bonusBaddie)
			elseif payload.Action == "ReleaseCast" then
				local baddie, success, bonusBaddie = self.Registry:Get("FishingService"):ResolveActiveCast(player)
				self:NotifyFishingResult(player, baddie, success, bonusBaddie)
			elseif payload.Action == "CancelCast" then
				self.Registry:Get("FishingService"):CancelCast(player)
			end
		end)
	end)

	self.Remotes[RemoteContracts.PlacementRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validatePlacementPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			if payload.Action == "VisitPlot" then
				self.Registry:Get("PlotService"):TeleportToPlot(player)
			elseif payload.Action == "VisitDock" then
				self.Registry:Get("PlotService"):TeleportToDock(player)
			elseif payload.Action == "Remove" then
				self.Registry:Get("PlacementService"):Remove(player, payload.BaddieId)
			elseif payload.Action == "HoldBaddie" then
				local baddie = self.Registry:Get("PlacementService"):HoldBaddie(player, payload.BaddieId)
				self:Notify(player, "Reward", NotificationCode.BaddieHeld, {
					BaddieId = baddie and baddie.Id or payload.BaddieId,
				})
			elseif payload.Action == "ClearHeldBaddie" then
				self.Registry:Get("PlacementService"):ClearHeldBaddie(player)
			elseif payload.Action == "PlaceHeld" then
				local baddieId = self.Registry:Get("PlacementService"):PlaceHeld(player, payload.GridX, payload.GridY)
				self:Notify(player, "Reward", NotificationCode.BaddiePlaced, {
					BaddieId = baddieId,
					GridX = payload.GridX,
					GridY = payload.GridY,
				})
			elseif payload.Action == "PickupCell" then
				local baddie = self.Registry:Get("PlacementService"):PickupCell(player, payload.GridX, payload.GridY)
				self:Notify(player, "Reward", NotificationCode.BaddiePickedUp, {
					BaddieId = baddie and baddie.Id,
					GridX = payload.GridX,
					GridY = payload.GridY,
				})
			else
				self.Registry:Get("PlacementService"):Place(player, payload.BaddieId, payload.GridX, payload.GridY, payload.Rotation or 0)
			end
		end)
	end)

	self.Remotes[RemoteContracts.ClaimRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateClaimPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			local claimedAmount = self.Registry:Get("ClaimService"):ClaimIncome(player)
			self:Notify(player, "Reward", NotificationCode.IncomeClaimed, {
				Amount = claimedAmount,
			})
		end)
	end)

	self.Remotes[RemoteContracts.UpgradeRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateUpgradePayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			local requestedLevels = 1
			if payload.Action == "UpgradeTen" then
				requestedLevels = 10
			elseif payload.Action == "MaxBaddie" then
				requestedLevels = 10 ^ 6
			end

			local levelsBought = self.Registry:Get("UpgradeService"):UpgradeBaddie(player, payload.BaddieId, requestedLevels)
			self:Notify(player, "Reward", NotificationCode.UpgradePurchased, {
				LevelsBought = levelsBought,
				BaddieId = payload.BaddieId,
			})
		end)
	end)

	self.Remotes[RemoteContracts.RebirthRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateRebirthPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			local rebirthCount = self.Registry:Get("RebirthService"):Execute(player)
			self:Notify(player, "Reward", NotificationCode.RebirthComplete, {
				RebirthCount = rebirthCount,
			})
		end)
	end)

	self.Remotes[RemoteContracts.ShopRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateShopPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			if payload.Action == "Purchase" then
				self.Registry:Get("ShopService"):Purchase(player, payload.EntryId, payload.Quantity)
				self:Notify(player, "Reward", NotificationCode.PurchaseSuccess, { EntryId = payload.EntryId })
			elseif payload.Action == "EquipRod" then
				self.Registry:Get("ShopService"):EquipRod(player, payload.EntryId)
				self:Notify(player, "Reward", NotificationCode.PurchaseSuccess, { EntryId = payload.EntryId, Equipped = true })
			elseif payload.Action == "PromptProduct" then
				self.Registry:Get("MonetizationService"):PromptProduct(player, payload.EntryId, payload.Context)
			end
		end)
	end)

	self.Remotes[RemoteContracts.FusionRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateFusionPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			if payload.Action == "FuseTemplate" then
				self.Registry:Get("FusionService"):FuseTemplate(player, payload.TemplateId)
				self:Notify(player, "Reward", NotificationCode.FusionComplete, {
					TemplateId = payload.TemplateId,
				})
			elseif payload.Action == "ConvertSecret" then
				self.Registry:Get("FusionService"):ConvertSecret(player, payload.BaddieId)
				self:Notify(player, "Reward", NotificationCode.SecretConverted, {
					BaddieId = payload.BaddieId,
				})
			end
		end)
	end)

	self.Remotes[RemoteContracts.CrateRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateCratePayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			local reward = self.Registry:Get("CrateService"):OpenOwnedCrate(player, payload.CrateId)
			self:Notify(player, "Reward", NotificationCode.CrateOpened, reward)
			if reward and reward.BaddieId then
				self:BroadcastRareCatch(player, {
					Id = reward.BaddieId,
					TemplateId = reward.TemplateId,
					RarityId = reward.RarityId,
				}, false)
			end
		end)
	end)

	self.Remotes[RemoteContracts.TraitRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateTraitPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			if payload.Action == "RerollTrait" then
				local traitId = self.Registry:Get("TraitService"):RerollTrait(player, payload.BaddieId, payload.SlotIndex)
				self:Notify(player, "Reward", NotificationCode.TraitRerolled, {
					BaddieId = payload.BaddieId,
					TraitId = traitId,
					SlotIndex = payload.SlotIndex or 1,
				})
			elseif payload.Action == "TargetedTraitRoll" then
				local traitId = self.Registry:Get("TraitService"):TargetedTraitRoll(player, payload.BaddieId, payload.SlotIndex)
				self:Notify(player, "Reward", NotificationCode.TraitRerolled, {
					BaddieId = payload.BaddieId,
					TraitId = traitId,
					SlotIndex = payload.SlotIndex or 1,
				})
			elseif payload.Action == "GodTierRoll" then
				local traitId = self.Registry:Get("TraitService"):GodTierRoll(player, payload.BaddieId, payload.SlotIndex)
				self:Notify(player, "Reward", NotificationCode.TraitRerolled, {
					BaddieId = payload.BaddieId,
					TraitId = traitId,
					SlotIndex = payload.SlotIndex or 1,
				})
			elseif payload.Action == "LockTraitSlot" then
				local slotIndex = self.Registry:Get("TraitService"):LockTraitSlot(player, payload.BaddieId, payload.SlotIndex)
				self:Notify(player, "Reward", NotificationCode.TraitLocked, {
					BaddieId = payload.BaddieId,
					SlotIndex = slotIndex,
				})
			elseif payload.Action == "UpgradeTraitTier" then
				local traitId = self.Registry:Get("TraitService"):UpgradeTraitTier(player, payload.BaddieId, payload.SlotIndex)
				self:Notify(player, "Reward", NotificationCode.TraitUpgraded, {
					BaddieId = payload.BaddieId,
					TraitId = traitId,
					SlotIndex = payload.SlotIndex or 1,
				})
			elseif payload.Action == "ApplyUpgradePack" then
				local levelsBought = self.Registry:Get("UpgradeService"):ApplyUpgradePack(player, payload.BaddieId)
				self:Notify(player, "Reward", NotificationCode.UpgradePurchased, {
					BaddieId = payload.BaddieId,
					LevelsBought = levelsBought,
					UsedPack = true,
				})
			end
		end)
	end)

	self.Remotes[RemoteContracts.RodComponentRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateRodComponentPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			if payload.Action == "UpgradeComponent" then
				local newTier, spent = self.Registry:Get("RodComponentService"):UpgradeComponent(player, payload.RodId, payload.ComponentName)
				self:Notify(player, "Reward", NotificationCode.ComponentUpgraded, {
					RodId = payload.RodId,
					ComponentName = payload.ComponentName,
					Tier = newTier,
					Spent = spent,
				})
			elseif payload.Action == "InstantMaxComponent" then
				self.Registry:Get("MonetizationService"):PromptProduct(player, "InstantMaxComponent", {
					RodId = payload.RodId,
					ComponentName = payload.ComponentName,
				})
			elseif payload.Action == "InstantMaxAllComponents" then
				self.Registry:Get("MonetizationService"):PromptProduct(player, "InstantMaxAllComponents", {
					RodId = payload.RodId,
				})
			end
		end)
	end)

	self.Remotes[RemoteContracts.DatingRequestRE].OnServerEvent:Connect(function(player, payload)
		self:_dispatch(player, function()
			local ok, code = self:_validateDatingPayload(player, payload)
			if not ok then
				self:Notify(player, "Error", code)
				return
			end

			local affection, reward = self.Registry:Get("DatingService"):DateBaddie(player, payload.BaddieId)
			self:Notify(player, "Reward", NotificationCode.DateComplete, {
				BaddieId = payload.BaddieId,
				Affection = affection,
				CoinReward = reward,
			})
		end)
	end)
end

function RemoteRouterService:_ensureRemote(remoteName, className)
	local remote = self.RemotesFolder:FindFirstChild(remoteName)
	if remote then
		return remote
	end

	remote = Instance.new(className)
	remote.Name = remoteName
	remote.Parent = self.RemotesFolder
	return remote
end

function RemoteRouterService:_dispatch(player, handler)
	local ok, err = pcall(handler)
	if not ok then
		self:Notify(player, "Error", self:_normalizeError(err))
	end
end

function RemoteRouterService:Notify(player, notificationType, code, context)
	self.Remotes[RemoteContracts.NotificationRE]:FireClient(player, {
		Type = notificationType,
		Code = code,
		Context = context,
	})
end

function RemoteRouterService:NotifyFishingResult(player, baddie, success, bonusBaddie)
	if success and baddie then
		self:Notify(player, "Reward", NotificationCode.CatchSuccess, {
			BaddieId = baddie.Id,
			TemplateId = baddie.TemplateId,
			RarityId = baddie.RarityId,
			TraitIds = baddie.TraitIds,
			Level = baddie.Level,
		})

		if bonusBaddie then
			self:Notify(player, "Reward", NotificationCode.CatchSuccess, {
				BaddieId = bonusBaddie.Id,
				TemplateId = bonusBaddie.TemplateId,
				RarityId = bonusBaddie.RarityId,
				TraitIds = bonusBaddie.TraitIds,
				Level = bonusBaddie.Level,
				BonusCatch = true,
			})
		end

		self:BroadcastRareCatch(player, baddie, false)
		if bonusBaddie then
			self:BroadcastRareCatch(player, bonusBaddie, true)
		end
	else
		self:Notify(player, "Error", NotificationCode.CatchFail)
	end
end

function RemoteRouterService:_getRarityIndex(rarityId)
	return table.find(RarityConfig.Order, rarityId) or 0
end

function RemoteRouterService:BroadcastRareCatch(player, baddie, isBonus)
	if self:_getRarityIndex(baddie.RarityId) < self:_getRarityIndex("Legendary") then
		return
	end

	local template = BaddieConfig.Definitions[baddie.TemplateId]
	local code = baddie.RarityId == "Secret" and NotificationCode.SecretCaughtBroadcast or NotificationCode.RareCatchBroadcast
	local context = {
		Code = code,
		CatcherUserId = player.UserId,
		CatcherName = player.DisplayName,
		BaddieId = baddie.Id,
		TemplateId = baddie.TemplateId,
		BaddieName = template and template.DisplayName or baddie.TemplateId,
		RarityId = baddie.RarityId,
		BonusCatch = isBonus == true,
		ServerTime = os.time(),
	}

	self.Remotes[RemoteContracts.RareCatchBroadcastRE]:FireAllClients(context)
	self.Remotes[RemoteContracts.NotificationRE]:FireAllClients({
		Type = "Broadcast",
		Code = code,
		Context = context,
	})
	self.Registry:Get("WorldService"):SpawnRareCatchBurst(player, baddie.RarityId)
end

function RemoteRouterService:_normalizeError(err)
	local text = tostring(err)
	if ErrorCode[text] or NotificationCode[text] then
		return text
	end

	return "RequestFailed"
end

function RemoteRouterService:_checkRateLimit(player, bucketId)
	local config = NetworkSchema.RateLimits[bucketId]
	local now = os.clock()
	local key = string.format("%d:%s", player.UserId, bucketId)
	local bucket = self.RateBuckets[key]

	if not bucket or now - bucket.StartedAt >= config.WindowSeconds then
		bucket = {
			StartedAt = now,
			Count = 0,
		}
		self.RateBuckets[key] = bucket
	end

	if bucket.Count >= config.MaxCalls then
		return false
	end

	bucket.Count += 1
	return true
end

function RemoteRouterService:_isString(value, maxLength)
	return type(value) == "string" and value ~= "" and #value <= maxLength
end

function RemoteRouterService:_isInteger(value)
	return type(value) == "number" and value % 1 == 0
end

function RemoteRouterService:_isVector3(value)
	return typeof(value) == "Vector3"
end

function RemoteRouterService:_validateFishingPayload(player, payload)
	local schema = NetworkSchema.FishingRequest
	if not self:_checkRateLimit(player, "FishingRequest") then
		return false, "FishingRateLimited"
	end
	if type(payload) ~= "table" or not schema.AllowedActions[payload.Action] then
		return false, "InvalidFishingAction"
	end
	if payload.Action == "ResolveCatch" then
		if not self:_isString(payload.SessionId, schema.MaxSessionIdLength) or type(payload.HoldDurationSeconds) ~= "number" then
			return false, "InvalidPayload"
		end
	end
	if payload.Action == "BeginCast" then
		if payload.TargetPosition ~= nil and not self:_isVector3(payload.TargetPosition) then
			return false, "InvalidPayload"
		end
		if payload.CastDirection ~= nil and not self:_isVector3(payload.CastDirection) then
			return false, "InvalidPayload"
		end
		if payload.CastDistance ~= nil and type(payload.CastDistance) ~= "number" then
			return false, "InvalidPayload"
		end
	end
	return true
end

function RemoteRouterService:_validatePlacementPayload(player, payload)
	local schema = NetworkSchema.PlacementRequest
	if not self:_checkRateLimit(player, "PlacementRequest") then
		return false, "InvalidPlacementAction"
	end
	if type(payload) ~= "table" or not schema.AllowedActions[payload.Action] then
		return false, "InvalidPlacementAction"
	end

	if payload.Action == "ClearHeldBaddie" or payload.Action == "VisitPlot" or payload.Action == "VisitDock" then
		return true
	end

	if payload.Action == "HoldBaddie" or payload.Action == "Remove" or payload.Action == "Place" or payload.Action == "Move" then
		if not self:_isString(payload.BaddieId, schema.MaxBaddieIdLength) then
			return false, "InvalidPlacementAction"
		end
	end

	if payload.Action == "Place" or payload.Action == "Move" or payload.Action == "PlaceHeld" or payload.Action == "PickupCell" then
		if not self:_isInteger(payload.GridX) or not self:_isInteger(payload.GridY) then
			return false, "InvalidPlacementAction"
		end
		if payload.GridX < schema.MinGrid or payload.GridX > schema.MaxGrid or payload.GridY < schema.MinGrid or payload.GridY > schema.MaxGrid then
			return false, "InvalidPlacementAction"
		end
	end

	if (payload.Action == "Place" or payload.Action == "Move") and payload.Rotation ~= nil then
		if not schema.AllowedRotations[payload.Rotation] then
			return false, "InvalidPlacementAction"
		end
	end

	return true
end

function RemoteRouterService:_validateClaimPayload(player, payload)
	if not self:_checkRateLimit(player, "ClaimRequest") then
		return false, "InvalidClaimAction"
	end
	if type(payload) ~= "table" or payload.Action ~= "ClaimIncome" then
		return false, "InvalidClaimAction"
	end
	return true
end

function RemoteRouterService:_validateUpgradePayload(player, payload)
	local schema = NetworkSchema.UpgradeRequest
	if not self:_checkRateLimit(player, "UpgradeRequest") then
		return false, "InvalidUpgradeAction"
	end
	if type(payload) ~= "table" or not schema.AllowedActions[payload.Action] then
		return false, "InvalidUpgradeAction"
	end
	if not self:_isString(payload.BaddieId, schema.MaxBaddieIdLength) then
		return false, "InvalidUpgradeAction"
	end
	return true
end

function RemoteRouterService:_validateRebirthPayload(player, payload)
	if not self:_checkRateLimit(player, "RebirthRequest") then
		return false, "InvalidRebirthAction"
	end
	if type(payload) ~= "table" or payload.Action ~= "Execute" then
		return false, "InvalidRebirthAction"
	end
	return true
end

function RemoteRouterService:_validateShopPayload(player, payload)
	local schema = NetworkSchema.ShopRequest
	if not self:_checkRateLimit(player, "ShopRequest") then
		return false, "InvalidShopAction"
	end
	if type(payload) ~= "table" or not schema.AllowedActions[payload.Action] then
		return false, "InvalidShopAction"
	end
	if not self:_isString(payload.EntryId, schema.MaxEntryIdLength) then
		return false, "InvalidShopAction"
	end
	if payload.Action == "Purchase" and payload.Quantity ~= nil then
		if not self:_isInteger(payload.Quantity) or payload.Quantity < 1 or payload.Quantity > schema.MaxQuantity then
			return false, "InvalidShopAction"
		end
	end
	return true
end

function RemoteRouterService:_validateFusionPayload(player, payload)
	local schema = NetworkSchema.FusionRequest
	if not self:_checkRateLimit(player, "FusionRequest") then
		return false, "InvalidFusionAction"
	end
	if type(payload) ~= "table" or not schema.AllowedActions[payload.Action] then
		return false, "InvalidFusionAction"
	end
	if payload.Action == "FuseTemplate" then
		if not self:_isString(payload.TemplateId, schema.MaxTemplateIdLength) then
			return false, "InvalidFusionAction"
		end
	elseif payload.Action == "ConvertSecret" then
		if not self:_isString(payload.BaddieId, schema.MaxBaddieIdLength) then
			return false, "InvalidFusionAction"
		end
	end
	return true
end

function RemoteRouterService:_validateCratePayload(player, payload)
	local schema = NetworkSchema.CrateRequest
	if not self:_checkRateLimit(player, "CrateRequest") then
		return false, "InvalidCrateAction"
	end
	if type(payload) ~= "table" or payload.Action ~= "OpenOwnedCrate" then
		return false, "InvalidCrateAction"
	end
	if not self:_isString(payload.CrateId, schema.MaxCrateIdLength) then
		return false, "InvalidCrateAction"
	end
	return true
end

function RemoteRouterService:_validateTraitPayload(player, payload)
	local schema = NetworkSchema.TraitRequest
	if not self:_checkRateLimit(player, "TraitRequest") then
		return false, "InvalidTraitAction"
	end
	if type(payload) ~= "table" or not schema.AllowedActions[payload.Action] then
		return false, "InvalidTraitAction"
	end
	if not self:_isString(payload.BaddieId, schema.MaxBaddieIdLength) then
		return false, "InvalidTraitAction"
	end
	if payload.SlotIndex ~= nil and (not self:_isInteger(payload.SlotIndex) or payload.SlotIndex < 1 or payload.SlotIndex > 3) then
		return false, "TraitSlotInvalid"
	end
	return true
end

function RemoteRouterService:_validateRodComponentPayload(player, payload)
	local schema = NetworkSchema.RodComponentRequest
	if not self:_checkRateLimit(player, "RodComponentRequest") then
		return false, "InvalidRodComponentAction"
	end
	if type(payload) ~= "table" or not schema.AllowedActions[payload.Action] then
		return false, "InvalidRodComponentAction"
	end
	if payload.RodId ~= nil and not self:_isString(payload.RodId, schema.MaxRodIdLength) then
		return false, "InvalidRodComponentAction"
	end
	if payload.Action ~= "InstantMaxAllComponents" then
		if not schema.AllowedComponents[payload.ComponentName] then
			return false, "UnknownComponent"
		end
	end
	return true
end

function RemoteRouterService:_validateDatingPayload(player, payload)
	local schema = NetworkSchema.DatingRequest
	if not self:_checkRateLimit(player, "DatingRequest") then
		return false, "InvalidDatingAction"
	end
	if type(payload) ~= "table" or not schema.AllowedActions[payload.Action] then
		return false, "InvalidDatingAction"
	end
	if not self:_isString(payload.BaddieId, schema.MaxBaddieIdLength) then
		return false, "InvalidDatingAction"
	end
	return true
end

return RemoteRouterService
