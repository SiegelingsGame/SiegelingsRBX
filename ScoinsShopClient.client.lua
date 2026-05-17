-- ScoinsShopClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Last updated: 2026-04-18 21:00
-- Shop hub: buy SCoins with Diamonds (gems).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)
local DiamondNeedHint = require(ReplicatedStorage.Modules:WaitForChild("DiamondNeedHint"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local buyScoinsPack = Events:WaitForChild("BuyScoinsPack", 10)
local getInventory = Events:WaitForChild("GetInventory", 10)
local gemsUpdate = Events:FindFirstChild("GemsUpdate") or Events:WaitForChild("GemsUpdate", 5)
local scoinsUpdate = Events:FindFirstChild("SCoinsUpdate") or Events:WaitForChild("SCoinsUpdate", 5)

local PANEL_DESIGN_W = 440
local PANEL_DESIGN_H = 460

local C = {
	bg = Color3.fromRGB(22, 26, 38),
	card = Color3.fromRGB(28, 32, 48),
	coinGold = Color3.fromRGB(255, 200, 90),
	scoinAccent = Color3.fromRGB(100, 220, 255),
	gem = Color3.fromRGB(140, 100, 255),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(255, 80, 70),
	muted = Color3.fromRGB(140, 145, 165),
	white = Color3.new(1, 1, 1),
}

local sg = Instance.new("ScreenGui")
sg.Name = "ScoinsShopGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 33
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
titleLbl.Size = UDim2.new(0.55, 0, 1, 0)
titleLbl.Position = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 18
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextColor3 = C.scoinAccent
titleLbl.Text = "SCoins Shop"
titleLbl.Parent = titleBar

local currLbl = Instance.new("TextLabel")
currLbl.Size = UDim2.new(0.42, -8, 1, 0)
currLbl.Position = UDim2.new(0.58, 0, 0, 0)
currLbl.BackgroundTransparency = 1
currLbl.Font = Enum.Font.GothamBold
currLbl.TextSize = 11
currLbl.TextXAlignment = Enum.TextXAlignment.Right
currLbl.TextColor3 = C.muted
currLbl.Text = ""
currLbl.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -38, 0, 6)
closeBtn.BackgroundColor3 = C.red
closeBtn.BackgroundTransparency = 0.35
closeBtn.Text = "X"
closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	sg.IgnoreGuiInset = false
	MobileWindowLayout.NotifyMenuClosed()
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -54)
scroll.Position = UDim2.new(0, 10, 0, 48)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.Parent = scroll

local playerGems = 0
local playerScoins = 0

local function refreshBalances()
	if not getInventory then return end
	local ok, data = pcall(function()
		return getInventory:InvokeServer()
	end)
	if ok and data then
		playerGems = data.gems or 0
		playerScoins = data.scoins or 0
		currLbl.Text = string.format("Diamonds: %s  |  SCoins: %s", tostring(playerGems), tostring(playerScoins))
	end
end

if gemsUpdate then
	gemsUpdate.OnClientEvent:Connect(refreshBalances)
end
if scoinsUpdate then
	scoinsUpdate.OnClientEvent:Connect(refreshBalances)
end

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

	for _, pack in ipairs(GameConfig.ScoinsGemPacks or {}) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 56)
		card.BackgroundColor3 = C.card
		card.BorderSizePixel = 0
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.48, 0, 0, 22)
		nameLbl.Position = UDim2.new(0, 12, 0, 8)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 14
		nameLbl.TextColor3 = C.white
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = pack.name
		nameLbl.Parent = card

		local detail = Instance.new("TextLabel")
		detail.Size = UDim2.new(0.55, 0, 0, 18)
		detail.Position = UDim2.new(0, 12, 0, 30)
		detail.BackgroundTransparency = 1
		detail.Font = Enum.Font.GothamMedium
		detail.TextSize = 11
		detail.TextColor3 = C.muted
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.Text = "+" .. tostring(pack.scoins or 0) .. " SCoins"
		detail.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.new(0, 110, 0, 34)
		buyBtn.Position = UDim2.new(1, -118, 0.5, -17)
		buyBtn.BackgroundColor3 = Color3.fromRGB(45, 30, 75)
		buyBtn.TextColor3 = C.gem
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.TextSize = 13
		buyBtn.Text = "" .. tostring(pack.gemCost or 0) .. " ◆"
		buyBtn.BorderSizePixel = 0
		buyBtn.Parent = card
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)

		buyBtn.MouseButton1Click:Connect(function()
			if not buyScoinsPack then return end
			local ok, success, msg = pcall(function()
				return buyScoinsPack:InvokeServer(pack.id)
			end)
			if not ok then
				Notify.Toast("Connection error", C.red, 3)
				return
			end
			if success then
				Notify.Toast(type(msg) == "string" and msg ~= "" and msg or "Purchased!", C.green, 3)
				refreshBalances()
			else
				Notify.Toast(type(msg) == "string" and msg or "Purchase failed", C.red, 3)
				DiamondNeedHint.OnInsufficientDiamonds(success, msg, Notify)
			end
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
	if menuName == "ScoinsShopGUI" then
		if not panel.Visible then
			applyPanelScale()
		end
		panel.Visible = not panel.Visible
		if panel.Visible then
			MobileWindowLayout.NotifyMenuOpened()
			refreshBalances()
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

print("[ScoinsShopClient] Loaded — Shop hub → SCoins")
