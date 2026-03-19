-- LaserDoorSystem.lua - ServerScriptService (ModuleScript)
-- Dome shield over each player's plot.
-- Shield must be ACTIVATED by pressing a button inside the base.
-- Shield lasts 50 seconds then expires. Player must reactivate.
-- Monsters/raiders are blocked by the shield while active.s
-- Owner + friends pass through. Others get pushed out + damaged.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataManager

local LaserDoorSystem = {}

local DOME_TAG = "BaseShieldDome"
local activeDomes = {} -- plotId -> domeData
local damageCooldowns = {}

-- FIX #25: Forward-declare ellipsoid math functions so runDomeLoop can reference them.
-- Previously these were defined AFTER runDomeLoop, causing nil upvalues in Lua scoping.
-- Result: shield never pushed/damaged intruders because isInsideEllipsoid was nil.
local isInsideEllipsoid
local pushOutsideEllipsoid

-- -- FIND PLOT CENTER --

local function findPlotCenter(plotModel)
	local pc = plotModel:FindFirstChild("PlotCenter")
	if pc then
		if pc:IsA("BasePart") then
			return pc.Position
		elseif pc:IsA("Model") then
			local inner = pc:FindFirstChildWhichIsA("BasePart")
			if inner then return inner.Position end
			local ok, pivot = pcall(function() return pc:GetPivot().Position end)
			if ok then return pivot end
		end
	end
	for _, name in ipairs({"PlotFloor", "Floor", "Base", "Ground"}) do
		local part = plotModel:FindFirstChild(name)
		if part and part:IsA("BasePart") then return part.Position end
	end
	for _, child in ipairs(plotModel:GetChildren()) do
		if child:IsA("BasePart") and not child.Name:lower():find("wall") then
			return child.Position
		end
	end
	for _, child in ipairs(plotModel:GetChildren()) do
		if child:IsA("BasePart") then return child.Position end
	end
	local ok, pivot = pcall(function() return plotModel:GetPivot().Position end)
	if ok then return pivot end
	return Vector3.new(0, 5, 0)
end

-- -- FIND GROUND Y FOR DOME (floor level so dome touches floor and rises over base) --

local function findGroundY(center, plotModel)
	if not plotModel then return center.Y end
	-- Use the bottom of the plot so the dome touches the floor and rises over the base
	local ok, bboxCf, bboxSize = pcall(function()
		return plotModel:GetBoundingBox()
	end)
	if ok and bboxCf and bboxSize then
		-- GetBoundingBox returns (CFrame, Size); bottom of box = center.Y - size.Y/2
		return bboxCf.Position.Y - bboxSize.Y / 2
	end
	-- Fallback: raycast below plot (exclude plot to hit terrain)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { plotModel }
	local rayOrigin = Vector3.new(center.X, center.Y + 50, center.Z)
	local result = workspace:Raycast(rayOrigin, Vector3.new(0, -500, 0), params)
	if result then return result.Position.Y end
	return center.Y
end

-- -- SHOW / HIDE SHIELD VISUALS --

local hideShield -- forward declaration

local function getShieldDuration(ownerUserId)
	local base = GameConfig.ShieldDuration or 50
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner or not PlayerDataManager then return base end
	local lvl = (PlayerDataManager.GetPlayerLevel(owner)) or 1
	local extraFromLevel = (lvl - 1) * 10  -- +10 sec per level (level 1 = 0 bonus)
	local purchasedFloors = 0
	if PlayerDataManager.OwnsFloor(owner, 2) then purchasedFloors = purchasedFloors + 1 end
	if PlayerDataManager.OwnsFloor(owner, 3) then purchasedFloors = purchasedFloors + 1 end
	local extraFromFloors = purchasedFloors * 30  -- +30 sec per purchased floor (Floor 2 or 3)
	return base + extraFromLevel + extraFromFloors
end

local function showShield(data)
	if data.shieldActive then return end
	data.shieldActive = true
	local duration = getShieldDuration(data.ownerUserId)
	data.shieldExpireTime = tick() + duration

	-- Show dome parts
	if data.dome then data.dome.Transparency = 0.75; data.dome.Parent = data.plotModel end
	if data.innerGlow then data.innerGlow.Transparency = 0.92; data.innerGlow.Parent = data.plotModel end
	if data.ring then data.ring.Parent = data.plotModel end
	if data.beacon then data.beacon.Parent = data.plotModel end
	if data.billboard then data.billboard.Parent = data.plotModel end

	-- Update button text
	if data.buttonLabel then
		data.buttonLabel.Text = "SHIELD ACTIVE"
		data.buttonLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
	end

	-- Start pulse animation
	if data.pulseThread then task.cancel(data.pulseThread) end
	data.pulseThread = task.spawn(function()
		local t = 0
		while data.shieldActive and data.dome and data.dome.Parent do
			t = t + RunService.Heartbeat:Wait() * 0.8
			data.dome.Transparency = 0.72 + math.sin(t) * 0.08
			if data.innerGlow and data.innerGlow.Parent then
				data.innerGlow.Transparency = 0.88 + math.sin(t * 1.5) * 0.04
			end
		end
	end)

	-- Timer billboard
	if data.timerLabel then
		data.timerThread = task.spawn(function()
			while data.shieldActive do
				local remaining = math.max(0, math.ceil(data.shieldExpireTime - tick()))
				data.timerLabel.Text = remaining .. "s"
				if remaining <= 10 then
					data.timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
				else
					data.timerLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
				end
				if remaining <= 0 then break end
				task.wait(1)
			end
			-- Shield expired
			hideShield(data)
		end)
	end

	print("[LaserDoor] Shield ACTIVATED for " .. data.plotModel.Name)
end

hideShield = function(data)
	if not data.shieldActive then return end
	data.shieldActive = false
	data.shieldExpireTime = 0

	-- Hide dome parts (keep in storage, don't destroy)
	if data.dome then data.dome.Parent = nil end
	if data.innerGlow then data.innerGlow.Parent = nil end
	if data.ring then data.ring.Parent = nil end
	if data.beacon then data.beacon.Parent = nil end
	if data.billboard then data.billboard.Parent = nil end

	-- Cancel animations
	if data.pulseThread then pcall(task.cancel, data.pulseThread); data.pulseThread = nil end
	if data.timerThread then pcall(task.cancel, data.timerThread); data.timerThread = nil end

	-- Update button text
	if data.buttonLabel then
		data.buttonLabel.Text = "ACTIVATE SHIELD"
		data.buttonLabel.TextColor3 = Color3.fromRGB(80, 200, 255)
	end

	-- Update timer
	if data.timerLabel then
		data.timerLabel.Text = "OFF"
		data.timerLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	end

	print("[LaserDoor] Shield EXPIRED for " .. data.plotModel.Name)
end

-- -- CHECK IF PLAYER ALLOWED (owner or friend) --

local function isAllowedThrough(ownerUserId, visitorPlayer)
	if visitorPlayer.UserId == ownerUserId then return true end
	if not PlayerDataManager or not PlayerDataManager.IsFriend then return false end
	local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
	if not ownerPlayer then return false end
	return PlayerDataManager.IsFriend(ownerPlayer, visitorPlayer.UserId)
end

-- -- CREATE ACTIVATION BUTTON --

local function createActivationButton(plotModel, center, groundY, ownerUserId)
	-- Place button beneath the beacon light (at plot center X/Z) but on top of PlotCenter
	local plotCenter = plotModel:FindFirstChild("PlotCenter")
	local buttonY = groundY + 1  -- default fallback
	if plotCenter and plotCenter:IsA("BasePart") then
		buttonY = plotCenter.Position.Y + plotCenter.Size.Y / 2
	end
	local buttonPos = Vector3.new(center.X, buttonY, center.Z)

	-- Button pedestal (vertical now)
	local pedestal = Instance.new("Part")
	pedestal.Name = "ShieldButton"
	pedestal.Size = Vector3.new(3, 5, 3)  -- Tall in Y for vertical stand
	pedestal.Position = buttonPos
	pedestal.Anchored = true
	pedestal.CanCollide = true
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.Material = Enum.Material.SmoothPlastic
	pedestal.Color = Color3.fromRGB(30, 30, 50)
	pedestal.Parent = plotModel  -- No rotation needed

	-- Glowing top disk
	local btnTop = Instance.new("Part")
	btnTop.Name = "ShieldButtonTop"
	btnTop.Size = Vector3.new(2, 0.6, 2)  -- Wide flat disk on top
	btnTop.Position = buttonPos + Vector3.new(0, 2.8, 0)  -- On top of pedestal
	btnTop.Anchored = true
	btnTop.CanCollide = false
	btnTop.Shape = Enum.PartType.Cylinder
	btnTop.Material = Enum.Material.Neon
	btnTop.Color = Color3.fromRGB(40, 160, 255)
	btnTop.Parent = plotModel

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(60, 180, 255)
	light.Brightness = 2; light.Range = 6
	light.Parent = btnTop

	-- Billboard with label (only visible when nearby, not through walls)
	local bb = Instance.new("BillboardGui")
	bb.Name = "ShieldButtonGui"
	bb.Size = UDim2.new(0, 180, 0, 50)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = false; bb.MaxDistance = 30
	bb.Adornee = pedestal
	bb.Parent = plotModel

	local lbl = Instance.new("TextLabel")
	lbl.Name = "ButtonLabel"
	lbl.Size = UDim2.new(1, 0, 0.6, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "ACTIVATE SHIELD"
	lbl.TextColor3 = Color3.fromRGB(80, 200, 255)
	lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = bb

	local timerLbl = Instance.new("TextLabel")
	timerLbl.Name = "TimerLabel"
	timerLbl.Size = UDim2.new(1, 0, 0.35, 0)
	timerLbl.Position = UDim2.new(0, 0, 0.6, 0)
	timerLbl.BackgroundTransparency = 1
	timerLbl.Text = "OFF"
	timerLbl.TextColor3 = Color3.fromRGB(150, 150, 150)
	timerLbl.Font = Enum.Font.GothamMedium; timerLbl.TextScaled = true
	timerLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	timerLbl.TextStrokeTransparency = 0.4
	timerLbl.Parent = bb

	-- Click detector on pedestal
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 12
	cd.Parent = pedestal
	cd:SetAttribute("OwnerUserId", ownerUserId)

	-- Proximity prompt (RequiresLineOfSight so dome blocks it for non-friends outside)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Activate Shield"
	pp.ObjectText = "Shield Generator"
	pp.MaxActivationDistance = 10
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = true
	pp.Parent = pedestal
	pp:SetAttribute("OwnerUserId", ownerUserId)

	return {
		pedestal = pedestal,
		btnTop = btnTop,
		buttonBB = bb,
		buttonLabel = lbl,
		timerLabel = timerLbl,
		clickDetector = cd,
		proximityPrompt = pp,
	}
end

-- -- CREATE DOME (starts hidden, activated by button) --

local function createDome(plotModel, ownerPlayer)
	if not plotModel then return nil end

	local center = findPlotCenter(plotModel)
	local groundY = findGroundY(center, plotModel)

	-- Scale dome to cover highest floor in the plot
	local maxFloorY = groundY
	for _, floorNum in ipairs({1, 2, 3}) do
		local floorFolder = plotModel:FindFirstChild("Floor" .. floorNum)
		if floorFolder then
			for _, desc in ipairs(floorFolder:GetDescendants()) do
				if desc:IsA("BasePart") then
					local topY = desc.Position.Y + desc.Size.Y / 2
					if topY > maxFloorY then maxFloorY = topY end
				end
			end
		end
	end
	local floorHeight = maxFloorY - groundY
	local radiusXZ = math.max(GameConfig.DomeRadius or 50, floorHeight + 10)
	local heightMult = tonumber(GameConfig.DomeHeightMultiplier) or 1.5
	local radiusY = radiusXZ * heightMult  -- taller ellipse, same horizontal footprint

	local domeCenter = Vector3.new(center.X, center.Y, center.Z)  -- 50% point (equator) at plot center so it appears as a domez

	-- Main dome ellipsoid (Ball with different X/Z vs Y size = taller, same width at base)
	local dome = Instance.new("Part")
	dome.Name = "ShieldDome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(radiusXZ * 2, radiusY * 2, radiusXZ * 2)
	dome.Position = domeCenter
	dome.Anchored = true; dome.CanCollide = false; dome.CastShadow = false
	dome.Material = Enum.Material.ForceField
	dome.Color = Color3.fromRGB(40, 160, 255)
	dome.Transparency = 0.75
	CollectionService:AddTag(dome, DOME_TAG)
	dome:SetAttribute("OwnerUserId", ownerPlayer.UserId)
	-- Start HIDDEN (not parented) until activated
	dome.Parent = nil

	-- Inner glow (same ellipsoid shape, slightly smaller)
	local innerGlow = Instance.new("Part")
	innerGlow.Name = "ShieldInner"
	innerGlow.Shape = Enum.PartType.Ball
	innerGlow.Size = Vector3.new(radiusXZ * 2 - 2, radiusY * 2 - 2, radiusXZ * 2 - 2)
	innerGlow.Position = domeCenter
	innerGlow.Anchored = true; innerGlow.CanCollide = false; innerGlow.CastShadow = false
	innerGlow.Material = Enum.Material.Neon
	innerGlow.Color = Color3.fromRGB(60, 180, 255)
	innerGlow.Transparency = 0.92
	innerGlow.Parent = nil

	---- Base ring � flat glowing disk/ring at ground level (no more horizontal beam)
	--local ring = Instance.new("Part")
	--ring.Name = "ShieldRing"
	--ring.Shape = Enum.PartType.Cylinder
	--ring.Size = Vector3.new(domeSize + 4, 0.4, domeSize + 4)  -- Wide X/Z for full circle diameter, very thin Y for flat glow
	--ring.Position = Vector3.new(center.X, groundY + 0.2, center.Z)  -- Slightly above floor to avoid z-fighting
	--ring.Orientation = Vector3.new(0, 0, 0)  -- No rotation � keeps it perfectly flat
	--ring.Anchored = true
	--ring.CanCollide = false
	--ring.CastShadow = false
	--ring.Material = Enum.Material.Neon
	--ring.Color = Color3.fromRGB(60, 200, 255)
	--ring.Transparency = 0.1  -- Brighter glow (adjust 0-0.3 as needed)
	--ring.Parent = nil

	-- Beacon
	local beacon = Instance.new("Part")
	beacon.Name = "ShieldBeacon"
	beacon.Size = Vector3.new(1.5, 120, 1.5)
	beacon.Position = domeCenter + Vector3.new(0, radiusY + 10, 0)
	beacon.Anchored = true; beacon.CanCollide = false; beacon.CastShadow = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(40, 160, 255)
	beacon.Transparency = 0.5
	beacon.Parent = nil

	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = Color3.fromRGB(60, 180, 255)
	beaconLight.Brightness = 4; beaconLight.Range = 40
	beaconLight.Parent = beacon

	local topLight = Instance.new("PointLight")
	topLight.Color = Color3.fromRGB(60, 200, 255)
	topLight.Brightness = 2; topLight.Range = radiusXZ * 0.8
	topLight.Parent = dome

	-- Owner billboard
	local bb = Instance.new("BillboardGui")
	bb.Name = "ShieldLabel"
	bb.Size = UDim2.new(0, 200, 0, 40)
	bb.StudsOffset = Vector3.new(0, radiusY + 3, 0)
	bb.AlwaysOnTop = true; bb.Adornee = dome
	bb.Parent = nil

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, 0, 1, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = ownerPlayer.Name .. "'s Base"
	nameLbl.TextColor3 = Color3.fromRGB(100, 200, 255)
	nameLbl.Font = Enum.Font.GothamBold; nameLbl.TextScaled = true
	nameLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLbl.TextStrokeTransparency = 0.3
	nameLbl.Parent = bb

	-- Create activation button
	local btnData = createActivationButton(plotModel, center, groundY, ownerPlayer.UserId)

	print("[LaserDoor] Dome + button created for " .. ownerPlayer.Name .. " at " .. tostring(center))

	local data = {
		plotModel = plotModel,
		dome = dome,
		innerGlow = innerGlow,
		ring = nil, -- ring creation is disabled
		beacon = beacon,
		billboard = bb,
		center = center,
		domeCenter = domeCenter,
		groundY = groundY,
		radius = radiusXZ,        -- horizontal (for API / CreatureAI compatibility)
		radiusXZ = radiusXZ,
		radiusY = radiusY,
		ownerUserId = ownerPlayer.UserId,
		shieldActive = false,
		shieldExpireTime = 0,
		-- Button parts
		pedestal = btnData.pedestal,
		btnTop = btnData.btnTop,
		buttonBB = btnData.buttonBB,
		buttonLabel = btnData.buttonLabel,
		timerLabel = btnData.timerLabel,
		clickDetector = btnData.clickDetector,
		proximityPrompt = btnData.proximityPrompt,
		pulseThread = nil,
		timerThread = nil,
	}

	-- Connect button activation (owner + friends can activate)
	btnData.clickDetector.MouseClick:Connect(function(plr)
		if not isAllowedThrough(data.ownerUserId, plr) then return end
		if data.shieldActive then return end -- already active
		-- FIX #35: Block shield during knight base rental (base recharging from teleport)
		if data.plotModel and data.plotModel:GetAttribute("KnightBaseRental") then
			local warnEvt = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("KnightBaseWarning")
			if warnEvt then warnEvt:FireClient(plr, "shield_blocked") end
			return
		end
		showShield(data)
	end)

	btnData.proximityPrompt.Triggered:Connect(function(plr)
		if not isAllowedThrough(data.ownerUserId, plr) then return end
		if data.shieldActive then return end
		-- FIX #35: Block shield during knight base rental (base recharging from teleport)
		if data.plotModel and data.plotModel:GetAttribute("KnightBaseRental") then
			local warnEvt = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("KnightBaseWarning")
			if warnEvt then warnEvt:FireClient(plr, "shield_blocked") end
			return
		end
		showShield(data)
	end)

	return data
end

-- -- PROTECTION LOOP (players + creatures) --

local function runDomeLoop()
	while true do
		task.wait(0.4)

		for plotId, data in pairs(activeDomes) do
			if not data.shieldActive then continue end
			if not data.dome or not data.dome.Parent then continue end

			-- Use dome's current world position so inside/damage check works (data.domeCenter may be in model space)
			local domeCenter = data.dome.CFrame.Position
			local radiusXZ = data.radiusXZ or data.radius
			local radiusY = data.radiusY or data.radius
			local ownerUserId = data.ownerUserId

			-- Push and damage non-owner, non-friend PLAYERS inside the dome
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				if not char then continue end
				local root = char:FindFirstChild("HumanoidRootPart")
				local humanoid = char:FindFirstChild("Humanoid")
				if not root or not humanoid or humanoid.Health <= 0 then continue end

				if isInsideEllipsoid(root.Position, domeCenter, radiusXZ, radiusY) then
					if not isAllowedThrough(ownerUserId, p) then
						local now = tick()
						local cdKey = p.UserId .. "_" .. plotId
						if not damageCooldowns[cdKey] or (now - damageCooldowns[cdKey]) >= 0.8 then
							damageCooldowns[cdKey] = now
							humanoid:TakeDamage(GameConfig.LaserDoorDamage or 20)

							local pushPos = pushOutsideEllipsoid(domeCenter, radiusXZ, radiusY, root.Position, 3)
							root.CFrame = CFrame.new(pushPos + Vector3.new(0, 2, 0))

							task.spawn(function()
								local d = data.dome
								if not d or not d.Parent then return end
								d.Color = Color3.fromRGB(255, 50, 50); d.Transparency = 0.5
								task.wait(0.3)
								if d and d.Parent then
									d.Color = Color3.fromRGB(40, 160, 255); d.Transparency = 0.75
								end
							end)
						end
					end
				end
			end

			-- Push WORLD CREATURES out of dome
			for _, creature in ipairs(CollectionService:GetTagged("WorldCreature")) do
				local body = creature:FindFirstChild("Body")
				if not body then continue end
				if isInsideEllipsoid(body.Position, domeCenter, radiusXZ, radiusY) then
					body.Position = pushOutsideEllipsoid(domeCenter, radiusXZ, radiusY, body.Position, 2)
					local core = creature:FindFirstChild("Core")
					if core then core.Position = body.Position end
				end
			end

			-- Push RAID CREATURES out of dome
			for _, raider in ipairs(CollectionService:GetTagged("AIRaider")) do
				local body = raider:FindFirstChild("Body")
				if not body then continue end
				if isInsideEllipsoid(body.Position, domeCenter, radiusXZ, radiusY) then
					body.Position = pushOutsideEllipsoid(domeCenter, radiusXZ, radiusY, body.Position, 2)
					local core = raider:FindFirstChild("Core")
					if core then core.Position = body.Position end
				end
			end
		end
	end
end

-- -- PUBLIC API --

-- Ellipsoid containment: (dx/rXZ)^2 + (dy/rY)^2 + (dz/rXZ)^2 <= 1
-- FIX #25: Assign to forward-declared locals (not 'local function') so runDomeLoop sees them.
isInsideEllipsoid = function(position, domeCenter, radiusXZ, radiusY)
	local dx = position.X - domeCenter.X
	local dy = position.Y - domeCenter.Y
	local dz = position.Z - domeCenter.Z
	local q = (dx / radiusXZ) ^ 2 + (dy / radiusY) ^ 2 + (dz / radiusXZ) ^ 2
	return q <= 1
end

-- Push position to just outside ellipsoid surface in direction of diff from domeCenter
pushOutsideEllipsoid = function(domeCenter, radiusXZ, radiusY, fromPosition, margin)
	margin = margin or 3
	local diff = fromPosition - domeCenter
	local len = diff.Magnitude
	if len < 0.01 then diff = Vector3.new(1, 0, 0); len = 1 end
	local ux, uy, uz = diff.X / len, diff.Y / len, diff.Z / len
	local surfaceDist = 1 / math.sqrt((ux / radiusXZ) ^ 2 + (uy / radiusY) ^ 2 + (uz / radiusXZ) ^ 2)
	return domeCenter + diff.Unit * (surfaceDist + margin)
end

-- Check if a position is inside any active shield (for creature AI movement)
function LaserDoorSystem.IsInsideActiveShield(position)
	for _, data in pairs(activeDomes) do
		if data.shieldActive and data.dome and data.dome.Parent then
			local rXZ = data.radiusXZ or data.radius
			local rY = data.radiusY or data.radius
			local dc = data.domeCenter or data.center
			if isInsideEllipsoid(position, dc, rXZ, rY) then
				return true, dc, rXZ
			end
		end
	end
	return false
end

function LaserDoorSystem.HasDome(plotId)
	return activeDomes[plotId] ~= nil
end

function LaserDoorSystem.GetDomeData(plotModel)
	if not plotModel then return nil end
	local data = activeDomes[plotModel.Name]
	if not data then return nil end
	return { center = data.center, radius = data.radius, ownerUserId = data.ownerUserId }
end

function LaserDoorSystem.CreateForPlot(plotModel, player)
	if not GameConfig.LaserDoorEnabled then return end
	LaserDoorSystem.RemoveForPlot(plotModel)
	local domeData = createDome(plotModel, player)
	if domeData then
		activeDomes[plotModel.Name] = domeData
	end
end

function LaserDoorSystem.RemoveForPlot(plotModel)
	local plotId = plotModel.Name
	local data = activeDomes[plotId]
	if data then
		hideShield(data)
		for _, key in ipairs({"dome", "innerGlow", "ring", "beacon", "billboard", "pedestal", "btnTop", "buttonBB"}) do
			if data[key] then
				if data[key].Parent then data[key]:Destroy()
				else data[key]:Destroy() end
			end
		end
	end
	activeDomes[plotId] = nil
end

function LaserDoorSystem.Init(pdm)
	PlayerDataManager = pdm
	task.spawn(runDomeLoop)
	print("[LaserDoorSystem] Initialized - dome shields active")
end

return LaserDoorSystem