-- ScoinsShopClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Last updated: 2026-04-19
-- Shop hub: buy SCoins with Diamonds (gems).
-- ─────────────────────────────────────────────────────────────
-- Visual redesign pass: matches mockups/coin-shop/index.html as
-- closely as Roblox native UI allows. Pure client-side styling —
-- no config, server, or RemoteEvent contracts changed.
-- Revert with: git checkout HEAD -- ScoinsShopClient.client.lua
-- ─────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)
local DiamondNeedHint = require(ReplicatedStorage.Modules:WaitForChild("DiamondNeedHint"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local buyScoinsPack = Events:WaitForChild("BuyScoinsPack", 10)
local getInventory  = Events:WaitForChild("GetInventory", 10)
local gemsUpdate    = Events:FindFirstChild("GemsUpdate")   or Events:WaitForChild("GemsUpdate", 5)
local scoinsUpdate  = Events:FindFirstChild("SCoinsUpdate") or Events:WaitForChild("SCoinsUpdate", 5)

-- ═══════════════════════════════════════════════════════════════════
-- Layout + palette
-- ═══════════════════════════════════════════════════════════════════
local PANEL_DESIGN_W = 700
local PANEL_DESIGN_H = 540
local HEADER_H, SUBBAR_H, FOOTER_H = 72, 44, 28
local CARD_PADDING, CARD_GAP = 14, 12

local C = {
	panelTop   = Color3.fromRGB(58, 29, 92),
	panelBot   = Color3.fromRGB(14, 8, 32),
	headerTop  = Color3.fromRGB(58, 29, 92),
	headerBot  = Color3.fromRGB(42, 19, 68),

	goldLight  = Color3.fromRGB(255, 227, 107),
	goldMid    = Color3.fromRGB(255, 177, 59),
	goldDark   = Color3.fromRGB(184, 116, 10),
	goldBorder = Color3.fromRGB(255, 194, 58),

	gemLight = Color3.fromRGB(122, 243, 255),
	gemMid   = Color3.fromRGB(41, 182, 255),
	gemDark  = Color3.fromRGB(27, 76, 179),

	coinLight = Color3.fromRGB(255, 232, 133),
	coinMid   = Color3.fromRGB(255, 194, 58),
	coinDark  = Color3.fromRGB(163, 95, 9),

	textLight = Color3.fromRGB(255, 244, 214),
	textDim   = Color3.fromRGB(199, 179, 224),
	black     = Color3.fromRGB(14, 8, 32),
	green     = Color3.fromRGB(107, 226, 107),
	red       = Color3.fromRGB(255, 77, 122),
	orange    = Color3.fromRGB(255, 122, 41),

	cardBgTop = Color3.fromRGB(42, 24, 86),
	cardBgBot = Color3.fromRGB(21, 10, 48),
}

local TIER_META = {
	handful = { tier = "COMMON",    color = Color3.fromRGB(177, 181, 196), order = 1 },
	bag     = { tier = "UNCOMMON",  color = Color3.fromRGB(107, 226, 107), order = 2 },
	sack    = { tier = "RARE",      color = Color3.fromRGB( 87, 168, 255), order = 3 },
	chest   = { tier = "EPIC",      color = Color3.fromRGB(200, 118, 255), order = 4 },
	safe    = { tier = "LEGENDARY", color = Color3.fromRGB(255, 186,  43), order = 5 },
	bank    = { tier = "MYTHIC",    color = Color3.fromRGB(255,  77, 122), order = 6 },
}

local BASELINE_RATIO = 5000 / 100 -- Handful = 50 scoins per gem

local function bonusMultiplier(pack)
	return (pack.scoins / math.max(1, pack.gemCost)) / BASELINE_RATIO
end

local function fmt(n)
	local s, k = tostring(math.floor(n + 0.5)), 1
	while k ~= 0 do
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	end
	return s
end

-- ═══════════════════════════════════════════════════════════════════
-- UI helpers (keeps Instance.new clutter contained)
-- ═══════════════════════════════════════════════════════════════════
local function addCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

local function addStroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function addVGradient(parent, topColor, bottomColor)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	})
	g.Rotation = 90
	g.Parent = parent
	return g
end

-- Fake CSS text-shadow with a twin TextLabel offset behind the front
local function makeShadowedText(parent, text, opts)
	local shadow = Instance.new("TextLabel")
	shadow.BackgroundTransparency = 1
	shadow.Size = opts.size
	shadow.Position = opts.position + UDim2.new(0, 2, 0, 2)
	shadow.Font = opts.font
	shadow.TextSize = opts.textSize
	shadow.TextColor3 = opts.shadowColor
	shadow.Text = text
	shadow.TextXAlignment = opts.xAlign or Enum.TextXAlignment.Center
	shadow.TextYAlignment = opts.yAlign or Enum.TextYAlignment.Center
	shadow.Parent = parent

	local front = shadow:Clone()
	front.Position = opts.position
	front.TextColor3 = opts.color
	front.Parent = parent
	return front
end

-- Balance pill (translucent rounded capsule with a colored currency dot)
local function makeBalancePill(iconText, dotTop, dotBot, dotBorder, dotTextColor, showPlus)
	local pill = Instance.new("Frame")
	pill.BackgroundColor3 = C.black
	pill.BackgroundTransparency = 0.55
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(0, showPlus and 128 or 108, 0, 34)
	addCorner(pill, 17)
	addStroke(pill, Color3.fromRGB(255, 255, 255), 2, 0.88)

	local dot = Instance.new("TextLabel")
	dot.Size = UDim2.new(0, 24, 0, 24)
	dot.Position = UDim2.new(0, 5, 0.5, -12)
	dot.BackgroundColor3 = dotTop
	dot.BorderSizePixel = 0
	dot.Font = Enum.Font.GothamBlack
	dot.TextSize = 13
	dot.TextColor3 = dotTextColor
	dot.Text = iconText
	dot.Parent = pill
	addCorner(dot, 12)
	addStroke(dot, dotBorder, 2, 0)
	addVGradient(dot, dotTop, dotBot)

	local num = Instance.new("TextLabel")
	num.BackgroundTransparency = 1
	num.Size = UDim2.new(1, showPlus and -60 or -34, 1, 0)
	num.Position = UDim2.new(0, 34, 0, 0)
	num.Font = Enum.Font.GothamBlack
	num.TextSize = 14
	num.TextColor3 = C.textLight
	num.TextXAlignment = Enum.TextXAlignment.Left
	num.Text = "0"
	num.Parent = pill

	local plus
	if showPlus then
		plus = Instance.new("TextButton")
		plus.Size = UDim2.new(0, 22, 0, 22)
		plus.Position = UDim2.new(1, -27, 0.5, -11)
		plus.BackgroundColor3 = C.green
		plus.BorderSizePixel = 0
		plus.Font = Enum.Font.GothamBlack
		plus.TextSize = 16
		plus.TextColor3 = C.black
		plus.Text = "+"
		plus.Parent = pill
		addCorner(plus, 11)
		addStroke(plus, Color3.fromRGB(167, 255, 199), 2, 0)
	end

	return pill, num, plus
end

-- ═══════════════════════════════════════════════════════════════════
-- ScreenGui + panel
-- ═══════════════════════════════════════════════════════════════════
local sg = Instance.new("ScreenGui")
sg.Name = "ScoinsShopGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 100
sg.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W / 2, 0.5, -PANEL_DESIGN_H / 2)
panel.BackgroundColor3 = C.panelBot
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = true
panel.Draggable = true
panel.ClipsDescendants = true
panel.Parent = sg
addCorner(panel, 22)
addStroke(panel, C.goldBorder, 4, 0)
addVGradient(panel, C.panelTop, C.panelBot)

-- ═══════════════════════════════════════════════════════════════════
-- Header
-- ═══════════════════════════════════════════════════════════════════
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C.headerBot
header.BorderSizePixel = 0
header.Parent = panel
addVGradient(header, C.headerTop, C.headerBot)

local headerSep = Instance.new("Frame")
headerSep.Size = UDim2.new(1, 0, 0, 3)
headerSep.Position = UDim2.new(0, 0, 1, -3)
headerSep.BackgroundColor3 = C.goldBorder
headerSep.BorderSizePixel = 0
headerSep.Parent = header

-- Title coin-badge
local titleIcon = Instance.new("Frame")
titleIcon.Size = UDim2.new(0, 50, 0, 50)
titleIcon.Position = UDim2.new(0, 12, 0.5, -25)
titleIcon.BackgroundColor3 = C.coinMid
titleIcon.BorderSizePixel = 0
titleIcon.Parent = header
addCorner(titleIcon, 14)
addStroke(titleIcon, Color3.fromRGB(255, 243, 161), 3, 0)
addVGradient(titleIcon, C.coinLight, C.coinDark)

local titleIconLbl = Instance.new("TextLabel")
titleIconLbl.BackgroundTransparency = 1
titleIconLbl.Size = UDim2.new(1, 0, 1, 0)
titleIconLbl.Font = Enum.Font.GothamBlack
titleIconLbl.TextSize = 24
titleIconLbl.TextColor3 = Color3.fromRGB(90, 50, 0)
titleIconLbl.Text = "$"
titleIconLbl.Parent = titleIcon

-- Title + subtitle
makeShadowedText(header, "COIN EXCHANGE", {
	size = UDim2.new(0, 300, 0, 32),
	position = UDim2.new(0, 72, 0, 8),
	font = Enum.Font.FredokaOne,
	textSize = 28,
	color = C.coinLight,
	shadowColor = C.coinDark,
	xAlign = Enum.TextXAlignment.Left,
})

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Size = UDim2.new(0, 300, 0, 18)
subtitle.Position = UDim2.new(0, 72, 0, 42)
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextSize = 11
subtitle.TextColor3 = C.textDim
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "Trade your Diamonds for stacks of SCoins"
subtitle.Parent = header

-- Balance pills (top-right)
local pillsHolder = Instance.new("Frame")
pillsHolder.BackgroundTransparency = 1
pillsHolder.AnchorPoint = Vector2.new(1, 0.5)
pillsHolder.Size = UDim2.new(0, 260, 0, 34)
pillsHolder.Position = UDim2.new(1, -56, 0.5, 0)
pillsHolder.Parent = header

local pillsLayout = Instance.new("UIListLayout")
pillsLayout.FillDirection = Enum.FillDirection.Horizontal
pillsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
pillsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pillsLayout.Padding = UDim.new(0, 8)
pillsLayout.SortOrder = Enum.SortOrder.LayoutOrder
pillsLayout.Parent = pillsHolder

local gemPill, gemNumLbl = makeBalancePill(
	"◆", C.gemLight, C.gemDark,
	Color3.fromRGB(184, 250, 255), Color3.fromRGB(255, 255, 255), true
)
gemPill.LayoutOrder = 1
gemPill.Parent = pillsHolder

local coinPill, coinNumLbl = makeBalancePill(
	"$", C.coinLight, C.coinDark,
	Color3.fromRGB(255, 243, 161), Color3.fromRGB(90, 50, 0), false
)
coinPill.LayoutOrder = 2
coinPill.Parent = pillsHolder

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 34, 0, 34)
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(177, 38, 58)
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 18
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "X"
closeBtn.Parent = header
addCorner(closeBtn, 10)
addStroke(closeBtn, Color3.fromRGB(255, 141, 160), 3, 0)

closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	sg.IgnoreGuiInset = false
	MobileWindowLayout.NotifyMenuClosed()
end)

-- ═══════════════════════════════════════════════════════════════════
-- Subbar (tabs + rate hint)
-- ═══════════════════════════════════════════════════════════════════
local subbar = Instance.new("Frame")
subbar.Size = UDim2.new(1, 0, 0, SUBBAR_H)
subbar.Position = UDim2.new(0, 0, 0, HEADER_H)
subbar.BackgroundColor3 = C.black
subbar.BackgroundTransparency = 0.6
subbar.BorderSizePixel = 0
subbar.Parent = panel

local subbarSep = Instance.new("Frame")
subbarSep.Size = UDim2.new(1, 0, 0, 2)
subbarSep.Position = UDim2.new(0, 0, 1, -2)
subbarSep.BackgroundColor3 = C.goldBorder
subbarSep.BackgroundTransparency = 0.5
subbarSep.BorderSizePixel = 0
subbarSep.Parent = subbar

local function makeTab(text, active)
	local tab = Instance.new("TextLabel")
	tab.BackgroundColor3 = active and C.goldMid or Color3.fromRGB(255, 255, 255)
	tab.BackgroundTransparency = active and 0 or 0.92
	tab.Text = text
	tab.Font = Enum.Font.GothamBlack
	tab.TextSize = 12
	tab.TextColor3 = active and Color3.fromRGB(42, 19, 68) or C.textDim
	tab.Size = UDim2.new(0, 112, 0, 30)
	tab.BorderSizePixel = 0
	addCorner(tab, 8)
	if active then
		addStroke(tab, Color3.fromRGB(255, 243, 161), 2, 0)
		addVGradient(tab, C.goldLight, C.goldMid)
	else
		addStroke(tab, Color3.fromRGB(255, 255, 255), 2, 0.85)
	end
	return tab
end

local tabsHolder = Instance.new("Frame")
tabsHolder.BackgroundTransparency = 1
tabsHolder.Size = UDim2.new(0, 380, 0, 30)
tabsHolder.Position = UDim2.new(0, 12, 0.5, -15)
tabsHolder.Parent = subbar

local tabsLayout = Instance.new("UIListLayout")
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.Padding = UDim.new(0, 6)
tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabsLayout.Parent = tabsHolder

local t1 = makeTab("COIN PACKS", true);  t1.LayoutOrder = 1; t1.Parent = tabsHolder
local t2 = makeTab("BOOSTS", false);     t2.LayoutOrder = 2; t2.Parent = tabsHolder
local t3 = makeTab("BUNDLES", false);    t3.LayoutOrder = 3; t3.Parent = tabsHolder

local rateLbl = Instance.new("TextLabel")
rateLbl.BackgroundTransparency = 1
rateLbl.AnchorPoint = Vector2.new(1, 0.5)
rateLbl.Size = UDim2.new(0, 240, 0, 24)
rateLbl.Position = UDim2.new(1, -12, 0.5, 0)
rateLbl.Font = Enum.Font.GothamMedium
rateLbl.TextSize = 11
rateLbl.TextColor3 = C.textDim
rateLbl.TextXAlignment = Enum.TextXAlignment.Right
rateLbl.Text = "Bigger packs give MUCH more value"
rateLbl.Parent = subbar

-- ═══════════════════════════════════════════════════════════════════
-- Scroll grid + footer
-- ═══════════════════════════════════════════════════════════════════
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -CARD_PADDING * 2,
	1, -(HEADER_H + SUBBAR_H + FOOTER_H + CARD_PADDING * 2))
scroll.Position = UDim2.new(0, CARD_PADDING, 0, HEADER_H + SUBBAR_H + CARD_PADDING)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.ScrollBarImageColor3 = C.goldBorder
scroll.ScrollBarImageTransparency = 0.5
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 210, 0, 184)
grid.CellPadding = UDim2.new(0, CARD_GAP, 0, CARD_GAP)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.Parent = scroll

local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
footer.Position = UDim2.new(0, 0, 1, -FOOTER_H)
footer.BackgroundColor3 = C.black
footer.BackgroundTransparency = 0.55
footer.BorderSizePixel = 0
footer.Parent = panel

local footerSep = Instance.new("Frame")
footerSep.Size = UDim2.new(1, 0, 0, 2)
footerSep.BackgroundColor3 = C.goldBorder
footerSep.BackgroundTransparency = 0.5
footerSep.BorderSizePixel = 0
footerSep.Parent = footer

local footerLeft = Instance.new("TextLabel")
footerLeft.BackgroundTransparency = 1
footerLeft.Size = UDim2.new(0.6, -12, 1, 0)
footerLeft.Position = UDim2.new(0, 12, 0, 0)
footerLeft.Font = Enum.Font.GothamMedium
footerLeft.TextSize = 11
footerLeft.TextColor3 = C.textDim
footerLeft.TextXAlignment = Enum.TextXAlignment.Left
footerLeft.Text = "Siege Monsters · SCoin Exchange"
footerLeft.Parent = footer

local footerRight = Instance.new("TextLabel")
footerRight.BackgroundTransparency = 1
footerRight.AnchorPoint = Vector2.new(1, 0)
footerRight.Size = UDim2.new(0.6, -12, 1, 0)
footerRight.Position = UDim2.new(1, -12, 0, 0)
footerRight.Font = Enum.Font.GothamMedium
footerRight.TextSize = 11
footerRight.TextColor3 = C.textDim
footerRight.TextXAlignment = Enum.TextXAlignment.Right
footerRight.Text = "Tip: Legendary+ unlock massive bonus value"
footerRight.Parent = footer

-- ═══════════════════════════════════════════════════════════════════
-- Balance refresh
-- ═══════════════════════════════════════════════════════════════════
local playerGems, playerScoins = 0, 0

local function refreshBalances()
	if not getInventory then return end
	local ok, data = pcall(function()
		return getInventory:InvokeServer()
	end)
	if ok and data then
		playerGems   = data.gems   or 0
		playerScoins = data.scoins or 0
		gemNumLbl.Text  = fmt(playerGems)
		coinNumLbl.Text = fmt(playerScoins)
	end
end

if gemsUpdate   then gemsUpdate.OnClientEvent:Connect(refreshBalances) end
if scoinsUpdate then scoinsUpdate.OnClientEvent:Connect(refreshBalances) end

-- ═══════════════════════════════════════════════════════════════════
-- Card builder — one card per pack
-- ═══════════════════════════════════════════════════════════════════
local function buildCard(pack, isBestValue)
	local meta = TIER_META[pack.id]
		or { tier = "PACK", color = Color3.fromRGB(200, 200, 200), order = 99 }

	local card = Instance.new("Frame")
	card.BackgroundColor3 = C.cardBgTop
	card.BorderSizePixel = 0
	card.LayoutOrder = meta.order
	addCorner(card, 16)
	addStroke(card, meta.color, 3, 0)
	addVGradient(card, C.cardBgTop, C.cardBgBot)

	-- Tier badge (top-left)
	local tierBadge = Instance.new("TextLabel")
	tierBadge.Size = UDim2.new(0, 90, 0, 20)
	tierBadge.Position = UDim2.new(0, 10, 0, 10)
	tierBadge.BackgroundColor3 = meta.color
	tierBadge.Text = meta.tier
	tierBadge.Font = Enum.Font.GothamBlack
	tierBadge.TextSize = 11
	tierBadge.TextColor3 = Color3.fromRGB(18, 9, 31)
	tierBadge.BorderSizePixel = 0
	tierBadge.Parent = card
	addCorner(tierBadge, 6)
	addStroke(tierBadge, Color3.fromRGB(255, 255, 255), 1, 0.5)

	-- Right-side chip: BEST VALUE or NxVALUE multiplier
	if isBestValue then
		local best = Instance.new("TextLabel")
		best.Size = UDim2.new(0, 84, 0, 20)
		best.AnchorPoint = Vector2.new(1, 0)
		best.Position = UDim2.new(1, -10, 0, 10)
		best.BackgroundColor3 = C.green
		best.Text = "BEST VALUE"
		best.Font = Enum.Font.GothamBlack
		best.TextSize = 10
		best.TextColor3 = Color3.fromRGB(14, 45, 26)
		best.BorderSizePixel = 0
		best.Parent = card
		addCorner(best, 6)
		addStroke(best, Color3.fromRGB(198, 255, 198), 2, 0)
	elseif bonusMultiplier(pack) > 1.0001 then
		local chip = Instance.new("TextLabel")
		chip.Size = UDim2.new(0, 72, 0, 20)
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -10, 0, 10)
		chip.BackgroundColor3 = C.orange
		chip.Text = string.format("%.1fx VALUE", bonusMultiplier(pack))
		chip.Font = Enum.Font.GothamBlack
		chip.TextSize = 10
		chip.TextColor3 = Color3.fromRGB(255, 255, 255)
		chip.BorderSizePixel = 0
		chip.Parent = card
		addCorner(chip, 6)
		addStroke(chip, Color3.fromRGB(255, 208, 174), 2, 0)
	end

	-- Coin visual (halo + gold circle) — substitutes the CSS coin stack
	local coinHolder = Instance.new("Frame")
	coinHolder.BackgroundTransparency = 1
	coinHolder.Size = UDim2.new(0, 64, 0, 64)
	coinHolder.AnchorPoint = Vector2.new(0.5, 0)
	coinHolder.Position = UDim2.new(0.5, 0, 0, 36)
	coinHolder.Parent = card

	local halo = Instance.new("Frame")
	halo.Size = UDim2.new(1.4, 0, 1.4, 0)
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.new(0.5, 0, 0.5, 0)
	halo.BackgroundColor3 = meta.color
	halo.BackgroundTransparency = 0.75
	halo.BorderSizePixel = 0
	halo.Parent = coinHolder
	addCorner(halo, 999)

	local coin = Instance.new("Frame")
	coin.Size = UDim2.new(1, 0, 1, 0)
	coin.BackgroundColor3 = C.coinMid
	coin.BorderSizePixel = 0
	coin.Parent = coinHolder
	addCorner(coin, 999)
	addStroke(coin, Color3.fromRGB(255, 243, 161), 3, 0)
	addVGradient(coin, C.coinLight, C.coinDark)

	local coinLbl = Instance.new("TextLabel")
	coinLbl.BackgroundTransparency = 1
	coinLbl.Size = UDim2.new(1, 0, 1, 0)
	coinLbl.Font = Enum.Font.GothamBlack
	coinLbl.TextSize = 28
	coinLbl.TextColor3 = Color3.fromRGB(90, 50, 0)
	coinLbl.Text = "$"
	coinLbl.Parent = coin

	-- Amount + "SCOINS" subtitle
	makeShadowedText(card, fmt(pack.scoins), {
		size = UDim2.new(1, -20, 0, 26),
		position = UDim2.new(0, 10, 0, 106),
		font = Enum.Font.FredokaOne,
		textSize = 22,
		color = C.coinLight,
		shadowColor = C.coinDark,
	})

	local amountSub = Instance.new("TextLabel")
	amountSub.BackgroundTransparency = 1
	amountSub.Size = UDim2.new(1, -20, 0, 12)
	amountSub.Position = UDim2.new(0, 10, 0, 130)
	amountSub.Font = Enum.Font.GothamBold
	amountSub.TextSize = 9
	amountSub.TextColor3 = C.textDim
	amountSub.Text = "SCOINS"
	amountSub.Parent = card

	-- Buy button (gem-blue bevel)
	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(1, -20, 0, 32)
	buyBtn.AnchorPoint = Vector2.new(0, 1)
	buyBtn.Position = UDim2.new(0, 10, 1, -10)
	buyBtn.BackgroundColor3 = C.gemMid
	buyBtn.BorderSizePixel = 0
	buyBtn.AutoButtonColor = false
	buyBtn.Font = Enum.Font.FredokaOne
	buyBtn.TextSize = 16
	buyBtn.TextColor3 = Color3.fromRGB(7, 25, 46)
	buyBtn.Text = fmt(pack.gemCost) .. "  ◆"
	buyBtn.Parent = card
	addCorner(buyBtn, 10)
	addStroke(buyBtn, Color3.fromRGB(184, 250, 255), 3, 0)
	addVGradient(buyBtn, C.gemLight, C.gemDark)

	-- Hover tweens (desktop-only — MouseEnter doesn't fire on touch)
	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12),
			{ Position = UDim2.new(0, 0, 0, -4) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12),
			{ Position = UDim2.new(0, 0, 0, 0) }):Play()
	end)

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

	return card
end

-- ═══════════════════════════════════════════════════════════════════
-- Rebuild grid from config
-- ═══════════════════════════════════════════════════════════════════
local function buildList()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end

	local packs = GameConfig.ScoinsGemPacks or {}

	-- Highest coins-per-gem ratio wins the "BEST VALUE" badge
	local bestId, bestRatio = nil, 0
	for _, p in ipairs(packs) do
		local r = (p.scoins or 0) / math.max(1, p.gemCost or 1)
		if r > bestRatio then bestRatio, bestId = r, p.id end
	end

	for _, pack in ipairs(packs) do
		local card = buildCard(pack, pack.id == bestId)
		card.Parent = scroll
	end

	scroll.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 10)
end

-- ═══════════════════════════════════════════════════════════════════
-- Mobile window scaling
-- ═══════════════════════════════════════════════════════════════════
local function applyPanelScale()
	MobileWindowLayout.SyncNpcMenuScreenGui(sg, PANEL_DESIGN_W, PANEL_DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(panel,
			MobileWindowLayout.GetNpcFullscreenBoundsConfig(PANEL_DESIGN_W, PANEL_DESIGN_H))
	else
		sg.IgnoreGuiInset = false
		panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
		panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W / 2, 0.5, -PANEL_DESIGN_H / 2)
		MobileWindowLayout.RestoreDesktopWindow(panel, { draggable = true })
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- HUD toggle wiring (unchanged; follows FIX #18)
-- ═══════════════════════════════════════════════════════════════════
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

print("[ScoinsShopClient] Loaded — Shop hub → SCoins (redesigned 2026-04-19)")

