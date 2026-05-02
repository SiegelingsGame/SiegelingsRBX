-- KnightBaseSystem.lua - ServerScriptService (ModuleScript)
-- ═══════════════════════════════════════════════════════════════════════════════
-- FIX #35: Knight Base Rental System
-- Allows players to temporarily relocate their entire base (Plot model) to a
-- biome outpost ("KnightBases") for a configurable duration (default 5 minutes).
--
-- Each outer biome (Desert, Ocean, Electric, Cave) has a KnightBases folder
-- containing 2 PlotCenter parts (slots). Players walk up and press E to rent.
--
-- During rental:
--   - The Plot model is physically PivotTo'd to the knight base location
--   - Recall (goHome) naturally teleports to the new location (PlotCenter moved)
--   - Shield is BLOCKED via KnightBaseRental attribute on the Plot model
--   - All income, defense, battle creatures continue working at the new position
--
-- On expiry or disconnect:
--   - Base PivotTo'd back to original position
--   - Player teleported home (if still in game)
--   - Warnings at 30s and 10s remaining
--
-- Architecture:
--   - Init() called from MainServer after BasePlacementSystem + LaserDoorSystem.
--   - ProximityPrompts created on each knight base PlotCenter at runtime
--   - Physical PivotTo means ALL existing systems (income, defense AI, recall,
--     summary billboard, raids) work at the new location with zero changes
--   - Only shield needs explicit blocking (attribute check in LaserDoorSystem)
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local KnightBaseSystem = {}

-- ═══════════════════════════════════════════════════════════════════════════════
-- Dependencies (set in Init)
-- ═══════════════════════════════════════════════════════════════════════════════
local PlayerDataManager  -- player data: coins, plotId, playerLevel
local BasePlacementSystem -- PlaceCreatures() to refresh orbs after move
local LaserDoorSystem     -- reference only; shield blocking uses attribute

-- ═══════════════════════════════════════════════════════════════════════════════
-- State Tables
-- ═══════════════════════════════════════════════════════════════════════════════

-- Tracks which knight base slots are occupied
-- Key: "BiomeName_SlotIndex" (e.g. "DesertBiome_1"), Value: userId
local occupiedSlots = {}

-- Tracks active rentals per player
-- Key: userId, Value: { biome, slotIndex, originalPivot, expiresAt, timerThread, promptPart, placeholderSign }
local activeRentals = {}

-- Discovered knight base PlotCenter parts from workspace
-- Key: "BiomeName_SlotIndex", Value: BasePart (the PlotCenter in KnightBases)
local knightBaseParts = {}
-- Raw slot instance (BasePart or Model). Used for accurate center alignment.
local knightBaseTargets = {}

-- ProximityPrompts created on knight base PlotCenters
-- Key: "BiomeName_SlotIndex", Value: ProximityPrompt
local knightBasePrompts = {}
-- Original transparency for each rental point part so visibility can be restored.
local knightBasePartTransparency = {}
-- Canonical home pivots captured near server start: [plotId] = CFrame
local homePlotPivots = {}
-- Canonical home PlotCenter positions captured near server start: [plotId] = Vector3
local homePlotCenters = {}

-- Events folder reference
local eventsFolder = nil

-- ═══════════════════════════════════════════════════════════════════════════════
-- Config (read from GameConfig with fallbacks)
-- ═══════════════════════════════════════════════════════════════════════════════
local RENTAL_COST     = GameConfig.KnightBaseRentalCost     or 1000
local RENTAL_DURATION = GameConfig.KnightBaseRentalDuration or 300
local WARNING_TIMES   = GameConfig.KnightBaseWarningTimes   or {30, 10}
local BIOMES          = GameConfig.KnightBaseBiomes         or {"DesertBiome", "OceanBiome", "ElectricBiome", "CaveBiome"}
local SLOTS_PER_BIOME = GameConfig.KnightBaseSlotsPerBiome  or 2
local MIN_LEVEL       = GameConfig.KnightBaseMinPlayerLevel  or 5

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Find the plot model for a player
-- @param data  Player data table (must have .plotId)
-- @return Model|nil  The Plot model from workspace.BasePlots
-- ═══════════════════════════════════════════════════════════════════════════════
local function findPlotModel(data)
	if not data or not data.plotId or data.plotId == 0 then return nil end
	local plotsFolder = Workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return nil end
	return plotsFolder:FindFirstChild("Plot" .. data.plotId)
		or plotsFolder:FindFirstChild("Part" .. data.plotId)
end

local function getPlotIdFromModel(plotModel)
	if not plotModel then return nil end
	local id = plotModel.Name:match("^Plot(%d+)$") or plotModel.Name:match("^Part(%d+)$")
	return tonumber(id)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Get a friendly biome display name from the folder name
-- @param biome  e.g. "DesertBiome"
-- @return string  e.g. "Desert"
-- ═══════════════════════════════════════════════════════════════════════════════
local function getBiomeDisplayName(biome)
	return string.gsub(biome, "Biome$", "")
end

local function setKnightBasePointVisible(slotKey, isVisible)
	local part = knightBaseParts[slotKey]
	if not part or not part.Parent then return end

	if knightBasePartTransparency[slotKey] == nil then
		knightBasePartTransparency[slotKey] = part.Transparency
	end

	if isVisible then
		part.Transparency = knightBasePartTransparency[slotKey] or 0
	else
		part.Transparency = 1
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Fire a client notification via the NotificationManager pattern
-- Uses the ShowNotification event if available, otherwise KnightBaseWarning
-- @param player  Player to notify
-- @param message string  The notification text
-- @param level   string  "info"|"warning"|"error"
-- ═══════════════════════════════════════════════════════════════════════════════
local function notifyClient(player, message, level)
	if not eventsFolder then return end
	-- Try ShowNotification first (standard pattern)
	local showNotif = eventsFolder:FindFirstChild("ShowNotification")
	if showNotif then
		showNotif:FireClient(player, message, level or "info")
		return
	end
	-- Fallback: fire KnightBaseWarning with string payload
	local warnEvt = eventsFolder:FindFirstChild("KnightBaseWarning")
	if warnEvt then
		warnEvt:FireClient(player, message)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TELEPORT PART POSITION LOCK
-- The four zone-entrance teleport pads (CaveTele / DesertTele / ElectricTele /
-- OceanTele) live under plot.Floor3 so they travel with the plot for ownership
-- + streaming reasons. But their TeleportPart2 landing targets are world-fixed:
-- they teleport players to zone-entry coordinates baked relative to the hub.
-- When PivotTo moves the plot, the TeleportPart2 parts would translate too,
-- and the player ends up off-map.
--
-- Strategy: before any PivotTo on the plot model, snapshot the world CFrame of
-- every BasePart beneath those four Tele folders. After the PivotTo, restore
-- each part's CFrame. That way the plot shell moves freely while the teleport
-- targets stay exactly where they were placed in the world.
-- ═══════════════════════════════════════════════════════════════════════════════

local LOCKED_TELE_FOLDER_NAMES = {
	CaveTele     = true,
	DesertTele   = true,
	ElectricTele = true,
	OceanTele    = true,
}

local function getModelLikeWorldPosition(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		local namedCenter = inst:FindFirstChild("PlotCenter", true)
		if namedCenter and namedCenter:IsA("BasePart") then
			return namedCenter.Position
		end
		if inst.PrimaryPart then
			return inst.PrimaryPart.Position
		end
		local any = inst:FindFirstChildWhichIsA("BasePart", true)
		if any then
			return any.Position
		end
		local ok, pos = pcall(function() return inst:GetPivot().Position end)
		if ok then return pos end
	end
	return nil
end

local function getPlotCenterWorldPosition(plotModel)
	if not plotModel then return nil end
	local centerInst = plotModel:FindFirstChild("PlotCenter", true) or plotModel:FindFirstChild("PlotCenter")
	local pos = getModelLikeWorldPosition(centerInst)
	if pos then return pos end
	local ok, pivotPos = pcall(function() return plotModel:GetPivot().Position end)
	if ok then return pivotPos end
	return nil
end

local function captureHomePlotPivots()
	local plotsFolder = Workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return 0 end
	local count = 0
	for _, plotModel in ipairs(plotsFolder:GetChildren()) do
		if plotModel:IsA("Model") then
			local plotId = getPlotIdFromModel(plotModel)
			if plotId then
				if not homePlotPivots[plotId] then
					homePlotPivots[plotId] = plotModel:GetPivot()
					count += 1
				end
				if not homePlotCenters[plotId] then
					local centerPos = getPlotCenterWorldPosition(plotModel)
					if centerPos then
						homePlotCenters[plotId] = centerPos
					end
				end
			end
		end
	end
	return count
end

local function movePlotCenterTo(plotModel, targetCenterPos)
	if not plotModel or not targetCenterPos then return false end
	local currentCenter = getPlotCenterWorldPosition(plotModel)
	if not currentCenter then return false end
	local delta = targetCenterPos - currentCenter
	local currentPivot = plotModel:GetPivot()
	plotModel:PivotTo(currentPivot + delta)
	return true
end

--- Collect only the TeleportPart2 parts (plus explicitly opted-in descendants) under
--- the four Tele folders in plot.Floor3. TeleportPart1 and any other siblings
--- are intentionally excluded — they live relative to the plot and must move
--- with it. Only the biome-entrance landing targets should stay world-fixed.
--- Descendants are included only when they explicitly opt in via
--- LockToWorldWithTeleportTarget=true, so cosmetic extras (ramps/decor) don't
--- get stranded at the rental location.
--- are world-fixed.
--- @param plotModel Model — the player's plot model
--- @return BasePart[] — flat list of parts to world-lock across a PivotTo
local function collectLockedTeleParts(plotModel)
	local out = {}
	if not plotModel then return out end
	local floor3 = plotModel:FindFirstChild("Floor3")
	if not floor3 then return out end
	for _, teleFolder in ipairs(floor3:GetChildren()) do
		if LOCKED_TELE_FOLDER_NAMES[teleFolder.Name] then
			for _, child in ipairs(teleFolder:GetChildren()) do
				if child.Name == "TeleportPart2" then
					if child:IsA("BasePart") then
						table.insert(out, child)
					end
					-- Include only opted-in descendants to avoid locking
					-- unrelated cosmetic parts (e.g., ramps) to world space.
					for _, d in ipairs(child:GetDescendants()) do
						if d:IsA("BasePart") and d:GetAttribute("LockToWorldWithTeleportTarget") == true then
							table.insert(out, d)
						end
					end
				end
			end
		end
	end
	return out
end

--- Snapshot world CFrames for the parts returned by collectLockedTeleParts.
--- @param parts BasePart[]
--- @return { [BasePart]: CFrame }
local function snapshotTelePartCFrames(parts)
	local snap = {}
	for _, p in ipairs(parts) do
		if p.Parent then
			snap[p] = p.CFrame
		end
	end
	return snap
end

--- Restore each part to its saved CFrame (reverses translation caused by PivotTo).
--- @param snap { [BasePart]: CFrame }
local function restoreTelePartCFrames(snap)
	if not snap then return end
	for part, cf in pairs(snap) do
		if part and part.Parent then
			part.CFrame = cf
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PLACEHOLDER SIGN (temporary billboard at original plot location during rental)
-- When a base is physically PivotTo'd to a knight base, the SignPart moves with
-- it, leaving nothing at the home location. This creates a temporary sign so
-- other players visiting the empty plot see a countdown: "PlayerName returns
-- in M:SS" instead of an empty lot or stale "Available Base" text.
-- ═══════════════════════════════════════════════════════════════════════════════

--- Format seconds into "M:SS" display string.
--- @param seconds number — remaining seconds
--- @return string — e.g. "4:30", "0:09"
local function formatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

--- Create a temporary BillboardGui sign anchored at the original PlotCenter
--- position. The sign floats where the plot used to be so visitors see the
--- rental countdown.
--- @param originalPivot CFrame — the plot model's original pivot (from before PivotTo)
--- @param plotCenterOffset Vector3 — local offset of PlotCenter within the plot
--- @param playerName string — the renting player's display name
--- @param remaining number — initial seconds remaining
--- @return BasePart — the anchor part (store in rental state for cleanup)
local function createPlaceholderSign(originalPivot, plotCenterPos, playerName, remaining)
	-- Create a small invisible anchor part at the original plot center position
	local anchor = Instance.new("Part")
	anchor.Name = "KnightBaseSignPlaceholder"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(plotCenterPos + Vector3.new(0, 8, 0))
	anchor.Parent = Workspace

	-- BillboardGui visible from a distance so players can spot it across the map
	local bb = Instance.new("BillboardGui")
	bb.Name = "RentalCountdownBillboard"
	bb.Size = UDim2.new(0, 220, 0, 70)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 80
	bb.Active = false
	bb.Parent = anchor

	-- Player name label (top line)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 24)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = playerName .. "'s Base"
	nameLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Parent = bb

	-- Countdown label (bottom line)
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 0, 28)
	timerLabel.Position = UDim2.new(0, 0, 0, 24)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "Returns in " .. formatCountdown(remaining)
	timerLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	timerLabel.Font = Enum.Font.GothamMedium
	timerLabel.TextSize = 14
	timerLabel.TextStrokeTransparency = 0.3
	timerLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	timerLabel.Parent = bb

	return anchor
end

--- Update the countdown text on a placeholder sign.
--- @param anchor BasePart — the anchor part returned by createPlaceholderSign
--- @param remaining number — seconds remaining
local function updatePlaceholderSign(anchor, remaining)
	if not anchor or not anchor.Parent then return end
	local bb = anchor:FindFirstChild("RentalCountdownBillboard")
	if not bb then return end
	local timerLabel = bb:FindFirstChild("TimerLabel")
	if timerLabel then
		timerLabel.Text = "Returns in " .. formatCountdown(remaining)
	end
end

--- Remove the placeholder sign from the workspace.
--- @param anchor BasePart|nil — the anchor part to destroy
local function removePlaceholderSign(anchor)
	if anchor and anchor.Parent then
		anchor:Destroy()
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- FORWARD DECLARATIONS
-- ═══════════════════════════════════════════════════════════════════════════════
local returnToHome
local startRentalTimer

-- ═══════════════════════════════════════════════════════════════════════════════
-- returnToHome(player, skipTeleport)
-- Moves the player's base back to its original position, frees the knight base
-- slot, cancels the timer, and optionally teleports the player home.
--
-- @param player       Player  The player whose rental is ending
-- @param skipTeleport bool    If true, skip client notify on end (used for disconnect cleanup)
-- ═══════════════════════════════════════════════════════════════════════════════
returnToHome = function(player, skipTeleport)
	local userId = player.UserId
	local rental = activeRentals[userId]
	if not rental then return end

	-- Cancel timer thread if running
	if rental.timerThread then
		pcall(function() task.cancel(rental.timerThread) end)
		rental.timerThread = nil
	end

	-- Get the plot model
	local data = PlayerDataManager.GetData(player)
	local plotModel = findPlotModel(data)

	if plotModel then
		local plotId = getPlotIdFromModel(plotModel)
		local targetHomePivot = (plotId and homePlotPivots[plotId]) or rental.originalPivot
		local targetHomeCenter = (plotId and homePlotCenters[plotId]) or rental.originalPlotCenterPos
		if plotId and not homePlotPivots[plotId] then
			homePlotPivots[plotId] = plotModel:GetPivot()
			targetHomePivot = homePlotPivots[plotId]
		end
		if plotId and not homePlotCenters[plotId] then
			local centerPos = getPlotCenterWorldPosition(plotModel)
			if centerPos then
				homePlotCenters[plotId] = centerPos
			end
		end
		if plotId and not targetHomeCenter then
			targetHomeCenter = homePlotCenters[plotId]
		end
		if not targetHomePivot then
			targetHomePivot = plotModel:GetPivot()
		end
		if not targetHomeCenter then
			targetHomeCenter = targetHomePivot.Position
		end

		-- Lock Floor3 teleport pads to their world positions so the PivotTo does
		-- not drag TeleportPart2 and friends off their intended zone-entry spots.
		local teleSnap = snapshotTelePartCFrames(collectLockedTeleParts(plotModel))

		-- Move by exact PlotCenter delta to avoid vertical drift from model pivot changes.
		local moved = movePlotCenterTo(plotModel, targetHomeCenter)
		if not moved then
			-- Fallback: at least return to the canonical home pivot if center-based move fails.
			plotModel:PivotTo(targetHomePivot)
		end

		restoreTelePartCFrames(teleSnap)

		-- Clear the rental attribute so shield works again
		plotModel:SetAttribute("KnightBaseRental", nil)
	end

	-- Free the occupied slot
	local slotKey = rental.biome .. "_" .. rental.slotIndex
	occupiedSlots[slotKey] = nil
	setKnightBasePointVisible(slotKey, true)

	-- Re-enable the ProximityPrompt on the freed slot
	local prompt = knightBasePrompts[slotKey]
	if prompt then
		prompt.Enabled = true
		prompt.ActionText = "Rent Knight Base"
		prompt.ObjectText = getBiomeDisplayName(rental.biome)
	end

	-- Remove the temporary placeholder sign at the original plot location
	if rental.placeholderSign then
		removePlaceholderSign(rental.placeholderSign)
		rental.placeholderSign = nil
	end

	-- Clear rental state
	activeRentals[userId] = nil

	-- Refresh creature orbs at home position
	if BasePlacementSystem and BasePlacementSystem.PlaceCreatures then
		pcall(function() BasePlacementSystem.PlaceCreatures(player) end)
	end

	-- Do not force-teleport the player (or companion) when the base returns home.

	-- Notify client (unless they already left — skipTeleport)
	if not skipTeleport then
		local returnedEvt = eventsFolder and eventsFolder:FindFirstChild("KnightBaseReturned")
		if returnedEvt then
			returnedEvt:FireClient(player)
		end

		notifyClient(player, "Your base has returned home!", "info")
	end

	print("[KnightBaseSystem] Rental ended for " .. player.Name .. " (slot " .. slotKey .. ")")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- startRentalTimer(player)
-- Spawns a coroutine that counts down every second, fires timer updates to
-- the client, fires warnings at configured thresholds, and auto-returns
-- the base when time expires.
--
-- @param player  Player  The player with an active rental
-- ═══════════════════════════════════════════════════════════════════════════════
startRentalTimer = function(player)
	local userId = player.UserId
	local rental = activeRentals[userId]
	if not rental then return end

	local timerEvt = eventsFolder and eventsFolder:FindFirstChild("KnightBaseTimer")
	local warnEvt  = eventsFolder and eventsFolder:FindFirstChild("KnightBaseWarning")

	-- Build a set of warning thresholds for O(1) lookup
	local warningSet = {}
	for _, t in ipairs(WARNING_TIMES) do
		warningSet[t] = true
	end

	rental.timerThread = task.spawn(function()
		local remaining = RENTAL_DURATION

		while remaining > 0 do
			task.wait(1)
			remaining = remaining - 1

			-- Bail if rental was cancelled externally
			if not activeRentals[userId] then return end

			-- Fire timer update to client every second
			if timerEvt and player.Parent then
				timerEvt:FireClient(player, remaining)
			end

			-- Update the placeholder sign countdown at the original plot location
			local rental = activeRentals[userId]
			if rental and rental.placeholderSign then
				updatePlaceholderSign(rental.placeholderSign, remaining)
			end

			-- Fire warning at configured thresholds (30s, 10s)
			if warningSet[remaining] and warnEvt and player.Parent then
				warnEvt:FireClient(player, remaining)
			end
		end

		-- Time's up — return base to home
		if activeRentals[userId] then
			returnToHome(player, false)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- moveBaseToSlot(player, biome, slotIndex)
-- Physically relocates the player's Plot model to the knight base PlotCenter
-- position, refreshes creature orbs, teleports the player, and starts the timer.
--
-- @param player    Player  The renting player
-- @param biome     string  e.g. "DesertBiome"
-- @param slotIndex number  1 or 2
-- ═══════════════════════════════════════════════════════════════════════════════
local function moveBaseToSlot(player, biome, slotIndex)
	local userId = player.UserId
	local data = PlayerDataManager.GetData(player)
	local plotModel = findPlotModel(data)
	if not plotModel then
		notifyClient(player, "Could not find your base!", "error")
		return false
	end

	local slotKey = biome .. "_" .. slotIndex
	local knightTarget = knightBaseTargets[slotKey] or knightBaseParts[slotKey]
	local knightCenterPos = getModelLikeWorldPosition(knightTarget)
	if not knightCenterPos then
		notifyClient(player, "Knight base slot not found!", "error")
		return false
	end

	-- Find the plot's own PlotCenter world position (supports nested Model/Part)
	local plotCenterPos = getPlotCenterWorldPosition(plotModel)
	if not plotCenterPos then
		notifyClient(player, "Your base is missing a PlotCenter!", "error")
		return false
	end

	-- Save original position for return + original PlotCenter position for placeholder sign
	local originalPivot = plotModel:GetPivot()
	local originalPlotCenterPos = plotCenterPos
	local plotId = getPlotIdFromModel(plotModel)
	if plotId and not homePlotPivots[plotId] then
		homePlotPivots[plotId] = originalPivot
	end
	if plotId and not homePlotCenters[plotId] then
		homePlotCenters[plotId] = originalPlotCenterPos
	end

	-- Lock Floor3 teleport pads to their world positions so the PivotTo does
	-- not drag TeleportPart2 and friends along with the plot. These parts
	-- teleport players to zone-entry points that are anchored in world space,
	-- not relative to the plot — without this, renters end up off the map.
	local teleSnap = snapshotTelePartCFrames(collectLockedTeleParts(plotModel))

	local moved = movePlotCenterTo(plotModel, knightCenterPos)
	if not moved then
		notifyClient(player, "Could not move base to rental slot!", "error")
		return false
	end

	restoreTelePartCFrames(teleSnap)

	-- Set attribute so LaserDoorSystem blocks shield activation
	-- FIX #35: LaserDoorSystem checks this attribute before activating shield
	plotModel:SetAttribute("KnightBaseRental", true)

	-- Mark slot as occupied
	occupiedSlots[slotKey] = userId
	setKnightBasePointVisible(slotKey, false)

	-- Create a placeholder sign at the ORIGINAL plot location so other players
	-- see a countdown ("PlayerName returns in M:SS") instead of an empty lot.
	-- The actual SignPart moved with the plot model, so we spawn a temporary one.
	local placeholderSign = createPlaceholderSign(
		originalPivot,
		originalPlotCenterPos, -- saved BEFORE PivotTo so it's the home location
		player.Name,
		RENTAL_DURATION
	)

	-- Store rental info
	activeRentals[userId] = {
		biome = biome,
		slotIndex = slotIndex,
		originalPivot = originalPivot,
		originalPlotCenterPos = originalPlotCenterPos,
		expiresAt = tick() + RENTAL_DURATION,
		timerThread = nil,
		placeholderSign = placeholderSign,
	}

	-- Disable ProximityPrompt on occupied slot + update text
	local prompt = knightBasePrompts[slotKey]
	if prompt then
		prompt.Enabled = false
	end

	-- Refresh creature orbs at the new location
	if BasePlacementSystem and BasePlacementSystem.PlaceCreatures then
		pcall(function() BasePlacementSystem.PlaceCreatures(player) end)
	end

	-- Do not force-teleport the player (or companion) to the outpost; they can travel there on their own.

	-- Fire KnightBaseRented event to client (biome name + duration for HUD)
	local rentedEvt = eventsFolder and eventsFolder:FindFirstChild("KnightBaseRented")
	if rentedEvt then
		rentedEvt:FireClient(player, getBiomeDisplayName(biome), RENTAL_DURATION)
	end

	notifyClient(player, "Base deployed to " .. getBiomeDisplayName(biome) .. "! (" .. math.floor(RENTAL_DURATION / 60) .. " min)", "info")

	-- Start countdown timer
	startRentalTimer(player)

	print("[KnightBaseSystem] " .. player.Name .. " rented " .. slotKey .. " for " .. RENTAL_DURATION .. "s")
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- onRentTriggered(player, biome, slotIndex)
-- ProximityPrompt callback. Validates all preconditions and initiates the rental.
--
-- @param player    Player
-- @param biome     string  Biome folder name (e.g. "DesertBiome")
-- @param slotIndex number  1 or 2
-- ═══════════════════════════════════════════════════════════════════════════════
local function onRentTriggered(player, biome, slotIndex)
	local userId = player.UserId

	-- Already renting?
	if activeRentals[userId] then
		notifyClient(player, "You already have a knight base rental active!", "warning")
		return
	end

	-- Get player data
	local data = PlayerDataManager.GetData(player)
	if not data then
		notifyClient(player, "Player data not loaded!", "error")
		return
	end

	-- Level requirement
	local playerLevel = data.playerLevel or 1
	if playerLevel < MIN_LEVEL then
		notifyClient(player, "Requires Player Level " .. MIN_LEVEL .. " (you are Level " .. playerLevel .. ")", "warning")
		return
	end

	-- Slot availability
	local slotKey = biome .. "_" .. slotIndex
	if occupiedSlots[slotKey] then
		notifyClient(player, "This knight base slot is occupied!", "warning")
		return
	end

	-- Check if ANY slot in this biome is available (for better UX messaging)
	-- (not strictly needed since they triggered a specific prompt, but good safeguard)

	-- Coin check + deduction
	if not PlayerDataManager.SpendCoins(player, RENTAL_COST) then
		notifyClient(player, "Not enough coins! Need " .. RENTAL_COST, "warning")
		return
	end

	-- Fire CoinsUpdate to refresh client HUD
	local coinsEvt = eventsFolder and eventsFolder:FindFirstChild("CoinsUpdate")
	if coinsEvt then
		coinsEvt:FireClient(player, PlayerDataManager.GetCoins(player))
	end

	-- Initiate the base move
	local success = moveBaseToSlot(player, biome, slotIndex)
	if not success then
		-- Refund coins on failure
		PlayerDataManager.AddCoins(player, RENTAL_COST)
		if coinsEvt then
			coinsEvt:FireClient(player, PlayerDataManager.GetCoins(player))
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PlotCenter slot resolution (Studio may use a Model folder per slot)
-- ProximityPrompt must parent to a BasePart — Models need PrimaryPart or any part.
-- ═══════════════════════════════════════════════════════════════════════════════
local function resolveKnightSlotToBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart end
		local any = inst:FindFirstChildWhichIsA("BasePart", true)
		if any then return any end
	end
	return nil
end

--- Find PlotCenterN under KnightBases: direct child first, then recursive (nested folders).
local function findKnightSlotInstance(knightFolder, centerName)
	local direct = knightFolder:FindFirstChild(centerName)
	if direct then return direct end
	return knightFolder:FindFirstChild(centerName, true)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- discoverKnightBases()
-- Scans workspace.Biomes for KnightBases folders and stores PlotCenter parts.
-- Also tries biomeName .. "_" (e.g. CaveBiome_) for naming variants.
--
-- Expected workspace structure:
--   workspace.Biomes.DesertBiome.KnightBases.PlotCenter1
--   workspace.Biomes.DesertBiome.KnightBases.PlotCenter2
--   workspace.Biomes.OceanBiome.KnightBases.PlotCenter1
--   ... etc.
-- ═══════════════════════════════════════════════════════════════════════════════
--- @param options table|nil { quiet: boolean } — if true, no warn when a slot is still missing
local function discoverKnightBases(options)
	options = options or {}
	local quiet = options.quiet == true

	local biomesFolder = Workspace:FindFirstChild("Biomes")
	if not biomesFolder then
		if not quiet then
			warn("[KnightBaseSystem] workspace.Biomes folder not found!")
		end
		return 0
	end

	local count = 0
	for _, biomeName in ipairs(BIOMES) do
		local biomeFolder = biomesFolder:FindFirstChild(biomeName)
			or biomesFolder:FindFirstChild(biomeName .. "_")
		if not biomeFolder then
			if not quiet then
				warn("[KnightBaseSystem] Biome folder not found: " .. biomeName)
			end
			continue
		end

		local knightFolder = biomeFolder:FindFirstChild("KnightBases")
		if not knightFolder then
			if not quiet then
				warn("[KnightBaseSystem] KnightBases folder not found in " .. biomeFolder.Name)
			end
			continue
		end

		for slot = 1, SLOTS_PER_BIOME do
			local centerName = "PlotCenter" .. slot
			local key = biomeName .. "_" .. slot
			local raw = findKnightSlotInstance(knightFolder, centerName)
			local center = resolveKnightSlotToBasePart(raw)
			if center then
				knightBaseParts[key] = center
				knightBaseTargets[key] = raw or center
				count += 1
				print("[KnightBaseSystem] Found " .. key .. " at " .. tostring(center.Position) .. " (" .. (raw and raw.ClassName or "?") .. ")")
			elseif not quiet and not knightBaseParts[key] then
				warn("[KnightBaseSystem] Missing " .. centerName .. " (Part/Model with BasePart) in " .. biomeFolder.Name .. ".KnightBases")
			end
		end
	end

	return count
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- setupProximityPrompts()
-- Creates a ProximityPrompt on each discovered knight base PlotCenter.
-- When triggered, calls onRentTriggered with the correct biome/slot.
-- ═══════════════════════════════════════════════════════════════════════════════
local function setupProximityPrompts()
	for key, part in pairs(knightBaseParts) do
		-- Parse "DesertBiome_1" → biome="DesertBiome", slotIndex=1
		local biome, slotStr = string.match(key, "^(.+)_(%d+)$")
		local slotIndex = tonumber(slotStr)
		if not biome or not slotIndex then continue end

		if knightBasePrompts[key] and knightBasePrompts[key].Parent == part then
			continue
		end
		if knightBasePrompts[key] then
			knightBasePrompts[key]:Destroy()
			knightBasePrompts[key] = nil
		end

		-- Remove any existing prompt (idempotent)
		local existing = part:FindFirstChildOfClass("ProximityPrompt")
		if existing then existing:Destroy() end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Rent Knight Base"
		prompt.ObjectText = getBiomeDisplayName(biome)
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = part

		knightBasePrompts[key] = prompt

		if occupiedSlots[key] then
			prompt.Enabled = false
			setKnightBasePointVisible(key, false)
		else
			setKnightBasePointVisible(key, true)
		end

		-- Connect the prompt's Triggered event
		prompt.Triggered:Connect(function(plr)
			onRentTriggered(plr, biome, slotIndex)
		end)

		print("[KnightBaseSystem] ProximityPrompt created on " .. key)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════════

--- Check if a player currently has an active knight base rental.
-- @param player Player
-- @return bool
function KnightBaseSystem.IsPlayerRenting(player)
	return activeRentals[player.UserId] ~= nil
end

--- Get the rental info table for a player (or nil if not renting).
-- @param player Player
-- @return table|nil  { biome, slotIndex, originalPivot, expiresAt, timerThread }
function KnightBaseSystem.GetRentalInfo(player)
	return activeRentals[player.UserId]
end

--- Force return a player's base to home. Used externally if needed.
-- @param player Player
function KnightBaseSystem.ReturnToHome(player)
	returnToHome(player, false)
end

--- Cleanup on player disconnect. Returns base without teleporting the player.
-- Must be called BEFORE PlayerDataManager clears data and BEFORE dome removal.
-- @param player Player
function KnightBaseSystem.Cleanup(player)
	if activeRentals[player.UserId] then
		returnToHome(player, true) -- skipTeleport = true (player already left)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Init(playerDataMgr, basePlacementSys, laserDoorSys)
-- Called from MainServer after BasePlacementSystem and LaserDoorSystem are initialized.
--
-- @param playerDataMgr    PlayerDataManager module
-- @param basePlacementSys BasePlacementSystem module
-- @param laserDoorSys     LaserDoorSystem module (stored but not directly called;
--                         shield blocking uses KnightBaseRental attribute)
-- ═══════════════════════════════════════════════════════════════════════════════
function KnightBaseSystem.Init(playerDataMgr, basePlacementSys, laserDoorSys)
	PlayerDataManager  = playerDataMgr
	BasePlacementSystem = basePlacementSys
	LaserDoorSystem     = laserDoorSys

	-- Get events folder
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")

	-- Discover knight base PlotCenters in workspace
	local found = discoverKnightBases()
	print("[KnightBaseSystem] Discovered " .. found .. " knight base slots")

	local capturedHomes = captureHomePlotPivots()
	print("[KnightBaseSystem] Captured " .. capturedHomes .. " home plot pivots")

	if found == 0 then
		warn("[KnightBaseSystem] No knight base slots yet — will keep scanning (streaming / CaveBiome may load late)")
	end

	-- Create ProximityPrompts on each knight base PlotCenter
	setupProximityPrompts()

	-- Cave / distant biomes may stream in after Init; merge new slots without duplicating prompts
	task.spawn(function()
		for _ = 1, 15 do
			task.wait(3)
			discoverKnightBases({ quiet = true })
			setupProximityPrompts()
			captureHomePlotPivots()
		end
	end)

	-- Cleanup when players leave
	Players.PlayerRemoving:Connect(function(plr)
		if activeRentals[plr.UserId] then
			pcall(function() KnightBaseSystem.Cleanup(plr) end)
		end
	end)

	print("[KnightBaseSystem] Init complete — " .. found .. " slots across " .. #BIOMES .. " biomes")
end

return KnightBaseSystem
