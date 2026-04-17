-- Last updated: 2026-03-27 14:45
-- BadlandsSystem.lua - ServerScriptService (ModuleScript)
-- ═══════════════════════════════════════════════════════════════════════════════
-- THE BADLANDS — Master Coordinator (Phase 1: Core Loop)
--
-- High-risk roguelike PvPvE mode. Players enter with nothing, capture creatures
-- during the run, and only keep what they successfully extract with.
--
-- This module handles:
--   - Matchmaking queue and run lifecycle (waiting → active → extraction → ended)
--   - Player teleportation to/from the Badlands zone
--   - Spawn shield management
--   - Run timer and phase transitions
--   - Zone collapse scheduling
--   - Creature spawning delegation (BadlandsSpawner)
--   - Death / elimination handling
--   - Extraction channel orchestration
--   - Post-run results and inventory transfer
--   - The Broker NPC (daily contract, creature sacrifice, queue entry)
--
-- Workspace structure (must exist in workspace.Badlands):
--   Badlands/
--     BadlandsCenter (Part — center reference for zone collapse)
--     SpawnPoints/ (Folder — any Part children, or Models with PrimaryPart)
--     and/or Parts named SpawnPoint1..N, or exactly "SpawnPoint" (world convention)
--     ExtractionPoints/ (Folder — optional, activated mid-run)
--       ExtractPoint1..ExtractPoint3 (Parts)
--     CreatureSpawns/ (Folder — creature spawn points by tier, optional subfolders)
--
-- Dependencies (set in Init):
--   PlayerDataManager, FavoriteCreatureSystem, MountSystem, CreatureAI
--
-- RemoteEvents (created by MainServer before Init):
--   BadlandsQueueJoin, BadlandsQueueLeave, BadlandsQueueUpdate,
--   BadlandsQueueReject, BadlandsRunStart, BadlandsRunEnd,
--   BadlandsEliminated, BadlandsExtracted, BadlandsBagUpdate,
--   BadlandsBagSwitch, BadlandsTimerSync, BadlandsLevelUp,
--   BadlandsExtractStart, BadlandsExtractCancel, BadlandsExtractProgress,
--   BadlandsExtractActivate, BadlandsZoneCollapse, BadlandsPlayerKill,
--   BadlandsSupplyDrop, BadlandsXPGain, BadlandsContractData,
--   BadlandsOfferCreature, BadlandsLootBagSpawned, BadlandsLootBagLoot,
--   BadlandsLootBagUpdate, BadlandsBagReplace
--   BadlandsCaptureResolve (RemoteFunction — client resolves pending capture)
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local BadlandsSystem = {}

-- ═══════════════════════════════════════════════════════════════════════════════
-- Dependencies (set in Init)
-- ═══════════════════════════════════════════════════════════════════════════════
local PlayerDataManager
local FavoriteCreatureSystem
local MountSystem
local CreatureAI
local BasePlacementSystem

-- ═══════════════════════════════════════════════════════════════════════════════
-- Config (from GameConfig with fallbacks)
-- ═══════════════════════════════════════════════════════════════════════════════
local MAX_PLAYERS            = GameConfig.BadlandsMaxPlayers           or 8
local QUEUE_TIMEOUT          = GameConfig.BadlandsQueueTimeout         or 60
local RUN_DURATION           = GameConfig.BadlandsRunDuration          or 600
local HARD_DEADLINE          = GameConfig.BadlandsHardDeadline         or 600
local EXTRACT_ACTIVATE_AT    = GameConfig.BadlandsExtractionActivateAt or 420
local SPAWN_SHIELD_DURATION  = GameConfig.BadlandsSpawnShieldDuration  or 30
local BAG_SLOTS              = GameConfig.BadlandsBagSlots             or 10
local EXTRACTION_TIME        = GameConfig.BadlandsExtractionTime       or 5
local EXTRACTION_MIN_TIME    = GameConfig.BadlandsExtractionMinTime    or 5
local LOOT_BAG_DESPAWN       = GameConfig.BadlandsLootBagDespawnTime   or 60
local COLLAPSE_DPS           = GameConfig.BadlandsCollapseDPS          or 5
local ENABLED                = GameConfig.BadlandsEnabled
if ENABLED == nil then ENABLED = true end

local BADLANDS_TAG = "BadlandsCreature"

-- Badlands creature config
local BL_INITIAL_SPAWN   = GameConfig.BadlandsInitialSpawnCount or 20
local BL_SPAWN_INTERVAL  = GameConfig.BadlandsSpawnInterval     or 8
local BL_MAX_CREATURES    = GameConfig.BadlandsMaxCreatures      or 40
local BL_SCALE_MIN        = GameConfig.BadlandsCreatureScaleMin  or 1.5
local BL_SCALE_MAX        = GameConfig.BadlandsCreatureScaleMax  or 2.0
local BL_STAT_MULT        = GameConfig.BadlandsCreatureStatMult  or 2.0
local BL_MIN_LEVEL        = GameConfig.BadlandsCreatureMinLevel  or 20
local BL_MAX_LEVEL        = GameConfig.BadlandsCreatureMaxLevel  or 50
-- ALL rarities spawn but every creature is Gold or Legend variant — no Normal/Silver
local BL_RARITY_WEIGHTS   = GameConfig.BadlandsRarityWeights     or { Common = 15, Uncommon = 20, Rare = 25, Epic = 25, Legendary = 15 }
local BL_VARIANT_WEIGHTS  = GameConfig.BadlandsVariantWeights    or { Gold = 50, Legend = 50 }

-- Lazy-loaded modules (set in Init to avoid circular requires)
local CreatureModelLoader = nil
local CreatureAnimation = nil

-- ═══════════════════════════════════════════════════════════════════════════════
-- Badlands Creature Spawning
-- All Badlands creatures are Epic/Legendary, Gold/Legend variants, 1.5-2x scale,
-- boosted stats. These are endgame-tier monsters designed to be terrifying.
-- ═══════════════════════════════════════════════════════════════════════════════

--- Pick a random rarity from the Badlands weight table (Epic/Legendary only)
-- @return string — rarity name
local function pickBadlandsRarity()
	local totalWeight = 0
	for _, w in pairs(BL_RARITY_WEIGHTS) do totalWeight = totalWeight + w end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for rarity, weight in pairs(BL_RARITY_WEIGHTS) do
		cumulative = cumulative + weight
		if roll <= cumulative then return rarity end
	end
	return "Legendary" -- fallback
end

--- Pick a random variant from the Badlands weight table (Gold/Legend only)
-- @return string — variant name
local function pickBadlandsVariant()
	local totalWeight = 0
	for _, w in pairs(BL_VARIANT_WEIGHTS) do totalWeight = totalWeight + w end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for variant, weight in pairs(BL_VARIANT_WEIGHTS) do
		cumulative = cumulative + weight
		if roll <= cumulative then return variant end
	end
	return "Legend" -- fallback
end

--- Pick a random creature ID of the given rarity
-- @param rarity string — "Epic" or "Legendary"
-- @return string|nil — creature ID
local function pickBadlandsCreatureId(rarity)
	return CreatureData.GetRandomCreatureIdByRarity(rarity)
end

--- Get all creature spawn points inside the Badlands zone
-- Finds any Part whose name contains "SpawnPoint" or "CreatureSpawn" inside
-- a "CreatureSpawns" folder, or falls back to player SpawnPoints.
-- @return BasePart[] — array of spawn location parts
local function getCreatureSpawnPoints()
	local zone = Workspace:FindFirstChild("Badlands")
	if not zone then return {} end

	local points = {}

	-- Look for dedicated creature spawn folders/points
	for _, desc in ipairs(zone:GetDescendants()) do
		if desc:IsA("BasePart") then
			local name = desc.Name:lower()
			if name:match("creaturespawn") or name:match("spawnpoint")
				or name:match("tier") or name:match("mobspawn") then
				table.insert(points, desc)
			end
		end
	end

	-- If nothing found, use the player spawn points as fallback
	if #points == 0 then
		for _, desc in ipairs(zone:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Name:match("^SpawnPoint%d+$") then
				table.insert(points, desc)
			end
		end
	end

	return points
end

--- Spawn a single Badlands creature at the given position
-- Creates an oversized, stat-boosted, high-rarity, high-variant creature.
-- @param position Vector3 — world position to spawn at
-- @return Model|nil — the spawned creature model
local function spawnBadlandsCreature(position)
	local rarity = pickBadlandsRarity()
	local creatureId = pickBadlandsCreatureId(rarity)
	if not creatureId then
		warn("[Badlands] Could not find creature for rarity: " .. rarity)
		return nil
	end

	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local variant = pickBadlandsVariant()
	local level = math.random(BL_MIN_LEVEL, BL_MAX_LEVEL)
	local scale = BL_SCALE_MIN + math.random() * (BL_SCALE_MAX - BL_SCALE_MIN)

	-- Compute boosted stats: base × level scaling × Badlands multiplier
	local baseHP = info.health or 100
	local baseATK = info.attack or 10
	local baseDEF = info.defense or 5
	local baseSPD = info.speed or 5
	local levelMult = 1 + (level - 1) * (GameConfig.StatGainPerLevel or 0.08)

	local finalHP  = math.floor(baseHP  * levelMult * BL_STAT_MULT)
	local finalATK = math.floor(baseATK * levelMult * BL_STAT_MULT)
	local finalDEF = math.floor(baseDEF * levelMult * BL_STAT_MULT)
	local finalSPD = math.floor(baseSPD * levelMult * BL_STAT_MULT)

	-- Spawn the model using CreatureModelLoader (same as arena/gym creatures)
	if not CreatureModelLoader then
		local ok
		ok, CreatureModelLoader = pcall(function()
			return require(ReplicatedStorage.Modules.CreatureModelLoader)
		end)
		if not ok then CreatureModelLoader = nil end
	end
	if not CreatureAnimation then
		local ok
		ok, CreatureAnimation = pcall(function()
			return require(ReplicatedStorage.Modules.CreatureAnimation)
		end)
		if not ok then CreatureAnimation = nil end
	end

	-- Create model container
	local model = Instance.new("Model")
	model.Name = "Badlands_" .. info.id .. "_" .. variant
	-- FIX #22: Badlands creatures need a UniqueId so CaptureClient's targeting
	-- system can track and select them (same as world creatures from CreatureSpawner).
	local uniqueId = "BL_" .. creatureId .. "_" .. tostring(math.random(100000, 999999))
	model:SetAttribute("UniqueId", uniqueId)
	model:SetAttribute("CreatureId", creatureId)
	model:SetAttribute("Variant", variant)
	model:SetAttribute("Level", level)
	model:SetAttribute("BadlandsCreature", true)
	model:SetAttribute("MaxHP", finalHP)
	model:SetAttribute("HP", finalHP)
	model:SetAttribute("Attack", finalATK)
	model:SetAttribute("Defense", finalDEF)
	model:SetAttribute("Speed", finalSPD)
	model:SetAttribute("Scale", scale)
	CollectionService:AddTag(model, BADLANDS_TAG)
	CollectionService:AddTag(model, "WorldCreature") -- so capture system can detect it

	local spawnPos = position + Vector3.new(0, 3, 0)

	-- Load the creature model (scaled up by the Badlands scale factor)
	local body, core, isCustomModel
	local baseSize = 4 * scale -- normal creature baseSize is 4, we multiply by 1.5-2x
	if CreatureModelLoader then
		local options = { targetSize = baseSize, creatureId = creatureId }
		body, core, isCustomModel = CreatureModelLoader.LoadAndIntegrate(
			model, info.modelName, info.displayName, spawnPos, options
		)
		if body then
			core = core or model:FindFirstChild("Core")
		end
	end

	-- Fallback: create orb body if model loading failed
	if not body then
		body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(baseSize, baseSize, baseSize)
		body.Color = info.primaryColor or Color3.fromRGB(255, 50, 50)
		body.Material = Enum.Material.Neon
		body.Anchored = true
		body.CanCollide = false
		body.CastShadow = true
		body.Position = spawnPos
		body.Parent = model
	end

	-- Variant glow: Gold = warm gold aura, Legend = intense magenta aura
	local variantColor = CreatureData.VariantColors and CreatureData.VariantColors[variant]
		or Color3.fromRGB(255, 100, 255)
	local glow = Instance.new("PointLight")
	glow.Name = "BadlandsGlow"
	glow.Color = variantColor
	glow.Brightness = variant == "Legend" and 4 or 3
	glow.Range = baseSize * 3
	glow.Parent = body

	-- Rarity highlight ring
	local rarityInfo = CreatureData.Rarities[rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(255, 184, 0)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = variantColor
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = rarityColor
	highlight.OutlineTransparency = 0
	highlight.Parent = model

	-- Billboard: Name + HP + Level + Variant badge
	local bb = Instance.new("BillboardGui")
	bb.Name = "InfoTag"
	bb.Adornee = body
	bb.Size = UDim2.new(0, 200, 0, 80)
	bb.StudsOffset = Vector3.new(0, baseSize * 0.8 + 2, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 80
	bb.Parent = model

	-- Variant badge (top line)
	local variantLabel = Instance.new("TextLabel")
	variantLabel.Name = "VariantLabel"
	variantLabel.Size = UDim2.new(1, 0, 0.2, 0)
	variantLabel.Position = UDim2.new(0, 0, 0, 0)
	variantLabel.BackgroundTransparency = 1
	variantLabel.Text = "★ " .. variant:upper() .. " ★"
	variantLabel.TextColor3 = variantColor
	variantLabel.Font = Enum.Font.GothamBlack
	variantLabel.TextScaled = true
	variantLabel.Parent = bb

	-- Name + Level line
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.3, 0)
	nameLabel.Position = UDim2.new(0, 0, 0.2, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = (info.displayName or creatureId) .. "  Lv" .. level
	nameLabel.TextColor3 = rarityColor
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Parent = bb

	-- HP bar background
	local hpBarBG = Instance.new("Frame")
	hpBarBG.Name = "HPBarBG"
	hpBarBG.Size = UDim2.new(0.8, 0, 0.12, 0)
	hpBarBG.Position = UDim2.new(0.1, 0, 0.55, 0)
	hpBarBG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBarBG.BorderSizePixel = 0
	hpBarBG.Parent = bb
	Instance.new("UICorner", hpBarBG).CornerRadius = UDim.new(0, 3)

	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(220, 50, 50) -- red for Badlands creatures
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBarBG
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 3)

	-- HP text
	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.new(1, 0, 0.2, 0)
	hpLabel.Position = UDim2.new(0, 0, 0.7, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Text = finalHP .. "/" .. finalHP
	hpLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	hpLabel.TextScaled = true
	hpLabel.Font = Enum.Font.GothamMedium
	hpLabel.Parent = bb

	-- Set PrimaryPart and parent to workspace
	model.PrimaryPart = body
	model.Parent = Workspace:FindFirstChild("Badlands") or Workspace

	-- Apply rotation offset for custom models
	if isCustomModel and info then
		local rotOffset = CreatureData.GetModelRotationOffset and
			CreatureData.GetModelRotationOffset(info) or CFrame.identity
		model:PivotTo(CFrame.new(spawnPos) * rotOffset)
	end

	-- Animation
	if CreatureAnimation then
		pcall(function() CreatureAnimation.Setup(model, creatureId, "Idle") end)
	end

	-- Register with CreatureAI for behavior (aggression, wandering, combat)
	if CreatureAI then
		pcall(function() CreatureAI.RegisterCreature(model, creatureId, spawnPos) end)
	end

	return model
end

--- Spawn the initial wave of Badlands creatures across all spawn points
-- Called once when a run starts, after players are teleported in.
-- @param run table — the active run state (to track spawned creatures)
local function spawnInitialBadlandsCreatures(run)
	local points = getCreatureSpawnPoints()
	if #points == 0 then
		warn("[Badlands] No creature spawn points found — using player spawn points")
		points = {}
		local zone = Workspace:FindFirstChild("Badlands")
		if zone then
			for _, d in ipairs(zone:GetDescendants()) do
				if d:IsA("BasePart") and d.Name:match("^SpawnPoint%d+$") then
					table.insert(points, d)
				end
			end
		end
	end

	if #points == 0 then
		warn("[Badlands] No spawn points at all — cannot spawn creatures")
		return
	end

	local spawned = 0
	for i = 1, BL_INITIAL_SPAWN do
		-- Pick a random spawn point and offset randomly within 20 studs
		local point = points[math.random(#points)]
		local offset = Vector3.new(
			math.random(-20, 20),
			0,
			math.random(-20, 20)
		)
		local pos = point.Position + offset

		local model = spawnBadlandsCreature(pos)
		if model then
			table.insert(run.spawnedCreatures, model)
			spawned = spawned + 1
		end
	end

	print("[Badlands] Spawned " .. spawned .. " initial creatures (Epic/Legendary, Gold/Legend, 1.5-2x scale)")
end

--- Continuous spawning loop — keeps creatures flowing during the run
-- Respawns creatures every BL_SPAWN_INTERVAL seconds up to BL_MAX_CREATURES.
-- @param run table — the active run state
-- @param runId string — the run ID (to detect if run ended)
local function badlandsSpawnLoop(run, runId)
	task.wait(5) -- small delay before continuous spawns start
	while activeRun and activeRun.runId == runId and activeRun.phase ~= "ended" do
		-- Count alive creatures
		local alive = 0
		for i = #run.spawnedCreatures, 1, -1 do
			local c = run.spawnedCreatures[i]
			if c and c.Parent then
				alive = alive + 1
			else
				table.remove(run.spawnedCreatures, i)
			end
		end

		-- Spawn more if below cap
		if alive < BL_MAX_CREATURES then
			local toSpawn = math.min(3, BL_MAX_CREATURES - alive)
			local points = getCreatureSpawnPoints()
			if #points > 0 then
				for _ = 1, toSpawn do
					local point = points[math.random(#points)]
					local offset = Vector3.new(math.random(-25, 25), 0, math.random(-25, 25))
					local model = spawnBadlandsCreature(point.Position + offset)
					if model then
						table.insert(run.spawnedCreatures, model)
					end
				end
			end
		end

		task.wait(BL_SPAWN_INTERVAL)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════════════════
local eventsFolder = nil

-- Queue: list of player references waiting to enter
local queue = {}

-- Active run state (nil when no run is happening, one run at a time in V1)
local activeRun = nil

-- Creature captured from world but not yet placed in bag (player must choose slot / replace)
local pendingBadlandsCapture = {} -- [userId] = entry table
--[[
activeRun = {
	runId        = string,
	startTime    = number (os.clock),
	phase        = "active" | "extraction" | "collapsing" | "ended",
	players      = { [userId] = playerState },
	lootBags     = { [bagId] = lootBagData },
	spawnedCreatures = { Model[] },
	extractionActive = false,
	zoneState    = { outer = false, mid = false, inner = false },
}

playerState = {
	player        = Player,
	alive         = true,
	bag           = { slots = {}, activeIndex = nil, capacity = BAG_SLOTS },
	runPower      = { level = 1, xp = 0 },
	savedCFrame   = CFrame,
	shieldExpiry  = number (os.clock),
	kills         = 0,
	captures      = 0,
	extracting    = false,   -- true while channeling extraction
	extractStart  = nil,     -- os.clock when channel started
}
--]]

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Get the Badlands zone folder from workspace
-- Searches for a Part or Folder named "Badlands" in workspace.
-- @return Instance|nil — the Badlands container
-- ═══════════════════════════════════════════════════════════════════════════════
local function getBadlandsZone()
	return Workspace:FindFirstChild("Badlands")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Find all spawn points in the Badlands zone
-- Priority:
--   1) Parts named SpawnPoint1..SpawnPointN (anywhere under Badlands)
--   2) Children of folder "SpawnPoints" (any BasePart, or Model with PrimaryPart)
--   3) Parts named exactly "SpawnPoint" (same convention as world CreatureSpawner)
--   4) SpawnLocation instances
-- @return { { part = BasePart, index = number }[] } — sorted / stable order
-- ═══════════════════════════════════════════════════════════════════════════════
local function getSpawnPoints()
	local zone = getBadlandsZone()
	if not zone then return {} end

	local points = {}
	for _, desc in ipairs(zone:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:match("^SpawnPoint%d+$") then
			local idx = tonumber(desc.Name:match("^SpawnPoint(%d+)$"))
			if idx then
				table.insert(points, { part = desc, index = idx })
			end
		end
	end
	table.sort(points, function(a, b) return a.index < b.index end)
	if #points > 0 then
		return points
	end

	local spawnFolder = zone:FindFirstChild("SpawnPoints", true)
	if spawnFolder and spawnFolder:IsA("Folder") then
		local idx = 0
		for _, ch in ipairs(spawnFolder:GetChildren()) do
			if ch:IsA("BasePart") then
				idx = idx + 1
				table.insert(points, { part = ch, index = idx })
			elseif ch:IsA("Model") then
				local pp = ch.PrimaryPart or ch:FindFirstChildWhichIsA("BasePart", true)
				if pp then
					idx = idx + 1
					table.insert(points, { part = pp, index = idx })
				end
			end
		end
	end
	if #points > 0 then
		return points
	end

	for _, desc in ipairs(zone:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "SpawnPoint" then
			table.insert(points, { part = desc, index = #points + 1 })
		end
	end
	if #points > 0 then
		return points
	end

	for _, desc in ipairs(zone:GetDescendants()) do
		if desc:IsA("SpawnLocation") then
			table.insert(points, { part = desc, index = #points + 1 })
		end
	end

	return points
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Find extraction points in the Badlands zone
-- @return BasePart[] — array of extraction point parts
-- ═══════════════════════════════════════════════════════════════════════════════
local function getExtractionPoints()
	local zone = getBadlandsZone()
	if not zone then return {} end

	local points = {}
	for _, desc in ipairs(zone:GetDescendants()) do
		if desc:IsA("BasePart") and (desc.Name:match("^ExtractPoint%d+$") or desc.Name:match("^ExtractionPoint%d+$")) then
			table.insert(points, desc)
		end
	end
	return points
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Get the Badlands center reference point
-- @return Vector3 — center position (fallback to origin if not found)
-- ═══════════════════════════════════════════════════════════════════════════════
local function getBadlandsCenter()
	local zone = getBadlandsZone()
	if not zone then return Vector3.new(0, 0, 0) end
	local center = zone:FindFirstChild("BadlandsCenter", true)
	if center and center:IsA("BasePart") then
		return center.Position
	end
	-- Fallback: average of spawn points
	local pts = getSpawnPoints()
	if #pts > 0 then
		local sum = Vector3.zero
		for _, p in ipairs(pts) do sum = sum + p.part.Position end
		return sum / #pts
	end
	return zone:GetPivot().Position
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Generate a unique run ID
-- ═══════════════════════════════════════════════════════════════════════════════
local function generateRunId()
	return "bl_" .. os.date("%Y%m%d") .. "_" .. HttpService:GenerateGUID(false):sub(1, 8)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Create an empty Badlands bag for a player
-- @return table — bag data structure
-- ═══════════════════════════════════════════════════════════════════════════════
local function createEmptyBag()
	return {
		slots = {},
		activeIndex = nil,
		capacity = BAG_SLOTS,
	}
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Create default run power state
-- @return table — run power data
-- ═══════════════════════════════════════════════════════════════════════════════
local function createRunPower()
	return {
		level = 1,
		xp = 0,
		statBoosts = { Health = 0, Attack = 0, Defense = 0, MovementSpeed = 0 },
	}
end

local SACRIFICE_STAT_BOOST = GameConfig.BadlandsSacrificeStatBoost or 5
local BONUS_BUFF_AMOUNT = GameConfig.BadlandsBonusBuffAmount or 10

local function getBagCount(bag)
	local count = 0
	if not bag or not bag.slots then return 0 end
	local cap = bag.capacity or BAG_SLOTS
	for i = 1, cap do
		local c = bag.slots[i]
		if c and c.id then
			count = count + 1
		end
	end
	return count
end

local function findFirstEmptyBagSlot(bag)
	if not bag or not bag.slots then return nil end
	for i = 1, bag.capacity do
		local s = bag.slots[i]
		if not (s and s.id) then
			return i
		end
	end
	return nil
end

local function extractBagEntryFromCreatureModel(creatureModel)
	if not creatureModel then return nil end
	local creatureId = creatureModel:GetAttribute("CreatureId")
	if not creatureId then return nil end
	if not CreatureData.GetById(creatureId) then return nil end
	return {
		id = creatureId,
		uid = creatureModel:GetAttribute("UniqueId") or HttpService:GenerateGUID(false),
		level = creatureModel:GetAttribute("Level") or 1,
		xp = creatureModel:GetAttribute("XP") or 0,
		variant = creatureModel:GetAttribute("Variant") or "Normal",
		capturedAt = os.clock(),
	}
end

local function serializeBagForClient(bag)
	local payload = {
		slots = {},
		activeIndex = bag and bag.activeIndex or nil,
		capacity = bag and bag.capacity or BAG_SLOTS,
		count = getBagCount(bag),
	}

	for slotIndex = 1, payload.capacity do
		local creature = bag and bag.slots and bag.slots[slotIndex] or nil
		if creature and creature.id then
			local info = CreatureData.GetById(creature.id)
			payload.slots[slotIndex] = {
				slot = slotIndex,
				id = creature.id,
				uid = creature.uid,
				displayName = info and info.displayName or creature.id,
				level = creature.level or 1,
				xp = creature.xp or 0,
				variant = creature.variant or "Normal",
				rarity = info and info.rarity or "Common",
				element = info and info.element or "Unknown",
				active = bag.activeIndex == slotIndex,
			}
		else
			payload.slots[slotIndex] = {
				slot = slotIndex,
				empty = true,
				active = bag and bag.activeIndex == slotIndex or false,
			}
		end
	end

	return payload
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Fire a RemoteEvent safely
-- ═══════════════════════════════════════════════════════════════════════════════
local function fireClient(eventName, player, ...)
	if not eventsFolder then return end
	local evt = eventsFolder:FindFirstChild(eventName)
	if evt and player and player.Parent then
		evt:FireClient(player, ...)
	end
end

local function fireAllRunClients(eventName, ...)
	if not activeRun then return end
	for _, ps in pairs(activeRun.players) do
		if ps.player and ps.player.Parent then
			fireClient(eventName, ps.player, ...)
		end
	end
end

local function pushBagUpdate(player, bag, reason)
	fireClient("BadlandsBagUpdate", player, {
		reason = reason or "update",
		bag = serializeBagForClient(bag),
	})
end

local function resolvePendingBadlandsCapture(player, mode, replaceSlotIndex)
	local userId = player.UserId
	local entry = pendingBadlandsCapture[userId]
	if not entry then
		return false, "No pending capture."
	end
	if not activeRun then
		pendingBadlandsCapture[userId] = nil
		return false, "No active Badlands run."
	end
	local ps = activeRun.players[userId]
	if not ps or not ps.alive or not ps.bag then
		pendingBadlandsCapture[userId] = nil
		return false, "You are not active in the Badlands."
	end
	local bag = ps.bag
	mode = type(mode) == "string" and string.lower(mode) or ""

	if mode == "cancel" then
		pendingBadlandsCapture[userId] = nil
		return true, "Capture abandoned."
	end

	if mode == "replace" or mode == "replaceslot" then
		local slotIndex = tonumber(replaceSlotIndex)
		if not slotIndex or slotIndex < 1 or slotIndex > bag.capacity then
			return false, "Pick a valid bag slot."
		end
		local old = bag.slots[slotIndex]
		if not (old and old.id) then
			return false, "That bag slot is empty."
		end
		bag.slots[slotIndex] = entry
		pendingBadlandsCapture[userId] = nil
		ps.captures = (ps.captures or 0) + 1
		pushBagUpdate(player, bag, "capture_replace")
		return true, "Creature swapped into your bag."
	end

	if mode == "active" or mode == "passive" then
		local dest = findFirstEmptyBagSlot(bag)
		if not dest then
			return false, "Your bag is full. Replace a slot instead."
		end
		bag.slots[dest] = entry
		if mode == "active" then
			bag.activeIndex = dest
		end
		pendingBadlandsCapture[userId] = nil
		ps.captures = (ps.captures or 0) + 1
		pushBagUpdate(player, bag, "capture")
		return true, mode == "active" and "Set as active creature." or "Added to your bag."
	end

	return false, "Invalid choice."
end

--- Apply pending capture before extraction so the creature is not lost (passive add or replace active slot).
local function tryApplyPendingBeforeExtract(player)
	local userId = player.UserId
	local entry = pendingBadlandsCapture[userId]
	if not entry then return end
	if not activeRun then pendingBadlandsCapture[userId] = nil return end
	local ps = activeRun.players[userId]
	if not ps or not ps.bag then pendingBadlandsCapture[userId] = nil return end
	local bag = ps.bag
	local dest = findFirstEmptyBagSlot(bag)
	if dest then
		bag.slots[dest] = entry
		if not bag.activeIndex then bag.activeIndex = dest end
	else
		local ai = bag.activeIndex or 1
		bag.slots[ai] = entry
	end
	pendingBadlandsCapture[userId] = nil
	ps.captures = (ps.captures or 0) + 1
	pushBagUpdate(player, bag, "capture_flush")
end

local function captureCreatureToBag(player, creatureModel)
	if not activeRun then
		return false, "No active Badlands run."
	end

	local ps = activeRun.players[player.UserId]
	if not ps or not ps.alive then
		return false, "You are not active in the Badlands."
	end

	local bag = ps.bag
	if not bag then
		return false, "Badlands bag unavailable."
	end

	local userId = player.UserId
	if pendingBadlandsCapture[userId] then
		return false, "You already have a capture to assign. Use the prompt first."
	end

	local entry = extractBagEntryFromCreatureModel(creatureModel)
	if not entry then
		return false, "Unknown Badlands creature."
	end

	local info = CreatureData.GetById(entry.id)

	if creatureModel and creatureModel.Parent then
		pcall(function()
			creatureModel:Destroy()
		end)
	end

	local firstEmpty = findFirstEmptyBagSlot(bag)
	local bagFull = firstEmpty == nil

	pendingBadlandsCapture[userId] = entry

	local bagPayload = serializeBagForClient(bag)

	return true, bagFull and "Bag full — replace a slot." or "Choose how to add this creature.", {
		badlandsPending = true,
		bagFull = bagFull,
		creatureId = entry.id,
		uid = entry.uid,
		slotIndex = nil,
		activeIndex = bag.activeIndex,
		bagCount = getBagCount(bag),
		bagMax = bag.capacity,
		bag = bagPayload,
	}
end

local function refreshPilotWorldStats(player)
	if not player or not player.Parent then
		return
	end
	if PlayerDataManager and PlayerDataManager.ApplyWorldStatsToCharacter then
		pcall(function()
			PlayerDataManager.ApplyWorldStatsToCharacter(player)
		end)
	end
end

local function sacrificeCreatureFromBag(player, slotIndex, statChoice)
	if not activeRun then
		return false, "No active Badlands run."
	end

	local ps = activeRun.players[player.UserId]
	if not ps or not ps.alive then
		return false, "You are not active in the Badlands."
	end

	slotIndex = tonumber(slotIndex)
	if not slotIndex then
		return false, "Invalid slot."
	end

	local validStats = { Health = true, Attack = true, Defense = true, MovementSpeed = true }
	if not (statChoice and validStats[statChoice]) then
		return false, "Choose Health, Attack, Defense, or MovementSpeed."
	end

	local slot = ps.bag and ps.bag.slots and ps.bag.slots[slotIndex]
	if not (slot and slot.id) then
		return false, "That slot is empty."
	end

	-- Cannot sacrifice the active/favorite creature
	if ps.bag.activeIndex == slotIndex then
		return false, "Cannot sacrifice your active Badlands creature. Switch active first."
	end

	-- Remove creature from bag
	ps.bag.slots[slotIndex] = nil

	-- Apply stat boost to run power
	ps.runPower.statBoosts = ps.runPower.statBoosts or { Health = 0, Attack = 0, Defense = 0, MovementSpeed = 0 }
	ps.runPower.statBoosts[statChoice] = (ps.runPower.statBoosts[statChoice] or 0) + SACRIFICE_STAT_BOOST

	-- Persist stat boosts to player attribute for combat/other systems
	local key = "BadlandsStat_" .. statChoice
	local current = player:GetAttribute(key) or 0
	player:SetAttribute(key, current + SACRIFICE_STAT_BOOST)

	refreshPilotWorldStats(player)

	pushBagUpdate(player, ps.bag, "sacrifice")

	local info = CreatureData.GetById(slot.id)
	local displayName = info and info.displayName or slot.id
	print("[Badlands] " .. player.Name .. " sacrificed " .. displayName .. " for +" .. SACRIFICE_STAT_BOOST .. " " .. statChoice)

	return true, ("Sacrificed %s for +%d %s."):format(displayName, SACRIFICE_STAT_BOOST, statChoice)
end

local function switchActiveBagSlot(player, slotIndex)
	if not activeRun then
		return false, "No active Badlands run."
	end

	local ps = activeRun.players[player.UserId]
	if not ps or not ps.alive then
		return false, "You are not active in the Badlands."
	end

	slotIndex = tonumber(slotIndex)
	if not slotIndex then
		return false, "Invalid slot."
	end

	local slot = ps.bag and ps.bag.slots and ps.bag.slots[slotIndex]
	if not (slot and slot.id) then
		return false, "That slot is empty."
	end

	ps.bag.activeIndex = slotIndex
	pushBagUpdate(player, ps.bag, "switch")
	return true, "Active Badlands creature switched."
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Suppress normal gameplay systems for a Badlands player
-- Despawns companion, dismounts, marks player as in Badlands.
--
-- @param player Player
-- @param savedCFrame CFrame — where to return the player after the run
-- ═══════════════════════════════════════════════════════════════════════════════
local BADLANDS_LOADING_DURATION = GameConfig.BadlandsLoadingDuration or 5

local function enterBadlandsMode(player, savedCFrame)
	player:SetAttribute("InBadlands", true)
	player:SetAttribute("BadlandsLoading", true)  -- blocks points/activities until cleared
	player:SetAttribute("BadlandsSpawnShield", true)

	-- Clear loading phase after delay so player can interact
	task.delay(BADLANDS_LOADING_DURATION, function()
		if player and player.Parent then
			player:SetAttribute("BadlandsLoading", nil)
		end
	end)

	-- Dismount if mounted
	if MountSystem and MountSystem.Dismount then
		pcall(function() MountSystem.Dismount(player) end)
	end

	-- Save favorite UID and clear it so player cannot summon base sieglings in Badlands
	if PlayerDataManager then
		local data = PlayerDataManager.GetData(player)
		if data and data.favoriteUid then
			player:SetAttribute("BadlandsSavedFavoriteUid", tostring(data.favoriteUid))
			pcall(function() PlayerDataManager.ClearFavorite(player) end)
		end
	end

	-- Despawn companion
	if FavoriteCreatureSystem and FavoriteCreatureSystem.DespawnCompanion then
		pcall(function() FavoriteCreatureSystem.DespawnCompanion(player) end)
		-- Second pass: character/teleport races can recreate a favorite model a frame later
		task.delay(0.2, function()
			if player and player.Parent and player:GetAttribute("InBadlands") == true
				and FavoriteCreatureSystem and FavoriteCreatureSystem.DespawnCompanion then
				pcall(function() FavoriteCreatureSystem.DespawnCompanion(player) end)
			end
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Restore normal gameplay for a player leaving The Badlands
--
-- @param player Player
-- @param savedCFrame CFrame — teleport destination
-- ═══════════════════════════════════════════════════════════════════════════════
local function exitBadlandsMode(player, savedCFrame)
	player:SetAttribute("InBadlands", nil)
	player:SetAttribute("BadlandsLoading", nil)
	player:SetAttribute("BadlandsSpawnShield", nil)
	player:SetAttribute("BadlandsPowerLevel", nil)
	player:SetAttribute("BadlandsRunId", nil)
	player:SetAttribute("BadlandsBonusBuff", nil)
	player:SetAttribute("BadlandsStat_Health", nil)
	player:SetAttribute("BadlandsStat_Attack", nil)
	player:SetAttribute("BadlandsStat_Defense", nil)
	player:SetAttribute("BadlandsStat_MovementSpeed", nil)

	-- Teleport back to saved position
	if player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if root and savedCFrame then
			root.CFrame = savedCFrame
		end
	end

	-- Restore saved favorite from before entering Badlands
	local savedFavUid = player:GetAttribute("BadlandsSavedFavoriteUid")
	player:SetAttribute("BadlandsSavedFavoriteUid", nil)
	if savedFavUid and savedFavUid ~= "" and PlayerDataManager then
		pcall(function() PlayerDataManager.SetFavorite(player, savedFavUid) end)
	end

	-- Re-summon companion (if the character is dead, e.g. Badlands elimination, wait for respawn)
	if FavoriteCreatureSystem and FavoriteCreatureSystem.SpawnCompanion then
		local function trySpawnCompanion()
			if not (player and player.Parent) then return end
			pcall(function() FavoriteCreatureSystem.SpawnCompanion(player) end)
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			trySpawnCompanion()
		elseif player.Parent then
			player.CharacterAdded:Once(function()
				task.defer(trySpawnCompanion)
			end)
		end
	end

	refreshPilotWorldStats(player)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Teleport a player to a spawn point
-- Places the player on top of the spawn part, preserving the part's rotation.
-- If Character / HumanoidRootPart is not ready yet, waits briefly (run start race).
--
-- @param player    Player
-- @param spawnPart BasePart — the SpawnPoint part
-- ═══════════════════════════════════════════════════════════════════════════════
local function teleportToSpawnPoint(player, spawnPart)
	if not spawnPart or not spawnPart.Parent or not player.Parent then
		return
	end

	local yOffset = 3 + (spawnPart.Size.Y * 0.5)
	local targetCF = spawnPart.CFrame * CFrame.new(0, yOffset, 0)

	local applied = false
	local function apply()
		if applied or not spawnPart.Parent or not player.Parent then
			return true
		end
		local char = player.Character
		if not char then
			return false
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then
			return false
		end
		applied = true
		root.CFrame = targetCF
		print("[Badlands] Teleported " .. player.Name .. " to " .. spawnPart.Name
			.. " at " .. tostring(root.Position))
		return true
	end

	if apply() then
		return
	end

	if player.Character then
		task.spawn(function()
			local char = player.Character
			if char then
				char:WaitForChild("HumanoidRootPart", 12)
			end
			apply()
		end)
	else
		player.CharacterAdded:Once(function()
			task.defer(function()
				local char = player.Character
				if char then
					char:WaitForChild("HumanoidRootPart", 12)
				end
				apply()
			end)
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Assign spawn points to players (spread out, no two adjacent)
-- Uses a shuffled set of spawn points so players are distributed.
--
-- @param playerList Player[] — array of players entering the run
-- @return { [Player] = BasePart } — mapping of player to spawn point
-- ═══════════════════════════════════════════════════════════════════════════════
local function assignSpawnPoints(playerList)
	-- Players should always enter at dedicated SpawnPoints.
	-- Extraction points are gameplay objectives and are not reliable entry spawns.
	local points = {}
	local sp = getSpawnPoints()
	for _, p in ipairs(sp) do
		table.insert(points, p.part)
	end
	if #points == 0 then
		-- Last-resort fallback for maps that only have extraction markers configured.
		points = getExtractionPoints()
		if #points > 0 then
			warn("[Badlands] No SpawnPoints found; falling back to ExtractionPoints for entry teleports")
		end
	end
	if #points == 0 then
		warn("[Badlands] No spawn locations found at all!")
		return {}
	end

	-- Shuffle for randomness
	for i = #points, 2, -1 do
		local j = math.random(1, i)
		points[i], points[j] = points[j], points[i]
	end

	local assignments = {}
	for i, player in ipairs(playerList) do
		assignments[player] = points[((i - 1) % #points) + 1]
	end

	return assignments
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- eliminatePlayer(userId, reason)
-- Handles a player death/elimination in The Badlands.
-- Drops their bag as a loot bag, teleports them out, fires results.
--
-- @param userId number
-- @param reason string — "killed", "collapse", "timeout"
-- ═══════════════════════════════════════════════════════════════════════════════
local function eliminatePlayer(userId, reason)
	if not activeRun then return end
	local ps = activeRun.players[userId]
	if not ps or not ps.alive then return end

	pendingBadlandsCapture[userId] = nil -- unpicked capture is lost on elimination

	ps.alive = false

	-- Snapshot bag for results UI, then clear server bag (loss — same as design: lose everything)
	local bagSnapshot = {}
	local cap = (ps.bag and ps.bag.capacity) or BAG_SLOTS
	for i = 1, cap do
		local c = ps.bag.slots[i]
		if c then bagSnapshot[i] = c end
	end
	ps.bag = createEmptyBag()
	if ps.player and ps.player.Parent then
		pushBagUpdate(ps.player, ps.bag, "eliminated")
	end

	-- Fire elimination event to the player
	fireClient("BadlandsEliminated", ps.player, {
		reason = reason,
		kills = ps.kills,
		captures = ps.captures,
		powerLevel = ps.runPower.level,
		bagContents = bagSnapshot,
	})

	-- Clear InBadlands and restore base Siegeling flow immediately (UI keys off the attribute)
	if ps.player and ps.player.Parent then
		exitBadlandsMode(ps.player, ps.savedCFrame)
	end

	-- Announce kill feed to remaining players
	fireAllRunClients("BadlandsPlayerKill", {
		eliminatedName = ps.player and ps.player.Name or "Unknown",
		reason = reason,
		playersRemaining = 0, -- computed below
	})

	-- Count remaining alive
	local aliveCount = 0
	for _, p in pairs(activeRun.players) do
		if p.alive then aliveCount = aliveCount + 1 end
	end

	-- Update remaining count in the kill feed
	fireAllRunClients("BadlandsTimerSync", {
		elapsed = os.clock() - activeRun.startTime,
		phase = activeRun.phase,
		playersAlive = aliveCount,
	})

	-- If no players remain, end the run
	if aliveCount == 0 then
		activeRun.phase = "ended"
	end

	print("[Badlands] " .. (ps.player and ps.player.Name or "?") .. " eliminated ("
		.. reason .. ") — " .. aliveCount .. " players remaining")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Character death while InBadlands: run full elimination (was only wired on disconnect)
-- ═══════════════════════════════════════════════════════════════════════════════
local function hookBadlandsCharacterDeath(player)
	local function onCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 20)
		if not humanoid or not humanoid:IsA("Humanoid") then return end
		humanoid.Died:Connect(function()
			if not activeRun then return end
			if player:GetAttribute("InBadlands") ~= true then return end
			local ps = activeRun.players[player.UserId]
			if not ps or not ps.alive then return end
			eliminatePlayer(player.UserId, "killed")
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.defer(onCharacter, player.Character)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- expelPlayer(userId)
-- Called when the hard deadline (10 minutes) expires. The player is kicked out
-- of The Badlands but gets to keep ONLY their currently equipped favorite
-- creature from the Badlands bag. Everything else in the bag is lost.
--
-- This is NOT the same as elimination (death → lose everything) or extraction
-- (channel → keep everything). It's a middle ground: you ran out of time, but
-- you don't walk away completely empty-handed if you had a favorite equipped.
--
-- @param userId number
-- ═══════════════════════════════════════════════════════════════════════════════
local function expelPlayer(userId)
	if not activeRun then return end
	local ps = activeRun.players[userId]
	if not ps or not ps.alive then return end

	tryApplyPendingBeforeExtract(ps.player)

	ps.alive = false
	ps.extracting = false

	-- Transfer ONLY the equipped favorite creature (activeIndex) to main inventory
	local keptCreature = nil
	if ps.bag.activeIndex and ps.bag.slots[ps.bag.activeIndex] then
		local creature = ps.bag.slots[ps.bag.activeIndex]
		if creature and creature.id then
			local uid = nil
			if PlayerDataManager and PlayerDataManager.AddCreature then
				uid = PlayerDataManager.AddCreature(
					ps.player, creature.id, creature.level or 1,
					creature.xp or 0, creature.variant or "Normal", creature.uid
				)
			end
			keptCreature = {
				id = creature.id,
				level = creature.level or 1,
				variant = creature.variant or "Normal",
				uid = uid,
			}
		end
	end

	-- Count what was lost (everything except the kept creature)
	local lostCount = 0
	for i, slot in ipairs(ps.bag.slots) do
		if slot and slot.id and i ~= ps.bag.activeIndex then
			lostCount = lostCount + 1
		end
	end

	-- Fire expulsion event to the player
	fireClient("BadlandsRunEnd", ps.player, {
		reason = "timeout",
		keptCreature = keptCreature,
		lostCount = lostCount,
		kills = ps.kills,
		captures = ps.captures,
		powerLevel = ps.runPower.level,
		bagContents = ps.bag.slots,
	})

	-- Teleport out
	task.delay(3, function()
		if ps.player and ps.player.Parent then
			exitBadlandsMode(ps.player, ps.savedCFrame)
		end
	end)

	local playerName = ps.player and ps.player.Name or "?"
	local keptStr = keptCreature and (keptCreature.id .. " Lv" .. keptCreature.level) or "nothing"
	print("[Badlands] " .. playerName .. " EXPELLED (timeout) — kept: " .. keptStr
		.. ", lost: " .. lostCount .. " creatures")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- extractPlayer(userId)
-- Handles a successful extraction. Transfers bag contents to main inventory.
--
-- @param userId number
-- ═══════════════════════════════════════════════════════════════════════════════
local function extractPlayer(userId)
	if not activeRun then return end
	local ps = activeRun.players[userId]
	if not ps or not ps.alive then return end

	tryApplyPendingBeforeExtract(ps.player)

	ps.alive = false
	ps.extracting = false

	-- Transfer bag contents to main inventory
	local transferred = {}
	for _, creature in ipairs(ps.bag.slots) do
		if creature and creature.id then
			local uid = nil
			if PlayerDataManager and PlayerDataManager.AddCreature then
				uid = PlayerDataManager.AddCreature(
					ps.player, creature.id, creature.level or 1,
					creature.xp or 0, creature.variant or "Normal", creature.uid
				)
			end
			table.insert(transferred, {
				id = creature.id,
				level = creature.level or 1,
				variant = creature.variant or "Normal",
				uid = uid,
			})
		end
	end

	-- SiegeLord sigil: first successful extraction grants the Badlands SiegeLord entry (Profile Sigils tab)
	local siegeLordZone = GameConfig.SiegeLordSigilZoneId or "Badlands"
	if PlayerDataManager and PlayerDataManager.HasSigil and PlayerDataManager.AddSigil then
		if not PlayerDataManager.HasSigil(ps.player, siegeLordZone) then
			PlayerDataManager.AddSigil(ps.player, siegeLordZone)
			-- Persist immediately: extraction is a milestone moment; don't rely on 120s auto-save.
			if PlayerDataManager.SavePlayer then
				pcall(function() PlayerDataManager.SavePlayer(ps.player) end)
			end
			local sigilEvt = eventsFolder and eventsFolder:FindFirstChild("SigilEarned")
			if sigilEvt then
				sigilEvt:FireClient(ps.player, siegeLordZone)
			end
		end
	end

	-- Fire extraction success
	fireClient("BadlandsExtracted", ps.player, {
		creatures = transferred,
		kills = ps.kills,
		captures = ps.captures,
		powerLevel = ps.runPower.level,
	})

	-- Teleport out
	task.delay(2, function()
		if ps.player and ps.player.Parent then
			exitBadlandsMode(ps.player, ps.savedCFrame)
		end
	end)

	print("[Badlands] " .. ps.player.Name .. " EXTRACTED with " .. #transferred .. " creatures!")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- startRun(playerList)
-- Begins a Badlands run with the given list of players.
-- Teleports all players, initializes state, starts the run timer.
--
-- @param playerList Player[] — array of 4-8 players
-- ═══════════════════════════════════════════════════════════════════════════════
local function startRun(playerList)
	local zone = getBadlandsZone()
	if not zone then
		warn("[Badlands] Cannot start run — workspace.Badlands not found")
		for _, p in ipairs(playerList) do
			fireClient("BadlandsQueueReject", p, "The Badlands zone is not available right now.")
		end
		return
	end

	-- If a run is already active, add the new player(s) to the existing run
	-- instead of blocking them. The Badlands is a shared open zone — any player
	-- can enter at any time via The Broker.
	if activeRun and (activeRun.phase == "active" or activeRun.phase == "extraction") then
		local assignments = assignSpawnPoints(playerList)
		for _, player in ipairs(playerList) do
			if not player.Parent then continue end
			if activeRun.players[player.UserId] then continue end -- already in

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local savedCFrame = root and root.CFrame or CFrame.new(0, 50, 0)

			enterBadlandsMode(player, savedCFrame)
			player:SetAttribute("BadlandsRunId", activeRun.runId)
			player:SetAttribute("BadlandsPowerLevel", 1)

			local rp = createRunPower()
			if player:GetAttribute("BadlandsBonusBuff") then
				rp.statBoosts.Health = rp.statBoosts.Health + BONUS_BUFF_AMOUNT
				rp.statBoosts.Attack = rp.statBoosts.Attack + BONUS_BUFF_AMOUNT
				rp.statBoosts.Defense = rp.statBoosts.Defense + BONUS_BUFF_AMOUNT
				rp.statBoosts.MovementSpeed = rp.statBoosts.MovementSpeed + BONUS_BUFF_AMOUNT
				player:SetAttribute("BadlandsBonusBuff", nil)
				player:SetAttribute("BadlandsStat_Health", rp.statBoosts.Health)
				player:SetAttribute("BadlandsStat_Attack", rp.statBoosts.Attack)
				player:SetAttribute("BadlandsStat_Defense", rp.statBoosts.Defense)
				player:SetAttribute("BadlandsStat_MovementSpeed", rp.statBoosts.MovementSpeed)
				print("[Badlands] Bonus buffs applied to " .. player.Name .. " (+" .. BONUS_BUFF_AMOUNT .. " all stats)")
			end

			refreshPilotWorldStats(player)

			activeRun.players[player.UserId] = {
				player = player,
				alive = true,
				bag = createEmptyBag(),
				runPower = rp,
				savedCFrame = savedCFrame,
				shieldExpiry = os.clock() + SPAWN_SHIELD_DURATION,
				kills = 0,
				captures = 0,
				extracting = false,
				extractStart = nil,
			}
			pushBagUpdate(player, activeRun.players[player.UserId].bag, "run_start")

			local spawnPart = assignments[player]
			if spawnPart then
				teleportToSpawnPoint(player, spawnPart)
			else
				local allPoints = getSpawnPoints()
				if #allPoints > 0 and allPoints[1].part then
					warn("[Badlands] No assigned spawn for " .. player.Name .. " (late join) — using SpawnPoints[1] fallback")
					teleportToSpawnPoint(player, allPoints[1].part)
				else
					warn("[Badlands] No spawn point assigned for " .. player.Name)
				end
			end

			-- Notify the joining player
			local elapsed = os.clock() - activeRun.startTime
			local remaining = math.max(0, RUN_DURATION - elapsed)
			fireClient("BadlandsRunStart", player, {
				runId = activeRun.runId,
				playerCount = 0, -- they'll discover others in-world
				timeRemaining = remaining,
				lateJoin = true,
			})

			print("[Badlands] " .. player.Name .. " joined active run (late join, " .. math.floor(remaining) .. "s remaining)")
		end
		return
	end

	local runId = generateRunId()

	-- Build run state
	activeRun = {
		runId = runId,
		startTime = os.clock(),
		phase = "active",
		players = {},
		lootBags = {},
		spawnedCreatures = {},
		extractionActive = false,
		zoneState = { outer = false, mid = false, inner = false },
	}

	-- Set workspace attributes
	zone:SetAttribute("BadlandsRunActive", true)
	zone:SetAttribute("BadlandsRunId", runId)

	-- Assign spawn points
	local assignments = assignSpawnPoints(playerList)

	-- Initialize each player
	for _, player in ipairs(playerList) do
		if not player.Parent then continue end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local savedCFrame = root and root.CFrame or CFrame.new(0, 50, 0)

		-- Enter Badlands mode (suppress companion, dismount, mark attributes)
		enterBadlandsMode(player, savedCFrame)
		player:SetAttribute("BadlandsRunId", runId)
		player:SetAttribute("BadlandsPowerLevel", 1)

		-- Build player state
		local rp = createRunPower()

		-- Apply bonus buffs if the player sacrificed the Broker's bonus creature
		if player:GetAttribute("BadlandsBonusBuff") then
			rp.statBoosts.Health = rp.statBoosts.Health + BONUS_BUFF_AMOUNT
			rp.statBoosts.Attack = rp.statBoosts.Attack + BONUS_BUFF_AMOUNT
			rp.statBoosts.Defense = rp.statBoosts.Defense + BONUS_BUFF_AMOUNT
			rp.statBoosts.MovementSpeed = rp.statBoosts.MovementSpeed + BONUS_BUFF_AMOUNT
			player:SetAttribute("BadlandsBonusBuff", nil)
			player:SetAttribute("BadlandsStat_Health", rp.statBoosts.Health)
			player:SetAttribute("BadlandsStat_Attack", rp.statBoosts.Attack)
			player:SetAttribute("BadlandsStat_Defense", rp.statBoosts.Defense)
			player:SetAttribute("BadlandsStat_MovementSpeed", rp.statBoosts.MovementSpeed)
			print("[Badlands] Bonus buffs applied to " .. player.Name .. " (+" .. BONUS_BUFF_AMOUNT .. " all stats)")
		end

		refreshPilotWorldStats(player)

		activeRun.players[player.UserId] = {
			player = player,
			alive = true,
			bag = createEmptyBag(),
			runPower = rp,
			savedCFrame = savedCFrame,
			shieldExpiry = os.clock() + SPAWN_SHIELD_DURATION,
			kills = 0,
			captures = 0,
			extracting = false,
			extractStart = nil,
		}
		pushBagUpdate(player, activeRun.players[player.UserId].bag, "run_start")

		-- Teleport to assigned spawn point
		local spawnPart = assignments[player]
		if spawnPart then
			teleportToSpawnPoint(player, spawnPart)
		else
			-- Hard fallback: if assignment fails, force-teleport to first available point.
			local allPoints = getSpawnPoints()
			if #allPoints > 0 and allPoints[1].part then
				warn("[Badlands] No assigned spawn for " .. player.Name .. " — using SpawnPoints[1] fallback")
				teleportToSpawnPoint(player, allPoints[1].part)
			else
				warn("[Badlands] No spawn point assigned for " .. player.Name)
			end
		end
	end

	-- Fire run start event to all participants
	local playerNames = {}
	for _, p in ipairs(playerList) do table.insert(playerNames, p.Name) end

	fireAllRunClients("BadlandsRunStart", {
		runId = runId,
		playerNames = playerNames,
		playerCount = #playerList,
		runDuration = RUN_DURATION,
		hardDeadline = HARD_DEADLINE,
		extractActivateAt = EXTRACT_ACTIVATE_AT,
		spawnShieldDuration = SPAWN_SHIELD_DURATION,
		bagSlots = BAG_SLOTS,
	})

	print("[Badlands] ═══ RUN STARTED ═══ ID: " .. runId .. " | Players: " .. #playerList)

	-- ── Add ProximityPrompts + visual beacons to extraction points ──────────
	local extractPoints = getExtractionPoints()
	for _, pt in ipairs(extractPoints) do
		-- Only add if not already present
		if not pt:FindFirstChild("ExtractPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "ExtractPrompt"
			prompt.ObjectText = "Extraction Point"
			prompt.ActionText = "Extract"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Parent = pt

			-- Purple beacon glow so players can find extraction points
			local beacon = Instance.new("PointLight")
			beacon.Name = "ExtractBeacon"
			beacon.Color = Color3.fromRGB(100, 255, 100) -- green glow
			beacon.Brightness = 4
			beacon.Range = 30
			beacon.Parent = pt

			-- Vertical beam (pillar of light)
			local beam = Instance.new("Part")
			beam.Name = "ExtractBeam"
			beam.Size = Vector3.new(2, 60, 2)
			beam.Position = pt.Position + Vector3.new(0, 30, 0)
			beam.Anchored = true
			beam.CanCollide = false
			beam.CanQuery = false
			beam.CanTouch = false
			beam.Material = Enum.Material.Neon
			beam.Color = Color3.fromRGB(80, 255, 80)
			beam.Transparency = 0.6
			beam.CastShadow = false
			beam.Parent = pt

			prompt.Triggered:Connect(function(triggerPlayer)
				-- Fire the extraction start for this player
				if not activeRun then return end
				if not activeRun.extractionActive then return end
				if triggerPlayer:GetAttribute("BadlandsLoading") then return end  -- no interactions during load-in
				local ps = activeRun.players[triggerPlayer.UserId]
				if not ps or not ps.alive then return end
				if ps.extracting then return end -- already channeling

				ps.extracting = true
				ps.extractStart = os.clock()

				-- Send bag contents to the client for the extraction UI
				local bagContents = {}
				for slotIdx, creature in ipairs(ps.bag.slots) do
					if creature and creature.id then
						local info = CreatureData.GetById(creature.id)
						table.insert(bagContents, {
							slot = slotIdx,
							id = creature.id,
							displayName = info and info.displayName or creature.id,
							level = creature.level or 1,
							variant = creature.variant or "Normal",
							rarity = info and info.rarity or "Common",
						})
					end
				end

				-- Tell client to show the extraction UI with bag contents
				fireClient("BadlandsExtractProgress", triggerPlayer, {
					progress = 0,
					remaining = EXTRACTION_TIME,
					channelTime = EXTRACTION_TIME,
					bag = bagContents,
					started = true,
				})

				-- Run extraction channel
				task.spawn(function()
					local channelTime = math.max(
						EXTRACTION_MIN_TIME,
						EXTRACTION_TIME - (ps.runPower.level >= 9 and 5 or ps.runPower.level >= 7 and 3 or 0)
					)
					local startT = os.clock()

					while ps.extracting and ps.alive and (os.clock() - startT) < channelTime do
						local pct = (os.clock() - startT) / channelTime
						fireClient("BadlandsExtractProgress", triggerPlayer, {
							progress = pct,
							remaining = channelTime - (os.clock() - startT),
							channelTime = channelTime,
							bag = bagContents,
						})
						task.wait(0.5)
					end

					if ps.extracting and ps.alive then
						extractPlayer(triggerPlayer.UserId)
					end
				end)
			end)
		end
	end
	print("[Badlands] Added ProximityPrompts to " .. #extractPoints .. " extraction points")

	-- ── Spawn Badlands creatures (initial wave + continuous loop) ────────────
	task.spawn(function()
		task.wait(2) -- brief delay so players land before creatures flood in
		spawnInitialBadlandsCreatures(activeRun)
		badlandsSpawnLoop(activeRun, runId)
	end)

	-- ── Run timer loop ──────────────────────────────────────────────────────
	task.spawn(function()
		while activeRun and activeRun.runId == runId and activeRun.phase ~= "ended" do
			local elapsed = os.clock() - activeRun.startTime

			-- Phase transitions
			if elapsed >= HARD_DEADLINE then
				-- Hard deadline (10 min): expel everyone — they keep ONLY their
				-- equipped favorite creature. Everything else in the bag is lost.
				activeRun.phase = "ended"
				for uid, ps in pairs(activeRun.players) do
					if ps.alive then
						expelPlayer(uid)
					end
				end
				break
			end

			-- Extraction is always available from the start — players can leave
			-- whenever they want. The risk is losing bag contents if they stay
			-- past the hard deadline.
			if not activeRun.extractionActive then
				activeRun.extractionActive = true
				activeRun.phase = "extraction"
				fireAllRunClients("BadlandsExtractActivate", {
					extractionPoints = #getExtractionPoints(),
				})
				print("[Badlands] Extraction points ACTIVATED immediately")
			end

			-- Periodic timer sync to clients (every 5 seconds)
			local aliveCount = 0
			for _, ps in pairs(activeRun.players) do
				if ps.alive then aliveCount = aliveCount + 1 end
			end

			if aliveCount == 0 then
				activeRun.phase = "ended"
				break
			end

			fireAllRunClients("BadlandsTimerSync", {
				elapsed = elapsed,
				remaining = HARD_DEADLINE - elapsed,
				phase = activeRun.phase,
				playersAlive = aliveCount,
				extractionActive = activeRun.extractionActive,
			})

			-- Spawn shield expiry check
			for _, ps in pairs(activeRun.players) do
				if ps.alive and ps.player:GetAttribute("BadlandsSpawnShield") then
					if os.clock() >= ps.shieldExpiry then
						ps.player:SetAttribute("BadlandsSpawnShield", nil)
					end
				end
			end

			task.wait(5)
		end

		-- ── Run ended: cleanup ──────────────────────────────────────────────
		print("[Badlands] ═══ RUN ENDED ═══ ID: " .. runId)

		-- Expel any remaining alive players (safety net — keep only favorite)
		if activeRun and activeRun.runId == runId then
			for uid, ps in pairs(activeRun.players) do
				if ps.alive then
					expelPlayer(uid)
				end
			end

			-- Clean up Badlands creatures
			for _, creature in ipairs(activeRun.spawnedCreatures) do
				if creature and creature.Parent then
					pcall(function() creature:Destroy() end)
				end
			end

			-- Clear workspace attributes
			local z = getBadlandsZone()
			if z then
				z:SetAttribute("BadlandsRunActive", nil)
				z:SetAttribute("BadlandsRunId", nil)
			end

			activeRun = nil
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Queue management
-- ═══════════════════════════════════════════════════════════════════════════════
local queueStartTime = nil

-- ═══════════════════════════════════════════════════════════════════════════════
-- THE BROKER NPC — Daily Contract System
--
-- The Broker is an NPC in the Arena Hub area. Players interact via
-- ProximityPrompt (E key). He generates a daily contract requiring a
-- specific creature sacrifice (rarity + element + min level). The contract
-- rotates daily using a deterministic seed from the date.
--
-- Flow:
--   1. Player presses E → server fires BadlandsContractData to client
--      with today's contract details + qualifying creatures from inventory
--   2. Client shows UI with contract info + creature picker
--   3. Player selects a creature → client fires BadlandsOfferCreature(uid)
--   4. Server validates: creature exists, matches contract, removes it,
--      then adds player to Badlands queue and teleports when run starts
--
-- The Broker NPC model is a simple Part with a BillboardGui (name tag).
-- Future: replace with a full R6/R15 character model.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Daily contract state (regenerated each day)
local dailyContract = nil   -- { rarity, element, minLevel, seed, dateKey }
local brokerNPC = nil       -- reference to the Broker Part in workspace

-- All elements from CreatureData for contract generation
local ALL_ELEMENTS = { "Fire", "Ice", "Wind", "Earth", "Shadow", "Light", "Lightning", "Water", "Psychic", "Metal" }

-- All rarities that the contract can request (Common through Epic; never Legendary)
-- Legendary sacrifice would be too punishing — Epic is the ceiling
local CONTRACT_RARITIES = { "Common", "Uncommon", "Rare", "Epic" }

--- Generate today's daily contract using a deterministic seed from the date.
-- The contract specifies a rarity, element, and minimum level that the
-- sacrificed creature must meet. Rotates daily at midnight (server time).
--
-- @return table — { rarity: string, element: string, minLevel: number,
--                    seed: number, dateKey: string, description: string }
local function generateDailyContract()
	local now = os.date("*t")
	local dateKey = string.format("%04d-%02d-%02d", now.year, now.month, now.day)

	-- Check if we already generated today's contract
	if dailyContract and dailyContract.dateKey == dateKey then
		return dailyContract
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- DEBUG: DebugBrokerCacty — always ask for a Lv1 Common Earth Cacty
	-- Set GameConfig.DebugBrokerCacty = true for easy testing
	-- ═══════════════════════════════════════════════════════════════════
	if GameConfig.DebugBrokerCacty then
		dailyContract = {
			rarity          = "Common",
			element         = "Earth",
			minLevel        = 1,
			seed            = 0,
			dateKey         = dateKey,
			description     = "Bring me a COMMON EARTH Siegeling, at least LEVEL 1.",
			bonusCreatureId   = "cacty",
			bonusCreatureName = "Cacty",
		}
		print("[Badlands] DEBUG: Broker contract forced to Lv1 Common Earth Cacty (" .. dateKey .. ")")
		return dailyContract
	end

	-- Deterministic seed from date (consistent across all servers for the same day)
	local seed = now.year * 10000 + now.month * 100 + now.day
	local rng = Random.new(seed)

	-- Pick a rarity (weighted: Common 10%, Uncommon 30%, Rare 40%, Epic 20%)
	local rarityRoll = rng:NextNumber()
	local rarity
	if rarityRoll < 0.10 then
		rarity = "Common"
	elseif rarityRoll < 0.40 then
		rarity = "Uncommon"
	elseif rarityRoll < 0.80 then
		rarity = "Rare"
	else
		rarity = "Epic"
	end

	-- Pick an element
	local elementIdx = rng:NextInteger(1, #ALL_ELEMENTS)
	local element = ALL_ELEMENTS[elementIdx]

	-- Pick a minimum level (scales with rarity: Common 1-3, Uncommon 3-5, Rare 5-10, Epic 8-15)
	local minLevel
	if rarity == "Common" then
		minLevel = rng:NextInteger(1, 3)
	elseif rarity == "Uncommon" then
		minLevel = rng:NextInteger(3, 5)
	elseif rarity == "Rare" then
		minLevel = rng:NextInteger(5, 10)
	else -- Epic
		minLevel = rng:NextInteger(8, 15)
	end

	-- Pick a specific bonus creature from the matching pool
	local bonusCreatureId, bonusCreatureName = nil, nil
	do
		local candidates = {}
		local allOfRarity = CreatureData.GetCreaturesByRarity(rarity) or {}
		for _, c in ipairs(allOfRarity) do
			if c.element == element
				and not string.find(c.id, "standin")
				and c.modelName and c.modelName ~= "Egg" then
				table.insert(candidates, c)
			end
		end
		if #candidates > 0 then
			local idx = rng:NextInteger(1, #candidates)
			bonusCreatureId = candidates[idx].id
			bonusCreatureName = candidates[idx].displayName
		end
	end

	local description = string.format(
		"Bring me a %s %s Siegeling, at least LEVEL %d.",
		rarity:upper(), element:upper(), minLevel
	)

	dailyContract = {
		rarity            = rarity,
		element           = element,
		minLevel          = minLevel,
		seed              = seed,
		dateKey           = dateKey,
		description       = description,
		bonusCreatureId   = bonusCreatureId,
		bonusCreatureName = bonusCreatureName,
	}

	print("[Badlands] Daily contract generated: " .. rarity .. " " .. element .. " Lv" .. minLevel .. "+ (" .. dateKey .. ")")
	return dailyContract
end

--- Check if a creature entry from inventory matches the daily contract.
-- @param entry table — inventory entry { id, level, variant, uid, ... }
-- @param contract table — daily contract from generateDailyContract()
-- @return boolean, string — matches, reason if not
local function creatureMatchesContract(entry, contract)
	if not entry or not contract then return false, "Invalid data" end

	local info = CreatureData.GetById(entry.id)
	if not info then return false, "Unknown creature" end

	-- Check rarity: must match exactly OR be higher rarity
	local creatureRarityOrder = CreatureData.RarityOrder[info.rarity] or 0
	local contractRarityOrder = CreatureData.RarityOrder[contract.rarity] or 0
	if creatureRarityOrder < contractRarityOrder then
		return false, "Rarity too low (need " .. contract.rarity .. "+)"
	end

	-- Check element
	if info.element ~= contract.element then
		return false, "Wrong element (need " .. contract.element .. ")"
	end

	-- Check level
	local creatureLevel = entry.level or 1
	if creatureLevel < contract.minLevel then
		return false, "Level too low (need Lv" .. contract.minLevel .. "+)"
	end

	return true, "Qualifies"
end

--- Slot placement flags for Broker UI (defense / income / battle).
-- @param data player data table
-- @param uid creature uid
local function getPlacementFlagsForUid(data, uid)
	if not data then return false, false, false end
	local su = tostring(uid or "")
	if su == "" then return false, false, false end
	local onDefense, onIncome, onBattle = false, false, false
	if data.defenseSlots then
		for _, slotUid in pairs(data.defenseSlots) do
			if tostring(slotUid) == su then onDefense = true break end
		end
	end
	if data.baseSlots then
		for _, slotUid in pairs(data.baseSlots) do
			if tostring(slotUid) == su then onIncome = true break end
		end
	end
	if data.battleTeam then
		for _, slotUid in pairs(data.battleTeam) do
			if slotUid and tostring(slotUid) == su then onBattle = true break end
		end
	end
	return onDefense, onIncome, onBattle
end

--- Find all creatures in a player's inventory that match the daily contract.
-- @param player Player
-- @return table[] — array of { uid, id, level, variant, displayName, rarity, onDefense, onIncome, onBattle }
local function findQualifyingCreatures(player)
	if not PlayerDataManager then return {} end

	local contract = generateDailyContract()
	local data = PlayerDataManager.GetData(player)
	if not data or not data.inventory then return {} end

	-- Build a set of "locked" UIDs that cannot be sacrificed right now.
	-- This keeps the Broker list aligned with server-side validation so players
	-- do not spend the 10s channel on a creature that will be rejected.
	local lockedUids = {}
	if data.favoriteUid and data.favoriteUid ~= "" then
		lockedUids[tostring(data.favoriteUid)] = true
	end
	for _, slotUid in pairs(data.baseSlots or {}) do
		if slotUid and slotUid ~= "" then
			lockedUids[tostring(slotUid)] = true
		end
	end
	for _, slotUid in pairs(data.defenseSlots or {}) do
		if slotUid and slotUid ~= "" then
			lockedUids[tostring(slotUid)] = true
		end
	end
	for _, slotUid in pairs(data.battleTeam or {}) do
		if slotUid and slotUid ~= "" then
			lockedUids[tostring(slotUid)] = true
		end
	end

	local qualifying = {}
	for _, entry in ipairs(data.inventory) do
		local matches, _ = creatureMatchesContract(entry, contract)
		local uidStr = tostring(entry.uid or "")
		if matches and uidStr ~= "" and not lockedUids[uidStr] then
			local info = CreatureData.GetById(entry.id)
			if info and not string.find(entry.id, "standin")
				and info.modelName and info.modelName ~= "Egg" then
				local onDefense, onIncome, onBattle = getPlacementFlagsForUid(data, entry.uid)
				table.insert(qualifying, {
					uid         = entry.uid,
					id          = entry.id,
					level       = entry.level or 1,
					variant     = entry.variant or "Normal",
					displayName = info and info.displayName or entry.id,
					rarity      = info and info.rarity or "Common",
					element     = info and info.element or "Unknown",
					onDefense   = onDefense,
					onIncome    = onIncome,
					onBattle    = onBattle,
				})
			end
		end
	end

	return qualifying
end

--- Choose a stable PrimaryPart for Broker (and similar) models.
-- If PrimaryPart is missing, the old code used the first BasePart from GetDescendants(),
-- which is arbitrary and often a limb/accessory — PivotTo then makes the whole model look
-- flipped or "face down". Prefer HumanoidRootPart / torso-like parts.
-- @param model Model
-- @return BasePart|nil
local function resolveBrokerPrimaryPart(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local preferredNames = {
		"HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso",
		"RootPart", "Main", "Handle",
	}
	for _, name in ipairs(preferredNames) do
		local p = model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			model.PrimaryPart = p
			return p
		end
	end
	-- Prefer direct children first (typical rig root), then full scan
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			model.PrimaryPart = p
			return p
		end
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			model.PrimaryPart = p
			return p
		end
	end
	return nil
end

--- Build world CFrame for Broker: upright, facing Hub SpawnLocation horizontal look (if any).
-- @param basePos Vector3 — XZ reference from Hub offset
-- @param groundY number
-- @param spawnRef BasePart|nil — HubArea.SpawnLocation when present
-- @return CFrame
local function buildBrokerSpawnCFrame(basePos, groundY, spawnRef)
	local yOfs = tonumber(GameConfig.BrokerNPCGroundOffsetStuds) or 0
	local pos = Vector3.new(basePos.X, groundY + yOfs, basePos.Z)
	local baseCF
	if spawnRef and spawnRef:IsA("BasePart") then
		-- Use horizontal facing only so a tilted SpawnLocation pad doesn't roll the NPC onto its face
		local lv = spawnRef.CFrame.LookVector
		local flat = Vector3.new(lv.X, 0, lv.Z)
		if flat.Magnitude > 1e-3 then
			baseCF = CFrame.lookAt(pos, pos + flat.Unit)
		else
			baseCF = CFrame.new(pos)
		end
	else
		baseCF = CFrame.new(pos)
	end
	local er = GameConfig.BrokerNPCExtraRotationDegrees
	if type(er) == "table" then
		local pitch = tonumber(er.pitch) or 0
		local yaw = tonumber(er.yaw) or 0
		local roll = tonumber(er.roll) or 0
		if pitch ~= 0 or yaw ~= 0 or roll ~= 0 then
			baseCF = baseCF * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
		end
	end
	return baseCF
end

--- Create The Broker NPC in the Arena Hub area.
-- Spawns a Part with a BillboardGui name tag and a ProximityPrompt.
-- If workspace.Arena exists, places the NPC near the arena entrance.
-- @return BasePart|nil — the broker NPC part
local function createBrokerNPC()
	-- ═══════════════════════════════════════════════════════════════════
	-- Spawn The Broker at workspace.HubArea.SpawnLocation.
	-- Falls back to workspace.Arena if HubArea doesn't exist.
	-- If there's already a BrokerNPC part anywhere, reuse it.
	-- ═══════════════════════════════════════════════════════════════════

	-- Check for an existing BrokerNPC already in workspace (Model or BasePart).
	-- FIX: Previously returned early without adding ProximityPrompt/BillboardGui,
	-- so pressing E on a pre-placed BrokerNPC model did nothing. Now we fall
	-- through to the prompt/tag/aura setup below instead of returning early.
	local existingNpc = nil
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == "BrokerNPC" and (desc:IsA("Model") or desc:IsA("BasePart")) then
			existingNpc = desc
			print("[Badlands] Found existing BrokerNPC at " .. desc:GetFullName())
			break
		end
	end
	if existingNpc then
		-- Reuse existing — ensure PrimaryPart is set for Models
		if existingNpc:IsA("Model") then
			resolveBrokerPrimaryPart(existingNpc)
		end
		-- Anchor all parts so the NPC doesn't fall
		if existingNpc:IsA("Model") then
			for _, part in ipairs(existingNpc:GetDescendants()) do
				if part:IsA("BasePart") then part.Anchored = true end
			end
		elseif existingNpc:IsA("BasePart") then
			existingNpc.Anchored = true
		end
		-- Don't return — fall through to add BillboardGui, ProximityPrompt, aura below
		brokerNPC = existingNpc
		-- Skip the clone/spawn section by jumping directly to accessory setup
		-- (reuse the local `npc` variable for the code below)
		local npc = existingNpc
		-- ── Add BillboardGui name tag (if the model doesn't already have one) ──
		if not npc:FindFirstChild("BrokerTag", true) then
			local adornee = (npc:IsA("Model") and npc.PrimaryPart) or npc
			local bb = Instance.new("BillboardGui")
			bb.Name = "BrokerTag"
			bb.Adornee = adornee
			bb.Size = UDim2.new(0, 220, 0, 60)
			bb.StudsOffset = Vector3.new(0, 4.5, 0)
			bb.AlwaysOnTop = false
			bb.MaxDistance = 60
			bb.Parent = npc

			local titleLabel = Instance.new("TextLabel")
			titleLabel.Name = "Title"
			titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
			titleLabel.Position = UDim2.new(0, 0, 0, 0)
			titleLabel.BackgroundTransparency = 1
			titleLabel.Text = "The Broker"
			titleLabel.TextColor3 = Color3.fromRGB(200, 100, 255)
			titleLabel.Font = Enum.Font.GothamBlack
			titleLabel.TextScaled = true
			titleLabel.Parent = bb

			local subLabel = Instance.new("TextLabel")
			subLabel.Name = "Subtitle"
			subLabel.Size = UDim2.new(1, 0, 0.4, 0)
			subLabel.Position = UDim2.new(0, 0, 0.55, 0)
			subLabel.BackgroundTransparency = 1
			subLabel.Text = "Badlands Gatekeeper"
			subLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			subLabel.Font = Enum.Font.GothamMedium
			subLabel.TextScaled = true
			subLabel.Parent = bb
		end

		-- ── Add ProximityPrompt (if missing — search recursively) ──
		if not npc:FindFirstChild("BrokerPrompt", true) then
			local promptParent = (npc:IsA("Model") and npc.PrimaryPart) or npc
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BrokerPrompt"
			prompt.ObjectText = "The Broker"
			prompt.ActionText = "Talk"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Parent = promptParent
		end

		-- ── Add aura effects ──
		local effectParent = (npc:IsA("Model") and npc.PrimaryPart) or npc
		if not npc:FindFirstChild("BrokerAura", true) then
			local glow = Instance.new("PointLight")
			glow.Name = "BrokerAura"
			glow.Color = Color3.fromRGB(180, 80, 255)
			glow.Brightness = 2
			glow.Range = 12
			glow.Parent = effectParent
		end
		if not npc:FindFirstChild("Highlight") and not npc:FindFirstChildWhichIsA("Highlight") then
			local highlight = Instance.new("Highlight")
			highlight.FillColor = Color3.fromRGB(80, 30, 120)
			highlight.FillTransparency = 0.6
			highlight.OutlineColor = Color3.fromRGB(200, 100, 255)
			highlight.OutlineTransparency = 0.2
			highlight.Parent = npc
		end

		print("[Badlands] Existing BrokerNPC accessorized (prompt, tag, aura)")
		return npc
	end

	-- ── Find spawn position: HubArea > SpawnLocation ──
	local parentFolder = nil   -- Where to parent the NPC
	local basePos = nil
	local spawnRef = nil       -- Hub SpawnLocation (used for upright facing)

	local hubArea = Workspace:FindFirstChild("HubArea")
	if hubArea then
		local spawnLoc = hubArea:FindFirstChild("SpawnLocation")
		if spawnLoc and spawnLoc:IsA("BasePart") then
			spawnRef = spawnLoc
			-- Place the Broker right next to the SpawnLocation (offset so they don't overlap)
			basePos = spawnLoc.Position + Vector3.new(8, 0, 0)
			parentFolder = hubArea
			print("[Badlands] Using HubArea.SpawnLocation as Broker reference")
		end
	end

	-- Fallback: workspace.Arena
	if not basePos then
		local arena = Workspace:FindFirstChild("Arena")
		if arena then
			local refPart = arena:FindFirstChild("ArenaShield")
			if refPart and refPart:IsA("BasePart") then
				basePos = refPart.Position + Vector3.new(40, 0, 0)
			else
				for _, desc in ipairs(arena:GetDescendants()) do
					if desc:IsA("BasePart") then
						basePos = desc.Position + Vector3.new(40, 0, 0)
						break
					end
				end
			end
			parentFolder = arena
		end
	end

	if not basePos then
		warn("[Badlands] Could not find HubArea.SpawnLocation or Arena for Broker NPC")
		return nil
	end

	-- Raycast down to find ground
	local rayOrigin = Vector3.new(basePos.X, basePos.Y + 50, basePos.Z)
	local rayDir = Vector3.new(0, -200, 0)
	local rayResult = Workspace:Raycast(rayOrigin, rayDir)
	local groundY = rayResult and rayResult.Position.Y or basePos.Y

	-- ── Clone the BrokerNPC model from ReplicatedStorage ──
	-- FIX: Use the custom BrokerNPC model instead of a placeholder block.
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local brokerTemplate = ReplicatedStorage:FindFirstChild("BrokerNPC")
	if not brokerTemplate then
		warn("[Badlands] BrokerNPC model not found in ReplicatedStorage! Falling back to placeholder block.")
		-- Fallback: create a simple block if the model is missing
		local fallback = Instance.new("Part")
		fallback.Name = "BrokerNPC"
		fallback.Size = Vector3.new(3, 6, 2)
		fallback.Position = Vector3.new(basePos.X, groundY + 3, basePos.Z)
		fallback.Anchored = true
		fallback.CanCollide = true
		fallback.Color = Color3.fromRGB(40, 25, 50)
		fallback.Material = Enum.Material.SmoothPlastic
		fallback.Parent = parentFolder or Workspace
		brokerNPC = fallback
		return fallback
	end

	local npc = brokerTemplate:Clone()
	npc.Name = "BrokerNPC"
	npc.Parent = parentFolder or Workspace

	-- Position the model at ground level (upright; facing matches SpawnLocation horizontal look when set)
	local spawnCFrame = buildBrokerSpawnCFrame(basePos, groundY, spawnRef)
	if npc:IsA("Model") then
		resolveBrokerPrimaryPart(npc)
		if npc.PrimaryPart then
			npc:PivotTo(spawnCFrame)
		else
			warn("[Badlands] BrokerNPC model has no BasePart — cannot PivotTo")
		end
	elseif npc:IsA("BasePart") then
		-- Apply same upright + facing as models (centered part: lift so bottom sits on ground)
		npc.CFrame = spawnCFrame * CFrame.new(0, npc.Size.Y / 2, 0)
		npc.Anchored = true
	end

	-- Anchor all parts so the NPC doesn't fall
	for _, part in ipairs(npc:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	-- ── Add BillboardGui name tag (if the model doesn't already have one) ──
	if not npc:FindFirstChild("BrokerTag", true) then
		local adornee = (npc:IsA("Model") and npc.PrimaryPart) or npc
		local bb = Instance.new("BillboardGui")
		bb.Name = "BrokerTag"
		bb.Adornee = adornee
		bb.Size = UDim2.new(0, 220, 0, 60)
		bb.StudsOffset = Vector3.new(0, 4.5, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 60
		bb.Parent = npc

		-- Title: "The Broker"
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
		titleLabel.Position = UDim2.new(0, 0, 0, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text = "The Broker"
		titleLabel.TextColor3 = Color3.fromRGB(200, 100, 255)
		titleLabel.Font = Enum.Font.GothamBlack
		titleLabel.TextScaled = true
		titleLabel.Parent = bb

		-- Subtitle: "Badlands Gatekeeper"
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle"
		subLabel.Size = UDim2.new(1, 0, 0.4, 0)
		subLabel.Position = UDim2.new(0, 0, 0.55, 0)
		subLabel.BackgroundTransparency = 1
		subLabel.Text = "Badlands Gatekeeper"
		subLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		subLabel.Font = Enum.Font.GothamMedium
		subLabel.TextScaled = true
		subLabel.Parent = bb
	end

	-- ── Add ProximityPrompt (if the model doesn't already have one) ──
	-- FIX: Use recursive search — prompt may be nested under PrimaryPart
	if not npc:FindFirstChild("BrokerPrompt", true) then
		local promptParent = (npc:IsA("Model") and npc.PrimaryPart) or npc
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BrokerPrompt"
		prompt.ObjectText = "The Broker"
		prompt.ActionText = "Talk"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = promptParent
	end

	-- ── Add aura effects (if not already present) ──
	local effectParent = (npc:IsA("Model") and npc.PrimaryPart) or npc
	if not npc:FindFirstChild("BrokerAura", true) then
		local glow = Instance.new("PointLight")
		glow.Name = "BrokerAura"
		glow.Color = Color3.fromRGB(180, 80, 255) -- purple
		glow.Brightness = 2
		glow.Range = 12
		glow.Parent = effectParent
	end

	if not npc:FindFirstChild("Highlight") and not npc:FindFirstChildWhichIsA("Highlight") then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(80, 30, 120)
		highlight.FillTransparency = 0.6
		highlight.OutlineColor = Color3.fromRGB(200, 100, 255)
		highlight.OutlineTransparency = 0.2
		highlight.Parent = npc
	end

	brokerNPC = npc
	print("[Badlands] Created The Broker NPC (model) at " .. tostring(spawnCFrame.Position) .. " (parent: " .. tostring(npc.Parent) .. ")")
	return npc
end

local function addToQueue(player, entrySource)
	-- Check if already in queue
	for _, p in ipairs(queue) do
		if p == player then
			fireClient("BadlandsQueueReject", player, "You are already in the queue.")
			return
		end
	end

	-- Check if already in a run
	if player:GetAttribute("InBadlands") then
		fireClient("BadlandsQueueReject", player, "You are already in a Badlands run.")
		return
	end

	-- Broker sacrifice is the intended live path, but direct queue joins remain
	-- available as a compatibility fallback while the Broker flow is being tested.

	table.insert(queue, player)

	-- Start queue timer if this is the first player
	if #queue == 1 then
		queueStartTime = os.clock()
	end

	-- Notify all queued players of updated count
	for _, p in ipairs(queue) do
		fireClient("BadlandsQueueUpdate", p, { count = #queue, max = MAX_PLAYERS })
	end

	print("[Badlands] " .. player.Name .. " joined queue (" .. #queue .. "/" .. MAX_PLAYERS .. ")")

	-- Start the run immediately for this player. The Badlands is a shared open zone —
	-- any player can enter at any time after sacrificing to The Broker. The server's
	-- own player cap (8) is the only limit. No min-player queue gate needed.
	local playerList = {}
	for _, p in ipairs(queue) do
		if p.Parent then table.insert(playerList, p) end
	end
	queue = {}
	queueStartTime = nil
	startRun(playerList)
end

local function removeFromQueue(player)
	for i, p in ipairs(queue) do
		if p == player then
			table.remove(queue, i)
			break
		end
	end

	-- Notify remaining
	for _, p in ipairs(queue) do
		fireClient("BadlandsQueueUpdate", p, { count = #queue, max = MAX_PLAYERS })
	end

	if #queue == 0 then
		queueStartTime = nil
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Queue timeout loop (LEGACY — kept as safety net for edge cases)
-- Players now enter immediately on sacrifice, but this catches any stranded
-- queue entries that somehow didn't trigger startRun.
-- ═══════════════════════════════════════════════════════════════════════════════
local function queueTimeoutLoop()
	while true do
		task.wait(5)

		-- Safety: if anyone is stuck in queue for more than 10 seconds, flush them in
		if #queue > 0 and queueStartTime then
			local elapsed = os.clock() - queueStartTime
			if elapsed >= 10 then
				-- Safety flush: start a run with whoever is stuck in queue
				local playerList = {}
				for _, p in ipairs(queue) do
					if p.Parent then table.insert(playerList, p) end
				end
				queue = {}
				queueStartTime = nil
				if #playerList > 0 then
					warn("[Badlands] Safety flush: starting run for " .. #playerList .. " stranded queue player(s)")
					startRun(playerList)
				end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════════

--- Returns true if a player is currently in a Badlands run
-- @param player Player
-- @return boolean
function BadlandsSystem.IsPlayerInBadlands(player)
	return player:GetAttribute("InBadlands") == true
end

--- Returns the active run data (for other systems to check)
-- @return table|nil
function BadlandsSystem.GetActiveRun()
	return activeRun
end

--- Returns true if any Badlands run is active
-- @return boolean
function BadlandsSystem.IsRunActive()
	return activeRun ~= nil and activeRun.phase ~= "ended"
end

--- Get a player's bag state during a run (for other Badlands modules)
-- @param player Player
-- @return table|nil — bag data
function BadlandsSystem.GetPlayerBag(player)
	if not activeRun then return nil end
	local ps = activeRun.players[player.UserId]
	return ps and ps.bag or nil
end

function BadlandsSystem.CaptureCreatureToBag(player, creatureModel)
	return captureCreatureToBag(player, creatureModel)
end

function BadlandsSystem.SwitchBagSlot(player, slotIndex)
	return switchActiveBagSlot(player, slotIndex)
end

--- Get a player's run power state (for other Badlands modules)
-- @param player Player
-- @return table|nil — run power data
function BadlandsSystem.GetPlayerRunPower(player)
	if not activeRun then return nil end
	local ps = activeRun.players[player.UserId]
	return ps and ps.runPower or nil
end

--- Get today's daily contract (for UI or external queries)
-- @return table|nil — { rarity, element, minLevel, description, dateKey }
function BadlandsSystem.GetDailyContract()
	return generateDailyContract()
end

--- Get The Broker NPC reference (for other systems that need to find it)
-- @return BasePart|nil
function BadlandsSystem.GetBrokerNPC()
	return brokerNPC
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Init(deps)
-- Called from MainServer after core systems are initialized.
-- Sets up RemoteEvent listeners and starts background loops.
--
-- @param playerDataMgr       PlayerDataManager module
-- @param favCreatureSys      FavoriteCreatureSystem module
-- @param mountSys            MountSystem module
-- @param creatureAISys       CreatureAI module
-- @param basePlacementSys    BasePlacementSystem module (optional; clears plot orbs on broker sacrifice)
-- ═══════════════════════════════════════════════════════════════════════════════
function BadlandsSystem.Init(playerDataMgr, favCreatureSys, mountSys, creatureAISys, basePlacementSys)
	if not ENABLED then
		print("[Badlands] BadlandsSystem DISABLED via GameConfig.BadlandsEnabled")
		return
	end

	PlayerDataManager = playerDataMgr
	FavoriteCreatureSystem = favCreatureSys
	MountSystem = mountSys
	CreatureAI = creatureAISys
	BasePlacementSystem = basePlacementSys

	eventsFolder = ReplicatedStorage:FindFirstChild("Events")

	-- Verify Badlands zone exists
	local zone = getBadlandsZone()
	if zone then
		local pts = getSpawnPoints()
		print("[Badlands] Found Badlands zone with " .. #pts .. " spawn points")
	else
		warn("[Badlands] workspace.Badlands not found — system will wait for it at runtime")
	end

	-- Wire RemoteEvent handlers
	if eventsFolder then
		local joinEvt = eventsFolder:FindFirstChild("BadlandsQueueJoin")
		if joinEvt then
			joinEvt.OnServerEvent:Connect(function(player)
				addToQueue(player, "direct")
			end)
		end

		local leaveEvt = eventsFolder:FindFirstChild("BadlandsQueueLeave")
		if leaveEvt then
			leaveEvt.OnServerEvent:Connect(function(player)
				removeFromQueue(player)
			end)
		end

		local bagSwitchEvt = eventsFolder:FindFirstChild("BadlandsBagSwitch")
		if bagSwitchEvt then
			bagSwitchEvt.OnServerEvent:Connect(function(player, slotIndex)
				switchActiveBagSlot(player, slotIndex)
			end)
		end

		local sacrificeEvt = eventsFolder:FindFirstChild("BadlandsSacrificeCreature")
		if sacrificeEvt then
			sacrificeEvt.OnServerEvent:Connect(function(player, slotIndex, statChoice)
				local ok, msg = sacrificeCreatureFromBag(player, slotIndex, statChoice)
				fireClient("BadlandsSacrificeResult", player, ok, msg or "")
			end)
		end

		local captureResolveFn = eventsFolder:FindFirstChild("BadlandsCaptureResolve")
		if captureResolveFn and captureResolveFn:IsA("RemoteFunction") then
			captureResolveFn.OnServerInvoke = function(player, mode, replaceSlotIndex)
				return resolvePendingBadlandsCapture(player, mode, replaceSlotIndex)
			end
		end

		-- Extraction is handled by ProximityPrompt Triggered in startRun.
		-- No duplicate BadlandsExtractStart handler needed here.
	end

	-- ═════════════════════════════════════════════════════════════════════
	-- THE BROKER NPC — Create + Wire Interaction
	-- ═════════════════════════════════════════════════════════════════════

	-- Generate today's contract on startup
	generateDailyContract()

	-- Spawn The Broker NPC in the Arena Hub
	local npc = createBrokerNPC()
	if npc then
		-- FIX: Use recursive search (true) because BrokerPrompt is parented to
		-- npc.PrimaryPart (a descendant), not a direct child of the model.
		-- Non-recursive FindFirstChild silently returned nil → handler never wired.
		local prompt = npc:FindFirstChild("BrokerPrompt", true)
		if prompt then
			prompt.Triggered:Connect(function(player)
				-- Player pressed E on The Broker — send contract data + qualifying creatures
				if player:GetAttribute("InBadlands") then
					-- Already in Badlands, ignore
					return
				end

				-- Check if already in queue
				for _, p in ipairs(queue) do
					if p == player then
						fireClient("BadlandsQueueReject", player, "You are already in the Badlands queue.")
						return
					end
				end

				-- Refresh contract (handles midnight rollover)
				local contract = generateDailyContract()

				-- Find qualifying creatures in player's inventory
				local qualifying = findQualifyingCreatures(player)

				-- Representative creature for the viewport: same id as the daily bonus pick
				-- (generateDailyContract chooses bonusCreatureId with the date RNG). Using the
				-- first rarity+element match in CreatureData order was wrong when multiple
				-- species share that combo (e.g. Clawkid vs Droxyl both Uncommon Water).
				local wantedCreatureId = nil
				if GameConfig.DebugBrokerCacty then
					wantedCreatureId = "cacty"
				else
					wantedCreatureId = contract.bonusCreatureId
					if not wantedCreatureId then
						local allOfRarity = CreatureData.GetCreaturesByRarity(contract.rarity) or {}
						for _, c in ipairs(allOfRarity) do
							if c.element == contract.element
								and not string.find(c.id, "standin")
								and c.modelName and c.modelName ~= "Egg" then
								wantedCreatureId = c.id
								break
							end
						end
						if not wantedCreatureId then
							for _, c in ipairs(allOfRarity) do
								if not string.find(c.id, "standin")
									and c.modelName and c.modelName ~= "Egg" then
									wantedCreatureId = c.id
									break
								end
							end
						end
					end
				end

				-- Fire contract data to client for UI display
				fireClient("BadlandsContractData", player, {
					rarity              = contract.rarity,
					element             = contract.element,
					minLevel            = contract.minLevel,
					description         = contract.description,
					dateKey             = contract.dateKey,
					qualifying          = qualifying,
					wantedCreatureId    = wantedCreatureId,
					bonusCreatureId     = contract.bonusCreatureId,
					bonusCreatureName   = contract.bonusCreatureName,
				})
			end)
		end
	else
		warn("[Badlands] Broker NPC not created — ProximityPrompt interaction unavailable")
	end

	-- Wire BadlandsOfferCreature: player selected a creature to sacrifice
	if eventsFolder then
		local offerEvt = eventsFolder:FindFirstChild("BadlandsOfferCreature")
		if offerEvt then
			offerEvt.OnServerEvent:Connect(function(player, uid)
				-- Validate: not already in Badlands or queue
				if player:GetAttribute("InBadlands") then
					fireClient("BadlandsQueueReject", player, "You are already in a Badlands run.")
					return
				end
				for _, p in ipairs(queue) do
					if p == player then
						fireClient("BadlandsQueueReject", player, "You are already in the queue.")
						return
					end
				end

				-- Validate UID
				if not uid or uid == "" then
					fireClient("BadlandsQueueReject", player, "No creature selected.")
					return
				end

				-- Validate creature exists in inventory
				if not PlayerDataManager then
					fireClient("BadlandsQueueReject", player, "System error — try again later.")
					return
				end

				local entry = PlayerDataManager.GetCreatureByUid(player, uid)
				if not entry then
					fireClient("BadlandsQueueReject", player, "Creature not found in your inventory.")
					return
				end

				-- Validate creature matches today's contract
				local contract = generateDailyContract()
				local matches, reason = creatureMatchesContract(entry, contract)
				if not matches then
					fireClient("BadlandsQueueReject", player,
						"That Siegeling doesn't satisfy the contract: " .. (reason or "unknown"))
					return
				end

				-- Favorite / companion must be cleared first (same as inventory rules)
				local data = PlayerDataManager.GetData(player)
				if data then
					local fav = data.favoriteUid or data.favoriteCreature
					if fav and tostring(fav) == tostring(uid) then
						fireClient("BadlandsQueueReject", player,
							"You can't sacrifice your equipped favorite. Unequip it first.")
						return
					end
				end

				local onDefense, onIncome, onBattle = getPlacementFlagsForUid(data, uid)

				-- ── All checks passed: sacrifice the creature and queue the player ──

				-- Get creature info for the confirmation message
				local info = CreatureData.GetById(entry.id)
				local displayName = info and info.displayName or entry.id

				local placementParts = {}
				if onDefense then table.insert(placementParts, "defense") end
				if onIncome then table.insert(placementParts, "income") end
				if onBattle then table.insert(placementParts, "battle team") end
				local placementSuffix = ""
				if #placementParts > 0 then
					placementSuffix = " Cleared from your "
						.. table.concat(placementParts, ", ")
						.. "."
				end

				local sacrificeMsg = string.format(
					"%s (Lv%d %s) has been consumed by The Broker.%s",
					displayName, entry.level or 1, entry.variant or "Normal", placementSuffix
				)

				-- Check if this is the bonus creature for extra buffs
				local isBonus = false
				if contract.bonusCreatureId and entry.id == contract.bonusCreatureId then
					isBonus = true
				end

				-- Remove creature from inventory (permanent sacrifice; also clears slot assignments in data).
				local removeOk = pcall(function()
					PlayerDataManager.RemoveCreature(player, uid)
				end)

				if not removeOk then
					fireClient("BadlandsQueueReject", player,
						"Failed to sacrifice creature — try again.")
					return
				end

				-- Despawn defense/income/battle orbs on the plot (RemoveCreature does not destroy world models).
				if BasePlacementSystem and BasePlacementSystem.ClearOrbByUid then
					pcall(function()
						BasePlacementSystem.ClearOrbByUid(player, uid, true)
					end)
				end

				if isBonus then
					player:SetAttribute("BadlandsBonusBuff", true)
					print("[Badlands] " .. player.Name .. " sacrificed BONUS creature " .. displayName)
				end

				print("[Badlands] " .. player.Name .. " sacrificed " .. displayName
					.. " (uid=" .. tostring(uid) .. ") to The Broker")

				-- Notify client that sacrifice was accepted
				fireClient("BadlandsRunStart", player, {
					accepted = true,
					sacrificeMessage = sacrificeMsg,
					contractMet = true,
					bonusActivated = isBonus,
				})

				-- Add player to queue (reuse existing queue logic)
				addToQueue(player, "broker")
			end)
		end
	end

	-- Death in The Badlands must clear run state / UI (same as elimination flow)
	for _, plr in ipairs(Players:GetPlayers()) do
		hookBadlandsCharacterDeath(plr)
	end
	Players.PlayerAdded:Connect(hookBadlandsCharacterDeath)

	-- Clean up queue when players leave the game
	Players.PlayerRemoving:Connect(function(player)
		removeFromQueue(player)

		-- If player was in a run, eliminate them
		if activeRun then
			local ps = activeRun.players[player.UserId]
			if ps and ps.alive then
				eliminatePlayer(player.UserId, "disconnect")
			end
		end
	end)

	-- Start queue timeout loop
	task.spawn(queueTimeoutLoop)

	-- Refresh daily contract at midnight (background task)
	task.spawn(function()
		while true do
			task.wait(60) -- check every minute
			generateDailyContract() -- no-ops if date hasn't changed
		end
	end)

	print("[Badlands] BadlandsSystem initialized (The Broker active in Arena Hub)")
end

return BadlandsSystem
