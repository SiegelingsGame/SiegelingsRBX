-- LeaderboardClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Full-screen leaderboard panel. Toggle with L key or HUD button.
-- Tabs: Income, Victories, PvP, Sieglings.
-- Shows top 3 with avatars + runner-ups (4th+) at the bottom.

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

-- Panel scales with viewport; on mobile allow smaller scale so it fits on screen
local PANEL_DESIGN_W = 540
local PANEL_DESIGN_H = 520
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

local function applyPanelScale(pnl)
	if MobileWindowLayout.IsMobile() then
		MobileWindowLayout.ApplyWindow(pnl, {
			leftInset = 14,
			rightInset = 14,
			topInset = 10,
			bottomInset = 14,
			bottomMobileExtra = 20,
		})
		pnl.Draggable = true
		return
	end

	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local scale = getPanelScale()
	local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
	pnl.Size = UDim2.new(0, w, 0, h)
	local centerX = vp.X * 0.5
	local centerY = vp.Y * 0.5
	local yMin = VIEWPORT_PADDING + h * 0.5
	local yMax = vp.Y - VIEWPORT_PADDING - h * 0.5
	local clampedY = math.clamp(centerY, yMin, math.max(yMin, yMax))
	pnl.Position = UDim2.new(0, math.floor(centerX - w * 0.5), 0, math.floor(clampedY - h * 0.5))
	MobileWindowLayout.RestoreDesktopWindow(pnl, { draggable = true })
end

-- Thumbnail cache to avoid repeated async calls
local thumbnailCache = {}

local function getPlayerThumbnail(userId)
	if thumbnailCache[userId] then return thumbnailCache[userId] end
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and content then
		thumbnailCache[userId] = content
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
	{ key = "monsters", label = "Sieglings" },
}

local currentTab = "income"
local tabButtons = {}
local contentFrame, myRankBar, myRankLabel

-- Content area (ScrollingFrame for the whole content including podium + runners)
contentFrame = Instance.new("ScrollingFrame")
contentFrame.Size = UDim2.new(1, -20, 1, -130)
contentFrame.Position = UDim2.new(0, 10, 0, 88)
contentFrame.BackgroundColor3 = C.bgLight
contentFrame.BorderSizePixel = 0
contentFrame.ScrollBarThickness = 4
contentFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 85, 100)
contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
contentFrame.Parent = panel
Instance.new("UICorner", contentFrame).CornerRadius = UDim.new(0, 8)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = contentFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 6)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.PaddingBottom = UDim.new(0, 6)
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
	local mobile = MobileWindowLayout.IsMobile()
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

-- Create a podium card for a top-3 player
local function createPodiumCard(rank, entry, isBattle, isPvp)
	local rankColor = RANK_COLORS[rank] or C.textSec
	local isMe = entry and entry.name == player.Name

	local card = Instance.new("Frame")
	card.Name = "Podium_" .. rank
	card.Size = UDim2.new(1 / 3, -6, 0, 150)
	card.BackgroundColor3 = isMe and C.playerHL or C.card
	card.BorderSizePixel = 0
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = rankColor
	cardStroke.Thickness = rank == 1 and 2 or 1
	cardStroke.Transparency = 0.4
	cardStroke.Parent = card

	-- Rank badge at top
	local rankBadge = Instance.new("TextLabel")
	rankBadge.Size = UDim2.new(1, 0, 0, 20)
	rankBadge.Position = UDim2.new(0, 0, 0, 4)
	rankBadge.BackgroundTransparency = 1
	rankBadge.Text = RANK_LABELS[rank] or ("#" .. rank)
	rankBadge.TextColor3 = rankColor
	rankBadge.Font = Enum.Font.GothamBlack
	rankBadge.TextSize = rank == 1 and 16 or 13
	rankBadge.Parent = card

	-- Avatar image
	local avatarFrame = Instance.new("Frame")
	avatarFrame.Size = UDim2.new(0, 60, 0, 60)
	avatarFrame.Position = UDim2.new(0.5, -30, 0, 26)
	avatarFrame.BackgroundColor3 = Color3.fromRGB(35, 37, 50)
	avatarFrame.BorderSizePixel = 0
	avatarFrame.Parent = card
	Instance.new("UICorner", avatarFrame).CornerRadius = UDim.new(1, 0)

	local avatarStroke = Instance.new("UIStroke")
	avatarStroke.Color = rankColor
	avatarStroke.Thickness = 2
	avatarStroke.Parent = avatarFrame

	local avatarImg = Instance.new("ImageLabel")
	avatarImg.Size = UDim2.new(1, 0, 1, 0)
	avatarImg.BackgroundTransparency = 1
	avatarImg.Image = ""
	avatarImg.ScaleType = Enum.ScaleType.Fit
	avatarImg.Parent = avatarFrame
	Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(1, 0)

	-- Load thumbnail async
	if entry and entry.userId then
		task.spawn(function()
			local thumb = getPlayerThumbnail(entry.userId)
			if thumb and avatarImg.Parent then
				avatarImg.Image = thumb
			end
		end)
	end

	-- Player name
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -8, 0, 16)
	nameLbl.Position = UDim2.new(0, 4, 0, 90)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = entry and entry.name or "---"
	nameLbl.TextColor3 = isMe and Color3.fromRGB(100, 200, 255) or C.text
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 12
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Parent = card

	-- Stat value
	local valueLbl = Instance.new("TextLabel")
	valueLbl.Size = UDim2.new(1, -8, 0, 28)
	valueLbl.Position = UDim2.new(0, 4, 0, 108)
	valueLbl.BackgroundTransparency = 1
	valueLbl.Text = formatEntryValue(entry, isBattle, isPvp)
	valueLbl.TextColor3 = C.accent
	valueLbl.Font = Enum.Font.GothamMedium
	valueLbl.TextSize = 11
	valueLbl.TextWrapped = true
	valueLbl.Parent = card

	return card
end

-- Create a compact row for runner-up entries (4th+)
local function createRunnerUpRow(i, entry, isBattle, isPvp)
	local isMe = entry and entry.name == player.Name
	local row = Instance.new("Frame")
	row.Name = "RunnerUp_" .. i
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = isMe and C.playerHL or (i % 2 == 0 and Color3.fromRGB(22, 24, 35) or Color3.fromRGB(18, 20, 30))
	row.BorderSizePixel = 0
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

	-- Rank
	local rankLbl = Instance.new("TextLabel")
	rankLbl.Size = UDim2.new(0, 32, 1, 0)
	rankLbl.Position = UDim2.new(0, 4, 0, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.Text = "#" .. i
	rankLbl.TextColor3 = C.textSec
	rankLbl.Font = Enum.Font.GothamBold
	rankLbl.TextSize = 13
	rankLbl.Parent = row

	-- Small avatar
	local miniAvatar = Instance.new("ImageLabel")
	miniAvatar.Size = UDim2.new(0, 22, 0, 22)
	miniAvatar.Position = UDim2.new(0, 38, 0.5, -11)
	miniAvatar.BackgroundColor3 = Color3.fromRGB(35, 37, 50)
	miniAvatar.BorderSizePixel = 0
	miniAvatar.Image = ""
	miniAvatar.ScaleType = Enum.ScaleType.Fit
	miniAvatar.Parent = row
	Instance.new("UICorner", miniAvatar).CornerRadius = UDim.new(1, 0)

	if entry and entry.userId then
		task.spawn(function()
			local thumb = getPlayerThumbnail(entry.userId)
			if thumb and miniAvatar.Parent then
				miniAvatar.Image = thumb
			end
		end)
	end

	-- Name
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.4, -68, 1, 0)
	nameLbl.Position = UDim2.new(0, 66, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = entry and entry.name or "---"
	nameLbl.TextColor3 = isMe and Color3.fromRGB(100, 200, 255) or C.text
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.TextSize = 12
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Parent = row

	-- Value
	local valueLbl = Instance.new("TextLabel")
	valueLbl.Size = UDim2.new(0.5, -10, 1, 0)
	valueLbl.Position = UDim2.new(0.5, 0, 0, 0)
	valueLbl.BackgroundTransparency = 1
	valueLbl.Text = formatEntryValue(entry, isBattle, isPvp)
	valueLbl.TextColor3 = C.accent
	valueLbl.Font = Enum.Font.GothamMedium
	valueLbl.TextSize = 12
	valueLbl.TextXAlignment = Enum.TextXAlignment.Right
	valueLbl.Parent = row

	return row
end

-- Refresh leaderboard display
local function refreshLeaderboard()
	local savedScrollY = contentFrame.CanvasPosition.Y

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
		task.defer(function()
			task.wait()
			local maxScroll = math.max(0, contentFrame.CanvasSize.Y.Offset - contentFrame.AbsoluteWindowSize.Y)
			contentFrame.CanvasPosition = Vector2.new(0, math.min(savedScrollY, maxScroll))
		end)
		return
	end

	local isBattle = (currentTab == "battle")
	local isPvp = (currentTab == "pvp")

	-- === TOP 3 PODIUM ===
	local podiumContainer = Instance.new("Frame")
	podiumContainer.Name = "PodiumContainer"
	podiumContainer.Size = UDim2.new(1, 0, 0, 158)
	podiumContainer.BackgroundTransparency = 1
	podiumContainer.LayoutOrder = 1
	podiumContainer.Parent = contentFrame

	for rank = 1, 3 do
		local entry = result.entries[rank]
		local card = createPodiumCard(rank, entry, isBattle, isPvp)
		card.Position = UDim2.new((rank - 1) / 3, 3, 0, 0)
		card.Parent = podiumContainer
	end

	-- === RUNNER-UPS SECTION (4th+) ===
	if #result.entries > 3 then
		-- Divider / section header
		local runnerHeader = Instance.new("Frame")
		runnerHeader.Name = "RunnerUpHeader"
		runnerHeader.Size = UDim2.new(1, 0, 0, 24)
		runnerHeader.BackgroundColor3 = Color3.fromRGB(30, 32, 48)
		runnerHeader.BorderSizePixel = 0
		runnerHeader.LayoutOrder = 2
		runnerHeader.Parent = contentFrame
		Instance.new("UICorner", runnerHeader).CornerRadius = UDim.new(0, 4)

		local runnerTitle = Instance.new("TextLabel")
		runnerTitle.Size = UDim2.new(1, -10, 1, 0)
		runnerTitle.Position = UDim2.new(0, 10, 0, 0)
		runnerTitle.BackgroundTransparency = 1
		runnerTitle.Text = "RUNNER-UPS"
		runnerTitle.TextColor3 = C.textSec
		runnerTitle.Font = Enum.Font.GothamBold
		runnerTitle.TextSize = 10
		runnerTitle.TextXAlignment = Enum.TextXAlignment.Left
		runnerTitle.Parent = runnerHeader

		-- Runner-up rows
		for i = 4, #result.entries do
			local entry = result.entries[i]
			local row = createRunnerUpRow(i, entry, isBattle, isPvp)
			row.LayoutOrder = i
			row.Parent = contentFrame
		end
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

	-- Restore scroll position after layout updates
	task.defer(function()
		task.wait()
		local maxScroll = math.max(0, contentFrame.CanvasSize.Y.Offset - contentFrame.AbsoluteWindowSize.Y)
		contentFrame.CanvasPosition = Vector2.new(0, math.min(savedScrollY, maxScroll))
	end)
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
	end
end)

-- FIX #18: Removed fallback X key handler — HUDButtonBar is the sole keyboard handler.
-- Having both caused double-toggle (open then immediately close).
