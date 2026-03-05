--[[
	DayNightCycle.lua - ServerScriptService (ModuleScript)
	Controls Lighting.ClockTime based on GameConfig.
	- Config: DayNightCycleEnabled, DayNightCycleSeconds (default 30)
	- One full real-time cycle = 24 in-game hours (dawn → day → dusk → night)
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

function DayNightCycle.Init()
	local config = getConfig()
	if not config.DayNightCycleEnabled then
		return
	end

	local cycleSeconds = math.max(1, tonumber(config.DayNightCycleSeconds) or 30)

	-- Stop existing cycle if re-initializing
	if DayNightCycle._conn then
		DayNightCycle._stopCycle = true
		DayNightCycle._conn = nil
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
			local elapsed = tick() - DayNightCycle._startTime
			local progress = (elapsed % sec) / sec
			Lighting.ClockTime = progress * 24
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
