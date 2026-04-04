-- BossBackboardClient.client.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Backboard UI: (1) SiegeSquire Sigils, (2) SiegeKnight Sigils, (3) SiegeLord Sigils (e.g. Badlands — Coming Soon).
-- Toggle with [R] key or "Sigils" HUD button.
--
-- FIX #34: DISABLED — Sigils content has been merged into the tabbed PlayerProfileClient.
-- This file is kept as reference. The early return prevents any UI creation or event listeners.
return

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then warn("[BossBackboard] Events missing") return end

local getInventory = Events:FindFirstChild("GetInventory")
local sigilEarned = Events:FindFirstChild("SigilEarned")

-- Section 1: Elemental bosses (Fire, Ice, Wind, Earth) — defeat in world to earn corresponding SiegeKnight Sigil
local ELEMENTAL_ELEMENTS = GameConfig.ElementalBossElements or { "Fire", "Ice", "Wind", "Earth" }
local ELEMENTAL_TO_ZONE = GameConfig.ElementalBossToZoneId or { Fire = "Desert", Ice = "Cave", Wind = "Ocean", Earth = "Electric" }
-- Section 2: SiegeKnight Sigils (display labels; backend zone ids for data lookup)
local SIEGE_LABELS = GameConfig.SiegeKnightSigilLabels or { "Desert", "Cave", "Ocean", "Cyber" }
local SIEGE_ZONE_IDS = GameConfig.SiegeKnightSigilZoneIds or { "Desert", "Cave", "Ocean", "Electric" }

-- Colors (match InventoryUIManager / profile style)
local C = {
	bg = Color3.fromRGB(14, 15, 22),
	bgLight = Color3.fromRGB(22, 24, 35),
	card = Color3.fromRGB(28, 30, 42),
	accent = Color3.fromRGB(255, 92, 53),
	text = Color3.fromRGB(240, 240, 245),
	textSec = Color3.fromRGB(140, 145, 160),
	textMut = Color3.fromRGB(80, 85, 100),
	income = Color3.fromRGB(50, 220, 120),
	divider = Color3.fromRGB(40, 42, 55),
}

-- Screen GUI
local sg = Instance.new("ScreenGui")
sg.Name = "BossBackboardUI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.DisplayOrder = 15
sg.Parent = playerGui

-- Backboard panel (tall for three sections)
local PANEL_W = 440
local PANEL_H = 540

local main = Instance.new("Frame")
main.Name = "Backboard"
main.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
main.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.Visible = false
main.Active = true
main.Draggable = true
main.Parent = sg

local mainCorner = Instance.new("UICorner", main)
mainCorner.CornerRadius = UDim.new(0, 16)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = C.divider
mainStroke.Thickness = 1

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = C.bgLight
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 16)
local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 14)
headerFix.Position = UDim2.new(0, 0, 1, -14)
headerFix.BackgroundColor3 = C.bgLight
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 16, 0, 0)
title.BackgroundTransparency = 1
title.Text = "COUNCIL OF HOUSES — SIGILS"
title.TextColor3 = C.accent
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 10)
closeBtn.BackgroundColor3 = C.card
closeBtn.Text = "X"
closeBtn.TextColor3 = C.textSec
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- Content area (scrollable, three sections)
local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -32, 1, -64)
content.Position = UDim2.new(0, 16, 0, 56)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.ScrollBarImageColor3 = C.divider
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.Parent = main

local listLayout = Instance.new("UIListLayout", content)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10)

local function getBossDisplayName(element)
	local bossId = CreatureData.GetBossCreatureId and CreatureData.GetBossCreatureId(element, false)
	if not bossId then return element .. " Boss" end
	local creature = CreatureData.GetById and CreatureData.GetById(bossId)
	if creature and creature.displayName then return creature.displayName end
	return element .. " Boss"
end

local function addSectionTitle(parent, layoutOrder, text)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 24)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = C.accent
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = layoutOrder
	lbl.Parent = parent
	return layoutOrder + 1
end

local function addRow(parent, layoutOrder, elementLabel, bossName, statusText, statusColor)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = C.card
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.ClipsDescendants = true
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
	row.Parent = parent

	-- Subtle strip + gradient for depth (kept lightweight; no external assets)
	local tint = Instance.new("Frame")
	tint.Name = "Tint"
	tint.Size = UDim2.new(1, 0, 1, 0)
	tint.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tint.BackgroundTransparency = 0.92
	tint.BorderSizePixel = 0
	tint.ZIndex = 0
	tint.Parent = row
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 130, 160)),
	})
	grad.Rotation = 90
	grad.Parent = tint

	-- Inventory-style background text (watermark)
	local watermark = Instance.new("TextLabel")
	watermark.Name = "RowWatermark"
	watermark.Size = UDim2.new(1, -24, 1, 0)
	watermark.Position = UDim2.new(0, 12, 0, 0)
	watermark.BackgroundTransparency = 1
	watermark.RichText = true
	watermark.Text = bossName and ("<i>" .. bossName .. "</i>") or ""
	watermark.Visible = bossName ~= nil and bossName ~= ""
	watermark.TextColor3 = C.textSec
	watermark.TextTransparency = 0.92
	watermark.Font = Enum.Font.GothamBlack
	watermark.TextScaled = true
	watermark.TextXAlignment = Enum.TextXAlignment.Center
	watermark.TextYAlignment = Enum.TextYAlignment.Center
	watermark.ZIndex = 1
	watermark.Parent = row

	-- Left element label
	local elem = Instance.new("TextLabel")
	elem.Name = "Element"
	elem.Size = UDim2.new(0, 72, 0, 18)
	elem.Position = UDim2.new(0, 12, 0, 10)
	elem.BackgroundTransparency = 1
	elem.Text = tostring(elementLabel or "")
	elem.TextColor3 = C.text
	elem.Font = Enum.Font.GothamBold
	elem.TextSize = 12
	elem.TextXAlignment = Enum.TextXAlignment.Left
	elem.ZIndex = 3
	elem.Parent = row

	-- Small boss name overlay (readable over watermark)
	local bossLbl = Instance.new("TextLabel")
	bossLbl.Name = "BossName"
	bossLbl.Size = UDim2.new(1, -190, 0, 18)
	bossLbl.Position = UDim2.new(0, 88, 0, 10)
	bossLbl.BackgroundTransparency = 1
	bossLbl.Text = tostring(bossName or "")
	bossLbl.TextColor3 = C.textSec
	bossLbl.Font = Enum.Font.GothamMedium
	bossLbl.TextSize = 11
	bossLbl.TextXAlignment = Enum.TextXAlignment.Left
	bossLbl.TextTruncate = Enum.TextTruncate.AtEnd
	bossLbl.ZIndex = 3
	bossLbl.Parent = row

	-- Right status pill (like the mockup's "Not defeated")
	local pill = Instance.new("Frame")
	pill.Name = "StatusPill"
	pill.Size = UDim2.new(0, 118, 0, 26)
	pill.Position = UDim2.new(1, -130, 0.5, -13)
	pill.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.ZIndex = 3
	pill.Parent = row
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Color = C.divider
	pillStroke.Thickness = 1
	pillStroke.Transparency = 0.35
	pillStroke.Parent = pill

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"
	statusLbl.Size = UDim2.new(1, -16, 1, 0)
	statusLbl.Position = UDim2.new(0, 8, 0, 0)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Text = tostring(statusText or "")
	statusLbl.TextColor3 = statusColor or C.textMut
	statusLbl.Font = Enum.Font.GothamMedium
	statusLbl.TextSize = 11
	statusLbl.TextXAlignment = Enum.TextXAlignment.Center
	statusLbl.ZIndex = 4
	statusLbl.Parent = pill
end

local function refreshBackboard()
	for _, child in ipairs(content:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
	end

	local sigils = {}
	if getInventory and getInventory:IsA("RemoteFunction") then
		local ok, data = pcall(function() return getInventory:InvokeServer() end)
		if ok and data then
			sigils = data.sigils or {}
		end
	end

	local function hasSigil(zoneId)
		return sigils[zoneId] == true or sigils[zoneId] == "true"
	end

	local order = 0

	-- Section 1: SiegeSquire Sigils (elemental bosses: Fire, Ice, Wind, Earth)
	order = addSectionTitle(content, order, "SiegeSquire Sigils")
	for i, element in ipairs(ELEMENTAL_ELEMENTS) do
		local zoneId = ELEMENTAL_TO_ZONE and ELEMENTAL_TO_ZONE[element]
		local defeated = zoneId and hasSigil(zoneId)
		addRow(
			content, order,
			element,
			getBossDisplayName(element),
			defeated and "Defeated" or "Not defeated",
			defeated and C.income or C.textMut
		)
		order = order + 1
	end

	order = order + 1  -- gap before next section

	-- Section 2: SiegeKnight Sigils (Desert, Cave, Ocean, Cyber)
	order = addSectionTitle(content, order, "SiegeKnight Sigils")
	for i, label in ipairs(SIEGE_LABELS) do
		local zoneId = SIEGE_ZONE_IDS and SIEGE_ZONE_IDS[i] or label
		local earned = hasSigil(zoneId)
		addRow(
			content, order,
			label,
			"Zone sigil",
			earned and "Earned" or "Not earned",
			earned and C.income or C.textMut
		)
		order = order + 1
	end

	order = order + 1  -- gap before next section

	-- Section 3: SiegeLord Sigils (Badlands — Coming Soon)
	order = addSectionTitle(content, order, "SiegeLord Sigils")
	addRow(content, order, "Badlands", "—", "Coming Soon", C.textMut)
	order = order + 1

	-- Hint
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 36)
	hint.BackgroundTransparency = 1
	hint.Text = "Defeat elemental bosses for SiegeSquire sigils; earn SiegeKnight sigils for zone doors. SiegeLord content coming soon."
	hint.TextColor3 = C.textMut
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 10
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.LayoutOrder = order + 1
	hint.Parent = content
end

closeBtn.MouseButton1Click:Connect(function()
	main.Visible = false
	MobileWindowLayout.NotifyMenuClosed()
end)

local function toggle()
	main.Visible = not main.Visible
	if main.Visible then
		MobileWindowLayout.NotifyMenuOpened()
		if MobileWindowLayout.IsMobile() then
			MobileWindowLayout.ApplyWindow(main, {})
			main.Draggable = true
			content.Size = UDim2.new(1, -20, 1, -64)
			content.Position = UDim2.new(0, 10, 0, 56)
			closeBtn.Size = UDim2.new(0, 38, 0, 38)
			closeBtn.Position = UDim2.new(1, -46, 0, 7)
			closeBtn.TextSize = 16
		else
			main.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
			main.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
			content.Size = UDim2.new(1, -32, 1, -64)
			content.Position = UDim2.new(0, 16, 0, 56)
			closeBtn.Size = UDim2.new(0, 32, 0, 32)
			closeBtn.Position = UDim2.new(1, -40, 0, 10)
			closeBtn.TextSize = 14
			MobileWindowLayout.RestoreDesktopWindow(main, { draggable = true })
		end
		refreshBackboard()
	else
		MobileWindowLayout.NotifyMenuClosed()
	end
end

-- HUD toggle (key R and [R] Sigils button)
local function connectHUD()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if not evt or not evt:IsA("BindableEvent") then
		evt = Instance.new("BindableEvent")
		evt.Name = "HUDToggleMenu"
		evt.Parent = playerGui
	end
	local function onHUDToggle(menuName)
		if menuName == "BossBackboardGUI" then toggle() end
	end
	evt.Event:Connect(onHUDToggle)
end

connectHUD()
if sigilEarned and sigilEarned:IsA("RemoteEvent") then
	sigilEarned.OnClientEvent:Connect(function(zoneId)
		if main.Visible then refreshBackboard() end
	end)
end
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then
		child.Event:Connect(function(menuName)
			if menuName == "BossBackboardGUI" then toggle() end
		end)
	end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if main.Visible then
		if MobileWindowLayout.IsMobile() then
			MobileWindowLayout.ApplyWindow(main, {})
			main.Draggable = true
			content.Size = UDim2.new(1, -20, 1, -64)
			content.Position = UDim2.new(0, 10, 0, 56)
			closeBtn.Size = UDim2.new(0, 38, 0, 38)
			closeBtn.Position = UDim2.new(1, -46, 0, 7)
			closeBtn.TextSize = 16
		else
			main.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
			main.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
			content.Size = UDim2.new(1, -32, 1, -64)
			content.Position = UDim2.new(0, 16, 0, 56)
			closeBtn.Size = UDim2.new(0, 32, 0, 32)
			closeBtn.Position = UDim2.new(1, -40, 0, 10)
			closeBtn.TextSize = 14
			MobileWindowLayout.RestoreDesktopWindow(main, { draggable = true })
		end
	end
end)
