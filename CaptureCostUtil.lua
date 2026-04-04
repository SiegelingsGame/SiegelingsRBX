-- CaptureCostUtil.lua — ReplicatedStorage.Modules
-- Shared capture cost math for base statue bonus (client tooltip + server).

local GameConfig = require(script.Parent.GameConfig)

local CaptureCostUtil = {}

function CaptureCostUtil.ApplyDecorStatueDiscount(baseCost, creatureId, decorBonusMap)
	if not decorBonusMap or not creatureId or not decorBonusMap[creatureId] then
		return baseCost
	end
	local mult = GameConfig.DecorStatueCaptureCostMultiplier
	if type(mult) ~= "number" or mult >= 1 or mult <= 0 then
		return baseCost
	end
	return math.floor(baseCost * mult)
end

function CaptureCostUtil.ApplyDecorStatueHoldMultiplier(holdTime, creatureId, decorBonusMap)
	if not decorBonusMap or not creatureId or not decorBonusMap[creatureId] then
		return holdTime
	end
	local mult = GameConfig.DecorStatueCaptureHoldMultiplier
	if type(mult) ~= "number" or mult >= 1 or mult <= 0 then
		return holdTime
	end
	return math.max(0.1, holdTime * mult)
end

return CaptureCostUtil
