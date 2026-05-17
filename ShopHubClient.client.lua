-- ShopHubClient.client.lua
-- Last updated: 2026-04-18 21:00
-- Single "Shop" selector that routes to Egg/Buff/Cosmetic/SCoins/Gems shop panels.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function getHUDToggle()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if not evt or not evt:IsA("BindableEvent") then
		evt = Instance.new("BindableEvent")
		evt.Name = "HUDToggleMenu"
		evt.Parent = playerGui
	end
	return evt
end

local ui = Instance.new("ScreenGui")
ui.Name = "ShopHubGUI"
ui.ResetOnSpawn = false
ui.DisplayOrder = 41
ui.IgnoreGuiInset = false
ui.Parent = playerGui

local SHOP_HUB_DESIGN_W = 420
local SHOP_HUB_DESIGN_H = 460

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, SHOP_HUB_DESIGN_W, 0, SHOP_HUB_DESIGN_H)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = true
panel.Draggable = true
panel.Parent = ui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(90, 130, 200)
panelStroke.Thickness = 1.2
panelStroke.Transparency = 0.15
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -56, 0, 36)
title.Position = UDim2.new(0, 14, 0, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235, 240, 255)
title.Text = "Shop"
title.Parent = panel
local applyShopHubTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(title, {
	Position = UDim2.new(0, 14, 0, 8),
	Size = UDim2.new(1, -56, 0, 36),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -20, 0, 20)
subtitle.Position = UDim2.new(0, 14, 0, 40)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 12
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.TextColor3 = Color3.fromRGB(160, 170, 190)
subtitle.Text = "Choose a sub-shop"
subtitle.Parent = panel
local applyShopHubSubtitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(subtitle, {
	Position = UDim2.new(0, 14, 0, 40),
	Size = UDim2.new(1, -20, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Left,
	mobileLeftGutter = 36,
	mobileRightGutter = 36,
})

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -36, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 70)
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.fromRGB(230, 230, 235)
closeBtn.Text = "X"
closeBtn.Parent = panel
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Top
list.Padding = UDim.new(0, 10)

local buttonHolder = Instance.new("Frame")
buttonHolder.Size = UDim2.new(1, -24, 1, -78)
buttonHolder.Position = UDim2.new(0, 12, 0, 66)
buttonHolder.BackgroundTransparency = 1
buttonHolder.Parent = panel
list.Parent = buttonHolder

local function applyPanelScale(frame)
	MobileWindowLayout.SyncNpcMenuScreenGui(ui, SHOP_HUB_DESIGN_W, SHOP_HUB_DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(SHOP_HUB_DESIGN_W, SHOP_HUB_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(frame, MobileWindowLayout.GetNpcFullscreenBoundsConfig(SHOP_HUB_DESIGN_W, SHOP_HUB_DESIGN_H))
		return
	end

	ui.IgnoreGuiInset = false
	local uiScale = frame:FindFirstChild("OpenScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "OpenScale"
		uiScale.Parent = frame
	end
	uiScale.Scale = 0.92
	TweenService:Create(uiScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, SHOP_HUB_DESIGN_W, 0, SHOP_HUB_DESIGN_H)
	MobileWindowLayout.RestoreDesktopWindow(frame, { draggable = true })
end

local function applyResponsiveContentLayout()
	local mobile = MobileWindowLayout.NpcMenuUsesFullscreenBounds(SHOP_HUB_DESIGN_W, SHOP_HUB_DESIGN_H)
	title.TextSize = mobile and 24 or 20
	subtitle.TextSize = mobile and 14 or 12
	closeBtn.Size = mobile and UDim2.new(0, 38, 0, 38) or UDim2.new(0, 28, 0, 28)
	closeBtn.Position = mobile and UDim2.new(1, -48, 0, 8) or UDim2.new(1, -36, 0, 8)
	closeBtn.TextSize = mobile and 20 or 16
	buttonHolder.Size = mobile and UDim2.new(1, -20, 1, -84) or UDim2.new(1, -24, 1, -78)
	buttonHolder.Position = mobile and UDim2.new(0, 10, 0, 70) or UDim2.new(0, 12, 0, 66)
	list.Padding = mobile and UDim.new(0, 12) or UDim.new(0, 10)
	applyShopHubTitleLayout()
	applyShopHubSubtitleLayout()
end

local function makeOptionButton(label, color)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 46)
	btn.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.TextColor3 = color
	btn.Text = label
	btn.AutoButtonColor = false
	btn.Parent = buttonHolder
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Transparency = 0.65
	stroke.Parent = btn

	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Color3.fromRGB(40, 46, 68)
		stroke.Transparency = 0.25
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
		stroke.Transparency = 0.65
	end)

	return btn
end

local eggBtn = makeOptionButton("Egg Shop", Color3.fromRGB(255, 210, 90))
local buffBtn = makeOptionButton("Buff Shop", Color3.fromRGB(110, 230, 150))
local cosmeticBtn = makeOptionButton("Drip Shop", Color3.fromRGB(215, 150, 255))
local scoinsBtn = makeOptionButton("SCoins", Color3.fromRGB(100, 210, 255))
local gemsBtn = makeOptionButton("Gems", Color3.fromRGB(160, 120, 255))

local function openSubShop(menuName)
	panel.Visible = false
	ui.IgnoreGuiInset = false
	MobileWindowLayout.NotifyMenuClosed()
	getHUDToggle():Fire(menuName)
end

eggBtn.MouseButton1Click:Connect(function()
	openSubShop("EggShopGUI")
end)

buffBtn.MouseButton1Click:Connect(function()
	openSubShop("BuffShopGUI")
end)

cosmeticBtn.MouseButton1Click:Connect(function()
	openSubShop("CosmeticShopGUI")
end)

scoinsBtn.MouseButton1Click:Connect(function()
	openSubShop("ScoinsShopGUI")
end)

gemsBtn.MouseButton1Click:Connect(function()
	openSubShop("GemsShopGUI")
end)

closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	ui.IgnoreGuiInset = false
	MobileWindowLayout.NotifyMenuClosed()
end)

local function onHUDToggle(menuName)
	if menuName == "ShopHubGUI" then
		if not panel.Visible then
			applyPanelScale(panel)
		end
		applyResponsiveContentLayout()
		panel.Visible = not panel.Visible
		if panel.Visible then
			MobileWindowLayout.NotifyMenuOpened()
		else
			MobileWindowLayout.NotifyMenuClosed()
		end
	elseif menuName == "EggShopGUI" or menuName == "BuffShopGUI" or menuName == "CosmeticShopGUI"
		or menuName == "ScoinsShopGUI" or menuName == "GemsShopGUI" then
		panel.Visible = false
		ui.IgnoreGuiInset = false
	end
end

getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then
		child.Event:Connect(onHUDToggle)
	end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if panel.Visible then
		applyPanelScale(panel)
		applyResponsiveContentLayout()
	else
		ui.IgnoreGuiInset = false
	end
end)

print("[ShopHubClient] Loaded - press G or click [G] Shop on HUD to open")
