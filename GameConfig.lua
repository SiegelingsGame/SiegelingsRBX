--[[
	GameConfig.lua
	ReplicatedStorage/Modules/GameConfig
	Central configuration. Shared by client and server.
	Returns a proxy that lazy-loads GameConfigData to avoid "required recursively" when
	multiple scripts require(GameConfig) in parallel.
]]

local cached

local function get()
	if not cached then
		cached = require(script.Parent:WaitForChild("GameConfigData"))
	end
	return cached
end

return setmetatable({}, {
	__index = function(_, k)
		return get()[k]
	end,
	__newindex = function(_, k, v)
		get()[k] = v
	end,
})
