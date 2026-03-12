-- InventoryUIManager.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Inventory, Battle Formation, and Base (layout + raids) UI.
-- Toggle with 'B' key or on-screen button.

-- Set to true to print base layout / placement debug logs to Output
local BASE_LAYOUT_DEBUG = false
local function baseLog(...) if BASE_LAYOUT_DEBUG then print("[BaseLayout]", ...) end end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
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

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then warn("[UI] Events missing") return end

local function safeGet(n, t)
	local o = Events:WaitForChild(n, t or 8)
	if not o then warn("[UI] Missing: " .. n) end
	return o
end

local getInventory    = safeGet("GetInventory")
local assignToBase    = safeGet("AssignToBase")
local assignToDefense = safeGet("AssignToDefense")
local slotAssignComplete = Events:FindFirstChild("SlotAssignComplete")
local setFavorite     = safeGet("SetFavorite")
local captureSuccess  = safeGet("CaptureSuccess")
local raidRequest     = safeGet("RaidRequest")
local getRaidTargets  = safeGet("GetRaidTargets")
local raidStart       = safeGet("RaidStart")
local raidEnd         = safeGet("RaidEnd")
local moveCreatureSlot = safeGet("MoveCreatureSlot")
local creatureStolen  = safeGet("CreatureStolen")
local incomeReceived  = safeGet("IncomeReceived")
local getBattleInfo   = safeGet("GetBattleInfo")
local arenaAnnounce   = safeGet("ArenaAnnounce")
local battleEnd       = safeGet("BattleEnd")
local battleKill      = safeGet("BattleKill")
-- Gym battle events (separate system from standard arena battles)
local gymAnnounce     = Events:FindFirstChild("GymArenaAnnounce")
local gymBattleEnd    = Events:FindFirstChild("GymBattleEnd")
local gymBattleKill   = Events:FindFirstChild("GymBattleKill")
local getBattleTimers = Events:FindFirstChild("GetBattleTimers") -- RemoteFunction for arena/gym timers
local assignToBattle  = safeGet("AssignToBattle")
local removeFromBattle = safeGet("RemoveFromBattle")
local toggleBattleTeam = safeGet("ToggleBattleTeam")
local getBattleTeam   = safeGet("GetBattleTeam")
local sellCreature    = safeGet("SellCreature")
local evolveCreature  = safeGet("EvolveCreature")
local evolveResult    = safeGet("EvolveResult")
local companionSpawnedEvt = safeGet("CompanionSpawned")
local companionRecalledEvt = Events:FindFirstChild("CompanionRecalled")  -- water recall: favorite carded (non-water in water)
-- FIX #17: Recall/Summon companion without changing favorite (Y / ReCard button)
local recallCompanionEvt = safeGet("RecallCompanion")
local summonCompanionEvt = safeGet("SummonCompanion")
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
}
local CLASS_COLOR = {
	Bruiser = Color3.fromRGB(220, 80, 60), Mage = Color3.fromRGB(100, 120, 255),
	Guardian = Color3.fromRGB(80, 180, 220), Assassin = Color3.fromRGB(200, 60, 200),
	Support = Color3.fromRGB(100, 220, 120),
}

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
-- args, deferred or queued) still show the correct button text ("Rem" vs "Inc"/"Def").
-- Entries self-clear inside refreshInventory once the server-side data (baseUidSet / defenseUidSet)
-- matches the optimistic expectation, meaning the server has caught up.
-- Safety: entries older than 5 seconds are force-cleared to prevent stale state from server errors.
local pendingOptimistic = {} -- { [uidStr] = { base = bool|nil, def = bool|nil, t = number } }

local pendingBattleUid = nil
-- Optimistic battle formation: { [slotIndex] = uid } — show placement instantly before server confirms
local pendingBattleOptimistic = {}
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
local PANEL_DESIGN_W = 960   -- Wider for sidebar (monster list)
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
	return vp.X < MOBILE_BREAKPOINT or vp.Y < 500
end

-- B toggle button: shield-shaped, "Battle" / "Menu" on two lines. Under smaller HUD (~76px).
local toggleBtn = Instance.new("TextButton")
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

local function updateFavOrb()
	if not getInventory then return end
	local ok, data = pcall(function() return getInventory:InvokeServer() end)
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
-- The creature STAYS as favorite throughout. Only the inventory "Unfav" button clears the favorite.
local function toggleFavorite()
	if not getInventory then return end
	local ok, data = pcall(function() return getInventory:InvokeServer() end)
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
			if recallCompanionEvt then
				recallCompanionEvt:FireServer()
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
			if summonCompanionEvt then
				summonCompanionEvt:FireServer()
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
		if setFavorite then setFavorite:FireServer(lastFavoriteUid) end
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
if companionSpawnedEvt then
	companionSpawnedEvt.OnClientEvent:Connect(function()
		companionOut = true
		task.defer(updateFavOrb)
	end)
end
-- When non-water favorite enters water: companion is carded (turns into card, flies to player); update UI to show "Summon [name]"
if companionRecalledEvt and companionRecalledEvt:IsA("RemoteEvent") then
	companionRecalledEvt.OnClientEvent:Connect(function()
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

-- 3 TABS
local tabC = Instance.new("Frame")
tabC.Size = UDim2.new(1, -28, 0, 30); tabC.Position = UDim2.new(0, 14, 0, 94)
tabC.BackgroundTransparency = 1; tabC.Parent = main

local activeTab = "inventory"
local function mkTab(name, text, px, w)
	local b = Instance.new("TextButton")
	b.Name = name; b.Size = UDim2.new(w, -4, 1, 0)
	b.Position = UDim2.new(px, px > 0 and 3 or 0, 0, 0)
	b.BackgroundColor3 = C.card; b.Text = text; b.TextColor3 = C.textSec
	b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.BorderSizePixel = 0; b.Parent = tabC
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	return b
end
local invTab = mkTab("Inv", "INVENTORY", 0, 0.34)
local battleTab = mkTab("Battle", "BATTLE", 0.34, 0.33)
local raidTab = mkTab("Base", "Base", 0.67, 0.33)

local function setTab(t)
	activeTab = t; pendingBattleUid = nil
	for _, btn in ipairs({invTab, battleTab, raidTab}) do
		btn.BackgroundColor3 = C.card; btn.TextColor3 = C.textSec
	end
	local active = t == "inventory" and invTab or (t == "battle" and battleTab or raidTab)
	active.BackgroundColor3 = C.accent; active.TextColor3 = Color3.new(1,1,1)
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

local refreshInventory, refreshBattle, refreshRaids, refreshCurrentTab

-- --------------------------------------------
-- INVENTORY CARD (no Battle button)
-- --------------------------------------------
local function mkCard(entry, creature, data, order)
	local isEgg = entry.isEgg == true
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
	card.ZIndex = 2  -- base for card so children can sit above
	-- Cell highlight: dark purple = Battle, dark red = Defense, dark green = Income; Favorite = gold tint; default = card
	local cardBg = C.card
	if isEgg then cardBg = Color3.fromRGB(38, 35, 25)
	elseif isFav then cardBg = Color3.fromRGB(35, 33, 20)
	elseif isBattle then cardBg = Color3.fromRGB(25, 24, 38)
	elseif isDef then cardBg = Color3.fromRGB(40, 22, 22)
	elseif isBase then cardBg = Color3.fromRGB(22, 38, 28)
	end
	card.Size = UDim2.new(1, 0, 0, 74); card.BackgroundColor3 = cardBg
	card.BorderSizePixel = 0; card.LayoutOrder = order
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 9)

	-- Rarity bar
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 3, 1, -8); bar.Position = UDim2.new(0, 5, 0, 4)
	bar.BackgroundColor3 = isEgg and Color3.fromRGB(255, 200, 80) or rc; bar.BorderSizePixel = 0; bar.Parent = card
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

	-- Orb (variant color stroke: Silver/Gold/Legend)
	local VARIANT_COLORS = CreatureData.VariantColors or { Silver = Color3.fromRGB(192,192,192), Gold = Color3.fromRGB(255,215,0), Legend = Color3.fromRGB(255,100,255) }
	local orb = Instance.new("Frame")
	orb.Size = UDim2.new(0, 28, 0, 28); orb.Position = UDim2.new(0, 16, 0.5, -14)
	orb.BackgroundColor3 = creature.primaryColor; orb.BorderSizePixel = 0; orb.Parent = card
	Instance.new("UICorner", orb).CornerRadius = UDim.new(1, 0)
	local variant = (not isEgg and entry.variant) and entry.variant ~= "Normal" and entry.variant or nil
	local VARIANT_COLORS = CreatureData.VariantColors or { Silver = Color3.fromRGB(192,192,192), Gold = Color3.fromRGB(255,215,0), Legend = Color3.fromRGB(255,100,255) }
	if isEgg then
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 200, 80); s.Thickness = 2; s.Transparency = 0.3; s.Parent = orb
	elseif variant and VARIANT_COLORS[variant] then
		local s = Instance.new("UIStroke"); s.Color = VARIANT_COLORS[variant]; s.Thickness = 2; s.Transparency = 0.25; s.Parent = orb
	elseif creature.rarity ~= "Common" then
		local s = Instance.new("UIStroke"); s.Color = rc; s.Thickness = 2; s.Transparency = 0.3; s.Parent = orb
	end

	-- Name (left) and XP bar + label (right) on the same row
	local variantSuffix = variant and (" · " .. variant) or ""
	local displayName = isEgg and ("Egg (" .. (creature.displayName or entry.id) .. ")") or (creature.displayName .. variantSuffix)
	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.new(0, 140, 0, 18); nm.Position = UDim2.new(0, 52, 0, 6)
	nm.BackgroundTransparency = 1; nm.Text = displayName
	nm.TextColor3 = C.text; nm.Font = Enum.Font.GothamBold; nm.TextSize = 13
	nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Parent = card

	-- XP bar + label (skip for eggs)
	if not isEgg then
		local xpBarW, xpLblW = 200, 54
		local xpBarBg = Instance.new("Frame")
		xpBarBg.Size = UDim2.new(0, xpBarW, 0, 6); xpBarBg.Position = UDim2.new(1, -xpBarW - xpLblW - 6, 0, 9)
		xpBarBg.BackgroundColor3 = Color3.fromRGB(20, 22, 30); xpBarBg.BorderSizePixel = 0
		xpBarBg.Parent = card
		Instance.new("UICorner", xpBarBg).CornerRadius = UDim.new(0, 3)
		local xpBarFill = Instance.new("Frame")
		xpBarFill.Size = UDim2.new(xpPct, 0, 1, 0); xpBarFill.Position = UDim2.new(0, 0, 0, 0)
		xpBarFill.BackgroundColor3 = lvl >= maxLvl and C.income or Color3.fromRGB(80, 160, 255)
		xpBarFill.BorderSizePixel = 0; xpBarFill.Parent = xpBarBg
		Instance.new("UICorner", xpBarFill).CornerRadius = UDim.new(0, 3)
		local xpLbl = Instance.new("TextLabel")
		xpLbl.Size = UDim2.new(0, xpLblW, 0, 18); xpLbl.Position = UDim2.new(1, -xpLblW, 0, 6)
		xpLbl.BackgroundTransparency = 1; xpLbl.Font = Enum.Font.GothamMedium; xpLbl.TextSize = 8
		xpLbl.TextXAlignment = Enum.TextXAlignment.Right; xpLbl.TextColor3 = C.textMut; xpLbl.Parent = card
		xpLbl.Text = lvl >= maxLvl and "MAX" or (tostring(xp) .. "/" .. tostring(xpNeeded))
	end

	-- Info line: rarity | element class | income | level (eggs: "Place on point to hatch")
	local elemClr = ELEMENT_COLOR[creature.element] or C.textMut
	local lvlText = lvl >= maxLvl and "MAX" or ("Lv." .. lvl)
	local infoText = isEgg and ((entry.rarity or creature.rarity) .. " | Place on Income or Defense point to hatch") or (creature.rarity .. " | " .. (creature.element or "?") .. " " .. (creature.class or "?") .. " | " .. creature.baseIncome .. " c/t | " .. lvlText)
	local inf = Instance.new("TextLabel")
	inf.Size = UDim2.new(0, 250, 0, 14); inf.Position = UDim2.new(0, 52, 0, 24)
	inf.BackgroundTransparency = 1; inf.Text = infoText
	inf.TextColor3 = isEgg and Color3.fromRGB(255, 200, 80) or rc; inf.Font = Enum.Font.GothamMedium; inf.TextSize = 9
	inf.TextXAlignment = Enum.TextXAlignment.Left; inf.Parent = card

	-- Badge
	local badge = Instance.new("TextLabel")
	badge.Size = UDim2.new(0, 70, 0, 13); badge.Position = UDim2.new(0, 52, 0, 50)
	badge.BackgroundTransparency = 0.8; badge.BorderSizePixel = 0
	badge.Font = Enum.Font.GothamBold; badge.TextSize = 8; badge.Parent = card
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 3)
	if isEgg and (isBase or isDef) then
		badge.Text = isBase and "INCOME" or "DEFENSE"
		badge.TextColor3 = isBase and C.income or C.defense
		badge.BackgroundColor3 = isBase and C.income or C.defense
	elseif isFav then
		badge.Text = "FAVORITE"; badge.TextColor3 = C.favorite; badge.BackgroundColor3 = C.favorite
	elseif isBase then
		badge.Text = "INCOME"; badge.TextColor3 = C.income; badge.BackgroundColor3 = C.income
	elseif isDef then
		badge.Text = "DEFENSE"; badge.TextColor3 = C.defense; badge.BackgroundColor3 = C.defense
	elseif isBattle then
		badge.Text = "BATTLE [" .. (battleSlot or "?") .. "]"; badge.TextColor3 = C.battle; badge.BackgroundColor3 = C.battle
	else
		badge.Text = isEgg and "EGG" or "UNASSIGNED"; badge.TextColor3 = isEgg and Color3.fromRGB(255, 200, 80) or C.textMut; badge.BackgroundColor3 = isEgg and Color3.fromRGB(255, 200, 80) or C.textMut
	end

	-- Codex: click creature icon/name to open Codex (when feature flag on)
	if GameConfig.ENABLE_CODEX_UI then
		local codexBtn = Instance.new("TextButton")
		codexBtn.Size = UDim2.new(0, 190, 0, 48)
		codexBtn.Position = UDim2.new(0, 12, 0, 6)
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

	-- Button row: align with FAVORITE/DEFENSE badge (Y 50) so buttons don't overlap description
	local BTN_W = 48
	local BTN_H = 22
	local BTN_GAP = 8
	local RIGHT_MARGIN = 6
	local BTN_ROW_Y = 47  -- fixed Y so row lines up with badge (badge at 50, height 13)
	local function mkBtn(text, leftOffset, color, enabled)
		-- leftOffset = distance from card right edge to this button's left edge (positive = inset)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, BTN_W, 0, BTN_H)
		b.Position = UDim2.new(1, -leftOffset - BTN_W, 0, BTN_ROW_Y)
		b.BackgroundColor3 = enabled and color or C.divider
		b.Text = text; b.TextColor3 = enabled and Color3.new(1,1,1) or C.textMut
		b.Font = Enum.Font.GothamBold; b.TextSize = 9; b.BorderSizePixel = 0
		b.Active = enabled
		b.ZIndex = 10  -- above Codex/overlays so clicks always register
		b.Parent = card
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
		return b
	end
	-- Right-to-left: Evolve, Def, Inc, Fav, Sell — each left edge = prev left - BTN_W - BTN_GAP t
	local function btnLeft(index)
		return RIGHT_MARGIN + (index - 1) * (BTN_W + BTN_GAP)
	end

	if isEgg then
		-- Eggs: Income and Defense are toggles (Inc/Rem, Def/Rem). When ADDING, pass nil so server u5ses first empty slot (not selected slot).
		local incLabelEgg = isBase and "Rem" or "Inc"
		local defLabelEgg = isDef and "Rem" or "Def"
		-- print("[InvRem] egg buttons: incLabel=" .. incLabelEgg, "defLabel=" .. defLabelEgg, "isBase=" .. tostring(isBase), "isDef=" .. tostring(isDef))
		local incEnabled = (isBase or (not baseFull and not isDef))
		local incBtn = mkBtn(incLabelEgg, btnLeft(2), isBase and Color3.fromRGB(50,55,60) or C.income, incEnabled)
		incBtn.MouseButton1Click:Connect(function()
			if not assignToBase or not incEnabled then return end
			invButtonDebounce(entry.uid, "base", function()
				assignToBase:FireServer(entry.uid, isBase and 0 or nil)
				pendingOptimistic[tostring(entry.uid)] = { base = not isBase, t = tick() }
				isBase = not isBase
				incBtn.Text = isBase and "Rem" or "Inc"
				incBtn.BackgroundColor3 = isBase and Color3.fromRGB(50,55,60) or C.income
				task.delay(0.35, function() if refreshInventory then refreshInventory() end end)
			end)
		end)
		local defEnabled = (isDef or (not defFull and not isBase))
		local defBtn = mkBtn(defLabelEgg, btnLeft(1), isDef and Color3.fromRGB(55,50,50) or C.defense, defEnabled)
		defBtn.MouseButton1Click:Connect(function()
			if not assignToDefense or not defEnabled then return end
			invButtonDebounce(entry.uid, "defense", function()
				assignToDefense:FireServer(entry.uid, isDef and 0 or nil)
				pendingOptimistic[tostring(entry.uid)] = { def = not isDef, t = tick() }
				isDef = not isDef
				defBtn.Text = isDef and "Rem" or "Def"
				defBtn.BackgroundColor3 = isDef and Color3.fromRGB(55,50,50) or C.defense
				task.delay(0.35, function() if refreshInventory then refreshInventory() end end)
			end)
		end)
	elseif isBattle then
		-- Battle team creatures: Dismiss + Sell buttons
		local dismissBtn = mkBtn("Dismiss", btnLeft(2), Color3.fromRGB(120, 60, 60), true)
		dismissBtn.MouseButton1Click:Connect(function()
			if not removeFromBattle then return end
			invButtonDebounce(entry.uid, "dismiss", function()
				removeFromBattle:FireServer(entry.uid); task.wait(0.3); refreshInventory()
			end)
		end)
		local sellBtn = mkBtn("Sell", btnLeft(1), Color3.fromRGB(200, 60, 60), true)
		sellBtn.MouseButton1Click:Connect(function()
			if not sellCreature then return end
			invButtonDebounce(entry.uid, "sell", function()
				local ok, coins = sellCreature:InvokeServer(entry.uid)
				if ok then Notify.Toast("Sold for " .. coins .. " coins!", Color3.fromRGB(255, 200, 50), 2) end
				task.wait(0.3); refreshInventory()
			end)
		end)
	else
		-- Normal creatures: Sell, Fav, Inc, Def, Evolve (right-to-left: Evolve nearest right edge, then Def, Inc, Fav, Sell)
		local sellBtn = mkBtn("Sell", btnLeft(5), Color3.fromRGB(200, 60, 60), not isFav)
		sellBtn.MouseButton1Click:Connect(function()
			if not isFav and sellCreature then
				invButtonDebounce(entry.uid, "sell", function()
					local ok, coins = sellCreature:InvokeServer(entry.uid)
					if ok then Notify.Toast("Sold for " .. coins .. " coins!", Color3.fromRGB(255, 200, 50), 2) end
					task.wait(0.3); refreshInventory()
				end)
			end
		end)

		local favBtn = mkBtn(isFav and "Unfav" or "Fav", btnLeft(4), isFav and Color3.fromRGB(60,55,30) or C.favorite, true)
		favBtn.MouseButton1Click:Connect(function()
			if not setFavorite then return end
			invButtonDebounce(entry.uid, "fav", function()
				-- FIX #20: Clear any optimistic Inc/Def state for this creature since
				-- setFavorite calls removeFromAllSlots on the server (clears base/defense).
				pendingOptimistic[tostring(entry.uid)] = nil
				if isFav then
					setFavorite:FireServer("")
					task.wait(0.4)
					refreshInventory()
					updateFavOrb()
					return
				end
				local playEvt = playerGui:FindFirstChild("PlayFavoriteCardAnimation")
				if playEvt and playEvt:IsA("BindableEvent") then playEvt:Fire(entry.id) end
				setFavorite:FireServer(entry.uid)
				task.wait(0.4)
				refreshInventory()
				companionOut = true
				updateFavOrb()
				task.delay(0.5, function() refreshInventory(); updateFavOrb() end)
			end)
		end)

		-- Inc/Def: Rem = remove (send 0), Inc/Def = add to first empty slot (send nil). Server uses 0 as explicit remove.
		-- Disable Rem when creature is favorited (isFav and in that slot).
		local incEnabled = (isBase or (not baseFull and not isFav and not isDef)) and not (isFav and isBase)
		local incLabel = isBase and "Rem" or "Inc"
		local defLabel = isDef and "Rem" or "Def"
		-- #region agent log [InvRem] button labels for normal creatures (Rem = grey remove) (commented after UI fixes verified)
		-- print("[InvRem] normal creature buttons: incLabel=" .. incLabel, "defLabel=" .. defLabel, "isBase=" .. tostring(isBase), "isDef=" .. tostring(isDef))
		-- #endregion
		local incBtn = mkBtn(incLabel, btnLeft(3), isBase and Color3.fromRGB(50,55,60) or C.income, incEnabled)
		incBtn.MouseButton1Click:Connect(function()
			if not assignToBase or not incEnabled then return end
			invButtonDebounce(entry.uid, "base", function()
				assignToBase:FireServer(entry.uid, isBase and 0 or nil)
				pendingOptimistic[tostring(entry.uid)] = { base = not isBase, t = tick() }
				isBase = not isBase
				incBtn.Text = isBase and "Rem" or "Inc"
				incBtn.BackgroundColor3 = isBase and Color3.fromRGB(50,55,60) or C.income
				task.delay(0.35, function() if refreshInventory then refreshInventory() end end)
			end)
		end)

		local defEnabled = (isDef or (not defFull and not isFav and not isBase)) and not (isFav and isDef)
		local defBtn = mkBtn(defLabel, btnLeft(2), isDef and Color3.fromRGB(55,50,50) or C.defense, defEnabled)
		defBtn.MouseButton1Click:Connect(function()
			if not assignToDefense or not defEnabled then return end
			invButtonDebounce(entry.uid, "defense", function()
				assignToDefense:FireServer(entry.uid, isDef and 0 or nil)
				pendingOptimistic[tostring(entry.uid)] = { def = not isDef, t = tick() }
				isDef = not isDef
				defBtn.Text = isDef and "Rem" or "Def"
				defBtn.BackgroundColor3 = isDef and Color3.fromRGB(55,50,50) or C.defense
				task.delay(0.35, function() if refreshInventory then refreshInventory() end end)
			end)
		end)

		-- Evolve: only when creature can evolve in-game and meets level requirement (10 for base, 25 for evolved)
		local minEvolveLvl = CreatureData.GetEvolvesFrom and CreatureData.GetEvolvesFrom(entry.id) and (GameConfig.EvolutionMinLevel2 or 25) or (GameConfig.EvolutionMinLevel or 10)
		local canEvolve = (lvl >= minEvolveLvl) and CreatureData.CanEvolveInGame and CreatureData.CanEvolveInGame(entry.id)
		local evolveBtn = mkBtn("Evolve", btnLeft(1), Color3.fromRGB(180, 100, 255), canEvolve)
		evolveBtn.MouseButton1Click:Connect(function()
			if canEvolve and evolveCreature then
				invButtonDebounce(entry.uid, "evolve", function()
					evolveCreature:FireServer(entry.uid)
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
	if getInventory then
		local ok, r = pcall(function() return getInventory:InvokeServer() end)
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
	if getBattleInfo then
		local ok2, r2 = pcall(function() return getBattleInfo:InvokeServer() end)
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
		local scroll = Instance.new("ScrollingFrame")
		scroll.Size = UDim2.new(1, -16, 1, -50); scroll.Position = UDim2.new(0, 8, 0, 44)
		scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 4; scroll.ZIndex = 52
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.Parent = inner
		local scrollList = Instance.new("UIListLayout")
		scrollList.SortOrder = Enum.SortOrder.LayoutOrder
		scrollList.Padding = UDim.new(0, 4)
		scrollList.Parent = scroll
		for i, av in ipairs(available) do
			local cr = av.cr
			local rc = RARITY[cr.rarity] or C.textMut
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 52); row.BackgroundColor3 = C.card
			row.BorderSizePixel = 0; row.LayoutOrder = i; row.Parent = scroll
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
			local pad = Instance.new("UIPadding", row)
			pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
			pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
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
			placeBtn.Size = UDim2.new(0, 52, 0, 24); placeBtn.Position = UDim2.new(1, -56, 0.5, -12)
			placeBtn.BackgroundColor3 = #battleTeam < (GameConfig.MaxBattleTeamSize or 9) and C.battle or C.divider
			placeBtn.Text = "Place"; placeBtn.TextColor3 = Color3.new(1,1,1)
			placeBtn.Font = Enum.Font.GothamBold; placeBtn.TextSize = 10; placeBtn.BorderSizePixel = 0
			placeBtn.Active = #battleTeam < (GameConfig.MaxBattleTeamSize or 9); placeBtn.Parent = row
			Instance.new("UICorner", placeBtn).CornerRadius = UDim.new(0, 5)
			placeBtn.MouseButton1Click:Connect(function()
				if #battleTeam < (GameConfig.MaxBattleTeamSize or 9) then
					if targetSlotIndex and assignToBattle then
						assignToBattle:FireServer(av.uid, targetSlotIndex)
						pendingBattleOptimistic[targetSlotIndex] = av.uid  -- instant UI update before server confirms
					else
						pendingBattleUid = av.uid
					end
					modal:Destroy()
					refreshBattle()
				end
			end)
		end
		local function closeModal()
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

	-- King status
	local kingFrame = Instance.new("Frame")
	kingFrame.Size = UDim2.new(1, 0, 0, 30); kingFrame.BackgroundColor3 = C.card
	kingFrame.BorderSizePixel = 0; kingFrame.LayoutOrder = 0; kingFrame.Parent = leftCol
	Instance.new("UICorner", kingFrame).CornerRadius = UDim.new(0, 8)

	local kingName = arenaInfo and arenaInfo.kingName
	local kLbl = Instance.new("TextLabel")
	kLbl.Size = UDim2.new(0.5, 0, 1, 0); kLbl.Position = UDim2.new(0, 12, 0, 0)
	kLbl.BackgroundTransparency = 1
	kLbl.Text = kingName and ("King: " .. kingName) or "No current King"
	kLbl.TextColor3 = C.favorite; kLbl.Font = Enum.Font.GothamBold; kLbl.TextSize = 11
	kLbl.TextXAlignment = Enum.TextXAlignment.Left; kLbl.Parent = kingFrame

	local sLbl = Instance.new("TextLabel")
	sLbl.Size = UDim2.new(0.5, -10, 1, 0); sLbl.Position = UDim2.new(0.5, 0, 0, 0)
	sLbl.BackgroundTransparency = 1
	sLbl.Text = (arenaInfo and arenaInfo.battleInProgress) and "BATTLE IN PROGRESS" or "Waiting for next round"
	sLbl.TextColor3 = C.textSec; sLbl.Font = Enum.Font.GothamMedium; sLbl.TextSize = 10
	sLbl.TextXAlignment = Enum.TextXAlignment.Right; sLbl.Parent = kingFrame

	-- ── BATTLE TIMER BAR: shows arena countdown + gym status side by side ──
	local timerFrame = Instance.new("Frame")
	timerFrame.Size = UDim2.new(1, 0, 0, 28)
	timerFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	timerFrame.BorderSizePixel = 0; timerFrame.LayoutOrder = 0.3
	timerFrame.Parent = leftCol
	Instance.new("UICorner", timerFrame).CornerRadius = UDim.new(0, 8)

	local arenaTimerLbl = Instance.new("TextLabel")
	arenaTimerLbl.Size = UDim2.new(0.5, -4, 1, 0)
	arenaTimerLbl.Position = UDim2.new(0, 8, 0, 0)
	arenaTimerLbl.BackgroundTransparency = 1
	arenaTimerLbl.Text = "Arena: --"
	arenaTimerLbl.TextColor3 = C.blue; arenaTimerLbl.Font = Enum.Font.GothamBold
	arenaTimerLbl.TextSize = 10; arenaTimerLbl.TextXAlignment = Enum.TextXAlignment.Left
	arenaTimerLbl.Parent = timerFrame

	local gymTimerLbl = Instance.new("TextLabel")
	gymTimerLbl.Size = UDim2.new(0.5, -12, 1, 0)
	gymTimerLbl.Position = UDim2.new(0.5, 4, 0, 0)
	gymTimerLbl.BackgroundTransparency = 1
	gymTimerLbl.Text = "Gym: --"
	gymTimerLbl.TextColor3 = Color3.fromRGB(100, 200, 255); gymTimerLbl.Font = Enum.Font.GothamBold
	gymTimerLbl.TextSize = 10; gymTimerLbl.TextXAlignment = Enum.TextXAlignment.Right
	gymTimerLbl.Parent = timerFrame

	-- Live-update loop: polls GetBattleTimers every 2s while this tab is visible
	task.spawn(function()
		while timerFrame and timerFrame.Parent do
			local timers = nil
			if getBattleTimers then
				local ok, result = pcall(function() return getBattleTimers:InvokeServer() end)
				if ok and result then timers = result end
			end
			-- Fallback to workspace attributes if remote not available yet
			if not timers then
				timers = {
					arenaCountdown = workspace:GetAttribute("ArenaCountdown") or 0,
					arenaBattleInProgress = workspace:GetAttribute("ArenaBattleInProgress") or false,
					gymBattleInProgress = workspace:GetAttribute("GymBattleInProgress") or false,
					gymCooldownRemaining = 0,
				}
			end

			-- Arena timer text
			if timers.arenaBattleInProgress then
				arenaTimerLbl.Text = "Arena: FIGHTING"
				arenaTimerLbl.TextColor3 = C.red
			elseif timers.arenaCountdown and timers.arenaCountdown > 0 then
				arenaTimerLbl.Text = "Arena: " .. timers.arenaCountdown .. "s"
				arenaTimerLbl.TextColor3 = timers.arenaCountdown <= 10 and C.favorite or C.blue
			else
				arenaTimerLbl.Text = "Arena: Starting..."
				arenaTimerLbl.TextColor3 = C.blue
			end

			-- Gym timer text
			if timers.gymBattleInProgress then
				gymTimerLbl.Text = "Gym: FIGHTING"
				gymTimerLbl.TextColor3 = C.red
			elseif timers.gymCooldownRemaining and timers.gymCooldownRemaining > 0 then
				gymTimerLbl.Text = "Gym: Cooldown " .. timers.gymCooldownRemaining .. "s"
				gymTimerLbl.TextColor3 = C.textMut
			else
				gymTimerLbl.Text = "Gym: Ready"
				gymTimerLbl.TextColor3 = Color3.fromRGB(80, 200, 100)
			end

			task.wait(2)
		end
	end)

	-- Inactive team banner (shown when team is out of arena queue)
	if not battleTeamEnabled then
		local inactiveBanner = Instance.new("Frame")
		inactiveBanner.Size = UDim2.new(1, 0, 0, 36); inactiveBanner.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
		inactiveBanner.BackgroundTransparency = 0.3; inactiveBanner.BorderSizePixel = 0
		inactiveBanner.LayoutOrder = 0.5; inactiveBanner.Parent = leftCol
		Instance.new("UICorner", inactiveBanner).CornerRadius = UDim.new(0, 8)
		local inactiveLbl = Instance.new("TextLabel")
		inactiveLbl.Size = UDim2.new(1, -16, 1, 0); inactiveLbl.Position = UDim2.new(0, 8, 0, 0)
		inactiveLbl.BackgroundTransparency = 1
		inactiveLbl.Text = "Your battle team is INACTIVE — taken out of arena queue. Press the button below to re-enable."
		inactiveLbl.TextColor3 = C.text; inactiveLbl.Font = Enum.Font.GothamBold
		inactiveLbl.TextSize = 10; inactiveLbl.TextXAlignment = Enum.TextXAlignment.Left
		inactiveLbl.TextWrapped = true; inactiveLbl.Parent = inactiveBanner
	end

	-- AFFINITY / SYNERGY DISPLAY (scrollable on mobile so all elements visible)
	local synergyFrame = Instance.new(mobile and "ScrollingFrame" or "Frame")
	synergyFrame.Size = UDim2.new(1, 0, 0, 42)
	synergyFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	synergyFrame.BorderSizePixel = 0
	synergyFrame.LayoutOrder = 1
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

	-- GRID LABEL + SET BATTLE TEAM (mobile) + TEAM ACTIVE TOGGLE
	local gridLabelRow = Instance.new("Frame")
	gridLabelRow.Size = UDim2.new(1, 0, 0, 28); gridLabelRow.BackgroundTransparency = 1
	gridLabelRow.LayoutOrder = 2; gridLabelRow.Parent = leftCol

	local gridLabel = Instance.new("TextLabel")
	-- Shrink when Set Battle Team button is shown (leaves room for both buttons)
	local hasSetBtn = (#available > 0 and not pendingBattleUid and #battleTeam < (GameConfig.MaxBattleTeamSize or 9))
	gridLabel.Size = UDim2.new(1, hasSetBtn and -240 or -120, 1, 0)
	gridLabel.Position = UDim2.new(0, 0, 0, 0)
	gridLabel.BackgroundTransparency = 1
	gridLabel.Text = "YOUR BATTLE FORMATION (" .. #battleTeam .. "/" .. (GameConfig.MaxBattleTeamSize or 9) .. ")"
	gridLabel.TextColor3 = C.battle; gridLabel.Font = Enum.Font.GothamBold
	gridLabel.TextSize = 11; gridLabel.TextXAlignment = Enum.TextXAlignment.Left
	gridLabel.TextTruncate = Enum.TextTruncate.AtEnd
	gridLabel.Parent = gridLabelRow

	-- Set Battle Team button: to the left of Active/Inactive (mobile: opens modal; desktop: also opens modal)
	local setBattleTeamBtn = nil
	if #available > 0 and not pendingBattleUid and #battleTeam < (GameConfig.MaxBattleTeamSize or 9) then
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
		if not toggleBattleTeam then return end
		-- Optimistic update: flip button immediately
		local newState = not battleTeamEnabled
		toggleBtn.Text = newState and "ACTIVE" or "INACTIVE"
		toggleBtn.BackgroundColor3 = newState and C.battle or C.divider
		toggleBtn.TextColor3 = newState and Color3.new(1,1,1) or C.textSec
		local ok = pcall(function() return toggleBattleTeam:InvokeServer() end)
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

	-- GRID + STATS PANEL (mobile: stats stack below grid so monster details visible when placed)
	local mapFrame = Instance.new("Frame")
	local mapH = mobile and 380 or 195  -- mobile: grid + stats stacked
	mapFrame.Size = UDim2.new(1, 0, 0, mapH)
	mapFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	mapFrame.BorderSizePixel = 0; mapFrame.LayoutOrder = 3; mapFrame.Parent = leftCol
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
				local orbF = Instance.new("Frame")
				orbF.Size = UDim2.new(0, 28, 0, 28); orbF.Position = UDim2.new(0.5, -14, 0, 2)
				orbF.BackgroundColor3 = ce.primaryColor; orbF.BorderSizePixel = 0; orbF.Parent = slot
				Instance.new("UICorner", orbF).CornerRadius = UDim.new(1, 0)
				Instance.new("UIStroke", orbF).Color = rc

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
						if assignToBattle then
							invButtonDebounce(tostring(pendingBattleUid) .. "_" .. tostring(slotIdx), "assignBattle", function()
								local uid = pendingBattleUid
								assignToBattle:FireServer(uid, slotIdx)
								pendingBattleOptimistic[slotIdx] = uid  -- instant UI update before server confirms
								pendingBattleUid = nil; task.wait(0.3); refreshBattle()
							end)
						end
					else
						-- Click on occupied slot = remove from battle
						if removeFromBattle then
							invButtonDebounce(ce.uid, "dismiss", function()
								removeFromBattle:FireServer(ce.uid); task.wait(0.3); refreshBattle()
							end)
						end
					end
				end)
			else
				-- Empty slot: place from pending, or tap/click to open monster selection
				slot.MouseButton1Click:Connect(function()
					if pendingBattleUid and assignToBattle then
						invButtonDebounce(tostring(pendingBattleUid) .. "_" .. tostring(slotIdx), "assignBattle", function()
							local uid = pendingBattleUid
							assignToBattle:FireServer(uid, slotIdx)
							pendingBattleOptimistic[slotIdx] = uid  -- instant UI update before server confirms
							pendingBattleUid = nil; task.wait(0.3); refreshBattle()
						end)
					elseif #available > 0 and #battleTeam < (GameConfig.MaxBattleTeamSize or 9) then
						-- Tap empty slot to open monster selection; Place assigns directly to this slot (one tap)
						openMonsterSelectionModal(slotIdx)
					end
				end)
			end
		end
	end

	-- Stats panel: desktop = right of grid; mobile = below grid (so monster details visible when placed)
	local statsBox = Instance.new("Frame")
	if mobile then
		statsBox.Size = UDim2.new(1, -16, 0, 175)
		statsBox.Position = UDim2.new(0, 8, 0, 200)
	else
		statsBox.Size = UDim2.new(0, 330, 0, 185)
		statsBox.Position = UDim2.new(0, 200, 0, 5)
	end
	statsBox.BackgroundColor3 = Color3.fromRGB(22, 24, 35); statsBox.BorderSizePixel = 0
	statsBox.Parent = mapFrame
	Instance.new("UICorner", statsBox).CornerRadius = UDim.new(0, 8)

	local yOff = 6
	for i, c in ipairs(battleTeam) do
		if i > (GameConfig.MaxBattleTeamSize or 9) then break end
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
			placeBtn.Size = UDim2.new(0, 44, 0, 20); placeBtn.Position = UDim2.new(1, -48, 0.5, -10)
			placeBtn.BackgroundColor3 = #battleTeam < (GameConfig.MaxBattleTeamSize or 9) and C.battle or C.divider
			placeBtn.Text = "Place"; placeBtn.TextColor3 = #battleTeam < (GameConfig.MaxBattleTeamSize or 9) and Color3.new(1,1,1) or C.textMut
			placeBtn.Font = Enum.Font.GothamBold; placeBtn.TextSize = 8; placeBtn.BorderSizePixel = 0
			placeBtn.Active = #battleTeam < (GameConfig.MaxBattleTeamSize or 9); placeBtn.Parent = row
			Instance.new("UICorner", placeBtn).CornerRadius = UDim.new(0, 4)
			placeBtn.MouseButton1Click:Connect(function()
				if #battleTeam < (GameConfig.MaxBattleTeamSize or 9) then
					pendingBattleUid = av.uid; refreshBattle()
				end
			end)
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
		local row = { uid = egg.uid, id = egg.creatureId, level = egg.level, isEgg = true, rarity = egg.rarity }
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
	title.Text = "Base Layout"
	title.TextColor3 = C.textSec
	title.Font = Enum.Font.GothamBold
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 0
	title.Parent = container

	-- Hint: select slot for replace, or click creature then another slot to move
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 32)
	hint.BackgroundTransparency = 1
	hint.Text = "Assign from Inventory tab (Inc/Def). Here: click a creature slot, then another slot to move. Same data as world placement."
	hint.TextColor3 = C.textMut
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 9
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.LayoutOrder = 1
	hint.Parent = container

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
			local variant = (not isEgg and entry and entry.variant and entry.variant ~= "Normal") and entry.variant or nil
			local VARIANT_COLORS = CreatureData.VariantColors or { Silver = Color3.fromRGB(192,192,192), Gold = Color3.fromRGB(255,215,0), Legend = Color3.fromRGB(255,100,255) }
			local color = (cr and cr.primaryColor) or (isEgg and Color3.fromRGB(255, 200, 80)) or C.textMut
			local orb = Instance.new("Frame")
			orb.Size = UDim2.new(0, 22, 0, 22)
			orb.Position = UDim2.new(0.5, -11, 0, 2)
			orb.BackgroundColor3 = color
			orb.BorderSizePixel = 0
			orb.Parent = cell
			Instance.new("UICorner", orb).CornerRadius = UDim.new(1, 0)
			-- Creature name on point (truncate to fit)
			local displayName = (cr and cr.displayName) or (isEgg and "Egg") or "?"
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
				if pendingBaseMove.slotIndex ~= slotIndex and pendingBaseMove.uid and moveCreatureSlot then
					-- targetPointIndex: server expects point index; slot index 1-based matches point order
					baseLog("moveCreatureSlot request: track=" .. tostring(track), "uid=" .. tostring(pendingBaseMove.uid), "targetSlotIndex=" .. tostring(slotIndex))
					local ok, msg = moveCreatureSlot:InvokeServer(track, pendingBaseMove.uid, slotIndex)
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
	for _, uid in ipairs(defenseSlots or {}) do
		if not uid or uid == "" then continue end
		local entry = uidToEntry[tostring(uid)]
		if entry and not entry.isEgg then
			local cr = CreatureData.GetById(entry.id)
			if cr and cr.health then totalMaxHP = totalMaxHP + (cr.health or 0) end
		end
	end

	local hpLbl = Instance.new("TextLabel")
	hpLbl.Size = UDim2.new(0, 140, 1, 0)
	hpLbl.Position = UDim2.new(0, 8, 0, 0)
	hpLbl.BackgroundTransparency = 1
	hpLbl.Text = "Defense HP (Max): " .. tostring(totalMaxHP)
	hpLbl.TextColor3 = C.textSec
	hpLbl.Font = Enum.Font.GothamMedium
	hpLbl.TextSize = 11
	hpLbl.TextXAlignment = Enum.TextXAlignment.Left
	hpLbl.Parent = hpRow

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -160, 0, 12)
	barBg.Position = UDim2.new(0, 150, 0.5, -6)
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
	barFill.Size = UDim2.new(1, 0, 1, 0)

	return container
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

	local layoutOrderNext = 1

	if GameConfig.ENABLE_BASE_LAYOUT_OVERVIEW and getInventory then
		local ok, invData = pcall(function() return getInventory:InvokeServer() end)
		baseLog("GetInventory: ok=" .. tostring(ok), invData and "has invData" or "invData nil")
		if ok and invData then
			baseLog("buildBaseLayoutPanel: baseSlots type=" .. type(invData.baseSlots), "defenseSlots type=" .. type(invData.defenseSlots), "ownedFloors=" .. tostring(invData.ownedFloors and #invData.ownedFloors or "nil"))
			buildBaseLayoutPanel(content, invData)
			layoutOrderNext = 10
		else
			if not ok then baseLog("GetInventory pcall failed or returned nil") end
		end
	else
		if not GameConfig.ENABLE_BASE_LAYOUT_OVERVIEW then baseLog("ENABLE_BASE_LAYOUT_OVERVIEW is false") end
		if not getInventory then baseLog("getInventory is nil") end
	end

	if not getRaidTargets then restoreScroll(); return end
	local ok, targets = pcall(function() return getRaidTargets:InvokeServer() end)
	if not ok or not targets or #targets == 0 then
		local n = Instance.new("TextLabel")
		n.Size = UDim2.new(1, 0, 0, 50)
		n.BackgroundTransparency = 1
		n.Text = "No other players online."
		n.TextColor3 = C.textMut
		n.Font = Enum.Font.GothamMedium
		n.TextSize = 13
		n.LayoutOrder = layoutOrderNext
		n.Parent = content
		restoreScroll()
		return
	end
	for i, t in ipairs(targets) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 46)
		card.BackgroundColor3 = C.card
		card.BorderSizePixel = 0
		card.LayoutOrder = layoutOrderNext + i
		card.Parent = content
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(0.4, 0, 1, 0)
		nm.Position = UDim2.new(0, 12, 0, 0)
		nm.BackgroundTransparency = 1
		nm.Text = t.name
		nm.TextColor3 = t.canRaid and C.text or C.textMut
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = 12
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.Parent = card
		local rb = Instance.new("TextButton")
		rb.Size = UDim2.new(0, 56, 0, 26)
		rb.Position = UDim2.new(1, -66, 0.5, -13)
		rb.BackgroundColor3 = t.canRaid and C.raidBtn or C.divider
		rb.Text = "RAID"
		rb.TextColor3 = t.canRaid and Color3.new(1,1,1) or C.textMut
		rb.Font = Enum.Font.GothamBlack
		rb.TextSize = 11
		rb.BorderSizePixel = 0
		rb.Active = t.canRaid
		rb.Parent = card
		Instance.new("UICorner", rb).CornerRadius = UDim.new(0, 6)
		if t.canRaid then
			rb.MouseButton1Click:Connect(function()
				if raidRequest then raidRequest:FireServer(t.name) end
			end)
		end
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

	for _, ch in ipairs(content:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end
	if not getInventory then refreshLock = false; restoreScroll(); return end
	local ok, data = pcall(function() return getInventory:InvokeServer() end)
	baseLog("refreshInventory GetInventory: ok=" .. tostring(ok), ok and data and ("inventory=" .. #(data.inventory or {}) .. " baseSlots=" .. type(data.baseSlots) .. " defenseSlots=" .. type(data.defenseSlots)) or "")
	if not ok or not data then refreshLock = false; restoreScroll(); return end

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
			table.insert(sorted, { uid = egg.uid, id = egg.creatureId, level = egg.level, isEgg = true, rarity = egg.rarity })
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
		restoreScroll()
		if refreshQueued then refreshQueued = false; task.defer(refreshInventory) end
		return
	end

	for i, entry in ipairs(sorted) do
		local cr = CreatureData.GetById(entry.id)
		if cr then mkCard(entry, cr, data, i).Parent = content end
	end

	refreshLock = false
	restoreScroll()
	if refreshQueued then refreshQueued = false; task.defer(refreshInventory) end
end

-- Refresh inventory as soon as server finishes assign/remove so Inc/Def/Rem buttons update immediately
task.spawn(function()
	local evt = slotAssignComplete or Events:WaitForChild("SlotAssignComplete", 10)
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
-- defaultTab: "inventory" (I / HUD Inventory button) or "battle" (B / B button)
local function openUI(defaultTab)
	defaultTab = defaultTab or "inventory"
	local scale = getPanelScale()
	local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
	main.Size = UDim2.new(0, w, 0, 10)
	main.Position = UDim2.new(0.5, -w/2, 0.5, -h/2)
	isVis = true; main.Visible = true
	task.defer(updateFavOrb)
	task.delay(0.5, updateFavOrb)  -- refresh again in case GetInventory was stale (e.g. favorite set before UI loaded)
	TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, w, 0, h)
	}):Play()
	if defaultTab == "battle" then
		setTab("battle"); refreshBattle()
	else
		setTab("inventory"); refreshInventory()
	end
end
local function closeUI()
	local w = main.AbsoluteSize.X
	TweenService:Create(main, TweenInfo.new(0.12), { Size = UDim2.new(0, w, 0, 10) }):Play()
	task.delay(0.13, function()
		isVis = false; main.Visible = false
		main.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
		main.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
	end)
end

toggleBtn.MouseButton1Click:Connect(function() if isVis then closeUI() else openUI("battle") end end)
closeBtn.MouseButton1Click:Connect(closeUI)
-- Q key handled by HUDButtonBar -> HUDToggleMenu -> onHUDToggle (no duplicate handler)

-- B/Y keys: battle tab and toggle favorite (menu-internal)
UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard or not input.KeyCode then return end
	if input.KeyCode == Enum.KeyCode.B then if isVis then closeUI() else openUI("battle") end
	elseif input.KeyCode == Enum.KeyCode.Y then toggleFavorite() end
end)

-- HUD button bar toggle: use/create event; reconnect when HUDToggleMenu is re-added (e.g. after respawn)
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
	if menuName == "InventoryUI" then
		if isVis then closeUI() else openUI("inventory") end
	end
end
getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then child.Event:Connect(onHUDToggle) end
end)

invTab.MouseButton1Click:Connect(function() setTab("inventory"); refreshInventory() end)
battleTab.MouseButton1Click:Connect(function() setTab("battle"); refreshBattle() end)
raidTab.MouseButton1Click:Connect(function() setTab("raids"); refreshRaids() end)

-- Refresh current tab only (never switch content to Inventory when user is on Battle/Raids).
-- FIX #19: Forward-declared above (alongside refreshInventory/refreshBattle/refreshRaids) so that
-- toggleFavorite (line ~324) can call it without getting a nil global. The local function form here
-- would shadow the forward-declared upvalue; using assignment form populates the shared binding.
refreshCurrentTab = function()
	if not isVis then return end
	if activeTab == "inventory" then refreshInventory()
	elseif activeTab == "battle" then refreshBattle()
	else refreshRaids() end
end

-- Events: refresh the *current* tab so we don't overwrite Battle/Raids with Inventory (fixes mobile reset bug)
if captureSuccess then captureSuccess.OnClientEvent:Connect(function()
		task.defer(function() task.wait(0.3); if isVis then refreshCurrentTab() end; updateFavOrb() end)
	end) end
if evolveResult then evolveResult.OnClientEvent:Connect(function(success, payload)
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
if raidEnd then raidEnd.OnClientEvent:Connect(function()
		task.defer(function() task.wait(0.5); if isVis then refreshCurrentTab() end; updateFavOrb() end)
	end) end
-- Income received: do NOT refresh inventory (coins update on next button/tab action).
-- Refreshing here caused constant scroll resets on mobile when income ticks fired.

if arenaAnnounce then arenaAnnounce.OnClientEvent:Connect(function(msg)
		Notify.Toast(msg, C.favorite, 4)
	end) end
if gymAnnounce then gymAnnounce.OnClientEvent:Connect(function(msg)
		Notify.Toast(msg, C.favorite, 4)
	end) end

if battleKill then battleKill.OnClientEvent:Connect(function(aN, dN, team)
		local color = team == "blue" and C.blue or C.red
		Notify.KillFeed(aN, dN, color)
	end) end
if gymBattleKill then gymBattleKill.OnClientEvent:Connect(function(aN, dN, team)
		local color = team == "blue" and C.blue or C.red
		Notify.KillFeed(aN, dN, color)
	end) end

if battleEnd then battleEnd.OnClientEvent:Connect(function(winName, winTeam)
		local isWin = (winName == player.Name)
		Notify.Banner(
			winName .. " WINS THE BATTLE!",
			isWin and Color3.fromRGB(80, 255, 120) or (winTeam == "blue" and C.blue or C.red),
			4
		)
		if isVis and activeTab == "battle" then task.wait(1); refreshBattle() end
	end) end
if gymBattleEnd then gymBattleEnd.OnClientEvent:Connect(function(winName, winTeam)
		local isWin = (winName == player.Name)
		Notify.Banner(
			winName .. " WINS THE BATTLE!",
			isWin and Color3.fromRGB(80, 255, 120) or (winTeam == "blue" and C.blue or C.red),
			4
		)
		if isVis and activeTab == "battle" then task.wait(1); refreshBattle() end
	end) end

-- No auto-refresh loop: inventory only refreshes on tab/button press or when
-- CaptureSuccess/RaidEnd adds a monster. Avoids scroll reset on mobile.
