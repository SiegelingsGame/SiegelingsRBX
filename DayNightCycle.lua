--[[
	DayNightCycle.lua - ServerScriptService (ModuleScript)
	Controls Lighting.ClockTime based on GameConfig.
	- Config: DayNightCycleEnabled, DayNightCycleSeconds (default 30)
	- One full real-time cycle = 24 in-game hours (dawn → day → dusk → night)[]gt
]]

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local GameConfig = nil
local function getConfig()
	if not GameConfig then
		GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("GameConfig"))
	end
	return GameConfig
end

local DayNightCycle = {}
DayNightCycle._conn = nil
DayNightCycle._startTime = nil
DayNightCycle._baseBrightness = nil

local function smoothstep01(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function getNightBlendFactor(clockTime, startH, endH, transitionHours)
	local nightLength = (endH - startH) % 24
	if nightLength <= 0 then
		return 0
	end
	if nightLength >= 24 then
		return 1
	end

	local u = (clockTime - startH) % 24
	if u >= nightLength then
		return 0
	end

	local transition = math.max(0, tonumber(transitionHours) or 0)
	if transition <= 0 then
		return 1
	end

	transition = math.min(transition, nightLength * 0.5)
	local fadeIn = smoothstep01(u / transition)
	local fadeOut = smoothstep01((nightLength - u) / transition)
	return fadeIn * fadeOut
end

function DayNightCycle.Init()
	local config = getConfig()
	if not config.DayNightCycleEnabled then
		return
	end

	local cycleSeconds = math.max(1, tonumber(config.DayNightCycleSeconds) or 30)
	local startHour = tonumber(config.DayNightCycleStartHour) or 5.5
	local nightDarknessReduction = math.clamp(tonumber(config.NightDarknessReductionPercent) or 0.10, 0, 1)

	-- Stop existing cycle if re-initializing
	if DayNightCycle._conn then
		DayNightCycle._stopCycle = true
		DayNightCycle._conn = nil
	end

	if DayNightCycle._baseBrightness == nil then
		DayNightCycle._baseBrightness = Lighting.Brightness
	end

	DayNightCycle._startTime = tick()
	DayNightCycle._stopCycle = false

	-- PERFORMANCE: Use task.wait loop instead of Heartbeat (lighting doesn't need 60 updates/sec)
	DayNightCycle._conn = {} -- non-nil indicates running
	task.spawn(function()
		while not DayNightCycle._stopCycle do
			task.wait(0.1) -- 10 updates/sec sufficient for day/night
			local cfg = getConfig()
			if not cfg.DayNightCycleEnabled then
				break
			end
			local sec = math.max(1, tonumber(cfg.DayNightCycleSeconds) or 30)
			local dawnStartHour = tonumber(cfg.DayNightCycleStartHour) or startHour
			local darknessReduction = math.clamp(tonumber(cfg.NightDarknessReductionPercent) or nightDarknessReduction, 0, 1)
			local nightStartHour = tonumber(cfg.NightStartHour) or 22
			local nightEndHour = tonumber(cfg.NightEndHour) or 5
			local transitionHours = tonumber(cfg.NightDarknessTransitionHours) or 0.75
			local elapsed = tick() - DayNightCycle._startTime
			local progress = (elapsed % sec) / sec
			local clockTime = (dawnStartHour + (progress * 24)) % 24
			Lighting.ClockTime = clockTime

			if DayNightCycle._baseBrightness ~= nil then
				local blend = getNightBlendFactor(clockTime, nightStartHour, nightEndHour, transitionHours)
				local brightnessScale = 1 + (darknessReduction * blend)
				Lighting.Brightness = DayNightCycle._baseBrightness * brightnessScale
			end
		end
		if DayNightCycle._baseBrightness ~= nil then
			Lighting.Brightness = DayNightCycle._baseBrightness
		end
		DayNightCycle._conn = nil
	end)

end

-- Returns true if it is currently night (defense/income monsters sleep except Shadow/Lightning)
function DayNightCycle.IsNight()
	local cfg = getConfig()
	if not cfg.DayNightCycleEnabled then return false end
	local ct = Lighting.ClockTime
	local startH = tonumber(cfg.NightStartHour) or 18
	local endH = tonumber(cfg.NightEndHour) or 6
	if startH > endH then
		return ct >= startH or ct < endH
	end
	return ct >= startH and ct < endH
end

-- Returns current in-game ClockTime (0-24)
function DayNightCycle.GetClockTime()
	return Lighting.ClockTime
end

return DayNightCycle
