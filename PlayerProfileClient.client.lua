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
sg.DisplayOrder = 16
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
sidebarTitle.Text = "BASE FLOORS"
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
sigilsTab.AutomaticCanvasSize = Enum.AutomaticSize.Y
sigilsTab.CanvasSize = UDim2.new(0, 0, 0, 0)
sigilsTab.Visible = false
sigilsTab.Parent = main

local sigilsLayout = Instance.new("UIListLayout")
sigilsLayout.SortOrder = Enum.SortOrder.LayoutOrder
sigilsLayout.Padding = UDim.new(0, 10)
sigilsLayout.Parent = sigilsTab

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
rebirthScroll.Size = UDim2.new(1, 0, 1, -60)
rebirthScroll.BackgroundTransparency = 1
rebirthScroll.BorderSizePixel = 0
rebirthScroll.ScrollBarThickness = 4
rebirthScroll.ScrollBarImageColor3 = C.divider
rebirthScroll.ScrollingDirection = Enum.ScrollingDirection.Y
rebirthScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rebirthScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
rebirthScroll.Parent = rebirthTab

local rebirthLayout = Instance.new("UIListLayout")
rebirthLayout.SortOrder = Enum.SortOrder.LayoutOrder
rebirthLayout.Padding = UDim.new(0, 8)
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
		title.Text = "PILOT REBIRTH"
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

-- Live economy row refs (avoid full profile rebuild on every coin tick)
local profileCoinsValueLbl = nil
local profileGemsValueLbl = nil

local function clearProfileEconomyRefs()
	profileCoinsValueLbl = nil
	profileGemsValueLbl = nil
end

local function updateProfileEconomyDisplay(coins, gems)
	if profileCoinsValueLbl and coins ~= nil then
		profileCoinsValueLbl.Text = tostring(coins)
	end
	if profileGemsValueLbl and gems ~= nil then
		profileGemsValueLbl.Text = tostring(gems)
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
	sidebarTitle.Text = "BASE FLOORS"

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
	mkSection(economyBlock, "ECONOMY", 10)
	do
		local _, coinsVal = mkStatRow(economyBlock, "Coins", tostring(data.coins or 0), C.gold, 11)
		local _, gemsVal = mkStatRow(economyBlock, "Gems", tostring(data.gems or 0), C.blue, 12)
		profileCoinsValueLbl = coinsVal
		profileGemsValueLbl = gemsVal
	end

	-- Lifetime / progression (not pilot combat — avoids mixing with ATK/DEF/HP rows)
	local statBlock = mkSectionFrame(leftCol, 200)
	mkSection(statBlock, "PROGRESS", 10)
	mkStatRow(statBlock, "Monsters Owned", tostring(data.monstersOwned or 0), C.text, 11)
	mkStatRow(statBlock, "Total Captured", tostring(data.totalCaptured or 0), C.green, 12)
	mkStatRow(statBlock, "Arena Wins", tostring(data.arenaWins or 0), C.gold, 13)
	mkStatRow(statBlock, "Max Win Streak", tostring(data.arenaMaxStreak or 0), Color3.fromRGB(255, 130, 50), 14)
	mkStatRow(statBlock, "Total Income Earned", tostring(data.totalIncome or 0), C.gold, 15)

	-- Base Floors
	local ownedFloors = data.ownedFloors or { 1 }
	local function ownsFloor(n)
		for _, f in ipairs(ownedFloors) do if f == n then return true end end
		return false
	end

	-- Pilot combat — own section before base floors (scroll order); never a sibling between floor rows.
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

		mkSection(pilotInner, "PILOT COMBAT STATS", 10)
		mkStatRow(pilotInner, "ATK", tostring(pc.attack), Color3.fromRGB(255, 100, 80), 11)
		mkStatRow(pilotInner, "DEF", tostring(pc.defense), Color3.fromRGB(80, 150, 255), 12)
		mkStatRow(pilotInner, "Health (max)", tostring(pc.maxHealth), Color3.fromRGB(90, 220, 120), 13)
		mkStatRow(pilotInner, "Speed (walk / sprint)", ("%d / %d studs/s"):format(pc.walkSpeed, pc.sprintSpeed), C.text, 14)
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
		mkSection(floorsParent, "BASE FLOORS", 10)
	end

	local unlockHint = Instance.new("TextLabel")
	unlockHint.Size = UDim2.new(1, 0, 0, 0)
	unlockHint.AutomaticSize = Enum.AutomaticSize.Y
	unlockHint.BackgroundTransparency = 1
	unlockHint.Text = "Each floor adds space and a siege title. Floor 2 — Siege Squire (Battles & battle team). Floor 3 — Siege Knight (teleporters, Recycler, and Combiners). Floor 4 — Siegelord (Siegelord Arena)."
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

		local fName = Instance.new("TextLabel")
		fName.Size = UDim2.new(1, -12, 0, 18)
		fName.Position = UDim2.new(0, 8, 0, 4)
		fName.BackgroundTransparency = 1
		fName.Text = FLOOR_DISPLAY_NAMES[floorNum] or ("Floor " .. floorNum)
		fName.TextColor3 = owned and C.green or C.textMut
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
			fStatus.Text = owned and "OWNED" or "STARTER"
			fStatus.TextColor3 = C.green
		else
			fBenefit.Size = UDim2.new(1, -16, 0, 22)
			fBenefit.Position = UDim2.new(0, 8, 0, 22)

			local floorCfg = FLOOR_UI_CONFIG[floorNum] or { cost = 0, levelReq = 1 }
			local reqLvl = floorCfg.levelReq
			local cost = floorCfg.cost
			local meetsLevel = lvl >= reqLvl
			local meetsPrereq = (not floorCfg.prereq) or ownsFloor(floorCfg.prereq)

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
			if floorCfg.prereq and not ownsFloor(floorCfg.prereq) then
				prereqText = " + Floor " .. floorCfg.prereq
			end
			lvlLbl.Text = "Requires Level " .. reqLvl .. prereqText
			lvlLbl.TextColor3 = meetsLevel and C.green or C.textMut
			lvlLbl.Parent = floorRow

			local canBuy = meetsLevel and meetsPrereq and (data.coins or 0) >= cost
			local buyBtn2 = Instance.new("TextButton")
			buyBtn2.Size = UDim2.new(1, -16, 0, 22)
			buyBtn2.Position = UDim2.new(0, 8, 0, 74)
			buyBtn2.BackgroundColor3 = canBuy and C.green or C.divider
			buyBtn2.Text = canBuy and ("BUY - " .. cost .. " Coins") or "BUY"
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
-- Sigils tab refresh (ported from BossBackboardClient)
-- ══════════════════════════════════════════════════════════════════════════════

local function getBossDisplayName(element)
	local bossId = CreatureData.GetBossCreatureId and CreatureData.GetBossCreatureId(element, false)
	if not bossId then return element .. " Boss" end
	local creature = CreatureData.GetById and CreatureData.GetById(bossId)
	if creature and creature.displayName then return creature.displayName end
	return element .. " Boss"
end

local function addSigilRow(parent, layoutOrder, elementLabel, bossName, statusText, statusColor)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = C.card
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.ClipsDescendants = true
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
	row.Parent = parent

	-- Gradient tint
	local tint = Instance.new("Frame")
	tint.Size = UDim2.new(1, 0, 1, 0)
	tint.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tint.BackgroundTransparency = 0.92
	tint.BorderSizePixel = 0
	tint.ZIndex = 0
	tint.Parent = row
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 130, 160)),
	})
	grad.Rotation = 90
	grad.Parent = tint

	-- Watermark
	local watermark = Instance.new("TextLabel")
	watermark.Size = UDim2.new(1, -24, 1, 0)
	watermark.Position = UDim2.new(0, 12, 0, 0)
	watermark.BackgroundTransparency = 1
	watermark.RichText = true
	watermark.Text = bossName and ("<i>" .. bossName .. "</i>") or ""
	watermark.Visible = bossName ~= nil and bossName ~= ""
	watermark.TextColor3 = C.textSec
	watermark.TextTransparency = 0.92
	watermark.Font = Enum.Font.GothamBlack
	watermark.TextScaled = true
	watermark.TextXAlignment = Enum.TextXAlignment.Center
	watermark.ZIndex = 1
	watermark.Parent = row

	-- Element label
	local elem = Instance.new("TextLabel")
	elem.Size = UDim2.new(0, 72, 0, 18)
	elem.Position = UDim2.new(0, 12, 0, 10)
	elem.BackgroundTransparency = 1
	elem.Text = tostring(elementLabel or "")
	elem.TextColor3 = C.text
	elem.Font = Enum.Font.GothamBold
	elem.TextSize = 12
	elem.TextXAlignment = Enum.TextXAlignment.Left
	elem.ZIndex = 3
	elem.Parent = row

	-- Boss name
	local bossLbl = Instance.new("TextLabel")
	bossLbl.Size = UDim2.new(1, -190, 0, 18)
	bossLbl.Position = UDim2.new(0, 88, 0, 10)
	bossLbl.BackgroundTransparency = 1
	bossLbl.Text = tostring(bossName or "")
	bossLbl.TextColor3 = C.textSec
	bossLbl.Font = Enum.Font.GothamMedium
	bossLbl.TextSize = 11
	bossLbl.TextXAlignment = Enum.TextXAlignment.Left
	bossLbl.TextTruncate = Enum.TextTruncate.AtEnd
	bossLbl.ZIndex = 3
	bossLbl.Parent = row

	-- Status pill
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(0, 118, 0, 26)
	pill.Position = UDim2.new(1, -130, 0.5, -13)
	pill.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.ZIndex = 3
	pill.Parent = row
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Color = C.divider
	pillStroke.Thickness = 1
	pillStroke.Transparency = 0.35
	pillStroke.Parent = pill

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size = UDim2.new(1, -16, 1, 0)
	statusLbl.Position = UDim2.new(0, 8, 0, 0)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Text = tostring(statusText or "")
	statusLbl.TextColor3 = statusColor or C.textMut
	statusLbl.Font = Enum.Font.GothamMedium
	statusLbl.TextSize = 11
	statusLbl.TextXAlignment = Enum.TextXAlignment.Center
	statusLbl.ZIndex = 4
	statusLbl.Parent = pill
end

function refreshSigils()
	for _, child in ipairs(sigilsTab:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
	end

	local sigils = {}
	if getInventory and getInventory:IsA("RemoteFunction") then
		local ok, data = pcall(function() return getInventory:InvokeServer() end)
		if ok and data then sigils = data.sigils or {} end
	end

	local function hasSigil(zoneId)
		return sigils[zoneId] == true or sigils[zoneId] == "true"
	end

	local order = 0

	-- SiegeSquire Sigils
	order = order + 1
	mkSection(sigilsTab, "SiegeSquire Sigils", order)
	for _, element in ipairs(ELEMENTAL_ELEMENTS) do
		order = order + 1
		local defeated = hasSigil(element)
		addSigilRow(sigilsTab, order, element, getBossDisplayName(element),
			defeated and "Defeated" or "Not defeated",
			defeated and C.income or C.textMut)
	end

	order = order + 1  -- gap

	-- SiegeKnight Sigils
	order = order + 1
	mkSection(sigilsTab, "SiegeKnight Sigils", order)
	for i, label in ipairs(SIEGE_LABELS) do
		order = order + 1
		local zoneId = SIEGE_ZONE_IDS and SIEGE_ZONE_IDS[i] or label
		local earned = hasSigil(zoneId)
		addSigilRow(sigilsTab, order, label, "Zone sigil",
			earned and "Earned" or "Not earned",
			earned and C.income or C.textMut)
	end

	order = order + 1  -- gap

	-- SiegeLord Sigils
	order = order + 1
	mkSection(sigilsTab, "SiegeLord Sigils", order)
	order = order + 1
	local lordEarned = hasSigil(SIEGE_LORD_ZONE_ID)
	addSigilRow(sigilsTab, order, "Badlands", SIEGE_LORD_SUB,
		lordEarned and "Earned" or "Not earned",
		lordEarned and C.income or C.textMut)

	-- Hint
	order = order + 1
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 36)
	hint.BackgroundTransparency = 1
	hint.Text = GameConfig.ZoneDoorModalSigilsHint
		or "Inner zones: defeat Legendary Siegelings for SiegeSquire Sigils (one per element). Exterior: win each zone Gym for SiegeKnight Sigils — four unlock a Biome Pass; each Gym also awards a pass for another gate. SiegeLord: complete a successful Badlands extraction to earn your SiegeLord Sigil."
	hint.TextColor3 = C.textMut
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 10
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.LayoutOrder = order
	hint.Parent = sigilsTab
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

	-- Current rebirth
	mkSection(rebirthScroll, "CURRENT REBIRTH", 0)
	mkStatRow(rebirthScroll, "Rebirth Level", rebirthLevel, C.rebirthAccent, 1)
	if bonuses.passiveGold and bonuses.passiveGold > 0 then
		mkStatRow(rebirthScroll, "Passive gold/tick", "+" .. tostring(bonuses.passiveGold), C.gold, 2)
	end
	if bonuses.healthBonus and bonuses.healthBonus > 0 then
		mkStatRow(rebirthScroll, "Bonus max health", "+" .. tostring(bonuses.healthBonus), C.green, 3)
	end
	if bonuses.damageMultiplier and bonuses.damageMultiplier > 1 then
		mkStatRow(rebirthScroll, "World damage", string.format("%.0f%%", (bonuses.damageMultiplier - 1) * 100), C.blue, 4)
	end

	-- Requirements
	mkSection(rebirthScroll, "REQUIREMENTS FOR NEXT REBIRTH", 10)
	if not nextReq then
		mkStatRow(rebirthScroll, "Status", "Max rebirth level reached", C.textMut, 11)
	else
		mkStatRow(rebirthScroll, "Gold needed",
			(nextReq.gold or 0) .. " (you have " .. tostring(data.coins or 0) .. ")",
			(data.coins or 0) >= (nextReq.gold or 0) and C.green or C.red, 11)

		local reqOrder = 12
		if nextReq.team and type(nextReq.team) == "table" and #nextReq.team > 0 and #teamProgress > 0 then
			for i, slot in ipairs(teamProgress) do
				local status = slot.haveAtMaxLevel and "\226\156\147 Max" or "\226\156\151 Need max"
				local color = slot.haveAtMaxLevel and C.green or C.red
				mkStatRow(rebirthScroll, "Slot " .. i .. ": " .. (slot.displayName or slot.creatureId), status, color, reqOrder)
				reqOrder = reqOrder + 1
			end
		else
			for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary" }) do
				local need = (nextReq.creatures or {})[rarity]
				if need and need > 0 then
					local have = counts[rarity] or 0
					local met = have >= need
					mkStatRow(rebirthScroll, rarity .. " creatures", have .. " / " .. need,
						met and (RARITY_COLORS[rarity] or C.text) or C.red, reqOrder)
					reqOrder = reqOrder + 1
				end
			end
		end
	end

	-- What you keep
	mkSection(rebirthScroll, "YOU KEEP", 20)
	if keepFavorite then
		local rc = RARITY_COLORS[keepFavorite.rarity] or C.text
		mkStatRow(rebirthScroll, "Favorite (equipped)", keepFavorite.name or "?", rc, 21)
	else
		mkStatRow(rebirthScroll, "Favorite (equipped)", "None", C.textMut, 21)
	end

	-- What you lose
	mkSection(rebirthScroll, "YOU LOSE", 30)
	mkStatRow(rebirthScroll, "Creatures removed", loseCount, C.red, 31)
	if (data.loseBaseCount or 0) > 0 then
		mkStatRow(rebirthScroll, "From base (income)", data.loseBaseCount, C.textSec, 32)
	end
	if (data.loseDefenseCount or 0) > 0 then
		mkStatRow(rebirthScroll, "From base (defense)", data.loseDefenseCount, C.textSec, 33)
	end
	if (data.loseBattleCount or 0) > 0 then
		mkStatRow(rebirthScroll, "From battle team", data.loseBattleCount, C.textSec, 34)
	end

	-- Rewards after rebirth
	if nextBonuses and nextBonuses.passiveGold then
		mkSection(rebirthScroll, "REWARDS AFTER REBIRTH", 40)
		mkStatRow(rebirthScroll, "Passive gold/tick", "+" .. tostring(nextBonuses.passiveGold), C.gold, 41)
		if nextBonuses.healthBonus and nextBonuses.healthBonus > 0 then
			mkStatRow(rebirthScroll, "Bonus max health", "+" .. tostring(nextBonuses.healthBonus), C.green, 42)
		end
		if nextBonuses.damageMultiplier and nextBonuses.damageMultiplier > 1 then
			mkStatRow(rebirthScroll, "World damage", string.format("%.0f%%", (nextBonuses.damageMultiplier - 1) * 100), C.blue, 43)
		end
	end

	-- Button state
	rebirthBtn.Visible = nextReq ~= nil
	if rebirthBtn.Visible then
		rebirthBtn.BackgroundColor3 = canRebirth and C.rebirthAccent or C.divider
		rebirthBtn.Text = canRebirth and "REBIRTH" or "REBIRTH (requirements not met)"
		rebirthBtn.TextColor3 = canRebirth and Color3.new(0.2, 0.15, 0.1) or C.textMut
	end
end

-- Rebirth button + confirmation
rebirthBtn.MouseButton1Click:Connect(function()
	if not currentRebirthData then return end
	if not currentRebirthData.canRebirth then
		Notify.Toast(currentRebirthData.errorMessage or "Requirements not met", C.red, 3)
		return
	end
	overlay.Visible = true
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
