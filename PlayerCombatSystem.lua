-- Last updated: 2026-04-23 21:35
-- PlayerCombatSystem.lua - ServerScriptService (ModuleScript)
-- Handles player direct attacks against world creatures.
-- Ranged (auto/manual aim) and Melee (AOE swing).
-- Uses WorldCreatureHP for damage + faint tracking.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PlayerCombatSystem = {}

local PlayerDataManager
local FavoriteCreatureSystem
local WorldCreatureHP -- loaded in Init, NOT at module scope
local CreatureAI       -- loaded in Init, to sync damage with AI state

local WORLD_TAG = "WorldCreature"
local rangedCooldowns = {}
local meleeCooldowns = {}

local function pilotDamageAfterLevelAndBadlands(player, baseDmg, mult)
	local lvlMult = player:GetAttribute("WorldStat_LevelMult")
	if type(lvlMult) ~= "number" or lvlMult <= 0 then
		lvlMult = 1
	end
	local dmg = math.floor(baseDmg * mult * lvlMult)
	local bl = player:GetAttribute("BadlandsStat_Attack")
	if type(bl) == "number" and bl > 0 then
		dmg = dmg + math.floor(bl)
	end
	return math.max(1, dmg)
end

local function findCreatureByUniqueId(targetId)
	if type(targetId) ~= "string" or #targetId == 0 then return nil end
	local targetStr = targetId
	for _, model in ipairs(CollectionService:GetTagged(WORLD_TAG)) do
		if model.Parent then
			local uid = model:GetAttribute("UniqueId") or model:GetAttribute("UID")
			if uid and tostring(uid) == targetStr then
				return model
			end
		end
	end
	return nil
end

-- -- RANGED ATTACK --
local function doRangedAttack(player, origin, direction, targetUniqueId)
	local userId = player.UserId
	local now = tick()
	if rangedCooldowns[userId] and (now - rangedCooldowns[userId]) < GameConfig.PlayerRangedCooldown then return end
	rangedCooldowns[userId] = now

	local baseDmg = GameConfig.PlayerRangedDamage
	local bonuses = PlayerDataManager.GetRebirthBonuses and PlayerDataManager.GetRebirthBonuses(player)
	local mult = (bonuses and bonuses.damageMultiplier) or 1
	if PlayerDataManager.HasBuff and PlayerDataManager.HasBuff(player, "food_powerstew") then
		mult = mult * 1.35
	end
	local char = player.Character
	local hum = char and char:FindFirstChild("Humanoid")
	if hum then
		local cm = hum:GetAttribute("BuffCraftAttackMult")
		if type(cm) == "number" and cm > 0 then
			mult = mult * cm
		end
	end
	local dmg = pilotDamageAfterLevelAndBadlands(player, baseDmg, mult)

	-- If targetUniqueId provided, only damage that creature (target-based combat)
	local bestTarget = nil
	local stealVictimHit = false
	if targetUniqueId then
		local thiefUidMatch = type(targetUniqueId) == "string" and string.match(targetUniqueId, "^pvpthief_(%d+)$")
		if thiefUidMatch and FavoriteCreatureSystem and FavoriteCreatureSystem.HandleStealVictimHit then
			local thief = Players:GetPlayerByUserId(tonumber(thiefUidMatch))
			if thief then
				stealVictimHit = FavoriteCreatureSystem.HandleStealVictimHit(player, thief, origin, false, dmg)
			end
		else
		local targetModel = findCreatureByUniqueId(targetUniqueId)
		if targetModel and targetModel.Parent and not targetModel:GetAttribute("Fainted") then
			local body = targetModel.PrimaryPart or targetModel:FindFirstChild("Body")
			if body then
				local toCreature = body.Position - origin
				local dist = toCreature.Magnitude
				if dist <= GameConfig.PlayerRangedRange then
					bestTarget = targetModel
				end
			end
		end
		end
	else
		-- Legacy fallback auto-aim is disabled by default to avoid unnecessary world scans.
		if GameConfig.EnableLegacyAutoAim == true then
			local bestDist = GameConfig.PlayerRangedRange
			for _, model in ipairs(CollectionService:GetTagged(WORLD_TAG)) do
				if model.Parent and not model:GetAttribute("Fainted") then
					local body = model.PrimaryPart or model:FindFirstChild("Body")
					if body then
						local toCreature = body.Position - origin
						local dot = toCreature.Unit:Dot(direction.Unit)
						if dot > 0.6 then
							local dist = toCreature.Magnitude
							if dist < bestDist and dist <= GameConfig.PlayerRangedRange then
								bestDist = dist
								bestTarget = model
							end
						end
					end
				end
			end
		end
	end

	-- Fire visual
	local events = ReplicatedStorage:FindFirstChild("Events")
	local attackEvent = events and events:FindFirstChild("PlayerAttackFX")
	local endPos = origin + direction.Unit * math.min(GameConfig.PlayerRangedRange, 40)

	if stealVictimHit and type(targetUniqueId) == "string" then
		local tid = string.match(targetUniqueId, "^pvpthief_(%d+)$")
		local thief = tid and Players:GetPlayerByUserId(tonumber(tid))
		local troot = thief and thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
		if troot then
			endPos = troot.Position
		end
	end

	if bestTarget then
		local targetBody = bestTarget.PrimaryPart or bestTarget:FindFirstChild("Body")
		if targetBody then endPos = targetBody.Position end

		-- Deal damage (sync both HP systems); pass player character so creature targets player
		local attacker = player.Character
		if CreatureAI and CreatureAI.DamageCreature then
			CreatureAI.DamageCreature(bestTarget, dmg, attacker)
		elseif WorldCreatureHP then
			WorldCreatureHP.DamageCreature(bestTarget, dmg, attacker)
		end

		-- Award XP on faint
		if bestTarget:GetAttribute("Fainted") and FavoriteCreatureSystem and PlayerDataManager then
			local entry = PlayerDataManager.GetFavorite(player)
			if entry then
				PlayerDataManager.AddXP(player, entry.uid, GameConfig.CaptureXP or 10)
			end
		end
	end

	-- Send FX to all players
	if attackEvent then
		local didHit = bestTarget ~= nil or stealVictimHit
		attackEvent:FireAllClients(player.UserId, origin, endPos, "ranged", didHit)
	end
end

-- -- MELEE ATTACK --
local function doMeleeAttack(player, origin, targetUniqueId)
	local userId = player.UserId
	local now = tick()
	if meleeCooldowns[userId] and (now - meleeCooldowns[userId]) < GameConfig.PlayerMeleeCooldown then return end
	meleeCooldowns[userId] = now

	local baseDmg = GameConfig.PlayerMeleeDamage
	local bonuses = PlayerDataManager.GetRebirthBonuses and PlayerDataManager.GetRebirthBonuses(player)
	local mult = (bonuses and bonuses.damageMultiplier) or 1
	if PlayerDataManager.HasBuff and PlayerDataManager.HasBuff(player, "food_powerstew") then
		mult = mult * 1.35
	end
	local char = player.Character
	local hum = char and char:FindFirstChild("Humanoid")
	if hum then
		local cm = hum:GetAttribute("BuffCraftAttackMult")
		if type(cm) == "number" and cm > 0 then
			mult = mult * cm
		end
	end
	local dmg = pilotDamageAfterLevelAndBadlands(player, baseDmg, mult)
	local radius = GameConfig.PlayerMeleeRadius
	local hitCount = 0

	if targetUniqueId then
		local thiefUidMatch = type(targetUniqueId) == "string" and string.match(targetUniqueId, "^pvpthief_(%d+)$")
		if thiefUidMatch and FavoriteCreatureSystem and FavoriteCreatureSystem.HandleStealVictimHit then
			local thief = Players:GetPlayerByUserId(tonumber(thiefUidMatch))
			if thief and FavoriteCreatureSystem.HandleStealVictimHit(player, thief, origin, true, dmg) then
				hitCount = 1
			end
		else
		local targetModel = findCreatureByUniqueId(targetUniqueId)
		if targetModel and targetModel.Parent and not targetModel:GetAttribute("Fainted") then
			local body = targetModel.PrimaryPart or targetModel:FindFirstChild("Body")
			if body then
				local dist = (origin - body.Position).Magnitude
				if dist <= radius then
					local attacker = player.Character
					if CreatureAI and CreatureAI.DamageCreature then
						CreatureAI.DamageCreature(targetModel, dmg, attacker)
					elseif WorldCreatureHP then
						WorldCreatureHP.DamageCreature(targetModel, dmg, attacker)
					end
					hitCount = 1
					if targetModel:GetAttribute("Fainted") and FavoriteCreatureSystem and PlayerDataManager then
						local entry = PlayerDataManager.GetFavorite(player)
						if entry then
							PlayerDataManager.AddXP(player, entry.uid, GameConfig.CaptureXP or 10)
						end
					end
				end
			end
		end
		end
	else
	for _, model in ipairs(CollectionService:GetTagged(WORLD_TAG)) do
		if model.Parent and not model:GetAttribute("Fainted") then
			local body = model.PrimaryPart or model:FindFirstChild("Body")
			if body then
				local dist = (origin - body.Position).Magnitude
				if dist <= radius then
					local attacker = player.Character
					if CreatureAI and CreatureAI.DamageCreature then
						CreatureAI.DamageCreature(model, dmg, attacker)
					elseif WorldCreatureHP then
						WorldCreatureHP.DamageCreature(model, dmg, attacker)
					end
					hitCount = hitCount + 1

					if model:GetAttribute("Fainted") and FavoriteCreatureSystem and PlayerDataManager then
						local entry = PlayerDataManager.GetFavorite(player)
						if entry then
							PlayerDataManager.AddXP(player, entry.uid, GameConfig.CaptureXP or 10)
						end
					end
				end
			end
		end
	end
	end

	local events = ReplicatedStorage:FindFirstChild("Events")
	local attackEvent = events and events:FindFirstChild("PlayerAttackFX")
	if attackEvent then
		attackEvent:FireAllClients(player.UserId, origin, nil, "melee", hitCount > 0)
	end

	return hitCount
end

-- -- INIT --
function PlayerCombatSystem.Init(pdm, cai, favSys)
	PlayerDataManager = pdm
	CreatureAI = cai
	FavoriteCreatureSystem = favSys

	-- Load WorldCreatureHP as fallback
	pcall(function() WorldCreatureHP = require(ServerScriptService.WorldCreatureHP) end)

	if CreatureAI then

	elseif WorldCreatureHP then

	else
		warn("[PlayerCombatSystem] No damage system loaded! Player attacks won't damage creatures.")
	end

	local events = ReplicatedStorage:WaitForChild("Events", 30)
	if not events then warn("[PlayerCombatSystem] Events folder not found!"); return end
	local playerAttack = events:WaitForChild("PlayerAttack", 30)

	if playerAttack then
		playerAttack.OnServerEvent:Connect(function(player, attackType, origin, direction, targetUniqueId)
			if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then return end
			local root = player.Character.HumanoidRootPart

			-- Sanity: origin must be near player
			if typeof(origin) ~= "Vector3" or (origin - root.Position).Magnitude > 20 then
				origin = root.Position + Vector3.new(0, 2, 0)
			end

			if attackType == "melee" then
				doMeleeAttack(player, origin, targetUniqueId)
			else
				if typeof(direction) ~= "Vector3" then return end
				doRangedAttack(player, origin, direction, targetUniqueId)
			end
		end)

	else
		warn("[PlayerCombatSystem] PlayerAttack event not found!")
	end

	Players.PlayerRemoving:Connect(function(p)
		rangedCooldowns[p.UserId] = nil
		meleeCooldowns[p.UserId] = nil
	end)

end

return PlayerCombatSystem
