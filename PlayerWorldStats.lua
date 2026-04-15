-- PlayerWorldStats.lua — ReplicatedStorage.Modules
-- Pilot (player) combat/movement stats scaled by account level using the same
-- per-level growth as creatures (GameConfig.StatGainPerLevel). Used by server
-- (sync, combat, defense) and profile payload.

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local PlayerWorldStats = {}

function PlayerWorldStats.LevelMultiplier(level)
	level = math.max(1, math.floor(tonumber(level) or 1))
	local gain = GameConfig.StatGainPerLevel or 0.08
	return 1 + gain * (level - 1)
end

--- @param playerLevel number
--- @param rebirthBonuses { damageMultiplier: number?, healthBonus: number? }|nil
function PlayerWorldStats.ComputeForPlayer(playerLevel, rebirthBonuses)
	local lm = PlayerWorldStats.LevelMultiplier(playerLevel)
	local b = rebirthBonuses or { damageMultiplier = 1, healthBonus = 0 }
	local baseAtk = math.max(GameConfig.PlayerMeleeDamage or 6, GameConfig.PlayerRangedDamage or 4)
	local baseDef = GameConfig.PlayerBaseDefense or 9
	local baseHP = (GameConfig.PlayerMaxHealth or 100) + (b.healthBonus or 0)
	local baseWalk = GameConfig.PlayerWalkSpeed or 16
	local baseSprint = GameConfig.PlayerSprintSpeed or 26
	local dmgMult = b.damageMultiplier or 1

	return {
		levelMult = lm,
		attack = math.max(1, math.floor(baseAtk * lm * dmgMult)),
		defense = math.max(0, math.floor(baseDef * lm)),
		maxHealth = math.max(1, math.floor(baseHP * lm)),
		walkSpeed = math.max(1, math.floor(baseWalk * lm)),
		sprintSpeed = math.max(1, math.floor(baseSprint * lm)),
		statGainPerLevel = GameConfig.StatGainPerLevel or 0.08,
	}
end

--- Arena-style mitigation: damage minus one third of defense (floored), min 1.
function PlayerWorldStats.ApplyDefenseFromPlayer(player, rawDamage)
	if type(rawDamage) ~= "number" then
		return 1
	end
	rawDamage = math.floor(rawDamage)
	if not player then
		return math.max(1, rawDamage)
	end
	local def = (player:GetAttribute("WorldStat_Defense") or 0) + (player:GetAttribute("BadlandsStat_Defense") or 0)
	if type(def) ~= "number" or def <= 0 then
		return math.max(1, rawDamage)
	end
	return math.max(1, math.floor(rawDamage - def / 3))
end

return PlayerWorldStats
