-- CosmeticShopClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Press C to open cosmetic shop. Buy trails, auras, name colors, base exteriors.

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

local buyCosmetic = Events:WaitForChild("BuyCosmetic", 8)
local equipCosmetic = Events:WaitForChild("EquipCosmetic", 8)
local buyExterior = Events:FindFirstChild("BuyExterior") or Events:WaitForChild("BuyExterior", 5)
local equipExterior = Events:FindFirstChild("EquipExterior") or Events:WaitForChild("EquipExterior", 5)
local buyBaseColor = Events:FindFirstChild("BuyBaseColor") or Events:WaitForChild("BuyBaseColor", 5)
local equipBaseColor = Events:FindFirstChild("EquipBaseColor") or Events:WaitForChild("EquipBaseColor", 5)
local getInventory = Events:WaitForChild("GetInventory", 8)
local coinsUpdate = Events:FindFirstChild("CoinsUpdate") or Events:WaitForChild("CoinsUpdate", 3)

-- #region agent log
do
	local HttpService = game:GetService("HttpService")
	pcall(function()
		HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
			location = "CosmeticShopClient.lua:remotes", message = "remotes after WaitForChild",
			data = { hasBuyCosmetic = buyCosmetic ~= nil, hasBuyExterior = buyExterior ~= nil, hasGetInventory = getInventory ~= nil },
			timestamp = math.floor(tick() * 1000), hypothesisId = "H1"
		}))
	end)
end
-- #endregion

-- -- COLORS --
local C = {
	bg = Color3.fromRGB(14, 16, 24),
	card = Color3.fromRGB(22, 26, 38),
	cardOwned = Color3.fromRGB(18, 35, 25),
	coin = Color3.fromRGB(255, 200, 50),
	gem = Color3.fromRGB(120, 80, 255),
	green = Color3.fromRGB(80, 220, 120),
	equipped = Color3.fromRGB(60, 200, 255),
	red = Color3.fromRGB(255, 70, 60),
	muted = Color3.fromRGB(120, 125, 140),
	white = Color3.new(1, 1, 1),
}

-- Panel scales with viewport (same pattern as other shops)
local PANEL_DESIGN_W = 440
local PANEL_DESIGN_H = 480
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

-- -- SCREEN GUI --
local sg = Instance.new("ScreenGui")
sg.Name = "CosmeticShopGUI"; sg.ResetOnSpawn = false; sg.DisplayOrder = 31; sg.Parent = playerGui

-- Main panel (size/position set on open via applyPanelScale; draggable)
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
panel.BackgroundColor3 = C.bg; panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0; panel.Visible = false; panel.Active = true; panel.Draggable = true; panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", panel).Color = Color3.fromRGB(80, 60, 120)

-- Title
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 42); titleBar.BackgroundColor3 = Color3.fromRGB(18, 22, 36)
titleBar.BorderSizePixel = 0; titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(0.6, 0, 1, 0); titleLbl.Position = UDim2.new(0, 15, 0, 0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "COSMETIC SHOP"
titleLbl.TextColor3 = C.gem; titleLbl.Font = Enum.Font.GothamBlack; titleLbl.TextSize = 18
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.Parent = titleBar

local currLbl = Instance.new("TextLabel")
currLbl.Name = "CurrLbl"
currLbl.Size = UDim2.new(0.4, -10, 1, 0); currLbl.Position = UDim2.new(0.6, 0, 0, 0)
currLbl.BackgroundTransparency = 1; currLbl.Text = "Coins: 0  |  Gems: 0"
currLbl.TextColor3 = C.muted; currLbl.Font = Enum.Font.GothamBold; currLbl.TextSize = 12
currLbl.TextXAlignment = Enum.TextXAlignment.Right; currLbl.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32); closeBtn.Position = UDim2.new(1, -38, 0, 5)
closeBtn.BackgroundColor3 = C.red; closeBtn.BackgroundTransparency = 0.5
closeBtn.Text = "X"; closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 14; closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function() panel.Visible = false end)

if coinsUpdate then
	coinsUpdate.OnClientEvent:Connect(function(balance)
		playerCoins = balance
		currLbl.Text = "Coins: " .. playerCoins .. "  |  Gems: " .. playerGems
	end)
end

-- Tab buttons
local tabFrame = Instance.new("Frame")
tabFrame.Size = UDim2.new(1, -20, 0, 30); tabFrame.Position = UDim2.new(0, 10, 0, 48)
tabFrame.BackgroundTransparency = 1; tabFrame.Parent = panel

local tabs = {"trail", "aura", "nameColor", "exterior", "baseColor"}
local tabLabels = {trail = "Trails", aura = "Auras", nameColor = "Names", exterior = "Base", baseColor = "Colors"}
local activeTab = "trail"
local tabButtons = {}

for i, tab in ipairs(tabs) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1/#tabs, -4, 1, 0); btn.Position = UDim2.new((i-1)/#tabs, 2, 0, 0)
	btn.BackgroundColor3 = C.card; btn.BorderSizePixel = 0
	btn.Text = tabLabels[tab]; btn.TextColor3 = C.muted
	btn.Font = Enum.Font.GothamBold; btn.TextSize = 11; btn.Parent = tabFrame
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	tabButtons[tab] = btn
end

-- Scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -90)
scroll.Position = UDim2.new(0, 10, 0, 84)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6); layout.Parent = scroll

-- -- REFRESH --

local playerCosmetics = {owned = {}, equipped = {}}
local playerExterior = {owned = {}, equipped = nil}
local playerBaseColor = {owned = {}, equipped = nil}
local playerCoins = 0
local playerGems = 0

local function refreshData()
	if not getInventory then return end
	local ok, data = pcall(function() return getInventory:InvokeServer() end)
	-- #region agent log
	do
		local HttpService = game:GetService("HttpService")
		pcall(function()
			HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
				location = "CosmeticShopClient.lua:refreshData", message = "getInventory result",
				data = { ok = ok, hasData = data ~= nil, coins = (data and data.coins) or "n/a", gems = (data and data.gems) or "n/a" },
				timestamp = math.floor(tick() * 1000), hypothesisId = "H2"
			}))
		end)
	end
	-- #endregion
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
		currLbl.Text = "Coins: " .. playerCoins .. "  |  Gems: " .. playerGems
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
				eqStroke.Color = C.equipped; eqStroke.Thickness = 1.5
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
						-- #region agent log
						do
							local HttpService = game:GetService("HttpService")
							pcall(function()
								HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
									location = "CosmeticShopClient.lua:exteriorBuyClick", message = "exterior buy before InvokeServer",
									data = { itemId = item.id, priceCurr = priceCurr },
									timestamp = math.floor(tick() * 1000), hypothesisId = "H4"
								}))
							end)
						end
						-- #endregion
						local pcallOk, a, b = pcall(function() return buyExterior:InvokeServer(item.id, priceCurr) end)
						local success, retMsg = pcallOk and a or false, (pcallOk and b or tostring(a)) or "nil"
						-- #region agent log
						do
							local HttpService = game:GetService("HttpService")
							pcall(function()
								HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
									location = "CosmeticShopClient.lua:exteriorBuyAfter", message = "exterior buy after InvokeServer",
									data = { itemId = item.id, pcallOk = pcallOk, success = success, msg = tostring(retMsg) },
									timestamp = math.floor(tick() * 1000), hypothesisId = "H4"
								}))
							end)
						end
						-- #endregion
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
		-- Base Colors tab: walls, stairs, points, combiner, recycler
		local items = (GameConfig.BaseColorItems or {})
		for _, item in ipairs(items) do
			order = order + 1
			local owned = playerBaseColor.owned and playerBaseColor.owned[item.id] == true
			local equipped = playerBaseColor.equipped == item.id

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 58); card.LayoutOrder = order
			card.BackgroundColor3 = equipped and Color3.fromRGB(20, 35, 50) or (owned and C.cardOwned or C.card)
			card.BorderSizePixel = 0; card.Parent = scroll
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
			if equipped then
				local eqStroke = Instance.new("UIStroke", card)
				eqStroke.Color = C.equipped; eqStroke.Thickness = 1.5
			end

			-- Color swatch
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
					if equipBaseColor then
						local ok, msg = equipBaseColor:InvokeServer(nil)
						if ok then
							playerBaseColor.equipped = nil
							buildItems()
							Notify.Toast("Restored default gray base", C.muted, 2)
						end
					end
				end)
			elseif owned then
				btn.Text = "Equip"; btn.TextColor3 = C.equipped
				btn.BackgroundColor3 = Color3.fromRGB(25, 50, 70)
				btn.MouseButton1Click:Connect(function()
					if equipBaseColor then
						local ok, msg = equipBaseColor:InvokeServer(item.id)
						if ok then
							playerBaseColor.equipped = item.id
							buildItems()
							Notify.Toast("Equipped " .. item.name .. " base color", C.equipped, 3)
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
					if buyBaseColor then
						local pcallOk, a, b = pcall(function() return buyBaseColor:InvokeServer(item.id, priceCurr) end)
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
				eqStroke.Color = C.equipped; eqStroke.Thickness = 1.5
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
						-- #region agent log
						do
							local HttpService = game:GetService("HttpService")
							pcall(function()
								HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
									location = "CosmeticShopClient.lua:buyClick", message = "cosmetic buy before InvokeServer",
									data = { itemId = item.id, priceCurr = priceCurr },
									timestamp = math.floor(tick() * 1000), hypothesisId = "H4"
								}))
							end)
						end
						-- #endregion
						local pcallOk, a, b = pcall(function() return buyCosmetic:InvokeServer(item.id, priceCurr) end)
						local success, retMsg = pcallOk and a or false, (pcallOk and b or tostring(a)) or "nil"
						-- #region agent log
						do
							local HttpService = game:GetService("HttpService")
							pcall(function()
								HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
									location = "CosmeticShopClient.lua:buyClickAfter", message = "cosmetic buy after InvokeServer",
									data = { itemId = item.id, pcallOk = pcallOk, success = success, msg = tostring(retMsg) },
									timestamp = math.floor(tick() * 1000), hypothesisId = "H4"
								}))
							end)
						end
						-- #endregion
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
		for t, b in pairs(tabButtons) do
			b.BackgroundColor3 = t == tab and Color3.fromRGB(40, 45, 65) or C.card
			b.TextColor3 = t == tab and C.white or C.muted
		end
		buildItems()
	end)
end

-- Toggle from HUD only (key C and [C] button both fire HUDToggleMenu from HUDButtonBar)
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
		panel.Visible = not panel.Visible
		if panel.Visible then refreshData(); buildItems() end
	end
end
getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then child.Event:Connect(onHUDToggle) end
end)

-- C key: open/close cosmetics (client-side fallback)
UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode ~= Enum.KeyCode.C then return end
	onHUDToggle("CosmeticShopGUI")
end)

print("[CosmeticShopClient] Loaded - press C or click [C] Cosmetics on HUD to open")