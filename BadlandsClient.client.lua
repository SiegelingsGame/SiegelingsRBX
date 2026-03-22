-- ═══════════════════════════════════════════════════════════════════════════════
-- Last updated: 2026-03-21 00:41
-- BadlandsClient.client.lua
-- ═══════════════════════════════════════════════════════════════════════════════
-- Client-side HUD and UI for active Badlands runs:
--   • Extraction progress bar + bag inventory overlay when extracting
--   • Timer display showing remaining time in the Badlands
--   • Extraction result screen (success / failure)
--   • Queue / run start notifications
--
-- Listens to: BadlandsRunStart, BadlandsRunEnd, BadlandsTimerSync,
--             BadlandsExtractProgress, BadlandsExtractCancel,
--             BadlandsExtracted, BadlandsExtractActivate,
--             BadlandsEliminated, BadlandsBagUpdate
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Module requires
-- ═══════════════════════════════════════════════════════════════════════════════
local Modules = ReplicatedStorage:WaitForChild("Modules")

local Notify = nil
do
	local notifScript = Modules:FindFirstChild("NotificationManager")
	if notifScript then
		local ok, result = pcall(require, notifScript)
		if ok then Notify = result end
	end
end

local CreatureData = nil
do
	local cdScript = Modules:FindFirstChild("CreatureData")
	if cdScript then
		local ok, result = pcall(require, cdScript)
		if ok then CreatureData = result end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Events
-- ═══════════════════════════════════════════════════════════════════════════════
local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
if not eventsFolder then
	warn("[BadlandsClient] Events folder not found")
	return
end

-- Gather all events (nil-safe)
local function getEvent(name) return eventsFolder:FindFirstChild(name) end

local runStartEvt       = getEvent("BadlandsRunStart")
local runEndEvt         = getEvent("BadlandsRunEnd")
local timerSyncEvt      = getEvent("BadlandsTimerSync")
local extractProgressEvt = getEvent("BadlandsExtractProgress")
local extractCancelEvt  = getEvent("BadlandsExtractCancel")
local extractedEvt      = getEvent("BadlandsExtracted")
local extractActivateEvt = getEvent("BadlandsExtractActivate")
local eliminatedEvt     = getEvent("BadlandsEliminated")
local bagUpdateEvt      = getEvent("BadlandsBagUpdate")
local bagSwitchEvt      = getEvent("BadlandsBagSwitch")
local sacrificeCreatureEvt = getEvent("BadlandsSacrificeCreature")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Color palette
-- ═══════════════════════════════════════════════════════════════════════════════
local C = {
	bg       = Color3.fromRGB(14, 15, 22),
	bgLight  = Color3.fromRGB(22, 24, 35),
	card     = Color3.fromRGB(28, 30, 42),
	accent   = Color3.fromRGB(180, 80, 255),
	green    = Color3.fromRGB(80, 220, 100),
	red      = Color3.fromRGB(220, 60, 60),
	gold     = Color3.fromRGB(255, 200, 50),
	white    = Color3.fromRGB(240, 240, 245),
	textSec  = Color3.fromRGB(140, 145, 160),
	grey     = Color3.fromRGB(80, 85, 100),
}

local RARITY_COLORS = {
	Common    = Color3.fromRGB(160, 160, 160),
	Uncommon  = Color3.fromRGB(80, 200, 80),
	Rare      = Color3.fromRGB(60, 140, 255),
	Epic      = Color3.fromRGB(180, 60, 255),
	Legendary = Color3.fromRGB(255, 180, 30),
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════════════════
local inBadlands = false
local screenGui = nil
local timerLabel = nil
local timerFrame = nil
local extractionUI = nil  -- the extraction overlay frame
local runStartTime = 0
local runDuration = 600
local bagButton = nil
local bagPanel = nil
local bagPanelOpen = false  -- legacy; bag UI now in InventoryUIManager BadBag tab
local bagState = {
	count = 0,
	capacity = 0,
	activeIndex = nil,
	slots = {},
}
local hudVisible = true
local hudToggleBadge = nil
local hudToggleStroke = nil
local hudBadgeGui = nil
local tickerLayoutConns = {}

local BADGE_WIDTH = 40
local BADGE_HEIGHT = 40
local BADGE_GAP = 8
local BADGE_SLOT = 2
local BADGE_DISPLAY_ORDER = 52

local function disconnectTickerLayoutSignals()
	for _, conn in ipairs(tickerLayoutConns) do
		conn:Disconnect()
	end
	tickerLayoutConns = {}
end

local function getTickerBar()
	local notifGui = playerGui:FindFirstChild("NotificationGUI")
	local tickerBar = notifGui and notifGui:FindFirstChild("TickerBar")
	if tickerBar and tickerBar:IsA("GuiObject") and tickerBar.Visible then
		return tickerBar
	end
	return nil
end

local function getHudTopY()
	local tickerBar = getTickerBar()
	if tickerBar then
		return math.floor(tickerBar.AbsolutePosition.Y + tickerBar.AbsoluteSize.Y + 6)
	end
	return 48
end

local function layoutHudElements()
	local yTop = getHudTopY()

	-- Timer: top-center, right under the ticker bar
	if timerFrame and timerFrame.Parent then
		timerFrame.Position = UDim2.new(0.5, 0, 0, yTop)
	end

	-- BadBag button: replaces the BattleMenu button position (top-left)
	-- Size and position match toggleBtn in InventoryUIManager (46×54 at 12,76)
	if bagButton and bagButton.Parent then
		bagButton.Position = UDim2.new(0, 12, 0, 76)
	end

	if bagPanel and bagPanel.Parent then
		bagPanel.Position = UDim2.new(0, 12, 0, 136)
	end

	-- BL toggle badge: bottom area, to the left of the "Tracking Sieglings" target bar
	if hudToggleBadge and hudToggleBadge.Parent then
		-- Position in the bottom-center area, left of the combat tracker bar.
		-- The target bar is at (0.5, 1, -offset) anchored bottom-center.
		-- Place BL badge to its left. We use scale positioning so it adapts.
		local camera = workspace.CurrentCamera
		if camera then
			local vh = camera.ViewportSize.Y
			local vw = camera.ViewportSize.X
			-- Match the target bar's vertical position: just above the HUD button bar
			local hudHeightPx = (32 / 1080) * 1.35 * vh
			local offsetFromBottom = hudHeightPx + 8
			-- Target bar is 376px wide at center; BL badge goes to its left
			local targetBarHalfW = 188  -- TARGET_BAR_WIDTH / 2 (12 + 5*64 + 4*8 + 12 = 376)
			local badgeX = math.floor(vw / 2 - targetBarHalfW - BADGE_GAP - BADGE_WIDTH)
			local badgeY = math.floor(vh - offsetFromBottom - BADGE_HEIGHT)
			hudToggleBadge.Position = UDim2.new(0, badgeX, 0, badgeY)
			hudToggleBadge.AnchorPoint = Vector2.new(0, 0)
		else
			hudToggleBadge.Position = UDim2.new(0.5, -260, 1, -80)
			hudToggleBadge.AnchorPoint = Vector2.new(1, 1)
		end
	end
end

local function bindTickerLayoutSignals()
	disconnectTickerLayoutSignals()
	local notifGui = playerGui:FindFirstChild("NotificationGUI")
	local tickerBar = notifGui and notifGui:FindFirstChild("TickerBar")
	if not (tickerBar and tickerBar:IsA("GuiObject")) then
		return
	end

	table.insert(tickerLayoutConns, tickerBar:GetPropertyChangedSignal("AbsolutePosition"):Connect(layoutHudElements))
	table.insert(tickerLayoutConns, tickerBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHudElements))
	table.insert(tickerLayoutConns, tickerBar:GetPropertyChangedSignal("Visible"):Connect(layoutHudElements))
	-- Also relayout when viewport resizes (BL badge position depends on screen size)
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(tickerLayoutConns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutHudElements))
	end
end

local function applyHudVisibility()
	local showHud = inBadlands and hudVisible

	if timerFrame then
		timerFrame.Visible = showHud
	end
	if bagButton then
		bagButton.Visible = showHud
	end
	if bagPanel then
		bagPanel.Visible = showHud and bagPanelOpen
	end

	if hudToggleBadge then
		hudToggleBadge.BackgroundColor3 = showHud and C.accent or C.bg
		hudToggleBadge.BackgroundTransparency = showHud and 0.15 or 0.25
	end
	if hudToggleStroke then
		hudToggleStroke.Color = showHud and C.accent or C.grey
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ScreenGui setup (created once, persists while in Badlands)
-- ═══════════════════════════════════════════════════════════════════════════════
local function ensureScreenGui()
	if screenGui and screenGui.Parent then return screenGui end
	-- Remove stale BadlandsHUD if it exists (e.g. from previous run)
	local existing = playerGui:FindFirstChild("BadlandsHUD")
	if existing then existing:Destroy() end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BadlandsHUD"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 46
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	return screenGui
end

local function destroyScreenGui()
	disconnectTickerLayoutSignals()
	if hudBadgeGui then
		hudBadgeGui:Destroy()
		hudBadgeGui = nil
	end
	if screenGui then screenGui:Destroy(); screenGui = nil end
	timerLabel = nil
	timerFrame = nil
	extractionUI = nil
	bagButton = nil
	bagPanel = nil
	hudToggleBadge = nil
	hudToggleStroke = nil
	hudVisible = true
	bagPanelOpen = false
	bagState = {
		count = 0,
		capacity = 0,
		activeIndex = nil,
		slots = {},
	}
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Timer HUD (top-center, shows remaining time in the Badlands)
-- ═══════════════════════════════════════════════════════════════════════════════
local function createTimerHUD()
	local gui = ensureScreenGui()

	-- Remove existing timer if present (prevents duplicates on re-enter)
	local old = gui:FindFirstChild("TimerFrame")
	if old then old:Destroy(); timerLabel = nil end

	local frame = Instance.new("Frame")
	frame.Name = "TimerFrame"
	frame.Size = UDim2.new(0, 200, 0, 40)
	frame.Position = UDim2.new(0.5, 0, 0, 48)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = C.bg
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = C.accent
	stroke.Thickness = 1.5

	-- "THE BADLANDS" label
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Size = UDim2.new(1, 0, 0.45, 0)
	titleLbl.Position = UDim2.new(0, 0, 0, 2)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "THE BADLANDS"
	titleLbl.TextColor3 = C.accent
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 11
	titleLbl.Parent = frame

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.Size = UDim2.new(1, 0, 0.5, 0)
	timerLabel.Position = UDim2.new(0, 0, 0.45, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "10:00"
	timerLabel.TextColor3 = C.white
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 16
	timerLabel.Parent = frame
	timerFrame = frame

	bindTickerLayoutSignals()
	layoutHudElements()
	applyHudVisibility()

	return frame
end

local function updateTimer(remaining)
	if not timerLabel then return end
	local mins = math.floor(remaining / 60)
	local secs = math.floor(remaining % 60)
	timerLabel.Text = string.format("%d:%02d", mins, secs)

	-- Color: green > 3min, gold > 1min, red < 1min
	if remaining > 180 then
		timerLabel.TextColor3 = C.green
	elseif remaining > 60 then
		timerLabel.TextColor3 = C.gold
	else
		timerLabel.TextColor3 = C.red
	end
end

local function updateBagButtonText()
	if not bagButton then return end
	local count = tonumber(bagState.count) or 0
	local capacity = tonumber(bagState.capacity) or 0
	bagButton.Text = ("BadBag\n%d/%d"):format(count, capacity)
end

local refreshBagUI
local toggleBagPanel

local function createHudToggleBadge()
	if hudToggleBadge and hudToggleBadge.Parent then
		layoutHudElements()
		applyHudVisibility()
		return hudToggleBadge
	end

	if not hudBadgeGui or not hudBadgeGui.Parent then
		hudBadgeGui = Instance.new("ScreenGui")
		hudBadgeGui.Name = "BadlandsHudBadgeGui"
		hudBadgeGui.ResetOnSpawn = false
		hudBadgeGui.DisplayOrder = BADGE_DISPLAY_ORDER
		hudBadgeGui.IgnoreGuiInset = true
		hudBadgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		hudBadgeGui.Parent = playerGui
	end

	local btn = Instance.new("TextButton")
	btn.Name = "BadlandsHudBadge"
	btn.Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT)
	btn.BackgroundColor3 = C.accent
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel = 0
	btn.Text = "BL"
	btn.TextColor3 = C.white
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 14
	btn.AutoButtonColor = false
	btn.ZIndex = 40
	btn.Parent = hudBadgeGui
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = C.accent
	stroke.Thickness = 2

	btn.MouseButton1Click:Connect(function()
		hudVisible = not hudVisible
		applyHudVisibility()
		local popOut = TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Back), {
			Size = UDim2.new(0, BADGE_WIDTH + 4, 0, BADGE_HEIGHT + 4),
		})
		popOut:Play()
		task.delay(0.1, function()
			if btn and btn.Parent then
				TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
					Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT),
				}):Play()
			end
		end)
	end)

	hudToggleBadge = btn
	hudToggleStroke = stroke
	layoutHudElements()
	applyHudVisibility()
	return hudToggleBadge
end

local function createBagButton()
	if bagButton and bagButton.Parent then
		updateBagButtonText()
		layoutHudElements()
		applyHudVisibility()
		return bagButton
	end

	local gui = ensureScreenGui()

	-- FIX #24: BadBag button replaces the Battle Menu button (top-left) when in Badlands.
	-- Matches toggleBtn in InventoryUIManager: 46×54, position (12, 76), same corner radius.
	bagButton = Instance.new("TextButton")
	bagButton.Name = "BadBagButton"
	bagButton.Size = UDim2.new(0, 46, 0, 54)
	bagButton.Position = UDim2.new(0, 12, 0, 76)
	bagButton.AnchorPoint = Vector2.new(0, 0)
	bagButton.BackgroundColor3 = C.accent
	bagButton.BackgroundTransparency = 0.15
	bagButton.BorderSizePixel = 0
	bagButton.TextColor3 = C.white
	bagButton.Font = Enum.Font.GothamBold
	bagButton.TextSize = 11
	bagButton.TextWrapped = true
	bagButton.LineHeight = 1.1
	bagButton.ZIndex = 30
	bagButton.Parent = gui
	Instance.new("UICorner", bagButton).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", bagButton)
	stroke.Color = Color3.fromRGB(255, 120, 60)
	stroke.Thickness = 1
	stroke.Transparency = 0.5

	bagButton.MouseButton1Click:Connect(function()
		if toggleBagPanel then
			toggleBagPanel()
		end
	end)

	updateBagButtonText()
	layoutHudElements()
	applyHudVisibility()
	return bagButton
end

-- Sacrifice stat choice modal: Health, Attack, Defense, Movement Speed
local sacrificeModalRef = nil
local sacrificeResultEvt = getEvent("BadlandsSacrificeResult")

local function showSacrificeStatModal(slotIndex, creatureName)
	if sacrificeModalRef and sacrificeModalRef.Parent then
		sacrificeModalRef:Destroy()
	end

	local gui = ensureScreenGui()
	local overlay = Instance.new("Frame")
	overlay.Name = "SacrificeModal"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 60
	overlay.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 280, 0, 200)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = C.bg
	panel.BorderSizePixel = 0
	panel.ZIndex = 61
	panel.Parent = overlay
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
	Instance.new("UIStroke", panel).Color = C.red
	panel:FindFirstChildOfClass("UIStroke").Thickness = 2

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 28)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "Sacrifice for Stat Boost"
	title.TextColor3 = C.red
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 16
	title.ZIndex = 62
	title.Parent = panel

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -16, 0, 20)
	sub.Position = UDim2.new(0, 8, 0, 36)
	sub.BackgroundTransparency = 1
	sub.Text = "Choose a stat to boost:"
	sub.TextColor3 = C.textSec
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 12
	sub.ZIndex = 62
	sub.Parent = panel

	local STATS = { "Health", "Attack", "Defense", "MovementSpeed" }
	local STAT_COLORS = {
		Health = Color3.fromRGB(220, 80, 80),
		Attack = Color3.fromRGB(255, 120, 50),
		Defense = Color3.fromRGB(80, 150, 255),
		MovementSpeed = Color3.fromRGB(100, 255, 120),
	}

	local btnY = 64
	for _, stat in ipairs(STATS) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -24, 0, 28)
		btn.Position = UDim2.new(0, 12, 0, btnY)
		btn.BackgroundColor3 = STAT_COLORS[stat] or C.accent
		btn.BackgroundTransparency = 0.4
		btn.BorderSizePixel = 0
		btn.Text = "+" .. stat:gsub("MovementSpeed", "Movement Speed")
		btn.TextColor3 = C.white
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.ZIndex = 63
		btn.Parent = panel
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		btnY = btnY + 32

		btn.MouseButton1Click:Connect(function()
			if sacrificeCreatureEvt then
				sacrificeCreatureEvt:FireServer(slotIndex, stat)
			end
			overlay:Destroy()
			sacrificeModalRef = nil
		end)
	end

	sacrificeModalRef = overlay
end

local function buildBagPanel()
	if bagPanel then
		bagPanel:Destroy()
		bagPanel = nil
	end

	local gui = ensureScreenGui()
	local panel = Instance.new("Frame")
	panel.Name = "BagPanel"
	panel.Size = UDim2.new(0, 320, 0, 420)
	panel.Position = UDim2.new(1, -18, 0, 114)
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.BackgroundColor3 = C.bg
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.ZIndex = 28
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", panel)
	stroke.Color = C.accent
	stroke.Thickness = 1.5

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 26)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "BADLANDS BAG"
	title.TextColor3 = C.accent
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 29
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 18)
	subtitle.Position = UDim2.new(0, 10, 0, 38)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = ("Captured creatures: %d / %d"):format(tonumber(bagState.count) or 0, tonumber(bagState.capacity) or 0)
	subtitle.TextColor3 = C.textSec
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 12
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 29
	subtitle.Parent = panel

	local tip = Instance.new("TextLabel")
	tip.Size = UDim2.new(1, -20, 0, 32)
	tip.Position = UDim2.new(0, 10, 0, 58)
	tip.BackgroundTransparency = 1
	tip.Text = "Click a slot to set favorite. Sacrifice for stat boosts."
	tip.TextColor3 = C.textSec
	tip.Font = Enum.Font.GothamMedium
	tip.TextSize = 10
	tip.TextXAlignment = Enum.TextXAlignment.Left
	tip.TextWrapped = true
	tip.ZIndex = 29
	tip.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "BagSlots"
	list.Size = UDim2.new(1, -20, 1, -110)
	list.Position = UDim2.new(0, 10, 0, 96)
	list.BackgroundColor3 = C.card
	list.BackgroundTransparency = 0.18
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = C.grey
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.ZIndex = 29
	list.Parent = panel
	Instance.new("UICorner", list).CornerRadius = UDim.new(0, 8)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = list

	for slotIndex, slot in ipairs(bagState.slots or {}) do
		local occupied = not slot.empty and slot.id ~= nil
		local row = Instance.new("TextButton")
		row.Name = "Slot_" .. slotIndex
		row.Size = UDim2.new(1, -4, 0, 48)
		row.BackgroundColor3 = occupied and C.bgLight or C.card
		row.BackgroundTransparency = occupied and 0.05 or 0.35
		row.BorderSizePixel = 0
		row.AutoButtonColor = occupied
		row.LayoutOrder = slotIndex
		row.Text = ""
		row.ZIndex = 30
		row.Parent = list
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

		local rowStroke = Instance.new("UIStroke", row)
		if slot.active then
			rowStroke.Color = C.green
			rowStroke.Thickness = 2
		else
			rowStroke.Color = occupied and Color3.fromRGB(70, 74, 92) or Color3.fromRGB(50, 54, 70)
			rowStroke.Thickness = 1
		end

		local slotLbl = Instance.new("TextLabel")
		slotLbl.Size = UDim2.new(0, 42, 1, 0)
		slotLbl.Position = UDim2.new(0, 8, 0, 0)
		slotLbl.BackgroundTransparency = 1
		slotLbl.Text = "#" .. slotIndex
		slotLbl.TextColor3 = slot.active and C.green or C.textSec
		slotLbl.Font = Enum.Font.GothamBold
		slotLbl.TextSize = 13
		slotLbl.ZIndex = 31
		slotLbl.Parent = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -122, 0, 20)
		nameLbl.Position = UDim2.new(0, 52, 0, 5)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = occupied and (slot.displayName or slot.id or "Unknown") or "Empty slot"
		nameLbl.TextColor3 = occupied and C.white or C.textSec
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 13
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.ZIndex = 31
		nameLbl.Parent = row

		local detailLbl = Instance.new("TextLabel")
		detailLbl.Size = UDim2.new(1, -122, 0, 16)
		detailLbl.Position = UDim2.new(0, 52, 0, 25)
		detailLbl.BackgroundTransparency = 1
		detailLbl.Text = occupied
			and ("Lv" .. tostring(slot.level or 1) .. " • " .. tostring(slot.variant or "Normal") .. " • " .. tostring(slot.rarity or "Common"))
			or "Capture a Badlands creature to fill this slot."
		detailLbl.TextColor3 = C.textSec
		detailLbl.Font = Enum.Font.GothamMedium
		detailLbl.TextSize = 11
		detailLbl.TextXAlignment = Enum.TextXAlignment.Left
		detailLbl.TextTruncate = Enum.TextTruncate.AtEnd
		detailLbl.ZIndex = 31
		detailLbl.Parent = row

		local stateLbl = Instance.new("TextLabel")
		stateLbl.Size = UDim2.new(0, 52, 0, 20)
		stateLbl.Position = UDim2.new(1, -148, 0.5, -10)
		stateLbl.BackgroundTransparency = 1
		stateLbl.Text = slot.active and "FAV" or (occupied and "READY" or "EMPTY")
		stateLbl.TextColor3 = slot.active and C.green or (occupied and C.white or C.textSec)
		stateLbl.Font = Enum.Font.GothamBold
		stateLbl.TextSize = 11
		stateLbl.TextXAlignment = Enum.TextXAlignment.Right
		stateLbl.ZIndex = 31
		stateLbl.Parent = row

		if occupied then
			-- Click = set as favorite (active)
			if bagSwitchEvt then
				row.MouseButton1Click:Connect(function()
					bagSwitchEvt:FireServer(slotIndex)
				end)
			end

			-- Sacrifice button (only for non-active slots)
			if not slot.active and sacrificeCreatureEvt then
				local sacBtn = Instance.new("TextButton")
				sacBtn.Name = "SacrificeBtn"
				sacBtn.Size = UDim2.new(0, 70, 0, 22)
				sacBtn.Position = UDim2.new(1, -76, 0.5, -11)
				sacBtn.BackgroundColor3 = C.red
				sacBtn.BackgroundTransparency = 0.3
				sacBtn.BorderSizePixel = 0
				sacBtn.Text = "Sacrifice"
				sacBtn.TextColor3 = C.white
				sacBtn.Font = Enum.Font.GothamBold
				sacBtn.TextSize = 10
				sacBtn.ZIndex = 32
				sacBtn.Parent = row
				Instance.new("UICorner", sacBtn).CornerRadius = UDim.new(0, 4)
				sacBtn.MouseButton1Click:Connect(function()
					showSacrificeStatModal(slotIndex, slot.displayName or slot.id or "Creature")
				end)
			end
		end
	end

	panel.Visible = bagPanelOpen
	bagPanel = panel
	layoutHudElements()
	applyHudVisibility()
end

refreshBagUI = function()
	createBagButton()
	updateBagButtonText()
	if bagPanelOpen then
		buildBagPanel()
	elseif bagPanel then
		bagPanel.Visible = false
	end
	applyHudVisibility()
end

toggleBagPanel = function()
	if not inBadlands then return end
	bagPanelOpen = not bagPanelOpen
	refreshBagUI()
	if bagPanel then
		bagPanel.Visible = bagPanelOpen
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Extraction UI: shows bag inventory + progress bar during 15s channel
-- ═══════════════════════════════════════════════════════════════════════════════
local function showExtractionUI(data)
	local gui = ensureScreenGui()

	-- Remove previous if exists
	if extractionUI then extractionUI:Destroy(); extractionUI = nil end

	local bag = data.bag or {}
	local channelTime = data.channelTime or 15

	-- ── Full-screen overlay ──
	local overlay = Instance.new("Frame")
	overlay.Name = "ExtractionOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 50
	overlay.Parent = gui
	extractionUI = overlay

	-- ── Center panel ──
	local panel = Instance.new("Frame")
	panel.Name = "ExtractPanel"
	panel.Size = UDim2.new(0, 400, 0, 380)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = C.bg
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.ZIndex = 51
	panel.Parent = overlay
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
	local panelStroke = Instance.new("UIStroke", panel)
	panelStroke.Color = C.green
	panelStroke.Thickness = 2

	-- ── Title ──
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 30)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "EXTRACTING..."
	title.TextColor3 = C.green
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.ZIndex = 52
	title.Parent = panel

	-- ── Progress bar ──
	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBG"
	barBg.Size = UDim2.new(1, -32, 0, 16)
	barBg.Position = UDim2.new(0, 16, 0, 44)
	barBg.BackgroundColor3 = C.grey
	barBg.BackgroundTransparency = 0.4
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 52
	barBg.Parent = panel
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

	local barFill = Instance.new("Frame")
	barFill.Name = "ProgressFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = C.green
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 53
	barFill.Parent = barBg
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

	-- ── Countdown ──
	local countdownLbl = Instance.new("TextLabel")
	countdownLbl.Name = "Countdown"
	countdownLbl.Size = UDim2.new(1, -16, 0, 20)
	countdownLbl.Position = UDim2.new(0, 8, 0, 64)
	countdownLbl.BackgroundTransparency = 1
	countdownLbl.Text = math.ceil(channelTime) .. "s remaining"
	countdownLbl.TextColor3 = C.textSec
	countdownLbl.Font = Enum.Font.GothamMedium
	countdownLbl.TextSize = 13
	countdownLbl.ZIndex = 52
	countdownLbl.Parent = panel

	-- ── "Your Bag" header ──
	local bagHeader = Instance.new("TextLabel")
	bagHeader.Name = "BagHeader"
	bagHeader.Size = UDim2.new(1, -16, 0, 22)
	bagHeader.Position = UDim2.new(0, 8, 0, 90)
	bagHeader.BackgroundTransparency = 1
	bagHeader.Text = "Your Bag (" .. #bag .. " creatures)"
	bagHeader.TextColor3 = C.white
	bagHeader.Font = Enum.Font.GothamBold
	bagHeader.TextSize = 14
	bagHeader.TextXAlignment = Enum.TextXAlignment.Left
	bagHeader.ZIndex = 52
	bagHeader.Parent = panel

	-- ── Bag list (scrolling) ──
	local bagList = Instance.new("ScrollingFrame")
	bagList.Name = "BagList"
	bagList.Size = UDim2.new(1, -24, 0, 230)
	bagList.Position = UDim2.new(0, 12, 0, 116)
	bagList.BackgroundColor3 = C.card
	bagList.BackgroundTransparency = 0.4
	bagList.BorderSizePixel = 0
	bagList.ScrollBarThickness = 5
	bagList.ScrollBarImageColor3 = C.grey
	bagList.CanvasSize = UDim2.new(0, 0, 0, 0)
	bagList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bagList.ZIndex = 52
	bagList.Parent = panel
	Instance.new("UICorner", bagList).CornerRadius = UDim.new(0, 6)

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 3)
	listLayout.Parent = bagList

	local listPad = Instance.new("UIPadding")
	listPad.PaddingLeft = UDim.new(0, 4)
	listPad.PaddingRight = UDim.new(0, 4)
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.PaddingBottom = UDim.new(0, 4)
	listPad.Parent = bagList

	if #bag == 0 then
		local emptyLbl = Instance.new("TextLabel")
		emptyLbl.Size = UDim2.new(1, 0, 0, 40)
		emptyLbl.BackgroundTransparency = 1
		emptyLbl.Text = "Your bag is empty.\nYou'll leave with nothing."
		emptyLbl.TextColor3 = C.textSec
		emptyLbl.Font = Enum.Font.GothamMedium
		emptyLbl.TextSize = 12
		emptyLbl.TextWrapped = true
		emptyLbl.ZIndex = 53
		emptyLbl.Parent = bagList
	else
		for i, creature in ipairs(bag) do
			local card = Instance.new("Frame")
			card.Name = "BagItem_" .. i
			card.Size = UDim2.new(1, -4, 0, 40)
			card.BackgroundColor3 = C.bgLight
			card.BackgroundTransparency = 0.2
			card.BorderSizePixel = 0
			card.LayoutOrder = i
			card.ZIndex = 53
			card.Parent = bagList
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 5)

			-- Rarity bar
			local rarBar = Instance.new("Frame")
			rarBar.Size = UDim2.new(0, 4, 1, -4)
			rarBar.Position = UDim2.new(0, 2, 0, 2)
			rarBar.BackgroundColor3 = RARITY_COLORS[creature.rarity] or C.grey
			rarBar.BorderSizePixel = 0
			rarBar.ZIndex = 54
			rarBar.Parent = card
			Instance.new("UICorner", rarBar).CornerRadius = UDim.new(0, 2)

			-- Name
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -90, 0, 20)
			nameLbl.Position = UDim2.new(0, 14, 0, 2)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = creature.displayName or creature.id or "???"
			nameLbl.TextColor3 = C.white
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 12
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.ZIndex = 54
			nameLbl.Parent = card

			-- Details
			local detLbl = Instance.new("TextLabel")
			detLbl.Size = UDim2.new(1, -90, 0, 14)
			detLbl.Position = UDim2.new(0, 14, 0, 22)
			detLbl.BackgroundTransparency = 1
			detLbl.Text = "Lv" .. (creature.level or 1) .. " • " .. (creature.variant or "Normal")
			detLbl.TextColor3 = C.textSec
			detLbl.Font = Enum.Font.GothamMedium
			detLbl.TextSize = 10
			detLbl.TextXAlignment = Enum.TextXAlignment.Left
			detLbl.ZIndex = 54
			detLbl.Parent = card

			-- Rarity label
			local rarLbl = Instance.new("TextLabel")
			rarLbl.Size = UDim2.new(0, 80, 1, 0)
			rarLbl.Position = UDim2.new(1, -82, 0, 0)
			rarLbl.BackgroundTransparency = 1
			rarLbl.Text = creature.rarity or "?"
			rarLbl.TextColor3 = RARITY_COLORS[creature.rarity] or C.textSec
			rarLbl.Font = Enum.Font.GothamBold
			rarLbl.TextSize = 11
			rarLbl.TextXAlignment = Enum.TextXAlignment.Right
			rarLbl.ZIndex = 54
			rarLbl.Parent = card
		end
	end

	-- Store references for updating progress
	overlay:SetAttribute("_barFill", "")
	overlay:SetAttribute("_countdown", "")

	-- We'll update these from the progress event handler
	return {
		overlay = overlay,
		barFill = barFill,
		countdownLbl = countdownLbl,
		title = title,
	}
end

-- Refs for live-updating extraction UI
local extractRefs = nil

local function updateExtractionProgress(data)
	if not extractRefs then return end

	local progress = data.progress or 0
	local remaining = data.remaining or 0

	-- Update progress bar
	if extractRefs.barFill and extractRefs.barFill.Parent then
		extractRefs.barFill.Size = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
	end

	-- Update countdown
	if extractRefs.countdownLbl and extractRefs.countdownLbl.Parent then
		extractRefs.countdownLbl.Text = math.ceil(remaining) .. "s remaining"
	end
end

local function hideExtractionUI()
	if extractionUI then
		extractionUI:Destroy()
		extractionUI = nil
	end
	extractRefs = nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Result screens
-- ═══════════════════════════════════════════════════════════════════════════════
local function showExtractionSuccess(data)
	hideExtractionUI()
	local gui = ensureScreenGui()

	local creatures = data.creatures or {}

	local overlay = Instance.new("Frame")
	overlay.Name = "ExtractSuccess"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 60
	overlay.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 360, 0, 260)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = C.bg
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.ZIndex = 61
	panel.Parent = overlay
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
	Instance.new("UIStroke", panel).Color = C.green; panel:FindFirstChildOfClass("UIStroke").Thickness = 2

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 36)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "EXTRACTION SUCCESSFUL"
	title.TextColor3 = C.green
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.ZIndex = 62
	title.Parent = panel

	local summary = Instance.new("TextLabel")
	summary.Size = UDim2.new(1, -16, 0, 60)
	summary.Position = UDim2.new(0, 8, 0, 48)
	summary.BackgroundTransparency = 1
	summary.Text = "You escaped The Badlands with " .. #creatures .. " creature(s)!\n"
		.. "Kills: " .. (data.kills or 0)
		.. "  |  Captures: " .. (data.captures or 0)
		.. "  |  Power Lv" .. (data.powerLevel or 1)
	summary.TextColor3 = C.white
	summary.Font = Enum.Font.GothamMedium
	summary.TextSize = 13
	summary.TextWrapped = true
	summary.ZIndex = 62
	summary.Parent = panel

	-- List transferred creatures
	local listY = 112
	for i, cr in ipairs(creatures) do
		if i > 6 then break end -- show max 6
		local info = CreatureData and CreatureData.GetById(cr.id)
		local displayName = info and info.displayName or cr.id or "???"
		local rarity = info and info.rarity or "?"
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -24, 0, 18)
		lbl.Position = UDim2.new(0, 12, 0, listY)
		lbl.BackgroundTransparency = 1
		lbl.Text = "• " .. displayName .. " Lv" .. (cr.level or 1) .. " (" .. (cr.variant or "Normal") .. ") — " .. rarity
		lbl.TextColor3 = RARITY_COLORS[rarity] or C.textSec
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextSize = 12
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.ZIndex = 62
		lbl.Parent = panel
		listY = listY + 20
	end

	if #creatures > 6 then
		local moreLbl = Instance.new("TextLabel")
		moreLbl.Size = UDim2.new(1, -24, 0, 16)
		moreLbl.Position = UDim2.new(0, 12, 0, listY)
		moreLbl.BackgroundTransparency = 1
		moreLbl.Text = "...and " .. (#creatures - 6) .. " more"
		moreLbl.TextColor3 = C.textSec
		moreLbl.Font = Enum.Font.GothamMedium
		moreLbl.TextSize = 11
		moreLbl.ZIndex = 62
		moreLbl.Parent = panel
	end

	-- Auto-close after 8 seconds
	task.delay(8, function()
		if overlay and overlay.Parent then
			local fade = TweenService:Create(overlay, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
			fade:Play()
			fade.Completed:Connect(function() overlay:Destroy() end)
		end
	end)
end

local function showExpelledScreen(data)
	hideExtractionUI()
	local gui = ensureScreenGui()

	local overlay = Instance.new("Frame")
	overlay.Name = "ExpelledScreen"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 60
	overlay.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 360, 0, 180)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = C.bg
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.ZIndex = 61
	panel.Parent = overlay
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
	Instance.new("UIStroke", panel).Color = C.red; panel:FindFirstChildOfClass("UIStroke").Thickness = 2

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 36)
	title.Position = UDim2.new(0, 8, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "TIME'S UP"
	title.TextColor3 = C.red
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.ZIndex = 62
	title.Parent = panel

	local msg = Instance.new("TextLabel")
	msg.Size = UDim2.new(1, -16, 0, 80)
	msg.Position = UDim2.new(0, 8, 0, 52)
	msg.BackgroundTransparency = 1
	msg.TextWrapped = true
	msg.ZIndex = 62
	msg.Parent = panel
	msg.Font = Enum.Font.GothamMedium
	msg.TextSize = 14
	msg.TextColor3 = C.white

	local kept = data and data.keptCreature
	if kept then
		msg.Text = "You were expelled from The Badlands.\nYour bag was lost, but you kept your favorite:\n" .. (kept.id or "???") .. " (Lv" .. (kept.level or 1) .. ")"
	else
		msg.Text = "You were expelled from The Badlands.\nEverything in your bag was lost."
	end

	task.delay(6, function()
		if overlay and overlay.Parent then
			local fade = TweenService:Create(overlay, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
			fade:Play()
			fade.Completed:Connect(function() overlay:Destroy() end)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Timer heartbeat loop (updates HUD timer every frame while in Badlands)
-- ═══════════════════════════════════════════════════════════════════════════════
local timerConn = nil

local function startTimerLoop()
	if timerConn then timerConn:Disconnect() end
	timerConn = RunService.Heartbeat:Connect(function()
		if not inBadlands then return end
		local elapsed = tick() - runStartTime
		local remaining = math.max(0, runDuration - elapsed)
		updateTimer(remaining)
	end)
end

local function stopTimerLoop()
	if timerConn then timerConn:Disconnect(); timerConn = nil end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- EVENT LISTENERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- BadlandsRunStart: we entered the Badlands
if runStartEvt then
	runStartEvt.OnClientEvent:Connect(function(data)
		if not data then return end
		-- The Broker fires accepted=true before the actual run; ignore that one here
		if data.accepted and not data.runId then return end
		if not data.runId then return end

		inBadlands = true
		runStartTime = tick()
		runDuration = data.runDuration or data.timeRemaining or 600

		-- If late join, adjust start time so the timer shows correct remaining
		if data.lateJoin and data.timeRemaining then
			runStartTime = tick() - (runDuration - data.timeRemaining)
		end

		createTimerHUD()
		createHudToggleBadge()
		hudVisible = true
		startTimerLoop()
		refreshBagUI()
		applyHudVisibility()

		if Notify and Notify.Toast then
			if data.lateJoin then
				Notify.Toast("Entered The Badlands (late join)", C.accent, 3)
			else
				Notify.Toast("Welcome to The Badlands. Survive.", C.accent, 4)
			end
		end
	end)
end

-- BadlandsTimerSync: periodic sync from server
if timerSyncEvt then
	timerSyncEvt.OnClientEvent:Connect(function(data)
		if not data or not inBadlands then return end
		if data.remaining then
			-- Recalibrate our timer
			runStartTime = tick() - (runDuration - data.remaining)
		end
	end)
end

-- BadlandsExtractProgress: extraction channel update (or start)
if extractProgressEvt then
	extractProgressEvt.OnClientEvent:Connect(function(data)
		if not data then return end

		-- First event with started=true: create the extraction UI
		if data.started then
			extractRefs = showExtractionUI(data)
		else
			updateExtractionProgress(data)
		end
	end)
end

-- BadlandsExtractCancel: extraction interrupted
if extractCancelEvt then
	extractCancelEvt.OnClientEvent:Connect(function(message)
		hideExtractionUI()
		if Notify and Notify.Toast then
			Notify.Toast(message or "Extraction interrupted!", C.red, 3)
		end
	end)
end

-- BadlandsExtracted: extraction succeeded — show results
if extractedEvt then
	extractedEvt.OnClientEvent:Connect(function(data)
		inBadlands = false
		stopTimerLoop()
		showExtractionSuccess(data or {})
		task.delay(10, destroyScreenGui)
	end)
end

-- BadlandsRunEnd: expelled (time ran out) or eliminated
if runEndEvt then
	runEndEvt.OnClientEvent:Connect(function(data)
		inBadlands = false
		stopTimerLoop()
		hideExtractionUI()
		showExpelledScreen(data or {})
		task.delay(8, destroyScreenGui)
	end)
end

-- BadlandsEliminated: player was killed by another player
if eliminatedEvt then
	eliminatedEvt.OnClientEvent:Connect(function(data)
		inBadlands = false
		stopTimerLoop()
		hideExtractionUI()

		local gui = ensureScreenGui()
		local overlay = Instance.new("Frame")
		overlay.Name = "EliminatedScreen"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = Color3.fromRGB(60, 0, 0)
		overlay.BackgroundTransparency = 0.3
		overlay.BorderSizePixel = 0
		overlay.ZIndex = 60
		overlay.Parent = gui

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(0.6, 0, 0, 50)
		title.Position = UDim2.new(0.2, 0, 0.4, 0)
		title.BackgroundTransparency = 1
		title.Text = "ELIMINATED"
		title.TextColor3 = C.red
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 36
		title.ZIndex = 61
		title.Parent = overlay

		local msg = Instance.new("TextLabel")
		msg.Size = UDim2.new(0.6, 0, 0, 30)
		msg.Position = UDim2.new(0.2, 0, 0.48, 0)
		msg.BackgroundTransparency = 1
		msg.Text = "You lost everything in your bag."
		msg.TextColor3 = C.white
		msg.Font = Enum.Font.GothamMedium
		msg.TextSize = 16
		msg.ZIndex = 61
		msg.Parent = overlay

		task.delay(5, function()
			if overlay and overlay.Parent then overlay:Destroy() end
			destroyScreenGui()
		end)
	end)
end

-- Q key now opens InventoryUI BadBag tab directly (handled by InventoryUIManager)

if bagUpdateEvt then
	bagUpdateEvt.OnClientEvent:Connect(function(payload)
		local bag = (payload and payload.bag) or payload or {}
		bagState = {
			count = tonumber(bag.count) or 0,
			capacity = tonumber(bag.capacity) or 0,
			activeIndex = bag.activeIndex,
			slots = bag.slots or {},
		}

		if inBadlands or bagPanelOpen then
			refreshBagUI()
		end
	end)
end

if sacrificeResultEvt then
	sacrificeResultEvt.OnClientEvent:Connect(function(success, message)
		if Notify and Notify.Toast then
			Notify.Toast(message or (success and "Sacrifice complete!" or "Sacrifice failed"), success and C.green or C.red, 3)
		end
		if success and bagPanelOpen then
			refreshBagUI()
		end
	end)
end

print("[BadlandsClient] Initialized — listening for Badlands events")
