-- ══════════════════════════════════════════════════════════════════════════════
-- ArenaBattleSummaryClient.client.lua
-- ══════════════════════════════════════════════════════════════════════════════
-- Condensed arena battle summary with crest-shield toggle badge.
--
-- When a battle starts, a gold-pulsing shield badge appears in the shared top-right tray.
-- Clicking it toggles the summary panel on/off.
--
-- Two summary views (selected automatically by distance when toggled ON):
--   60-350 studs  → BillboardGui at arena center (mid view)
--   350+ studs    → ScreenGui panel (far view, always on-screen)
--
-- When toggled OFF (default), individual InfoTag billboards show on creatures.
--
-- Data sources (in priority order):
--   1. RemoteEvents (BattleTeamsPlaced, ArenaStateUpdate) — primary
--   2. Live attribute polling of ArenaCreature models — fallback
--
-- FIX #29:  Condensed summary replaces per-creature billboards
-- FIX #29b: Robust center, live polling, guarded nil refs
-- FIX #29c: Slot dedup, InfoTag aggressive hiding, SP overflow
-- FIX #30:  Crest badge toggle (hidden by default, no auto-show)
-- FIX #31:  Clean rewrite — stable slot ordering, removed debug spam,
--           eliminated redundant refreshes, poll merges instead of clears
-- Last updated: 2026-04-20 16:00
-- ══════════════════════════════════════════════════════════════════════════════

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")
local UserInputService   = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig   = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local CreatureData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CreatureData"))
local TopRightBadgeTray = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TopRightBadgeTray"))

-- ══════════════════════════════════════════════════════════════════════════════
-- Configuration
-- ══════════════════════════════════════════════════════════════════════════════

-- Distance thresholds (studs, XZ plane)
local SUMMARY_SHOW_DIST   = GameConfig.ArenaSummaryShowDistance or 60
local SUMMARY_MAX_DIST    = GameConfig.ArenaSummaryMaxDistance or 350
local HEALTHBAR_SHOW_DIST = GameConfig.ArenaHealthBarShowDistance or 10

-- Timing
local SCAN_INTERVAL = 0.25   -- heartbeat tick rate
local FADE_DURATION = 0.25   -- billboard fade tween
local POLL_INTERVAL = 1.0    -- live attribute poll rate

-- Style (glass card)
local CARD_BG_COLOR        = Color3.fromRGB(14, 16, 24)
local CARD_BG_TRANSPARENCY = 0.15
local CARD_CORNER_RADIUS   = UDim.new(0, 10)
local CARD_STROKE_COLOR    = Color3.fromRGB(60, 60, 80)
local CARD_STROKE_WIDTH    = 1.5
local TITLE_COLOR          = Color3.fromRGB(240, 240, 245)
local BLUE_COLOR           = Color3.fromRGB(60, 120, 255)
local RED_COLOR            = Color3.fromRGB(255, 70, 70)
local MUTED_COLOR          = Color3.fromRGB(170, 175, 190)
local HP_COLOR             = Color3.fromRGB(210, 215, 230)
local SP_COLOR             = Color3.fromRGB(255, 210, 120)
local FAINT_COLOR          = Color3.fromRGB(255, 80, 80)
local SLOT_BG_COLOR        = Color3.fromRGB(18, 20, 28)
local WINBAR_BG_COLOR      = Color3.fromRGB(24, 26, 36)

-- Crest badge (FIX #30) — arena badge = slot 0, base badge = slot 1 (in BaseSummaryClient)
local BADGE_WIDTH       = 36
local BADGE_HEIGHT      = 42
local BADGE_GOLD        = Color3.fromRGB(220, 180, 60)
local BADGE_BG          = Color3.fromRGB(18, 22, 32)
local ARENA_CREATURE_TAG = "ArenaCreature"

-- ══════════════════════════════════════════════════════════════════════════════
-- Utility
-- ══════════════════════════════════════════════════════════════════════════════

local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function clamp01(x) return math.clamp(x, 0, 1) end

-- ══════════════════════════════════════════════════════════════════════════════
-- Arena center resolution
-- ══════════════════════════════════════════════════════════════════════════════

--- Resolve arena center from folder structure.
--- @param arenaFolder Instance
--- @return Vector3?, BasePart?
local function resolveCenterPosition(arenaFolder)
	if not arenaFolder then return nil end

	-- 1) Explicit ArenaCenter part/model
	local ac = arenaFolder:FindFirstChild("ArenaCenter")
	if ac then
		if ac:IsA("BasePart") then return ac.Position, ac end
		if ac:IsA("Model") then
			local part = ac.PrimaryPart or ac:FindFirstChildWhichIsA("BasePart", true)
			return (part and part.Position) or ac:GetPivot().Position, part
		end
	end

	-- 2) Arena is a Model with PrimaryPart (not workspace)
	if arenaFolder:IsA("Model") and arenaFolder ~= workspace then
		local part = arenaFolder.PrimaryPart or arenaFolder:FindFirstChildWhichIsA("BasePart", true)
		return (part and part.Position) or arenaFolder:GetPivot().Position, part
	end

	-- 3) Derive from BlueTeam/RedTeam BattlePoints
	local pts = {}
	for _, teamName in ipairs({"BlueTeam", "RedTeam"}) do
		local team = arenaFolder:FindFirstChild(teamName)
		if team then
			for _, child in ipairs(team:GetChildren()) do
				if child:IsA("BasePart") and child.Name:match("^BattlePoint") then
					table.insert(pts, child)
				end
			end
		end
	end
	if #pts > 0 then
		local sum = Vector3.zero
		for _, p in ipairs(pts) do sum += p.Position end
		return sum / #pts, nil
	end

	return nil
end

--- Average position of all tagged ArenaCreature models (last-resort fallback).
--- @return Vector3?
local function computeCenterFromFighters()
	local sum, n = Vector3.zero, 0
	for _, model in ipairs(CollectionService:GetTagged(ARENA_CREATURE_TAG)) do
		if model and model:IsA("Model") and model.Parent then
			local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			if pp then sum += pp.Position; n += 1 end
		end
	end
	return n > 0 and (sum / n) or nil
end

--- Walk parents from tagged fighters to find arena container.
--- @return Instance?
local function findArenaContainerFromFighters()
	for _, model in ipairs(CollectionService:GetTagged(ARENA_CREATURE_TAG)) do
		if model and model:IsA("Model") and model.Parent then
			local cur = model.Parent
			while cur and cur ~= workspace do
				if cur:FindFirstChild("BlueTeam") and cur:FindFirstChild("RedTeam") then
					return cur
				end
				cur = cur.Parent
			end
		end
	end
	return nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Battle data model
-- ══════════════════════════════════════════════════════════════════════════════

local battleModel = {
	blueName   = "Blue",
	redName    = "Red",
	inProgress = false,
	blueSlots  = {},  -- [pointIndex 1-9] = { creatureId, displayName, hp, maxHp, focus, maxFocus, attack, speed, alive }
	redSlots   = {},
}

-- FIX #31 + #33: Per-slot dirty tracking. Instead of one global flag that
-- triggers refreshAllSlots() (18 slot rewrites), track which slots changed.
-- slotDirty[side][idx] = true means that specific slot needs a UI update.
-- globalDirty covers non-slot elements (texts, win bar, all-slot refresh).
local globalDirty = false
local slotDirty = { blue = {}, red = {} }

local function markDirty()
	globalDirty = true
	-- Also mark all slots dirty for backward compat with callers that
	-- expect a full refresh (BattleTeamsPlaced, first creation, etc.)
	for i = 1, 9 do
		slotDirty.blue[i] = true
		slotDirty.red[i] = true
	end
end

local function markSlotDirty(side, idx)
	slotDirty[side][idx] = true
end

-- FIX #32: Remote authority tracking. When ArenaStateUpdate or BattleTeamsPlaced
-- fires, it sets authoritative HP/SP values from the server. The fallback poll
-- must NOT overwrite these with stale InfoTag-parsed values.
-- remoteSeq increments on every RemoteEvent. Each slot stores the seq it was
-- last written at. Poll skips any slot whose seq matches (already has fresh data).
local remoteSeq = 0

local function estimateDps(slot)
	return (tonumber(slot.attack) or 0) * ((tonumber(slot.speed) or 0) / 100)
end

--- Compute blue team's win likelihood as 0..1.
local function computeWinLikely()
	local blueHp, redHp, blueDps, redDps = 0, 0, 0, 0
	for _, slot in pairs(battleModel.blueSlots) do
		blueHp += math.max(0, tonumber(slot.hp) or 0)
		if slot.alive ~= false then blueDps += estimateDps(slot) end
	end
	for _, slot in pairs(battleModel.redSlots) do
		redHp += math.max(0, tonumber(slot.hp) or 0)
		if slot.alive ~= false then redDps += estimateDps(slot) end
	end
	local totalHp  = blueHp + redHp
	local totalDps = blueDps + redDps
	local hpShare  = totalHp  > 0 and (blueHp  / totalHp)  or 0.5
	local dpsShare = totalDps > 0 and (blueDps / totalDps) or 0.5
	return clamp01(hpShare * 0.75 + dpsShare * 0.25)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- UI state
-- ══════════════════════════════════════════════════════════════════════════════

local summary = {
	billboard = nil, anchor = nil, card = nil, stroke = nil, divider = nil,
	title = nil, blueLine = nil, redLine = nil, statusLine = nil,
	winBarBG = nil, winBarBlue = nil, winBarRed = nil, winBarLabel = nil,
	blueGrid = nil, redGrid = nil, blueGridHeader = nil, redGridHeader = nil,
	blueSlotUis = nil, redSlotUis = nil,
	visible = false, tweens = {},
}

local far = {
	gui = nil, root = nil, title = nil,
	blueLine = nil, redLine = nil, statusLine = nil,
	winBarBlue = nil, winBarRed = nil, winBarLabel = nil,
	blueSlotUis = nil, redSlotUis = nil, visible = false,
}

-- FIX #30: Crest shield badge state
local badge = {
	gui = nil, button = nil, glow = nil,
	visible = false, pulseConn = nil,
}
local manualToggle = false  -- true = summary ON (badge clicked)

-- ══════════════════════════════════════════════════════════════════════════════
-- Tween helpers
-- ══════════════════════════════════════════════════════════════════════════════

local function cancelTweens()
	for _, tw in ipairs(summary.tweens) do tw:Cancel() end
	summary.tweens = {}
end

local function addTween(instance, info, props)
	local tw = TweenService:Create(instance, info, props)
	table.insert(summary.tweens, tw)
	tw:Play()
end

-- ══════════════════════════════════════════════════════════════════════════════
-- UI text setters (safe to call before GUIs exist)
-- ══════════════════════════════════════════════════════════════════════════════

-- FIX #33: Cache last summary texts to skip redundant writes.
local _lastSummaryTexts = { title = nil, blue = nil, red = nil, status = nil }

local function setSummaryTexts()
	local titleStr  = "\226\154\148 Arena Battle"
	local blueStr   = "\240\159\148\181 " .. tostring(battleModel.blueName or "Blue")
	local redStr    = "\240\159\148\180 " .. tostring(battleModel.redName or "Red")
	local statusStr = battleModel.inProgress and "Status: In progress" or "Status: Waiting"

	local c = _lastSummaryTexts
	local titleChanged  = c.title ~= titleStr
	local blueChanged   = c.blue ~= blueStr
	local redChanged    = c.red ~= redStr
	local statusChanged = c.status ~= statusStr

	if not titleChanged and not blueChanged and not redChanged and not statusChanged then
		return
	end

	c.title = titleStr; c.blue = blueStr; c.red = redStr; c.status = statusStr

	if summary.title then
		if titleChanged then summary.title.Text = titleStr end
		if blueChanged then summary.blueLine.Text = blueStr end
		if redChanged then summary.redLine.Text = redStr end
		if statusChanged then summary.statusLine.Text = statusStr end
	end
	if far.title then
		if titleChanged then far.title.Text = titleStr end
		if blueChanged then far.blueLine.Text = blueStr end
		if redChanged then far.redLine.Text = redStr end
		if statusChanged then far.statusLine.Text = statusStr end
	end
end

--- Update a single slot's UI elements. Writes to both billboard and far GUI.
--- FIX #31: Deterministic — only updates the specific pointIndex, no reordering.
--- FIX #33: Change detection — only writes properties when values differ from
--- what was last written. Uses a _cache table on each UI slot to track last state.
--- @param side "blue"|"red"
--- @param pointIndex number  1..9
local function updateSlotUi(side, pointIndex)
	local slots = side == "blue" and battleModel.blueSlots or battleModel.redSlots
	local slot = slots[pointIndex]

	-- Helper: apply data to one UI slot element set, with change detection
	local function applyToUi(ui)
		if not ui then return end
		if not ui._cache then ui._cache = {} end
		local c = ui._cache

		if slot then
			if not c.visible then
				ui.frame.Visible = true
				c.visible = true
			end

			local nameStr = slot.displayName or "?"
			if c.name ~= nameStr then
				ui.name.Text = nameStr
				c.name = nameStr
			end

			local hp    = math.max(0, math.floor(tonumber(slot.hp) or 0))
			local maxHp = math.max(0, math.floor(tonumber(slot.maxHp) or 0))
			local hpStr = maxHp > 0 and ("HP " .. hp .. "/" .. maxHp) or ""
			if c.hp ~= hpStr then
				ui.hp.Text = hpStr
				c.hp = hpStr
			end

			local sp    = math.max(0, math.floor(tonumber(slot.focus) or 0))
			local maxSp = math.max(0, math.floor(tonumber(slot.maxFocus) or 0))
			local spStr = maxSp > 0 and ("SP " .. sp .. "/" .. maxSp) or ""
			if c.sp ~= spStr then
				ui.sp.Text = spStr
				c.sp = spStr
			end

			local alive = slot.alive ~= false and hp > 0
			local showFaint = not alive
			if c.fainted ~= showFaint then
				ui.fainted.Visible = showFaint
				c.fainted = showFaint
			end
		else
			if c.visible ~= false then
				ui.frame.Visible = false
				c.visible = false
			end
			if c.fainted ~= false then
				ui.fainted.Visible = false
				c.fainted = false
			end
		end
	end

	local sUis = side == "blue" and summary.blueSlotUis or summary.redSlotUis
	applyToUi(sUis and sUis[pointIndex])

	local fUis = side == "blue" and far.blueSlotUis or far.redSlotUis
	applyToUi(fUis and fUis[pointIndex])
end

local function refreshAllSlots()
	for i = 1, 9 do
		updateSlotUi("blue", i)
		updateSlotUi("red", i)
	end
end

-- FIX #33: Only refresh slots that are marked dirty, not all 18.
local function refreshDirtySlots()
	for i = 1, 9 do
		if slotDirty.blue[i] then
			updateSlotUi("blue", i)
			slotDirty.blue[i] = nil
		end
		if slotDirty.red[i] then
			updateSlotUi("red", i)
			slotDirty.red[i] = nil
		end
	end
end

-- FIX #33: Cache last win bar state to skip redundant Size/Text writes.
local _lastWinLabel = nil
local _lastWinPBlue = nil

local function updateWinBar()
	local pBlue = computeWinLikely()
	-- Quantize to 0.01 to avoid micro-updates from floating point jitter
	pBlue = math.floor(pBlue * 100 + 0.5) / 100
	local pRed  = 1 - pBlue

	local label
	if pBlue > 0.55 then
		label = "Winning: " .. tostring(battleModel.blueName or "Blue")
	elseif pRed > 0.55 then
		label = "Winning: " .. tostring(battleModel.redName or "Red")
	else
		label = "Tied \226\128\148 too close to call"
	end

	-- Skip if nothing changed
	if _lastWinPBlue == pBlue and _lastWinLabel == label then return end
	_lastWinPBlue = pBlue
	_lastWinLabel = label

	if summary.winBarBlue then
		summary.winBarBlue.Size  = UDim2.new(pBlue, 0, 1, 0)
		summary.winBarRed.Size   = UDim2.new(pRed, 0, 1, 0)
		summary.winBarLabel.Text = label
	end
	if far.winBarBlue then
		far.winBarBlue.Size  = UDim2.new(pBlue, 0, 1, 0)
		far.winBarRed.Size   = UDim2.new(pRed, 0, 1, 0)
		far.winBarLabel.Text = label
	end
end

--- Flush dirty data to UI (called once per heartbeat tick, not per event).
--- FIX #33: Only refreshes slots that were individually marked dirty,
--- and only updates win bar when global dirty is set (data actually changed).
local function flushIfDirty()
	-- Check if any slot is dirty
	local anySlotDirty = false
	for i = 1, 9 do
		if slotDirty.blue[i] or slotDirty.red[i] then
			anySlotDirty = true
			break
		end
	end

	if not anySlotDirty and not globalDirty then return end

	refreshDirtySlots()
	updateWinBar()
	globalDirty = false
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Grid construction (shared by billboard and far GUI)
-- ══════════════════════════════════════════════════════════════════════════════

local function createLineLabel(parent, color, yOffset, name, font, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, -16, 0, 16)
	label.Position = UDim2.new(0, 8, 0, yOffset)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamMedium
	label.TextSize = textSize or 13
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.TextTransparency = 1
	label.Parent = parent
	return label
end

--- Build a 3x3 formation grid of creature slots.
--- @param parent Frame
--- @param name string  "BlueGrid" or "RedGrid"
--- @param x number     X offset
--- @param y number     Y offset
--- @param sideColor Color3
--- @param cellW number
--- @param cellH number
--- @param pad number
--- @param startTransparent bool  Whether text starts invisible (billboard = true, far = false)
--- @return Frame, TextLabel, table  Grid, header, slotUis[1..9]
local function makeGrid(parent, name, x, y, sideColor, cellW, cellH, pad, startTransparent)
	cellW = cellW or 56; cellH = cellH or 42; pad = pad or 6
	local startTrans = startTransparent ~= false and 1 or 0

	local grid = Instance.new("Frame")
	grid.Name = name
	grid.Size = UDim2.new(0, cellW * 3 + pad * 2, 0, cellH * 3 + pad * 2 + 20)
	grid.Position = UDim2.new(0, x, 0, y)
	grid.BackgroundTransparency = 1
	grid.Parent = parent

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 16)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 12
	header.TextColor3 = sideColor
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextTransparency = startTrans
	header.Text = name == "BlueGrid" and "BLUE TEAM" or "RED TEAM"
	header.Parent = grid

	local slots = {}
	local baseY = 20
	for r = 0, 2 do
		for c = 0, 2 do
			local idx = r * 3 + c + 1

			local slot = Instance.new("Frame")
			slot.Name = "Slot" .. idx
			slot.Size = UDim2.new(0, cellW, 0, cellH)
			slot.Position = UDim2.new(0, c * (cellW + pad), 0, baseY + r * (cellH + pad))
			slot.BackgroundColor3 = SLOT_BG_COLOR
			slot.BackgroundTransparency = startTransparent ~= false and 1 or 0.25
			slot.BorderSizePixel = 0
			slot.ClipsDescendants = true  -- FIX #31: prevent faint text overflow
			slot.Parent = grid
			Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)

			local ss = Instance.new("UIStroke")
			ss.Color = CARD_STROKE_COLOR
			ss.Thickness = 1
			ss.Transparency = startTransparent ~= false and 1 or 0.2
			ss.Parent = slot

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "Name"
			nameLbl.Size = UDim2.new(1, -6, 0, 12)
			nameLbl.Position = UDim2.new(0, 3, 0, 2)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 10
			nameLbl.TextColor3 = TITLE_COLOR
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTransparency = startTrans
			nameLbl.Text = ""
			nameLbl.Parent = slot

			local hpText = Instance.new("TextLabel")
			hpText.Name = "HPText"
			hpText.Size = UDim2.new(1, -6, 0, 10)
			hpText.Position = UDim2.new(0, 3, 0, 15)
			hpText.BackgroundTransparency = 1
			hpText.Font = Enum.Font.GothamMedium
			hpText.TextSize = 9
			hpText.TextColor3 = HP_COLOR
			hpText.TextXAlignment = Enum.TextXAlignment.Left
			hpText.TextTransparency = startTrans
			hpText.Text = ""
			hpText.Parent = slot

			local spText = Instance.new("TextLabel")
			spText.Name = "SPText"
			spText.Size = UDim2.new(1, -6, 0, 10)
			spText.Position = UDim2.new(0, 3, 0, 28)
			spText.BackgroundTransparency = 1
			spText.Font = Enum.Font.GothamMedium
			spText.TextSize = 9
			spText.TextColor3 = SP_COLOR
			spText.TextXAlignment = Enum.TextXAlignment.Left
			spText.TextTransparency = startTrans
			spText.Text = ""
			spText.Parent = slot

			-- FIX #31: Faint overlay is clipped by parent (ClipsDescendants),
			-- centered within the slot, and never changes position.
			local faint = Instance.new("TextLabel")
			faint.Name = "Fainted"
			faint.Size = UDim2.new(1, 0, 1, 0)
			faint.Position = UDim2.new(0, 0, 0, 0)
			faint.AnchorPoint = Vector2.new(0, 0)
			faint.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			faint.BackgroundTransparency = 0.6
			faint.Font = Enum.Font.GothamBlack
			faint.TextSize = 14
			faint.TextColor3 = FAINT_COLOR
			faint.TextTransparency = 0.05
			faint.Text = "FAINT"
			faint.Visible = false
			faint.ZIndex = 5
			faint.Parent = slot

			slots[idx] = {
				frame   = slot,
				stroke  = ss,
				name    = nameLbl,
				hp      = hpText,
				sp      = spText,
				fainted = faint,
			}
		end
	end

	return grid, header, slots
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Billboard construction (mid-range)
-- ══════════════════════════════════════════════════════════════════════════════

--- Create the BillboardGui summary card at the arena center. Idempotent.
--- @param arenaFolder Instance?
--- @param fallbackCenter Vector3?
--- @return boolean
local function ensureSummaryGui(arenaFolder, fallbackCenter)
	if summary.billboard and summary.billboard.Parent then return true end

	-- Resolve center with multi-fallback chain
	local centerPos, centerAdornee = nil, nil
	if arenaFolder and arenaFolder ~= workspace then
		centerPos, centerAdornee = resolveCenterPosition(arenaFolder)
	end
	if not centerPos and fallbackCenter then centerPos = fallbackCenter end
	if not centerPos then centerPos = computeCenterFromFighters() end
	if not centerPos then
		warn("[ArenaBattleSummary] ensureSummaryGui: no center position")
		return false
	end

	-- Anchor part
	local anchor = centerAdornee
	if not anchor then
		local anchorParent = (arenaFolder and arenaFolder ~= workspace) and arenaFolder or workspace
		local part = Instance.new("Part")
		part.Name = "ArenaSummaryAnchor"
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Size = Vector3.new(1, 1, 1)
		part.CFrame = CFrame.new(centerPos)
		part.Parent = anchorParent
		anchor = part
		summary.anchor = part
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "ArenaBattleSummary"
	bb.Adornee = anchor
	bb.Size = UDim2.new(0, 420, 0, 300)
	bb.StudsOffset = Vector3.new(0, 25, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = SUMMARY_MAX_DIST
	bb.Enabled = false
	bb.Parent = anchor

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = CARD_BG_COLOR
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Parent = bb
	Instance.new("UICorner", card).CornerRadius = CARD_CORNER_RADIUS

	local stroke = Instance.new("UIStroke")
	stroke.Color = CARD_STROKE_COLOR
	stroke.Thickness = CARD_STROKE_WIDTH
	stroke.Transparency = 1
	stroke.Parent = card

	local title      = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 20)
	title.Position = UDim2.new(0, 8, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = TITLE_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTransparency = 1
	title.Parent = card

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, -16, 0, 1)
	divider.Position = UDim2.new(0, 8, 0, 28)
	divider.BackgroundColor3 = CARD_STROKE_COLOR
	divider.BackgroundTransparency = 1
	divider.BorderSizePixel = 0
	divider.Parent = card

	local blueLine   = createLineLabel(card, BLUE_COLOR, 36, "BlueLine")
	local redLine    = createLineLabel(card, RED_COLOR, 54, "RedLine")
	local statusLine = createLineLabel(card, MUTED_COLOR, 76, "StatusLine", Enum.Font.GothamMedium, 12)

	-- Win bar
	local barBg = Instance.new("Frame")
	barBg.Name = "WinBarBG"
	barBg.Size = UDim2.new(1, -16, 0, 10)
	barBg.Position = UDim2.new(0, 8, 0, 98)
	barBg.BackgroundColor3 = WINBAR_BG_COLOR
	barBg.BackgroundTransparency = 1
	barBg.BorderSizePixel = 0
	barBg.Parent = card
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 6)

	local barBlue = Instance.new("Frame")
	barBlue.Name = "WinBarBlue"
	barBlue.Size = UDim2.new(0.5, 0, 1, 0)
	barBlue.BackgroundColor3 = BLUE_COLOR
	barBlue.BackgroundTransparency = 1
	barBlue.BorderSizePixel = 0
	barBlue.Parent = barBg
	Instance.new("UICorner", barBlue).CornerRadius = UDim.new(0, 6)

	local barRed = Instance.new("Frame")
	barRed.Name = "WinBarRed"
	barRed.AnchorPoint = Vector2.new(1, 0)
	barRed.Position = UDim2.new(1, 0, 0, 0)
	barRed.Size = UDim2.new(0.5, 0, 1, 0)
	barRed.BackgroundColor3 = RED_COLOR
	barRed.BackgroundTransparency = 1
	barRed.BorderSizePixel = 0
	barRed.Parent = barBg
	Instance.new("UICorner", barRed).CornerRadius = UDim.new(0, 6)

	local barLabel = Instance.new("TextLabel")
	barLabel.Name = "WinBarLabel"
	barLabel.Size = UDim2.new(1, -16, 0, 14)
	barLabel.Position = UDim2.new(0, 8, 0, 110)
	barLabel.BackgroundTransparency = 1
	barLabel.Font = Enum.Font.GothamMedium
	barLabel.TextSize = 11
	barLabel.TextColor3 = MUTED_COLOR
	barLabel.TextXAlignment = Enum.TextXAlignment.Left
	barLabel.TextTransparency = 1
	barLabel.Parent = card

	local blueGrid, blueHeader, blueSlots = makeGrid(card, "BlueGrid", 8, 132, BLUE_COLOR, 56, 42, 4, true)
	local redGrid, redHeader, redSlots    = makeGrid(card, "RedGrid", 226, 132, RED_COLOR, 56, 42, 4, true)

	summary.billboard      = bb
	summary.card           = card
	summary.stroke         = stroke
	summary.divider        = divider
	summary.title          = title
	summary.blueLine       = blueLine
	summary.redLine        = redLine
	summary.statusLine     = statusLine
	summary.winBarBG       = barBg
	summary.winBarBlue     = barBlue
	summary.winBarRed      = barRed
	summary.winBarLabel    = barLabel
	summary.blueGrid       = blueGrid
	summary.redGrid        = redGrid
	summary.blueGridHeader = blueHeader
	summary.redGridHeader  = redHeader
	summary.blueSlotUis    = blueSlots
	summary.redSlotUis     = redSlots

	setSummaryTexts()
	markDirty()
	return true
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Far screen GUI construction (350+ studs)
-- ══════════════════════════════════════════════════════════════════════════════

local function ensureFarScreenGui()
	if far.gui and far.gui.Parent then return true end

	local sg = Instance.new("ScreenGui")
	sg.Name = "ArenaBattleSummaryFar"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 100
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0)
	-- PC: move the panel down so its top bound begins below the ticker.
	-- Mobile keeps the current placement to fit within smaller screens.
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local notifGui  = playerGui:FindFirstChild("NotificationGUI")
	local tickerBar = notifGui and notifGui:FindFirstChild("TickerBar")
	local yTop
	if (not isMobile) and tickerBar and tickerBar:IsA("GuiObject") then
		yTop = math.floor(tickerBar.AbsolutePosition.Y + tickerBar.AbsoluteSize.Y + 4)
	else
		yTop = 18
	end
	root.Position = UDim2.new(0.5, 0, 0, yTop)
	root.Size = UDim2.new(0, 520, 0, 320)
	root.BackgroundColor3 = CARD_BG_COLOR
	root.BackgroundTransparency = CARD_BG_TRANSPARENCY
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = sg
	Instance.new("UICorner", root).CornerRadius = UDim.new(0, 16)
	local farStroke = Instance.new("UIStroke")
	farStroke.Color = CARD_STROKE_COLOR
	farStroke.Thickness = CARD_STROKE_WIDTH
	farStroke.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = TITLE_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = root

	-- Panel close button (works even if the crest badge gets covered).
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 34, 0, 24)
	closeBtn.Position = UDim2.new(1, -8, 0, 4)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	closeBtn.BackgroundTransparency = 0.15
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(240, 240, 245)
	closeBtn.TextSize = 14
	closeBtn.ZIndex = 20
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = root
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	closeBtn.MouseButton1Click:Connect(function()
		manualToggle = false
		if far.root then
			far.root.Visible = false
			far.visible = false
		end
		stopBadgePulse()
	end)

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -16, 0, 1)
	divider.Position = UDim2.new(0, 8, 0, 34)
	divider.BackgroundColor3 = CARD_STROKE_COLOR
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.Parent = root

	local blueLine   = createLineLabel(root, BLUE_COLOR, 44, "BlueLine")
	local redLine    = createLineLabel(root, RED_COLOR, 62, "RedLine")
	local statusLine = createLineLabel(root, MUTED_COLOR, 82, "StatusLine", Enum.Font.GothamMedium, 12)
	blueLine.TextTransparency   = 0
	redLine.TextTransparency    = 0
	statusLine.TextTransparency = 0

	local barBg = Instance.new("Frame")
	barBg.Name = "WinBarBG"
	barBg.Size = UDim2.new(1, -16, 0, 12)
	barBg.Position = UDim2.new(0, 8, 0, 106)
	barBg.BackgroundColor3 = WINBAR_BG_COLOR
	barBg.BorderSizePixel = 0
	barBg.Parent = root
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 7)

	local barBlue = Instance.new("Frame")
	barBlue.Name = "WinBarBlue"
	barBlue.Size = UDim2.new(0.5, 0, 1, 0)
	barBlue.BackgroundColor3 = BLUE_COLOR
	barBlue.BorderSizePixel = 0
	barBlue.Parent = barBg
	Instance.new("UICorner", barBlue).CornerRadius = UDim.new(0, 7)

	local barRed = Instance.new("Frame")
	barRed.Name = "WinBarRed"
	barRed.AnchorPoint = Vector2.new(1, 0)
	barRed.Position = UDim2.new(1, 0, 0, 0)
	barRed.Size = UDim2.new(0.5, 0, 1, 0)
	barRed.BackgroundColor3 = RED_COLOR
	barRed.BorderSizePixel = 0
	barRed.Parent = barBg
	Instance.new("UICorner", barRed).CornerRadius = UDim.new(0, 7)

	local barLabel = Instance.new("TextLabel")
	barLabel.Name = "WinBarLabel"
	barLabel.Size = UDim2.new(1, -16, 0, 16)
	barLabel.Position = UDim2.new(0, 8, 0, 120)
	barLabel.BackgroundTransparency = 1
	barLabel.Font = Enum.Font.GothamMedium
	barLabel.TextSize = 12
	barLabel.TextColor3 = MUTED_COLOR
	barLabel.TextXAlignment = Enum.TextXAlignment.Left
	barLabel.Parent = root

	local _, _, blueSlots = makeGrid(root, "BlueGrid", 8, 148, BLUE_COLOR, 74, 44, 5, false)
	local _, _, redSlots  = makeGrid(root, "RedGrid", 270, 148, RED_COLOR, 74, 44, 5, false)

	far.gui         = sg
	far.root        = root
	far.title       = title
	far.blueLine    = blueLine
	far.redLine     = redLine
	far.statusLine  = statusLine
	far.winBarBlue  = barBlue
	far.winBarRed   = barRed
	far.winBarLabel = barLabel
	far.blueSlotUis = blueSlots
	far.redSlotUis  = redSlots

	setSummaryTexts()
	markDirty()
	return true
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Crest shield toggle badge (FIX #30)
-- ══════════════════════════════════════════════════════════════════════════════

local function startBadgePulse()
	if badge.pulseConn or not badge.glow then return end
	local elapsed = 0
	badge.pulseConn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = (math.sin(elapsed * 4 * math.pi) + 1) / 2
		if badge.glow then
			badge.glow.Thickness     = 2 + t * 2
			badge.glow.Transparency  = t * 0.3
		end
	end)
end

local function stopBadgePulse()
	if badge.pulseConn then badge.pulseConn:Disconnect(); badge.pulseConn = nil end
	if badge.glow then badge.glow.Thickness = 2; badge.glow.Transparency = 0 end
end

local function createCrestBadge()
	if badge.button and badge.button.Parent then return end

	local row = TopRightBadgeTray.GetBadgeRow(player)

	local btn = Instance.new("TextButton")
	btn.Name = "CrestButton"
	btn.Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT)
	btn.LayoutOrder = TopRightBadgeTray.Order.ArenaCrest
	btn.Parent = row

	btn.BackgroundColor3       = BADGE_BG
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel        = 0
	btn.Text                   = "\226\154\148"
	btn.TextColor3             = BADGE_GOLD
	btn.Font                   = Enum.Font.GothamBold
	btn.TextSize               = 18
	btn.AutoButtonColor        = false
	btn.ZIndex                 = 100

	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

	-- Shield point
	local point = Instance.new("Frame")
	point.Name = "ShieldPoint"
	point.Size = UDim2.new(0, 16, 0, 10)
	point.Position = UDim2.new(0.5, 0, 1, -4)
	point.AnchorPoint = Vector2.new(0.5, 0)
	point.BackgroundColor3 = BADGE_BG
	point.BackgroundTransparency = 0.15
	point.BorderSizePixel = 0
	point.Rotation = 45
	point.ZIndex = 1
	point.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = BADGE_GOLD
	stroke.Thickness = 2
	stroke.Parent = btn

	-- Click: toggle summary
	btn.MouseButton1Click:Connect(function()
		manualToggle = not manualToggle
		if far.root then
			far.root.Visible = manualToggle
			far.visible      = manualToggle
			-- FIX #33: No markDirty needed — UI already has cached values
		end
		stopBadgePulse()
		-- Scale bounce
		TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Back), {
			Size = UDim2.new(0, BADGE_WIDTH + 6, 0, BADGE_HEIGHT + 6)
		}):Play()
		task.delay(0.12, function()
			if btn and btn.Parent then
				TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT)
				}):Play()
			end
		end)
	end)

	badge.gui    = row:FindFirstAncestorWhichIsA("ScreenGui")
	badge.button = btn
	badge.glow   = stroke
	btn.Visible  = false
end

local function updateBadgeVisibility(inProgress)
	if inProgress and not badge.visible then
		createCrestBadge()
		if not badge.button then return end
		badge.visible = true
		badge.button.Visible = true
		badge.button.Size = UDim2.new(0, 0, 0, 0)
		TweenService:Create(badge.button, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT)
		}):Play()
		startBadgePulse()
		manualToggle = false
	elseif not inProgress and badge.visible then
		stopBadgePulse()
		badge.visible  = false
		manualToggle   = false
		if badge.button and badge.button.Parent then
			TweenService:Create(badge.button, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0)
			}):Play()
			task.delay(0.3, function()
				if badge.button then badge.button.Visible = false end
			end)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Billboard fade in/out
-- ══════════════════════════════════════════════════════════════════════════════

local function fadeIn()
	if summary.visible or not summary.billboard then return end
	cancelTweens()
	summary.visible = true
	summary.billboard.Enabled = true

	local info = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	addTween(summary.card, info, { BackgroundTransparency = CARD_BG_TRANSPARENCY })
	addTween(summary.stroke, info, { Transparency = 0 })
	addTween(summary.divider, info, { BackgroundTransparency = 0.5 })
	addTween(summary.title, info, { TextTransparency = 0 })
	addTween(summary.blueLine, info, { TextTransparency = 0 })
	addTween(summary.redLine, info, { TextTransparency = 0 })
	addTween(summary.statusLine, info, { TextTransparency = 0 })
	addTween(summary.winBarBG, info, { BackgroundTransparency = 0.25 })
	addTween(summary.winBarBlue, info, { BackgroundTransparency = 0 })
	addTween(summary.winBarRed, info, { BackgroundTransparency = 0 })
	addTween(summary.winBarLabel, info, { TextTransparency = 0 })
	if summary.blueGridHeader then addTween(summary.blueGridHeader, info, { TextTransparency = 0 }) end
	if summary.redGridHeader then addTween(summary.redGridHeader, info, { TextTransparency = 0 }) end
	for _, ui in pairs(summary.blueSlotUis or {}) do
		addTween(ui.frame, info, { BackgroundTransparency = 0.25 })
		addTween(ui.stroke, info, { Transparency = 0.2 })
		addTween(ui.name, info, { TextTransparency = 0 })
		addTween(ui.hp, info, { TextTransparency = 0 })
		addTween(ui.sp, info, { TextTransparency = 0 })
	end
	for _, ui in pairs(summary.redSlotUis or {}) do
		addTween(ui.frame, info, { BackgroundTransparency = 0.25 })
		addTween(ui.stroke, info, { Transparency = 0.2 })
		addTween(ui.name, info, { TextTransparency = 0 })
		addTween(ui.hp, info, { TextTransparency = 0 })
		addTween(ui.sp, info, { TextTransparency = 0 })
	end
end

local function fadeOut()
	if not summary.visible or not summary.billboard then return end
	cancelTweens()
	summary.visible = false

	local info = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	addTween(summary.card, info, { BackgroundTransparency = 1 })
	addTween(summary.stroke, info, { Transparency = 1 })
	addTween(summary.divider, info, { BackgroundTransparency = 1 })
	addTween(summary.title, info, { TextTransparency = 1 })
	addTween(summary.blueLine, info, { TextTransparency = 1 })
	addTween(summary.redLine, info, { TextTransparency = 1 })
	addTween(summary.statusLine, info, { TextTransparency = 1 })
	addTween(summary.winBarBG, info, { BackgroundTransparency = 1 })
	addTween(summary.winBarBlue, info, { BackgroundTransparency = 1 })
	addTween(summary.winBarRed, info, { BackgroundTransparency = 1 })
	addTween(summary.winBarLabel, info, { TextTransparency = 1 })
	if summary.blueGridHeader then addTween(summary.blueGridHeader, info, { TextTransparency = 1 }) end
	if summary.redGridHeader then addTween(summary.redGridHeader, info, { TextTransparency = 1 }) end
	for _, ui in pairs(summary.blueSlotUis or {}) do
		addTween(ui.frame, info, { BackgroundTransparency = 1 })
		addTween(ui.stroke, info, { Transparency = 1 })
		addTween(ui.name, info, { TextTransparency = 1 })
		addTween(ui.hp, info, { TextTransparency = 1 })
		addTween(ui.sp, info, { TextTransparency = 1 })
		ui.fainted.Visible = false
	end
	for _, ui in pairs(summary.redSlotUis or {}) do
		addTween(ui.frame, info, { BackgroundTransparency = 1 })
		addTween(ui.stroke, info, { Transparency = 1 })
		addTween(ui.name, info, { TextTransparency = 1 })
		addTween(ui.hp, info, { TextTransparency = 1 })
		addTween(ui.sp, info, { TextTransparency = 1 })
		ui.fainted.Visible = false
	end

	task.delay(FADE_DURATION + 0.05, function()
		if summary.billboard and summary.billboard.Parent and not summary.visible then
			summary.billboard.Enabled = false
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- InfoTag gating
-- ══════════════════════════════════════════════════════════════════════════════

local INFOTAG_ORIG_MAXDIST = {}  -- [BillboardGui] = original MaxDistance

local function setArenaCreatureTagVisible(model, enabled)
	local bb = model:FindFirstChild("InfoTag")
	if not bb or not bb:IsA("BillboardGui") then return end
	if enabled then
		bb.Enabled = true
		local orig = INFOTAG_ORIG_MAXDIST[bb]
		if orig then bb.MaxDistance = orig end
	else
		if not INFOTAG_ORIG_MAXDIST[bb] then
			INFOTAG_ORIG_MAXDIST[bb] = bb.MaxDistance
		end
		bb.Enabled = false
		bb.MaxDistance = 0
	end
end

local function setArenaCreatureHPVisible(model, enabled)
	local bb = model:FindFirstChild("InfoTag")
	if not bb or not bb:IsA("BillboardGui") then return end
	local hpBg    = bb:FindFirstChild("HPBarBG")
	local hpLabel = bb:FindFirstChild("HPLabel")
	if hpBg and hpBg:IsA("Frame") then hpBg.Visible = enabled end
	if hpLabel and hpLabel:IsA("TextLabel") then hpLabel.Visible = enabled end
end

local function applyTagGate(shouldShow)
	for _, model in ipairs(CollectionService:GetTagged(ARENA_CREATURE_TAG)) do
		if model and model:IsA("Model") and model.Parent then
			setArenaCreatureTagVisible(model, shouldShow)
		end
	end
end

local function applyHealthbarGate(shouldShow)
	for _, model in ipairs(CollectionService:GetTagged(ARENA_CREATURE_TAG)) do
		if model and model:IsA("Model") and model.Parent then
			setArenaCreatureHPVisible(model, shouldShow)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Live attribute polling (fallback data source)
-- ══════════════════════════════════════════════════════════════════════════════
-- FIX #31: MERGE strategy instead of clear-and-rebuild.
-- Creatures keep their pointIndex across polls. New creatures get the next free
-- slot. Removed creatures are cleared. This prevents slot-jumping.

local function pollArenaCreatureAttributes()
	local tagged = CollectionService:GetTagged(ARENA_CREATURE_TAG)
	if #tagged == 0 then return end

	-- Build a set of currently-alive creature IDs per team for cleanup later
	local seenBlue, seenRed = {}, {}

	for _, model in ipairs(tagged) do
		if not model or not model:IsA("Model") or not model.Parent then continue end

		local team = model:GetAttribute("Team")
		local cid  = model:GetAttribute("CreatureId")
		if not team or not cid then continue end

		local slots = (team == "blue") and battleModel.blueSlots or battleModel.redSlots
		local seen  = (team == "blue") and seenBlue or seenRed

		-- FIX #31: Determine a STABLE pointIndex for this creature.
		-- Priority: PointIndex attr → parent BattlePoint name → existing slot → next free.
		local pointIdx = model:GetAttribute("PointIndex")
		if not pointIdx and model.Parent and model.Parent.Name:match("^BattlePoint(%d+)$") then
			pointIdx = tonumber(model.Parent.Name:match("^BattlePoint(%d+)$"))
		end

		-- If no attribute/parent hint, check if this creature already has a slot
		if not pointIdx then
			for idx, slot in pairs(slots) do
				if slot.creatureId == cid then
					pointIdx = idx
					break
				end
			end
		end

		-- Last resort: next free slot
		if not pointIdx then
			for i = 1, 9 do
				if not slots[i] and not seen[i] then
					pointIdx = i
					break
				end
			end
		end
		if not pointIdx then continue end
		seen[pointIdx] = true

		-- Read HP/SP from InfoTag labels (most reliable live source)
		local hp, maxHp, sp, maxSp = 0, 0, 0, 0
		local fainted = model:GetAttribute("Fainted") == true

		local infoTag = model:FindFirstChild("InfoTag")
		if infoTag then
			local hpLabel = infoTag:FindFirstChild("HPLabel")
			if hpLabel and hpLabel:IsA("TextLabel") then
				local cur, mx = hpLabel.Text:match("(%d+)%s*/s*(%d+)")
				if not cur then cur, mx = hpLabel.Text:match("(%d+)/(%d+)") end
				hp    = tonumber(cur) or 0
				maxHp = tonumber(mx) or 0
			end
			local focusLabel = infoTag:FindFirstChild("FocusLabel") or infoTag:FindFirstChild("SPLabel")
			if focusLabel and focusLabel:IsA("TextLabel") then
				local cur, mx = focusLabel.Text:match("(%d+)/(%d+)")
				sp    = tonumber(cur) or 0
				maxSp = tonumber(mx) or 0
			end
		end

		-- Fallback to model attributes
		if maxHp == 0 then
			hp    = tonumber(model:GetAttribute("HP")) or hp
			maxHp = tonumber(model:GetAttribute("MaxHP")) or maxHp
		end
		if maxSp == 0 then
			sp    = tonumber(model:GetAttribute("Focus")) or sp
			maxSp = tonumber(model:GetAttribute("MaxFocus")) or maxSp
		end

		local alive       = not fainted and hp > 0
		local info        = CreatureData and CreatureData.GetById(cid)
		local displayName = info and info.displayName or cid

		-- FIX #32: Merge into slot, but SKIP HP/SP overwrite if the slot has
		-- fresh RemoteEvent data (slot._seq == remoteSeq). The server's values
		-- are authoritative; InfoTag labels may show different (leveled/buffed)
		-- values that cause HP flashing. Poll only populates NEW slots or slots
		-- whose RemoteEvent data has gone stale (older seq).
		-- FIX #33: Only mark individual slots dirty when data actually changes.
		local slot = slots[pointIdx]
		local sideName = (team == "blue") and "blue" or "red"
		if not slot then
			-- Brand new slot — poll is the only data source
			slots[pointIdx] = {
				pointIndex  = pointIdx,
				creatureId  = cid,
				displayName = displayName,
				hp = hp, maxHp = maxHp,
				focus = sp, maxFocus = maxSp,
				attack = info and info.attack or 0,
				speed  = info and info.speed or 0,
				alive  = alive,
				_seq   = 0,  -- not from remote
			}
			markSlotDirty(sideName, pointIdx)
		elseif slot._seq == remoteSeq then
			-- FIX #32: Slot has FRESH remote data — only update alive/fainted
			-- status (which the server may not send fast enough for faint visuals)
			-- but do NOT touch hp/maxHp/focus/maxFocus.
			local changed = false
			if slot.alive ~= alive then slot.alive = alive; changed = true end
			if slot.creatureId ~= cid then slot.creatureId = cid; changed = true end
			if displayName and displayName ~= cid and slot.displayName ~= displayName then
				slot.displayName = displayName; changed = true
			end
			if changed then markSlotDirty(sideName, pointIdx) end
		else
			-- Stale or poll-only slot — overwrite freely, but track changes
			local changed = false
			if slot.hp ~= hp then slot.hp = hp; changed = true end
			if slot.maxHp ~= maxHp then slot.maxHp = maxHp; changed = true end
			if slot.focus ~= sp then slot.focus = sp; changed = true end
			if slot.maxFocus ~= maxSp then slot.maxFocus = maxSp; changed = true end
			if slot.alive ~= alive then slot.alive = alive; changed = true end
			if slot.creatureId ~= cid then slot.creatureId = cid; changed = true end
			if displayName and displayName ~= cid and slot.displayName ~= displayName then
				slot.displayName = displayName; changed = true
			end
			if changed then markSlotDirty(sideName, pointIdx) end
		end
	end

	-- FIX #31: Remove slots for creatures that are no longer present
	-- FIX #33: Only mark dirty for actually removed slots
	for idx in pairs(battleModel.blueSlots) do
		if not seenBlue[idx] then
			battleModel.blueSlots[idx] = nil
			markSlotDirty("blue", idx)
		end
	end
	for idx in pairs(battleModel.redSlots) do
		if not seenRed[idx] then
			battleModel.redSlots[idx] = nil
			markSlotDirty("red", idx)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- RemoteEvent hookups
-- ══════════════════════════════════════════════════════════════════════════════

task.spawn(function()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
	if not eventsFolder then
		warn("[ArenaBattleSummary] Events folder not found")
		return
	end

	local battleTeamsPlaced = eventsFolder:FindFirstChild("BattleTeamsPlaced")
	local battleStart       = eventsFolder:FindFirstChild("BattleStart")
	local battleEnd         = eventsFolder:FindFirstChild("BattleEnd")
	local arenaStateUpdate  = eventsFolder:FindFirstChild("ArenaStateUpdate")

	if battleTeamsPlaced and battleTeamsPlaced:IsA("RemoteEvent") then
		battleTeamsPlaced.OnClientEvent:Connect(function(blueData, redData, kingName, challengerName)
			remoteSeq += 1  -- FIX #32: mark all new slots as authoritative
			battleModel.blueName = kingName or tostring(workspace:GetAttribute("ArenaFighterBlueName") or "Blue")
			battleModel.redName  = challengerName or tostring(workspace:GetAttribute("ArenaFighterRedName") or "Red")

			table.clear(battleModel.blueSlots)
			table.clear(battleModel.redSlots)

			for _, d in ipairs(blueData or {}) do
				if d.pointIndex then
					battleModel.blueSlots[d.pointIndex] = {
						pointIndex  = d.pointIndex,
						creatureId  = d.creatureId,
						displayName = d.displayName,
						hp = d.hp, maxHp = d.maxHp,
						focus = d.focus, maxFocus = d.maxFocus,
						attack = d.attack, speed = d.speed,
						alive = true,
						_seq = remoteSeq,  -- FIX #32
					}
				end
			end
			for _, d in ipairs(redData or {}) do
				if d.pointIndex then
					battleModel.redSlots[d.pointIndex] = {
						pointIndex  = d.pointIndex,
						creatureId  = d.creatureId,
						displayName = d.displayName,
						hp = d.hp, maxHp = d.maxHp,
						focus = d.focus, maxFocus = d.maxFocus,
						attack = d.attack, speed = d.speed,
						alive = true,
						_seq = remoteSeq,  -- FIX #32
					}
				end
			end

			setSummaryTexts()
			markDirty()
		end)
	end

	if battleStart and battleStart:IsA("RemoteEvent") then
		battleStart.OnClientEvent:Connect(function(kingName, challName)
			battleModel.inProgress = true
			battleModel.blueName   = kingName or battleModel.blueName
			battleModel.redName    = challName or battleModel.redName
			setSummaryTexts()
		end)
	end

	if battleEnd and battleEnd:IsA("RemoteEvent") then
		battleEnd.OnClientEvent:Connect(function()
			battleModel.inProgress = false
			manualToggle = false
			setSummaryTexts()
		end)
	end

	if arenaStateUpdate and arenaStateUpdate:IsA("RemoteEvent") then
		arenaStateUpdate.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then return end
			remoteSeq += 1  -- FIX #32: mark updated slots as authoritative
			-- FIX #33: Only mark individual slots dirty when values differ
			for _, d in ipairs(payload.blue or {}) do
				local slot = d.pointIndex and battleModel.blueSlots[d.pointIndex]
				if slot then
					local changed = false
					if slot.hp ~= d.hp then slot.hp = d.hp; changed = true end
					if slot.maxHp ~= d.maxHp then slot.maxHp = d.maxHp; changed = true end
					if slot.focus ~= d.focus then slot.focus = d.focus; changed = true end
					if slot.maxFocus ~= d.maxFocus then slot.maxFocus = d.maxFocus; changed = true end
					if slot.alive ~= d.alive then slot.alive = d.alive; changed = true end
					slot.attack = slot.attack or d.attack
					slot.speed  = slot.speed or d.speed
					slot._seq = remoteSeq  -- FIX #32
					if changed then markSlotDirty("blue", d.pointIndex) end
				end
			end
			for _, d in ipairs(payload.red or {}) do
				local slot = d.pointIndex and battleModel.redSlots[d.pointIndex]
				if slot then
					local changed = false
					if slot.hp ~= d.hp then slot.hp = d.hp; changed = true end
					if slot.maxHp ~= d.maxHp then slot.maxHp = d.maxHp; changed = true end
					if slot.focus ~= d.focus then slot.focus = d.focus; changed = true end
					if slot.maxFocus ~= d.maxFocus then slot.maxFocus = d.maxFocus; changed = true end
					if slot.alive ~= d.alive then slot.alive = d.alive; changed = true end
					slot.attack = slot.attack or d.attack
					slot.speed  = slot.speed or d.speed
					slot._seq = remoteSeq  -- FIX #32
					if changed then markSlotDirty("red", d.pointIndex) end
				end
			end
		end)
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- Main heartbeat loop
-- ══════════════════════════════════════════════════════════════════════════════

local timeSince    = 0
local pollSince    = 0
local lastHPShown  = nil
local lastTagsShown = nil
local lastFarShown = nil

RunService.Heartbeat:Connect(function(dt)
	timeSince += dt
	if timeSince < SCAN_INTERVAL then return end
	timeSince = 0

	-- ── Step 1: Find arena ─────────────────────────────────────────────
	local arenaFolder = workspace:FindFirstChild("Arena") or findArenaContainerFromFighters()
	local tagged      = CollectionService:GetTagged(ARENA_CREATURE_TAG)
	local hasFighters = #tagged > 0

	if not arenaFolder and not hasFighters then
		if summary.visible then fadeOut() end
		if far.root then far.root.Visible = false; far.visible = false end
		updateBadgeVisibility(false)
		return
	end

	-- ── Step 2: Player root ────────────────────────────────────────────
	local root = getRoot()
	if not root then return end

	-- ── Step 3: Center position ────────────────────────────────────────
	local centerPos = nil
	if arenaFolder and arenaFolder ~= workspace then
		centerPos = resolveCenterPosition(arenaFolder)
	end
	if not centerPos and hasFighters then
		centerPos = computeCenterFromFighters()
	end
	if not centerPos then return end

	-- ── Step 4: Distance ───────────────────────────────────────────────
	local p  = root.Position
	local dx = p.X - centerPos.X
	local dz = p.Z - centerPos.Z
	local dist = math.sqrt(dx * dx + dz * dz)

	-- ── Step 5: In-progress check ──────────────────────────────────────
	local wsAttr     = workspace:GetAttribute("ArenaBattleInProgress")
	local inProgress = (wsAttr == true) or hasFighters

	if battleModel.inProgress ~= inProgress then
		battleModel.inProgress = inProgress
		battleModel.blueName = tostring(workspace:GetAttribute("ArenaFighterBlueName") or battleModel.blueName or "Blue")
		battleModel.redName  = tostring(workspace:GetAttribute("ArenaFighterRedName") or battleModel.redName or "Red")
		setSummaryTexts()
		markDirty()
	end

	-- ── Step 6: Create GUIs if needed ──────────────────────────────────
	if inProgress then
		local wasNil = summary.billboard == nil
		pcall(ensureSummaryGui, arenaFolder, centerPos)
		pcall(ensureFarScreenGui)
		-- ensureSummaryGui already calls markDirty() on first creation
	end

	-- ── Step 7: Live attribute poll ────────────────────────────────────
	pollSince += SCAN_INTERVAL
	if pollSince >= POLL_INTERVAL and hasFighters then
		pollSince = 0
		pcall(pollArenaCreatureAttributes)
	end

	-- ── Step 7.5: Badge visibility ─────────────────────────────────────
	updateBadgeVisibility(inProgress)

	-- ── Step 8: Far on-screen summary ──────────────────────────────────
	-- Hidden by default. Only shows when player clicks the crest badge.
	local shouldShowFar = manualToggle and inProgress

	if lastFarShown ~= shouldShowFar then
		lastFarShown = shouldShowFar
		if far.root then
			far.root.Visible = shouldShowFar
			far.visible      = shouldShowFar
			-- FIX #33: Visibility toggle doesn't need a full data refresh.
			-- The UI elements already have cached values from prior updates.
		end
	end

	-- ── Step 9: Billboard summary ──────────────────────────────────────
	-- Badge-controlled. Shows in mid-range (60-350) when toggle is ON.
	local shouldShowSummary = false
	if manualToggle and inProgress and summary.billboard then
		shouldShowSummary = (dist >= SUMMARY_SHOW_DIST) and (dist <= SUMMARY_MAX_DIST)
	end
	if shouldShowFar then shouldShowSummary = false end

	if shouldShowSummary and not summary.visible then
		fadeIn()
	elseif not shouldShowSummary and summary.visible then
		fadeOut()
	end

	-- ── Step 10: InfoTag gating ────────────────────────────────────────
	local shouldShowTags = (dist <= SUMMARY_SHOW_DIST) and not shouldShowFar
	if lastTagsShown ~= shouldShowTags then
		lastTagsShown = shouldShowTags
		applyTagGate(shouldShowTags)
	end

	local shouldShowHP = (dist <= HEALTHBAR_SHOW_DIST)
	if lastHPShown ~= shouldShowHP then
		lastHPShown = shouldShowHP
		applyHealthbarGate(shouldShowHP)
	end

	-- ── Flush dirty data to UI (once per tick) ─────────────────────────
	flushIfDirty()
end)

-- When a new ArenaCreature is tagged mid-battle, apply current gate state
CollectionService:GetInstanceAddedSignal(ARENA_CREATURE_TAG):Connect(function(model)
	if lastTagsShown ~= nil and not lastTagsShown then
		if model and model:IsA("Model") then
			setArenaCreatureTagVisible(model, false)
		end
	end
end)

print("[ArenaBattleSummary] Initialized")
