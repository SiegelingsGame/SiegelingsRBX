-- EggShopClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Press K to open egg shop. Buy and hatch eggs of various rarities.sd

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local buyEgg = Events:WaitForChild("BuyEgg", 15)
local eggResult = Events:WaitForChild("EggResult", 15)
local getInventory = Events:WaitForChild("GetInventory", 15)

-- Colors
local C = {
	bg = Color3.fromRGB(14, 16, 24),
	card = Color3.fromRGB(22, 26, 38),
	coin = Color3.fromRGB(255, 200, 50),
	gem = Color3.fromRGB(120, 80, 255),
	robux = Color3.fromRGB(60, 200, 100),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(255, 70, 60),
	muted = Color3.fromRGB(120, 125, 140),
	white = Color3.new(1, 1, 1),
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(75, 200, 75),
	Rare = Color3.fromRGB(60, 130, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Mythic = Color3.fromRGB(180, 80, 255), -- same as Epic (egg display)
	Legendary = Color3.fromRGB(255, 184, 0),
}

local EGG_CARD_COLORS = {
	egg_common    = { border = Color3.fromRGB(200, 190, 170), bg = Color3.fromRGB(60, 55, 40) },
	egg_rare      = { border = Color3.fromRGB(80, 140, 255),  bg = Color3.fromRGB(25, 40, 70) },
	egg_mythic    = { border = Color3.fromRGB(160, 90, 255),  bg = Color3.fromRGB(40, 25, 60) },
	egg_legendary = { border = Color3.fromRGB(255, 184, 0),   bg = Color3.fromRGB(65, 50, 15) },
	egg_god       = { border = Color3.fromRGB(255, 100, 200), bg = Color3.fromRGB(50, 15, 45) },
}

-- Panel scales with viewport (wider for 5 egg tiers)
local PANEL_DESIGN_W = 620
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

-- Screen GUI
local sg = Instance.new("ScreenGui")
sg.Name = "EggShopGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 32
sg.Parent = playerGui

-- Main panel (size/position set on open via applyPanelScale)
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
panel.BackgroundColor3 = C.bg
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = true
panel.Draggable = true
panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(100, 80, 40)
panelStroke.Thickness = 2

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 42)
titleBar.BackgroundColor3 = Color3.fromRGB(18, 22, 36)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(0.5, 0, 1, 0)
titleLbl.Position = UDim2.new(0, 15, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "EGG SHOP"
titleLbl.TextColor3 = C.coin
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 18
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = titleBar

local currLbl = Instance.new("TextLabel")
currLbl.Name = "CurrLbl"
currLbl.Size = UDim2.new(0.45, -48, 1, 0)
currLbl.Position = UDim2.new(0.55, 0, 0, 0)
currLbl.BackgroundTransparency = 1
currLbl.Text = "Coins: 0  |  Gems: 0"
currLbl.TextColor3 = C.muted
currLbl.Font = Enum.Font.GothamBold
currLbl.TextSize = 12
currLbl.TextXAlignment = Enum.TextXAlignment.Right
currLbl.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 5)
closeBtn.BackgroundColor3 = C.red
closeBtn.BackgroundTransparency = 0.5
closeBtn.Text = "X"
closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	MobileWindowLayout.NotifyMenuClosed()
end)

-- Card container
local cardContainer = Instance.new("Frame")
cardContainer.Size = UDim2.new(1, -20, 1, -55)
cardContainer.Position = UDim2.new(0, 10, 0, 50)
cardContainer.BackgroundTransparency = 1
cardContainer.BorderSizePixel = 0
cardContainer.Parent = panel

local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Horizontal
cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardLayout.VerticalAlignment = Enum.VerticalAlignment.Top
cardLayout.Padding = UDim.new(0, 10)
cardLayout.Parent = cardContainer

local function applyResponsiveContentLayout()
	local mobile = MobileWindowLayout.IsMobile()
	titleLbl.TextSize = mobile and 22 or 18
	currLbl.TextSize = mobile and 14 or 12
	closeBtn.Size = mobile and UDim2.new(0, 38, 0, 38) or UDim2.new(0, 32, 0, 32)
	closeBtn.Position = mobile and UDim2.new(1, -46, 0, 4) or UDim2.new(1, -40, 0, 5)
	closeBtn.TextSize = mobile and 16 or 14
	cardContainer.Size = mobile and UDim2.new(1, -12, 1, -60) or UDim2.new(1, -20, 1, -55)
	cardContainer.Position = mobile and UDim2.new(0, 6, 0, 50) or UDim2.new(0, 10, 0, 50)
	cardLayout.FillDirection = Enum.FillDirection.Horizontal
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	cardLayout.Padding = mobile and UDim.new(0, 6) or UDim.new(0, 10)
end

local hatching = false

local function refreshCurrency()
	if not getInventory then return end
	local ok, data = pcall(function() return getInventory:InvokeServer() end)
	if ok and data then
		currLbl.Text = "Coins: " .. (data.coins or 0) .. "  |  Gems: " .. (data.gems or 0)
	end
end

local function buildEggCards()
	for _, ch in ipairs(cardContainer:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end

	local items = GameConfig.EggShopItems
	if not items or #items == 0 then return end

	local gap = MobileWindowLayout.IsMobile() and 6 or 10
	local containerWidth = math.max(200, cardContainer.AbsoluteSize.X)
	local cardWidth = math.max(62, math.floor((containerWidth - ((#items - 1) * gap)) / #items))
	local uiScale = math.clamp(cardWidth / 120, 0.58, 1)

	for i, egg in ipairs(items) do
		local eggStyle = EGG_CARD_COLORS[egg.id] or { border = C.muted, bg = C.card }

		local card = Instance.new("Frame")
		card.Size = UDim2.new(0, cardWidth, 1, 0)
		card.LayoutOrder = i
		card.BackgroundColor3 = C.card
		card.BorderSizePixel = 0
		card.Parent = cardContainer
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
		local cs = Instance.new("UIStroke", card)
		cs.Color = eggStyle.border
		cs.Thickness = 1.5

		-- Egg visual (colored oval)
		local eggVisual = Instance.new("Frame")
		eggVisual.Size = UDim2.new(0, 54, 0, 66)
		eggVisual.Position = UDim2.new(0.5, -27, 0, 14)
		eggVisual.BackgroundColor3 = eggStyle.border
		eggVisual.BorderSizePixel = 0
		eggVisual.Parent = card
		Instance.new("UICorner", eggVisual).CornerRadius = UDim.new(0.4, 0)

		local inner = Instance.new("Frame")
		inner.Size = UDim2.new(0, 30, 0, 20)
		inner.Position = UDim2.new(0.5, -15, 0, 10)
		inner.BackgroundColor3 = Color3.new(1, 1, 1)
		inner.BackgroundTransparency = 0.6
		inner.BorderSizePixel = 0
		inner.Parent = eggVisual
		Instance.new("UICorner", inner).CornerRadius = UDim.new(1, 0)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -8, 0, 20)
		nameLbl.Position = UDim2.new(0, 4, 0, 86)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = egg.name
		nameLbl.TextColor3 = eggStyle.border
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = math.max(7, math.floor(12 * uiScale))
		nameLbl.TextWrapped = true
		nameLbl.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(1, -8, 0, 30)
		descLbl.Position = UDim2.new(0, 4, 0, 108)
		descLbl.BackgroundTransparency = 1
		descLbl.Text = egg.desc
		descLbl.TextColor3 = C.muted
		descLbl.Font = Enum.Font.GothamMedium
		descLbl.TextSize = math.max(6, math.floor(9 * uiScale))
		descLbl.TextWrapped = true
		descLbl.Parent = card

		-- Rarity chances
		local yOff = 142
		for _, entry in ipairs(egg.pool) do
			local rc = RARITY_COLORS[entry.rarity] or C.muted
			local totalW = 0
			for _, e in ipairs(egg.pool) do totalW = totalW + e.weight end
			local pct = math.floor(entry.weight / totalW * 100)

			local chanceLbl = Instance.new("TextLabel")
			chanceLbl.Size = UDim2.new(1, -12, 0, 13)
			chanceLbl.Position = UDim2.new(0, 6, 0, yOff)
			chanceLbl.BackgroundTransparency = 1
			chanceLbl.Text = entry.rarity .. ": " .. pct .. "%"
			chanceLbl.TextColor3 = rc
			chanceLbl.Font = Enum.Font.GothamMedium
			chanceLbl.TextSize = math.max(6, math.floor(10 * uiScale))
			chanceLbl.TextXAlignment = Enum.TextXAlignment.Left
			chanceLbl.Parent = card
			yOff = yOff + 15
		end

		-- Buy with Coins button
		local coinCost = (type(egg.coinCost) == "number") and egg.coinCost or 0
		local robuxCost = (type(egg.robuxCost) == "number") and egg.robuxCost or 0
		local productId = (type(egg.productId) == "number") and egg.productId or 0

		local buyCoinsBtn = Instance.new("TextButton")
		buyCoinsBtn.Size = UDim2.new(1, -16, 0, 32)
		buyCoinsBtn.Position = UDim2.new(0, 8, 1, -78)
		buyCoinsBtn.BorderSizePixel = 0
		buyCoinsBtn.Font = Enum.Font.GothamBold
		buyCoinsBtn.TextSize = math.max(7, math.floor(12 * uiScale))
		buyCoinsBtn.Text = "Coins: " .. coinCost
		buyCoinsBtn.BackgroundColor3 = Color3.fromRGB(50, 45, 20)
		buyCoinsBtn.TextColor3 = C.coin
		buyCoinsBtn.Parent = card
		Instance.new("UICorner", buyCoinsBtn).CornerRadius = UDim.new(0, 8)
		buyCoinsBtn.Active = (coinCost > 0)

		local buyRobuxBtn = Instance.new("TextButton")
		buyRobuxBtn.Size = UDim2.new(1, -16, 0, 32)
		buyRobuxBtn.Position = UDim2.new(0, 8, 1, -42)
		buyRobuxBtn.BorderSizePixel = 0
		buyRobuxBtn.Font = Enum.Font.GothamBold
		buyRobuxBtn.TextSize = math.max(7, math.floor(12 * uiScale))
		buyRobuxBtn.Text = "R$ " .. robuxCost
		buyRobuxBtn.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
		buyRobuxBtn.TextColor3 = C.robux
		buyRobuxBtn.Parent = card
		Instance.new("UICorner", buyRobuxBtn).CornerRadius = UDim.new(0, 8)
		buyRobuxBtn.Active = (robuxCost > 0)

		local function doCoinPurchase()
			if hatching or coinCost <= 0 or not buyEgg then return end
			hatching = true
			buyCoinsBtn.Text = "Buying..."
			local pcallOk, serverOk, serverMsg = pcall(function()
				return buyEgg:InvokeServer(egg.id, "coins")
			end)
			if pcallOk and serverOk then
				Notify.Toast((type(serverMsg) == "string" and serverMsg ~= "") and serverMsg or "Egg purchased!", C.green, 3)
				refreshCurrency()
			elseif pcallOk then
				Notify.Toast((type(serverMsg) == "string" and serverMsg ~= "") and serverMsg or "Purchase failed", C.red, 3)
			else
				Notify.Toast("Connection error", C.red, 3)
			end
			hatching = false
			buyCoinsBtn.Text = "Coins: " .. coinCost
		end

		local function doRobuxPurchase()
			if hatching or robuxCost <= 0 then return end
			if productId <= 0 then
				Notify.Toast("Robux purchase: set productId in GameConfig", C.muted, 3)
				return
			end
			hatching = true
			buyRobuxBtn.Text = "..."
			MarketplaceService:PromptProductPurchase(player, productId)
			task.delay(2, function()
				hatching = false
				buyRobuxBtn.Text = "R$ " .. robuxCost
			end)
		end

		buyCoinsBtn.MouseButton1Click:Connect(doCoinPurchase)
		buyRobuxBtn.MouseButton1Click:Connect(doRobuxPurchase)
	end
end

-- Hatching animation (crash-safe: dismiss button created FIRST)
local function showHatchAnimation(result)
	if not result or type(result) ~= "table" then return end

	local displayName = result.displayName or "???"
	local rarity = result.rarity or "?"

	local rarityColor
	if result.rarityColor and type(result.rarityColor) == "table" then
		rarityColor = Color3.fromRGB(
			result.rarityColor[1] or 180,
			result.rarityColor[2] or 180,
			result.rarityColor[3] or 180
		)
	else
		rarityColor = RARITY_COLORS[rarity] or Color3.fromRGB(180, 180, 180)
	end

	-- Overlay
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Parent = sg

	-- CRITICAL: Create dismiss button FIRST so overlay is always dismissable
	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		pcall(function()
			TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		end)
		task.delay(0.45, function()
			if overlay and overlay.Parent then overlay:Destroy() end
		end)
	end

	local clickBtn = Instance.new("TextButton")
	clickBtn.Size = UDim2.new(1, 0, 1, 0)
	clickBtn.BackgroundTransparency = 1
	clickBtn.Text = ""
	clickBtn.ZIndex = 1
	clickBtn.Parent = overlay
	clickBtn.MouseButton1Click:Connect(dismiss)

	-- Auto-dismiss safety net
	task.delay(5, dismiss)

	-- Egg shape
	local eggFrame = Instance.new("Frame")
	eggFrame.Size = UDim2.new(0, 90, 0, 110)
	eggFrame.Position = UDim2.new(0.5, -45, 0.5, -75)
	eggFrame.BackgroundColor3 = Color3.fromRGB(240, 230, 210)
	eggFrame.BorderSizePixel = 0
	eggFrame.ZIndex = 2
	eggFrame.Parent = overlay
	Instance.new("UICorner", eggFrame).CornerRadius = UDim.new(0.35, 0)

	local eggLabel = Instance.new("TextLabel")
	eggLabel.Size = UDim2.new(1, 0, 1, 0)
	eggLabel.BackgroundTransparency = 1
	eggLabel.Text = "?"
	eggLabel.TextSize = 50
	eggLabel.Font = Enum.Font.GothamBold
	eggLabel.TextColor3 = C.muted
	eggLabel.ZIndex = 3
	eggLabel.Parent = eggFrame

	-- Run animation in protected call so overlay is always cleaned up
	task.spawn(function()
		local animOk, animErr = pcall(function()
			local baseX = 0.5
			local baseOffX = -45

			-- Shake
			for i = 1, 6 do
				local offset = (i % 2 == 0) and 10 or -10
				TweenService:Create(eggFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
					Position = UDim2.new(baseX, baseOffX + offset, 0.5, -75)
				}):Play()
				task.wait(0.15)
			end

			TweenService:Create(eggFrame, TweenInfo.new(0.1), {
				Position = UDim2.new(baseX, baseOffX, 0.5, -75)
			}):Play()
			task.wait(0.25)

			-- Crack and expand
			eggFrame.BackgroundColor3 = rarityColor
			eggLabel.Text = "!"
			eggLabel.TextColor3 = C.white

			TweenService:Create(eggFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 180, 0, 140),
				Position = UDim2.new(0.5, -90, 0.5, -90),
			}):Play()
			task.wait(0.4)

			-- Show creature info
			eggFrame.BackgroundColor3 = Color3.fromRGB(24, 28, 42)
			eggLabel.Text = ""
			local st = Instance.new("UIStroke", eggFrame)
			st.Color = rarityColor
			st.Thickness = 2

			local creNameLbl = Instance.new("TextLabel")
			creNameLbl.Size = UDim2.new(1, -16, 0, 24)
			creNameLbl.Position = UDim2.new(0, 8, 0, 20)
			creNameLbl.BackgroundTransparency = 1
			creNameLbl.Text = displayName
			creNameLbl.TextColor3 = C.white
			creNameLbl.Font = Enum.Font.GothamBlack
			creNameLbl.TextSize = 18
			creNameLbl.ZIndex = 3
			creNameLbl.Parent = eggFrame

			local rarLbl = Instance.new("TextLabel")
			rarLbl.Size = UDim2.new(1, 0, 0, 20)
			rarLbl.Position = UDim2.new(0, 0, 0, 50)
			rarLbl.BackgroundTransparency = 1
			rarLbl.Text = rarity
			rarLbl.TextColor3 = rarityColor
			rarLbl.Font = Enum.Font.GothamBold
			rarLbl.TextSize = 14
			rarLbl.ZIndex = 3
			rarLbl.Parent = eggFrame

			local tapLbl = Instance.new("TextLabel")
			tapLbl.Size = UDim2.new(1, 0, 0, 14)
			tapLbl.Position = UDim2.new(0, 0, 1, -20)
			tapLbl.BackgroundTransparency = 1
			tapLbl.Text = "tap to dismiss"
			tapLbl.TextColor3 = C.muted
			tapLbl.Font = Enum.Font.GothamMedium
			tapLbl.TextSize = 10
			tapLbl.ZIndex = 3
			tapLbl.Parent = eggFrame
		end)

		if not animOk then
			warn("[EggShopClient] Hatch animation error: " .. tostring(animErr))
			dismiss()
		end

		Notify.Toast("Hatched: " .. displayName .. " (" .. rarity .. ")!", rarityColor, 4)
	end)
end

if eggResult then
	eggResult.OnClientEvent:Connect(function(result)
		showHatchAnimation(result)
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
	if menuName == "EggShopGUI" then
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
			buildEggCards()
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
		buildEggCards()
	end
end)

-- FIX #18: Removed fallback R key handler — HUDButtonBar is the sole keyboard handler.
-- Having both caused double-toggle (open then immediately close).

print("[EggShopClient] Loaded - open via [G] Shop > Egg Shop")
