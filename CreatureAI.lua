-- CreatureAI.lua - ServerScriptService (ModuleScript)
-- Last updated: 2026-04-23 19:35
-- UPDATED: FIX #15 crawling upright reset on Move->Idle transition (2025)
-- Terrain swimmable water: water-type AI uses IsPositionInSwimmableWater; moveTowards skips seafloor raycast while swimming.
-- Manages world creature behaviors: wander, aggro, pack, flee, fight, faint.
-- Fainted creatures become capturable for a gold cost.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureData = require(game.ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(game.ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(game.ReplicatedStorage.Modules.CreatureModelLoader)
local CreatureAnimation = require(game.ReplicatedStorage.Modules.CreatureAnimation)
local PlayerWorldStats = require(game.ReplicatedStorage.Modules:WaitForChild("PlayerWorldStats"))

local cachedShowNotification -- nil = unchecked; RemoteEvent once resolved; false = missing

local function notifyPlayerHitByWorldCreature(player, appliedDamage, creatureId)
	if not player or not player.Parent then return end
	local dmg = math.max(0, math.floor((tonumber(appliedDamage) or 0) + 0.5))
	if dmg <= 0 then return end
	if cachedShowNotification == false then return end
	local evt = cachedShowNotification
	if not evt then
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		evt = eventsFolder and eventsFolder:FindFirstChild("ShowNotification")
		if not evt then
			cachedShowNotification = false
			return
		end
		cachedShowNotification = evt
	end
	local cinfo = creatureId and CreatureData.GetById(creatureId)
	local cname = (cinfo and cinfo.displayName) or "A wild creature"
	evt:FireClient(player, cname .. " hit you for " .. tostring(dmg) .. " damage", "warning", "combat")
end

local CreatureAI = {}

local CREATURE_TAG = "WorldCreature"
local FAINTED_TAG = "FaintedCreature"
local COMPANION_TAG = "FavoriteCreature"
local BASE_DEFENSE_TAG = "BaseDefenseCreature"
local BASE_INCOME_TAG = "BaseIncomeCreature"

-- State for each creature model
local creatureStates = {} -- [model] = { id, hp, maxHp, behavior, state, spawnPos, target, lastAttack, packId, faintTime }

-- States: "idle", "wander", "chase", "attack", "flee", "faint", "loneHold" (lone: territorial vs other world creatures, no chase)

-- ------ HELPERS ------

local function getBody(model)
	if not model then return nil end
	return CreatureModelLoader.GetBodyPart(model) or model:FindFirstChild("Body")
end

-- Raycast down to get ground Y at (x,z). Exclude ALL creature models (WorldCreature, BaseDefense,
-- BaseIncome, FavoriteCreature) and player characters so we hit actual ground, not other creatures.
-- Prevents fly-up/oscillation when dropped stolen creature and companion are near each other.
-- PERFORMANCE: getCreatureExcludeList builds list once per frame via getCachedExcludeList().
local _cachedExcludeList = nil
local _cachedExcludeTick = -1
local function getCachedExcludeList()
	local now = tick()
	if _cachedExcludeList and _cachedExcludeTick == now then
		return _cachedExcludeList
	end
	_cachedExcludeTick = now
	local list = {}
	local seen = {}
	for _, tag in ipairs({ CREATURE_TAG, BASE_DEFENSE_TAG, BASE_INCOME_TAG, COMPANION_TAG }) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			if m.Parent and not seen[m] then seen[m] = true; list[#list + 1] = m end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and not seen[p.Character] then seen[p.Character] = true; list[#list + 1] = p.Character end
	end
	_cachedExcludeList = list
	return list
end
-- Ocean: only water object in game (Biomes -> OceanBiome -> Ocean -> Ocean). Creatures move vertically only when inside it.
-- Fallback: if that hierarchy is missing, use first tagged WaterBlock under Biomes -> Ocean or Biomes -> OceanBiome.
local _oceanPart = nil
local function getOceanPart()
	if _oceanPart and _oceanPart.Parent then return _oceanPart end
	local biomes = Workspace:FindFirstChild("Biomes")
	local oceanBiome = biomes and biomes:FindFirstChild("OceanBiome")
	local oceanFolder = oceanBiome and oceanBiome:FindFirstChild("Ocean")
	_oceanPart = oceanFolder and oceanFolder:FindFirstChild("Ocean")
	if _oceanPart and not _oceanPart:IsA("BasePart") then _oceanPart = nil end
	if not _oceanPart and biomes then
		local oceanContainer = biomes:FindFirstChild("Ocean") or biomes:FindFirstChild("OceanBiome")
		if oceanContainer then
			local tag = (GameConfig and GameConfig.WaterBlockTag) or "WaterBlock"
			for _, part in ipairs(CollectionService:GetTagged(tag)) do
				if part and part:IsA("BasePart") and part.Parent and part:IsDescendantOf(oceanContainer) then
					_oceanPart = part
					break
				end
			end
		end
	end
	return _oceanPart
end

-- True if world position is inside the Ocean part's bounds (creatures can move vertically only there).
function CreatureAI.IsPositionInOcean(worldPos)
	local ocean = getOceanPart()
	if not ocean then return false end
	local localPos = ocean.CFrame:PointToObjectSpace(worldPos)
	local h = ocean.Size * 0.5
	return math.abs(localPos.X) <= h.X and math.abs(localPos.Y) <= h.Y and math.abs(localPos.Z) <= h.Z
end

-- Returns the Ocean part (Biomes -> OceanBiome -> Ocean -> Ocean) or nil. Used to clamp companion Y to water bounds.
function CreatureAI.GetOceanPart()
	return getOceanPart()
end

-- Terrain material water (same voxel check as UnderwaterBreathClient): Roblox swimming volumes without Ocean/WaterBlock parts.
local TERRAIN_WATER_SAMPLE_RADIUS = 1.5

local function isPositionInTerrainWater(worldPos)
	local terrain = Workspace.Terrain
	if not terrain then return false end
	local r = TERRAIN_WATER_SAMPLE_RADIUS
	local minV = worldPos - Vector3.new(r, r, r)
	local maxV = worldPos + Vector3.new(r, r, r)
	local region = Region3.new(minV, maxV):ExpandToGrid(4)
	local ok, mats = pcall(function()
		return terrain:ReadVoxels(region, 4)
	end)
	if not ok or not mats then return false end
	return mats[1] and mats[1][1] and mats[1][1][1] == Enum.Material.Water
end

function CreatureAI.IsPositionInTerrainWater(worldPos)
	return isPositionInTerrainWater(worldPos)
end

-- Ocean part, tagged WaterBlock, OR Terrain.Material.Water — anywhere the player can swim.
function CreatureAI.IsPositionInSwimmableWater(worldPos)
	if CreatureAI.IsPositionInOcean(worldPos) then return true end
	if CreatureAI.IsPositionInWaterBlock(worldPos) then return true end
	return isPositionInTerrainWater(worldPos)
end

-- Returns the WaterBlock part containing worldPos, or nil. Used by companion system to clamp Y to water volume bounds.
function CreatureAI.GetWaterBlockContaining(worldPos)
	return getWaterBlockContaining(worldPos)
end

-- WaterBlock parts (tagged): aquatic creatures seek these out and wander within bounds; surface to breathe.
local WATER_BLOCK_TAG = nil
local function getWaterBlockTag()
	if WATER_BLOCK_TAG == nil then
		WATER_BLOCK_TAG = (GameConfig and GameConfig.WaterBlockTag) or "WaterBlock"
	end
	return WATER_BLOCK_TAG
end

function CreatureAI.IsPositionInWaterBlock(worldPos)
	local tag = getWaterBlockTag()
	if not tag or tag == "" then return false end
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		if part and part:IsA("BasePart") and part.Parent then
			local localPos = part.CFrame:PointToObjectSpace(worldPos)
			local h = part.Size * 0.5
			if math.abs(localPos.X) <= h.X and math.abs(localPos.Y) <= h.Y and math.abs(localPos.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end

-- Returns the WaterBlock part that contains worldPos, or nil.
local function getWaterBlockContaining(worldPos)
	local tag = getWaterBlockTag()
	if not tag or tag == "" then return nil end
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		if part and part:IsA("BasePart") and part.Parent then
			local localPos = part.CFrame:PointToObjectSpace(worldPos)
			local h = part.Size * 0.5
			if math.abs(localPos.X) <= h.X and math.abs(localPos.Y) <= h.Y and math.abs(localPos.Z) <= h.Z then
				return part
			end
		end
	end
	return nil
end

-- Nearest WaterBlock part within maxDist of worldPos (by distance to part center).
local function getNearestWaterBlock(worldPos, maxDist)
	local tag = getWaterBlockTag()
	if not tag or tag == "" then return nil end
	local nearest, nearestDist = nil, maxDist or 80
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		if part and part:IsA("BasePart") and part.Parent then
			local d = (part.Position - worldPos).Magnitude
			if d < nearestDist then nearestDist = d; nearest = part end
		end
	end
	return nearest
end

-- Random point inside a WaterBlock part (world position). If belowSurfaceOnly, Y stays below surface (underwater).
local function getRandomPointInWaterBlock(part, belowSurfaceOnly)
	if not part or not part:IsA("BasePart") then return part and part.Position or Vector3.zero end
	local h = part.Size * 0.5
	local margin = 1
	local rx = (math.random() * 2 - 1) * (h.X - margin)
	local rz = (math.random() * 2 - 1) * (h.Z - margin)
	local ry
	if belowSurfaceOnly then
		-- Underwater: from bottom of part up to just below top (surface)
		ry = -h.Y + margin + math.random() * (h.Y * 2 - margin * 2)
		if ry > h.Y - 1.5 then ry = h.Y - 1.5 end
	else
		ry = (math.random() * 2 - 1) * (h.Y - margin)
	end
	local localPt = Vector3.new(rx, ry, rz)
	return part.CFrame:PointToWorldSpace(localPt)
end

-- World Y of water surface (top of part) for wading.
local function getSurfaceYInWaterBlock(part)
	if not part or not part:IsA("BasePart") then return nil end
	local topLocal = Vector3.new(0, part.Size.Y * 0.5, 0)
	return part.CFrame:PointToWorldSpace(topLocal).Y
end

-- Surface position (at top of part, for breathing).
local function getSurfacePositionInWaterBlock(part, currentPos)
	if not part or not part:IsA("BasePart") then return currentPos end
	local surfaceY = getSurfaceYInWaterBlock(part)
	return Vector3.new(currentPos.X, surfaceY - 0.5, currentPos.Z)
end

-- Clamp world position to stay inside part bounds.
local function clampPositionToWaterBlock(worldPos, part)
	if not part or not part:IsA("BasePart") then return worldPos end
	local localPos = part.CFrame:PointToObjectSpace(worldPos)
	local h = part.Size * 0.5
	local margin = 0.5
	local clampX = math.clamp(localPos.X, -h.X + margin, h.X - margin)
	local clampY = math.clamp(localPos.Y, -h.Y + margin, h.Y - margin)
	local clampZ = math.clamp(localPos.Z, -h.Z + margin, h.Z - margin)
	return part.CFrame:PointToWorldSpace(Vector3.new(clampX, clampY, clampZ))
end

-- FIX #16 Floating creatures: three-part fix.
--   (a) Raycast extended to 200 studs (was 50) + retry from high altitude on miss.
--       Prevents misses on hilly terrain or elevated spawn points.
--   (b) getDesiredBodyY guards against upward drift: if raycast returned the fallback
--       (fromY), the old formula was groundY + bodyHeight + 0.3 = currentY + bodyHeight + 0.3
--       which pushed creatures UP every frame. Now we detect the fallback case and return
--       the current Y unchanged to prevent drift.
--   (c) Idle ground snap added in updateCreature (see below) — creatures periodically
--       re-snap to ground even when not moving, so any residual float is corrected.
local _groundRaycastParams = nil
local function getGroundY(x, z, fromY, excludeModel)
	if not _groundRaycastParams then
		_groundRaycastParams = RaycastParams.new()
		_groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
	end
	_groundRaycastParams.FilterDescendantsInstances = getCachedExcludeList()
	-- Primary raycast: from slightly above current Y, down 200 studs
	local origin = Vector3.new(x, fromY + 2, z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -200, 0), _groundRaycastParams)
	if hit then return hit.Position.Y end
	-- Retry from high altitude (500 studs) in case creature is inside geometry or at extreme height
	local retryOrigin = Vector3.new(x, 500, z)
	local retryHit = Workspace:Raycast(retryOrigin, Vector3.new(0, -1000, 0), _groundRaycastParams)
	if retryHit then return retryHit.Position.Y end
	return fromY
end

-- Get desired body Y: ground creatures on surface, flying creatures at hover height
local FLOOR_OFFSET = 0.3
local function getDesiredBodyY(body, model, creatureId, posX, posZ)
	local fromY = body and body.Position.Y or 0
	local groundY = getGroundY(posX, posZ, fromY, model)
	if CreatureData.IsFlying(creatureId) then
		return groundY + (GameConfig.FlyingHoverHeight or 5)
	end
	-- FIX #16b: If raycast returned fallback (groundY == fromY), don't recompute —
	-- the formula groundY + bodyHeight + offset would push creature UP each frame.
	-- Instead, keep current Y to prevent upward drift.
	if groundY == fromY then
		return fromY
	end
	local cf, size = model:GetBoundingBox()
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
	return groundY + (body.Position.Y - minY) + FLOOR_OFFSET
end

-- Ground placement Y: where the model's bottom touches the surface (used when flying creatures faint and drop)
local function getGroundPlacementY(body, model, posX, posZ, fromY)
	local groundY = getGroundY(posX, posZ, fromY, model)
	-- FIX #16b: same drift guard as getDesiredBodyY
	if groundY == fromY then return fromY end
	local cf, size = model:GetBoundingBox()
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
	return groundY + (body.Position.Y - minY) + FLOOR_OFFSET
end

local function distBetween(a, b)
	if not a or not b then return 999 end
	return (a.Position - b.Position).Magnitude
end

-- Line of sight: raycast from fromModel to toModel; if anything blocks (e.g. base walls), return false.
-- Used so attacks cannot hit through walls — creatures must have clear line of sight to deal damage.
local function hasLineOfSight(fromModel, toModel)
	local fromBody = getBody(fromModel)
	local toBody = nil
	if toModel then
		toBody = CreatureModelLoader.GetBodyPart(toModel) or toModel:FindFirstChild("Body") or (toModel:FindFirstChild("HumanoidRootPart") and toModel.HumanoidRootPart)
	end
	if not fromBody or not toBody then return false end
	local fromPos = fromBody.Position
	local toPos = toBody.Position
	local dir = (toPos - fromPos).Unit
	local dist = (toPos - fromPos).Magnitude
	if dist < 0.5 then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { fromModel, toModel }
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(fromPos, dir * dist, params)
	return result == nil
end

local LaserDoorSystem = nil -- Set in Init
local ArenaShieldSystem = nil
pcall(function() ArenaShieldSystem = require(game:GetService("ServerScriptService"):FindFirstChild("ArenaShieldSystem")) end)

local function moveTowards(body, target, speed, dt, creatureId)
	local model = body and body.Parent and body.Parent:IsA("Model") and body.Parent
	-- Water creatures move in 3D inside any swimmable volume (Ocean, WaterBlock, Terrain water); otherwise ground level.
	local isWater3D = creatureId and CreatureData.IsWaterType(creatureId)
		and CreatureAI.IsPositionInSwimmableWater(body.Position)
	local dir
	if isWater3D then
		dir = target - body.Position
	else
		dir = (target - body.Position) * Vector3.new(1, 0, 1)
	end
	if dir.Magnitude < 0.5 then return end
	local newPos = body.Position + dir.Unit * math.min(speed * dt, dir.Magnitude)

	-- Water creatures: move on all axes (no ground snap). Ground/flying: set Y from surface or hover.
	if not isWater3D and model and creatureId then
		newPos = Vector3.new(newPos.X, getDesiredBodyY(body, model, creatureId, newPos.X, newPos.Z), newPos.Z)
	end

	-- Face movement direction. Water: full 3D look; others: horizontal.
	local pos = body.Position
	local lookTarget = isWater3D and (pos + dir.Unit) or Vector3.new(target.X, newPos.Y, target.Z)
	local rotOffset = creatureId and CreatureData.GetModelRotationOffset(creatureId, "world", true) or CFrame.identity
	body.CFrame = CFrame.lookAt(pos, lookTarget) * rotOffset

	-- Block movement into active dome shields (base plots)
	if LaserDoorSystem and LaserDoorSystem.IsInsideActiveShield then
		local inside, shieldCenter, shieldRadius = LaserDoorSystem.IsInsideActiveShield(newPos)
		if inside then
			local awayDir = (newPos - shieldCenter) * Vector3.new(1, 0, 1)
			if awayDir.Magnitude < 0.5 then awayDir = Vector3.new(1, 0, 0) end
			local pushPos = shieldCenter + awayDir.Unit * (shieldRadius + 1)
			if not isWater3D and model and creatureId then
				pushPos = Vector3.new(pushPos.X, getDesiredBodyY(body, model, creatureId, pushPos.X, pushPos.Z), pushPos.Z)
			end
			body.Position = pushPos
			return
		end
	end

	-- Block movement into arena shield (golden dome)
	if ArenaShieldSystem and ArenaShieldSystem.IsInsideArenaShield then
		local inside, shieldCenter, shieldRadius = ArenaShieldSystem.IsInsideArenaShield(newPos)
		if inside then
			local awayDir = (newPos - shieldCenter) * Vector3.new(1, 0, 1)
			if awayDir.Magnitude < 0.5 then awayDir = Vector3.new(1, 0, 0) end
			local pushPos = shieldCenter + awayDir.Unit * (shieldRadius + 1)
			if not isWater3D and model and creatureId then
				pushPos = Vector3.new(pushPos.X, getDesiredBodyY(body, model, creatureId, pushPos.X, pushPos.Z), pushPos.Z)
			end
			body.Position = pushPos
			return
		end
	end

	-- Block movement through walls: raycast path (skip while swimming in water — ray hits seafloor and pins creatures).
	local toNew = newPos - pos
	local moveDist = toNew.Magnitude
	if not isWater3D and moveDist > 0.01 then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = getCachedExcludeList()
		local rayDir = toNew.Unit
		local bodyRadius = math.max(body.Size.X, body.Size.Y, body.Size.Z) * 0.5
		local hit = Workspace:Raycast(pos, rayDir * (moveDist + bodyRadius * 0.5), rayParams)
		if hit and hit.Distance < moveDist + 0.1 then
			-- Stop short of wall; stay just outside surface
			newPos = hit.Position - hit.Normal * (bodyRadius + 0.2)
			if model and creatureId then
				newPos = Vector3.new(newPos.X, getDesiredBodyY(body, model, creatureId, newPos.X, newPos.Z), newPos.Z)
			end
		end
	end

	body.Position = newPos
end

-- center: Vector3, radius: number, creatureId: optional — Water type gets 3D wander (random Y) when center is inside Ocean or WaterBlock
local function getRandomWanderPoint(center, radius, creatureId)
	local angle = math.random() * math.pi * 2
	local dist = math.random() * radius
	local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	-- FIX #20: Water creatures get vertical wander in Ocean, WaterBlock, and Terrain water volumes
	if creatureId and CreatureData.IsWaterType(creatureId) and CreatureAI.IsPositionInSwimmableWater(center) then
		offset = Vector3.new(offset.X, (math.random() * 2 - 1) * radius * 0.4, offset.Z)
	end
	return center + offset
end

	local function findNearestCompanion(pos, range)
	local nearest, nearDist = nil, range
	for _, tagged in ipairs(CollectionService:GetTagged(COMPANION_TAG)) do
		if tagged.Parent then
			-- Only target alive companions (avoids attacking fainted companions that won't take damage)
			if CreatureAI._FavoriteSystem and CreatureAI._FavoriteSystem.IsCompanionAlive and not CreatureAI._FavoriteSystem.IsCompanionAlive(tagged) then
				continue
			end
			local b = getBody(tagged)
			if b then
				local d = (pos - b.Position).Magnitude
				if d < nearDist then nearDist = d; nearest = tagged end
			end
		end
	end
	return nearest, nearDist
end

local function findNearestPlayer(pos, range)
	local nearest, nearDist = nil, range
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local d = (pos - root.Position).Magnitude
				if d < nearDist then nearDist = d; nearest = char end
			end
		end
	end
	return nearest, nearDist
end

local function findNearestCreature(pos, range, excludeModel, behaviorFilter)
	local nearest, nearDist = nil, range
	for model, state in pairs(creatureStates) do
		if model ~= excludeModel and model.Parent and state.state ~= "faint" then
			if not behaviorFilter or state.behavior ~= behaviorFilter then
				local b = getBody(model)
				if b then
					local d = (pos - b.Position).Magnitude
					if d < nearDist then nearDist = d; nearest = model end
				end
			end
		end
	end
	return nearest, nearDist
end

-- Find nearest base creature (defense first, then income) near a plot center
local DEFENSE_TAG = "BaseDefenseCreature"
local INCOME_TAG = "BaseIncomeCreature"

local function findNearestBaseCreature(pos, range, plotCenter, plotRadius)
	local nearest, nearDist = nil, range
	-- Search defense creatures first (priority targets)
	for _, tagged in ipairs(CollectionService:GetTagged(DEFENSE_TAG)) do
		if tagged.Parent and not tagged:GetAttribute("Fainted") then
			local b = CreatureModelLoader.GetBodyPart(tagged) or tagged:FindFirstChild("Body")
			if b then
				-- Must be near the target plot
				local toPlot = (b.Position - plotCenter).Magnitude
				if toPlot < (plotRadius or 60) then
					local d = (pos - b.Position).Magnitude
					if d < nearDist then nearDist = d; nearest = tagged end
				end
			end
		end
	end
	if nearest then return nearest, nearDist end
	-- Fallback: income creatures
	for _, tagged in ipairs(CollectionService:GetTagged(INCOME_TAG)) do
		if tagged.Parent and not tagged:GetAttribute("Fainted") then
			local b = CreatureModelLoader.GetBodyPart(tagged) or tagged:FindFirstChild("Body")
			if b then
				local toPlot = (b.Position - plotCenter).Magnitude
				if toPlot < (plotRadius or 60) then
					local d = (pos - b.Position).Magnitude
					if d < nearDist then nearDist = d; nearest = tagged end
				end
			end
		end
	end
	return nearest, nearDist
end

-- Fire a projectile from creature toward target; on hit, run the provided callback
local function fireCreatureProjectile(fromPos, toPos, color, onHit)
	task.spawn(function()
		local speed = GameConfig.AI_CreatureProjectileSpeed or 80
		local dist = (toPos - fromPos).Magnitude
		local dur = math.clamp(dist / speed, 0.1, 0.8)

		local bolt = Instance.new("Part")
		bolt.Shape = Enum.PartType.Ball
		bolt.Size = Vector3.new(1.2, 1.2, 1.2)
		bolt.Color = color
		bolt.Material = Enum.Material.Neon
		bolt.Anchored = true
		bolt.CanCollide = false
		bolt.CastShadow = false
		bolt.Position = fromPos
		bolt.Parent = Workspace

		local light = Instance.new("PointLight")
		light.Color = color
		light.Brightness = 2
		light.Range = 8
		light.Parent = bolt

		local startT = tick()
		while tick() - startT < dur do
			if not bolt.Parent then return end
			local t = (tick() - startT) / dur
			bolt.Position = fromPos:Lerp(toPos, t)
			RunService.Heartbeat:Wait()
		end

		bolt:Destroy()
		if onHit then pcall(onHit) end
	end)
end

-- Billboard behavior label helper: show current behavior (pack vs skittish) next to element/class
local function refreshBehaviorLabel(model, state)
	if not model or not state then return end
	local bb = model:FindFirstChild("NameTag")
	if not bb then return end
	local infoLabel = bb:FindFirstChild("BehaviorLabel")
	if not infoLabel then return end

	local creatureId = model:GetAttribute("CreatureId") or state.id
	local info = creatureId and CreatureData.GetById(creatureId) or nil
	if not info then return end

	local behaviorForLabel = info.behavior or state.behavior or "gentle"
	-- Pack creatures that are in fear mode act skittish — surface this in the label
	if state.behavior == "pack" and state.fearUntil and tick() < state.fearUntil then
		behaviorForLabel = "skittish"
	elseif state.behavior == "pack" then
		behaviorForLabel = "pack"
	elseif state.behavior == "aggressive" then
		behaviorForLabel = "aggressive"
	elseif state.behavior == "skittish" then
		behaviorForLabel = "skittish"
	end

	local behaviorTag = ""
	if behaviorForLabel == "aggressive" then
		behaviorTag = " | aggressive"
	elseif behaviorForLabel == "pack" then
		behaviorTag = " | pack"
	elseif behaviorForLabel == "skittish" then
		behaviorTag = " | skittish"
	end

	local elementText = info.element or "?"
	local classText = info.class or "?"
	infoLabel.Text = elementText .. " " .. classText .. behaviorTag
end

-- Pack alerting: when one pack member is attacked, alert nearby pack members
local function alertPack(attackedModel, attacker)
	local state = creatureStates[attackedModel]
	if not state or state.behavior ~= "pack" or not state.packId then return end

	for model, s in pairs(creatureStates) do
		if model ~= attackedModel and model.Parent and s.packId == state.packId and s.state ~= "faint" then
			local b1 = getBody(attackedModel)
			local b2 = getBody(model)
			if b1 and b2 and distBetween(b1, b2) < GameConfig.AI_PackCallRange then
				s.target = attacker
				s.state = "chase"
			end
		end
	end
end

-- When a pack member faints, nearby pack mates become skittish briefly (fear), or 10% chance to become aggressive and chase the killer
local PACK_REVENGE_CHANCE = 0.10

local function notifyPackMemberDied(faintedModel, killerModel)
	local state = creatureStates[faintedModel]
	if not state or state.behavior ~= "pack" or not state.packId then return end

	-- Pack fear lasts at least 10 seconds so skittish behavior is noticeable
	local duration = math.max(10, GameConfig.AI_PackFearDuration or 10)
	local fearUntil = tick() + duration
	local faintedBody = getBody(faintedModel)
	local faintedPos = faintedBody and faintedBody.Position or nil

	for model, s in pairs(creatureStates) do
		if model ~= faintedModel and model.Parent and s.packId == state.packId and s.state ~= "faint" then
			local inRange = not faintedPos
			if faintedPos then
				local b = getBody(model)
				inRange = b and (b.Position - faintedPos).Magnitude < GameConfig.AI_PackCallRange
			end
			if not inRange then continue end

			-- 10% chance per eligible packmate: become aggressive and chase killer until one dies
			if killerModel and killerModel.Parent and math.random() < PACK_REVENGE_CHANCE then
				s.revengeTarget = killerModel
				s.target = killerModel
				s.state = "chase"
			else
				s.fearUntil = fearUntil
				s.target = killerModel
				s.state = "flee"
			end
			refreshBehaviorLabel(model, s)
		end
	end
end

-- ------ DAMAGE / FAINT ------
-- Only show damage number to the attacking player (player or companion owner), not all players in open world
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local function fireDamageNumberToAttacker(pos, damage, attackerModel)
	if not attackerModel or not pos then return end
	local player = nil
	if attackerModel:IsA("Model") then
		if attackerModel:FindFirstChild("Humanoid") then
			player = Players:GetPlayerFromCharacter(attackerModel)
		else
			local ownerId = attackerModel:GetAttribute("OwnerUserId")
			if ownerId then player = Players:GetPlayerByUserId(ownerId) end
		end
	end
	if player and player.Parent then
		local evt = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("ShowDamageNumber")
		if evt and evt:IsA("RemoteEvent") then
			evt:FireClient(player, pos, damage)
		end
	end
end

local WorldCreatureHP = nil
local function getWorldCreatureHP()
	if WorldCreatureHP == nil then
		local ok, mod = pcall(require, game:GetService("ServerScriptService"):FindFirstChild("WorldCreatureHP"))
		WorldCreatureHP = ok and mod or false
	end
	return WorldCreatureHP and WorldCreatureHP or nil
end

-- Badlands uses InfoTag + HPBarBG + HPFill + HPLabel; open-world uses NameTag + HPBar + Fill.
-- WorldCreatureHP.updateHPBar only handles the latter — keep both in sync when CreatureAI owns HP.
local function updateCreatureHPBillboard(model, hp, maxHp)
	if not model or not model.Parent then return end
	maxHp = math.max(1, maxHp or 1)
	hp = math.clamp(hp, 0, maxHp)
	local ratio = hp / maxHp

	local infoTag = model:FindFirstChild("InfoTag")
	if infoTag then
		local hpBarBG = infoTag:FindFirstChild("HPBarBG")
		if hpBarBG then
			local fill = hpBarBG:FindFirstChild("HPFill")
			if fill then
				fill.Size = UDim2.new(ratio, 0, 1, 0)
				if ratio > 0.5 then
					fill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
				elseif ratio > 0.25 then
					fill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
				else
					fill.BackgroundColor3 = Color3.fromRGB(255, 60, 50)
				end
			end
		end
		local hpLabel = infoTag:FindFirstChild("HPLabel")
		if hpLabel and hpLabel:IsA("TextLabel") then
			hpLabel.Text = math.floor(hp) .. "/" .. math.floor(maxHp)
		end
		return
	end

	local bb = model:FindFirstChild("NameTag")
	if bb then
		local hpBg = bb:FindFirstChild("HPBar") or bb:FindFirstChild("HPBarBG")
		if hpBg then
			local fill = hpBg:FindFirstChild("Fill")
			if fill then
				fill.Size = UDim2.new(ratio, 0, 1, 0)
				if ratio > 0.5 then
					fill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
				elseif ratio > 0.25 then
					fill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
				else
					fill.BackgroundColor3 = Color3.fromRGB(255, 60, 50)
				end
			end
		end
	end
end

function CreatureAI.DamageCreature(model, damage, attackerModel)
	local state = creatureStates[model]
	if not state then
		-- Creature not in AI state (e.g. spawn race, or not yet registered) — fall back to WorldCreatureHP
		local wchp = getWorldCreatureHP()
		if wchp and wchp.DamageCreature then
			wchp.DamageCreature(model, damage, attackerModel)
		end
		return
	end
	if state.state == "faint" then return end

	state.hp = state.hp - damage
	if state.hp < 0 then
		state.hp = 0
	end

	-- Sync HP to model attribute for external systems (AIRaidSystem HP bars)
	model:SetAttribute("HP", state.hp)
	model:SetAttribute("MaxHP", state.maxHp)
	updateCreatureHPBillboard(model, state.hp, state.maxHp)

	local body = getBody(model)
	if body then
		fireDamageNumberToAttacker(body.Position, damage, attackerModel)
		-- Flash red
		task.spawn(function()
			local oc = body.Color; body.Color = Color3.fromRGB(255, 50, 50)
			task.wait(0.12); if body.Parent then body.Color = oc end
		end)
	end

	-- Alert pack (skip for raiders - they have their own targeting)
	if attackerModel and state.behavior ~= "raider" then
		alertPack(model, attackerModel)
	end

	-- Engage attacker: set target so creature chases/flees the player who hit it
	-- Raiders and pack revenge keep their current target, don't redirect
	if attackerModel and state.behavior ~= "raider" and not state.revengeTarget then
		local effectiveBehavior = state.behavior
		if state.behavior == "pack" and state.fearUntil and tick() < state.fearUntil then
			effectiveBehavior = "skittish"
		end
		if effectiveBehavior == "skittish" then
			state.target = attackerModel; state.state = "flee"
			state.loneHoldGround = nil
		elseif effectiveBehavior == "gentle" or effectiveBehavior == "aggressive" or effectiveBehavior == "pack" or effectiveBehavior == "lone" then
			state.target = attackerModel; state.state = "chase"
			state.loneHoldGround = nil -- lone may resume territorial hold after combat via idle/wander
		end
	end

	if state.hp <= 0 then
		CreatureAI.FaintCreature(model, attackerModel)
	end
end

-- Optional killer model (e.g. defense turret or world creature). Fired so defense can award XP on kill.
CreatureAI.OnCreatureFainted = nil -- set in Init to Instance.new("BindableEvent")

function CreatureAI.FaintCreature(model, killerModel)
	local state = creatureStates[model]
	if not state then return end

	state.state = "faint"
	state.faintTime = tick()
	state.target = nil
	state.hp = 0
	model:SetAttribute("HP", 0)
	updateCreatureHPBillboard(model, 0, state.maxHp)

	-- Check if this is a base creature (defense / income / battle)
	local isBaseCreature = CollectionService:HasTag(model, DEFENSE_TAG)
		or CollectionService:HasTag(model, INCOME_TAG)

	-- Visual: darken but keep clickable size
	local body = getBody(model)
	if body then
		body.Color = Color3.fromRGB(80, 80, 80)
		body.Material = Enum.Material.SmoothPlastic
		body.Transparency = 0.15
	end

	local core = model:FindFirstChild("Core")
	if core then core:Destroy() end

	-- Remove highlight, add faint highlight
	local hl = model:FindFirstChildOfClass("Highlight")
	if hl then hl:Destroy() end
	local faintHL = Instance.new("Highlight")
	faintHL.FillColor = Color3.fromRGB(100, 100, 100)
	faintHL.FillTransparency = 0.5
	faintHL.OutlineColor = isBaseCreature and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 200, 0)
	faintHL.OutlineTransparency = 0.3
	faintHL.Parent = model

	-- Set fainted attribute
	model:SetAttribute("Fainted", true)
	model:SetAttribute("FaintTime", tick())

	-- Faint animation: play once and freeze on final frame (model stays until despawn/capture)
	CreatureAnimation.PlayAnimation(model, "Faint", state.id)

	-- Faint pose: walk/stand creatures roll forward on belly; crawling stay as-is; flying drop to surface
	if body then
		local creatureId = state.id
		local pos = body.Position
		local isCrawling = CreatureData.IsCrawling(creatureId)
		local isFlying = CreatureData.IsFlying(creatureId)
		if not isCrawling then
			-- Walk/stand and flying: roll forward onto belly (tween over animation)
			local startRot = (body.CFrame - body.CFrame.Position)
			local uprightRot = CreatureData.GetModelRotationOffset(creatureId, "world", false)
			local bellyPitch = CFrame.Angles(math.rad(-90), 0, 0)
			local bellyRot = uprightRot * bellyPitch
			local flatLook = body.CFrame.LookVector * Vector3.new(1, 0, 1)
			if flatLook.Magnitude < 0.1 then flatLook = Vector3.new(0, 0, -1) end
			flatLook = flatLook.Unit
			local FAINT_ROLL_DURATION = 0.35
			state.faintRollEndTime = tick() + FAINT_ROLL_DURATION
			state.faintRollStartRot = startRot
			state.faintBellyRot = bellyRot
			state.faintFlatLook = flatLook
		end
		if isFlying then
			-- Flying: drop to surface (lose hover height)
			local targetY = getGroundPlacementY(body, model, pos.X, pos.Z, pos.Y)
			state.faintDropTargetY = targetY
		end
	end

	if isBaseCreature then
		-- Base creature: add steal tag instead of capture tag, no despawn timer
		CollectionService:AddTag(model, "FaintedBaseCreature")
	else
		-- World creature: normal capture flow
		-- Update billboard
		local bb = model:FindFirstChild("NameTag")
		if bb then
			local rarityLbl = bb:FindFirstChild("RarityLabel")
			if rarityLbl then
				rarityLbl.Text = "FAINTED - Click to Capture!"
				rarityLbl.TextColor3 = Color3.fromRGB(255, 200, 50)
			end
		end

		-- Add fainted tag for capture system
		CollectionService:AddTag(model, FAINTED_TAG)
	end

	-- Pack survivors become skittish briefly when a packmate faints
	notifyPackMemberDied(model, killerModel)

	-- Notify listeners (e.g. defense turret gets XP for this kill)
	if CreatureAI.OnCreatureFainted then
		task.spawn(function()
			CreatureAI.OnCreatureFainted:Fire(model, killerModel)
		end)
	end
end

-- ------ AI UPDATE ------

local function updateCreature(model, state, dt)
	if state.state == "faint" then
		local body = getBody(model)
		if body then
			-- Flying: drop to surface until touching ground
			if state.faintDropTargetY then
				local currentY = body.Position.Y
				if currentY > state.faintDropTargetY + 0.05 then
					local dropSpeed = 18
					local newY = math.max(state.faintDropTargetY, currentY - dropSpeed * dt)
					body.Position = Vector3.new(body.Position.X, newY, body.Position.Z)
				else
					state.faintDropTargetY = nil
				end
			end
			-- Roll forward on belly: lerp rotation during faint animation (walk/stand and flying only)
			if state.faintRollEndTime and state.faintRollStartRot and state.faintBellyRot and state.faintFlatLook then
				local now = tick()
				if now < state.faintRollEndTime then
					local duration = 0.35
					local elapsed = now - (state.faintRollEndTime - duration)
					local alpha = math.clamp(elapsed / duration, 0, 1)
					local targetRot = CFrame.lookAt(Vector3.zero, state.faintFlatLook) * state.faintBellyRot
					local rot = state.faintRollStartRot:Lerp(targetRot, alpha)
					body.CFrame = CFrame.new(body.Position) * rot
				else
					state.faintRollEndTime = nil
					state.faintRollStartRot = nil
					state.faintBellyRot = nil
					state.faintFlatLook = nil
				end
			end
		end
		-- Despawn after FaintDuration (skip for base creatures - they stay until stolen or refreshed)
		if state.behavior ~= "stationary" then
			if tick() - (state.faintTime or 0) > GameConfig.FaintDuration then
				if model.Parent then model:Destroy() end
			end
		end
		return
	end

	-- Stun (e.g. ElectricBiome ElectroBall): skip AI while StunnedUntil > tick()
	local stunnedUntil = model:GetAttribute("StunnedUntil")
	if stunnedUntil and type(stunnedUntil) == "number" and tick() < stunnedUntil then
		return
	end
	if stunnedUntil and tick() >= stunnedUntil then
		model:SetAttribute("StunnedUntil", nil)
	end

	local body = getBody(model)
	if not body then return end
	local pos = body.Position

	local info = CreatureData.GetById(state.id)
	if not info then return end

	-- FIX #16c Idle ground snap: every frame, correct body Y to ground level.
	-- Without this, creatures can float when idle (moveTowards not called).
	-- Water creatures in water are exempt (3D movement). Stationary base creatures skip
	-- only if behavior is "stationary" AND currently at income/defense (they're placed by BasePlacementSystem).
	local isWaterSwimming = CreatureData.IsWaterType(state.id)
		and CreatureAI.IsPositionInSwimmableWater(pos)
	if not isWaterSwimming and state.behavior ~= "stationary" then
		local desiredY = getDesiredBodyY(body, model, state.id, pos.X, pos.Z)
		if math.abs(body.Position.Y - desiredY) > 0.1 then
			body.Position = Vector3.new(pos.X, desiredY, pos.Z)
			pos = body.Position
		end
	end

	-- Runtime: if water creature is inside a WaterBlock but wasn't registered with aquaticWaterBlock, assign it so they get full-bounds wander and vertical swimming
	if CreatureData.IsWaterType(state.id) and not (state.aquaticWaterBlock and state.waterBlockPart) then
		local wb = getWaterBlockContaining(pos)
		if wb then
			state.waterBlockPart = wb
			state.aquaticWaterBlock = true
			state.breathState = "underwater"
			state.underwaterSince = tick()
			local baseSec = GameConfig.WaterBreathUnderwaterBaseSeconds or 30
			local mult = (GameConfig.WaterBreathRarityMultiplier and GameConfig.WaterBreathRarityMultiplier[info.rarity]) or 1
			state.maxUnderwaterTime = baseSec * mult
		end
	end

	local speedMult = info.speed / 10

	-- Idle delay: if model hasn't moved for 2 seconds, prefer Idle over Move
	local posDelta = (pos - (state.lastAnimPos or pos)).Magnitude
	if posDelta > 0.3 then
		state.lastAnimPos = pos
		state.lastAnimPosTime = tick()
	end
	local idleDelay = 2
	local stationaryFor2s = (tick() - (state.lastAnimPosTime or tick())) >= idleDelay

	-- Animation: Attack when attacking, Move when chasing/wandering/fleeing (unless stationary 2s), Income on income slots, Idle otherwise. Water: Swimming when moving.
	local animType
	if state.state == "attack" then animType = "Attack"
	elseif state.state == "loneHold" then animType = "Idle"
	elseif (state.state == "chase" or state.state == "wander" or state.state == "flee") and not stationaryFor2s then
		local useSwimAnim = CreatureData.IsWaterType(state.id) and CreatureAI.IsPositionInSwimmableWater(pos)
		animType = (useSwimAnim and "Swimming") or "Move"
	elseif state.behavior == "stationary" and model:GetAttribute("SlotType") == "income" then animType = "Income"
	else animType = "Idle"
	end
	local prevAnimType = state._lastAnimType or ""
	-- PERFORMANCE: Only call PlayAnimation when anim type changes (skip redundant per-frame calls)
	if animType ~= prevAnimType then
		state._lastAnimType = animType
		local opts = (animType == "Attack") and { speed = math.clamp(speedMult, 0.5, 2) } or nil
		CreatureAnimation.PlayAnimation(model, animType, state.id, opts)
	end

	-- FIX #15 Crawling orientation reset: when a crawling creature stops moving (Idle/Attack/Income),
	-- reset its rotation to the upright (non-crawling) offset. Without this, the -90° pitch from
	-- moveTowards() persists and the creature stays belly-down permanently after walking.
	-- We track the previous animation state so we only apply the reset on the transition frame
	-- (Move → non-Move), avoiding redundant CFrame writes every tick.
	-- Use prevAnimType (before we may have updated _lastAnimType) for wasMoving check
	if CreatureData.IsCrawling(state.id) then
		local wasMoving = prevAnimType == "Move"
		local isMoving = animType == "Move"
		if wasMoving and not isMoving then
			-- Transition from Move → non-Move: reset to upright orientation (isWalking=false)
			local uprightRot = CreatureData.GetModelRotationOffset(state.id, "world", false)
			local lookTarget = state.target and typeof(state.target) == "Instance" and state.target.Parent
				and (CreatureModelLoader.GetBodyPart(state.target) or state.target:FindFirstChild("Body") or state.target:FindFirstChild("HumanoidRootPart"))
			if lookTarget then
				-- Face attack/chase target while standing upright
				local targetFlat = Vector3.new(lookTarget.Position.X, pos.Y, lookTarget.Position.Z)
				body.CFrame = CFrame.lookAt(pos, targetFlat) * uprightRot
			else
				-- No target: keep current facing direction but reset pitch to upright
				local currentLook = body.CFrame.LookVector * Vector3.new(1, 0, 1)
				if currentLook.Magnitude > 0.1 then
					local forwardPos = pos + currentLook.Unit
					body.CFrame = CFrame.lookAt(pos, forwardPos) * uprightRot
				else
					body.CFrame = CFrame.new(pos) * uprightRot
				end
			end
		end
		state._lastAnimType = animType
	end

	-- Aquatic WaterBlock AI: seek water, wander within bounds, surface to breathe 10s (underwater time scales by rarity)
	if state.aquaticWaterBlock and state.waterBlockPart and state.waterBlockPart.Parent and (state.state == "idle" or state.state == "wander") then
		local wb = state.waterBlockPart
		local now = tick()
		local surfaceDuration = GameConfig.WaterBreathSurfaceDuration or 10
		local surfaceY = getSurfaceYInWaterBlock(wb)

		if state.breathState == "seeking" then
			local targetPos = wb.Position
			if CreatureAI.IsPositionInWaterBlock(pos) then
				state.breathState = "underwater"
				state.underwaterSince = now
				state.wanderTarget = getRandomPointInWaterBlock(wb, false)
			else
				state.wanderTarget = targetPos
			end
			moveTowards(body, state.wanderTarget or targetPos, GameConfig.AI_WanderSpeed * speedMult * 1.2, dt, state.id)
			body.Position = clampPositionToWaterBlock(body.Position, wb)
		elseif state.breathState == "underwater" then
			if (now - state.underwaterSince) >= (state.maxUnderwaterTime or 30) then
				state.breathState = "surfacing"
				state.surfaceTarget = getSurfacePositionInWaterBlock(wb, pos)
			else
				if not state.wanderTarget or (body.Position - state.wanderTarget).Magnitude < 3 then
					state.wanderTarget = getRandomPointInWaterBlock(wb, false)
				end
				moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult, dt, state.id)
			end
			body.Position = clampPositionToWaterBlock(body.Position, wb)
		elseif state.breathState == "surfacing" then
			state.surfaceTarget = state.surfaceTarget or getSurfacePositionInWaterBlock(wb, pos)
			moveTowards(body, state.surfaceTarget, GameConfig.AI_WanderSpeed * speedMult * 1.2, dt, state.id)
			body.Position = clampPositionToWaterBlock(body.Position, wb)
			if surfaceY and body.Position.Y >= surfaceY - 1.5 then
				state.breathState = "surface"
				state.surfaceUntil = now + surfaceDuration
			end
		elseif state.breathState == "surface" then
			-- Wading at surface for 10 seconds
			local holdPos = Vector3.new(body.Position.X, surfaceY - 0.5, body.Position.Z)
			body.Position = clampPositionToWaterBlock(holdPos, wb)
			if now >= state.surfaceUntil then
				state.breathState = "diving"
				state.diveTarget = getRandomPointInWaterBlock(wb, false)
			end
		elseif state.breathState == "diving" then
			state.diveTarget = state.diveTarget or getRandomPointInWaterBlock(wb, false)
			moveTowards(body, state.diveTarget, GameConfig.AI_WanderSpeed * speedMult * 1.2, dt, state.id)
			body.Position = clampPositionToWaterBlock(body.Position, wb)
			if (body.Position - state.diveTarget).Magnitude < 3 then
				state.breathState = "underwater"
				state.underwaterSince = now
				state.diveTarget = nil
			end
		end
		state.lastAnimPos = body.Position
		state.lastAnimPosTime = now
	-- Behavior-specific AI
	elseif state.behavior == "aggressive" then
		-- Look for targets: companions first, then player (if no companion out), then other creatures
		if state.state == "idle" or state.state == "wander" then
			local comp, compDist = findNearestCompanion(pos, GameConfig.AI_AggroRange)
			if comp then
				state.target = comp; state.state = "chase"
			else
				-- No companion in range - target player only if they have NO companion out (fainted/Y-swapped)
				local plr, plrDist = findNearestPlayer(pos, GameConfig.AI_AggroRange)
				if plr then
					local playerObj = Players:GetPlayerFromCharacter(plr)
					if playerObj and CreatureAI._FavoriteSystem and CreatureAI._FavoriteSystem.HasCompanion(playerObj) then
						plr = nil  -- Player has companion out - don't target player, companion will be found when in range
					end
				end
				if plr then
					state.target = plr; state.state = "chase"
				else
				local prey, preyDist = findNearestCreature(pos, GameConfig.AI_AggroRange * 0.7, model, "aggressive")
				if prey then
					state.target = prey; state.state = "chase"
				else
					-- Wander
					if state.state ~= "wander" or not state.wanderTarget then
						state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius, state.id)
						state.state = "wander"
					end
					moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult, dt, state.id)
					if (body.Position - state.wanderTarget).Magnitude < 3 then
						state.state = "idle"; state.wanderTarget = nil
						state.idleUntil = tick() + math.random(2, 5)
					end
				end
				end
			end
		end

	elseif state.behavior == "pack" then
		local now = tick()
		-- Revenge: chasing killer (handled by shared chase/attack logic; don't overwrite with fear or wander)
		if state.revengeTarget then
			-- Nothing to do here; chase/attack block below drives movement
		elseif state.fearUntil then
			-- Fear: after a packmate faints, act skittish briefly then return to pack
			if now >= state.fearUntil then
				state.fearUntil = nil
				state.target = nil
				state.state = "idle"
				state.wanderTarget = nil
				refreshBehaviorLabel(model, state)
			else
				-- Act skittish: flee from threats or wander
				if state.state == "idle" or state.state == "wander" then
					local comp, compDist = findNearestCompanion(pos, GameConfig.AI_AggroRange * 0.8)
					local plr, plrDist = findNearestPlayer(pos, GameConfig.AI_AggroRange * 0.5)
					if comp or plr then
						state.target = comp or plr
						state.state = "flee"
					else
						if state.state ~= "wander" or not state.wanderTarget then
							state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.8, state.id)
							state.state = "wander"
						end
						moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult, dt, state.id)
						if (body.Position - state.wanderTarget).Magnitude < 3 then
							state.state = "idle"
							state.wanderTarget = nil
							state.idleUntil = tick() + math.random(2, 4)
						end
					end
				end
			end
		end
		if not state.fearUntil and not state.revengeTarget then
			-- Normal pack: only engages when provoked or a packmate calls
			if state.state == "idle" or state.state == "wander" then
				if state.state ~= "wander" or not state.wanderTarget then
					state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.6, state.id)
					state.state = "wander"
				end
				moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult * 0.8, dt, state.id)
				if (body.Position - state.wanderTarget).Magnitude < 3 then
					state.state = "idle"; state.wanderTarget = nil
					state.idleUntil = tick() + math.random(3, 8)
				end
			end
		end

	elseif state.behavior == "gentle" then
		-- Peaceful wander, only fights back
		if state.state == "idle" or state.state == "wander" then
			if state.state ~= "wander" or not state.wanderTarget then
				state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.4, state.id)
				state.state = "wander"
			end
			moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult * 0.5, dt, state.id)
			if (body.Position - state.wanderTarget).Magnitude < 3 then
				state.state = "idle"; state.wanderTarget = nil
				state.idleUntil = tick() + math.random(5, 12)
			end
		end

	elseif state.behavior == "lone" then
		-- Territorial patrol: engage Siegelings (companions + other world creatures) in aggro range but hold ground (no chase). Human players only if they strike first → chase.
		if state.state == "idle" or state.state == "wander" then
			local prey = select(1, findNearestCompanion(pos, GameConfig.AI_AggroRange * 0.6))
			if not prey then
				prey = select(1, findNearestCreature(pos, GameConfig.AI_AggroRange * 0.6, model, nil))
			end
			if prey then
				state.target = prey
				state.state = "loneHold"
				state.loneHoldGround = true
			else
				if state.state ~= "wander" or not state.wanderTarget then
					state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.5, state.id)
					state.state = "wander"
				end
				moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult * 0.7, dt, state.id)
				if (body.Position - state.wanderTarget).Magnitude < 3 then
					state.state = "idle"; state.wanderTarget = nil
					state.idleUntil = tick() + math.random(3, 7)
				end
			end
		end

	elseif state.behavior == "skittish" then
		-- Flee when anything gets close
		if state.state == "idle" or state.state == "wander" then
			local comp, compDist = findNearestCompanion(pos, GameConfig.AI_AggroRange * 0.8)
			local plr, plrDist = findNearestPlayer(pos, GameConfig.AI_AggroRange * 0.5)
			if comp or plr then
				state.target = comp or plr; state.state = "flee"
			else
				if state.state ~= "wander" or not state.wanderTarget then
					state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.8, state.id)
					state.state = "wander"
				end
				moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult, dt, state.id)
				if (body.Position - state.wanderTarget).Magnitude < 3 then
					state.state = "idle"; state.wanderTarget = nil
					state.idleUntil = tick() + math.random(2, 4)
				end
			end
		end
	elseif state.behavior == "stationary" then
		-- Base creatures don't move, just stay at their position
		-- They only take damage; no wandering, no chasing
		state.state = "idle"
		return

	elseif state.behavior == "raider" then
		-- Raid behavior: target base defense/income creatures on the assigned plot
		if state.state == "idle" or state.state == "wander" then
			local raidCenter = state.raidCenter or state.spawnPos
			local target, tDist = findNearestBaseCreature(pos, 80, raidCenter, 60)
			if target then
				state.target = target; state.state = "chase"
			else
				-- No targets left, wander toward plot center
				if state.state ~= "wander" or not state.wanderTarget then
					state.wanderTarget = getRandomWanderPoint(raidCenter, 15, state.id)
					state.state = "wander"
				end
				moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult * 1.2, dt, state.id)
				if (body.Position - state.wanderTarget).Magnitude < 3 then
					state.state = "idle"; state.wanderTarget = nil
					state.idleUntil = tick() + math.random(1, 3)
				end
			end
		end
	end

	-- Lone territorial hold: face another world creature in aggro range; attack at range; never advance (no chase)
	if state.state == "loneHold" and state.target and state.behavior == "lone" then
		if typeof(state.target) == "Instance" and state.target:GetAttribute("Fainted") then
			state.state = "wander"
			state.target = nil
			state.loneHoldGround = nil
			state.wanderTarget = nil
		else
			local targetBody = nil
			if typeof(state.target) == "Instance" and state.target.Parent then
				targetBody = CreatureModelLoader.GetBodyPart(state.target)
					or state.target:FindFirstChild("Body")
					or state.target:FindFirstChild("HumanoidRootPart")
			end
			if not targetBody then
				state.state = "wander"
				state.target = nil
				state.loneHoldGround = nil
				state.wanderTarget = nil
			else
				local aggroR = GameConfig.AI_AggroRange * 0.6
				local tdist = (pos - targetBody.Position).Magnitude
				if tdist > aggroR then
					state.state = "wander"
					state.target = nil
					state.loneHoldGround = nil
					state.wanderTarget = nil
				else
					local targetFlat = Vector3.new(targetBody.Position.X, pos.Y, targetBody.Position.Z)
					local rotOffset = state.id and CreatureData.GetModelRotationOffset(state.id) or CFrame.identity
					body.CFrame = CFrame.lookAt(pos, targetFlat) * rotOffset
					if tdist <= GameConfig.AI_AttackRange and hasLineOfSight(model, state.target) then
						state.state = "attack"
					end
				end
			end
		end
	end

	-- Handle idle timer (if no idleUntil set, give a short one to prevent permanent idle)
	if state.state == "idle" then
		-- Flying creatures: enforce hover height every tick (they don't move, so we don't call moveTowards)
		if CreatureData.IsFlying(state.id) then
			local desiredY = getDesiredBodyY(body, model, state.id, pos.X, pos.Z)
			if math.abs(body.Position.Y - desiredY) > 0.1 then
				body.Position = Vector3.new(body.Position.X, desiredY, body.Position.Z)
			end
		elseif CreatureData.IsWaterType(state.id) and not CreatureAI.IsPositionInSwimmableWater(body.Position) then
			-- Water creatures outside swimmable water: snap to ground level
			local desiredY = getDesiredBodyY(body, model, state.id, pos.X, pos.Z)
			if math.abs(body.Position.Y - desiredY) > 0.1 then
				body.Position = Vector3.new(body.Position.X, desiredY, body.Position.Z)
			end
		end
		if not state.idleUntil then
			state.idleUntil = tick() + math.random(1, 3)
		elseif tick() > state.idleUntil then
			state.state = "wander"; state.wanderTarget = nil
		end
	end

	-- -- CHASE --
	if state.state == "chase" and state.target then
		-- Don't chase fainted targets (world creatures shouldn't attack monsters that are already fainted)
		if typeof(state.target) == "Instance" and state.target:GetAttribute("Fainted") then
			state.state = "wander"; state.target = nil; state.revengeTarget = nil; state.wanderTarget = nil; state.loneHoldGround = nil; return
		end
		local targetBody = nil
		if typeof(state.target) == "Instance" and state.target.Parent then
			targetBody = CreatureModelLoader.GetBodyPart(state.target) or state.target:FindFirstChild("Body") or state.target:FindFirstChild("HumanoidRootPart")
		end
		if not targetBody then
			-- Target lost — return to wander (not bare idle which can get stuck)
			state.state = "wander"; state.target = nil; state.revengeTarget = nil; state.wanderTarget = nil; state.loneHoldGround = nil; return
		end

		local tdist = (pos - targetBody.Position).Magnitude
		local maxChaseRange = state.revengeTarget and 800 or (state.behavior == "raider" and 200 or (GameConfig.AI_AggroRange * 1.5))
		if tdist > maxChaseRange then
			-- Lost target, return
			state.state = "wander"; state.target = nil; state.revengeTarget = nil; state.wanderTarget = nil; state.loneHoldGround = nil
		elseif tdist > GameConfig.AI_AttackRange then
			-- Raiders: waypoint sequence — door → plot center (up ramp) → then chase target (or path to door if no LOS)
			local moveTarget = targetBody.Position
			if state.behavior == "raider" and state.raidCenter and state.raidDoor then
				local doorReach = tonumber(GameConfig.AIRaidDoorReachRadius) or 10
				local centerReach = tonumber(GameConfig.AIRaidCenterReachRadius) or 14
				local toCenter = (pos - state.raidCenter) * Vector3.new(1, 0, 1)
				local toDoor = (pos - state.raidDoor) * Vector3.new(1, 0, 1)
				local atDoor = toDoor.Magnitude <= doorReach
				local atCenter = toCenter.Magnitude <= centerReach
				if not atDoor then
					-- Phase 1: path to the door
					moveTarget = state.raidDoor
				elseif not atCenter then
					-- Phase 2: at door — path to plot center (up the ramp to PlotCenter)
					moveTarget = state.raidCenter
				else
					-- Phase 3: at center — may path to target (or to door if no LOS)
					local noLOS = not hasLineOfSight(model, state.target)
					if noLOS then
						moveTarget = state.raidDoor
					end
				end
			end
			moveTowards(body, moveTarget, GameConfig.AI_WanderSpeed * speedMult * 1.5, dt, state.id)
		else
			-- Raiders: only enter attack after reaching plot center (door → center waypoint done) and have LOS
			local centerReach = tonumber(GameConfig.AIRaidCenterReachRadius) or 14
			if state.behavior == "raider" and state.raidCenter and state.raidDoor then
				local toCenter = (pos - state.raidCenter) * Vector3.new(1, 0, 1)
				local atCenter = toCenter.Magnitude <= centerReach
				local noLOS = not hasLineOfSight(model, state.target)
				if not atCenter then
					-- Not at center yet — keep pathing to center (or door if not at door)
					local doorReach = tonumber(GameConfig.AIRaidDoorReachRadius) or 10
					local toDoor = (pos - state.raidDoor) * Vector3.new(1, 0, 1)
					local dest = (toDoor.Magnitude > doorReach) and state.raidDoor or state.raidCenter
					moveTowards(body, dest, GameConfig.AI_WanderSpeed * speedMult * 1.5, dt, state.id)
				elseif noLOS then
					moveTowards(body, state.raidDoor, GameConfig.AI_WanderSpeed * speedMult * 1.5, dt, state.id)
				else
					state.state = "attack"
				end
			else
				state.state = "attack"
			end
		end
	end

	-- -- ATTACK --
	if state.state == "attack" and state.target then
		-- Don't attack fainted targets (world creatures shouldn't attack monsters that are already fainted)
		if typeof(state.target) == "Instance" and state.target:GetAttribute("Fainted") then
			state.state = "wander"; state.target = nil; state.revengeTarget = nil; state.wanderTarget = nil; state.loneHoldGround = nil; return
		end
		local targetBody = nil
		if typeof(state.target) == "Instance" and state.target.Parent then
			targetBody = CreatureModelLoader.GetBodyPart(state.target) or state.target:FindFirstChild("Body") or state.target:FindFirstChild("HumanoidRootPart")
		end
		if not targetBody then
			state.state = "wander"; state.target = nil; state.revengeTarget = nil; state.wanderTarget = nil; state.loneHoldGround = nil; return
		end

		-- Face target while attacking (apply model rotation offset for crawling/facing)
		local targetFlat = Vector3.new(targetBody.Position.X, pos.Y, targetBody.Position.Z)
		local rotOffset = state.id and CreatureData.GetModelRotationOffset(state.id) or CFrame.identity
		body.CFrame = CFrame.lookAt(pos, targetFlat) * rotOffset

		local tdist = (pos - targetBody.Position).Magnitude
		if tdist > GameConfig.AI_AttackRange * 1.5 then
			if state.behavior == "lone" and state.loneHoldGround then
				state.state = "loneHold"
			else
				state.state = "chase"
			end
			return
		end
		-- Raiders: lose LOS (e.g. target behind wall) — drop to chase so they path to door
		if state.behavior == "raider" and not hasLineOfSight(model, state.target) then
			state.state = "chase"; return
		end
		-- Lone territorial: no LOS — hold ground (wait) instead of repositioning
		if state.behavior == "lone" and state.loneHoldGround and not hasLineOfSight(model, state.target) then
			state.state = "loneHold"
			return
		end
		-- Raiders must stay inside base to attack; if pushed out, chase again
		if state.behavior == "raider" and state.raidCenter then
			local insideRadius = tonumber(GameConfig.AIRaidAttackInsideRadius) or 55
			local toCenter = (pos - state.raidCenter) * Vector3.new(1, 0, 1)
			if toCenter.Magnitude > insideRadius then
				state.state = "chase"; return
			end
		end

		if tick() - (state.lastAttack or 0) >= GameConfig.AI_AttackCooldown then
			state.lastAttack = tick()
			local damage = math.max(1, math.floor(info.attack))

			-- Elemental weakness: world creature (attacker) vs target (defender)
			local defenderElement = nil
			local targetState = creatureStates[state.target]
			if targetState then
				local dinfo = CreatureData.GetById(targetState.id)
				defenderElement = dinfo and dinfo.element
			else
				local ownerId = state.target:GetAttribute("OwnerUserId")
				local ownerPlayer = ownerId and Players:GetPlayerByUserId(ownerId)
				if ownerPlayer and CreatureAI._FavoriteSystem then
					local _, comp = CreatureAI._FavoriteSystem.GetCompanionForModel(state.target)
					if comp then
						local dinfo = CreatureData.GetById(comp.creatureId)
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
			damage = math.floor(math.max(1, damage * elemMult))

			-- Projectile color from element or body
			local projColor = (info.element and CreatureData.Elements and CreatureData.Elements[info.element] and CreatureData.Elements[info.element].color) or body.Color

			local fromPos = body.Position + (targetBody.Position - body.Position).Unit * 1.5
			local toPos = targetBody.Position
			local targetModel = state.target
			local capturedTargetState = targetState

			-- Fire projectile; apply damage when it hits (only if line of sight — walls block attacks)
			fireCreatureProjectile(fromPos, toPos, projColor, function()
				local target = targetModel
				if not target or not target.Parent then return end
				if not hasLineOfSight(model, target) then return end
				local hitBody = CreatureModelLoader.GetBodyPart(target) or target:FindFirstChild("Body") or target:FindFirstChild("HumanoidRootPart")
				local hitPos = hitBody and hitBody.Position or toPos

				if capturedTargetState then
					CreatureAI.DamageCreature(target, damage, model)
				else
					local ownerId = target:GetAttribute("OwnerUserId")
					local ownerPlayer = ownerId and Players:GetPlayerByUserId(ownerId)
					if ownerPlayer then
						if CreatureAI._FavoriteSystem then
							CreatureAI._FavoriteSystem.DamageCompanion(ownerPlayer, damage, model)
						end
					else
						local player = Players:GetPlayerFromCharacter(target)
						if player then
							local hum = target:FindFirstChild("Humanoid")
							if hum and hum.Health > 0 then
								local applied = PlayerWorldStats.ApplyDefenseFromPlayer(player, damage)
								hum:TakeDamage(applied)
								notifyPlayerHitByWorldCreature(player, applied, state.id)
							end
						end
					end
				end

				if state.onAttackHit then
					pcall(state.onAttackHit, model, target, damage)
				end
			end)
		end
	end

	-- -- FLEE --
	if state.state == "flee" then
		local fleeFrom = nil
		if state.target and typeof(state.target) == "Instance" and state.target.Parent then
			fleeFrom = CreatureModelLoader.GetBodyPart(state.target) or state.target:FindFirstChild("Body") or state.target:FindFirstChild("HumanoidRootPart")
		end
		if fleeFrom then
			-- FIX #20: Water creatures flee in 3D in Ocean, WaterBlock, and Terrain water
			local isWater3D = CreatureData.IsWaterType(state.id) and CreatureAI.IsPositionInSwimmableWater(body.Position)
			local away = isWater3D and (pos - fleeFrom.Position) or (pos - fleeFrom.Position) * Vector3.new(1, 0, 1)
			if away.Magnitude > 0.1 then
				local newPos = body.Position + away.Unit * GameConfig.AI_FleeSpeed * speedMult * dt
				if not isWater3D then
					newPos = Vector3.new(newPos.X, getDesiredBodyY(body, model, state.id, newPos.X, newPos.Z), newPos.Z)
				end
				body.Position = newPos
				-- Face away from the threat (direction of movement) so skittish creatures run with their backs to the player
				local lookTarget = isWater3D and (newPos + away.Unit) or Vector3.new(newPos.X + away.Unit.X, newPos.Y, newPos.Z + away.Unit.Z)
				local rotOffset = CreatureData.GetModelRotationOffset(state.id, "world", true) or CFrame.identity
				body.CFrame = CFrame.lookAt(newPos, lookTarget) * rotOffset
			end
			-- Pack creatures in skittish (fear) mode flee farther — up to at least 60 studs
			local fleeRange = GameConfig.AI_FleeRange
			if state.behavior == "pack" and state.fearUntil and tick() < (state.fearUntil or 0) then
				fleeRange = math.max(fleeRange or 0, 60)
			end
			if away.Magnitude > (fleeRange or GameConfig.AI_FleeRange) then
				state.state = "wander"; state.target = nil; state.wanderTarget = nil
			end
		else
			state.state = "wander"; state.target = nil; state.wanderTarget = nil
		end
	end
end

-- ------ PUBLIC API ------

local nextPackId = 0
function CreatureAI.RegisterCreature(model, creatureId, spawnPos, packId)
	local info = CreatureData.GetById(creatureId)
	if not info then return end

	-- Badlands (and any spawner) may set HP/MaxHP on the model before RegisterCreature; use those so damage + UI match.
	local baseHealth = info.health or 100
	local maxHp = baseHealth
	local hp = baseHealth
	local attrMax = model:GetAttribute("MaxHP")
	local attrHp = model:GetAttribute("HP")
	if type(attrMax) == "number" and attrMax > 0 then
		maxHp = math.floor(attrMax)
		if type(attrHp) == "number" and attrHp >= 0 then
			hp = math.floor(attrHp)
		else
			hp = maxHp
		end
	end

	creatureStates[model] = {
		id = creatureId,
		hp = hp,
		maxHp = maxHp,
		behavior = info.behavior or "gentle",
		state = "idle",
		spawnPos = spawnPos,
		target = nil,
		lastAttack = 0,
		packId = packId,
		faintTime = nil,
		idleUntil = tick() + math.random(1, 4),
		wanderTarget = nil,
	}

	-- Aquatic WaterBlock behavior: water creatures spawned near OceanBiome seek out WaterBlock and wander within it, surfacing to breathe.
	if CreatureData.IsWaterType(creatureId) then
		local wb = getWaterBlockContaining(spawnPos) or getNearestWaterBlock(spawnPos, GameConfig.WaterBlockSeekRange or 80)
		if wb then
			local state = creatureStates[model]
			state.waterBlockPart = wb
			state.aquaticWaterBlock = true
			state.breathState = "seeking"
			state.underwaterSince = tick()
			state.surfaceUntil = nil
			local baseSec = GameConfig.WaterBreathUnderwaterBaseSeconds or 30
			local mult = (GameConfig.WaterBreathRarityMultiplier and GameConfig.WaterBreathRarityMultiplier[info.rarity]) or 1
			state.maxUnderwaterTime = baseSec * mult
		end
	end
end

function CreatureAI.UnregisterCreature(model)
	creatureStates[model] = nil
end

function CreatureAI.GetState(model)
	return creatureStates[model]
end

function CreatureAI.IsFainted(model)
	local s = creatureStates[model]
	return s and s.state == "faint"
end

-- Walls block attacks: attackers need clear line of sight to deal damage (used by defense turrets too).
function CreatureAI.HasLineOfSight(fromModel, toModel)
	return hasLineOfSight(fromModel, toModel)
end

function CreatureAI.GetHP(model)
	local s = creatureStates[model]
	if s then return s.hp, s.maxHp end
	-- Fallback: creature may use WorldCreatureHP (e.g. damage applied before AI registration)
	local wchp = getWorldCreatureHP()
	if wchp and wchp.GetHP then
		return wchp.GetHP(model)
	end
	return 0, 0
end

function CreatureAI.GeneratePackId()
	nextPackId = nextPackId + 1
	return "pack_" .. nextPackId
end

CreatureAI._FavoriteSystem = nil  -- Set by MainServer after init

function CreatureAI.SetFavoriteSystem(favSys)
	CreatureAI._FavoriteSystem = favSys
end

-- ------ INIT ------

function CreatureAI.Init(laserDoorRef)
	if laserDoorRef then LaserDoorSystem = laserDoorRef end
	CreatureAI.OnCreatureFainted = Instance.new("BindableEvent")
	-- Main AI loop: distance-based LOD to reduce per-frame AI cost while keeping nearby movement fluid.
	-- <40 studs: full rate; 40-120 studs: 10 Hz; >120 studs: 2 Hz.
	-- IMPORTANT: Never modify creatureStates during pairs() iteration.
	-- Collect removals in a separate list, then apply after iteration.
	local lastTick = tick()
	RunService.Heartbeat:Connect(function()
		local now = tick()
		local dt = math.min(now - lastTick, 1/15) -- clamp dt to avoid huge jumps after lag
		lastTick = now
		local playerRoots = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and hum and hum.Health > 0 then
				table.insert(playerRoots, root.Position)
			end
		end

		local toRemove = {}
		for model, state in pairs(creatureStates) do
			if model.Parent then
				local body = getBody(model)
				local nearest = math.huge
				if body and #playerRoots > 0 then
					local bpos = body.Position
					for _, rpos in ipairs(playerRoots) do
						local d = (bpos - rpos).Magnitude
						if d < nearest then nearest = d end
					end
				end

				local updateInterval
				if nearest <= 40 then
					updateInterval = 0
				elseif nearest <= 120 then
					updateInterval = 0.1
				else
					updateInterval = 0.5
				end

				local stepDt = dt
				if updateInterval > 0 then
					local nextAt = state._nextAiUpdateAt or 0
					if now < nextAt then
						continue
					end
					local lastAi = state._lastAiUpdateAt or now
					stepDt = math.min(now - lastAi, 0.25)
					state._lastAiUpdateAt = now
					state._nextAiUpdateAt = now + updateInterval
				else
					state._lastAiUpdateAt = now
					state._nextAiUpdateAt = now
				end

				local ok, err = pcall(updateCreature, model, state, stepDt)
				if not ok then warn("[CreatureAI] Error: " .. tostring(err)) end
			else
				table.insert(toRemove, model)
			end
		end

		-- Clean up destroyed models outside of iteration
		for _, model in ipairs(toRemove) do
			creatureStates[model] = nil
		end
	end)

end

return CreatureAI