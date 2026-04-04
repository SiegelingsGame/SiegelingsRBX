-- SprintClient.client.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Sprint: mobile uses toggle button; desktop uses hold Shift.
-- Applies PlayerSprintSpeed / PlayerWalkSpeed to Humanoid.
-- Respects freeze (WalkSpeed 0) from LoadingGate by not overriding when current speed is 0.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig
do
	local ok, mod = pcall(function() return require(ReplicatedStorage.Modules.GameConfig) end)
	GameConfig = (ok and mod) and mod or {}
end

local BASE_SPEED = (function()
	if GameConfig.DebugDoubleSpeed then return 32 end
	return GameConfig.PlayerWalkSpeed or 16
end)()
local SPRINT_SPEED = GameConfig.PlayerSprintSpeed or 26
local MOBILE_SPRINT_TOGGLE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- State:
-- - Desktop: Shift-held controls sprint.
-- - Mobile: button toggle controls sprint.
local shiftHeld = false
local buttonToggled = false

-- Mount awareness: when mounted, sprint uses mount speed * mount sprint multiplier
local isMountedLocal = false
local mountBaseSpeed = 0

local function isSprintActive()
	if MOBILE_SPRINT_TOGGLE then
		return buttonToggled
	end
	return shiftHeld
end

-- BindableEvents for UI: ToggleSprint (button tap), SprintStateChanged (UI can show active state)
local function ensureBindable(name)
	local existing = playerGui:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then return existing end
	local e = Instance.new("BindableEvent")
	e.Name = name
	e.Parent = playerGui
	return e
end

local toggleSprintEvt = ensureBindable("ToggleSprint")
local sprintStateChangedEvt = ensureBindable("SprintStateChanged")

toggleSprintEvt.Event:Connect(function()
	if not MOBILE_SPRINT_TOGGLE then return end
	buttonToggled = not buttonToggled
	sprintStateChangedEvt:Fire(isSprintActive())
	applySprintToCharacter()
end)

-- Apply walk or sprint speed to current character. Do not override when WalkSpeed is 0 (freeze).
-- When mounted, uses mount speed with MountSprintMultiplier instead of normal sprint.
local function applySprintToCharacter()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	if not hum then return end
	-- Don't override freeze (e.g. LoadingGate sets 0)
	if hum.WalkSpeed == 0 then return end

	local desired
	if isMountedLocal and mountBaseSpeed > 0 then
		-- Mounted: use mount speed with mount sprint multiplier
		local sprintMult = GameConfig.MountSprintMultiplier or 1.4
		desired = isSprintActive() and math.floor(mountBaseSpeed * sprintMult) or mountBaseSpeed
	else
		desired = isSprintActive() and SPRINT_SPEED or BASE_SPEED
	end
	if hum.WalkSpeed ~= desired then
		hum.WalkSpeed = desired
	end
end

-- Shift: hold to sprint
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if MOBILE_SPRINT_TOGGLE then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftHeld = true
		sprintStateChangedEvt:Fire(true)
		applySprintToCharacter()
	end
end)

UserInputService.InputEnded:Connect(function(input, _)
	if MOBILE_SPRINT_TOGGLE then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftHeld = false
		sprintStateChangedEvt:Fire(isSprintActive())
		applySprintToCharacter()
	end
end)

-- Apply on character spawn and when character is ready (Humanoid may not exist immediately)
local function onCharacterAdded(char)
	char:WaitForChild("Humanoid", 10)
	applySprintToCharacter()
	-- Re-apply when Humanoid.WalkSpeed is changed by others (e.g. unfreeze) so we restore our desired speed
	local hum = char:FindFirstChild("Humanoid")
	if hum then
		hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			-- Only react when we're not frozen (0) and we have a desired state
			if hum.WalkSpeed ~= 0 then
				applySprintToCharacter()
			end
		end)
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Mount state listener: MountClient fires MountStateChanged(isMounted, baseSpeed)
task.defer(function()
	local mountStateEvt = playerGui:WaitForChild("MountStateChanged", 15)
	if mountStateEvt and mountStateEvt:IsA("BindableEvent") then
		mountStateEvt.Event:Connect(function(mounted, baseSpeed)
			isMountedLocal = mounted == true
			mountBaseSpeed = (type(baseSpeed) == "number" and baseSpeed) or 0
			applySprintToCharacter()
		end)
	end
end)
