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
local ELEMENTAL_TO_ZONE  = GameConfig.ElementalBossToZoneId or { Fire = "Desert", Ice = "Cave", Wind = "Ocean", Earth = "Electric" }
local SIEGE_LABELS       = GameConfig.SiegeKnightSigilLabels or { "Desert", "Cave", "Ocean", "Cyber" }
local SIEGE_ZONE_IDS     = GameConfig.SiegeKnightSigilZoneIds or { "Desert", "Cave", "Ocean", "Electric" }

-- ══════════════════════════════════════════════════════════════════════════════
-- Layout constants
-- ══════════════════════════════════════════════════════════════════════════════

local PANEL_DESIGN_W   = 775
local PANEL_DESIGN_H   = 560   -- slightly taller for tab bar
local SIDEBAR_DESIGN_W = 200
local PANEL_SCALE_MIN  = 0.55
local PANEL_SCALE_MAX  = 1
local TAB_BAR_HEIGHT   = 36
local HEADER_HEIGHT    = 48

local function getPanelScale()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local s = math.min(vp.X / PANEL_DESIGN_W, vp.Y / PANEL_DESIGN_H)
	return math.clamp(s, PANEL_SCALE_MIN, PANEL_SCALE_MAX)
end

local function getScaledDims()
	if MobileWindowLayout.IsMobile() then
		local bounds = MobileWindowLayout.GetBounds({
			leftInset = 14, rightInset = 14, topInset = 10,
			bottomInset = 14, bottomMobileExtra = 20,
		})
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

	-- Update header title per tab
	if tabName == "Profile" then
		title.Text = "PLAYER PROFILE"
		title.TextColor3 = C.accent
	elseif tabName == "Sigils" then
		title.Text = "COUNCIL OF HOUSES — SIGILS"
		title.TextColor3 = C.sigilAccent
	elseif tabName == "Rebirth" then
		title.Text = "PILOT REBIRTH"
		title.TextColor3 = C.rebirthAccent
	elseif tabName == "Achievements" then
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
	val.Size = UDim2.new(0.4, -12, 1, 0)
	val.Position = UDim2.new(0.6, 0, 0, 0)
	val.BackgroundTransparency = 1
	val.Text = tostring(value)
	val.TextColor3 = color or C.text
	val.Font = Enum.Font.GothamBold
	val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = row
	return row
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Profile tab refresh
-- ══════════════════════════════════════════════════════════════════════════════

function refreshProfile()
	-- Clear left column
	for _, ch in ipairs(leftCol:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end
	-- Clear sidebar
	for _, ch in ipairs(sidebarContent:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end
	sidebarTitle.Text = MobileWindowLayout.IsMobile() and "DETAILS" or "BASE FLOORS"

	if not getProfile then return end
	local ok, data = pcall(function() return getProfile:InvokeServer() end)
	if not ok or not data then
		mkSection(leftCol, "Loading...", 0)
		return
	end

	local lvl = data.playerLevel or 1
	local xp = data.playerXP or 0
	local xpNeeded = data.xpNeeded or 100
	local isMobile = MobileWindowLayout.IsMobile()

	-- Name + level + XP (goes in sidebar on mobile)
	local barParent = isMobile and sidebarContent or leftCol

	local nameFrame = Instance.new("Frame")
	nameFrame.Size = UDim2.new(1, 0, 0, 50)
	nameFrame.BackgroundColor3 = C.card
	nameFrame.BorderSizePixel = 0
	nameFrame.LayoutOrder = 0
	nameFrame.Parent = barParent
	Instance.new("UICorner", nameFrame).CornerRadius = UDim.new(0, 10)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.6, 0, 0, 24)
	nameLbl.Position = UDim2.new(0, 14, 0, 5)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = player.Name
	nameLbl.TextColor3 = C.text
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextSize = 16
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = nameFrame

	local lvlBadge = Instance.new("TextLabel")
	lvlBadge.Size = UDim2.new(0, 80, 0, 24)
	lvlBadge.Position = UDim2.new(1, -90, 0, 5)
	lvlBadge.BackgroundColor3 = C.xpBar
	lvlBadge.BackgroundTransparency = 0.2
	lvlBadge.BorderSizePixel = 0
	lvlBadge.Text = "LEVEL " .. lvl
	lvlBadge.TextColor3 = Color3.new(1, 1, 1)
	lvlBadge.Font = Enum.Font.GothamBlack
	lvlBadge.TextSize = 12
	lvlBadge.Parent = nameFrame
	Instance.new("UICorner", lvlBadge).CornerRadius = UDim.new(0, 6)

	local xpBg = Instance.new("Frame")
	xpBg.Size = UDim2.new(1, -28, 0, 10)
	xpBg.Position = UDim2.new(0, 14, 0, 34)
	xpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	xpBg.BorderSizePixel = 0
	xpBg.Parent = nameFrame
	Instance.new("UICorner", xpBg).CornerRadius = UDim.new(0, 4)

	local xpRatio = xpNeeded > 0 and math.clamp(xp / xpNeeded, 0, 1) or 0
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(xpRatio, 0, 1, 0)
	xpFill.BackgroundColor3 = C.xpBar
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBg
	Instance.new("UICorner", xpFill).CornerRadius = UDim.new(0, 4)

	local xpLbl = Instance.new("TextLabel")
	xpLbl.Size = UDim2.new(1, 0, 1, 0)
	xpLbl.BackgroundTransparency = 1
	xpLbl.Text = xp .. " / " .. xpNeeded .. " XP"
	xpLbl.TextColor3 = Color3.new(1, 1, 1)
	xpLbl.Font = Enum.Font.GothamBold
	xpLbl.TextSize = 8
	xpLbl.Parent = xpBg

	-- Economy + Stats
	mkSection(leftCol, "ECONOMY", 1)
	mkStatRow(leftCol, "Coins", tostring(data.coins or 0), C.gold, 2)
	mkStatRow(leftCol, "Gems", tostring(data.gems or 0), C.blue, 3)

	mkSection(leftCol, "STATS", 20)
	mkStatRow(leftCol, "Monsters Owned", tostring(data.monstersOwned or 0), C.text, 21)
	mkStatRow(leftCol, "Total Captured", tostring(data.totalCaptured or 0), C.green, 22)
	mkStatRow(leftCol, "Arena Wins", tostring(data.arenaWins or 0), C.gold, 23)
	mkStatRow(leftCol, "Max Win Streak", tostring(data.arenaMaxStreak or 0), Color3.fromRGB(255, 130, 50), 24)
	mkStatRow(leftCol, "Total Income Earned", tostring(data.totalIncome or 0), C.gold, 25)

	-- Base Floors
	local ownedFloors = data.ownedFloors or { 1 }
	local function ownsFloor(n)
		for _, f in ipairs(ownedFloors) do if f == n then return true end end
		return false
	end

	local floorsParent = isMobile and leftCol or sidebarContent
	if isMobile then mkSection(leftCol, "BASE FLOORS", 40) end

	local unlockHint = Instance.new("TextLabel")
	unlockHint.Size = UDim2.new(1, 0, 0, 32)
	unlockHint.BackgroundTransparency = 1
	unlockHint.Text = "Floor 2 unlocks the Battle System!"
	unlockHint.TextColor3 = C.textMut
	unlockHint.Font = Enum.Font.GothamMedium
	unlockHint.TextSize = 9
	unlockHint.TextWrapped = true
	unlockHint.LayoutOrder = 0
	unlockHint.Parent = floorsParent

	for i, floorNum in ipairs({ 1, 2, 3 }) do
		local owned = ownsFloor(floorNum)
		local isLocked = not owned and floorNum > 1
		local rowHeight = isLocked and 70 or 44
		local floorRow = Instance.new("Frame")
		floorRow.Size = UDim2.new(1, 0, 0, rowHeight)
		floorRow.BackgroundColor3 = C.card
		floorRow.BorderSizePixel = 0
		floorRow.LayoutOrder = i
		floorRow.Parent = floorsParent
		Instance.new("UICorner", floorRow).CornerRadius = UDim.new(0, 7)

		local fName = Instance.new("TextLabel")
		fName.Size = UDim2.new(1, -12, 0, 18)
		fName.Position = UDim2.new(0, 8, 0, 4)
		fName.BackgroundTransparency = 1
		fName.Text = "Floor " .. floorNum
		fName.TextColor3 = owned and C.green or C.textMut
		fName.Font = Enum.Font.GothamBold
		fName.TextSize = 12
		fName.TextXAlignment = Enum.TextXAlignment.Left
		fName.Parent = floorRow

		if owned or floorNum == 1 then
			local fStatus = Instance.new("TextLabel")
			fStatus.Size = UDim2.new(1, -16, 0, 14)
			fStatus.Position = UDim2.new(0, 8, 0, 22)
			fStatus.BackgroundTransparency = 1
			fStatus.Font = Enum.Font.GothamMedium
			fStatus.TextSize = 9
			fStatus.TextXAlignment = Enum.TextXAlignment.Left
			fStatus.Parent = floorRow
			fStatus.Text = owned and "OWNED" or "STARTER"
			fStatus.TextColor3 = C.green
		else
			local reqLvl = floorNum == 2 and (GameConfig.Floor2LevelReq or 5) or (GameConfig.Floor3LevelReq or 15)
			local cost = floorNum == 2 and (GameConfig.Floor2Cost or 5000) or (GameConfig.Floor3Cost or 15000)
			local meetsLevel = lvl >= reqLvl
			local meetsPrereq = floorNum == 2 or ownsFloor(2)

			local costLbl = Instance.new("TextLabel")
			costLbl.Size = UDim2.new(1, -16, 0, 14)
			costLbl.Position = UDim2.new(0, 8, 0, 22)
			costLbl.BackgroundTransparency = 1
			costLbl.Font = Enum.Font.GothamBold
			costLbl.TextSize = 11
			costLbl.TextXAlignment = Enum.TextXAlignment.Left
			costLbl.Text = tostring(cost) .. " Coins"
			costLbl.TextColor3 = (data.coins or 0) >= cost and C.gold or C.red
			costLbl.Parent = floorRow

			local lvlLbl = Instance.new("TextLabel")
			lvlLbl.Size = UDim2.new(1, -16, 0, 12)
			lvlLbl.Position = UDim2.new(0, 8, 0, 36)
			lvlLbl.BackgroundTransparency = 1
			lvlLbl.Font = Enum.Font.GothamMedium
			lvlLbl.TextSize = 9
			lvlLbl.TextXAlignment = Enum.TextXAlignment.Left
			lvlLbl.Text = "Requires Level " .. reqLvl .. (not meetsPrereq and " + Floor " .. (floorNum - 1) or "")
			lvlLbl.TextColor3 = meetsLevel and C.green or C.textMut
			lvlLbl.Parent = floorRow

			local canBuy = meetsLevel and meetsPrereq and (data.coins or 0) >= cost
			local buyBtn2 = Instance.new("TextButton")
			buyBtn2.Size = UDim2.new(1, -16, 0, 22)
			buyBtn2.Position = UDim2.new(0, 8, 1, -26)
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
		local zoneId = ELEMENTAL_TO_ZONE and ELEMENTAL_TO_ZONE[element]
		local defeated = zoneId and hasSigil(zoneId)
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
	addSigilRow(sigilsTab, order, "Badlands", "\226\128\148", "Coming Soon", C.textMut)

	-- Hint
	order = order + 1
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 36)
	hint.BackgroundTransparency = 1
	hint.Text = "Defeat elemental bosses for SiegeSquire sigils; earn SiegeKnight sigils for zone doors. SiegeLord content coming soon."
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
local unlockedPopupShown = {}   -- id -> true (client-side duplicate guard)

local function mkBadgeIcon(parent, iconId, tint, locked)
	if iconId and iconId ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.new(0, 56, 0, 56)
		img.Position = UDim2.new(0, 12, 0.5, -28)
		img.Image = iconId
		img.ImageColor3 = tint or Color3.new(1, 1, 1)
		img.ImageTransparency = locked and 0.55 or 0
		img.Parent = parent
		return img
	end

	local ring = Instance.new("Frame")
	ring.Size = UDim2.new(0, 56, 0, 56)
	ring.Position = UDim2.new(0, 12, 0.5, -28)
	ring.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	ring.BackgroundTransparency = locked and 0.45 or 0.2
	ring.BorderSizePixel = 0
	ring.Parent = parent
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke", ring)
	stroke.Color = tint or C.achieveAccent
	stroke.Thickness = 2
	stroke.Transparency = locked and 0.5 or 0.15

	local star = Instance.new("TextLabel")
	star.Size = UDim2.new(1, 0, 1, 0)
	star.BackgroundTransparency = 1
	star.Text = "★"
	star.TextColor3 = tint or C.achieveAccent
	star.TextTransparency = locked and 0.55 or 0
	star.Font = Enum.Font.GothamBlack
	star.TextSize = 22
	star.Parent = ring
	return ring
end

local function applyAchievementVisualState(card, entry)
	local required = entry.requiredProgress or 0
	local cur = entry.currentProgress or 0
	local unlocked = entry.unlocked == true
	local inProgress = (not unlocked) and required > 0 and cur > 0
	local locked = (not unlocked) and (not inProgress)

	local tint = unlocked and C.green or inProgress and C.achieveAccent or C.textMut
	local bg = card:FindFirstChild("Bg")
	local titleLbl = card:FindFirstChild("Title")
	local descLbl = card:FindFirstChild("Desc")
	local pill = card:FindFirstChild("StatePill")
	local pillText = pill and pill:FindFirstChild("Text")
	local barBg = card:FindFirstChild("BarBg")
	local barFill = barBg and barBg:FindFirstChild("Fill")
	local progText = card:FindFirstChild("ProgText")
	local reqText = card:FindFirstChild("ReqText")
	local lockOverlay = card:FindFirstChild("LockOverlay")

	if bg then
		bg.BackgroundColor3 = unlocked and Color3.fromRGB(18, 28, 22) or C.card
		bg.BackgroundTransparency = unlocked and 0.08 or 0
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
	titleLbl.Parent = bg

	local descLbl = Instance.new("TextLabel")
	descLbl.Name = "Desc"
	descLbl.Size = UDim2.new(1, -92, 0, 28)
	descLbl.Position = UDim2.new(0, 80, 0, 28)
	descLbl.BackgroundTransparency = 1
	descLbl.Text = tostring(entry.description or "")
	descLbl.TextColor3 = C.textSec
	descLbl.Font = Enum.Font.GothamMedium
	descLbl.TextSize = 10
	descLbl.TextWrapped = true
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.TextYAlignment = Enum.TextYAlignment.Top
	descLbl.Parent = bg

	-- State pill (top-right)
	local pill = Instance.new("Frame")
	pill.Name = "StatePill"
	pill.Size = UDim2.new(0, 112, 0, 22)
	pill.Position = UDim2.new(1, -122, 0, 8)
	pill.BackgroundColor3 = Color3.fromRGB(22, 24, 35)
	pill.BorderSizePixel = 0
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
	barBg.Parent = bg
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = C.achieveAccent
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

	local progText = Instance.new("TextLabel")
	progText.Name = "ProgText"
	progText.Size = UDim2.new(0, 70, 0, 14)
	progText.Position = UDim2.new(1, -78, 1, -38)
	progText.BackgroundTransparency = 1
	progText.Text = "0/0"
	progText.TextColor3 = C.textMut
	progText.Font = Enum.Font.GothamBold
	progText.TextSize = 10
	progText.TextXAlignment = Enum.TextXAlignment.Right
	progText.Parent = bg

	local reqText = Instance.new("TextLabel")
	reqText.Name = "ReqText"
	reqText.Size = UDim2.new(1, -92, 0, 14)
	reqText.Position = UDim2.new(0, 80, 1, -38)
	reqText.BackgroundTransparency = 1
	reqText.Text = tostring(entry.category or "General")
	reqText.TextColor3 = C.textMut
	reqText.Font = Enum.Font.GothamMedium
	reqText.TextSize = 9
	reqText.TextXAlignment = Enum.TextXAlignment.Left
	reqText.Parent = bg

	-- Lock overlay (visible only when locked)
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	lockOverlay.BackgroundTransparency = 0.75
	lockOverlay.BorderSizePixel = 0
	lockOverlay.Visible = false
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

	local isMobile = MobileWindowLayout.IsMobile()
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

local function showAchievementUnlockPopup(def)
	if not def or not def.id then return end
	if unlockedPopupShown[def.id] then return end
	unlockedPopupShown[def.id] = true

	Notify.RewardPopup(
		"ACHIEVEMENT UNLOCKED",
		C.achieveAccent,
		{
			{ text = def.name or "Badge Earned", color = C.text, font = Enum.Font.GothamBlack, textSize = 16, size = 22 },
			{ text = def.description or "", color = C.textSec, font = Enum.Font.GothamMedium, textSize = 12, size = 18 },
		},
		5.5
	)
end

-- Live updates
if achievementProgress and achievementProgress:IsA("RemoteEvent") then
	achievementProgress.OnClientEvent:Connect(function(entry)
		if type(entry) ~= "table" or not entry.id then return end
		achievementCacheById[entry.id] = entry
		local card = achievementCardById[entry.id]
		if card then
			applyAchievementVisualState(card, entry)
		elseif isVis and activeTab == "Achievements" then
			-- If UI is open but card missing (e.g. refreshed during layout), rebuild.
			refreshAchievements()
		end
	end)
end

if achievementUnlocked and achievementUnlocked:IsA("RemoteEvent") then
	achievementUnlocked.OnClientEvent:Connect(function(def)
		showAchievementUnlockPopup(def)
		-- Ensure the achievements tab reflects completed state immediately.
		if isVis and activeTab == "Achievements" then
			task.defer(refreshAchievements)
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Rebirth tab refresh (ported from RebirthUIClient)
-- ══════════════════════════════════════════════════════════════════════════════

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

local isVis = false

local function applyMobileScale()
	local w, h, sbWidth = getScaledDims()
	local mobile = MobileWindowLayout.IsMobile()
	if mobile then
		MobileWindowLayout.ApplyWindow(main, {
			leftInset = 14, rightInset = 14, topInset = 10,
			bottomInset = 14, bottomMobileExtra = 20,
		})
		main.Draggable = true
		profileBody.FillDirection = Enum.FillDirection.Horizontal
		profileBody.Padding = UDim.new(0, 10)
		leftCol.Size = UDim2.new(1, -sbWidth - 10, 1, -8)
		rightSidebar.Size = UDim2.new(0, sbWidth, 1, -8)
		closeBtn.Size = UDim2.new(0, 36, 0, 36)
		closeBtn.Position = UDim2.new(1, -44, 0, 6)
		closeBtn.TextSize = 15
		sidebarTitle.Text = "DETAILS"
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
	if isVis then applyMobileScale() end
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

-- Auto-refresh profile tab while open
task.spawn(function()
	while true do
		task.wait(10)
		if isVis and activeTab == "Profile" then refreshProfile() end
	end
end)

-- Initialize default tab state (Profile active, others hidden)
switchTab("Profile")

print("[PlayerProfileClient] Loaded — tabbed Profile/Sigils/Rebirth menu (press P)")
