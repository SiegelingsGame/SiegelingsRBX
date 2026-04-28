-- ══════════════════════════════════════════════════════════════════════════════
-- PlayerProfileClient.client.lua  (StarterPlayerScripts — LocalScript)
-- ══════════════════════════════════════════════════════════════════════════════
-- Unified player menu with three tabs:
--   1. Profile  – level, XP, economy, stats, base floors
--   2. Sigils   – boss sigil checklist (squire / knight / lord)
--   3. Rebirth  – reset for permanent bonuses (requirements + confirmation)
--
-- FIX #34: Merged BossBackboardClient and RebirthUIClient into this single
--          tabbed menu.  Their standalone scripts are disabled (early return).
--          HUDButtonBar now only has [P] Profile; [R] Sigils and [Z] Rebirth
--          buttons removed.  Backward-compat: "BossBackboardGUI" and
--          "RebirthUI" toggle events open this menu to the matching tab.
--
-- Toggle: [P] key or Profile HUD button (via HUDToggleMenu BindableEvent).
-- ══════════════════════════════════════════════════════════════════════════════
-- Last updated: 2026-04-18 23:59

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig    = require(ReplicatedStorage.Modules.GameConfig)
local Notify        = require(ReplicatedStorage.Modules.NotificationManager)
local CreatureData  = require(ReplicatedStorage.Modules.CreatureData)
local CreatureModelLoader = nil
pcall(function()
	CreatureModelLoader = require(ReplicatedStorage.Modules:WaitForChild("CreatureModelLoader"))
end)
local AchievementsConfig = nil
pcall(function()
	AchievementsConfig = require(ReplicatedStorage.Modules:WaitForChild("AchievementsConfig"))
end)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then warn("[Profile] Events missing") return end

-- Remote references (profile)
local getProfile   = Events:WaitForChild("GetProfile", 8)
local buyFloor     = Events:WaitForChild("BuyFloor", 8)
local playerLevelUp = Events:WaitForChild("PlayerLevelUp", 8)
local CoinsUpdate   = Events:FindFirstChild("CoinsUpdate")
local GemsUpdate    = Events:FindFirstChild("GemsUpdate")
local IncomeReceived = Events:FindFirstChild("IncomeReceived")

-- Remote references (sigils)
local getInventory = Events:FindFirstChild("GetInventory")
local sigilEarned  = Events:FindFirstChild("SigilEarned")

-- Remote references (rebirth)
local getRebirthInfo = Events:FindFirstChild("GetRebirthInfo")
local requestRebirth = Events:FindFirstChild("RequestRebirth")
local rebirthSuccess = Events:FindFirstChild("RebirthSuccess")
local rebirthFailed  = Events:FindFirstChild("RebirthFailed")

-- Remote references (achievements)
local getAchievements = Events:FindFirstChild("GetAchievements")
local achievementProgress = Events:FindFirstChild("AchievementProgress")
local achievementUnlocked = Events:FindFirstChild("AchievementUnlocked")

-- ══════════════════════════════════════════════════════════════════════════════
-- Colors
-- ══════════════════════════════════════════════════════════════════════════════

local C = {
	bg            = Color3.fromRGB(14, 15, 22),
	bgLight       = Color3.fromRGB(22, 24, 35),
	card          = Color3.fromRGB(28, 30, 42),
	accent        = Color3.fromRGB(200, 180, 255),
	rebirthAccent = Color3.fromRGB(255, 180, 80),
	sigilAccent   = Color3.fromRGB(255, 92, 53),
	text          = Color3.fromRGB(240, 240, 245),
	textSec       = Color3.fromRGB(140, 145, 160),
	textMut       = Color3.fromRGB(80, 85, 100),
	gold          = Color3.fromRGB(255, 200, 50),
	green         = Color3.fromRGB(80, 220, 120),
	red           = Color3.fromRGB(220, 60, 70),
	blue          = Color3.fromRGB(60, 160, 255),
	xpBar         = Color3.fromRGB(130, 100, 255),
	divider       = Color3.fromRGB(40, 42, 55),
	tabActive     = Color3.fromRGB(255, 200, 50),   -- gold underline
	tabInactive   = Color3.fromRGB(80, 85, 100),
	income        = Color3.fromRGB(50, 220, 120),
	battlePurple  = Color3.fromRGB(130, 100, 255),
	achieveAccent = Color3.fromRGB(255, 215, 90),
	rarityCommon     = Color3.fromRGB(180, 180, 180),
	rarityUncommon   = Color3.fromRGB(75, 200, 75),
	rarityRare       = Color3.fromRGB(60, 130, 255),
	rarityEpic       = Color3.fromRGB(180, 80, 255),
	rarityLegendary  = Color3.fromRGB(255, 184, 0),
}

local RARITY_COLORS = {
	Common    = C.rarityCommon,
	Uncommon  = C.rarityUncommon,
	Rare      = C.rarityRare,
	Epic      = C.rarityEpic,
	Legendary = C.rarityLegendary,
}

-- ══════════════════════════════════════════════════════════════════════════════
-- Sigil config (from GameConfig, same as old BossBackboardClient)
-- ══════════════════════════════════════════════════════════════════════════════

local ELEMENTAL_ELEMENTS = GameConfig.ElementalBossElements or { "Fire", "Ice", "Wind", "Earth" }
local SIEGE_LABELS       = GameConfig.SiegeKnightSigilLabels or { "Desert", "Cave", "Ocean", "Cyber" }
local SIEGE_ZONE_IDS     = GameConfig.SiegeKnightSigilZoneIds or { "Desert", "Cave", "Ocean", "Electric" }
local SIEGE_LORD_ZONE_ID = GameConfig.SiegeLordSigilZoneId or "Badlands"
local SIEGE_LORD_SUB     = GameConfig.SiegeLordSigilSubtext or "Successful extraction"

local TOTAL_SIGIL_COUNT = 9 -- 4 Squire + 4 Knight + 1 Lord
local KNIGHT_ZONE_BOSS_ELEMENT = {
	Desert = "Fire",
	Cave = "Earth",
	Ocean = "Water",
	Electric = "Lightning",
}
local SIGIL_ELEMENT_EMOJI = {
	Fire = "🔥",
	Ice = "❄️",
	Wind = "💨",
	Earth = "🌍",
}
local KNIGHT_ZONE_EMOJI = {
	Desert = "🏜️",
	Cave = "🦇",
	Ocean = "🌊",
	Electric = "⚡",
}

local DEFAULT_SIGIL_ELEMENTS = { "Fire", "Ice", "Wind", "Earth" }

--- GameConfig.ElementalBossElements must be a sequential array; if # is 0, sigil rows would be empty.
local function getSquireElementList()
	local t = ELEMENTAL_ELEMENTS
	if type(t) ~= "table" or #t < 1 then
		return DEFAULT_SIGIL_ELEMENTS
	end
	return t
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Layout constants
-- ══════════════════════════════════════════════════════════════════════════════

local PANEL_DESIGN_W   = 775
local PANEL_DESIGN_H   = 560   -- slightly taller for tab bar
local SIDEBAR_DESIGN_W = 200
local PANEL_SCALE_MIN  = 0.55
local PANEL_SCALE_MAX  = 1
local TAB_BAR_HEIGHT   = 36
local HEADER_HEIGHT    = 56
local MOBILE_BREAKPOINT = 620
-- Tab bar uses 4 equal columns; Sigils + Rebirth = middle 50% — align name + XP with that span
local PROFILE_HDR_MID_X = 1 / 4
local PROFILE_HDR_MID_W = 2 / 4

local function rgbToHex(c)
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function escapeRichText(s)
	s = tostring(s or "")
	s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	return s
end

-- Same abbreviation rules as HUD coin bar (HUDClient.formatAbbrev): K / M / B / T.
local function formatAbbrev(n)
	n = tonumber(n) or 0
	local neg = n < 0
	n = math.abs(n)
	local function trunc2(x)
		return math.floor(x * 100) / 100
	end
	local function fmt(x, suffix)
		local v = trunc2(x)
		local s
		if v == math.floor(v) then
			s = tostring(math.floor(v))
		else
			s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
		end
		return s .. suffix
	end
	local out
	if n >= 1e12 then      out = fmt(n / 1e12, "T")
	elseif n >= 1e9 then   out = fmt(n / 1e9,  "B")
	elseif n >= 1e6 then   out = fmt(n / 1e6,  "M")
	elseif n >= 1e3 then   out = fmt(n / 1e3,  "K")
	else                    out = tostring(math.floor(n))
	end
	return neg and ("-" .. out) or out
end

--- Highest unlocked floor title for header (matches floor list copy).
local function siegeRankTitleFromMaxFloor(maxFloor)
	if maxFloor >= 4 then
		return "Siegelord"
	elseif maxFloor >= 3 then
		return "Siege Knight"
	elseif maxFloor >= 2 then
		return "Siege Squire"
	end
	return ""
end

local function isMobileLayout()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	return MobileWindowLayout.IsMobile() or vp.X < MOBILE_BREAKPOINT or vp.Y < 500
end

-- Match InventoryUI: full safe-area rect, vertical bleed, no hub gap (same GetBounds flags).
local function profileUsesFullscreenBounds()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	if isMobileLayout() then
		return true
	end
	return vp.X < PANEL_DESIGN_W or vp.Y < PANEL_DESIGN_H
end

local function profileGetBoundsConfig()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local compactViewport = vp.X < PANEL_DESIGN_W or vp.Y < PANEL_DESIGN_H
	local boundsConfig = {
		extendViewportVertically = true,
		reserveBottomHubGap = false,
		bottomMobileExtra = 0,
		topInset = 0,
		bottomInset = 0,
		mobileDraggable = false,
	}
	if compactViewport and not isMobileLayout() then
		boundsConfig.useMaximalSafeRect = true
	end
	return boundsConfig
end

local function getPanelScale()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local s = math.min(vp.X / PANEL_DESIGN_W, vp.Y / PANEL_DESIGN_H)
	return math.clamp(s, PANEL_SCALE_MIN, PANEL_SCALE_MAX)
end

local function getScaledDims()
	if profileUsesFullscreenBounds() then
		local bounds = MobileWindowLayout.GetBounds(profileGetBoundsConfig())
		local w = math.floor(bounds.width)
		local h = math.floor(bounds.height)
		local sb = math.floor(math.clamp(w * 0.34, 140, 220))
		return w, h, sb
	end
	local s = getPanelScale()
	return math.floor(PANEL_DESIGN_W * s), math.floor(PANEL_DESIGN_H * s), math.floor(SIDEBAR_DESIGN_W * s)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Screen GUI + main frame
-- ══════════════════════════════════════════════════════════════════════════════

local sg = Instance.new("ScreenGui")
sg.Name = "PlayerProfileUI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.DisplayOrder = 100
sg.Parent = playerGui

local function syncProfileScreenGuiInset()
	if profileUsesFullscreenBounds() then
		sg.IgnoreGuiInset = true
	else
		sg.IgnoreGuiInset = false
	end
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
main.Position = UDim2.new(0.5, -PANEL_DESIGN_W / 2, 0.5, -PANEL_DESIGN_H / 2)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.Visible = false
main.Active = true
main.Draggable = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
Instance.new("UIStroke", main).Color = C.divider

-- ── Header ─────────────────────────────────────────────────────────────────
local hdr = Instance.new("Frame")
hdr.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
hdr.BackgroundColor3 = C.bgLight
hdr.BorderSizePixel = 0
hdr.Parent = main
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 16)
-- Fix bottom corners (header bottom is flush)
local hdrFix = Instance.new("Frame")
hdrFix.Size = UDim2.new(1, 0, 0, 14)
hdrFix.Position = UDim2.new(0, 0, 1, -14)
hdrFix.BackgroundColor3 = C.bgLight
hdrFix.BorderSizePixel = 0
hdrFix.Parent = hdr

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 18, 0, 0)
title.BackgroundTransparency = 1
title.Text = "PLAYER PROFILE"
title.TextColor3 = C.accent
title.Font = Enum.Font.GothamBlack
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = hdr
local applyProfileHeaderTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(title, {
	Position = UDim2.new(0, 18, 0, 0),
	Size = UDim2.new(1, -50, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- Profile tab only: siege title + name (centered in Sigils–Rebirth span), level badge, XP bar in same span
local profileHdrCluster = Instance.new("Frame")
profileHdrCluster.Name = "ProfileHeaderCluster"
profileHdrCluster.BackgroundTransparency = 1
profileHdrCluster.Visible = false
profileHdrCluster.ZIndex = 1
profileHdrCluster.Size = UDim2.new(1, 0, 1, 0)
profileHdrCluster.Position = UDim2.new(0, 0, 0, 0)
profileHdrCluster.Parent = hdr

local profileNameStrip = Instance.new("Frame")
profileNameStrip.Name = "NameStrip"
profileNameStrip.BackgroundTransparency = 1
profileNameStrip.Position = UDim2.new(PROFILE_HDR_MID_X, 0, 0, 5)
profileNameStrip.Size = UDim2.new(PROFILE_HDR_MID_W, 0, 0, 22)
profileNameStrip.Parent = profileHdrCluster

local profileNameRowLayout = Instance.new("UIListLayout")
profileNameRowLayout.FillDirection = Enum.FillDirection.Horizontal
profileNameRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
profileNameRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
profileNameRowLayout.Padding = UDim.new(0, 8)
profileNameRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
profileNameRowLayout.Parent = profileNameStrip

local profileNameRich = Instance.new("TextLabel")
profileNameRich.Name = "NameRich"
profileNameRich.LayoutOrder = 1
profileNameRich.Size = UDim2.new(0, 0, 1, 0)
profileNameRich.AutomaticSize = Enum.AutomaticSize.X
profileNameRich.BackgroundTransparency = 1
profileNameRich.Font = Enum.Font.GothamBold
profileNameRich.TextSize = 15
profileNameRich.TextXAlignment = Enum.TextXAlignment.Left
profileNameRich.TextYAlignment = Enum.TextYAlignment.Center
profileNameRich.RichText = true
profileNameRich.TextTruncate = Enum.TextTruncate.AtEnd
profileNameRich.Parent = profileNameStrip
local profileNameMaxW = Instance.new("UISizeConstraint", profileNameRich)
profileNameMaxW.MaxSize = Vector2.new(340, 22)

local profileLvlBadge = Instance.new("TextLabel")
profileLvlBadge.Name = "LvlBadge"
profileLvlBadge.LayoutOrder = 2
profileLvlBadge.Size = UDim2.new(0, 0, 0, 22)
profileLvlBadge.AutomaticSize = Enum.AutomaticSize.X
profileLvlBadge.BackgroundColor3 = C.xpBar
profileLvlBadge.BackgroundTransparency = 0.15
profileLvlBadge.BorderSizePixel = 0
profileLvlBadge.Text = "LEVEL 1"
profileLvlBadge.TextColor3 = Color3.new(1, 1, 1)
profileLvlBadge.Font = Enum.Font.GothamBlack
profileLvlBadge.TextSize = 11
profileLvlBadge.ZIndex = 2
profileLvlBadge.Parent = profileNameStrip
local profileLvlBadgePad = Instance.new("UIPadding", profileLvlBadge)
profileLvlBadgePad.PaddingLeft = UDim.new(0, 8)
profileLvlBadgePad.PaddingRight = UDim.new(0, 8)
Instance.new("UICorner", profileLvlBadge).CornerRadius = UDim.new(0, 6)

local profileXpBg = Instance.new("Frame")
profileXpBg.Name = "XpBg"
profileXpBg.Position = UDim2.new(PROFILE_HDR_MID_X, 0, 0, 30)
profileXpBg.Size = UDim2.new(PROFILE_HDR_MID_W, 0, 0, 14)
profileXpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
profileXpBg.BorderSizePixel = 0
profileXpBg.ZIndex = 1
profileXpBg.Parent = profileHdrCluster
Instance.new("UICorner", profileXpBg).CornerRadius = UDim.new(0, 5)

local profileXpFill = Instance.new("Frame")
profileXpFill.Name = "XpFill"
profileXpFill.Size = UDim2.new(0.5, 0, 1, 0)
profileXpFill.BackgroundColor3 = C.xpBar
profileXpFill.BorderSizePixel = 0
profileXpFill.Parent = profileXpBg
Instance.new("UICorner", profileXpFill).CornerRadius = UDim.new(0, 5)

local profileXpLbl = Instance.new("TextLabel")
profileXpLbl.Name = "XpLbl"
profileXpLbl.Size = UDim2.new(1, 0, 1, 0)
profileXpLbl.BackgroundTransparency = 1
profileXpLbl.Text = "0 / 100 XP"
profileXpLbl.TextColor3 = Color3.new(1, 1, 1)
profileXpLbl.Font = Enum.Font.GothamBold
profileXpLbl.TextSize = 10
profileXpLbl.ZIndex = 2
profileXpLbl.Parent = profileXpBg

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -38, 0, 9)
closeBtn.BackgroundColor3 = C.card
closeBtn.Text = "X"
closeBtn.TextColor3 = C.textSec
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.BorderSizePixel = 0
closeBtn.Parent = hdr
closeBtn.ZIndex = 5
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- ══════════════════════════════════════════════════════════════════════════════
-- Tab bar
-- ══════════════════════════════════════════════════════════════════════════════

local TAB_DEFS = {
	{ name = "Profile", color = C.accent },
	{ name = "Sigils",  color = C.sigilAccent },
	{ name = "Rebirth", color = C.rebirthAccent },
	{ name = "Achievements", color = C.achieveAccent },
}

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, TAB_BAR_HEIGHT)
tabBar.Position = UDim2.new(0, 0, 0, HEADER_HEIGHT)
tabBar.BackgroundColor3 = C.bgLight
tabBar.BorderSizePixel = 0
tabBar.Parent = main

-- Divider at bottom of tab bar
local tabDivider = Instance.new("Frame")
tabDivider.Size = UDim2.new(1, 0, 0, 1)
tabDivider.Position = UDim2.new(0, 0, 1, -1)
tabDivider.BackgroundColor3 = C.divider
tabDivider.BorderSizePixel = 0
tabDivider.Parent = tabBar

local tabButtons = {}   -- { Profile = { btn, underline, label }, ... }
local tabContents = {}  -- { Profile = Frame, Sigils = Frame, Rebirth = Frame }
local activeTab = "Profile"
isVis = false

local tabWidth = 1 / #TAB_DEFS

for i, def in ipairs(TAB_DEFS) do
	local btn = Instance.new("TextButton")
	btn.Name = "Tab_" .. def.name
	btn.Size = UDim2.new(tabWidth, 0, 1, -3)
	btn.Position = UDim2.new(tabWidth * (i - 1), 0, 0, 0)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = def.name
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = C.tabInactive
	btn.AutoButtonColor = false
	btn.Parent = tabBar

	-- Active underline (gold bar at bottom of tab)
	local underline = Instance.new("Frame")
	underline.Name = "Underline"
	underline.Size = UDim2.new(0.6, 0, 0, 3)
	underline.Position = UDim2.new(0.2, 0, 1, -3)
	underline.BackgroundColor3 = def.color
	underline.BorderSizePixel = 0
	underline.Visible = false
	underline.Parent = btn
	Instance.new("UICorner", underline).CornerRadius = UDim.new(0, 2)

	tabButtons[def.name] = { btn = btn, underline = underline, color = def.color }
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Tab content area (below tab bar, fills rest of main frame)
-- ══════════════════════════════════════════════════════════════════════════════

local CONTENT_TOP = HEADER_HEIGHT + TAB_BAR_HEIGHT + 2

-- ── Profile tab content ────────────────────────────────────────────────────
local profileTab = Instance.new("Frame")
profileTab.Name = "ProfileTab"
profileTab.Size = UDim2.new(1, -28, 1, -(CONTENT_TOP + 14))
profileTab.Position = UDim2.new(0, 14, 0, CONTENT_TOP + 4)
profileTab.BackgroundTransparency = 1
profileTab.Visible = true
profileTab.Parent = main

local profileBody = Instance.new("UIListLayout")
profileBody.FillDirection = Enum.FillDirection.Horizontal
profileBody.HorizontalAlignment = Enum.HorizontalAlignment.Left
profileBody.VerticalAlignment = Enum.VerticalAlignment.Top
profileBody.Padding = UDim.new(0, 12)
profileBody.Parent = profileTab

-- Left column (scrollable stats)
local leftCol = Instance.new("ScrollingFrame")
leftCol.Name = "LeftCol"
leftCol.Size = UDim2.new(1, -SIDEBAR_DESIGN_W - 40, 1, -8)
leftCol.BackgroundTransparency = 1
leftCol.BorderSizePixel = 0
leftCol.ScrollBarThickness = 4
leftCol.ScrollBarImageColor3 = C.divider
leftCol.ScrollingDirection = Enum.ScrollingDirection.Y
leftCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
leftCol.LayoutOrder = 1
leftCol.Parent = profileTab

local leftLayout = Instance.new("UIListLayout")
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Padding = UDim.new(0, 8)
leftLayout.Parent = leftCol

-- Right sidebar (base floors on desktop; details on mobile)
local rightSidebar = Instance.new("Frame")
rightSidebar.Name = "RightSidebar"
rightSidebar.Size = UDim2.new(0, SIDEBAR_DESIGN_W, 1, -8)
rightSidebar.BackgroundColor3 = C.bgLight
rightSidebar.BorderSizePixel = 0
rightSidebar.LayoutOrder = 2
rightSidebar.Parent = profileTab
Instance.new("UICorner", rightSidebar).CornerRadius = UDim.new(0, 10)

local sidebarTitle = Instance.new("TextLabel")
sidebarTitle.Size = UDim2.new(1, -16, 0, 28)
sidebarTitle.Position = UDim2.new(0, 10, 0, 6)
sidebarTitle.BackgroundTransparency = 1
sidebarTitle.Text = "🏛️ BASE FLOORS"
sidebarTitle.TextColor3 = C.accent
sidebarTitle.Font = Enum.Font.GothamBold
sidebarTitle.TextSize = 12
sidebarTitle.TextXAlignment = Enum.TextXAlignment.Left
sidebarTitle.Parent = rightSidebar

local sidebarContent = Instance.new("Frame")
sidebarContent.Size = UDim2.new(1, -20, 1, -44)
sidebarContent.Position = UDim2.new(0, 10, 0, 36)
sidebarContent.BackgroundTransparency = 1
sidebarContent.Parent = rightSidebar

local sidebarList = Instance.new("UIListLayout")
sidebarList.SortOrder = Enum.SortOrder.LayoutOrder
sidebarList.Padding = UDim.new(0, 6)
sidebarList.Parent = sidebarContent

tabContents.Profile = profileTab

-- ── Sigils tab content ─────────────────────────────────────────────────────
local sigilsTab = Instance.new("ScrollingFrame")
sigilsTab.Name = "SigilsTab"
sigilsTab.Size = UDim2.new(1, -28, 1, -(CONTENT_TOP + 14))
sigilsTab.Position = UDim2.new(0, 14, 0, CONTENT_TOP + 4)
sigilsTab.BackgroundTransparency = 1
sigilsTab.BorderSizePixel = 0
sigilsTab.ScrollBarThickness = 4
sigilsTab.ScrollBarImageColor3 = C.divider
sigilsTab.ScrollingDirection = Enum.ScrollingDirection.Y
-- Manual CanvasSize after layout: AutomaticCanvasSize + Y-scale children often yields 0-width canvas → invisible rows.
sigilsTab.AutomaticCanvasSize = Enum.AutomaticSize.None
sigilsTab.CanvasSize = UDim2.new(0, 400, 0, 800)
sigilsTab.ClipsDescendants = true
sigilsTab.Visible = false
sigilsTab.Parent = main

local sigilsLayout = Instance.new("UIListLayout")
sigilsLayout.SortOrder = Enum.SortOrder.LayoutOrder
sigilsLayout.Padding = UDim.new(0, 12)
sigilsLayout.Parent = sigilsTab

local sigilsPadding = Instance.new("UIPadding")
sigilsPadding.PaddingLeft = UDim.new(0, 2)
sigilsPadding.PaddingRight = UDim.new(0, 2)
sigilsPadding.Parent = sigilsTab

tabContents.Sigils = sigilsTab

-- ── Achievements tab content ────────────────────────────────────────────────
local achievementsTab = Instance.new("ScrollingFrame")
achievementsTab.Name = "AchievementsTab"
achievementsTab.Size = UDim2.new(1, -28, 1, -(CONTENT_TOP + 14))
achievementsTab.Position = UDim2.new(0, 14, 0, CONTENT_TOP + 4)
achievementsTab.BackgroundTransparency = 1
achievementsTab.BorderSizePixel = 0
achievementsTab.ScrollBarThickness = 4
achievementsTab.ScrollBarImageColor3 = C.divider
achievementsTab.ScrollingDirection = Enum.ScrollingDirection.Y
achievementsTab.AutomaticCanvasSize = Enum.AutomaticSize.Y
achievementsTab.CanvasSize = UDim2.new(0, 0, 0, 0)
achievementsTab.Visible = false
achievementsTab.Parent = main

local achievementsPadding = Instance.new("UIPadding")
achievementsPadding.PaddingTop = UDim.new(0, 2)
achievementsPadding.PaddingBottom = UDim.new(0, 6)
achievementsPadding.PaddingLeft = UDim.new(0, 2)
achievementsPadding.PaddingRight = UDim.new(0, 2)
achievementsPadding.Parent = achievementsTab

local achievementsLayout = Instance.new("UIListLayout")
achievementsLayout.SortOrder = Enum.SortOrder.LayoutOrder
achievementsLayout.Padding = UDim.new(0, 12)
achievementsLayout.Parent = achievementsTab

tabContents.Achievements = achievementsTab

-- ── Rebirth tab content ────────────────────────────────────────────────────
local rebirthTab = Instance.new("Frame")
rebirthTab.Name = "RebirthTab"
rebirthTab.Size = UDim2.new(1, -28, 1, -(CONTENT_TOP + 14))
rebirthTab.Position = UDim2.new(0, 14, 0, CONTENT_TOP + 4)
rebirthTab.BackgroundTransparency = 1
rebirthTab.Visible = false
rebirthTab.Parent = main

-- Scroll area inside rebirth tab (leaves room for rebirth button at bottom)
local rebirthScroll = Instance.new("ScrollingFrame")
rebirthScroll.Name = "RebirthScroll"
rebirthScroll.Size = UDim2.new(1, 0, 1, 0)
rebirthScroll.BackgroundTransparency = 1
rebirthScroll.BorderSizePixel = 0
rebirthScroll.ScrollBarThickness = 4
rebirthScroll.ScrollBarImageColor3 = C.divider
rebirthScroll.ScrollingDirection = Enum.ScrollingDirection.Y
rebirthScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
rebirthScroll.CanvasSize = UDim2.new(1, 0, 1, 0)
rebirthScroll.ScrollingEnabled = false
rebirthScroll.Parent = rebirthTab

local rebirthLayout = Instance.new("UIListLayout")
rebirthLayout.SortOrder = Enum.SortOrder.LayoutOrder
rebirthLayout.Padding = UDim.new(0, 0)
rebirthLayout.Parent = rebirthScroll

-- Bottom rebirth button
local rebirthBtn = Instance.new("TextButton")
rebirthBtn.Name = "RebirthButton"
rebirthBtn.Size = UDim2.new(1, 0, 0, 40)
rebirthBtn.Position = UDim2.new(0, 0, 1, -48)
rebirthBtn.BackgroundColor3 = C.rebirthAccent
rebirthBtn.Text = "REBIRTH"
rebirthBtn.TextColor3 = Color3.new(0.2, 0.15, 0.1)
rebirthBtn.Font = Enum.Font.GothamBlack
rebirthBtn.TextSize = 14
rebirthBtn.BorderSizePixel = 0
rebirthBtn.Parent = rebirthTab
rebirthBtn.Visible = false
Instance.new("UICorner", rebirthBtn).CornerRadius = UDim.new(0, 10)

-- Confirmation overlay (covers entire main frame)
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.Visible = false
overlay.ZIndex = 10
overlay.Parent = main

local confirmBox = Instance.new("Frame")
confirmBox.Size = UDim2.new(0, 320, 0, 200)
confirmBox.Position = UDim2.new(0.5, -160, 0.5, -100)
confirmBox.BackgroundColor3 = C.card
confirmBox.BorderSizePixel = 0
confirmBox.ZIndex = 11
confirmBox.Parent = overlay
Instance.new("UICorner", confirmBox).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", confirmBox).Color = C.red

local confirmTitle = Instance.new("TextLabel")
confirmTitle.Size = UDim2.new(1, -24, 0, 32)
confirmTitle.Position = UDim2.new(0, 12, 0, 8)
confirmTitle.BackgroundTransparency = 1
confirmTitle.Text = "FINAL CONFIRMATION"
confirmTitle.TextColor3 = C.red
confirmTitle.Font = Enum.Font.GothamBlack
confirmTitle.TextSize = 14
confirmTitle.TextXAlignment = Enum.TextXAlignment.Left
confirmTitle.ZIndex = 12
confirmTitle.Parent = confirmBox

local confirmBody = Instance.new("TextLabel")
confirmBody.Size = UDim2.new(1, -24, 0, 70)
confirmBody.Position = UDim2.new(0, 12, 0, 42)
confirmBody.BackgroundTransparency = 1
confirmBody.Text = "You will lose ALL creatures except your equipped favorite. Base and Battle Team will be cleared. This cannot be undone."
confirmBody.TextColor3 = C.text
confirmBody.Font = Enum.Font.GothamMedium
confirmBody.TextSize = 11
confirmBody.TextWrapped = true
confirmBody.TextXAlignment = Enum.TextXAlignment.Left
confirmBody.TextYAlignment = Enum.TextYAlignment.Top
confirmBody.ZIndex = 12
confirmBody.Parent = confirmBox

local confirmYesBtn = Instance.new("TextButton")
confirmYesBtn.Size = UDim2.new(0, 120, 0, 36)
confirmYesBtn.Position = UDim2.new(0.5, -130, 1, -52)
confirmYesBtn.BackgroundColor3 = C.green
confirmYesBtn.Text = "YES, REBIRTH"
confirmYesBtn.TextColor3 = Color3.new(1, 1, 1)
confirmYesBtn.Font = Enum.Font.GothamBold
confirmYesBtn.TextSize = 12
confirmYesBtn.BorderSizePixel = 0
confirmYesBtn.ZIndex = 12
confirmYesBtn.Parent = confirmBox
Instance.new("UICorner", confirmYesBtn).CornerRadius = UDim.new(0, 8)

local confirmNoBtn = Instance.new("TextButton")
confirmNoBtn.Size = UDim2.new(0, 120, 0, 36)
confirmNoBtn.Position = UDim2.new(0.5, 10, 1, -52)
confirmNoBtn.BackgroundColor3 = C.divider
confirmNoBtn.Text = "CANCEL"
confirmNoBtn.TextColor3 = C.textSec
confirmNoBtn.Font = Enum.Font.GothamBold
confirmNoBtn.TextSize = 12
confirmNoBtn.BorderSizePixel = 0
confirmNoBtn.ZIndex = 12
confirmNoBtn.Parent = confirmBox
Instance.new("UICorner", confirmNoBtn).CornerRadius = UDim.new(0, 8)

tabContents.Rebirth = rebirthTab

-- ══════════════════════════════════════════════════════════════════════════════
-- Tab switching
-- ══════════════════════════════════════════════════════════════════════════════

local function switchTab(tabName)
	if not tabContents[tabName] then return end
	activeTab = tabName
	overlay.Visible = false  -- always close confirmation on tab switch

	-- Toggle content visibility
	for name, frame in pairs(tabContents) do
		frame.Visible = (name == tabName)
	end

	-- Update tab button styles
	for name, t in pairs(tabButtons) do
		local isActive = (name == tabName)
		t.btn.TextColor3 = isActive and t.color or C.tabInactive
		t.underline.Visible = isActive
	end

	-- Header: Profile uses identity row; other tabs use title label
	if tabName == "Profile" then
		title.Visible = false
		profileHdrCluster.Visible = true
	elseif tabName == "Sigils" then
		title.Visible = true
		profileHdrCluster.Visible = false
		title.Text = "COUNCIL OF HOUSES — SIGILS"
		title.TextColor3 = C.sigilAccent
	elseif tabName == "Rebirth" then
		title.Visible = true
		profileHdrCluster.Visible = false
		title.Text = "KNIGHT REBIRTH"
		title.TextColor3 = C.rebirthAccent
	elseif tabName == "Achievements" then
		title.Visible = true
		profileHdrCluster.Visible = false
		title.Text = "ACHIEVEMENTS"
		title.TextColor3 = C.achieveAccent
	end

	-- Refresh the active tab's data
	if tabName == "Profile" then
		refreshProfile()
	elseif tabName == "Sigils" then
		refreshSigils()
	elseif tabName == "Rebirth" then
		refreshRebirth()
	elseif tabName == "Achievements" then
		refreshAchievements()
	end
end

-- Connect tab button clicks
for _, def in ipairs(TAB_DEFS) do
	tabButtons[def.name].btn.MouseButton1Click:Connect(function()
		switchTab(def.name)
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Profile tab helpers
-- ══════════════════════════════════════════════════════════════════════════════

local function mkSection(parent, text, order)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 22)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = C.accent
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = order
	lbl.Parent = parent
	return lbl
end

local function mkStatRow(parent, label, value, color, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundColor3 = C.card
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.6, 0, 1, 0)
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = C.textSec
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local val = Instance.new("TextLabel")
	val.Name = "StatValue"
	val.Size = UDim2.new(0.4, -12, 1, 0)
	val.Position = UDim2.new(0.6, 0, 0, 0)
	val.BackgroundTransparency = 1
	val.Text = tostring(value)
	val.TextColor3 = color or C.text
	val.Font = Enum.Font.GothamBold
	val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = row
	return row, val
end

-- 2×2 stat pills — same layout/visual language as Battle slot inspector (InventoryUIManager buildInspector mkStatPill).
local function mkPilotStatPill(parent, pos, label, iconColor, valueText)
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(0.5, -12, 0, 26)
	pill.Position = pos
	pill.BackgroundColor3 = Color3.fromRGB(22, 24, 35)
	pill.BorderSizePixel = 0
	pill.Parent = parent
	Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 10)
	local pst = Instance.new("UIStroke")
	pst.Color = C.divider
	pst.Transparency = 0.55
	pst.Parent = pill

	local icon = Instance.new("Frame")
	icon.Size = UDim2.new(0, 18, 0, 18)
	icon.Position = UDim2.new(0, 8, 0.5, -9)
	icon.BackgroundColor3 = iconColor
	icon.BorderSizePixel = 0
	icon.Parent = pill
	Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 48, 1, 0)
	lbl.Position = UDim2.new(0, 30, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = C.textSec
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = pill

	local val = Instance.new("TextLabel")
	val.Size = UDim2.new(1, -10, 1, 0)
	val.Position = UDim2.new(0, 0, 0, 0)
	val.BackgroundTransparency = 1
	val.Text = valueText or "-"
	val.TextColor3 = C.text
	val.Font = Enum.Font.GothamBold
	val.TextSize = 11
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.TextTruncate = Enum.TextTruncate.AtEnd
	val.Parent = pill
	return pill
end

-- Live economy row refs (avoid full profile rebuild on every coin tick)
local profileCoinsValueLbl = nil
local profileGemsValueLbl = nil

local function clearProfileEconomyRefs()
	profileCoinsValueLbl = nil
	profileGemsValueLbl = nil
end

local function updateProfileEconomyDisplay(coins, gems)
	if profileCoinsValueLbl and coins ~= nil then
		profileCoinsValueLbl.Text = formatAbbrev(coins)
	end
	if profileGemsValueLbl and gems ~= nil then
		profileGemsValueLbl.Text = formatAbbrev(gems)
	end
end

local function mkSectionFrame(parent, layoutOrder)
	local wrap = Instance.new("Frame")
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.LayoutOrder = layoutOrder
	wrap.Parent = parent
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = wrap
	return wrap
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Profile tab refresh
-- ══════════════════════════════════════════════════════════════════════════════

local function applyProfileSidebarLayout()
	if activeTab ~= "Profile" or not profileTab.Visible then
		return
	end
	local mobile = isMobileLayout()
	rightSidebar.Visible = not mobile
	sidebarTitle.Visible = rightSidebar.Visible
	local w, h, sbWidth = getScaledDims()
	if profileUsesFullscreenBounds() then
		if mobile then
			leftCol.Size = UDim2.new(1, -28, 1, -8)
		else
			leftCol.Size = UDim2.new(1, -sbWidth - 10, 1, -8)
			rightSidebar.Size = UDim2.new(0, sbWidth, 1, -8)
		end
	else
		if mobile then
			leftCol.Size = UDim2.new(1, -28, 1, -8)
		else
			leftCol.Size = UDim2.new(1, -sbWidth - 40, 1, -8)
			rightSidebar.Size = UDim2.new(0, sbWidth, 1, -8)
		end
	end
end

local function updateProfileIdentityHeader(data)
	if not data then
		return
	end
	local lvl = data.playerLevel or 1
	local xp = data.playerXP or 0
	local xpNeeded = data.xpNeeded or 100
	local ownedFloors = data.ownedFloors or { 1 }
	local maxF = 1
	for _, f in ipairs(ownedFloors) do
		maxF = math.max(maxF, f)
	end
	local rank = siegeRankTitleFromMaxFloor(maxF)
	local nm = escapeRichText(player.Name)
	local accentHex = rgbToHex(C.accent)
	if rank ~= "" then
		profileNameRich.Text = ('<font color="%s">%s</font> <font color="#f0f0f5">%s</font>'):format(accentHex, escapeRichText(rank), nm)
	else
		profileNameRich.Text = '<font color="#f0f0f5">' .. nm .. "</font>"
	end
	profileLvlBadge.Text = "LEVEL " .. tostring(lvl)
	local xpRatio = xpNeeded > 0 and math.clamp(xp / xpNeeded, 0, 1) or 0
	profileXpFill.Size = UDim2.new(xpRatio, 0, 1, 0)
	profileXpLbl.Text = xp .. " / " .. xpNeeded .. " XP"
end

function refreshProfile()
	clearProfileEconomyRefs()
	-- Clear left column
	for _, ch in ipairs(leftCol:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end
	-- Clear sidebar
	for _, ch in ipairs(sidebarContent:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end
	sidebarTitle.Text = "🏛️ BASE FLOORS"

	if not getProfile then return end
	local ok, data = pcall(function() return getProfile:InvokeServer() end)
	if not ok or not data then
		mkSection(leftCol, "Loading...", 100)
		return
	end

	local lvl = data.playerLevel or 1
	updateProfileIdentityHeader(data)
	local isMobile = isMobileLayout()

	-- Economy (coin/gem value labels kept for live Updates without full rebuild)
	local economyBlock = mkSectionFrame(leftCol, 100)
	mkSection(economyBlock, "💰 ECONOMY", 10)
	do
		local _, coinsVal = mkStatRow(economyBlock, "💰 Coins", formatAbbrev(data.coins or 0), C.gold, 11)
		local _, gemsVal = mkStatRow(economyBlock, "💎 Gems", formatAbbrev(data.gems or 0), C.blue, 12)
		profileCoinsValueLbl = coinsVal
		profileGemsValueLbl = gemsVal
	end

	-- Lifetime / progression (not pilot combat — avoids mixing with ATK/DEF/HP rows)
	local statBlock = mkSectionFrame(leftCol, 200)
	mkSection(statBlock, "📊 PROGRESS", 10)
	mkStatRow(statBlock, "👾 Monsters Owned", tostring(data.monstersOwned or 0), C.text, 11)
	mkStatRow(statBlock, "🎯 Total Captured", tostring(data.totalCaptured or 0), C.green, 12)
	mkStatRow(statBlock, "⚔️ Arena Wins", tostring(data.arenaWins or 0), C.gold, 13)
	mkStatRow(statBlock, "🔥 Max Win Streak", tostring(data.arenaMaxStreak or 0), Color3.fromRGB(255, 130, 50), 14)
	mkStatRow(statBlock, "📈 Total Coins Earned", formatAbbrev(data.totalIncome or 0), C.gold, 15)

	-- Base Floors
	local ownedFloors = data.ownedFloors or { 1 }
	local function ownsFloor(n)
		for _, f in ipairs(ownedFloors) do if f == n then return true end end
		return false
	end

	-- Pilot combat — own section before base floors (scroll order); never a sibling between floor rows..
	local pc = data.pilotCombat
	if pc then
		local pct = math.floor((pc.statGainPerLevel or 0.08) * 100 + 0.5)
		local pilotCard = Instance.new("Frame")
		pilotCard.BackgroundColor3 = C.bgLight
		pilotCard.BorderSizePixel = 0
		pilotCard.Size = UDim2.new(1, 0, 0, 0)
		pilotCard.AutomaticSize = Enum.AutomaticSize.Y
		pilotCard.LayoutOrder = 250
		pilotCard.Parent = leftCol
		pilotCard.Name = "PilotCombatSection"
		Instance.new("UICorner", pilotCard).CornerRadius = UDim.new(0, 8)
		local pStroke = Instance.new("UIStroke")
		pStroke.Color = C.divider
		pStroke.Thickness = 1
		pStroke.Parent = pilotCard
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = pilotCard
		local pilotInner = Instance.new("Frame")
		pilotInner.BackgroundTransparency = 1
		pilotInner.Size = UDim2.new(1, 0, 0, 0)
		pilotInner.AutomaticSize = Enum.AutomaticSize.Y
		pilotInner.Parent = pilotCard
		local pilList = Instance.new("UIListLayout")
		pilList.SortOrder = Enum.SortOrder.LayoutOrder
		pilList.Padding = UDim.new(0, 6)
		pilList.Parent = pilotInner

		mkSection(pilotInner, "⚔️ KNIGHT COMBAT STATS", 10)
		local pilotStatsBox = Instance.new("Frame")
		pilotStatsBox.Name = "PilotStatsGrid"
		pilotStatsBox.Size = UDim2.new(1, 0, 0, 96)
		pilotStatsBox.BackgroundColor3 = C.card
		pilotStatsBox.BorderSizePixel = 0
		pilotStatsBox.LayoutOrder = 11
		pilotStatsBox.Parent = pilotInner
		Instance.new("UICorner", pilotStatsBox).CornerRadius = UDim.new(0, 12)
		local spdStr = ("%d / %d"):format(pc.walkSpeed or 0, pc.sprintSpeed or 0)
		mkPilotStatPill(pilotStatsBox, UDim2.new(0, 10, 0, 34), "ATK", Color3.fromRGB(255, 120, 120), tostring(pc.attack))
		mkPilotStatPill(pilotStatsBox, UDim2.new(0.5, 2, 0, 34), "DEF", Color3.fromRGB(120, 180, 255), tostring(pc.defense))
		mkPilotStatPill(pilotStatsBox, UDim2.new(0, 10, 0, 64), "HP", Color3.fromRGB(80, 220, 140), tostring(pc.maxHealth))
		mkPilotStatPill(pilotStatsBox, UDim2.new(0.5, 2, 0, 64), "SPD", Color3.fromRGB(255, 220, 100), spdStr)
		local pilotNote = Instance.new("TextLabel")
		pilotNote.Size = UDim2.new(1, 0, 0, 0)
		pilotNote.AutomaticSize = Enum.AutomaticSize.Y
		pilotNote.BackgroundTransparency = 1
		pilotNote.TextXAlignment = Enum.TextXAlignment.Left
		pilotNote.Font = Enum.Font.GothamMedium
		pilotNote.TextSize = 9
		pilotNote.TextColor3 = C.textSec
		pilotNote.TextWrapped = true
		pilotNote.LayoutOrder = 15
		pilotNote.Parent = pilotInner
		local multPct = math.floor(((pc.levelMult or 1) - 1) * 100 + 0.5)
		local note = ("Each player level adds +%d%% to your pilot combat stats (same rule as creature level scaling). Right now your level multiplier is +%d%% vs. level 1. Rebirth further boosts damage and max health. This growth is what keeps you viable in the Badlands when you enter without your Siegeling."):format(pct, multPct)
		if pc.inBadlands and (pc.badlandsAttack > 0 or pc.badlandsDefense > 0 or pc.badlandsHealth > 0 or pc.badlandsMove > 0) then
			note = note .. " Badlands run bonuses are included in the numbers above."
		end
		pilotNote.Text = note
	end

	-- Mobile: floors in their own section after pilot. Desktop: right sidebar only.
	local floorsParent = isMobile and mkSectionFrame(leftCol, 300) or sidebarContent
	if isMobile then
		mkSection(floorsParent, "🏛️ BASE FLOORS", 10)
	end

	local unlockHint = Instance.new("TextLabel")
	unlockHint.Size = UDim2.new(1, 0, 0, 0)
	unlockHint.AutomaticSize = Enum.AutomaticSize.Y
	unlockHint.BackgroundTransparency = 1
	unlockHint.Text = "🏗️ Each floor adds space and a siege title. Floor 2 — Siege Squire (Battles & battle team). Floor 3 — Siege Knight (teleporters, Recycler, and Combiners). Floor 4 — Siegelord (Siegelord Arena)."
	unlockHint.TextColor3 = C.textMut
	unlockHint.Font = Enum.Font.GothamMedium
	unlockHint.TextSize = 9
	unlockHint.TextWrapped = true
	unlockHint.LayoutOrder = 11
	unlockHint.Parent = floorsParent

	-- All floor tier rows live in one container so nothing can appear between them.
	local floorRowsHost = Instance.new("Frame")
	floorRowsHost.Name = "FloorRows"
	floorRowsHost.BackgroundTransparency = 1
	floorRowsHost.Size = UDim2.new(1, 0, 0, 0)
	floorRowsHost.AutomaticSize = Enum.AutomaticSize.Y
	floorRowsHost.LayoutOrder = 12
	floorRowsHost.Parent = floorsParent
	local floorRowsLayout = Instance.new("UIListLayout")
	floorRowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	floorRowsLayout.Padding = UDim.new(0, 6)
	floorRowsLayout.Parent = floorRowsHost

	-- Titles match progression; benefits explain gameplay unlocks per row below.
	local FLOOR_DISPLAY_NAMES = {
		[1] = "Floor 1 — Starter base",
		[2] = "Floor 2 — Siege Squire",
		[3] = "Floor 3 — Siege Knight",
		[4] = "Floor 4 — Siegelord",
	}
	local FLOOR_BENEFITS = {
		[1] = "Starting stronghold: ground-floor income & defense slots.",
		[2] = "You become a Siege Squire. Unlocks Battles and your battle team.",
		[3] = "You become a Siege Knight. Unlocks teleporters, the Recycler, and Combiners on Floor 3.",
		[4] = "You become a Siegelord. Unlocks the Siegelord Arena.",
	}
	-- Floor config lookup: { cost, levelReq } for purchasable floors
	local FLOOR_UI_CONFIG = {
		[2] = { cost = GameConfig.Floor2Cost or 500,    levelReq = GameConfig.Floor2LevelReq or 2,   prereq = nil },
		[3] = { cost = GameConfig.Floor3Cost or 5000,   levelReq = GameConfig.Floor3LevelReq or 10,  prereq = 2   },
		[4] = { cost = GameConfig.Floor4Cost or 25000,  levelReq = GameConfig.Floor4LevelReq or 20,  prereq = 3   },
	}

	for i, floorNum in ipairs({ 1, 2, 3, 4 }) do
		local owned = ownsFloor(floorNum)
		local floorCfg = FLOOR_UI_CONFIG[floorNum]
		local reqLvl = floorCfg and floorCfg.levelReq or 1
		local cost = floorCfg and floorCfg.cost or 0
		local meetsLevel = lvl >= reqLvl
		local meetsPrereq = (not floorCfg or not floorCfg.prereq) or ownsFloor(floorCfg.prereq)
		local canBuy = false
		if not owned and floorNum > 1 and floorCfg then
			canBuy = meetsLevel and meetsPrereq and (data.coins or 0) >= cost
		end

		local isLocked = not owned and floorNum > 1
		local benefitLine = FLOOR_BENEFITS[floorNum] or ""
		local rowHeight = isLocked and 96 or (floorNum == 1 and 56 or 62)
		local floorRow = Instance.new("Frame")
		floorRow.Size = UDim2.new(1, 0, 0, rowHeight)
		floorRow.BackgroundColor3 = C.card
		floorRow.BorderSizePixel = 0
		floorRow.LayoutOrder = i
		floorRow.Parent = floorRowsHost
		Instance.new("UICorner", floorRow).CornerRadius = UDim.new(0, 7)
		local rowStroke = Instance.new("UIStroke")
		rowStroke.Thickness = 1
		rowStroke.Parent = floorRow

		if owned or floorNum == 1 then
			if owned then
				floorRow.BackgroundColor3 = C.card:Lerp(Color3.fromRGB(45, 110, 75), 0.10)
				rowStroke.Color = C.green
				rowStroke.Transparency = 0.55
			else
				floorRow.BackgroundColor3 = C.card:Lerp(Color3.fromRGB(45, 110, 75), 0.06)
				rowStroke.Color = C.green
				rowStroke.Transparency = 0.72
			end
		elseif canBuy then
			floorRow.BackgroundColor3 = C.card:Lerp(Color3.fromRGB(170, 130, 55), 0.11)
			rowStroke.Color = C.gold
			rowStroke.Transparency = 0.42
		else
			floorRow.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
			rowStroke.Color = C.divider
			rowStroke.Transparency = 0.32
		end

		local baseTitle = FLOOR_DISPLAY_NAMES[floorNum] or ("Floor " .. floorNum)
		local titleText = baseTitle
		if owned and floorNum > 1 then
			titleText = "✓ " .. baseTitle
		elseif isLocked and not canBuy then
			titleText = "🔒 " .. baseTitle
		end

		local fName = Instance.new("TextLabel")
		fName.Size = UDim2.new(1, -12, 0, 18)
		fName.Position = UDim2.new(0, 8, 0, 4)
		fName.BackgroundTransparency = 1
		fName.Text = titleText
		fName.TextColor3 = owned and C.green or (canBuy and C.gold or C.textMut)
		fName.Font = Enum.Font.GothamBold
		fName.TextSize = 12
		fName.TextXAlignment = Enum.TextXAlignment.Left
		fName.Parent = floorRow

		local fBenefit = Instance.new("TextLabel")
		fBenefit.BackgroundTransparency = 1
		fBenefit.Font = Enum.Font.GothamMedium
		fBenefit.TextSize = 8
		fBenefit.TextXAlignment = Enum.TextXAlignment.Left
		fBenefit.TextWrapped = true
		fBenefit.TextColor3 = C.textSec
		fBenefit.Text = benefitLine
		fBenefit.Parent = floorRow

		if owned or floorNum == 1 then
			local benH = floorNum == 1 and 20 or 26
			fBenefit.Size = UDim2.new(1, -16, 0, benH)
			fBenefit.Position = UDim2.new(0, 8, 0, 22)
			local fStatus = Instance.new("TextLabel")
			fStatus.Size = UDim2.new(1, -16, 0, 12)
			fStatus.Position = UDim2.new(0, 8, 0, 22 + benH + 2)
			fStatus.BackgroundTransparency = 1
			fStatus.Font = Enum.Font.GothamBold
			fStatus.TextSize = 9
			fStatus.TextXAlignment = Enum.TextXAlignment.Left
			fStatus.Parent = floorRow
			fStatus.Text = owned and "✓ OWNED" or "🏠 STARTER"
			fStatus.TextColor3 = C.green
		else
			fBenefit.Size = UDim2.new(1, -16, 0, 22)
			fBenefit.Position = UDim2.new(0, 8, 0, 22)

			local costLbl = Instance.new("TextLabel")
			costLbl.Size = UDim2.new(1, -16, 0, 13)
			costLbl.Position = UDim2.new(0, 8, 0, 46)
			costLbl.BackgroundTransparency = 1
			costLbl.Font = Enum.Font.GothamBold
			costLbl.TextSize = 11
			costLbl.TextXAlignment = Enum.TextXAlignment.Left
			costLbl.Text = tostring(cost) .. " Coins"
			costLbl.TextColor3 = (data.coins or 0) >= cost and C.gold or C.red
			costLbl.Parent = floorRow

			local lvlLbl = Instance.new("TextLabel")
			lvlLbl.Size = UDim2.new(1, -16, 0, 11)
			lvlLbl.Position = UDim2.new(0, 8, 0, 60)
			lvlLbl.BackgroundTransparency = 1
			lvlLbl.Font = Enum.Font.GothamMedium
			lvlLbl.TextSize = 9
			lvlLbl.TextXAlignment = Enum.TextXAlignment.Left
			local prereqText = ""
			if floorCfg and floorCfg.prereq and not ownsFloor(floorCfg.prereq) then
				prereqText = " + Floor " .. floorCfg.prereq
			end
			lvlLbl.Text = "Requires Level " .. reqLvl .. prereqText
			lvlLbl.TextColor3 = meetsLevel and C.green or C.textMut
			lvlLbl.Parent = floorRow

			local buyBtn2 = Instance.new("TextButton")
			buyBtn2.Size = UDim2.new(1, -16, 0, 22)
			buyBtn2.Position = UDim2.new(0, 8, 0, 74)
			buyBtn2.BackgroundColor3 = canBuy and C.green or C.divider
			buyBtn2.Text = canBuy and ("BUY UPGRADE — " .. formatAbbrev(cost) .. " 💰") or "🔒 LOCKED"
			buyBtn2.TextColor3 = canBuy and Color3.new(1, 1, 1) or C.textMut
			buyBtn2.Font = Enum.Font.GothamBold
			buyBtn2.TextSize = 10
			buyBtn2.BorderSizePixel = 0
			buyBtn2.Active = canBuy
			buyBtn2.Parent = floorRow
			Instance.new("UICorner", buyBtn2).CornerRadius = UDim.new(0, 5)

			if canBuy then
				buyBtn2.MouseButton1Click:Connect(function()
					if buyFloor then
						local ok2, msg = buyFloor:InvokeServer(floorNum)
						if ok2 then
							Notify.Toast("Floor " .. floorNum .. " unlocked!", C.green, 3)
						else
							Notify.Toast(msg or "Failed", C.red, 2)
						end
						task.wait(0.3)
						refreshProfile()
					end
				end)
			end
		end
	end

	applyProfileSidebarLayout()
end

-- Coin/gem balance events update only the economy row text (avoid rebuilding the whole Profile tab every tick)
if CoinsUpdate then
	CoinsUpdate.OnClientEvent:Connect(function(balance)
		if isVis and activeTab == "Profile" then
			updateProfileEconomyDisplay(tonumber(balance) or 0, nil)
		end
	end)
end
if GemsUpdate then
	GemsUpdate.OnClientEvent:Connect(function(balance)
		if isVis and activeTab == "Profile" then
			updateProfileEconomyDisplay(nil, tonumber(balance) or 0)
		end
	end)
end
if IncomeReceived then
	IncomeReceived.OnClientEvent:Connect(function(_amount, newBalance)
		if isVis and activeTab == "Profile" then
			updateProfileEconomyDisplay(tonumber(newBalance) or 0, nil)
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Sigils tab — badge cards + Viewport silhouettes / colors.
-- ══════════════════════════════════════════════════════════════════════════════

local function getBossDisplayName(element)
	local bossId = CreatureData.GetBossCreatureId and CreatureData.GetBossCreatureId(element, false)
	if not bossId then return element .. " Boss" end
	local creature = CreatureData.GetById and CreatureData.GetById(bossId)
	if creature and creature.displayName then return creature.displayName end
	return element .. " Boss"
end

local function resolveBossCreatureIdForElement(element)
	if not element then return nil end
	local id = CreatureData.GetBossCreatureId(element, false)
	if id then return id end
	return CreatureData.GetBossCreatureId("Fire", false)
end

local function gymShortName(zoneId)
	local names = GameConfig.ZoneDoorGymNames
	if names and zoneId and names[zoneId] then
		return names[zoneId]
	end
	return (zoneId or "Zone") .. " Gym"
end

local function createSigilCreatureViewport(parent, creatureId)
	if not CreatureModelLoader or not creatureId then return nil end
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local ok, vf = pcall(function()
		local vfInner = Instance.new("ViewportFrame")
		vfInner.Name = "BossViewport"
		vfInner.Size = UDim2.new(1, 0, 1, 0)
		vfInner.Position = UDim2.new(0, 0, 0, 0)
		vfInner.BackgroundTransparency = 1
		vfInner.BorderSizePixel = 0
		vfInner.ZIndex = 1
		vfInner.Ambient = Color3.fromRGB(140, 140, 160)
		vfInner.LightColor = Color3.new(1, 1, 1)
		vfInner.LightDirection = Vector3.new(-0.4, -0.7, -0.5).Unit
		vfInner.Parent = parent

		local cam = Instance.new("Camera")
		cam.CameraType = Enum.CameraType.Scriptable
		cam.Parent = vfInner
		vfInner.CurrentCamera = cam

		local world = Instance.new("WorldModel")
		world.Name = "SigilWorld"
		world.Parent = vfInner

		local tempModel = Instance.new("Model")
		tempModel.Name = info.modelName or "ViewportClone"
		local body, _, integrated = CreatureModelLoader.LoadAndIntegrate(tempModel, info.modelName, info.displayName, nil, {
			targetSize = 4,
			creatureId = creatureId,
		})
		if not integrated or not body then
			vfInner:Destroy()
			tempModel:Destroy()
			return nil
		end

		for _, desc in ipairs(tempModel:GetDescendants()) do
			if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then desc:Destroy() end
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = false
			end
		end

		local cf, sz
		pcall(function()
			cf, sz = tempModel:GetBoundingBox()
		end)
		if not cf then cf = CFrame.new() end
		if not sz then sz = Vector3.new(4, 4, 4) end
		tempModel:PivotTo(CFrame.new(-cf.Position) * tempModel:GetPivot())
		tempModel.Parent = world

		local maxDim = math.max(sz.X, sz.Y, sz.Z)
		local camDist = math.max(3.5, maxDim * 1.3)
		local camAngleX = math.rad(10)
		local camAngleY = math.pi * 1.5
		local camPos = Vector3.new(
			math.cos(camAngleY) * math.cos(camAngleX) * camDist,
			math.sin(camAngleX) * camDist,
			math.sin(camAngleY) * math.cos(camAngleX) * camDist
		)
		cam.CFrame = CFrame.new(camPos, Vector3.new(0, 0, 0))

		return vfInner
	end)

	if ok and vf then
		return vf
	end
	return nil
end

local function mkCouncilBanner(parent, layoutOrder, earnedTotal)
	local wrap = Instance.new("Frame")
	wrap.Name = "CouncilBanner"
	wrap.LayoutOrder = layoutOrder
	wrap.Size = UDim2.new(1, 0, 0, 58)
	wrap.BackgroundColor3 = C.bgLight
	wrap.BorderSizePixel = 0
	wrap.Parent = parent
	Instance.new("UICorner", wrap).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.divider
	stroke.Thickness = 1
	stroke.Transparency = 0.55
	stroke.Parent = wrap

	local pad = Instance.new("UIPadding", wrap)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -140, 0, 22)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = C.text
	title.Text = "Council of Houses"
	title.Parent = wrap

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(1, -140, 0, 16)
	sub.Position = UDim2.new(0, 0, 0, 26)
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 10
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = C.textSec
	sub.Text = "Earn sigils by defeating Legendary bosses, outer Gyms, and the Badlands trial."
	sub.TextWrapped = true
	sub.Parent = wrap

	local prog = Instance.new("TextLabel")
	prog.BackgroundTransparency = 1
	prog.Size = UDim2.new(0, 200, 1, 0)
	prog.Position = UDim2.new(1, -200, 0, 0)
	prog.Font = Enum.Font.GothamBold
	prog.TextSize = 11
	prog.TextXAlignment = Enum.TextXAlignment.Right
	prog.TextYAlignment = Enum.TextYAlignment.Center
	prog.TextColor3 = C.sigilAccent
	prog.Text = ("%d / %d SIGILS EARNED"):format(earnedTotal, TOTAL_SIGIL_COUNT)
	prog.Parent = wrap
end

local function mkSigilsSectionHeader(parent, layoutOrder, title, subtitle, progressStr, showLocked)
	local wrap = Instance.new("Frame")
	wrap.LayoutOrder = layoutOrder
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.BackgroundTransparency = 1
	wrap.Parent = parent

	local vlist = Instance.new("UIListLayout")
	vlist.SortOrder = Enum.SortOrder.LayoutOrder
	vlist.Padding = UDim.new(0, 4)
	vlist.Parent = wrap

	local row = Instance.new("Frame")
	row.LayoutOrder = 1
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.Parent = wrap

	local ttl = Instance.new("TextLabel")
	ttl.BackgroundTransparency = 1
	ttl.Size = UDim2.new(1, -130, 1, 0)
	ttl.Font = Enum.Font.GothamBold
	ttl.TextSize = 13
	ttl.TextXAlignment = Enum.TextXAlignment.Left
	ttl.TextColor3 = C.text
	ttl.Text = title
	ttl.Parent = row

	if showLocked then
		local lk = Instance.new("TextLabel")
		lk.BackgroundTransparency = 1
		lk.Size = UDim2.new(0, 90, 1, 0)
		lk.Position = UDim2.new(1, -90, 0, 0)
		lk.Font = Enum.Font.GothamBold
		lk.TextSize = 11
		lk.TextXAlignment = Enum.TextXAlignment.Right
		lk.TextColor3 = C.textMut
		lk.Text = "🔒 Locked"
		lk.Parent = row
	elseif progressStr and progressStr ~= "" then
		local pr = Instance.new("TextLabel")
		pr.BackgroundTransparency = 1
		pr.Size = UDim2.new(0, 130, 1, 0)
		pr.Position = UDim2.new(1, -130, 0, 0)
		pr.Font = Enum.Font.GothamBold
		pr.TextSize = 11
		pr.TextXAlignment = Enum.TextXAlignment.Right
		pr.TextColor3 = C.sigilAccent
		pr.Text = progressStr
		pr.Parent = row
	end

	if subtitle and subtitle ~= "" then
		local sub = Instance.new("TextLabel")
		sub.LayoutOrder = 2
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(1, 0, 0, 0)
		sub.AutomaticSize = Enum.AutomaticSize.Y
		sub.Font = Enum.Font.GothamMedium
		sub.TextSize = 10
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextColor3 = C.textMut
		sub.TextWrapped = true
		sub.Text = subtitle
		sub.Parent = wrap
	end
end

local SIGIL_CELL_W = 156
local SIGIL_CELL_H = 178
local SIGIL_GRID_PAD = 10
local sigilRuntimeCellW = SIGIL_CELL_W

local function computeSigilCellWidth()
	local w = sigilsTab.AbsoluteWindowSize.X
	if w < 100 then
		w = sigilsTab.AbsoluteSize.X
	end
	w = math.max(320, w)
	local inner = w - sigilsPadding.PaddingLeft.Offset - sigilsPadding.PaddingRight.Offset
	local candidate = math.floor((inner - (SIGIL_GRID_PAD * 3)) / 4)
	sigilRuntimeCellW = math.clamp(candidate, 120, SIGIL_CELL_W)
end

--- Horizontal strip of badge cards (avoids UIGridLayout + ScrollingFrame sizing bugs).
local function mkSigilBadgeRow(parent, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "SigilBadgeRow"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, SIGIL_CELL_H + 16)
	row.LayoutOrder = layoutOrder
	row.Parent = parent
	local hl = Instance.new("UIListLayout")
	hl.Name = "RowLayout"
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	hl.VerticalAlignment = Enum.VerticalAlignment.Top
	hl.Padding = UDim.new(0, SIGIL_GRID_PAD)
	hl.SortOrder = Enum.SortOrder.LayoutOrder
	hl.Wraps = false
	hl.Parent = row
	return row
end

local function syncSigilsCanvasSize()
	if not sigilsTab or not sigilsLayout then return end
	local wx = sigilsTab.AbsoluteWindowSize.X
	if wx < 50 then
		wx = sigilsTab.AbsoluteSize.X
	end
	wx = math.max(wx, 320)
	local padExtra = 0
	local pad = sigilsTab:FindFirstChildOfClass("UIPadding")
	if pad then
		padExtra = pad.PaddingTop.Offset + pad.PaddingBottom.Offset
	end
	local cy = sigilsLayout.AbsoluteContentSize.Y + padExtra + 24
	sigilsTab.CanvasSize = UDim2.new(0, wx, 0, math.max(cy, 120))
end

--[[
	opts: {
		layoutOrder, title, subtitle, emojiTL,
		creatureId,
		requirementText,
		tierLocked: bool — section gated (previous tier incomplete),
		sigilEarned: bool,
		accentEarned: Color3? — stroke glow when earned,
		wideCard: bool — full-width Siege Lord layout,
	}
]]
local function buildSigilBadgeCard(opts)
	local tierLocked = opts.tierLocked == true
	local earned = opts.sigilEarned == true and not tierLocked
	local useViewport = opts.useViewport ~= false

	local card = Instance.new("Frame")
	card.Name = "SigilBadge"
	card.BackgroundColor3 = C.card
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.LayoutOrder = opts.layoutOrder or 0
	if opts.wideCard then
		card.Size = UDim2.new(1, 0, 0, 138)
	else
		card.Size = UDim2.new(0, sigilRuntimeCellW, 0, SIGIL_CELL_H)
	end
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = earned and 2.6 or 1.2
	if earned then
		stroke.Color = opts.accentEarned or C.sigilAccent
		stroke.Transparency = 0.05
	elseif tierLocked then
		stroke.Color = C.divider
		stroke.Transparency = 0.45
	else
		stroke.Color = C.divider
		stroke.Transparency = 0.35
	end
	stroke.Parent = card

	-- Defer 3D load so frames + text appear even if CreatureModelLoader errors or yields.
	local cidDefer = opts.creatureId
	local earnedDefer = earned
	local tierLockedDefer = tierLocked
	if useViewport and cidDefer then
		task.defer(function()
			if not card.Parent then return end
			local vf = createSigilCreatureViewport(card, cidDefer)
			if not vf then return end
			if earnedDefer then
				vf.ImageColor3 = Color3.new(1, 1, 1)
				vf.ImageTransparency = 0
				local sc = Instance.new("UIScale")
				sc.Scale = 1.045
				sc.Parent = vf
			else
				vf.ImageColor3 = Color3.new(0, 0, 0)
				vf.ImageTransparency = tierLockedDefer and 0.35 or 0.08
			end
		end)
	end

	if not useViewport then
		local medallion = Instance.new("Frame")
		medallion.Name = "BadgeMedallion"
		medallion.Size = UDim2.new(0, 82, 0, 82)
		medallion.AnchorPoint = Vector2.new(0.5, 0.5)
		medallion.Position = UDim2.new(0.5, 0, 0.36, 0)
		medallion.BackgroundColor3 = tierLocked and Color3.fromRGB(35, 38, 48) or Color3.fromRGB(28, 34, 56)
		medallion.BorderSizePixel = 0
		medallion.ZIndex = 2
		medallion.Parent = card
		Instance.new("UICorner", medallion).CornerRadius = UDim.new(1, 0)
		local medStroke = Instance.new("UIStroke")
		medStroke.Thickness = 2
		medStroke.Color = earned and (opts.accentEarned or C.sigilAccent) or C.divider
		medStroke.Transparency = earned and 0.12 or 0.42
		medStroke.Parent = medallion

		local glyph = Instance.new("TextLabel")
		glyph.Size = UDim2.new(1, 0, 1, 0)
		glyph.BackgroundTransparency = 1
		glyph.Font = Enum.Font.GothamBlack
		glyph.TextSize = 28
		glyph.Text = opts.badgeGlyph or "◆"
		glyph.TextColor3 = earned and (opts.accentEarned or C.sigilAccent) or C.textSec
		glyph.ZIndex = 3
		glyph.Parent = medallion
	end

	local shade = Instance.new("Frame")
	shade.Name = "BottomShade"
	shade.Size = UDim2.new(1, 0, 1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.ZIndex = 3
	shade.Parent = card
	local shadeGrad = Instance.new("UIGradient")
	shadeGrad.Rotation = 90
	shadeGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.55, 0.82),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	shadeGrad.Parent = shade

	if tierLocked then
		local lockVeil = Instance.new("Frame")
		lockVeil.Name = "LockVeil"
		lockVeil.Size = UDim2.new(1, 0, 1, 0)
		lockVeil.BackgroundColor3 = Color3.new(0, 0, 0)
		lockVeil.BackgroundTransparency = 0.42
		lockVeil.BorderSizePixel = 0
		lockVeil.ZIndex = 7
		lockVeil.Parent = card
	end

	local emojiTL = Instance.new("TextLabel")
	emojiTL.Size = UDim2.new(0, 36, 0, 28)
	emojiTL.Position = UDim2.new(0, 8, 0, 6)
	emojiTL.BackgroundTransparency = 1
	emojiTL.Font = Enum.Font.GothamBold
	emojiTL.TextSize = 20
	emojiTL.Text = opts.emojiTL or ""
	emojiTL.TextXAlignment = Enum.TextXAlignment.Left
	emojiTL.ZIndex = 8
	emojiTL.Parent = card

	local topRight = Instance.new("TextLabel")
	topRight.Size = UDim2.new(0, 36, 0, 28)
	topRight.Position = UDim2.new(1, -40, 0, 6)
	topRight.BackgroundTransparency = 1
	topRight.Font = Enum.Font.GothamBold
	topRight.TextSize = 18
	topRight.TextXAlignment = Enum.TextXAlignment.Right
	topRight.ZIndex = 8
	topRight.Parent = card
	if earned then
		topRight.Text = "✓"
		topRight.TextColor3 = C.green
	elseif tierLocked then
		topRight.Text = "🔒"
		topRight.TextColor3 = C.textMut
	else
		topRight.Text = ""
	end

	local title = Instance.new("TextLabel")
	title.Size = opts.wideCard and UDim2.new(0.62, -16, 0, 24) or UDim2.new(1, -16, 0, 18)
	title.Position = opts.wideCard and UDim2.new(0, 12, 0, 20) or UDim2.new(0, 8, 0, 86)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = opts.wideCard and 15 or 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = earned and (opts.accentEarned or C.sigilAccent) or C.text
	title.Text = opts.title or ""
	title.ZIndex = 9
	title.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Size = opts.wideCard and UDim2.new(0.62, -16, 0, 18) or UDim2.new(1, -16, 0, 16)
	sub.Position = opts.wideCard and UDim2.new(0, 12, 0, 46) or UDim2.new(0, 8, 0, 106)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 11
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = C.textSec
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Text = opts.subtitle or ""
	sub.ZIndex = 9
	sub.Parent = card

	local foot = Instance.new("Frame")
	foot.Name = "Footer"
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.new(0, 8, 1, -8)
	foot.Size = opts.wideCard and UDim2.new(0.58, -16, 0, 26) or UDim2.new(1, -16, 0, 26)
	foot.BackgroundColor3 = earned and Color3.fromRGB(22, 75, 42) or Color3.fromRGB(18, 20, 28)
	foot.BackgroundTransparency = tierLocked and 0.35 or 0.12
	foot.BorderSizePixel = 0
	foot.ZIndex = 10
	foot.Parent = card
	Instance.new("UICorner", foot).CornerRadius = UDim.new(0, 8)

	local footLbl = Instance.new("TextLabel")
	footLbl.Size = UDim2.new(1, -12, 1, 0)
	footLbl.Position = UDim2.new(0, 6, 0, 0)
	footLbl.BackgroundTransparency = 1
	footLbl.Font = Enum.Font.GothamBold
	footLbl.TextSize = 10
	footLbl.TextWrapped = true
	footLbl.TextXAlignment = Enum.TextXAlignment.Center
	footLbl.TextYAlignment = Enum.TextYAlignment.Center
	footLbl.ZIndex = 11
	footLbl.Parent = foot

	if tierLocked then
		footLbl.Text = "LOCKED"
		footLbl.TextColor3 = C.textMut
	elseif earned then
		footLbl.Text = "EARNED"
		footLbl.TextColor3 = Color3.new(1, 1, 1)
	else
		footLbl.Text = opts.requirementText or ""
		footLbl.TextColor3 = C.textSec
	end

	return card
end

local function refreshSigilsCore()
	computeSigilCellWidth()
	for _, child in ipairs(sigilsTab:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end

	local sigils = {}
	if getInventory and getInventory:IsA("RemoteFunction") then
		local ok, data = pcall(function() return getInventory:InvokeServer() end)
		if ok and data then sigils = data.sigils or {} end
	end

	local function hasSigil(zoneId)
		return sigils[zoneId] == true or sigils[zoneId] == "true"
	end

	local squireElList = getSquireElementList()
	local earnedSquire = 0
	for _, el in ipairs(squireElList) do
		if hasSigil(el) then
			earnedSquire = earnedSquire + 1
		end
	end

	local earnedKnight = 0
	for _, zid in ipairs(SIEGE_ZONE_IDS) do
		if hasSigil(zid) then
			earnedKnight = earnedKnight + 1
		end
	end

	local lordEarned = hasSigil(SIEGE_LORD_ZONE_ID)
	local totalEarned = earnedSquire + earnedKnight + (lordEarned and 1 or 0)

	local nSquire = #squireElList
	local nKnight = #SIEGE_ZONE_IDS
	local squireComplete = earnedSquire >= nSquire
	local knightComplete = earnedKnight >= nKnight

	local knightTierLocked = not squireComplete
	local lordTierLocked = not knightComplete

	local order = 0

	order = order + 1
	mkCouncilBanner(sigilsTab, order, totalEarned)

	order = order + 1
	mkSigilsSectionHeader(
		sigilsTab,
		order,
		"⚔️ Siege Squire Sigils",
		"Defeat each inner-zone Legendary elemental boss.",
		("%d / %d Earned"):format(earnedSquire, nSquire),
		false
	)

	order = order + 1
	local squireRow = mkSigilBadgeRow(sigilsTab, order)
	local sqCell = 0
	for _, element in ipairs(squireElList) do
		sqCell = sqCell + 1
		local defeated = hasSigil(element)
		local cid = resolveBossCreatureIdForElement(element)
		buildSigilBadgeCard({
			layoutOrder = sqCell,
			title = element .. " Sigil",
			subtitle = getBossDisplayName(element),
			emojiTL = SIGIL_ELEMENT_EMOJI[element] or "✦",
			creatureId = cid,
			requirementText = "REQUIREMENT: Capture Legendary",
			tierLocked = false,
			sigilEarned = defeated,
			accentEarned = C.sigilAccent,
			wideCard = false,
		}).Parent = squireRow
	end

	order = order + 1
	mkSigilsSectionHeader(
		sigilsTab,
		order,
		"🛡️ Siege Knight Sigils",
		"Win each outer-zone Gym to earn Knight sigils and passes.",
		("%d / %d Earned"):format(earnedKnight, nKnight),
		knightTierLocked
	)

	order = order + 1
	local knightRow = mkSigilBadgeRow(sigilsTab, order)
	local knCell = 0
	for i, label in ipairs(SIEGE_LABELS) do
		knCell = knCell + 1
		local zoneId = SIEGE_ZONE_IDS[i]
		local repEl = KNIGHT_ZONE_BOSS_ELEMENT[zoneId]
		local cid = resolveBossCreatureIdForElement(repEl)
		local earned = hasSigil(zoneId)
		buildSigilBadgeCard({
			layoutOrder = knCell,
			title = label .. " Sigil",
			subtitle = gymShortName(zoneId),
			emojiTL = KNIGHT_ZONE_EMOJI[zoneId] or "◇",
			creatureId = nil,
			useViewport = false,
			badgeGlyph = KNIGHT_ZONE_EMOJI[zoneId] or "◆",
			requirementText = ("WIN: %s"):format(gymShortName(zoneId)),
			tierLocked = knightTierLocked,
			sigilEarned = earned,
			accentEarned = Color3.fromRGB(130, 200, 255),
			wideCard = false,
		}).Parent = knightRow
	end

	order = order + 1
	mkSigilsSectionHeader(
		sigilsTab,
		order,
		"👑 Siege Lord Sigil",
		SIEGE_LORD_SUB .. ".",
		lordEarned and "Earned" or "",
		lordTierLocked
	)

	order = order + 1
	local lordCid = resolveBossCreatureIdForElement("Shadow")
	buildSigilBadgeCard({
		layoutOrder = order,
		title = "Badlands Extraction",
		subtitle = "Successfully extract a Siegeling from the Badlands.",
		emojiTL = "☠",
		creatureId = lordCid,
		requirementText = lordTierLocked and "REQUIRES ALL KNIGHT SIGILS" or "Complete a successful extraction run",
		tierLocked = lordTierLocked,
		sigilEarned = lordEarned,
		accentEarned = C.gold,
		wideCard = true,
	}).Parent = sigilsTab

	order = order + 1
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 0)
	hint.AutomaticSize = Enum.AutomaticSize.Y
	hint.BackgroundTransparency = 1
	hint.Text = GameConfig.ZoneDoorModalSigilsHint
		or "Inner zones: defeat Legendary Siegelings for Siege Squire sigils. Exterior: win each zone Gym for Siege Knight sigils and passes. Siege Lord: complete a successful Badlands extraction."
	hint.TextColor3 = C.textMut
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 10
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.LayoutOrder = order
	hint.Parent = sigilsTab

	task.defer(function()
		sigilsTab.CanvasPosition = Vector2.zero
		syncSigilsCanvasSize()
	end)
	task.delay(0.05, syncSigilsCanvasSize)
end

function refreshSigils()
	local ok, err = pcall(refreshSigilsCore)
	if not ok then
		warn("[PlayerProfileClient] refreshSigils failed:", err)
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Achievements tab (UI + dynamic progress)
-- ══════════════════════════════════════════════════════════════════════════════

local achievementCacheById = {} -- id -> entry (client-facing table)
local achievementCardById = {}  -- id -> card frame

local function mkBadgeIcon(parent, iconId, tint, locked)
	if iconId and iconId ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "BadgeIcon"
		img.BackgroundTransparency = 1
		img.Size = UDim2.new(0, 56, 0, 56)
		img.Position = UDim2.new(0, 12, 0.5, -28)
		img.Image = iconId
		img.ImageColor3 = tint or Color3.new(1, 1, 1)
		img.ImageTransparency = locked and 0.55 or 0
		img.ZIndex = 10
		img.Parent = parent
		return img
	end

	local ring = Instance.new("Frame")
	ring.Name = "BadgeRing"
	ring.Size = UDim2.new(0, 56, 0, 56)
	ring.Position = UDim2.new(0, 12, 0.5, -28)
	ring.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	ring.BackgroundTransparency = locked and 0.45 or 0.2
	ring.BorderSizePixel = 0
	-- Keep the badge/letter circle above the lock overlay and text.
	ring.ZIndex = 10
	ring.Parent = parent
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke", ring)
	stroke.Name = "BadgeStroke"
	stroke.Color = tint or C.achieveAccent
	stroke.Thickness = 2
	stroke.Transparency = locked and 0.5 or 0.15

	local star = Instance.new("TextLabel")
	star.Name = "BadgeStar"
	star.Size = UDim2.new(1, 0, 1, 0)
	star.BackgroundTransparency = 1
	star.Text = "★"
	star.TextColor3 = tint or C.achieveAccent
	star.TextTransparency = locked and 0.55 or 0
	star.ZIndex = 11
	star.Font = Enum.Font.GothamBlack
	star.TextSize = 22
	star.Parent = ring
	return ring
end

--- Gold + diamonds + player XP granted on first unlock (from server `rewardData` or config).
local function getAchievementRewardLine(entry)
	local rd = type(entry) == "table" and entry.rewardData
	if type(rd) ~= "table" then
		return ""
	end
	local gems = math.floor(tonumber(rd.gems) or 0)
	local xp = math.floor(tonumber(rd.xp) or 0)
	local coins = math.floor(tonumber(rd.coins) or 0)
	if gems <= 0 and xp <= 0 and coins <= 0 then
		return ""
	end
	local parts = {}
	-- Show gold first so it matches the order the player sees in the HUD (gold left of diamonds).
	if coins > 0 then
		table.insert(parts, "+" .. tostring(coins) .. " gold")
	end
	if gems > 0 then
		table.insert(parts, "+" .. tostring(gems) .. " diamonds")
	end
	if xp > 0 then
		table.insert(parts, "+" .. tostring(xp) .. " XP")
	end
	return table.concat(parts, " · ")
end

local function applyAchievementVisualState(card, entry)
	local required = entry.requiredProgress or 0
	local cur = entry.currentProgress or 0
	local unlocked = entry.unlocked == true
	local inProgress = (not unlocked) and required > 0 and cur > 0
	local locked = (not unlocked) and (not inProgress)

	local tint = unlocked and C.green or inProgress and C.achieveAccent or C.textMut
	local bg = card:FindFirstChild("Bg")
	local badgeIcon = bg and bg:FindFirstChild("BadgeIcon")
	local badgeRing = bg and bg:FindFirstChild("BadgeRing")
	local titleLbl = bg and bg:FindFirstChild("Title")
	local descLbl = bg and bg:FindFirstChild("Desc")
	local pill = bg and bg:FindFirstChild("StatePill")
	local pillText = pill and pill:FindFirstChild("Text")
	local barBg = bg and bg:FindFirstChild("BarBg")
	local barFill = barBg and barBg:FindFirstChild("Fill")
	local progText = bg and bg:FindFirstChild("ProgText")
	local reqText = bg and bg:FindFirstChild("ReqText")
	local lockOverlay = bg and bg:FindFirstChild("LockOverlay")
	local rewardRow = bg and bg:FindFirstChild("RewardRow")

	if bg then
		bg.BackgroundColor3 = unlocked and Color3.fromRGB(18, 28, 22) or C.card
		bg.BackgroundTransparency = unlocked and 0.08 or 0
	end

	-- Update badge/letter circle visuals when the state changes.
	if badgeIcon and badgeIcon:IsA("ImageLabel") then
		badgeIcon.ImageColor3 = tint
		badgeIcon.ImageTransparency = locked and 0.55 or 0
	elseif badgeRing and badgeRing:IsA("Frame") then
		badgeRing.BackgroundTransparency = locked and 0.45 or 0.2
		local stroke = badgeRing:FindFirstChild("BadgeStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Color = tint
			stroke.Transparency = locked and 0.5 or 0.15
		end
		local star = badgeRing:FindFirstChild("BadgeStar")
		if star and star:IsA("TextLabel") then
			star.TextColor3 = tint
			star.TextTransparency = locked and 0.55 or 0
		end
	end
	if titleLbl then
		titleLbl.TextColor3 = unlocked and C.text or inProgress and C.text or C.textMut
	end
	if descLbl then
		descLbl.TextColor3 = unlocked and C.textSec or inProgress and C.textSec or C.textMut
	end
	if pill and pillText then
		if unlocked then
			pill.BackgroundColor3 = Color3.fromRGB(30, 70, 44)
			pillText.Text = "COMPLETED"
			pillText.TextColor3 = C.green
		elseif inProgress then
			pill.BackgroundColor3 = Color3.fromRGB(34, 30, 20)
			pillText.Text = "IN PROGRESS"
			pillText.TextColor3 = C.achieveAccent
		else
			pill.BackgroundColor3 = Color3.fromRGB(22, 24, 35)
			pillText.Text = "LOCKED"
			pillText.TextColor3 = C.textMut
		end
	end

	local ratio = (required > 0) and math.clamp(cur / required, 0, 1) or 0
	if barFill then
		barFill.Size = UDim2.new(ratio, 0, 1, 0)
		barFill.BackgroundColor3 = tint
		barFill.BackgroundTransparency = locked and 0.35 or 0
	end
	if progText then
		progText.Text = string.format("%d/%d", cur, required)
		progText.TextColor3 = unlocked and C.green or inProgress and C.achieveAccent or C.textMut
	end
	if reqText then
		reqText.TextColor3 = unlocked and C.textSec or inProgress and C.textSec or C.textMut
	end
	if lockOverlay then
		lockOverlay.Visible = locked
	end
	if rewardRow and rewardRow:IsA("TextLabel") then
		local line = getAchievementRewardLine(entry)
		rewardRow.Visible = line ~= ""
		rewardRow.Text = line ~= "" and ("Reward: " .. line) or ""
		rewardRow.TextColor3 = unlocked and Color3.fromRGB(130, 210, 160) or inProgress and C.blue or C.textMut
		rewardRow.TextTransparency = locked and 0.25 or 0
	end
end

local function buildAchievementCard(entry, layoutOrder, cellW)
	local card = Instance.new("Frame")
	card.Name = "Ach_" .. tostring(entry.id)
	card.Size = UDim2.new(0, cellW, 0, 96)
	card.BackgroundTransparency = 1
	card.LayoutOrder = layoutOrder or 0

	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = C.card
	bg.BorderSizePixel = 0
	bg.Parent = card
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke", bg)
	stroke.Color = C.divider
	stroke.Thickness = 1
	stroke.Transparency = 0.15

	-- Subtle gradient sheen (fantasy card feel)
	local sheen = Instance.new("Frame")
	sheen.Size = UDim2.new(1, 0, 1, 0)
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BackgroundTransparency = 0.94
	sheen.BorderSizePixel = 0
	sheen.Parent = bg
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 120, 90)),
	})
	grad.Rotation = 35
	grad.Parent = sheen

	-- Badge / emblem
	mkBadgeIcon(bg, entry.icon, C.achieveAccent, entry.unlocked ~= true and (entry.currentProgress or 0) <= 0)

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Size = UDim2.new(1, -92, 0, 18)
	titleLbl.Position = UDim2.new(0, 80, 0, 10)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = tostring(entry.name or "Achievement")
	titleLbl.TextColor3 = C.text
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 13
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	titleLbl.ZIndex = 6
	titleLbl.Parent = bg

	local descLbl = Instance.new("TextLabel")
	descLbl.Name = "Desc"
	descLbl.Size = UDim2.new(1, -92, 0, 20)
	descLbl.Position = UDim2.new(0, 80, 0, 28)
	descLbl.BackgroundTransparency = 1
	descLbl.Text = tostring(entry.description or "")
	descLbl.TextColor3 = C.textSec
	descLbl.Font = Enum.Font.GothamMedium
	descLbl.TextSize = 10
	descLbl.TextWrapped = true
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.TextYAlignment = Enum.TextYAlignment.Top
	descLbl.ZIndex = 6
	descLbl.Parent = bg

	local rewardRow = Instance.new("TextLabel")
	rewardRow.Name = "RewardRow"
	rewardRow.Size = UDim2.new(1, -92, 0, 12)
	rewardRow.Position = UDim2.new(0, 80, 0, 48)
	rewardRow.BackgroundTransparency = 1
	rewardRow.Text = ""
	rewardRow.TextColor3 = C.blue
	rewardRow.Font = Enum.Font.GothamBold
	rewardRow.TextSize = 9
	rewardRow.TextXAlignment = Enum.TextXAlignment.Left
	rewardRow.TextTruncate = Enum.TextTruncate.AtEnd
	rewardRow.ZIndex = 6
	rewardRow.Visible = false
	rewardRow.Parent = bg

	-- State pill (top-right)
	local pill = Instance.new("Frame")
	pill.Name = "StatePill"
	pill.Size = UDim2.new(0, 112, 0, 22)
	pill.Position = UDim2.new(1, -122, 0, 8)
	pill.BackgroundColor3 = Color3.fromRGB(22, 24, 35)
	pill.BorderSizePixel = 0
	pill.ZIndex = 6
	pill.Parent = bg
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
	local pillStroke = Instance.new("UIStroke", pill)
	pillStroke.Color = C.divider
	pillStroke.Thickness = 1
	pillStroke.Transparency = 0.35
	local pillText = Instance.new("TextLabel")
	pillText.Name = "Text"
	pillText.Size = UDim2.new(1, -12, 1, 0)
	pillText.Position = UDim2.new(0, 6, 0, 0)
	pillText.BackgroundTransparency = 1
	pillText.Text = "LOCKED"
	pillText.TextColor3 = C.textMut
	pillText.Font = Enum.Font.GothamBold
	pillText.TextSize = 10
	pillText.TextXAlignment = Enum.TextXAlignment.Center
	pillText.Parent = pill

	-- Progress bar
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, -92, 0, 10)
	barBg.Position = UDim2.new(0, 80, 1, -22)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 6
	barBg.Parent = bg
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = C.achieveAccent
	fill.BorderSizePixel = 0
	fill.ZIndex = 6
	fill.Parent = barBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

	local progText = Instance.new("TextLabel")
	progText.Name = "ProgText"
	progText.Size = UDim2.new(0, 70, 0, 14)
	progText.Position = UDim2.new(1, -78, 1, -36)
	progText.BackgroundTransparency = 1
	progText.Text = "0/0"
	progText.TextColor3 = C.textMut
	progText.Font = Enum.Font.GothamBold
	progText.TextSize = 10
	progText.TextXAlignment = Enum.TextXAlignment.Right
	progText.ZIndex = 6
	progText.Parent = bg

	local reqText = Instance.new("TextLabel")
	reqText.Name = "ReqText"
	reqText.Size = UDim2.new(1, -92, 0, 14)
	reqText.Position = UDim2.new(0, 80, 1, -36)
	reqText.BackgroundTransparency = 1
	reqText.Text = tostring(entry.category or "General")
	reqText.TextColor3 = C.textMut
	reqText.Font = Enum.Font.GothamMedium
	reqText.TextSize = 9
	reqText.TextXAlignment = Enum.TextXAlignment.Left
	reqText.ZIndex = 6
	reqText.Parent = bg

	-- Lock overlay (visible only when locked)
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	lockOverlay.BackgroundTransparency = 0.75
	lockOverlay.BorderSizePixel = 0
	lockOverlay.Visible = false
	-- Put the lock overlay behind badge/letter circle and text.
	lockOverlay.ZIndex = 0
	lockOverlay.Parent = bg
	Instance.new("UICorner", lockOverlay).CornerRadius = UDim.new(0, 12)
	local lock = Instance.new("TextLabel")
	lock.Size = UDim2.new(0, 90, 0, 20)
	lock.Position = UDim2.new(0, 12, 0, 10)
	lock.BackgroundTransparency = 1
	lock.Text = "🔒"
	lock.TextColor3 = C.textMut
	lock.Font = Enum.Font.GothamBlack
	lock.TextSize = 14
	lock.TextXAlignment = Enum.TextXAlignment.Left
	lock.ZIndex = 0
	lock.Parent = lockOverlay

	return card
end

function refreshAchievements()
	-- Clear existing cards
	for _, child in ipairs(achievementsTab:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	achievementCardById = {}

	local isMobile = isMobileLayout()
	local w = achievementsTab.AbsoluteSize.X
	if w <= 0 then w = 720 end
	local cols = isMobile and 1 or 2
	local pad = 10
	local cellW = math.floor((w - (pad * (cols - 1))) / cols)
	achievementsLayout.CellSize = UDim2.new(0, cellW, 0, isMobile and 104 or 96)

	local entries = nil
	if getAchievements and getAchievements:IsA("RemoteFunction") then
		local ok, data = pcall(function() return getAchievements:InvokeServer() end)
		if ok and type(data) == "table" then entries = data end
	end

	if not entries then
		-- Fallback (offline / missing server) for dev sanity
		entries = {}
		local defs = AchievementsConfig and AchievementsConfig.Definitions or {}
		for _, def in ipairs(defs) do
			table.insert(entries, {
				id = def.id,
				name = def.name,
				description = def.description,
				icon = def.icon or "",
				category = def.category,
				currentProgress = 0,
				requiredProgress = def.requiredProgress,
				unlocked = false,
				rewardData = def.rewardData,
			})
		end
	end

	-- Sort: completed first? Better: in-progress first, then locked, then completed at end? Players want wins visible.
	table.sort(entries, function(a, b)
		local aDone = a.unlocked == true
		local bDone = b.unlocked == true
		if aDone ~= bDone then return aDone and not bDone end
		local ar = (a.requiredProgress or 0) > 0 and (a.currentProgress or 0) / (a.requiredProgress or 1) or 0
		local br = (b.requiredProgress or 0) > 0 and (b.currentProgress or 0) / (b.requiredProgress or 1) or 0
		if math.abs(ar - br) > 0.0001 then return ar > br end
		return tostring(a.name) < tostring(b.name)
	end)

	-- Header hint card (full width)
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 34)
	hint.BackgroundTransparency = 1
	hint.Text = "Earn badges by hatching, battling, exploring, and building. Completed achievements stay here forever."
	hint.TextColor3 = C.textMut
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 10
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.LayoutOrder = -1000
	hint.Parent = achievementsTab

	local order = 0
	for _, entry in ipairs(entries) do
		order += 1
		achievementCacheById[entry.id] = entry
		local card = buildAchievementCard(entry, order, cellW)
		card.Parent = achievementsTab
		achievementCardById[entry.id] = card
		applyAchievementVisualState(card, entry)
	end
end

-- Achievement unlock RewardPopup: AchievementUnlockBadge.client.lua (top-edge badge, tap to open).

-- Live updates
if achievementProgress and achievementProgress:IsA("RemoteEvent") then
	achievementProgress.OnClientEvent:Connect(function(entry)
		if type(entry) ~= "table" or not entry.id then return end
		achievementCacheById[entry.id] = entry
		local card = achievementCardById[entry.id]
		if card then
			applyAchievementVisualState(card, entry)
		end
	end)
end

if achievementUnlocked and achievementUnlocked:IsA("RemoteEvent") then
	achievementUnlocked.OnClientEvent:Connect(function(def)
		-- Flip the cached visual state immediately (prevents "still LOCKED" after unlock).
		if def and def.id then
			local cached = achievementCacheById[def.id]
			if cached then
				cached.unlocked = true
				local card = achievementCardById[def.id]
				if card then
					applyAchievementVisualState(card, cached)
				end
			end
		end

		-- Re-fetch server data for correctness (e.g., progress numbers/titles).
		if isVis and activeTab == "Achievements" then
			-- Small delay: lets the unlocked tier briefly render as "COMPLETED"
			-- before we rebuild and advance the display to the next tier.
			task.delay(0.35, function()
				if isVis and activeTab == "Achievements" then
					refreshAchievements()
				end
			end)
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Rebirth tab refresh (ported from RebirthUIClient)
-- ══════════════════════════════════════════════════════════════════════════════

local ACHIEVEMENT_FILTERS = {
	{ id = "All", label = "All Tiers" },
	{ id = "In Progress", label = "In Progress" },
	{ id = "Completed", label = "Completed" },
	{ id = "Locked", label = "Locked" },
}

local achievementViewCategory = "All"
local achievementViewFilter = "All"
local achievementRefreshQueued = false
local achievementRefreshToken = 0

local function getAchievementCategoryMeta(category)
	local meta = AchievementsConfig and AchievementsConfig.Categories and AchievementsConfig.Categories[category]
	if meta then
		return meta
	end
	return {
		label = category or "Achievements",
		accent = C.achieveAccent,
		description = "Track the deeds that shape your legend.",
	}
end

local function getAchievementEntryState(entry)
	local required = math.max(1, tonumber(entry.requiredProgress) or 1)
	local current = math.max(0, tonumber(entry.currentProgress) or 0)
	if entry.unlocked == true then
		return "Completed", current, required
	end
	if current > 0 then
		return "In Progress", current, required
	end
	return "Locked", current, required
end

local function getLastCompletedChainEntry(chainEntries)
	local last = nil
	for _, entry in ipairs(chainEntries) do
		if getAchievementEntryState(entry) == "Completed" then
			last = entry
		end
	end
	return last
end

local function getFirstInProgressChainEntry(chainEntries)
	for _, entry in ipairs(chainEntries) do
		if getAchievementEntryState(entry) == "In Progress" then
			return entry
		end
	end
	return nil
end

local function achievementMatchesFilter(chainEntries)
	if achievementViewFilter == "All" then
		return true
	end

	for _, entry in ipairs(chainEntries) do
		local state = getAchievementEntryState(entry)
		if state == achievementViewFilter then
			return true
		end
	end

	return false
end

local function fetchAchievementEntries()
	local entries = nil
	if getAchievements and getAchievements:IsA("RemoteFunction") then
		local ok, data = pcall(function()
			return getAchievements:InvokeServer()
		end)
		if ok and type(data) == "table" then
			entries = data
		end
	end

	if type(entries) ~= "table" then
		entries = {}
		for _, cached in pairs(achievementCacheById) do
			table.insert(entries, cached)
		end
	end

	if #entries == 0 and AchievementsConfig and AchievementsConfig.Definitions then
		for _, def in ipairs(AchievementsConfig.Definitions) do
			table.insert(entries, {
				id = def.id,
				category = def.category,
				subcategory = def.subcategory,
				chainName = def.chainName,
				name = def.name,
				titleEarned = def.titleEarned,
				description = def.description,
				icon = def.icon or "",
				badgeKey = def.badgeKey or "",
				badgeGlyph = def.badgeGlyph or "",
				badgeAccent = def.badgeAccent,
				currentProgress = 0,
				requiredProgress = def.requiredProgress or 0,
				unlocked = false,
				tier = def.tier or 1,
				tierChainId = def.tierChainId or def.id,
				chainTierCount = def.chainTierCount or 1,
				rewardData = def.rewardData,
				sortOrder = def.sortOrder or 0,
			})
		end
	end

	return entries
end

local function buildAchievementEntryMap(entries)
	local byId = {}
	for _, entry in ipairs(entries or {}) do
		if type(entry) == "table" and entry.id then
			byId[entry.id] = entry
		end
	end
	return byId
end

local function buildMergedAchievementEntries(entries)
	local mergedById = {}
	local liveById = buildAchievementEntryMap(entries)
	local defs = AchievementsConfig and AchievementsConfig.Definitions or {}

	for _, def in ipairs(defs) do
		local live = liveById[def.id] or achievementCacheById[def.id]
		local entry = {
			id = def.id,
			category = live and live.category or def.category,
			subcategory = live and live.subcategory or def.subcategory,
			chainName = live and live.chainName or def.chainName,
			name = live and live.name or def.name,
			titleEarned = live and live.titleEarned or def.titleEarned,
			description = live and live.description or def.description,
			icon = live and live.icon or def.icon or "",
			badgeKey = live and live.badgeKey or def.badgeKey or def.id,
			badgeGlyph = live and live.badgeGlyph or def.badgeGlyph or string.sub(def.chainName or def.name or "A", 1, 1),
			badgeAccent = live and live.badgeAccent or def.badgeAccent or getAchievementCategoryMeta(def.category).accent,
			currentProgress = math.max(0, tonumber(live and live.currentProgress) or 0),
			requiredProgress = math.max(0, tonumber(live and live.requiredProgress) or tonumber(def.requiredProgress) or 0),
			unlocked = live and live.unlocked == true or false,
			tier = live and live.tier or def.tier or 1,
			tierChainId = live and live.tierChainId or def.tierChainId or def.id,
			chainTierCount = live and live.chainTierCount or def.chainTierCount or 1,
			rewardData = live and live.rewardData or def.rewardData,
			sortOrder = live and live.sortOrder or def.sortOrder or 0,
		}

		mergedById[def.id] = entry
		achievementCacheById[def.id] = entry
	end

	for id, live in pairs(liveById) do
		if not mergedById[id] then
			mergedById[id] = live
			achievementCacheById[id] = live
		end
	end

	return mergedById
end

local function computeChainSummary(chainEntries)
	local unlockedCount = 0
	local totalRatio = 0
	local nextEntry = nil
	local hasProgress = false

	for _, entry in ipairs(chainEntries) do
		local state, current, required = getAchievementEntryState(entry)
		if state == "Completed" then
			unlockedCount += 1
		end
		if state == "In Progress" then
			hasProgress = true
		end
		if state ~= "Completed" and not nextEntry then
			nextEntry = entry
		end
		totalRatio += math.clamp(current / required, 0, 1)
	end

	local status = "Locked"
	if unlockedCount >= #chainEntries and #chainEntries > 0 then
		status = "Completed"
	elseif hasProgress then
		status = "In Progress"
	end

	return {
		unlockedCount = unlockedCount,
		totalCount = #chainEntries,
		status = status,
		nextEntry = nextEntry,
		ratio = (#chainEntries > 0) and (totalRatio / #chainEntries) or 0,
	}
end

local function queueAchievementRefresh()
	if achievementRefreshQueued then
		return
	end

	achievementRefreshQueued = true
	local token = achievementRefreshToken + 1
	achievementRefreshToken = token

	task.delay(0.12, function()
		if achievementRefreshToken ~= token then
			return
		end
		achievementRefreshQueued = false
		if isVis and activeTab == "Achievements" then
			refreshAchievements()
		end
	end)
end

local function getAchievementsAvailableWidth()
	local width = achievementsTab.AbsoluteSize.X
	if width <= 0 then
		width = main.AbsoluteSize.X - 40
	end
	return math.max(280, width - 6)
end

local function createAchievementChipRow(parent, heading, items, selectedId, accent, order, onSelected)
	local availableWidth = getAchievementsAvailableWidth()
	local chipHeight = 38
	local gap = 8
	local minChipWidth = (#items <= 4) and 120 or 110
	local columns = math.max(1, math.min(#items, math.floor((availableWidth + gap) / (minChipWidth + gap))))
	local rowCount = math.max(1, math.ceil(#items / columns))
	local rowHeight = 22 + (rowCount * chipHeight) + ((rowCount - 1) * gap)
	local chipWidth = math.max(minChipWidth, math.floor((availableWidth - ((columns - 1) * gap)) / columns))

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, rowHeight)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = heading
	label.TextColor3 = C.textMut
	label.Font = Enum.Font.GothamBold
	label.TextSize = 10
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local gridHolder = Instance.new("Frame")
	gridHolder.Size = UDim2.new(1, 0, 0, rowHeight - 22)
	gridHolder.Position = UDim2.new(0, 0, 0, 22)
	gridHolder.BackgroundTransparency = 1
	gridHolder.Parent = row

	local chipLayout = Instance.new("UIGridLayout")
	chipLayout.FillDirectionMaxCells = columns
	chipLayout.CellPadding = UDim2.new(0, gap, 0, gap)
	chipLayout.CellSize = UDim2.new(0, chipWidth, 0, chipHeight)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = gridHolder

	for _, item in ipairs(items) do
		local active = item.id == selectedId
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, chipWidth, 0, chipHeight)
		button.BackgroundColor3 = active and accent or C.card
		button.BackgroundTransparency = active and 0.08 or 0
		button.BorderSizePixel = 0
		button.Text = item.label
		button.TextColor3 = active and C.bg or C.textSec
		button.Font = Enum.Font.GothamBold
		button.TextSize = 11
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.AutoButtonColor = false
		button.Parent = gridHolder
		Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)

		local stroke = Instance.new("UIStroke", button)
		stroke.Color = active and accent or C.divider
		stroke.Thickness = active and 1.5 or 1
		stroke.Transparency = active and 0.05 or 0.2

		button.MouseButton1Click:Connect(function()
			onSelected(item.id)
		end)
	end
end

local function createAchievementBadge(parent, entry)
	local accent = entry.badgeAccent or C.achieveAccent

	local shell = Instance.new("Frame")
	shell.Size = UDim2.new(0, 42, 0, 42)
	shell.Position = UDim2.new(0, 12, 0, 12)
	shell.BackgroundColor3 = Color3.fromRGB(17, 19, 28)
	shell.BorderSizePixel = 0
	shell.ZIndex = 10
	shell.Parent = parent
	Instance.new("UICorner", shell).CornerRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke", shell)
	stroke.Color = accent
	stroke.Thickness = 2
	stroke.Transparency = 0.15

	if entry.icon and entry.icon ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, -10, 1, -10)
		icon.Position = UDim2.new(0, 5, 0, 5)
		icon.BackgroundTransparency = 1
		icon.Image = entry.icon
		icon.ImageColor3 = accent
		icon.ZIndex = 11
		icon.Parent = shell
	else
		local glyph = Instance.new("TextLabel")
		glyph.Size = UDim2.new(1, 0, 1, 0)
		glyph.BackgroundTransparency = 1
		glyph.Text = tostring(entry.badgeGlyph or string.sub(entry.chainName or entry.name or "A", 1, 1))
		glyph.TextColor3 = accent
		glyph.Font = Enum.Font.GothamBlack
		glyph.TextSize = 17
		glyph.ZIndex = 11
		glyph.Parent = shell
	end

	return shell
end

local function buildAchievementTierCard(entry, order, cardWidth, cardHeight)
	local card = Instance.new("Frame")
	card.Name = "Ach_" .. tostring(entry.id)
	card.Size = UDim2.new(0, cardWidth, 0, cardHeight)
	card.BackgroundTransparency = 1
	card.LayoutOrder = order

	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = C.card
	bg.BorderSizePixel = 0
	bg.Parent = card
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", bg)
	stroke.Color = C.divider
	stroke.Thickness = 1
	stroke.Transparency = 0.1

	local sheen = Instance.new("Frame")
	sheen.Size = UDim2.new(1, 0, 1, 0)
	sheen.BackgroundColor3 = entry.badgeAccent or C.achieveAccent
	sheen.BackgroundTransparency = 0.94
	sheen.BorderSizePixel = 0
	sheen.Parent = bg
	local sheenGradient = Instance.new("UIGradient")
	sheenGradient.Rotation = 30
	sheenGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0.95),
	})
	sheenGradient.Parent = sheen

	createAchievementBadge(bg, entry)

	local tierPill = Instance.new("Frame")
	tierPill.Size = UDim2.new(0, 58, 0, 20)
	-- Move right a bit so the "TIER" label never ends up under
	-- the left lettered circle.
	tierPill.Position = UDim2.new(1, -58, 0, 10)
	tierPill.BackgroundColor3 = Color3.fromRGB(22, 24, 35)
	tierPill.BorderSizePixel = 0
	tierPill.ZIndex = 6
	tierPill.Parent = bg
	Instance.new("UICorner", tierPill).CornerRadius = UDim.new(1, 0)

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Size = UDim2.new(1, 0, 1, 0)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = "TIER " .. tostring((AchievementsConfig and AchievementsConfig.TierLabels and AchievementsConfig.TierLabels[entry.tier]) or entry.tier or 1)
	tierLabel.TextColor3 = C.textSec
	tierLabel.Font = Enum.Font.GothamBold
	tierLabel.TextSize = 9
	tierLabel.ZIndex = 6
	tierLabel.Parent = tierPill

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Size = UDim2.new(1, -132, 0, 18)
	titleLbl.Position = UDim2.new(0, 64, 0, 12)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = tostring(entry.name or "Achievement")
	titleLbl.TextColor3 = C.text
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 12
	titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	-- Center in the available area (between the badge and the tier pill)
	-- so the full "Muster I" line remains visible.
	titleLbl.TextXAlignment = Enum.TextXAlignment.Center
	titleLbl.ZIndex = 6
	titleLbl.Parent = bg

	local pill = Instance.new("Frame")
	pill.Name = "StatePill"
	pill.Size = UDim2.new(0, 96, 0, 22)
	pill.Position = UDim2.new(1, -108, 0, 34)
	pill.BackgroundColor3 = Color3.fromRGB(22, 24, 35)
	pill.BorderSizePixel = 0
	pill.ZIndex = 6
	pill.Parent = bg
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

	local pillStroke = Instance.new("UIStroke", pill)
	pillStroke.Color = C.divider
	pillStroke.Thickness = 1
	pillStroke.Transparency = 0.35

	local pillText = Instance.new("TextLabel")
	pillText.Name = "Text"
	pillText.Size = UDim2.new(1, -10, 1, 0)
	pillText.Position = UDim2.new(0, 5, 0, 0)
	pillText.BackgroundTransparency = 1
	pillText.Text = "LOCKED"
	pillText.TextColor3 = C.textMut
	pillText.Font = Enum.Font.GothamBold
	pillText.TextSize = 9
	pillText.ZIndex = 6
	pillText.Parent = pill

	local descLbl = Instance.new("TextLabel")
	descLbl.Name = "Desc"
	descLbl.Size = UDim2.new(1, -24, 0, 24)
	descLbl.Position = UDim2.new(0, 12, 0, 64)
	descLbl.BackgroundTransparency = 1
	descLbl.Text = tostring(entry.description or "")
	descLbl.TextColor3 = C.textSec
	descLbl.Font = Enum.Font.GothamMedium
	descLbl.TextSize = 10
	descLbl.TextWrapped = true
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.TextYAlignment = Enum.TextYAlignment.Top
	descLbl.ZIndex = 6
	descLbl.Parent = bg

	local rewardRow = Instance.new("TextLabel")
	rewardRow.Name = "RewardRow"
	rewardRow.Size = UDim2.new(1, -24, 0, 14)
	rewardRow.Position = UDim2.new(0, 12, 0, 89)
	rewardRow.BackgroundTransparency = 1
	rewardRow.Text = ""
	rewardRow.TextColor3 = C.blue
	rewardRow.Font = Enum.Font.GothamBold
	rewardRow.TextSize = 9
	rewardRow.TextXAlignment = Enum.TextXAlignment.Left
	rewardRow.TextTruncate = Enum.TextTruncate.AtEnd
	rewardRow.ZIndex = 6
	rewardRow.Visible = false
	rewardRow.Parent = bg

	local reqText = Instance.new("TextLabel")
	reqText.Name = "ReqText"
	reqText.Size = UDim2.new(1, -106, 0, 14)
	reqText.Position = UDim2.new(0, 12, 1, -36)
	reqText.BackgroundTransparency = 1
	reqText.Text = "Title: " .. tostring(entry.titleEarned or "Unknown Honor")
	reqText.TextColor3 = entry.badgeAccent or C.achieveAccent
	reqText.Font = Enum.Font.GothamBold
	reqText.TextSize = 9
	reqText.TextXAlignment = Enum.TextXAlignment.Left
	reqText.TextTruncate = Enum.TextTruncate.AtEnd
	reqText.ZIndex = 6
	reqText.Parent = bg

	local progText = Instance.new("TextLabel")
	progText.Name = "ProgText"
	progText.Size = UDim2.new(0, 82, 0, 14)
	progText.Position = UDim2.new(1, -94, 1, -36)
	progText.BackgroundTransparency = 1
	progText.Text = "0/0"
	progText.TextColor3 = C.textMut
	progText.Font = Enum.Font.GothamBold
	progText.TextSize = 10
	progText.TextXAlignment = Enum.TextXAlignment.Right
	progText.ZIndex = 6
	progText.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, -24, 0, 10)
	barBg.Position = UDim2.new(0, 12, 1, -22)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 6
	barBg.Parent = bg
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = entry.badgeAccent or C.achieveAccent
	fill.BorderSizePixel = 0
	fill.ZIndex = 6
	fill.Parent = barBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	lockOverlay.BackgroundTransparency = 0.8
	lockOverlay.BorderSizePixel = 0
	lockOverlay.Visible = false
	-- Put the lock overlay behind the badge/letter circle and all text.
	lockOverlay.ZIndex = 0
	lockOverlay.Parent = bg
	Instance.new("UICorner", lockOverlay).CornerRadius = UDim.new(0, 12)

	applyAchievementVisualState(card, entry)
	return card
end

local function buildAchievementHero(parent, summary, accent, order)
	local availableWidth = getAchievementsAvailableWidth()
	local gap = 8
	local statBoxHeight = 34
	local minStatWidth = 120
	local stats = {
		{ label = "Unlocked", value = string.format("%d", summary.unlockedTiers) },
		{ label = "Active", value = string.format("%d", summary.activeChains) },
		{ label = "Complete", value = string.format("%d", summary.completedChains) },
		{ label = "Showing", value = string.format("%d/%d", summary.visibleChains, summary.totalChains) },
	}
	local statColumns = math.max(1, math.min(#stats, math.floor(((availableWidth - 24) + gap) / (minStatWidth + gap))))
	local statRows = math.max(1, math.ceil(#stats / statColumns))
	local statRowHeight = (statRows * statBoxHeight) + ((statRows - 1) * gap)
	local heroHeight = 110 + statRowHeight

	local hero = Instance.new("Frame")
	hero.Size = UDim2.new(1, 0, 0, heroHeight)
	hero.BackgroundColor3 = C.bgLight
	hero.BorderSizePixel = 0
	hero.LayoutOrder = order
	hero.Parent = parent
	Instance.new("UICorner", hero).CornerRadius = UDim.new(0, 16)

	local stroke = Instance.new("UIStroke", hero)
	stroke.Color = accent
	stroke.Thickness = 1
	stroke.Transparency = 0.3

	local wash = Instance.new("Frame")
	wash.Size = UDim2.new(1, 0, 1, 0)
	wash.BackgroundColor3 = accent
	wash.BackgroundTransparency = 0.92
	wash.BorderSizePixel = 0
	wash.Parent = hero
	local washGradient = Instance.new("UIGradient")
	washGradient.Rotation = 20
	washGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.95),
	})
	washGradient.Parent = wash

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -24, 0, 24)
	titleLbl.Position = UDim2.new(0, 12, 0, 12)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Knightly Deeds"
	titleLbl.TextColor3 = C.text
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 16
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = hero

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -24, 0, 34)
	subtitle.Position = UDim2.new(0, 12, 0, 38)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = summary.subtitle
	subtitle.TextColor3 = C.textSec
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 11
	subtitle.TextWrapped = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.Parent = hero

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -24, 0, 10)
	barBg.Position = UDim2.new(0, 12, 0, 80)
	barBg.BackgroundColor3 = Color3.fromRGB(34, 36, 48)
	barBg.BorderSizePixel = 0
	barBg.Parent = hero
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(summary.completionRatio, 0, 1, 0)
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

	local progressText = Instance.new("TextLabel")
	progressText.Size = UDim2.new(1, -24, 0, 14)
	progressText.Position = UDim2.new(0, 12, 0, 94)
	progressText.BackgroundTransparency = 1
	progressText.Text = string.format("%d/%d tiers claimed", summary.unlockedTiers, summary.totalTiers)
	progressText.TextColor3 = accent
	progressText.Font = Enum.Font.GothamBold
	progressText.TextSize = 10
	progressText.TextXAlignment = Enum.TextXAlignment.Left
	progressText.Parent = hero

	local statRow = Instance.new("Frame")
	statRow.Size = UDim2.new(1, -24, 0, statRowHeight)
	statRow.Position = UDim2.new(0, 12, 1, -(statRowHeight + 10))
	statRow.BackgroundTransparency = 1
	statRow.Parent = hero
	local boxWidth = math.max(minStatWidth, math.floor((((availableWidth - 24) - ((statColumns - 1) * gap))) / statColumns))

	local statLayout = Instance.new("UIGridLayout")
	statLayout.FillDirectionMaxCells = statColumns
	statLayout.CellPadding = UDim2.new(0, gap, 0, gap)
	statLayout.CellSize = UDim2.new(0, boxWidth, 0, statBoxHeight)
	statLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statLayout.Parent = statRow

	for index, stat in ipairs(stats) do
		local box = Instance.new("Frame")
		box.Size = UDim2.new(0, boxWidth, 0, statBoxHeight)
		box.BackgroundColor3 = Color3.fromRGB(20, 22, 31)
		box.BorderSizePixel = 0
		box.LayoutOrder = index
		box.Parent = statRow
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)

		local boxStroke = Instance.new("UIStroke", box)
		boxStroke.Color = accent
		boxStroke.Thickness = 1
		boxStroke.Transparency = 0.65

		local value = Instance.new("TextLabel")
		value.Size = UDim2.new(1, -12, 0, 16)
		value.Position = UDim2.new(0, 6, 0, 4)
		value.BackgroundTransparency = 1
		value.Text = stat.value
		value.TextColor3 = C.text
		value.Font = Enum.Font.GothamBlack
		value.TextSize = 12
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.Parent = box

		local statLabel = Instance.new("TextLabel")
		statLabel.Size = UDim2.new(1, -12, 0, 12)
		statLabel.Position = UDim2.new(0, 6, 1, -16)
		statLabel.BackgroundTransparency = 1
		statLabel.Text = stat.label
		statLabel.TextColor3 = C.textMut
		statLabel.Font = Enum.Font.GothamBold
		statLabel.TextSize = 9
		statLabel.TextXAlignment = Enum.TextXAlignment.Left
		statLabel.Parent = box
	end
end

function refreshAchievements()
	for _, child in ipairs(achievementsTab:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	achievementCardById = {}

	local entries = fetchAchievementEntries()
	local mergedById = buildMergedAchievementEntries(entries)
	local categoryKeys = {}
	if AchievementsConfig and AchievementsConfig.CategoryOrder then
		for _, category in ipairs(AchievementsConfig.CategoryOrder) do
			table.insert(categoryKeys, category)
		end
	else
		categoryKeys = { "Capture", "Evolution", "Collection", "Battle", "Base", "Economy", "Exploration" }
	end

	local categoriesToShow = {}
	if achievementViewCategory == "All" then
		for _, category in ipairs(categoryKeys) do
			table.insert(categoriesToShow, category)
		end
	else
		table.insert(categoriesToShow, achievementViewCategory)
	end

	local summary = {
		totalChains = 0,
		visibleChains = 0,
		completedChains = 0,
		activeChains = 0,
		totalTiers = 0,
		unlockedTiers = 0,
		completionRatio = 0,
		subtitle = "Track your legend across the full world of Siegelings.",
	}

	local chainsByCategory = {}
	for _, category in ipairs(categoriesToShow) do
		chainsByCategory[category] = {}
	end

	for _, chainMeta in ipairs((AchievementsConfig and AchievementsConfig.Chains) or {}) do
		if chainsByCategory[chainMeta.category] then
			local defs = AchievementsConfig.DefinitionsByChain and AchievementsConfig.DefinitionsByChain[chainMeta.id] or {}
			local chainEntries = {}
			for _, def in ipairs(defs) do
				local entry = mergedById[def.id]
				if entry then
					table.insert(chainEntries, entry)
				end
			end

			if #chainEntries > 0 then
				local chainSummary = computeChainSummary(chainEntries)
				summary.totalChains += 1
				summary.totalTiers += chainSummary.totalCount
				summary.unlockedTiers += chainSummary.unlockedCount
				if chainSummary.status == "Completed" then
					summary.completedChains += 1
				elseif chainSummary.status == "In Progress" then
					summary.activeChains += 1
				end

				if achievementMatchesFilter(chainEntries) then
					summary.visibleChains += 1
					table.insert(chainsByCategory[chainMeta.category], {
						meta = chainMeta,
						entries = chainEntries,
						summary = chainSummary,
					})
				end
			end
		end
	end

	summary.completionRatio = (summary.totalTiers > 0) and (summary.unlockedTiers / summary.totalTiers) or 0
	local selectedCategoryMeta = achievementViewCategory ~= "All" and getAchievementCategoryMeta(achievementViewCategory) or nil
	if selectedCategoryMeta then
		summary.subtitle = string.format(
			"%s Showing %d chain lines with %d completed titles and %d active pursuits.",
			selectedCategoryMeta.description or "Track your deeds in this category.",
			summary.visibleChains,
			summary.completedChains,
			summary.activeChains
		)
	elseif achievementViewFilter ~= "All" then
		summary.subtitle = string.format(
			"Showing %s chains across the realm. Completed tiers remain visible in their full chain lines when they match the filter.",
			string.lower(achievementViewFilter)
		)
	end

	local order = 0
	local heroAccent = selectedCategoryMeta and selectedCategoryMeta.accent or C.achieveAccent
	order += 1
	buildAchievementHero(achievementsTab, summary, heroAccent, order)

	order += 1
	local categoryItems = { { id = "All", label = "All Categories" } }
	for _, category in ipairs(categoryKeys) do
		local meta = getAchievementCategoryMeta(category)
		table.insert(categoryItems, {
			id = category,
			label = meta.label or category,
		})
	end
	createAchievementChipRow(achievementsTab, "Browse by category", categoryItems, achievementViewCategory, heroAccent, order, function(categoryId)
		if achievementViewCategory ~= categoryId then
			achievementViewCategory = categoryId
			refreshAchievements()
		end
	end)

	order += 1
	createAchievementChipRow(achievementsTab, "Show", ACHIEVEMENT_FILTERS, achievementViewFilter, C.achieveAccent, order, function(filterId)
		if achievementViewFilter ~= filterId then
			achievementViewFilter = filterId
			refreshAchievements()
		end
	end)

	local availableWidth = achievementsTab.AbsoluteSize.X
	if availableWidth <= 0 then
		availableWidth = main.AbsoluteSize.X - 40
	end
	availableWidth = math.max(280, availableWidth - 6)
	local tierColumns
	if availableWidth >= 720 then
		tierColumns = 5
	elseif availableWidth >= 580 then
		tierColumns = 4
	elseif availableWidth >= 420 then
		tierColumns = 3
	else
		tierColumns = 2
	end

	local tierGap = 10
	local tierCellHeight = isMobileLayout() and 146 or 138
	local innerGridWidth = availableWidth - 28
	local tierCellWidth = math.max(118, math.floor((innerGridWidth - (tierGap * (tierColumns - 1))) / tierColumns))

	local renderedAnything = false
	for _, category in ipairs(categoriesToShow) do
		local visibleChains = chainsByCategory[category] or {}
		if #visibleChains > 0 then
			renderedAnything = true

			order += 1
			local section = Instance.new("Frame")
			section.Size = UDim2.new(1, 0, 0, 0)
			section.AutomaticSize = Enum.AutomaticSize.Y
			section.BackgroundTransparency = 1
			section.LayoutOrder = order
			section.Parent = achievementsTab

			local sectionLayout = Instance.new("UIListLayout")
			sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
			sectionLayout.Padding = UDim.new(0, 10)
			sectionLayout.Parent = section

			local categoryMeta = getAchievementCategoryMeta(category)
			local sectionHeader = Instance.new("Frame")
			sectionHeader.Size = UDim2.new(1, 0, 0, 52)
			sectionHeader.BackgroundColor3 = C.bgLight
			sectionHeader.BorderSizePixel = 0
			sectionHeader.LayoutOrder = 1
			sectionHeader.Parent = section
			Instance.new("UICorner", sectionHeader).CornerRadius = UDim.new(0, 12)

			local sectionStroke = Instance.new("UIStroke", sectionHeader)
			sectionStroke.Color = categoryMeta.accent or C.achieveAccent
			sectionStroke.Thickness = 1
			sectionStroke.Transparency = 0.35

			local accentBar = Instance.new("Frame")
			accentBar.Size = UDim2.new(0, 4, 1, -12)
			accentBar.Position = UDim2.new(0, 8, 0, 6)
			accentBar.BackgroundColor3 = categoryMeta.accent or C.achieveAccent
			accentBar.BorderSizePixel = 0
			accentBar.Parent = sectionHeader
			Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 3)

			local headerTitle = Instance.new("TextLabel")
			headerTitle.Size = UDim2.new(1, -180, 0, 18)
			headerTitle.Position = UDim2.new(0, 22, 0, 8)
			headerTitle.BackgroundTransparency = 1
			headerTitle.Text = string.upper(categoryMeta.label or category)
			headerTitle.TextColor3 = categoryMeta.accent or C.achieveAccent
			headerTitle.Font = Enum.Font.GothamBlack
			headerTitle.TextSize = 12
			headerTitle.TextXAlignment = Enum.TextXAlignment.Left
			headerTitle.Parent = sectionHeader

			local headerBody = Instance.new("TextLabel")
			headerBody.Size = UDim2.new(1, -180, 0, 16)
			headerBody.Position = UDim2.new(0, 22, 0, 28)
			headerBody.BackgroundTransparency = 1
			headerBody.Text = categoryMeta.description or "Long-form progress awaits in this category."
			headerBody.TextColor3 = C.textSec
			headerBody.Font = Enum.Font.GothamMedium
			headerBody.TextSize = 10
			headerBody.TextXAlignment = Enum.TextXAlignment.Left
			headerBody.TextTruncate = Enum.TextTruncate.AtEnd
			headerBody.Parent = sectionHeader

			local headerCount = Instance.new("TextLabel")
			headerCount.Size = UDim2.new(0, 150, 0, 18)
			headerCount.Position = UDim2.new(1, -162, 0.5, -9)
			headerCount.BackgroundTransparency = 1
			headerCount.Text = string.format("%d chain lines", #visibleChains)
			headerCount.TextColor3 = C.textMut
			headerCount.Font = Enum.Font.GothamBold
			headerCount.TextSize = 10
			headerCount.TextXAlignment = Enum.TextXAlignment.Right
			headerCount.Parent = sectionHeader

			local subcategoryOrder = 1
			local lastSubcategory = nil
			for _, chainData in ipairs(visibleChains) do
				if chainData.meta.subcategory ~= lastSubcategory then
					subcategoryOrder += 1
					lastSubcategory = chainData.meta.subcategory

					local subHeader = Instance.new("TextLabel")
					subHeader.Size = UDim2.new(1, -4, 0, 18)
					subHeader.BackgroundTransparency = 1
					subHeader.Text = tostring(lastSubcategory or "General")
					subHeader.TextColor3 = C.textMut
					subHeader.Font = Enum.Font.GothamBold
					subHeader.TextSize = 10
					subHeader.TextXAlignment = Enum.TextXAlignment.Left
					subHeader.LayoutOrder = subcategoryOrder
					subHeader.Parent = section
				end

				subcategoryOrder += 1
				-- Snapshot tier for the list: Completed = last claimed tier only (no in-progress card).
				-- In Progress = the tier currently being worked; All/Locked/etc. = next chain target.
				local entryToShow
				if achievementViewFilter == "Completed" then
					entryToShow = getLastCompletedChainEntry(chainData.entries)
				elseif achievementViewFilter == "In Progress" then
					entryToShow = getFirstInProgressChainEntry(chainData.entries)
						or chainData.summary.nextEntry
				else
					entryToShow = chainData.summary.nextEntry or chainData.entries[#chainData.entries]
				end
				local gridHeight = tierCellHeight

				local chainFrame = Instance.new("Frame")
				chainFrame.Size = UDim2.new(1, 0, 0, 82 + gridHeight)
				chainFrame.BackgroundColor3 = C.bgLight
				chainFrame.BorderSizePixel = 0
				-- Prevent card content from visually spilling beyond the golden border.
				chainFrame.ClipsDescendants = true
				chainFrame.LayoutOrder = subcategoryOrder
				chainFrame.Parent = section
				Instance.new("UICorner", chainFrame).CornerRadius = UDim.new(0, 14)

				local chainStroke = Instance.new("UIStroke", chainFrame)
				chainStroke.Color = chainData.meta.badgeAccent or categoryMeta.accent or C.achieveAccent
				chainStroke.Thickness = 1
				chainStroke.Transparency = 0.28

				local badgeShell = Instance.new("Frame")
				badgeShell.Size = UDim2.new(0, 44, 0, 44)
				badgeShell.Position = UDim2.new(0, 14, 0, 14)
				badgeShell.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
				badgeShell.BorderSizePixel = 0
				badgeShell.Parent = chainFrame
				Instance.new("UICorner", badgeShell).CornerRadius = UDim.new(1, 0)

				local badgeStroke = Instance.new("UIStroke", badgeShell)
				badgeStroke.Color = chainData.meta.badgeAccent or categoryMeta.accent or C.achieveAccent
				badgeStroke.Thickness = 2
				badgeStroke.Transparency = 0.15

				local badgeGlyph = Instance.new("TextLabel")
				badgeGlyph.Size = UDim2.new(1, 0, 1, 0)
				badgeGlyph.BackgroundTransparency = 1
				badgeGlyph.Text = tostring(chainData.meta.badgeGlyph or string.sub(chainData.meta.chainName or "A", 1, 1))
				badgeGlyph.TextColor3 = chainData.meta.badgeAccent or categoryMeta.accent or C.achieveAccent
				badgeGlyph.Font = Enum.Font.GothamBlack
				badgeGlyph.TextSize = 18
				badgeGlyph.Parent = badgeShell

				local chainTitle = Instance.new("TextLabel")
				chainTitle.Size = UDim2.new(1, -210, 0, 20)
				chainTitle.Position = UDim2.new(0, 68, 0, 14)
				chainTitle.BackgroundTransparency = 1
				chainTitle.Text = tostring(chainData.meta.chainName or "Achievement Chain")
				chainTitle.TextColor3 = C.text
				chainTitle.Font = Enum.Font.GothamBlack
				chainTitle.TextSize = 14
				chainTitle.TextXAlignment = Enum.TextXAlignment.Left
				chainTitle.TextTruncate = Enum.TextTruncate.AtEnd
				chainTitle.Parent = chainFrame

				local nextTextValue = "All titles claimed."
				if achievementViewFilter == "Completed" and entryToShow then
					nextTextValue = tostring(entryToShow.description or "")
				elseif chainData.summary.nextEntry then
					nextTextValue = tostring(chainData.summary.nextEntry.description or "")
				end
				local chainDetail = Instance.new("TextLabel")
				chainDetail.Size = UDim2.new(1, -210, 0, 16)
				chainDetail.Position = UDim2.new(0, 68, 0, 36)
				chainDetail.BackgroundTransparency = 1
				chainDetail.Text = nextTextValue
				chainDetail.TextColor3 = C.textSec
				chainDetail.Font = Enum.Font.GothamMedium
				chainDetail.TextSize = 10
				chainDetail.TextXAlignment = Enum.TextXAlignment.Left
				chainDetail.TextTruncate = Enum.TextTruncate.AtEnd
				chainDetail.Parent = chainFrame

				local countPill = Instance.new("Frame")
				countPill.Size = UDim2.new(0, 116, 0, 24)
				countPill.Position = UDim2.new(1, -130, 0, 14)
				countPill.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
				countPill.BorderSizePixel = 0
				countPill.Parent = chainFrame
				Instance.new("UICorner", countPill).CornerRadius = UDim.new(1, 0)

				local countText = Instance.new("TextLabel")
				countText.Size = UDim2.new(1, -12, 1, 0)
				countText.Position = UDim2.new(0, 6, 0, 0)
				countText.BackgroundTransparency = 1
				countText.Text = string.format("%d/%d tiers", chainData.summary.unlockedCount, chainData.summary.totalCount)
				countText.TextColor3 = chainData.meta.badgeAccent or categoryMeta.accent or C.achieveAccent
				countText.Font = Enum.Font.GothamBold
				countText.TextSize = 10
				countText.Parent = countPill

				local chainBarBg = Instance.new("Frame")
				chainBarBg.Size = UDim2.new(1, -28, 0, 8)
				chainBarBg.Position = UDim2.new(0, 14, 0, 62)
				chainBarBg.BackgroundColor3 = Color3.fromRGB(34, 36, 48)
				chainBarBg.BorderSizePixel = 0
				chainBarBg.Parent = chainFrame
				Instance.new("UICorner", chainBarBg).CornerRadius = UDim.new(0, 4)

				local chainBarFill = Instance.new("Frame")
				chainBarFill.Size = UDim2.new(chainData.summary.ratio, 0, 1, 0)
				chainBarFill.BackgroundColor3 = chainData.meta.badgeAccent or categoryMeta.accent or C.achieveAccent
				chainBarFill.BorderSizePixel = 0
				chainBarFill.Parent = chainBarBg
				Instance.new("UICorner", chainBarFill).CornerRadius = UDim.new(0, 4)

				local gridHolder = Instance.new("Frame")
				gridHolder.Size = UDim2.new(1, -28, 0, gridHeight)
				gridHolder.Position = UDim2.new(0, 14, 0, 82)
				gridHolder.BackgroundTransparency = 1
				gridHolder.ClipsDescendants = true
				gridHolder.Parent = chainFrame
				-- Render only the next (or last) tier card, filling the block.
				if entryToShow and entryToShow.id then
					local tierCardWidth = math.floor(innerGridWidth)
					local tierCard = buildAchievementTierCard(entryToShow, 1, tierCardWidth, tierCellHeight)
					tierCard.Parent = gridHolder
					achievementCardById[entryToShow.id] = tierCard
				end
			end
		end
	end

	if not renderedAnything then
		order += 1
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, 0, 0, 92)
		empty.BackgroundColor3 = C.bgLight
		empty.BorderSizePixel = 0
		empty.LayoutOrder = order
		empty.Parent = achievementsTab
		Instance.new("UICorner", empty).CornerRadius = UDim.new(0, 14)

		local emptyTitle = Instance.new("TextLabel")
		emptyTitle.Size = UDim2.new(1, -24, 0, 20)
		emptyTitle.Position = UDim2.new(0, 12, 0, 16)
		emptyTitle.BackgroundTransparency = 1
		emptyTitle.Text = "No chains match the current view."
		emptyTitle.TextColor3 = C.text
		emptyTitle.Font = Enum.Font.GothamBlack
		emptyTitle.TextSize = 14
		emptyTitle.TextXAlignment = Enum.TextXAlignment.Left
		emptyTitle.Parent = empty

		local emptyBody = Instance.new("TextLabel")
		emptyBody.Size = UDim2.new(1, -24, 0, 34)
		emptyBody.Position = UDim2.new(0, 12, 0, 42)
		emptyBody.BackgroundTransparency = 1
		emptyBody.Text = "Try another category or filter to browse the rest of the achievement ledger."
		emptyBody.TextColor3 = C.textSec
		emptyBody.Font = Enum.Font.GothamMedium
		emptyBody.TextSize = 11
		emptyBody.TextWrapped = true
		emptyBody.TextXAlignment = Enum.TextXAlignment.Left
		emptyBody.TextYAlignment = Enum.TextYAlignment.Top
		emptyBody.Parent = empty
	end
end

if achievementProgress and achievementProgress:IsA("RemoteEvent") then
	achievementProgress.OnClientEvent:Connect(function(entry)
		-- Avoid full UI rebuild on every progress tick; we rebuild on unlock.
		if isVis and activeTab == "Achievements" and type(entry) == "table" and entry.id then
			achievementCacheById[entry.id] = entry
			local card = achievementCardById[entry.id]
			if card then
				applyAchievementVisualState(card, entry)
			end
		end
	end)
end

achievementsTab:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if isVis and activeTab == "Achievements" then
		queueAchievementRefresh()
	end
end)

local currentRebirthData = nil

local function tryOpenRebirthConfirm()
	if not currentRebirthData then return end
	if not currentRebirthData.canRebirth then
		Notify.Toast(currentRebirthData.errorMessage or "Requirements not met", C.red, 3)
		return
	end
	overlay.Visible = true
end

function refreshRebirth()
	for _, ch in ipairs(rebirthScroll:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	if not getRebirthInfo or not getRebirthInfo:IsA("RemoteFunction") then
		mkSection(rebirthScroll, "Could not load rebirth data", 0)
		return
	end

	local ok, data = pcall(function() return getRebirthInfo:InvokeServer() end)
	if not ok or not data then
		mkSection(rebirthScroll, "Loading...", 0)
		return
	end
	currentRebirthData = data

	local rebirthLevel = data.rebirthLevel or 0
	local nextReq      = data.nextRequirements
	local canRebirth   = data.canRebirth
	local counts       = data.creatureCountsByRarity or {}
	local teamProgress = data.teamProgress or {}
	local keepFavorite = data.keepFavorite
	local loseCount    = data.loseCreaturesCount or 0
	local bonuses      = data.bonuses or {}
	local nextBonuses  = data.nextBonuses or {}

	local dashboard = Instance.new("Frame")
	dashboard.Name = "RebirthDashboard"
	dashboard.Size = UDim2.new(1, 0, 1, 0)
	dashboard.BackgroundTransparency = 1
	dashboard.LayoutOrder = 1
	dashboard.Parent = rebirthScroll

	local colGap = 10
	local topBlock = Instance.new("Frame")
	topBlock.Size = UDim2.new(1, 0, 0, 84)
	topBlock.BackgroundTransparency = 1
	topBlock.Parent = dashboard

	local mainTitle = Instance.new("TextLabel")
	mainTitle.Size = UDim2.new(1, 0, 0, 34)
	mainTitle.Position = UDim2.new(0, 0, 0, 4)
	mainTitle.BackgroundTransparency = 1
	mainTitle.Text = "SIEGEKNIGHT ASCENSION"
	mainTitle.TextColor3 = C.text
	mainTitle.Font = Enum.Font.GothamBlack
	mainTitle.TextSize = 18
	mainTitle.TextXAlignment = Enum.TextXAlignment.Center
	mainTitle.Parent = topBlock

	local levelPill = Instance.new("Frame")
	levelPill.Size = UDim2.new(0, 180, 0, 34)
	levelPill.Position = UDim2.new(0.5, -90, 0, 44)
	levelPill.BackgroundColor3 = C.bgLight
	levelPill.BorderSizePixel = 0
	levelPill.Parent = topBlock
	Instance.new("UICorner", levelPill).CornerRadius = UDim.new(1, 0)
	local levelStroke = Instance.new("UIStroke")
	levelStroke.Color = C.divider
	levelStroke.Thickness = 1
	levelStroke.Transparency = 0.2
	levelStroke.Parent = levelPill
	local levelLbl = Instance.new("TextLabel")
	levelLbl.Size = UDim2.new(1, -16, 1, 0)
	levelLbl.Position = UDim2.new(0, 8, 0, 0)
	levelLbl.BackgroundTransparency = 1
	levelLbl.Font = Enum.Font.GothamBold
	levelLbl.TextSize = 12
	levelLbl.TextXAlignment = Enum.TextXAlignment.Center
	levelLbl.TextColor3 = C.textSec
	levelLbl.Text = ("Rebirth Level  %d  ->  %d"):format(rebirthLevel, rebirthLevel + (nextReq and 1 or 0))
	levelLbl.Parent = levelPill

	local cols = Instance.new("Frame")
	cols.Size = UDim2.new(1, 0, 1, -92)
	cols.Position = UDim2.new(0, 0, 0, 92)
	cols.BackgroundTransparency = 1
	cols.Parent = dashboard

	local colsLayout = Instance.new("UIListLayout")
	colsLayout.FillDirection = Enum.FillDirection.Horizontal
	colsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	colsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	colsLayout.Padding = UDim.new(0, colGap)
	colsLayout.Parent = cols

	local colWidth = math.floor((rebirthTab.AbsoluteSize.X - 2 * colGap) / 3)
	colWidth = math.max(140, colWidth)
	local colHeight = math.max(360, rebirthTab.AbsoluteSize.Y - 118)

	local function mkCol(titleText, accentColor)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(0, colWidth, 0, colHeight)
		f.BackgroundColor3 = C.card
		f.BorderSizePixel = 0
		f.Parent = cols
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
		local st = Instance.new("UIStroke")
		st.Color = accentColor or C.divider
		st.Thickness = 1
		st.Transparency = 0.25
		st.Parent = f
		local h = Instance.new("TextLabel")
		h.Size = UDim2.new(1, -18, 0, 22)
		h.Position = UDim2.new(0, 9, 0, 10)
		h.BackgroundTransparency = 1
		h.Text = titleText
		h.TextColor3 = accentColor or C.text
		h.Font = Enum.Font.GothamBold
		h.TextSize = 12
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.Parent = f
		return f
	end

	-- LEFT: Requirements
	local reqCol = mkCol("📋  REQUIREMENTS", C.text)

	local goldNeed = nextReq and (nextReq.gold or 0) or 0
	local haveCoins = data.coins or 0
	local goldMet = haveCoins >= goldNeed
	local goldCard = Instance.new("Frame")
	goldCard.Size = UDim2.new(1, -22, 0, 58)
	goldCard.Position = UDim2.new(0, 11, 0, 44)
	goldCard.BackgroundColor3 = C.bgLight
	goldCard.BorderSizePixel = 0
	goldCard.Parent = reqCol
	Instance.new("UICorner", goldCard).CornerRadius = UDim.new(0, 8)
	local goldStroke = Instance.new("UIStroke")
	goldStroke.Color = goldMet and C.green or C.red
	goldStroke.Thickness = 1
	goldStroke.Transparency = 0.25
	goldStroke.Parent = goldCard
	local goldLabel = Instance.new("TextLabel")
	goldLabel.Size = UDim2.new(1, -18, 0, 16)
	goldLabel.Position = UDim2.new(0, 9, 0, 6)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Font = Enum.Font.GothamBold
	goldLabel.TextSize = 9
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.TextColor3 = C.textSec
	goldLabel.Text = "GOLD NEEDED"
	goldLabel.Parent = goldCard
	local goldValue = Instance.new("TextLabel")
	goldValue.Size = UDim2.new(1, -40, 0, 18)
	goldValue.Position = UDim2.new(0, 9, 0, 20)
	goldValue.BackgroundTransparency = 1
	goldValue.Font = Enum.Font.GothamBlack
	goldValue.TextSize = 16
	goldValue.TextXAlignment = Enum.TextXAlignment.Left
	goldValue.TextColor3 = goldMet and C.green or C.red
	goldValue.Text = "💰 " .. formatAbbrev(goldNeed)
	goldValue.Parent = goldCard
	local goldSub = Instance.new("TextLabel")
	goldSub.Size = UDim2.new(1, -40, 0, 12)
	goldSub.Position = UDim2.new(0, 9, 0, 40)
	goldSub.BackgroundTransparency = 1
	goldSub.Font = Enum.Font.GothamMedium
	goldSub.TextSize = 9
	goldSub.TextXAlignment = Enum.TextXAlignment.Left
	goldSub.TextColor3 = goldMet and C.green or C.textSec
	goldSub.Text = "You have: " .. formatAbbrev(haveCoins)
	goldSub.Parent = goldCard
	local goldCheck = Instance.new("TextLabel")
	goldCheck.Size = UDim2.new(0, 20, 0, 20)
	goldCheck.Position = UDim2.new(1, -26, 0, 18)
	goldCheck.BackgroundTransparency = 1
	goldCheck.Font = Enum.Font.GothamBlack
	goldCheck.TextSize = 15
	goldCheck.TextColor3 = goldMet and C.green or C.red
	goldCheck.Text = goldMet and "✓" or "✕"
	goldCheck.Parent = goldCard

	local teamCard = Instance.new("Frame")
	teamCard.Size = UDim2.new(1, -22, 0, 168)
	teamCard.Position = UDim2.new(0, 11, 0, 110)
	teamCard.BackgroundColor3 = C.bgLight
	teamCard.BorderSizePixel = 0
	teamCard.Parent = reqCol
	Instance.new("UICorner", teamCard).CornerRadius = UDim.new(0, 8)
	local teamStroke = Instance.new("UIStroke")
	teamStroke.Color = canRebirth and C.green or C.red
	teamStroke.Thickness = 1
	teamStroke.Transparency = 0.3
	teamStroke.Parent = teamCard
	local teamTitle = Instance.new("TextLabel")
	teamTitle.Size = UDim2.new(1, -16, 0, 16)
	teamTitle.Position = UDim2.new(0, 8, 0, 6)
	teamTitle.BackgroundTransparency = 1
	teamTitle.Text = "MAX LEVEL TEAM"
	teamTitle.TextColor3 = C.textSec
	teamTitle.Font = Enum.Font.GothamBold
	teamTitle.TextSize = 9
	teamTitle.TextXAlignment = Enum.TextXAlignment.Left
	teamTitle.Parent = teamCard

	local teamY = 24
	if nextReq and nextReq.team and type(nextReq.team) == "table" and #nextReq.team > 0 and #teamProgress > 0 then
		for _, slot in ipairs(teamProgress) do
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, -16, 0, 24)
			row.Position = UDim2.new(0, 8, 0, teamY)
			row.BackgroundTransparency = 1
			row.Font = Enum.Font.GothamBold
			row.TextSize = 11
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = C.text
			row.Text = tostring(slot.displayName or slot.creatureId or "?")
			row.Parent = teamCard
			local status = Instance.new("TextLabel")
			status.Size = UDim2.new(0, 86, 0, 24)
			status.Position = UDim2.new(1, -92, 0, teamY)
			status.BackgroundTransparency = 1
			status.Font = Enum.Font.GothamBold
			status.TextSize = 10
			status.TextXAlignment = Enum.TextXAlignment.Right
			status.TextColor3 = slot.haveAtMaxLevel and C.green or C.red
			status.Text = slot.haveAtMaxLevel and "✓ Max" or "✕ Need Max"
			status.Parent = teamCard
			teamY = teamY + 24
		end
	else
		local rarityY = 24
		for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary" }) do
			local need = nextReq and (nextReq.creatures or {})[rarity]
			if need and need > 0 then
				local have = counts[rarity] or 0
				local met = have >= need
				local row = Instance.new("TextLabel")
				row.Size = UDim2.new(1, -16, 0, 20)
				row.Position = UDim2.new(0, 8, 0, rarityY)
				row.BackgroundTransparency = 1
				row.Font = Enum.Font.GothamMedium
				row.TextSize = 10
				row.TextXAlignment = Enum.TextXAlignment.Left
				row.TextColor3 = RARITY_COLORS[rarity] or C.text
				row.Text = ("%s: %d/%d"):format(rarity, have, need)
				row.Parent = teamCard
				local check = Instance.new("TextLabel")
				check.Size = UDim2.new(0, 20, 0, 20)
				check.Position = UDim2.new(1, -24, 0, rarityY)
				check.BackgroundTransparency = 1
				check.Font = Enum.Font.GothamBold
				check.TextSize = 12
				check.TextColor3 = met and C.green or C.red
				check.Text = met and "✓" or "✕"
				check.Parent = teamCard
				rarityY = rarityY + 20
			end
		end
	end

	-- CENTER: Sacrifice
	local sacCol = mkCol("⚖️  THE SACRIFICE", C.text)
	local keepHdr = Instance.new("TextLabel")
	keepHdr.Size = UDim2.new(1, -22, 0, 16)
	keepHdr.Position = UDim2.new(0, 11, 0, 44)
	keepHdr.BackgroundTransparency = 1
	keepHdr.Text = "WHAT YOU KEEP"
	keepHdr.TextColor3 = C.green
	keepHdr.Font = Enum.Font.GothamBlack
	keepHdr.TextSize = 10
	keepHdr.TextXAlignment = Enum.TextXAlignment.Left
	keepHdr.Parent = sacCol
	local keepCard = Instance.new("Frame")
	keepCard.Size = UDim2.new(1, -22, 0, 62)
	keepCard.Position = UDim2.new(0, 11, 0, 62)
	keepCard.BackgroundColor3 = Color3.fromRGB(20, 57, 49)
	keepCard.BorderSizePixel = 0
	keepCard.Parent = sacCol
	Instance.new("UICorner", keepCard).CornerRadius = UDim.new(0, 8)
	local keepStroke = Instance.new("UIStroke")
	keepStroke.Color = C.green
	keepStroke.Thickness = 1
	keepStroke.Transparency = 0.3
	keepStroke.Parent = keepCard
	local favIcon = Instance.new("Frame")
	favIcon.Size = UDim2.new(0, 34, 0, 34)
	favIcon.Position = UDim2.new(0, 10, 0, 14)
	favIcon.BackgroundColor3 = Color3.fromRGB(14, 20, 28)
	favIcon.BorderSizePixel = 0
	favIcon.Parent = keepCard
	Instance.new("UICorner", favIcon).CornerRadius = UDim.new(0, 8)
	local favTxt = Instance.new("TextLabel")
	favTxt.Size = UDim2.new(1, 0, 1, 0)
	favTxt.BackgroundTransparency = 1
	favTxt.Font = Enum.Font.GothamBlack
	favTxt.TextSize = 16
	favTxt.Text = keepFavorite and string.sub(tostring(keepFavorite.name or "?"), 1, 1) or "?"
	favTxt.TextColor3 = C.text
	favTxt.Parent = favIcon
	local keepLbl = Instance.new("TextLabel")
	keepLbl.Size = UDim2.new(1, -56, 0, 16)
	keepLbl.Position = UDim2.new(0, 50, 0, 16)
	keepLbl.BackgroundTransparency = 1
	keepLbl.Text = "EQUIPPED FAVORITE"
	keepLbl.TextColor3 = C.green
	keepLbl.Font = Enum.Font.GothamBold
	keepLbl.TextSize = 10
	keepLbl.TextXAlignment = Enum.TextXAlignment.Left
	keepLbl.Parent = keepCard
	local keepName = Instance.new("TextLabel")
	keepName.Size = UDim2.new(1, -56, 0, 18)
	keepName.Position = UDim2.new(0, 50, 0, 32)
	keepName.BackgroundTransparency = 1
	keepName.Text = keepFavorite and (keepFavorite.name or "?") or "None"
	keepName.TextColor3 = C.text
	keepName.Font = Enum.Font.GothamBlack
	keepName.TextSize = 18 > colWidth and 12 or 14
	keepName.TextXAlignment = Enum.TextXAlignment.Left
	keepName.TextTruncate = Enum.TextTruncate.AtEnd
	keepName.Parent = keepCard

	local loseHdr = Instance.new("TextLabel")
	loseHdr.Size = UDim2.new(1, -22, 0, 16)
	loseHdr.Position = UDim2.new(0, 11, 1, -108)
	loseHdr.BackgroundTransparency = 1
	loseHdr.Text = "WHAT YOU LOSE"
	loseHdr.TextColor3 = C.red
	loseHdr.Font = Enum.Font.GothamBlack
	loseHdr.TextSize = 10
	loseHdr.TextXAlignment = Enum.TextXAlignment.Left
	loseHdr.Parent = sacCol
	local loseCard = Instance.new("Frame")
	loseCard.Size = UDim2.new(1, -22, 0, 78)
	loseCard.Position = UDim2.new(0, 11, 1, -88)
	loseCard.BackgroundColor3 = Color3.fromRGB(50, 22, 30)
	loseCard.BorderSizePixel = 0
	loseCard.Parent = sacCol
	Instance.new("UICorner", loseCard).CornerRadius = UDim.new(0, 8)
	local loseStroke = Instance.new("UIStroke")
	loseStroke.Color = C.red
	loseStroke.Thickness = 1
	loseStroke.Transparency = 0.35
	loseStroke.Parent = loseCard
	local loseRow1 = Instance.new("TextLabel")
	loseRow1.Size = UDim2.new(1, -16, 0, 28)
	loseRow1.Position = UDim2.new(0, 8, 0, 8)
	loseRow1.BackgroundTransparency = 1
	loseRow1.Text = ("⚠️  Creatures removed                      %d"):format(loseCount)
	loseRow1.TextColor3 = C.text
	loseRow1.Font = Enum.Font.GothamBold
	loseRow1.TextSize = 11
	loseRow1.TextXAlignment = Enum.TextXAlignment.Left
	loseRow1.Parent = loseCard
	local loseBattle = data.loseBattleCount or 0
	local loseRow2 = Instance.new("TextLabel")
	loseRow2.Size = UDim2.new(1, -16, 0, 28)
	loseRow2.Position = UDim2.new(0, 8, 0, 36)
	loseRow2.BackgroundTransparency = 1
	loseRow2.Text = ("⚠️  From battle team                          %d"):format(loseBattle)
	loseRow2.TextColor3 = C.text
	loseRow2.Font = Enum.Font.GothamBold
	loseRow2.TextSize = 11
	loseRow2.TextXAlignment = Enum.TextXAlignment.Left
	loseRow2.Parent = loseCard

	-- RIGHT: Rewards / action
	local ascCol = mkCol("✨  ASCENSION REWARDS", C.gold)
	local glow = Instance.new("Frame")
	glow.Size = UDim2.new(1, -8, 1, -8)
	glow.Position = UDim2.new(0, 4, 0, 4)
	glow.BackgroundColor3 = C.gold
	glow.BackgroundTransparency = 0.94
	glow.BorderSizePixel = 0
	glow.ZIndex = 0
	glow.Parent = ascCol
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 10)
	local glowGrad = Instance.new("UIGradient")
	glowGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 145, 40)),
	})
	glowGrad.Rotation = 40
	glowGrad.Parent = glow

	local function mkRewardRow(y, icon, text, value, valColor)
		local r = Instance.new("Frame")
		r.Size = UDim2.new(1, -22, 0, 38)
		r.Position = UDim2.new(0, 11, 0, y)
		r.BackgroundColor3 = C.bgLight
		r.BorderSizePixel = 0
		r.Parent = ascCol
		Instance.new("UICorner", r).CornerRadius = UDim.new(0, 8)
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.new(0, 18, 1, 0)
		tl.Position = UDim2.new(0, 8, 0, 0)
		tl.BackgroundTransparency = 1
		tl.Text = icon
		tl.Font = Enum.Font.GothamBold
		tl.TextSize = 12
		tl.TextXAlignment = Enum.TextXAlignment.Center
		tl.TextColor3 = C.text
		tl.Parent = r
		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, -78, 1, 0)
		txt.Position = UDim2.new(0, 28, 0, 0)
		txt.BackgroundTransparency = 1
		txt.Text = text
		txt.Font = Enum.Font.GothamBold
		txt.TextSize = 11
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextColor3 = C.text
		txt.Parent = r
		local vv = Instance.new("TextLabel")
		vv.Size = UDim2.new(0, 42, 1, 0)
		vv.Position = UDim2.new(1, -48, 0, 0)
		vv.BackgroundTransparency = 1
		vv.Text = value
		vv.Font = Enum.Font.GothamBlack
		vv.TextSize = 20 > colWidth and 12 or 15
		vv.TextXAlignment = Enum.TextXAlignment.Right
		vv.TextColor3 = valColor
		vv.Parent = r
	end

	local rewardPassive = nextBonuses.passiveGold or bonuses.passiveGold or 0
	local rewardHP = nextBonuses.healthBonus or bonuses.healthBonus or 0
	local rewardDmg = nextBonuses.damageMultiplier or bonuses.damageMultiplier or 1
	mkRewardRow(52, "🪙", "Passive gold/tick", "+" .. tostring(rewardPassive), C.gold)
	mkRewardRow(96, "💚", "Bonus max health", "+" .. tostring(rewardHP), C.green)
	mkRewardRow(140, "⚔️", "World damage", "+" .. string.format("%.0f%%", math.max(0, (rewardDmg - 1) * 100)), C.blue)

	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "AscendButton"
	actionBtn.Size = UDim2.new(1, -22, 0, 50)
	actionBtn.Position = UDim2.new(0, 11, 1, -64)
	actionBtn.BackgroundColor3 = canRebirth and C.rebirthAccent or C.divider
	actionBtn.TextColor3 = canRebirth and Color3.new(0.2, 0.15, 0.1) or C.textMut
	actionBtn.Font = Enum.Font.GothamBlack
	actionBtn.TextSize = 17 > colWidth and 12 or 14
	actionBtn.Text = canRebirth and "ASCEND NOW" or "REBIRTH LOCKED"
	actionBtn.BorderSizePixel = 0
	actionBtn.Parent = ascCol
	Instance.new("UICorner", actionBtn).CornerRadius = UDim.new(0, 8)
	actionBtn.MouseButton1Click:Connect(tryOpenRebirthConfirm)

	local actionSub = Instance.new("TextLabel")
	actionSub.Size = UDim2.new(1, -22, 0, 12)
	actionSub.Position = UDim2.new(0, 11, 1, -14)
	actionSub.BackgroundTransparency = 1
	actionSub.Font = Enum.Font.GothamBold
	actionSub.TextSize = 9
	actionSub.TextXAlignment = Enum.TextXAlignment.Center
	actionSub.TextColor3 = canRebirth and C.green or C.red
	actionSub.Text = canRebirth and "ALL REQUIREMENTS MET" or "REQUIREMENTS NOT MET"
	actionSub.Parent = ascCol

	rebirthBtn.Visible = false
end

-- Rebirth button + confirmation
rebirthBtn.MouseButton1Click:Connect(function()
	tryOpenRebirthConfirm()
end)

confirmNoBtn.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)

confirmYesBtn.MouseButton1Click:Connect(function()
	overlay.Visible = false
	if not requestRebirth or not requestRebirth:IsA("RemoteEvent") then return end
	requestRebirth:FireServer()
	closeUI()
end)

-- Rebirth success/failure events
if rebirthSuccess then
	rebirthSuccess.OnClientEvent:Connect(function(newLevel)
		Notify.Toast("Rebirth " .. tostring(newLevel) .. "! Passive gold, damage & health increased.", C.green, 4)
	end)
end
if rebirthFailed then
	rebirthFailed.OnClientEvent:Connect(function(msg)
		Notify.Toast(msg or "Rebirth failed", C.red, 3)
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Open / Close / Toggle
-- ══════════════════════════════════════════════════════════════════════════════

isVis = false

local function applyMobileScale()
	syncProfileScreenGuiInset()
	local w, h, sbWidth = getScaledDims()
	if profileUsesFullscreenBounds() then
		MobileWindowLayout.ApplyWindow(main, profileGetBoundsConfig())
		main.Draggable = false
		profileBody.FillDirection = Enum.FillDirection.Horizontal
		profileBody.Padding = UDim.new(0, 10)
		leftCol.Size = UDim2.new(1, -sbWidth - 10, 1, -8)
		rightSidebar.Size = UDim2.new(0, sbWidth, 1, -8)
		closeBtn.Size = UDim2.new(0, 36, 0, 36)
		closeBtn.Position = UDim2.new(1, -44, 0, 6)
		closeBtn.TextSize = 15
		applyProfileHeaderTitleLayout()
		applyProfileSidebarLayout()
		return
	end
	main.Size = UDim2.new(0, w, 0, h)
	main.Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2)
	leftCol.Size = UDim2.new(1, -sbWidth - 40, 1, -8)
	rightSidebar.Size = UDim2.new(0, sbWidth, 1, -8)
	profileBody.FillDirection = Enum.FillDirection.Horizontal
	profileBody.Padding = UDim.new(0, 12)
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -38, 0, 9)
	closeBtn.TextSize = 13
	MobileWindowLayout.RestoreDesktopWindow(main, { draggable = true })
	applyProfileHeaderTitleLayout()
	applyProfileSidebarLayout()
end

local function openUI(tabName)
	isVis = true
	applyMobileScale()
	main.Visible = true
	MobileWindowLayout.NotifyMenuOpened()

	-- Animate open
	local w, h = getScaledDims()
	main.Size = UDim2.new(0, w, 0, 10)
	TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, w, 0, h)
	}):Play()

	switchTab(tabName or activeTab or "Profile")
end

local function closeUI()
	overlay.Visible = false
	local w, h = getScaledDims()
	TweenService:Create(main, TweenInfo.new(0.12), { Size = UDim2.new(0, w, 0, 10) }):Play()
	task.delay(0.13, function()
		isVis = false
		main.Visible = false
		MobileWindowLayout.NotifyMenuClosed()
		applyMobileScale()
	end)
end

closeBtn.MouseButton1Click:Connect(closeUI)

-- ══════════════════════════════════════════════════════════════════════════════
-- HUD toggle (handles all three old menu names for backward compat)
-- ══════════════════════════════════════════════════════════════════════════════

local function getHUDToggle()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if not evt or not evt:IsA("BindableEvent") then
		evt = Instance.new("BindableEvent")
		evt.Name = "HUDToggleMenu"
		evt.Parent = playerGui
	end
	return evt
end

--- Maps old menu names to tab names for backward compatibility.
local MENU_TO_TAB = {
	ProfileGUI       = "Profile",
	BossBackboardGUI = "Sigils",   -- FIX #34: old Sigils standalone menu
	RebirthUI        = "Rebirth",  -- FIX #34: old Rebirth standalone menu
}

local function onHUDToggle(menuName)
	local tab = MENU_TO_TAB[menuName]
	if not tab then return end

	if isVis and activeTab == tab then
		-- Same tab already open → close
		closeUI()
	elseif isVis then
		-- Different tab → switch (don't close)
		switchTab(tab)
	else
		-- Closed → open to this tab
		openUI(tab)
	end
end

getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then
		child.Event:Connect(onHUDToggle)
	end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if isVis then
		applyMobileScale()
	else
		syncProfileScreenGuiInset()
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- Event listeners
-- ══════════════════════════════════════════════════════════════════════════════

-- Level up notification
if playerLevelUp then
	playerLevelUp.OnClientEvent:Connect(function(newLevel)
		Notify.Banner("LEVEL UP! You are now Level " .. newLevel .. "!", C.xpBar, 4)
		if isVis and activeTab == "Profile" then task.wait(0.5); refreshProfile() end
	end)
end

-- Sigil earned → auto-refresh sigils tab if visible
if sigilEarned and sigilEarned:IsA("RemoteEvent") then
	sigilEarned.OnClientEvent:Connect(function()
		if isVis and activeTab == "Sigils" then refreshSigils() end
	end)
end

-- Occasional full resync while Profile is open (coin/gems use economy row updates above)
task.spawn(function()
	while true do
		task.wait(90)
		if isVis and activeTab == "Profile" then refreshProfile() end
	end
end)

-- Initialize default tab state (Profile active, others hidden)
switchTab("Profile")

task.defer(syncProfileScreenGuiInset)
print("[PlayerProfileClient] Loaded — tabbed Profile/Sigils/Rebirth menu (press P)")
