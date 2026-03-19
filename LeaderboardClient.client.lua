-- LeaderboardClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Full-screen leaderboard panel. Toggle with L key or HUD button.
-- Tabs: Income, Victories, Sieglings. Shows top 10 + player's own rank.

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

-- Panel scales with viewport; on mobile allow smaller scale so it fits on screen
local PANEL_DESIGN_W = 520
local PANEL_DESIGN_H = 480
local PANEL_SCALE_MIN = 0.32
local PANEL_SCALE_MAX = 1
local VIEWPORT_PADDING = 24 -- margin so panel stays inside safe area on mobile

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
	-- Center horizontally; vertically center but clamp so panel stays fully on screen (fixes mobile "slightly below")
	local centerX = vp.X * 0.5
	local centerY = vp.Y * 0.5
	local yMin = VIEWPORT_PADDING + h * 0.5
	local yMax = vp.Y - VIEWPORT_PADDING - h * 0.5
	local clampedY = math.clamp(centerY, yMin, math.max(yMin, yMax))
	pnl.Position = UDim2.new(0, math.floor(centerX - w * 0.5), 0, math.floor(clampedY - h * 0.5))
	MobileWindowLayout.RestoreDesktopWindow(pnl, { draggable = true })
end

-- ScreenGui
local sg = Instance.new("ScreenGui")
sg.Name = "LeaderboardGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 45
sg.Parent = playerGui

-- Main panel (size/position set on open via applyPanelScale)
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

-- Content areavv
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
listLayout.Padding = UDim.new(0, 2)
listLayout.Parent = contentFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 4)
listPadding.PaddingLeft = UDim.new(0, 4)
listPadding.PaddingRight = UDim.new(0, 4)
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

-- Build tab buttons (scale-based so all tabs fit on small/mobile)
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

-- Column header labels
local headerLabels = {
	income = { "Rank", "Player", "Total Income" },
	battle = { "Rank", "Player", "Wins | Best Streak" },
	pvp = { "Rank", "Player", "Wins | Losses" },
	monsters = { "Rank", "Player", "Sieglings Owned" },
}

-- Create a row Frame for a leaderboard entry
local function createRow(i, entry, isBattle, isPvp)
	local isMe = entry and entry.name == player.Name
	local row = Instance.new("Frame")
	row.Name = "Row_" .. i
	row.Size = UDim2.new(1, -8, 0, 32)
	row.BackgroundColor3 = isMe and C.playerHL or (i % 2 == 0 and Color3.fromRGB(22, 24, 35) or Color3.fromRGB(18, 20, 30))
	row.BorderSizePixel = 0
	row.LayoutOrder = i
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

	-- Rank
	local rankColor = i == 1 and C.gold or i == 2 and C.silver or i == 3 and C.bronze or C.textSec
	local rankLbl = Instance.new("TextLabel")
	rankLbl.Size = UDim2.new(0, 40, 1, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.Text = "#" .. i
	rankLbl.TextColor3 = rankColor
	rankLbl.Font = Enum.Font.GothamBlack
	rankLbl.TextSize = 16
	rankLbl.Parent = row

	-- Name
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.45, -45, 1, 0)
	nameLbl.Position = UDim2.new(0, 45, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = entry and entry.name or "---"
	nameLbl.TextColor3 = isMe and Color3.fromRGB(100, 200, 255) or C.text
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.TextSize = 14
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row

	-- Value
	local valueLbl = Instance.new("TextLabel")
	valueLbl.Size = UDim2.new(0.5, -10, 1, 0)
	valueLbl.Position = UDim2.new(0.5, 0, 0, 0)
	valueLbl.BackgroundTransparency = 1
	valueLbl.TextColor3 = C.accent
	valueLbl.Font = Enum.Font.GothamMedium
	valueLbl.TextSize = 13
	valueLbl.TextXAlignment = Enum.TextXAlignment.Right
	valueLbl.Parent = row

	if not entry then
		valueLbl.Text = ""
	elseif isPvp then
		local losses = entry.losses or 0
		valueLbl.Text = tostring(entry.value) .. " W / " .. tostring(losses) .. " L"
	elseif isBattle then
		local streakText = ""
		if entry.maxStreak and entry.maxStreak > 0 then
			streakText = " | " .. entry.maxStreak .. " streak"
		end
		valueLbl.Text = tostring(entry.value) .. " wins" .. streakText
	elseif currentTab == "income" then
		valueLbl.Text = tostring(entry.value) .. " coins"
	else
		valueLbl.Text = tostring(entry.value) .. " owned"
	end

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

	-- Header row
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -8, 0, 24)
	header.BackgroundColor3 = Color3.fromRGB(30, 32, 48)
	header.BorderSizePixel = 0
	header.LayoutOrder = 0
	header.Parent = contentFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

	local cols = headerLabels[currentTab] or { "Rank", "Player", "Value" }
	local hRank = Instance.new("TextLabel")
	hRank.Size = UDim2.new(0, 40, 1, 0); hRank.BackgroundTransparency = 1
	hRank.Text = cols[1]; hRank.TextColor3 = C.textSec
	hRank.Font = Enum.Font.GothamBold; hRank.TextSize = 10; hRank.Parent = header

	local hName = Instance.new("TextLabel")
	hName.Size = UDim2.new(0.45, -45, 1, 0); hName.Position = UDim2.new(0, 45, 0, 0)
	hName.BackgroundTransparency = 1; hName.Text = cols[2]; hName.TextColor3 = C.textSec
	hName.Font = Enum.Font.GothamBold; hName.TextSize = 10
	hName.TextXAlignment = Enum.TextXAlignment.Left; hName.Parent = header

	local hVal = Instance.new("TextLabel")
	hVal.Size = UDim2.new(0.5, -10, 1, 0); hVal.Position = UDim2.new(0.5, 0, 0, 0)
	hVal.BackgroundTransparency = 1; hVal.Text = cols[3]; hVal.TextColor3 = C.textSec
	hVal.Font = Enum.Font.GothamBold; hVal.TextSize = 10
	hVal.TextXAlignment = Enum.TextXAlignment.Right; hVal.Parent = header

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

	-- Create rows
	for i = 1, 10 do
		local entry = result.entries[i]
		local row = createRow(i, entry, isBattle, isPvp)
		row.Parent = contentFrame
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
