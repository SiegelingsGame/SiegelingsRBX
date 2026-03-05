-- PlayerProfileClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Player profile panel: level, XP, floor upgrades, stats.
-- Toggle with 'P' key or HUD button bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then warn("[Profile] Events missing") return end

local getProfile = Events:WaitForChild("GetProfile", 8)
local buyFloor = Events:WaitForChild("BuyFloor", 8)
local playerLevelUp = Events:WaitForChild("PlayerLevelUp", 8)

-- Colors
local C = {
	bg = Color3.fromRGB(14, 15, 22),
	bgLight = Color3.fromRGB(22, 24, 35),
	card = Color3.fromRGB(28, 30, 42),
	accent = Color3.fromRGB(200, 180, 255),
	text = Color3.fromRGB(240, 240, 245),
	textSec = Color3.fromRGB(140, 145, 160),
	textMut = Color3.fromRGB(80, 85, 100),
	gold = Color3.fromRGB(255, 200, 50),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(220, 60, 70),
	blue = Color3.fromRGB(60, 160, 255),
	xpBar = Color3.fromRGB(130, 100, 255),
	divider = Color3.fromRGB(40, 42, 55),
}

-- Screen GUI
local sg = Instance.new("ScreenGui")
sg.Name = "PlayerProfileUI"; sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; sg.DisplayOrder = 15; sg.Parent = playerGui

-- Main panel
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 420, 0, 520)
main.Position = UDim2.new(0.5, -210, 0.5, -260)
main.BackgroundColor3 = C.bg; main.BorderSizePixel = 0
main.Visible = false; main.Active = true; main.Draggable = true; main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
Instance.new("UIStroke", main).Color = C.divider

-- Header
local hdr = Instance.new("Frame")
hdr.Size = UDim2.new(1, 0, 0, 48); hdr.BackgroundColor3 = C.bgLight
hdr.BorderSizePixel = 0; hdr.Parent = main
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 16)
local hdrFix = Instance.new("Frame")
hdrFix.Size = UDim2.new(1, 0, 0, 14); hdrFix.Position = UDim2.new(0, 0, 1, -14)
hdrFix.BackgroundColor3 = C.bgLight; hdrFix.BorderSizePixel = 0; hdrFix.Parent = hdr

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0); title.Position = UDim2.new(0, 18, 0, 0)
title.BackgroundTransparency = 1; title.Text = "PLAYER PROFILE"
title.TextColor3 = C.accent; title.Font = Enum.Font.GothamBlack
title.TextSize = 17; title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = hdr

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.Position = UDim2.new(1, -38, 0, 9)
closeBtn.BackgroundColor3 = C.card; closeBtn.Text = "X"; closeBtn.TextColor3 = C.textSec
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 13; closeBtn.BorderSizePixel = 0
closeBtn.Parent = hdr; Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- Content scroll
local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -28, 1, -62)
content.Position = UDim2.new(0, 14, 0, 56)
content.BackgroundTransparency = 1; content.BorderSizePixel = 0
content.ScrollBarThickness = 4; content.ScrollBarImageColor3 = C.divider
content.ScrollingDirection = Enum.ScrollingDirection.Y
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new(0, 0, 0, 0); content.Parent = main

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8); layout.Parent = content

-- -- BUILD UI HELPERS --

local function mkSection(text, order)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 22); lbl.BackgroundTransparency = 1
	lbl.Text = text; lbl.TextColor3 = C.accent; lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 11; lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = order; lbl.Parent = content
	return lbl
end

local function mkStatRow(label, value, color, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24); row.BackgroundColor3 = C.card
	row.BorderSizePixel = 0; row.LayoutOrder = order; row.Parent = content
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.6, 0, 1, 0); lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.BackgroundTransparency = 1; lbl.Text = label
	lbl.TextColor3 = C.textSec; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

	local val = Instance.new("TextLabel")
	val.Size = UDim2.new(0.4, -12, 1, 0); val.Position = UDim2.new(0.6, 0, 0, 0)
	val.BackgroundTransparency = 1; val.Text = tostring(value)
	val.TextColor3 = color or C.text; val.Font = Enum.Font.GothamBold; val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Right; val.Parent = row

	return row
end

-- -- REFRESH --

local function refreshProfile()
	for _, ch in ipairs(content:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	if not getProfile then return end
	local ok, data = pcall(function() return getProfile:InvokeServer() end)
	if not ok or not data then
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 50); lbl.BackgroundTransparency = 1
		lbl.Text = "Loading..."; lbl.TextColor3 = C.textMut
		lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13; lbl.Parent = content
		return
	end

	local lvl = data.playerLevel or 1
	local xp = data.playerXP or 0
	local xpNeeded = data.xpNeeded or 100

	-- PLAYER NAME + LEVEL
	local nameFrame = Instance.new("Frame")
	nameFrame.Size = UDim2.new(1, 0, 0, 50); nameFrame.BackgroundColor3 = C.card
	nameFrame.BorderSizePixel = 0; nameFrame.LayoutOrder = 0; nameFrame.Parent = content
	Instance.new("UICorner", nameFrame).CornerRadius = UDim.new(0, 10)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.6, 0, 0, 24); nameLbl.Position = UDim2.new(0, 14, 0, 5)
	nameLbl.BackgroundTransparency = 1; nameLbl.Text = player.Name
	nameLbl.TextColor3 = C.text; nameLbl.Font = Enum.Font.GothamBlack; nameLbl.TextSize = 16
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left; nameLbl.Parent = nameFrame

	local lvlBadge = Instance.new("TextLabel")
	lvlBadge.Size = UDim2.new(0, 80, 0, 24); lvlBadge.Position = UDim2.new(1, -90, 0, 5)
	lvlBadge.BackgroundColor3 = C.xpBar; lvlBadge.BackgroundTransparency = 0.2; lvlBadge.BorderSizePixel = 0
	lvlBadge.Text = "LEVEL " .. lvl; lvlBadge.TextColor3 = Color3.new(1, 1, 1)
	lvlBadge.Font = Enum.Font.GothamBlack; lvlBadge.TextSize = 12; lvlBadge.Parent = nameFrame
	Instance.new("UICorner", lvlBadge).CornerRadius = UDim.new(0, 6)

	-- XP BAR
	local xpBg = Instance.new("Frame")
	xpBg.Size = UDim2.new(1, -28, 0, 10); xpBg.Position = UDim2.new(0, 14, 0, 34)
	xpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 55); xpBg.BorderSizePixel = 0
	xpBg.Parent = nameFrame
	Instance.new("UICorner", xpBg).CornerRadius = UDim.new(0, 4)

	local xpRatio = xpNeeded > 0 and math.clamp(xp / xpNeeded, 0, 1) or 0
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(xpRatio, 0, 1, 0)
	xpFill.BackgroundColor3 = C.xpBar; xpFill.BorderSizePixel = 0; xpFill.Parent = xpBg
	Instance.new("UICorner", xpFill).CornerRadius = UDim.new(0, 4)

	local xpLbl = Instance.new("TextLabel")
	xpLbl.Size = UDim2.new(1, 0, 1, 0); xpLbl.BackgroundTransparency = 1
	xpLbl.Text = xp .. " / " .. xpNeeded .. " XP"
	xpLbl.TextColor3 = Color3.new(1, 1, 1); xpLbl.Font = Enum.Font.GothamBold
	xpLbl.TextSize = 8; xpLbl.Parent = xpBg

	-- ECONOMY
	mkSection("ECONOMY", 1)
	mkStatRow("Coins", tostring(data.coins or 0), C.gold, 2)
	mkStatRow("Gems", tostring(data.gems or 0), C.blue, 3)

	-- BASE FLOORS
	mkSection("BASE FLOORS", 10)

	local ownedFloors = data.ownedFloors or {1}
	local function ownsFloor(n)
		for _, f in ipairs(ownedFloors) do if f == n then return true end end
		return false
	end

	for _, floorNum in ipairs({1, 2, 3}) do
		local owned = ownsFloor(floorNum)
		local floorRow = Instance.new("Frame")
		floorRow.Size = UDim2.new(1, 0, 0, 36); floorRow.BackgroundColor3 = C.card
		floorRow.BorderSizePixel = 0; floorRow.LayoutOrder = 10 + floorNum; floorRow.Parent = content
		Instance.new("UICorner", floorRow).CornerRadius = UDim.new(0, 7)

		local fName = Instance.new("TextLabel")
		fName.Size = UDim2.new(0.35, 0, 1, 0); fName.Position = UDim2.new(0, 12, 0, 0)
		fName.BackgroundTransparency = 1
		fName.Text = "Floor " .. floorNum
		fName.TextColor3 = owned and C.green or C.textMut
		fName.Font = Enum.Font.GothamBold; fName.TextSize = 12
		fName.TextXAlignment = Enum.TextXAlignment.Left; fName.Parent = floorRow

		local fStatus = Instance.new("TextLabel")
		fStatus.Size = UDim2.new(0.3, 0, 1, 0); fStatus.Position = UDim2.new(0.35, 0, 0, 0)
		fStatus.BackgroundTransparency = 1
		fStatus.Font = Enum.Font.GothamMedium; fStatus.TextSize = 10
		fStatus.Parent = floorRow

		if owned then
			fStatus.Text = "OWNED"; fStatus.TextColor3 = C.green
		elseif floorNum == 1 then
			fStatus.Text = "STARTER"; fStatus.TextColor3 = C.green
		else
			local reqLvl = floorNum == 2 and (GameConfig.Floor2LevelReq or 5) or (GameConfig.Floor3LevelReq or 15)
			local cost = floorNum == 2 and (GameConfig.Floor2Cost or 5000) or (GameConfig.Floor3Cost or 15000)
			local meetsLevel = lvl >= reqLvl
			local meetsPrereq = floorNum == 2 or ownsFloor(2)
			fStatus.Text = cost .. " coins | Lv." .. reqLvl
			fStatus.TextColor3 = (meetsLevel and meetsPrereq) and C.gold or C.textMut

			-- Buy button
			local canBuy = meetsLevel and meetsPrereq and (data.coins or 0) >= cost
			local buyBtn = Instance.new("TextButton")
			buyBtn.Size = UDim2.new(0, 60, 0, 24); buyBtn.Position = UDim2.new(1, -68, 0.5, -12)
			buyBtn.BackgroundColor3 = canBuy and C.green or C.divider
			buyBtn.Text = "BUY"; buyBtn.TextColor3 = canBuy and Color3.new(1, 1, 1) or C.textMut
			buyBtn.Font = Enum.Font.GothamBold; buyBtn.TextSize = 10; buyBtn.BorderSizePixel = 0
			buyBtn.Active = canBuy; buyBtn.Parent = floorRow
			Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 5)

			if canBuy then
				buyBtn.MouseButton1Click:Connect(function()
					if buyFloor then
						local ok2, msg = buyFloor:InvokeServer(floorNum)
						if ok2 then
							Notify.Toast("Floor " .. floorNum .. " unlocked!", C.green, 3)
						else
							Notify.Toast(msg or "Failed", C.red, 2)
						end
						task.wait(0.3); refreshProfile()
					end
				end)
			end
		end
	end

	-- Unlock info
	local unlockInfo = Instance.new("TextLabel")
	unlockInfo.Size = UDim2.new(1, 0, 0, 18); unlockInfo.BackgroundTransparency = 1
	unlockInfo.Text = "Floor 2 unlocks the Battle System!"
	unlockInfo.TextColor3 = C.textMut; unlockInfo.Font = Enum.Font.GothamMedium
	unlockInfo.TextSize = 9; unlockInfo.LayoutOrder = 14; unlockInfo.Parent = content

	-- STATS
	mkSection("STATS", 20)
	mkStatRow("Monsters Owned", tostring(data.monstersOwned or 0), C.text, 21)
	mkStatRow("Total Captured", tostring(data.totalCaptured or 0), C.green, 22)
	mkStatRow("Arena Wins", tostring(data.arenaWins or 0), C.gold, 23)
	mkStatRow("Max Win Streak", tostring(data.arenaMaxStreak or 0), Color3.fromRGB(255, 130, 50), 24)
	mkStatRow("Total Income Earned", tostring(data.totalIncome or 0), C.gold, 25)
end

-- -- TOGGLE --

local isVis = false
local function openUI()
	isVis = true; main.Visible = true
	main.Size = UDim2.new(0, 420, 0, 10)
	TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 420, 0, 520)
	}):Play()
	refreshProfile()
end
local function closeUI()
	TweenService:Create(main, TweenInfo.new(0.12), { Size = UDim2.new(0, 420, 0, 10) }):Play()
	task.delay(0.13, function() isVis = false; main.Visible = false; main.Size = UDim2.new(0, 420, 0, 520) end)
end

closeBtn.MouseButton1Click:Connect(closeUI)
-- Toggle from HUD only (key P and [P] Profile button both fire HUDToggleMenu from HUDButtonBar)
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
	if menuName == "ProfileGUI" then
		if isVis then closeUI() else openUI() end
	end
end
getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then child.Event:Connect(onHUDToggle) end
end)

-- P key: open/close profile (client-side fallback)
UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode ~= Enum.KeyCode.P then return end
	onHUDToggle("ProfileGUI")
end)

-- Level up notification listener
if playerLevelUp then
	playerLevelUp.OnClientEvent:Connect(function(newLevel)
		Notify.Banner("LEVEL UP! You are now Level " .. newLevel .. "!", C.xpBar, 4)
		-- Auto-refresh if profile is open
		if isVis then task.wait(0.5); refreshProfile() end
	end)
end

-- Auto-refresh while open
task.spawn(function()
	while true do
		task.wait(10)
		if isVis then refreshProfile() end
	end
end)

print("[PlayerProfileClient] Loaded - press P for profile")
