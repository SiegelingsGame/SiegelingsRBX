-- BuffShopClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Press G to open buff shop. Buy buffs with coins or gems.
-- Active buffs shown as icons on the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
	local scale = getPanelScale()
	local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
	pnl.Size = UDim2.new(0, w, 0, h)
	pnl.Position = UDim2.new(0.5, -w/2, 0.5, -h/2)
end

-- Simple full-screen FX when a buff activates
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
	lbl.Text = "BUFF ACTIVE"
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.ZIndex = 52
	lbl.Parent = circle

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
		task.delay(0.45, function()
			if fx.Parent then
				fx:Destroy()
			end
		end)
	end)
end

-- -- SCREEN GUI --
local sg = Instance.new("ScreenGui")
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
closeBtn.MouseButton1Click:Connect(function() panel.Visible = false end)

-- Scrolling item list
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -55)
scroll.Position = UDim2.new(0, 10, 0, 48)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = C.muted
scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6); layout.Parent = scroll

-- -- ACTIVE BUFFS HUD (badge style) - defined before buildShopItems so click handlers can call updateActiveBuffsDisplay
local buffBar = Instance.new("Frame")
buffBar.Name = "ActiveBuffs"
buffBar.Size = UDim2.new(0, 400, 0, 52)
buffBar.AnchorPoint = Vector2.new(0.5, 1)
buffBar.Position = UDim2.new(0.5, 0, 1, -120)
buffBar.BackgroundTransparency = 1
buffBar.Parent = sg

local buffLayout = Instance.new("UIListLayout")
buffLayout.FillDirection = Enum.FillDirection.Horizontal
buffLayout.Padding = UDim.new(0, 8)
buffLayout.VerticalAlignment = Enum.VerticalAlignment.Center
buffLayout.SortOrder = Enum.SortOrder.LayoutOrder
buffLayout.Parent = buffBar

local function getBuffShortName(buffId)
	for _, item in ipairs(GameConfig.BuffShopItems) do
		if item.id == buffId then
			local n = item.name or buffId
			if #n > 8 then n = n:sub(1, 8) end
			return n
		end
	end
	return buffId:sub(1, 6)
end

local function updateActiveBuffsDisplay()
	for _, ch in ipairs(buffBar:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	if not getInventory then return end
	local ok, data = pcall(function() return getInventory:InvokeServer() end)
	if not ok or not data or not data.activeBuffs then return end

	local now = tick()
	local order = 0
	for buffId, info in pairs(data.activeBuffs) do
		if info.expiresAt and info.expiresAt > now then
			order = order + 1
			local remaining = math.ceil(info.expiresAt - now)
			local shortName = getBuffShortName(buffId)

			local badge = Instance.new("Frame")
			badge.Name = "BuffBadge_" .. buffId
			badge.Size = UDim2.new(0, 0, 0, 40)
			badge.AutomaticSize = Enum.AutomaticSize.X
			badge.LayoutOrder = order
			badge.BackgroundColor3 = Color3.fromRGB(28, 34, 52)
			badge.BorderSizePixel = 0
			badge.Parent = buffBar

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 20)
			corner.Parent = badge

			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(70, 180, 100)
			stroke.Thickness = 1.5
			stroke.Parent = badge

			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, 12)
			padding.PaddingRight = UDim.new(0, 12)
			padding.PaddingTop = UDim.new(0, 6)
			padding.PaddingBottom = UDim.new(0, 6)
			padding.Parent = badge

			local inner = Instance.new("Frame")
			inner.Size = UDim2.new(0, 0, 1, 0)
			inner.AutomaticSize = Enum.AutomaticSize.X
			inner.BackgroundTransparency = 1
			inner.Parent = badge

			local innerLayout = Instance.new("UIListLayout")
			innerLayout.FillDirection = Enum.FillDirection.Horizontal
			innerLayout.Padding = UDim.new(0, 6)
			innerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
			innerLayout.Parent = inner

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(0, 0, 0, 18)
			nameLbl.AutomaticSize = Enum.AutomaticSize.X
			nameLbl.LayoutOrder = 1
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = shortName
			nameLbl.TextColor3 = Color3.fromRGB(180, 230, 180)
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 11
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.Parent = inner

			local timePill = Instance.new("Frame")
			timePill.Size = UDim2.new(0, 0, 0, 20)
			timePill.AutomaticSize = Enum.AutomaticSize.X
			timePill.LayoutOrder = 2
			timePill.BackgroundColor3 = Color3.fromRGB(20, 45, 30)
			timePill.BorderSizePixel = 0
			timePill.Parent = inner

			local timeCorner = Instance.new("UICorner")
			timeCorner.CornerRadius = UDim.new(0, 10)
			timeCorner.Parent = timePill

			local timePad = Instance.new("UIPadding")
			timePad.PaddingLeft = UDim.new(0, 8)
			timePad.PaddingRight = UDim.new(0, 8)
			timePad.PaddingTop = UDim.new(0, 2)
			timePad.PaddingBottom = UDim.new(0, 2)
			timePad.Parent = timePill

			local timeLbl = Instance.new("TextLabel")
			timeLbl.Size = UDim2.new(0, 0, 1, 0)
			timeLbl.AutomaticSize = Enum.AutomaticSize.X
			timeLbl.BackgroundTransparency = 1
			timeLbl.Text = remaining .. "s"
			timeLbl.TextColor3 = C.green
			timeLbl.Font = Enum.Font.GothamBold
			timeLbl.TextSize = 10
			timeLbl.Parent = timePill
		end
	end
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

-- Toggle from HUD only (key G and [G] Buffs button both fire HUDToggleMenu from HUDButtonBar)
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
		panel.Visible = not panel.Visible
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

-- G key: open/close buff shop (client-side fallback; HUDButtonBar also fires HUDToggleMenu)
UserInputService.InputBegan:Connect(function(input, gp)
	if UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode ~= Enum.KeyCode.G then return end
	onHUDToggle("BuffShopGUI")
end)

buildShopItems()
print("[BuffShopClient] Loaded - press G or click [G] Buffs on HUD to open")