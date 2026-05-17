-- LaserDoorSystem.lua - ServerScriptService (ModuleScript)
-- Dome shield over each player's plot.
-- Shield must be ACTIVATED by pressing a button inside the base.
-- Shield lasts 50 seconds then expires. Player must reactivate.
-- Monsters/raiders are blocked by the shield while active.s
-- Owner + friends pass through. Others get pushed out + damaged.
-- Last updated: 2026-04-18 22:50

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
local DEFAULT_LASER_DOOR_COLOR = Color3.fromRGB(255, 0, 0)
local SHIELD_DOME_COLOR = Color3.fromRGB(255, 70, 70)
local SHIELD_INNER_COLOR = Color3.fromRGB(255, 110, 110)
local SHIELD_BUTTON_COLOR = Color3.fromRGB(255, 60, 60)

-- FIX #25: Forward-declare shield volume math functions so runDomeLoop can reference them.
-- Previously these were defined AFTER runDomeLoop, causing nil upvalues in Lua scoping.
local isInsideShieldVolume
local pushOutsideShieldVolume

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
local setLaserDoorsState -- forward declaration
local getShieldBarrierColor -- forward declaration

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

local function isBaseDomeVisualEnabled()
	return GameConfig.BaseShieldDomeEnabled ~= false
end

local function showShield(data)
	if data.shieldActive then return end
	data.shieldActive = true
	data.shieldBarrierColor = getShieldBarrierColor(data.ownerUserId)
	local duration = getShieldDuration(data.ownerUserId)
	data.shieldExpireTime = tick() + duration

	-- Show dome visual parts only when enabled in config.
	if isBaseDomeVisualEnabled() then
		if data.dome then data.dome.Color = data.shieldBarrierColor or SHIELD_DOME_COLOR end
		if data.beacon then data.beacon.Color = data.shieldBarrierColor or SHIELD_DOME_COLOR end
		if data.dome then data.dome.Transparency = 0.75; data.dome.Parent = data.plotModel end
		if data.innerGlow then data.innerGlow.Transparency = 0.92; data.innerGlow.Parent = data.plotModel end
		if data.ring then data.ring.Parent = data.plotModel end
		if data.beacon then data.beacon.Parent = data.plotModel end
		if data.billboard then data.billboard.Parent = data.plotModel end
	end
	setLaserDoorsState(data, true)

	-- Update button text
	if data.buttonLabel then
		data.buttonLabel.Text = "SHIELD ACTIVE"
		data.buttonLabel.TextColor3 = Color3.fromRGB(255, 130, 130)
	end
	if data.btnTop and data.btnTop.Parent then
		data.btnTop.Color = Color3.fromRGB(255, 90, 90)
	end

	-- Start pulse animation
	if data.pulseThread then task.cancel(data.pulseThread) end
	data.pulseThread = task.spawn(function()
		local t = 0
		while data.shieldActive do
			t = t + RunService.Heartbeat:Wait() * 0.8
			if data.dome and data.dome.Parent then
				data.dome.Transparency = 0.72 + math.sin(t) * 0.08
			end
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
	setLaserDoorsState(data, false)

	-- Cancel animations
	if data.pulseThread then pcall(task.cancel, data.pulseThread); data.pulseThread = nil end
	if data.timerThread then pcall(task.cancel, data.timerThread); data.timerThread = nil end

	-- Update button text
	if data.buttonLabel then
		data.buttonLabel.Text = "ACTIVATE SHIELD"
		data.buttonLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
	end
	if data.btnTop and data.btnTop.Parent then
		data.btnTop.Color = SHIELD_BUTTON_COLOR
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

local function isAllowedFavoriteSiegeling(data, model)
	if not data or not model then return false end
	if not CollectionService:HasTag(model, "FavoriteCreature") then
		return false
	end
	local creatureOwnerUserId = tonumber(model:GetAttribute("OwnerUserId"))
	if not creatureOwnerUserId then
		return false
	end
	if creatureOwnerUserId == data.ownerUserId then
		return true
	end
	local ownerOrFriendPlayer = Players:GetPlayerByUserId(creatureOwnerUserId)
	if not ownerOrFriendPlayer then
		return false
	end
	return isAllowedThrough(data.ownerUserId, ownerOrFriendPlayer)
end

local function collectDoorPartsFromNode(node, outParts)
	if not node then return end
	if node:IsA("BasePart") then
		table.insert(outParts, node)
		return
	end
	for _, desc in ipairs(node:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(outParts, desc)
		end
	end
end

local function collectShieldLaserDoorParts(plotModel)
	local parts = {}
	local function addDoor(floorName, doorName)
		local floorFolder = plotModel:FindFirstChild(floorName)
		if not floorFolder then return end
		local doorNode = floorFolder:FindFirstChild(doorName, true)
		if not doorNode then return end
		local tmp = {}
		collectDoorPartsFromNode(doorNode, tmp)
		local requiredFloor = tonumber(string.match(floorName, "^Floor(%d+)$"))
		for _, p in ipairs(tmp) do
			table.insert(parts, {
				part = p,
				requiredFloor = requiredFloor,
				doorName = doorName,
			})
		end
	end
	addDoor("Floor1", "LaserDoor1")
	addDoor("Floor4", "LaserDoor4")

	local unique, seen = {}, {}
	for _, entry in ipairs(parts) do
		local p = entry.part
		if not seen[p] then
			seen[p] = true
			table.insert(unique, entry)
		end
	end
	return unique
end

local function getOwnedFloor(data, floorNum)
	if floorNum == nil or floorNum <= 1 then return true end
	if not PlayerDataManager or not PlayerDataManager.OwnsFloor then return false end
	local owner = Players:GetPlayerByUserId(data.ownerUserId)
	if not owner then return false end
	return PlayerDataManager.OwnsFloor(owner, floorNum)
end

local function getLaserDoorColor(data)
	if not PlayerDataManager or not PlayerDataManager.GetBaseColor then
		return DEFAULT_LASER_DOOR_COLOR
	end
	local owner = Players:GetPlayerByUserId(data.ownerUserId)
	if not owner then
		return DEFAULT_LASER_DOOR_COLOR
	end
	local baseColorData = PlayerDataManager.GetBaseColor(owner)
	local equippedId = baseColorData and baseColorData.equipped
	if not equippedId or equippedId == "" then
		return DEFAULT_LASER_DOOR_COLOR
	end
	for _, item in ipairs(GameConfig.BaseColorItems or {}) do
		if item.id == equippedId and item.color then
			return item.color
		end
	end
	return DEFAULT_LASER_DOOR_COLOR
end

getShieldBarrierColor = function(ownerUserId)
	if not PlayerDataManager or not PlayerDataManager.GetExterior then
		return SHIELD_DOME_COLOR
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner then
		return SHIELD_DOME_COLOR
	end
	local exteriorData = PlayerDataManager.GetExterior(owner)
	local equippedId = exteriorData and exteriorData.equipped
	if not equippedId or equippedId == "" then
		return SHIELD_DOME_COLOR
	end
	for _, item in ipairs(GameConfig.BaseExteriorItems or {}) do
		if item.id == equippedId and item.color then
			return item.color
		end
	end
	return SHIELD_DOME_COLOR
end

setLaserDoorsState = function(data, isActive)
	if not data.laserDoors then return end
	local laserColor = getLaserDoorColor(data)
	local activeDoorTransparency = tonumber(GameConfig.ShieldLaserDoorTransparency)
	if activeDoorTransparency == nil then activeDoorTransparency = 1 end
	activeDoorTransparency = math.clamp(activeDoorTransparency, 0, 1)
	local seen = {}
	for _, info in ipairs(data.laserDoors) do
		local part = info.part
		if part and part.Parent then
			seen[part] = true
			local floorAllowed = getOwnedFloor(data, info.requiredFloor)
			if isActive and floorAllowed then
				part.Color = laserColor
				part.Transparency = (info.doorName == "LaserDoor1") and 0 or activeDoorTransparency
				part.CanCollide = false
				part.CanTouch = true
			else
				part.Transparency = 1
				part.CanCollide = false
				part.CanTouch = false
			end
		end
	end

	-- Safety pass: apply state to any current LaserDoor1/LaserDoor4 descendants that were
	-- added/replaced after initial shield setup so they never keep stale collision.
	if data.plotModel and data.plotModel.Parent then
		for _, doorInfo in ipairs(collectShieldLaserDoorParts(data.plotModel)) do
			local part = doorInfo.part
			if part and part.Parent and not seen[part] then
				local floorAllowed = getOwnedFloor(data, doorInfo.requiredFloor)
				if isActive and floorAllowed then
					part.Color = laserColor
					part.Transparency = (doorInfo.doorName == "LaserDoor1") and 0 or activeDoorTransparency
					part.CanCollide = false
					part.CanTouch = true
				else
					part.Transparency = 1
					part.CanCollide = false
					part.CanTouch = false
				end
			end
		end
	end
end

local function forceDoorPartsOffForPlot(plotModel)
	if not plotModel then return end
	for _, doorInfo in ipairs(collectShieldLaserDoorParts(plotModel)) do
		local part = doorInfo.part
		if part and part.Parent then
			part.Transparency = 1
			part.CanCollide = false
			part.CanTouch = false
		end
	end
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
	btnTop.Color = SHIELD_BUTTON_COLOR
	btnTop.Parent = plotModel

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 90, 90)
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
	lbl.TextColor3 = Color3.fromRGB(255, 110, 110)
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
	pp.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
	pp.RequiresLineOfSight = true
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
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

	-- Use PlotCenter footprint exactly (X/Z), then extrude straight up.
	local plotCenterPart = plotModel:FindFirstChild("PlotCenter")
	local baseCenter = center
	local baseSize = Vector3.new(50, 1, 50)
	if plotCenterPart and plotCenterPart:IsA("BasePart") then
		baseCenter = plotCenterPart.Position
		baseSize = plotCenterPart.Size
	end

	-- Expand by 1 stud on each side (left/right/front/back), keeping center fixed.
	local sidePadding = tonumber(GameConfig.ShieldSidePadding) or 1
	local halfX = baseSize.X * 0.5 + sidePadding
	local halfZ = baseSize.Z * 0.5 + sidePadding

	-- Cap shield top to the highest owned floor walls (Floor1 -> Floor2 -> max Floor3).
	local plotCenterY = baseCenter.Y
	local topY = plotCenterY + (tonumber(GameConfig.ShieldVerticalHeight) or 240)
	local ownedFloorCap = 1
	if PlayerDataManager and PlayerDataManager.OwnsFloor then
		if PlayerDataManager.OwnsFloor(ownerPlayer, 3) then
			ownedFloorCap = 3
		elseif PlayerDataManager.OwnsFloor(ownerPlayer, 2) then
			ownedFloorCap = 2
		end
	end
	for floorNum = ownedFloorCap, 1, -1 do
		local floorFolder = plotModel:FindFirstChild("Floor" .. floorNum)
		if floorFolder then
			local highestY = -math.huge
			for _, desc in ipairs(floorFolder:GetDescendants()) do
				if desc:IsA("BasePart") then
					local partTopY = desc.Position.Y + desc.Size.Y * 0.5
					if partTopY > highestY then
						highestY = partTopY
					end
				end
			end
			if highestY > -math.huge then
				topY = highestY
				break
			end
		end
	end

	local shieldHeight = math.max(8, topY - plotCenterY)
	local halfY = shieldHeight * 0.5
	local domeCenter = Vector3.new(baseCenter.X, plotCenterY + halfY, baseCenter.Z)
	local shieldBarrierColor = getShieldBarrierColor(ownerPlayer.UserId)

	-- Main rectangular shield volume
	local dome = Instance.new("Part")
	dome.Name = "ShieldDome"
	dome.Size = Vector3.new(halfX * 2, halfY * 2, halfZ * 2)
	dome.Position = domeCenter
	dome.Anchored = true; dome.CanCollide = false; dome.CastShadow = false
	dome.Material = Enum.Material.ForceField
	dome.Color = shieldBarrierColor
	dome.Transparency = 0.75
	CollectionService:AddTag(dome, DOME_TAG)
	dome:SetAttribute("OwnerUserId", ownerPlayer.UserId)
	-- Start HIDDEN (not parented) until activated
	dome.Parent = nil

	-- Inner glow (same rectangular shape, slightly smaller)
	local innerGlow = Instance.new("Part")
	innerGlow.Name = "ShieldInner"
	innerGlow.Size = Vector3.new(
		math.max(1, halfX * 2 - 2),
		math.max(1, halfY * 2 - 2),
		math.max(1, halfZ * 2 - 2)
	)
	innerGlow.Position = domeCenter
	innerGlow.Anchored = true; innerGlow.CanCollide = false; innerGlow.CastShadow = false
	innerGlow.Material = Enum.Material.Neon
	innerGlow.Color = SHIELD_INNER_COLOR
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
	beacon.Position = domeCenter + Vector3.new(0, halfY + 10, 0)
	beacon.Anchored = true; beacon.CanCollide = false; beacon.CastShadow = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = shieldBarrierColor
	beacon.Transparency = 0.5
	beacon.Parent = nil

	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = SHIELD_INNER_COLOR
	beaconLight.Brightness = 4; beaconLight.Range = 40
	beaconLight.Parent = beacon

	local topLight = Instance.new("PointLight")
	topLight.Color = SHIELD_INNER_COLOR
	topLight.Brightness = 2; topLight.Range = math.max(halfX, halfZ) * 0.8
	topLight.Parent = dome

	-- Owner billboard
	local bb = Instance.new("BillboardGui")
	bb.Name = "ShieldLabel"
	bb.Size = UDim2.new(0, 200, 0, 40)
	bb.StudsOffset = Vector3.new(0, halfY + 3, 0)
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
		radius = math.max(halfX, halfZ), -- compatibility for systems that expect one horizontal radius
		radiusX = halfX,
		radiusY = halfY,
		radiusZ = halfZ,
		shieldBarrierColor = shieldBarrierColor,
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
		laserDoors = {},
		laserDoorTouchConnections = {},
		pulseThread = nil,
		timerThread = nil,
	}

	-- Track floor laser walls that toggle with shield state.
	local activeDoorTransparency = tonumber(GameConfig.ShieldLaserDoorTransparency)
	if activeDoorTransparency == nil then activeDoorTransparency = 1 end
	activeDoorTransparency = math.clamp(activeDoorTransparency, 0, 1)
	for _, doorInfo in ipairs(collectShieldLaserDoorParts(plotModel)) do
		local part = doorInfo.part
		table.insert(data.laserDoors, {
			part = part,
			requiredFloor = doorInfo.requiredFloor,
			doorName = doorInfo.doorName,
			activeTransparency = activeDoorTransparency,
		})

		-- Keep laser walls hidden/inactive until shield is activated.
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false

		local conn = part.Touched:Connect(function(hit)
			if not data.shieldActive then return end
			if not hit then return end
			local model = hit:FindFirstAncestorOfClass("Model")
			if not model then return end
			local humanoid = model:FindFirstChildOfClass("Humanoid")

			local touchingPlayer = Players:GetPlayerFromCharacter(model)
			if touchingPlayer then
				if not humanoid or humanoid.Health <= 0 then return end
				if isAllowedThrough(data.ownerUserId, touchingPlayer) then
					return
				end
				humanoid.Health = 0
				return
			end

			-- Non-player models: only FAVORITE siegelings owned by base owner/friends can pass.
			if isAllowedFavoriteSiegeling(data, model) then
				return
			end

			-- Unauthorized NPC/siegeling at the wall: push it outside the active shield volume.
			local body = model:FindFirstChild("Body") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			if body and body:IsA("BasePart") then
				local dc = (data.dome and data.dome.CFrame.Position) or data.domeCenter or body.Position
				local rX = data.radiusX or data.radius or 25
				local rY = data.radiusY or data.radius or 25
				local rZ = data.radiusZ or data.radius or 25
				local pushed = pushOutsideShieldVolume(dc, rX, rY, rZ, body.Position, 2)
				body.CFrame = CFrame.new(pushed)
			end
		end)
		table.insert(data.laserDoorTouchConnections, conn)
	end
	-- Force initial state to match shield/button condition at spawn (OFF by default).
	setLaserDoorsState(data, data.shieldActive)

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

		-- Global spawn safety: keep plot laser doors OFF by default unless an active shield
		-- explicitly enables them through setLaserDoorsState.
		local plotsRoot = workspace:FindFirstChild("BasePlots")
		if plotsRoot then
			for _, plotModel in ipairs(plotsRoot:GetChildren()) do
				if plotModel and plotModel:IsA("Model") then
					local data = activeDomes[plotModel.Name]
					if not data or not data.shieldActive then
						forceDoorPartsOffForPlot(plotModel)
					end
				end
			end
		end

		for plotId, data in pairs(activeDomes) do
			-- Enforce laser door state every loop in case any script/layout update flips properties.
			setLaserDoorsState(data, data.shieldActive)
			if not data.shieldActive then continue end

			-- Use dome position when present; otherwise use stored center so protection still works
			-- when dome visuals are disabled via GameConfig.BaseShieldDomeEnabled.
			local domeCenter = (data.dome and data.dome.Parent and data.dome.CFrame.Position) or data.domeCenter or data.center
			if not domeCenter then continue end
			local radiusX = data.radiusX or data.radius
			local radiusY = data.radiusY or data.radius
			local radiusZ = data.radiusZ or data.radius
			local ownerUserId = data.ownerUserId

			-- Push and damage non-owner, non-friend PLAYERS inside the dome
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				if not char then continue end
				local root = char:FindFirstChild("HumanoidRootPart")
				local humanoid = char:FindFirstChild("Humanoid")
				if not root or not humanoid or humanoid.Health <= 0 then continue end

				if isInsideShieldVolume(root.Position, domeCenter, radiusX, radiusY, radiusZ) then
					if not isAllowedThrough(ownerUserId, p) then
						local now = tick()
						local cdKey = p.UserId .. "_" .. plotId
						if not damageCooldowns[cdKey] or (now - damageCooldowns[cdKey]) >= 0.8 then
							damageCooldowns[cdKey] = now
							humanoid:TakeDamage(GameConfig.LaserDoorDamage or 20)

							local pushPos = pushOutsideShieldVolume(domeCenter, radiusX, radiusY, radiusZ, root.Position, 3)
							root.CFrame = CFrame.new(pushPos + Vector3.new(0, 2, 0))

							task.spawn(function()
								local d = data.dome
								if not d or not d.Parent then return end
								d.Color = Color3.fromRGB(255, 50, 50); d.Transparency = 0.5
								task.wait(0.3)
								if d and d.Parent then
									d.Color = data.shieldBarrierColor or SHIELD_DOME_COLOR; d.Transparency = 0.75
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
				if isInsideShieldVolume(body.Position, domeCenter, radiusX, radiusY, radiusZ) then
					body.Position = pushOutsideShieldVolume(domeCenter, radiusX, radiusY, radiusZ, body.Position, 2)
					local core = creature:FindFirstChild("Core")
					if core then core.Position = body.Position end
				end
			end

			-- Push RAID CREATURES out of dome
			for _, raider in ipairs(CollectionService:GetTagged("AIRaider")) do
				local body = raider:FindFirstChild("Body")
				if not body then continue end
				if isInsideShieldVolume(body.Position, domeCenter, radiusX, radiusY, radiusZ) then
					body.Position = pushOutsideShieldVolume(domeCenter, radiusX, radiusY, radiusZ, body.Position, 2)
					local core = raider:FindFirstChild("Core")
					if core then core.Position = body.Position end
				end
			end
		end
	end
end

-- -- PUBLIC API --

-- Axis-aligned rectangular shield containment.
-- FIX #25: Assign to forward-declared locals (not 'local function') so runDomeLoop sees them.
isInsideShieldVolume = function(position, shieldCenter, halfX, halfY, halfZ)
	local dx = math.abs(position.X - shieldCenter.X)
	local dy = math.abs(position.Y - shieldCenter.Y)
	local dz = math.abs(position.Z - shieldCenter.Z)
	return dx <= halfX and dy <= halfY and dz <= halfZ
end

-- Push position to just outside nearest X/Z face of the rectangular shield.
pushOutsideShieldVolume = function(shieldCenter, halfX, halfY, halfZ, fromPosition, margin)
	margin = margin or 3
	local localPos = fromPosition - shieldCenter
	local signX = (localPos.X >= 0) and 1 or -1
	local signZ = (localPos.Z >= 0) and 1 or -1
	local distX = halfX - math.abs(localPos.X)
	local distZ = halfZ - math.abs(localPos.Z)

	local outX = localPos.X
	local outY = math.clamp(localPos.Y, -halfY, halfY)
	local outZ = localPos.Z

	if distX <= distZ then
		outX = signX * (halfX + margin)
		outZ = math.clamp(outZ, -halfZ - margin, halfZ + margin)
	else
		outZ = signZ * (halfZ + margin)
		outX = math.clamp(outX, -halfX - margin, halfX + margin)
	end

	return shieldCenter + Vector3.new(outX, outY, outZ)
end

-- Check if a position is inside any active shield (for creature AI movement)
function LaserDoorSystem.IsInsideActiveShield(position)
	for _, data in pairs(activeDomes) do
		if data.shieldActive and data.dome and data.dome.Parent then
			local rX = data.radiusX or data.radius
			local rY = data.radiusY or data.radius
			local rZ = data.radiusZ or data.radius
			local dc = data.domeCenter or data.center
			if isInsideShieldVolume(position, dc, rX, rY, rZ) then
				return true, dc, math.max(rX, rZ)
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

function LaserDoorSystem.RefreshForPlot(plotModel)
	if not plotModel then return end
	local data = activeDomes[plotModel.Name]
	if not data then return end
	setLaserDoorsState(data, data.shieldActive)
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
		if data.laserDoorTouchConnections then
			for _, conn in ipairs(data.laserDoorTouchConnections) do
				if conn then
					pcall(function() conn:Disconnect() end)
				end
			end
		end
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