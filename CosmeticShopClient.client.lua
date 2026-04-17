-- CosmeticShopClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Press C to open cosmetic shop. Buy trails, auras, name colors, base exteriors.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")


local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local buyCosmetic = Events:WaitForChild("BuyCosmetic", 8)
local equipCosmetic = Events:WaitForChild("EquipCosmetic", 8)
local buyExterior = Events:FindFirstChild("BuyExterior") or Events:WaitForChild("BuyExterior", 5)
local equipExterior = Events:FindFirstChild("EquipExterior") or Events:WaitForChild("EquipExterior", 5)
local buyBaseColor = Events:FindFirstChild("BuyBaseColor") or Events:WaitForChild("BuyBaseColor", 5)
local equipBaseColor = Events:FindFirstChild("EquipBaseColor") or Events:WaitForChild("EquipBaseColor", 5)
local getInventory = Events:WaitForChild("GetInventory", 8)
local coinsUpdate = Events:FindFirstChild("CoinsUpdate") or Events:WaitForChild("CoinsUpdate", 3)

-- -- COLORS --.
local C = {
	bg = Color3.fromRGB(26, 26, 36),
	card = Color3.fromRGB(22, 26, 38),
	cardOwned = Color3.fromRGB(18, 35, 25),
	coin = Color3.fromRGB(255, 200, 50),
	gem = Color3.fromRGB(120, 80, 255),
	green = Color3.fromRGB(80, 220, 120),
	equipped = Color3.fromRGB(60, 200, 255),
	red = Color3.fromRGB(255, 70, 60),
	muted = Color3.fromRGB(120, 125, 140),
	white = Color3.new(1, 1, 1),
	-- Portrait mobile (SiegelinQ-style accents)
	accentOrange = Color3.fromRGB(255, 130, 45),
	tabInactive = Color3.fromRGB(35, 38, 48),
	statusBar = Color3.fromRGB(22, 24, 32),
	closeMuted = Color3.fromRGB(58, 60, 72),
	equippedRingPortrait = Color3.fromRGB(255, 210, 72),
}

-- Panel scales with viewport (same pattern as other shops)
local PANEL_DESIGN_W = 440
local PANEL_DESIGN_H = 480
local PANEL_SCALE_MIN = 0.52
local PANEL_SCALE_MAX = 1
local sg

local function getViewportSize()
	local camera = workspace.CurrentCamera
	return (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
end

local function isMobilePortrait()
	if not MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H) then
		return false
	end
	local vp = getViewportSize()
	return vp.Y >= vp.X
end

local function getPanelScale()
	local vp = getViewportSize()
	local scale = math.min(vp.X / PANEL_DESIGN_W, vp.Y / PANEL_DESIGN_H)
	return math.clamp(scale, PANEL_SCALE_MIN, PANEL_SCALE_MAX)
end

local function applyPanelScale(pnl)
	MobileWindowLayout.SyncNpcMenuScreenGui(sg, PANEL_DESIGN_W, PANEL_DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H) then
		local portrait = isMobilePortrait()
		MobileWindowLayout.ApplyWindow(
			pnl,
			MobileWindowLayout.GetNpcFullscreenBoundsConfig(PANEL_DESIGN_W, PANEL_DESIGN_H, {
				mobileDraggable = not portrait,
			})
		)
		pnl.Draggable = not portrait
		return
	end

	sg.IgnoreGuiInset = false
	local scale = getPanelScale()
	local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
	pnl.Size = UDim2.new(0, w, 0, h)
	pnl.Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2)
	MobileWindowLayout.RestoreDesktopWindow(pnl, { draggable = true })
end

-- -- SCREEN GUI --
sg = Instance.new("ScreenGui")
sg.Name = "CosmeticShopGUI"; sg.ResetOnSpawn = false; sg.DisplayOrder = 31; sg.Parent = playerGui

-- Main panel (size/position set on open via applyPanelScale; draggable)
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
panel.BackgroundColor3 = C.bg; panel.BackgroundTransparency = 0.02
panel.BorderSizePixel = 0; panel.Visible = false; panel.Active = true; panel.Draggable = true; panel.Parent = sg
local panelCorner = Instance.new("UICorner", panel)
panelCorner.CornerRadius = UDim.new(0, 14)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(80, 60, 120)
panelStroke.Thickness = 1

-- Title
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 42); titleBar.BackgroundColor3 = Color3.fromRGB(18, 22, 36)
titleBar.BorderSizePixel = 0; titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(0.6, 0, 1, 0); titleLbl.Position = UDim2.new(0, 15, 0, 0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "DRIP SHOP"
titleLbl.TextColor3 = C.gem; titleLbl.Font = Enum.Font.GothamBlack; titleLbl.TextSize = 18
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.Parent = titleBar

-- Second row on portrait mobile: coins / gems (reference-style status strip)
local statusBar = Instance.new("Frame")
statusBar.Name = "StatusBar"
statusBar.Size = UDim2.new(1, 0, 0, 34)
statusBar.Position = UDim2.new(0, 0, 0, 42)
statusBar.BackgroundColor3 = C.statusBar
statusBar.BorderSizePixel = 0
statusBar.Visible = false
statusBar.Parent = panel

local currLbl = Instance.new("TextLabel")
currLbl.Name = "CurrLbl"
currLbl.Size = UDim2.new(0.45, -48, 1, 0); currLbl.Position = UDim2.new(0.55, 0, 0, 0)
currLbl.BackgroundTransparency = 1; currLbl.Text = "Coins: 0  |  Gems: 0"
currLbl.TextColor3 = C.muted; currLbl.Font = Enum.Font.GothamBold; currLbl.TextSize = 12
currLbl.TextXAlignment = Enum.TextXAlignment.Right; currLbl.Parent = titleBar

local playerCoins = 0
local playerGems = 0
local function updateCurrencyLabel()
	if currLbl.RichText then
		currLbl.Text = string.format(
			'<font color="#ff822d">Coins:</font> <font color="#b8bcc8">%s</font>    <font color="#ff822d">Gems:</font> <font color="#b8bcc8">%s</font>',
			tostring(playerCoins or 0),
			tostring(playerGems or 0)
		)
	else
		currLbl.Text = "Coins: " .. tostring(playerCoins or 0) .. "  |  Gems: " .. tostring(playerGems or 0)
	end
end

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32); closeBtn.Position = UDim2.new(1, -40, 0, 5)
closeBtn.BackgroundColor3 = C.red; closeBtn.BackgroundTransparency = 0.5
closeBtn.Text = "X"; closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 14; closeBtn.Parent = titleBar
local closeCorner = Instance.new("UICorner", closeBtn)
closeCorner.CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	sg.IgnoreGuiInset = false
	MobileWindowLayout.NotifyMenuClosed()
end)

if coinsUpdate then
	coinsUpdate.OnClientEvent:Connect(function(balance)
		playerCoins = balance
		updateCurrencyLabel()
	end)
end

-- Tab buttons (desktop: even row on tabFrame; portrait mobile: horizontal scroll in tabScroll)
local tabFrame = Instance.new("Frame")
tabFrame.Size = UDim2.new(1, -20, 0, 30); tabFrame.Position = UDim2.new(0, 10, 0, 48)
tabFrame.BackgroundTransparency = 1; tabFrame.ClipsDescendants = false; tabFrame.Parent = panel

local tabScroll = Instance.new("ScrollingFrame")
tabScroll.Name = "TabScroll"
tabScroll.Size = UDim2.new(1, 0, 1, 0)
tabScroll.Position = UDim2.new(0, 0, 0, 0)
tabScroll.BackgroundTransparency = 1
tabScroll.BorderSizePixel = 0
tabScroll.ScrollBarThickness = 0
tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
tabScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
tabScroll.Visible = false
tabScroll.Parent = tabFrame

local tabList = Instance.new("Frame")
tabList.Name = "TabList"
tabList.BackgroundTransparency = 1
tabList.Size = UDim2.new(0, 0, 1, 0)
tabList.AutomaticSize = Enum.AutomaticSize.X
tabList.Parent = tabScroll

local tabListLayout = Instance.new("UIListLayout")
tabListLayout.FillDirection = Enum.FillDirection.Horizontal
tabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabListLayout.Padding = UDim.new(0, 6)
tabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabListLayout.Parent = tabList

local tabs = {"trail", "aura", "nameColor", "exterior", "baseColor"}
local tabLabels = {trail = "Trails", aura = "Auras", nameColor = "Names", exterior = "Base", baseColor = "Colors"}
local activeTab = "trail"
local tabButtons = {}

for i, tab in ipairs(tabs) do
	local btn = Instance.new("TextButton")
	btn.Name = "Tab_" .. tab
	btn.LayoutOrder = i
	btn.Size = UDim2.new(1 / #tabs, -4, 1, 0)
	btn.Position = UDim2.new((i - 1) / #tabs, 2, 0, 0)
	btn.BackgroundColor3 = C.tabInactive
	btn.BorderSizePixel = 0
	btn.Text = tabLabels[tab]
	btn.TextColor3 = C.muted
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 11
	btn.Parent = tabFrame
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	local tabPad = Instance.new("UIPadding", btn)
	tabPad.PaddingLeft = UDim.new(0, 8)
	tabPad.PaddingRight = UDim.new(0, 8)
	tabButtons[tab] = btn
end

local function styleActiveTab()
	for t, b in pairs(tabButtons) do
		local on = (t == activeTab)
		b.BackgroundColor3 = on and C.accentOrange or C.tabInactive
		b.TextColor3 = on and C.white or C.muted
	end
end

local function syncTabBarLayout()
	local portrait = isMobilePortrait()
	tabScroll.Visible = portrait
	if portrait then
		for _, tab in ipairs(tabs) do
			local btn = tabButtons[tab]
			btn.Parent = tabList
			btn.Position = UDim2.new(0, 0, 0, 0)
			btn.Size = UDim2.new(0, 0, 0, 28)
			btn.AutomaticSize = Enum.AutomaticSize.X
		end
		tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
		tabList.AutomaticSize = Enum.AutomaticSize.X
		tabList.Size = UDim2.new(0, 0, 1, 0)
	else
		for _, tab in ipairs(tabs) do
			local btn = tabButtons[tab]
			btn.Parent = tabFrame
			btn.AutomaticSize = Enum.AutomaticSize.None
		end
		local n = #tabs
		for i, tab in ipairs(tabs) do
			local btn = tabButtons[tab]
			btn.Position = UDim2.new((i - 1) / n, 2, 0, 0)
			btn.Size = UDim2.new(1 / n, -4, 1, 0)
		end
		tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
		tabScroll.CanvasSize = UDim2.new(1, 0, 0, 0)
		tabList.AutomaticSize = Enum.AutomaticSize.None
		tabList.Size = UDim2.new(1, 0, 1, 0)
	end
end

-- Scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -90)
scroll.Position = UDim2.new(0, 10, 0, 84)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6); layout.Parent = scroll

local function applyResponsiveContentLayout()
	local portrait = isMobilePortrait()
	local mobile = MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H)

	syncTabBarLayout()

	if portrait then
		titleBar.Size = UDim2.new(1, 0, 0, 44)
		statusBar.Position = UDim2.new(0, 0, 0, 44)
		statusBar.Visible = true
		currLbl.Parent = statusBar
		currLbl.Size = UDim2.new(1, -24, 1, 0)
		currLbl.Position = UDim2.new(0, 12, 0, 0)
		currLbl.TextXAlignment = Enum.TextXAlignment.Left
		currLbl.TextSize = 14
		currLbl.RichText = true
		titleLbl.Size = UDim2.new(1, -58, 1, 0)
		titleLbl.TextXAlignment = Enum.TextXAlignment.Center
		titleLbl.TextColor3 = C.accentOrange
		titleLbl.TextSize = 20
		closeBtn.Size = UDim2.new(0, 36, 0, 36)
		closeBtn.Position = UDim2.new(1, -44, 0, 4)
		closeBtn.TextSize = 15
		closeBtn.BackgroundTransparency = 0
		closeBtn.BackgroundColor3 = C.closeMuted
		closeCorner.CornerRadius = UDim.new(1, 0)
		panelStroke.Color = Color3.fromRGB(45, 48, 62)
		panelCorner.CornerRadius = UDim.new(0, 12)
		tabFrame.Size = UDim2.new(1, -16, 0, 38)
		tabFrame.Position = UDim2.new(0, 8, 0, 44 + 34 + 6)
		local bodyTop = 44 + 34 + 6 + 38 + 8
		scroll.Size = UDim2.new(1, -16, 1, -bodyTop)
		scroll.Position = UDim2.new(0, 8, 0, bodyTop)
		for _, btn in pairs(tabButtons) do
			btn.TextSize = 12
		end
	elseif mobile then
		titleBar.Size = UDim2.new(1, 0, 0, 42)
		statusBar.Visible = false
		currLbl.Parent = titleBar
		currLbl.TextSize = 14
		currLbl.RichText = false
		titleLbl.TextColor3 = C.gem
		titleLbl.TextSize = 22
		titleLbl.TextXAlignment = Enum.TextXAlignment.Center
		titleLbl.Position = UDim2.new(0, 8, 0, 2)
		titleLbl.Size = UDim2.new(1, -16, 0, 22)
		currLbl.TextXAlignment = Enum.TextXAlignment.Center
		currLbl.Position = UDim2.new(0, 8, 0, 24)
		currLbl.Size = UDim2.new(1, -16, 0, 16)
		closeBtn.Size = UDim2.new(0, 38, 0, 38)
		closeBtn.Position = UDim2.new(1, -46, 0, 4)
		closeBtn.TextSize = 16
		closeBtn.BackgroundTransparency = 0.5
		closeBtn.BackgroundColor3 = C.red
		closeCorner.CornerRadius = UDim.new(0, 6)
		panelStroke.Color = Color3.fromRGB(80, 60, 120)
		panelCorner.CornerRadius = UDim.new(0, 14)
		tabFrame.Size = UDim2.new(1, -12, 0, 34)
		tabFrame.Position = UDim2.new(0, 6, 0, 48)
		scroll.Size = UDim2.new(1, -12, 1, -94)
		scroll.Position = UDim2.new(0, 6, 0, 86)
		for _, btn in pairs(tabButtons) do
			btn.TextSize = 12
		end
	else
		titleBar.Size = UDim2.new(1, 0, 0, 42)
		statusBar.Visible = false
		currLbl.Parent = titleBar
		currLbl.Size = UDim2.new(0.45, -48, 1, 0)
		currLbl.Position = UDim2.new(0.55, 0, 0, 0)
		currLbl.TextXAlignment = Enum.TextXAlignment.Right
		currLbl.TextSize = 12
		currLbl.RichText = false
		titleLbl.Size = UDim2.new(0.6, 0, 1, 0)
		titleLbl.TextColor3 = C.gem
		titleLbl.TextSize = 18
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.Position = UDim2.new(0, 15, 0, 0)
		titleLbl.Size = UDim2.new(0.6, 0, 1, 0)
		closeBtn.Size = UDim2.new(0, 32, 0, 32)
		closeBtn.Position = UDim2.new(1, -40, 0, 5)
		closeBtn.TextSize = 14
		closeBtn.BackgroundTransparency = 0.5
		closeBtn.BackgroundColor3 = C.red
		closeCorner.CornerRadius = UDim.new(0, 6)
		panelStroke.Color = Color3.fromRGB(80, 60, 120)
		panelCorner.CornerRadius = UDim.new(0, 14)
		tabFrame.Size = UDim2.new(1, -20, 0, 30)
		tabFrame.Position = UDim2.new(0, 10, 0, 48)
		scroll.Size = UDim2.new(1, -20, 1, -90)
		scroll.Position = UDim2.new(0, 10, 0, 84)
		for _, btn in pairs(tabButtons) do
			btn.TextSize = 11
		end
	end

	layout.Padding = UDim.new(0, portrait and 8 or 6)
	updateCurrencyLabel()
	styleActiveTab()
end

-- -- REFRESH --

local playerCosmetics = {owned = {}, equipped = {}}
local playerExterior = {owned = {}, equipped = nil}
local playerBaseColor = {owned = {}, equipped = nil}

local function refreshData()
	if not getInventory then return end
	local ok, data = pcall(function() return getInventory:InvokeServer() end)
	if ok and data then
		playerCoins = data.coins or 0
		playerGems = data.gems or 0
		playerCosmetics = data.cosmetics or {owned = {}, equipped = {}}
		if not playerCosmetics.owned then playerCosmetics.owned = {} end
		if not playerCosmetics.equipped then playerCosmetics.equipped = {} end
		playerExterior = data.exterior or {owned = {}, equipped = nil}
		if not playerExterior.owned then playerExterior.owned = {} end
		playerBaseColor = data.baseColor or {owned = {}, equipped = nil}
		if not playerBaseColor.owned then playerBaseColor.owned = {} end
		updateCurrencyLabel()
	end
end

local function buildItems()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end

	local order = 0

	-- Base Exteriors tab: use GameConfig.BaseExteriorItems
	if activeTab == "exterior" then
		local items = (GameConfig.BaseExteriorItems or {})
		for _, item in ipairs(items) do
			order = order + 1
			local owned = playerExterior.owned and playerExterior.owned[item.id] == true
			local equipped = playerExterior.equipped == item.id

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 58); card.LayoutOrder = order
			card.BackgroundColor3 = equipped and Color3.fromRGB(20, 35, 50) or (owned and C.cardOwned or C.card)
			card.BorderSizePixel = 0; card.Parent = scroll
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
			if equipped then
				local eqStroke = Instance.new("UIStroke", card)
				if isMobilePortrait() then
					eqStroke.Color = C.equippedRingPortrait
					eqStroke.Thickness = 2
				else
					eqStroke.Color = C.equipped
					eqStroke.Thickness = 1.5
				end
			end

			-- Color swatch for color-only themes (exterior_red, etc.)
			if item.color then
				local swatch = Instance.new("Frame")
				swatch.Size = UDim2.new(0, 28, 0, 28); swatch.Position = UDim2.new(0, 10, 0, 15)
				swatch.BackgroundColor3 = item.color
				swatch.BorderSizePixel = 0; swatch.Parent = card
				Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 6)
				local swStroke = Instance.new("UIStroke", swatch)
				swStroke.Color = Color3.new(0.3, 0.3, 0.35); swStroke.Thickness = 1
			end
			local nameOffset = item.color and 46 or 12
			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(0.6, -nameOffset, 0, 20); name.Position = UDim2.new(0, nameOffset, 0, 6)
			name.BackgroundTransparency = 1; name.Text = item.name
			name.TextColor3 = C.white; name.Font = Enum.Font.GothamBold; name.TextSize = 13
			name.TextXAlignment = Enum.TextXAlignment.Left; name.Parent = card

			local desc = Instance.new("TextLabel")
			desc.Size = UDim2.new(0.6, -nameOffset, 0, 14); desc.Position = UDim2.new(0, nameOffset, 0, 26)
			desc.BackgroundTransparency = 1; desc.Text = item.desc or "Base theme"
			desc.TextColor3 = C.muted; desc.Font = Enum.Font.GothamMedium; desc.TextSize = 9
			desc.TextXAlignment = Enum.TextXAlignment.Left; desc.TextWrapped = true; desc.Parent = card

			local status = Instance.new("TextLabel")
			status.Size = UDim2.new(0.4, 0, 0, 12); status.Position = UDim2.new(0, nameOffset, 0, 42)
			status.BackgroundTransparency = 1
			status.Text = equipped and "EQUIPPED" or (owned and "OWNED" or "")
			status.TextColor3 = equipped and C.equipped or C.green
			status.Font = Enum.Font.GothamMedium; status.TextSize = 9
			status.TextXAlignment = Enum.TextXAlignment.Left; status.Parent = card

			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 90, 0, 30); btn.Position = UDim2.new(1, -100, 0.5, -15)
			btn.BorderSizePixel = 0; btn.Font = Enum.Font.GothamBold; btn.TextSize = 11
			btn.Parent = card
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

			if equipped then
				btn.Text = "Unequip"; btn.TextColor3 = C.muted
				btn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
				btn.MouseButton1Click:Connect(function()
					if equipExterior then
						local ok, msg = equipExterior:InvokeServer(nil)
						if ok then
							playerExterior.equipped = nil
							buildItems()
							Notify.Toast("Restored default gray base", C.muted, 2)
						end
					end
				end)
			elseif owned then
				btn.Text = "Equip"; btn.TextColor3 = C.equipped
				btn.BackgroundColor3 = Color3.fromRGB(25, 50, 70)
				btn.MouseButton1Click:Connect(function()
					if equipExterior then
						local ok, msg = equipExterior:InvokeServer(item.id)
						if ok then
							playerExterior.equipped = item.id
							buildItems()
							Notify.Toast("Equipped " .. item.name, C.equipped, 3)
						else
							Notify.Toast(msg or "Equip failed", C.red, 3)
						end
					end
				end)
			else
				local priceText, priceCurr
				if (item.coinCost or 0) > 0 then
					priceText = "" .. (item.coinCost or 0); priceCurr = "coins"
					btn.BackgroundColor3 = Color3.fromRGB(50, 45, 20)
					btn.TextColor3 = C.coin
				else
					priceText = "" .. (item.gemCost or 0); priceCurr = "gems"
					btn.BackgroundColor3 = Color3.fromRGB(35, 25, 60)
					btn.TextColor3 = C.gem
				end
				btn.Text = priceText
				btn.MouseButton1Click:Connect(function()
					if buyExterior then
						local pcallOk, a, b = pcall(function() return buyExterior:InvokeServer(item.id, priceCurr) end)
						local success, retMsg = pcallOk and a or false, (pcallOk and b or tostring(a)) or "nil"
						if success then
							Notify.Toast("Purchased " .. item.name .. "!", C.green, 3)
							refreshData(); buildItems()
						else
							Notify.Toast(tostring(retMsg) ~= "nil" and tostring(retMsg) or "Purchase failed", C.red, 3)
						end
					end
				end)
			end
		end
	elseif activeTab == "baseColor" then
		local function addSectionHeader(titleText, subtitleText)
			order = order + 1
			local header = Instance.new("Frame")
			header.Size = UDim2.new(1, 0, 0, 38)
			header.LayoutOrder = order
			header.BackgroundTransparency = 1
			header.Parent = scroll

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, 0, 0, 18)
			title.Position = UDim2.new(0, 2, 0, 0)
			title.BackgroundTransparency = 1
			title.Text = titleText
			title.TextColor3 = C.white
			title.Font = Enum.Font.GothamBold
			title.TextSize = 14
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Parent = header

			local subtitle = Instance.new("TextLabel")
			subtitle.Size = UDim2.new(1, 0, 0, 16)
			subtitle.Position = UDim2.new(0, 2, 0, 18)
			subtitle.BackgroundTransparency = 1
			subtitle.Text = subtitleText
			subtitle.TextColor3 = C.muted
			subtitle.Font = Enum.Font.GothamMedium
			subtitle.TextSize = 9
			subtitle.TextXAlignment = Enum.TextXAlignment.Left
			subtitle.Parent = header
		end

		local function addColorSection(items, state, buyRemote, equipRemote, sectionTitle, sectionSubtitle, equipToast, removeToast)
			if not items or #items == 0 then return end
			addSectionHeader(sectionTitle, sectionSubtitle)

			for _, item in ipairs(items) do
				order = order + 1
				local owned = state.owned and state.owned[item.id] == true
				local equipped = state.equipped == item.id

				local card = Instance.new("Frame")
				card.Size = UDim2.new(1, 0, 0, 58); card.LayoutOrder = order
				card.BackgroundColor3 = equipped and Color3.fromRGB(20, 35, 50) or (owned and C.cardOwned or C.card)
				card.BorderSizePixel = 0; card.Parent = scroll
				Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
				if equipped then
					local eqStroke = Instance.new("UIStroke", card)
					if isMobilePortrait() then
						eqStroke.Color = C.equippedRingPortrait
						eqStroke.Thickness = 2
					else
						eqStroke.Color = C.equipped
						eqStroke.Thickness = 1.5
					end
				end

				local swatch = Instance.new("Frame")
				swatch.Size = UDim2.new(0, 32, 0, 32); swatch.Position = UDim2.new(0, 12, 0, 13)
				swatch.BackgroundColor3 = item.color or Color3.new(0.5, 0.5, 0.5)
				swatch.BorderSizePixel = 0; swatch.Parent = card
				Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 6)
				local swStroke = Instance.new("UIStroke", swatch)
				swStroke.Color = Color3.new(0.3, 0.3, 0.35); swStroke.Thickness = 1

				local name = Instance.new("TextLabel")
				name.Size = UDim2.new(0.5, -55, 0, 20); name.Position = UDim2.new(0, 52, 0, 6)
				name.BackgroundTransparency = 1; name.Text = item.name
				name.TextColor3 = C.white; name.Font = Enum.Font.GothamBold; name.TextSize = 13
				name.TextXAlignment = Enum.TextXAlignment.Left; name.Parent = card

				local status = Instance.new("TextLabel")
				status.Size = UDim2.new(0.5, -55, 0, 14); status.Position = UDim2.new(0, 52, 0, 26)
				status.BackgroundTransparency = 1
				status.Text = equipped and "EQUIPPED" or (owned and "OWNED" or "")
				status.TextColor3 = equipped and C.equipped or C.green
				status.Font = Enum.Font.GothamMedium; status.TextSize = 9
				status.TextXAlignment = Enum.TextXAlignment.Left; status.Parent = card

				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(0, 90, 0, 30); btn.Position = UDim2.new(1, -100, 0.5, -15)
				btn.BorderSizePixel = 0; btn.Font = Enum.Font.GothamBold; btn.TextSize = 11
				btn.Parent = card
				Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

				if equipped then
					btn.Text = "Unequip"; btn.TextColor3 = C.muted
					btn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
					btn.MouseButton1Click:Connect(function()
						if equipRemote then
							local ok, msg = equipRemote:InvokeServer(nil)
							if ok then
								refreshData(); buildItems()
								Notify.Toast(removeToast, C.muted, 2)
							else
								Notify.Toast(msg or "Unequip failed", C.red, 3)
							end
						end
					end)
				elseif owned then
					btn.Text = "Equip"; btn.TextColor3 = C.equipped
					btn.BackgroundColor3 = Color3.fromRGB(25, 50, 70)
					btn.MouseButton1Click:Connect(function()
						if equipRemote then
							local ok, msg = equipRemote:InvokeServer(item.id)
							if ok then
								refreshData(); buildItems()
								Notify.Toast("Equipped " .. item.name .. " " .. equipToast, C.equipped, 3)
							else
								Notify.Toast(msg or "Equip failed", C.red, 3)
							end
						end
					end)
				else
					local priceText, priceCurr
					if (item.coinCost or 0) > 0 then
						priceText = "" .. (item.coinCost or 0); priceCurr = "coins"
						btn.BackgroundColor3 = Color3.fromRGB(50, 45, 20)
						btn.TextColor3 = C.coin
					else
						priceText = "" .. (item.gemCost or 0); priceCurr = "gems"
						btn.BackgroundColor3 = Color3.fromRGB(35, 25, 60)
						btn.TextColor3 = C.gem
					end
					btn.Text = priceText
					btn.MouseButton1Click:Connect(function()
						if buyRemote then
							local pcallOk, a, b = pcall(function() return buyRemote:InvokeServer(item.id, priceCurr) end)
							local success, retMsg = pcallOk and a or false, (pcallOk and b or tostring(a)) or "nil"
							if success then
								Notify.Toast("Purchased " .. item.name .. "!", C.green, 3)
								refreshData(); buildItems()
							else
								Notify.Toast(tostring(retMsg) ~= "nil" and tostring(retMsg) or "Purchase failed", C.red, 3)
							end
						end
					end)
				end
			end
		end

		addColorSection(
			GameConfig.BaseColorItems or {},
			playerBaseColor,
			buyBaseColor,
			equipBaseColor,
			"Base Foundations",
			"Plot center, ramp, stairs, and floors",
			"foundations",
			"Restored default gray foundations"
		)
	else
		-- Cosmetics: trails, auras, nameColor
		for _, item in ipairs(GameConfig.CosmeticItems or {}) do
			if item.slot ~= activeTab then continue end
			order = order + 1

			local owned = playerCosmetics.owned[item.id] == true
			local equipped = playerCosmetics.equipped[item.slot] == item.id

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 50); card.LayoutOrder = order
			card.BackgroundColor3 = equipped and Color3.fromRGB(20, 35, 50) or (owned and C.cardOwned or C.card)
			card.BorderSizePixel = 0; card.Parent = scroll
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

			if equipped then
				local eqStroke = Instance.new("UIStroke", card)
				if isMobilePortrait() then
					eqStroke.Color = C.equippedRingPortrait
					eqStroke.Thickness = 2
				else
					eqStroke.Color = C.equipped
					eqStroke.Thickness = 1.5
				end
			end

			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(0.5, 0, 0, 20); name.Position = UDim2.new(0, 12, 0, 6)
			name.BackgroundTransparency = 1; name.Text = item.name
			name.TextColor3 = C.white; name.Font = Enum.Font.GothamBold; name.TextSize = 13
			name.TextXAlignment = Enum.TextXAlignment.Left; name.Parent = card

			local status = Instance.new("TextLabel")
			status.Size = UDim2.new(0.5, 0, 0, 12); status.Position = UDim2.new(0, 12, 0, 28)
			status.BackgroundTransparency = 1
			status.Text = equipped and "EQUIPPED" or (owned and "OWNED" or "")
			status.TextColor3 = equipped and C.equipped or C.green
			status.Font = Enum.Font.GothamMedium; status.TextSize = 9
			status.TextXAlignment = Enum.TextXAlignment.Left; status.Parent = card

			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 90, 0, 30); btn.Position = UDim2.new(1, -100, 0.5, -15)
			btn.BorderSizePixel = 0; btn.Font = Enum.Font.GothamBold; btn.TextSize = 11
			btn.Parent = card
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

			if equipped then
				btn.Text = "Unequip"; btn.TextColor3 = C.muted
				btn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
				btn.MouseButton1Click:Connect(function()
					if equipCosmetic then
						local ok, msg = equipCosmetic:InvokeServer(item.slot, nil)
						if ok then
							playerCosmetics.equipped = playerCosmetics.equipped or {}
							playerCosmetics.equipped[item.slot] = nil
							buildItems()
						end
					end
				end)
			elseif owned then
				btn.Text = "Equip"; btn.TextColor3 = C.equipped
				btn.BackgroundColor3 = Color3.fromRGB(25, 50, 70)
				btn.MouseButton1Click:Connect(function()
					if equipCosmetic then
						local ok, msg = equipCosmetic:InvokeServer(item.slot, item.id)
						if ok then
							playerCosmetics.equipped = playerCosmetics.equipped or {}
							playerCosmetics.equipped[item.slot] = item.id
							buildItems()
							Notify.Toast("Equipped " .. item.name, C.equipped, 2, "X")
						end
					end
				end)
			else
				local priceText, priceCurr
				if (item.coinCost or 0) > 0 then
					priceText = "" .. (item.coinCost or 0); priceCurr = "coins"
					btn.BackgroundColor3 = Color3.fromRGB(50, 45, 20)
					btn.TextColor3 = C.coin
				else
					priceText = "" .. (item.gemCost or 0); priceCurr = "gems"
					btn.BackgroundColor3 = Color3.fromRGB(35, 25, 60)
					btn.TextColor3 = C.gem
				end
				btn.Text = priceText
				btn.MouseButton1Click:Connect(function()
					if buyCosmetic then
						local pcallOk, a, b = pcall(function() return buyCosmetic:InvokeServer(item.id, priceCurr) end)
						local success, retMsg = pcallOk and a or false, (pcallOk and b or tostring(a)) or "nil"
						if success then
							Notify.Toast("Purchased " .. item.name .. "!", C.green, 3, "X")
							refreshData(); buildItems()
						else
							Notify.Toast(tostring(retMsg) ~= "nil" and tostring(retMsg) or "Purchase failed", C.red, 3, "X")
						end
					end
				end)
			end
		end
	end

	layout:ApplyLayout()
	scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
end

-- Tab switching
for tab, btn in pairs(tabButtons) do
	btn.MouseButton1Click:Connect(function()
		activeTab = tab
		styleActiveTab()
		buildItems()
	end)
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
	if menuName == "CosmeticShopGUI" then
		if not panel.Visible then applyPanelScale(panel) end
		applyResponsiveContentLayout()
		panel.Visible = not panel.Visible
		if panel.Visible then
			MobileWindowLayout.NotifyMenuOpened()
		else
			MobileWindowLayout.NotifyMenuClosed()
		end
		if panel.Visible then refreshData(); buildItems() end
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
		buildItems()
	else
		sg.IgnoreGuiInset = false
	end
end)

-- FIX #18: Removed fallback C key handler — HUDButtonBar is the sole keyboard handler.
-- Having both caused double-toggle (open then immediately close).

print("[CosmeticShopClient] Loaded - open via [G] Shop > Drip Shop")
