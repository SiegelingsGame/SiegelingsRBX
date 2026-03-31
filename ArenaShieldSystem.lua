-- ArenaShieldSystem.lua - ServerScriptService (ModuleScript)
-- Golden dome shield over the arena area. Uses an invisible "ArenaShield" sphere in workspace.Arena
-- to define bounds. Prevents world creatures from entering; they avoid it and cannot spawn within it.
-- Similar to LaserDoorSystem dome but always visible and golden.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local ArenaShieldSystem = {}

local arenaFolder = nil
local arenaShieldPart = nil   -- Invisible sphere defining bounds
local domePart = nil          -- Golden visible dome (ForceField)
local innerGlowPart = nil     -- Inner glow
local domeData = nil          -- { center, radius, radiusXZ, radiusY } for sphere (radiusXZ = radiusY)

-- Sphere containment: (dx/r)^2 + (dy/r)^2 + (dz/r)^2 <= 1
local function isInsideSphere(position, center, radius)
	local dx = position.X - center.X
	local dy = position.Y - center.Y
	local dz = position.Z - center.Z
	local q = (dx / radius) ^ 2 + (dy / radius) ^ 2 + (dz / radius) ^ 2
	return q <= 1
end

-- Push position to just outside sphere surface
local function pushOutsideSphere(center, radius, fromPosition, margin)
	margin = margin or 3
	local diff = fromPosition - center
	local len = diff.Magnitude
	if len < 0.01 then diff = Vector3.new(1, 0, 0); len = 1 end
	local surfaceDist = radius
	return center + diff.Unit * (surfaceDist + margin)
end

-- Find or create ArenaShield in Arena folder
local function ensureArenaShield()
	if arenaShieldPart and arenaShieldPart.Parent then return arenaShieldPart end

	arenaFolder = workspace:FindFirstChild("Arena")
	if not arenaFolder then
		warn("[ArenaShield] No Arena folder in Workspace")
		return nil
	end

	arenaShieldPart = arenaFolder:FindFirstChild("ArenaShield")
	if arenaShieldPart and arenaShieldPart:IsA("BasePart") then
		-- Make it invisible and non-colliding (designer may have left it visible)
		arenaShieldPart.Transparency = 1
		arenaShieldPart.CanCollide = false
		arenaShieldPart.CastShadow = false
		return arenaShieldPart
	end

	-- Create fallback ArenaShield if missing (center at Arena, radius from GameConfig)
	local ac = arenaFolder:FindFirstChild("ArenaCenter")
	local center = ac and ac:IsA("BasePart") and ac.Position or arenaFolder:GetPivot().Position
	local radius = GameConfig.ArenaExclusionRadius or 80

	arenaShieldPart = Instance.new("Part")
	arenaShieldPart.Name = "ArenaShield"
	arenaShieldPart.Shape = Enum.PartType.Ball
	arenaShieldPart.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	arenaShieldPart.Position = center
	arenaShieldPart.Anchored = true
	arenaShieldPart.CanCollide = false
	arenaShieldPart.Transparency = 1
	arenaShieldPart.CastShadow = false
	arenaShieldPart.Parent = arenaFolder

	print("[ArenaShield] Created fallback ArenaShield (radius " .. radius .. ") - place one manually to customize")
	return arenaShieldPart
end

-- Create golden dome visual from ArenaShield bounds
local function createDomeVisual()
	if not arenaShieldPart then return nil end

	local center = arenaShieldPart.Position
	local radius = math.max(arenaShieldPart.Size.X, arenaShieldPart.Size.Y, arenaShieldPart.Size.Z) * 0.5

	-- Main dome (ForceField Ball, golden)
	domePart = Instance.new("Part")
	domePart.Name = "ArenaShieldDome"
	domePart.Shape = Enum.PartType.Ball
	domePart.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	domePart.Position = center
	domePart.Anchored = true
	domePart.CanCollide = false
	domePart.CastShadow = false
	domePart.Material = Enum.Material.ForceField
	domePart.Color = Color3.fromRGB(255, 215, 0)  -- Golden
	domePart.Transparency = 0.72
	domePart.Parent = arenaFolder

	-- Inner glow (slightly smaller, Neon)
	innerGlowPart = Instance.new("Part")
	innerGlowPart.Name = "ArenaShieldInner"
	innerGlowPart.Shape = Enum.PartType.Ball
	innerGlowPart.Size = Vector3.new(radius * 2 - 2, radius * 2 - 2, radius * 2 - 2)
	innerGlowPart.Position = center
	innerGlowPart.Anchored = true
	innerGlowPart.CanCollide = false
	innerGlowPart.CastShadow = false
	innerGlowPart.Material = Enum.Material.Neon
	innerGlowPart.Color = Color3.fromRGB(255, 230, 100)
	innerGlowPart.Transparency = 0.9
	innerGlowPart.Parent = arenaFolder

	-- Point light for ambient glow
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 215, 0)
	light.Brightness = 2
	light.Range = radius * 0.8
	light.Parent = domePart

	domeData = { center = center, radius = radius, radiusXZ = radius, radiusY = radius }
	return domeData
end

-- Protection loop: push WorldCreatures and AIRaiders out of dome
local function runShieldLoop()
	while true do
		task.wait(0.4)

		if not domeData or not domePart or not domePart.Parent then continue end

		local center = domeData.center
		local radius = domeData.radius

		-- Push WORLD CREATURES out
		for _, creature in ipairs(CollectionService:GetTagged("WorldCreature")) do
			local body = creature:FindFirstChild("Body")
			if not body then
				body = creature:FindFirstChildWhichIsA("BasePart")
			end
			if not body then continue end
			if isInsideSphere(body.Position, center, radius) then
				local pushPos = pushOutsideSphere(center, radius, body.Position, 2)
				body.Position = pushPos
				local core = creature:FindFirstChild("Core")
				if core then core.Position = pushPos end
			end
		end

		-- Push RAID CREATURES out
		for _, raider in ipairs(CollectionService:GetTagged("AIRaider")) do
			local body = raider:FindFirstChild("Body")
			if not body then
				body = raider:FindFirstChildWhichIsA("BasePart")
			end
			if not body then continue end
			if isInsideSphere(body.Position, center, radius) then
				local pushPos = pushOutsideSphere(center, radius, body.Position, 2)
				body.Position = pushPos
				local core = raider:FindFirstChild("Core")
				if core then core.Position = pushPos end
			end
		end
	end
end

-- Pulse animation for dome
local function runPulseAnimation()
	while domePart and domePart.Parent do
		local t = tick() * 0.6
		domePart.Transparency = 0.68 + math.sin(t) * 0.08
		if innerGlowPart and innerGlowPart.Parent then
			innerGlowPart.Transparency = 0.86 + math.sin(t * 1.2) * 0.06
		end
		RunService.Heartbeat:Wait()
	end
end

-- PUBLIC API

-- Check if position is inside arena shield (for CreatureAI avoidance, CreatureSpawner exclusion)
-- Returns: inside (bool), center (Vector3), radius (number)
function ArenaShieldSystem.IsInsideArenaShield(position)
	if not domeData then return false, nil, nil end
	local inside = isInsideSphere(position, domeData.center, domeData.radius)
	return inside, domeData.center, domeData.radius
end

-- Push a position to just outside the arena shield (for spawn rejection)
-- Returns: Vector3 outside the shield, or original position if no shield
function ArenaShieldSystem.PushOutsideArenaShield(position, margin)
	if not domeData then return position end
	if not isInsideSphere(position, domeData.center, domeData.radius) then
		return position
	end
	return pushOutsideSphere(domeData.center, domeData.radius, position, margin or 5)
end

-- Check if a position is inside (for spawn rejection without needing to push)
function ArenaShieldSystem.IsPositionInside(position)
	if not domeData then return false end
	return isInsideSphere(position, domeData.center, domeData.radius)
end

-- Init: find ArenaShield, create dome, start protection loop
function ArenaShieldSystem.Init()
	ensureArenaShield()
	if not arenaShieldPart then return end

	createDomeVisual()
	if domeData then
		task.spawn(runShieldLoop)
		task.spawn(runPulseAnimation)
		print("[ArenaShield] Golden dome active - radius " .. domeData.radius .. " studs")
	else
		warn("[ArenaShield] Failed to create dome visual")
	end
end

return ArenaShieldSystem
