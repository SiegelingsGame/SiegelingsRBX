-- BiomeZone.lua - ReplicatedStorage/Modules/BiomeZone
-- Server-safe biome region for ingredients (matches BiomeSkyboxClient: outer baseplates, hub, roads, inner wedges).
-- Returns sky names (e.g. DesertSky, CaveSky) or nil for hub/roads/default.

local Workspace = game:GetService("Workspace")

local GameConfig = require(script.Parent.GameConfig)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local BiomeZone = {}

local VERTICAL_BUFFER = 900
local GROUND_VERTICAL_BUFFER = 100

local cached = {
	outerZones = nil, -- { part, sky }
	hubParts = nil,
	roadPartList = nil,
	roadAngles = nil,
	hubCenter = nil,
	innerWedges = nil,
	innerMaxRadius = nil,
	innerWallPartsBySky = nil, -- sky -> BasePart
	innerBiomeXZBoundsBySky = nil, -- sky -> {minX,maxX,minZ,maxZ}
	resolved = false,
}

local function resolvePath(pathParts)
	local current = Workspace
	for _, name in ipairs(pathParts) do
		current = current:FindFirstChild(name)
		if not current then
			return nil
		end
	end
	return current
end

local function ensureResolved()
	if cached.resolved then
		return
	end
	cached.resolved = true

	local cfg = GameConfig.BiomeZone or {}
	cached.innerMaxRadius = tonumber(cfg.InnerWedgeMaxRadius) or 1000

	cached.outerZones = {}
	for _, def in ipairs(cfg.OuterZones or {}) do
		local part = resolvePath(def.path or {})
		if part and part:IsA("BasePart") then
			table.insert(cached.outerZones, { part = part, sky = def.sky })
		end
	end

	cached.hubParts = {}
	for _, pathParts in ipairs(cfg.HubParts or {}) do
		local part = resolvePath(pathParts)
		if part and part:IsA("BasePart") then
			table.insert(cached.hubParts, part)
		end
	end

	cached.roadPartList = {}
	local roadNames = cfg.RoadNames or { "CaveRoad", "ElectricRoad", "DesertRoad", "WetRoad" }
	local roadsFolder = Workspace:FindFirstChild("Roads")
	if roadsFolder then
		for _, name in ipairs(roadNames) do
			local part = roadsFolder:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				table.insert(cached.roadPartList, part)
			end
		end
	end

	local hubCenter = Vector3.zero
	if #cached.hubParts > 0 then
		hubCenter = cached.hubParts[1].Position
	end
	cached.hubCenter = hubCenter

	cached.roadAngles = {}
	for _, part in ipairs(cached.roadPartList) do
		local dx = part.Position.X - hubCenter.X
		local dz = part.Position.Z - hubCenter.Z
		cached.roadAngles[part.Name] = math.atan2(dz, dx)
	end

	cached.innerWedges = cfg.InnerWedges or {
		{ from = "ElectricRoad", to = "CaveRoad", sky = "EarthSky" },
		{ from = "CaveRoad", to = "WetRoad", sky = "FireSky" },
		{ from = "WetRoad", to = "DesertRoad", sky = "IceSky" },
		{ from = "DesertRoad", to = "ElectricRoad", sky = "WindSky" },
	}

	-- Inner biome wall parts (Workspace.ForestGround / Forestground)
	local innerWallNameBySky = {
		WindSky = "WindWall",
		FireSky = "LavaWall",
		EarthSky = "JungleWall",
		IceSky = "IceWall",
	}
	cached.innerWallPartsBySky = {}
	cached.innerBiomeXZBoundsBySky = {}
	local function pickContainer(root)
		if not root then return nil end
		for _, name in ipairs({ "ForestGround", "Forestground", "ForestsGround" }) do
			local found = root:FindFirstChild(name)
			if found and (found:IsA("Model") or found:IsA("Folder")) then
				return found
			end
		end
		return nil
	end
	local fg = pickContainer(Workspace) or pickContainer(Workspace:FindFirstChild("Terrain"))
	if fg then
		for sky, wallName in pairs(innerWallNameBySky) do
			local wall = fg:FindFirstChild(wallName, true)
			if wall and (wall:IsA("BasePart") or wall:IsA("Model")) then
				cached.innerWallPartsBySky[sky] = wall
			end
		end
	end

	-- Build inner biome XZ "box" bounds using (fromRoad + toRoad + wall + hubCenter).
	local roadByName = {}
	for _, part in ipairs(cached.roadPartList) do
		roadByName[part.Name] = part
	end
	local function clampBoundsToSkyQuadrant(bounds, sky)
		if sky == "EarthSky" then
			bounds.maxX = math.min(bounds.maxX, hubCenter.X)
			bounds.maxZ = math.min(bounds.maxZ, hubCenter.Z)
		elseif sky == "FireSky" then
			bounds.minX = math.max(bounds.minX, hubCenter.X)
			bounds.maxZ = math.min(bounds.maxZ, hubCenter.Z)
		elseif sky == "IceSky" then
			bounds.minX = math.max(bounds.minX, hubCenter.X)
			bounds.minZ = math.max(bounds.minZ, hubCenter.Z)
		elseif sky == "WindSky" then
			bounds.maxX = math.min(bounds.maxX, hubCenter.X)
			bounds.minZ = math.max(bounds.minZ, hubCenter.Z)
		end
		return bounds
	end
	local function expandPartXZBounds(minX, maxX, minZ, maxZ, part)
		if not part then
			return minX, maxX, minZ, maxZ
		end
		local cf, size
		if part:IsA("BasePart") then
			cf, size = part.CFrame, part.Size
		elseif part:IsA("Model") then
			local ok, boxCf, boxSize = pcall(function()
				return part:GetBoundingBox()
			end)
			if not ok then
				return minX, maxX, minZ, maxZ
			end
			cf, size = boxCf, boxSize
		else
			return minX, maxX, minZ, maxZ
		end
		-- Rotation-aware world AABB for the part.
		local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
		local r = cf.RightVector
		local u = cf.UpVector
		local l = cf.LookVector
		local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(l.X) * hz
		local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(l.Z) * hz
		local p = cf.Position
		return math.min(minX, p.X - ex),
			math.max(maxX, p.X + ex),
			math.min(minZ, p.Z - ez),
			math.max(maxZ, p.Z + ez)
	end
	for _, wedge in ipairs(cached.innerWedges) do
		local wall = cached.innerWallPartsBySky[wedge.sky]
		local fromRoad = roadByName[wedge.from]
		local toRoad = roadByName[wedge.to]
		if wall and fromRoad and toRoad then
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			minX, maxX, minZ, maxZ = expandPartXZBounds(minX, maxX, minZ, maxZ, fromRoad)
			minX, maxX, minZ, maxZ = expandPartXZBounds(minX, maxX, minZ, maxZ, toRoad)
			minX, maxX, minZ, maxZ = expandPartXZBounds(minX, maxX, minZ, maxZ, wall)
			minX = math.min(minX, hubCenter.X)
			maxX = math.max(maxX, hubCenter.X)
			minZ = math.min(minZ, hubCenter.Z)
			maxZ = math.max(maxZ, hubCenter.Z)
			cached.innerBiomeXZBoundsBySky[wedge.sky] = clampBoundsToSkyQuadrant(
				{ minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ },
				wedge.sky
			)
		end
	end
end

local function isOverPart(position, part, verticalBuffer)
	verticalBuffer = verticalBuffer or GROUND_VERTICAL_BUFFER
	local cf = part.CFrame
	local size = part.Size
	local localPos = cf:PointToObjectSpace(position)
	local halfX, halfZ, halfY = size.X / 2, size.Z / 2, size.Y / 2
	if math.abs(localPos.X) > halfX or math.abs(localPos.Z) > halfZ then
		return false
	end
	if localPos.Y < -halfY or localPos.Y > halfY + verticalBuffer then
		return false
	end
	return true
end

local function isOverPartXZ(position, part)
	local cf = part.CFrame
	local size = part.Size
	local localPos = cf:PointToObjectSpace(position)
	local halfX, halfZ = size.X / 2, size.Z / 2
	return math.abs(localPos.X) <= halfX and math.abs(localPos.Z) <= halfZ
end

local function normalizeAngle(a)
	a = a % (2 * math.pi)
	if a > math.pi then
		a = a - 2 * math.pi
	end
	return a
end

local function isAngleBetween(a, fromAngle, toAngle)
	local sweep = normalizeAngle(toAngle - fromAngle)
	local test = normalizeAngle(a - fromAngle)
	if sweep > 0 then
		return test >= 0 and test <= sweep
	end
	return test >= 0 or test <= sweep
end

function BiomeZone.InvalidateCache()
	cached.resolved = false
end

--- @return string|nil  DesertSky, ElectricSky, WaterSky, CaveSky, EarthSky, FireSky, IceSky, WindSky, or nil
function BiomeZone.GetIngredientRegion(position)
	ensureResolved()
	if typeof(position) ~= "Vector3" then
		return nil
	end

	for _, zone in ipairs(cached.outerZones) do
		if isOverPart(position, zone.part, VERTICAL_BUFFER) then
			return zone.sky
		end
	end

	for _, part in ipairs(cached.hubParts) do
		if isOverPart(position, part, GROUND_VERTICAL_BUFFER) then
			return nil
		end
	end

	for _, part in ipairs(cached.roadPartList) do
		if isOverPart(position, part, GROUND_VERTICAL_BUFFER) then
			return nil
		end
	end

	for _, zone in ipairs(cached.outerZones) do
		if isOverPartXZ(position, zone.part) then
			return zone.sky
		end
	end

	local hubCenter = cached.hubCenter
	if hubCenter and next(cached.roadAngles) then
		-- Prefer inner biome "box" bounds (roads + wall) so inner back corners
		-- don't fall through to hub/default when slightly outside innerMaxRadius.
		for _, wedge in ipairs(cached.innerWedges) do
			local b = cached.innerBiomeXZBoundsBySky and cached.innerBiomeXZBoundsBySky[wedge.sky]
			if b
				and position.X >= b.minX and position.X <= b.maxX
				and position.Z >= b.minZ and position.Z <= b.maxZ
			then
				return wedge.sky
			end
		end

		-- If wall-driven bounds exist, use box-based routing only for inner zones.
		-- Keep angle wedges only as a fallback when no wall bounds were resolved.
		if cached.innerBiomeXZBoundsBySky and next(cached.innerBiomeXZBoundsBySky) then
			return nil
		end

		local dx = position.X - hubCenter.X
		local dz = position.Z - hubCenter.Z
		local distFromHub = math.sqrt(dx * dx + dz * dz)
		if distFromHub <= cached.innerMaxRadius then
			local playerAngle = math.atan2(dz, dx)
			for _, wedge in ipairs(cached.innerWedges) do
				local fromAngle = cached.roadAngles[wedge.from]
				local toAngle = cached.roadAngles[wedge.to]
				if fromAngle and toAngle then
					if isAngleBetween(playerAngle, fromAngle, toAngle) then
						return wedge.sky
					end
				end
			end
		end
	end

	return nil
end

local function rayDownToGround(xzPos)
	local origin = Vector3.new(xzPos.X, 650, xzPos.Z)
	rayParams.FilterDescendantsInstances = {}
	local hit = Workspace:Raycast(origin, Vector3.new(0, -1200, 0), rayParams)
	if hit then
		return hit.Position + Vector3.new(0, 2, 0)
	end
	return Vector3.new(xzPos.X, 50, xzPos.Z)
end

local function randomXZOnPartTop(part)
	local cf = part.CFrame
	local sz = part.Size
	local lx = (math.random() - 0.5) * sz.X * 0.88
	local lz = (math.random() - 0.5) * sz.Z * 0.88
	local localTop = Vector3.new(lx, sz.Y / 2 + 3, lz)
	return cf:PointToWorldSpace(localTop)
end

--- @param regionName string
--- @return Vector3|nil
function BiomeZone.GetRandomSurfacePositionForRegion(regionName)
	ensureResolved()
	for _, zone in ipairs(cached.outerZones) do
		if zone.sky == regionName then
			return rayDownToGround(randomXZOnPartTop(zone.part))
		end
	end
	local hubCenter = cached.hubCenter
	if hubCenter and next(cached.roadAngles) then
		for _, wedge in ipairs(cached.innerWedges) do
			if wedge.sky == regionName then
				local fromA = cached.roadAngles[wedge.from]
				local toA = cached.roadAngles[wedge.to]
				if fromA and toA then
					local a
					for _ = 1, 40 do
						local try = (math.random() * 2 - 1) * math.pi
						if isAngleBetween(try, fromA, toA) then
							a = try
							break
						end
					end
					if not a then
						a = fromA
					end
					local rad = math.sqrt(math.random()) * cached.innerMaxRadius * 0.9
					local x = hubCenter.X + math.cos(a) * rad
					local z = hubCenter.Z + math.sin(a) * rad
					return rayDownToGround(Vector3.new(x, 0, z))
				end
			end
		end
	end
	return nil
end

return BiomeZone
