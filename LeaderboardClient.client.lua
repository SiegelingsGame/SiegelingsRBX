-- LeaderboardClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Full-screen leaderboard panel. Toggle with L key or HUD button.
-- Tabs: Income, Victories, PvP, Siegelings.
-- Top 3 only: Smash-style tilted portrait frames (2nd | 1st | 3rd).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local getLeaderboardData = Events:WaitForChild("GetLeaderboardData", 10)
if not getLeaderboardData then return end

-- Colors
local C = {
	bg = Color3.fromRGB(14, 15, 22),
	bgLight = Color3.fromRGB(22, 24, 35),
	card = Color3.fromRGB(28, 30, 42),
	text = Color3.fromRGB(240, 240, 245),
	textSec = Color3.fromRGB(140, 145, 160),
	gold = Color3.fromRGB(255, 200, 50),
	silver = Color3.fromRGB(200, 200, 210),
	bronze = Color3.fromRGB(200, 140, 60),
	accent = Color3.fromRGB(100, 220, 160),
	tabActive = Color3.fromRGB(60, 160, 255),
	tabInactive = Color3.fromRGB(60, 65, 80),
	playerHL = Color3.fromRGB(40, 80, 120),
	streak = Color3.fromRGB(255, 140, 40),
}

local RANK_COLORS = { C.gold, C.silver, C.bronze }
local RANK_LABELS = { "1ST", "2ND", "3RD" }

-- Smash-style layout: left = 2nd, center = 1st (elevated), right = 3rd
local SMASH_DISPLAY_ORDER = {
	{ rank = 2, slot = "left" },
	{ rank = 1, slot = "center" },
	{ rank = 3, slot = "right" },
}

-- Panel scales with viewport; on mobile allow smaller scale so it fits on screen
local PANEL_DESIGN_W = 580
local PANEL_DESIGN_H = 468
local PANEL_SCALE_MIN = 0.32
local PANEL_SCALE_MAX = 1
local VIEWPORT_PADDING = 24

local function getPanelScale()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local usableW = math.max(PANEL_DESIGN_W * PANEL_SCALE_MIN, vp.X - VIEWPORT_PADDING * 2)
	local usableH = math.max(PANEL_DESIGN_H * PANEL_SCALE_MIN, vp.Y - VIEWPORT_PADDING * 2)
	local scale = math.min(usableW / PANEL_DESIGN_W, usableH / PANEL_DESIGN_H)
	return math.clamp(scale, PANEL_SCALE_MIN, PANEL_SCALE_MAX)
end

-- Thumbnail cache to avoid repeated async calls (key = userId .. "_" .. sizeName)
local thumbnailCache = {}

local function getPlayerThumbnail(userId, thumbSize)
	thumbSize = thumbSize or Enum.ThumbnailSize.Size150x150
	local sizeName = tostring(thumbSize.Name)
	local cacheKey = tostring(userId) .. "_" .. sizeName
	if thumbnailCache[cacheKey] then return thumbnailCache[cacheKey] end
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, thumbSize)
	end)
	if ok and content then
		thumbnailCache[cacheKey] = content
		return content
	end
	return nil
end

-- ScreenGui
local sg = Instance.new("ScreenGui")
sg.Name = "LeaderboardGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 45
sg.Parent = playerGui

local function applyPanelScale(pnl)
	MobileWindowLayout.SyncNpcMenuScreenGui(sg, PANEL_DESIGN_W, PANEL_DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(
			pnl,
			MobileWindowLayout.GetNpcFullscreenBoundsConfig(PANEL_DESIGN_W, PANEL_DESIGN_H, {
				mobileDraggable = true,
			})
		)
		return
	end

	sg.IgnoreGuiInset = false
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local scale = getPanelScale()
	local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
	pnl.AnchorPoint = Vector2.new(0.5, 0.5)
	pnl.Size = UDim2.new(0, w, 0, h)
	local centerX = vp.X * 0.5
	local centerY = vp.Y * 0.5
	local yMin = VIEWPORT_PADDING + h * 0.5
	local yMax = vp.Y - VIEWPORT_PADDING - h * 0.5
	local clampedY = math.clamp(centerY, yMin, math.max(yMin, yMax))
	pnl.Position = UDim2.new(0, math.floor(centerX - w * 0.5), 0, math.floor(clampedY - h * 0.5))
	MobileWindowLayout.RestoreDesktopWindow(pnl, { draggable = true })
end

-- Main panel
local panel = Instance.new("Frame")
panel.Name = "LeaderboardPanel"
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
panel.BackgroundColor3 = C.bg
panel.BackgroundTransparency = 0.03
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = true
panel.Draggable = true
panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(50, 55, 70); panelStroke.Thickness = 1; panelStroke.Parent = panel

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = C.bgLight
titleBar.BorderSizePixel = 0
titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -50, 1, 0)
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "LEADERBOARDS"
titleLabel.TextColor3 = C.gold
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextSize = 18
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar
local applyLeaderboardTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(titleLabel, {
	Position = UDim2.new(0, 14, 0, 0),
	Size = UDim2.new(1, -50, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -36, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Tab bar
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -20, 0, 32)
tabBar.Position = UDim2.new(0, 10, 0, 48)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel

local tabs = {
	{ key = "income",   label = "Income" },
	{ key = "battle",   label = "Victories" },
	{ key = "pvp",      label = "PvP" },
	{ key = "monsters", label = "Siegelings" },
}

local currentTab = "income"
local tabButtons = {}
local contentFrame, myRankBar, myRankLabel

-- Content area (top 3 portraits only — no scroll list)
contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -20, 1, -130)
contentFrame.Position = UDim2.new(0, 10, 0, 88)
contentFrame.BackgroundColor3 = C.bgLight
contentFrame.BorderSizePixel = 0
contentFrame.ClipsDescendants = false
contentFrame.Parent = panel
Instance.new("UICorner", contentFrame).CornerRadius = UDim.new(0, 8)

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 10)
listPadding.PaddingLeft = UDim.new(0, 8)
listPadding.PaddingRight = UDim.new(0, 8)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.Parent = contentFrame

-- Player's own rank bar
myRankBar = Instance.new("Frame")
myRankBar.Size = UDim2.new(1, -20, 0, 28)
myRankBar.Position = UDim2.new(0, 10, 1, -36)
myRankBar.BackgroundColor3 = C.playerHL
myRankBar.BorderSizePixel = 0
myRankBar.Parent = panel
Instance.new("UICorner", myRankBar).CornerRadius = UDim.new(0, 6)

myRankLabel = Instance.new("TextLabel")
myRankLabel.Size = UDim2.new(1, -10, 1, 0)
myRankLabel.Position = UDim2.new(0, 10, 0, 0)
myRankLabel.BackgroundTransparency = 1
myRankLabel.Text = "Your Rank: ---"
myRankLabel.TextColor3 = C.text
myRankLabel.Font = Enum.Font.GothamBold
myRankLabel.TextSize = 12
myRankLabel.TextXAlignment = Enum.TextXAlignment.Left
myRankLabel.Parent = myRankBar

local function applyResponsiveContentLayout()
	local mobile = MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H)
	tabBar.Size = mobile and UDim2.new(1, -12, 0, 36) or UDim2.new(1, -20, 0, 32)
	tabBar.Position = mobile and UDim2.new(0, 6, 0, 48) or UDim2.new(0, 10, 0, 48)
	contentFrame.Size = mobile and UDim2.new(1, -12, 1, -140) or UDim2.new(1, -20, 1, -130)
	contentFrame.Position = mobile and UDim2.new(0, 6, 0, 92) or UDim2.new(0, 10, 0, 88)
	myRankBar.Size = mobile and UDim2.new(1, -12, 0, 32) or UDim2.new(1, -20, 0, 28)
	myRankBar.Position = mobile and UDim2.new(0, 6, 1, -40) or UDim2.new(0, 10, 1, -36)

	for _, btn in pairs(tabButtons) do
		btn.TextSize = mobile and 14 or 13
	end
	myRankLabel.TextSize = mobile and 13 or 12
	applyLeaderboardTitleLayout()
end

-- Build tab buttons
local tabGap = 4
for i, tab in ipairs(tabs) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1 / #tabs, -tabGap, 1, 0)
	btn.Position = UDim2.new((i - 1) / #tabs, tabGap * 0.5, 0, 0)
	btn.BackgroundColor3 = C.tabInactive
	btn.Text = tab.label
	btn.TextColor3 = C.textSec
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.BorderSizePixel = 0
	btn.Parent = tabBar
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	tabButtons[tab.key] = btn
end

-- Format a stat value as display text
local function formatEntryValue(entry, isBattle, isPvp)
	if not entry then return "" end
	if isPvp then
		return tostring(entry.value) .. " W / " .. tostring(entry.losses or 0) .. " L"
	elseif isBattle then
		local streakText = ""
		if entry.maxStreak and entry.maxStreak > 0 then
			streakText = " | " .. entry.maxStreak .. " streak"
		end
		return tostring(entry.value) .. " wins" .. streakText
	elseif currentTab == "income" then
		return tostring(entry.value) .. " coins"
	else
		return tostring(entry.value) .. " owned"
	end
end

local THUMB_SMASH_CENTER = Enum.ThumbnailSize.Size420x420
local THUMB_SMASH_SIDE = Enum.ThumbnailSize.Size180x180

-- Smash-style portrait: tilted panel, oversized rank watermark, thick metallic border
local function createSmashPortraitSlot(rank, entry, isBattle, isPvp, slotKind)
	local rankColor = RANK_COLORS[rank] or C.textSec
	local isMe = entry and entry.name == player.Name
	local rotation = slotKind == "left" and -5 or slotKind == "right" and 5 or 0
	local isCenter = slotKind == "center"

	local slot = Instance.new("Frame")
	slot.Name = "SmashSlot_" .. rank
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.ZIndex = isCenter and 3 or 2

	local shadow = Instance.new("Frame")
	shadow.Name = "DropShadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 5, 0.52, 6)
	shadow.Size = UDim2.new(0.86, 0, 0.8, 0)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.Rotation = rotation
	shadow.ZIndex = slot.ZIndex - 1
	shadow.Parent = slot
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 6)

	local tilt = Instance.new("Frame")
	tilt.Name = "PortraitTilt"
	tilt.AnchorPoint = Vector2.new(0.5, 0.5)
	tilt.Position = UDim2.new(0.5, 0, 0.48, 0)
	tilt.Size = UDim2.new(0.92, 0, isCenter and 0.9 or 0.82, 0)
	tilt.BackgroundColor3 = isMe and C.playerHL:Lerp(Color3.new(0, 0, 0), 0.5) or Color3.fromRGB(16, 18, 28)
	tilt.BorderSizePixel = 0
	tilt.Rotation = rotation
	tilt.ZIndex = slot.ZIndex
	tilt.Parent = slot
	Instance.new("UICorner", tilt).CornerRadius = UDim.new(0, 5)

	local tiltGrad = Instance.new("UIGradient")
	tiltGrad.Rotation = 100
	tiltGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(120, 125, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 42, 58)),
	})
	tiltGrad.Transparency = NumberSequence.new(0.88)
	tiltGrad.Parent = tilt

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Color = rankColor
	outerStroke.Thickness = isCenter and 4 or 3
	outerStroke.Transparency = isMe and 0.05 or 0.15
	outerStroke.Parent = tilt

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = Color3.fromRGB(255, 255, 255)
	innerStroke.Thickness = 1
	innerStroke.Transparency = 0.82
	innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerStroke.Parent = tilt

	local bigRank = Instance.new("TextLabel")
	bigRank.Name = "RankWatermark"
	bigRank.Size = UDim2.new(1, 0, 0.42, 0)
	bigRank.Position = UDim2.new(0, 4, 0, -4)
	bigRank.BackgroundTransparency = 1
	bigRank.Text = RANK_LABELS[rank] or ("#" .. tostring(rank))
	bigRank.TextColor3 = rankColor
	bigRank.Font = Enum.Font.GothamBlack
	bigRank.TextSize = isCenter and 52 or 36
	bigRank.TextXAlignment = Enum.TextXAlignment.Left
	bigRank.TextYAlignment = Enum.TextYAlignment.Top
	bigRank.TextTransparency = 0.5
	bigRank.ZIndex = tilt.ZIndex
	bigRank.Parent = tilt

	local avatarImg = Instance.new("ImageLabel")
	avatarImg.Name = "Portrait"
	avatarImg.AnchorPoint = Vector2.new(0.5, 0)
	avatarImg.Position = UDim2.new(0.5, 0, 0.08, 0)
	avatarImg.Size = UDim2.new(1, -12, isCenter and 0.52 or 0.48, 0)
	avatarImg.BackgroundColor3 = Color3.fromRGB(8, 9, 14)
	avatarImg.BackgroundTransparency = 0.2
	avatarImg.BorderSizePixel = 0
	avatarImg.Image = ""
	avatarImg.ScaleType = Enum.ScaleType.Crop
	avatarImg.ZIndex = tilt.ZIndex + 1
	avatarImg.Parent = tilt
	Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(0, 3)

	local avStroke = Instance.new("UIStroke")
	avStroke.Color = rankColor
	avStroke.Thickness = 2
	avStroke.Transparency = 0.35
	avStroke.Parent = avatarImg

	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "NamePlate"
	bottomBar.AnchorPoint = Vector2.new(0.5, 1)
	bottomBar.Position = UDim2.new(0.5, 0, 1, -4)
	bottomBar.Size = UDim2.new(1, -8, 0, isCenter and 52 or 46)
	bottomBar.BackgroundColor3 = rankColor:Lerp(Color3.new(0, 0, 0), 0.72)
	bottomBar.BorderSizePixel = 0
	bottomBar.ZIndex = tilt.ZIndex + 2
	bottomBar.Parent = tilt
	Instance.new("UICorner", bottomBar).CornerRadius = UDim.new(0, 4)

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = rankColor
	barStroke.Thickness = 1
	barStroke.Transparency = 0.4
	barStroke.Parent = bottomBar

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -8, 0.45, 0)
	nameLbl.Position = UDim2.new(0, 4, 0, 3)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = entry and entry.name or "---"
	nameLbl.TextColor3 = isMe and Color3.fromRGB(180, 230, 255) or C.text
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextSize = isCenter and 14 or 12
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.ZIndex = bottomBar.ZIndex
	nameLbl.Parent = bottomBar

	local valueLbl = Instance.new("TextLabel")
	valueLbl.Size = UDim2.new(1, -8, 0.48, 0)
	valueLbl.Position = UDim2.new(0, 4, 0.5, 0)
	valueLbl.BackgroundTransparency = 1
	valueLbl.Text = formatEntryValue(entry, isBattle, isPvp)
	valueLbl.TextColor3 = Color3.fromRGB(255, 248, 220)
	valueLbl.Font = Enum.Font.GothamBold
	valueLbl.TextSize = isCenter and 12 or 10
	valueLbl.TextWrapped = true
	valueLbl.TextXAlignment = Enum.TextXAlignment.Left
	valueLbl.TextYAlignment = Enum.TextYAlignment.Top
	valueLbl.ZIndex = bottomBar.ZIndex
	valueLbl.Parent = bottomBar

	if entry and entry.userId then
		local thumbSize = isCenter and THUMB_SMASH_CENTER or THUMB_SMASH_SIDE
		task.spawn(function()
			local thumb = getPlayerThumbnail(entry.userId, thumbSize)
			if thumb and avatarImg.Parent then
				avatarImg.Image = thumb
			end
		end)
	end

	return slot
end

local SMASH_SLOT_LAYOUT = {
	left = { pos = UDim2.new(0, 2, 0.04, 0), size = UDim2.new(0.30, -4, 0.93, 0) },
	center = { pos = UDim2.new(0.30, 0, 0, 0), size = UDim2.new(0.40, 0, 1, 0) },
	right = { pos = UDim2.new(0.70, -2, 0.04, 0), size = UDim2.new(0.30, -4, 0.93, 0) },
}

-- Refresh leaderboard display
local function refreshLeaderboard()
	-- Update tab button visuals
	for key, btn in pairs(tabButtons) do
		if key == currentTab then
			btn.BackgroundColor3 = C.tabActive
			btn.TextColor3 = C.text
		else
			btn.BackgroundColor3 = C.tabInactive
			btn.TextColor3 = C.textSec
		end
	end

	-- Clear content
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- Fetch data
	local ok, result = pcall(function()
		return getLeaderboardData:InvokeServer(currentTab)
	end)

	if not ok or not result or not result.entries then
		myRankLabel.Text = "Your Rank: ---"
		return
	end

	local isBattle = (currentTab == "battle")
	local isPvp = (currentTab == "pvp")

	-- === TOP 3 — Smash order: 2nd | 1st | 3rd ===
	local podiumContainer = Instance.new("Frame")
	podiumContainer.Name = "PodiumContainer"
	podiumContainer.Size = UDim2.new(1, 0, 1, 0)
	podiumContainer.BackgroundTransparency = 1
	podiumContainer.BorderSizePixel = 0
	podiumContainer.Parent = contentFrame

	for _, spec in ipairs(SMASH_DISPLAY_ORDER) do
		local entry = result.entries[spec.rank]
		local slot = createSmashPortraitSlot(spec.rank, entry, isBattle, isPvp, spec.slot)
		local lay = SMASH_SLOT_LAYOUT[spec.slot]
		slot.Position = lay.pos
		slot.Size = lay.size
		slot.Parent = podiumContainer
	end

	-- Update own rank
	if result.playerRank then
		local valText = tostring(result.playerValue or 0)
		if currentTab == "income" then valText = valText .. " coins"
		elseif currentTab == "battle" then valText = valText .. " wins"
		elseif currentTab == "pvp" then
			valText = valText .. " W / " .. tostring(result.playerLosses or 0) .. " L"
		else valText = valText .. " owned" end
		myRankLabel.Text = "Your Rank: #" .. result.playerRank .. " (" .. valText .. ")"
	else
		myRankLabel.Text = "Your Rank: ---"
	end
end

-- Tab button clicks
for _, tab in ipairs(tabs) do
	tabButtons[tab.key].MouseButton1Click:Connect(function()
		currentTab = tab.key
		refreshLeaderboard()
	end)
end

-- Close
closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	sg.IgnoreGuiInset = false
	MobileWindowLayout.NotifyMenuClosed()
end)

-- Toggle from HUD only (key X and [X] Leaders button both fire HUDToggleMenu from HUDButtonBar)
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
	if menuName == "LeaderboardGUI" then
		if not panel.Visible then applyPanelScale(panel) end
		applyResponsiveContentLayout()
		panel.Visible = not panel.Visible
		if panel.Visible then
			MobileWindowLayout.NotifyMenuOpened()
		else
			MobileWindowLayout.NotifyMenuClosed()
		end
		if panel.Visible then refreshLeaderboard() end
	end
end
getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then child.Event:Connect(onHUDToggle) end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if panel.Visible then
		applyPanelScale(panel)
		applyResponsiveContentLayout()
	else
		sg.IgnoreGuiInset = false
	end
end)

-- FIX #18: Removed fallback X key handler — HUDButtonBar is the sole keyboard handler.
-- Having both caused double-toggle (open then immediately close).
