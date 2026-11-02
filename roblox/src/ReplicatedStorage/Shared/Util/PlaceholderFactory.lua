local PlaceholderFactory = {}

local function setPartDefaults(part, anchored)
	part.Anchored = anchored == true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Massless = not anchored
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function makePart(parent, name, size, cframe, color, material, shape, anchored)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	setPartDefaults(part, anchored)
	part.Parent = parent
	return part
end

local function weldTo(handle, part)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "PlaceholderWeld"
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

local function colorVariant(color, delta)
	return Color3.new(
		math.clamp(color.R + delta, 0, 1),
		math.clamp(color.G + delta, 0, 1),
		math.clamp(color.B + delta, 0, 1)
	)
end

local function getSeed(text)
	local seed = 17
	for index = 1, #text do
		seed = (seed * 31 + string.byte(text, index)) % 2147483647
	end
	return seed
end

-- Temporary, intentionally code-generated baddie. Real models can replace it by
-- adding a model with the matching TemplateId under ReplicatedStorage/Assets/Baddies.
function PlaceholderFactory.CreateBaddie(templateId, displayColor, anchored)
	local random = Random.new(getSeed(templateId))
	local accent = colorVariant(displayColor, 0.18)
	local dark = colorVariant(displayColor, -0.22)
	local model = Instance.new("Model")
	model.Name = templateId
	model:SetAttribute("IsPlaceholder", true)

	local root = makePart(
		model,
		"Root",
		Vector3.new(2.6, 2.9, 1.65),
		CFrame.new(0, 1.6, 0),
		displayColor,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball,
		anchored
	)
	root.Transparency = 0.02
	model.PrimaryPart = root

	local head = makePart(
		model,
		"Head",
		Vector3.new(2.25, 1.95, 1.75),
		CFrame.new(0, 3.25, -0.08),
		accent,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball,
		anchored
	)

	local eyeSpacing = 0.54 + random:NextNumber(-0.08, 0.08)
	for index, x in ipairs({ -eyeSpacing, eyeSpacing }) do
		local eye = makePart(
			model,
			"Eye" .. index,
			Vector3.new(0.38, 0.48, 0.25),
			CFrame.new(x, 3.48, -0.88),
			Color3.fromRGB(248, 251, 255),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			anchored
		)
		local pupil = makePart(
			model,
			"Pupil" .. index,
			Vector3.new(0.16, 0.22, 0.12),
			CFrame.new(x, 3.46, -1.02),
			Color3.fromRGB(24, 28, 38),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			anchored
		)
		if not anchored then
			weldTo(root, eye)
			weldTo(root, pupil)
		end
	end

	local mouth = makePart(
		model,
		"Mouth",
		Vector3.new(0.65, 0.16, 0.13),
		CFrame.new(0, 2.94, -1.01),
		dark,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Block,
		anchored
	)
	mouth.CFrame = mouth.CFrame * CFrame.Angles(0, 0, math.rad(random:NextInteger(-8, 8)))

	local finHeight = random:NextNumber(0.65, 1.05)
	for index, x in ipairs({ -1.42, 1.42 }) do
		local fin = makePart(
			model,
			"Fin" .. index,
			Vector3.new(0.35, finHeight, 1.1),
			CFrame.new(x, 1.7, 0) * CFrame.Angles(0, 0, math.rad(index == 1 and -28 or 28)),
			accent,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Block,
			anchored
		)
		if not anchored then
			weldTo(root, fin)
		end
	end

	for index, x in ipairs({ -0.66, 0.66 }) do
		local foot = makePart(
			model,
			"Foot" .. index,
			Vector3.new(0.78, 0.4, 1.1),
			CFrame.new(x, 0.3, -0.12),
			dark,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			anchored
		)
		if not anchored then
			weldTo(root, foot)
		end
	end

	local crestCount = random:NextInteger(2, 4)
	for index = 1, crestCount do
		local offset = (index - ((crestCount + 1) / 2)) * 0.48
		local crest = makePart(
			model,
			"Crest" .. index,
			Vector3.new(0.28, 0.62 + (index % 2) * 0.2, 0.3),
			CFrame.new(offset, 4.38, 0.02) * CFrame.Angles(0, 0, math.rad(offset * 16)),
			dark,
			Enum.Material.Neon,
			Enum.PartType.Block,
			anchored
		)
		if not anchored then
			weldTo(root, crest)
		end
	end

	if not anchored then
		weldTo(root, head)
		weldTo(root, mouth)
	end

	return model
end

local ROD_COLORS = {
	StarterRod = Color3.fromRGB(169, 113, 64),
	BreezeRod = Color3.fromRGB(96, 225, 204),
	SurgeRod = Color3.fromRGB(62, 149, 255),
	CoralRod = Color3.fromRGB(255, 112, 122),
	FluxRod = Color3.fromRGB(185, 88, 255),
	VoidlineRod = Color3.fromRGB(68, 48, 108),
	LuminRod = Color3.fromRGB(255, 239, 130),
	AurexRod = Color3.fromRGB(255, 184, 44),
	DepthcoreRod = Color3.fromRGB(48, 188, 202),
	EclipseRod = Color3.fromRGB(218, 66, 157),
	PoseidonRod = Color3.fromRGB(54, 215, 255),
	AbyssRod = Color3.fromRGB(91, 48, 161),
	GodRod = Color3.fromRGB(255, 239, 168),
}

function PlaceholderFactory.GetRodColor(rodId)
	return ROD_COLORS[rodId] or ROD_COLORS.StarterRod
end

function PlaceholderFactory.CreateRodParts(tool, rodId)
	local mainColor = PlaceholderFactory.GetRodColor(rodId)
	local accent = colorVariant(mainColor, 0.24)
	local handle = makePart(
		tool,
		"Handle",
		Vector3.new(0.32, 3.8, 0.32),
		CFrame.new(),
		mainColor,
		Enum.Material.Wood,
		Enum.PartType.Cylinder,
		false
	)
	handle.CFrame = CFrame.Angles(0, 0, math.rad(90))

	local grip = makePart(
		tool,
		"Grip",
		Vector3.new(0.54, 1.15, 0.54),
		handle.CFrame * CFrame.new(0, -1.35, 0),
		Color3.fromRGB(40, 44, 52),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder,
		false
	)
	local tip = makePart(
		tool,
		"Tip",
		Vector3.new(0.18, 3.15, 0.18),
		handle.CFrame * CFrame.new(0, 3.25, 0),
		accent,
		Enum.Material.Neon,
		Enum.PartType.Cylinder,
		false
	)
	local reel = makePart(
		tool,
		"Reel",
		Vector3.new(0.9, 0.9, 0.38),
		handle.CFrame * CFrame.new(0.58, -0.72, 0),
		accent,
		Enum.Material.Metal,
		Enum.PartType.Cylinder,
		false
	)

	weldTo(handle, grip)
	weldTo(handle, tip)
	weldTo(handle, reel)

	local lineAttachment = Instance.new("Attachment")
	lineAttachment.Name = "LineAttachment"
	lineAttachment.Position = Vector3.new(0, 1.5, 0)
	lineAttachment.Parent = tip

	return handle
end

return PlaceholderFactory
