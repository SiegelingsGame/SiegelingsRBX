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
local METER_ACTIVATE_DELAY = 10  -- seconds underwater before O2 meter appears and breath drains

-- ══════════════════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════════════════

local isUnderwater = false
local breathActive = false   -- true after METER_ACTIVATE_DELAY seconds underwater
local underwaterGraceTimer = 0
local breathRemaining = BASE_BREATH_TIME
local maxBreath = BASE_BREATH_TIME
local drownTickTimer = 0
local meterVisible = false

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

local function isPlayerSwimming()
	local character = player.Character
	if not character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	return humanoid:GetState() == Enum.HumanoidStateType.Swimming
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
	local swimming = isPlayerSwimming()

	if swimming and not isUnderwater then
		-- Just entered water: start grace period, meter not active yet
		isUnderwater = true
		breathActive = false
		underwaterGraceTimer = 0
		drownTickTimer = 0
	elseif not swimming and isUnderwater then
		-- Just exited water
		isUnderwater = false
		breathActive = false
		underwaterGraceTimer = 0
		breathRemaining = maxBreath
		drownTickTimer = 0
		hideMeter()
	end

	if not isUnderwater then return end

	-- Grace period: wait METER_ACTIVATE_DELAY seconds before activating O2 meter and breath drain
	if not breathActive then
		underwaterGraceTimer = underwaterGraceTimer + dt
		if underwaterGraceTimer >= METER_ACTIVATE_DELAY then
			breathActive = true
			cachedBonus = getWaterCreatureBonus()
			maxBreath = BASE_BREATH_TIME + cachedBonus
			breathRemaining = maxBreath
			drownTickTimer = 0
			showMeter()
		else
			return  -- don't drain or update meter during grace period
		end
	end

	-- Drain breath (only after grace period)
	breathRemaining = breathRemaining - dt

	-- Drowning: when breath runs out, deal damage on a tick interval
	if breathRemaining <= 0 then
		breathRemaining = 0
		drownTickTimer = drownTickTimer + dt
		if drownTickTimer >= DROWN_TICK_INTERVAL then
			drownTickTimer = drownTickTimer - DROWN_TICK_INTERVAL
			-- Request server to deal drown damage (client can't directly damage humanoid in FilteringEnabled)
			local drownEvt = ReplicatedStorage:FindFirstChild("Events")
				and ReplicatedStorage.Events:FindFirstChild("DrownDamage")
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
	end

	updateMeterVisual()
end)

-- Reset on respawn
player.CharacterAdded:Connect(function()
	isUnderwater = false
	breathActive = false
	underwaterGraceTimer = 0
	breathRemaining = maxBreath
	drownTickTimer = 0
	hideMeter()
end)

print("[UnderwaterBreathClient] Loaded - breath meter active")