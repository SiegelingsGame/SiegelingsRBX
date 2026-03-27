-- UnderwaterBreathClient.client.lua - StarterPlayerScripts (LocalScript)
-- FIX #27: Underwater breath mechanic.
-- After BreathMaxTime seconds underwater, player takes BreathDrownDamage every BreathDrownTickInterval.
-- If a Water-type creature is equipped as favorite, breath time extends by
-- BreathWaterCreatureBonus * creatureLevel seconds (capped at BreathWaterCreatureMaxBonus).
-- A breath meter UI appears when the player enters water and hides when they exit.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local CreatureData = require(ReplicatedStorage.Modules:WaitForChild("CreatureData"))

-- ══════════════════════════════════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════════════════════════════════

local BASE_BREATH_TIME = GameConfig.BreathMaxTime or 10
local DROWN_DAMAGE = GameConfig.BreathDrownDamage or 10
local DROWN_TICK_INTERVAL = GameConfig.BreathDrownTickInterval or 5
local BONUS_PER_LEVEL = GameConfig.BreathWaterCreatureBonus or 2
local MAX_BONUS = GameConfig.BreathWaterCreatureMaxBonus or 60
-- Full bar, no O2 drain for this many seconds after submerging (see GameConfig.BreathSubmergeGraceSeconds)
local SUBMERGE_GRACE = GameConfig.BreathSubmergeGraceSeconds or 5

-- ══════════════════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════════════════

local isUnderwater = false
local breathActive = false   -- true after SUBMERGE_GRACE seconds underwater (O2 drain starts)
local underwaterGraceTimer = 0
local breathRemaining = BASE_BREATH_TIME
local maxBreath = BASE_BREATH_TIME
local drownTickTimer = 0
local meterVisible = false
local spawnGraceTimer = 0
local SPAWN_GRACE = 1.5
local oxygenDepleted = false
local HEAD_SUBMERGE_BUFFER = 3 -- studs head must be below water surface before O2 drains
local TERRAIN_WATER_SAMPLE_RADIUS = 1.5
local swimTimer = 0              -- tracks continuous seconds in Swimming state
local SWIM_CONFIRM_TIME = 0      -- O2 uses head-underwater test; no extra swimming confirm needed..

-- ══════════════════════════════════════════════════════════════════════════
-- BREATH METER UI
-- ══════════════════════════════════════════════════════════════════════════

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BreathMeterGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

-- Container (centered near bottom, above HUD)
local container = Instance.new("Frame")
container.Name = "BreathContainer"
container.Size = UDim2.new(0, 200, 0, 28)
container.Position = UDim2.new(0.5, -100, 0, 60)
container.BackgroundColor3 = Color3.fromRGB(10, 20, 40)
container.BackgroundTransparency = 0.3
container.BorderSizePixel = 0
container.Visible = false
container.Parent = screenGui
Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

-- Icon (water droplet emoji via text)
local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.Size = UDim2.new(0, 24, 1, 0)
icon.Position = UDim2.new(0, 4, 0, 0)
icon.BackgroundTransparency = 1
icon.Text = "O2"
icon.TextColor3 = Color3.fromRGB(80, 180, 255)
icon.Font = Enum.Font.GothamBold
icon.TextSize = 11
icon.Parent = container

-- Bar background
local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.Size = UDim2.new(1, -36, 0, 12)
barBg.Position = UDim2.new(0, 30, 0.5, -6)
barBg.BackgroundColor3 = Color3.fromRGB(20, 40, 60)
barBg.BorderSizePixel = 0
barBg.Parent = container
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

-- Bar fill
local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(60, 160, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBg
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

-- Breath timer text overlay
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.Size = UDim2.new(1, 0, 1, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = ""
timerLabel.TextColor3 = Color3.new(1, 1, 1)
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextSize = 9
timerLabel.Parent = barBg

-- ══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ══════════════════════════════════════════════════════════════════════════

-- Get the equipped favorite creature info from player data (uses GetFavoriteInfo remote or client cache)
local function getWaterCreatureBonus()
	local getFav = ReplicatedStorage:FindFirstChild("Events")
		and ReplicatedStorage.Events:FindFirstChild("GetFavoriteInfo")
	if not getFav or not getFav:IsA("RemoteFunction") then
		-- Fallback: check inventory event for favoriteUid
		local getInv = ReplicatedStorage:FindFirstChild("Events")
			and ReplicatedStorage.Events:FindFirstChild("GetInventory")
		if not getInv or not getInv:IsA("RemoteFunction") then return 0 end
		local ok, data = pcall(function() return getInv:InvokeServer() end)
		if not ok or not data then return 0 end
		local favUid = data.favoriteUid
		if not favUid or favUid == "" then return 0 end
		-- Find creature in inventory
		for _, entry in ipairs(data.inventory or {}) do
			if tostring(entry.uid) == tostring(favUid) then
				local info = CreatureData.GetById(entry.id)
				if info and CreatureData.IsWaterType(entry.id) then
					local lvl = entry.level or 1
					return math.min(lvl * BONUS_PER_LEVEL, MAX_BONUS)
				end
				return 0
			end
		end
		return 0
	end
	local ok, info = pcall(function() return getFav:InvokeServer() end)
	if not ok or not info then return 0 end
	if not info.creatureId then return 0 end
	if not CreatureData.IsWaterType(info.creatureId) then return 0 end
	local lvl = info.level or 1
	return math.min(lvl * BONUS_PER_LEVEL, MAX_BONUS)
end

-- Swimming state OR inside tagged WaterBlock OR ocean volume (Terrain/water volumes often lack Swimming)
local function getClientOceanPart()
	local biomes = Workspace:FindFirstChild("Biomes")
	local oceanBiome = biomes and biomes:FindFirstChild("OceanBiome")
	local oceanFolder = oceanBiome and oceanBiome:FindFirstChild("Ocean")
	local ocean = oceanFolder and oceanFolder:FindFirstChild("Ocean")
	if ocean and ocean:IsA("BasePart") then return ocean end
	if biomes then
		local oceanContainer = biomes:FindFirstChild("Ocean") or biomes:FindFirstChild("OceanBiome")
		if oceanContainer then
			local tag = (GameConfig and GameConfig.WaterBlockTag) or "WaterBlock"
			for _, part in ipairs(CollectionService:GetTagged(tag)) do
				if part and part:IsA("BasePart") and part.Parent and part:IsDescendantOf(oceanContainer) then
					return part
				end
			end
		end
	end
	return nil
end

local function getContainingTaggedWaterPart(worldPos)
	local tag = (GameConfig and GameConfig.WaterBlockTag) or "WaterBlock"
	if not tag or tag == "" then return nil end
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		if part and part:IsA("BasePart") and part.Parent then
			local lp = part.CFrame:PointToObjectSpace(worldPos)
			local h = part.Size * 0.5
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
				return part
			end
		end
	end
	return nil
end

local function getContainingWaterPart(worldPos)
	local tagged = getContainingTaggedWaterPart(worldPos)
	if tagged then return tagged end

	local ocean = getClientOceanPart()
	if ocean then
		local lp = ocean.CFrame:PointToObjectSpace(worldPos)
		local h = ocean.Size * 0.5
		if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
			return ocean
		end
	end
	return nil
end

local function isTerrainWaterAtPosition(worldPos)
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

local function isHeadUnderTerrainWater(headPos)
	-- Only count as underwater when water exists at head and still at a small
	-- point above head, so surface swimming/wading doesn't drain O2.
	if not isTerrainWaterAtPosition(headPos) then
		return false
	end
	return isTerrainWaterAtPosition(headPos + Vector3.new(0, HEAD_SUBMERGE_BUFFER, 0))
end

local function isPlayerSubmerged()
	local character = player.Character
	if not character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local head = character:FindFirstChild("Head")
	local probe = head and head.Position or (root.Position + Vector3.new(0, 1.5, 0)) -- approx head position fallback
	local waterPart = getContainingWaterPart(probe)
	if waterPart then
		local surfaceY = waterPart.CFrame:PointToWorldSpace(Vector3.new(0, waterPart.Size.Y * 0.5, 0)).Y
		return probe.Y <= (surfaceY - HEAD_SUBMERGE_BUFFER)
	end

	-- Terrain water path: if we are swimming, allow terrain-water check even
	-- when there is no tagged WaterBlock/ocean part at head position.
	return humanoid and humanoid:GetState() == Enum.HumanoidStateType.Swimming
		and isHeadUnderTerrainWater(probe)
end

local function setOxygenDepletedState(depleted)
	if oxygenDepleted == depleted then return end
	oxygenDepleted = depleted
	local events = ReplicatedStorage:FindFirstChild("Events")
	local oxygenEvt = events and events:FindFirstChild("OxygenState")
	if oxygenEvt then
		oxygenEvt:FireServer(depleted)
	end
end

local function showMeter()
	if meterVisible then return end
	meterVisible = true
	container.Visible = true
	container.BackgroundTransparency = 1
	TweenService:Create(container, TweenInfo.new(0.3), { BackgroundTransparency = 0.3 }):Play()
end

local function hideMeter()
	if not meterVisible then return end
	meterVisible = false
	TweenService:Create(container, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	task.delay(0.6, function()
		if not meterVisible then container.Visible = false end
	end)
end

local function updateMeterVisual()
	local ratio = maxBreath > 0 and math.clamp(breathRemaining / maxBreath, 0, 1) or 0
	barFill.Size = UDim2.new(ratio, 0, 1, 0)

	-- Color: blue when OK, yellow when low, red when drowning
	if ratio > 0.5 then
		barFill.BackgroundColor3 = Color3.fromRGB(60, 160, 255)
	elseif ratio > 0.2 then
		barFill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	else
		barFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	end

	timerLabel.Text = math.ceil(breathRemaining) .. "s"
end

-- ══════════════════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ══════════════════════════════════════════════════════════════════════════

-- Cache water creature bonus (recalculate when entering water, not every frame)
local cachedBonus = 0

RunService.Heartbeat:Connect(function(dt)
	-- Spawn grace: ignore transient Swimming state right after respawn
	if spawnGraceTimer > 0 then
		spawnGraceTimer = spawnGraceTimer - dt
		return
	end

	-- Track continuous swimming time (kept for stability; SWIM_CONFIRM_TIME may be 0)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local isSwimming = humanoid and humanoid:GetState() == Enum.HumanoidStateType.Swimming
	if isSwimming then
		swimTimer = swimTimer + dt
	else
		swimTimer = 0
	end

	-- Only run submerge check after optional confirm time
	local submerged = swimTimer >= SWIM_CONFIRM_TIME and isPlayerSubmerged()

	if submerged and not isUnderwater then
		isUnderwater = true
		breathActive = false
		underwaterGraceTimer = 0
		drownTickTimer = 0
		setOxygenDepletedState(false)
		cachedBonus = getWaterCreatureBonus()
		maxBreath = BASE_BREATH_TIME + cachedBonus
		breathRemaining = maxBreath
		hideMeter()
	elseif not submerged and isUnderwater then
		-- Just exited water
		isUnderwater = false
		breathActive = false
		underwaterGraceTimer = 0
		breathRemaining = maxBreath
		drownTickTimer = 0
		setOxygenDepletedState(false)
		hideMeter()
	end

	if not isUnderwater then return end

	-- Grace: meter hidden + no drain until SUBMERGE_GRACE seconds submerged
	if not breathActive then
		underwaterGraceTimer = underwaterGraceTimer + dt
		if underwaterGraceTimer < SUBMERGE_GRACE then
			return
		end
		breathActive = true
		drownTickTimer = 0
		breathRemaining = maxBreath
		showMeter()
		updateMeterVisual()
	end

	-- Drain breath (only after grace period)
	local prevBreath = breathRemaining
	breathRemaining = breathRemaining - dt

	-- Drowning: when breath runs out, deal damage on a tick interval
	if breathRemaining <= 0 then
		breathRemaining = 0
		local events = ReplicatedStorage:FindFirstChild("Events")
		local drownEvt = events and events:FindFirstChild("DrownDamage")

		-- Notify server once that oxygen is depleted (blocks regen server-side)
		setOxygenDepletedState(true)

		-- Immediate first damage tick the moment O2 hits 0.
		-- Then continue applying damage on interval.
		local shouldImmediateHit = prevBreath > 0
		drownTickTimer = drownTickTimer + dt
		if shouldImmediateHit or drownTickTimer >= DROWN_TICK_INTERVAL then
			if not shouldImmediateHit then
				drownTickTimer = drownTickTimer - DROWN_TICK_INTERVAL
			else
				drownTickTimer = 0
			end
			if drownEvt then
				drownEvt:FireServer(DROWN_DAMAGE)
			else
				-- Fallback: direct client damage (works for non-FE games or if server event missing)
				local character = player.Character
				if character then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						humanoid:TakeDamage(DROWN_DAMAGE)
					end
				end
			end
		end
	else
		-- Oxygen restored (still underwater but > 0): re-enable regen
		setOxygenDepletedState(false)
	end

	updateMeterVisual()
end)

-- Reset on respawn — force-hide immediately (don't rely on tween delay)
-- and add a brief spawn grace to ignore transient water states during load.
player.CharacterAdded:Connect(function()
	isUnderwater = false
	breathActive = false
	underwaterGraceTimer = 0
	breathRemaining = maxBreath
	drownTickTimer = 0
	meterVisible = false
	container.Visible = false
	spawnGraceTimer = SPAWN_GRACE
	swimTimer = 0
	setOxygenDepletedState(false)
end)

print("[UnderwaterBreathClient] Loaded - breath meter active")