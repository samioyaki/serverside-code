local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FishingConfig = require(Shared.Config.FishingConfig)
local RodConfig = require(Shared.Config.RodConfig)
local FormulaUtil = require(Shared.Util.FormulaUtil)
local IdUtil = require(Shared.Util.IdUtil)
local NetworkSchema = require(Shared.Schema.NetworkSchema)

local FishingService = {}
FishingService.__index = FishingService

local function fail(code)
	error(code, 0)
end

local function getFlatDirection(direction, fallback)
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude >= 0.001 then
		return flatDirection.Unit
	end

	local fallbackDirection = Vector3.new(fallback.X, 0, fallback.Z)
	if fallbackDirection.Magnitude >= 0.001 then
		return fallbackDirection.Unit
	end

	return Vector3.new(0, 0, -1)
end

function FishingService.new(registry)
	return setmetatable({
		Registry = registry,
		Random = Random.new(),
	}, FishingService)
end

function FishingService:_getCharacterRoot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not character or not root or (humanoid and humanoid.Health <= 0) then
		fail("FishingNoCharacter")
	end

	return root
end

function FishingService:_resolveCastTarget(player, request)
	local worldService = self.Registry:Get("WorldService")
	local surfaceY = worldService:GetWaterSurfaceY()
	if not surfaceY then
		fail("FishingNoWater")
	end

	local root = self:_getCharacterRoot(player)
	local origin = root.Position + Vector3.new(0, 1.6, 0)
	local targetPosition = nil

	if type(request) == "table" and typeof(request.TargetPosition) == "Vector3" then
		targetPosition = Vector3.new(request.TargetPosition.X, surfaceY, request.TargetPosition.Z)
	else
		local direction = root.CFrame.LookVector
		if type(request) == "table" and typeof(request.CastDirection) == "Vector3" then
			direction = request.CastDirection
		end

		local castDistance = FishingConfig.DefaultCastDistance
		if type(request) == "table" and type(request.CastDistance) == "number" then
			castDistance = request.CastDistance
		end
		castDistance = math.clamp(castDistance, FishingConfig.MinCastDistance, FishingConfig.MaxCastDistance)

		local flatDirection = getFlatDirection(direction, root.CFrame.LookVector)
		targetPosition = Vector3.new(origin.X, surfaceY, origin.Z) + (flatDirection * castDistance)
	end

	local horizontalDelta = Vector3.new(targetPosition.X - origin.X, 0, targetPosition.Z - origin.Z)
	local castDistance = horizontalDelta.Magnitude
	if castDistance < FishingConfig.MinCastDistance then
		fail("FishingTargetTooClose")
	end
	if castDistance > FishingConfig.MaxCastDistance then
		fail("FishingTargetTooFar")
	end
	if not worldService:IsPointInFishingWater(targetPosition, FishingConfig.WaterBoundsMargin) then
		fail("FishingTargetInvalid")
	end

	return {
		Origin = origin,
		TargetPosition = targetPosition,
		CastDistance = castDistance,
	}
end

function FishingService:_clearPlayerCastModel(player)
	local castsFolder = self.Registry:Get("WorldService"):GetFishingCastsFolder()
	if not castsFolder then
		return
	end

	local existing = castsFolder:FindFirstChild(tostring(player.UserId))
	if existing then
		existing:Destroy()
	end
end

function FishingService:_clearCastWorldModel(fishingSession)
	if fishingSession and fishingSession.WorldModel then
		fishingSession.WorldModel:Destroy()
		fishingSession.WorldModel = nil
	end
end

function FishingService:_createCastWorldModel(player, fishingSession)
	local castsFolder = self.Registry:Get("WorldService"):GetFishingCastsFolder()
	if not castsFolder then
		return
	end

	self:_clearPlayerCastModel(player)

	local model = Instance.new("Folder")
	model.Name = tostring(player.UserId)
	model:SetAttribute("PlayerUserId", player.UserId)
	model:SetAttribute("SessionId", fishingSession.Id)
	model:SetAttribute("RodId", fishingSession.RodId)
	model:SetAttribute("CastDistance", fishingSession.CastDistance)
	model.Parent = castsFolder

	local bobber = Instance.new("Part")
	bobber.Name = "Bobber"
	bobber.Anchored = true
	bobber.CanCollide = false
	bobber.CanTouch = false
	bobber.CanQuery = false
	bobber.Shape = Enum.PartType.Ball
	bobber.Size = Vector3.new(1, 1, 1) * FishingConfig.BobberSize
	bobber.Position = fishingSession.TargetPosition
	bobber.Material = Enum.Material.SmoothPlastic
	bobber.Color = Color3.fromRGB(255, 68, 68)
	bobber:SetAttribute("SessionId", fishingSession.Id)
	bobber.Parent = model

	local glow = Instance.new("PointLight")
	glow.Name = "BobberGlow"
	glow.Brightness = 1.2
	glow.Color = Color3.fromRGB(255, 92, 78)
	glow.Range = 8
	glow.Parent = bobber

	local splash = Instance.new("ParticleEmitter")
	splash.Name = "BiteSplash"
	splash.Color = ColorSequence.new(Color3.fromRGB(183, 235, 255), Color3.fromRGB(65, 159, 255))
	splash.Lifetime = NumberRange.new(0.35, 0.7)
	splash.Rate = 0
	splash.Speed = NumberRange.new(3, 7)
	splash.SpreadAngle = Vector2.new(120, 120)
	splash.Parent = bobber

	local lineDelta = fishingSession.TargetPosition - fishingSession.Origin
	local lineLength = lineDelta.Magnitude
	if lineLength > 0.001 then
		local line = Instance.new("Part")
		line.Name = "Line"
		line.Anchored = true
		line.CanCollide = false
		line.CanTouch = false
		line.CanQuery = false
		line.Size = Vector3.new(FishingConfig.LineThickness, FishingConfig.LineThickness, lineLength)
		line.CFrame = CFrame.lookAt(fishingSession.Origin:Lerp(fishingSession.TargetPosition, 0.5), fishingSession.TargetPosition)
		line.Material = Enum.Material.SmoothPlastic
		line.Color = Color3.fromRGB(235, 242, 255)
		line.Transparency = 0.15
		line.Parent = model
	end

	fishingSession.WorldModel = model

	task.delay(fishingSession.CastDurationSeconds * fishingSession.SweetSpot, function()
		if not bobber.Parent or fishingSession.WorldModel ~= model then
			return
		end
		splash:Emit(18)
		local restPosition = bobber.Position
		local dip = TweenService:Create(
			bobber,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = restPosition - Vector3.new(0, 0.65, 0) }
		)
		dip:Play()
		dip.Completed:Connect(function()
			if bobber.Parent then
				TweenService:Create(
					bobber,
					TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Position = restPosition }
				):Play()
			end
		end)
	end)
end

function FishingService:_finishRuntimeFishing(runtimeSession)
	self:_clearCastWorldModel(runtimeSession.Runtime.Fishing)
	runtimeSession.Runtime.Fishing = nil
	runtimeSession.Runtime.LastCastEndedAt = os.clock()
end

function FishingService:_scheduleAutoCatch(player, sessionId, delaySeconds)
	task.delay(delaySeconds, function()
		local session = self.Registry:Get("PlayerDataService"):FindSession(player)
		local fishingSession = session and session.Runtime.Fishing
		if not fishingSession or fishingSession.Id ~= sessionId then
			return
		end

		local results = table.pack(pcall(function()
			return self:ResolveActiveCast(player)
		end))
		local router = self.Registry:Get("RemoteRouterService")

		if results[1] then
			router:NotifyFishingResult(player, results[2], results[3], results[4])
		else
			router:Notify(player, "Error", router:_normalizeError(results[2]))
		end
	end)
end

function FishingService:_scheduleCastTimeout(player, sessionId, delaySeconds)
	task.delay(delaySeconds, function()
		local session = self.Registry:Get("PlayerDataService"):FindSession(player)
		local fishingSession = session and session.Runtime.Fishing
		if fishingSession and fishingSession.Id == sessionId then
			self:CancelCast(player)
		end
	end)
end

function FishingService:HasActiveSession(player)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	return session ~= nil and session.Runtime.Fishing ~= nil
end

function FishingService:BeginCast(player, request)
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local profile = session.Profile

	if session.Runtime.Fishing then
		fail("FishingAlreadyActive")
	end

	local now = os.clock()
	local lastEndedAt = session.Runtime.LastCastEndedAt or 0
	if now - lastEndedAt < FishingConfig.CooldownSeconds then
		fail("FishingCooldown")
	end

	local castContext = self:_resolveCastTarget(player, request)
	local castDuration = FormulaUtil.GetRodCastDuration(profile)
	local windowHalfWidth = FormulaUtil.GetFishingWindowHalfWidth(profile)
	local sweetSpot = self.Random:NextNumber(FishingConfig.SweetSpotMin, FishingConfig.SweetSpotMax)
	local rodId = profile.Progression.EquippedRodId
	local fishingSession = {
		Id = IdUtil.GenerateGuid(),
		StartedAt = now,
		SweetSpot = sweetSpot,
		WindowHalfWidth = windowHalfWidth,
		CastDurationSeconds = castDuration,
		RodId = rodId,
		Origin = castContext.Origin,
		TargetPosition = castContext.TargetPosition,
		CastDistance = castContext.CastDistance,
		Source = type(request) == "table" and request.Source or nil,
		Public = {
			Id = nil,
			SweetSpot = sweetSpot,
			WindowHalfWidth = windowHalfWidth,
			CastDurationSeconds = castDuration,
			RodId = rodId,
			Origin = castContext.Origin,
			TargetPosition = castContext.TargetPosition,
			CastDistance = castContext.CastDistance,
			StartedAt = os.time(),
			StartedAtServer = workspace:GetServerTimeNow(),
		},
	}

	fishingSession.Public.Id = fishingSession.Id
	session.Runtime.Fishing = fishingSession
	self:_createCastWorldModel(player, fishingSession)
	self:_scheduleCastTimeout(player, fishingSession.Id, (castDuration * (FishingConfig.MaxHoldRatio or 1.25)) + FishingConfig.ResolveGraceSeconds)
	if profile.Premium.Effects.AutoCatch then
		self:_scheduleAutoCatch(player, fishingSession.Id, castDuration * sweetSpot)
	end

	self.Registry:Get("PlayerDataService"):PublishRuntime(player, "BeginCast", { "Fishing" })

	return fishingSession.Public
end

function FishingService:ResolveActiveCast(player)
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local fishingSession = session.Runtime.Fishing
	if not fishingSession then
		fail("FishingNotActive")
	end

	return self:ResolveCatch(player, fishingSession.Id, os.clock() - fishingSession.StartedAt)
end

function FishingService:ResolveCatch(player, sessionId, holdDurationSeconds)
	local session = self.Registry:Get("PlayerDataService"):GetSession(player)
	local fishingSession = session.Runtime.Fishing
	if not fishingSession then
		fail("FishingNotActive")
	end
	if fishingSession.Id ~= sessionId then
		fail("FishingSessionMismatch")
	end

	local actualDuration = os.clock() - fishingSession.StartedAt
	if math.abs(actualDuration - holdDurationSeconds) > NetworkSchema.FishingRequest.ValidationLeewaySeconds then
		self:CancelCast(player)
		fail("FishingValidationFailed")
	end
	if actualDuration > (fishingSession.CastDurationSeconds * (FishingConfig.MaxHoldRatio or 1.25)) + FishingConfig.ResolveGraceSeconds then
		self:CancelCast(player)
		fail("FishingValidationFailed")
	end

	local profile = session.Profile
	local holdRatio = math.clamp(holdDurationSeconds / fishingSession.CastDurationSeconds, 0, FishingConfig.MaxHoldRatio or 1.25)
	local distanceFromSweetSpot = math.abs(holdRatio - fishingSession.SweetSpot)
	local success = distanceFromSweetSpot <= fishingSession.WindowHalfWidth

	if profile.Premium.Effects.AutoCatch then
		success = true
		holdRatio = fishingSession.SweetSpot
		distanceFromSweetSpot = 0
	end

	if not success then
		self.Registry:Get("PlayerDataService"):MutateProfile(player, "ResolveFishingMiss", {
			"Fishing",
			"Progression",
			"Stats",
			"Leaderstats",
		}, function(runtimeSession, innerProfile)
			self:_finishRuntimeFishing(runtimeSession)
			innerProfile.Progression.ChainBonus = 0
			innerProfile.Stats.FailedCatches += 1
		end)

		return nil, false
	end

	local skillMultiplierBps = 10000
		+ math.floor(math.clamp(holdRatio, 0, 1) * (FishingConfig.MaxSkillBonusBps - 10000))
		+ profile.Progression.ChainBonus
	local rolledCatch = self.Registry:Get("RollService"):RollCatch(profile, skillMultiplierBps)
	local equippedRod = RodConfig.Definitions[profile.Progression.EquippedRodId] or RodConfig.Definitions.StarterRod
	local bonusCatchRoll = nil
	if equippedRod.DoubleCatchChanceBps and self.Random:NextInteger(1, 10000) <= equippedRod.DoubleCatchChanceBps then
		bonusCatchRoll = self.Registry:Get("RollService"):RollCatch(profile, skillMultiplierBps)
	end
	local createdBaddie = nil
	local bonusBaddie = nil

	self.Registry:Get("PlayerDataService"):MutateProfile(player, "ResolveFishingCatch", {
		"Inventory",
		"Dex",
		"Fishing",
		"Progression",
		"Stats",
		"Wallet",
		"Leaderstats",
	}, function(runtimeSession, innerProfile)
		createdBaddie = self.Registry:Get("InventoryService"):AddBaddie(
			innerProfile,
			rolledCatch.TemplateId,
			rolledCatch.RarityId,
			rolledCatch.TraitId,
			"Fishing",
			os.time()
		)
		self.Registry:Get("CollectionService"):RegisterBaddie(innerProfile, createdBaddie)
		innerProfile.Stats.CaughtByRarity[createdBaddie.RarityId] = (innerProfile.Stats.CaughtByRarity[createdBaddie.RarityId] or 0) + 1

		if bonusCatchRoll then
			bonusBaddie = self.Registry:Get("InventoryService"):AddBaddie(
				innerProfile,
				bonusCatchRoll.TemplateId,
				bonusCatchRoll.RarityId,
				bonusCatchRoll.TraitId,
				"FishingBonus",
				os.time()
			)
			self.Registry:Get("CollectionService"):RegisterBaddie(innerProfile, bonusBaddie)
			innerProfile.Stats.CaughtByRarity[bonusBaddie.RarityId] = (innerProfile.Stats.CaughtByRarity[bonusBaddie.RarityId] or 0) + 1
		end

		self:_finishRuntimeFishing(runtimeSession)
		innerProfile.Progression.ChainBonus = math.min(
			FormulaUtil.GetChainBonusCapBps(innerProfile),
			innerProfile.Progression.ChainBonus + FormulaUtil.GetChainBonusGainBps(innerProfile)
		)
		innerProfile.Stats.LifetimeCaught += bonusBaddie and 2 or 1
		innerProfile.Stats.SuccessfulCatches += 1
	end)

	return createdBaddie, true, bonusBaddie
end

function FishingService:CancelCast(player, silent)
	local session = self.Registry:Get("PlayerDataService"):FindSession(player)
	if not session or not session.Runtime.Fishing then
		return
	end

	self:_finishRuntimeFishing(session)

	if not silent then
		self.Registry:Get("PlayerDataService"):PublishRuntime(player, "CancelCast", { "Fishing" })
	end
end

return FishingService
