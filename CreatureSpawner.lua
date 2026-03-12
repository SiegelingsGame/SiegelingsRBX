--[[
	CreatureSpawner.lua - ServerScriptService (ModuleScript)
	Spawns creatures into the world with pack grouping and AI registration.

	SPAWN POINT TYPES (handled by separate spawn loops):
		SpawnPoint    - Regular wild creature spawns (common/uncommon)
		DungeonPoint  - Rarer, harder encounters (dungeon-tagged + rare+ creatures)
		BossPoint     - Legendary boss spawns (one per biome, respawn timer)

	Each biome folder (e.g. workspace.Biomes.VolcanicBiome) should contain:
		- One or more "SpawnPoint" parts for regular spawns
		- One or more "DungeonPoint" parts for dungeon encounters
		- One "BossPoint" part for the legendary boss

	FUTURE: Cross-biome spawning
		The spawn functions accept element overrides so an EventSystem
		could spawn creatures from a different element in any biome.
		See CreatureData.GetCreaturesByElement() for the data side.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local CreatureData = require(game.ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(game.ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(game.ReplicatedStorage.Modules.CreatureModelLoader)
local CreatureAnimation = require(game.ReplicatedStorage.Modules.CreatureAnimation)
local EvolutionEffects = nil
pcall(function() EvolutionEffects = require(ServerScriptService.EvolutionEffects) end)
local DayNightCycle = nil
pcall(function() DayNightCycle = require(ServerScriptService.DayNightCycle) end)

local CreatureAI -- Set in Init
local ArenaShieldSystem = nil
pcall(function() ArenaShieldSystem = require(ServerScriptService:FindFirstChild("ArenaShieldSystem")) end)

local CreatureSpawner = {}

local CREATURE_TAG = "WorldCreature"
local activeCreatures = {}

-- Tracks boss respawn cooldowns: { [bossPointPart] = lastSpawnTime }
-- Prevents bosses from instantly respawning when defeated
local bossSpawnTimers = {}

-- ======================================
-- POSITION HELPERS
-- ======================================
-- These functions pick spawn positions near various point types,
-- with spread radius and Y-raycast for proper ground placement.

-- Raycast down from the spawn point to find floor Y at (x, z) (uses surface the spawn point is on)
-- Returns: ground Y (number) - raw hit position, no offset (use for ground/flying placement)
-- FIX #16: Extended range to 200 studs + retry from high altitude on miss (consistent with CreatureAI)
local function raycastGroundY(x, z, fallbackY)
	local rayOrigin = Vector3.new(x, fallbackY + 2, z)
	local rayDirection = Vector3.new(0, -200, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {}
	local result = workspace:Raycast(rayOrigin, rayDirection, rayParams)
	if result then
		return result.Position.Y
	end
	-- Retry from high altitude in case spawn point is inside geometry
	local retryOrigin = Vector3.new(x, 500, z)
	local retryResult = workspace:Raycast(retryOrigin, Vector3.new(0, -1000, 0), rayParams)
	if retryResult then
		return retryResult.Position.Y
	end
	return fallbackY
end

-- Height from body to bottom of model bbox (min of 8 corners) + floor offset so creature sits on surface
local FLOOR_OFFSET = 0.3
local function getBodyHeightAboveBboxBottom(creatureModel, bodyPart)
	local cf, size = creatureModel:GetBoundingBox()
	local half = size * 0.5
	local minY = math.huge
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local corner = cf:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
				if corner.Y < minY then minY = corner.Y end
			end
		end
	end
	local bodyY = bodyPart and bodyPart.Position.Y or cf.Position.Y
	return (bodyY - minY) + FLOOR_OFFSET
end

-- Push position outside arena shield if inside. Uses ArenaShieldSystem when available,
-- else fallback to ArenaCenter + ArenaExclusionRadius. Re-raycasts for ground Y after push.
local function applyArenaExclusion(position)
	if ArenaShieldSystem and ArenaShieldSystem.PushOutsideArenaShield then
		local pushed = ArenaShieldSystem.PushOutsideArenaShield(position, 5)
		if pushed ~= position then
			local y = raycastGroundY(pushed.X, pushed.Z, pushed.Y)
			return Vector3.new(pushed.X, y, pushed.Z)
		end
		return position
	end
	-- Fallback: ArenaCenter + radius
	local arenaFolder = workspace:FindFirstChild("Arena")
	if arenaFolder then
		local ac = arenaFolder:FindFirstChild("ArenaCenter")
		if ac and ac:IsA("BasePart") then
			local exclusion = GameConfig.ArenaExclusionRadius or 80
			local flatDist = (Vector3.new(position.X, 0, position.Z) - Vector3.new(ac.Position.X, 0, ac.Position.Z)).Magnitude
			if flatDist < exclusion then
				local dir = Vector3.new(position.X - ac.Position.X, 0, position.Z - ac.Position.Z)
				if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) else dir = dir.Unit end
				local x = ac.Position.X + dir.X * (exclusion + 10)
				local z = ac.Position.Z + dir.Z * (exclusion + 10)
				local y = raycastGroundY(x, z, position.Y)
				return Vector3.new(x, y, z)
			end
		end
	end
	return position
end

-- Get a position spread around a center point within a given radius
-- Used by all spawn point types for adding randomness to exact positions.
-- Returns: Vector3 position on the ground (always outside arena shield)
local function getSpreadPosition(center, spreadRadius)
	local angle = math.random() * math.pi * 2
	local dist = math.random() * spreadRadius
	local x = center.X + math.cos(angle) * dist
	local z = center.Z + math.sin(angle) * dist
	local y = raycastGroundY(x, z, center.Y)
	return applyArenaExclusion(Vector3.new(x, y, z))
end

-- Zone-aware spawn: pick a SpawnPoint from the creature's matching biome
-- Tries primary and alias folder names (e.g. AquaticBiome, WaterBiome, OceanBiome for Water)
-- Returns: Vector3 position or nil (caller should fallback to random).
local function getZoneSpawnPosition(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local folderNames = CreatureData.GetBiomeFolderNamesForElement and CreatureData.GetBiomeFolderNamesForElement(info.element)
		or { CreatureData.GetBiomeFolderForElement(info.element) }
	if not folderNames or #folderNames == 0 then return nil end

	local biomesFolder = workspace:FindFirstChild("Biomes")
	if not biomesFolder then return nil end

	local biomeFolder = nil
	for _, name in ipairs(folderNames) do
		if name then
			local f = biomesFolder:FindFirstChild(name)
			if f then biomeFolder = f; break end
		end
	end
	if not biomeFolder then return nil end

	-- Collect all SpawnPoint parts in this biome folder
	local spawnPoints = {}
	for _, child in ipairs(biomeFolder:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "SpawnPoint" then
			table.insert(spawnPoints, child)
		end
	end

	if #spawnPoints == 0 then return nil end

	-- Pick a random SpawnPoint and spread around it (getSpreadPosition applies arena exclusion)
	local chosen = spawnPoints[math.random(1, #spawnPoints)]
	local spread = GameConfig.SpawnPointSpread or 25
	return getSpreadPosition(chosen.Position, spread)
end

-- Fallback: random position within SpawnRadius (avoids arena shield)
-- Used when no biome SpawnPoint is found for a creature
local function getRandomSpawnPosition()
	local angle = math.random() * math.pi * 2
	local distance = 30 + math.random() * (GameConfig.SpawnRadius - 30)
	local x = math.cos(angle) * distance
	local z = math.sin(angle) * distance
	local y = GameConfig.SpawnHeightOffset
	y = raycastGroundY(x, z, 0)
	return applyArenaExclusion(Vector3.new(x, y, z))
end

-- Get a spread position near a pack center (for pack members after the first)
local function getGroupSpawnPosition(center, spreadRadius)
	return getSpreadPosition(center, spreadRadius)
end

-- ======================================
-- CREATURE MODEL CREATION
-- ======================================
-- Creates the physical model, billboard, HP bar, highlight, etc.
-- This is shared by all spawn types (regular, dungeon, boss).

local function createCreatureModel(creatureId, position)
	local data = CreatureData.GetById(creatureId)
	if not data then return nil end

	local rarityInfo = CreatureData.Rarities[data.rarity]

	local model = Instance.new("Model")
	model.Name = "Creature_" .. data.id

	-- CreatureModelLoader: prefers Model type, then legacy mesh. Scale Model to match mesh.
	local targetSize = GameConfig.PlaceholderSize and GameConfig.PlaceholderSize.X or 4
	local options = { targetSize = targetSize, creatureId = data.id }
	local body, core, isCustomModel = CreatureModelLoader.LoadAndIntegrate(model, data.modelName, data.displayName, position, options)
	if isCustomModel then
		core = core or model:FindFirstChild("Core")
	else
		-- === PLACEHOLDER ORB (no custom model found) ===
		body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = GameConfig.PlaceholderSize
		body.Color = data.primaryColor
		body.Material = Enum.Material.SmoothPlastic
		body.Anchored = true
		body.CanCollide = false
		body.CastShadow = true
		body.Position = position
		body.Parent = model

		core = Instance.new("Part")
		core.Name = "Core"
		core.Shape = Enum.PartType.Ball
		core.Size = body.Size * 0.5
		core.Color = rarityInfo.color
		core.Material = Enum.Material.Neon
		core.Transparency = 0.4
		core.Anchored = true
		core.CanCollide = false
		core.CastShadow = false
		core.Position = position
		core.Parent = model
	end

	-- Rarity glow (Uncommon+ get a point light)
	if data.rarity ~= "Common" then
		local light = Instance.new("PointLight")
		light.Color = rarityInfo.color
		light.Brightness = data.rarity == "Legendary" and 3 or (data.rarity == "Epic" and 2 or 1)
		light.Range = data.rarity == "Legendary" and 16 or 10
		light.Parent = body
	end

	-- Highlight outline (only for placeholder orbs — custom models show clean without aura)
	if not isCustomModel then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = rarityInfo.color
		highlight.FillTransparency = 0.7
		highlight.OutlineColor = rarityInfo.color
		highlight.OutlineTransparency = 0.3
		highlight.Parent = model
	end

	-- Billboard: compact layout - name, element/class, rarity, HP bar (offset to top of bounding box so name isn't blocked)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 160, 0, 52)
	billboard.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60
	billboard.Adornee = body
	billboard.Parent = model

	-- Row 1: Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = data.displayName
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Parent = billboard

	-- Row 2: Element + Class + behavior tag
	local elementColor = CreatureData.Elements[data.element] and CreatureData.Elements[data.element].color or Color3.fromRGB(180, 180, 180)

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "BehaviorLabel"
	infoLabel.Size = UDim2.new(1, 0, 0, 12)
	infoLabel.Position = UDim2.new(0, 0, 0, 16)
	infoLabel.BackgroundTransparency = 1
	local behaviorTag = ""
	if data.behavior == "aggressive" then behaviorTag = " | aggressive"
	elseif data.behavior == "pack" then behaviorTag = " | pack"
	elseif data.behavior == "skittish" then behaviorTag = " | skittish"
	end
	infoLabel.Text = (data.element or "?") .. " " .. (data.class or "?") .. behaviorTag
	infoLabel.TextColor3 = elementColor
	infoLabel.Font = Enum.Font.GothamMedium
	infoLabel.TextSize = 10
	infoLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	infoLabel.TextStrokeTransparency = 0.6
	infoLabel.Parent = billboard

	-- Row 3: Rarity (also used for FAINTED text)
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "RarityLabel"
	rarityLabel.Size = UDim2.new(1, 0, 0, 12)
	rarityLabel.Position = UDim2.new(0, 0, 0, 28)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = data.rarity
	rarityLabel.TextColor3 = rarityInfo.color
	rarityLabel.Font = Enum.Font.GothamMedium
	rarityLabel.TextSize = 10
	rarityLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	rarityLabel.TextStrokeTransparency = 0.6
	rarityLabel.Parent = billboard

	-- Row 4: HP bar
	local hpBg = Instance.new("Frame")
	hpBg.Name = "HPBar"
	hpBg.Size = UDim2.new(0.8, 0, 0, 5)
	hpBg.Position = UDim2.new(0.1, 0, 0, 43)
	hpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBg.BorderSizePixel = 0
	hpBg.Parent = billboard
	Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0, 3)

	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBg
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 3)

	-- Attributes for identification by other systems (UniqueId persists when caught and saved to inventory)
	model:SetAttribute("UniqueId", HttpService:GenerateGUID(false))
	model:SetAttribute("CreatureId", data.id)
	model:SetAttribute("SpawnTime", os.time())
	model:SetAttribute("Behavior", data.behavior or "gentle")

	CollectionService:AddTag(model, CREATURE_TAG)
	model.PrimaryPart = body
	model.Parent = workspace

	-- Apply model rotation offset (fixes models that face wrong direction)
	local rotOffset = CreatureData.GetModelRotationOffset(data)
	if rotOffset ~= CFrame.identity then
		model:PivotTo(model:GetPivot() * rotOffset)
	end

	-- Place model: ground creatures sit on surface (bottom on ground); flying creatures hover at player height
	local groundY = position.Y
	local body = CreatureModelLoader.GetBodyPart(model) or model:FindFirstChild("Body")
	if CreatureData.IsFlying(creatureId) then
		local hoverHeight = GameConfig.FlyingHoverHeight or 5
		local desiredY = groundY + hoverHeight
		model:PivotTo(model:GetPivot() + Vector3.new(0, desiredY - (body and body.Position.Y or model:GetPivot().Position.Y), 0))
	else
		local heightAboveGround = getBodyHeightAboveBboxBottom(model, body)
		local desiredY = groundY + heightAboveGround
		model:PivotTo(model:GetPivot() + Vector3.new(0, desiredY - (body and body.Position.Y or model:GetPivot().Position.Y), 0))
	end

	-- Default to Idle animation (for rigged models with Humanoid)
	CreatureAnimation.Setup(model, creatureId, "Idle")

	return model
end

-- ======================================
-- HP BAR UPDATER
-- ======================================
-- Polls CreatureAI for current HP and updates the billboard bar.

local function startHPBarUpdater(model)
	task.spawn(function()
		while model.Parent do
			if CreatureAI then
				local hp, maxHp = CreatureAI.GetHP(model)
				local bb = model:FindFirstChild("NameTag")
				if bb then
					local hpBar = bb:FindFirstChild("HPBar")
					if hpBar then
						local fill = hpBar:FindFirstChild("Fill")
						if fill and maxHp > 0 then
							local ratio = math.clamp(hp / maxHp, 0, 1)
							fill.Size = UDim2.new(ratio, 0, 1, 0)
							if ratio > 0.5 then
								fill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
							elseif ratio > 0.25 then
								fill.BackgroundColor3 = Color3.fromRGB(255, 180, 40)
							else
								fill.BackgroundColor3 = Color3.fromRGB(255, 60, 40)
							end
						end
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

-- ======================================
-- BOB ANIMATION
-- ======================================
-- All world creatures bob up and down while alive.

local function startBobAnimation(model)
	task.spawn(function()
		local body = CreatureModelLoader.GetBodyPart(model) or model:FindFirstChild("Body")
		local core = model:FindFirstChild("Core")
		if not body then return end

		local baseY = body.Position.Y
		local time = math.random() * math.pi * 2
		local lastBobOffset = 0

		while model.Parent and body.Parent do
			local dt = RunService.Heartbeat:Wait()
			time += dt * GameConfig.CreatureBobSpeed * math.pi * 2

			-- Track the base Y by removing the previous bob offset
			-- This lets AI movement change X/Z/Y freely between frames
			baseY = body.Position.Y - lastBobOffset

			local bobOffset = math.sin(time) * GameConfig.CreatureBobHeight
			lastBobOffset = bobOffset

			body.Position = Vector3.new(body.Position.X, baseY + bobOffset, body.Position.Z)
			if core and core.Parent then
				core.Position = body.Position
				core.Transparency = 0.3 + math.sin(time * 2) * 0.15
			end
		end
	end)
end

-- ======================================
-- INTERNAL SPAWN HELPER
-- ======================================
-- Shared logic for spawning a single creature (used by all spawn paths).
-- Creates model, starts animations, registers with AI, tracks in activeCreatures.
-- variant: optional "Silver" or "Gold" for night spawns (captured creatures get this variant)
-- Returns: model or nil

local function spawnSingleCreature(creatureId, position, packId, variant)
	local ok, model = pcall(createCreatureModel, creatureId, position)
	if not ok then
		warn("[CreatureSpawner] createCreatureModel ERROR for", creatureId .. ":", tostring(model))
		return nil
	end
	if not model then return nil end

	if variant and (variant == "Silver" or variant == "Gold") then
		model:SetAttribute("Variant", variant)
	end

	-- startBobAnimation(model)
	startHPBarUpdater(model)
	activeCreatures[model] = { id = creatureId, spawnTime = os.time() }
	if CreatureAI then CreatureAI.RegisterCreature(model, creatureId, position, packId) end

	return model
end

-- Effective max creatures: base + NightSpawnBonus at night
local function getEffectiveMaxCreatures()
	local base = GameConfig.MaxWorldCreatures or 200
	if DayNightCycle and DayNightCycle.IsNight and DayNightCycle.IsNight() then
		return base + (tonumber(GameConfig.NightSpawnBonus) or 100)
	end
	return base
end

-- During night, non-standard variants (Silver/Gold) spawn based on rarity
local function getNightSpawnVariant(rarity)
	if not DayNightCycle or not DayNightCycle.IsNight or not DayNightCycle.IsNight() then
		return nil
	end
	local silverChance = tonumber(GameConfig.NightSpawnSilverChance) or 0.35
	local goldChance = tonumber(GameConfig.NightSpawnGoldChance) or 0.25
	local rarityRank = CreatureData.RarityOrder and CreatureData.RarityOrder[rarity] or 1
	if rarityRank >= (CreatureData.RarityOrder and CreatureData.RarityOrder["Rare"] or 3) then
		return math.random() < goldChance and "Gold" or nil
	end
	return math.random() < silverChance and "Silver" or nil
end

-- ======================================
-- REGULAR SPAWN (SpawnPoints)
-- ======================================
-- Picks a random creature (excluding dungeon/boss types) and spawns it
-- near a SpawnPoint in the matching biome, or at a random position.

function CreatureSpawner.SpawnCreature()
	local currentCount = #CollectionService:GetTagged(CREATURE_TAG)
	if currentCount >= getEffectiveMaxCreatures() then return nil end

	local onlyWithModels = GameConfig.SpawnOnlyCreaturesWithModels
	local creatureId = CreatureData.GetRandomCreatureId(onlyWithModels, true)  -- prefer Common at SpawnPoints
	local info = CreatureData.GetById(creatureId)
	if not info then
		warn("[CreatureSpawner] SpawnCreature: GetById nil for", tostring(creatureId))
		return nil
	end

	local variant = getNightSpawnVariant(info.rarity)

	-- Pack creatures spawn in groups
	if info.behavior == "pack" and info.packSize then
		local packCenter = getZoneSpawnPosition(creatureId) or getRandomSpawnPosition()
		local packId = CreatureAI and CreatureAI.GeneratePackId() or nil
		local min, max = info.packSize[1] or 2, info.packSize[2] or 3
		local count = math.random(min, max)
		local spawned = {}

		for i = 1, count do
			if #CollectionService:GetTagged(CREATURE_TAG) >= getEffectiveMaxCreatures() then break end
			local pos = i == 1 and packCenter or getGroupSpawnPosition(packCenter, 12)
			local model = spawnSingleCreature(creatureId, pos, packId, variant)
			if model then
				table.insert(spawned, model)
			end
		end

		if #spawned > 0 then
			return spawned[1]
		end
		return nil
	else
		-- Single spawn
		local position = getZoneSpawnPosition(creatureId) or getRandomSpawnPosition()
		local model = spawnSingleCreature(creatureId, position, nil, variant)
		return model
	end
end

-- ======================================
-- DUNGEON SPAWN (DungeonPoints)
-- ======================================
-- Spawns rarer/harder creatures near DungeonPoint parts.
-- Called periodically by the dungeon spawn loop.
-- Each DungeonPoint gets 1-3 creatures per cycle.

function CreatureSpawner.SpawnDungeonCreatures()
	local biomesFolder = workspace:FindFirstChild("Biomes")
	if not biomesFolder then return end

	-- Iterate through all biome folders
	for _, biomeFolder in ipairs(biomesFolder:GetChildren()) do
		if biomeFolder:IsA("Folder") then
			-- Determine which element this biome belongs to
			local element = CreatureData.GetElementForBiomeFolder(biomeFolder.Name)
			if not element then continue end

			-- Find all DungeonPoint parts in this biome
			for _, child in ipairs(biomeFolder:GetChildren()) do
				if child:IsA("BasePart") and child.Name == "DungeonPoint" then
					-- Check world creature cap
					local currentCount = #CollectionService:GetTagged(CREATURE_TAG)
					if currentCount >= getEffectiveMaxCreatures() then return end

					-- Spawn 1-3 creatures at this DungeonPoint
					local minCount = GameConfig.DungeonSpawnCount and GameConfig.DungeonSpawnCount[1] or 1
					local maxCount = GameConfig.DungeonSpawnCount and GameConfig.DungeonSpawnCount[2] or 3
					local spawnCount = math.random(minCount, maxCount)
					local spread = GameConfig.DungeonPointSpread or 15

					for _ = 1, spawnCount do
						if #CollectionService:GetTagged(CREATURE_TAG) >= getEffectiveMaxCreatures() then break end

						local creatureId = CreatureData.GetDungeonCreatureId(element, GameConfig.SpawnOnlyCreaturesWithModels)
						if creatureId then
							local info = CreatureData.GetById(creatureId)
							local position = getSpreadPosition(child.Position, spread)
							local variant = info and getNightSpawnVariant(info.rarity) or nil

							-- Pack creatures at dungeons still form packs
							if info and info.behavior == "pack" and info.packSize then
								local packId = CreatureAI and CreatureAI.GeneratePackId() or nil
								local min, max = info.packSize[1] or 2, info.packSize[2] or 3
								local packCount = math.random(min, max)
								for i = 1, packCount do
									if #CollectionService:GetTagged(CREATURE_TAG) >= getEffectiveMaxCreatures() then break end
									local pos = i == 1 and position or getGroupSpawnPosition(position, 8)
									local model = spawnSingleCreature(creatureId, pos, packId, variant)
								end
							else
								spawnSingleCreature(creatureId, position, nil, variant)
							end
						end
					end
				end
			end
		end
	end
end

-- ======================================
-- BOSS SPAWN (BossPoints)
-- ======================================
-- Spawns the legendary creature for each biome at its BossPoint.
-- Respects a cooldown timer so bosses don't instantly respawn.
-- Only spawns if no existing boss creature is alive at that point.

function CreatureSpawner.SpawnBossCreatures()
	local biomesFolder = workspace:FindFirstChild("Biomes")
	if not biomesFolder then return end

	local now = os.time()
	local bossRespawnTime = GameConfig.BossRespawnTime or 300

	for _, biomeFolder in ipairs(biomesFolder:GetChildren()) do
		if biomeFolder:IsA("Folder") then
			local element = CreatureData.GetElementForBiomeFolder(biomeFolder.Name)
			if not element then continue end

			-- Find BossPoint in this biome
			for _, child in ipairs(biomeFolder:GetChildren()) do
				if child:IsA("BasePart") and child.Name == "BossPoint" then
					-- Check respawn cooldown
					local lastSpawn = bossSpawnTimers[child]
					if lastSpawn and (now - lastSpawn) < bossRespawnTime then
						continue -- Still on cooldown
					end

					-- Check if a boss is already alive near this point
					local bossAlive = false
					local bossCreatureId = CreatureData.GetBossCreatureId(element, GameConfig.SpawnOnlyCreaturesWithModels)
					if bossCreatureId then
						for model, data in pairs(activeCreatures) do
							if data.id == bossCreatureId and model.Parent then
								-- Check if this boss is near this specific BossPoint
								local body = CreatureModelLoader.GetBodyPart(model) or model:FindFirstChild("Body")
								if body then
									local dist = (body.Position - child.Position).Magnitude
									if dist < 100 then -- Within reasonable range of the BossPoint
										bossAlive = true
										break
									end
								end
							end
						end
					end

					if bossAlive then continue end

					-- Check world creature cap
					local currentCount = #CollectionService:GetTagged(CREATURE_TAG)
					if currentCount >= getEffectiveMaxCreatures() then return end

					-- Spawn the boss!
					if bossCreatureId then
						local spread = GameConfig.BossPointSpread or 10
						local position = getSpreadPosition(child.Position, spread)
						local model = spawnSingleCreature(bossCreatureId, position, nil)

						if model then
							bossSpawnTimers[child] = now
							model:SetAttribute("IsBoss", true)
						end
					end
				end
			end
		end
	end
end

-- ======================================
-- SPECIFIC CREATURE SPAWN (for other systems)
-- ======================================
-- Used by external systems (raids, events, etc.) that need to spawn
-- a specific creature at an explicit position.

function CreatureSpawner.SpawnSpecificCreature(creatureId, position)
	return spawnSingleCreature(creatureId, position, nil)
end

-- ======================================
-- CREATURE MANAGEMENT
-- ======================================

function CreatureSpawner.RemoveCreature(model)
	if model then
		if CreatureAI then CreatureAI.UnregisterCreature(model) end
		activeCreatures[model] = nil
		if model.Parent then model:Destroy() end
	end
end

function CreatureSpawner.GetCreatureId(model)
	return model and model:GetAttribute("CreatureId")
end

function CreatureSpawner.GetActiveCreatures()
	return activeCreatures
end

-- ======================================
-- INITIALIZATION
-- ======================================

local spawningStarted = false

-- Called by MainServer when the first player finishes the launch screen
function CreatureSpawner.StartSpawning()
	if spawningStarted then return end
	spawningStarted = true

	-- Initial spawn burst: fill SpawnPoints quickly (aim for LoadingSpawnTarget if set, else 50)
	local burstTarget = GameConfig.LoadingSpawnTarget or 50
	local burst = math.min(burstTarget, GameConfig.MaxWorldCreatures or 200)
	task.spawn(function()
		local burstSpawned = 0
		for i = 1, burst do
			local m = CreatureSpawner.SpawnCreature()
			if m then burstSpawned = burstSpawned + 1 end
			task.wait(0.08)
		end
	end)

	-- Regular auto-spawn loop: keep SpawnPoints full, prioritize Common
	task.spawn(function()
		local loopCount = 0
		while true do
			local interval = math.random(GameConfig.SpawnIntervalMin or 0.5, GameConfig.SpawnIntervalMax or 1.5)
			task.wait(interval)
			loopCount = loopCount + 1
			local count = #CollectionService:GetTagged(CREATURE_TAG)
			local maxC = getEffectiveMaxCreatures()
			local perCycle = GameConfig.SpawnsPerCycle or 4
			local toSpawn = (count < maxC * 0.5) and math.min(perCycle, maxC - count) or 1
			for i = 1, toSpawn do
				if #CollectionService:GetTagged(CREATURE_TAG) >= maxC then break end
				local ok, err = pcall(CreatureSpawner.SpawnCreature)
				if not ok then
					warn("[CreatureSpawner] SpawnCreature ERROR (loop #" .. loopCount .. "):", tostring(err))
				end
				task.wait(0.05)
			end
		end
	end)

	-- Dungeon spawn loop: keep each DungeonPoint stocked with at least 1 rare+ creature
	task.spawn(function()
		task.wait(15)
		while true do
			local count = #CollectionService:GetTagged(CREATURE_TAG)
			local maxC = getEffectiveMaxCreatures()
			local fillTarget = GameConfig.SpawnPointFillTarget or 0.5
			if count >= maxC * fillTarget then
				local ok, err = pcall(CreatureSpawner.SpawnDungeonCreatures)
				if not ok then
					warn("[CreatureSpawner] SpawnDungeonCreatures ERROR:", tostring(err))
				end
			end
			task.wait(25 + math.random() * 20)  -- check every 25–45s (was 45–75s)
		end
	end)

	-- Boss spawn loop (BossPoints)
	-- Checks if bosses need spawning/respawning
	task.spawn(function()
		-- Initial delay, then spawn bosses
		task.wait(10)
		while true do
			local ok, err = pcall(CreatureSpawner.SpawnBossCreatures)
			if not ok then
				warn("[CreatureSpawner] SpawnBossCreatures ERROR:", tostring(err))
			end
			-- Check every 30 seconds if bosses need respawning
			task.wait(30)
		end
	end)

	-- Night: world creatures with evolutions randomly evolve; dawn: evolved world creatures devolve
	task.spawn(function()
		task.wait(15)
		local RAIDER_TAG = "AIRaider"
		local interval = math.max(5, tonumber(GameConfig.NightWorldEvolutionInterval) or 22)
		local chance = math.clamp(tonumber(GameConfig.NightWorldEvolutionChance) or 0.18, 0, 1)
		local wasNight = false
		while true do
			task.wait(interval)
			local isNight = DayNightCycle and DayNightCycle.IsNight and DayNightCycle.IsNight()
			-- At dawn: devolve all evolved world creatures
			if wasNight and not isNight then
				for _, model in ipairs(CollectionService:GetTagged(CREATURE_TAG)) do
					if not model.Parent then continue end
					if model:GetAttribute("Fainted") or model:GetAttribute("IsBoss") then continue end
					if CollectionService:HasTag(model, RAIDER_TAG) then continue end
					local creatureId = model:GetAttribute("CreatureId")
					if not creatureId then continue end
					local baseId = CreatureData.GetEvolvesFrom(creatureId)
					if not baseId then continue end
					local evolvedInfo = CreatureData.GetById(creatureId)
					local baseInfo = CreatureData.GetById(baseId)
					local pos = model:GetPivot().Position
					local lvl = model:GetAttribute("CreatureLevel") or 1
					local xp = model:GetAttribute("CreatureXP") or 0
					local variant = model:GetAttribute("Variant")
					if EvolutionEffects and EvolutionEffects.PlayDevolutionEffect then
						EvolutionEffects.PlayDevolutionEffect(pos)
					end
					CreatureSpawner.RemoveCreature(model)
					local newModel = CreatureSpawner.SpawnSpecificCreature(baseId, pos)
					if newModel then
						newModel:SetAttribute("CreatureLevel", lvl)
						newModel:SetAttribute("CreatureXP", xp)
						if variant == "Silver" or variant == "Gold" then newModel:SetAttribute("Variant", variant) end
					end
				end
			end
			wasNight = isNight
			-- At night: randomly evolve base-form world creatures that have evolutions
			if not isNight then continue end
			for _, model in ipairs(CollectionService:GetTagged(CREATURE_TAG)) do
				if not model.Parent then continue end
				if model:GetAttribute("Fainted") or model:GetAttribute("IsBoss") then continue end
				if CollectionService:HasTag(model, RAIDER_TAG) then continue end
				local creatureId = model:GetAttribute("CreatureId")
				if not creatureId then continue end
				if CreatureData.GetEvolvesFrom(creatureId) then continue end
				local evolvedId = CreatureData.GetEvolvesTo(creatureId)
				if not evolvedId or not CreatureData.CanEvolveInGame(creatureId) then continue end
				if math.random() > chance then continue end
				local baseInfo = CreatureData.GetById(creatureId)
				local evolvedInfo = CreatureData.GetById(evolvedId)
				local pos = model:GetPivot().Position
				local lvl = model:GetAttribute("CreatureLevel") or 1
				local xp = model:GetAttribute("CreatureXP") or 0
				local variant = model:GetAttribute("Variant")
				if EvolutionEffects and EvolutionEffects.PlayEvolutionEffect then
					EvolutionEffects.PlayEvolutionEffect(pos)
				end
				CreatureSpawner.RemoveCreature(model)
				local newModel = CreatureSpawner.SpawnSpecificCreature(evolvedId, pos)
				if newModel then
					newModel:SetAttribute("CreatureLevel", lvl)
					newModel:SetAttribute("CreatureXP", xp)
					if variant == "Silver" or variant == "Gold" then newModel:SetAttribute("Variant", variant) end
				end
			end
		end
	end)
end

function CreatureSpawner.Init(creatureAIRef)
	CreatureAI = creatureAIRef

	-- Auto-despawn old uncaptured creatures (not fainted, not bosses)
	task.spawn(function()
		while true do
			task.wait(15)
			local now = os.time()
			for model, data in pairs(activeCreatures) do
				if model.Parent then
					local age = now - data.spawnTime
					local isFainted = model:GetAttribute("Fainted")
					local isBoss = model:GetAttribute("IsBoss")
					-- Bosses don't auto-despawn from age (only from defeat/capture)
					if age > GameConfig.CreatureDespawnTime and not isFainted and not isBoss then
						CreatureSpawner.RemoveCreature(model)
					end
				else
					activeCreatures[model] = nil
				end
			end
		end
	end)
end

return CreatureSpawner
