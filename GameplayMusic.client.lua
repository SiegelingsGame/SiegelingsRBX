local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local config = GameConfig.GameplayMusic or {}

if config.Enabled == false then
	return
end

local function normalizeSoundId(value)
	if typeof(value) == "number" then
		if value <= 0 then
			return nil
		end
		return ("rbxassetid://%d"):format(value)
	end

	if type(value) ~= "string" then
		return nil
	end

	local trimmed = value:match("^%s*(.-)%s*$")
	if not trimmed or trimmed == "" or trimmed == "0" or trimmed == "rbxassetid://0" then
		return nil
	end

	local digitsOnly = trimmed:match("^(%d+)$")
	if digitsOnly then
		return "rbxassetid://" .. digitsOnly
	end

	if trimmed:match("^rbxassetid://%d+$") then
		return trimmed
	end

	return nil
end

local function resolveSoundIdFromImportedSound()
	local fallbackName = tostring(config.FallbackImportedSoundName or "Sieglings_ BattleTheme")
	local imported = SoundService:FindFirstChild(fallbackName)
	if imported and imported:IsA("Sound") then
		return normalizeSoundId(imported.SoundId)
	end
	return nil
end

local soundId = normalizeSoundId(config.SoundId) or resolveSoundIdFromImportedSound()
if not soundId then
	warn(
		"[GameplayMusic] Missing soundtrack id. Upload Sieglings_ BattleTheme.mp3 and set GameConfig.GameplayMusic.SoundId,"
			.. " or import a Sound in SoundService named '"
			.. tostring(config.FallbackImportedSoundName or "Sieglings_ BattleTheme")
			.. "'."
	)
	return
end

local function getOrCreateSoundGroup(name)
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end

	local soundGroup = Instance.new("SoundGroup")
	soundGroup.Name = name
	soundGroup.Parent = SoundService
	return soundGroup
end

local function screensAreBlocking()
	local waitForScreens = config.WaitForScreens
	if type(waitForScreens) ~= "table" then
		return false
	end

	for _, screenName in ipairs(waitForScreens) do
		local screenGui = playerGui:FindFirstChild(screenName)
		if screenGui and (not screenGui:IsA("ScreenGui") or screenGui.Enabled ~= false) then
			return true
		end
	end

	return false
end

local function waitForGameplayWindow()
	local initialDelay = tonumber(config.StartDelay) or 0
	if initialDelay > 0 then
		task.wait(initialDelay)
	end

	local deadline = os.clock() + math.max(5, tonumber(config.MaxScreenWait) or 45)
	local settleWindow = math.max(0.25, tonumber(config.ScreenSettleTime) or 0.75)
	local clearSince = nil

	while os.clock() < deadline do
		if screensAreBlocking() then
			clearSince = nil
		else
			clearSince = clearSince or os.clock()
			if os.clock() - clearSince >= settleWindow then
				return
			end
		end
		task.wait(0.1)
	end
end

local function waitForStartupReady()
	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then
		events = ReplicatedStorage:WaitForChild("Events", 15)
	end
	if not events then
		return
	end

	local criticalReady = events:FindFirstChild("LoadingCriticalReady")
	local worldReady = events:FindFirstChild("LoadingReady")
	if criticalReady then
		criticalReady.OnClientEvent:Wait()
	elseif worldReady then
		worldReady.OnClientEvent:Wait()
	end
end

local soundGroup = getOrCreateSoundGroup(config.SoundGroupName or "Music")
local soundName = config.SoundName or "SieglingsGameplayTheme"
local sound = SoundService:FindFirstChild(soundName)

if sound and not sound:IsA("Sound") then
	sound:Destroy()
	sound = nil
end

if not sound then
	sound = Instance.new("Sound")
	sound.Name = soundName
	sound.Parent = SoundService
end

sound.SoundId = soundId
sound.SoundGroup = soundGroup
sound.Volume = 0
sound.PlaybackSpeed = tonumber(config.PlaybackSpeed) or 1
sound.RollOffMode = Enum.RollOffMode.InverseTapered
sound.Archivable = false

local loopStart = math.max(0, tonumber(config.LoopStartTime) or 0)
local loopEnd = math.max(0, tonumber(config.LoopEndTime) or 0)
local useCustomLoop = loopEnd > loopStart + 0.05

sound.Looped = not useCustomLoop

local function restartFromLoopPoint()
	local restartTime = useCustomLoop and loopStart or 0
	if restartTime > 0 and sound.TimeLength > 0 then
		restartTime = math.min(restartTime, math.max(0, sound.TimeLength - 0.05))
	end
	sound.TimePosition = restartTime
	sound:Play()
end

task.spawn(function()
	waitForStartupReady()
	waitForGameplayWindow()

	if not sound.IsLoaded then
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
	end

	if not sound.IsPlaying then
		restartFromLoopPoint()
	end

	local targetVolume = math.max(0, tonumber(config.Volume) or 0.32)
	local fadeInTime = math.max(0, tonumber(config.FadeInTime) or 0)

	if fadeInTime > 0 then
		TweenService:Create(sound, TweenInfo.new(fadeInTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Volume = targetVolume,
		}):Play()
	else
		sound.Volume = targetVolume
	end

	sound.Ended:Connect(function()
		if useCustomLoop then
			restartFromLoopPoint()
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not useCustomLoop or not sound.IsPlaying then
			return
		end

		local soundLength = sound.TimeLength
		if soundLength <= 0 then
			return
		end

		local effectiveLoopEnd = math.min(loopEnd, soundLength)
		if effectiveLoopEnd <= loopStart + 0.05 then
			return
		end

		if sound.TimePosition >= effectiveLoopEnd - 0.03 then
			sound.TimePosition = loopStart
		end
	end)
end)
