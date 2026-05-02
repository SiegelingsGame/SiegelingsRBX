--[[
	CodexClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
	Dual-mode Codex: (1) Details view for one creature, (2) Visual Codex grid/gallery.
	Open via OpenCodex(creatureId). All creature clicks route through OpenCodex.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local CodexModelViewer = nil
if GameConfig.ENABLE_CODEX_3D_VIEWER then
	local modScript = ReplicatedStorage.Modules:FindFirstChild("CodexModelViewer")
	if modScript then
		local ok, mod = pcall(function() return require(modScript) end)
		if ok and mod and type(mod.new) == "function" then CodexModelViewer = mod end
	end
end

if not GameConfig.ENABLE_CODEX_UI then
	local evt = Instance.new("BindableEvent")
	evt.Name = "OpenCodex"
	evt.Parent = playerGui
	evt.Event:Connect(function() end)
	return
end

-- Controller state
local currentCreatureId = nil
local currentMode = "DETAILS" -- "GUIDE" | "LORE" | "DETAILS" | "VISUAL"
local guideViewMode = "OVERVIEW" -- "OVERVIEW" | "ADVANCED"
local visualScrollPosition = 0
local seenCreatureIds = {} -- [id] = true (ever opened in codex)
local ownedCreatureIds = {} -- [id] = true (from GetInventory)
local filteredCreatures = {} -- cached list for Visual grid
local filterElement = nil   -- nil = All
local filterRarity = nil
local filterSearch = ""
local showCreature -- forward declaration (used by switchToDetails before definition)

-- Colors
local C = {
	bg = Color3.fromRGB(14, 16, 24),
	card = Color3.fromRGB(22, 26, 38),
	text = Color3.fromRGB(240, 240, 245),
	textSec = Color3.fromRGB(140, 145, 160),
	muted = Color3.fromRGB(100, 105, 120),
	accent = Color3.fromRGB(100, 180, 255),
	red = Color3.fromRGB(255, 70, 60),
	white = Color3.new(1, 1, 1),
}

-- Egg placeholder shown in Visual Codex for uncaught creatures.
-- Replace with your uploaded screenshot asset id to match exactly:
-- e.g. CODEX_EGG_PLACEHOLDER_IMAGE_ID = "rbxassetid://1234567890"fgv
local CODEX_EGG_PLACEHOLDER_IMAGE_ID = "" -- TODO
local CODEX_EGG_BACKDROP = Color3.fromRGB(235, 225, 180)
local CODEX_EGG_BORDER = Color3.fromRGB(255, 200, 80)

-- Panel scaling: wider so filters/dropdowns/buttons fit; on mobile use most of viewport
local PANEL_DESIGN_W = 640
local PANEL_DESIGN_H = 620
local PANEL_SCALE_MIN = 0.5
local PANEL_SCALE_MAX = 1
local MOBILE_BREAKPOINT = 620

local function isMobileLayout()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	return MobileWindowLayout.IsMobile() or vp.X < MOBILE_BREAKPOINT or vp.Y < 500
end

-- Match InventoryUI / profile: full bleed GetBounds (vertical extend, no hub gap).
local function codexUsesFullscreenBounds()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	if isMobileLayout() then
		return true
	end
	return vp.X < PANEL_DESIGN_W or vp.Y < PANEL_DESIGN_H
end

local function codexGetBoundsConfig()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local compactViewport = vp.X < PANEL_DESIGN_W or vp.Y < PANEL_DESIGN_H
	local boundsConfig = {
		extendViewportVertically = true,
		reserveBottomHubGap = false,
		bottomMobileExtra = 0,
		topInset = 0,
		bottomInset = 0,
		mobileDraggable = false,
	}
	if compactViewport and not isMobileLayout() then
		boundsConfig.useMaximalSafeRect = true
	end
	return boundsConfig
end

local function getPanelScale()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local scale = math.min(vp.X / PANEL_DESIGN_W, vp.Y / PANEL_DESIGN_H)
	return math.clamp(scale, PANEL_SCALE_MIN, PANEL_SCALE_MAX)
end

-- Ordered creature list for next/prev
local allCreatures = CreatureData.GetAll()
local function indexOfCreature(creatureId)
	for i, c in ipairs(allCreatures) do
		if c.id == creatureId then return i end
	end
	return nil
end

-- ScreenGui
local sg = Instance.new("ScreenGui")
sg.Name = "CodexGUI"
sg.ResetOnSpawn = false
-- Must render above HUD elements (battle menu / recard / melee / sprint) and other menus.
sg.DisplayOrder = 200
sg.ZIndexBehavior = Enum.ZIndexBehavior.Global
sg.Parent = playerGui

local function syncCodexScreenGuiInset()
	if codexUsesFullscreenBounds() then
		sg.IgnoreGuiInset = true
	else
		sg.IgnoreGuiInset = false
	end
end

local applyCodexTitleLayout = nil

local function applyPanelScale(pnl)
	syncCodexScreenGuiInset()
	if codexUsesFullscreenBounds() then
		MobileWindowLayout.ApplyWindow(pnl, codexGetBoundsConfig())
		pnl.Draggable = false
	else
		pnl.AnchorPoint = Vector2.new(0, 0)
		local scale = getPanelScale()
		local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
		pnl.Size = UDim2.new(0, w, 0, h)
		pnl.Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2)
		MobileWindowLayout.RestoreDesktopWindow(pnl, { draggable = true })
	end
	if applyCodexTitleLayout then
		applyCodexTitleLayout()
	end
end

-- Main panel
local panel = Instance.new("Frame")
panel.Name = "CodexPanel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
panel.BackgroundColor3 = C.bg
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = true
panel.Draggable = true
panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(60, 100, 140)
stroke.Thickness = 2

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -50, 1, 0)
titleLbl.Position = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "CODEX"
titleLbl.TextColor3 = C.accent
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 18
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = titleBar
applyCodexTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(titleLbl, {
	Position = UDim2.new(0, 14, 0, 0),
	Size = UDim2.new(1, -50, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 6)
closeBtn.BackgroundColor3 = C.red
closeBtn.BackgroundTransparency = 0.5
closeBtn.Text = GameConfig.UICloseGlyph or "X"
closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	MobileWindowLayout.NotifyMenuClosed()
end)

-- Tab bar: Guide | Lore | Details | Visual
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -20, 0, 32)
tabBar.Position = UDim2.new(0, 10, 0, 48)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel

local guideTab = Instance.new("TextButton")
guideTab.Size = UDim2.new(0.25, -4, 1, 0)
guideTab.Position = UDim2.new(0, 0, 0, 0)
guideTab.Text = "Guide"
guideTab.Font = Enum.Font.GothamBold
guideTab.TextSize = 10
guideTab.BorderSizePixel = 0
guideTab.Parent = tabBar
Instance.new("UICorner", guideTab).CornerRadius = UDim.new(0, 6)

local loreTab = Instance.new("TextButton")
loreTab.Size = UDim2.new(0.25, -4, 1, 0)
loreTab.Position = UDim2.new(0.25, 2, 0, 0)
loreTab.Text = "Lore"
loreTab.Font = Enum.Font.GothamBold
loreTab.TextSize = 10
loreTab.BorderSizePixel = 0
loreTab.Parent = tabBar
Instance.new("UICorner", loreTab).CornerRadius = UDim.new(0, 6)

local detailsTab = Instance.new("TextButton")
detailsTab.Size = UDim2.new(0.25, -4, 1, 0)
detailsTab.Position = UDim2.new(0.5, 2, 0, 0)
detailsTab.Text = "Details"
detailsTab.Font = Enum.Font.GothamBold
detailsTab.TextSize = 10
detailsTab.BorderSizePixel = 0
detailsTab.Parent = tabBar
Instance.new("UICorner", detailsTab).CornerRadius = UDim.new(0, 6)

local visualTab = Instance.new("TextButton")
visualTab.Size = UDim2.new(0.25, -4, 1, 0)
visualTab.Position = UDim2.new(0.75, 2, 0, 0)
visualTab.Text = "Visual"
visualTab.Font = Enum.Font.GothamBold
visualTab.TextSize = 10
visualTab.BorderSizePixel = 0
visualTab.Parent = tabBar
Instance.new("UICorner", visualTab).CornerRadius = UDim.new(0, 6)

-- Details content container (visible when mode == DETAILS)
local detailsContent = Instance.new("Frame")
detailsContent.Name = "DetailsContent"
detailsContent.Size = UDim2.new(1, -20, 1, -90)
detailsContent.Position = UDim2.new(0, 10, 0, 82)
detailsContent.BackgroundTransparency = 1
detailsContent.Parent = panel

-- Content area (scrollable) - details view (nav bar is fixed below, so scroll doesn't need to extend past content)
local NAV_BAR_HEIGHT = 56
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -50 - NAV_BAR_HEIGHT)
scroll.Position = UDim2.new(0, 10, 0, 50)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = C.muted
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = detailsContent

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 8)
contentLayout.Parent = scroll

-- Reusable content holders (we rebuild text when opening)
local previewFrame = Instance.new("Frame")
previewFrame.Name = "Preview"
previewFrame.Size = UDim2.new(1, 0, 0, 196)
previewFrame.BackgroundColor3 = C.card
previewFrame.BorderSizePixel = 0
previewFrame.LayoutOrder = 3
previewFrame.Parent = scroll
Instance.new("UICorner", previewFrame).CornerRadius = UDim.new(0, 10)

-- 3D viewer container (ModelViewer or placeholder lives here)
local previewViewportContainer = Instance.new("Frame")
previewViewportContainer.Name = "ViewportContainer"
previewViewportContainer.Size = UDim2.new(1, 0, 0, 156)
previewViewportContainer.BackgroundTransparency = 1
previewViewportContainer.Parent = previewFrame

local previewPlaceholder = Instance.new("Frame")
previewPlaceholder.Name = "Placeholder"
previewPlaceholder.Size = UDim2.new(0, 120, 0, 120)
previewPlaceholder.Position = UDim2.new(0.5, -60, 0.5, -60)
previewPlaceholder.BackgroundColor3 = Color3.fromRGB(60, 65, 80)
previewPlaceholder.BorderSizePixel = 0
previewPlaceholder.Parent = previewFrame
Instance.new("UICorner", previewPlaceholder).CornerRadius = UDim.new(1, 0)

local previewLabel = Instance.new("TextLabel")
previewLabel.Size = UDim2.new(1, -20, 0, 24)
previewLabel.Position = UDim2.new(0, 10, 0, 8)
previewLabel.BackgroundTransparency = 1
previewLabel.Text = "Preview"
previewLabel.TextColor3 = C.textSec
previewLabel.Font = Enum.Font.GothamMedium
previewLabel.TextSize = 11
previewLabel.TextXAlignment = Enum.TextXAlignment.Left
previewLabel.Parent = previewFrame

-- Load by Asset ID controls (3D viewer only)
local customModelControls = Instance.new("Frame")
customModelControls.Name = "CustomModelControls"
customModelControls.Size = UDim2.new(1, -20, 0, 32)
customModelControls.Position = UDim2.new(0, 10, 0, 162)
customModelControls.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
customModelControls.BorderSizePixel = 0
customModelControls.Visible = false
customModelControls.Parent = previewFrame
Instance.new("UICorner", customModelControls).CornerRadius = UDim.new(0, 6)

local idLabel = Instance.new("TextLabel")
idLabel.Size = UDim2.new(0, 65, 1, 0)
idLabel.BackgroundTransparency = 1
idLabel.Text = "Model ID:"
idLabel.TextColor3 = C.textSec
idLabel.Font = Enum.Font.GothamMedium
idLabel.TextSize = 10
idLabel.TextXAlignment = Enum.TextXAlignment.Right
idLabel.Parent = customModelControls

local assetIdBox = Instance.new("TextBox")
assetIdBox.Size = UDim2.new(0, 180, 0, 24)
assetIdBox.Position = UDim2.new(0, 72, 0.5, -12)
assetIdBox.BackgroundColor3 = Color3.fromRGB(55, 58, 70)
assetIdBox.Text = ""
assetIdBox.PlaceholderText = "Enter asset ID (e.g. 257489726)"
assetIdBox.TextColor3 = C.text
assetIdBox.Font = Enum.Font.Gotham
assetIdBox.TextSize = 10
assetIdBox.ClearTextOnFocus = false
assetIdBox.Parent = customModelControls
Instance.new("UICorner", assetIdBox).CornerRadius = UDim.new(0, 4)

local loadModelBtn = Instance.new("TextButton")
loadModelBtn.Size = UDim2.new(0, 80, 0, 24)
loadModelBtn.Position = UDim2.new(0, 258, 0.5, -12)
loadModelBtn.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
loadModelBtn.Text = "Load Model"
loadModelBtn.TextColor3 = C.white
loadModelBtn.Font = Enum.Font.GothamBold
loadModelBtn.TextSize = 10
loadModelBtn.BorderSizePixel = 0
loadModelBtn.Parent = customModelControls
Instance.new("UICorner", loadModelBtn).CornerRadius = UDim.new(0, 4)

loadModelBtn.MouseButton1Click:Connect(function()
	if not detailsModelViewer or not detailsModelViewer.LoadModelByAssetId then return end
	local id = assetIdBox.Text and assetIdBox.Text:match("%d+")
	if id then
		local ok = detailsModelViewer:LoadModelByAssetId(id)
		if not ok then warn("[Codex] Failed to load model with ID: " .. id) end
	end
end)

local detailsModelViewer = nil -- created when first showing details with 3D enabled
local detailsSnapshotImg = nil -- ImageLabel from CaptureSnapshotAsync (static fallback)
local ENABLE_CODEX_SNAPSHOT_FALLBACK = false -- keep live ViewportFrame visible by default

local nameLbl = Instance.new("TextLabel")
nameLbl.Name = "Name"
nameLbl.Size = UDim2.new(1, -20, 0, 26)
nameLbl.Position = UDim2.new(0, 10, 0, 0)
nameLbl.BackgroundTransparency = 1
nameLbl.Text = ""
nameLbl.TextColor3 = C.text
nameLbl.Font = Enum.Font.GothamBlack
nameLbl.TextSize = 20
nameLbl.TextXAlignment = Enum.TextXAlignment.Left
nameLbl.LayoutOrder = 1
nameLbl.Parent = scroll

local metaLbl = Instance.new("TextLabel")
metaLbl.Name = "Meta"
metaLbl.Size = UDim2.new(1, -20, 0, 20)
metaLbl.BackgroundTransparency = 1
metaLbl.Text = ""
metaLbl.TextColor3 = C.textSec
metaLbl.Font = Enum.Font.GothamMedium
metaLbl.TextSize = 12
metaLbl.TextXAlignment = Enum.TextXAlignment.Left
metaLbl.TextWrapped = true
metaLbl.LayoutOrder = 2
metaLbl.Parent = scroll

local descLbl = Instance.new("TextLabel")
descLbl.Name = "Desc"
descLbl.Size = UDim2.new(1, -20, 0, 50)
descLbl.BackgroundTransparency = 1
descLbl.Text = ""
descLbl.TextColor3 = C.textSec
descLbl.Font = Enum.Font.GothamMedium
descLbl.TextSize = 12
descLbl.TextXAlignment = Enum.TextXAlignment.Left
descLbl.TextWrapped = true
descLbl.AutomaticSize = Enum.AutomaticSize.Y
descLbl.LayoutOrder = 4
descLbl.Parent = scroll

local statsLbl = Instance.new("TextLabel")
statsLbl.Name = "Stats"
statsLbl.Size = UDim2.new(1, -20, 0, 60)
statsLbl.BackgroundTransparency = 1
statsLbl.Text = ""
statsLbl.TextColor3 = C.text
statsLbl.Font = Enum.Font.GothamMedium
statsLbl.TextSize = 12
statsLbl.TextXAlignment = Enum.TextXAlignment.Left
statsLbl.TextWrapped = true
statsLbl.AutomaticSize = Enum.AutomaticSize.Y
statsLbl.LayoutOrder = 5
statsLbl.Parent = scroll

local abilitiesLbl = Instance.new("TextLabel")
abilitiesLbl.Name = "Abilities"
abilitiesLbl.Size = UDim2.new(1, -20, 0, 40)
abilitiesLbl.BackgroundTransparency = 1
abilitiesLbl.Text = ""
abilitiesLbl.TextColor3 = C.textSec
abilitiesLbl.Font = Enum.Font.GothamMedium
abilitiesLbl.TextSize = 11
abilitiesLbl.TextXAlignment = Enum.TextXAlignment.Left
abilitiesLbl.TextWrapped = true
abilitiesLbl.AutomaticSize = Enum.AutomaticSize.Y
abilitiesLbl.LayoutOrder = 6
abilitiesLbl.Parent = scroll

-- Nav bar (fixed at bottom of Details so always visible; not inside scroll)
local navFrame = Instance.new("Frame")
navFrame.Size = UDim2.new(1, -20, 0, NAV_BAR_HEIGHT)
navFrame.Position = UDim2.new(0, 10, 1, -NAV_BAR_HEIGHT)
navFrame.BackgroundTransparency = 1
navFrame.Parent = detailsContent

local prevBtn = Instance.new("TextButton")
prevBtn.Size = UDim2.new(0, 100, 0, 28)
prevBtn.Position = UDim2.new(0, 0, 0, 0)
prevBtn.BackgroundColor3 = C.card
prevBtn.Text = "← Previous"
prevBtn.TextColor3 = C.text
prevBtn.Font = Enum.Font.GothamBold
prevBtn.TextSize = 11
prevBtn.BorderSizePixel = 0
prevBtn.Parent = navFrame
Instance.new("UICorner", prevBtn).CornerRadius = UDim.new(0, 6)

local nextBtn = Instance.new("TextButton")
nextBtn.Size = UDim2.new(0, 100, 0, 28)
nextBtn.Position = UDim2.new(1, -100, 0, 0)
nextBtn.BackgroundColor3 = C.card
nextBtn.Text = "Next →"
nextBtn.TextColor3 = C.text
nextBtn.Font = Enum.Font.GothamBold
nextBtn.TextSize = 11
nextBtn.BorderSizePixel = 0
nextBtn.Parent = navFrame
Instance.new("UICorner", nextBtn).CornerRadius = UDim.new(0, 6)

local visualCodexBtn = Instance.new("TextButton")
visualCodexBtn.Size = UDim2.new(0, 120, 0, 28)
visualCodexBtn.Position = UDim2.new(0.5, -60, 0, 28)
visualCodexBtn.BackgroundColor3 = C.accent
visualCodexBtn.Text = "Visual Codex"
visualCodexBtn.TextColor3 = C.white
visualCodexBtn.Font = Enum.Font.GothamBold
visualCodexBtn.TextSize = 10
visualCodexBtn.BorderSizePixel = 0
visualCodexBtn.Parent = navFrame
Instance.new("UICorner", visualCodexBtn).CornerRadius = UDim.new(0, 6)

-- Build a scrollable book with chapter quick-links. Returns { scrollFrame, sectionOffsets } and fills scrollOffsets when layout is ready.
local function buildBookView(parent, sections, isLore)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = parent

	local listFrame = Instance.new("Frame")
	listFrame.Size = UDim2.new(1, 0, 0, 62)
	listFrame.BackgroundColor3 = C.card
	listFrame.BorderSizePixel = 0
	listFrame.Parent = container
	Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 8)

	local listLabel = Instance.new("TextLabel")
	listLabel.Size = UDim2.new(1, -12, 0, 18)
	listLabel.Position = UDim2.new(0, 6, 0, 6)
	listLabel.BackgroundTransparency = 1
	listLabel.Text = isLore and "Lore chapters" or "Advanced guide"
	listLabel.TextColor3 = C.text
	listLabel.Font = Enum.Font.GothamBold
	listLabel.TextSize = 11
	listLabel.TextXAlignment = Enum.TextXAlignment.Left
	listLabel.Parent = listFrame

	local listScroll = Instance.new("ScrollingFrame")
	listScroll.Size = UDim2.new(1, -12, 0, 28)
	listScroll.Position = UDim2.new(0, 6, 0, 28)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 4
	listScroll.ScrollBarImageColor3 = C.muted
	listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	listScroll.ScrollingDirection = Enum.ScrollingDirection.X
	listScroll.Parent = listFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Parent = listScroll

	local listPad = Instance.new("UIPadding", listScroll)
	listPad.PaddingRight = UDim.new(0, 6)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -70)
	scroll.Position = UDim2.new(0, 0, 0, 70)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = C.muted
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = container

	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -6, 0, 0)
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = scroll

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 10)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	local contentPad = Instance.new("UIPadding", content)
	contentPad.PaddingLeft = UDim.new(0, 2)
	contentPad.PaddingRight = UDim.new(0, 6)
	contentPad.PaddingTop = UDim.new(0, 2)
	contentPad.PaddingBottom = UDim.new(0, 12)

	local sectionFrames = {}
	local sectionOffsets = {}
	for i, sec in ipairs(sections) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 128, 0, 28)
		btn.LayoutOrder = i
		btn.Text = sec.title
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 10
		btn.TextColor3 = C.text
		btn.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
		btn.BorderSizePixel = 0
		btn.TextXAlignment = Enum.TextXAlignment.Center
		btn.Parent = listScroll
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		btn.TextTruncate = Enum.TextTruncate.AtEnd

		local secFrame = Instance.new("Frame")
		secFrame.Size = UDim2.new(1, 0, 0, 0)
		secFrame.BackgroundColor3 = C.card
		secFrame.BorderSizePixel = 0
		secFrame.LayoutOrder = i
		secFrame.AutomaticSize = Enum.AutomaticSize.Y
		secFrame.Parent = content
		Instance.new("UICorner", secFrame).CornerRadius = UDim.new(0, 8)

		local secLayout = Instance.new("UIListLayout")
		secLayout.Padding = UDim.new(0, 6)
		secLayout.SortOrder = Enum.SortOrder.LayoutOrder
		secLayout.Parent = secFrame

		local secPad = Instance.new("UIPadding", secFrame)
		secPad.PaddingLeft = UDim.new(0, 12)
		secPad.PaddingRight = UDim.new(0, 12)
		secPad.PaddingTop = UDim.new(0, 10)
		secPad.PaddingBottom = UDim.new(0, 12)

		local secTitle = Instance.new("TextLabel")
		secTitle.Size = UDim2.new(1, 0, 0, 0)
		secTitle.BackgroundTransparency = 1
		secTitle.AutomaticSize = Enum.AutomaticSize.Y
		secTitle.Text = sec.title
		secTitle.TextColor3 = C.text
		secTitle.Font = Enum.Font.GothamBold
		secTitle.TextSize = isLore and 13 or 14
		secTitle.TextWrapped = true
		secTitle.TextXAlignment = Enum.TextXAlignment.Left
		secTitle.TextYAlignment = Enum.TextYAlignment.Top
		secTitle.Parent = secFrame

		local secLbl = Instance.new("TextLabel")
		secLbl.Size = UDim2.new(1, 0, 0, 0)
		secLbl.BackgroundTransparency = 1
		secLbl.Text = sec.text
		secLbl.TextColor3 = C.textSec
		secLbl.Font = Enum.Font.SourceSans
		secLbl.TextSize = isLore and 14 or 16
		secLbl.TextXAlignment = Enum.TextXAlignment.Left
		secLbl.TextYAlignment = Enum.TextYAlignment.Top
		secLbl.TextWrapped = true
		secLbl.AutomaticSize = Enum.AutomaticSize.Y
		secLbl.LineHeight = 1.15
		secLbl.Parent = secFrame
		table.insert(sectionFrames, secFrame)

		btn.MouseButton1Click:Connect(function()
			local y = sectionOffsets[i]
			if type(y) == "number" then scroll.CanvasPosition = Vector2.new(0, math.max(0, y - 8)) end
		end)
	end

	task.defer(function()
		for i, frame in ipairs(sectionFrames) do
			sectionOffsets[i] = frame.Position.Y.Offset
		end
	end)

	return scroll, sectionOffsets
end

-- Guide content (visible when mode == GUIDE)
local guideContent = Instance.new("Frame")
guideContent.Name = "GuideContent"
guideContent.Size = UDim2.new(1, -20, 1, -90)
guideContent.Position = UDim2.new(0, 10, 0, 82)
guideContent.BackgroundTransparency = 1
guideContent.Visible = false
guideContent.Parent = panel

local GUIDE_SECTIONS = {
	{ title = "I. Quick Ref", text = [[CONTROLS
[W][A][S][D] Move  [E] Target  [F] Attack  [Q] SiegelinQ  [G] Shop  [V] Friends  [X] Leaders  [P] Profile  [Z] Rebirth  [H] Home Recall  [B] Battle tab  [Y] Toggle favorite

HOW TO PLAY
1. CAPTURE — Find Siegelings in the world. Tap to target. Attack with [F] (and your companion) until the creature faints. Click the fainted creature to capture (costs gold; rarer = more cost).
2. COMPANION — Set one creature as your Favorite in SiegelinQ. That Siegeling follows you and fights by your side.
3. BASE — Assign creatures to Income (coins), Defense (raids), Battle (arena/PvP). Unlock Floor 2 for battle grid; up to five Siegelings in 3×3 formation.
4. ARENA — Team battles for fame and rewards.
5. PVP — Challenge nearby players to 1v1 duels.
6. RAIDS — Attack or defend bases; defend with your defense team.
7. COMBINE — Three of the same variant tier (Normal/Silver/Gold) combine into the next. Use the Combiner at your base.]] },
	{ title = "II. Foreword", text = [[You have taken the Rite of Thirteen. You hold your shield, you hold your first Capture Card. In the flame-lands of the frontier, we say: Through flame, we hold.

This world turns on Siegelings—the creatures bound to us by card and shield. As a Squire, you must learn to capture, to assign, to fight, and to defend. The four houses have gathered our teachings here. Read them. Use them. Then go into the wilds.

— Lord Theron Emberward, House Emberward (Fire)]] },
	{ title = "III. Shield & Card", text = [[Your SHIELD is more than armor. It is a wristguard with a slot for your Siegeling card. Place a card into the slot, and the creature bound to it is summoned to your side. Withdraw the card, and it returns to the vault.

Every shield bears a SIGIL. Ours declares house and allegiance. Hedge knights carry personal sigils they may pass to their Squires. Orders share sigils between members. Great houses wear one sigil for all—a mark of loyalty.

Guard your shield. Guard your cards. They are the proof of your bond.

— Lady Elara Frostholm, House Frostholm (Ice)]] },
	{ title = "IV. Capturing", text = [[Capture is the heart of the path. You weaken a wild Siegeling in combat—your strikes and your COMPANION's attacks—until it faints. Then you use a Capture Card. Success costs gold; the rarer the creature, the higher the cost.

TIP: Set one creature as your FAVORITE. That Siegeling becomes your companion and follows you into the wilds, fighting by your side. Choose well—your companion will be your first line of defense and offense.

Do not force the bond. A Siegeling that refuses the card cannot be bound. Patience and respect matter more than strength.

— Lord Marcus Cinderthorn, House Cinderthorn (Earth)]] },
	{ title = "V. Your Base", text = [[Every Squire is granted a PLOT—your home in this land. On it you assign your Siegelings to three roles:

• INCOME — Your Siegelings work the land. Coins flow over time.
• DEFENSE — Your Siegelings stand guard. Raiders who attack your base must face them. Build a strong defense.
• BATTLE TEAM — Your Siegelings fight for you in the arena and in duels. Unlock Floor 2 to access the battle grid. You may field up to five Siegelings in a 3×3 formation.

Choose based on each creature's strengths. Fire for offense, Ice for control, Earth for endurance, Air for speed. Build a balanced team. Swift as the storm means knowing when to strike and when to hold.

— Lord Kael Zephyran, House Zephyran (Air)]] },
	{ title = "VI. Arena & Duels", text = [[The arena is where the Valorous prove themselves. Knights and Siegelords battle daily for fame, territory, and the people's amusement. You will enter that arena. You will lose and you will win. Both teach.

Arena battles pit teams against each other. PvP duels let you challenge nearby knights. Your battle team fights; you command. Learn the focus bar, special attacks, and synergies. Fire burns, Earth slows, Wind drains focus, Ice freezes.

Fight with honor. Win or lose, you represent your house and the Valorous way.

— Lord Theron Emberward, House Emberward (Fire)]] },
	{ title = "VII. Dungeons & Raids", text = [[Beyond the safe paths lie DUNGEONS—stronger Siegelings, higher risk, greater reward. Rarer creatures lurk there. Face them when you are ready.

Beware RAIDS. Other knights may assault your base to steal your Siegelings. Defend with your defense team. And remember: not all who wield Siegelings are Valorous. Some lay siege to these lands—raiders, warlords, outcasts. They take by force and fight without honor. Our duty is to stand against them.

Cold steel, warm heart.

— Lady Elara Frostholm, House Frostholm (Ice)]] },
	{ title = "VIII. Evolve & Combine", text = [[Siegelings can grow stronger. EVOLUTION advances a creature to a higher form. COMBINING takes three of the same variant tier—Normal, Silver, Gold—and merges them into the next. Three Normals become one Silver. Three Silvers become one Gold. Three Golds become one Legend.

House Cinderthorn holds the forges and the combiner. Use it. A stronger team means a stronger defense.

Forge and defend.

— Lord Marcus Cinderthorn, House Cinderthorn (Earth)]] },
	{ title = "IX. Path Ahead", text = [[You begin as a Squire. Prove yourself, and you may become a full Knight. Rise further, and you may be named Siegelord. And one day, if you are the finest of all—Everybody is Ser. Only one is Sire.

Choose your starter. Claim your plot. Capture, assign, and battle. The four houses watch. The arena awaits. Go with honor.

— Lord Kael Zephyran, House Zephyran (Air)

— The Siegler's Codex, compiled by the Council of Houses]] },
	{ title = "X. Codex of Binding", text = [[THE CODEX OF BINDING — A History of the Siegelings and the Gift of Maestro

I. THE AGE BEFORE CARDS
In the earliest chronicles, before the wristguard and the Capture Card, the lands were wild. Humans fought the elements and the beasts of the frontier. Among those beasts were the Siegelings—creatures of flame, frost, stone, and wind—who lived as rivals and predators. Yet whispers survived of beings unlike the rest. Beings that spoke in the mind. They wore a third eye, hidden between the brows, and through it they saw the thoughts of others. They understood human speech. They could translate the tongues of the Siegelings. The chronicles name them Eleminions.

II. THE ELEMINIONS AND THE THIRD EYE
Each elemental region holds one Eleminion. Fire, Ice, Earth, Air. They live in secluded places. They are neither fully Siegeling nor fully human. Their third eye pierces illusion, reads intention, and opens a bridge between minds. Through this gift they understand both human and Siegeling. They translate meaning, emotion, and nuance. A knight may speak to his Siegeling only because an Eleminion first taught how such speech might work. The Four Houses guard their whereabouts. To meet one is rare; to refuse their counsel, foolish.

III. MAESTRO AND THE FIRST CARDS
The deepest mystery is Maestro. Whether Siegeling or Eleminion, no text is certain. Some claim he was the progenitor of the Eleminions—the first of their kind. Others say he was an Eleminion who ascended, or a Siegeling who transcended. What is recorded: Maestro appeared in a time of crisis. Humans and Siegelings fought without end. Then Maestro emerged—from where, none could say—and offered the first Capture Cards. Not weapons, but instruments of covenant. A card could bind a Siegeling to a human only if the creature chose to accept. The bond was voluntary. Coercion broke it. He taught the crafting of the shield. The wristguard with its slot for the card. Place the card, and the creature answers. Withdraw it, and the creature returns. He gave the knowledge and then withdrew. He vanished. No grave, no shrine. Only the cards, the shields, and a legend: that Maestro might still watch over those who honor the bond.

IV. THE VALOROUS AND THE UNVALOROUS
Not all who hold cards are worthy. Raiders and warlords stole the craft. They learn to force bonds, to break the compact Maestro intended. They lay siege to peaceful lands. The chronicles call them the Unvalorous. The Valorous keep the pact: bond by consent, fight with honor, defend the realm. The conflict has never ended.]] },
	{ title = "XI. Glossary", text = [[SIEGELING (pl. Siegelings) — Elemental creatures of Fire, Ice, Earth, Air (and faraway: Shadow, Lightning). Bound to humans via Capture Card and shield. Have their own language.

SIEGE KNIGHT — A knight who bonds Siegelings and duels in the arena. Noble defenders of the realm. Full rank after Squire.

SQUIRE — Apprentice who serves under a Knight. Learns capture and combat. Earns Knighthood after proving themselves. Begins at 13 with the Rite.

SIEGELORD — Elite knights; legendary status. Lead realms, sit on councils, defend frontiers. Best in the arenas.

SIRE — The single highest-ranked knight. Head of the Council. Everybody is Ser; only one is Sire.

SER — Honorific for all knights. "Ser" before a name.

SHIELD — Wristguard device with a slot for the Siegeling card. Placing the card summons the creature. Bears a sigil (house, order, or hedge knight).

CAPTURE CARD — Enchanted card that binds a Siegeling. Given by Maestro to humankind. Bond requires the creature's consent.

RITE OF THIRTEEN — Ceremony at age 13. Youth receives shield and first Capture Card, then sets off to find and bond their first Siegeling.

ELEMINION — Rare creatures with a third eye. Understand humans and Siegelings. Act as translators. One per elemental land. Can read minds and interpret language.

MAESTRO — Mysterious figure who gave humans the first Capture Cards. Believed to be Eleminion or progenitor of their kind. Vanished; may still watch over the bonded.

VALOROUS — Honorable Siege Knights who bond by consent, fight with honor, and defend the realm.

UNVALOROUS — Raiders, warlords, outcasts who force bonds and lay siege to peaceful lands. Fight without honor.

SIGIL — Mark on the shield declaring identity. Hedge knights: personal, passed to Squire. Orders: shared. Great Houses: same for all members.

FOUR HOUSES — Emberward (Fire), Frostholm (Ice), Cinderthorn (Earth), Zephyran (Air). Govern this land. Each associated with an Eleminion.

COUNCIL OF SIEGELORDS — Ruling body of the finest knights. The Sire sits at its head.]] },
}
guideScroll, guideSectionOffsets = buildBookView(guideContent, GUIDE_SECTIONS, false)
if guideScroll.Parent then
	guideScroll.Parent.Visible = false
end

local guideModeBar = Instance.new("Frame")
guideModeBar.Size = UDim2.new(1, 0, 0, 32)
guideModeBar.BackgroundTransparency = 1
guideModeBar.Parent = guideContent

local guideOverviewTab = Instance.new("TextButton")
guideOverviewTab.Size = UDim2.new(0.5, -3, 1, 0)
guideOverviewTab.Position = UDim2.new(0, 0, 0, 0)
guideOverviewTab.Text = "One Page"
guideOverviewTab.Font = Enum.Font.GothamBold
guideOverviewTab.TextSize = 11
guideOverviewTab.BorderSizePixel = 0
guideOverviewTab.Parent = guideModeBar
Instance.new("UICorner", guideOverviewTab).CornerRadius = UDim.new(0, 6)

local guideAdvancedTab = Instance.new("TextButton")
guideAdvancedTab.Size = UDim2.new(0.5, -3, 1, 0)
guideAdvancedTab.Position = UDim2.new(0.5, 3, 0, 0)
guideAdvancedTab.Text = "Advanced"
guideAdvancedTab.Font = Enum.Font.GothamBold
guideAdvancedTab.TextSize = 11
guideAdvancedTab.BorderSizePixel = 0
guideAdvancedTab.Parent = guideModeBar
Instance.new("UICorner", guideAdvancedTab).CornerRadius = UDim.new(0, 6)

local guideOverviewContent = Instance.new("Frame")
guideOverviewContent.Name = "GuideOverviewContent"
guideOverviewContent.Size = UDim2.new(1, 0, 1, -40)
guideOverviewContent.Position = UDim2.new(0, 0, 0, 40)
guideOverviewContent.BackgroundTransparency = 1
guideOverviewContent.Parent = guideContent

local guideAdvancedContent = Instance.new("Frame")
guideAdvancedContent.Name = "GuideAdvancedContent"
guideAdvancedContent.Size = UDim2.new(1, 0, 1, -40)
guideAdvancedContent.Position = UDim2.new(0, 0, 0, 40)
guideAdvancedContent.BackgroundTransparency = 1
guideAdvancedContent.Visible = false
guideAdvancedContent.Parent = guideContent

local GUIDE_OVERVIEW_CARDS = {
	{
		title = "Game On 1 Page",
		text = [[Your mission is to build an awesome team of Siegelings.

Catch wild Siegelings, grow your dream team, protect your base, and win big battles. There is always a new creature to find or a stronger team to build.]],
		color = Color3.fromRGB(30, 44, 70),
		titleColor = C.white,
		bodyColor = Color3.fromRGB(224, 232, 245),
		isHero = true,
	},
	{
		title = "Catch, Train, Repeat",
		text = [[1. Find a wild Siegeling.
2. Press [E] or Tap to target and [F] to attack.
3. When it faints, click it to capture it.
4. Open SiegelinQ and pick a Favorite so it follows you.
5. Keep catching better Siegelings and upgrading your team.]],
		color = Color3.fromRGB(22, 26, 38),
	},
	{
		title = "Why Your Base Matters",
		text = [[Income team = makes coins.
Defense team = guards your home during raids.
Battle team = fights in Arena and PvP.

Good teams make everything easier.]],
		color = Color3.fromRGB(22, 26, 38),
	},
	{
		title = "The Fun Stuff",
		text = [[Battle in the Arena, duel other players, explore risky places, defend your base, and combine matching Siegelings into stronger ones.]],
		color = Color3.fromRGB(22, 26, 38),
	},
	{
		title = "Buttons You Will Use Most",
		text = [[Move: [W][A][S][D]
Target: [E]
Attack: [F]
Creature menu: [Q]
Shop: [G]
Go home: [H]
Profile: [P]],
		color = Color3.fromRGB(22, 26, 38),
	},
}

local GUIDE_ADVANCED_SECTIONS = {
	{
		title = "1. Your Big Goal",
		text = [[Build a stronger and stronger team of Siegelings.

You are not trying to do one tiny mission and stop. The fun is catching new creatures, growing your favorites, defending your base, and winning tougher battles over time.]],
	},
	{
		title = "2. Catching a Siegeling",
		text = [[Walk up to a wild Siegeling.
Press [E] to target it.
Press [F] to attack until it faints.
Click the fainted Siegeling to capture it.

Rare Siegelings cost more gold to capture, so save up for the cool ones.]],
	},
	{
		title = "3. Your Favorite Buddy",
		text = [[Open SiegelinQ with [Q].
Pick one Siegeling as your Favorite.

That Favorite follows you around and helps you fight. If you want a different helper, just change your Favorite.]],
	},
	{
		title = "4. Jobs At Your Base",
		text = [[Your Siegelings can help in three ways:

Income - makes coins over time.
Defense - protects your base during raids.
Battle Team - fights in Arena and PvP.

Unlock Floor 2 when you want to place your battle team on the grid.]],
	},
	{
		title = "5. Where Fights Happen",
		text = [[Arena = team battles for rewards.
PvP = fight another player.
Raids = attack or defend a base.
Dungeons and risky areas = tougher enemies and better rewards.

If a place feels hard, it probably means you need a stronger team first.]],
	},
	{
		title = "6. Getting Stronger",
		text = [[You can power up your collection over time.

Use the Combiner at your base:
3 Normal = 1 Silver
3 Silver = 1 Gold
3 Gold = 1 Legend

Better Siegelings make your battles and base defense much stronger.]],
	},
	{
		title = "7. Quick Controls",
		text = [[[W][A][S][D] Move
[E] Target
[F] Attack
[Q] SiegelinQ
[G] Shop
[H] Home Recall
[P] Profile
[B] Battle tab]],
	},
}

local function buildGuideOverview(parent, cards)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = C.muted
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = parent

	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -6, 0, 0)
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = scroll

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 10)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	local contentPad = Instance.new("UIPadding", content)
	contentPad.PaddingLeft = UDim.new(0, 2)
	contentPad.PaddingRight = UDim.new(0, 6)
	contentPad.PaddingTop = UDim.new(0, 2)
	contentPad.PaddingBottom = UDim.new(0, 12)

	for i, card in ipairs(cards) do
		local cardFrame = Instance.new("Frame")
		cardFrame.Size = UDim2.new(1, 0, 0, 0)
		cardFrame.AutomaticSize = Enum.AutomaticSize.Y
		cardFrame.LayoutOrder = i
		cardFrame.BackgroundColor3 = card.color or C.card
		cardFrame.BorderSizePixel = 0
		cardFrame.Parent = content
		Instance.new("UICorner", cardFrame).CornerRadius = UDim.new(0, 10)

		local cardLayout = Instance.new("UIListLayout")
		cardLayout.Padding = UDim.new(0, 6)
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.Parent = cardFrame

		local cardPad = Instance.new("UIPadding", cardFrame)
		cardPad.PaddingLeft = UDim.new(0, 12)
		cardPad.PaddingRight = UDim.new(0, 12)
		cardPad.PaddingTop = UDim.new(0, 10)
		cardPad.PaddingBottom = UDim.new(0, 12)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 0)
		title.BackgroundTransparency = 1
		title.AutomaticSize = Enum.AutomaticSize.Y
		title.Text = card.title
		title.TextColor3 = card.titleColor or C.text
		title.Font = Enum.Font.GothamBold
		title.TextSize = card.isHero and 18 or 14
		title.TextWrapped = true
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Top
		title.Parent = cardFrame

		local body = Instance.new("TextLabel")
		body.Size = UDim2.new(1, 0, 0, 0)
		body.BackgroundTransparency = 1
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Text = card.text
		body.TextColor3 = card.bodyColor or C.textSec
		body.Font = Enum.Font.SourceSans
		body.TextSize = card.isHero and 18 or 16
		body.TextWrapped = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.LineHeight = 1.1
		body.Parent = cardFrame
	end

	return scroll
end

local guideOverviewScroll = buildGuideOverview(guideOverviewContent, GUIDE_OVERVIEW_CARDS)
local guideAdvancedScroll = buildBookView(guideAdvancedContent, GUIDE_ADVANCED_SECTIONS, false)

local function applyGuideViewStyle()
	local activeBg = Color3.fromRGB(50, 90, 140)
	local inactiveBg = C.card
	guideOverviewTab.BackgroundColor3 = guideViewMode == "OVERVIEW" and activeBg or inactiveBg
	guideOverviewTab.TextColor3 = guideViewMode == "OVERVIEW" and C.white or C.textSec
	guideAdvancedTab.BackgroundColor3 = guideViewMode == "ADVANCED" and activeBg or inactiveBg
	guideAdvancedTab.TextColor3 = guideViewMode == "ADVANCED" and C.white or C.textSec
end

local function setGuideViewMode(mode)
	guideViewMode = mode
	guideOverviewContent.Visible = mode == "OVERVIEW"
	guideAdvancedContent.Visible = mode == "ADVANCED"
	applyGuideViewStyle()
	if mode == "OVERVIEW" then
		guideOverviewScroll.CanvasPosition = Vector2.new(0, 0)
	else
		guideAdvancedScroll.CanvasPosition = Vector2.new(0, 0)
	end
end

guideOverviewTab.MouseButton1Click:Connect(function()
	setGuideViewMode("OVERVIEW")
end)

guideAdvancedTab.MouseButton1Click:Connect(function()
	setGuideViewMode("ADVANCED")
end)

setGuideViewMode("OVERVIEW")

-- Lore content (visible when mode == LORE)
local loreContent = Instance.new("Frame")
loreContent.Name = "LoreContent"
loreContent.Size = UDim2.new(1, -20, 1, -90)
loreContent.Position = UDim2.new(0, 10, 0, 82)
loreContent.BackgroundTransparency = 1
loreContent.Visible = false
loreContent.Parent = panel

local LORE_SECTIONS = {
	{ title = "I. Age Before Cards", text = [[In the earliest chronicles, before the wristguard and the Capture Card, the lands were wild. Humans fought the elements and the beasts of the frontier. Among those beasts were the Siegelings—creatures of flame, frost, stone, and wind—who lived as rivals and predators.

Yet whispers survived of beings unlike the rest. Beings that spoke in the mind. They wore a third eye, hidden between the brows, and through it they saw the thoughts of others. They understood human speech. They could translate the tongues of the Siegelings. The chronicles name them Eleminions.]] },
	{ title = "II. Eleminions", text = [[Each elemental region holds one Eleminion. Fire, Ice, Earth, Air. They live in secluded places. They are neither fully Siegeling nor fully human. Their third eye pierces illusion, reads intention, and opens a bridge between minds.

Through this gift they understand both human and Siegeling. They translate meaning, emotion, and nuance. A knight may speak to his Siegeling only because an Eleminion first taught how such speech might work. The Four Houses guard their whereabouts. To meet one is rare; to refuse their counsel, foolish.]] },
	{ title = "III. Maestro", text = [[The deepest mystery is Maestro. Whether Siegeling or Eleminion, no text is certain. Some claim he was the progenitor of the Eleminions—the first of their kind. Others say he was an Eleminion who ascended, or a Siegeling who transcended.

What is recorded: Maestro appeared in a time of crisis. Humans and Siegelings fought without end. Then Maestro emerged—from where, none could say—and offered the first Capture Cards. Not weapons, but instruments of covenant. A card could bind a Siegeling to a human only if the creature chose to accept. The bond was voluntary. Coercion broke it.

He taught the crafting of the shield. The wristguard with its slot for the card. Place the card, and the creature answers. Withdraw it, and the creature returns. He gave the knowledge and then withdrew. He vanished. No grave, no shrine. Only the cards, the shields, and a legend: that Maestro might still watch over those who honor the bond.]] },
	{ title = "IV. Valorous & Unvalorous", text = [[Not all who hold cards are worthy. Raiders and warlords stole the craft. They learn to force bonds, to break the compact Maestro intended. They lay siege to peaceful lands. The chronicles call them the Unvalorous. The Valorous keep the pact: bond by consent, fight with honor, defend the realm. The conflict has never ended.]] },
	{ title = "V. Glossary", text = [[SIEGELING (pl. Siegelings) — Elemental creatures of Fire, Ice, Earth, Air (and faraway: Shadow, Lightning). Bound to humans via Capture Card and shield. Have their own language.

SIEGE KNIGHT — A knight who bonds Siegelings and duels in the arena. Noble defenders of the realm. Full rank after Squire.

SQUIRE — Apprentice who serves under a Knight. Learns capture and combat. Earns Knighthood after proving themselves. Begins at 13 with the Rite.

SIEGELORD — Elite knights; legendary status. Lead realms, sit on councils, defend frontiers. Best in the arenas.

SIRE — The single highest-ranked knight. Head of the Council. Everybody is Ser; only one is Sire.

SER — Honorific for all knights.

SHIELD — Wristguard device with a slot for the Siegeling card. Placing the card summons the creature. Bears a sigil (house, order, or hedge knight).

CAPTURE CARD — Enchanted card that binds a Siegeling. Given by Maestro to humankind. Bond requires the creature's consent.

RITE OF THIRTEEN — Ceremony at age 13. Youth receives shield and first Capture Card, then sets off to find and bond their first Siegeling.

ELEMINION — Rare creatures with a third eye. Understand humans and Siegelings. Act as translators. One per elemental land. Can read minds and interpret language.

MAESTRO — Mysterious figure who gave humans the first Capture Cards. Believed to be Eleminion or progenitor of their kind. Vanished; may still watch over the bonded.

VALOROUS — Honorable Siege Knights who bond by consent, fight with honor, and defend the realm.

UNVALOROUS — Raiders, warlords, outcasts who force bonds and lay siege to peaceful lands. Fight without honor.

SIGIL — Mark on the shield declaring identity. Hedge knights: personal, passed to Squire. Orders: shared. Great Houses: same for all members.

FOUR HOUSES — Emberward (Fire), Frostholm (Ice), Cinderthorn (Earth), Zephyran (Air). Govern this land. Each associated with an Eleminion.

COUNCIL OF SIEGELORDS — Ruling body of the finest knights. The Sire sits at its head.]] },
}
local loreScroll, loreSectionOffsets = buildBookView(loreContent, LORE_SECTIONS, true)

-- Visual Codex content (visible when mode == VISUAL)
local visualContent = Instance.new("Frame")
visualContent.Name = "VisualContent"
visualContent.Size = UDim2.new(1, -20, 1, -90)
visualContent.Position = UDim2.new(0, 10, 0, 82)
visualContent.BackgroundTransparency = 1
visualContent.Visible = false
visualContent.Parent = panel

-- Cinematic filter rows + search/progress bar
local filterRow = Instance.new("Frame")
filterRow.Size = UDim2.new(1, 0, 0, 102)
filterRow.BackgroundTransparency = 1
filterRow.Parent = visualContent

local elementFilterLabel = Instance.new("TextLabel")
elementFilterLabel.Size = UDim2.new(0, 46, 0, 22)
elementFilterLabel.Position = UDim2.new(0, 0, 0, 2)
elementFilterLabel.BackgroundTransparency = 1
elementFilterLabel.Text = "Element"
elementFilterLabel.TextColor3 = C.textSec
elementFilterLabel.Font = Enum.Font.GothamMedium
elementFilterLabel.TextSize = 10
elementFilterLabel.Parent = filterRow

local elementScroll = Instance.new("ScrollingFrame")
elementScroll.Size = UDim2.new(1, -48, 0, 26)
elementScroll.Position = UDim2.new(0, 48, 0, 2)
elementScroll.BackgroundTransparency = 1
elementScroll.BorderSizePixel = 0
elementScroll.ScrollBarThickness = 4
elementScroll.ScrollBarImageColor3 = C.muted
elementScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
elementScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
elementScroll.ScrollingDirection = Enum.ScrollingDirection.X
elementScroll.Parent = filterRow
local elementList = Instance.new("Frame")
elementList.Size = UDim2.new(0, 0, 1, 0)
elementList.BackgroundTransparency = 1
elementList.AutomaticSize = Enum.AutomaticSize.X
elementList.Parent = elementScroll
local elementLayout = Instance.new("UIListLayout")
elementLayout.FillDirection = Enum.FillDirection.Horizontal
elementLayout.VerticalAlignment = Enum.VerticalAlignment.Center
elementLayout.Padding = UDim.new(0, 4)
elementLayout.SortOrder = Enum.SortOrder.LayoutOrder
elementLayout.Parent = elementList

local elementButtons = {}
local elements = {"All", "Fire", "Ice", "Wind", "Earth", "Shadow", "Light", "Lightning", "Water", "Psychic"}
local elementGlyphs = {
	All = "All",
	Fire = "🔥 Fire",
	Ice = "❄ Ice",
	Wind = "🌪 Wind",
	Earth = "🌍 Earth",
	Shadow = "🌑 Shadow",
	Light = "✨ Light",
	Lightning = "⚡ Lightning",
	Water = "💧 Water",
	Psychic = "🧠 Psychic",
}
for i, el in ipairs(elements) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, (el == "Lightning" or el == "Psychic") and 88 or 72, 0, 22)
	btn.LayoutOrder = i
	btn.Text = elementGlyphs[el] or el
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 9
	btn.BorderSizePixel = 0
	btn.Parent = elementList
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
	elementButtons[el] = btn
end

local rarityFilterLabel = Instance.new("TextLabel")
rarityFilterLabel.Size = UDim2.new(0, 42, 0, 22)
rarityFilterLabel.Position = UDim2.new(0, 0, 0, 28)
rarityFilterLabel.BackgroundTransparency = 1
rarityFilterLabel.Text = "Rarity"
rarityFilterLabel.TextColor3 = C.textSec
rarityFilterLabel.Font = Enum.Font.GothamMedium
rarityFilterLabel.TextSize = 10
rarityFilterLabel.Parent = filterRow

local rarityScroll = Instance.new("ScrollingFrame")
rarityScroll.Size = UDim2.new(1, -44, 0, 26)
rarityScroll.Position = UDim2.new(0, 44, 0, 28)
rarityScroll.BackgroundTransparency = 1
rarityScroll.BorderSizePixel = 0
rarityScroll.ScrollBarThickness = 4
rarityScroll.ScrollBarImageColor3 = C.muted
rarityScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
rarityScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
rarityScroll.ScrollingDirection = Enum.ScrollingDirection.X
rarityScroll.Parent = filterRow
local rarityList = Instance.new("Frame")
rarityList.Size = UDim2.new(0, 0, 1, 0)
rarityList.BackgroundTransparency = 1
rarityList.AutomaticSize = Enum.AutomaticSize.X
rarityList.Parent = rarityScroll
local rarityLayout = Instance.new("UIListLayout")
rarityLayout.FillDirection = Enum.FillDirection.Horizontal
rarityLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rarityLayout.Padding = UDim.new(0, 4)
rarityLayout.SortOrder = Enum.SortOrder.LayoutOrder
rarityLayout.Parent = rarityList

local rarityButtons = {}
local rarities = {"All", "Common", "Uncommon", "Rare", "Epic", "Legendary"}
for i, r in ipairs(rarities) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, r == "Legendary" and 76 or 62, 0, 22)
	btn.LayoutOrder = i
	btn.Text = r
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 9
	btn.BorderSizePixel = 0
	btn.Parent = rarityList
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
	rarityButtons[r] = btn
end

local searchLabel = Instance.new("TextLabel")
searchLabel.Size = UDim2.new(0, 42, 0, 22)
searchLabel.Position = UDim2.new(0, 0, 0, 54)
searchLabel.BackgroundTransparency = 1
searchLabel.Text = "Search"
searchLabel.TextColor3 = C.textSec
searchLabel.Font = Enum.Font.GothamMedium
searchLabel.TextSize = 10
searchLabel.Parent = filterRow

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -176, 0, 24)
searchBox.Position = UDim2.new(0, 44, 0, 54)
searchBox.PlaceholderText = "Search by creature name..."
searchBox.Text = ""
searchBox.ClearTextOnFocus = false
searchBox.Font = Enum.Font.GothamMedium
searchBox.TextSize = 10
searchBox.BackgroundColor3 = C.card
searchBox.BorderSizePixel = 0
searchBox.TextColor3 = C.text
searchBox.Parent = filterRow
Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 4)

local completionChip = Instance.new("Frame")
completionChip.Size = UDim2.new(0, 126, 0, 24)
completionChip.Position = UDim2.new(1, -126, 0, 54)
completionChip.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
completionChip.BorderSizePixel = 0
completionChip.Parent = filterRow
Instance.new("UICorner", completionChip).CornerRadius = UDim.new(0, 4)
local completionStroke = Instance.new("UIStroke")
completionStroke.Color = Color3.fromRGB(72, 82, 120)
completionStroke.Thickness = 1
completionStroke.Transparency = 0.3
completionStroke.Parent = completionChip

local completionTitle = Instance.new("TextLabel")
completionTitle.Size = UDim2.new(1, -8, 0, 10)
completionTitle.Position = UDim2.new(0, 4, 0, 1)
completionTitle.BackgroundTransparency = 1
completionTitle.Text = "DISCOVERY"
completionTitle.TextColor3 = Color3.fromRGB(177, 186, 220)
completionTitle.Font = Enum.Font.GothamBold
completionTitle.TextSize = 7
completionTitle.TextXAlignment = Enum.TextXAlignment.Left
completionTitle.Parent = completionChip

local completionCount = Instance.new("TextLabel")
completionCount.Size = UDim2.new(0, 34, 0, 10)
completionCount.Position = UDim2.new(1, -36, 0, 1)
completionCount.BackgroundTransparency = 1
completionCount.Text = "0/0"
completionCount.TextColor3 = Color3.fromRGB(255, 213, 96)
completionCount.Font = Enum.Font.GothamBold
completionCount.TextSize = 8
completionCount.TextXAlignment = Enum.TextXAlignment.Right
completionCount.Parent = completionChip

local completionBar = Instance.new("Frame")
completionBar.Size = UDim2.new(1, -8, 0, 5)
completionBar.Position = UDim2.new(0, 4, 1, -7)
completionBar.BackgroundColor3 = Color3.fromRGB(40, 45, 65)
completionBar.BorderSizePixel = 0
completionBar.Parent = completionChip
Instance.new("UICorner", completionBar).CornerRadius = UDim.new(0, 99)

local completionBarFill = Instance.new("Frame")
completionBarFill.Size = UDim2.new(0, 0, 1, 0)
completionBarFill.BackgroundColor3 = Color3.fromRGB(238, 187, 70)
completionBarFill.BorderSizePixel = 0
completionBarFill.Parent = completionBar
Instance.new("UICorner", completionBarFill).CornerRadius = UDim.new(0, 99)

local visualScroll = Instance.new("ScrollingFrame")
visualScroll.Size = UDim2.new(1, 0, 1, -108)
visualScroll.Position = UDim2.new(0, 0, 0, 104)
visualScroll.BackgroundTransparency = 1
visualScroll.BorderSizePixel = 0
visualScroll.ScrollBarThickness = 6
visualScroll.ScrollBarImageColor3 = C.muted
visualScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
visualScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
visualScroll.ScrollBarImageTransparency = 0.5
visualScroll.Parent = visualContent

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 108, 0, 135)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = visualScroll

local CELLS = {}
local cellViewers = {} -- [creatureId] = { viewer = CodexModelViewer, mode = "full"|"silhouette", loaded = bool }

local function setElementFilter(el)
	filterElement = (el == "All") and nil or el
	for name, btn in pairs(elementButtons) do
		local selected = (filterElement == nil and name == "All") or (filterElement == name)
		btn.BackgroundColor3 = selected and Color3.fromRGB(50, 90, 140) or C.card
		btn.TextColor3 = selected and C.white or C.textSec
	end
	refreshVisualGrid()
end
local function setRarityFilter(r)
	filterRarity = (r == "All") and nil or r
	for name, btn in pairs(rarityButtons) do
		local selected = (filterRarity == nil and name == "All") or (filterRarity == name)
		btn.BackgroundColor3 = selected and Color3.fromRGB(50, 90, 140) or C.card
		btn.TextColor3 = selected and C.white or C.textSec
	end
	refreshVisualGrid()
end
for name, btn in pairs(elementButtons) do
	btn.MouseButton1Click:Connect(function() setElementFilter(name) end)
end
for name, btn in pairs(rarityButtons) do
	btn.MouseButton1Click:Connect(function() setRarityFilter(name) end)
end
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	filterSearch = searchBox.Text or ""
	refreshVisualGrid()
end)
-- Initial filter state: All selected
if elementButtons["All"] then elementButtons["All"].BackgroundColor3 = Color3.fromRGB(50, 90, 140); elementButtons["All"].TextColor3 = C.white end
if rarityButtons["All"] then rarityButtons["All"].BackgroundColor3 = Color3.fromRGB(50, 90, 140); rarityButtons["All"].TextColor3 = C.white end

-- Build abilities text from element/class (no per-creature abilities in CreatureData)
local function getAbilitiesText(info)
	if not info then return "—" end
	local parts = {}
	if info.element and CreatureData.Elements[info.element] then
		table.insert(parts, "Element: " .. info.element .. " (element-type special in battle)")
	end
	if info.class and CreatureData.Classes[info.class] then
		table.insert(parts, "Class: " .. info.class)
	end
	if #parts == 0 then return "—" end
	return table.concat(parts, "\n")
end

local function applyTabStyle()
	local activeBg = Color3.fromRGB(50, 90, 140)
	local inactiveBg = C.card
	guideTab.BackgroundColor3 = currentMode == "GUIDE" and activeBg or inactiveBg
	guideTab.TextColor3 = currentMode == "GUIDE" and C.white or C.textSec
	loreTab.BackgroundColor3 = currentMode == "LORE" and activeBg or inactiveBg
	loreTab.TextColor3 = currentMode == "LORE" and C.white or C.textSec
	detailsTab.BackgroundColor3 = currentMode == "DETAILS" and activeBg or inactiveBg
	detailsTab.TextColor3 = currentMode == "DETAILS" and C.white or C.textSec
	visualTab.BackgroundColor3 = currentMode == "VISUAL" and activeBg or inactiveBg
	visualTab.TextColor3 = currentMode == "VISUAL" and C.white or C.textSec
end

local function switchToGuide()
	currentMode = "GUIDE"
	guideContent.Visible = true
	loreContent.Visible = false
	detailsContent.Visible = false
	visualContent.Visible = false
	applyTabStyle()
	setGuideViewMode("OVERVIEW")
end

local function switchToLore()
	currentMode = "LORE"
	guideContent.Visible = false
	loreContent.Visible = true
	detailsContent.Visible = false
	visualContent.Visible = false
	applyTabStyle()
	loreScroll.CanvasPosition = Vector2.new(0, 0)
end

local function switchToDetails()
	currentMode = "DETAILS"
	guideContent.Visible = false
	loreContent.Visible = false
	detailsContent.Visible = true
	visualContent.Visible = false
	applyTabStyle()
	if currentCreatureId then
		showCreature(currentCreatureId)
	end
end

local function switchToVisual()
	currentMode = "VISUAL"
	guideContent.Visible = false
	loreContent.Visible = false
	detailsContent.Visible = false
	visualContent.Visible = true
	applyTabStyle()
	task.spawn(function()
		refreshOwnedCreatures()
		if currentMode == "VISUAL" then
			refreshVisualGrid()
		end
	end)
	refreshVisualGrid()
	preloadVisualViewers()
	visualScroll.CanvasPosition = Vector2.new(0, visualScrollPosition)
	task.defer(updateVisualViewerPool)
end

showCreature = function(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info then
		panel.Visible = false
		return
	end

	seenCreatureIds[creatureId] = true
	currentCreatureId = creatureId
	local rarityInfo = CreatureData.Rarities[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or C.textSec
	local elemInfo = CreatureData.Elements[info.element]
	local classInfo = CreatureData.Classes[info.class]

	-- Preview: 3D viewer with element theming, floor, and auto-rotate
	if CodexModelViewer then
		previewViewportContainer.Visible = true
		previewPlaceholder.Visible = false
		customModelControls.Visible = true
		if detailsSnapshotImg then
			detailsSnapshotImg:Destroy()
			detailsSnapshotImg = nil
		end
		if not detailsModelViewer then
			detailsModelViewer = CodexModelViewer.new(previewViewportContainer, {
				size = UDim2.new(1, 0, 1, 0),
				autoRotate = true,
				autoRotateSpeed = 0.3,
				zoomEnabled = true,
				showFloor = true,
				themedLighting = true,
				playIdleAnimation = true,
			})
		end
		if detailsModelViewer then
			local vf = detailsModelViewer:GetViewportFrame()
			if vf then vf.Visible = true end
			if detailsModelViewer.SetRenderMode then
				detailsModelViewer:SetRenderMode(ownedCreatureIds[creatureId] and "full" or "silhouette")
			end
			detailsModelViewer:SetCreature(creatureId)
		end
		-- Optional static snapshot fallback (disabled by default to avoid hiding live viewer)
		if ENABLE_CODEX_SNAPSHOT_FALLBACK then
			task.spawn(function()
				task.wait(0.25)
				if not detailsModelViewer or currentCreatureId ~= creatureId then return end
				local ok, img = pcall(function()
					return detailsModelViewer:CaptureSnapshotAsync()
				end)
				if ok and img and currentCreatureId == creatureId then
					if detailsSnapshotImg then detailsSnapshotImg:Destroy() end
					detailsSnapshotImg = img
					img.Parent = previewViewportContainer
					if vf then vf.Visible = false end
				end
			end)
		end
	else
		previewViewportContainer.Visible = false
		previewPlaceholder.Visible = true
		customModelControls.Visible = false
		previewPlaceholder.BackgroundColor3 = info.primaryColor or C.muted
	end
	previewLabel.Text = (info.displayName or info.id) .. " — " .. (info.rarity or "?")

	-- Name
	nameLbl.Text = info.displayName or info.id or "?"
	nameLbl.TextColor3 = rarityColor

	-- Meta: element, class, rarity
	local metaParts = {}
	if info.element then table.insert(metaParts, info.element) end
	if info.class then table.insert(metaParts, info.class) end
	table.insert(metaParts, info.rarity or "?")
	metaLbl.Text = table.concat(metaParts, " · ")
	metaLbl.TextColor3 = C.textSec

	-- Description
	descLbl.Text = info.description and #info.description > 0 and info.description or "No description."

	-- Stats
	local stats = {}
	if info.health then table.insert(stats, "HP: " .. tostring(info.health)) end
	if info.attack then table.insert(stats, "ATK: " .. tostring(info.attack)) end
	if info.defense then table.insert(stats, "DEF: " .. tostring(info.defense)) end
	if info.speed then table.insert(stats, "SPD: " .. tostring(info.speed)) end
	statsLbl.Text = #stats > 0 and table.concat(stats, "  |  ") or "—"

	-- Abilities (element/class based)
	abilitiesLbl.Text = getAbilitiesText(info)

	-- Prev/Next visibility
	local idx = indexOfCreature(creatureId)
	prevBtn.Visible = idx and idx > 1
	nextBtn.Visible = idx and idx < #allCreatures

	-- Scroll to top
	scroll.CanvasPosition = Vector2.new(0, 0)
end

prevBtn.MouseButton1Click:Connect(function()
	if not currentCreatureId then return end
	local idx = indexOfCreature(currentCreatureId)
	if idx and idx > 1 then
		showCreature(allCreatures[idx - 1].id)
	end
end)

nextBtn.MouseButton1Click:Connect(function()
	if not currentCreatureId then return end
	local idx = indexOfCreature(currentCreatureId)
	if idx and idx < #allCreatures then
		showCreature(allCreatures[idx + 1].id)
	end
end)

visualCodexBtn.MouseButton1Click:Connect(function()
	visualScrollPosition = scroll.CanvasPosition.Y
	switchToVisual()
end)

guideTab.MouseButton1Click:Connect(switchToGuide)
loreTab.MouseButton1Click:Connect(switchToLore)
detailsTab.MouseButton1Click:Connect(switchToDetails)
visualTab.MouseButton1Click:Connect(switchToVisual)

local rarityFrameColors = {
	Common = Color3.fromRGB(145, 154, 178),
	Uncommon = Color3.fromRGB(69, 189, 126),
	Rare = Color3.fromRGB(78, 132, 255),
	Epic = Color3.fromRGB(166, 92, 255),
	Legendary = Color3.fromRGB(255, 193, 82),
}

local rarityBadgeText = {
	Common = "C",
	Uncommon = "UC",
	Rare = "R",
	Epic = "E",
	Legendary = "L",
}

local function isDiscovered(creatureId)
	return true
end

local function isOwnedCreature(creatureId)
	return ownedCreatureIds[creatureId] == true
end

local function updateDiscoveryProgress()
	local total = #allCreatures
	local unlocked = 0
	for _, c in ipairs(allCreatures) do
		if isOwnedCreature(c.id) then
			unlocked = unlocked + 1
		end
	end
	local percent = total > 0 and (unlocked / total) or 0
	completionCount.Text = string.format("%d/%d", unlocked, total)
	completionBarFill.Size = UDim2.fromScale(math.clamp(percent, 0, 1), 1)
end

local function setDashedFrame(frame, color)
	local segment = 12
	local gap = 8
	for x = 6, 100, segment + gap do
		local top = Instance.new("Frame")
		top.Size = UDim2.new(0, segment, 0, 1)
		top.Position = UDim2.new(0, x, 0, 4)
		top.BackgroundColor3 = color
		top.BorderSizePixel = 0
		top.Parent = frame
		local bottom = top:Clone()
		bottom.Position = UDim2.new(0, x, 1, -5)
		bottom.Parent = frame
	end
	for y = 10, 110, segment + gap do
		local left = Instance.new("Frame")
		left.Size = UDim2.new(0, 1, 0, segment)
		left.Position = UDim2.new(0, 4, 0, y)
		left.BackgroundColor3 = color
		left.BorderSizePixel = 0
		left.Parent = frame
		local right = left:Clone()
		right.Position = UDim2.new(1, -5, 0, y)
		right.Parent = frame
	end
end

local bottomSpacer = nil

local function makeCell(creatureInfo, order)
	local cell = Instance.new("Frame")
	cell.Size = UDim2.new(0, 108, 0, 135)
	cell.BackgroundColor3 = Color3.fromRGB(19, 24, 38)
	cell.BorderSizePixel = 0
	cell.LayoutOrder = order
	cell.Parent = visualScroll
	Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 8)
	local cellStroke = Instance.new("UIStroke")
	cellStroke.Color = rarityFrameColors[creatureInfo.rarity] or Color3.fromRGB(96, 106, 130)
	cellStroke.Thickness = 1.5
	cellStroke.Transparency = 0.2
	cellStroke.Parent = cell

	local viewerSlot = Instance.new("Frame")
	viewerSlot.Name = "ViewerSlot"
	viewerSlot.Size = UDim2.new(1, -8, 0, 94)
	viewerSlot.Position = UDim2.new(0, 4, 0, 4)
	viewerSlot.BackgroundColor3 = Color3.fromRGB(31, 36, 54)
	viewerSlot.BorderSizePixel = 0
	viewerSlot.Parent = cell
	Instance.new("UICorner", viewerSlot).CornerRadius = UDim.new(0, 6)

	local placeholder = Instance.new("Frame")
	placeholder.Name = "Placeholder"
	placeholder.Size = UDim2.new(0, 38, 0, 38)
	placeholder.Position = UDim2.new(0.5, -19, 0.5, -19)
	placeholder.BackgroundColor3 = creatureInfo.primaryColor or C.muted
	placeholder.BorderSizePixel = 0
	placeholder.Parent = viewerSlot
	Instance.new("UICorner", placeholder).CornerRadius = UDim.new(1, 0)

	local rarityBadge = Instance.new("TextLabel")
	rarityBadge.Size = UDim2.new(0, 20, 0, 14)
	rarityBadge.Position = UDim2.new(1, -24, 0, 4)
	rarityBadge.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
	rarityBadge.Text = rarityBadgeText[creatureInfo.rarity] or "?"
	rarityBadge.TextColor3 = C.white
	rarityBadge.Font = Enum.Font.GothamBlack
	rarityBadge.TextSize = 8
	rarityBadge.BorderSizePixel = 0
	rarityBadge.Parent = cell
	Instance.new("UICorner", rarityBadge).CornerRadius = UDim.new(0, 3)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -8, 0, 18)
	nameLabel.Position = UDim2.new(0, 4, 0, 101)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = creatureInfo.displayName or creatureInfo.id or "?"
	nameLabel.TextColor3 = C.text
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 10
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = cell

	local metaLabel = Instance.new("TextLabel")
	metaLabel.Size = UDim2.new(1, -8, 0, 12)
	metaLabel.Position = UDim2.new(0, 4, 0, 117)
	metaLabel.BackgroundTransparency = 1
	metaLabel.Text = (creatureInfo.element or "?") .. " · " .. (creatureInfo.rarity or "?")
	metaLabel.TextColor3 = C.textSec
	metaLabel.Font = Enum.Font.GothamMedium
	metaLabel.TextSize = 8
	metaLabel.TextTruncate = Enum.TextTruncate.AtEnd
	metaLabel.TextXAlignment = Enum.TextXAlignment.Left
	metaLabel.Parent = cell

	local lockedOverlay = Instance.new("Frame")
	lockedOverlay.Name = "LockedOverlay"
	lockedOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockedOverlay.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	lockedOverlay.BackgroundTransparency = 0.35
	lockedOverlay.BorderSizePixel = 0
	lockedOverlay.Visible = false
	lockedOverlay.Parent = cell
	Instance.new("UICorner", lockedOverlay).CornerRadius = UDim.new(0, 8)
	setDashedFrame(lockedOverlay, Color3.fromRGB(88, 98, 128))

	local unknownWatermark = Instance.new("TextLabel")
	unknownWatermark.Size = UDim2.new(0.7, 0, 0.6, 0)
	unknownWatermark.Position = UDim2.new(0.15, 0, 0.18, 0)
	unknownWatermark.BackgroundTransparency = 1
	unknownWatermark.Text = "?"
	unknownWatermark.Font = Enum.Font.GothamBlack
	unknownWatermark.TextColor3 = Color3.fromRGB(86, 94, 120)
	unknownWatermark.TextTransparency = 0.65
	unknownWatermark.TextScaled = true
	unknownWatermark.Parent = lockedOverlay

	local unknownLabel = Instance.new("TextLabel")
	unknownLabel.Size = UDim2.new(1, -8, 0, 16)
	unknownLabel.Position = UDim2.new(0, 4, 1, -22)
	unknownLabel.BackgroundTransparency = 1
	unknownLabel.Text = "???"
	unknownLabel.TextColor3 = Color3.fromRGB(132, 140, 168)
	unknownLabel.Font = Enum.Font.GothamBold
	unknownLabel.TextSize = 10
	unknownLabel.TextXAlignment = Enum.TextXAlignment.Left
	unknownLabel.Parent = lockedOverlay

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = cell
	btn.MouseButton1Click:Connect(function()
		OpenCodex(creatureInfo.id)
	end)

	return {
		frame = cell,
		creatureInfo = creatureInfo,
		creatureId = creatureInfo.id,
		viewerSlot = viewerSlot,
		placeholder = placeholder,
		nameLabel = nameLabel,
		metaLabel = metaLabel,
		lockedOverlay = lockedOverlay,
		rarityBadge = rarityBadge,
		cellStroke = cellStroke,
	}
end

local function applyCellDiscoveryState(cellData)
	local creatureInfo = cellData.creatureInfo
	local discovered = isDiscovered(creatureInfo.id)
	local owned = isOwnedCreature(creatureInfo.id)
	cellData.discovered = discovered
	cellData.owned = owned
	cellData.lockedOverlay.Visible = false
	cellData.nameLabel.Text = creatureInfo.displayName or creatureInfo.id or "?"
	cellData.metaLabel.Text = (creatureInfo.element or "?") .. " · " .. (creatureInfo.rarity or "?")
	cellData.rarityBadge.Text = rarityBadgeText[creatureInfo.rarity] or "?"
	cellData.placeholder.BackgroundColor3 = owned and (creatureInfo.primaryColor or C.muted) or Color3.fromRGB(45, 50, 66)
	cellData.cellStroke.Color = rarityFrameColors[creatureInfo.rarity] or Color3.fromRGB(96, 106, 130)
end

local function applyFilters()
	filteredCreatures = {}
	local searchLower = filterSearch and string.lower(filterSearch) or ""
	local layoutOrder = 1
	for _, cellData in ipairs(CELLS) do
		local c = cellData.creatureInfo
		local matches = true
		if filterElement and filterElement ~= "All" and c.element ~= filterElement then
			matches = false
		end
		if matches and filterRarity and filterRarity ~= "All" and c.rarity ~= filterRarity then
			matches = false
		end
		if matches and #searchLower > 0 then
			local name = (c.displayName or c.id or ""):lower()
			if not name:find(searchLower, 1, true) then
				matches = false
			end
		end
		cellData.frame.Visible = matches
		if matches then
			cellData.frame.LayoutOrder = layoutOrder
			layoutOrder = layoutOrder + 1
			table.insert(filteredCreatures, c)
		end
	end
	if bottomSpacer then
		bottomSpacer.LayoutOrder = layoutOrder
	end
end

local visualCellsBuilt = false
local visualPreloadStarted = false
local function ensureVisualCells()
	if visualCellsBuilt then
		return
	end
	for i, c in ipairs(allCreatures) do
		local cellData = makeCell(c, i)
		applyCellDiscoveryState(cellData)
		table.insert(CELLS, cellData)
	end
	bottomSpacer = Instance.new("Frame")
	bottomSpacer.Size = UDim2.new(1, 0, 0, 1)
	bottomSpacer.BackgroundTransparency = 1
	bottomSpacer.LayoutOrder = #allCreatures + 1
	bottomSpacer.Parent = visualScroll
	visualCellsBuilt = true
end

local function ensureCellViewerLoaded(cellData)
	if not CodexModelViewer or not cellData then return nil end
	local desiredMode = cellData.owned and "full" or "silhouette"
	local entry = cellViewers[cellData.creatureId]
	if not entry then
		local viewer = CodexModelViewer.new(cellData.viewerSlot, {
			size = UDim2.new(1, 0, 1, 0),
			autoRotate = false,
			autoRotateSpeed = 0.2,
			zoomEnabled = false,
			showFloor = false,
			themedLighting = true,
			playIdleAnimation = true,
		})
		entry = { viewer = viewer, mode = desiredMode, loaded = false }
		cellViewers[cellData.creatureId] = entry
	end
	if entry.viewer and entry.viewer.GetViewportFrame then
		local vf = entry.viewer:GetViewportFrame()
		if vf and vf.Parent ~= cellData.viewerSlot then
			vf.Parent = cellData.viewerSlot
		end
	end
	if entry.viewer and entry.viewer.SetRenderMode then
		entry.viewer:SetRenderMode(desiredMode)
	end
	if (not entry.loaded) or entry.mode ~= desiredMode then
		if entry.viewer then
			entry.viewer:SetCreature(cellData.creatureId)
		end
		entry.mode = desiredMode
		entry.loaded = true
	end
	return entry
end

local function preloadVisualViewers()
	if visualPreloadStarted then return end
	visualPreloadStarted = true
	task.spawn(function()
		local batch = 0
		for _, cellData in ipairs(CELLS) do
			ensureCellViewerLoaded(cellData)
			batch = batch + 1
			if batch >= 6 then
				batch = 0
				task.wait()
			end
		end
	end)
end

function refreshVisualGrid()
	ensureVisualCells()
	for _, cellData in ipairs(CELLS) do
		applyCellDiscoveryState(cellData)
		local entry = cellViewers[cellData.creatureId]
		if entry and entry.loaded and entry.mode ~= (cellData.owned and "full" or "silhouette") then
			ensureCellViewerLoaded(cellData)
		end
	end
	applyFilters()
	updateDiscoveryProgress()
	if currentMode == "VISUAL" then
		preloadVisualViewers()
		task.defer(updateVisualViewerPool)
	end
end

-- Assign persistent viewers to visible cells (no re-parent shuffling).
function updateVisualViewerPool()
	if not CodexModelViewer or #CELLS == 0 then return end
	local scrollAbs = visualScroll.AbsolutePosition
	local scrollSize = visualScroll.AbsoluteWindowSize
	local visibleById = {}
	for _, cellData in ipairs(CELLS) do
		local f = cellData.frame
		if f and f.Visible and f.AbsolutePosition and f.AbsoluteSize then
			local cy = f.AbsolutePosition.Y
			local ch = f.AbsoluteSize.Y
			if cy + ch >= scrollAbs.Y and cy <= scrollAbs.Y + scrollSize.Y then
				local entry = ensureCellViewerLoaded(cellData)
				visibleById[cellData.creatureId] = true
				if entry and entry.loaded then
					cellData.placeholder.Visible = false
				else
					cellData.placeholder.Visible = true
				end
			else
				local entry = cellViewers[cellData.creatureId]
				cellData.placeholder.Visible = not (entry and entry.loaded)
			end
		else
			local entry = cellViewers[cellData.creatureId]
			cellData.placeholder.Visible = not (entry and entry.loaded)
		end
	end
	for creatureId, entry in pairs(cellViewers) do
		if entry and entry.viewer and entry.viewer.SetAutoRotate then
			entry.viewer:SetAutoRotate(visibleById[creatureId] == true)
		end
	end
end

visualScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	visualScrollPosition = visualScroll.CanvasPosition.Y
	if currentMode == "VISUAL" then updateVisualViewerPool() end
end)

-- Fetch owned creature IDs from server (for Visual grid "owned" overlay)
local function refreshOwnedCreatures()
	table.clear(ownedCreatureIds)
	local events = ReplicatedStorage:FindFirstChild("Events")
	local getInv = events and events:FindFirstChild("GetInventory")
	if not getInv then return end
	local ok, data = pcall(function() return getInv:InvokeServer() end)
	if ok and data and data.inventory then
		for _, e in ipairs(data.inventory) do
			if e.id then ownedCreatureIds[e.id] = true end
		end
	end
end

-- Single entry point: open Codex for creatureId, or "guide" for lore/guide
function OpenCodex(creatureId)
	if not GameConfig.ENABLE_CODEX_UI then return end
	applyPanelScale(panel)
	if creatureId == "guide" or creatureId == "lore" or creatureId == nil or creatureId == "" then
		task.spawn(function()
			refreshOwnedCreatures()
			if currentMode == "VISUAL" then
				refreshVisualGrid()
			end
		end)
		if creatureId == "lore" then switchToLore() else switchToGuide() end
		panel.Visible = true
		MobileWindowLayout.NotifyMenuOpened()
		return
	end
	if type(creatureId) ~= "string" then return end
	local info = CreatureData.GetById(creatureId)
	if not info then return end

	task.spawn(function()
		refreshOwnedCreatures()
		-- Update visual/details once inventory lands so silhouettes flip to full models for owned entries.
		if currentMode == "VISUAL" then
			refreshVisualGrid()
		elseif currentMode == "DETAILS" and currentCreatureId == creatureId then
			showCreature(creatureId)
		end
	end)
	switchToDetails()
	showCreature(creatureId)
	panel.Visible = true
	MobileWindowLayout.NotifyMenuOpened()
end

-- Expose for other scripts: fire with creatureId to open Codex, or "guide" for lore/guide
local openCodexEvent = Instance.new("BindableEvent")
openCodexEvent.Name = "OpenCodex"
openCodexEvent.Parent = playerGui
openCodexEvent.Event:Connect(function(creatureId)
	OpenCodex(creatureId)
end)

-- Also expose as BindableFunction so Invoke works
local openCodexFunc = Instance.new("BindableFunction")
openCodexFunc.Name = "OpenCodexInvoke"
openCodexFunc.Parent = playerGui
openCodexFunc.OnInvoke = function(creatureId)
	OpenCodex(creatureId)
	return true
end

-- Listen for HUD "CodexGuide" to toggle Codex (reconnect when HUDToggleMenu is re-added, e.g. after respawn)
local function getHUDToggle()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if not evt or not evt:IsA("BindableEvent") then
		evt = Instance.new("BindableEvent")
		evt.Name = "HUDToggleMenu"
		evt.Parent = playerGui
	end
	return evt
end
local function onHUDToggle(menuName)
	if menuName == "CodexGuide" then
		if panel.Visible then
			panel.Visible = false
			MobileWindowLayout.NotifyMenuClosed()
		else
			OpenCodex("guide")
		end
	end
end
getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then child.Event:Connect(onHUDToggle) end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if panel.Visible then
		applyPanelScale(panel)
	else
		syncCodexScreenGuiInset()
	end
end)

-- Auto-show disabled.
-- Codex panel will only open via `OpenCodex(...)` (creature click / HUD toggle),
-- so it won't interrupt players right after spawn.

task.defer(syncCodexScreenGuiInset)
print("[CodexClient] Loaded — OpenCodex(creatureId) or OpenCodex(\"guide\") when ENABLE_CODEX_UI is true")
