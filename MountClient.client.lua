--[[
	MountClient.client.lua
	StarterPlayer.StarterPlayerScripts (LocalScript)

	══════════════════════════════════════════════════════════════════════════
	MOUNT CLIENT — Visual effects, flying input, and mount HUD
	══════════════════════════════════════════════════════════════════════════

	Listens for MountStarted/MountEnded from server.
	When mounted:
		- Hides player leg meshes for clean riding visual
		- Starts mount animation driver (Idle/Move based on player velocity)
		- Shows mount speed HUD indicator + elemental bonus badges
		- For flying mounts: handles Space/Ctrl vertical input, sends to server
		- Fires MountStateChanged BindableEvent so SprintClient adjusts speed
	When dismounted:
		- Restores player visuals
		- Clears HUD
		- Fires MountStateChanged(false, 0)

	CONTROLS:
		- Mount/Dismount: triggered from inventory UI "Mount" button
		- Flying vertical: Space = ascend, LeftControl = descend
		- Sprint while mounted: Shift (handled by SprintClient via MountStateChanged)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig
do
	local ok, mod = pcall(function() return require(ReplicatedStorage.Modules.GameConfig) end)
	GameConfig = ok and mod or {}
end

local CreatureData
do
	local ok, mod = pcall(function() return require(ReplicatedStorage.Modules.CreatureData) end)
	CreatureData = ok and mod or {}
end

-- ══════════════════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════════════════

local isMounted = false
local currentMountType = nil  -- "Ground" | "Flying" | "Swimming"
local currentMountSpeed = 0
local currentBonuses = {}
local currentCreatureId = nil
local mountModel = nil
local mountHudGui = nil
local flyingInputConn = nil
local animationConn = nil
local shieldConn = nil -- AttributeChanged connection for shield updates

-- [BasePart] = original Transparency (restored on dismount; part keys survive until restored)
local hiddenLegPartTransparency = {}
local INVENTORY_GUI_NAME = "InventoryUI"
local SUMMON_CARD_NAME = "FavoriteSummonCard"
local BATTLE_MENU_NAME = "BattleMenuToggle"
local MOUNT_HUD_GAP = 10
local MOUNT_HUD_RIGHT_PADDING = 18
local MOUNT_HUD_PC_WIDTH = 250
local MOUNT_HUD_PC_MIN_WIDTH = 180
local MOUNT_HUD_PC_HEIGHT = 62
local MOUNT_HUD_PC_FLY_HEIGHT = 76
local MOUNT_HUD_FALLBACK_WIDTH = 240
local MOUNT_HUD_FALLBACK_HEIGHT = 64
local MOUNT_HUD_FALLBACK_FLY_HEIGHT = 78
local MOUNT_HUD_BOTTOM_PADDING = 86
local MOUNT_HUD_BG = Color3.fromRGB(16, 18, 30)
local MOUNT_HUD_STROKE = Color3.fromRGB(255, 200, 72)

local BONUS_SHORT_NAMES = {
	LavaImmunity = "Lava Safe",
	NoOxygenLoss = "No O2",
	IcePenaltyImmunity = "Ice Safe",
	ElectricHazardImmunity = "Shock Safe",
	GlideBonus = "Glide",
	Flight = "Flight",
	SwimMount = "Swim",
}
local MOBILE_TOUCH_FLIGHT = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local MOBILE_FLY_CAMERA_DEADZONE = 0.12

-- ══════════════════════════════════════════════════════════════════════════
-- BINDABLE EVENTS (for SprintClient communication)
-- ══════════════════════════════════════════════════════════════════════════

local function ensureBindable(name)
	local existing = playerGui:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then return existing end
	local e = Instance.new("BindableEvent")
	e.Name = name
	e.Parent = playerGui
	return e
end

local mountStateEvt = ensureBindable("MountStateChanged")

local function getViewportSize()
	local camera = workspace.CurrentCamera
	return (camera and camera.ViewportSize) or Vector2.new(1280, 720)
end

local function findSummonCard()
	local inventoryGui = playerGui:FindFirstChild(INVENTORY_GUI_NAME)
	if not inventoryGui then return nil end
	local summonCard = inventoryGui:FindFirstChild(SUMMON_CARD_NAME, true)
	if summonCard and summonCard:IsA("GuiObject") and summonCard.Visible then
		return summonCard
	end
	return nil
end

local function getAnchorTop()
	local inventoryGui = playerGui:FindFirstChild(INVENTORY_GUI_NAME)
	if not inventoryGui then return nil end

	local top = nil
	local summonCard = inventoryGui:FindFirstChild(SUMMON_CARD_NAME, true)
	if summonCard and summonCard:IsA("GuiObject") and summonCard.Visible then
		top = summonCard.AbsolutePosition.Y
	end

	local battleMenu = inventoryGui:FindFirstChild(BATTLE_MENU_NAME, true)
	if battleMenu and battleMenu:IsA("GuiObject") and battleMenu.Visible then
		top = top and math.max(top, battleMenu.AbsolutePosition.Y) or battleMenu.AbsolutePosition.Y
	end

	return top
end

local function formatBonusesText(bonuses)
	if not bonuses or #bonuses == 0 then return "" end
	local parts = {}
	for _, bonus in ipairs(bonuses) do
		table.insert(parts, BONUS_SHORT_NAMES[bonus] or bonus)
	end
	return table.concat(parts, " | ")
end

local function getMountHudBounds(mountType)
	local viewport = getViewportSize()
	local desktopHeight = (mountType == "Flying") and MOUNT_HUD_PC_FLY_HEIGHT or MOUNT_HUD_PC_HEIGHT
	local summonCard = findSummonCard()

	if UserInputService.KeyboardEnabled and summonCard then
		local left = summonCard.AbsolutePosition.X + summonCard.AbsoluteSize.X + MOUNT_HUD_GAP
		local top = getAnchorTop() or summonCard.AbsolutePosition.Y
		local width = math.min(MOUNT_HUD_PC_WIDTH, viewport.X - left - MOUNT_HUD_RIGHT_PADDING)
		if width >= MOUNT_HUD_PC_MIN_WIDTH then
			return width, desktopHeight, left, top
		end
	end

	local fallbackHeight = (mountType == "Flying") and MOUNT_HUD_FALLBACK_FLY_HEIGHT or MOUNT_HUD_FALLBACK_HEIGHT
	local fallbackWidth = math.min(MOUNT_HUD_FALLBACK_WIDTH, math.max(180, viewport.X - 24))
	local fallbackX = math.max(12, math.floor((viewport.X - fallbackWidth) * 0.5))
	local fallbackY = math.max(12, viewport.Y - fallbackHeight - MOUNT_HUD_BOTTOM_PADDING)
	return fallbackWidth, fallbackHeight, fallbackX, fallbackY
end

-- ══════════════════════════════════════════════════════════════════════════
-- PLAYER VISUAL HIDING (hide legs while mounted)
-- ══════════════════════════════════════════════════════════════════════════

local LEG_PARTS = {
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
	"Left Leg", "Right Leg",
}

local function collectLegBaseParts(char)
	local list = {}
	for _, partName in ipairs(LEG_PARTS) do
		local root = char:FindFirstChild(partName, true)
		if root and root:IsA("BasePart") then
			table.insert(list, root)
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(list, d)
				end
			end
		end
	end
	return list
end

local function hidePlayerLegs()
	local char = player.Character
	if not char then return end
	for _, part in ipairs(collectLegBaseParts(char)) do
		if not hiddenLegPartTransparency[part] then
			hiddenLegPartTransparency[part] = part.Transparency
			part.Transparency = 1
		end
	end
end

-- Force default-visible legs (covers missed restores, new limbs streaming in, or stale state)
local function ensureLegPartsVisible(char)
	if not char then return end
	for _, part in ipairs(collectLegBaseParts(char)) do
		part.Transparency = 0
	end
end

local function restorePlayerLegs()
	local char = player.Character
	hiddenLegPartTransparency = {}
	if char then
		ensureLegPartsVisible(char)
	end
end

-- ══════════════════════════════════════════════════════════════════════════
-- MOUNT HUD (speed indicator + bonus badges)
-- ══════════════════════════════════════════════════════════════════════════

local function createMountHud(creatureId, mountType, speed, bonuses)
	-- Destroy old HUD if any
	if mountHudGui and mountHudGui.Parent then mountHudGui:Destroy() end

	local info = CreatureData and CreatureData.GetById and CreatureData.GetById(creatureId)
	local displayName = info and info.displayName or creatureId
	local bonusText = formatBonusesText(bonuses)
	local width, height, posX, posY = getMountHudBounds(mountType)

	mountHudGui = Instance.new("ScreenGui")
	mountHudGui.Name = "MountHUD"
	mountHudGui.ResetOnSpawn = false
	mountHudGui.IgnoreGuiInset = false
	mountHudGui.DisplayOrder = 8
	mountHudGui.Parent = playerGui

	-- Compact card that anchors beside the summon card on desktop layouts.
	local container = Instance.new("Frame")
	container.Name = "MountInfo"
	container.Size = UDim2.fromOffset(width, height)
	container.Position = UDim2.fromOffset(posX, posY)
	container.BackgroundColor3 = MOUNT_HUD_BG
	container.BackgroundTransparency = 0.08
	container.BorderSizePixel = 0
	container.Parent = mountHudGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = MOUNT_HUD_STROKE
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = container

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 4, 1, -12)
	accent.Position = UDim2.new(0, 6, 0, 6)
	accent.BackgroundColor3 = Color3.fromRGB(95, 220, 255)
	accent.BorderSizePixel = 0
	accent.Parent = container
	Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

	-- Mount name + type badge
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "MountName"
	nameLabel.Size = UDim2.new(1, -26, 0, 18)
	nameLabel.Position = UDim2.new(0, 16, 0, 7)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = string.format("%s  [%s]", displayName, mountType)
	nameLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = container

	-- Speed indicator
	local speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "SpeedLabel"
	speedLabel.Size = bonusText ~= "" and UDim2.new(0.36, -4, 0, 14) or UDim2.new(1, -26, 0, 14)
	speedLabel.Position = UDim2.new(0, 16, 0, 25)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Text = string.format("%d studs/s", math.floor(speed))
	speedLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	speedLabel.Font = Enum.Font.Gotham
	speedLabel.TextSize = 10
	speedLabel.TextXAlignment = Enum.TextXAlignment.Left
	speedLabel.Parent = container

	-- Bonus badges (right side)
	if bonusText ~= "" then
		local bonusLabel = Instance.new("TextLabel")
		bonusLabel.Name = "BonusLabel"
		bonusLabel.Size = UDim2.new(0.64, -18, 0, 14)
		bonusLabel.Position = UDim2.new(0.36, 2, 0, 25)
		bonusLabel.BackgroundTransparency = 1
		bonusLabel.Text = bonusText
		bonusLabel.TextColor3 = Color3.fromRGB(100, 255, 180)
		bonusLabel.Font = Enum.Font.GothamBold
		bonusLabel.TextSize = 10
		bonusLabel.TextTruncate = Enum.TextTruncate.AtEnd
		bonusLabel.TextXAlignment = Enum.TextXAlignment.Right
		bonusLabel.Parent = container
	end

	-- ── Mount Shield Bar ──
	-- Reads MountShieldCurrent / MountShieldMax attributes set by server
	local shieldMax = player:GetAttribute("MountShieldMax") or 0
	local shieldCurrent = player:GetAttribute("MountShieldCurrent") or shieldMax
	local shieldYOffset = 42

	if shieldMax > 0 then
		-- Shield bar background
		local shieldBg = Instance.new("Frame")
		shieldBg.Name = "ShieldBarBg"
		shieldBg.Size = UDim2.new(1, -32, 0, 10)
		shieldBg.Position = UDim2.new(0, 16, 0, shieldYOffset)
		shieldBg.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
		shieldBg.BorderSizePixel = 0
		shieldBg.Parent = container

		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 4)
		bgCorner.Parent = shieldBg

		-- Shield bar fill
		local shieldFill = Instance.new("Frame")
		shieldFill.Name = "ShieldBarFill"
		local fillPct = (shieldMax > 0) and math.clamp(shieldCurrent / shieldMax, 0, 1) or 1
		shieldFill.Size = UDim2.new(fillPct, 0, 1, 0)
		shieldFill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
		shieldFill.BorderSizePixel = 0
		shieldFill.Parent = shieldBg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = shieldFill

		-- Shield value text
		local shieldValLabel = Instance.new("TextLabel")
		shieldValLabel.Name = "ShieldValue"
		shieldValLabel.Size = UDim2.new(1, 0, 1, 0)
		shieldValLabel.BackgroundTransparency = 1
		shieldValLabel.Text = string.format("Shield %d / %d", math.floor(shieldCurrent), math.floor(shieldMax))
		shieldValLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
		shieldValLabel.Font = Enum.Font.GothamBold
		shieldValLabel.TextSize = 8
		shieldValLabel.Parent = shieldBg

		-- Live update via attribute changes
		if shieldConn then shieldConn:Disconnect() end
		shieldConn = player:GetAttributeChangedSignal("MountShieldCurrent"):Connect(function()
			local cur = player:GetAttribute("MountShieldCurrent") or 0
			local mx = player:GetAttribute("MountShieldMax") or 1
			local pct = math.clamp(cur / mx, 0, 1)
			if shieldFill and shieldFill.Parent then
				shieldFill.Size = UDim2.new(pct, 0, 1, 0)
				-- Color: blue when full, orange when recharging, red when empty
				if pct <= 0 then
					shieldFill.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
				elseif pct < 1 then
					shieldFill.BackgroundColor3 = Color3.fromRGB(220, 160, 50)
				else
					shieldFill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
				end
			end
			if shieldValLabel and shieldValLabel.Parent then
				shieldValLabel.Text = string.format("Shield %d / %d", math.floor(cur), math.floor(mx))
			end
		end)
	end

	-- Dismount hint (flying mounts)
	if mountType == "Flying" then
		local flyHint = Instance.new("TextLabel")
		flyHint.Name = "FlyHint"
		flyHint.Size = UDim2.new(1, -26, 0, 12)
		flyHint.Position = UDim2.new(0, 16, 0, height - 17)
		flyHint.BackgroundTransparency = 1
		flyHint.Text = MOBILE_TOUCH_FLIGHT and "Fly: look up/down while moving" or "Fly: Space / Ctrl"
		flyHint.TextColor3 = Color3.fromRGB(180, 180, 200)
		flyHint.Font = Enum.Font.Gotham
		flyHint.TextSize = 9
		flyHint.TextXAlignment = Enum.TextXAlignment.Left
		flyHint.Parent = container
	end
end

local function destroyMountHud()
	if mountHudGui and mountHudGui.Parent then
		mountHudGui:Destroy()
	end
	mountHudGui = nil
end

-- ══════════════════════════════════════════════════════════════════════════
-- FLYING INPUT (Space=up, Ctrl=down → send target Y to server)
-- ══════════════════════════════════════════════════════════════════════════

local flyUpHeld = false
local flyDownHeld = false

local function startFlyingInput()
	if flyingInputConn then return end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local mountFlyInput = eventsFolder and eventsFolder:FindFirstChild("MountFlyInput")

	-- Key tracking
	local upConn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.Space then flyUpHeld = true end
		if input.KeyCode == Enum.KeyCode.LeftControl then flyDownHeld = true end
	end)
	local upEndConn = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space then flyUpHeld = false end
		if input.KeyCode == Enum.KeyCode.LeftControl then flyDownHeld = false end
	end)

	-- Send vertical target every frame
	local verticalSpeed = GameConfig.MountFlyVerticalSpeed or 25
	flyingInputConn = RunService.RenderStepped:Connect(function(dt)
		if not isMounted or currentMountType ~= "Flying" then return end
		local char = player.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local hum = char:FindFirstChildOfClass("Humanoid")

		local currentY = root.Position.Y
		local deltaY = 0
		if flyUpHeld then deltaY = verticalSpeed * dt end
		if flyDownHeld then deltaY = -verticalSpeed * dt end
		if deltaY == 0 and MOBILE_TOUCH_FLIGHT and hum and hum.MoveDirection.Magnitude > 0.05 then
			local camera = workspace.CurrentCamera
			local lookY = camera and camera.CFrame.LookVector.Y or 0
			if math.abs(lookY) >= MOBILE_FLY_CAMERA_DEADZONE then
				deltaY = verticalSpeed * dt * lookY
			end
		end

		if deltaY ~= 0 then
			local targetY = currentY + deltaY
			-- Send to server for validation and BodyPosition update
			if mountFlyInput then
				mountFlyInput:FireServer(targetY)
			end
		end
	end)

	-- Store connections for cleanup
	flyingInputConn._upConn = upConn
	flyingInputConn._upEndConn = upEndConn
end

local function stopFlyingInput()
	flyUpHeld = false
	flyDownHeld = false
	if flyingInputConn then
		-- Disconnect the RenderStepped connection
		if flyingInputConn.Disconnect then flyingInputConn:Disconnect() end
		-- Disconnect the key listeners stored on it
		if flyingInputConn._upConn then flyingInputConn._upConn:Disconnect() end
		if flyingInputConn._upEndConn then flyingInputConn._upEndConn:Disconnect() end
		flyingInputConn = nil
	end
end

-- ══════════════════════════════════════════════════════════════════════════
-- EVENT HANDLERS
-- ══════════════════════════════════════════════════════════════════════════

local function onMountStarted(creatureId, mountType, speed, bonuses)
	isMounted = true
	currentMountType = mountType
	currentMountSpeed = speed
	currentBonuses = bonuses or {}
	currentCreatureId = creatureId

	-- Hide player legs (immediate + deferred: limbs/LC may stream in after mount)
	hidePlayerLegs()
	task.defer(hidePlayerLegs)
	task.delay(0.15, function()
		if isMounted then hidePlayerLegs() end
	end)

	-- Create HUD
	createMountHud(creatureId, mountType, speed, bonuses)

	-- Notify SprintClient
	mountStateEvt:Fire(true, speed)

	-- Start flying input if needed
	if mountType == "Flying" then
		startFlyingInput()
	end

	print("[MountClient] Mounted:", creatureId, mountType, "speed:", speed)
end

local function onMountEnded(errorMsg)
	local hadVisualState = isMounted or next(hiddenLegPartTransparency) ~= nil or (mountHudGui and mountHudGui.Parent)
	if not hadVisualState then return end

	isMounted = false
	currentMountType = nil
	currentMountSpeed = 0
	currentBonuses = {}
	currentCreatureId = nil

	-- Restore player legs
	restorePlayerLegs()

	-- Destroy HUD
	destroyMountHud()
	if shieldConn then shieldConn:Disconnect(); shieldConn = nil end

	-- Stop flying input
	stopFlyingInput()

	-- Notify SprintClient
	mountStateEvt:Fire(false, 0)

	print("[MountClient] Dismounted", errorMsg and ("reason: " .. tostring(errorMsg)) or "")
end

-- ══════════════════════════════════════════════════════════════════════════
-- INIT — Wait for Events and connect
-- ══════════════════════════════════════════════════════════════════════════

local function init()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
	if not eventsFolder then
		warn("[MountClient] Events folder not found!")
		return
	end

	local mountStarted = eventsFolder:WaitForChild("MountStarted", 10)
	local mountEnded = eventsFolder:WaitForChild("MountEnded", 10)

	if mountStarted then
		mountStarted.OnClientEvent:Connect(onMountStarted)
	end

	if mountEnded then
		mountEnded.OnClientEvent:Connect(onMountEnded)
	end

	-- Character respawn: clear mount visuals; ensure new rig legs are visible
	player.CharacterAdded:Connect(function(char)
		if isMounted then
			onMountEnded("respawn")
		end
		hiddenLegPartTransparency = {}
		task.defer(function()
			if player:GetAttribute("IsMounted") ~= true and char and char.Parent then
				ensureLegPartsVisible(char)
			end
		end)
	end)

	-- If server clears IsMounted before/without MountEnded, still restore the rig
	player:GetAttributeChangedSignal("IsMounted"):Connect(function()
		if player:GetAttribute("IsMounted") == true then return end
		if next(hiddenLegPartTransparency) == nil and not isMounted and not (mountHudGui and mountHudGui.Parent) then
			return
		end
		onMountEnded("IsMounted cleared")
	end)

	print("[MountClient] Initialized")
end

init()
