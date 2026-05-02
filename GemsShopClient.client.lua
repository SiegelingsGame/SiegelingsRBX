-- GemsShopClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Last updated: 2026-04-18 21:00
-- Shop hub: buy Diamonds (gems) with Robux via Developer Products.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PANEL_DESIGN_W = 440
local PANEL_DESIGN_H = 460

local C = {
	bg = Color3.fromRGB(22, 26, 38),
	card = Color3.fromRGB(28, 32, 48),
	gem = Color3.fromRGB(140, 100, 255),
	robux = Color3.fromRGB(60, 200, 120),
	muted = Color3.fromRGB(140, 145, 165),
	white = Color3.new(1, 1, 1),
}

local WHITE = Color3.new(1, 1, 1)

local sg = Instance.new("ScreenGui")
sg.Name = "GemsShopGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 200
sg.ZIndexBehavior = Enum.ZIndexBehavior.Global
sg.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W / 2, 0.5, -PANEL_DESIGN_H / 2)
panel.BackgroundColor3 = C.bg
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = true
panel.Draggable = true
panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 42)
titleBar.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -52, 1, 0)
titleLbl.Position = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 18
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextColor3 = C.gem
titleLbl.Text = "Diamonds (Robux)"
titleLbl.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -38, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 70)
closeBtn.BackgroundTransparency = 0.35
closeBtn.Text = "X"
closeBtn.TextColor3 = WHITE
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	sg.IgnoreGuiInset = false
	MobileWindowLayout.NotifyMenuClosed()
end)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -24, 0, 28)
hint.Position = UDim2.new(0, 12, 0, 46)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 11
hint.TextColor3 = C.muted
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "Purchase packs with Robux. Set Developer Product IDs in GameConfig.GemsRobuxPacks for each tier."
hint.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -88)
scroll.Position = UDim2.new(0, 10, 0, 78)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.Parent = scroll

local function applyPanelScale()
	MobileWindowLayout.SyncNpcMenuScreenGui(sg, PANEL_DESIGN_W, PANEL_DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(panel, MobileWindowLayout.GetNpcFullscreenBoundsConfig(PANEL_DESIGN_W, PANEL_DESIGN_H))
	else
		sg.IgnoreGuiInset = false
		panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
		panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W / 2, 0.5, -PANEL_DESIGN_H / 2)
		MobileWindowLayout.RestoreDesktopWindow(panel, { draggable = true })
	end
end

local function buildList()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end

	for _, pack in ipairs(GameConfig.GemsRobuxPacks or {}) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 58)
		card.BackgroundColor3 = C.card
		card.BorderSizePixel = 0
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.45, 0, 0, 22)
		nameLbl.Position = UDim2.new(0, 12, 0, 8)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 14
		nameLbl.TextColor3 = C.white
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = pack.name
		nameLbl.Parent = card

		local gemsLbl = Instance.new("TextLabel")
		gemsLbl.Size = UDim2.new(0.5, 0, 0, 18)
		gemsLbl.Position = UDim2.new(0, 12, 0, 32)
		gemsLbl.BackgroundTransparency = 1
		gemsLbl.Font = Enum.Font.GothamMedium
		gemsLbl.TextSize = 11
		gemsLbl.TextColor3 = C.gem
		gemsLbl.TextXAlignment = Enum.TextXAlignment.Left
		gemsLbl.Text = "+" .. tostring(pack.gems or 0) .. " Diamonds"
		gemsLbl.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.new(0, 130, 0, 36)
		buyBtn.Position = UDim2.new(1, -138, 0.5, -18)
		buyBtn.BackgroundColor3 = Color3.fromRGB(35, 75, 50)
		buyBtn.TextColor3 = C.robux
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.TextSize = 13
		local r = tonumber(pack.robuxListPrice) or 0
		buyBtn.Text = "R$ " .. tostring(r)
		buyBtn.BorderSizePixel = 0
		buyBtn.Parent = card
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)

		local pid = tonumber(pack.productId) or 0
		buyBtn.Active = pid > 0

		buyBtn.MouseButton1Click:Connect(function()
			if pid <= 0 then
				Notify.Toast("Configure productId for this tier in GameConfig.GemsRobuxPacks", C.muted, 4)
				return
			end
			buyBtn.Text = "..."
			MarketplaceService:PromptProductPurchase(player, pid)
			task.delay(2, function()
				buyBtn.Text = "R$ " .. tostring(r)
			end)
		end)
	end

	layout:ApplyLayout()
	scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
end

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
	if menuName == "GemsShopGUI" then
		if not panel.Visible then
			applyPanelScale()
		end
		panel.Visible = not panel.Visible
		if panel.Visible then
			MobileWindowLayout.NotifyMenuOpened()
			buildList()
		else
			MobileWindowLayout.NotifyMenuClosed()
			sg.IgnoreGuiInset = false
		end
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
		applyPanelScale()
		buildList()
	else
		sg.IgnoreGuiInset = false
	end
end)

print("[GemsShopClient] Loaded — Shop hub → Gems (Robux)")
