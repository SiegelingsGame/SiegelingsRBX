--[[
	ServerLog.lua — ReplicatedStorage/Modules
	Gates noisy startup / diagnostic logging behind GameConfig.DebugServerLogging.
	Server scripts should require this from the server only (pattern matches GameConfig).
]]

local GameConfig = require(script.Parent.GameConfig)

local warnedOnce = {}

local ServerLog = {}

function ServerLog.PrintDebug(...)
	if GameConfig.DebugServerLogging then
		print(...)
	end
end

function ServerLog.WarnDebug(...)
	if GameConfig.DebugServerLogging then
		warn(...)
	end
end

--- Non-debug warnings that should never spam (e.g. missing optional asset): call once per key.
function ServerLog.WarnOnce(key, ...)
	if warnedOnce[key] then
		return
	end
	warnedOnce[key] = true
	warn(...)
end

return ServerLog
