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
		local gcd = script.Parent:WaitForChild("GameConfigData", 10)
		if not gcd then
			warn("[GameConfig] GameConfigData module not found after 10s! Check Rojo sync.")
			cached = {}
			return cached
		end
		cached = require(gcd)
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
