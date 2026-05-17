--[[
	CollectorPlatformAnimator — ReplicatedStorage.Modules
	Drives collector hub motion (orbits, sway, ledger, orb, beams).
	Fixed: Specimen_Pivot_* / Orb_Pivot may be Models → use PivotTo, not .CFrame.
]]

local RunService = game:GetService("RunService")

local M = {}

local active = {} -- [model] = true — avoid double Heartbeat if SSS + in-model script both run

local function getPivot(inst)
	if not inst then
		return nil
	end
	if inst:IsA("Model") then
		return inst:GetPivot()
	end
	if inst:IsA("BasePart") then
		return inst.CFrame
	end
	return nil
end

local function setPivot(inst, cf)
	if not inst or not cf then
		return
	end
	if inst:IsA("Model") then
		inst:PivotTo(cf)
	elseif inst:IsA("BasePart") then
		inst.CFrame = cf
	end
end

--- @param model Model outer Collector_Platform (contains inner geometry + script optional)
function M.start(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return
	end
	if active[model] then
		return
	end
	active[model] = true

	-- Original script used global (0,0,0)-relative orbit; hubs placed elsewhere looked "broken".
	local hubOrigin = model:GetPivot().Position

	local function find(name)
		return model:FindFirstChild(name, true)
	end

	local pivots = {
		find("Specimen_Pivot_01"),
		find("Specimen_Pivot_02"),
		find("Specimen_Pivot_03"),
		find("Specimen_Pivot_04"),
	}
	local pivotRest = {}
	for i, p in ipairs(pivots) do
		if p then
			pivotRest[i] = getPivot(p)
		end
	end

	local cubes = {
		find("Specimen_Glass_01_Fire"),
		find("Specimen_Glass_02_Earth"),
		find("Specimen_Glass_03_Water"),
		find("Specimen_Glass_04_Arcane"),
	}

	local siegelings = {
		find("Siegeling_01_Fire"),
		find("Siegeling_02_Earth"),
		find("Siegeling_03_Water"),
		find("Siegeling_04_Arcane"),
	}

	local siegelingBaseSize = {}
	for i, s in ipairs(siegelings) do
		if s and s:IsA("BasePart") then
			siegelingBaseSize[i] = s.Size
		end
	end

	local flipPage = find("Ledger_Page_Flipping")
	local flipRest = flipPage and getPivot(flipPage)

	local orbPivot = find("Orb_Pivot")
	local orbPivotRest = orbPivot and getPivot(orbPivot)

	local staticParts = {}
	local ORBITAL_NAMES = {
		Specimen_Pivot_01 = true,
		Specimen_Pivot_02 = true,
		Specimen_Pivot_03 = true,
		Specimen_Pivot_04 = true,
		Specimen_Glass_01_Fire = true,
		Specimen_Glass_02_Earth = true,
		Specimen_Glass_03_Water = true,
		Specimen_Glass_04_Arcane = true,
		Siegeling_01_Fire = true,
		Siegeling_02_Earth = true,
		Siegeling_03_Water = true,
		Siegeling_04_Arcane = true,
		Orbital_Ring = true,
		Orb_Pivot = true,
		Collector_Orb = true,
		Ledger_Page_Flipping = true,
	}
	for _ in pairs(ORBITAL_NAMES) do
		for i = 1, 4 do
			for _, combo in ipairs({ "C000", "C001", "C010", "C011", "C100", "C101", "C110", "C111" }) do
				ORBITAL_NAMES[string.format("Specimen_Frame_%02d_%s", i, combo)] = true
			end
		end
	end

	task.wait(0.1)
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("Part") or d:IsA("MeshPart")) and not ORBITAL_NAMES[d.Name] and d.Name ~= "Ledger_Page_Flipping" then
			table.insert(staticParts, { part = d, rest = d.CFrame })
		end
	end

	local ORBIT_RADIUS = 2.4 * 3.5
	local ORBIT_PERIOD = 8.0
	local ORBIT_HEIGHT = 4.4 * 3.5
	local BOB_AMP = 0.3 * 3.5
	local BOB_PERIOD = 4.0
	local bobPhaseOffsets = { 0.25, 0.50, 0.75, 1.00 }
	local TILT_SPECS = {
		{ x = 3.0, y = -4.0 },
		{ x = -2.5, y = 3.5 },
		{ x = 4.5, y = -2.0 },
		{ x = -3.0, y = 4.5 },
	}
	local SWAY_X = 0.4 * 3.5
	local SWAY_Y = 0.15 * 3.5
	local SWAY_PERIOD = 8.0
	local ORB_ORBIT_PER = 8.0
	local FLIP_INTERVAL = 5.0
	local FLIP_DURATION = 0.8

	local t0 = tick()
	local lastFlip = tick()
	local flipping = false
	local flipStart = 0

	local heartbeatErrLogged = false

	print("[CollectorPlatformAnimator] Running on " .. model:GetFullName())

	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(function()
			local now = tick()
			local elapsed = now - t0

			local orbitT = (elapsed % ORBIT_PERIOD) / ORBIT_PERIOD
			local orbitAngle = orbitT * math.pi * 2
			local startAngles = {
				math.rad(45),
				math.rad(135),
				math.rad(225),
				math.rad(315),
			}

			for i, p in ipairs(pivots) do
				if p and pivotRest[i] then
					local ang = orbitAngle + startAngles[i]
					local bobT = (elapsed % BOB_PERIOD) / BOB_PERIOD
					local bobPhase = math.pi * 2 * (bobT - bobPhaseOffsets[i] + 1)
					local zOff = BOB_AMP * math.sin(bobPhase)
					local tiltT = bobT
					local rx = math.rad(TILT_SPECS[i].x) * math.sin(tiltT * math.pi * 2)
					local ry = math.rad(TILT_SPECS[i].y) * math.cos(tiltT * math.pi * 2)
					local worldX = hubOrigin.X + ORBIT_RADIUS * math.cos(ang)
					local worldZ = hubOrigin.Z + ORBIT_RADIUS * math.sin(ang)
					local worldY = hubOrigin.Y + ORBIT_HEIGHT + zOff
					local targetCf = CFrame.new(worldX, worldY, worldZ) * CFrame.Angles(rx, 0, ry)
					setPivot(p, targetCf)
				end
			end

			local swayT = elapsed / SWAY_PERIOD
			local swayX = SWAY_X * math.sin(swayT * math.pi * 2)
			local swayZ = SWAY_X * 0.3 * math.sin(swayT * math.pi * 4)
			local swayY = SWAY_Y * math.sin(swayT * math.pi * 2 + math.pi / 2)

			for _, entry in ipairs(staticParts) do
				if entry.part and entry.part.Parent then
					entry.part.CFrame = entry.rest + Vector3.new(swayX, swayY, swayZ)
				end
			end

			if not flipping and (now - lastFlip) >= FLIP_INTERVAL then
				flipping = true
				flipStart = now
			end
			if flipping and flipPage and flipRest then
				local fp = math.min((now - flipStart) / FLIP_DURATION, 1.0)
				local t = fp * fp * (3 - 2 * fp)
				setPivot(flipPage, flipRest * CFrame.Angles(0, -math.pi * t, 0))
				if fp >= 1.0 then
					flipping = false
					lastFlip = now
					flipRest = getPivot(flipPage)
				end
			end

			if orbPivot and orbPivotRest then
				local orbAngle = (elapsed % ORB_ORBIT_PER) / ORB_ORBIT_PER * math.pi * 2
				setPivot(orbPivot, orbPivotRest * CFrame.Angles(0, orbAngle, 0))
			end

			for i, s in ipairs(siegelings) do
				if s and siegelingBaseSize[i] and s:IsA("BasePart") then
					local pulseT = (elapsed % BOB_PERIOD) / BOB_PERIOD
					local pPhase = math.pi * 2 * (pulseT - bobPhaseOffsets[i] + 1)
					local scale = 1 + 0.12 * math.abs(math.sin(pPhase))
					s.Size = siegelingBaseSize[i] * scale
				end
			end

			for i, cube in ipairs(cubes) do
				if cube then
					local beam = cube:FindFirstChild("SpecimenBeam_" .. i)
					if beam and beam:IsA("Beam") then
						local bT = (elapsed % BOB_PERIOD) / BOB_PERIOD
						local bp = math.pi * 2 * (bT - bobPhaseOffsets[i] + 1)
						beam.Brightness = 1 + 2 * math.abs(math.sin(bp))
					end
				end
			end
		end)
		if not ok and not heartbeatErrLogged then
			heartbeatErrLogged = true
			warn("[CollectorPlatformAnimator] Heartbeat error (once): " .. tostring(err))
		end
	end)
end

return M
