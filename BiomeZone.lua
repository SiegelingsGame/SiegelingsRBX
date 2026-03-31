-- BiomeZone.lua - ReplicatedStorage/Modules/BiomeZone
-- Server-safe biome region for ingredients (matches BiomeSkyboxClient logic + Cave).
-- Returns sky names for 7 regions or "Cave", or nil for hub/roads/default.

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
	cavePart = nil,
	caveVerticalRange = nil,
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

	local caveCfg = cfg.Cave or {}
	local cavePath = caveCfg.BaseplatePath or { "Terrain", "CaveBaseplate" }
	local cavePart = resolvePath(cavePath)
	if cavePart and cavePart:IsA("BasePart") then
		cached.cavePart = cavePart
	end
	cached.caveVerticalRange = tonumber(caveCfg.VerticalRange) or 700
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

--- Over CaveBaseplate: XZ on part and within VerticalRange above top surface (world Y).
local function isInCaveRegion(position)
	local part = cached.cavePart
	if not part then
		return false
	end
	if not isOverPartXZ(position, part) then
		return false
	end
	local cf = part.CFrame
	local size = part.Size
	local localPos = cf:PointToObjectSpace(position)
	local halfY = size.Y / 2
	local topLocalY = halfY
	local worldTopY = cf:PointToWorldSpace(Vector3.new(0, topLocalY, 0)).Y
	local maxY = worldTopY + cached.caveVerticalRange
	return position.Y <= maxY and position.Y >= worldTopY - halfY * 2
end

function BiomeZone.InvalidateCache()
	cached.resolved = false
end

--- @return string|nil  DesertSky, ElectricSky, WaterSky, EarthSky, FireSky, IceSky, WindSky, Cave, or nil
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

	if isInCaveRegion(position) then
		return "Cave"
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
	if regionName == "Cave" and cached.cavePart then
		return rayDownToGround(randomXZOnPartTop(cached.cavePart))
	end
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
