local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BaddieConfig = require(Shared.Config.BaddieConfig)
local FormulaUtil = require(Shared.Util.FormulaUtil)
local PlotConfig = require(Shared.Config.PlotConfig)
local RarityConfig = require(Shared.Config.RarityConfig)

local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

local PlotScreen = {
	Network = nil,
	ReplicaClient = nil,
	ShopScreen = nil,
	Replica = nil,
	Gui = nil,
	Panel = nil,
	Content = nil,
	HeldLabel = nil,
	ActionLabel = nil,
	InspectPanel = nil,
	CurrentCellPart = nil,
	CurrentCellData = nil,
	Highlight = nil,
}

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function addCorner(parent, radius)
	create("UICorner", {
		CornerRadius = UDim.new(0, radius or 6),
	}, parent)
end

local function addStroke(parent, color, transparency)
	create("UIStroke", {
		Color = color or Color3.fromRGB(72, 84, 102),
		Transparency = transparency or 0,
		Thickness = 1,
	}, parent)
end

local function formatNumber(value)
	value = math.floor(tonumber(value) or 0)
	local text = tostring(value)
	local left, num, right = string.match(text, "^([^%d]*%d)(%d*)(.-)$")
	return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

local function clearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function getBaddieName(baddie)
	local definition = baddie and BaddieConfig.Definitions[baddie.TemplateId]
	return definition and definition.DisplayName or (baddie and baddie.TemplateId) or "Unknown"
end

local function getTraitText(baddie)
	local traits = {}
	for _, traitId in ipairs((baddie and baddie.TraitIds) or {}) do
		if traitId and traitId ~= "None" then
			table.insert(traits, traitId)
		end
	end

	if #traits == 0 then
		return "No trait"
	end

	return table.concat(traits, ", ")
end

function PlotScreen:MakeText(parent, text, size, color, bold)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		Text = text,
		TextColor3 = color or Color3.fromRGB(233, 238, 245),
		TextSize = size or 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 20),
	}, parent)
end

function PlotScreen:MakeButton(parent, text, disabled, callback)
	local button = create("TextButton", {
		AutoButtonColor = not disabled,
		BackgroundColor3 = disabled and Color3.fromRGB(63, 70, 82) or Color3.fromRGB(41, 132, 255),
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = disabled and Color3.fromRGB(168, 176, 188) or Color3.fromRGB(255, 255, 255),
		TextSize = 13,
		TextWrapped = true,
		Size = UDim2.fromOffset(118, 34),
	}, parent)
	addCorner(button, 6)

	if not disabled and callback then
		button.Activated:Connect(callback)
	end

	return button
end

function PlotScreen:BuildGui()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = create("ScreenGui", {
		Name = "FishABaddiePlot",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Enabled = true,
	}, playerGui)
	self.Gui = gui

	local openButton = self:MakeButton(gui, "Baddies", false, function()
		self:Toggle()
	end)
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 18, 1, -18)
	openButton.Size = UDim2.fromOffset(116, 38)

	local panel = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 25, 34),
		Position = UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.fromOffset(430, 560),
		Visible = false,
	}, gui)
	self.Panel = panel
	addCorner(panel, 8)
	addStroke(panel, Color3.fromRGB(74, 88, 108), 0)

	local topBar = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(25, 32, 43),
		Size = UDim2.new(1, 0, 0, 58),
	}, panel)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
	}, topBar)

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Plot",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -48, 1, -10),
	}, topBar)

	local close = self:MakeButton(topBar, "X", false, function()
		self:Close()
	end)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(34, 34)

	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
	}, panel)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 14),
	}, body)
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, body)

	self.HeldLabel = self:MakeText(body, "Holding: none", 14, Color3.fromRGB(191, 205, 222), false)

	local actions = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 38),
	}, body)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, actions)
	self:MakeButton(actions, "Put Away", false, function()
		self.Network:SendPlacement({ Action = "ClearHeldBaddie" })
	end)
	self:MakeButton(actions, "Plot Shop", false, function()
		self:OpenPlotShop()
	end)

	self.Content = create("ScrollingFrame", {
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarImageColor3 = Color3.fromRGB(92, 110, 136),
		ScrollBarThickness = 6,
		Size = UDim2.new(1, 0, 1, -82),
	}, body)
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, self.Content)

	self.ActionLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(15, 20, 28),
		BackgroundTransparency = 0.1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(260, 42),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		TextWrapped = true,
		Visible = false,
	}, gui)
	addCorner(self.ActionLabel, 7)
	addStroke(self.ActionLabel, Color3.fromRGB(86, 104, 130), 0.1)

	self.Highlight = Instance.new("SelectionBox")
	self.Highlight.Name = "PlotCellHighlight"
	self.Highlight.LineThickness = 0.06
	self.Highlight.SurfaceTransparency = 0.75
	self.Highlight.Visible = false
	self.Highlight.Parent = Workspace

	self:BuildInspectPanel(gui)
end

function PlotScreen:BuildInspectPanel(gui)
	local panel = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 25, 34),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(320, 210),
		Visible = false,
	}, gui)
	self.InspectPanel = panel
	addCorner(panel, 8)
	addStroke(panel, Color3.fromRGB(74, 88, 108), 0)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 14),
	}, panel)
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, panel)

	self.InspectTitle = self:MakeText(panel, "", 18, Color3.fromRGB(255, 255, 255), true)
	self.InspectBody = self:MakeText(panel, "", 14, Color3.fromRGB(190, 205, 222), false)
	self:MakeButton(panel, "Close", false, function()
		self.InspectPanel.Visible = false
	end)
end

function PlotScreen:Open()
	self.Panel.Visible = true
	self:Render()
end

function PlotScreen:Close()
	self.Panel.Visible = false
end

function PlotScreen:Toggle()
	if self.Panel.Visible then
		self:Close()
	else
		self:Open()
	end
end

function PlotScreen:OpenPlotShop()
	if self.ShopScreen and self.ShopScreen.OpenForShop then
		self.ShopScreen:OpenForShop("PlotShop", "Plot Shop")
	end
end

function PlotScreen:GetHeldBaddie()
	local heldId = self.Replica and self.Replica.Plot and self.Replica.Plot.HeldBaddieId
	return heldId, heldId and self.Replica.Inventory and self.Replica.Inventory.Baddies[heldId] or nil
end

function PlotScreen:RenderRow(parent, baddie)
	local row = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(31, 38, 50),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -8, 0, 0),
	}, parent)
	addCorner(row, 6)
	addStroke(row, Color3.fromRGB(57, 68, 84), 0.1)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
	}, row)

	local line = create("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	}, row)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, line)

	local textColumn = create("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -132, 0, 0),
	}, line)
	create("UIListLayout", {
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, textColumn)

	local rarityColor = RarityConfig.RewardColors[baddie.RarityId] or Color3.fromRGB(245, 248, 252)
	self:MakeText(textColumn, getBaddieName(baddie), 15, rarityColor, true)
	local income = 0
	if self.Replica then
		income = FormulaUtil.GetBaddieIncomePerSecond(baddie, self.Replica)
	end

	local heldId = self.Replica and self.Replica.Plot and self.Replica.Plot.HeldBaddieId
	local status = baddie.State or "Inventory"
	if heldId == baddie.Id then
		status = "Held"
	end

	self:MakeText(
		textColumn,
		string.format("%s | Lv.%d | %s | %.1f coins/s", status, baddie.Level or 1, getTraitText(baddie), income),
		13,
		Color3.fromRGB(176, 187, 201),
		false
	)

	local disabled = false
	local buttonText = "Hold"
	local callback = function()
		self.Network:SendPlacement({ Action = "HoldBaddie", BaddieId = baddie.Id })
	end

	if heldId == baddie.Id then
		buttonText = "Put Away"
		callback = function()
			self.Network:SendPlacement({ Action = "ClearHeldBaddie" })
		end
	elseif status == "Placed" then
		buttonText = "Move"
	elseif status == "Locked" then
		buttonText = "Locked"
		disabled = true
	end

	self:MakeButton(line, buttonText, disabled, callback)
end

function PlotScreen:Render()
	local replica = self.Replica
	if not replica or not self.Content then
		return
	end

	local heldId, heldBaddie = self:GetHeldBaddie()
	self.HeldLabel.Text = heldBaddie and ("Holding: " .. getBaddieName(heldBaddie)) or "Holding: none"

	clearChildren(self.Content)

	local order = replica.Inventory and replica.Inventory.Order or {}
	local baddies = replica.Inventory and replica.Inventory.Baddies or {}
	if #order == 0 then
		self:MakeText(self.Content, "No baddies in inventory.", 14, Color3.fromRGB(176, 187, 201), false)
		return
	end

	for _, baddieId in ipairs(order) do
		local baddie = baddies[baddieId]
		if baddie then
			self:RenderRow(self.Content, baddie)
		end
	end
end

function PlotScreen:GetOwnCellsFolder()
	local plotId = self.Replica and self.Replica.Plot and self.Replica.Plot.PlotId
	if not plotId then
		return nil
	end

	local gameFolder = Workspace:FindFirstChild("Game")
	local plotModels = gameFolder and gameFolder:FindFirstChild("PlotModels")
	local plotFolder = plotModels and plotModels:FindFirstChild(plotId)
	return plotFolder and plotFolder:FindFirstChild("Cells")
end

function PlotScreen:UpdateCellHighlight()
	local cellsFolder = self:GetOwnCellsFolder()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not cellsFolder or not root then
		self.CurrentCellPart = nil
		self.CurrentCellData = nil
		self.Highlight.Visible = false
		self.ActionLabel.Visible = false
		return
	end

	local bestPart = nil
	local bestDistance = PlotConfig.InteractionDistance
	for _, child in ipairs(cellsFolder:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("IsPlotCell") == true then
			local distance = (root.Position - child.Position).Magnitude
			if distance <= bestDistance then
				bestDistance = distance
				bestPart = child
			end
		end
	end

	self.CurrentCellPart = bestPart
	if not bestPart then
		self.CurrentCellData = nil
		self.Highlight.Visible = false
		self.ActionLabel.Visible = false
		return
	end

	local cellKey = bestPart:GetAttribute("CellKey")
	local plotState = self.Replica and self.Replica.Plot or {}
	local cellData = plotState.Cells and plotState.Cells[cellKey]
	self.CurrentCellData = cellData

	local heldId = plotState.HeldBaddieId
	local occupiedId = cellData and cellData.OccupiedBaddieId
	local unlocked = cellData and cellData.Unlocked == true
	local actionText = "Empty Cell"
	local color = Color3.fromRGB(96, 255, 147)

	if not unlocked then
		actionText = "E  Plot Shop"
		color = Color3.fromRGB(255, 210, 88)
	elseif heldId and not occupiedId then
		actionText = "E  Place"
		color = Color3.fromRGB(96, 255, 147)
	elseif heldId and occupiedId then
		actionText = "Occupied"
		color = Color3.fromRGB(255, 112, 112)
	elseif occupiedId then
		actionText = "E  Pick Up"
		color = Color3.fromRGB(102, 204, 255)
	end

	self.Highlight.Adornee = bestPart
	self.Highlight.Color3 = color
	self.Highlight.Visible = true
	self.ActionLabel.Text = actionText
	self.ActionLabel.TextColor3 = color
	self.ActionLabel.Visible = true
end

function PlotScreen:ExecuteCellAction()
	local cellData = self.CurrentCellData
	if not cellData then
		return
	end

	local plotState = self.Replica and self.Replica.Plot or {}
	local heldId = plotState.HeldBaddieId
	local occupiedId = cellData.OccupiedBaddieId

	if cellData.Unlocked ~= true then
		self:OpenPlotShop()
	elseif heldId and not occupiedId then
		self.Network:SendPlacement({
			Action = "PlaceHeld",
			GridX = cellData.GridX,
			GridY = cellData.GridY,
		})
	elseif not heldId and occupiedId then
		self.Network:SendPlacement({
			Action = "PickupCell",
			GridX = cellData.GridX,
			GridY = cellData.GridY,
		})
	end
end

function PlotScreen:FindBaddieVisual(target)
	local cursor = target
	while cursor and cursor ~= Workspace do
		if cursor:GetAttribute("BaddieId") then
			return cursor
		end
		cursor = cursor.Parent
	end

	return nil
end

function PlotScreen:InspectTarget(target)
	local visual = self:FindBaddieVisual(target)
	if not visual then
		return
	end

	local ownerName = visual:GetAttribute("OwnerName") or "Unknown"
	local baddieName = visual:GetAttribute("BaddieName") or visual:GetAttribute("TemplateId") or "Unknown"
	local rarityId = visual:GetAttribute("RarityId") or "Unknown"
	local level = visual:GetAttribute("Level") or 1
	local traitSummary = visual:GetAttribute("TraitSummary") or "No trait"
	local income = visual:GetAttribute("IncomePerSecond") or 0

	self.InspectTitle.Text = baddieName
	self.InspectTitle.TextColor3 = RarityConfig.RewardColors[rarityId] or Color3.fromRGB(255, 255, 255)
	self.InspectBody.Text = string.format(
		"Owner: %s\nRarity: %s\nLevel: %s\nTraits: %s\nIncome: %.1f coins/s",
		ownerName,
		rarityId,
		tostring(level),
		traitSummary,
		income
	)
	self.InspectPanel.Visible = true
end

function PlotScreen:BindInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.B and not gameProcessed then
			self:Toggle()
		elseif input.KeyCode == Enum.KeyCode.E and not gameProcessed then
			self:ExecuteCellAction()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not gameProcessed then
			self:InspectTarget(mouse.Target)
		end
	end)

	RunService.RenderStepped:Connect(function()
		self:UpdateCellHighlight()
	end)
end

function PlotScreen:Init(network, replicaClient, shopScreen)
	self.Network = network
	self.ReplicaClient = replicaClient
	self.ShopScreen = shopScreen
	self:BuildGui()

	self.Replica = replicaClient:Get()
	replicaClient:Subscribe(function(replica)
		self.Replica = replica
		if self.Panel.Visible then
			self:Render()
		end
	end)

	self:BindInput()
	self:Render()
end

return PlotScreen
