-- RaidSystem.lua - ServerScriptService (ModuleScript)
-- Player-vs-player base raiding. Only raids ONLINE players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PlayerDataManager

local RaidSystem = {}

local raidCooldowns = {}
local raidProtection = {}
local activeRaids = {}  -- [raiderUserId] = victimUserId

-- Returns true if raiderUserId is currently raiding victimUserId's base (for defense turret targeting).
function RaidSystem.IsPlayerRaidingVictim(raiderUserId, victimUserId)
	return activeRaids[raiderUserId] == victimUserId
end

local function canRaid(raider, victim)
	if raider.UserId == victim.UserId then return false, "Can't raid yourself" end
	if not Players:FindFirstChild(victim.Name) then return false, "Player offline" end

	local last = raidCooldowns[raider.UserId]
	if last and (tick() - last) < GameConfig.RaidCooldown then
		return false, "Cooldown (" .. math.ceil(GameConfig.RaidCooldown - (tick() - last)) .. "s)"
	end

	local prot = raidProtection[victim.UserId]
	if prot and (tick() - prot) < GameConfig.RaidProtectionTime then
		return false, "Protected"
	end

	if activeRaids[raider.UserId] then return false, "Already raiding" end
	return true, ""
end

local function calculateStealChance(victim)
	local data = PlayerDataManager.GetData(victim)
	if not data then return 0 end
	local defenseCount = 0
	for _, uid in ipairs(data.defenseSlots or {}) do
		if not uid or uid == "" then continue end
		if not PlayerDataManager.GetEggByUid(victim, uid) then defenseCount = defenseCount + 1 end
	end
	local reduction = defenseCount * GameConfig.DefensePerCreature
	return math.max(0.1, GameConfig.StealChanceBase - reduction)
end

local function tryStealOne(raider, victim)
	if math.random() > calculateStealChance(victim) then return false, nil end

	local stealable = PlayerDataManager.GetStealableCreatures(victim)
	if #stealable == 0 then return false, nil end

	local target = stealable[math.random(#stealable)]
	if PlayerDataManager.TransferCreature(victim, raider, target.uid, { source = "raid" }) then
		local info = CreatureData.GetById(target.id)
		local named = (type(target.nickname) == "string" and target.nickname ~= "") and target.nickname or nil
		if named and info and info.displayName then
			return true, named .. " (" .. info.displayName .. ")"
		end
		return true, named or (info and info.displayName or target.id)
	end
	return false, nil
end

function RaidSystem.StartRaid(raider, victim)
	local ok, reason = canRaid(raider, victim)
	if not ok then return false, reason end

	activeRaids[raider.UserId] = victim.UserId

	local events = ReplicatedStorage:FindFirstChild("Events")
	local raidStartEv = events and events:FindFirstChild("RaidStart")
	if raidStartEv then
		raidStartEv:FireClient(raider, victim.Name, GameConfig.RaidDuration)
		raidStartEv:FireClient(victim, raider.Name, GameConfig.RaidDuration)
	end

	task.spawn(function()
		local stolen = {}
		local interval = GameConfig.RaidDuration / (GameConfig.MaxStealPerRaid + 1)

		for i = 1, GameConfig.MaxStealPerRaid do
			task.wait(interval)
			if not Players:FindFirstChild(raider.Name) or not Players:FindFirstChild(victim.Name) then break end

			local stole, name = tryStealOne(raider, victim)
			if stole and name then
				table.insert(stolen, name)
				local stealEv = events and events:FindFirstChild("CreatureStolen")
				if stealEv then
					stealEv:FireClient(raider, name, true)
					stealEv:FireClient(victim, name, false)
				end
			end
		end

		activeRaids[raider.UserId] = nil
		raidCooldowns[raider.UserId] = tick()
		raidProtection[victim.UserId] = tick()

		local endEv = events and events:FindFirstChild("RaidEnd")
		if endEv then
			endEv:FireClient(raider, #stolen, stolen)
			endEv:FireClient(victim, #stolen, stolen)
		end
		if #stolen == 0 and PlayerDataManager.NotifyAchievement then
			PlayerDataManager.NotifyAchievement("OnDefenseSuccess", victim, "player_raid")
		end

		local data = PlayerDataManager.GetData(raider)
		if data then data.stats.totalRaids = data.stats.totalRaids + 1 end

		-- Award player XP for successful raid
		if #stolen > 0 and PlayerDataManager.AddPlayerXP then
			local pLvl, pDidLvl = PlayerDataManager.AddPlayerXP(raider, GameConfig.PlayerXP_RaidWin or 30)
			if pDidLvl then
				local events = game.ReplicatedStorage:FindFirstChild("Events")
				local lvlEvt = events and events:FindFirstChild("PlayerLevelUp")
				if lvlEvt then lvlEvt:FireClient(raider, pLvl) end
			end
		end

		print("[RaidSystem] " .. raider.Name .. " raided " .. victim.Name .. " � stole " .. #stolen)
	end)

	return true, "Started"
end

function RaidSystem.GetRaidableTargets(raider)
	local targets = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId ~= raider.UserId then
			local ok, reason = canRaid(raider, p)
			local data = PlayerDataManager.GetData(p)
			table.insert(targets, {
				name = p.Name,
				canRaid = ok,
				reason = reason,
				creatureCount = data and #data.inventory or 0,
			})
		end
	end
	return targets
end

function RaidSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr

	-- DO NOT create events � MainServer already created them
	-- Just find and connect
	local events = ReplicatedStorage:WaitForChild("Events", 10)
	local raidRequest = events:FindFirstChild("RaidRequest")
	local getRaidTargets = events:FindFirstChild("GetRaidTargets")

	if raidRequest then
		raidRequest.OnServerEvent:Connect(function(raider, victimName)
			local victim = Players:FindFirstChild(victimName)
			if victim then RaidSystem.StartRaid(raider, victim) end
		end)
	end

	if getRaidTargets then
		getRaidTargets.OnServerInvoke = function(player)
			return RaidSystem.GetRaidableTargets(player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		activeRaids[player.UserId] = nil
		raidCooldowns[player.UserId] = nil
		raidProtection[player.UserId] = nil
		for raiderId, victimId in pairs(activeRaids) do
			if victimId == player.UserId then activeRaids[raiderId] = nil end
		end
	end)

	print("[RaidSystem] Initialized")
end

return RaidSystem
