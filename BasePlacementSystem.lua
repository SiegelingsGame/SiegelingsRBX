-- BasePlacementSystem.lua - ServerScriptService (ModuleScript)
-- Last updated: 2026-04-20 18:00
-- Places creature orbs on DefensePoints, IncomePoints, AND BattlePoints in each plot.
-- Supports multi-floor bases where points live inside Floor folders.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- BASE STRUCTURE CONTRACT (for custom bases / skin changes / agent updates)
-- ═══════════════════════════════════════════════════════════════════════════
-- All updates MUST preserve:
--   1. FLOOR FOLDERS: Plot must have Floor1, Floor2, Floor3 (Model or Folder).
--      Floor2 and Floor3 may be hidden until purchased; do not reparent or rename.
--   2. FLOOR ACCESS: Stairs (or equivalent) live inside Floor2 and Floor3.
--      setFloorVisibility toggles visibility/collision only; do not remove Stairs.
--   3. POINT NAMES & CONTINUITY: DefensePoint1..6 (Floor1), 7..12 (Floor2), 13..18 (Floor3);
--      IncomePoint same numbering; BattlePoint1..9 inside Floor2 (e.g. Floor2/BattleTeam/).
--      Do NOT reparent or rename point parts; discovery uses GetDescendants + name match.
--   4. PLOT ANCHORS: Point parts and floor structure parts are anchored in code when
--      visibility is set; custom bases should keep parts anchored to avoid fall-through.
--
-- Expected plot structure (multi-floor):
--   Plot1/
--     Floor1/
--       Carpet1/        optional decorative floor — tinted with Base Plots income color (see BaseExteriorSystem)
--       DefensePoints/  DefensePoint1..6
--       IncomePoints/   IncomePoint1..6
--     Floor2/           (invisible until purchased)
--       Carpet2/        optional decorative floor — tinted with Base Plots defense color
--       BattleTeam/     BattlePoint1..9 (INSIDE Floor2)
--       DefensePoints/  DefensePoint7..12
--       IncomePoints/   IncomePoint7..12
--       Stairs
--       [Glass parts: name contains "Glass" or attribute IsGlass = true → stay transparent]
--       BattlePointWall + Glass / IsGlass = invisible collision (stairs); ForceField walls stay visible.
--     Floor3/           (invisible until purchased)
--       DefensePoints/  DefensePoint13..18
--       IncomePoints/   IncomePoint13..18
--       Stairs
--     PlotCenter
--     SignPart
--
-- CRITICAL: BattleTeam is INSIDE Floor2. setFloorVisibility handles ALL
-- descendants of Floor2 including BattleTeam. There is NO separate
-- setBattleTeamVisibility function.
--
-- getPointsByPrefix uses GetDescendants() so it auto-discovers points in any sub-folder.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CreatureData = require(game.ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(game.ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(game.ReplicatedStorage.Modules.CreatureModelLoader)
local PlayerWorldStats = require(game.ReplicatedStorage.Modules:WaitForChild("PlayerWorldStats"))

-- Set true to log placement/slot resolution for troubleshooting
local PLACEMENT_DEBUG = false
local function placementLog(...) if PLACEMENT_DEBUG then print("[BasePlacement]", ...) end end
-- Set true to log defense target/LOS lock decisions
local DEFENSE_DEBUG = false
local function defenseLog(...) if DEFENSE_DEBUG then print("[BasePlacementDefense]", ...) end end

local RaidSystem = nil
pcall(function()
	RaidSystem = require(game:GetService("ServerScriptService"):FindFirstChild("RaidSystem") or game:GetService("ServerScriptService"):WaitForChild("RaidSystem", 2))
end)
local CreatureAnimation = require(game.ReplicatedStorage.Modules.CreatureAnimation)

local PlayerDataManager
local CreatureAI

local BasePlacementSystem = {}

local DEFENSE_TAG = "BaseDefenseCreature"
local INCOME_TAG = "BaseIncomeCreature"
local BATTLE_TAG = "BaseBattleCreature"
local PLOTS_FOLDER = nil
local placementLocks = {} -- userId -> true if placement in progress

-- -- HELPERS --

local function runWhenPlacementIdle(player, fn)
	local userId = player and player.UserId
	if not userId or not placementLocks[userId] then return false end
	task.spawn(function()
		for _ = 1, 30 do
			if not player.Parent then return end
			if not placementLocks[userId] then
				fn()
				return
			end
			task.wait(0.1)
		end
	end)
	return true
end

local function getPointsByPrefix(plotModel, prefix)
	local points = {}
	for _, child in ipairs(plotModel:GetDescendants()) do
		if child:IsA("BasePart") then
			local num = child.Name:match("^" .. prefix .. "(%d+)$")
			if num then
				table.insert(points, { part = child, index = tonumber(num) })
			end
		end
	end
	table.sort(points, function(a, b) return a.index < b.index end)
	return points
end

--- Studio folders may be "Floor2", "Floor 2", "Floor02"; used for visibility + slot floor detection.
local function floorIndexFromFloorFolderName(name)
	if type(name) ~= "string" then return nil end
	local n = name:match("^Floor(%d+)$") or name:match("^Floor%s+(%d+)$") or name:match("^Floor0*(%d+)$")
	return n and tonumber(n) or nil
end

local function resolveFloorFolder(plotModel, floorNum)
	if not plotModel or type(floorNum) ~= "number" then return nil end
	local candidates = {
		"Floor" .. floorNum,
		"Floor " .. floorNum,
		string.format("Floor%02d", floorNum),
	}
	for _, name in ipairs(candidates) do
		local f = plotModel:FindFirstChild(name)
		if f then return f end
	end
	for _, child in ipairs(plotModel:GetChildren()) do
		if floorIndexFromFloorFolderName(child.Name) == floorNum then
			return child
		end
	end
	return nil
end

-- Returns { [index] = part } for BattlePoints (BattlePoint1..9 inside Floor2).
-- CONTINUITY: Do not reparent/rename; slot index 1-9 maps to BattlePoint1-9.
-- getBattlePointMap: Only finds BattlePoints inside Floor2/BattleTeam.
-- Floor4/BaseGym also has BattlePoints (inside RedTeam/BlueTeam), but those are
-- exclusively for gym battles — battle creatures must NOT idle there.
local function getBattlePointMap(plotModel)
	local map = {}
	local floor2 = resolveFloorFolder(plotModel, 2)
	if not floor2 then return map end
	local battleTeam = floor2:FindFirstChild("BattleTeam")
	if not battleTeam then return map end
	for _, child in ipairs(battleTeam:GetDescendants()) do
		if child:IsA("BasePart") then
			local num = child.Name:match("^BattlePoint(%d+)$")
			if num then map[tonumber(num)] = child end
		end
	end
	return map
end

-- Glass stair-safety shells around Floor2 BattleTeam (name contains BattlePointWall + Glass / IsGlass).
-- Fully invisible but collidable — not the team-colored ForceField arena shells.
local function isGlassBattlePointSafetyWall(desc)
	if not desc:IsA("BasePart") then return false end
	local nl = desc.Name:lower()
	if not nl:find("battlepointwall", 1, true) then return false end
	if desc:GetAttribute("IsGlass") == true then return true end
	if nl:find("glass") then return true end
	if desc.Material == Enum.Material.Glass then return true end
	return false
end

-- Set BattlePoint + BattlePointWall colors in Floor2/BattleTeam.
-- IMPORTANT: only used for battle-team active toggle state.
-- Inactive = base white, Active = green.
-- Do NOT change materials here (preserve authored material).
local function setBattlePointColors(plotModel, battleTeamActive)
	local color = battleTeamActive and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(255, 255, 255)
	local floor2 = resolveFloorFolder(plotModel, 2)
	if not floor2 then return end
	local battleTeam = floor2:FindFirstChild("BattleTeam")
	if not battleTeam then return end
	for _, desc in ipairs(battleTeam:GetDescendants()) do
		if desc:IsA("BasePart") then
			local nl = desc.Name:lower()
			local isBattlePoint = desc.Name:match("^BattlePoint%d+$")
			local isBattlePointWall = nl:find("battlepointwall", 1, true)
			if isGlassBattlePointSafetyWall(desc) then
				-- Preserve glass safety walls as-authored.
			elseif isBattlePoint or isBattlePointWall then
				desc.Color = color
			end
		end
	end
end

local function findPlotModel(plotId)
	if not PLOTS_FOLDER then return nil end
	local id = tonumber(plotId)
	if not id or id <= 0 then return nil end
	local variants = {
		"Plot" .. id,
		"Part" .. id,
		string.format("Plot%02d", id),
		string.format("Part%02d", id),
		string.format("Plot%03d", id),
		string.format("Part%03d", id),
	}
	for _, name in ipairs(variants) do
		local m = PLOTS_FOLDER:FindFirstChild(name)
		if m then return m end
	end
	for _, child in ipairs(PLOTS_FOLDER:GetChildren()) do
		local pid = child.Name:match("^Plot(%d+)$") or child.Name:match("^Part(%d+)$")
		if tonumber(pid) == id then
			return child
		end
	end
	return nil
end

--- When PlayerRemoving runs, PlayerDataManager may have already cleared cache (plotId lost). Use OwnerUserId on plot.
local function findPlotModelForLeavingPlayer(player)
	if not PLOTS_FOLDER or not player then return nil end
	local data = PlayerDataManager.GetData(player)
	if data and data.plotId and data.plotId > 0 then
		local pm = findPlotModel(data.plotId)
		if pm then return pm end
	end
	local uid = player.UserId
	for _, plot in ipairs(PLOTS_FOLDER:GetChildren()) do
		if tonumber(plot:GetAttribute("OwnerUserId")) == uid then
			return plot
		end
	end
	return nil
end

--- Catch creatures reparented or left outside plot hierarchy (same tags + OwnerUserId).
local function destroyTaggedBaseCreaturesForOwnerUserId(ownerUserId)
	ownerUserId = tonumber(ownerUserId)
	if not ownerUserId then return end
	for _, tag in ipairs({ DEFENSE_TAG, INCOME_TAG, BATTLE_TAG }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if inst:IsA("Model") and tonumber(inst:GetAttribute("OwnerUserId")) == ownerUserId then
				if CreatureAI and CreatureAI.UnregisterCreature then
					pcall(function() CreatureAI.UnregisterCreature(inst) end)
				end
				if inst.Parent then
					inst:Destroy()
				end
			end
		end
	end
end

-- Get plot model and plotId from any descendant part (e.g. PlotCenter, walls)
local function getPlotFromPart(part)
	if not part or not PLOTS_FOLDER then return nil, nil end
	local current = part
	while current and current ~= workspace do
		if current.Parent == PLOTS_FOLDER then
			local id = current.Name:match("^Plot(%d+)$") or current.Name:match("^Part(%d+)$")
			if id then return current, tonumber(id) end
		end
		current = current.Parent
	end
	return nil, nil
end

-- Track players who touched plot center/walls but don't own and aren't on access list (physical invaders)
local activeInvaders = {} -- [plotId] = { [userId] = lastTouchTime }
local INVADER_TIMEOUT = 45

-- Helper: is this part a glass/window that should stay transparent when floor is visible?
local function setPlotInhabitedIsGlassPart(part)
	if part:GetAttribute("IsGlass") then return true end
	local n = part.Name and part.Name:lower() or ""
	if n:find("glass") then return true end
	if n:find("window") then return true end
	if n:find("pane") then return true end
	if n:find("panel") and not n:find("defense") and not n:find("income") and not n:find("battle") then return true end
	return false
end

-- Uninhabited plots: not visible, not collidable, not interactable. Only inhabited (claimed) bases appear.
-- Glass parts: when inhabited, do NOT set Transparency=0 (would make them opaque). setFloorVisibility
-- in PlaceCreatures handles correct glass transparency per floor. Skipping glass here prevents them
-- from breaking when RefreshAllPlotVisibility runs (e.g. before PlaceCreatures for that plot).
-- FIX #21: When inhabited=true, only show Floor1 parts. Floor2/Floor3 stay HIDDEN until PlaceCreatures
-- runs and calls setFloorVisibility based on actual owned floors. Previously ALL parts were shown,
-- causing upper floors (stairs, battle team, glass) to flash visible before purchase.
local function getFloorAncestorNum(part)
	local current = part.Parent
	while current and current ~= workspace do
		local floorNum = floorIndexFromFloorFolderName(current.Name)
		if floorNum then return floorNum end
		current = current.Parent
	end
	return nil
end

local function setPlotInhabited(plotModel, inhabited)
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			if inhabited then
				-- FIX #21: Only show Floor1 parts by default; Floor2/3 stay hidden
				-- until PlaceCreatures calls setFloorVisibility with actual ownership
				local floorNum = getFloorAncestorNum(desc)
				if floorNum and floorNum > 1 then
					-- Upper floor parts: keep hidden (PlaceCreatures will handle them)
					desc.Transparency = 1
					desc.CanCollide = false
					desc.CanQuery = false
				elseif not setPlotInhabitedIsGlassPart(desc) then
					desc.Transparency = 0
					desc.CanCollide = true
					desc.CanQuery = true
				else
					-- Glass on Floor1: let setFloorVisibility handle proper transparency
					desc.CanCollide = true
					desc.CanQuery = true
				end
			else
				desc.Transparency = 1
				desc.CanCollide = false
				desc.CanQuery = false
			end
		elseif desc:IsA("SelectionBox") then
			-- SelectionBoxes (e.g. in Floor3 TeleportParts) use Visible, not Transparency.
			-- Hide when uninhabited or on upper floors (Floor2/3) until purchased.
			local floorNum = getFloorAncestorNum(desc)
			desc.Visible = inhabited and (not floorNum or floorNum <= 1)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════
-- FLOOR-GATED POINT DISCOVERY
-- FIX #1 / FIX #3: Only returns points that live inside OWNED floor folders.
-- Without this, getPointsByPrefix returns ALL points from ALL floors, causing
-- creatures to be placed on Floor 2/3 points before those floors are purchased.
-- ══════════════════════════════════════════════════════════════════════════

-- Walk up ancestors of a part to find which FloorX folder it lives in.
-- Returns the floor number (1, 2, 3) or nil if not inside any floor folder.
-- FIX #5: Defined BEFORE getPointsForOwnedFloors which calls it.
local function getFloorForPart(part)
	local current = part.Parent
	while current do
		local floorNum = floorIndexFromFloorFolderName(current.Name)
		if floorNum then return floorNum end
		current = current.Parent
	end
	return nil
end

-- Returns true if part is inside a folder with this name (e.g. "DefensePoints", "IncomePoints").
local function isPartInFolderNamed(part, folderName)
	local current = part.Parent
	while current do
		if current.Name == folderName then return true end
		current = current.Parent
	end
	return false
end

-- Match PlayerDataManager.normalizeOwnedFloors: `{}` must not hide floor 1 (Lua: {} is truthy, so `or {1}` fails).
local function normalizeOwnedFloorsForPlacement(raw)
	if type(raw) ~= "table" then
		return {1}
	end
	local seen = {}
	local out = {}
	for k, v in pairs(raw) do
		local n = tonumber(v) or tonumber(k)
		if n and n >= 1 and n <= 6 then
			if not seen[n] then
				seen[n] = true
				table.insert(out, n)
			end
		end
	end
	table.sort(out)
	if #out == 0 then
		return {1}
	end
	if not seen[1] then
		table.insert(out, 1)
		table.sort(out)
	end
	return out
end

-- Returns points matching prefix but ONLY from owned floors.
-- excludeFolder: if set (e.g. "DefensePoints"), skip parts inside that folder so income/defense stay separate.
-- CONTINUITY: Slot index maps to array position (1-based). Point names DefensePoint1..6 (Floor1),
-- 7..12 (Floor2), 13..18 (Floor3) must be preserved for correct defense/income slot mapping.
-- @param plotModel Model - the plot to search
-- @param prefix string - e.g. "DefensePoint" or "IncomePoint"
-- @param ownedFloors table - array of floor numbers player owns, e.g. {1} or {1,2}
-- @param excludeFolder string|nil - optional, e.g. "DefensePoints" so income creatures never spawn on defense points
-- @return array of {part, index} sorted by index
local function getPointsForOwnedFloors(plotModel, prefix, ownedFloors, excludeFolder)
	local ownedSet = {}
	for _, f in ipairs(ownedFloors) do ownedSet[f] = true end

	local points = {}
	local skippedFloor = 0
	local skippedNoFloor = 0
	local skippedExclude = 0
	for _, child in ipairs(plotModel:GetDescendants()) do
		if child:IsA("BasePart") then
			local num = child.Name:match("^" .. prefix .. "(%d+)$")
			if num then
				if excludeFolder and isPartInFolderNamed(child, excludeFolder) then
					skippedExclude = skippedExclude + 1
				else
					local floor = getFloorForPart(child)
					if not floor then
						skippedNoFloor = skippedNoFloor + 1
						-- DEBUG: Print full path of any point not inside a FloorX folder
						warn("[BasePlacement] " .. prefix .. num .. " has NO FloorX ancestor! Path: " .. child:GetFullName())
					elseif not ownedSet[floor] then
						skippedFloor = skippedFloor + 1
					else
						table.insert(points, { part = child, index = tonumber(num) })
					end
				end
			end
		end
	end
	table.sort(points, function(a, b) return a.index < b.index end)
	return points
end

-- -- SPAWN CREATURE ORB --

-- Get the lowest Y of any part in the model (more accurate than GetBoundingBox for rigged/Meshy AI skeletons)
local function getModelBottomY(creatureModel)
	local minY = math.huge
	for _, desc in ipairs(creatureModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			local bottom = desc.Position.Y - desc.Size.Y * 0.5
			if bottom < minY then minY = bottom end
		end
	end
	return minY == math.huge and nil or minY
end

local function spawnBaseOrb(creatureId, pointPart, uid, plotModel, slotType, slotLabel, creatureLevel, ownerUserId, isEgg, hatchAt, pointIndex, slotIndex, creatureVariant, creatureNickname, eggInspected)
	isEgg = isEgg == true
	eggInspected = eggInspected == true
	creatureVariant = creatureVariant or "Normal"
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local rarityInfo = CreatureData.Rarities[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(180, 180, 180)

	local isDefense = (slotType == "defense")
	local isBattle = (slotType == "battle")
	local tag = isDefense and DEFENSE_TAG or (isBattle and BATTLE_TAG or INCOME_TAG)

	local model = Instance.new("Model")
	model.Name = slotType .. "_" .. info.id .. "_" .. uid
	model:SetAttribute("UID", uid)
	model:SetAttribute("CreatureId", creatureId)
	model:SetAttribute("IsEgg", isEgg)
	model:SetAttribute("EggInspected", eggInspected)
	model:SetAttribute("Nickname", creatureNickname or "")
	model:SetAttribute("SlotType", slotType)
	model:SetAttribute("CreatureLevel", creatureLevel or 1)
	model:SetAttribute("CreatureVariant", creatureVariant)
	if ownerUserId then model:SetAttribute("OwnerUserId", ownerUserId) end
	if slotIndex then model:SetAttribute("SlotIndex", slotIndex) end
	CollectionService:AddTag(model, tag)

	-- Body size varies by type (used for placeholder orb or for scaling)
	-- TEST: Set to true to use uniform scale for income/defense (no slot-based size difference)
	local UNIFORM_CREATURE_SCALE = true
	local bodySize
	if UNIFORM_CREATURE_SCALE then
		bodySize = Vector3.new(4.5, 4.5, 4.5)
	else
		if isDefense then bodySize = Vector3.new(5, 5, 5)
		elseif isBattle then bodySize = Vector3.new(4.5, 4.5, 4.5)
		else bodySize = Vector3.new(4, 4, 4)
		end
	end

	-- Position on top of the point part (avoids clipping through Floor 2/3)
	-- Per-creature Y offset (modelPlacementYOffset) for models whose limbs extend below base (defense, income, battle)
	local placementYOffset = (slotType == "defense" or slotType == "income" or slotType == "battle") and CreatureData.GetModelPlacementYOffset(info) or 0
	local placementOffset = (slotType == "defense" or slotType == "income" or slotType == "battle") and CreatureData.GetModelPlacementOffset(info) or Vector3.zero
	local pointPartTopY = pointPart.Position.Y + (pointPart.Size.Y * 0.5)
	local spawnPos = Vector3.new(
		pointPart.Position.X + placementOffset.X,
		pointPartTopY + (bodySize.Y * 0.5) + placementYOffset + placementOffset.Y,
		pointPart.Position.Z + placementOffset.Z
	)
	local body, core

	-- CreatureModelLoader: prefers Model type, then legacy mesh. Scale/orient Model to match mesh.
	-- When a real 3D model loads, we skip the Core sphere entirely — no orb auras on models.
	-- Only the rarity Highlight outline is kept for visual polish.
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local hasCustomModel = false -- tracks whether a real model loaded (vs placeholder orb)

	-- Eggs: load dedicated EggModel from ReplicatedStorage.CreatureModels instead of creature model.
	-- Tinted by rarity color (uninspected = tan/beige highlight, inspected = rarity color).
	if isEgg then
		local options = { targetSize = bodySize.X }
		body, core = CreatureModelLoader.LoadAndIntegrate(model, "Egg", "Egg", spawnPos, options)
		if body then
			hasCustomModel = true
			-- Remove Core sphere — egg model is the visual, no orb overlay
			core = core or model:FindFirstChild("Core")
			if core and core.Parent then
				core:Destroy()
			end
			core = nil
		end
	elseif info.modelName then
		local options = { targetSize = bodySize.X, creatureId = creatureId }
		body, core = CreatureModelLoader.LoadAndIntegrate(model, info.modelName, info.displayName, spawnPos, options)
		if body then
			hasCustomModel = true
			-- BasePlot additive rotation: Group A (1,2)=0°, B (5,6)=+180°Y, C (3,4)=-90°Y, D (7,8)=+90°Yes
			local basePlotId = tonumber(plotModel.Name:match("%d+")) or 1
			local baseRotation = CFrame.identity
			if basePlotId == 7 or basePlotId == 8 then
				baseRotation = CFrame.Angles(0, math.rad(90), 0)
			elseif basePlotId == 5 or basePlotId == 6 then
				baseRotation = CFrame.Angles(0, math.rad(180), 0)
			elseif basePlotId == 3 or basePlotId == 4 then
				baseRotation = CFrame.Angles(0, math.rad(-90), 0)
			end
			-- FIX #18: Income AND Battle monsters share the same rotation pipeline.
			-- Step 1: rotate body part -90° Y BEFORE any model-level rotation.
			-- Previously battle skipped this step and tried to compensate with an extra
			-- -90° Y in the PivotTo (Step 3), but rotsating body.CFrame before model offsets
			-- produces a different result than applying it via PivotTdo after — causing
			-- creatures like Draco to face the wrong direction on battle points.123
			if slotType == "income" or slotType == "battle" then
				body.CFrame = CFrame.new(body.Position) * CFrame.Angles(0, math.rad(-90), 0)
			end
			-- Step 2: Apply creature model rotation (crawling, modelStandUpAngles, modelRotationY)
			local rotOffset = CreatureData.GetModelRotationOffset(info)
			if rotOffset ~= CFrame.identity then
				model:PivotTo(model:GetPivot() * rotOffset)
			end
			-- Step 3: Apply BasePlot additive rotation. Income and battle both face inward;h
			-- battle slots are perpendicular to income, so apply an extra 90° Y for battle.g
			if slotType == "income" then
				model:PivotTo(model:GetPivot() * baseRotation)
			elseif slotType == "battle" then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(-90), 0) * baseRotation)
			end
			-- Floor 1 defense points: pointIndex rotation * baseRotation (additive)
			if isDefense and pointIndex and pointIndex >= 4 and pointIndex <= 6 then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(0), 0) * baseRotation)
			end
			if isDefense and pointIndex and pointIndex >= 0 and pointIndex <= 3 then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(-180), 0) * baseRotation)
			end
			if isDefense and pointIndex and pointIndex >= 8 and pointIndex <= 10 then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(90), 0) * baseRotation)
			end
			if isDefense and pointIndex and (pointIndex == 8 or pointIndex == 17 or pointIndex == 18) then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(90), 0) * baseRotation)
			end
			-- FIX: No Core sphere for custom models. If LoadAndIntegrate resturned ac
			-- core, or the model already has one from the asset, remove it.as
			-- Custom models show the 3D creature — no orb/sphere overlay needed.z
			core = core or model:FindFirstChild("Core")
			if core and core.Parent then
				core:Destroy()
			end
			core = nil
		end
	end

	if not body or not body.Parent then
		-- Fallback: placeholder orb if custom model failed or had no Body
		body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = bodySize
		body.Color = (isEgg and not eggInspected) and Color3.fromRGB(235, 225, 180) or info.primaryColor
		body.Material = Enum.Material.Neon
		body.Anchored = true
		body.CanCollide = true
		body.CastShadow = true
		body.Position = spawnPos
		body.Parent = model
		core = model:FindFirstChild("Core")
		if not core then
			core = Instance.new("Part")
			core.Name = "Core"
			core.Shape = Enum.PartType.Ball
			core.Size = bodySize * 0.5
			core.Color = rarityColor
			core.Material = Enum.Material.Neon
			core.Transparency = 0.3
			core.Anchored = true
			core.CanCollide = false
			core.CastShadow = false
			core.Position = spawnPos
			core.Parent = model
		end
	end

	local light = Instance.new("PointLight")
	light.Color = rarityColor
	light.Brightness = info.rarity == "Legendary" and 4 or (info.rarity == "Epic" and 3 or 2)
	light.Range = info.rarity == "Legendary" and 20 or 12
	light.Parent = body

	local highlight = Instance.new("Highlight")
	highlight.OutlineColor = rarityColor
	highlight.OutlineTransparency = 0.2
	if hasCustomModel then
		-- Custom 3D model: outline only, no color fill wash over the model
		highlight.FillTransparency = 1
	else
		-- Placeholder orb: slight rarity color fill to tint the orb
		highlight.FillColor = rarityColor
		highlight.FillTransparency = 0.75
	end
	highlight.Parent = model

	-- Name tag (offset to top of bounding box so name isn't blocked)
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = body
	billboard.Size = UDim2.new(0, 160, 0, 50)
	billboard.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = GameConfig.BaseBillboardMaxDistance or 80
	billboard.Parent = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	if isEgg and not eggInspected then
		nameLabel.Text = "Unknown Egg"
	else
		nameLabel.Text = (type(creatureNickname) == "string" and creatureNickname ~= "")
			and (creatureNickname .. " (" .. info.displayName .. ")")
			or info.displayName
	end
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = billboard

	-- Type label
	local typeColor, typeText
	if isEgg then
		local remaining = (hatchAt or 0) - (os.time() or 0)
		local mins = math.max(0, math.floor(remaining / 60))
		typeColor = Color3.fromRGB(255, 200, 80)
		local prefix = eggInspected and ("EGG | " .. info.rarity) or "EGG | ???"
		typeText = prefix .. " | " .. (mins > 0 and (mins .. "m to hatch") or "Hatching...")
	elseif isDefense then
		typeColor = Color3.fromRGB(220, 60, 70)
		typeText = "DEFENSE | " .. info.rarity
	elseif isBattle then
		typeColor = Color3.fromRGB(130, 100, 255)
		typeText = "BATTLE [" .. (slotLabel or "?") .. "] | " .. info.rarity
	else
		typeColor = Color3.fromRGB(50, 220, 120)
		typeText = "INCOME | " .. info.rarity
	end

	local typeLabel = Instance.new("TextLabel")
	typeLabel.Size = UDim2.new(1, 0, 0.35, 0)
	typeLabel.Position = UDim2.new(0, 0, 0.55, 0)
	typeLabel.BackgroundTransparency = 1
	typeLabel.Text = typeText
	typeLabel.TextColor3 = typeColor
	typeLabel.TextScaled = true
	typeLabel.Font = Enum.Font.GothamMedium
	typeLabel.Parent = billboard

	-- Ground ring
	local ringColor
	if isEgg then ringColor = Color3.fromRGB(255, 200, 80)
	elseif isDefense then ringColor = Color3.fromRGB(220, 60, 70)
	elseif isBattle then ringColor = Color3.fromRGB(130, 100, 255)
	else ringColor = Color3.fromRGB(50, 220, 120)
	end

	local ringSize = isDefense and 7 or (isBattle and 6.5 or 5.5)
	local ring = Instance.new("Part")
	ring.Name = "BaseRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, ringSize, ringSize)
	ring.Color = ringColor
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.6
	ring.Anchored = true
	ring.CanCollide = false
	ring.CastShadow = false
	ring.CFrame = CFrame.new(pointPart.Position.X, pointPartTopY + 0.2, pointPart.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model

	-- HP bar (between type label and ground ring area)
	local hpBg = Instance.new("Frame")
	hpBg.Name = "HPBar"; hpBg.Size = UDim2.new(0.8, 0, 0, 5)
	hpBg.Position = UDim2.new(0.1, 0, 0, 46); hpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBg.BorderSizePixel = 0; hpBg.Parent = billboard
	Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0, 3)

	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"; hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(80, 255, 120); hpFill.BorderSizePixel = 0; hpFill.Parent = hpBg
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 3)

	-- Expand billboard to fit HP bar
	billboard.Size = UDim2.new(0, 160, 0, 55)

	model.PrimaryPart = body
	model.Parent = plotModel
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false -- FIX #20: placed creatures should not block players/companions
			if part.Name == "Body" or part.Name == "HitBox" then
				part.CanQuery = true -- FIX #20: keep Body/HitBox targetable by raycasts
			else
				part.CanQuery = false -- FIX #20: reduce raycast noise from decorative parts
			end
		end
	end

	-- Place custom models so bottom sits on point top (avoids clipping on Floor 2/3)
	-- Meshy AI / rigged: GetBoundingBox can miss mesh extent; use part-based bottom (lowest part bottom)
	-- Manual fix: modelPlacementYOffset in CreatureData lifts creatures whose limbs extend below base
	local MAX_PLACEMENT_LIFT = 12  -- studs; prevents extreme floating
	if body and not isEgg and info.modelName then
		local partBottom = getModelBottomY(model)
		local bboxBottom = nil
		if model.GetBoundingBox then
			local ok, bboxCf, bboxSize = pcall(function() return model:GetBoundingBox() end)
			if ok and bboxCf and bboxSize and bboxSize.Y > 0 and bboxSize.Y < 100 then
				bboxBottom = bboxCf.Position.Y - (bboxSize.Y * 0.5)
			end
		end
		-- Use the LOWER Y (true model bottom) so we lift enough; Meshy/rigged often extend below bbox
		local modelBottomY = math.min(partBottom or math.huge, bboxBottom or math.huge)
		if modelBottomY and modelBottomY < math.huge then
			local lift = math.max(0, pointPartTopY - modelBottomY) + placementYOffset
			-- Rigged/Meshy AI: mesh extends beyond bbox; add floor buffer for Humanoid models
			local riggedBuffer = GameConfig and GameConfig.RiggedModelFloorBuffer or 2.5
			if model:FindFirstChildOfClass("Humanoid") and riggedBuffer > 0 then
				lift = lift + riggedBuffer
			end
			lift = math.min(lift, MAX_PLACEMENT_LIFT)
			if lift ~= 0 then
				model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
			end
		end
	end

	-- Default animation: Income on income points, Idle on defense/battle
	local defaultAnim = (slotType == "income" and not isEgg) and "Income" or "Idle"
	CreatureAnimation.Setup(model, creatureId, defaultAnim)

	-- Set owner attribute for steal system
	if ownerUserId then
		model:SetAttribute("OwnerUserId", ownerUserId)
	end

	-- Register with CreatureAI so base creatures are damageable / faintable (eggs are not registered)
	if not isEgg and CreatureAI and CreatureAI.RegisterCreature then
		CreatureAI.RegisterCreature(model, creatureId, body.Position, nil)
		local aiState = CreatureAI.GetState(model)
		if aiState and PlayerDataManager and PlayerDataManager.GetEffectiveStats then
			local lvl = creatureLevel or 1
			local ownerPlayer = ownerUserId and Players:GetPlayerByUserId(ownerUserId) or nil
			local stats = PlayerDataManager.GetEffectiveStats(creatureId, lvl, creatureVariant, ownerPlayer)
			local maxHp = stats and stats.health or math.floor(info.health * (1 + (GameConfig.StatGainPerLevel or 0.08) * (lvl - 1)))
			aiState.hp = maxHp
			aiState.maxHp = maxHp
			aiState.behavior = "stationary"
			aiState.state = "idle"
		elseif aiState then
			local lvl = creatureLevel or 1
			local lvlMult = 1 + GameConfig.StatGainPerLevel * (lvl - 1)
			aiState.hp = math.floor(info.health * lvlMult)
			aiState.maxHp = aiState.hp
			aiState.behavior = "stationary"
			aiState.state = "idle"
		end
	end

	-- HP bar updater — reads from CreatureAI
	task.spawn(function()
		while model.Parent and body.Parent do
			task.wait(0.5)
			if CreatureAI and CreatureAI.GetHP then
				local hp, maxHp = CreatureAI.GetHP(model)
				if maxHp and maxHp > 0 then
					local ratio = math.clamp(hp / maxHp, 0, 1)
					local fill = hpBg:FindFirstChild("Fill")
					if fill then
						fill.Size = UDim2.new(ratio, 0, 1, 0)
						if ratio > 0.5 then fill.BackgroundColor3 = Color3.fromRGB(80, 255, 120)
						elseif ratio > 0.25 then fill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
						else fill.BackgroundColor3 = Color3.fromRGB(255, 60, 40) end
					end
				end
			end
		end
	end)

	-- Hover animation (bob up and down)
	-- For custom models: only bobs the body, no core pulse.
	-- For placeholder orbs: bobs both body and core with transparency pulse.
	task.spawn(function()
		local startY = body.Position.Y
		local coreStartY = core and core.Parent and core.Position.Y or nil
		local t = math.random() * math.pi * 2
		local bobSpeed = isDefense and 1.5 or (isBattle and 1.8 or 1.2)
		local bobHeight = isDefense and 0.8 or (isBattle and 0.6 or 0.5)

		while model.Parent and body.Parent do
			local dt = RunService.Heartbeat:Wait()
			t = t + dt * bobSpeed * math.pi * 2
			local bob = math.sin(t) * bobHeight
			body.Position = Vector3.new(body.Position.X, startY + bob, body.Position.Z)
			if core and core.Parent and coreStartY then
				core.Position = Vector3.new(core.Position.X, coreStartY + bob, core.Position.Z)
				core.Transparency = 0.3 + math.sin(t * 2) * 0.15
			end
		end
	end)

	return model
end

-- -- FLOOR VISIBILITY --
-- Show/hide a floor's parts based on ownership.
-- Glass/window parts stay transparent and use Material.Glass when floor is visible.

local GLASS_TRANSPARENCY_VISIBLE = 0.35  -- 0 = opaque, 1 = invisible; ~0.3-0.5 = see-through glass

local function isGlassPart(part)
	if part:GetAttribute("IsGlass") then return true end
	local nameLower = part.Name:lower()
	if nameLower:find("glass") then return true end
	if nameLower:find("window") then return true end
	if nameLower:find("pane") then return true end
	if nameLower:find("panel") and not nameLower:find("defense") and not nameLower:find("income") and not nameLower:find("battle") then return true end
	return false
end

local function setFloorVisibility(plotModel, floorNum, visible)
	local floorFolder = resolveFloorFolder(plotModel, floorNum)
	if not floorFolder then
		warn("[BasePlacement] Floor" .. floorNum .. " folder not found in " .. plotModel.Name .. " (expected Floor2, Floor 2, Floor02, etc.)")
		return
	end
	local partCount = 0
	local defCount = 0
	local incCount = 0
	local btlCount = 0
	local glassCount = 0
	for _, desc in ipairs(floorFolder:GetDescendants()) do
		if desc:IsA("SelectionBox") then
			-- SelectionBoxes in TeleportParts (ElectricTele, CaveTele, etc.) use Visible.
			-- Sync with floor visibility to avoid phantom wireframes when floor is hidden.
			desc.Visible = visible
		elseif desc:IsA("BasePart") then
			-- FIX #12: ALWAYS anchor parts BEFORE changing CanCollide.
			-- If a part is unanchored and we set CanCollide=false, it falls through
			-- the world and gets destroyed by FallenPartsDestroyHeight.
			-- This was killing DefensePoint and BattlePoint parts on Floor2 while
			-- IncomePoints survived (they happened to be anchored already).
			desc.Anchored = true
			-- Glass panels: keep transparent when floor is visible (Floor 2/3); when hidden, full invisible.
			local isSafetyGlassWall = isGlassBattlePointSafetyWall(desc)
			local isGlass = isGlassPart(desc) or isSafetyGlassWall
			if isGlass then glassCount = glassCount + 1 end
			if visible then
				if isSafetyGlassWall then
					desc.Transparency = 1
					desc.Material = Enum.Material.Glass
				elseif isGlassPart(desc) then
					local custom = desc:GetAttribute("GlassTransparency")
					local transparency = (type(custom) == "number" and math.clamp(custom, 0, 1)) or GLASS_TRANSPARENCY_VISIBLE
					desc.Transparency = transparency
					desc.Material = Enum.Material.Glass  -- so Roblox renders actual transparent glass
				else
					desc.Transparency = 0
				end
			else
				desc.Transparency = 1
			end
			desc.CanCollide = visible
			partCount = partCount + 1
			-- Track what types of points we're toggling
			if desc.Name:match("^DefensePoint") then defCount = defCount + 1 end
			if desc.Name:match("^IncomePoint") then incCount = incCount + 1 end
			if desc.Name:match("^BattlePoint") then btlCount = btlCount + 1 end
		end
	end
	print("[BasePlacement] setFloorVisibility: " .. plotModel.Name .. " Floor" .. floorNum
		.. " visible=" .. tostring(visible) .. " | " .. partCount .. " parts total"
		.. " (inc=" .. incCount .. " def=" .. defCount .. " btl=" .. btlCount .. " glass=" .. glassCount .. ")")
end

local function setFloor2RoofState(plotModel, floor2Owned)
	local floor1 = resolveFloorFolder(plotModel, 1)
	if not floor1 then return end
	local roofNode = floor1:FindFirstChild("NewPlotFloor2", true)
	if not roofNode then return end

	local parts = {}
	if roofNode:IsA("BasePart") then
		table.insert(parts, roofNode)
	else
		for _, desc in ipairs(roofNode:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(parts, desc)
			end
		end
	end

	for _, part in ipairs(parts) do
		part.Anchored = true
		if floor2Owned then
			part.Transparency = 1
			part.CanCollide = false
			part.CanTouch = false
		else
			part.Transparency = 0
			part.CanCollide = true
			part.CanTouch = true
		end
	end
end

-- normalizedOwnedFloors: output of normalizeOwnedFloorsForPlacement (sorted array including 1)
local function applyOwnedFloorsVisibility(plotModel, normalizedOwnedFloors)
	local function ownsFloor(n)
		for _, f in ipairs(normalizedOwnedFloors) do
			if f == n then return true end
		end
		return false
	end
	for _, floorNum in ipairs({ 1, 2, 3, 4 }) do
		setFloorVisibility(plotModel, floorNum, ownsFloor(floorNum))
	end
	setFloor2RoofState(plotModel, ownsFloor(2))
end

-- Declared AFTER normalizeOwnedFloorsForPlacement + applyOwnedFloorsVisibility so locals resolve (Lua: no forward local refs).
function BasePlacementSystem.RefreshAllPlotVisibility()
	if not PLOTS_FOLDER or not PlayerDataManager or not PlayerDataManager.GetClaimedPlotIds then return end
	local claimed = PlayerDataManager.GetClaimedPlotIds()
	for _, plot in ipairs(PLOTS_FOLDER:GetChildren()) do
		local plotId = plot.Name:match("^Plot(%d+)$") or plot.Name:match("^Part(%d+)$")
		if plotId then
			local id = tonumber(plotId)
			setPlotInhabited(plot, claimed[id] == true)
		end
	end
	if PlayerDataManager.GetUserIdForPlot then
		for _, plot in ipairs(PLOTS_FOLDER:GetChildren()) do
			local plotId = plot.Name:match("^Plot(%d+)$") or plot.Name:match("^Part(%d+)$")
			if plotId then
				local id = tonumber(plotId)
				if claimed[id] then
					local userId = PlayerDataManager.GetUserIdForPlot(id)
					local owner = userId and Players:GetPlayerByUserId(userId)
					local data = owner and PlayerDataManager.GetData(owner)
					if data then
						local normalized = normalizeOwnedFloorsForPlacement(data.ownedFloors)
						applyOwnedFloorsVisibility(plot, normalized)
					end
				end
			end
		end
	end
end

-- FIX #11: setBattleTeamVisibility REMOVED. BattleTeam is now INSIDE Floor2.
-- setFloorVisibility handles ALL descendants of FloorX including BattleTeam.
-- There is NO separate visibility function. Everything in FloorX toggles together.

-- -- CLEAR + PLACE --
-- Only removes creature orb Models (Defense/Income/Battle tags). Never modifies point parts or floor structure.

local function clearTaggedCreatures(plotModel, tag)
	for _, child in ipairs(plotModel:GetDescendants()) do
		if child:IsA("Model") and CollectionService:HasTag(child, tag) then
			if CreatureAI and CreatureAI.UnregisterCreature then
				CreatureAI.UnregisterCreature(child)
			end
			child:Destroy()
		end
	end
end

-- Clear a single creature at slot (defense/income). Does not touch other slots.
local function clearCreatureAtSlot(plotModel, tag, slotIndex)
	local toDestroy = {}
	for _, child in ipairs(plotModel:GetDescendants()) do
		if child:IsA("Model") and CollectionService:HasTag(child, tag) then
			if child:GetAttribute("SlotIndex") == slotIndex then
				table.insert(toDestroy, child)
			end
		end
	end
	for _, child in ipairs(toDestroy) do
		if child.Parent then
			if CreatureAI and CreatureAI.UnregisterCreature then
				CreatureAI.UnregisterCreature(child)
			end
			child:Destroy()
		end
	end
end

-- Place one creature at slot (incremental - no full refresh). Clears any existing model at that slot first.
function BasePlacementSystem.PlaceCreatureInSlot(player, slotType, slotIndex, uid)
	if runWhenPlacementIdle(player, function()
		BasePlacementSystem.PlaceCreatureInSlot(player, slotType, slotIndex, uid)
	end) then
		placementLog("PlaceCreatureInSlot deferred: full placement in progress", player and player.Name, slotType, slotIndex, uid)
		return nil
	end
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then
		placementLog("PlaceCreatureInSlot nil: no data or plotId", player and player.Name, slotType, slotIndex, uid)
		return nil
	end
	local plotModel = findPlotModel(data.plotId)
	if not plotModel then
		placementLog("PlaceCreatureInSlot nil: no plotModel", data.plotId, player and player.Name)
		return nil
	end

	-- Only place if this slot still has this uid in current data (prevents deferred place from re-adding after Rem).sd
	local su = tostring(uid or "")
	if slotType == "income" then
		local slotUid = data.baseSlots and data.baseSlots[slotIndex]
		if not slotUid or tostring(slotUid) ~= su then
			placementLog("PlaceCreatureInSlot skip: uid no longer in income slot", slotIndex, player and player.Name, su)
			return nil
		end
	elseif slotType == "defense" then
		local slotUid = data.defenseSlots and data.defenseSlots[slotIndex]
		if not slotUid or tostring(slotUid) ~= su then
			placementLog("PlaceCreatureInSlot skip: uid no longer in defense slot", slotIndex, player and player.Name, su)
			return nil
		end
	elseif slotType == "battle" then
		local slotUid = data.battleTeam and data.battleTeam[slotIndex]
		if not slotUid or tostring(slotUid) ~= su then
			placementLog("PlaceCreatureInSlot skip: uid no longer in battle slot", slotIndex, player and player.Name, su)
			return nil
		end
	end

	local tag = (slotType == "defense") and DEFENSE_TAG or INCOME_TAG
	clearCreatureAtSlot(plotModel, tag, slotIndex)

	local ownedFloors = normalizeOwnedFloorsForPlacement(data.ownedFloors)
	local points
	if slotType == "defense" then
		points = getPointsForOwnedFloors(plotModel, "DefensePoint", ownedFloors, "IncomePoints")
		if #points == 0 then
			local raw = getPointsByPrefix(plotModel, "DefensePoint")
			points = {}
			for _, p in ipairs(raw) do
				if not isPartInFolderNamed(p.part, "IncomePoints") then table.insert(points, p) end
			end
		end
	else
		points = getPointsForOwnedFloors(plotModel, "IncomePoint", ownedFloors, "DefensePoints")
		if #points == 0 then
			local raw = getPointsByPrefix(plotModel, "IncomePoint")
			points = {}
			for _, p in ipairs(raw) do
				if not isPartInFolderNamed(p.part, "DefensePoints") then table.insert(points, p) end
			end
		end
	end
	if not points or #points == 0 or type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > #points then
		placementLog("PlaceCreatureInSlot nil: slotIndex out of range", "slotIndex=" .. tostring(slotIndex), "#points=" .. (points and #points or 0), player and player.Name)
		return nil
	end
	local pt = points[slotIndex]
	if not pt then
		placementLog("PlaceCreatureInSlot nil: points[slotIndex] nil", slotIndex, player and player.Name)
		return nil
	end

	local egg = PlayerDataManager.GetEggByUid(player, uid)
	if egg then
		local hatchAt = egg.createdAt + egg.hatchMinutes * 60
		if (os.time() or 0) < hatchAt then
			return spawnBaseOrb(egg.creatureId, pt.part, uid, plotModel, slotType, nil, egg.level, player.UserId, true, hatchAt, pt.index, slotIndex, "Normal", nil, egg.inspected == true)
		end
	end
	for _, entry in ipairs(data.inventory) do
		if entry.uid and tostring(entry.uid) == tostring(uid) then
			return spawnBaseOrb(entry.id, pt.part, uid, plotModel, slotType, nil, entry.level, player.UserId, nil, nil, pt.index, slotIndex, entry.variant, entry.nickname)
		end
	end
	placementLog("PlaceCreatureInSlot nil: uid not in inventory or eggs", tostring(uid), player and player.Name, slotType, slotIndex)
	return nil
end

-- Clear one slot (creature died). Removes model and marks slot available.
function BasePlacementSystem.ClearCreatureAtSlot(player, slotType, slotIndex)
	PlayerDataManager.ClearSlotAt(player, slotType, slotIndex)
	if runWhenPlacementIdle(player, function()
		BasePlacementSystem.ClearCreatureAtSlot(player, slotType, slotIndex)
	end) then
		return
	end
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return end
	local plotModel = findPlotModel(data.plotId)
	if plotModel then
		local tag = (slotType == "defense") and DEFENSE_TAG or INCOME_TAG
		clearCreatureAtSlot(plotModel, tag, slotIndex)
	end
end

-- Refresh the orb model at a slot (defense/income/battle) when creature evolves. Replaces old model with new evolved form.
-- Call after PlayerDataManager.EvolveCreature succeeds and inventory entry.id has been updated.
function BasePlacementSystem.RefreshOrbByUid(player, uid)
	if not uid or uid == "" then return end
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return end
	local plotModel = findPlotModel(data.plotId)
	if not plotModel then return end

	-- Defense slots
	if data.defenseSlots then
		for slotIndex, slotUid in ipairs(data.defenseSlots) do
			if slotUid and tostring(slotUid) == tostring(uid) then
				BasePlacementSystem.PlaceCreatureInSlot(player, "defense", slotIndex, uid)
				return
			end
		end
	end

	-- Income slots (baseSlots)
	if data.baseSlots then
		for slotIndex, slotUid in ipairs(data.baseSlots) do
			if slotUid and tostring(slotUid) == tostring(uid) then
				BasePlacementSystem.PlaceCreatureInSlot(player, "income", slotIndex, uid)
				return
			end
		end
	end

	-- Battle team
	if data.battleTeam then
		for slotIndex, slotUid in pairs(data.battleTeam) do
			if slotUid == uid then
				local battlePointMap = getBattlePointMap(plotModel)
				local pointPart = battlePointMap[tonumber(slotIndex) or slotIndex]
				if pointPart then
					-- Clear old model
					for _, child in ipairs(plotModel:GetDescendants()) do
						if child:IsA("Model") and CollectionService:HasTag(child, BATTLE_TAG) and child:GetAttribute("UID") == uid then
							if CreatureAI and CreatureAI.UnregisterCreature then
								CreatureAI.UnregisterCreature(child)
							end
							child:Destroy()
							break
						end
					end
					-- Spawn new model with evolved form
					for _, entry in ipairs(data.inventory) do
						if entry.uid and tostring(entry.uid) == tostring(uid) then
							spawnBaseOrb(entry.id, pointPart, uid, plotModel, "battle", tostring(slotIndex), entry.level, player.UserId, nil, nil, nil, slotIndex, entry.variant, entry.nickname)
							break
						end
					end
				end
				return
			end
		end
	end
end

-- Remove all orbs with this UID from the plot (defense/income/battle). Collect first then destroy so iteration is safe.
-- When immediate is true (e.g. Rem button), clear synchronously so a concurrent PlaceCreatures doesn't re-place from stale state.
function BasePlacementSystem.ClearOrbByUid(player, uid, immediate)
	if not uid or uid == "" then return end
	if not immediate and runWhenPlacementIdle(player, function()
		BasePlacementSystem.ClearOrbByUid(player, uid)
	end) then
		return
	end
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return end
	local plotModel = findPlotModel(data.plotId)
	if not plotModel then return end
	local tags = { DEFENSE_TAG, INCOME_TAG, BATTLE_TAG }
	local su = tostring(uid or "")
	local toDestroy = {}
	for _, tag in ipairs(tags) do
		for _, child in ipairs(plotModel:GetDescendants()) do
			if child:IsA("Model") and CollectionService:HasTag(child, tag) then
				if child:GetAttribute("UID") and tostring(child:GetAttribute("UID")) == su then
					table.insert(toDestroy, child)
				end
			end
		end
	end
	for _, child in ipairs(toDestroy) do
		if child.Parent then
			if CreatureAI and CreatureAI.UnregisterCreature then
				CreatureAI.UnregisterCreature(child)
			end
			child:Destroy()
		end
	end
end

--- Map a point number (e.g. 7 from "IncomePoint7") to its slot array index.
-- The slot index is the position of that point in the sorted owned-floors points array.
-- @param player Player
-- @param slotType string "income" or "defense"
-- @param pointIndex number the numeric suffix from the point name (e.g. 7)
-- @return slotIndex number|nil the array index in baseSlots/defenseSlots, or nil if not found
function BasePlacementSystem.GetSlotIndexForPoint(player, slotType, pointIndex)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then
		placementLog("GetSlotIndexForPoint nil: no data or plotId", player and player.Name, slotType, pointIndex)
		return nil
	end
	local plotModel = findPlotModel(data.plotId)
	if not plotModel then
		placementLog("GetSlotIndexForPoint nil: no plotModel for plotId", data.plotId, player and player.Name)
		return nil
	end
	local ownedFloors = normalizeOwnedFloorsForPlacement(data.ownedFloors)
	local points
	if slotType == "defense" then
		points = getPointsForOwnedFloors(plotModel, "DefensePoint", ownedFloors, "IncomePoints")
		if #points == 0 then
			local raw = getPointsByPrefix(plotModel, "DefensePoint")
			points = {}
			for _, p in ipairs(raw) do
				if not isPartInFolderNamed(p.part, "IncomePoints") then table.insert(points, p) end
			end
		end
	else
		points = getPointsForOwnedFloors(plotModel, "IncomePoint", ownedFloors, "DefensePoints")
		if #points == 0 then
			local raw = getPointsByPrefix(plotModel, "IncomePoint")
			points = {}
			for _, p in ipairs(raw) do
				if not isPartInFolderNamed(p.part, "DefensePoints") then table.insert(points, p) end
			end
		end
	end
	local maxSlots = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(player, slotType) or #points
	for arrayPos, entry in ipairs(points) do
		if entry.index == pointIndex then
			if arrayPos > maxSlots then
				placementLog("GetSlotIndexForPoint nil: arrayPos " .. arrayPos .. " > maxSlots " .. maxSlots, player and player.Name, slotType, pointIndex)
				return nil
			end
			return arrayPos
		end
	end
	placementLog("GetSlotIndexForPoint nil: no point with index=" .. tostring(pointIndex), "points count=" .. #points, player and player.Name, slotType)
	return nil
end

-- Remove defense/income/battle base creatures tagged with this OwnerUserId anywhere in Workspace
-- (orphans or stale plot after random re-assign). Safe before PlaceCreatures on the new plot.
function BasePlacementSystem.DestroyTaggedCreaturesForOwnerUserId(ownerUserId)
	destroyTaggedBaseCreaturesForOwnerUserId(ownerUserId)
end

function BasePlacementSystem.PlaceCreatures(player)
	local userId = player.UserId
	-- Prevent concurrent placement calls from racing
	if placementLocks[userId] then return end
	placementLocks[userId] = true

	local data = PlayerDataManager.GetData(player)
	if not data then placementLocks[userId] = nil; return end

	local plotId = data.plotId
	if not plotId or plotId == 0 then placementLocks[userId] = nil; return end

	local plotModel = findPlotModel(plotId)
	if not plotModel then
		warn("[BasePlacement] Plot " .. plotId .. " not found for " .. player.Name)
		placementLocks[userId] = nil
		return
	end

	-- Set floor visibility based on owned floors
	local ownedFloors = normalizeOwnedFloorsForPlacement(data.ownedFloors)
	data.ownedFloors = ownedFloors
	applyOwnedFloorsVisibility(plotModel, ownedFloors)
	local ownsBattle = false
	for _, f in ipairs(ownedFloors) do
		if f == 2 then ownsBattle = true break end
	end

	-- Apply equipped base exterior theme (colors + shell) so base cosmetic always shows
	-- Wrapped in pcall so exterior bugs don't block creature placement
	do
		local ok, err = pcall(function()
			local BES = require(game:GetService("ServerScriptService"):FindFirstChild("BaseExteriorSystem") or game:GetService("ServerScriptService"):WaitForChild("BaseExteriorSystem", 3))
			if BES then
				local ext = data.exterior
				local equippedExt = ext and ext.equipped
				-- Default: grass foundations + grey trim when no exterior theme is equipped.
				local themeToApply = (equippedExt and equippedExt ~= "") and equippedExt or nil
				if BES.ApplyThemeToPlot then BES.ApplyThemeToPlot(plotModel, themeToApply) end
				local bc = data.baseColor
				local equippedColor = bc and bc.equipped
				if BES.ApplyBaseColorToPlot then
					BES.ApplyBaseColorToPlot(plotModel, (equippedColor and equippedColor ~= "") and equippedColor or nil)
				end
			end
		end)
		if not ok then
			warn("[BasePlacement] BaseExteriorSystem.ApplyTheme failed:", tostring(err))
		end
	end

	-- Clear all existing placed creatures
	clearTaggedCreatures(plotModel, DEFENSE_TAG)
	clearTaggedCreatures(plotModel, INCOME_TAG)
	clearTaggedCreatures(plotModel, BATTLE_TAG)

	-- -- Defense creatures --
	-- FIX #1/#3: Use getPointsForOwnedFloors to only place on OWNED floor points.
	-- Exclude IncomePoints folder so defense creatures never spawn on income points.
	-- Fallback: if no points found (e.g. plot has points outside Floor1/2/3 folders), use getPointsByPrefix so orbs still appear.
	local defensePoints = getPointsForOwnedFloors(plotModel, "DefensePoint", ownedFloors, "IncomePoints")
	if #defensePoints == 0 then
		local raw = getPointsByPrefix(plotModel, "DefensePoint")
		defensePoints = {}
		for _, p in ipairs(raw) do
			if not isPartInFolderNamed(p.part, "IncomePoints") then
				table.insert(defensePoints, p)
			end
		end
		local maxSlots = (GameConfig and GameConfig.MaxDefenseSlots) or (#ownedFloors * 6)
		while #defensePoints > maxSlots do table.remove(defensePoints) end
		if #defensePoints > 0 then
			print("[BasePlacement] Fallback: using getPointsByPrefix for DefensePoint on " .. plotModel.Name .. " (" .. #defensePoints .. " points)")
		end
	end
	local defPlaced = 0
	local maxDefSlots = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(player, "defense") or #defensePoints
	for i = 1, maxDefSlots do
		if i > #defensePoints then break end
		local uid = data.defenseSlots and data.defenseSlots[i]
		if not uid or uid == "" then continue end
		local egg = PlayerDataManager.GetEggByUid(player, uid)
		if egg then
			local hatchAt = egg.createdAt + egg.hatchMinutes * 60
			if (os.time() or 0) < hatchAt then
				spawnBaseOrb(egg.creatureId, defensePoints[i].part, uid, plotModel, "defense", nil, egg.level, player.UserId, true, hatchAt, defensePoints[i].index, i, "Normal", nil, egg.inspected == true)
				defPlaced = defPlaced + 1
			end
		else
			for _, entry in ipairs(data.inventory) do
				if entry.uid and tostring(entry.uid) == tostring(uid) then
					spawnBaseOrb(entry.id, defensePoints[i].part, uid, plotModel, "defense", nil, entry.level, player.UserId, nil, nil, defensePoints[i].index, i, entry.variant, entry.nickname)
					defPlaced = defPlaced + 1
					break
				end
			end
		end
	end

	-- -- Income creatures --
	-- FIX #1: Use getPointsForOwnedFloors for income points too.
	-- Exclude DefensePoints folder so income creatures never spawn on defense points.
	-- Fallback to getPointsByPrefix if none found.
	local incomePoints = getPointsForOwnedFloors(plotModel, "IncomePoint", ownedFloors, "DefensePoints")
	if #incomePoints == 0 then
		local raw = getPointsByPrefix(plotModel, "IncomePoint")
		incomePoints = {}
		for _, p in ipairs(raw) do
			if not isPartInFolderNamed(p.part, "DefensePoints") then
				table.insert(incomePoints, p)
			end
		end
		local maxSlots = (GameConfig and GameConfig.MaxIncomeSlots) or (#ownedFloors * 6)
		while #incomePoints > maxSlots do table.remove(incomePoints) end
		if #incomePoints > 0 then
			print("[BasePlacement] Fallback: using getPointsByPrefix for IncomePoint on " .. plotModel.Name .. " (" .. #incomePoints .. " points)")
		end
	end
	local incPlaced = 0
	local maxIncSlots = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(player, "income") or #incomePoints
	for i = 1, maxIncSlots do
		if i > #incomePoints then break end
		local uid = data.baseSlots and data.baseSlots[i]
		if not uid or uid == "" then continue end
		local egg = PlayerDataManager.GetEggByUid(player, uid)
		if egg then
			local hatchAt = egg.createdAt + egg.hatchMinutes * 60
			if (os.time() or 0) < hatchAt then
				spawnBaseOrb(egg.creatureId, incomePoints[i].part, uid, plotModel, "income", nil, egg.level, player.UserId, true, hatchAt, nil, i, "Normal", nil, egg.inspected == true)
				incPlaced = incPlaced + 1
			end
		else
			for _, entry in ipairs(data.inventory) do
				if entry.uid and tostring(entry.uid) == tostring(uid) then
					spawnBaseOrb(entry.id, incomePoints[i].part, uid, plotModel, "income", nil, entry.level, player.UserId, nil, nil, nil, i, entry.variant, entry.nickname)
					incPlaced = incPlaced + 1
					break
				end
			end
		end
	end

	-- -- Battle team creatures (always show on BattlePoints; skip if arena in progress or Floor 2 not owned) --
	local battlePointMap = getBattlePointMap(plotModel)
	local btlPlaced = 0
	local arenaBusy = workspace:GetAttribute("ArenaBattleInProgress")
	if data.battleTeam and not arenaBusy and ownsBattle then
		for slotIndex, uid in pairs(data.battleTeam) do
			local pointPart = battlePointMap[tonumber(slotIndex) or slotIndex]
			if pointPart and uid then
				for _, entry in ipairs(data.inventory) do
					if entry.uid and tostring(entry.uid) == tostring(uid) then
						spawnBaseOrb(entry.id, pointPart, uid, plotModel, "battle", tostring(slotIndex), entry.level, player.UserId, nil, nil, nil, slotIndex, entry.variant, entry.nickname)
						btlPlaced = btlPlaced + 1
						break
					end
				end
			end
		end
	end
	print("[BasePlacement] " .. player.Name .. ": " ..
		defPlaced .. " defense, " ..
		incPlaced .. " income, " ..
		btlPlaced .. " battle on " .. plotModel.Name)

	-- Set up MCombiner / MRecycler ProximityPrompts on this plot (only when Floor 3 is owned; parts live in Floor3 folder)
	do
		local ok, err = pcall(function()
			local SSS = game:GetService("ServerScriptService")
			local CombinerRecyclerSystem = require(SSS:FindFirstChild("CombinerRecyclerSystem") or SSS:WaitForChild("CombinerRecyclerSystem", 5))
			if CombinerRecyclerSystem and CombinerRecyclerSystem.SetupPlotPrompts then
				CombinerRecyclerSystem.SetupPlotPrompts(plotModel, ownedFloors)
			end
		end)
		if not ok then
			warn("[BasePlacement] CombinerRecycler SetupPlotPrompts failed:", tostring(err))
		end
	end

	placementLocks[userId] = nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ActivateFloor(player, floorNum)
-- Lightweight alternative to PlaceCreatures for floor purchases. Instead of
-- clearing and respawning ALL creatures on ALL floors, this only:
--   1. Makes the newly purchased floor visible (setFloorVisibility)
--   2. Places creatures on the NEW floor's income/defense points
--   3. Spawns battle orbs on Floor 2 BattlePoints (if buying Floor 2)
--   4. Sets up combiner/recycler prompts (if buying Floor 3)
--
-- Existing creatures on previously owned floors are NOT touched.
--
-- @param player   Player — the buyer
-- @param floorNum number — the floor just purchased (2, 3, or 4)
-- ═══════════════════════════════════════════════════════════════════════════════
function BasePlacementSystem.ActivateFloor(player, floorNum)
	local userId = player.UserId
	if placementLocks[userId] then return end
	placementLocks[userId] = true

	local data = PlayerDataManager.GetData(player)
	if not data then placementLocks[userId] = nil return end

	local plotId = data.plotId
	if not plotId or plotId == 0 then placementLocks[userId] = nil return end

	local plotModel = findPlotModel(plotId)
	if not plotModel then
		warn("[BasePlacement] ActivateFloor: Plot " .. plotId .. " not found for " .. player.Name)
		placementLocks[userId] = nil
		return
	end

	local ownedFloors = normalizeOwnedFloorsForPlacement(data.ownedFloors)

	-- ── Step 1: Make the new floor visible ──────────────────────────────────
	setFloorVisibility(plotModel, floorNum, true)
	setFloor2RoofState(plotModel, floorNum >= 2)

	-- ── Step 2: Place creatures only on the NEW floor's points ──────────────
	-- We pass a single-element ownedFloors table so getPointsForOwnedFloors
	-- only returns points that live inside the newly purchased FloorX folder.
	local newFloorOnly = { floorNum }

	-- Defense creatures on new floor
	local defensePoints = getPointsForOwnedFloors(plotModel, "DefensePoint", newFloorOnly, "IncomePoints")
	local defPlaced = 0
	local maxDefSlots = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(player, "defense") or (#ownedFloors * 6)
	for _, pt in ipairs(defensePoints) do
		local slotIdx = pt.index
		if slotIdx > maxDefSlots then continue end
		local uid = data.defenseSlots and data.defenseSlots[slotIdx]
		if not uid or uid == "" then continue end
		local egg = PlayerDataManager.GetEggByUid and PlayerDataManager.GetEggByUid(player, uid)
		if egg then
			local hatchAt = egg.createdAt + egg.hatchMinutes * 60
			if (os.time() or 0) < hatchAt then
				spawnBaseOrb(egg.creatureId, pt.part, uid, plotModel, "defense", nil, egg.level, player.UserId, true, hatchAt, pt.index, slotIdx, "Normal", nil, egg.inspected == true)
				defPlaced = defPlaced + 1
			end
		else
			for _, entry in ipairs(data.inventory) do
				if entry.uid and tostring(entry.uid) == tostring(uid) then
					spawnBaseOrb(entry.id, pt.part, uid, plotModel, "defense", nil, entry.level, player.UserId, nil, nil, pt.index, slotIdx, entry.variant, entry.nickname)
					defPlaced = defPlaced + 1
					break
				end
			end
		end
	end

	-- Income creatures on new floor
	local incomePoints = getPointsForOwnedFloors(plotModel, "IncomePoint", newFloorOnly, "DefensePoints")
	local incPlaced = 0
	local maxIncSlots = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(player, "income") or (#ownedFloors * 6)
	for _, pt in ipairs(incomePoints) do
		local slotIdx = pt.index
		if slotIdx > maxIncSlots then continue end
		local uid = data.baseSlots and data.baseSlots[slotIdx]
		if not uid or uid == "" then continue end
		local egg = PlayerDataManager.GetEggByUid and PlayerDataManager.GetEggByUid(player, uid)
		if egg then
			local hatchAt = egg.createdAt + egg.hatchMinutes * 60
			if (os.time() or 0) < hatchAt then
				spawnBaseOrb(egg.creatureId, pt.part, uid, plotModel, "income", nil, egg.level, player.UserId, true, hatchAt, nil, slotIdx, "Normal", nil, egg.inspected == true)
				incPlaced = incPlaced + 1
			end
		else
			for _, entry in ipairs(data.inventory) do
				if entry.uid and tostring(entry.uid) == tostring(uid) then
					spawnBaseOrb(entry.id, pt.part, uid, plotModel, "income", nil, entry.level, player.UserId, nil, nil, nil, slotIdx, entry.variant, entry.nickname)
					incPlaced = incPlaced + 1
					break
				end
			end
		end
	end

	-- ── Step 3: Floor-specific feature activation ───────────────────────────

	-- Floor 2: spawn battle team orbs on BattlePoints (inside Floor2/BattleTeam)
	local btlPlaced = 0
	if floorNum == 2 and data.battleTeam then
		local battlePointMap = getBattlePointMap(plotModel)
		for slotIndex, uid in pairs(data.battleTeam) do
			local pointPart = battlePointMap[tonumber(slotIndex) or slotIndex]
			if pointPart and uid then
				for _, entry in ipairs(data.inventory) do
					if entry.uid and tostring(entry.uid) == tostring(uid) then
						spawnBaseOrb(entry.id, pointPart, uid, plotModel, "battle", tostring(slotIndex), entry.level, player.UserId, nil, nil, nil, slotIndex, entry.variant, entry.nickname)
						btlPlaced = btlPlaced + 1
						break
					end
				end
			end
		end
	end

	-- Floor 3: set up combiner/recycler prompts (parts live in Floor3 folder)
	if floorNum == 3 then
		pcall(function()
			local SSS = game:GetService("ServerScriptService")
			local CRS = require(SSS:FindFirstChild("CombinerRecyclerSystem") or SSS:WaitForChild("CombinerRecyclerSystem", 5))
			if CRS and CRS.SetupPlotPrompts then
				CRS.SetupPlotPrompts(plotModel, ownedFloors)
			end
		end)
	end

	print("[BasePlacement] ActivateFloor " .. floorNum .. " for " .. player.Name .. ": "
		.. defPlaced .. " defense, " .. incPlaced .. " income, " .. btlPlaced .. " battle")

	placementLocks[userId] = nil
end

function BasePlacementSystem.ClearBattleCreatures(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return end
	local plotModel = findPlotModel(data.plotId)
	if plotModel then clearTaggedCreatures(plotModel, BATTLE_TAG) end
end

-- Clear a single battle creature at a battle slot index (1..9). Does not touch other slots.
function BasePlacementSystem.ClearBattleCreatureAtSlot(player, slotIndex)
	if type(slotIndex) ~= "number" then return false end
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return false end
	local plotModel = findPlotModel(data.plotId)
	if not plotModel then return false end
	clearCreatureAtSlot(plotModel, BATTLE_TAG, slotIndex)
	return true
end

-- Place one battle creature at a battle slot index (1..9) on Floor2/BattleTeam/BattlePointX.
-- Incremental: clears only that slot's existing model, then spawns the new one.
function BasePlacementSystem.PlaceBattleCreatureInSlot(player, slotIndex, uid)
	if runWhenPlacementIdle(player, function()
		BasePlacementSystem.PlaceBattleCreatureInSlot(player, slotIndex, uid)
	end) then
		return false
	end
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 9 then return false end
	if not uid or uid == "" then return false end

	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return false end
	local plotModel = findPlotModel(data.plotId)
	if not plotModel then return false end

	-- Ensure Floor2 exists; if not owned, skip (no battle visuals).
	local ownedFloors = normalizeOwnedFloorsForPlacement(data.ownedFloors)
	local ownsBattle = false
	for _, f in ipairs(ownedFloors) do
		if f == 2 then ownsBattle = true break end
	end
	if not ownsBattle then return false end

	local battlePointMap = getBattlePointMap(plotModel)
	local pointPart = battlePointMap[slotIndex]
	if not pointPart then return false end

	-- Clear anything currently at this battle slot
	clearCreatureAtSlot(plotModel, BATTLE_TAG, slotIndex)

	-- Spawn new battle orb from inventory entry
	local su = tostring(uid)
	for _, entry in ipairs(data.inventory or {}) do
		if entry.uid and tostring(entry.uid) == su then
			spawnBaseOrb(
				entry.id,
				pointPart,
				uid,
				plotModel,
				"battle",
				tostring(slotIndex),
				entry.level,
				player.UserId,
				nil,
				nil,
				nil,
				slotIndex,
				entry.variant,
				entry.nickname
			)
			return true
		end
	end
	return false
end

function BasePlacementSystem.RespawnBattleCreatures(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return end
	local plotModel = findPlotModel(data.plotId)
	if not plotModel then return end

	local ownedFloors = normalizeOwnedFloorsForPlacement(data.ownedFloors)
	local ownsBattle = false
	for _, f in ipairs(ownedFloors) do if f == 2 then ownsBattle = true break end end

	clearTaggedCreatures(plotModel, BATTLE_TAG)
	local battlePointMap = getBattlePointMap(plotModel)
	if data.battleTeam and ownsBattle then
		for slotIndex, uid in pairs(data.battleTeam) do
			local pointPart = battlePointMap[tonumber(slotIndex) or slotIndex]
			if pointPart and uid then
				for _, entry in ipairs(data.inventory) do
					if entry.uid and tostring(entry.uid) == tostring(uid) then
						spawnBaseOrb(entry.id, pointPart, uid, plotModel, "battle", tostring(slotIndex), entry.level, player.UserId, nil, nil, nil, slotIndex, entry.variant, entry.nickname)
						break
					end
				end
			end
		end
	end
end

-- Update only BattlePoint visual state (color/material) without respawning any models.
-- Used when toggling battle team active/inactive so base creatures do not flicker.
function BasePlacementSystem.UpdateBattlePointVisualState(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return false end
	local plotModel = findPlotModel(data.plotId)
	if not plotModel then return false end

	local ownedFloors = normalizeOwnedFloorsForPlacement(data.ownedFloors)
	local ownsBattle = false
	for _, f in ipairs(ownedFloors) do
		if f == 2 then
			ownsBattle = true
			break
		end
	end
	if not ownsBattle then return false end

	setBattlePointColors(plotModel, data.battleTeamEnabled ~= false)
	return true
end

-- -- INVADER TRACKING (touch PlotCenter or walls) --
-- When a player who does NOT own the base and is NOT on the access list touches plot center or walls,
-- they become an "invader" and defense creatures will target them and their companion.

local function isPlotTouchPart(part)
	if not part or not part:IsA("BasePart") then return false end
	local name = part.Name:lower()
	if part.Name == "PlotCenter" then return true end
	if name:find("wall") then return true end
	-- Floor parts (PlotCenter has CanCollide=false; floors trigger when walking on base)
	if name:find("floor") then return true end
	return false
end

local function getPlotOwnerUserId(plotId)
	for _, p in ipairs(Players:GetPlayers()) do
		local pd = PlayerDataManager.GetData(p)
		if pd and pd.plotId and pd.plotId == plotId then return p.UserId end
	end
	return nil
end

local function isPlayerAllowedOnPlot(plotOwnerUserId, visitorUserId)
	if not plotOwnerUserId or visitorUserId == plotOwnerUserId then return true end
	local ownerPlayer = Players:GetPlayerByUserId(plotOwnerUserId)
	if not ownerPlayer then return false end
	return PlayerDataManager.IsFriend(ownerPlayer, visitorUserId)
end

local function markInvader(plotId, userId)
	if not activeInvaders[plotId] then activeInvaders[plotId] = {} end
	activeInvaders[plotId][userId] = tick()
end

function BasePlacementSystem.IsPlayerInvader(plotId, plotOwnerUserId, userId)
	if not plotId or not userId or userId == plotOwnerUserId then return false end
	if isPlayerAllowedOnPlot(plotOwnerUserId, userId) then return false end
	local invs = activeInvaders[plotId]
	if not invs then return false end
	local lastTouch = invs[userId]
	if not lastTouch then return false end
	if tick() - lastTouch > INVADER_TIMEOUT then invs[userId] = nil; return false end
	return true
end

local function setupPlotTouchDetection(plotModel, plotId)
	local function onTouched(_touchedPart, otherPart)
		if not otherPart or not otherPart.Parent then return end
		local character = otherPart.Parent
		if not character:IsA("Model") or not character:FindFirstChild("Humanoid") then return end
		local hum = character:FindFirstChild("Humanoid")
		if not hum or hum.Health <= 0 then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		local ownerUserId = getPlotOwnerUserId(plotId)
		if not ownerUserId then return end
		if isPlayerAllowedOnPlot(ownerUserId, player.UserId) then return end
		markInvader(plotId, player.UserId)
	end

	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and isPlotTouchPart(desc) then
			desc.Touched:Connect(function(other) onTouched(desc, other) end)
		end
	end
end

-- Clean stale invaders (called periodically)
local function pruneStaleInvaders()
	local now = tick()
	for plotId, invs in pairs(activeInvaders) do
		for userId, lastTouch in pairs(invs) do
			if now - lastTouch > INVADER_TIMEOUT then invs[userId] = nil end
		end
		if next(invs) == nil then activeInvaders[plotId] = nil end
	end
end

-- -- DEFENSE TURRET AI --
-- Defense creatures attack hostile world creatures and enemy companions within their plot area.

local WORLD_CREATURE_TAG = "WorldCreature"
local COMPANION_TAG = "FavoriteCreature"

local function defenseAttackEffect(fromPos, toPos, color)
	task.spawn(function()
		local bolt = Instance.new("Part")
		bolt.Size = Vector3.new(1.2, 1.2, 1.2); bolt.Shape = Enum.PartType.Ball
		bolt.Color = color; bolt.Material = Enum.Material.Neon
		bolt.Anchored = true; bolt.CanCollide = false; bolt.CastShadow = false
		bolt.Parent = Workspace
		local dur = 0.15; local s = tick()
		while tick() - s < dur do
			bolt.Position = fromPos:Lerp(toPos, (tick() - s) / dur)
			RunService.Heartbeat:Wait()
		end
		bolt.Transparency = 0.3; task.wait(0.08); bolt:Destroy()
	end)
end

local function defenseShowDamage(pos, dmg)
	local att = Instance.new("Part")
	att.Size = Vector3.new(0.1,0.1,0.1); att.Position = pos + Vector3.new(0,2,0)
	att.Anchored = true; att.CanCollide = false; att.Transparency = 1; att.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0,60,0,24); bb.StudsOffset = Vector3.new(0,2,0)
	bb.AlwaysOnTop = true; bb.Adornee = att; bb.Parent = att
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
	lbl.Text = "-"..math.floor(dmg); lbl.TextColor3 = Color3.fromRGB(220, 60, 70)
	lbl.Font = Enum.Font.GothamBlack; lbl.TextSize = 14
	lbl.TextStrokeColor3 = Color3.new(0,0,0); lbl.TextStrokeTransparency = 0.3; lbl.Parent = bb
	task.spawn(function()
		for i = 1, 12 do
			att.Position = att.Position + Vector3.new(0, 0.1, 0)
			lbl.TextTransparency = i/12; lbl.TextStrokeTransparency = 0.3 + (i/12)*0.7
			RunService.Heartbeat:Wait()
		end; att:Destroy()
	end)
end

local defenseLastAttack = {} -- [model] = tick
local defenseLockedTarget = {} -- FIX #28b: [defModel] = targetModel (persistent target lock)
local defenseLOSFailCount = {} -- [defModel] = consecutive ticks where target had no tp/LOS

local function awardDefenseKillXP(killerModel, killKind)
	if not killerModel or not killerModel.Parent then return end
	if not CollectionService:HasTag(killerModel, DEFENSE_TAG) then return end
	local uid = killerModel:GetAttribute("UID")
	local ownerUserId = killerModel:GetAttribute("OwnerUserId")
	if not uid or not ownerUserId then return end
	local player = Players:GetPlayerByUserId(ownerUserId)
	if not player or not PlayerDataManager.GetData(player) then return end
	local killXP = GameConfig.DefenseKillXP or 15
	PlayerDataManager.AddXP(player, uid, killXP)
	local d = PlayerDataManager.GetData(player)
	if d and d.stats then
		d.stats.defenseKills = (d.stats.defenseKills or 0) + 1
	end
	if PlayerDataManager.NotifyAchievement then
		PlayerDataManager.NotifyAchievement("OnDefenseKill", player, killKind or "monster")
	end
end

local function runDefenseTurretLoop()
	-- CreatureAI is already set at module level by Init()
	local loopCount = 0
	while true do
		task.wait(0.5)
		loopCount = loopCount + 1
		if loopCount % 20 == 0 then pruneStaleInvaders() end

		-- FIX #28: For each defense creature, check for hostile targets.
		-- Wrapped in pcall so one turret erroring doesn't kill the entire loop.
		for _, defModel in ipairs(CollectionService:GetTagged(DEFENSE_TAG)) do
			local okTurret, errTurret = pcall(function()
			if not defModel.Parent then return end

			local body = CreatureModelLoader.GetBodyPart(defModel) or defModel:FindFirstChild("Body")
			if not body then return end

			local cid = defModel:GetAttribute("CreatureId")
			local info = cid and CreatureData.GetById(cid)
			if not info then return end

			-- Check cooldown (ensure numeric: config could be string from DataStore)
			local attackCD = tonumber(GameConfig.DefenseAttackCD) or 2.5
			local lastAtk = defenseLastAttack[defModel] or 0
			local canAttackNow = (tick() - lastAtk) >= attackCD
			local losFailThreshold = math.max(1, tonumber(GameConfig.DefenseLOSFailThreshold) or 3)

			local defPos = body.Position
			local attackRange = tonumber(GameConfig.DefenseAttackRange) or 40
			-- Scale damage by creature level, tier, and rarity (GetEffectiveStats)
			local defLevel = defModel:GetAttribute("CreatureLevel") or 1
			local defVariant = defModel:GetAttribute("CreatureVariant") or "Normal"
			local ownerPlayer = Players:GetPlayerByUserId(tonumber(defModel:GetAttribute("OwnerUserId")) or 0)
			local defStats = (PlayerDataManager and PlayerDataManager.GetEffectiveStats) and PlayerDataManager.GetEffectiveStats(info.id, defLevel, defVariant, ownerPlayer)
			local atkStat = defStats and defStats.attack or (info.attack * (1 + GameConfig.StatGainPerLevel * (defLevel - 1)))
			local baseDmg = math.max(3, math.floor(atkStat * GameConfig.DefenseBaseDamage / 10))
			local attackColor = Color3.fromRGB(220, 60, 70)

			-- Find the plot this defense creature belongs to (walk up hierarchy for robustness)
			local plotModel, plotId = getPlotFromPart(defModel)
			if not plotModel then
				plotModel = defModel.Parent
				plotId = plotModel and (plotModel.Name:match("^Plot(%d+)$") or plotModel.Name:match("^Part(%d+)$"))
				plotId = plotId and tonumber(plotId) or nil
			end
			if not plotModel then return end
			-- Get plot center for range check (recursive - PlotCenter may be nested; support Model or BasePart)
			local plotCenter = plotModel:FindFirstChild("PlotCenter", true)
			local plotCenterPos = defPos
			if plotCenter then
				if plotCenter:IsA("BasePart") then
					plotCenterPos = plotCenter.Position
				else
					local ok, pivot = pcall(function() return plotCenter:GetPivot().Position end)
					if ok and pivot then plotCenterPos = pivot end
				end
			end

			-- FIX #28: Determine who owns this plot. Primary source: OwnerUserId attribute
			-- stamped on the defense model at spawn time (reliable, no per-tick lookup).
			-- Fallback: plotId-based lookup + player iteration.
			local plotOwnerUserId = tonumber(defModel:GetAttribute("OwnerUserId"))
			if not plotOwnerUserId and plotModel then
				if plotId then
					plotOwnerUserId = getPlotOwnerUserId(plotId)
				end
				if not plotOwnerUserId then
					for _, p in ipairs(Players:GetPlayers()) do
						local pd = PlayerDataManager.GetData(p)
						if pd and pd.plotId and pd.plotId > 0 then
							local pm = findPlotModel(pd.plotId)
							if pm == plotModel then plotOwnerUserId = p.UserId; break end
						end
					end
				end
				-- Cache on model so future ticks don't need to re-lookup
				if plotOwnerUserId then
					defModel:SetAttribute("OwnerUserId", plotOwnerUserId)
				end
			end

			-- plotId already set from getPlotFromPart above; ensure we have it
			if not plotId and plotModel then
				plotId = plotModel.Name:match("^Plot(%d+)$") or plotModel.Name:match("^Part(%d+)$")
				plotId = plotId and tonumber(plotId) or nil
			end

			-- Helper: is this player hostile? (formal raider OR physical invader OR inside plot OR within this defense's range)
			-- Uses touch-based invader tracking, plot proximity, and per-defense range so multiplayer trespassers are always targetable.
			local PLOT_INVADE_RADIUS = 55  -- horizontal (XZ) radius from plot center; ignore Y so multi-floor works
			local function isPlayerHostile(userId)
				userId = tonumber(userId)
				if not userId then return false end
				if not plotOwnerUserId then return false end
				if userId == plotOwnerUserId then return false end
				if isPlayerAllowedOnPlot(plotOwnerUserId, userId) then return false end
				local p = Players:GetPlayerByUserId(userId)
				if not p or not p.Character then return false end
				local root = p.Character:FindFirstChild("HumanoidRootPart")
				local hum = p.Character:FindFirstChild("Humanoid")
				if not root or not hum or hum.Health <= 0 then return false end
				-- Within this defense's attack range => always hostile (so entering base and getting close triggers targeting)
				if (defPos - root.Position).Magnitude <= attackRange then
					return true
				end
				-- Formal raid (via Raids UI)
				if RaidSystem and RaidSystem.IsPlayerRaidingVictim and RaidSystem.IsPlayerRaidingVictim(userId, plotOwnerUserId) then
					return true
				end
				-- Touch-based invader (touched plot center/walls/floors)
				if plotId and BasePlacementSystem.IsPlayerInvader(plotId, plotOwnerUserId, userId) then
					return true
				end
				-- Proximity-based: physically inside plot bounds (XZ distance only - works on any floor)
				local dxz = (root.Position - plotCenterPos) * Vector3.new(1, 0, 1)
				if dxz.Magnitude < PLOT_INVADE_RADIUS then
					return true
				end
				return false
			end

			-- Helper: is this target still valid (alive, parented, in range)?
			local function isTargetValid(tgt)
				if not tgt or not tgt.Parent then return false end
				-- Player character
				if tgt:FindFirstChild("Humanoid") then
					local hum = tgt:FindFirstChild("Humanoid")
					if not hum or hum.Health <= 0 then return false end
					local root = tgt:FindFirstChild("HumanoidRootPart")
					if not root then return false end
					if (defPos - root.Position).Magnitude > attackRange then return false end
					local targetPlayer = Players:GetPlayerFromCharacter(tgt)
					if not targetPlayer or not isPlayerHostile(targetPlayer.UserId) then return false end
					return true
				end
				-- Companion
				if CollectionService:HasTag(tgt, COMPANION_TAG) then
					local cb = CreatureModelLoader.GetBodyPart(tgt) or tgt:FindFirstChild("Body")
					if not cb then return false end
					if (defPos - cb.Position).Magnitude > attackRange then return false end
					local ownerId = tonumber(tgt:GetAttribute("OwnerUserId"))
					if not ownerId or not isPlayerHostile(ownerId) then return false end
					return true
				end
				-- World creature
				if CollectionService:HasTag(tgt, WORLD_CREATURE_TAG) then
					if tgt:GetAttribute("Fainted") then return false end
					local wb = tgt.PrimaryPart or CreatureModelLoader.GetBodyPart(tgt) or tgt:FindFirstChild("Body")
					if not wb then return false end
					if (defPos - wb.Position).Magnitude > attackRange then return false end
					return true
				end
				return false
			end

			-- FIX #28b: Target persistence — keep shooting locked target until it dies or leaves.
			-- Only re-acquire a new target when the locked one is invalid.
			local bestTarget = defenseLockedTarget[defModel]
			if not isTargetValid(bestTarget) then
				if bestTarget then
					defenseLog("Drop lock: invalid target", defModel.Name, bestTarget.Name)
				end
				bestTarget = nil
				defenseLockedTarget[defModel] = nil
				defenseLOSFailCount[defModel] = 0
			end

			-- Re-acquire target if no locked target.
			-- TARGET PRIORITY: 1) Companion monsters, 2) Players (raiders), 3) World creatures
			if not bestTarget then
				local bestDist = attackRange
				-- 1) Enemy companions first
				for _, comp in ipairs(CollectionService:GetTagged(COMPANION_TAG)) do
					if comp.Parent then
						local ownerIdRaw = comp:GetAttribute("OwnerUserId")
						local ownerId = (type(ownerIdRaw) == "number") and ownerIdRaw or tonumber(ownerIdRaw)
						if ownerId and isPlayerHostile(ownerId) then
							local cb = CreatureModelLoader.GetBodyPart(comp) or comp:FindFirstChild("Body")
							if cb then
								local d = (defPos - cb.Position).Magnitude
								if d < bestDist then bestDist = d; bestTarget = comp end
							end
						end
					end
				end
				-- 2) Player raiders/invaders
				if not bestTarget and plotOwnerUserId then
					for _, p in ipairs(Players:GetPlayers()) do
						if not isPlayerHostile(p.UserId) then continue end
						local char = p.Character
						if not char then continue end
						local root = char:FindFirstChild("HumanoidRootPart")
						if not root then continue end
						local d = (defPos - root.Position).Magnitude
						if d < bestDist then bestDist = d; bestTarget = char end
					end
				end
				-- 3) World creatures (not arena)
				if not bestTarget then
					for _, wc in ipairs(CollectionService:GetTagged(WORLD_CREATURE_TAG)) do
						if wc.Parent and not wc:GetAttribute("Fainted")
							and not CollectionService:HasTag(wc, "ArenaCreature") then
							local wb = wc.PrimaryPart or CreatureModelLoader.GetBodyPart(wc) or wc:FindFirstChild("Body")
							if wb then
								local d = (defPos - wb.Position).Magnitude
								if d < bestDist then bestDist = d; bestTarget = wc end
							end
						end
					end
				end
				-- Lock onto new target
				if bestTarget then
					defenseLockedTarget[defModel] = bestTarget
					defenseLOSFailCount[defModel] = 0
					defenseLog("Acquire lock", defModel.Name, bestTarget.Name)
				end
			end

			if not bestTarget then
				defenseLOSFailCount[defModel] = 0
			end
			defModel:SetAttribute("DefenderActive", bestTarget ~= nil)

			-- FIX #25b: Line of sight for world creatures; intruders inside the base bypass LOS.
			if bestTarget then
				local tp = bestTarget.PrimaryPart or CreatureModelLoader.GetBodyPart(bestTarget)
					or bestTarget:FindFirstChild("Body") or bestTarget:FindFirstChild("HumanoidRootPart")
				-- Determine if target is an intruder (player char or companion of hostile player) — bypass LOS
				local isIntruder = false
				if bestTarget:FindFirstChild("Humanoid") then
					local targetPlayer = Players:GetPlayerFromCharacter(bestTarget)
					if targetPlayer and isPlayerHostile(targetPlayer.UserId) then
						isIntruder = true
					end
				elseif CollectionService:HasTag(bestTarget, COMPANION_TAG) then
					local compOwnerId = tonumber(bestTarget:GetAttribute("OwnerUserId"))
					if compOwnerId and isPlayerHostile(compOwnerId) then
						isIntruder = true
					end
				end
				-- Intruders skip LOS; world creatures require LOS
				local hasLOS = isIntruder or not CreatureAI or not CreatureAI.HasLineOfSight
					or CreatureAI.HasLineOfSight(defModel, bestTarget)
				if tp and hasLOS then
					defenseLOSFailCount[defModel] = 0
					if canAttackNow then
						defenseLastAttack[defModel] = tick()
						-- Elemental weakness
						local defenderElement = nil
						if CollectionService:HasTag(bestTarget, WORLD_CREATURE_TAG) then
							local dcid = bestTarget:GetAttribute("CreatureId")
							local dinfo = dcid and CreatureData.GetById(dcid)
							defenderElement = dinfo and dinfo.element
						elseif CollectionService:HasTag(bestTarget, COMPANION_TAG) then
							local FavSys = nil
							pcall(function() FavSys = require(game:GetService("ServerScriptService").FavoriteCreatureSystem) end)
							if FavSys then
								local comp2 = FavSys.GetCompanionForModel(bestTarget)
								if comp2 then
									local dinfo = CreatureData.GetById(comp2.creatureId)
									defenderElement = dinfo and dinfo.element
								end
							end
						end
						local elemMult = CreatureData.GetElementalDamageMultiplier(info.element, defenderElement)
						if elemMult > 1 then
							elemMult = GameConfig.ElementalAdvantageMultiplier or elemMult
						elseif elemMult < 1 then
							elemMult = GameConfig.ElementalDisadvantageMultiplier or elemMult
						end
						local finalDmg = math.floor(math.max(1, baseDmg * elemMult))
						defenseAttackEffect(body.Position, tp.Position, attackColor)
						defenseShowDamage(tp.Position, finalDmg)

						-- Deal damage
						if CollectionService:HasTag(bestTarget, WORLD_CREATURE_TAG) then
							if CreatureAI then CreatureAI.DamageCreature(bestTarget, finalDmg, defModel) end
						elseif CollectionService:HasTag(bestTarget, COMPANION_TAG) then
							local FavSys = nil
							pcall(function() FavSys = require(game:GetService("ServerScriptService").FavoriteCreatureSystem) end)
							if FavSys then
								local ownerId2 = tonumber(bestTarget:GetAttribute("OwnerUserId"))
								local ownerPlayer = ownerId2 and Players:GetPlayerByUserId(ownerId2)
								if ownerPlayer then FavSys.DamageCompanion(ownerPlayer, finalDmg, defModel) end
							end
						elseif bestTarget:IsA("Model") and bestTarget:FindFirstChild("Humanoid") then
							local hum = bestTarget:FindFirstChild("Humanoid")
							if hum and hum.Health > 0 then
								local p = Players:GetPlayerFromCharacter(bestTarget)
								local applied = p and PlayerWorldStats.ApplyDefenseFromPlayer(p, finalDmg) or finalDmg
								hum:TakeDamage(applied)
							end
						end
					end
				else
					-- Transient LOS/body misses can happen; only clear lock after a few consecutive failures.
					local failCount = (defenseLOSFailCount[defModel] or 0) + 1
					defenseLOSFailCount[defModel] = failCount
					if failCount >= losFailThreshold then
						defenseLog("Drop lock: LOS/tp fail threshold", defModel.Name, bestTarget.Name, failCount)
						defenseLockedTarget[defModel] = nil
						defenseLOSFailCount[defModel] = 0
						defModel:SetAttribute("DefenderActive", false)
					else
						defenseLog("Keep lock: transient LOS/tp miss", defModel.Name, bestTarget.Name, failCount)
					end
				end
			end
			end) -- end pcall
			if not okTurret then
				warn("[BasePlacement] Turret error on " .. (defModel.Name or "?") .. ": " .. tostring(errTurret))
			end
		end

		-- Clean up dead entries
		for model, _ in pairs(defenseLastAttack) do
			if not model.Parent then defenseLastAttack[model] = nil end
		end
		for model, _ in pairs(defenseLockedTarget) do
			if not model.Parent then defenseLockedTarget[model] = nil end
		end
		for model, _ in pairs(defenseLOSFailCount) do
			if not model.Parent then defenseLOSFailCount[model] = nil end
		end
	end
end

-- Returns current defense activity for a specific owner.
-- activeCount: defenders that currently have a valid target lock this tick.
-- totalCount: defenders currently spawned for this owner.
function BasePlacementSystem.GetDefenseActivityForOwner(ownerUserId)
	ownerUserId = tonumber(ownerUserId)
	if not ownerUserId then return 0, 0 end
	local activeCount = 0
	local totalCount = 0
	for _, defModel in ipairs(CollectionService:GetTagged(DEFENSE_TAG)) do
		if defModel and defModel.Parent then
			local ownerId = tonumber(defModel:GetAttribute("OwnerUserId"))
			if ownerId == ownerUserId then
				totalCount = totalCount + 1
				if defModel:GetAttribute("DefenderActive") == true then
					activeCount = activeCount + 1
				end
			end
		end
	end
	return activeCount, totalCount
end

-- -- INIT --

function BasePlacementSystem.Init(playerDataMgr, creatureAIRef)
	PlayerDataManager = playerDataMgr
	if creatureAIRef then CreatureAI = creatureAIRef end

	do
		local w = Workspace
		PLOTS_FOLDER = w:FindFirstChild("BasePlots") or w:FindFirstChild("Plots")
		if not PLOTS_FOLDER then
			for _, segName in ipairs({ "World", "Map", "Game", "Lobby", "Hub", "Main", "Terrain" }) do
				local seg = w:FindFirstChild(segName)
				if seg then
					PLOTS_FOLDER = seg:FindFirstChild("BasePlots") or seg:FindFirstChild("Plots")
					if PLOTS_FOLDER then break end
				end
			end
		end
	end
	if not PLOTS_FOLDER then
		PLOTS_FOLDER = Workspace:WaitForChild("BasePlots", 10)
	end
	if not PLOTS_FOLDER then
		warn("[BasePlacement] No BasePlots/Plots folder (workspace or nested). Disabled.")
		return
	end

	for _, plot in ipairs(PLOTS_FOLDER:GetChildren()) do
		local dp = getPointsByPrefix(plot, "DefensePoint")
		local ip = getPointsByPrefix(plot, "IncomePoint")
		local bp = getBattlePointMap(plot)
		local bpCount = 0; for _ in pairs(bp) do bpCount = bpCount + 1 end
		print("[BasePlacement] " .. plot.Name .. ": " .. #dp .. " defense, " .. #ip .. " income, " .. bpCount .. " battle points")
		-- Setup touch detection for invaders (PlotCenter + walls)
		local plotId = plot.Name:match("^Plot(%d+)$") or plot.Name:match("^Part(%d+)$")
		if plotId then setupPlotTouchDetection(plot, tonumber(plotId)) end
	end

	local minDef = 999
	for _, plot in ipairs(PLOTS_FOLDER:GetChildren()) do
		local count = #getPointsByPrefix(plot, "DefensePoint")
		if count > 0 and count < minDef then minDef = count end
	end
	if minDef < 999 then GameConfig.MaxDefenseSlots = minDef end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Wait()
		task.wait(2)
		-- Wait for player data to load before placing (DataStore may still be loading)
		for attempt = 1, 15 do
			if PlayerDataManager.GetData(player) then break end
			task.wait(1)
		end
		BasePlacementSystem.PlaceCreatures(player)
	end)

	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			task.wait(2)
			-- Wait for player data to load (critical for existing players when server starts)
			for attempt = 1, 15 do
				if not p.Parent then return end
				if PlayerDataManager.GetData(p) then break end
				task.wait(1)
			end
			if p.Parent then BasePlacementSystem.PlaceCreatures(p) end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		placementLocks[player.UserId] = nil
		-- Do NOT trust GetData(plotId): OnPlayerLeave may run first and clear cache / plotId.
		local plotModel = findPlotModelForLeavingPlayer(player)
		if plotModel then
			clearTaggedCreatures(plotModel, DEFENSE_TAG)
			clearTaggedCreatures(plotModel, INCOME_TAG)
			clearTaggedCreatures(plotModel, BATTLE_TAG)
		end
		destroyTaggedBaseCreaturesForOwnerUserId(player.UserId)
		BasePlacementSystem.RefreshAllPlotVisibility()
	end)

	-- Start defense turret AI loop
	task.spawn(runDefenseTurretLoop)

	-- Award defense creature XP when they get a kill (world creature fainted by defense turret)
	if CreatureAI and CreatureAI.OnCreatureFainted then
		CreatureAI.OnCreatureFainted.Event:Connect(function(faintedModel, killerModel)
			awardDefenseKillXP(killerModel, "monster")
			-- Base creatures: do NOT clear/destroy on faint — model stays in faint animation and steal state
			-- so the attacker can walk up and press E to pick up. Slot is cleared only when stolen (FavoriteCreatureSystem).
		end)
	end

	-- Uninhabited plots start hidden; they become visible when a player is assigned (MainServer calls RefreshAllPlotVisibility)
	BasePlacementSystem.RefreshAllPlotVisibility()
	print("[BasePlacement] Initialized with defense turret AI (incremental slot placement)")
end

-- Called from FavoriteCreatureSystem.Init so defense gets XP when they kill an enemy companion.
function BasePlacementSystem.RegisterCompanionFaintForDefenseXP(favSys)
	if not favSys or not favSys.OnCompanionFainted then return end
	favSys.OnCompanionFainted.Event:Connect(function(_player, killerModel)
		awardDefenseKillXP(killerModel, "raider")
	end)
end

return BasePlacementSystem
