--[[
	ElectricBiomeHazardSystem.lua - ServerScriptService (ModuleScript)
	ElectricBiome world hazards: ElectroBalls spawn in random spreads, charge up, explode, and then disappear.
	Every cycle, ElectroBalls spawn across the biome, charge an AOE, then explode for damage + stun before despawning.

	Required in your place:
		Workspace.Biomes.PeaksBiome (or ElectricBiome / ElectriBiome) - folder containing:
		  - ElectricGround or ElectriGround (Part, Model, or Folder of parts) OR any BasePart with Size X,Z > 5
		  - Optional: SpawnPoint, DungeonPoint, BossPoint parts for extra positions
		ReplicatedStorage.Hazards.ElectroBall - optional; if missing, a default neon ball Part is created
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local WorldCreatureHP = nil
pcall(function() WorldCreatureHP = require(ServerScriptService.WorldCreatureHP) end)
local CreatureModelLoader = nil
pcall(function() CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader) end)

local WORLD_CREATURE_TAG = "WorldCreature"
local COMPANION_TAG = "FavoriteCreature"

local ElectricBiomeHazardSystem = {}

-- Config (GameConfig overrides when set)
local SPAWN_INTERVAL = 10
local AOE_RADIUS = 10
local CHARGE_SECONDS = 3
local STUN_SECONDS = 1
local DAMAGE_PERCENT = 0.25

local function cfg(key, fallback)
	return (GameConfig and GameConfig[key]) or fallback
end

local biomeFolder = nil
local groundParts = {}
local electroBallPositions = {}  -- { Vector3 } - positions for activation
local electroBallInstances = {}  -- index -> orb instance placed in biome
local activationIndex = 0
local lastActivationTime = 0
local running = false

local ELECTROBALL_COUNT = 50
local GRID_VARIANCE = 3  -- studs random offset for grid positions (used at init)
local RANDOM_POSITION_MARGIN = 15  -- keep random spawns this many studs inside ground edges
local MIN_HEIGHT_ABOVE_GROUND = 1
local MAX_HEIGHT_ABOVE_GROUND = 10
local LIGHTNING_BIOME_FALLBACKS = { "ElectricBiome", "ElectriBiome", "PeaksBiome" }

local function getLightningBiomeFolderNames()
	local names = {}
	local seen = {}

	local function addName(name)
		if typeof(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end

	for _, name in ipairs(LIGHTNING_BIOME_FALLBACKS) do
		addName(name)
	end

	local configuredNames = CreatureData.GetBiomeFolderNamesForElement and CreatureData.GetBiomeFolderNamesForElement("Lightning")
	if configuredNames then
		for _, name in ipairs(configuredNames) do
			addName(name)
		end
	end

	return names
end

local function findLightningBiomeFolder(biomes)
	if not biomes then return nil end
	for _, name in ipairs(getLightningBiomeFolderNames()) do
		local folder = biomes:FindFirstChild(name)
		if folder then
			return folder
		end
	end
	return nil
end

local function collectGroundPartsForBiome(folder)
	local parts = {}
	if not folder then return parts end

	local ground = folder:FindFirstChild("ElectricGround") or folder:FindFirstChild("ElectriGround")
	if ground then
		if ground:IsA("BasePart") then
			table.insert(parts, ground)
		elseif ground:IsA("Model") or ground:IsA("Folder") then
			for _, desc in ipairs(ground:GetDescendants()) do
				if desc:IsA("BasePart") then table.insert(parts, desc) end
			end
		end
	end

	if #parts == 0 then
		for _, child in ipairs(folder:GetDescendants()) do
			if child:IsA("BasePart") and child.Size.X > 5 and child.Size.Z > 5 then
				table.insert(parts, child)
			end
		end
	end

	return parts
end

local function getSpawnHeightOffset()
	local minOffset = math.floor(tonumber(cfg("ElectroBallMinHeightAboveGround", MIN_HEIGHT_ABOVE_GROUND)) or MIN_HEIGHT_ABOVE_GROUND)
	local maxOffset = math.floor(tonumber(cfg("ElectroBallMaxHeightAboveGround", MAX_HEIGHT_ABOVE_GROUND)) or MAX_HEIGHT_ABOVE_GROUND)
	if minOffset < 1 then minOffset = 1 end
	if maxOffset < minOffset then
		minOffset, maxOffset = maxOffset, minOffset
		if minOffset < 1 then minOffset = 1 end
	end
	return math.random(minOffset, maxOffset)
end

-- Get surface Y at (x, z) via raycast
local function getSurfaceY(x, z, fromY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local origin = Vector3.new(x, (fromY or 100) + 5, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -200, 0), params)
	if result then
		return result.Position.Y + 0.1
	end
	return fromY or 0
end

-- Create growing sphere AOE: red sphere that emanates from center over CHARGE_SECONDS
local function createAOEVisual(position, radius, chargeSeconds)
	local folder = Instance.new("Folder")
	folder.Name = "ElectroBallAOE"

	-- Growing sphere (starts tiny at center, expands to full radius - no vertical line)
	local sphere = Instance.new("Part")
	sphere.Name = "AOESphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(0.5, 0.5, 0.5)
	sphere.CFrame = CFrame.new(position)
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Material = Enum.Material.Neon
	sphere.Color = Color3.fromRGB(255, 50, 50)
	sphere.Transparency = 0.4
	sphere.Parent = folder

	local targetSize = Vector3.new(radius * 2, radius * 2, radius * 2)
	local tween = TweenService:Create(sphere, TweenInfo.new(chargeSeconds, Enum.EasingStyle.Linear), { Size = targetSize })
	tween:Play()
	return folder, tween
end

-- Electrical explosion burst at position when AOE triggers
local function createExplosionEffect(position)
	local folder = Instance.new("Folder")
	folder.Name = "ElectroBallExplosion"
	folder.Parent = biomeFolder

	-- Bright flash sphere that expands and fades
	local flash = Instance.new("Part")
	flash.Name = "Flash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(2, 2, 2)
	flash.CFrame = CFrame.new(position)
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(200, 220, 255)
	flash.Transparency = 0
	flash.Parent = folder

	local radius = cfg("ElectroBallRadius", AOE_RADIUS)
	TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = Vector3.new(radius * 2.5, radius * 2.5, radius * 2.5),
		Transparency = 1,
	}):Play()

	-- Sparks / electrical particles
	local sparks = Instance.new("Part")
	sparks.Name = "SparksAnchor"
	sparks.Anchored = true
	sparks.CanCollide = false
	sparks.Transparency = 1
	sparks.Size = Vector3.new(0.1, 0.1, 0.1)
	sparks.CFrame = CFrame.new(position)
	sparks.Parent = folder

	local emit = Instance.new("ParticleEmitter")
	emit.Name = "ElectricSparks"
	emit.Color = ColorSequence.new(Color3.fromRGB(180, 200, 255))
	emit.Size = NumberSequence.new({ { 0, 0 }, { 0.5, 1.5 }, { 1, 0 } })
	emit.Transparency = NumberSequence.new({ { 0, 0 }, { 0.7, 0.5 }, { 1, 1 } })
	emit.Lifetime = NumberRange.new(0.3, 0.6)
	emit.Rate = 80
	emit.Speed = NumberRange.new(15, 35)
	emit.SpreadAngle = Vector2.new(180, 180)
	emit.LightEmission = 1
	emit.LightInfluence = 0
	emit.Parent = sparks

	task.delay(0.6, function()
		if folder and folder.Parent then folder:Destroy() end
	end)
end

-- Apply damage and stun to entities in radius
local function applyHazardEffect(center, radius)
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart")
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then continue end
		local dist = (root.Position - center).Magnitude
		if dist > radius then continue end

		local pct = cfg("ElectroBallDamagePercent", DAMAGE_PERCENT)
		local damage = math.ceil(humanoid.MaxHealth * pct)
		humanoid:TakeDamage(damage)

		-- Stun: zero WalkSpeed/JumpPower for STUN_SECONDS (Lightning companion = resistant)
		local hasLightningCompanion = false
		for _, compModel in ipairs(CollectionService:GetTagged(COMPANION_TAG)) do
			if compModel.Parent and compModel:GetAttribute("OwnerUserId") == player.UserId then
				local cid = compModel:GetAttribute("CreatureId")
				local cinfo = cid and CreatureData.GetById(cid)
				if cinfo and cinfo.element == "Lightning" then
					hasLightningCompanion = true
					break
				end
			end
		end
		if not hasLightningCompanion then
			local origWalk = humanoid.WalkSpeed
			local origJump = humanoid.JumpPower
			local stunSec = cfg("ElectroBallStunSeconds", STUN_SECONDS)
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			task.delay(stunSec, function()
				if humanoid and humanoid.Parent then
					humanoid.WalkSpeed = origWalk
					humanoid.JumpPower = origJump
				end
			end)
		end
	end

	-- World creatures
	if WorldCreatureHP then
		for _, model in ipairs(CollectionService:GetTagged(WORLD_CREATURE_TAG)) do
			if not model.Parent or model:GetAttribute("Fainted") then continue end
			local body = (CreatureModelLoader and CreatureModelLoader.GetBodyPart and CreatureModelLoader.GetBodyPart(model))
				or model:FindFirstChild("Body") or model.PrimaryPart
			if not body then continue end
			local dist = (body.Position - center).Magnitude
			if dist > radius then continue end

			local hp, maxHp = WorldCreatureHP.GetHP(model)
			if maxHp and maxHp > 0 then
				local pct = cfg("ElectroBallDamagePercent", DAMAGE_PERCENT)
				local damage = math.ceil(maxHp * pct)
				WorldCreatureHP.DamageCreature(model, damage, nil)
			end
			-- Lightning creatures immune to stun
			local cid = model:GetAttribute("CreatureId")
			local info = cid and CreatureData.GetById(cid)
			if not (info and info.element == "Lightning") then
				local stunSec = cfg("ElectroBallStunSeconds", STUN_SECONDS)
				model:SetAttribute("StunnedUntil", tick() + stunSec)
			end
		end
	end

	-- Companions (FavoriteCreature)
	local FavoriteCreatureSystem = nil
	pcall(function() FavoriteCreatureSystem = require(ServerScriptService.FavoriteCreatureSystem) end)
	if FavoriteCreatureSystem and FavoriteCreatureSystem.DamageCompanion then
		for _, model in ipairs(CollectionService:GetTagged(COMPANION_TAG)) do
			if not model.Parent then continue end
			local body = (CreatureModelLoader and CreatureModelLoader.GetBodyPart and CreatureModelLoader.GetBodyPart(model))
				or model:FindFirstChild("Body") or model.PrimaryPart
			if not body then continue end
			local dist = (body.Position - center).Magnitude
			if dist > radius then continue end

			local ownerId = model:GetAttribute("OwnerUserId")
			local player = ownerId and Players:GetPlayerByUserId(ownerId)
			if player and player.Parent then
				local creatureId = model:GetAttribute("CreatureId")
				local info = creatureId and CreatureData.GetById(creatureId)
				local maxHp = (info and info.health) or 100
				local pct = cfg("ElectroBallDamagePercent", DAMAGE_PERCENT)
				local damage = math.ceil(maxHp * pct)
				FavoriteCreatureSystem.DamageCompanion(player, damage, nil)
			end
			-- Lightning companions immune to stun
			local cid = model:GetAttribute("CreatureId")
			local info = cid and CreatureData.GetById(cid)
			if not (info and info.element == "Lightning") then
				local stunSec = cfg("ElectroBallStunSeconds", STUN_SECONDS)
				model:SetAttribute("StunnedUntil", tick() + stunSec)
			end
		end
	else
		local stunSec = cfg("ElectroBallStunSeconds", STUN_SECONDS)
		for _, model in ipairs(CollectionService:GetTagged(COMPANION_TAG)) do
			if not model.Parent then continue end
			local body = (CreatureModelLoader and CreatureModelLoader.GetBodyPart and CreatureModelLoader.GetBodyPart(model))
				or model:FindFirstChild("Body") or model.PrimaryPart
			if not body then continue end
			local dist = (body.Position - center).Magnitude
			if dist > radius then continue end
			-- Lightning companions immune to stun
			local cid = model:GetAttribute("CreatureId")
			local info = cid and CreatureData.GetById(cid)
			if not (info and info.element == "Lightning") then
				model:SetAttribute("StunnedUntil", tick() + stunSec)
			end
		end
	end
end

local function getHazardsFolder()
	local destFolder = biomeFolder:FindFirstChild("Hazards")
	if not destFolder then
		destFolder = Instance.new("Folder")
		destFolder.Name = "Hazards"
		destFolder.Parent = biomeFolder
	end
	return destFolder
end

local function clearElectroBallInstances()
	local destFolder = biomeFolder and biomeFolder:FindFirstChild("Hazards")
	for index, orb in pairs(electroBallInstances) do
		if orb and orb.Parent then
			orb:Destroy()
		end
		electroBallInstances[index] = nil
	end
	if destFolder then
		for _, child in ipairs(destFolder:GetChildren()) do
			if child.Name:match("^ElectroBall_") then
				child:Destroy()
			end
		end
	end
end

-- Activate one ElectroBall (AOE charge + damage) at a given index/position
local function activateElectroBallAt(position, index)
	local radius = cfg("ElectroBallRadius", AOE_RADIUS)
	local charge = cfg("ElectroBallChargeSeconds", CHARGE_SECONDS)
	local orb = electroBallInstances[index]
	local folder, tween = createAOEVisual(position, radius, charge)
	folder.Parent = biomeFolder
	tween.Completed:Connect(function()
		applyHazardEffect(position, radius)
		createExplosionEffect(position)
		task.delay(0.5, function()
			if folder and folder.Parent then folder:Destroy() end
			if orb and orb.Parent then
				orb:Destroy()
			end
			if electroBallInstances[index] == orb then
				electroBallInstances[index] = nil
			end
		end)
	end)
end

local collectPointPositions

-- Pick random positions within ground bounds for this activation cycle
local function pickRandomPositionsForCycle()
	local count = cfg("ElectroBallCount", ELECTROBALL_COUNT)
	local minX, maxX, minZ, maxZ, refY = getGroundBounds()
	if minX >= maxX or minZ >= maxZ then return electroBallPositions end

	local width = maxX - minX
	local depth = maxZ - minZ
	local margin = math.min(RANDOM_POSITION_MARGIN, math.max(4, math.min(width, depth) * 0.15))
	local usableWidth = math.max(12, width - margin * 2)
	local usableDepth = math.max(12, depth - margin * 2)
	local area = usableWidth * usableDepth
	local minSpacing = math.max(6, math.min(16, math.sqrt(area / math.max(count, 1)) * 0.45))

	local positions = {}
	local pointPositions = collectPointPositions()
	for _, pos in ipairs(pointPositions) do
		table.insert(positions, pos)
		if #positions >= count then
			return positions
		end
	end

	local attempts = math.max(count * 12, 60)
	while #positions < count and attempts > 0 do
		attempts = attempts - 1
		local x = minX + margin + math.random() * usableWidth
		local z = minZ + margin + math.random() * usableDepth
		local tooClose = false
		for _, existing in ipairs(positions) do
			local dx = existing.X - x
			local dz = existing.Z - z
			if dx * dx + dz * dz < minSpacing * minSpacing then
				tooClose = true
				break
			end
		end
		if not tooClose or attempts < count then
			local y = getSurfaceY(x, z, refY) + getSpawnHeightOffset()
			table.insert(positions, Vector3.new(x, y, z))
		end
	end

	return positions
end

collectPointPositions = function()
	local positions = {}
	for _, child in ipairs(biomeFolder:GetDescendants()) do
		if not child:IsA("BasePart") then continue end
		local name = child.Name
		if name == "SpawnPoint" or name == "DungeonPoint" or name == "BossPoint" then
			local p = child.Position
			local variance = (math.random() * 2 - 1) * GRID_VARIANCE
			local varianceZ = (math.random() * 2 - 1) * GRID_VARIANCE
			local y = getSurfaceY(p.X + variance, p.Z + varianceZ, p.Y) + getSpawnHeightOffset()
			table.insert(positions, Vector3.new(p.X + variance, y, p.Z + varianceZ))
		end
	end
	return positions
end

-- Grid positions over ElectricGround bounds
local function getGroundBounds()
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local anyY = 0
	for _, part in ipairs(groundParts) do
		local cf, size = part.CFrame, part.Size
		local half = size * 0.5
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local w = cf:PointToWorldSpace(Vector3.new(sx * half.X, 0, sz * half.Z))
				minX = math.min(minX, w.X); maxX = math.max(maxX, w.X)
				minZ = math.min(minZ, w.Z); maxZ = math.max(maxZ, w.Z)
			end
		end
		anyY = cf.Position.Y
	end
	return minX, maxX, minZ, maxZ, anyY
end

local function buildElectroBallPositions()
	electroBallPositions = {}
	local count = cfg("ElectroBallCount", ELECTROBALL_COUNT)
	local pointPositions = collectPointPositions()
	for _, pos in ipairs(pointPositions) do
		table.insert(electroBallPositions, pos)
	end
	local remaining = count - #electroBallPositions
	if remaining <= 0 then
		while #electroBallPositions > count do
			table.remove(electroBallPositions)
		end
		return
	end
	local minX, maxX, minZ, maxZ, refY = getGroundBounds()
	if minX >= maxX or minZ >= maxZ then return end
	local cols = math.ceil(math.sqrt(remaining))
	local rows = math.ceil(remaining / cols)
	local stepX = (maxX - minX) / (cols + 1)
	local stepZ = (maxZ - minZ) / (rows + 1)
	for i = 0, remaining - 1 do
		local col = i % cols
		local row = math.floor(i / cols)
		local baseX = minX + stepX * (col + 1)
		local baseZ = minZ + stepZ * (row + 1)
		local variance = (math.random() * 2 - 1) * GRID_VARIANCE
		local varianceZ = (math.random() * 2 - 1) * GRID_VARIANCE
		local x = baseX + variance
		local z = baseZ + varianceZ
		local y = getSurfaceY(x, z, refY) + getSpawnHeightOffset()
		table.insert(electroBallPositions, Vector3.new(x, y, z))
	end
end

local function findBiomeAndGround()
	local biomes = Workspace:FindFirstChild("Biomes")
	if not biomes then
		print("[ElectricBiomeHazardSystem] findBiomeAndGround: Workspace.Biomes not found")
		return false
	end

	local candidateFolders = {}
	for _, name in ipairs(getLightningBiomeFolderNames()) do
		local folder = biomes:FindFirstChild(name)
		if folder then
			table.insert(candidateFolders, folder)
		end
	end

	if #candidateFolders == 0 then
		print("[ElectricBiomeHazardSystem] findBiomeAndGround: No lightning biome folder found under Biomes (expected one of: " .. table.concat(getLightningBiomeFolderNames(), ", ") .. "; have: " .. table.concat((function()
			local names = {}
			for _, c in ipairs(biomes:GetChildren()) do table.insert(names, c.Name) end
			return names
		end)(), ", ") .. ")")
		return false
	end

	for _, folder in ipairs(candidateFolders) do
		local candidateGroundParts = collectGroundPartsForBiome(folder)
		if #candidateGroundParts > 0 then
			biomeFolder = folder
			groundParts = candidateGroundParts
			return true
		end
	end

	biomeFolder = candidateFolders[1]
	groundParts = {}
	print("[ElectricBiomeHazardSystem] findBiomeAndGround: No ElectricGround/ElectriGround and no large parts in any lightning biome folder (checked: " .. table.concat((function()
		local names = {}
		for _, folder in ipairs(candidateFolders) do table.insert(names, folder.Name) end
		return names
	end)(), ", ") .. ")")
	return false
end

-- Ensure ReplicatedStorage.Hazards.ElectroBall exists; create a simple default Part if missing (so electroballs still spawn)
local function ensureElectroBallTemplate()
	local hazards = ReplicatedStorage:FindFirstChild("Hazards")
	if not hazards then
		hazards = Instance.new("Folder")
		hazards.Name = "Hazards"
		hazards.Parent = ReplicatedStorage
	end
	local template = hazards:FindFirstChild("ElectroBall")
	if not template then
		template = Instance.new("Part")
		template.Name = "ElectroBall"
		template.Shape = Enum.PartType.Ball
		template.Size = Vector3.new(2, 2, 2)
		template.Anchored = true
		template.CanCollide = false
		template.Material = Enum.Material.Neon
		template.Color = Color3.fromRGB(100, 180, 255)
		template.Transparency = 0.3
		template.Parent = hazards
		print("[ElectricBiomeHazardSystem] Created default ReplicatedStorage.Hazards.ElectroBall (add a custom model in Studio to override)")
	end
	return template
end

local function placeElectroBalls()
	local template = ensureElectroBallTemplate()
	if not template then
		return
	end

	clearElectroBallInstances()
	electroBallInstances = {}
	local destFolder = getHazardsFolder()
	for i, pos in ipairs(electroBallPositions) do
		local clone = template:Clone()
		clone.Name = "ElectroBall_" .. i
		if clone:IsA("BasePart") then
			clone.CFrame = CFrame.new(pos)
			clone.Anchored = true
			clone.CanCollide = false
		elseif clone:IsA("Model") then
			clone:SetPivot(CFrame.new(pos))
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
				end
			end
		else
			local primary = clone:FindFirstChildWhichIsA("BasePart")
			if primary then
				primary.CFrame = CFrame.new(pos)
				primary.Anchored = true
				primary.CanCollide = false
			end
		end
		clone.Parent = destFolder
		electroBallInstances[i] = clone
	end
end

local function startElectroBallLoop()
	ensureElectroBallTemplate()
	buildElectroBallPositions()
	if #electroBallPositions == 0 then
		warn("[ElectricBiomeHazardSystem] No ElectroBall positions (need ground or points in the lightning biome folder)")
		return
	end

	local function runCycle()
		electroBallPositions = pickRandomPositionsForCycle()
		if #electroBallPositions == 0 then
			warn("[ElectricBiomeHazardSystem] Could not find random ElectroBall positions for this cycle")
			return
		end
		placeElectroBalls()
		for index, position in ipairs(electroBallPositions) do
			activateElectroBallAt(position, index)
		end
	end

	running = true
	lastActivationTime = tick()
	activationIndex = 0
	print("[ElectricBiomeHazardSystem] Initialized - " .. #electroBallPositions .. " ElectroBalls will spawn every " .. cfg("ElectroBallSpawnInterval", SPAWN_INTERVAL) .. "s")
	runCycle()
	RunService.Heartbeat:Connect(function()
		if not running or not biomeFolder or not biomeFolder.Parent then return end
		local interval = cfg("ElectroBallSpawnInterval", SPAWN_INTERVAL)
		if tick() - lastActivationTime >= interval then
			lastActivationTime = tick()
			runCycle()
		end
	end)
end

function ElectricBiomeHazardSystem.Init()
	print("[ElectricBiomeHazardSystem] Init() called")
	if running then
		print("[ElectricBiomeHazardSystem] Already running, skipping")
		return
	end
	if findBiomeAndGround() then
		print("[ElectricBiomeHazardSystem] Biome and ground found, starting loop")
		startElectroBallLoop()
		return
	end
	-- Biome may be created after server start (e.g. by map loader); wait briefly then retry
	print("[ElectricBiomeHazardSystem] Lightning biome not found yet. Waiting up to 10s for Workspace.Biomes to contain one of: " .. table.concat(getLightningBiomeFolderNames(), ", "))
	task.spawn(function()
		local biomes = Workspace:WaitForChild("Biomes", 10)
		if not biomes then
			warn("[ElectricBiomeHazardSystem] Workspace.Biomes not found after 10s. Ensure the lightning biome exists with ElectricGround or large parts.")
			return
		end
		local biome = findLightningBiomeFolder(biomes)
		if not biome then
			local deadline = tick() + 10
			repeat
				task.wait(0.25)
				biome = findLightningBiomeFolder(biomes)
			until biome or tick() >= deadline
		end
		if not biome then
			warn("[ElectricBiomeHazardSystem] No lightning biome folder found under Biomes. Add one named " .. table.concat(getLightningBiomeFolderNames(), ", ") .. " with ElectricGround or large parts.")
			return
		end
		if running then return end
		if not findBiomeAndGround() then
			warn("[ElectricBiomeHazardSystem] ElectricGround or suitable parts not found in " .. biome.Name .. ".")
			return
		end
		print("[ElectricBiomeHazardSystem] Deferred: Biome found, starting loop")
		startElectroBallLoop()
	end)
end

function ElectricBiomeHazardSystem.Stop()
	running = false
end

return ElectricBiomeHazardSystem







