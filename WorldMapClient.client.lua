-- WorldMapClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- World map image with live player position. Open via HUD [M] Map (HUDToggleMenu → WorldMapGUI).
-- Last updated: 2026-04-24 22:55

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local WM = GameConfig.WorldMap
if not WM or WM.Enabled ~= true then
	return
end

-- Map-only mode: show only the map image (no pins, base markers, arrows, or calibration/capture UI).
-- Re-enable markers/calibration later by flipping this to false.
local MAP_ONLY = true

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = {
	bg = Color3.fromRGB(14, 16, 24),
	accent = Color3.fromRGB(120, 200, 255),
	gold = Color3.fromRGB(232, 175, 72),
	move = Color3.fromRGB(90, 220, 255),
	white = Color3.new(1, 1, 1),
	muted = Color3.fromRGB(140, 145, 160),
	base = Color3.fromRGB(120, 200, 255),
}

local function resolvePath(root, pathParts)
	local inst = root
	for _, name in ipairs(pathParts or {}) do
		inst = inst and inst:FindFirstChild(name)
	end
	return inst
end

local function expandPartXZ(minX, maxX, minZ, maxZ, part)
	if not part or not part:IsA("BasePart") then
		return minX, maxX, minZ, maxZ
	end
	local e = part.Size * 0.5
	local p = part.Position
	return math.min(minX, p.X - e.X),
		math.max(maxX, p.X + e.X),
		math.min(minZ, p.Z - e.Z),
		math.max(maxZ, p.Z + e.Z)
end

local function computeWorldXZBounds()
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local biome = GameConfig.BiomeZone
	if WM.UseAutoBounds and biome then
		for _, def in ipairs(biome.OuterZones or {}) do
			local part = resolvePath(workspace, def.path or {})
			minX, maxX, minZ, maxZ = expandPartXZ(minX, maxX, minZ, maxZ, part)
		end
		for _, pathParts in ipairs(biome.HubParts or {}) do
			local part = resolvePath(workspace, pathParts)
			minX, maxX, minZ, maxZ = expandPartXZ(minX, maxX, minZ, maxZ, part)
		end
	end
	if minX == math.huge or maxX <= minX or maxZ <= minZ then
		return {
			minX = WM.MinWorldXZ.X,
			maxX = WM.MaxWorldXZ.X,
			minZ = WM.MinWorldXZ.Y,
			maxZ = WM.MaxWorldXZ.Y,
		}
	end
	local pad = math.clamp(tonumber(WM.AutoBoundsPadFraction) or 0.08, 0, 0.25)
	local w = maxX - minX
	local d = maxZ - minZ
	minX -= w * pad
	maxX += w * pad
	minZ -= d * pad
	maxZ += d * pad
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local function rotateUV(tx, tz)
	local rot = tonumber(WM.RotationDegrees) or 0
	rot = ((math.floor(rot / 90 + 0.5) * 90) % 360 + 360) % 360
	if rot == 0 then
		return tx, tz
	end
	-- rotate around center (0.5, 0.5) in 90-degree steps
	local x = tx - 0.5
	local y = tz - 0.5
	if rot == 90 then
		x, y = y, -x
	elseif rot == 180 then
		x, y = -x, -y
	elseif rot == 270 then
		x, y = -y, x
	end
	return x + 0.5, y + 0.5
end

local function findBasePlotsFolderClient()
	local w = workspace
	local f = w:FindFirstChild("BasePlots") or w:FindFirstChild("Plots")
	if f then return f end
	for _, segName in ipairs({ "World", "Map", "Game", "Lobby", "Hub", "Main", "Terrain" }) do
		local seg = w:FindFirstChild(segName)
		if seg then
			f = seg:FindFirstChild("BasePlots") or seg:FindFirstChild("Plots")
			if f then return f end
		end
	end
	return nil
end

local function findMyPlot()
	local plotsFolder = findBasePlotsFolderClient()
	if not plotsFolder then return nil end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	-- Fallback: server sometimes only stamps OwnerUserId on the creature orbs
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		for _, desc in ipairs(plot:GetDescendants()) do
			if desc:IsA("Model") then
				local ownerId = desc:GetAttribute("OwnerUserId")
				if ownerId == player.UserId then
					return plot
				end
			end
		end
	end
	return nil
end

local function getPlotCenterWorldPosition(plot)
	if not plot then return nil end
	local raw = plot:FindFirstChild("PlotCenter", true)
	if not raw then
		if plot:IsA("Model") then
			return plot:GetPivot().Position
		end
		return nil
	end
	if raw:IsA("BasePart") then
		return raw.Position
	end
	if raw:IsA("Model") then
		if raw.PrimaryPart then
			return raw.PrimaryPart.Position
		end
		local bp = raw:FindFirstChildWhichIsA("BasePart", true)
		return bp and bp.Position or nil
	end
	return nil
end

local function det3(a11, a12, a13, a21, a22, a23, a31, a32, a33)
	return a11 * (a22 * a33 - a23 * a32) - a12 * (a21 * a33 - a23 * a31) + a13 * (a21 * a32 - a22 * a31)
end

local function solveAffineFrom3(worldA, uvA, worldB, uvB, worldC, uvC)
	-- Solve:
	-- u = a*x + b*z + e
	-- v = c*x + d*z + f
	local x1, z1 = worldA.X, worldA.Y
	local x2, z2 = worldB.X, worldB.Y
	local x3, z3 = worldC.X, worldC.Y
	local u1, v1 = uvA.X, uvA.Y
	local u2, v2 = uvB.X, uvB.Y
	local u3, v3 = uvC.X, uvC.Y

	local D = det3(x1, z1, 1, x2, z2, 1, x3, z3, 1)
	if math.abs(D) < 1e-6 then
		return nil
	end

	local Da = det3(u1, z1, 1, u2, z2, 1, u3, z3, 1)
	local Db = det3(x1, u1, 1, x2, u2, 1, x3, u3, 1)
	local De = det3(x1, z1, u1, x2, z2, u2, x3, z3, u3)

	local Dc = det3(v1, z1, 1, v2, z2, 1, v3, z3, 1)
	local Dd = det3(x1, v1, 1, x2, v2, 1, x3, v3, 1)
	local Df = det3(x1, z1, v1, x2, z2, v2, x3, z3, v3)

	return {
		a = Da / D, b = Db / D, e = De / D,
		c = Dc / D, d = Dd / D, f = Df / D,
	}
end

local function solve3x3(A11, A12, A13, A21, A22, A23, A31, A32, A33, B1, B2, B3)
	local D = det3(A11, A12, A13, A21, A22, A23, A31, A32, A33)
	if math.abs(D) < 1e-9 then
		return nil
	end
	local Dx = det3(B1, A12, A13, B2, A22, A23, B3, A32, A33)
	local Dy = det3(A11, B1, A13, A21, B2, A23, A31, B3, A33)
	local Dz = det3(A11, A12, B1, A21, A22, B2, A31, A32, B3)
	return Dx / D, Dy / D, Dz / D
end

local function solveLeastSquares3(points, outKey) -- outKey is "u" or "v"
	-- Solve y = p1*x + p2*z + p3 in least squares, where y is u or v.
	-- Normal equations: (X'X) p = X'y with X rows [x z 1]
	local sxx, sxz, sx1 = 0, 0, 0
	local szz, sz1 = 0, 0
	local s11 = 0
	local sxy, szy, s1y = 0, 0, 0

	for _, p in ipairs(points) do
		local x = p.x
		local z = p.z
		local y = p[outKey]
		sxx += x * x
		sxz += x * z
		sx1 += x
		szz += z * z
		sz1 += z
		s11 += 1
		sxy += x * y
		szy += z * y
		s1y += y
	end

	-- | sxx sxz sx1 | |p1| = |sxy|
	-- | sxz szz sz1 | |p2|   |szy|
	-- | sx1 sz1 s11 | |p3|   |s1y|
	return solve3x3(
		sxx, sxz, sx1,
		sxz, szz, sz1,
		sx1, sz1, s11,
		sxy, szy, s1y
	)
end

local function solveAffineLeastSquares(points)
	if #points < 3 then return nil end
	local a, b, e = solveLeastSquares3(points, "u")
	local c, d, f = solveLeastSquares3(points, "v")
	if not (a and b and e and c and d and f) then
		return nil
	end
	return { a = a, b = b, e = e, c = c, d = d, f = f }
end

local function asVector2(value)
	if typeof(value) == "Vector2" then return value end
	if type(value) ~= "table" then return nil end
	local x = tonumber(value.X or value.x or value[1])
	local y = tonumber(value.Y or value.y or value.Z or value.z or value[2])
	if not x or not y then return nil end
	return Vector2.new(x, y)
end

local function getCalibration()
	local cal = WM.Calibration
	if type(cal) ~= "table" then return nil end
	if type(cal.A) ~= "table" or type(cal.B) ~= "table" or type(cal.C) ~= "table" then return nil end

	local A_world = asVector2(cal.A.world)
	local A_uv = asVector2(cal.A.uv)
	local B_world = asVector2(cal.B.world)
	local B_uv = asVector2(cal.B.uv)
	local C_world = asVector2(cal.C.world)
	local C_uv = asVector2(cal.C.uv)
	if not (A_world and A_uv and B_world and B_uv and C_world and C_uv) then return nil end

	return solveAffineFrom3(A_world, A_uv, B_world, B_uv, C_world, C_uv)
end

local function findBiomesFolder()
	local w = workspace
	local b = w:FindFirstChild("Biomes")
	if b and (b:IsA("Folder") or b:IsA("Model")) then
		return b
	end
	for _, segName in ipairs({ "World", "Map", "Game", "Lobby", "Hub", "Main", "Terrain" }) do
		local seg = w:FindFirstChild(segName)
		if seg then
			b = seg:FindFirstChild("Biomes")
			if b and (b:IsA("Folder") or b:IsA("Model")) then
				return b
			end
		end
	end
	return nil
end

local function findBiomeFolderForZone(zoneId, biomes)
	if not biomes or not zoneId then return nil end
	local folders = GameConfig.ZoneDoorBiomeFolders
	local name = folders and folders[zoneId]
	if type(name) == "string" and name ~= "" then
		local direct = biomes:FindFirstChild(name) or biomes:FindFirstChild(name, true)
		if direct and (direct:IsA("Folder") or direct:IsA("Model")) then
			return direct
		end
	end
	local aliasesByZone = GameConfig.ZoneDoorBiomeAliases
	local aliases = aliasesByZone and aliasesByZone[zoneId]
	if type(aliases) == "table" then
		for _, alias in ipairs(aliases) do
			if type(alias) == "string" and alias ~= "" then
				local f = biomes:FindFirstChild(alias) or biomes:FindFirstChild(alias, true)
				if f and (f:IsA("Folder") or f:IsA("Model")) then
					return f
				end
			end
		end
	end
	return nil
end

local function getZoneDoorPartNames()
	local t = GameConfig.ZoneDoorPartNames
	if type(t) == "table" and #t > 0 then
		return t
	end
	return { "ZoneDoor", "ZoneDoorTrigger", "GateTrigger", "BiomeGate" }
end

local function getPromptAnchorPart(door)
	if not door then return nil end
	if door:IsA("BasePart") then
		return door
	end
	if door:IsA("Model") then
		if door.PrimaryPart then
			return door.PrimaryPart
		end
		local bp = door:FindFirstChildWhichIsA("BasePart", true)
		return bp
	end
	return nil
end

local function findZoneDoorInstance(folder)
	if not folder then return nil end
	for _, partName in ipairs(getZoneDoorPartNames()) do
		local door = folder:FindFirstChild(partName, true)
		if door and (door:IsA("BasePart") or door:IsA("Model")) then
			return door
		end
	end
	return nil
end

local function resolveZoneDoorWorldXZ(zoneId)
	local biomes = findBiomesFolder()
	local biomeFolder = findBiomeFolderForZone(zoneId, biomes)
	local door = findZoneDoorInstance(biomeFolder)
	local anchor = getPromptAnchorPart(door)
	if not anchor then return nil end
	return Vector2.new(anchor.Position.X, anchor.Position.Z)
end

local function getZoneDoorUV(zoneId)
	local t = WM.ZoneDoorMapUV
	if type(t) ~= "table" then return nil end
	local v = t[zoneId]
	return asVector2(v)
end

local function getInstanceWorldXZ(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then
		return Vector2.new(inst.Position.X, inst.Position.Z)
	end
	if inst:IsA("Model") then
		local pos = inst:GetPivot().Position
		return Vector2.new(pos.X, pos.Z)
	end
	return nil
end

local function getAnchorId(anchor, index)
	return tostring(anchor.id or anchor.name or anchor.Name or anchor.zoneId or anchor.ZoneId or ("Anchor" .. tostring(index)))
end

local function getAnchorUV(anchor)
	local uv = asVector2(anchor.uv or anchor.UV or anchor.mapUV or anchor.MapUV)
	if uv then
		return uv
	end
	local zoneId = anchor.zoneId or anchor.ZoneId
	if zoneId and anchor.useZoneDoorUV ~= false then
		return getZoneDoorUV(zoneId)
	end
	return nil
end

local function resolveAnchorWorldXZ(anchor)
	local directWorld = asVector2(anchor.world or anchor.World or anchor.xz or anchor.XZ)
	if directWorld then
		return directWorld
	end
	local zoneId = anchor.zoneId or anchor.ZoneId
	if zoneId then
		local zoneWorld = resolveZoneDoorWorldXZ(zoneId)
		if zoneWorld then
			return zoneWorld
		end
	end
	local path = anchor.path or anchor.Path
	if type(path) == "table" then
		local inst = resolvePath(workspace, path)
		return getInstanceWorldXZ(inst)
	end
	return nil
end

local function computeAffineFit(affineToFit, points)
	if not affineToFit or type(points) ~= "table" or #points == 0 then
		return nil
	end
	local maxErr, sumSq = 0, 0
	for _, p in ipairs(points) do
		local u = affineToFit.a * p.x + affineToFit.b * p.z + affineToFit.e
		local v = affineToFit.c * p.x + affineToFit.d * p.z + affineToFit.f
		local du = u - p.u
		local dv = v - p.v
		local err = math.sqrt(du * du + dv * dv)
		p.fitU = u
		p.fitV = v
		p.fitError = err
		maxErr = math.max(maxErr, err)
		sumSq += err * err
	end
	return {
		maxError = maxErr,
		rmsError = math.sqrt(sumSq / #points),
	}
end

local function solveNearestAnchorAffine(worldPos, points)
	if type(points) ~= "table" or #points < 3 then
		return nil
	end
	local ranked = {}
	for index, p in ipairs(points) do
		local dx = worldPos.X - p.x
		local dz = worldPos.Z - p.z
		table.insert(ranked, { point = p, distSq = dx * dx + dz * dz, index = index })
	end
	table.sort(ranked, function(a, b)
		return a.distSq < b.distSq
	end)
	for i = 1, #ranked - 2 do
		for j = i + 1, #ranked - 1 do
			for k = j + 1, #ranked do
				local a = ranked[i].point
				local b = ranked[j].point
				local c = ranked[k].point
				local solved = solveAffineFrom3(
					Vector2.new(a.x, a.z), Vector2.new(a.u, a.v),
					Vector2.new(b.x, b.z), Vector2.new(b.u, b.v),
					Vector2.new(c.x, c.z), Vector2.new(c.u, c.v)
				)
				if solved then
					return solved, { a.id, b.id, c.id }
				end
			end
		end
	end
	return nil
end

local function applyAffineToWorld(affineToApply, worldPos)
	return affineToApply.a * worldPos.X + affineToApply.b * worldPos.Z + affineToApply.e,
		affineToApply.c * worldPos.X + affineToApply.d * worldPos.Z + affineToApply.f
end

local function applyMapTransformRaw(transform, worldPos)
	if transform and transform.mode == "nearest3" then
		local localAffine = solveNearestAnchorAffine(worldPos, transform.points)
		if localAffine then
			return applyAffineToWorld(localAffine, worldPos)
		end
		transform = transform.fallbackAffine
	end
	if transform then
		return applyAffineToWorld(transform, worldPos)
	end
	return nil
end

local function computeTransformFit(transform, points)
	if not transform or type(points) ~= "table" or #points == 0 then
		return nil
	end
	local maxErr, sumSq = 0, 0
	for _, p in ipairs(points) do
		local u, v = applyMapTransformRaw(transform, Vector3.new(p.x, 0, p.z))
		if u and v then
			local du = u - p.u
			local dv = v - p.v
			local err = math.sqrt(du * du + dv * dv)
			p.fitU = u
			p.fitV = v
			p.fitError = err
			maxErr = math.max(maxErr, err)
			sumSq += err * err
		end
	end
	return {
		maxError = maxErr,
		rmsError = math.sqrt(sumSq / #points),
	}
end

local function getAnchorCalibration()
	local cfg = WM.AnchorCalibration
	if type(cfg) ~= "table" or cfg.Enabled ~= true then
		return nil, { source = "anchor", reason = "disabled" }
	end
	local anchors = cfg.Points or cfg.Anchors
	if type(anchors) ~= "table" then
		return nil, { source = "anchor", reason = "missing points" }
	end

	local pts = {}
	local skipped = {}
	for index, anchor in ipairs(anchors) do
		if type(anchor) == "table" then
			local id = getAnchorId(anchor, index)
			local uv = getAnchorUV(anchor)
			local worldXZ = resolveAnchorWorldXZ(anchor)
			if uv and worldXZ then
				table.insert(pts, { id = id, x = worldXZ.X, z = worldXZ.Y, u = uv.X, v = uv.Y })
			else
				table.insert(skipped, {
					id = id,
					reason = (not worldXZ and not uv and "missing world and uv") or (not worldXZ and "missing world") or "missing uv",
				})
			end
		end
	end

	local minPoints = math.max(3, tonumber(cfg.MinResolvedPoints) or 3)
	if #pts < minPoints then
		return nil, {
			source = "anchor",
			reason = ("resolved %d/%d anchors; need %d"):format(#pts, #anchors, minPoints),
			points = pts,
			skipped = skipped,
		}
	end

	local solved
	if #pts >= 4 then
		solved = solveAffineLeastSquares(pts)
	else
		solved = solveAffineFrom3(
			Vector2.new(pts[1].x, pts[1].z), Vector2.new(pts[1].u, pts[1].v),
			Vector2.new(pts[2].x, pts[2].z), Vector2.new(pts[2].u, pts[2].v),
			Vector2.new(pts[3].x, pts[3].z), Vector2.new(pts[3].u, pts[3].v)
		)
	end
	if not solved then
		return nil, {
			source = "anchor",
			reason = "anchor world points are collinear or nearly collinear",
			points = pts,
			skipped = skipped,
		}
	end

	local useNearest3 = cfg.Mode == "nearest3" or cfg.UseNearestTriangle == true
	local transform = solved
	if useNearest3 and #pts >= 4 then
		transform = { mode = "nearest3", points = pts, fallbackAffine = solved }
	end

	local fit = useNearest3 and computeTransformFit(transform, pts) or computeAffineFit(solved, pts)
	local warnErrorUV = tonumber(cfg.WarnErrorUV) or 0.025
	return transform, {
		source = "anchor",
		label = useNearest3 and "WorldMap.AnchorCalibration nearest3" or "WorldMap.AnchorCalibration",
		reason = (fit and fit.maxError > warnErrorUV) and ("high fit error %.4f UV"):format(fit.maxError) or nil,
		points = pts,
		skipped = skipped,
		fit = fit,
		warnErrorUV = warnErrorUV,
	}
end

local function getAutoCalibrationFromZoneDoors()
	if WM.AutoFromZoneDoors ~= true then
		return nil
	end
	local zoneIds = GameConfig.ZoneDoorZoneIds or { "Ocean", "Desert", "Electric", "Cave" }
	local pts = {}
	for _, zid in ipairs(zoneIds) do
		local uv = getZoneDoorUV(zid)
		if uv then
			local worldXZ = resolveZoneDoorWorldXZ(zid)
			if worldXZ then
				table.insert(pts, { x = worldXZ.X, z = worldXZ.Y, u = uv.X, v = uv.Y, zoneId = zid })
			end
		end
	end
	-- If we have 4, solve least squares; if only 3, exact affine still works.
	if #pts >= 4 then
		return solveAffineLeastSquares(pts)
	elseif #pts == 3 then
		return solveAffineFrom3(
			Vector2.new(pts[1].x, pts[1].z), Vector2.new(pts[1].u, pts[1].v),
			Vector2.new(pts[2].x, pts[2].z), Vector2.new(pts[2].u, pts[2].v),
			Vector2.new(pts[3].x, pts[3].z), Vector2.new(pts[3].u, pts[3].v)
		)
	end
	return nil
end

local function resolveMapTransform()
	local manual = getCalibration()
	if manual then
		return manual, { source = "manual", label = "WorldMap.Calibration" }
	end

	local anchorAffine, anchorInfo = getAnchorCalibration()
	if anchorAffine then
		return anchorAffine, anchorInfo
	end

	local zoneDoorAffine = getAutoCalibrationFromZoneDoors()
	if zoneDoorAffine then
		return zoneDoorAffine, { source = "zoneDoor", label = "WorldMap.ZoneDoorMapUV" }
	end

	return nil, {
		source = "fallback",
		label = "bounds",
		reason = anchorInfo and anchorInfo.reason or "no calibration resolved",
	}
end

local function worldXZToUV_fallback_raw(worldPos, bounds)
	local spanX = math.max(1e-3, bounds.maxX - bounds.minX)
	local spanZ = math.max(1e-3, bounds.maxZ - bounds.minZ)
	local tx = (worldPos.X - bounds.minX) / spanX
	local tz = (worldPos.Z - bounds.minZ) / spanZ
	if WM.FlipWorldZOnMap then
		tz = 1 - tz
	end
	tx, tz = rotateUV(tx, tz)
	return tx, tz
end

local function worldXZToUV_raw(worldPos, bounds, affine)
	if affine then
		local u, v = applyMapTransformRaw(affine, worldPos)
		if u and v then
			return u, v
		end
	end
	return worldXZToUV_fallback_raw(worldPos, bounds)
end

local function worldXZToUV(worldPos, bounds, affine)
	local u, v = worldXZToUV_raw(worldPos, bounds, affine)
	return math.clamp(u, 0, 1), math.clamp(v, 0, 1)
end

local function worldDirectionToMapRotation(worldPos, worldDir, bounds, affine)
	local dir = Vector3.new(worldDir.X, 0, worldDir.Z)
	if dir.Magnitude < 1e-3 then
		return nil
	end
	dir = dir.Unit
	local u1, v1 = worldXZToUV_raw(worldPos, bounds, affine)
	local u2, v2 = worldXZToUV_raw(worldPos + dir * 40, bounds, affine)
	local du = u2 - u1
	local dv = v2 - v1
	if math.abs(du) + math.abs(dv) < 1e-6 then
		return nil
	end
	return math.deg(math.atan2(dv, du)) + 90
end

local sg = Instance.new("ScreenGui")
sg.Name = "WorldMapGUI"
sg.ResetOnSpawn = false
sg.Enabled = true
sg.DisplayOrder = 96
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.ZIndex = 1
backdrop.Visible = false
backdrop.Parent = sg

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(400, 320)
panel.BackgroundColor3 = C.bg
panel.BackgroundTransparency = 0.02
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Visible = false
panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", panel).Color = C.accent

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -80, 0, 36)
title.Position = UDim2.new(0, 14, 0, 6)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = C.white
title.Text = "World map"
title.ZIndex = 3
title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.fromOffset(32, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 45)
closeBtn.BackgroundTransparency = 0.2
closeBtn.Text = "✕"
closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 3
closeBtn.Parent = panel
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

local mapFrame = Instance.new("Frame")
mapFrame.Name = "MapFrame"
mapFrame.AnchorPoint = Vector2.new(0.5, 0)
mapFrame.Position = UDim2.new(0.5, 0, 0, 44)
mapFrame.Size = UDim2.new(0.92, 0, 1, -92)
mapFrame.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
mapFrame.BorderSizePixel = 0
mapFrame.ZIndex = 2
mapFrame.ClipsDescendants = true
mapFrame.Parent = panel
Instance.new("UICorner", mapFrame).CornerRadius = UDim.new(0, 10)

local mapImage = Instance.new("ImageLabel")
mapImage.Name = "MapImage"
mapImage.Size = UDim2.fromScale(1, 1)
mapImage.BackgroundTransparency = 1
mapImage.ScaleType = Enum.ScaleType.Fit
mapImage.ZIndex = 2
mapImage.Parent = mapFrame

local placeholder = Instance.new("TextLabel")
placeholder.Name = "Placeholder"
placeholder.Size = UDim2.new(1, -20, 1, -20)
placeholder.Position = UDim2.new(0, 10, 0, 10)
placeholder.BackgroundTransparency = 1
placeholder.Font = Enum.Font.GothamMedium
placeholder.TextSize = 13
placeholder.TextColor3 = C.muted
placeholder.TextWrapped = true
placeholder.TextYAlignment = Enum.TextYAlignment.Center
placeholder.Text = "Upload your world map image to Roblox, then set GameConfig.WorldMap.ImageAssetId to rbxassetid://… in GameConfigData."
placeholder.Visible = true
placeholder.ZIndex = 3
placeholder.Parent = mapFrame

local marker = Instance.new("Frame")
marker.Name = "YouAreHere"
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Size = UDim2.fromOffset(14, 14)
marker.BackgroundColor3 = C.gold
marker.BorderSizePixel = 0
marker.ZIndex = 10
marker.Parent = mapFrame
marker.Visible = not MAP_ONLY
Instance.new("UICorner", marker).CornerRadius = UDim.new(1, 0)
local mStroke = Instance.new("UIStroke", marker)
mStroke.Color = Color3.new(1, 1, 1)
mStroke.Thickness = 2

local facingArrow = Instance.new("TextLabel")
facingArrow.Name = "FacingArrow"
facingArrow.AnchorPoint = Vector2.new(0.5, 0.5)
facingArrow.Size = UDim2.fromOffset(28, 28)
facingArrow.BackgroundTransparency = 1
facingArrow.Font = Enum.Font.GothamBlack
facingArrow.TextSize = 22
facingArrow.TextColor3 = C.gold
facingArrow.TextStrokeColor3 = Color3.new(0, 0, 0)
facingArrow.TextStrokeTransparency = 0.2
facingArrow.Text = "▲"
facingArrow.ZIndex = 12
facingArrow.Parent = mapFrame
facingArrow.Visible = not MAP_ONLY

local moveArrow = Instance.new("TextLabel")
moveArrow.Name = "MoveArrow"
moveArrow.AnchorPoint = Vector2.new(0.5, 0.5)
moveArrow.Size = UDim2.fromOffset(22, 22)
moveArrow.BackgroundTransparency = 1
moveArrow.Font = Enum.Font.GothamBlack
moveArrow.TextSize = 18
moveArrow.TextColor3 = C.move
moveArrow.TextStrokeColor3 = Color3.new(0, 0, 0)
moveArrow.TextStrokeTransparency = 0.25
moveArrow.Text = "▲"
moveArrow.Visible = false
moveArrow.ZIndex = 13
moveArrow.Parent = mapFrame
if MAP_ONLY then
	moveArrow.Visible = false
end

local baseMarker = Instance.new("Frame")
baseMarker.Name = "BaseMarker"
baseMarker.AnchorPoint = Vector2.new(0.5, 0.5)
baseMarker.Size = UDim2.fromOffset(12, 12)
baseMarker.BackgroundColor3 = C.base
baseMarker.BorderSizePixel = 0
baseMarker.ZIndex = 9
baseMarker.Visible = false
baseMarker.Parent = mapFrame
if MAP_ONLY then
	baseMarker.Visible = false
end
Instance.new("UICorner", baseMarker).CornerRadius = UDim.new(0, 4)
local bStroke = Instance.new("UIStroke", baseMarker)
bStroke.Color = Color3.new(0, 0, 0)
bStroke.Transparency = 0.35
bStroke.Thickness = 2

local baseLabel = Instance.new("TextLabel")
baseLabel.Name = "BaseLabel"
baseLabel.AnchorPoint = Vector2.new(0, 0.5)
baseLabel.Position = UDim2.new(0, 10, 0.5, 0)
baseLabel.Size = UDim2.fromOffset(80, 18)
baseLabel.BackgroundTransparency = 1
baseLabel.Font = Enum.Font.GothamBold
baseLabel.TextSize = 11
baseLabel.TextColor3 = C.white
baseLabel.TextStrokeTransparency = 0.6
baseLabel.TextXAlignment = Enum.TextXAlignment.Left
baseLabel.Text = "BASE"
baseLabel.ZIndex = 10
baseLabel.Visible = false
baseLabel.Parent = baseMarker

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -10)
hint.Size = UDim2.new(1, -24, 0, 22)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 11
hint.TextColor3 = C.muted
hint.Text = "[M] or HUD · Esc or ✕ to close"
hint.ZIndex = 3
hint.Parent = panel
if MAP_ONLY then
	hint.Visible = false
end

local calHelp = Instance.new("TextLabel")
calHelp.Name = "CalHelp"
calHelp.AnchorPoint = Vector2.new(0.5, 0)
calHelp.Position = UDim2.new(0.5, 0, 0, 36)
calHelp.Size = UDim2.new(1, -24, 0, 18)
calHelp.BackgroundTransparency = 1
calHelp.Font = Enum.Font.GothamMedium
calHelp.TextSize = 11
calHelp.TextColor3 = C.muted
calHelp.Text = ""
calHelp.ZIndex = 4
calHelp.Visible = false
calHelp.Parent = panel

local function normalizeMapImageId(id)
	if type(id) ~= "string" then
		return nil
	end
	id = string.match(id, "^%s*(.-)%s*$") or id
	if id == "" then
		return nil
	end
	if string.match(id, "^rbxassetid://") then
		return id
	end
	if string.match(id, "^%d+$") then
		return "rbxassetid://" .. id
	end
	return nil
end

local function applyImage()
	local nid = normalizeMapImageId(WM.ImageAssetId)
	if nid then
		mapImage.Image = nid
		placeholder.Visible = false
	else
		mapImage.Image = ""
		placeholder.Visible = true
	end
end
applyImage()

local function fmtNumber(n)
	return string.format("%.3f", n)
end

local function fmtVector2(v)
	return ("Vector2.new(%s, %s)"):format(fmtNumber(v.X), fmtNumber(v.Y))
end

local function fmtVector3(v)
	return ("Vector3.new(%s, %s, %s)"):format(fmtNumber(v.X), fmtNumber(v.Y), fmtNumber(v.Z))
end

-- IMPORTANT: The map art is drawn with ScaleType.Fit, so the image can be letterboxed inside mapImage.
-- All world<->UV calibration is done in normalized UV space (0..1 on the art). To keep pins/clicks aligned,
-- we must convert UV <-> pixel position using the *drawn image rect*, not the full mapFrame.
local function getMapDrawRectLocal()
	-- Returns drawX, drawY, drawW, drawH in *local pixels* relative to mapImage (== mapFrame).
	local absSize = mapImage.AbsoluteSize
	local w = absSize.X
	local h = absSize.Y
	if w <= 1 or h <= 1 then
		return 0, 0, math.max(1, w), math.max(1, h)
	end

	local imageAR = math.max(0.5, tonumber(WM.MapAspectRatio) or 1.65) -- width / height
	local frameAR = w / h

	if frameAR > imageAR then
		-- Frame is wider than the art: fit by height, pad X.
		local drawH = h
		local drawW = drawH * imageAR
		local padX = (w - drawW) * 0.5
		return padX, 0, drawW, drawH
	else
		-- Frame is taller than the art: fit by width, pad Y.
		local drawW = w
		local drawH = drawW / imageAR
		local padY = (h - drawH) * 0.5
		return 0, padY, drawW, drawH
	end
end

local function uvToMapOffset(u, v)
	local drawX, drawY, drawW, drawH = getMapDrawRectLocal()
	u = math.clamp(u, 0, 1)
	v = math.clamp(v, 0, 1)
	return Vector2.new(drawX + u * drawW, drawY + v * drawH)
end

local function mapAbsPosToUV(mousePos)
	-- mousePos is absolute screen pixel position (UserInputService:GetMouseLocation()).
	-- Returns u,v in 0..1 space on the art.
	local absPos = mapImage.AbsolutePosition
	local drawX, drawY, drawW, drawH = getMapDrawRectLocal()
	if drawW <= 1 or drawH <= 1 then
		return 0.5, 0.5
	end
	local u = (mousePos.X - (absPos.X + drawX)) / drawW
	local v = (mousePos.Y - (absPos.Y + drawY)) / drawH
	return math.clamp(u, 0, 1), math.clamp(v, 0, 1)
end

local function setGuiToUV(gui, u, v)
	local off = uvToMapOffset(u, v)
	gui.Position = UDim2.new(0, off.X, 0, off.Y)
end

local function getLocalRootPart()
	local ch = player.Character
	return ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart")) or nil
end

local rsConn = nil
local openBounds = nil
local baseRetryAt = 0
local affine = nil
local calibrationInfo = nil
local calibrating = false
local calStep = 1
local calAnchors = { nil, nil, nil } -- { world=Vector2(x,z), uv=Vector2(u,v) }
local baseUvCapture = false

local function getAnchorWorldXZ(anchor)
	if type(anchor) ~= "table" then
		return nil
	end
	local world = anchor.world or anchor.World or anchor.xz or anchor.XZ
	if typeof(world) == "Vector2" then
		return world
	end
	if type(world) == "table" then
		local x = tonumber(world.X or world.x or world[1])
		local z = tonumber(world.Y or world.y or world.Z or world.z or world[2])
		if x and z then
			return Vector2.new(x, z)
		end
	end
	return nil
end

local function findNearestBasePointAnchor(basePos)
	if WM.UseBasePointAnchors == false or type(WM.BasePointAnchors) ~= "table" then
		return nil
	end
	local baseXZ = Vector2.new(basePos.X, basePos.Z)
	local best = nil
	local bestDistSq = math.huge
	for _, anchor in ipairs(WM.BasePointAnchors) do
		local worldXZ = getAnchorWorldXZ(anchor)
		if worldXZ then
			local delta = worldXZ - baseXZ
			local distSq = delta.X * delta.X + delta.Y * delta.Y
			if distSq < bestDistSq then
				best = {
					id = tostring(anchor.id or anchor.name or anchor.Name or "?"),
					worldXZ = worldXZ,
					mapUV = asVector2(anchor.uv or anchor.UV or anchor.mapUV or anchor.MapUV),
					distance = math.sqrt(distSq),
				}
				bestDistSq = distSq
			end
		end
	end
	local maxDistance = tonumber(WM.BasePointAnchorSnapDistance) or 90
	if best and best.distance <= maxDistance then
		return best
	end
	return nil
end

local function resolveBaseMarkerPosition(basePos)
	local anchor = findNearestBasePointAnchor(basePos)
	if anchor then
		return Vector3.new(anchor.worldXZ.X, basePos.Y, anchor.worldXZ.Y), anchor
	end
	return basePos, nil
end

local function worldXZToUVWithBaseAnchor(worldPos, bounds, transform, anchor)
	if anchor and anchor.mapUV then
		return math.clamp(anchor.mapUV.X, 0, 1), math.clamp(anchor.mapUV.Y, 0, 1)
	end
	return worldXZToUV(worldPos, bounds, transform)
end

local function printMapOpenDebugPosition()
	if WM.DebugPrintPlayerPositionOnOpen ~= true then
		return
	end
	local root = getLocalRootPart()
	if not root then
		print("[WorldMapDebug] Map opened; local player root part was not ready yet.")
		return
	end

	local pos = root.Position
	local playerXZ = Vector2.new(pos.X, pos.Z)
	local u, v = worldXZToUV(pos, openBounds, affine)
	local message = ("[WorldMapDebug] Map opened: player=%s playerXZ=%s mapUV=Vector2.new(%.6f, %.6f)"):format(
		fmtVector3(pos),
		fmtVector2(playerXZ),
		u,
		v
	)
	if calibrationInfo then
		message ..= (" transform=%s"):format(tostring(calibrationInfo.label or calibrationInfo.source or "unknown"))
		if calibrationInfo.reason then
			message ..= (" transformNote=%s"):format(tostring(calibrationInfo.reason))
		end
	end

	local plot = findMyPlot()
	local basePos = plot and getPlotCenterWorldPosition(plot)
	if plot then
		message ..= (" plot=%s"):format(plot.Name)
	end
	if basePos then
		local bu, bv = worldXZToUV(basePos, openBounds, affine)
		message ..= (" baseCenter=%s baseXZ=%s baseMapUV=Vector2.new(%.6f, %.6f)"):format(
			fmtVector3(basePos),
			fmtVector2(Vector2.new(basePos.X, basePos.Z)),
			bu,
			bv
		)
		local markerPos, anchor = resolveBaseMarkerPosition(basePos)
		local mu, mv = worldXZToUVWithBaseAnchor(markerPos, openBounds, affine, anchor)
		if anchor then
			message ..= (" baseAnchor=%s anchorDist=%.3f"):format(anchor.id, anchor.distance)
			if anchor.mapUV then
				message ..= (" baseAnchorUV=%s"):format(fmtVector2(anchor.mapUV))
			end
		end
		message ..= (" baseMarkerWorld=%s baseMarkerMapUV=Vector2.new(%.6f, %.6f)"):format(
			fmtVector3(markerPos),
			mu,
			mv
		)
	end

	print(message)

	if calibrationInfo and calibrationInfo.points then
		local fit = calibrationInfo.fit
		if fit then
			print(("[WorldMapDebug] Calibration fit: source=%s points=%d rmsUV=%.6f maxUV=%.6f warnUV=%.6f"):format(
				tostring(calibrationInfo.source or "?"),
				#calibrationInfo.points,
				fit.rmsError or 0,
				fit.maxError or 0,
				calibrationInfo.warnErrorUV or 0
			))
		else
			print(("[WorldMapDebug] Calibration points: source=%s points=%d"):format(
				tostring(calibrationInfo.source or "?"),
				#calibrationInfo.points
			))
		end
		for _, p in ipairs(calibrationInfo.points) do
			local err = p.fitError or 0
			print(("[WorldMapDebug] Anchor %s worldXZ=Vector2.new(%.3f, %.3f) targetUV=Vector2.new(%.6f, %.6f) fitUV=Vector2.new(%.6f, %.6f) errUV=%.6f"):format(
				tostring(p.id),
				p.x,
				p.z,
				p.u,
				p.v,
				p.fitU or 0,
				p.fitV or 0,
				err
			))
		end
	end
	if calibrationInfo and calibrationInfo.skipped and #calibrationInfo.skipped > 0 then
		for _, skipped in ipairs(calibrationInfo.skipped) do
			print(("[WorldMapDebug] Skipped anchor %s: %s"):format(tostring(skipped.id), tostring(skipped.reason)))
		end
	end
end

local function printCalibrationBlock()
	local labels = { "A", "B", "C" }
	for i = 1, 3 do
		if not calAnchors[i] then return end
	end
	local function fmt(n)
		return string.format("%.6f", n)
	end
	local function fmtWorld(v2)
		return ("Vector2.new(%s, %s)"):format(fmt(v2.X), fmt(v2.Y))
	end
	local function fmtUV(v2)
		return ("Vector2.new(%s, %s)"):format(fmt(v2.X), fmt(v2.Y))
	end

	print("[WorldMapCalibration] Paste this into GameConfigData.lua under GameConfig.WorldMap.Calibration = { ... }")
	print("Calibration = {")
	for i = 1, 3 do
		local a = calAnchors[i]
		print(("  %s = { world = %s, uv = %s },"):format(labels[i], fmtWorld(a.world), fmtUV(a.uv)))
	end
	print("},")
	print("[WorldMapCalibration] Or paste as durable WorldMap.AnchorCalibration points if these are fixed landmarks:")
	print("AnchorCalibration = {")
	print("  Enabled = true,")
	print("  Points = {")
	for i = 1, 3 do
		local a = calAnchors[i]
		print(("    { id = %q, world = %s, uv = %s },"):format(labels[i], fmtWorld(a.world), fmtUV(a.uv)))
	end
	print("  },")
	print("},")
end

local function updateCalHelp()
	if not calibrating then
		calHelp.Visible = false
		hint.Text = "[M] or HUD · Esc or ✕ to close"
		return
	end
	calHelp.Visible = true
	local stepName = ({ "A", "B", "C" })[calStep] or "?"
	calHelp.Text = ("CALIBRATE: Stand on landmark %s, then click it on the map. (Click = set %s)"):format(stepName, stepName)
	hint.Text = "[C] Exit calibrate · Esc/✕ close · After C, copy Output snippet"
end

local function updateBaseUvHelp()
	if not panel.Visible or baseUvCapture ~= true then
		return
	end
	calHelp.Visible = true
	calHelp.Text = "BASE UV: Click where your BASE should appear. [B] exits and prints snippet."
	hint.Text = "[B] Exit base UV · Esc/✕ close"
end

local function setOpen(open)
	panel.Visible = open
	backdrop.Visible = open
	if open then
		-- In map-only mode, don't run any world->map transforms or show any markers.
		if MAP_ONLY then
			openBounds = nil
			affine = nil
			calibrationInfo = nil
			calibrating = false
			baseUvCapture = false
			updateCalHelp()
			baseMarker.Visible = false
			baseLabel.Visible = false
			moveArrow.Visible = false
			marker.Visible = false
			facingArrow.Visible = false
			MobileWindowLayout.NotifyMenuOpened()
			if rsConn then
				rsConn:Disconnect()
				rsConn = nil
			end
			return
		end

		openBounds = computeWorldXZBounds()
		baseRetryAt = 0
		affine, calibrationInfo = resolveMapTransform()
		if calibrationInfo and calibrationInfo.source == "fallback" then
			warn(("[WorldMapClient] Using bounds fallback for map transform: %s"):format(tostring(calibrationInfo.reason or "no calibration")))
		elseif calibrationInfo and calibrationInfo.reason then
			warn(("[WorldMapClient] Map calibration note: %s"):format(tostring(calibrationInfo.reason)))
		end
		printMapOpenDebugPosition()
		calibrating = false
		baseUvCapture = false
		updateCalHelp()
		MobileWindowLayout.NotifyMenuOpened()
		if rsConn then
			rsConn:Disconnect()
		end
		rsConn = RunService.RenderStepped:Connect(function()
			local root = getLocalRootPart()
			if not root then
				return
			end

			local b = openBounds
			local spanX = math.max(1e-3, b.maxX - b.minX)
			local spanZ = math.max(1e-3, b.maxZ - b.minZ)

			-- Base marker: resolve occasionally (plot replication can lag behind character spawn)
			if not baseMarker.Visible and tick() >= baseRetryAt then
				baseRetryAt = tick() + 0.75
				local plot = findMyPlot()
				local basePos = plot and getPlotCenterWorldPosition(plot)
				if basePos then
					local markerPos, anchor = resolveBaseMarkerPosition(basePos)
					local bx, bz = worldXZToUVWithBaseAnchor(markerPos, b, affine, anchor)
					setGuiToUV(baseMarker, bx, bz)
					baseMarker.Visible = true
					baseLabel.Visible = true
				end
			end

			local tx, tz = worldXZToUV(root.Position, b, affine)
			setGuiToUV(marker, tx, tz)
			setGuiToUV(facingArrow, tx, tz)
			setGuiToUV(moveArrow, tx, tz)

			local facingRotation = worldDirectionToMapRotation(root.Position, root.CFrame.LookVector, b, affine)
			if facingRotation then
				facingArrow.Rotation = facingRotation
			end

			local velocity = root.AssemblyLinearVelocity or root.Velocity
			local moveRotation = worldDirectionToMapRotation(root.Position, velocity, b, affine)
			local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= 1.5
			moveArrow.Visible = moving and moveRotation ~= nil
			if moveRotation then
				moveArrow.Rotation = moveRotation
			end
		end)
	else
		openBounds = nil
		affine = nil
		calibrationInfo = nil
		calibrating = false
		baseUvCapture = false
		updateCalHelp()
		baseMarker.Visible = false
		baseLabel.Visible = false
		moveArrow.Visible = false
		marker.Visible = not MAP_ONLY
		facingArrow.Visible = not MAP_ONLY
		if rsConn then
			rsConn:Disconnect()
			rsConn = nil
		end
		MobileWindowLayout.NotifyMenuClosed()
	end
end

local function layoutPanel()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	local fill = math.clamp(tonumber(WM.PanelFill) or 0.88, 0.4, 0.98)
	local short = math.min(vp.X, vp.Y) * fill
	local ar = math.max(0.5, tonumber(WM.MapAspectRatio) or 1.65)
	local mapW = short * 0.92
	local mapH = mapW / ar
	mapFrame.Size = UDim2.new(0.92, 0, 0, math.floor(mapH))
	panel.Size = UDim2.fromOffset(math.floor(short), math.floor(44 + mapH + 48))
end

layoutPanel()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutPanel)
end
MobileWindowLayout.BindViewportUpdate(layoutPanel)

local function toggle()
	setOpen(not panel.Visible)
end

closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)
-- NOTE: Backdrop clicks do NOT close the map. This is required for calibration clicks on the map image.

-- Zone-door UV capture: press [Z], then press 1-4 to pick a zone door, then click it on the map.
-- Prints a ready-to-paste ZoneDoorMapUV table.
local zdCapture = false
local zdSelectedIndex = 1
local function zoneIds()
	return GameConfig.ZoneDoorZoneIds or { "Ocean", "Desert", "Electric", "Cave" }
end
local function selectedZoneId()
	local ids = zoneIds()
	return ids[zdSelectedIndex] or ids[1]
end

-- Forward declarations (used by key handler below)
local updateZDHelp
local printZoneDoorUVBlock

UserInputService.InputBegan:Connect(function(input, processed)
	if not panel.Visible then
		return
	end

	-- Don't trigger hotkeys while typing.
	if UserInputService:GetFocusedTextBox() then
		return
	end

	-- Map-only: only allow Escape to close.
	if MAP_ONLY then
		if input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
		return
	end

	-- Z/C should work even if CoreGui marks input as processed.
	local allowProcessed = (input.KeyCode == Enum.KeyCode.Z or input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.B)
	if processed and not allowProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.B then
		baseUvCapture = not baseUvCapture
		calibrating = false
		zdCapture = false
		updateCalHelp()
		if baseUvCapture then
			updateBaseUvHelp()
		else
			calHelp.Visible = false
			hint.Text = "[M] or HUD · Esc or ✕ to close"
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.Z and WM.CalibrationEnabled == true then
		zdCapture = not zdCapture
		calibrating = false
		baseUvCapture = false
		updateCalHelp()
		if zdCapture then
			zdSelectedIndex = 1
			updateZDHelp()
		else
			calHelp.Visible = false
			hint.Text = "[M] or HUD · Esc or ✕ to close"
			printZoneDoorUVBlock()
			affine, calibrationInfo = resolveMapTransform()
		end
		return
	end
	if zdCapture then
		local idx = nil
		if input.KeyCode == Enum.KeyCode.One then idx = 1 end
		if input.KeyCode == Enum.KeyCode.Two then idx = 2 end
		if input.KeyCode == Enum.KeyCode.Three then idx = 3 end
		if input.KeyCode == Enum.KeyCode.Four then idx = 4 end
		if idx then
			zdSelectedIndex = idx
			updateZDHelp()
			return
		end
	end
	if input.KeyCode == Enum.KeyCode.C and WM.CalibrationEnabled == true then
		calibrating = not calibrating
		baseUvCapture = false
		calStep = 1
		calAnchors = { nil, nil, nil }
		updateCalHelp()
		if not calibrating then
			-- when exiting, attempt to print if all points captured
			printCalibrationBlock()
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		setOpen(false)
	end
end)
updateZDHelp = function()
	if not panel.Visible or not zdCapture then
		return
	end
	local zid = selectedZoneId()
	calHelp.Visible = true
	calHelp.Text = ("ZONE DOOR UV: Selected %s (press 1-4). Click its marker on the map. [Z] exits."):format(tostring(zid))
end
printZoneDoorUVBlock = function()
	local ids = zoneIds()
	print("[WorldMapCalibration] Paste this into GameConfigData.lua under GameConfig.WorldMap.ZoneDoorMapUV = { ... }")
	print("ZoneDoorMapUV = {")
	for _, zid in ipairs(ids) do
		local uv = getZoneDoorUV(zid)
		if uv then
			print(("  %s = Vector2.new(%.6f, %.6f),"):format(zid, uv.X, uv.Y))
		end
	end
	print("},")
	print("[WorldMapCalibration] Matching WorldMap.AnchorCalibration points:")
	print("AnchorCalibration = {")
	print("  Enabled = true,")
	print("  Points = {")
	for _, zid in ipairs(ids) do
		local uv = getZoneDoorUV(zid)
		if uv then
			print(("    { id = %q, zoneId = %q, uv = Vector2.new(%.6f, %.6f) },"):format(tostring(zid) .. "Door", tostring(zid), uv.X, uv.Y))
		end
	end
	print("  },")
	print("},")
end


mapFrame.InputBegan:Connect(function(input)
	if not panel.Visible or (not calibrating and not zdCapture and not baseUvCapture) then
		return
	end
	if MAP_ONLY then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local root = getLocalRootPart()
	if not root then
		return
	end
	local mousePos = UserInputService:GetMouseLocation()
	local u, v = mapAbsPosToUV(mousePos)

	if baseUvCapture then
		local plot = findMyPlot()
		local basePos = plot and getPlotCenterWorldPosition(plot)
		if not basePos then
			print("[WorldMapCalibration] BASE UV: could not resolve PlotCenter yet.")
			return
		end
		local _, anchor = resolveBaseMarkerPosition(basePos)
		if not anchor then
			print("[WorldMapCalibration] BASE UV: no nearby BasePointAnchor to stamp (check snap distance / anchors).")
			return
		end
		-- Stamp the configured anchor table in-place so the marker updates immediately this session.
		for _, a in ipairs(WM.BasePointAnchors or {}) do
			if tostring(a.id or a.name or a.Name or "?") == tostring(anchor.id) then
				a.mapUV = Vector2.new(u, v)
				break
			end
		end
		print(("[WorldMapCalibration] Set BasePointAnchors[%s].mapUV = Vector2.new(%.6f, %.6f)"):format(tostring(anchor.id), u, v))
		print("[WorldMapCalibration] Paste this into GameConfigData.lua under the matching BasePointAnchors entry:")
		print(("  { id = %q, world = Vector2.new(%.3f, %.3f), mapUV = Vector2.new(%.6f, %.6f) },"):format(
			tostring(anchor.id),
			anchor.worldXZ.X,
			anchor.worldXZ.Y,
			u,
			v
		))
		baseUvCapture = false
		calHelp.Visible = false
		hint.Text = "[M] or HUD · Esc or ✕ to close"
		return
	end

	if zdCapture then
		local zid = selectedZoneId()
		if zid then
			WM.ZoneDoorMapUV = WM.ZoneDoorMapUV or {}
			WM.ZoneDoorMapUV[zid] = Vector2.new(u, v)
			print(("[WorldMapCalibration] Set ZoneDoorMapUV.%s = (%.6f, %.6f)"):format(zid, u, v))
			updateZDHelp()
		end
		return
	end

	calAnchors[calStep] = {
		world = Vector2.new(root.Position.X, root.Position.Z),
		uv = Vector2.new(u, v),
	}
	print(("[WorldMapCalibration] Set %s: world=(%.3f, %.3f) uv=(%.4f, %.4f)"):format(
		({ "A", "B", "C" })[calStep] or "?", root.Position.X, root.Position.Z, u, v
	))

	if calStep < 3 then
		calStep += 1
		updateCalHelp()
	else
		-- Done: print block + immediately apply for this session
		printCalibrationBlock()
		local a = calAnchors[1]
		local b = calAnchors[2]
		local c = calAnchors[3]
		local solved = solveAffineFrom3(a.world, a.uv, b.world, b.uv, c.world, c.uv)
		if solved then
			affine = solved
			calibrationInfo = { source = "manualSession", label = "session calibration" }
			print("[WorldMapCalibration] Applied solved calibration for this session. Paste into config to persist.")
		else
			print("[WorldMapCalibration] Could not solve (anchors collinear). Pick 3 points not in a straight line.")
		end
		calibrating = false
		updateCalHelp()
	end
end)

local function getHUDToggle()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if not evt or not evt:IsA("BindableEvent") then
		evt = Instance.new("BindableEvent")
		evt.Name = "HUDToggleMenu"
		evt.Parent = playerGui
	end
	return evt
end

local function onHUDToggle(menuName)
	if menuName == "WorldMapGUI" then
		layoutPanel()
		toggle()
	end
end

getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then
		child.Event:Connect(onHUDToggle)
	end
end)

print("[WorldMapClient] Loaded — set WorldMap.ImageAssetId after uploading map art; [M] to open")
