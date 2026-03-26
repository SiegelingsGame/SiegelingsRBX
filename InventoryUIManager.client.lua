-- InventoryUIManager.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Inventory, Battle Formation, and Base (layout + raids) UI.
-- Toggle with 'B' key or on-screen button.

-- Set to true to print base layout / placement debug logs to Output
local BASE_LAYOUT_DEBUG = false
local function baseLog(...) if BASE_LAYOUT_DEBUG then print("[BaseLayout]", ...) end end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Shared bindable events (created here so HUD / Capture / Combat can all use them)
local function ensureBindable(name)
	local existing = playerGui:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local e = Instance.new("BindableEvent")
	e.Name = name
	e.Parent = playerGui
	return e
end

local PLAY_FAV_ANIM_NAME = "PlayFavoriteCardAnimation"
ensureBindable(PLAY_FAV_ANIM_NAME)
ensureBindable("ToggleWeaponMode")
ensureBindable("WeaponModeChanged")  -- so we can connect before PlayerCombatClient fires; combat client finds and fires current modes
ensureBindable("ToggleSprint")       -- SprintClient listens; tap or Shift to sprint
ensureBindable("SprintStateChanged")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local CodexModelViewer = nil
if GameConfig.ENABLE_CODEX_3D_VIEWER then
	local modScript = ReplicatedStorage.Modules:FindFirstChild("CodexModelViewer")
	if modScript then
		local ok, mod = pcall(function() return require(modScript) end)
		if ok and mod and type(mod.new) == "function" then CodexModelViewer = mod end
	end
end
local INV_VIEWER_POOL_SIZE = 12
local invViewerPool = {}
local invViewerInUse = {}

-- Map UID -> card frame for fast selection highlight updates (avoids full refresh on select).
local invCardByUid = {}

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then warn("[UI] Events missing") return end

local function safeGet(n, t)
	local o = Events:WaitForChild(n, t or 8)
	if not o then warn("[UI] Missing: " .. n) end
	return o
end

-- FIX #23: Consolidate event references into a single table to stay under Luau's
-- 200 local-register limit. Previously each event was its own local variable (~40),
-- pushing the script past the cap and crashing at line ~3760 before input handlers loaded.
local Evt = {
	getInventory        = safeGet("GetInventory"),
	setCreatureNickname = safeGet("SetCreatureNickname"),
	assignToBase        = safeGet("AssignToBase"),
	assignToDefense     = safeGet("AssignToDefense"),
	slotAssignComplete  = Events:FindFirstChild("SlotAssignComplete"),
	setFavorite         = safeGet("SetFavorite"),
	captureSuccess      = safeGet("CaptureSuccess"),
	raidStart           = safeGet("RaidStart"),
	raidEnd             = safeGet("RaidEnd"),
	moveCreatureSlot    = safeGet("MoveCreatureSlot"),
	creatureStolen      = safeGet("CreatureStolen"),
	incomeReceived      = safeGet("IncomeReceived"),
	getBattleInfo       = safeGet("GetBattleInfo"),
	arenaAnnounce       = safeGet("ArenaAnnounce"),
	battleEnd           = safeGet("BattleEnd"),
	battleKill          = safeGet("BattleKill"),
	-- Gym battle events (separate system from standard arena battles)
	gymAnnounce         = Events:FindFirstChild("GymArenaAnnounce"),
	gymBattleEnd        = Events:FindFirstChild("GymBattleEnd"),
	gymBattleKill       = Events:FindFirstChild("GymBattleKill"),
	getBattleTimers     = Events:FindFirstChild("GetBattleTimers"),
	assignToBattle      = safeGet("AssignToBattle"),
	removeFromBattle    = safeGet("RemoveFromBattle"),
	toggleBattleTeam    = safeGet("ToggleBattleTeam"),
	getBattleTeam       = safeGet("GetBattleTeam"),
	sellCreature        = safeGet("SellCreature"),
	evolveCreature      = safeGet("EvolveCreature"),
	-- Badlands bag events
	badlandsBagUpdate   = Events:FindFirstChild("BadlandsBagUpdate"),
	badlandsBagSwitch   = Events:FindFirstChild("BadlandsBagSwitch"),
	badlandsSacrifice   = Events:FindFirstChild("BadlandsSacrificeCreature"),
	badlandsSacrificeResult = Events:FindFirstChild("BadlandsSacrificeResult"),
	evolveResult        = safeGet("EvolveResult"),
	companionSpawned    = safeGet("CompanionSpawned"),
	companionRecalled   = Events:FindFirstChild("CompanionRecalled"),
	-- FIX #17: Recall/Summon companion without changing favorite (Y / ReCard button)
	recallCompanion     = safeGet("RecallCompanion"),
	summonCompanion     = safeGet("SummonCompanion"),
	-- Mount system
	mountRequest        = Events:FindFirstChild("MountRequest"),
	dismountRequest     = Events:FindFirstChild("DismountRequest"),
}
-- Colors
local C = {
	bg = Color3.fromRGB(14, 15, 22),
	bgLight = Color3.fromRGB(22, 24, 35),
	card = Color3.fromRGB(28, 30, 42),
	accent = Color3.fromRGB(255, 92, 53),
	text = Color3.fromRGB(240, 240, 245),
	textSec = Color3.fromRGB(140, 145, 160),
	textMut = Color3.fromRGB(80, 85, 100),
	income = Color3.fromRGB(50, 220, 120),
	defense = Color3.fromRGB(220, 60, 70),
	favorite = Color3.fromRGB(255, 200, 50),
	raidBtn = Color3.fromRGB(180, 40, 50),
	divider = Color3.fromRGB(40, 42, 55),
	scroll = Color3.fromRGB(60, 62, 75),
	blue = Color3.fromRGB(60, 120, 255),
	red = Color3.fromRGB(255, 70, 70),
	battle = Color3.fromRGB(130, 100, 255),
}
local RARITY = {
	Common = Color3.fromRGB(120, 125, 140), Uncommon = Color3.fromRGB(50, 200, 90),
	Rare = Color3.fromRGB(50, 130, 255), Epic = Color3.fromRGB(170, 70, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
}
local ELEMENT_COLOR = {
	Fire = Color3.fromRGB(255, 80, 30), Ice = Color3.fromRGB(100, 200, 255),
	Wind = Color3.fromRGB(150, 255, 180), Earth = Color3.fromRGB(180, 140, 80),
	Shadow = Color3.fromRGB(120, 50, 180), Light = Color3.fromRGB(255, 250, 200),
	Lightning = Color3.fromRGB(255, 230, 60), Water = Color3.fromRGB(50, 150, 255),
	Psychic = Color3.fromRGB(200, 150, 255),
	Metal = Color3.fromRGB(160, 170, 180), Poison = Color3.fromRGB(120, 220, 80),
	Undead = Color3.fromRGB(140, 120, 160),
}
local CLASS_COLOR = {
	Bruiser = Color3.fromRGB(220, 80, 60), Mage = Color3.fromRGB(100, 120, 255),
	Guardian = Color3.fromRGB(80, 180, 220), Assassin = Color3.fromRGB(200, 60, 200),
	Support = Color3.fromRGB(100, 220, 120),
}

-- ══════════════════════════════════════════════════════════════════════════════
-- Base Under-Attack badge (same crest/pulse system as arena badge).
-- Shows when `GetInventory()` reports `defenseRaidActive == true`.
-- ══════════════════════════════════════════════════════════════════════════════
local BADGE_WIDTH       = 30
local BADGE_HEIGHT      = 34
local BADGE_GAP         = 8
local BADGE_BG          = Color3.fromRGB(18, 22, 32)
local BADGE_RED         = C.defense
local BADGE_DISPLAY_ORD = 90

local baseBadge = {
	gui = nil,
	button = nil,
	glow = nil,
	pulseConn = nil,
	visible = false,
}

local function startBaseBadgePulse()
	if baseBadge.pulseConn or not baseBadge.glow then return end
	local elapsed = 0
	baseBadge.pulseConn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = (math.sin(elapsed * 4 * math.pi) + 1) / 2
		if baseBadge.glow then
			baseBadge.glow.Thickness = 2 + t * 2
			baseBadge.glow.Transparency = t * 0.35
		end
	end)
end

local function stopBaseBadgePulse()
	if baseBadge.pulseConn then
		baseBadge.pulseConn:Disconnect()
		baseBadge.pulseConn = nil
	end
	if baseBadge.glow then
		baseBadge.glow.Thickness = 2
		baseBadge.glow.Transparency = 0
	end
end

local function createBaseUnderAttackBadge()
	if baseBadge.gui and baseBadge.gui.Parent then return end

	local sg = Instance.new("ScreenGui")
	sg.Name = "BaseUnderAttackBadge"
	sg.DisplayOrder = BADGE_DISPLAY_ORD
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.Parent = playerGui

	-- Position relative to Notification ticker bar (if present).
	local notifGui = playerGui:FindFirstChild("NotificationGUI")
	local tickerBar = notifGui and notifGui:FindFirstChild("TickerBar")

	local btn = Instance.new("TextButton")
	btn.Name = "BaseRaidButton"
	btn.Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT)
	btn.BackgroundColor3 = BADGE_BG
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel = 0
	btn.Text = "\226\154\148" -- same crest glyph used by arena badge
	btn.TextColor3 = BADGE_RED
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 18
	btn.AutoButtonColor = false
	btn.ZIndex = 100
	btn.Parent = sg

	if tickerBar then
		local ap = tickerBar.AbsolutePosition
		local as = tickerBar.AbsoluteSize
		btn.Position = UDim2.new(0, ap.X + as.X + BADGE_GAP, 0, ap.Y + as.Y / 2)
		btn.AnchorPoint = Vector2.new(0, 0.5)
	else
		btn.Position = UDim2.new(0.86, 0, 0, 18)
		btn.AnchorPoint = Vector2.new(0.5, 0)
	end

	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

	local glow = Instance.new("UIStroke")
	glow.Color = BADGE_RED
	glow.Thickness = 2
	glow.Transparency = 0
	glow.Parent = btn

	baseBadge.gui = sg
	baseBadge.button = btn
	baseBadge.glow = glow
	btn.Visible = false
end

local function updateBaseUnderAttackBadgeVisibility(isUnderAttack)
	if isUnderAttack and not baseBadge.visible then
		createBaseUnderAttackBadge()
		if not baseBadge.button then return end
		baseBadge.visible = true
		baseBadge.button.Visible = true
		baseBadge.button.Size = UDim2.new(0, 0, 0, 0)
		TweenService:Create(baseBadge.button, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT),
		}):Play()
		startBaseBadgePulse()
	elseif (not isUnderAttack) and baseBadge.visible then
		stopBaseBadgePulse()
		baseBadge.visible = false
		if baseBadge.button and baseBadge.button.Parent then
			TweenService:Create(baseBadge.button, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0),
			}):Play()
			task.delay(0.3, function()
				if baseBadge.button then baseBadge.button.Visible = false end
			end)
		end
	end
end

local lastBadgeRefreshT = 0
local function refreshBaseUnderAttackBadgeFromServer()
	-- Debounce: `RaidStart`/`RaidEnd` can arrive back-to-back.
	local now = tick()
	if (now - lastBadgeRefreshT) < 0.25 then return end
	lastBadgeRefreshT = now

	if not Evt.getInventory then return end
	local ok, invData = pcall(function() return Evt.getInventory:InvokeServer() end)
	if ok and invData then
		updateBaseUnderAttackBadgeVisibility(invData.defenseRaidActive == true)
	end
end

-- Initialize badge once (handles cases where player joins mid-raid).
task.defer(refreshBaseUnderAttackBadgeFromServer)

-- Debounce inventory button actions so double-clicks don't duplicate (e.g. assign then unassign).

local INV_BTN_DEBOUNCE = 0.5
local invBtnLastFire = {}
local function invButtonDebounce(uid, action, fn)
	local key = tostring(uid or "") .. ":" .. tostring(action or "")
	local now = tick()
	if invBtnLastFire[key] and (now - invBtnLastFire[key]) < INV_BTN_DEBOUNCE then return end
	invBtnLastFire[key] = now
	return fn()
end

-- FIX #20: Persistent optimistic state for Inc/Def buttons.
-- When the user clicks Inc/Def, we store the *expected* state here. mkCard checks this table
-- BEFORE server data so that ANY number of refreshInventory rebuilds (with or without override
-- args, deferred or queued) still show the correct button text ("Remove" vs "Income"/"Defense").
-- Entries self-clear inside refreshInventory once the server-side data (baseUidSet / defenseUidSet)
-- matches the optimistic expectation, meaning the server has caught up.
-- Safety: entries older than 5 seconds are force-cleared to prevent stale state from server errors.
local pendingOptimistic = {} -- { [uidStr] = { base = bool|nil, def = bool|nil, t = number } }

local pendingBattleUid = nil
-- Optimistic battle formation: { [slotIndex] = uid } — show placement instantly before server confirms
local pendingBattleOptimistic = {}
local selectedInventoryUid = nil
local latestInventoryData = nil
local latestInventoryLookup = {}
local refreshSelectedInventoryDetails
local renderInventoryDetails
local refreshInventory, refreshBattle, refreshRaids, refreshCurrentTab
local badBagState = { count = 0, capacity = 0, activeIndex = nil, slots = {} }
local lastFavoriteUid = nil   -- when user removes favorite, store here; Y or orb can re-equip it t
local lastFavoriteName = nil  -- display name for ReCard label when favorite is unequipped
local lastFavoriteCreatureId = nil  -- creature id for summon card animation (ReCard)
local companionOut = false   -- true when companion is spawned in world (for Summon vs ReCard label)

-- Base Layout (Base tab): selected slot for assignment; nil = none selected
local activeBaseSlotTrack = nil   -- "income" | "defense" | nil
local activeBaseSlotIndex = nil  -- 1-based slot index
local BASE_LAYOUT_SLOTS_PER_ROW = 6
local SLOT_CELL_SIZE = 36
local SLOT_CELL_PAD = 4

-- Expose active slot for assignment logic: read from sg:GetAttribute("BaseLayoutActiveTrack") / ("BaseLayoutActiveIndex")
local function updateBaseLayoutActiveAttrs()
	sg:SetAttribute("BaseLayoutActiveTrack", activeBaseSlotTrack or "")
	sg:SetAttribute("BaseLayoutActiveIndex", activeBaseSlotIndex or 0)
end

-- Root GUI
local sg = Instance.new("ScreenGui")
sg.Name = "InventoryUI"; sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; sg.DisplayOrder = 10; sg.Parent = playerGui

--[[ PANEL SCALING (viewport-based so window fits on mobile and desktop)
     Design size: width 680 so all text (stats, tabs, battle affinity, buttons) fits; height 640.
     getPanelScale() returns a multiplier so the panel fits in the viewport. ]]
local PANEL_DESIGN_W = 1040   -- Wider so inventory + details can coexist on mobile
local PANEL_DESIGN_H = 640
local PANEL_SCALE_MIN = 0.52   -- minimum scale so panel stays usable on small phones
local PANEL_SCALE_MAX = 1      -- never larger than design size
local MOBILE_BREAKPOINT = 620  -- viewport width below this = mobile layout (monster selection as sub-menu)

local function getPanelScale()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local scale = math.min(vp.X / PANEL_DESIGN_W, vp.Y / PANEL_DESIGN_H)
	return math.clamp(scale, PANEL_SCALE_MIN, PANEL_SCALE_MAX)
end

local function isMobileLayout()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	return MobileWindowLayout.IsMobile() or vp.X < MOBILE_BREAKPOINT or vp.Y < 500
end

-- B toggle button: shield-shaped, "Battle" / "Menu" on two lines. Under smaller HUD (~76px).
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "BattleMenuToggle"
toggleBtn.Size = UDim2.new(0, 46, 0, 54)
toggleBtn.Position = UDim2.new(0, 12, 0, 76)
toggleBtn.AnchorPoint = Vector2.new(0, 0)
toggleBtn.BackgroundColor3 = C.accent
toggleBtn.Text = "Battle\nMenu"
toggleBtn.TextColor3 = Color3.new(1, 1, 1)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 11
toggleBtn.TextWrapped = true
toggleBtn.LineHeight = 1.1
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = sg
local toggleCorner = Instance.new("UICorner", toggleBtn)
toggleCorner.CornerRadius = UDim.new(0, 10)
local toggleStroke = Instance.new("UIStroke", toggleBtn)
toggleStroke.Color = Color3.fromRGB(255, 120, 60)
toggleStroke.Thickness = 1
toggleStroke.Transparency = 0.5

-- Favorite card (Y): rectangle/card shape, "Summon [name]" or "ReCard [name]", color by creature type.
local favOrbBtn = Instance.new("TextButton")
favOrbBtn.Name = "FavoriteSummonCard"
favOrbBtn.Size = UDim2.new(0, 50, 0, 72)
favOrbBtn.Position = UDim2.new(0, 66, 0, 76)
favOrbBtn.AnchorPoint = Vector2.new(0, 0)
favOrbBtn.BackgroundColor3 = Color3.fromRGB(50, 48, 55)
favOrbBtn.Text = ""
favOrbBtn.BorderSizePixel = 0
favOrbBtn.Parent = sg
Instance.new("UICorner", favOrbBtn).CornerRadius = UDim.new(0, 8)
local favOrbStroke = Instance.new("UIStroke", favOrbBtn)
favOrbStroke.Color = C.divider
favOrbStroke.Transparency = 0.5

-- Card label: "Summon [name]" or "ReCard [name]" (updated in updateFavOrb)
local favOrbYLabel = Instance.new("TextLabel")
favOrbYLabel.Name = "FavCardLabel"
favOrbYLabel.Size = UDim2.new(1, -10, 1, -10)
favOrbYLabel.Position = UDim2.new(0, 5, 0, 5)
favOrbYLabel.BackgroundTransparency = 1
favOrbYLabel.Text = "No favorite"
favOrbYLabel.TextColor3 = Color3.new(1, 1, 1)
favOrbYLabel.Font = Enum.Font.GothamMedium
favOrbYLabel.TextSize = 10
favOrbYLabel.TextWrapped = true
favOrbYLabel.TextXAlignment = Enum.TextXAlignment.Center
favOrbYLabel.TextYAlignment = Enum.TextYAlignment.Center
favOrbYLabel.TextStrokeTransparency = 0.6
favOrbYLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
favOrbYLabel.Parent = favOrbBtn

-- Melee/Ranged swap button: triangle (▲ = switch to Melee) or upside-down triangle (▼ = switch to Ranged). Placed under Battle Menu.
local TRIANGLE_MELEE = "\u{25B2}"   -- ▲ (click to switch to Melee)
local TRIANGLE_RANGED = "\u{25BC}"  -- ▼ (click to switch to Ranged)
local weaponIcon = Instance.new("TextButton")
weaponIcon.Size = UDim2.new(0, 44, 0, 44)
-- Under Battle Menu button: toggleBtn is at (12, 76), height 54 → bottom at 130; place weapon 6px below
weaponIcon.Position = UDim2.new(0, 12, 0, 136)
weaponIcon.AnchorPoint = Vector2.new(0, 0)
weaponIcon.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
weaponIcon.BorderSizePixel = 0
weaponIcon.Text = TRIANGLE_MELEE
weaponIcon.TextColor3 = Color3.new(1, 1, 1)
weaponIcon.Font = Enum.Font.GothamBold
weaponIcon.TextSize = 18
weaponIcon.Parent = sg
Instance.new("UICorner", weaponIcon).CornerRadius = UDim.new(1, 0)
-- Mode label ON the button, below the arrow; white and visible
local weaponLbl = Instance.new("TextLabel")
weaponLbl.Size = UDim2.new(1, -6, 0, 12)
weaponLbl.Position = UDim2.new(0.5, 0, 0.58, 0)
weaponLbl.AnchorPoint = Vector2.new(0.5, 0)
weaponLbl.BackgroundTransparency = 1
weaponLbl.Text = "Melee"
weaponLbl.TextColor3 = Color3.new(1, 1, 1)
weaponLbl.Font = Enum.Font.GothamMedium
weaponLbl.TextSize = 9
weaponLbl.TextStrokeTransparency = 0.3
weaponLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
weaponLbl.TextXAlignment = Enum.TextXAlignment.Center
weaponLbl.Parent = weaponIcon
--

-- When in Ranged: show ▲ and "Melee" (next mode). When in Melee: show ▼ and "Ranged".
local function updateWeaponLabel(mode)
	if mode == "ranged" then
		weaponIcon.Text = TRIANGLE_MELEE   -- ▲ = click to switch to Melee
		weaponLbl.Text = "Melee"
	else
		weaponIcon.Text = TRIANGLE_RANGED  -- ▼ = click to switch to Ranged
		weaponLbl.Text = "Ranged"
	end
end
updateWeaponLabel("ranged")  -- default; PlayerCombatClient fires WeaponModeChanged on load to sync
local weaponModeEvt = playerGui:FindFirstChild("WeaponModeChanged")
if weaponModeEvt and weaponModeEvt:IsA("BindableEvent") then
	weaponModeEvt.Event:Connect(updateWeaponLabel)
end

-- Click/tap triangle = Swap weapon (melee/ranged); same as F key (TouchTap for touch screens)
local function fireWeaponToggle()
	local ev = playerGui:FindFirstChild("ToggleWeaponMode") or playerGui:WaitForChild("ToggleWeaponMode", 2)
	if ev and ev:IsA("BindableEvent") then ev:Fire() end
end
weaponIcon.MouseButton1Click:Connect(fireWeaponToggle)
weaponIcon.Activated:Connect(fireWeaponToggle)

-- Sprint button: next to Melee/Ranged (right of weaponIcon).
-- Mobile only: tap to toggle sprint. Desktop uses hold-Shift (no sprint button).
local SPRINT_BUTTON_GAP = 6
local MOBILE_SPRINT_Y = 144 -- move sprint button down a bit for touch comfort
local showMobileSprintButton = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local sprintBtn = Instance.new("TextButton")
sprintBtn.Name = "SprintButton"
sprintBtn.Size = UDim2.new(0, 44, 0, 44)
sprintBtn.Position = UDim2.new(0, 12 + 44 + SPRINT_BUTTON_GAP, 0, MOBILE_SPRINT_Y)
sprintBtn.AnchorPoint = Vector2.new(0, 0)
sprintBtn.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
sprintBtn.BorderSizePixel = 0
sprintBtn.Text = ""
sprintBtn.Visible = showMobileSprintButton
sprintBtn.Parent = sg
Instance.new("UICorner", sprintBtn).CornerRadius = UDim.new(1, 0)
local sprintLbl = Instance.new("TextLabel")
sprintLbl.Size = UDim2.new(1, -6, 1, -6)
sprintLbl.Position = UDim2.new(0.5, 0, 0.5, 0)
sprintLbl.AnchorPoint = Vector2.new(0.5, 0.5)
sprintLbl.BackgroundTransparency = 1
sprintLbl.Text = "Sprint"
sprintLbl.TextColor3 = Color3.new(1, 1, 1)
sprintLbl.Font = Enum.Font.GothamMedium
sprintLbl.TextSize = 10
sprintLbl.TextStrokeTransparency = 0.3
sprintLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
sprintLbl.TextXAlignment = Enum.TextXAlignment.Center
sprintLbl.TextYAlignment = Enum.TextYAlignment.Center
sprintLbl.Parent = sprintBtn
local sprintStroke = Instance.new("UIStroke", sprintBtn)
sprintStroke.Color = Color3.fromRGB(100, 180, 255)
sprintStroke.Thickness = 1
sprintStroke.Transparency = 0.5
local function setSprintButtonActive(active)
	sprintBtn.BackgroundColor3 = active and Color3.fromRGB(38, 50, 70) or Color3.fromRGB(28, 30, 42)
	sprintStroke.Transparency = active and 0.2 or 0.5
end
local toggleSprintEvt = ensureBindable("ToggleSprint")
sprintBtn.MouseButton1Click:Connect(function()
	if showMobileSprintButton then toggleSprintEvt:Fire() end
end)
sprintBtn.Activated:Connect(function()
	if showMobileSprintButton then toggleSprintEvt:Fire() end
end)
ensureBindable("SprintStateChanged").Event:Connect(setSprintButtonActive)

local function updateFavOrb()
	if not Evt.getInventory then return end
	local ok, data = pcall(function() return Evt.getInventory:InvokeServer() end)
	if not ok or not data then return end
	-- Sync companionOut with world: if our companion model exists, it's out (handles missed CompanionSpawned)
	local ourCompanionInWorld = false
	for _, model in ipairs(CollectionService:GetTagged("FavoriteCreature")) do
		if model.Parent and model:GetAttribute("OwnerUserId") == player.UserId then
			ourCompanionInWorld = true
			break
		end
	end
	if data.favoriteUid then
		companionOut = ourCompanionInWorld
	end
	local favUid = data.favoriteUid
	if favUid and data.inventory then
		for _, e in ipairs(data.inventory) do
			if tostring(e.uid) == tostring(favUid) then
				local cr = CreatureData.GetById(e.id)
				local displayName = (cr and cr.displayName) or e.id or "Creature"
				lastFavoriteUid = favUid
				lastFavoriteName = displayName
				lastFavoriteCreatureId = e.id
				favOrbBtn.BackgroundColor3 = (cr and cr.primaryColor) or Color3.fromRGB(180, 180, 180)
				local variant = e.variant and e.variant ~= "Normal" and e.variant or nil
				local VARIANT_COLORS = CreatureData.VariantColors or { Silver = Color3.fromRGB(192,192,192), Gold = Color3.fromRGB(255,215,0), Legend = Color3.fromRGB(255,100,255) }
				if variant and VARIANT_COLORS[variant] then
					favOrbStroke.Color = VARIANT_COLORS[variant]
				else
					favOrbStroke.Color = RARITY[cr and cr.rarity or "Common"] or C.textMut
				end
				favOrbStroke.Transparency = 0.2
				-- Card label: "ReCard [name]" when companion is out, else "Summon [name]"
				favOrbYLabel.Text = companionOut and ("ReCard " .. displayName) or ("Summon " .. displayName)
				favOrbYLabel.TextColor3 = Color3.new(1, 1, 1)
				return
			end
		end
	end
	-- No current favorite in data; clear companionOut
	companionOut = false
	-- No favorite: show "ReCard [last name]" if we can re-equip, else "No favorite"
	if lastFavoriteUid and lastFavoriteName then
		favOrbYLabel.Text = "ReCard " .. lastFavoriteName
		favOrbYLabel.TextColor3 = C.textSec
	else
		favOrbYLabel.Text = "No favorite"
		favOrbYLabel.TextColor3 = C.textMut
	end
	favOrbBtn.BackgroundColor3 = Color3.fromRGB(50, 48, 55)
	favOrbStroke.Color = C.divider
	favOrbStroke.Transparency = 0.5
end

-- FIX #17: toggleFavorite rewritten to RECALL/SUMMON instead of unfavorite/re-equip.
-- Y button / ReCard card toggles companion between summoned ↔ recalled WITHOUT clearing favoriteUid.
-- The creature STAYS as favorite throughout. Only the inventory "Unfavorite" button clears the favorite.
local function toggleFavorite()
	if not Evt.getInventory then return end
	local ok, data = pcall(function() return Evt.getInventory:InvokeServer() end)
	if not ok or not data then return end
	local favUid = data.favoriteUid

	-- Sync companionOut with world: check if our companion model actually exists right now
	local ourCompanionInWorld = false
	for _, model in ipairs(CollectionService:GetTagged("FavoriteCreature")) do
		if model.Parent and model:GetAttribute("OwnerUserId") == player.UserId then
			ourCompanionInWorld = true
			break
		end
	end
	if favUid then companionOut = ourCompanionInWorld end

	if favUid then
		-- Always keep track of the favorite for label/animation
		lastFavoriteUid = favUid
		for _, e in ipairs(data.inventory or {}) do
			if tostring(e.uid) == tostring(favUid) then
				local cr = CreatureData.GetById(e.id)
				lastFavoriteName = (cr and cr.displayName) or e.id or "Creature"
				lastFavoriteCreatureId = e.id
				break
			end
		end

		if companionOut then
			-- RECALL: companion is in the world → card it (despawn model, keep favorite)
			if Evt.recallCompanion then
				Evt.recallCompanion:FireServer()
			end
			companionOut = false
			Notify.Toast("Companion recalled", C.textSec, 2)
			task.wait(0.3)
			updateFavOrb()
			if isVis then refreshCurrentTab() end
		else
			-- SUMMON: companion is recalled/carded → bring it back out
			local playEvt = playerGui:FindFirstChild("PlayFavoriteCardAnimation")
			if playEvt and playEvt:IsA("BindableEvent") then playEvt:Fire(lastFavoriteCreatureId) end
			if Evt.summonCompanion then
				Evt.summonCompanion:FireServer()
			end
			companionOut = true
			Notify.Toast("Companion summoned", C.favorite, 2)
			task.wait(0.4)
			updateFavOrb()
			if isVis then refreshCurrentTab() end
		end
		return
	elseif lastFavoriteUid then
		-- No current favorite but we remember the last one → re-equip (set as favorite + summon)
		local stillInInv = false
		if data.inventory then
			for _, e in ipairs(data.inventory) do
				if tostring(e.uid) == tostring(lastFavoriteUid) then stillInInv = true; break end
			end
		end
		if not stillInInv then
			Notify.Toast("Creature no longer in inventory", C.textMut, 2)
			lastFavoriteUid = nil
			lastFavoriteName = nil
			lastFavoriteCreatureId = nil
			task.wait(0.25)
			updateFavOrb()
			if isVis then refreshCurrentTab() end
			return
		end
		-- Re-equip: play summon card animation first, then tell server to set favorite + spawn
		effectOverlay.Visible = true
		effectOverlay.BackgroundTransparency = 1
		TweenService:Create(effectOverlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.88 }):Play()
		local playEvt = playerGui:FindFirstChild("PlayFavoriteCardAnimation")
		if playEvt and playEvt:IsA("BindableEvent") then playEvt:Fire(lastFavoriteCreatureId) end
		if Evt.setFavorite then Evt.setFavorite:FireServer(lastFavoriteUid) end
		Notify.Toast("Favorite re-equipped", C.favorite, 2)
		if not isVis then openUI("inventory") end
		task.wait(0.4)
		companionOut = true
		updateFavOrb()
		if isVis then refreshCurrentTab() end
		task.delay(0.6, function()
			TweenService:Create(effectOverlay, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function() effectOverlay.Visible = false end)
		end)
		task.delay(2.5, function() effectOverlay.Visible = false end)  -- safety: force hide
		return
	else
		Notify.Toast("No favorite to re-equip", C.textMut, 2)
		task.wait(0.25)
		updateFavOrb()
		if isVis then refreshCurrentTab() end
		return
	end
end

favOrbBtn.MouseButton1Click:Connect(toggleFavorite)
task.defer(updateFavOrb)
if Evt.companionSpawned then
	Evt.companionSpawned.OnClientEvent:Connect(function()
		companionOut = true
		task.defer(updateFavOrb)
	end)
end
-- When non-water favorite enters water: companion is carded (turns into card, flies to player); update UI to show "Summon [name]"
if Evt.companionRecalled and Evt.companionRecalled:IsA("RemoteEvent") then
	Evt.companionRecalled.OnClientEvent:Connect(function()
		companionOut = false
		Notify.Toast("Companion carded (water)", C.textSec, 2.5)
		task.defer(updateFavOrb)
	end)
end

-- Main panel (size/position set in openUI from getPanelScale(); inner layout is relative so it scales with main)
local main = Instance.new("Frame")
main.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
main.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
main.BackgroundColor3 = C.bg; main.BorderSizePixel = 0
main.Visible = false; main.Active = true; main.Draggable = true; main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
Instance.new("UIStroke", main).Color = C.divider

-- Effect overlay for "card grows leaving body" + module grows from beneath (favorite button)
local effectOverlay = Instance.new("Frame")
effectOverlay.Name = "FavoriteEffectOverlay"
effectOverlay.Size = UDim2.new(1, 0, 1, 0)
effectOverlay.Position = UDim2.new(0, 0, 0, 0)
effectOverlay.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
effectOverlay.BackgroundTransparency = 1
effectOverlay.BorderSizePixel = 0
effectOverlay.Visible = false
effectOverlay.Active = false
effectOverlay.Parent = sg
effectOverlay.ZIndex = 100

-- Header
local hdr = Instance.new("Frame")
hdr.Size = UDim2.new(1, 0, 0, 48); hdr.BackgroundColor3 = C.bgLight
hdr.BorderSizePixel = 0; hdr.Parent = main
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 16)
local hdrFix = Instance.new("Frame")
hdrFix.Size = UDim2.new(1, 0, 0, 14); hdrFix.Position = UDim2.new(0, 0, 1, -14)
hdrFix.BackgroundColor3 = C.bgLight; hdrFix.BorderSizePixel = 0; hdrFix.Parent = hdr

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0); title.Position = UDim2.new(0, 18, 0, 0)
title.BackgroundTransparency = 1; title.Text = "MONSTER SIEGE"
title.TextColor3 = C.accent; title.Font = Enum.Font.GothamBlack
title.TextSize = 17; title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = hdr

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.Position = UDim2.new(1, -38, 0, 9)
closeBtn.BackgroundColor3 = C.card; closeBtn.Text = "X"; closeBtn.TextColor3 = C.textSec
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 13; closeBtn.BorderSizePixel = 0
closeBtn.Parent = hdr; Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- Stats bar
local stats = Instance.new("Frame")
stats.Size = UDim2.new(1, -28, 0, 36); stats.Position = UDim2.new(0, 14, 0, 52)
stats.BackgroundColor3 = C.card; stats.BorderSizePixel = 0; stats.Parent = main
Instance.new("UICorner", stats).CornerRadius = UDim.new(0, 8)

local coinLbl = Instance.new("TextLabel")
coinLbl.Size = UDim2.new(0.25, 0, 1, 0); coinLbl.Position = UDim2.new(0, 10, 0, 0)
coinLbl.BackgroundTransparency = 1; coinLbl.Text = "Coins: 0"
coinLbl.TextColor3 = Color3.fromRGB(255, 184, 0); coinLbl.Font = Enum.Font.GothamBold
coinLbl.TextSize = 12; coinLbl.TextXAlignment = Enum.TextXAlignment.Left; coinLbl.Parent = stats

local plotLbl = Instance.new("TextLabel")
plotLbl.Size = UDim2.new(0.2, 0, 1, 0); plotLbl.Position = UDim2.new(0.25, 0, 0, 0)
plotLbl.BackgroundTransparency = 1; plotLbl.Text = "Plot: -"
plotLbl.TextColor3 = C.textSec; plotLbl.Font = Enum.Font.GothamMedium; plotLbl.TextSize = 11; plotLbl.Parent = stats

local incomeLbl = Instance.new("TextLabel")
incomeLbl.Size = UDim2.new(0.25, 0, 1, 0); incomeLbl.Position = UDim2.new(0.45, 0, 0, 0)
incomeLbl.BackgroundTransparency = 1; incomeLbl.Text = "0/min"
incomeLbl.TextColor3 = C.income; incomeLbl.Font = Enum.Font.GothamBold; incomeLbl.TextSize = 11; incomeLbl.Parent = stats

local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(0.3, -10, 1, 0); countLbl.Position = UDim2.new(0.7, 0, 0, 0)
countLbl.BackgroundTransparency = 1; countLbl.Text = "0/" .. GameConfig.MaxInventorySize
countLbl.TextColor3 = C.textSec; countLbl.Font = Enum.Font.GothamMedium
countLbl.TextSize = 11; countLbl.TextXAlignment = Enum.TextXAlignment.Right; countLbl.Parent = stats

-- TABS (Inventory, Battle, Base, BadBag)
local tabC = Instance.new("Frame")
tabC.Size = UDim2.new(1, -28, 0, 30); tabC.Position = UDim2.new(0, 14, 0, 94)
tabC.BackgroundTransparency = 1; tabC.Parent = main

local activeTab = "inventory"
local updateInventoryLayout
local refreshBadBag  -- forward-declare
local function mkTab(name, text, px, w)
	local b = Instance.new("TextButton")
	b.Name = name; b.Size = UDim2.new(w, -4, 1, 0)
	b.Position = UDim2.new(px, px > 0 and 2 or 0, 0, 0)
	b.BackgroundColor3 = C.card; b.Text = text; b.TextColor3 = C.textSec
	b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.BorderSizePixel = 0; b.Parent = tabC
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	return b
end
local invTab = mkTab("Inv", "SIEGLINGS", 0, 1/4)
local battleTab = mkTab("Battle", "BATTLE", 1/4, 1/4)
local raidTab = mkTab("Base", "BASE", 2/4, 1/4)
local badBagTab = mkTab("BadBag", "BADBAG", 3/4, 1/4)
badBagTab.Visible = false  -- hidden until Badlands

local tabButtons = { invTab, battleTab, raidTab, badBagTab }

local function updateTabVisibility()
	local inBL = player:GetAttribute("InBadlands") == true
	badBagTab.Visible = inBL
	if inBL then
		invTab.Size = UDim2.new(1/4, -4, 1, 0); invTab.Position = UDim2.new(0, 0, 0, 0)
		battleTab.Size = UDim2.new(1/4, -4, 1, 0); battleTab.Position = UDim2.new(1/4, 2, 0, 0)
		raidTab.Size = UDim2.new(1/4, -4, 1, 0); raidTab.Position = UDim2.new(2/4, 2, 0, 0)
		badBagTab.Size = UDim2.new(1/4, -4, 1, 0); badBagTab.Position = UDim2.new(3/4, 2, 0, 0)
	else
		invTab.Size = UDim2.new(1/3, -4, 1, 0); invTab.Position = UDim2.new(0, 0, 0, 0)
		battleTab.Size = UDim2.new(1/3, -4, 1, 0); battleTab.Position = UDim2.new(1/3, 2, 0, 0)
		raidTab.Size = UDim2.new(1/3, -4, 1, 0); raidTab.Position = UDim2.new(2/3, 2, 0, 0)
	end
end

local function setTab(t)
	local inBL = player:GetAttribute("InBadlands") == true
	if inBL and t == "inventory" then t = "badbag" end
	activeTab = t; pendingBattleUid = nil
	for _, btn in ipairs(tabButtons) do
		btn.BackgroundColor3 = C.card; btn.TextColor3 = C.textSec
	end
	local active = (t == "inventory" and invTab) or (t == "battle" and battleTab) or (t == "raids" and raidTab) or (t == "badbag" and badBagTab)
	if active then active.BackgroundColor3 = C.accent; active.TextColor3 = Color3.new(1,1,1) end

	if inBL then
		invTab.BackgroundTransparency = 0.5
		invTab.AutoButtonColor = false
	else
		invTab.BackgroundTransparency = 0
		invTab.AutoButtonColor = true
	end

	if updateInventoryLayout then updateInventoryLayout() end
end

-- Content scroll
local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -28, 1, -140)
content.Position = UDim2.new(0, 14, 0, 130)
content.BackgroundTransparency = 1; content.BorderSizePixel = 0
content.ScrollBarThickness = 4; content.ScrollBarImageColor3 = C.scroll
content.ScrollingDirection = Enum.ScrollingDirection.Y
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new(0,0,0,0); content.Parent = main

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 5); contentLayout.Parent = content

local DETAIL_PANEL_W = 295
local detailPanel = Instance.new("Frame")
detailPanel.Name = "InventoryDetailPanel"
detailPanel.Size = UDim2.new(0, DETAIL_PANEL_W, 1, -140)
detailPanel.Position = UDim2.new(1, -14 - DETAIL_PANEL_W, 0, 130)
detailPanel.BackgroundColor3 = C.bgLight
detailPanel.BorderSizePixel = 0
detailPanel.Visible = false
detailPanel.Parent = main
Instance.new("UICorner", detailPanel).CornerRadius = UDim.new(0, 10)
local detailStroke = Instance.new("UIStroke")
detailStroke.Color = C.divider
detailStroke.Transparency = 0.2
detailStroke.Parent = detailPanel

local detailScroll = Instance.new("ScrollingFrame")
detailScroll.Size = UDim2.new(1, -12, 1, -12)
detailScroll.Position = UDim2.new(0, 6, 0, 6)
detailScroll.BackgroundTransparency = 1
detailScroll.BorderSizePixel = 0
detailScroll.ScrollBarThickness = 4
detailScroll.ScrollBarImageColor3 = C.scroll
detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
detailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
detailScroll.Parent = detailPanel
local detailList = Instance.new("UIListLayout")
detailList.SortOrder = Enum.SortOrder.LayoutOrder
detailList.Padding = UDim.new(0, 6)
detailList.Parent = detailScroll

-- Large 3D viewer at top of details panel (cycles animations)
local detailViewerHost = Instance.new("Frame")
detailViewerHost.Name = "DetailViewerHost"
detailViewerHost.Size = UDim2.new(1, -4, 0, 160)
detailViewerHost.BackgroundColor3 = C.card
detailViewerHost.BorderSizePixel = 0
detailViewerHost.LayoutOrder = 2
detailViewerHost.Parent = detailScroll
Instance.new("UICorner", detailViewerHost).CornerRadius = UDim.new(0, 10)

local detailViewer = nil
local detailViewerAnimThread = nil
local detailViewerCurrentCreatureId = nil

local function mkDetailLabel(height, size, bold, color)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -4, 0, height)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = color or C.text
	lbl.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	lbl.TextSize = size
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.Parent = detailScroll
	return lbl
end

local detailName = mkDetailLabel(26, 18, true, C.favorite)
local detailType = mkDetailLabel(18, 11, false, C.textSec)
local detailWeak = mkDetailLabel(16, 10, false, Color3.fromRGB(255, 120, 120))
local detailStrong = mkDetailLabel(16, 10, false, Color3.fromRGB(120, 255, 170))
local detailTraits = mkDetailLabel(32, 10, false, C.textSec)
local detailDesc = mkDetailLabel(70, 10, false, C.textMut)
local detailStats = mkDetailLabel(78, 10, false, C.text)
local detailXP = mkDetailLabel(30, 10, false, Color3.fromRGB(140, 190, 255))
detailName.LayoutOrder = 0
detailType.LayoutOrder = 1
detailWeak.LayoutOrder = 3
detailStrong.LayoutOrder = 4
detailTraits.LayoutOrder = 5
detailDesc.LayoutOrder = 6
detailStats.LayoutOrder = 7
detailXP.LayoutOrder = 8

local nickTitle = mkDetailLabel(16, 10, true, C.accent)
nickTitle.Text = "Nickname"
nickTitle.LayoutOrder = 9

local nickBox = Instance.new("TextBox")
nickBox.Size = UDim2.new(1, -4, 0, 28)
nickBox.BackgroundColor3 = C.card
nickBox.TextColor3 = C.text
nickBox.PlaceholderColor3 = C.textMut
nickBox.PlaceholderText = "Enter nickname..."
nickBox.Font = Enum.Font.GothamMedium
nickBox.TextSize = 11
nickBox.ClearTextOnFocus = false
nickBox.TextXAlignment = Enum.TextXAlignment.Left
nickBox.LayoutOrder = 10
nickBox.Parent = detailScroll
Instance.new("UICorner", nickBox).CornerRadius = UDim.new(0, 6)
local nickPad = Instance.new("UIPadding")
nickPad.PaddingLeft = UDim.new(0, 8)
nickPad.PaddingRight = UDim.new(0, 8)
nickPad.Parent = nickBox

local nickBtn = Instance.new("TextButton")
nickBtn.Size = UDim2.new(1, -4, 0, 24)
nickBtn.BackgroundColor3 = C.favorite
nickBtn.TextColor3 = Color3.new(0, 0, 0)
nickBtn.Font = Enum.Font.GothamBold
nickBtn.TextSize = 10
nickBtn.Text = "Set Name (Free)"
nickBtn.LayoutOrder = 11
nickBtn.Parent = detailScroll
Instance.new("UICorner", nickBtn).CornerRadius = UDim.new(0, 6)

local nickHint = mkDetailLabel(26, 9, false, C.textMut)
nickHint.LayoutOrder = 12

local function getEntryDisplayName(entry, creature)
	if entry and entry.isEgg == true and entry.mystery == true and entry.inspected ~= true then
		return "Unknown Egg"
	end
	if entry and type(entry.nickname) == "string" and entry.nickname ~= "" then
		local baseName = (creature and creature.displayName) or (entry and entry.id) or "Siegling"
		return entry.nickname .. " (" .. baseName .. ")"
	end
	return (creature and creature.displayName) or (entry and entry.id) or "Unknown"
end

local function computeEffectiveStatsClient(creature, entry)
	local level = (entry and entry.level) or 1
	local variant = (entry and entry.variant) or "Normal"
	local baseStats = {
		health = creature.health or 1,
		attack = creature.attack or 1,
		defense = creature.defense or 1,
		speed = creature.speed or 1,
	}
	local statKeys = { "health", "attack", "defense", "speed" }
	local order = { health = 1, attack = 2, defense = 3, speed = 4 }
	table.sort(statKeys, function(a, b)
		if baseStats[a] ~= baseStats[b] then return baseStats[a] > baseStats[b] end
		return (order[a] or 0) < (order[b] or 0)
	end)
	local rankOf = {}
	for rank, key in ipairs(statKeys) do rankOf[key] = rank end
	local rankMults = GameConfig.StatGainByRank or { 1.5, 1.25, 1.0, 0.75 }
	local baseGain = GameConfig.StatGainPerLevel or 0.08
	local rarityMult = (GameConfig.RarityStatMultipliers and GameConfig.RarityStatMultipliers[creature.rarity]) or 1
	local variantMult = (CreatureData.GetVariantStatMultiplier and CreatureData.GetVariantStatMultiplier(variant)) or 1
	local mult = rarityMult * variantMult
	local out = {}
	for _, key in ipairs({ "health", "attack", "defense", "speed" }) do
		local r = rankOf[key] or 4
		local lm = 1 + (level - 1) * baseGain * (rankMults[r] or 1)
		out[key] = math.floor((baseStats[key] or 1) * lm * mult)
	end
	return out
end

local function getMatchupText(creature)
	local weak, strong = {}, {}
	for elementName, _ in pairs(CreatureData.Elements or {}) do
		if elementName ~= creature.element then
			if CreatureData.GetElementalDamageMultiplier(elementName, creature.element) > 1 then
				table.insert(weak, elementName)
			end
			if CreatureData.GetElementalDamageMultiplier(creature.element, elementName) > 1 then
				table.insert(strong, elementName)
			end
		end
	end
	table.sort(weak)
	table.sort(strong)
	return (#weak > 0 and table.concat(weak, ", ") or "None"), (#strong > 0 and table.concat(strong, ", ") or "None")
end

renderInventoryDetails = function(data, entry, creature)
	if not entry or not creature then
		if detailViewer then
			detailViewer:SetCreature(nil)
		end
		if detailViewerAnimThread then
			detailViewerAnimThread = nil
		end
		detailName.Text = "Select a Siegling"
		detailType.Text = "Tap a monster cell to inspect details."
		detailWeak.Text = ""
		detailStrong.Text = ""
		detailTraits.Text = ""
		detailDesc.Text = ""
		detailStats.Text = ""
		detailXP.Text = ""
		nickBox.Text = ""
		nickBox.Visible = false
		nickBtn.Visible = false
		nickHint.Text = ""
		return
	end

	local lvl = entry.level or 1
	local xp = entry.xp or 0
	local maxLvl = CreatureData.GetMaxCreatureLevel and CreatureData.GetMaxCreatureLevel(entry.id) or (GameConfig.MaxCreatureLevel or 10)
	local xpNeeded = (lvl >= maxLvl) and 0 or math.floor((GameConfig.BaseXPRequired or 50) * ((GameConfig.XPScaling or 1.5) ^ (lvl - 1)))
	local statsNow = computeEffectiveStatsClient(creature, entry)
	local weakText, strongText = getMatchupText(creature)
	local activeName = getEntryDisplayName(entry, creature)
	local renameCost = tonumber(GameConfig.CreatureRenameGemCost) or 5
	local hasNamedBefore = entry.nicknameEverSet == true
	local canNickname = entry.isEgg ~= true
	local eggHidden = entry.isEgg == true and entry.mystery == true and entry.inspected ~= true

	if eggHidden then
		if detailViewer then
			detailViewer:SetCreature(nil)
		end
		if detailViewerAnimThread then
			detailViewerAnimThread = nil
		end
		detailName.Text = "Unknown Egg"
		detailType.Text = "Unknown | ??? | ???"
		detailWeak.Text = "Weak vs: ???"
		detailStrong.Text = "Strong vs: ???"
		detailTraits.Text = "Traits: Unknown until inspected or hatched"
		detailDesc.Text = "A mystery egg. Place it on your base to hatch, or inspect it for diamonds."
		detailStats.Text = ("Stats @ Lv.%d\nHidden until inspected"):format(lvl)
		detailXP.Text = "XP: Not available while egg is hidden"
		nickBox.Visible = false
		nickBtn.Visible = false
		nickBox.Text = ""
		nickHint.Text = "Eggs cannot be nicknamed until they hatch."
		return
	end

	detailName.Text = activeName
	detailType.Text = ("%s | %s | %s"):format(creature.rarity or "?", creature.element or "?", creature.class or "?")
	detailWeak.Text = "Weak vs: " .. weakText
	detailStrong.Text = "Strong vs: " .. strongText
	detailTraits.Text = ("Traits: %s behavior | %s rarity | %s variant"):format(creature.behavior or "unknown", creature.rarity or "?", entry.variant or "Normal")
	detailDesc.Text = creature.description or "No description."
	detailStats.Text = ("Stats @ Lv.%d\nHP %d | ATK %d\nDEF %d | SPD %d"):format(lvl, statsNow.health, statsNow.attack, statsNow.defense, statsNow.speed)
	detailXP.Text = (lvl >= maxLvl) and ("XP: MAX LEVEL (" .. tostring(xp) .. " stored)") or ("XP: " .. tostring(xp) .. " / " .. tostring(xpNeeded) .. " to level")
	nickBox.Visible = canNickname
	nickBtn.Visible = canNickname
	nickBox.Text = canNickname and (entry.nickname or "") or ""
	if canNickname then
		nickBtn.Text = hasNamedBefore and ("Rename (" .. tostring(renameCost) .. " diamonds)") or "Set Name (Free)"
		nickHint.Text = hasNamedBefore and "Renaming costs diamonds. Name shows to everyone and follows this creature if stolen." or "First name is free. Name shows to everyone and follows this creature if stolen."
	else
		nickHint.Text = "Eggs cannot be nicknamed until they hatch."
	end

	-- Ensure detail viewer exists and show this creature
	if CodexModelViewer and not entry.isEgg then
		if not detailViewer then
			detailViewer = CodexModelViewer.new(detailViewerHost, {
				size = UDim2.new(1, -12, 1, -12),
				autoRotate = false,
				zoomEnabled = false,
				showFloor = false,
				themedLighting = true,
				-- Ensure we never flash into a bind/T-pose during scroll-driven UI work.
				-- The animation cycle below will still override this as needed.
				playIdleAnimation = true,
				interactable = false,
			})
		end
		if detailViewerCurrentCreatureId ~= entry.id then
			detailViewerCurrentCreatureId = entry.id
			detailViewer:SetCreature(entry.id)
		end

		-- Cycle through animation states: Idle → Move → Income → Attack → Special (CreatureAnimation names)
		local entryUidStr = tostring(entry.uid or "")
		local token = {}
		detailViewerAnimThread = token
		task.spawn(function()
			task.wait(0.15)  -- let model load and Setup run once
			local states = { "Idle", "Move", "Income", "Attack", "Special" }
			local idx = 1
			while detailViewerAnimThread == token and selectedInventoryUid == entryUidStr do
				if detailViewer and detailViewer.PlayAnimationState then
					detailViewer:PlayAnimationState(states[idx])
				end
				idx = idx + 1
				if idx > #states then idx = 1 end
				for _ = 1, 40 do
					if detailViewerAnimThread ~= token or selectedInventoryUid ~= entryUidStr then return end
					task.wait(0.1)
				end
			end
		end)
	elseif detailViewer then
		detailViewerCurrentCreatureId = nil
		detailViewer:SetCreature(nil)
	end
end

refreshSelectedInventoryDetails = function()
	if activeTab ~= "inventory" then return end
	if not latestInventoryData or not selectedInventoryUid then
		renderInventoryDetails(nil, nil, nil)
		return
	end
	local entry = latestInventoryLookup[selectedInventoryUid]
	if not entry then
		renderInventoryDetails(nil, nil, nil)
		return
	end
	local creature = CreatureData.GetById(entry.id)
	if not creature then
		renderInventoryDetails(nil, nil, nil)
		return
	end
	renderInventoryDetails(latestInventoryData, entry, creature)
end

updateInventoryLayout = function()
	local showDetails = activeTab == "inventory"
	local detailW = isMobileLayout() and 220 or DETAIL_PANEL_W
	detailPanel.Visible = showDetails
	detailPanel.Size = UDim2.new(0, detailW, 1, -140)
	detailPanel.Position = UDim2.new(1, -14 - detailW, 0, 130)
	if showDetails then
		content.Size = UDim2.new(1, -(28 + detailW + 10), 1, -140)
	else
		content.Size = UDim2.new(1, -28, 1, -140)
	end
	content.Position = UDim2.new(0, 14, 0, 130)
	if showDetails then
		refreshSelectedInventoryDetails()
	end
end

nickBtn.MouseButton1Click:Connect(function()
	if not selectedInventoryUid or selectedInventoryUid == "" then
		Notify.Toast("Select a Siegling first.", C.textSec, 2)
		return
	end
	local selectedEntry = latestInventoryLookup[selectedInventoryUid]
	if selectedEntry and selectedEntry.isEgg then
		Notify.Toast("Hatch the egg before naming it.", C.textSec, 2)
		return
	end
	local desiredName = nickBox.Text or ""
	local ok, success, serverMsg = pcall(function()
		return Evt.setCreatureNickname:InvokeServer(selectedInventoryUid, desiredName)
	end)
	if not ok then
		Notify.Toast("Rename failed", C.red, 2)
		return
	end
	if success then
		Notify.Toast(serverMsg or "Name updated!", C.income, 2)
		if refreshInventory then refreshInventory() end
	else
		Notify.Toast(serverMsg or "Could not rename", C.red, 3)
	end
end)

-- Capture scroll position before refresh; call returned function when done to restore
local function captureScrollPosition()
	local savedY = content.CanvasPosition.Y
	return function()
		task.defer(function()
			task.wait()
			local maxScroll = math.max(0, content.CanvasSize.Y.Offset - content.AbsoluteWindowSize.Y)
			content.CanvasPosition = Vector2.new(0, math.min(savedY, maxScroll))
		end)
	end
end

local function scrollSelectedCardIntoView(forceSnap)
	if not selectedInventoryUid or selectedInventoryUid == "" then return end
	local card = content:FindFirstChild("InvCard_" .. tostring(selectedInventoryUid))
	if not card or not card:IsA("GuiObject") then return end
	task.defer(function()
		task.wait()
		if not card.Parent then return end
		local currentY = content.CanvasPosition.Y
		local windowH = content.AbsoluteWindowSize.Y
		local maxScroll = math.max(0, content.CanvasSize.Y.Offset - windowH)
		local topY = (card.AbsolutePosition.Y - content.AbsolutePosition.Y) + currentY
		local bottomY = topY + card.AbsoluteSize.Y
		local targetY = currentY
		if forceSnap then
			targetY = topY - 8
		else
			local viewTop = currentY
			local viewBottom = currentY + windowH
			if topY < viewTop + 8 then
				targetY = topY - 8
			elseif bottomY > viewBottom - 8 then
				targetY = bottomY - windowH + 8
			else
				return
			end
		end
		targetY = math.clamp(targetY, 0, maxScroll)
		content.CanvasPosition = Vector2.new(0, targetY)
	end)
end

-- --------------------------------------------
-- INVENTORY CARD (no Battle button)
-- --------------------------------------------
local function mkCard(entry, creature, data, order)
	local mobile = isMobileLayout()
	local isEgg = entry.isEgg == true
	local eggHidden = isEgg and entry.mystery == true and entry.inspected ~= true
	local rc = RARITY[entry.rarity or creature.rarity] or C.textMut
	local isBase, isDef, isFav, isBattle = false, false, false, false
	local battleSlot = nil
	-- Single source of truth: use precomputed UID sets from refreshInventory (built after slot normalization).
	local entryUidStr = tostring(entry.uid or "")
	if data.baseUidSet and data.baseUidSet[entryUidStr] then isBase = true end
	if data.defenseUidSet and data.defenseUidSet[entryUidStr] then isDef = true end
	-- FIX #20: Optimistic state overrides server data until the server catches up.
	-- This ensures that no matter how many refreshInventory cycles run (deferred, queued,
	-- no-args), the button always reflects the user's last click until confirmed.
	local optState = pendingOptimistic[entryUidStr]
	if optState then
		if optState.base ~= nil then isBase = optState.base end
		if optState.def  ~= nil then isDef  = optState.def  end
	end
	-- #region agent log [InvRem] confirm when Rem should appear (commented after UI fixes verified)
	-- do
	-- 	local name = (creature and creature.displayName) or entry.id or "?"
	-- 	local inBase = not not (data.baseUidSet and data.baseUidSet[entryUidStr])
	-- 	local inDef = not not (data.defenseUidSet and data.defenseUidSet[entryUidStr])
	-- 	print("[InvRem] mkCard", name, "uid=" .. tostring(entryUidStr), "hasBaseSet=" .. tostring(data.baseUidSet ~= nil), "hasDefSet=" .. tostring(data.defenseUidSet ~= nil), "inBase=" .. tostring(inBase), "inDef=" .. tostring(inDef), "=> isBase=" .. tostring(isBase), "isDef=" .. tostring(isDef))
	-- end
	-- #endregion
	if data.favoriteUid and tostring(data.favoriteUid) == tostring(entry.uid) then isFav = true end
	if data.battleTeamSlots and #data.battleTeamSlots > 0 then
		for _, t in ipairs(data.battleTeamSlots) do
			if t and t.uid and tostring(t.uid) == tostring(entry.uid) then isBattle = true; battleSlot = t.slot break end
		end
	elseif data.battleTeam then
		for s, bu in pairs(data.battleTeam) do
			if bu and tostring(bu) == tostring(entry.uid) then isBattle = true; battleSlot = tonumber(s) break end
		end
	end
	-- Eggs cannot be favorite or battle
	if isEgg then isFav = false; isBattle = false end
	local watermarkText, watermarkColor = nil, nil
	if isFav then
		watermarkText = "FAVORITE"
		watermarkColor = C.favorite
	elseif isDef then
		watermarkText = "DEFENSE"
		watermarkColor = C.defense
	elseif isBase then
		watermarkText = "INCOME"
		watermarkColor = C.income
	elseif isBattle then
		watermarkText = battleSlot and ("BATTLE: " .. tostring(battleSlot)) or "BATTLE"
		watermarkColor = C.battle
	end
	-- Dynamic slot limits based on owned floors
	local numFloors = data.ownedFloors and #data.ownedFloors or 1
	local maxIncome = numFloors * (GameConfig.IncomePointsPerFloor or 6)
	local maxDefense = numFloors * (GameConfig.DefensePointsPerFloor or 6)
	local filledBase = data.filledBaseCount
	if filledBase == nil then
		filledBase = 0
		for _, u in pairs(data.baseSlots or {}) do if u and u ~= "" then filledBase = filledBase + 1 end end
	end
	local filledDef = data.filledDefenseCount
	if filledDef == nil then
		filledDef = 0
		for _, u in pairs(data.defenseSlots or {}) do if u and u ~= "" then filledDef = filledDef + 1 end end
	end
	local baseFull = filledBase >= maxIncome
	local defFull = filledDef >= maxDefense

	-- Level & XP (client-side XP-for-next-level to show progress)
	local lvl = entry.level or 1
	local xp = entry.xp or 0
	local maxLvl = (not isEgg) and (CreatureData.GetMaxCreatureLevel and CreatureData.GetMaxCreatureLevel(entry.id) or (GameConfig.MaxCreatureLevel or 10)) or 1
	local function xpNeededForNextLevel(level)
		if level >= maxLvl then return 0 end
		return math.floor((GameConfig.BaseXPRequired or 50) * ((GameConfig.XPScaling or 1.5) ^ (level - 1)))
	end
	local xpNeeded = xpNeededForNextLevel(lvl)
	local xpPct = (xpNeeded > 0) and math.clamp(xp / xpNeeded, 0, 1) or 1

	local card = Instance.new("Frame")
	card.Name = "InvCard_" .. entryUidStr
	card.ZIndex = 2  -- base for card so children can sit above
	-- Cell highlight: dark purple = Battle, dark red = Defense, dark green = Income; Favorite = gold tint; default = card
	local cardBg = C.card
	if isEgg then cardBg = Color3.fromRGB(38, 35, 25)
	elseif isFav then cardBg = Color3.fromRGB(35, 33, 20)
	elseif isBattle then cardBg = Color3.fromRGB(25, 24, 38)
	elseif isDef then cardBg = Color3.fromRGB(40, 22, 22)
	elseif isBase then cardBg = Color3.fromRGB(22, 38, 28)
	end
	local cardInsetX = mobile and 4 or 6
	card.Size = UDim2.new(1, -(cardInsetX * 2), 0, mobile and 86 or 80); card.BackgroundColor3 = cardBg
	card.Position = UDim2.new(0, cardInsetX, 0, 0)
	card.BorderSizePixel = 0; card.LayoutOrder = order
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 9)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "SelectionStroke"
	stroke.Color = C.favorite
	stroke.Thickness = 2
	stroke.Transparency = 0.05
	stroke.Enabled = (selectedInventoryUid and tostring(selectedInventoryUid) == entryUidStr) and true or false
	stroke.Parent = card
	invCardByUid[entryUidStr] = card
	card.ClipsDescendants = false

	local watermark = Instance.new("TextLabel")
	watermark.Name = "StatusWatermark"
	watermark.Size = UDim2.new(1, 0, 1, 0)
	watermark.Position = UDim2.new(0, 0, 0, 0)
	watermark.BackgroundTransparency = 1
	watermark.RichText = true
	watermark.Text = watermarkText and ("<i>" .. watermarkText .. "</i>") or ""
	watermark.Visible = watermarkText ~= nil and watermarkText ~= ""
	watermark.TextColor3 = watermarkColor or C.textMut
	watermark.TextTransparency = mobile and 0.93 or 0.92
	watermark.Font = Enum.Font.GothamBlack
	watermark.TextScaled = true
	watermark.TextXAlignment = Enum.TextXAlignment.Left
	watermark.TextYAlignment = Enum.TextYAlignment.Center
	watermark.ZIndex = 1
	watermark.Parent = card

	-- Creature visual removed from list row; keep variant info for name suffix.
	local variant = (not isEgg and entry.variant) and entry.variant ~= "Normal" and entry.variant or nil

	-- Name (left) and XP bar + label (right) on the same row
	local variantSuffix = variant and (" · " .. variant) or ""
	local baseName = getEntryDisplayName(entry, creature)
	local displayName = isEgg and (eggHidden and "Unknown Egg" or ("Egg (" .. (creature.displayName or entry.id) .. ")")) or (baseName .. variantSuffix)
	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.new(0, mobile and 152 or 180, 0, 18); nm.Position = UDim2.new(0, 12, 0, 6)
	nm.BackgroundTransparency = 1; nm.Text = displayName
	nm.TextColor3 = C.text; nm.Font = Enum.Font.GothamBold; nm.TextSize = 13
	nm.TextXAlignment = Enum.TextXAlignment.Left; nm.ZIndex = 2; nm.Parent = card

	-- XP bar + label (skip for eggs)
	if not isEgg then
		local xpBarW, xpLblW = (mobile and 84 or 140), (mobile and 42 or 54)
		local xpBarBg = Instance.new("Frame")
		xpBarBg.Size = UDim2.new(0, xpBarW, 0, 6); xpBarBg.Position = UDim2.new(1, -xpBarW - xpLblW - 6, 0, 9)
		xpBarBg.BackgroundColor3 = Color3.fromRGB(20, 22, 30); xpBarBg.BorderSizePixel = 0
		xpBarBg.ZIndex = 2
		xpBarBg.Parent = card
		Instance.new("UICorner", xpBarBg).CornerRadius = UDim.new(0, 3)
		local xpBarFill = Instance.new("Frame")
		xpBarFill.Size = UDim2.new(xpPct, 0, 1, 0); xpBarFill.Position = UDim2.new(0, 0, 0, 0)
		xpBarFill.BackgroundColor3 = lvl >= maxLvl and C.income or Color3.fromRGB(80, 160, 255)
		xpBarFill.BorderSizePixel = 0; xpBarFill.ZIndex = 2; xpBarFill.Parent = xpBarBg
		Instance.new("UICorner", xpBarFill).CornerRadius = UDim.new(0, 3)
		local xpLbl = Instance.new("TextLabel")
		xpLbl.Size = UDim2.new(0, xpLblW, 0, 18); xpLbl.Position = UDim2.new(1, -xpLblW - 3, 0, 6)
		xpLbl.BackgroundTransparency = 1; xpLbl.Font = Enum.Font.GothamMedium; xpLbl.TextSize = 8
		xpLbl.TextXAlignment = Enum.TextXAlignment.Right; xpLbl.TextColor3 = C.textMut; xpLbl.ZIndex = 2; xpLbl.Parent = card
		xpLbl.Text = lvl >= maxLvl and "MAX" or (tostring(xp) .. "/" .. tostring(xpNeeded))
	end

	-- Info line: rarity | element class | income | level (eggs: "Place on point to hatch")
	local elemClr = ELEMENT_COLOR[creature.element] or C.textMut
	local lvlText = lvl >= maxLvl and "MAX" or ("Lv." .. lvl)
	local infoText = isEgg
		and ((eggHidden and "Unknown" or (entry.rarity or creature.rarity)) .. " | Place on Income or Defense point to hatch")
		or (creature.rarity .. " | " .. (creature.element or "?") .. " " .. (creature.class or "?") .. " | " .. creature.baseIncome .. " c/t | " .. lvlText)
	local inf = Instance.new("TextLabel")
	inf.Size = UDim2.new(0, mobile and 204 or 286, 0, 14); inf.Position = UDim2.new(0, 12, 0, 24)
	inf.BackgroundTransparency = 1; inf.Text = infoText
	inf.TextColor3 = isEgg and Color3.fromRGB(255, 200, 80) or rc; inf.Font = Enum.Font.GothamMedium; inf.TextSize = mobile and 8 or 9
	inf.TextXAlignment = Enum.TextXAlignment.Left; inf.ZIndex = 2; inf.Parent = card

	local BTN_MIN_W = mobile and 44 or 48
	local BTN_MAX_W = mobile and 96 or 112
	local BTN_H = mobile and 22 or 24
	local BTN_GAP = mobile and 4 or 6
	local BTN_TEXT_SIZE = mobile and 8 or 9
	local BTN_TEXT_PADDING = mobile and 12 or 18
	local RIGHT_MARGIN = mobile and 8 or 6
	local BTN_ROW_Y = mobile and 54 or 52  -- extra gap keeps the action row clear of the card copy
	local nextBtnLeft = RIGHT_MARGIN
	local function getButtonWidth(text)
		local ok, textBounds = pcall(function()
			return TextService:GetTextSize(tostring(text or ""), BTN_TEXT_SIZE, Enum.Font.GothamBold, Vector2.new(1000, BTN_H))
		end)
		local measuredWidth = ok and textBounds.X or (#tostring(text or "") * (BTN_TEXT_SIZE + 1))
		return math.clamp(math.max(BTN_MIN_W, measuredWidth + BTN_TEXT_PADDING), BTN_MIN_W, BTN_MAX_W)
	end
	local function reserveButtonSlot(text)
		local width = getButtonWidth(text)
		local leftOffset = nextBtnLeft
		nextBtnLeft += width + BTN_GAP
		return leftOffset, width
	end

	-- Codex: click creature icon/name to open Codex (when feature flag on)
	if GameConfig.ENABLE_CODEX_UI and not eggHidden then
		local codexBtn = Instance.new("TextButton")
		codexBtn.Size = UDim2.new(0, mobile and 188 or 220, 0, 48)
		codexBtn.Position = UDim2.new(0, 8, 0, 6)
		codexBtn.BackgroundTransparency = 1
		codexBtn.Text = ""
		codexBtn.ZIndex = 2
		codexBtn.Parent = card
		local openCodexEvt = playerGui:FindFirstChild("OpenCodex")
		if openCodexEvt and openCodexEvt:IsA("BindableEvent") then
			codexBtn.MouseButton1Click:Connect(function()
				openCodexEvt:Fire(entry.id)
			end)
		end
	end

	-- Full-row selection target (sits above row body, below action buttons).
	local selectBtn = Instance.new("TextButton")
	selectBtn.Size = UDim2.new(1, 0, 1, 0)
	selectBtn.BackgroundTransparency = 1
	selectBtn.Text = ""
	selectBtn.AutoButtonColor = false
	selectBtn.ZIndex = 1
	selectBtn.Parent = card
	selectBtn.MouseButton1Click:Connect(function()
		if not entry.uid then return end
		local newUid = tostring(entry.uid)
		-- Update highlight locally (don’t refresh the whole inventory on selection;
		-- refresh causes viewport resets and can duplicate pooled viewers during scroll).
		if selectedInventoryUid and invCardByUid[tostring(selectedInventoryUid)] then
			local prev = invCardByUid[tostring(selectedInventoryUid)]
			local prevStroke = prev:FindFirstChild("SelectionStroke")
			if prevStroke and prevStroke:IsA("UIStroke") then
				prevStroke.Enabled = false
			end
		end
		selectedInventoryUid = newUid
		local cur = invCardByUid[newUid]
		if cur then
			local curStroke = cur:FindFirstChild("SelectionStroke")
			if curStroke and curStroke:IsA("UIStroke") then
				curStroke.Enabled = true
			end
		end
		if renderInventoryDetails then renderInventoryDetails(data, entry, creature) end
	end)

	-- Button row: fixed lower row so buttons don't overlap description text
	local function mkBtn(text, leftOffset, width, color, enabled)
		-- leftOffset = distance from card right edge to this button's left edge (positive = inset)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, width, 0, BTN_H)
		b.Position = UDim2.new(1, -leftOffset - width, 0, BTN_ROW_Y)
		b.BackgroundColor3 = enabled and color or C.divider
		b.Text = text; b.TextColor3 = enabled and Color3.new(1,1,1) or C.textMut
		b.Font = Enum.Font.GothamBold; b.TextSize = BTN_TEXT_SIZE; b.BorderSizePixel = 0
		b.Active = enabled
		b.ZIndex = 10  -- above Codex/overlays so clicks always register
		b.Parent = card
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
		return b
	end
	-- Right-to-left: Evolve, Defense, Income, Favorite, Sell — each left edge = prev left - BTN_W - BTN_GAP

	if isEgg then
		-- Eggs: Income and Defense are toggles (Income/Remove, Defense/Remove).
		-- When ADDING, pass nil so server uses first empty slot (not selected slot).
		local incLabelEgg = isBase and "Remove" or "Income"
		local defLabelEgg = isDef and "Remove" or "Defense"
		-- print("[InvRem] egg buttons: incLabel=" .. incLabelEgg, "defLabel=" .. defLabelEgg, "isBase=" .. tostring(isBase), "isDef=" .. tostring(isDef))
		local incEnabled = (isBase or (not baseFull and not isDef))
		local defEnabled = (isDef or (not defFull and not isBase))
		local defLeft, defWidth = reserveButtonSlot(defLabelEgg)
		local defBtn = mkBtn(defLabelEgg, defLeft, defWidth, isDef and Color3.fromRGB(55,50,50) or C.defense, defEnabled)
		defBtn.MouseButton1Click:Connect(function()
			if not Evt.assignToDefense or not defEnabled then return end
			invButtonDebounce(entry.uid, "defense", function()
				Evt.assignToDefense:FireServer(entry.uid, isDef and 0 or nil)
				pendingOptimistic[tostring(entry.uid)] = { def = not isDef, t = tick() }
				isDef = not isDef
				defBtn.Text = isDef and "Remove" or "Defense"
				defBtn.BackgroundColor3 = isDef and Color3.fromRGB(55,50,50) or C.defense
				task.delay(0.35, function() if refreshInventory then refreshInventory() end end)
			end)
		end)
		local incLeft, incWidth = reserveButtonSlot(incLabelEgg)
		local incBtn = mkBtn(incLabelEgg, incLeft, incWidth, isBase and Color3.fromRGB(50,55,60) or C.income, incEnabled)
		incBtn.MouseButton1Click:Connect(function()
			if not Evt.assignToBase or not incEnabled then return end
			invButtonDebounce(entry.uid, "base", function()
				Evt.assignToBase:FireServer(entry.uid, isBase and 0 or nil)
				pendingOptimistic[tostring(entry.uid)] = { base = not isBase, t = tick() }
				isBase = not isBase
				incBtn.Text = isBase and "Remove" or "Income"
				incBtn.BackgroundColor3 = isBase and Color3.fromRGB(50,55,60) or C.income
				task.delay(0.35, function() if refreshInventory then refreshInventory() end end)
			end)
		end)
	elseif isBattle then
		-- Battle team creatures: Dismiss + Sell buttons
		local sellLeft, sellWidth = reserveButtonSlot("Sell")
		local sellBtn = mkBtn("Sell", sellLeft, sellWidth, Color3.fromRGB(200, 60, 60), true)
		sellBtn.MouseButton1Click:Connect(function()
			if not Evt.sellCreature then return end
			invButtonDebounce(entry.uid, "sell", function()
				local ok, coins = Evt.sellCreature:InvokeServer(entry.uid)
				if ok then Notify.Toast("Sold for " .. coins .. " coins!", Color3.fromRGB(255, 200, 50), 2) end
				task.wait(0.3); refreshInventory()
			end)
		end)
		local dismissLeft, dismissWidth = reserveButtonSlot("Dismiss")
		local dismissBtn = mkBtn("Dismiss", dismissLeft, dismissWidth, Color3.fromRGB(120, 60, 60), true)
		dismissBtn.MouseButton1Click:Connect(function()
			if not Evt.removeFromBattle then return end
			invButtonDebounce(entry.uid, "dismiss", function()
				Evt.removeFromBattle:FireServer(entry.uid); task.wait(0.3); refreshInventory()
			end)
		end)
	else
		-- Normal creatures: Sell, Mount/Favorite, Income, Defense, Evolve (right-to-left)
		local isMountable = isFav and CreatureData.IsMountable and CreatureData.IsMountable(entry.id)
		local isMounted = isFav and player:GetAttribute("IsMounted") == true
		local sellLabel = "Sell"
		local favLabel = isFav and "Unfavorite" or "Favorite"
		local mountLabel = isMounted and "Dismount" or "Mount"
		local mountColor = isMounted and Color3.fromRGB(180, 80, 50) or Color3.fromRGB(50, 180, 120)

		-- Income/Defense: Remove = remove (send 0), Income/Defense = add to first empty slot (send nil).
		-- Server uses 0 as explicit remove. Disable Remove when creature is favorited (isFav and in that slot).
		local incEnabled = (isBase or (not baseFull and not isFav and not isDef)) and not (isFav and isBase)
		local incLabel = isBase and "Remove" or "Income"
		local defLabel = isDef and "Remove" or "Defense"
		-- #region agent log [InvRem] button labels for normal creatures (Rem = grey remove) (commented after UI fixes verified)
		-- print("[InvRem] normal creature buttons: incLabel=" .. incLabel, "defLabel=" .. defLabel, "isBase=" .. tostring(isBase), "isDef=" .. tostring(isDef))
		-- #endregion

		-- Evolve: only when creature can evolve in-game and meets level requirement (10 for base, 25 for evolved)
		local minEvolveLvl = CreatureData.GetEvolvesFrom and CreatureData.GetEvolvesFrom(entry.id) and (GameConfig.EvolutionMinLevel2 or 25) or (GameConfig.EvolutionMinLevel or 10)
		local canEvolve = (lvl >= minEvolveLvl) and CreatureData.CanEvolveInGame and CreatureData.CanEvolveInGame(entry.id)

		local evolveLeft, evolveWidth = reserveButtonSlot("Evolve")
		local defLeft, defWidth = reserveButtonSlot(defLabel)
		local incLeft, incWidth = reserveButtonSlot(incLabel)
		local mountLeft, mountWidth = nil, nil
		if isMountable then
			mountLeft, mountWidth = reserveButtonSlot(mountLabel)
		end
		local favLeft, favWidth = reserveButtonSlot(favLabel)
		local sellLeft, sellWidth = reserveButtonSlot(sellLabel)

		local sellBtn = mkBtn(sellLabel, sellLeft, sellWidth, Color3.fromRGB(200, 60, 60), not isFav)
		sellBtn.MouseButton1Click:Connect(function()
			if not isFav and Evt.sellCreature then
				invButtonDebounce(entry.uid, "sell", function()
					local ok, coins = Evt.sellCreature:InvokeServer(entry.uid)
					if ok then Notify.Toast("Sold for " .. coins .. " coins!", Color3.fromRGB(255, 200, 50), 2) end
					task.wait(0.3); refreshInventory()
				end)
			end
		end)

		local favBtn = mkBtn(favLabel, favLeft, favWidth, isFav and Color3.fromRGB(60,55,30) or C.favorite, true)
		favBtn.MouseButton1Click:Connect(function()
			if not Evt.setFavorite then return end
			invButtonDebounce(entry.uid, "fav", function()
				-- FIX #20: Clear any optimistic Inc/Def state for this creature since
				-- setFavorite calls removeFromAllSlots on the server (clears base/defense).
				pendingOptimistic[tostring(entry.uid)] = nil
				if isFav then
					Evt.setFavorite:FireServer("")
					task.wait(0.4)
					refreshInventory()
					updateFavOrb()
					return
				end
				local playEvt = playerGui:FindFirstChild("PlayFavoriteCardAnimation")
				if playEvt and playEvt:IsA("BindableEvent") then playEvt:Fire(entry.id) end
				Evt.setFavorite:FireServer(entry.uid)
				task.wait(0.4)
				refreshInventory()
				companionOut = true
				updateFavOrb()
				task.delay(0.5, function() refreshInventory(); updateFavOrb() end)
			end)
		end)

		if isMountable then
			local mountBtn = mkBtn(mountLabel, mountLeft, mountWidth, mountColor, true)
			mountBtn.MouseButton1Click:Connect(function()
				invButtonDebounce(entry.uid, "mount", function()
					if isMounted then
						if Evt.dismountRequest then Evt.dismountRequest:FireServer() end
					else
						if Evt.mountRequest then Evt.mountRequest:FireServer() end
					end
					task.wait(0.5)
					refreshInventory()
				end)
			end)
		end

		local incBtn = mkBtn(incLabel, incLeft, incWidth, isBase and Color3.fromRGB(50,55,60) or C.income, incEnabled)
		incBtn.MouseButton1Click:Connect(function()
			if not Evt.assignToBase or not incEnabled then return end
			invButtonDebounce(entry.uid, "base", function()
				Evt.assignToBase:FireServer(entry.uid, isBase and 0 or nil)
				pendingOptimistic[tostring(entry.uid)] = { base = not isBase, t = tick() }
				isBase = not isBase
				incBtn.Text = isBase and "Remove" or "Income"
				incBtn.BackgroundColor3 = isBase and Color3.fromRGB(50,55,60) or C.income
				task.delay(0.35, function() if refreshInventory then refreshInventory() end end)
			end)
		end)

		local defEnabled = (isDef or (not defFull and not isFav and not isBase)) and not (isFav and isDef)
		local defBtn = mkBtn(defLabel, defLeft, defWidth, isDef and Color3.fromRGB(55,50,50) or C.defense, defEnabled)
		defBtn.MouseButton1Click:Connect(function()
			if not Evt.assignToDefense or not defEnabled then return end
			invButtonDebounce(entry.uid, "defense", function()
				Evt.assignToDefense:FireServer(entry.uid, isDef and 0 or nil)
				pendingOptimistic[tostring(entry.uid)] = { def = not isDef, t = tick() }
				isDef = not isDef
				defBtn.Text = isDef and "Remove" or "Defense"
				defBtn.BackgroundColor3 = isDef and Color3.fromRGB(55,50,50) or C.defense
				task.delay(0.35, function() if refreshInventory then refreshInventory() end end)
			end)
		end)

		local evolveBtn = mkBtn("Evolve", evolveLeft, evolveWidth, Color3.fromRGB(180, 100, 255), canEvolve)
		evolveBtn.MouseButton1Click:Connect(function()
			if canEvolve and Evt.evolveCreature then
				invButtonDebounce(entry.uid, "evolve", function()
					Evt.evolveCreature:FireServer(entry.uid)
				end)
			end
		end)
	end

	return card
end

-- --------------------------------------------
-- BATTLE TAB - YOUR FORMATION + AFFINITY
-- --------------------------------------------
refreshBattle = function()
	local restoreScroll = captureScrollPosition()
	for _, ch in ipairs(content:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	local invData = nil
	if Evt.getInventory then
		local ok, r = pcall(function() return Evt.getInventory:InvokeServer() end)
		if ok and r then invData = r end
	end
	if not invData then
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 50); lbl.BackgroundTransparency = 1
		lbl.Text = "Loading..."; lbl.TextColor3 = C.textMut
		lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13; lbl.Parent = content
		restoreScroll()
		return
	end

	-- Floor 2 ownership gating — battle requires Floor 2
	local ownedFloors = invData.ownedFloors or {1}
	local ownsFloor2 = false
	for _, f in ipairs(ownedFloors) do if f == 2 then ownsFloor2 = true; break end end
	if not ownsFloor2 then
		local lockLbl = Instance.new("TextLabel")
		lockLbl.Size = UDim2.new(1, 0, 0, 80); lockLbl.BackgroundTransparency = 1
		lockLbl.Text = "BATTLE SYSTEM LOCKED\nPurchase Floor 2 upgrade to unlock!\nRequires Player Level " .. (GameConfig.Floor2LevelReq or 5)
		lockLbl.TextColor3 = C.textMut; lockLbl.Font = Enum.Font.GothamBold
		lockLbl.TextSize = 14; lockLbl.TextWrapped = true; lockLbl.Parent = content
		restoreScroll()
		return
	end

	-- Battle team active state (affects arena queue)
	local battleTeamEnabled = invData.battleTeamEnabled ~= false

	-- Read server battle team: prefer battleTeamSlots (array) so sparse keys are never lost over remotes
	local serverBT = invData.battleTeam or {}
	local battleTeamSlots = invData.battleTeamSlots or {}
	local battleCreatureCap = tonumber(invData.battleMax) or tonumber(GameConfig.MaxBattleTeamCreatures) or 5
	if battleCreatureCap < 1 then battleCreatureCap = 5 end
	local uidToEntry = {}
	for _, e in ipairs(invData.inventory) do uidToEntry[e.uid] = e end

	-- Build grid data + count elements/classes
	local gridData = {}  -- [number slotIndex] -> creature info
	local battleTeam = {}
	local elementCounts = {}
	local classCounts = {}

	local function addSlotEntry(slot, uid)
		local e = uidToEntry[uid]
		if e then
			local cr = CreatureData.GetById(e.id)
			if cr then
				local entry = {
					uid = uid, id = e.id, slotIndex = slot,
					displayName = cr.displayName, rarity = cr.rarity,
					health = cr.health, attack = cr.attack,
					defense = cr.defense, speed = cr.speed,
					primaryColor = cr.primaryColor,
					element = cr.element or "", class = cr.class or "",
				}
				gridData[slot] = entry
				table.insert(battleTeam, entry)
				if cr.element and cr.element ~= "" then
					elementCounts[cr.element] = (elementCounts[cr.element] or 0) + 1
				end
				if cr.class and cr.class ~= "" then
					classCounts[cr.class] = (classCounts[cr.class] or 0) + 1
				end
			end
		end
	end

	-- Build merged slot->uid: server data first, then optimistic adds (instant UI update before server confirms)
	local mergedSlots = {}
	if #battleTeamSlots > 0 then
		for _, t in ipairs(battleTeamSlots) do
			if t and type(t.slot) == "number" and type(t.uid) == "string" and t.uid ~= "" then
				mergedSlots[t.slot] = t.uid
			end
		end
	else
		for slotStr, uid in pairs(serverBT) do
			local slot = tonumber(slotStr)
			if slot and uid and uid ~= "" then mergedSlots[slot] = uid end
		end
	end
	for slot, uid in pairs(pendingBattleOptimistic) do
		if type(slot) == "number" and uid and uid ~= "" then
			mergedSlots[slot] = uid
		end
	end
	-- Clear optimistic when server has confirmed (prevents stale state)
	local serverHas = {}
	if #battleTeamSlots > 0 then
		for _, t in ipairs(battleTeamSlots) do
			if t and type(t.slot) == "number" and type(t.uid) == "string" and t.uid ~= "" then
				serverHas[t.slot] = t.uid
			end
		end
	else
		for slotStr, uid in pairs(serverBT) do
			local s = tonumber(slotStr)
			if s and uid and uid ~= "" then serverHas[s] = uid end
		end
	end
	for slot, uid in pairs(pendingBattleOptimistic) do
		if serverHas[slot] == uid then pendingBattleOptimistic[slot] = nil end
	end
	for slot, uid in pairs(mergedSlots) do addSlotEntry(slot, uid) end
	table.sort(battleTeam, function(a, b) return a.slotIndex < b.slotIndex end)
	local activeSynergies = {}
	if CreatureData.CalculateSynergies then
		local teamIds = {}
		for _, c in ipairs(battleTeam) do
			table.insert(teamIds, c.id)
		end
		local syn = nil
		local okSyn, errSyn = pcall(function()
			syn = select(1, CreatureData.CalculateSynergies(teamIds))
		end)
		if okSyn and type(syn) == "table" then
			activeSynergies = syn
		elseif not okSyn then
			warn("[InventoryUI] CalculateSynergies failed: " .. tostring(errSyn))
		end
	end
	table.sort(activeSynergies, function(a, b)
		local at = (a and a.traitType) or ""
		local bt = (b and b.traitType) or ""
		if at ~= bt then return at < bt end
		local ac = (a and a.count) or 0
		local bc = (b and b.count) or 0
		if ac ~= bc then return ac > bc end
		return tostring((a and a.trait) or "") < tostring((b and b.trait) or "")
	end)
	local canPlaceMore = #battleTeam < battleCreatureCap
	if pendingBattleUid and not canPlaceMore then pendingBattleUid = nil end

	-- Find unassigned creatures (use gridData so battle-assigned matches what we displayed)
	local assigned = {}
	for _, u in ipairs(invData.baseSlots or {}) do if u and u ~= "" then assigned[tostring(u)] = true end end
	for _, u in ipairs(invData.defenseSlots or {}) do if u and u ~= "" then assigned[tostring(u)] = true end end
	if invData.favoriteUid then assigned[tostring(invData.favoriteUid)] = true end
	for _, entry in ipairs(battleTeam) do if entry.uid then assigned[tostring(entry.uid)] = true end end

	local available = {}
	for _, e in ipairs(invData.inventory) do
		if not assigned[e.uid] and not assigned[tostring(e.uid)] then
			local cr = CreatureData.GetById(e.id)
			if cr then table.insert(available, { uid = e.uid, id = e.id, cr = cr }) end
		end
	end

	-- Arena info
	local arenaInfo = nil
	if Evt.getBattleInfo then
		local ok2, r2 = pcall(function() return Evt.getBattleInfo:InvokeServer() end)
		if ok2 and r2 then arenaInfo = r2 end
	end

	-- Mobile: monster selection is a true sub-menu (modal outside main panel); desktop: sidebar
	local mobile = isMobileLayout()
	local SIDEBAR_WIDTH = mobile and 0 or 190
	local battleLayout = Instance.new("Frame")
	battleLayout.Size = UDim2.new(1, 0, 0, 0)
	battleLayout.AutomaticSize = Enum.AutomaticSize.Y
	battleLayout.BackgroundTransparency = 1
	battleLayout.LayoutOrder = 0
	battleLayout.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 10)
	layout.Parent = battleLayout

	local leftCol = Instance.new("Frame")
	leftCol.Size = UDim2.new(1, mobile and 0 or (-SIDEBAR_WIDTH - 10), 0, 0)
	leftCol.AutomaticSize = Enum.AutomaticSize.Y
	leftCol.BackgroundTransparency = 1
	leftCol.LayoutOrder = 1
	leftCol.Parent = battleLayout

	local leftList = Instance.new("UIListLayout")
	leftList.SortOrder = Enum.SortOrder.LayoutOrder
	leftList.Padding = UDim.new(0, 5)
	leftList.Parent = leftCol

	-- Tooltip: no battle team — create one to fight in arena and gym
	if #battleTeam == 0 then
		local noTeamTip = Instance.new("Frame")
		noTeamTip.Size = UDim2.new(1, 0, 0, 44)
		noTeamTip.BackgroundColor3 = Color3.fromRGB(50, 55, 75)
		noTeamTip.BackgroundTransparency = 0.2
		noTeamTip.BorderSizePixel = 0
		noTeamTip.LayoutOrder = -1
		noTeamTip.Parent = leftCol
		Instance.new("UICorner", noTeamTip).CornerRadius = UDim.new(0, 8)
		local noTeamLbl = Instance.new("TextLabel")
		noTeamLbl.Size = UDim2.new(1, -16, 1, 0)
		noTeamLbl.Position = UDim2.new(0, 8, 0, 0)
		noTeamLbl.BackgroundTransparency = 1
		noTeamLbl.Text = "Create a battle team to fight in the arena and in gym battles. Tap 'Set Battle Team' or place creatures in the grid below."
		noTeamLbl.TextColor3 = C.battle
		noTeamLbl.Font = Enum.Font.GothamBold
		noTeamLbl.TextSize = 10
		noTeamLbl.TextWrapped = true
		noTeamLbl.TextXAlignment = Enum.TextXAlignment.Left
		noTeamLbl.Parent = noTeamTip
	end

	-- Monster sidebar: hidden on mobile (use Add Monster modal instead)
	local rightSidebar = Instance.new("ScrollingFrame")
	rightSidebar.Size = UDim2.new(0, SIDEBAR_WIDTH, 0, 420)
	rightSidebar.Visible = not mobile
	rightSidebar.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	rightSidebar.BorderSizePixel = 0
	rightSidebar.ScrollBarThickness = 4
	rightSidebar.ScrollBarImageColor3 = C.scroll
	rightSidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightSidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightSidebar.LayoutOrder = 2
	rightSidebar.Parent = battleLayout
	Instance.new("UICorner", rightSidebar).CornerRadius = UDim.new(0, 8)

	local sidebarList = Instance.new("UIListLayout")
	sidebarList.SortOrder = Enum.SortOrder.LayoutOrder
	sidebarList.Padding = UDim.new(0, 4)
	sidebarList.Parent = rightSidebar

	-- Open monster selection as sub-menu modal (true sub-menu outside main battle panel)
	-- targetSlotIndex: if provided, Place assigns directly to that slot (e.g. when tapping empty formation slot)
	local function openMonsterSelectionModal(targetSlotIndex)
		local modal = Instance.new("TextButton")
		modal.Name = "MonsterSelectionModal"
		modal.Size = UDim2.new(1, 0, 1, 0)
		modal.Position = UDim2.new(0, 0, 0, 0)
		modal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		modal.BackgroundTransparency = 0.5
		modal.BorderSizePixel = 0
		modal.Text = ""
		modal.AutoButtonColor = false
		modal.ZIndex = 50
		modal.Parent = sg
		local inner = Instance.new("Frame")
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(400, 600)
		local mw = math.min(340, vp.X - 40)
		local mh = math.min(450, vp.Y - 80)
		inner.Size = UDim2.new(0, mw, 0, mh)
		inner.Position = UDim2.new(0.5, -mw/2, 0.5, -mh/2)
		inner.BackgroundColor3 = C.bg
		inner.BorderSizePixel = 0
		inner.ZIndex = 51
		inner.Parent = modal
		Instance.new("UICorner", inner).CornerRadius = UDim.new(0, 12)
		local closeBtn = Instance.new("TextButton")
		closeBtn.Size = UDim2.new(0, 36, 0, 36); closeBtn.Position = UDim2.new(1, -42, 0, 6)
		closeBtn.BackgroundColor3 = C.card; closeBtn.Text = "X"; closeBtn.TextColor3 = C.textSec
		closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 14
		closeBtn.ZIndex = 52; closeBtn.Parent = inner
		Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
		local modalTitle = Instance.new("TextLabel")
		modalTitle.Size = UDim2.new(1, -50, 0, 28); modalTitle.Position = UDim2.new(0, 14, 0, 8)
		modalTitle.BackgroundTransparency = 1; modalTitle.Text = "Select Monster to Place"
		modalTitle.TextColor3 = C.accent; modalTitle.Font = Enum.Font.GothamBold; modalTitle.TextSize = 12
		modalTitle.ZIndex = 52; modalTitle.Parent = inner
		-- Viewport: show selected creature in confirmation area
		local modalViewerHost = Instance.new("Frame")
		modalViewerHost.Name = "ModalViewerHost"
		modalViewerHost.Size = UDim2.new(1, -24, 0, 120)
		modalViewerHost.Position = UDim2.new(0, 12, 0, 38)
		modalViewerHost.BackgroundColor3 = C.card
		modalViewerHost.BorderSizePixel = 0
		modalViewerHost.ZIndex = 51
		modalViewerHost.Parent = inner
		Instance.new("UICorner", modalViewerHost).CornerRadius = UDim.new(0, 8)
		local modalViewer = nil
		if CodexModelViewer then
			modalViewer = CodexModelViewer.new(modalViewerHost, {
				size = UDim2.new(1, -8, 1, -8),
				autoRotate = true,
				zoomEnabled = false,
				showFloor = false,
				themedLighting = true,
				playIdleAnimation = true,
				interactable = false,
			})
		end
		local scroll = Instance.new("ScrollingFrame")
		scroll.Size = UDim2.new(1, -16, 1, -174); scroll.Position = UDim2.new(0, 8, 0, 164)
		scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 4; scroll.ZIndex = 52
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.Parent = inner
		local scrollList = Instance.new("UIListLayout")
		scrollList.SortOrder = Enum.SortOrder.LayoutOrder
		scrollList.Padding = UDim.new(0, 4)
		scrollList.Parent = scroll
		local selectedModalUid = nil
		local rowByUid = {}
		local function setModalSelection(uid, creatureId, creatureName)
			selectedModalUid = tostring(uid)
			for rowUid, rowFrame in pairs(rowByUid) do
				rowFrame.BackgroundColor3 = (rowUid == selectedModalUid) and Color3.fromRGB(40, 44, 62) or C.card
			end
			if creatureName and creatureName ~= "" then
				modalTitle.Text = "Select Monster to Place: " .. creatureName
			end
			-- Force a reset before applying the next model so stale model state
			-- never persists between submenu selections.
			if modalViewer then
				modalViewer:SetCreature(nil)
				task.defer(function()
					if modalViewer and selectedModalUid == tostring(uid) then
						modalViewer:SetCreature(creatureId)
					end
				end)
			end
		end
		for i, av in ipairs(available) do
			local cr = av.cr
			local rc = RARITY[cr.rarity] or C.textMut
			local uidStr = tostring(av.uid)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 52); row.BackgroundColor3 = C.card
			row.BorderSizePixel = 0; row.LayoutOrder = i; row.Parent = scroll
			rowByUid[uidStr] = row
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
			local pad = Instance.new("UIPadding", row)
			pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
			pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
			-- Select row: show this creature in the viewport above
			if modalViewer then
				local selectBtn = Instance.new("TextButton")
				selectBtn.Size = UDim2.new(1, -60, 1, 0); selectBtn.Position = UDim2.new(0, 0, 0, 0)
				selectBtn.BackgroundTransparency = 1; selectBtn.Text = ""; selectBtn.ZIndex = 2
				selectBtn.Parent = row
				selectBtn.MouseButton1Click:Connect(function()
					setModalSelection(av.uid, cr.id, cr.displayName)
				end)
			end
			local mo2 = Instance.new("Frame")
			mo2.Size = UDim2.new(0, 24, 0, 24); mo2.Position = UDim2.new(0, 4, 0, 0)
			mo2.BackgroundColor3 = cr.primaryColor; mo2.BorderSizePixel = 0; mo2.Parent = row
			Instance.new("UICorner", mo2).CornerRadius = UDim.new(1, 0)
			local nm2 = Instance.new("TextLabel")
			nm2.Size = UDim2.new(1, -70, 0, 14); nm2.Position = UDim2.new(0, 32, 0, 0)
			nm2.BackgroundTransparency = 1; nm2.Text = cr.displayName
			nm2.TextColor3 = C.text; nm2.Font = Enum.Font.GothamBold; nm2.TextSize = 10
			nm2.TextTruncate = Enum.TextTruncate.AtEnd; nm2.TextXAlignment = Enum.TextXAlignment.Left; nm2.Parent = row
			local affLbl = Instance.new("TextLabel")
			affLbl.Size = UDim2.new(1, -70, 0, 10); affLbl.Position = UDim2.new(0, 32, 0, 16)
			affLbl.BackgroundTransparency = 1
			affLbl.Text = (cr.element or "?") .. " " .. (cr.class or "?") .. " · " .. cr.rarity
			affLbl.TextColor3 = ELEMENT_COLOR[cr.element] or C.textMut
			affLbl.Font = Enum.Font.GothamMedium; affLbl.TextSize = 8
			affLbl.TextXAlignment = Enum.TextXAlignment.Left; affLbl.Parent = row
			local st2 = Instance.new("TextLabel")
			st2.Size = UDim2.new(1, -70, 0, 10); st2.Position = UDim2.new(0, 32, 0, 28)
			st2.BackgroundTransparency = 1
			st2.Text = "HP:" .. cr.health .. " ATK:" .. cr.attack .. " DEF:" .. cr.defense .. " SPD:" .. cr.speed
			st2.TextColor3 = C.textSec; st2.Font = Enum.Font.GothamMedium; st2.TextSize = 8
			st2.TextXAlignment = Enum.TextXAlignment.Left; st2.Parent = row
			local placeBtn = Instance.new("TextButton")
			if canPlaceMore then
				placeBtn.Size = UDim2.new(0, 52, 0, 24); placeBtn.Position = UDim2.new(1, -56, 0.5, -12)
				placeBtn.BackgroundColor3 = C.battle
				placeBtn.Text = "Place"; placeBtn.TextColor3 = Color3.new(1,1,1)
				placeBtn.Font = Enum.Font.GothamBold; placeBtn.TextSize = 10; placeBtn.BorderSizePixel = 0
				placeBtn.Active = true; placeBtn.Parent = row
				Instance.new("UICorner", placeBtn).CornerRadius = UDim.new(0, 5)
				placeBtn.MouseButton1Click:Connect(function()
					if canPlaceMore then
						setModalSelection(av.uid, cr.id, cr.displayName)
						if targetSlotIndex and Evt.assignToBattle then
							Evt.assignToBattle:FireServer(av.uid, targetSlotIndex)
							pendingBattleOptimistic[targetSlotIndex] = av.uid  -- instant UI update before server confirms
						else
							pendingBattleUid = av.uid
						end
						modal:Destroy()
						refreshBattle()
					end
				end)
			end
		end
		-- Show first creature in viewport by default
		if modalViewer and available[1] then
			setModalSelection(available[1].uid, available[1].cr.id, available[1].cr.displayName)
		end
		local function closeModal()
			if modalViewer and modalViewer.Destroy then
				modalViewer:SetCreature(nil)
				modalViewer:Destroy()
			end
			modal:Destroy()
		end
		closeBtn.MouseButton1Click:Connect(closeModal)
		modal.MouseButton1Click:Connect(closeModal)  -- Click backdrop to close
	end

	-- Pending placement bar
	if pendingBattleUid then
		local pendingCr = nil
		local pe = uidToEntry[pendingBattleUid]
		if pe then pendingCr = CreatureData.GetById(pe.id) end

		local instr = Instance.new("Frame")
		instr.Size = UDim2.new(1, 0, 0, 32); instr.BackgroundColor3 = C.battle
		instr.BackgroundTransparency = 0.3; instr.BorderSizePixel = 0; instr.LayoutOrder = -1
		instr.Parent = leftCol; Instance.new("UICorner", instr).CornerRadius = UDim.new(0, 8)

		local instrText = "Click a grid slot to place"
		if pendingCr then instrText = instrText .. " " .. pendingCr.displayName end
		local instrLbl = Instance.new("TextLabel")
		instrLbl.Size = UDim2.new(0.7, 0, 1, 0); instrLbl.Position = UDim2.new(0, 12, 0, 0)
		instrLbl.BackgroundTransparency = 1; instrLbl.Text = instrText
		instrLbl.TextColor3 = Color3.new(1,1,1); instrLbl.Font = Enum.Font.GothamBold
		instrLbl.TextSize = 11; instrLbl.TextXAlignment = Enum.TextXAlignment.Left; instrLbl.Parent = instr

		local cancelBtn = Instance.new("TextButton")
		cancelBtn.Size = UDim2.new(0, 60, 0, 22); cancelBtn.Position = UDim2.new(1, -68, 0.5, -11)
		cancelBtn.BackgroundColor3 = C.defense; cancelBtn.Text = "Cancel"
		cancelBtn.TextColor3 = Color3.new(1,1,1); cancelBtn.Font = Enum.Font.GothamBold
		cancelBtn.TextSize = 9; cancelBtn.BorderSizePixel = 0; cancelBtn.Parent = instr
		Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 5)
		cancelBtn.MouseButton1Click:Connect(function() pendingBattleUid = nil; refreshBattle() end)
	end

	-- Unified battle header card:
	-- - Row 1: status strip (inactive queue message OR king/arena/gym status).
	-- - Row 2: formation label + Set Battle Team + Active toggle.
	local function escapeRichText(s)
		return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	end

	local battleHeader = Instance.new("Frame")
	battleHeader.Size = UDim2.new(1, 0, 0, 62)
	battleHeader.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	battleHeader.BackgroundTransparency = 0
	battleHeader.BorderSizePixel = 0
	battleHeader.LayoutOrder = 0
	battleHeader.Parent = leftCol
	Instance.new("UICorner", battleHeader).CornerRadius = UDim.new(0, 8)

	local statusStrip = Instance.new("Frame")
	statusStrip.Size = UDim2.new(1, -8, 0, 28)
	statusStrip.Position = UDim2.new(0, 4, 0, 4)
	statusStrip.BackgroundColor3 = battleTeamEnabled and Color3.fromRGB(18, 20, 30) or Color3.fromRGB(80, 40, 40)
	statusStrip.BackgroundTransparency = battleTeamEnabled and 0 or 0.3
	statusStrip.BorderSizePixel = 0
	statusStrip.Parent = battleHeader
	Instance.new("UICorner", statusStrip).CornerRadius = UDim.new(0, 8)

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size = UDim2.new(1, -16, 1, 0)
	statusLbl.Position = UDim2.new(0, 8, 0, 0)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.TextSize = 10
	statusLbl.TextXAlignment = Enum.TextXAlignment.Left
	statusLbl.TextYAlignment = Enum.TextYAlignment.Center
	statusLbl.TextWrapped = false
	statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
	statusLbl.RichText = true
	statusLbl.Parent = statusStrip

	local kingName = arenaInfo and arenaInfo.kingName

	if not battleTeamEnabled then
		statusLbl.RichText = false
		statusLbl.TextColor3 = C.text
		statusLbl.Text = "Battle Team INACTIVE - Press ACTIVE below to rejoin arena queue."
	else
		local function updateActiveStatusLine()
			local timers = nil
			if Evt.getBattleTimers then
				local ok, result = pcall(function() return Evt.getBattleTimers:InvokeServer() end)
				if ok and result then timers = result end
			end
			if not timers then
				timers = {
					arenaCountdown = workspace:GetAttribute("ArenaCountdown") or 0,
					arenaBattleInProgress = workspace:GetAttribute("ArenaBattleInProgress") or false,
					gymBattleInProgress = workspace:GetAttribute("GymBattleInProgress") or false,
					gymCooldownRemaining = 0,
					arenaFighterBlueName = workspace:GetAttribute("ArenaFighterBlueName"),
					arenaFighterRedName = workspace:GetAttribute("ArenaFighterRedName"),
				}
			end

			local kingPart = kingName and ("<font color='#F5CD55'>KING</font> " .. escapeRichText(kingName))
				or "<font color='#AAB3C5'>KING None</font>"
			local arenaPart
			if timers.arenaBattleInProgress then
				local blueName = timers.arenaFighterBlueName
				local redName = timers.arenaFighterRedName
				if blueName and redName and blueName ~= "" and redName ~= "" then
					arenaPart = "<font color='#F15F5F'>ARENA </font>"
						.. "<font color='#F5CD55'>" .. escapeRichText(blueName) .. "</font>"
						.. "<font color='#D0D6E2'> vs </font>"
						.. "<font color='#F15F5F'>" .. escapeRichText(redName) .. "</font>"
				else
					arenaPart = "<font color='#F15F5F'>ARENA Fighting</font>"
				end
			elseif timers.arenaCountdown and timers.arenaCountdown > 0 then
				local arenaColor = (timers.arenaCountdown <= 10) and "#F5CD55" or "#5AAFFF"
				arenaPart = string.format("<font color='%s'>ARENA %ss</font>", arenaColor, tostring(timers.arenaCountdown))
			else
				arenaPart = "<font color='#5AAFFF'>ARENA Starting</font>"
			end
			local gymPart
			if timers.gymBattleInProgress then
				gymPart = "<font color='#F15F5F'>GYM Fighting</font>"
			elseif timers.gymCooldownRemaining and timers.gymCooldownRemaining > 0 then
				gymPart = "<font color='#AAB3C5'>GYM CD " .. tostring(timers.gymCooldownRemaining) .. "s</font>"
			else
				gymPart = "<font color='#6AD78A'>GYM Ready</font>"
			end

			statusLbl.TextColor3 = C.text
			statusLbl.Text = table.concat({ kingPart, arenaPart, gymPart }, "   <font color='#4A5368'>|</font>   ")
		end

		updateActiveStatusLine()
		task.spawn(function()
			while statusStrip and statusStrip.Parent and battleTeamEnabled do
				updateActiveStatusLine()
				task.wait(2)
			end
		end)
	end

	-- Formation controls are in the same header card as status.
	local gridLabelRow = Instance.new("Frame")
	gridLabelRow.Size = UDim2.new(1, -8, 0, 24)
	gridLabelRow.Position = UDim2.new(0, 4, 0, 34)
	gridLabelRow.BackgroundTransparency = 1
	gridLabelRow.Parent = battleHeader

	local gridLabel = Instance.new("TextLabel")
	-- Shrink when Set Battle Team button is shown (leaves room for both buttons)
	local hasSetBtn = (#available > 0 and not pendingBattleUid and canPlaceMore)
	gridLabel.Size = UDim2.new(1, hasSetBtn and -240 or -120, 1, 0)
	gridLabel.Position = UDim2.new(0, 0, 0, 0)
	gridLabel.BackgroundTransparency = 1
	gridLabel.Text = "YOUR BATTLE FORMATION (" .. #battleTeam .. "/" .. battleCreatureCap .. ")"
	gridLabel.TextColor3 = C.battle; gridLabel.Font = Enum.Font.GothamBold
	gridLabel.TextSize = 11; gridLabel.TextXAlignment = Enum.TextXAlignment.Left
	gridLabel.TextTruncate = Enum.TextTruncate.AtEnd
	gridLabel.Parent = gridLabelRow

	-- Set Battle Team button: to the left of Active/Inactive (mobile: opens modal; desktop: also opens modal)
	local setBattleTeamBtn = nil
	if #available > 0 and not pendingBattleUid and canPlaceMore then
		setBattleTeamBtn = Instance.new("TextButton")
		setBattleTeamBtn.Size = UDim2.new(0, 105, 0, 24)
		setBattleTeamBtn.Position = UDim2.new(1, -229, 0, 2)  -- left of Active/Inactive
		setBattleTeamBtn.BackgroundColor3 = C.battle
		setBattleTeamBtn.Text = "Set Battle Team"
		setBattleTeamBtn.TextColor3 = Color3.new(1,1,1)
		setBattleTeamBtn.Font = Enum.Font.GothamBold; setBattleTeamBtn.TextSize = 9
		setBattleTeamBtn.BorderSizePixel = 0; setBattleTeamBtn.Parent = gridLabelRow
		Instance.new("UICorner", setBattleTeamBtn).CornerRadius = UDim.new(0, 6)
		setBattleTeamBtn.MouseButton1Click:Connect(function() openMonsterSelectionModal() end)
	end

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0, 110, 0, 24); toggleBtn.Position = UDim2.new(1, -114, 0, 2)
	toggleBtn.BackgroundColor3 = battleTeamEnabled and C.battle or C.divider
	toggleBtn.Text = battleTeamEnabled and "ACTIVE" or "INACTIVE"
	toggleBtn.TextColor3 = battleTeamEnabled and Color3.new(1,1,1) or C.textSec
	toggleBtn.Font = Enum.Font.GothamBold; toggleBtn.TextSize = 10
	toggleBtn.BorderSizePixel = 0; toggleBtn.Parent = gridLabelRow
	Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)
	toggleBtn.MouseButton1Click:Connect(function()
		if not Evt.toggleBattleTeam then return end
		-- Optimistic update: flip button immediately
		local newState = not battleTeamEnabled
		toggleBtn.Text = newState and "ACTIVE" or "INACTIVE"
		toggleBtn.BackgroundColor3 = newState and C.battle or C.divider
		toggleBtn.TextColor3 = newState and Color3.new(1,1,1) or C.textSec
		local ok = pcall(function() return Evt.toggleBattleTeam:InvokeServer() end)
		if ok then
			-- Refresh so the inactive banner text goes away (or appears) and UI matches server
			refreshBattle()
		else
			-- Revert button if server call failed
			toggleBtn.Text = battleTeamEnabled and "ACTIVE" or "INACTIVE"
			toggleBtn.BackgroundColor3 = battleTeamEnabled and C.battle or C.divider
			toggleBtn.TextColor3 = battleTeamEnabled and Color3.new(1,1,1) or C.textSec
		end
	end)

	-- GRID + STATS PANEL
	-- Mobile now uses side-by-side layout so the stats panel fills the empty
	-- space next to the 3x3 map instead of sitting below it.
	local mapFrame = Instance.new("Frame")
	local mapH = mobile and 205 or 195
	mapFrame.Size = UDim2.new(1, 0, 0, mapH)
	mapFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	mapFrame.BorderSizePixel = 0; mapFrame.LayoutOrder = 1; mapFrame.Parent = leftCol
	Instance.new("UICorner", mapFrame).CornerRadius = UDim.new(0, 10)

	-- 3x3 grid
	for row = 0, 2 do
		for col = 0, 2 do
			local idx = row * 3 + col + 1
			local slotIdx = idx  -- capture for closure (avoid Lua loop variable capture bug)
			local px = col * 58 + 12
			local py = row * 58 + 8

			local slot = Instance.new("TextButton")
			slot.Size = UDim2.new(0, 50, 0, 50); slot.Position = UDim2.new(0, px, 0, py)
			slot.BackgroundColor3 = Color3.fromRGB(25, 27, 38); slot.BorderSizePixel = 0
			slot.Text = ""; slot.AutoButtonColor = true; slot.Parent = mapFrame
			Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)

			local slotStroke = Instance.new("UIStroke")
			slotStroke.Color = pendingBattleUid and C.battle or C.divider
			slotStroke.Thickness = pendingBattleUid and 2 or 1
			slotStroke.Transparency = pendingBattleUid and 0.2 or 0.5
			slotStroke.Parent = slot

			-- Slot number
			local numLbl = Instance.new("TextLabel")
			numLbl.Size = UDim2.new(1, 0, 0, 10); numLbl.Position = UDim2.new(0, 0, 1, -11)
			numLbl.BackgroundTransparency = 1; numLbl.Text = tostring(idx)
			numLbl.TextColor3 = C.textMut; numLbl.Font = Enum.Font.GothamMedium
			numLbl.TextSize = 7; numLbl.Parent = slot

			local ce = gridData[idx]
			if ce then
				local rc = RARITY[ce.rarity] or C.textMut
				-- Circular ring + masked viewport so creature stays inside circumference.
				local viewerRing = Instance.new("Frame")
				viewerRing.Name = "ViewerRing"
				viewerRing.Size = UDim2.new(0, 44, 0, 44)
				viewerRing.Position = UDim2.new(0.5, -22, 0, 2)
				viewerRing.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
				viewerRing.BorderSizePixel = 0
				viewerRing.ZIndex = 3
				viewerRing.Parent = slot
				Instance.new("UICorner", viewerRing).CornerRadius = UDim.new(1, 0)
				local stroke = Instance.new("UIStroke", viewerRing)
				stroke.Color = rc
				stroke.Thickness = 2
				stroke.Transparency = 0.2

				local viewerHost = Instance.new("Frame")
				viewerHost.Name = "ViewerHost"
				viewerHost.Size = UDim2.new(1, -4, 1, -4)
				viewerHost.Position = UDim2.new(0, 2, 0, 2)
				viewerHost.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
				viewerHost.BorderSizePixel = 0
				viewerHost.ClipsDescendants = true
				viewerHost.ZIndex = 2
				viewerHost.Parent = viewerRing
				Instance.new("UICorner", viewerHost).CornerRadius = UDim.new(1, 0)
				if CodexModelViewer then
					local slotViewer = CodexModelViewer.new(viewerHost, {
						size = UDim2.new(1, 0, 1, 0),
						autoRotate = true,
						zoomEnabled = false,
						showFloor = false,
						themedLighting = true,
						playIdleAnimation = true,
						interactable = false,
					})
					slotViewer:SetCreature(ce.id)
				else
					local orbF = Instance.new("Frame")
					orbF.Size = UDim2.new(1, 0, 1, 0); orbF.BackgroundColor3 = ce.primaryColor
					orbF.BorderSizePixel = 0; orbF.Parent = viewerHost
					Instance.new("UICorner", orbF).CornerRadius = UDim.new(1, 0)
				end

				-- Element/class indicator dot
				local elemClr = ELEMENT_COLOR[ce.element]
				if elemClr then
					local dot = Instance.new("Frame")
					dot.Size = UDim2.new(0, 8, 0, 8); dot.Position = UDim2.new(1, -10, 0, 2)
					dot.BackgroundColor3 = elemClr; dot.BorderSizePixel = 0; dot.Parent = slot
					Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
				end

				local tipLbl = Instance.new("TextLabel")
				tipLbl.Size = UDim2.new(0, 54, 0, 9); tipLbl.Position = UDim2.new(0.5, -27, 0, -9)
				tipLbl.BackgroundTransparency = 1; tipLbl.Text = ce.displayName
				tipLbl.TextColor3 = Color3.new(1,1,1); tipLbl.Font = Enum.Font.GothamBold
				tipLbl.TextSize = 7; tipLbl.TextTruncate = Enum.TextTruncate.AtEnd; tipLbl.Parent = slot

				slotStroke.Color = rc; slotStroke.Transparency = 0.2

				-- Right-click to remove (click while not placing)
				slot.MouseButton1Click:Connect(function()
					if pendingBattleUid then
						if Evt.assignToBattle then
							invButtonDebounce(tostring(pendingBattleUid) .. "_" .. tostring(slotIdx), "assignBattle", function()
								local uid = pendingBattleUid
								Evt.assignToBattle:FireServer(uid, slotIdx)
								pendingBattleOptimistic[slotIdx] = uid  -- instant UI update before server confirms
								pendingBattleUid = nil; task.wait(0.3); refreshBattle()
							end)
						end
					else
						-- Click on occupied slot = remove from battle
						if Evt.removeFromBattle then
							invButtonDebounce(ce.uid, "dismiss", function()
								Evt.removeFromBattle:FireServer(ce.uid); task.wait(0.3); refreshBattle()
							end)
						end
					end
				end)
			else
				-- Empty slot: place from pending, or tap/click to open monster selection
				slot.MouseButton1Click:Connect(function()
					if pendingBattleUid and Evt.assignToBattle then
						invButtonDebounce(tostring(pendingBattleUid) .. "_" .. tostring(slotIdx), "assignBattle", function()
							local uid = pendingBattleUid
							Evt.assignToBattle:FireServer(uid, slotIdx)
							pendingBattleOptimistic[slotIdx] = uid  -- instant UI update before server confirms
							pendingBattleUid = nil; task.wait(0.3); refreshBattle()
						end)
					elseif #available > 0 and canPlaceMore then
						-- Tap empty slot to open monster selection; Place assigns directly to this slot (one tap)
						openMonsterSelectionModal(slotIdx)
					end
				end)
			end
		end
	end

	-- Stats panel: desktop + mobile both sit to the right of the 3x3 grid.
	local statsBox = Instance.new("Frame")
	if mobile then
		statsBox.Size = UDim2.new(1, -208, 0, 185)
		statsBox.Position = UDim2.new(0, 200, 0, 5)
	else
		statsBox.Size = UDim2.new(0, 330, 0, 185)
		statsBox.Position = UDim2.new(0, 200, 0, 5)
	end
	statsBox.BackgroundColor3 = Color3.fromRGB(22, 24, 35); statsBox.BorderSizePixel = 0
	statsBox.Parent = mapFrame
	Instance.new("UICorner", statsBox).CornerRadius = UDim.new(0, 8)

	local yOff = 6
	for i, c in ipairs(battleTeam) do
		if i > battleCreatureCap then break end
		local rc = RARITY[c.rarity] or C.textMut
		local miniRow = Instance.new("Frame")
		miniRow.Size = UDim2.new(1, -12, 0, 30); miniRow.Position = UDim2.new(0, 6, 0, yOff)
		miniRow.BackgroundColor3 = Color3.fromRGB(28, 30, 42); miniRow.BorderSizePixel = 0
		miniRow.Parent = statsBox; Instance.new("UICorner", miniRow).CornerRadius = UDim.new(0, 5)

		-- Slot number
		local slotNum = Instance.new("TextLabel")
		slotNum.Size = UDim2.new(0, 14, 1, 0); slotNum.Position = UDim2.new(0, 2, 0, 0)
		slotNum.BackgroundTransparency = 1; slotNum.Text = tostring(c.slotIndex)
		slotNum.TextColor3 = C.battle; slotNum.Font = Enum.Font.GothamBold; slotNum.TextSize = 9
		slotNum.Parent = miniRow

		-- Mini orb
		local mo = Instance.new("Frame")
		mo.Size = UDim2.new(0, 14, 0, 14); mo.Position = UDim2.new(0, 18, 0.5, -7)
		mo.BackgroundColor3 = c.primaryColor; mo.BorderSizePixel = 0; mo.Parent = miniRow
		Instance.new("UICorner", mo).CornerRadius = UDim.new(1, 0)

		-- Name
		local mn = Instance.new("TextLabel")
		mn.Size = UDim2.new(0, 70, 0, 12); mn.Position = UDim2.new(0, 36, 0, 2)
		mn.BackgroundTransparency = 1; mn.Text = c.displayName; mn.TextTruncate = Enum.TextTruncate.AtEnd
		mn.TextColor3 = C.text; mn.Font = Enum.Font.GothamBold; mn.TextSize = 9
		mn.TextXAlignment = Enum.TextXAlignment.Left; mn.Parent = miniRow

		-- Element + Class
		local elemClr = ELEMENT_COLOR[c.element] or C.textMut
		local clsClr = CLASS_COLOR[c.class] or C.textMut
		local affinityLbl = Instance.new("TextLabel")
		affinityLbl.Size = UDim2.new(0, 100, 0, 10); affinityLbl.Position = UDim2.new(0, 36, 0, 16)
		affinityLbl.BackgroundTransparency = 1
		affinityLbl.Text = (c.element or "?") .. " " .. (c.class or "?")
		affinityLbl.TextColor3 = elemClr; affinityLbl.Font = Enum.Font.GothamMedium; affinityLbl.TextSize = 8
		affinityLbl.TextXAlignment = Enum.TextXAlignment.Left; affinityLbl.Parent = miniRow

		-- Stats
		local ms = Instance.new("TextLabel")
		ms.Size = UDim2.new(0, 140, 1, 0); ms.Position = UDim2.new(0, 140, 0, 0)
		ms.BackgroundTransparency = 1
		ms.Text = "HP:" .. c.health .. " ATK:" .. c.attack .. " DEF:" .. c.defense .. " SPD:" .. c.speed
		ms.TextColor3 = C.textSec; ms.Font = Enum.Font.GothamMedium; ms.TextSize = 8
		ms.TextXAlignment = Enum.TextXAlignment.Left; ms.Parent = miniRow

		if GameConfig.ENABLE_CODEX_UI then
			local codexGridBtn = Instance.new("TextButton")
			codexGridBtn.Size = UDim2.new(0, 138, 0, 34)
			codexGridBtn.Position = UDim2.new(0, 16, 0, 0)
			codexGridBtn.BackgroundTransparency = 1
			codexGridBtn.Text = ""
			codexGridBtn.ZIndex = 2
			codexGridBtn.Parent = miniRow
			local openCodexEvt = playerGui:FindFirstChild("OpenCodex")
			if openCodexEvt and openCodexEvt:IsA("BindableEvent") then
				codexGridBtn.MouseButton1Click:Connect(function()
					openCodexEvt:Fire(c.id)
				end)
			end
		end

		yOff = yOff + 34
	end

	if #battleTeam == 0 then
		local emptyLbl = Instance.new("TextLabel")
		emptyLbl.Size = UDim2.new(1, -12, 0, 60); emptyLbl.Position = UDim2.new(0, 6, 0, 10)
		emptyLbl.BackgroundTransparency = 1
		emptyLbl.Text = mobile
			and "No battle team!\nTap 'Set Battle Team' or an empty slot."
			or "No battle team!\nTap 'Set Battle Team', an empty slot,\nor Place on creatures at right."
		emptyLbl.TextColor3 = C.textMut; emptyLbl.Font = Enum.Font.GothamMedium
		emptyLbl.TextSize = 10; emptyLbl.TextWrapped = true; emptyLbl.Parent = statsBox
	end

	-- AFFINITY / SYNERGY DISPLAY (moved below team view)
	local synergyFrame = Instance.new(mobile and "ScrollingFrame" or "Frame")
	synergyFrame.Size = UDim2.new(1, 0, 0, 42)
	synergyFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	synergyFrame.BorderSizePixel = 0
	synergyFrame.LayoutOrder = 2
	synergyFrame.Parent = leftCol
	Instance.new("UICorner", synergyFrame).CornerRadius = UDim.new(0, 8)
	if mobile then
		synergyFrame.ScrollBarThickness = 4
		synergyFrame.ScrollingDirection = Enum.ScrollingDirection.X
		synergyFrame.CanvasSize = UDim2.new(0, 520, 0, 42)  -- wide enough for elements+classes
	end

	-- Element counts row
	local elemX = 8
	for elem, clr in pairs(ELEMENT_COLOR) do
		local cnt = elementCounts[elem] or 0
		local eLbl = Instance.new("TextLabel")
		eLbl.Size = UDim2.new(0, 70, 0, 16); eLbl.Position = UDim2.new(0, elemX, 0, 3)
		eLbl.BackgroundTransparency = 1
		eLbl.Text = elem .. ": " .. cnt
		eLbl.TextColor3 = cnt > 0 and clr or C.textMut
		eLbl.Font = cnt >= 2 and Enum.Font.GothamBold or Enum.Font.GothamMedium
		eLbl.TextSize = 9; eLbl.TextXAlignment = Enum.TextXAlignment.Left
		eLbl.Parent = synergyFrame
		elemX = elemX + 74
	end

	-- Class counts row
	local clsX = 8
	for cls, clr in pairs(CLASS_COLOR) do
		local cnt = classCounts[cls] or 0
		local cLbl = Instance.new("TextLabel")
		cLbl.Size = UDim2.new(0, 80, 0, 16); cLbl.Position = UDim2.new(0, clsX, 0, 22)
		cLbl.BackgroundTransparency = 1
		cLbl.Text = cls .. ": " .. cnt
		cLbl.TextColor3 = cnt > 0 and clr or C.textMut
		cLbl.Font = cnt >= 2 and Enum.Font.GothamBold or Enum.Font.GothamMedium
		cLbl.TextSize = 9; cLbl.TextXAlignment = Enum.TextXAlignment.Left
		cLbl.Parent = synergyFrame
		clsX = clsX + 85
	end

	-- Active bonus details (shown only when any synergy is active)
	if #activeSynergies > 0 then
		local bonusFrame = Instance.new("Frame")
		local bonusRows = math.min(#activeSynergies, 6)
		bonusFrame.Size = UDim2.new(1, 0, 0, 24 + bonusRows * 16)
		bonusFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
		bonusFrame.BorderSizePixel = 0
		bonusFrame.LayoutOrder = 3
		bonusFrame.Parent = leftCol
		Instance.new("UICorner", bonusFrame).CornerRadius = UDim.new(0, 8)

		local bonusTitle = Instance.new("TextLabel")
		bonusTitle.Size = UDim2.new(1, -12, 0, 16)
		bonusTitle.Position = UDim2.new(0, 8, 0, 4)
		bonusTitle.BackgroundTransparency = 1
		bonusTitle.Text = "ACTIVE BONUSES"
		bonusTitle.TextColor3 = C.favorite
		bonusTitle.Font = Enum.Font.GothamBold
		bonusTitle.TextSize = 10
		bonusTitle.TextXAlignment = Enum.TextXAlignment.Left
		bonusTitle.Parent = bonusFrame

		local function formatBonusText(bonuses)
			local out = {}
			local order = { "health", "attack", "defense", "speed" }
			local labelByStat = { health = "HP", attack = "ATK", defense = "DEF", speed = "SPD" }
			for _, stat in ipairs(order) do
				local v = bonuses and bonuses[stat]
				if type(v) == "number" and v ~= 0 then
					local sign = v > 0 and "+" or ""
					table.insert(out, string.format("%s%s%.0f%%", labelByStat[stat], sign, v * 100))
				end
			end
			return (#out > 0) and table.concat(out, "  ") or "No stat changes"
		end

		for i = 1, bonusRows do
			local syn = activeSynergies[i]
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, -12, 0, 14)
			row.Position = UDim2.new(0, 8, 0, 8 + i * 16)
			row.BackgroundTransparency = 1
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Font = Enum.Font.GothamMedium
			row.TextSize = 9
			row.TextColor3 = C.text
			row.RichText = true
			local traitColor = "#CFCFCF"
			if syn and syn.color then
				traitColor = string.format("#%02X%02X%02X", math.floor(syn.color.R * 255), math.floor(syn.color.G * 255), math.floor(syn.color.B * 255))
			end
			local traitText = escapeRichText((syn and syn.trait) or "?")
			local labelText = escapeRichText((syn and syn.label) or "Bonus")
			local bonusText = escapeRichText(formatBonusText(syn and syn.bonuses))
			row.Text = string.format(
				"<font color='%s'>%s x%d</font> - %s: <font color='#D7DCEC'>%s</font>",
				traitColor,
				traitText,
				tonumber((syn and syn.count) or 0) or 0,
				labelText,
				bonusText
			)
			row.Parent = bonusFrame
		end
	end

	-- SIDEBAR: AVAILABLE CREATURES (desktop only - mobile uses Set Battle Team button + tap empty slot)
	if not mobile and #available > 0 and not pendingBattleUid then
		local availHeader = Instance.new("TextLabel")
		availHeader.Size = UDim2.new(1, -8, 0, 18); availHeader.BackgroundTransparency = 1
		availHeader.Text = "AVAILABLE (" .. #available .. ")"
		availHeader.TextColor3 = C.textSec; availHeader.Font = Enum.Font.GothamBold
		availHeader.TextSize = 9; availHeader.TextXAlignment = Enum.TextXAlignment.Left
		availHeader.LayoutOrder = 0; availHeader.Parent = rightSidebar

		for i, av in ipairs(available) do
			local cr = av.cr
			local rc = RARITY[cr.rarity] or C.textMut
			local elemClr = ELEMENT_COLOR[cr.element] or C.textMut

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 52); row.BackgroundColor3 = C.card
			row.BorderSizePixel = 0; row.LayoutOrder = i; row.Parent = rightSidebar
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
			local pad = Instance.new("UIPadding", row)
			pad.PaddingLeft = UDim.new(0, 4); pad.PaddingRight = UDim.new(0, 4)
			pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)

			local mo2 = Instance.new("Frame")
			mo2.Size = UDim2.new(0, 20, 0, 20); mo2.Position = UDim2.new(0, 4, 0, 0)
			mo2.BackgroundColor3 = cr.primaryColor; mo2.BorderSizePixel = 0; mo2.Parent = row
			Instance.new("UICorner", mo2).CornerRadius = UDim.new(1, 0)

			local nm2 = Instance.new("TextLabel")
			nm2.Size = UDim2.new(1, -60, 0, 12); nm2.Position = UDim2.new(0, 28, 0, 0)
			nm2.BackgroundTransparency = 1; nm2.Text = cr.displayName
			nm2.TextColor3 = C.text; nm2.Font = Enum.Font.GothamBold; nm2.TextSize = 9
			nm2.TextTruncate = Enum.TextTruncate.AtEnd
			nm2.TextXAlignment = Enum.TextXAlignment.Left; nm2.Parent = row

			-- Succinct: "Fire Assassin · Common"
			local affLbl = Instance.new("TextLabel")
			affLbl.Size = UDim2.new(1, -60, 0, 10); affLbl.Position = UDim2.new(0, 28, 0, 14)
			affLbl.BackgroundTransparency = 1
			affLbl.Text = (cr.element or "?") .. " " .. (cr.class or "?") .. " · " .. cr.rarity
			affLbl.TextColor3 = elemClr; affLbl.Font = Enum.Font.GothamMedium; affLbl.TextSize = 7
			affLbl.TextTruncate = Enum.TextTruncate.AtEnd
			affLbl.TextXAlignment = Enum.TextXAlignment.Left; affLbl.Parent = row

			-- Compact stats: "55/10/8/6"
			local st2 = Instance.new("TextLabel")
			st2.Size = UDim2.new(1, -60, 0, 10); st2.Position = UDim2.new(0, 28, 0, 26)
			st2.BackgroundTransparency = 1
			st2.Text = cr.health .. "/" .. cr.attack .. "/" .. cr.defense .. "/" .. cr.speed
			st2.TextColor3 = C.textSec; st2.Font = Enum.Font.GothamMedium; st2.TextSize = 7
			st2.TextXAlignment = Enum.TextXAlignment.Left; st2.Parent = row

			if GameConfig.ENABLE_CODEX_UI then
				local codexRowBtn = Instance.new("TextButton")
				codexRowBtn.Size = UDim2.new(1, -52, 0, 40)
				codexRowBtn.Position = UDim2.new(0, 0, 0, 0)
				codexRowBtn.BackgroundTransparency = 1
				codexRowBtn.Text = ""
				codexRowBtn.ZIndex = 2
				codexRowBtn.Parent = row
				local openCodexEvt = playerGui:FindFirstChild("OpenCodex")
				if openCodexEvt and openCodexEvt:IsA("BindableEvent") then
					codexRowBtn.MouseButton1Click:Connect(function()
						openCodexEvt:Fire(av.id)
					end)
				end
			end

			local placeBtn = Instance.new("TextButton")
			if canPlaceMore then
				placeBtn.Size = UDim2.new(0, 44, 0, 20); placeBtn.Position = UDim2.new(1, -48, 0.5, -10)
				placeBtn.BackgroundColor3 = C.battle
				placeBtn.Text = "Place"; placeBtn.TextColor3 = Color3.new(1,1,1)
				placeBtn.Font = Enum.Font.GothamBold; placeBtn.TextSize = 8; placeBtn.BorderSizePixel = 0
				placeBtn.Active = true; placeBtn.Parent = row
				Instance.new("UICorner", placeBtn).CornerRadius = UDim.new(0, 4)
				placeBtn.MouseButton1Click:Connect(function()
					if canPlaceMore then
						pendingBattleUid = av.uid; refreshBattle()
					end
				end)
			end
		end
	else
		-- Empty sidebar when no available creatures or during placement
		local emptySidebar = Instance.new("TextLabel")
		emptySidebar.Size = UDim2.new(1, -8, 0, 40); emptySidebar.BackgroundTransparency = 1
		emptySidebar.Text = pendingBattleUid and "Click a grid slot to place" or "No unassigned creatures"
		emptySidebar.TextColor3 = C.textMut; emptySidebar.Font = Enum.Font.GothamMedium
		emptySidebar.TextSize = 9; emptySidebar.TextWrapped = true
		emptySidebar.LayoutOrder = 1; emptySidebar.Parent = rightSidebar
	end

	-- DEV MODE
	if arenaInfo and arenaInfo.devMode then
		local devLbl = Instance.new("TextLabel")
		devLbl.Size = UDim2.new(1, 0, 0, 18); devLbl.BackgroundTransparency = 1
		devLbl.Text = "DEV MODE: AI challengers enabled"; devLbl.TextColor3 = C.favorite
		devLbl.Font = Enum.Font.GothamBold; devLbl.TextSize = 10; devLbl.LayoutOrder = 100
		devLbl.Parent = content
	end
	restoreScroll()
end

--[[ BASE LAYOUT / SLOT OVERVIEW (Raids tab - secondary to Inventory)
  Primary assignment: use Inventory tab Inc/Def buttons; server uses first empty slot. Raids tab is view + move.
  When GameConfig.ENABLE_BASE_LAYOUT_OVERVIEW is true, the Raids tab shows:
  - Income track ($) and Defense track (D): same baseSlots/defenseSlots as Inventory and world placement.
  - Assign from Inventory (Inc/Def) or by picking up creatures in-world and placing on points; all stay in sync.
  - Here: click a creature slot then another slot to move; or view which creatures are on which points.
  - Defense HP bar: sum of CreatureData.health for assigned defense creatures (static Max HP). ]]
local function buildBaseLayoutPanel(parent, invData)
	local floors = invData.ownedFloors or { 1 }
	local numFloors = #floors
	local slotCountIncome = numFloors * (GameConfig.IncomePointsPerFloor or 6)
	local slotCountDefense = numFloors * (GameConfig.DefensePointsPerFloor or 6)
	-- Normalize slot arrays: replication can send number keys as strings, so ipairs would only see slot 1.
	local rawBase = invData.baseSlots or {}
	local rawDef = invData.defenseSlots or {}
	local function normalizeSlots(raw, slotCount)
		local out = {}
		for i = 1, slotCount do
			local v = raw[i] or raw[tostring(i)]
			out[i] = (v and v ~= "") and tostring(v) or ""
		end
		return out
	end
	local baseSlots = normalizeSlots(rawBase, slotCountIncome)
	local defenseSlots = normalizeSlots(rawDef, slotCountDefense)
	-- Debug: raw slot key sample (replication can send string keys)
	local function rawKeySample(raw, name)
		local keys = {}
		for k in pairs(raw) do table.insert(keys, tostring(k) .. "(" .. type(k) .. ")") end
		table.sort(keys)
		baseLog(name, "keys sample:", #keys > 0 and table.concat(keys, ", ") or "empty")
	end
	rawKeySample(rawBase, "rawBase")
	rawKeySample(rawDef, "rawDef")
	local filledIncome, filledDef = 0, 0
	for i = 1, slotCountIncome do if baseSlots[i] and baseSlots[i] ~= "" then filledIncome = filledIncome + 1 end end
	for i = 1, slotCountDefense do if defenseSlots[i] and defenseSlots[i] ~= "" then filledDef = filledDef + 1 end end
	baseLog("slotCountIncome=" .. slotCountIncome, "slotCountDefense=" .. slotCountDefense, "filledIncome=" .. filledIncome, "filledDefense=" .. filledDef)
	local uidToEntry = {}
	for _, e in ipairs(invData.inventory or {}) do
		local k = tostring(e.uid)
		uidToEntry[k] = e
		if e.uid ~= k then uidToEntry[e.uid] = e end
	end
	for _, egg in ipairs(invData.eggs or {}) do
		local row = {
			uid = egg.uid,
			id = egg.creatureId,
			level = egg.level,
			isEgg = true,
			rarity = egg.rarity,
			mystery = egg.mystery == true,
			inspected = egg.inspected == true,
		}
		local k = tostring(egg.uid)
		uidToEntry[k] = row
		if egg.uid ~= k then uidToEntry[egg.uid] = row end
	end
	local uidCount = 0
	for _ in pairs(uidToEntry) do uidCount = uidCount + 1 end
	baseLog("uidToEntry size:", uidCount, "inventory=" .. #(invData.inventory or {}), "eggs=" .. #(invData.eggs or {}))

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.LayoutOrder = 0
	container.Parent = parent

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = container

	-- Section title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 20)
	title.BackgroundTransparency = 1
	title.Text = "BASE"
	title.TextColor3 = C.textSec
	title.Font = Enum.Font.GothamBold
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 0
	title.Parent = container

	-- Base summary metrics
	local incomePerTick = 0
	for _, uid in ipairs(baseSlots) do
		if uid and uid ~= "" then
			local entry = uidToEntry[tostring(uid)] or uidToEntry[uid]
			if entry and not entry.isEgg then
				local cr = CreatureData.GetById(entry.id)
				if cr then incomePerTick = incomePerTick + (cr.baseIncome or 0) end
			end
		end
	end
	local tickSec = tonumber(GameConfig.IncomeTickSeconds) or 10
	local incomePerSec = incomePerTick / math.max(1, tickSec)
	local incomePerMin = incomePerTick * (60 / math.max(1, tickSec))
	local filledTotal = (filledIncome + filledDef)
	local pointTotal = (slotCountIncome + slotCountDefense)

	local baseStatsRow = Instance.new("Frame")
	baseStatsRow.Size = UDim2.new(1, 0, 0, 52)
	baseStatsRow.BackgroundColor3 = Color3.fromRGB(22, 24, 35)
	baseStatsRow.BorderSizePixel = 0
	baseStatsRow.LayoutOrder = 1
	baseStatsRow.Parent = container
	Instance.new("UICorner", baseStatsRow).CornerRadius = UDim.new(0, 6)

	local baseStatsLbl = Instance.new("TextLabel")
	baseStatsLbl.Size = UDim2.new(1, -10, 1, -8)
	baseStatsLbl.Position = UDim2.new(0, 8, 0, 4)
	baseStatsLbl.BackgroundTransparency = 1
	baseStatsLbl.TextColor3 = C.textSec
	baseStatsLbl.Font = Enum.Font.GothamMedium
	baseStatsLbl.TextSize = 10
	baseStatsLbl.TextXAlignment = Enum.TextXAlignment.Left
	baseStatsLbl.TextYAlignment = Enum.TextYAlignment.Top
	baseStatsLbl.TextWrapped = true
	baseStatsLbl.Text = ("INC/sec: %.2f   INC/min: %d\nPoints: %d/%d   Income: %d/%d   Defense: %d/%d")
		:format(incomePerSec, math.floor(incomePerMin), filledTotal, pointTotal, filledIncome, slotCountIncome, filledDef, slotCountDefense)
	baseStatsLbl.Parent = baseStatsRow

	-- Pending move: { track, slotIndex, uid } when user picked a creature to move
	local pendingBaseMove = nil

	local allSlotCells = {} -- { btn, stroke, track, index }

	local function applyHighlights()
		for _, cell in ipairs(allSlotCells) do
			local selected = (activeBaseSlotTrack == cell.track and activeBaseSlotIndex == cell.index)
			cell.stroke.Color = selected and C.accent or C.divider
			cell.stroke.Thickness = selected and 2 or 1
			cell.stroke.Transparency = selected and 0.2 or 0.5
		end
		updateBaseLayoutActiveAttrs()
	end

	local function mkSlotCell(cellParent, track, slotIndex, assignedUid, layoutOrder)
		local cell = Instance.new("TextButton")
		cell.Size = UDim2.new(0, SLOT_CELL_SIZE, 0, SLOT_CELL_SIZE)
		cell.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
		cell.BorderSizePixel = 0
		cell.Text = ""
		cell.AutoButtonColor = true
		cell.LayoutOrder = layoutOrder
		cell.Parent = cellParent
		Instance.new("UICorner", cell).CornerRadius = UDim.new(1, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Color = C.divider
		stroke.Thickness = 1
		stroke.Transparency = 0.5
		stroke.Parent = cell

		local isSelected = (activeBaseSlotTrack == track and activeBaseSlotIndex == slotIndex)
		if isSelected then stroke.Color = C.accent; stroke.Thickness = 2; stroke.Transparency = 0.2 end

		local numLbl = Instance.new("TextLabel")
		numLbl.Size = UDim2.new(1, 0, 0, 12)
		numLbl.Position = UDim2.new(0, 0, 1, -12)
		numLbl.BackgroundTransparency = 1
		numLbl.Text = tostring(slotIndex)
		numLbl.TextColor3 = C.textMut
		numLbl.Font = Enum.Font.GothamMedium
		numLbl.TextSize = 9
		numLbl.Parent = cell

		if assignedUid and assignedUid ~= "" then
			local entry = uidToEntry[tostring(assignedUid)] or uidToEntry[assignedUid]
			if not entry then baseLog("mkSlotCell no entry for uid", tostring(assignedUid), "track=" .. track, "slotIndex=" .. slotIndex) end
			local cr = entry and CreatureData.GetById(entry.id)
			local isEgg = entry and entry.isEgg
			local eggHidden = isEgg and entry.mystery == true and entry.inspected ~= true
			local variant = (not isEgg and entry and entry.variant and entry.variant ~= "Normal") and entry.variant or nil
			local VARIANT_COLORS = CreatureData.VariantColors or { Silver = Color3.fromRGB(192,192,192), Gold = Color3.fromRGB(255,215,0), Legend = Color3.fromRGB(255,100,255) }
			local color = (eggHidden and Color3.fromRGB(235, 225, 180)) or (cr and cr.primaryColor) or (isEgg and Color3.fromRGB(255, 200, 80)) or C.textMut
			local orb = Instance.new("Frame")
			orb.Size = UDim2.new(0, 22, 0, 22)
			orb.Position = UDim2.new(0.5, -11, 0, 2)
			orb.BackgroundColor3 = color
			orb.BorderSizePixel = 0
			orb.Parent = cell
			Instance.new("UICorner", orb).CornerRadius = UDim.new(1, 0)
			-- Creature name on point (truncate to fit)
			local displayName = eggHidden and "Unknown Egg" or ((cr and cr.displayName) or (isEgg and "Egg") or "?")
			if #displayName > 6 then displayName = displayName:sub(1, 5) .. "…" end
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -2, 0, 10)
			nameLbl.Position = UDim2.new(0, 1, 0, 24)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = displayName
			nameLbl.TextColor3 = C.text
			nameLbl.Font = Enum.Font.GothamMedium
			nameLbl.TextSize = 8
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.Parent = cell
			if isEgg then
				local rs = Instance.new("UIStroke")
				rs.Color = Color3.fromRGB(255, 200, 80)
				rs.Thickness = 1
				rs.Transparency = 0.3
				rs.Parent = orb
			elseif variant and VARIANT_COLORS[variant] then
				local rs = Instance.new("UIStroke")
				rs.Color = VARIANT_COLORS[variant]
				rs.Thickness = 1
				rs.Transparency = 0.3
				rs.Parent = orb
			elseif cr and cr.rarity and cr.rarity ~= "Common" then
				local rs = Instance.new("UIStroke")
				rs.Color = RARITY[cr.rarity] or C.textMut
				rs.Thickness = 1
				rs.Transparency = 0.4
				rs.Parent = orb
			end
		else
			numLbl.Position = UDim2.new(0, 0, 0, 0)
			numLbl.Size = UDim2.new(1, 0, 1, 0)
			cell.BackgroundColor3 = Color3.fromRGB(35, 37, 50)
		end

		cell.MouseButton1Click:Connect(function()
			-- Move creature: if we had a pending move to same track, try move to this slot
			if pendingBaseMove and pendingBaseMove.track == track then
				if pendingBaseMove.slotIndex ~= slotIndex and pendingBaseMove.uid and Evt.moveCreatureSlot then
					-- targetPointIndex: server expects point index; slot index 1-based matches point order
					baseLog("moveCreatureSlot request: track=" .. tostring(track), "uid=" .. tostring(pendingBaseMove.uid), "targetSlotIndex=" .. tostring(slotIndex))
					local ok, msg = Evt.moveCreatureSlot:InvokeServer(track, pendingBaseMove.uid, slotIndex)
					baseLog("moveCreatureSlot result: ok=" .. tostring(ok), msg and ("msg=" .. tostring(msg)) or "")
					if ok then
						pendingBaseMove = nil
						if refreshRaids then refreshRaids() end
						return
					else
						Notify.Toast("Move failed: " .. tostring(msg or "unknown"), C.red, 2)
					end
				end
				pendingBaseMove = nil
			end
			-- Select this slot; if it has a creature, set as pending move source
			if assignedUid and assignedUid ~= "" then
				pendingBaseMove = { track = track, slotIndex = slotIndex, uid = assignedUid }
			else
				pendingBaseMove = nil
			end
			activeBaseSlotTrack = track
			activeBaseSlotIndex = slotIndex
			applyHighlights()
		end)
		table.insert(allSlotCells, { btn = cell, stroke = stroke, track = track, index = slotIndex })
		return cell
	end

	local function buildTrack(labelText, iconChar, trackKey, slotCount, assignedUids, rowLayoutOrder)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundColor3 = C.card
		row.BorderSizePixel = 0
		row.LayoutOrder = rowLayoutOrder
		row.Parent = container
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local rowList = Instance.new("UIListLayout")
		rowList.FillDirection = Enum.FillDirection.Horizontal
		rowList.VerticalAlignment = Enum.VerticalAlignment.Center
		rowList.Padding = UDim.new(0, 6)
		rowList.SortOrder = Enum.SortOrder.LayoutOrder
		rowList.Parent = row

		-- Icon + label strip (left)
		local iconStrip = Instance.new("Frame")
		iconStrip.Size = UDim2.new(0, 44, 0, SLOT_CELL_SIZE + 8)
		iconStrip.BackgroundColor3 = trackKey == "income" and Color3.fromRGB(25, 55, 40) or Color3.fromRGB(55, 25, 30)
		iconStrip.BorderSizePixel = 0
		iconStrip.LayoutOrder = 0
		iconStrip.Parent = row
		Instance.new("UICorner", iconStrip).CornerRadius = UDim.new(0, 6)
		local iconLbl = Instance.new("TextLabel")
		iconLbl.Size = UDim2.new(1, 0, 1, 0)
		iconLbl.BackgroundTransparency = 1
		iconLbl.Text = iconChar
		iconLbl.TextColor3 = trackKey == "income" and C.income or C.defense
		iconLbl.Font = Enum.Font.GothamBlack
		iconLbl.TextSize = 18
		iconLbl.Parent = iconStrip

		-- Slots container: wrap at BASE_LAYOUT_SLOTS_PER_ROW (fixed width so UIGridLayout wraps)
		local cellTotal = SLOT_CELL_SIZE + SLOT_CELL_PAD
		local wrapWidth = BASE_LAYOUT_SLOTS_PER_ROW * cellTotal + SLOT_CELL_PAD
		local slotsContainer = Instance.new("Frame")
		slotsContainer.Size = UDim2.new(0, wrapWidth, 0, 0)
		slotsContainer.AutomaticSize = Enum.AutomaticSize.Y
		slotsContainer.BackgroundTransparency = 1
		slotsContainer.LayoutOrder = 1
		slotsContainer.Parent = row

		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0, SLOT_CELL_SIZE + SLOT_CELL_PAD, 0, SLOT_CELL_SIZE + SLOT_CELL_PAD)
		grid.CellPadding = UDim2.new(0, SLOT_CELL_PAD, 0, SLOT_CELL_PAD)
		grid.FillDirection = Enum.FillDirection.Horizontal
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = slotsContainer

		for i = 1, slotCount do
			local uid = assignedUids[i]
			mkSlotCell(slotsContainer, trackKey, i, uid, i)
		end
	end

	buildTrack("Income / Resource", "$", "income", slotCountIncome, baseSlots, 2)
	buildTrack("Defense", "D", "defense", slotCountDefense, defenseSlots, 3) -- D = Defense (use ImageLabel with shield asset if desired)

	-- Defense HP (combined bar: sum of max HP of assigned defense creatures)
	local hpRow = Instance.new("Frame")
	hpRow.Size = UDim2.new(1, 0, 0, 28)
	hpRow.BackgroundColor3 = Color3.fromRGB(22, 24, 35)
	hpRow.BorderSizePixel = 0
	hpRow.LayoutOrder = 4
	hpRow.Parent = container
	Instance.new("UICorner", hpRow).CornerRadius = UDim.new(0, 6)

	local totalMaxHP = 0
	local totalCurrentHP = 0
	local totalDefenseDps = 0
	for _, uid in ipairs(defenseSlots or {}) do
		if not uid or uid == "" then continue end
		local entry = uidToEntry[tostring(uid)]
		if entry and not entry.isEgg then
			local cr = CreatureData.GetById(entry.id)
			if cr and cr.health then
				local lvl = entry.level or 1
				local statsScaled = computeEffectiveStatsClient(cr, entry)
				local hp = statsScaled and statsScaled.health or (cr.health or 0)
				local atk = statsScaled and statsScaled.attack or (cr.attack or 0)
				totalMaxHP = totalMaxHP + hp
				totalCurrentHP = totalCurrentHP + hp
				local dmgPerShot = math.max(3, math.floor(atk * (tonumber(GameConfig.DefenseBaseDamage) or 12) / 10))
				local attackCd = tonumber(GameConfig.DefenseAttackCD) or 2.5
				totalDefenseDps = totalDefenseDps + (dmgPerShot / math.max(0.1, attackCd))
			end
		end
	end

	-- Prefer live world HP from active defense models if present (client-side read of replicated attributes).
	local liveHpSum, liveHpMaxSum, liveCount = 0, 0, 0
	for _, model in ipairs(CollectionService:GetTagged("BaseDefenseCreature")) do
		if model and model.Parent and tonumber(model:GetAttribute("OwnerUserId")) == player.UserId then
			local mh = tonumber(model:GetAttribute("MaxHealth")) or tonumber(model:GetAttribute("Health")) or 0
			local ch = tonumber(model:GetAttribute("Health")) or mh
			if mh > 0 then
				liveHpMaxSum = liveHpMaxSum + mh
				liveHpSum = liveHpSum + math.clamp(ch, 0, mh)
				liveCount = liveCount + 1
			end
		end
	end
	if liveCount > 0 and liveHpMaxSum > 0 then
		totalCurrentHP = liveHpSum
		totalMaxHP = liveHpMaxSum
	end
	local defendedCount = ((invData.stats or {}).defenseKills) or 0
	local defenseActiveCount = tonumber(invData.defenseActiveCount) or 0
	local defenseRaidActive = invData.defenseRaidActive == true

	local hpLbl = Instance.new("TextLabel")
	hpLbl.Size = UDim2.new(1, -10, 1, 0)
	hpLbl.Position = UDim2.new(0, 8, 0, 0)
	hpLbl.BackgroundTransparency = 1
	hpLbl.Text = ("HP: %d/%d   DPS: %.1f   Raids Defended: %d%s")
		:format(math.floor(totalCurrentHP), math.floor(totalMaxHP), totalDefenseDps, defendedCount, defenseRaidActive and "   UNDER ATTACK" or "")
	hpLbl.TextColor3 = C.textSec
	hpLbl.Font = Enum.Font.GothamMedium
	hpLbl.TextSize = 10
	hpLbl.TextXAlignment = Enum.TextXAlignment.Left
	hpLbl.TextYAlignment = Enum.TextYAlignment.Center
	hpLbl.Parent = hpRow

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -16, 0, 10)
	barBg.Position = UDim2.new(0, 8, 1, -12)
	barBg.BackgroundColor3 = C.divider
	barBg.BorderSizePixel = 0
	barBg.Parent = hpRow
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = C.defense
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)
	-- Static max HP bar (no live HP in this UI)
	local hpRatio = (totalMaxHP > 0) and math.clamp(totalCurrentHP / totalMaxHP, 0, 1) or 0
	barFill.Size = UDim2.new(hpRatio, 0, 1, 0)
	if defenseRaidActive then
		hpLbl.TextColor3 = C.defense
	end

	return container
end

-- --------------------------------------------
-- BADBAG TAB (Badlands bag: captured creatures, set favorite, sacrifice)
-- --------------------------------------------
local badBagSacrificeModal = nil

local function showBadBagSacrificeModal(slotIndex, creatureName)
	if badBagSacrificeModal and badBagSacrificeModal.Parent then
		badBagSacrificeModal:Destroy()
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "BadBagSacrificeModal"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 80
	overlay.Parent = sg

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 300, 0, 240)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = C.bg
	panel.BorderSizePixel = 0
	panel.ZIndex = 81
	panel.Parent = overlay
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
	local pStroke = Instance.new("UIStroke", panel)
	pStroke.Color = C.red or Color3.fromRGB(220, 60, 60)
	pStroke.Thickness = 2

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -16, 0, 28)
	titleLbl.Position = UDim2.new(0, 8, 0, 8)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Sacrifice " .. creatureName
	titleLbl.TextColor3 = C.red or Color3.fromRGB(220, 60, 60)
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 15
	titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	titleLbl.ZIndex = 82
	titleLbl.Parent = panel

	local subLbl = Instance.new("TextLabel")
	subLbl.Size = UDim2.new(1, -16, 0, 18)
	subLbl.Position = UDim2.new(0, 8, 0, 38)
	subLbl.BackgroundTransparency = 1
	subLbl.Text = "Choose a stat to boost:"
	subLbl.TextColor3 = C.textSec
	subLbl.Font = Enum.Font.GothamMedium
	subLbl.TextSize = 12
	subLbl.ZIndex = 82
	subLbl.Parent = panel

	local STATS = { "Health", "Attack", "Defense", "MovementSpeed" }
	local STAT_LABELS = { Health = "Health", Attack = "Attack", Defense = "Defense", MovementSpeed = "Movement Speed" }
	local STAT_COLORS = {
		Health = Color3.fromRGB(220, 80, 80),
		Attack = Color3.fromRGB(255, 120, 50),
		Defense = Color3.fromRGB(80, 150, 255),
		MovementSpeed = Color3.fromRGB(100, 255, 120),
	}

	local btnY = 64
	for _, stat in ipairs(STATS) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -24, 0, 32)
		btn.Position = UDim2.new(0, 12, 0, btnY)
		btn.BackgroundColor3 = STAT_COLORS[stat] or C.accent
		btn.BackgroundTransparency = 0.35
		btn.BorderSizePixel = 0
		btn.Text = "+" .. STAT_LABELS[stat]
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.ZIndex = 83
		btn.Parent = panel
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		btnY = btnY + 36

		btn.MouseButton1Click:Connect(function()
			if Evt.badlandsSacrifice then
				Evt.badlandsSacrifice:FireServer(slotIndex, stat)
			end
			overlay:Destroy()
			badBagSacrificeModal = nil
		end)
	end

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Size = UDim2.new(1, -24, 0, 26)
	cancelBtn.Position = UDim2.new(0, 12, 0, btnY + 4)
	cancelBtn.BackgroundColor3 = C.card
	cancelBtn.BackgroundTransparency = 0.2
	cancelBtn.BorderSizePixel = 0
	cancelBtn.Text = "Cancel"
	cancelBtn.TextColor3 = C.textSec
	cancelBtn.Font = Enum.Font.GothamMedium
	cancelBtn.TextSize = 12
	cancelBtn.ZIndex = 83
	cancelBtn.Parent = panel
	Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 6)
	cancelBtn.MouseButton1Click:Connect(function()
		overlay:Destroy()
		badBagSacrificeModal = nil
	end)

	badBagSacrificeModal = overlay
end

refreshBadBag = function()
	for _, ch in ipairs(content:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	-- Hide detail panel
	if detailPanel then detailPanel.Visible = false end

	-- Adjust content width (full width, no detail panel)
	content.Size = UDim2.new(1, -28, 1, -140)
	content.Position = UDim2.new(0, 14, 0, 130)

	-- Header
	local hdrFrame = Instance.new("Frame")
	hdrFrame.Name = "BadBagHeader"
	hdrFrame.Size = UDim2.new(1, 0, 0, 56)
	hdrFrame.BackgroundColor3 = C.card
	hdrFrame.BackgroundTransparency = 0.2
	hdrFrame.BorderSizePixel = 0
	hdrFrame.LayoutOrder = 0
	hdrFrame.Parent = content
	Instance.new("UICorner", hdrFrame).CornerRadius = UDim.new(0, 8)

	local bagTitle = Instance.new("TextLabel")
	bagTitle.Size = UDim2.new(1, -16, 0, 24)
	bagTitle.Position = UDim2.new(0, 8, 0, 4)
	bagTitle.BackgroundTransparency = 1
	bagTitle.Text = "BADLANDS BAG"
	bagTitle.TextColor3 = Color3.fromRGB(180, 80, 255)
	bagTitle.Font = Enum.Font.GothamBlack
	bagTitle.TextSize = 16
	bagTitle.TextXAlignment = Enum.TextXAlignment.Left
	bagTitle.Parent = hdrFrame

	local bagSub = Instance.new("TextLabel")
	bagSub.Size = UDim2.new(1, -16, 0, 18)
	bagSub.Position = UDim2.new(0, 8, 0, 30)
	bagSub.BackgroundTransparency = 1
	bagSub.Text = ("Captured: %d / %d  |  Tap to set favorite  |  Sacrifice for stat boosts"):format(
		tonumber(badBagState.count) or 0, tonumber(badBagState.capacity) or 0
	)
	bagSub.TextColor3 = C.textSec
	bagSub.Font = Enum.Font.GothamMedium
	bagSub.TextSize = 11
	bagSub.TextXAlignment = Enum.TextXAlignment.Left
	bagSub.TextTruncate = Enum.TextTruncate.AtEnd
	bagSub.Parent = hdrFrame

	local slots = badBagState.slots or {}
	if #slots == 0 then
		local emptyLbl = Instance.new("TextLabel")
		emptyLbl.Size = UDim2.new(1, 0, 0, 60)
		emptyLbl.BackgroundTransparency = 1
		emptyLbl.LayoutOrder = 1
		emptyLbl.Text = "Your Badlands bag is empty.\nCapture creatures in The Badlands to fill it."
		emptyLbl.TextColor3 = C.textMut
		emptyLbl.Font = Enum.Font.GothamMedium
		emptyLbl.TextSize = 13
		emptyLbl.TextWrapped = true
		emptyLbl.Parent = content
		return
	end

	for slotIndex, slot in ipairs(slots) do
		local occupied = slot and not slot.empty and slot.id ~= nil
		local isFav = slot and slot.active

		local card = Instance.new("Frame")
		card.Name = "BagSlot_" .. slotIndex
		card.Size = UDim2.new(1, 0, 0, 62)
		card.BackgroundColor3 = isFav and Color3.fromRGB(30, 38, 28) or (occupied and C.bgLight or C.card)
		card.BackgroundTransparency = occupied and 0 or 0.3
		card.BorderSizePixel = 0
		card.LayoutOrder = slotIndex
		card.Parent = content
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

		local cStroke = Instance.new("UIStroke", card)
		if isFav then
			cStroke.Color = C.income or Color3.fromRGB(50, 220, 120)
			cStroke.Thickness = 2
		else
			cStroke.Color = occupied and Color3.fromRGB(60, 64, 80) or Color3.fromRGB(40, 42, 55)
			cStroke.Thickness = 1
		end

		-- Rarity bar
		if occupied then
			local rarColor = RARITY[slot.rarity] or C.textMut
			local rarBar = Instance.new("Frame")
			rarBar.Size = UDim2.new(0, 4, 1, -8)
			rarBar.Position = UDim2.new(0, 4, 0, 4)
			rarBar.BackgroundColor3 = rarColor
			rarBar.BorderSizePixel = 0
			rarBar.Parent = card
			Instance.new("UICorner", rarBar).CornerRadius = UDim.new(0, 2)
		end

		-- Slot number
		local slotLbl = Instance.new("TextLabel")
		slotLbl.Size = UDim2.new(0, 32, 1, 0)
		slotLbl.Position = UDim2.new(0, 14, 0, 0)
		slotLbl.BackgroundTransparency = 1
		slotLbl.Text = "#" .. slotIndex
		slotLbl.TextColor3 = isFav and (C.income or Color3.fromRGB(50, 220, 120)) or C.textSec
		slotLbl.Font = Enum.Font.GothamBold
		slotLbl.TextSize = 13
		slotLbl.Parent = card

		-- Name
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -200, 0, 22)
		nameLbl.Position = UDim2.new(0, 50, 0, 6)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = occupied and (slot.displayName or slot.id or "Unknown") or "Empty slot"
		nameLbl.TextColor3 = occupied and C.text or C.textMut
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 14
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = card

		-- Details
		local detLbl = Instance.new("TextLabel")
		detLbl.Size = UDim2.new(1, -200, 0, 16)
		detLbl.Position = UDim2.new(0, 50, 0, 30)
		detLbl.BackgroundTransparency = 1
		detLbl.Text = occupied
			and ("Lv" .. tostring(slot.level or 1) .. "  •  " .. tostring(slot.variant or "Normal") .. "  •  " .. tostring(slot.rarity or "Common"))
			or "Capture a creature to fill this slot."
		detLbl.TextColor3 = C.textSec
		detLbl.Font = Enum.Font.GothamMedium
		detLbl.TextSize = 11
		detLbl.TextXAlignment = Enum.TextXAlignment.Left
		detLbl.TextTruncate = Enum.TextTruncate.AtEnd
		detLbl.Parent = card

		-- Status badge
		local statusLbl = Instance.new("TextLabel")
		statusLbl.Size = UDim2.new(0, 60, 0, 18)
		statusLbl.Position = UDim2.new(1, -145, 0, 6)
		statusLbl.BackgroundTransparency = 1
		statusLbl.Text = isFav and "FAVORITE" or (occupied and "READY" or "EMPTY")
		statusLbl.TextColor3 = isFav and (C.income or Color3.fromRGB(50, 220, 120)) or (occupied and C.text or C.textMut)
		statusLbl.Font = Enum.Font.GothamBold
		statusLbl.TextSize = 10
		statusLbl.TextXAlignment = Enum.TextXAlignment.Right
		statusLbl.Parent = card

		if occupied then
			-- Set as favorite button
			local favBtn = Instance.new("TextButton")
			favBtn.Size = UDim2.new(0, 64, 0, 24)
			favBtn.Position = UDim2.new(1, -144, 0, 30)
			favBtn.BackgroundColor3 = isFav and (C.income or Color3.fromRGB(50, 220, 120)) or C.accent
			favBtn.BackgroundTransparency = isFav and 0.5 or 0.3
			favBtn.BorderSizePixel = 0
			favBtn.Text = isFav and "Active" or "Equip"
			favBtn.TextColor3 = Color3.new(1, 1, 1)
			favBtn.Font = Enum.Font.GothamBold
			favBtn.TextSize = 11
			favBtn.Parent = card
			Instance.new("UICorner", favBtn).CornerRadius = UDim.new(0, 5)
			favBtn.MouseButton1Click:Connect(function()
				if Evt.badlandsBagSwitch then
					Evt.badlandsBagSwitch:FireServer(slotIndex)
				end
			end)

			-- Sacrifice button (only non-favorite)
			if not isFav and Evt.badlandsSacrifice then
				local sacBtn = Instance.new("TextButton")
				sacBtn.Size = UDim2.new(0, 64, 0, 24)
				sacBtn.Position = UDim2.new(1, -72, 0, 30)
				sacBtn.BackgroundColor3 = C.red or Color3.fromRGB(255, 70, 70)
				sacBtn.BackgroundTransparency = 0.3
				sacBtn.BorderSizePixel = 0
				sacBtn.Text = "Sacrifice"
				sacBtn.TextColor3 = Color3.new(1, 1, 1)
				sacBtn.Font = Enum.Font.GothamBold
				sacBtn.TextSize = 10
				sacBtn.Parent = card
				Instance.new("UICorner", sacBtn).CornerRadius = UDim.new(0, 5)
				sacBtn.MouseButton1Click:Connect(function()
					showBadBagSacrificeModal(slotIndex, slot.displayName or slot.id or "Creature")
				end)
			end
		end
	end
end

-- --------------------------------------------
-- RAID TAB
-- --------------------------------------------
refreshRaids = function()
	baseLog("refreshRaids called")
	local restoreScroll = captureScrollPosition()
	for _, ch in ipairs(content:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	if GameConfig.ENABLE_BASE_LAYOUT_OVERVIEW and Evt.getInventory then
		local ok, invData = pcall(function() return Evt.getInventory:InvokeServer() end)
		baseLog("GetInventory: ok=" .. tostring(ok), invData and "has invData" or "invData nil")
		if ok and invData then
			baseLog("buildBaseLayoutPanel: baseSlots type=" .. type(invData.baseSlots), "defenseSlots type=" .. type(invData.defenseSlots), "ownedFloors=" .. tostring(invData.ownedFloors and #invData.ownedFloors or "nil"))
			updateBaseUnderAttackBadgeVisibility(invData.defenseRaidActive == true)
			buildBaseLayoutPanel(content, invData)
		else
			if not ok then baseLog("GetInventory pcall failed or returned nil") end
		end
	else
		if not GameConfig.ENABLE_BASE_LAYOUT_OVERVIEW then baseLog("ENABLE_BASE_LAYOUT_OVERVIEW is false") end
		if not Evt.getInventory then baseLog("getInventory is nil") end
	end
	restoreScroll()
end

-- --------------------------------------------
-- REFRESH INVENTORY
-- --------------------------------------------
local refreshLock = false
local refreshQueued = false
-- Last slot UID strings from SlotAssignComplete; used when refresh runs without overrides (e.g. deferred)
local lastSlotBaseStr, lastSlotDefStr = nil, nil

refreshInventory = function(overrideBaseStr, overrideDefStr)
	if refreshLock then
		refreshQueued = true
		return
	end
	refreshLock = true
	local restoreScroll = captureScrollPosition()

	-- Clear selection cache (cards will be recreated below)
	table.clear(invCardByUid)

	for _, ch in ipairs(content:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end
	if not Evt.getInventory then refreshLock = false; restoreScroll(); return end
	local ok, data = pcall(function() return Evt.getInventory:InvokeServer() end)
	baseLog("refreshInventory GetInventory: ok=" .. tostring(ok), ok and data and ("inventory=" .. #(data.inventory or {}) .. " baseSlots=" .. type(data.baseSlots) .. " defenseSlots=" .. type(data.defenseSlots)) or "")
	if not ok or not data then refreshLock = false; restoreScroll(); return end
	latestInventoryData = data
	updateBaseUnderAttackBadgeVisibility(data.defenseRaidActive == true)
	latestInventoryLookup = {}

	local function normalizeSlots(raw, slotCount)
		if not raw then return {} end
		local out = {}
		local n = math.max(tonumber(slotCount) or 6, 6)
		for i = 1, n do
			local v = raw[i] or raw[tostring(i)]
			out[i] = (v and v ~= "") and tostring(v) or ""
		end
		return out
	end
	local function csvToUidSet(s)
		local set = {}
		if type(s) ~= "string" or s == "" then return set end
		for part in string.gmatch(s, "[^,]+") do
			local u = part:gsub("^%s+", ""):gsub("%s+$", "")
			if u ~= "" then set[u] = true end
		end
		return set
	end
	local function slotArrayToUidSet(slots)
		local set = {}
		if not slots then return set end
		for i = 1, #slots do local u = slots[i]; if u and u ~= "" then set[tostring(u)] = true end end
		for _, u in pairs(slots) do if u and u ~= "" then set[tostring(u)] = true end end
		return set
	end
	local numFloors = data.ownedFloors and #data.ownedFloors or 1
	local maxInc = math.max(data.incomeMax or (numFloors * (GameConfig.IncomePointsPerFloor or 6)), 6)
	local maxDef = math.max(data.defenseMax or (numFloors * (GameConfig.DefensePointsPerFloor or 6)), 6)
	data.baseSlots = normalizeSlots(data.baseSlots, maxInc)
	data.defenseSlots = normalizeSlots(data.defenseSlots, maxDef)
	-- Rem button: use slot UIDs from event (override or last from SlotAssignComplete), else GetInventory/slots.
	-- FIX #16b: After consuming lastSlotBaseStr/lastSlotDefStr, clear them. Stale values from a previous
	-- SlotAssignComplete must not override FRESH data from GetInventory on future refreshes. Without clearing,
	-- the following sequence breaks: Inc (sets lastSlotBaseStr="X") → Fav (refreshInventory with no args uses
	-- stale lastSlotBaseStr="X" instead of fresh baseSlotUidsStr="" → Rem stays visible after favoriting).
	local resolvedBaseStr = overrideBaseStr or lastSlotBaseStr or data.baseSlotUidsStr
	local resolvedDefStr  = overrideDefStr  or lastSlotDefStr  or data.defenseSlotUidsStr
	-- Clear after consumption so future refreshes without overrides use fresh GetInventory data
	lastSlotBaseStr = nil
	lastSlotDefStr  = nil
	data.baseUidSet = csvToUidSet(resolvedBaseStr)
	if next(data.baseUidSet) == nil then data.baseUidSet = slotArrayToUidSet(data.baseSlots) end
	data.defenseUidSet = csvToUidSet(resolvedDefStr)
	if next(data.defenseUidSet) == nil then data.defenseUidSet = slotArrayToUidSet(data.defenseSlots) end

	-- FIX #20: Self-clear optimistic entries once server data confirms the expected state.
	-- If the user clicked Inc (optimistic base=true) and the server now reports that UID in
	-- baseUidSet, the optimistic entry is no longer needed. Also force-clear entries older
	-- than 5 seconds as a safety net against server errors / lost events.
	local now = tick()
	for uid, opt in pairs(pendingOptimistic) do
		if (now - (opt.t or 0)) > 5 then
			pendingOptimistic[uid] = nil
		else
			local matched = true
			if opt.base ~= nil then
				local serverBase = (data.baseUidSet and data.baseUidSet[uid]) == true
				if opt.base ~= serverBase then matched = false end
			end
			if opt.def ~= nil then
				local serverDef = (data.defenseUidSet and data.defenseUidSet[uid]) == true
				if opt.def ~= serverDef then matched = false end
			end
			if matched then pendingOptimistic[uid] = nil end
		end
	end

	-- Clear again after yield (another refresh may have added cards during InvokeServer)
	for _, ch in ipairs(content:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	coinLbl.Text = "Coins: " .. tostring(data.coins)
	countLbl.Text = #data.inventory .. "/" .. GameConfig.MaxInventorySize
	plotLbl.Text = data.plotId and data.plotId > 0 and ("Plot " .. data.plotId) or "No Plot"

	local ipt = 0
	local eggUids = {}
	for _, egg in ipairs(data.eggs or {}) do
		if egg and egg.uid then eggUids[tostring(egg.uid)] = true end
	end
	for _, uid in pairs(data.baseSlots or {}) do
		if not uid or uid == "" then continue end
		if not eggUids[tostring(uid)] then
			for _, e in ipairs(data.inventory) do
				if e.uid and tostring(e.uid) == tostring(uid) then
					local c = CreatureData.GetById(e.id)
					if c then ipt = ipt + c.baseIncome end
					break
				end
			end
		end
	end
	incomeLbl.Text = math.floor(ipt * (60 / GameConfig.IncomeTickSeconds)) .. "/min"

	local ro = { Legendary=1, Epic=2, Rare=3, Uncommon=4, Common=5 }

	-- Build status lookup: category order = Favorite, Battle Team, Defense, Income, Unassignedg
	local statusOf = {} -- uid -> { group }
	-- Group 0 = Favorite, 1 = Battle Team, 2 = Defense, 3 = Income, 4 = Unassigned
	if data.favoriteUid then statusOf[tostring(data.favoriteUid)] = { group = 0 } end
	if data.battleTeamSlots and #data.battleTeamSlots > 0 then
		for _, t in ipairs(data.battleTeamSlots) do if t and t.uid then statusOf[tostring(t.uid)] = { group = 1 } end end
	elseif data.battleTeam then
		for _, bu in pairs(data.battleTeam) do statusOf[tostring(bu)] = { group = 1 } end
	end
	for _, u in pairs(data.defenseSlots or {}) do if u and u ~= "" then statusOf[tostring(u)] = { group = 2 } end end
	for _, u in pairs(data.baseSlots or {}) do if u and u ~= "" then statusOf[tostring(u)] = { group = 3 } end end

	local sorted = {}
	for _, e in ipairs(data.inventory) do table.insert(sorted, e) end
	for _, egg in ipairs(data.eggs or {}) do
		if not statusOf[tostring(egg.uid)] and not statusOf[egg.uid] then
			table.insert(sorted, {
				uid = egg.uid,
				id = egg.creatureId,
				level = egg.level,
				isEgg = true,
				rarity = egg.rarity,
				mystery = egg.mystery == true,
				inspected = egg.inspected == true,
			})
		end
	end
	table.sort(sorted, function(a, b)
		local ca, cb = CreatureData.GetById(a.id), CreatureData.GetById(b.id)
		if not ca or not cb then return false end
		local sa = statusOf[tostring(a.uid)] or statusOf[a.uid] or { group = 4 }
		local sb = statusOf[tostring(b.uid)] or statusOf[b.uid] or { group = 4 }
		-- Sort by category first: Favorite, Battle Team, Defense, Income, Unassigned
		if sa.group ~= sb.group then return sa.group < sb.group end
		-- Within each category, sort by rarity then name
		local ra2, rb2 = ro[ca.rarity] or 99, ro[cb.rarity] or 99
		if ra2 ~= rb2 then return ra2 < rb2 end
		return ca.displayName < cb.displayName
	end)

	if #sorted == 0 then
		local e = Instance.new("TextLabel"); e.Size = UDim2.new(1, 0, 0, 70)
		e.BackgroundTransparency = 1; e.Text = "No creatures yet!\nClick creatures in the world to capture them."
		e.TextColor3 = C.textMut; e.Font = Enum.Font.GothamMedium; e.TextSize = 12
		e.TextWrapped = true; e.Parent = content
		refreshLock = false
		selectedInventoryUid = nil
		renderInventoryDetails(nil, nil, nil)
		restoreScroll()
		if refreshQueued then refreshQueued = false; task.defer(refreshInventory) end
		return
	end

	local hasSelected = false
	for _, entry in ipairs(sorted) do
		local uidStr = tostring(entry.uid or "")
		if uidStr ~= "" then
			latestInventoryLookup[uidStr] = entry
			if selectedInventoryUid and selectedInventoryUid == uidStr then
				hasSelected = true
			end
		end
	end
	if not hasSelected then
		selectedInventoryUid = tostring(sorted[1].uid or "")
	end

	local invCards = {}
	for i, entry in ipairs(sorted) do
		local cr = CreatureData.GetById(entry.id)
		if cr then
			local cardFrame = mkCard(entry, cr, data, i)
			cardFrame.Parent = content
			local viewerHost = cardFrame:FindFirstChild("IconSlot") and cardFrame.IconSlot:FindFirstChild("OrbWindow") and cardFrame.IconSlot.OrbWindow:FindFirstChild("ViewerHost")
			if viewerHost and CodexModelViewer and not (entry.isEgg == true) then
				table.insert(invCards, { frame = cardFrame, slot = viewerHost, creatureId = entry.id })
			end
		end
	end
	refreshSelectedInventoryDetails()
	scrollSelectedCardIntoView(true)

	-- Populate visible inventory cards with 3D viewport models (pooled)
	if CodexModelViewer and #invCards > 0 then
		task.defer(function()
			for i = 1, math.min(INV_VIEWER_POOL_SIZE, #invCards) do
				local card = invCards[i]
				if not invViewerPool[i] then
					invViewerPool[i] = CodexModelViewer.new(card.slot, {
						size = UDim2.new(1, 0, 1, 0),
						autoRotate = false,
						zoomEnabled = false,
						showFloor = false,
						themedLighting = true,
						playIdleAnimation = true,
					})
				end
				invViewerPool[i]:GetViewportFrame().Parent = card.slot
				invViewerPool[i]:SetCreature(card.creatureId)
				invViewerInUse[i] = card.creatureId
			end
			for i = #invCards + 1, INV_VIEWER_POOL_SIZE do
				if invViewerPool[i] then
					invViewerPool[i]:SetCreature(nil)
					invViewerPool[i]:GetViewportFrame().Parent = nil
				end
			end
		end)
	end

	refreshLock = false
	restoreScroll()
	if refreshQueued then refreshQueued = false; task.defer(refreshInventory) end
end

-- Refresh inventory as soon as server finishes assign/remove so Inc/Def/Rem buttons update immediately
task.spawn(function()
	local evt = Evt.slotAssignComplete or Events:WaitForChild("SlotAssignComplete", 10)
	if evt and evt:IsA("RemoteEvent") then
		evt.OnClientEvent:Connect(function(baseStr, defStr)
			lastSlotBaseStr, lastSlotDefStr = baseStr, defStr
			refreshInventory(baseStr, defStr)
			if activeTab == "raids" and refreshRaids then refreshRaids() end
		end)
	end
end)

-- --------------------------------------------
-- TOGGLE (open/close use viewport scale so panel fits on mobile)
-- --------------------------------------------
local isVis = false
local function getLivePlayerGui()
	local live = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
	if playerGui ~= live then
		playerGui = live
	end
	return playerGui
end

local function ensureInventoryGuiReady()
	-- PlayerGui can be reset on spawn on some clients; reattach persistent UI objects before toggling.
	local livePlayerGui = getLivePlayerGui()
	if sg.Parent ~= livePlayerGui then
		local ok = pcall(function()
			sg.Parent = livePlayerGui
		end)
		if not ok then
			return false
		end
	end
	if main and main.Parent ~= sg then
		local ok = pcall(function()
			main.Parent = sg
		end)
		if not ok then
			return false
		end
	end
	return sg.Parent == livePlayerGui and main and main.Parent == sg
end

local function syncVisibleStateFromGui()
	local guiOk = ensureInventoryGuiReady()
	if not guiOk then
		warn("[InventoryUI] ensureInventoryGuiReady failed — attempting recovery")
		-- FIX #21b: Don't hard-block on GUI check. Try to recover by re-parenting.
		pcall(function()
			local live = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 2)
			if live and sg then
				sg.Parent = live
				if main then main.Parent = sg end
				playerGui = live
			end
		end)
		-- Re-check after recovery attempt
		guiOk = (sg and sg.Parent and main and main.Parent == sg)
		if not guiOk then
			isVis = false
			return false
		end
	end
	if isVis and (not main.Visible) then
		isVis = false
	end
	return true
end

local function getPanelOpenRect()
	if MobileWindowLayout.IsMobile() then
		local bounds = MobileWindowLayout.GetBounds({
			leftInset = 14,
			rightInset = 14,
			topInset = 10,
			bottomInset = 14,
			bottomMobileExtra = 20,
		})
		return math.floor(bounds.left), math.floor(bounds.top), math.floor(bounds.width), math.floor(bounds.height), true
	end

	local scale = getPanelScale()
	local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
	local x = math.floor(0.5 * ((workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X) or PANEL_DESIGN_W) - w / 2)
	local y = math.floor(0.5 * ((workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y) or PANEL_DESIGN_H) - h / 2)
	return x, y, w, h, false
end

local function applyMainFrameLayout()
	local x, y, w, h, mobile = getPanelOpenRect()
	main.AnchorPoint = Vector2.new(0, 0)
	main.Position = UDim2.fromOffset(x, y)
	main.Size = UDim2.fromOffset(w, h)
	if mobile then
		main.Draggable = true
	else
		MobileWindowLayout.RestoreDesktopWindow(main, { draggable = true })
	end
end
-- defaultTab: "inventory" (I / HUD Inventory button) or "battle" (B / B button) or "badbag" (Badlands)
local function openUI(defaultTab)
	if not syncVisibleStateFromGui() then return end
	defaultTab = defaultTab or "inventory"
	updateTabVisibility()
	local x, y, w, h, mobile = getPanelOpenRect()
	main.AnchorPoint = Vector2.new(0, 0)
	main.Position = UDim2.fromOffset(x, y)
	main.Size = UDim2.fromOffset(w, 10)
	if mobile then
		main.Draggable = true
	else
		MobileWindowLayout.RestoreDesktopWindow(main, { draggable = true })
	end
	isVis = true; main.Visible = true
	MobileWindowLayout.NotifyMenuOpened()
	task.defer(updateFavOrb)
	task.delay(0.5, updateFavOrb)
	TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(w, h)
	}):Play()
	-- FIX #21: Wrap tab switch + refresh in pcall so a rendering error in one tab
	-- (e.g. mkCard button layout) doesn't kill the thread and leave the UI invisible.
	local tabOk, tabErr = pcall(function()
		if defaultTab == "badbag" then
			setTab("badbag"); if refreshBadBag then refreshBadBag() end
		elseif defaultTab == "battle" then
			setTab("battle"); refreshBattle()
		else
			setTab("inventory"); refreshInventory()
		end
	end)
	if not tabOk then
		warn("[InventoryUI] openUI tab refresh error: " .. tostring(tabErr))
	end
end
local function closeUI()
	if not syncVisibleStateFromGui() then return end
	if not main.Visible then
		isVis = false
		return
	end
	local w = main.AbsoluteSize.X
	TweenService:Create(main, TweenInfo.new(0.12), { Size = UDim2.new(0, w, 0, 10) }):Play()
	task.delay(0.13, function()
		isVis = false; main.Visible = false
		MobileWindowLayout.NotifyMenuClosed()
		applyMainFrameLayout()
	end)
end

toggleBtn.MouseButton1Click:Connect(function()
	print("[InventoryUI] toggleBtn clicked, syncCheck...")
	if not syncVisibleStateFromGui() then warn("[InventoryUI] toggleBtn sync failed"); return end
	if isVis then closeUI() else
		if player:GetAttribute("InBadlands") then openUI("badbag") else openUI("battle") end
	end
end)
closeBtn.MouseButton1Click:Connect(closeUI)
-- Q key handled by HUDButtonBar -> HUDToggleMenu -> onHUDToggle (direct handler below as fallback)
local lastQKeyTick = 0
local lastHUDInventoryToggleTick = 0

-- Q/B/Y keys: direct inventory toggle, battle tab, and toggle favorite
print("[InventoryUI] InputBegan handler registered — Q/B/Y keys active")
UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard or not input.KeyCode then return end
	if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.B then
		print("[InventoryUI] Key pressed:", input.KeyCode.Name, "isVis=", isVis, "InBadlands=", player:GetAttribute("InBadlands"))
	end
	if not syncVisibleStateFromGui() then
		warn("[InventoryUI] syncVisibleStateFromGui returned false — Q/B key blocked")
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		-- If HUDButtonBar already handled this exact Q press first, ignore direct fallback to avoid open->close flip.
		if (tick() - lastHUDInventoryToggleTick) < 0.12 then return end
		lastQKeyTick = tick()
		if player:GetAttribute("InBadlands") then
			if isVis then closeUI() else openUI("badbag") end
		else
			if isVis then closeUI() else openUI("inventory") end
		end
	elseif input.KeyCode == Enum.KeyCode.B then
		if isVis then closeUI() else openUI("battle") end
	elseif input.KeyCode == Enum.KeyCode.Y then
		if player:GetAttribute("InBadlands") then return end
		toggleFavorite()
	end
end)

-- HUD button bar toggle: use/create event; reconnect when HUDToggleMenu is re-added (e.g. after respawn)
local function getHUDToggle()
	local livePlayerGui = getLivePlayerGui()
	local evt = livePlayerGui:FindFirstChild("HUDToggleMenu")
	if not evt or not evt:IsA("BindableEvent") then
		evt = Instance.new("BindableEvent")
		evt.Name = "HUDToggleMenu"
		evt.Parent = livePlayerGui
	end
	return evt
end
local function onHUDToggle(menuName)
	if not syncVisibleStateFromGui() then
		warn("[InventoryUI] onHUDToggle syncVisibleStateFromGui failed for:", menuName)
		return
	end
	if menuName == "InventoryUI" then
		lastHUDInventoryToggleTick = tick()
		-- Skip if Q key was just handled directly (prevents double-toggle from keyboard path)
		if (tick() - lastQKeyTick) < 0.15 then return end
		if player:GetAttribute("InBadlands") then
			if isVis then closeUI() else openUI("badbag") end
		else
			if isVis then closeUI() else openUI("inventory") end
		end
	end
end

local hudToggleConnect, hudToggleChildAddedConnect
local function bindHUDToggleListeners()
	if hudToggleConnect then hudToggleConnect:Disconnect() end
	if hudToggleChildAddedConnect then hudToggleChildAddedConnect:Disconnect() end
	hudToggleConnect = getHUDToggle().Event:Connect(onHUDToggle)
	local livePlayerGui = getLivePlayerGui()
	hudToggleChildAddedConnect = livePlayerGui.ChildAdded:Connect(function(child)
		if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then
			child.Event:Connect(onHUDToggle)
		end
	end)
end
bindHUDToggleListeners()
player.CharacterAdded:Connect(function()
	task.defer(function()
		getLivePlayerGui()
		bindHUDToggleListeners()
		syncVisibleStateFromGui()
	end)
end)

-- When InBadlands changes, update tabs; if entering and Sieglings is open, switch to BadBag
-- FIX #24: Also hide Battle Menu button while in Badlands (BadBag button replaces it).
player:GetAttributeChangedSignal("InBadlands"):Connect(function()
	updateTabVisibility()
	local inBL = player:GetAttribute("InBadlands") == true
	-- Hide/show Battle Menu + weapon swap buttons (BadlandsClient shows BadBag in same spot)
	if toggleBtn then toggleBtn.Visible = not inBL end
	if weaponIcon then weaponIcon.Visible = not inBL end
	if inBL then
		if isVis and activeTab == "inventory" then
			setTab("badbag"); if refreshBadBag then refreshBadBag() end
		end
	else
		if isVis and activeTab == "badbag" then
			setTab("inventory"); refreshInventory()
		end
	end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if isVis then
		applyMainFrameLayout()
		if updateInventoryLayout then
			updateInventoryLayout()
		end
		if activeTab == "inventory" then
			refreshSelectedInventoryDetails()
		end
	end
end)

invTab.MouseButton1Click:Connect(function()
	if player:GetAttribute("InBadlands") then
		if Notify and Notify.Toast then Notify.Toast("Sieglings inventory is disabled in The Badlands", C.textMut, 2) end
		return
	end
	setTab("inventory"); refreshInventory()
end)
battleTab.MouseButton1Click:Connect(function() setTab("battle"); refreshBattle() end)
raidTab.MouseButton1Click:Connect(function() setTab("raids"); refreshRaids() end)
badBagTab.MouseButton1Click:Connect(function() setTab("badbag"); if refreshBadBag then refreshBadBag() end end)

-- Refresh current tab only (never switch content to Inventory when user is on Battle/Raids).
-- FIX #19: Forward-declared above (alongside refreshInventory/refreshBattle/refreshRaids) so that
-- toggleFavorite (line ~324) can call it without getting a nil global. The local function form here
-- would shadow the forward-declared upvalue; using assignment form populates the shared binding.
refreshCurrentTab = function()
	if not isVis then return end
	if activeTab == "inventory" then refreshInventory()
	elseif activeTab == "battle" then refreshBattle()
	elseif activeTab == "badbag" then if refreshBadBag then refreshBadBag() end
	else refreshRaids() end
end

-- Events: refresh the *current* tab so we don't overwrite Battle/Raids with Inventory (fixes mobile reset bug)
if Evt.captureSuccess then Evt.captureSuccess.OnClientEvent:Connect(function()
		task.defer(function() task.wait(0.3); if isVis then refreshCurrentTab() end; updateFavOrb() end)
	end) end
if Evt.evolveResult then Evt.evolveResult.OnClientEvent:Connect(function(success, payload)
		if success then
			local newName = payload and CreatureData.GetById(payload)
			local toastText = newName and ("Evolved to " .. newName.displayName .. "!") or "Evolved!"
			Notify.Toast(toastText, Color3.fromRGB(180, 100, 255), 3)
			task.defer(function()
				setTab("inventory")
				task.wait(0.25)
				refreshInventory()
				updateFavOrb()
			end)
		else
			Notify.Toast(payload or "Evolution failed", C.red, 3)
		end
	end) end
if Evt.raidStart then Evt.raidStart.OnClientEvent:Connect(function()
		task.defer(function()
			task.wait(0.25)
			refreshBaseUnderAttackBadgeFromServer()
			-- If the user is currently viewing the base overview, refresh it
			-- so the "RAID" label + HP bar color update immediately.
			if isVis and activeTab == "raids" then refreshRaids() end
		end)
	end) end
if Evt.raidEnd then Evt.raidEnd.OnClientEvent:Connect(function()
		task.defer(function()
			task.wait(0.5)
			refreshBaseUnderAttackBadgeFromServer()
			if isVis then refreshCurrentTab() end
			updateFavOrb()
		end)
	end) end
-- Income received: do NOT refresh inventory (coins update on next button/tab action).
-- Refreshing here caused constant scroll resets on mobile when income ticks fired.

if Evt.arenaAnnounce then Evt.arenaAnnounce.OnClientEvent:Connect(function(msg)
		if type(msg) == "string" and string.find(string.lower(msg), "battle team", 1, true) then
			return
		end
		Notify.Toast(msg, C.favorite, 4)
	end) end
if Evt.gymAnnounce then Evt.gymAnnounce.OnClientEvent:Connect(function(msg)
		Notify.Toast(msg, C.favorite, 4)
	end) end

if Evt.battleKill then Evt.battleKill.OnClientEvent:Connect(function(aN, dN, team)
		local color = team == "blue" and C.blue or C.red
		Notify.KillFeed(aN, dN, color)
	end) end
if Evt.gymBattleKill then Evt.gymBattleKill.OnClientEvent:Connect(function(aN, dN, team)
		local color = team == "blue" and C.blue or C.red
		Notify.KillFeed(aN, dN, color)
	end) end

if Evt.battleEnd then Evt.battleEnd.OnClientEvent:Connect(function(winName, winTeam)
		local isWin = (winName == player.Name)
		Notify.Banner(
			winName .. " WINS THE BATTLE!",
			isWin and Color3.fromRGB(80, 255, 120) or (winTeam == "blue" and C.blue or C.red),
			4
		)
		if isVis and activeTab == "battle" then task.wait(1); refreshBattle() end
	end) end
if Evt.gymBattleEnd then Evt.gymBattleEnd.OnClientEvent:Connect(function(winName, winTeam)
		local isWin = (winName == player.Name)
		Notify.Banner(
			winName .. " WINS THE BATTLE!",
			isWin and Color3.fromRGB(80, 255, 120) or (winTeam == "blue" and C.blue or C.red),
			4
		)
		if isVis and activeTab == "battle" then task.wait(1); refreshBattle() end
	end) end

local zoneDoorLocked = Events:FindFirstChild("ZoneDoorLocked")
if zoneDoorLocked then zoneDoorLocked.OnClientEvent:Connect(function(zoneId, msg)
		if type(msg) == "string" and msg ~= "" then Notify.Toast(msg, C.textSec, 5) end
	end) end
local sigilEarned = Events:FindFirstChild("SigilEarned")
if sigilEarned then sigilEarned.OnClientEvent:Connect(function(zoneId)
		Notify.Toast("Sigil earned: " .. tostring(zoneId), C.income, 3)
	end) end

-- Badlands bag: update state and auto-refresh BadBag tab when data arrives
if Evt.badlandsBagUpdate then
	Evt.badlandsBagUpdate.OnClientEvent:Connect(function(payload)
		local bag = (payload and payload.bag) or payload or {}
		badBagState = {
			count = tonumber(bag.count) or 0,
			capacity = tonumber(bag.capacity) or 0,
			activeIndex = bag.activeIndex,
			slots = bag.slots or {},
		}
		if isVis and activeTab == "badbag" and refreshBadBag then
			refreshBadBag()
		end
	end)
end

if Evt.badlandsSacrificeResult then
	Evt.badlandsSacrificeResult.OnClientEvent:Connect(function(success, message)
		if success then
			Notify.Toast(message or "Sacrifice complete!", C.income, 3)
		else
			Notify.Toast(message or "Sacrifice failed", C.red, 3)
		end
		if isVis and activeTab == "badbag" and refreshBadBag then
			task.wait(0.2)
			refreshBadBag()
		end
	end)
end

-- No auto-refresh loop: inventory only refreshes on tab/button press or when
-- CaptureSuccess/RaidEnd adds a monster. Avoids scroll reset on mobile.
print("[InventoryUI] Script fully loaded — all handlers registered")
