-- BuffShopClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Press G to open buff shop. Buy buffs with coins or gems.
-- Active buffs shown as icons on the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")


local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local buyBuff = Events:WaitForChild("BuyBuff", 8)
local getInventory = Events:WaitForChild("GetInventory", 8)

-- -- COLORS --
local C = {
	bg = Color3.fromRGB(14, 16, 24),
	card = Color3.fromRGB(22, 26, 38),
	coin = Color3.fromRGB(255, 200, 50),
	gem = Color3.fromRGB(120, 80, 255),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(255, 70, 60),
	muted = Color3.fromRGB(120, 125, 140),
	white = Color3.new(1, 1, 1),
}

local TOP_BADGE_WIDTH = 36
local TOP_BADGE_HEIGHT = 42
local TOP_BADGE_GAP = 8
local TOP_BADGE_START_SLOT = 2
local TOP_BADGE_DISPLAY_ORD = 96
local TOP_BADGE_BG = Color3.fromRGB(18, 22, 32)
local TOP_BADGE_ACCENT = Color3.fromRGB(220, 180, 60)

local function emoji(...)
	return utf8.char(...)
end

local BUFF_EMOJIS = {
	shield = emoji(0x1F6E1, 0xFE0F),
	highjump = emoji(0x1F680),
	speed = emoji(0x26A1, 0xFE0F),
	invuln = emoji(0x2728),
	invis = emoji(0x1F47B),
	swap = emoji(0x1F504),
	lowgrav = emoji(0x1F319),
	regen = emoji(0x2764, 0xFE0F),
	doublejump = emoji(0x1F45F),
	glide = emoji(0x1FA82),
	xpboost = emoji(0x2B50),
	coinboost = emoji(0x1F4B0),
	haste = emoji(0x1F4A8),
	giant = emoji(0x1F5FF),
	glow = emoji(0x1F31F),
	antifall = emoji(0x1FAB6),
	swimspeed = emoji(0x1F42C),
	lucky = emoji(0x1F340),
}

local buffConfigById = {}
for _, item in ipairs(GameConfig.BuffShopItems) do
	buffConfigById[item.id] = item
end

local function getBuffDisplayName(buffId)
	local config = buffConfigById[buffId]
	return (config and config.name) or buffId
end

local function getBuffEmoji(buffId)
	return BUFF_EMOJIS[buffId] or emoji(0x2728)
end

-- Panel scales with viewport (same pattern as InventoryUIManager); width +25%
local PANEL_DESIGN_W = 550
local PANEL_DESIGN_H = 420
local PANEL_SCALE_MIN = 0.52
local PANEL_SCALE_MAX = 1

local function getPanelScale()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local scale = math.min(vp.X / PANEL_DESIGN_W, vp.Y / PANEL_DESIGN_H)
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

	local scale = getPanelScale()
	local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
	pnl.Size = UDim2.new(0, w, 0, h)
	pnl.Position = UDim2.new(0.5, -w/2, 0.5, -h/2)
	MobileWindowLayout.RestoreDesktopWindow(pnl, { draggable = true })
end

-- Simple full-screen FX when a buff activates
local sg
local function playBuffActivatedFX(buffId)
	local existing = sg:FindFirstChild("BuffFX")
	if existing then
		existing:Destroy()
	end

	local fx = Instance.new("Frame")
	fx.Name = "BuffFX"
	fx.Size = UDim2.new(1, 0, 1, 0)
	fx.Position = UDim2.new(0, 0, 0, 0)
	fx.BackgroundColor3 = Color3.new(0, 0, 0)
	fx.BackgroundTransparency = 1
	fx.ZIndex = 50
	fx.Parent = sg

	-- Radial badge in the middle of the screen
	local circle = Instance.new("Frame")
	circle.Size = UDim2.new(0, 120, 0, 120)
	circle.Position = UDim2.new(0.5, -60, 0.5, -60)
	circle.BackgroundColor3 = Color3.fromRGB(30, 220, 120)
	circle.BackgroundTransparency = 0.1
	circle.BorderSizePixel = 0
	circle.ZIndex = 51
	circle.Parent = fx

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle

	local glow = Instance.new("UIStroke")
	glow.Color = Color3.fromRGB(120, 255, 200)
	glow.Thickness = 4
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.Transparency = 0
	glow.Parent = circle

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, -16)
	lbl.Position = UDim2.new(0, 8, 0, 8)
	lbl.BackgroundTransparency = 1
	lbl.Text = getBuffEmoji(buffId)
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 54
	lbl.ZIndex = 52
	lbl.Parent = circle

	local subLbl = Instance.new("TextLabel")
	subLbl.Size = UDim2.new(1, -16, 0, 20)
	subLbl.Position = UDim2.new(0, 8, 1, -34)
	subLbl.BackgroundTransparency = 1
	subLbl.Text = "BUFF ACTIVE"
	subLbl.TextColor3 = Color3.new(1, 1, 1)
	subLbl.Font = Enum.Font.GothamBlack
	subLbl.TextSize = 13
	subLbl.ZIndex = 52
	subLbl.Parent = circle

	-- Pulse + fade out
	local tweenIn = TweenService:Create(circle, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 160, 0, 160),
		BackgroundTransparency = 0.05,
	})
	local tweenGlow = TweenService:Create(glow, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Thickness = 6,
	})
	local tweenOut = TweenService:Create(fx, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})

	tweenIn:Play()
	tweenGlow:Play()

	task.delay(0.25, function()
		tweenOut:Play()
		TweenService:Create(circle, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 200, 0, 200),
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(glow, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		TweenService:Create(lbl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(subLbl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		task.delay(0.45, function()
			if fx.Parent then
				fx:Destroy()
			end
		end)
	end)
end

-- -- SCREEN GUI --
sg = Instance.new("ScreenGui")
sg.Name = "BuffShopGUI"; sg.ResetOnSpawn = false; sg.DisplayOrder = 30; sg.Parent = playerGui

-- Main panel (size/position set on open via applyPanelScale)
local panel = Instance.new("Frame")
panel.Name = "BuffPanel"
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
panel.BackgroundColor3 = C.bg; panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0; panel.Visible = false; panel.Active = true; panel.Draggable = true; panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(60, 70, 100); stroke.Thickness = 2

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 42); titleBar.BackgroundColor3 = Color3.fromRGB(18, 22, 36)
titleBar.BorderSizePixel = 0; titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(0.7, 0, 1, 0); titleLbl.Position = UDim2.new(0, 15, 0, 0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "BUFF SHOP"
titleLbl.TextColor3 = C.coin; titleLbl.Font = Enum.Font.GothamBlack; titleLbl.TextSize = 18
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.Parent = titleBar

-- Currency display (ends before close button so X doesn't overlap Gems)
local currLbl = Instance.new("TextLabel")
currLbl.Name = "CurrLbl"
currLbl.Size = UDim2.new(0.45, -48, 1, 0); currLbl.Position = UDim2.new(0.55, 0, 0, 0)
currLbl.BackgroundTransparency = 1; currLbl.Text = "Coins: 0  |  Gems: 0"
currLbl.TextColor3 = C.muted; currLbl.Font = Enum.Font.GothamBold; currLbl.TextSize = 12
currLbl.TextXAlignment = Enum.TextXAlignment.Right; currLbl.Parent = titleBar

-- Close button (spaced so it doesn't overlap currency)
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32); closeBtn.Position = UDim2.new(1, -40, 0, 5)
closeBtn.BackgroundColor3 = C.red; closeBtn.BackgroundTransparency = 0.5
closeBtn.Text = "X"; closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 14; closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	MobileWindowLayout.NotifyMenuClosed()
end)

-- Scrolling item list
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -55)
scroll.Position = UDim2.new(0, 10, 0, 48)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = C.muted
scroll.Parent = panel

local function applyResponsiveContentLayout()
	local mobile = MobileWindowLayout.IsMobile()
	titleLbl.TextSize = mobile and 22 or 18
	currLbl.TextSize = mobile and 14 or 12
	closeBtn.Size = mobile and UDim2.new(0, 38, 0, 38) or UDim2.new(0, 32, 0, 32)
	closeBtn.Position = mobile and UDim2.new(1, -46, 0, 4) or UDim2.new(1, -40, 0, 5)
	closeBtn.TextSize = mobile and 16 or 14
	scroll.Size = mobile and UDim2.new(1, -12, 1, -60) or UDim2.new(1, -20, 1, -55)
	scroll.Position = mobile and UDim2.new(0, 6, 0, 50) or UDim2.new(0, 10, 0, 48)
end

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6); layout.Parent = scroll

local topBuffBadgeGui
local topBuffBadgeRow
local topBuffBadgeEntries = {}
local topBuffPulseConn

local function ensureTopBuffBadgeGui()
	if topBuffBadgeGui and topBuffBadgeGui.Parent then
		return
	end

	topBuffBadgeGui = Instance.new("ScreenGui")
	topBuffBadgeGui.Name = "ActiveBuffTopBadges"
	topBuffBadgeGui.DisplayOrder = TOP_BADGE_DISPLAY_ORD
	topBuffBadgeGui.ResetOnSpawn = false
	topBuffBadgeGui.IgnoreGuiInset = true
	topBuffBadgeGui.Parent = playerGui

	topBuffBadgeRow = Instance.new("Frame")
	topBuffBadgeRow.Name = "BadgeRow"
	topBuffBadgeRow.Size = UDim2.fromOffset(0, TOP_BADGE_HEIGHT)
	topBuffBadgeRow.AutomaticSize = Enum.AutomaticSize.X
	topBuffBadgeRow.BackgroundTransparency = 1
	topBuffBadgeRow.AnchorPoint = Vector2.new(0, 0.5)
	topBuffBadgeRow.Visible = false
	topBuffBadgeRow.Parent = topBuffBadgeGui

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, TOP_BADGE_GAP)
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = topBuffBadgeRow
end

local function positionTopBuffBadgeRow()
	ensureTopBuffBadgeGui()

	local notifGui = playerGui:FindFirstChild("NotificationGUI")
	local tickerBar = notifGui and notifGui:FindFirstChild("TickerBar")

	if tickerBar then
		local ap = tickerBar.AbsolutePosition
		local as = tickerBar.AbsoluteSize
		local xOffset = ap.X + as.X + TOP_BADGE_GAP + TOP_BADGE_START_SLOT * (TOP_BADGE_WIDTH + TOP_BADGE_GAP)
		topBuffBadgeRow.Position = UDim2.fromOffset(xOffset, math.floor(ap.Y + as.Y / 2))
		topBuffBadgeRow.AnchorPoint = Vector2.new(0, 0.5)
	else
		local fallbackX = 0.86 + (TOP_BADGE_START_SLOT * 0.04)
		topBuffBadgeRow.Position = UDim2.new(fallbackX, 0, 0, 18 + math.floor(TOP_BADGE_HEIGHT * 0.5))
		topBuffBadgeRow.AnchorPoint = Vector2.new(0.5, 0.5)
	end
end

local function refreshTopBuffPulse()
	local hasBadges = next(topBuffBadgeEntries) ~= nil
	if hasBadges and not topBuffPulseConn then
		local elapsed = 0
		topBuffPulseConn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			local t = (math.sin(elapsed * 4 * math.pi) + 1) / 2
			for _, entry in pairs(topBuffBadgeEntries) do
				if entry.stroke and entry.button and entry.button.Parent then
					entry.stroke.Thickness = 2 + t * 1.5
					entry.stroke.Transparency = t * 0.25
				end
			end
		end)
	elseif (not hasBadges) and topBuffPulseConn then
		topBuffPulseConn:Disconnect()
		topBuffPulseConn = nil
	end
end

local function createTopBuffBadge(buffId, order)
	ensureTopBuffBadgeGui()

	local btn = Instance.new("TextButton")
	btn.Name = "BuffBadge_" .. buffId
	btn.Size = UDim2.fromOffset(0, 0)
	btn.LayoutOrder = order
	btn.BackgroundColor3 = TOP_BADGE_BG
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = getBuffEmoji(buffId)
	btn.TextColor3 = C.white
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 20
	btn.AutoButtonColor = false
	btn.ZIndex = 100
	btn.Parent = topBuffBadgeRow
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

	local stroke = Instance.new("UIStroke")
	stroke.Color = TOP_BADGE_ACCENT
	stroke.Thickness = 2
	stroke.Transparency = 0
	stroke.Parent = btn

	local entry = {
		button = btn,
		stroke = stroke,
		name = getBuffDisplayName(buffId),
		remaining = 0,
	}
	topBuffBadgeEntries[buffId] = entry

	btn.MouseButton1Click:Connect(function()
		local liveEntry = topBuffBadgeEntries[buffId]
		if not liveEntry then
			return
		end
		Notify.Toast(liveEntry.name .. " active - " .. tostring(liveEntry.remaining) .. "s left", C.green, 2)
	end)

	TweenService:Create(btn, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(TOP_BADGE_WIDTH, TOP_BADGE_HEIGHT),
		BackgroundTransparency = 0.15,
	}):Play()

	return entry
end

local function collectActiveBuffs()
	if not getInventory then
		return nil
	end

	local ok, data = pcall(function()
		return getInventory:InvokeServer()
	end)
	if not ok or not data then
		return nil
	end

	local now = tick()
	local active = {}
	for buffId, info in pairs(type(data.activeBuffs) == "table" and data.activeBuffs or {}) do
		if type(info) == "table" and info.expiresAt and info.expiresAt > now then
			table.insert(active, {
				id = buffId,
				remaining = math.max(1, math.ceil(info.expiresAt - now)),
				activatedAt = tonumber(info.activatedAt) or math.huge,
			})
		end
	end

	table.sort(active, function(a, b)
		if a.activatedAt == b.activatedAt then
			return getBuffDisplayName(a.id) < getBuffDisplayName(b.id)
		end
		return a.activatedAt < b.activatedAt
	end)

	return active
end

local function updateActiveBuffsDisplay()
	local activeBuffs = collectActiveBuffs()
	if not activeBuffs then
		return
	end
	local activeLookup = {}

	ensureTopBuffBadgeGui()
	positionTopBuffBadgeRow()

	for order, buff in ipairs(activeBuffs) do
		activeLookup[buff.id] = true

		local entry = topBuffBadgeEntries[buff.id]
		if not entry or not entry.button or not entry.button.Parent then
			entry = createTopBuffBadge(buff.id, order)
		end

		entry.button.LayoutOrder = order
		entry.button.Text = getBuffEmoji(buff.id)
		entry.name = getBuffDisplayName(buff.id)
		entry.remaining = buff.remaining
		entry.button.Visible = true
	end

	local staleBuffIds = {}
	for buffId in pairs(topBuffBadgeEntries) do
		if not activeLookup[buffId] then
			table.insert(staleBuffIds, buffId)
		end
	end

	for _, buffId in ipairs(staleBuffIds) do
		local entry = topBuffBadgeEntries[buffId]
		topBuffBadgeEntries[buffId] = nil
		if entry and entry.button and entry.button.Parent then
			local button = entry.button
			TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.22, function()
				if button.Parent then
					button:Destroy()
				end
			end)
		end
	end

	topBuffBadgeRow.Visible = #activeBuffs > 0
	refreshTopBuffPulse()
end

-- Update buff display every 2 seconds
task.spawn(function()
	while true do
		task.wait(2)
		updateActiveBuffsDisplay()
	end
end)

-- -- BUILD ITEM CARDS --

local function refreshCurrency()
	if getInventory then
		local ok, data = pcall(function() return getInventory:InvokeServer() end)
		if ok and data then
			currLbl.Text = "Coins: " .. (data.coins or 0) .. "  |  Gems: " .. (data.gems or 0)
		end
	end
end

local function buildShopItems()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	for i, item in ipairs(GameConfig.BuffShopItems) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 60)
		card.LayoutOrder = i; card.BackgroundColor3 = C.card
		card.BorderSizePixel = 0; card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		-- Name
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.55, 0, 0, 22); name.Position = UDim2.new(0, 12, 0, 6)
		name.BackgroundTransparency = 1; name.Text = item.name
		name.TextColor3 = C.white; name.Font = Enum.Font.GothamBold; name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left; name.Parent = card

		-- Description
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(0.55, 0, 0, 14); desc.Position = UDim2.new(0, 12, 0, 28)
		desc.BackgroundTransparency = 1; desc.Text = item.desc
		desc.TextColor3 = C.muted; desc.Font = Enum.Font.GothamMedium; desc.TextSize = 10
		desc.TextXAlignment = Enum.TextXAlignment.Left; desc.Parent = card

		-- Duration tag
		if item.duration > 0 then
			local durLbl = Instance.new("TextLabel")
			durLbl.Size = UDim2.new(0.3, 0, 0, 12); durLbl.Position = UDim2.new(0, 12, 0, 44)
			durLbl.BackgroundTransparency = 1; durLbl.Text = "" .. item.duration .. "s"
			durLbl.TextColor3 = Color3.fromRGB(100, 140, 180); durLbl.Font = Enum.Font.GothamMedium
			durLbl.TextSize = 9; durLbl.TextXAlignment = Enum.TextXAlignment.Left; durLbl.Parent = card
		end

		-- Buy button(s)
		local btnX = 0.58

		if item.coinCost > 0 then
			local coinBtn = Instance.new("TextButton")
			coinBtn.Size = UDim2.new(0, 85, 0, 30); coinBtn.Position = UDim2.new(btnX, 0, 0.5, -15)
			coinBtn.BackgroundColor3 = Color3.fromRGB(50, 45, 20); coinBtn.BorderSizePixel = 0
			coinBtn.Text = "" .. item.coinCost; coinBtn.TextColor3 = C.coin
			coinBtn.Font = Enum.Font.GothamBold; coinBtn.TextSize = 12; coinBtn.Parent = card
			Instance.new("UICorner", coinBtn).CornerRadius = UDim.new(0, 6)

			coinBtn.MouseButton1Click:Connect(function()
				if not buyBuff then return end
				local ok, success, msg = pcall(function() return buyBuff:InvokeServer(item.id, "coins") end)
				if not ok then
					Notify.Toast(success and tostring(success):sub(1, 60) or "Connection error", C.red, 3, "X")
					return
				end
				if success then
					Notify.Toast("Activated " .. item.name .. "!", C.green, 3, "X")
					refreshCurrency()
					updateActiveBuffsDisplay()
					playBuffActivatedFX(item.id)
				else
					Notify.Toast(msg or "Purchase failed", C.red, 3, "X")
				end
			end)
			btnX = btnX + 0.22
		end

		if item.gemCost > 0 then
			local gemBtn = Instance.new("TextButton")
			gemBtn.Size = UDim2.new(0, 85, 0, 30); gemBtn.Position = UDim2.new(btnX, 0, 0.5, -15)
			gemBtn.BackgroundColor3 = Color3.fromRGB(35, 25, 60); gemBtn.BorderSizePixel = 0
			gemBtn.Text = "" .. item.gemCost; gemBtn.TextColor3 = C.gem
			gemBtn.Font = Enum.Font.GothamBold; gemBtn.TextSize = 12; gemBtn.Parent = card
			Instance.new("UICorner", gemBtn).CornerRadius = UDim.new(0, 6)

			gemBtn.MouseButton1Click:Connect(function()
				if not buyBuff then return end
				local ok, success, msg = pcall(function() return buyBuff:InvokeServer(item.id, "gems") end)
				if not ok then
					Notify.Toast(success and tostring(success):sub(1, 60) or "Connection error", C.red, 3, "X")
					return
				end
				if success then
					Notify.Toast("Activated " .. item.name .. "!", C.green, 3, "X")
					refreshCurrency()
					updateActiveBuffsDisplay()
					playBuffActivatedFX(item.id)
				else
					Notify.Toast(msg or "Purchase failed", C.red, 3, "X")
				end
			end)
		end
	end

	layout:ApplyLayout()
	scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
end

-- Toggle from HUD only (routed from ShopHub via HUDButtonBar)
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
	if menuName == "BuffShopGUI" then
		if not panel.Visible then applyPanelScale(panel) end
		applyResponsiveContentLayout()
		panel.Visible = not panel.Visible
		if panel.Visible then
			MobileWindowLayout.NotifyMenuOpened()
		else
			MobileWindowLayout.NotifyMenuClosed()
		end
		if panel.Visible then
			refreshCurrency()
			buildShopItems()
			updateActiveBuffsDisplay()
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
		applyResponsiveContentLayout()
	end
	positionTopBuffBadgeRow()
end)

-- FIX #18: Removed fallback G key handler — HUDButtonBar is the sole keyboard handler.
-- Having both caused double-toggle (open then immediately close).

buildShopItems()
task.defer(updateActiveBuffsDisplay)
print("[BuffShopClient] Loaded - open via [G] Shop > Buff Shop")
