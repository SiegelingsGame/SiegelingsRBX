-- MainServer.lua - ServerScriptService (Script)
-- THE SINGLE ENTRY POINT. All remote handlers live HERE.
-- DELETE "EssentialdHandlers" and "BattleTeamSystem" if they exist....

print("--------------------------------------")
print("   MONSTER SIEGE - Server Starting")
print("--------------------------------------")
-- #region agent logsdds
print("[DEBUG-1234af] MainServer: before requires")
-- #endregion

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

-- Prevent PlayerGud from being cleared odfn death/respawn so Leadesrboard (X), Profile (P),f and HUD button bar shortcuts keep working
StarterGui.ResetPlayerGuiOnSpawn = false

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
-- #region agent log
print("[DEBUG-1234af] MainServer: CreatureData required OK")
-- #endregion
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
-- #region agent log
print("[DEBUG-1234af] MainServer: GameConfig required OK")
-- #endregion

-- === STEP 1: Create ALL remotes ===
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end
-- #region agent log
print("[DEBUG-1234af] MainServer: Events folder created")
-- #endregion

local function makeEvent(n)
	local existing = eventsFolder:FindFirstChild(n)
	if existing then return existing end
	local e = Instance.new("RemoteEvent"); e.Name = n; e.Parent = eventsFolder; return e
end
local function makeFunc(n)
	local existing = eventsFolder:FindFirstChild(n)
	if existing then return existing end
	local f = Instance.new("RemoteFunction"); f.Name = n; f.Parent = eventsFolder; return f
end

-- Inventory
local getInventory = makeFunc("GetInventory")
local setCreatureNickname = makeFunc("SetCreatureNickname")
local assignToBase = makeEvent("AssignToBase")
local assignToDefense = makeEvent("AssignToDefense")
local slotAssignComplete = makeEvent("SlotAssignComplete")  -- server -> client: fire after assign/remove so UI can refresh immediately
local setFavorite = makeEvent("SetFavorite")
local assignToBattle = makeEvent("AssignToBattle")
local removeFromBattle = makeEvent("RemoveFromBattle")
local toggleBattleTeam = makeFunc("ToggleBattleTeam")
local getBattleTeam = makeFunc("GetBattleTeam")

-- Companion
makeEvent("CompanionSpawned")  -- server -> client: favorite companion model (for grow-from-beneath animation)
makeEvent("CompanionFainted")  -- server -> client: creaturePos, creatureId (card flies to player; triggers respawn cooldown)
makeEvent("CompanionRecalled")  -- server -> client: creaturePos, creatureId (water recall; same card effect, NO cooldown)
local toggleAttackMode = makeEvent("ToggleAttackMode")
local setCompanionTarget = makeEvent("SetCompanionTarget")
local clearCompanionTarget = makeEvent("ClearCompanionTarget")
-- FIX #17: Recall/Summon companion without changing favorite.
-- RecallCompanion: despawn companion model, fire CompanionRecalled, keep favoriteUid intact.
-- SummonCompanion: spawn companion model back (requires favoriteUid already set).
local recallCompanion = makeEvent("RecallCompanion")
local summonCompanion = makeEvent("SummonCompanion")

-- Mounting
makeEvent("MountRequest")      -- client -> server: mount favorite creature
makeEvent("DismountRequest")   -- client -> server: dismount
makeEvent("MountStarted")      -- server -> client: creatureId, mountType, speed, bonuses
makeEvent("MountEnded")        -- server -> client: dismount notification
makeEvent("MountFlyInput")     -- client -> server: targetY (flying mount vertical control)

-- Economy
local incomeReceived = makeEvent("IncomeReceived")
makeEvent("CoinsUpdate")
makeEvent("GemsUpdate")

-- Capture
makeEvent("CaptureRequest"); makeEvent("CaptureStart"); makeEvent("CaptureSuccess")
makeEvent("SigilEarned")  -- FireClient(player, zoneId) when player earns a sigil from defeating a boss
makeEvent("CaptureCancel"); makeEvent("CaptureFail"); makeEvent("CaptureOutOfRange"); makeEvent("AssignCaptured")

-- AI Raids
makeEvent("AIRaidStart"); makeEvent("AIRaidEnd"); makeEvent("AIRaidAlert"); makeEvent("CreatureFreedByRaid")

-- Dungeons
makeEvent("DungeonSpawned"); makeEvent("DungeonDespawned")

-- Raid
makeEvent("RaidRequest"); makeEvent("RaidStart"); makeEvent("RaidEnd")
makeEvent("CreatureStolen"); makeFunc("GetRaidTargets")

-- Arena
makeEvent("ArenaAnnounce"); makeEvent("BattleStart"); makeEvent("BattleEnd")
makeEvent("BattleKill"); makeEvent("BattleTeamsPlaced"); makeFunc("GetBattleInfo")
makeEvent("BaseGymReject")
makeEvent("BaseGymResult")  -- server -> client: gym battle completion screen (bounty, rewards, winner/loser)
makeEvent("BaseGymStart")   -- server -> client: gym battle start banner (owner, challenger names)

-- Badlands (roguelike PvPvE mode)
makeEvent("BadlandsQueueJoin"); makeEvent("BadlandsQueueLeave"); makeEvent("BadlandsQueueUpdate")
makeEvent("BadlandsQueueReject"); makeEvent("BadlandsRunStart"); makeEvent("BadlandsRunEnd")
makeEvent("BadlandsEliminated"); makeEvent("BadlandsExtracted"); makeEvent("BadlandsBagUpdate")
makeEvent("BadlandsBagSwitch"); makeEvent("BadlandsBagReplace"); makeEvent("BadlandsTimerSync")
makeEvent("BadlandsLevelUp"); makeEvent("BadlandsExtractStart"); makeEvent("BadlandsExtractCancel")
makeEvent("BadlandsExtractProgress"); makeEvent("BadlandsExtractActivate")
makeEvent("BadlandsZoneCollapse"); makeEvent("BadlandsPlayerKill"); makeEvent("BadlandsSupplyDrop")
makeEvent("BadlandsXPGain"); makeEvent("BadlandsContractData"); makeEvent("BadlandsOfferCreature")
makeEvent("BadlandsLootBagSpawned"); makeEvent("BadlandsLootBagLoot"); makeEvent("BadlandsLootBagUpdate")
makeEvent("BadlandsSacrificeCreature"); makeEvent("BadlandsSacrificeResult")

-- Shared notifications
makeEvent("ShowNotification")

-- Creature animations (server -> clients for multiplayer replication)
makeEvent("PlayCreatureAnimation")

-- Loading: server fires when creatures/models are ready; client LoadingGate waits for this
makeEvent("LoadingReady")
makeEvent("LoadingCriticalReady")

-- PvP (player vs player 1v1; challenge then confirm like trade)
makeEvent("RequestPvPBattle"); makeEvent("PvPBattleStart"); makeEvent("PvPBattleEnd"); makeEvent("PvPBattleReject")
makeEvent("PvPChallengeNotice"); makeEvent("PvPRevivePrompt"); makeEvent("PvPReviveSuccess"); makeEvent("PvPReviveWith")
makeEvent("PvPChallengeInvite"); makeEvent("PvPAcceptChallenge"); makeEvent("PvPDeclineChallenge")

-- Player Combat
makeEvent("PlayerAttack"); makeEvent("PlayerAttackFX")
makeEvent("ShowDamageNumber")  -- S->C: (position, damage) only to attacker/companion owner for open-world

-- FIX #27: Underwater drowning (client fires when breath runs out)
local drownDamage = makeEvent("DrownDamage")

-- Buff Shop
makeFunc("BuyBuff")

-- Cosmetic Shop
makeFunc("BuyCosmetic"); makeFunc("EquipCosmetic")
-- Base Exterior Shop (purchase/equip theme; equip rebuilds plot with theme generator)
local buyExterior = makeFunc("BuyExterior")
local equipExterior = makeFunc("EquipExterior")
-- Base Color Shop (walls, stairs, points, combiner, recycler)
local buyBaseColor = makeFunc("BuyBaseColor")
local equipBaseColor = makeFunc("EquipBaseColor")

-- Egg Shop
makeFunc("BuyEgg"); makeEvent("EggResult")
local inspectEgg = makeFunc("InspectEgg")

-- Friends List / Laser Door
makeEvent("AddBaseFriend"); makeEvent("RemoveBaseFriend"); makeFunc("GetFriendsList")

-- Trading (Friends menu)
makeEvent("TradeRequest")      -- client -> server (targetUserId)
makeEvent("TradeInvite")       -- server -> client (payload {tradeId, fromUserId, fromName})
makeEvent("TradeResponse")     -- client -> server (tradeId, acceptBool)
makeEvent("TradeUpdateOffer")  -- client -> server (tradeId, offeredUids[])
makeEvent("TradeAccept")       -- client -> server (tradeId)
makeEvent("TradeCancel")       -- client -> server (tradeId)
makeEvent("TradeState")        -- server -> client (full state)
makeFunc("GetPublicProfile")   -- client -> server (targetUserId) -> {name, favorite...}

-- Leaderboard
makeFunc("GetLeaderboardData")

-- Evolution & Combine (monster evolution + 3→1 variant combine)
makeEvent("EvolveCreature")   -- client sends uid
makeEvent("EvolveResult")    -- server → client (success, newCreatureId or errorMessage)
makeEvent("CombineCreatures") -- client sends {uid1, uid2, uid3}
makeEvent("CombineResult")   -- server → client (success, newUid or errorMessage)
makeEvent("OpenCombiner")    -- server → client (open combine UI at MCombiner)
makeEvent("OpenRecycler")    -- server → client (open recycler UI at MRecycler)
makeEvent("RecycleDuplicates") -- client sends {uid1, uid2, ...} (same creature, min 3)
makeEvent("RecycleResult")   -- server → client (success, newUid or errorMessage)

-- Base Building / Player Level
local sellCreature = makeFunc("SellCreature")
local buyFloor = makeFunc("BuyFloor")
local goHome = makeEvent("GoHome")
makeEvent("HomeRecallStart")  -- server → client: channelTime (show timer)
makeEvent("HomeRecallEnd")    -- server → client: success (hide timer)
makeEvent("HomeRecallCancel") -- server → client: interrupted (hide timer)
local getProfile = makeFunc("GetProfile")
makeEvent("PlayerLevelUp")    -- server → client: level up notification
makeEvent("PlayerXPGained")   -- server → client: XP gain notification

-- Knight Base Rental (FIX #35)
makeEvent("KnightBaseRented")    -- server → client: biomeName, duration
makeEvent("KnightBaseReturned")  -- server → client: rental ended, base returned home
makeEvent("KnightBaseTimer")     -- server → client: remainingSeconds (every second)
makeEvent("KnightBaseWarning")   -- server → client: remainingSeconds (30s/10s warning) or "shield_blocked"

-- Achievements
makeFunc("GetAchievements")
makeEvent("AchievementProgress") -- server -> client: (entry, reason)
makeEvent("AchievementUnlocked") -- server -> client: (def summary)

-- Base Interaction (walk-up creature management: pick up, move, swap)
local moveCreatureSlot = makeFunc("MoveCreatureSlot")    -- client sends: slotType, uid, targetPointIndex → ok, message
local swapCreatureSlots = makeFunc("SwapCreatureSlots")  -- client sends: slotType, uidA, uidB → ok, message

-- Base Exterior (UI agent: bounds from Floor3, decoration zone, build instructions)
makeFunc("GetExteriorBounds")     -- invoke → returns bounds for player's plot
makeFunc("GetBuildInstructions") -- invoke(themeName) → returns Instructions module table
makeEvent("RefreshExterior")      -- fire → server refreshes exterior/decoration zone for player

-- Launch screen
local selectStarter = makeEvent("SelectStarter")
local selectPlot = makeFunc("SelectPlot")

-- Pilot Rebirth
local getRebirthInfo = makeFunc("GetRebirthInfo")
local requestRebirth = makeEvent("RequestRebirth")
makeEvent("RebirthSuccess")   -- server -> client: newRebirthLevel, bonuses
makeEvent("RebirthFailed")   -- server -> client: errorMessage

print("[MainServer] All RemoteEvents created")

-- === STEP 2: Require modules ===
local PlayerDataManager = require(ServerScriptService.PlayerDataManager)

local AchievementsSystem = nil
pcall(function() AchievementsSystem = require(ServerScriptService.AchievementsSystem) end)
if AchievementsSystem and AchievementsSystem.BindPlayerDataManager then
	AchievementsSystem.BindPlayerDataManager(PlayerDataManager)
end
if PlayerDataManager and PlayerDataManager.BindAchievementObserver then
	PlayerDataManager.BindAchievementObserver(AchievementsSystem)
end

local CreatureAI = nil
pcall(function() CreatureAI = require(ServerScriptService.CreatureAI) end)

local CreatureSpawner = nil
do
	local ok, err = pcall(function() CreatureSpawner = require(ServerScriptService.CreatureSpawner) end)
	if not ok then
		warn("[MainServer] CreatureSpawner require FAILED:", tostring(err))
	elseif CreatureSpawner then
		print("[MainServer] CreatureSpawner loaded OK")
	else
		warn("[MainServer] CreatureSpawner require returned nil")
	end
end

local CaptureSystem = nil
pcall(function() CaptureSystem = require(ServerScriptService.CaptureSystem) end)

local RaidSystem = nil
pcall(function() RaidSystem = require(ServerScriptService.RaidSystem) end)

local TradeSystem = nil
pcall(function() TradeSystem = require(ServerScriptService.TradeSystem) end)

local BasePlacementSystem = nil
pcall(function() BasePlacementSystem = require(ServerScriptService.BasePlacementSystem) end)

local FavoriteCreatureSystem = nil
pcall(function() FavoriteCreatureSystem = require(ServerScriptService.FavoriteCreatureSystem) end)

local ArenaSystem = nil
pcall(function() ArenaSystem = require(ServerScriptService.ArenaSystem) end)

local ArenaShieldSystem = nil
pcall(function() ArenaShieldSystem = require(ServerScriptService.ArenaShieldSystem) end)

local WaterGymSystem = nil
pcall(function() WaterGymSystem = require(ServerScriptService.WaterGymSystem) end)
local CaveGymSystem = nil
pcall(function() CaveGymSystem = require(ServerScriptService.CaveGymSystem) end)
local DesertGymSystem = nil
pcall(function() DesertGymSystem = require(ServerScriptService.DesertGymSystem) end)
local ElectricGymSystem = nil
pcall(function() ElectricGymSystem = require(ServerScriptService.ElectricGymSystem) end)

local PvPBattleSystem = nil
pcall(function() PvPBattleSystem = require(ServerScriptService.PvPBattleSystem) end)

local BaseIncomeSystem = nil
pcall(function() BaseIncomeSystem = require(ServerScriptService.BaseIncomeSystem) end)

local AIRaidSystem = nil
pcall(function() AIRaidSystem = require(ServerScriptService.AIRaidSystem) end)

local DungeonSpawner = nil
pcall(function() DungeonSpawner = require(ServerScriptService.DungeonSpawner) end)
local ElectricBiomeHazardSystem = nil
do
	local ok, mod = pcall(function() return require(ServerScriptService.ElectricBiomeHazardSystem) end)
	if ok and mod then ElectricBiomeHazardSystem = mod
	else warn("[MainServer] ElectricBiomeHazardSystem require failed: " .. tostring(mod)) end
end

local PlayerCombatSystem = nil
pcall(function() PlayerCombatSystem = require(ServerScriptService.PlayerCombatSystem) end)

local PlayerHealthSystem = nil
pcall(function() PlayerHealthSystem = require(ServerScriptService.PlayerHealthSystem) end)

local BuffShopSystem = nil
pcall(function() BuffShopSystem = require(ServerScriptService.BuffShopSystem) end)

local CosmeticSystem = nil
pcall(function() CosmeticSystem = require(ServerScriptService.CosmeticSystem) end)

local EggShopSystem = nil
pcall(function() EggShopSystem = require(ServerScriptService.EggShopSystem) end)

local WorldCreatureHP = nil
pcall(function() WorldCreatureHP = require(ServerScriptService.WorldCreatureHP) end)

local LaserDoorSystem = nil
pcall(function() LaserDoorSystem = require(ServerScriptService.LaserDoorSystem) end)
local ZoneDoorSystem = nil
pcall(function() ZoneDoorSystem = require(ServerScriptService.ZoneDoorSystem) end)

local LeaderboardSystem = nil
pcall(function() LeaderboardSystem = require(ServerScriptService.LeaderboardSystem) end)

local EvolutionCombineSystem = nil
pcall(function() EvolutionCombineSystem = require(ServerScriptService.EvolutionCombineSystem) end)

local CombinerRecyclerSystem = nil
pcall(function() CombinerRecyclerSystem = require(ServerScriptService.CombinerRecyclerSystem) end)

local KnightBaseSystem = nil
do
	local ok, result = pcall(function() return require(ServerScriptService.KnightBaseSystem) end)
	if ok then
		KnightBaseSystem = result
		print("[MainServer] KnightBaseSystem require OK")
	else
		warn("[MainServer] KnightBaseSystem require FAILED: " .. tostring(result))
	end
end

local GymBattleSystem = nil
do
	local ok, result = pcall(function() return require(ServerScriptService.GymBattleSystem) end)
	if ok then
		GymBattleSystem = result
		print("[MainServer] GymBattleSystem require OK")
	else
		warn("[MainServer] GymBattleSystem require FAILED: " .. tostring(result))
	end
end

local BadlandsSystem = nil
do
	local ok, result = pcall(function() return require(ServerScriptService.BadlandsSystem) end)
	if ok then
		BadlandsSystem = result
		print("[MainServer] BadlandsSystem require OK")
	else
		warn("[MainServer] BadlandsSystem require FAILED: " .. tostring(result))
	end
end

local DecorSystem = nil
do
	local ok, result = pcall(function() return require(ServerScriptService.DecorSystem) end)
	if ok then
		DecorSystem = result
		print("[MainServer] DecorSystem require OK")
	else
		warn("[MainServer] DecorSystem require FAILED: " .. tostring(result))
	end
end

local MountSystem = nil
do
	local ok, result = pcall(function() return require(ServerScriptService.MountSystem) end)
	if ok then
		MountSystem = result
		print("[MainServer] MountSystem require OK")
	else
		warn("[MainServer] MountSystem require FAILED: " .. tostring(result))
	end
end

-- === STEP 3: Initialize ===
PlayerDataManager.Init()
if CreatureAI then
	local ok, err = pcall(function() CreatureAI.Init(LaserDoorSystem) end)
	if ok then print("[MainServer] CreatureAI OK") else warn("[MainServer] CreatureAI Init failed: " .. tostring(err)) end
end
if CreatureSpawner then
	local ok, err = pcall(function() CreatureSpawner.Init(CreatureAI) end)
	if ok then print("[MainServer] CreatureSpawner OK") else warn("[MainServer] CreatureSpawner Init FAILED: " .. tostring(err)) end
else
	warn("[MainServer] CreatureSpawner not loaded!")
end
if CaptureSystem then
	local ok, err = pcall(function() CaptureSystem.Init(PlayerDataManager, CreatureSpawner, CreatureAI, BasePlacementSystem) end)
	if ok then print("[MainServer] CaptureSystem OK") else warn("[MainServer] CaptureSystem Init failed: " .. tostring(err)) end
end
if RaidSystem then
	local ok, err = pcall(function() RaidSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] RaidSystem OK") else warn("[MainServer] RaidSystem Init failed: " .. tostring(err)) end
end

-- Trading
if TradeSystem then
	local rem = {
		TradeRequest = eventsFolder:FindFirstChild("TradeRequest"),
		TradeInvite = eventsFolder:FindFirstChild("TradeInvite"),
		TradeResponse = eventsFolder:FindFirstChild("TradeResponse"),
		TradeUpdateOffer = eventsFolder:FindFirstChild("TradeUpdateOffer"),
		TradeAccept = eventsFolder:FindFirstChild("TradeAccept"),
		TradeCancel = eventsFolder:FindFirstChild("TradeCancel"),
		TradeState = eventsFolder:FindFirstChild("TradeState"),
	}
	pcall(function() TradeSystem.Init(PlayerDataManager, rem) end)
	local getPublicProfile = eventsFolder:FindFirstChild("GetPublicProfile")
	if getPublicProfile and getPublicProfile:IsA("RemoteFunction") then
		getPublicProfile.OnServerInvoke = function(plr, targetUserId)
			return TradeSystem.GetPublicProfile(plr, targetUserId)
		end
	end
end

if BasePlacementSystem then
	local ok, err = pcall(function() BasePlacementSystem.Init(PlayerDataManager, CreatureAI) end)
	if ok then print("[MainServer] BasePlacementSystem OK") else warn("[MainServer] BasePlacementSystem failed: " .. tostring(err)) end
end
if FavoriteCreatureSystem then
	local ok, err = pcall(function() FavoriteCreatureSystem.Init(PlayerDataManager, CreatureSpawner, CreatureAI) end)
	if ok then print("[MainServer] FavoriteCreatureSystem OK") else warn("[MainServer] FavoriteCreatureSystem failed: " .. tostring(err)) end
end

-- Mount system: depends on PlayerDataManager + FavoriteCreatureSystem
if MountSystem then
	local ok, err = pcall(function() MountSystem.Init(PlayerDataManager, FavoriteCreatureSystem, CreatureAI) end)
	if ok then print("[MainServer] MountSystem OK") else warn("[MainServer] MountSystem failed: " .. tostring(err)) end
end

-- Wire CreatureAI <-> FavoriteCreatureSystem so AI creatures can damage companions
if CreatureAI and FavoriteCreatureSystem then
	pcall(function()
		CreatureAI.SetFavoriteSystem(FavoriteCreatureSystem)
		print("[MainServer] CreatureAI <-> FavoriteCreatureSystem linked")
	end)
end
if ArenaSystem then
	local ok, err = pcall(function() ArenaSystem.Init(PlayerDataManager, BasePlacementSystem) end)
	if ok then print("[MainServer] ArenaSystem OK") else warn("[MainServer] ArenaSystem failed: " .. tostring(err)) end
end
if ArenaShieldSystem then
	local ok, err = pcall(function() ArenaShieldSystem.Init() end)
	if ok then print("[MainServer] ArenaShieldSystem OK") else warn("[MainServer] ArenaShieldSystem failed: " .. tostring(err)) end
end
if WaterGymSystem then
	local ok, err = pcall(function() WaterGymSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] WaterGymSystem OK") else warn("[MainServer] WaterGymSystem failed: " .. tostring(err)) end
end
if CaveGymSystem then
	local ok, err = pcall(function() CaveGymSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] CaveGymSystem OK") else warn("[MainServer] CaveGymSystem failed: " .. tostring(err)) end
end
if DesertGymSystem then
	local ok, err = pcall(function() DesertGymSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] DesertGymSystem OK") else warn("[MainServer] DesertGymSystem failed: " .. tostring(err)) end
end
if ElectricGymSystem then
	local ok, err = pcall(function() ElectricGymSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] ElectricGymSystem OK") else warn("[MainServer] ElectricGymSystem failed: " .. tostring(err)) end
end
if LeaderboardSystem then
	local ok, err = pcall(function() LeaderboardSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] LeaderboardSystem OK") else warn("[MainServer] LeaderboardSystem failed: " .. tostring(err)) end
end
if PvPBattleSystem then
	local ok, err = pcall(function() PvPBattleSystem.Init(PlayerDataManager, FavoriteCreatureSystem, LeaderboardSystem) end)
	if ok then print("[MainServer] PvPBattleSystem OK") else warn("[MainServer] PvPBattleSystem failed: " .. tostring(err)) end
end
if AIRaidSystem then
	local ok, err = pcall(function() AIRaidSystem.Init(PlayerDataManager, BasePlacementSystem, CreatureSpawner, CreatureAI) end)
	if ok then print("[MainServer] AIRaidSystem OK") else warn("[MainServer] AIRaidSystem failed: " .. tostring(err)) end
end
if DungeonSpawner then
	local ok, err = pcall(function() DungeonSpawner.Init(CreatureSpawner) end)
	if ok then print("[MainServer] DungeonSpawner OK") else warn("[MainServer] DungeonSpawner failed: " .. tostring(err)) end
end
if ElectricBiomeHazardSystem then
	local ok, err = pcall(function() ElectricBiomeHazardSystem.Init() end)
	if ok then print("[MainServer] ElectricBiomeHazardSystem OK") else warn("[MainServer] ElectricBiomeHazardSystem failed: " .. tostring(err)) end
end
if WorldCreatureHP then
	local ok, err = pcall(function() WorldCreatureHP.Init() end)
	if ok then print("[MainServer] WorldCreatureHP OK") else warn("[MainServer] WorldCreatureHP failed: " .. tostring(err)) end
end
if PlayerCombatSystem then
	local ok, err = pcall(function() PlayerCombatSystem.Init(PlayerDataManager, CreatureAI, FavoriteCreatureSystem) end)
	if ok then print("[MainServer] PlayerCombatSystem OK") else warn("[MainServer] PlayerCombatSystem failed: " .. tostring(err)) end
end
if PlayerHealthSystem then
	local ok, err = pcall(function() PlayerHealthSystem.Init() end)
	if ok then print("[MainServer] PlayerHealthSystem OK") else warn("[MainServer] PlayerHealthSystem failed: " .. tostring(err)) end
end
if BuffShopSystem then
	local ok, err = pcall(function() BuffShopSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] BuffShopSystem OK") else warn("[MainServer] BuffShopSystem failed: " .. tostring(err)) end
end
if CosmeticSystem then
	local ok, err = pcall(function() CosmeticSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] CosmeticSystem OK") else warn("[MainServer] CosmeticSystem failed: " .. tostring(err)) end
end
if EggShopSystem then
	local ok, err = pcall(function() EggShopSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] EggShopSystem OK") else warn("[MainServer] EggShopSystem failed: " .. tostring(err)) end
end
if LaserDoorSystem then
	local ok, err = pcall(function() LaserDoorSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] LaserDoorSystem OK") else warn("[MainServer] LaserDoorSystem failed: " .. tostring(err)) end
	if ZoneDoorSystem and ZoneDoorSystem.Init then
		local okZD, errZD = pcall(function() ZoneDoorSystem.Init(PlayerDataManager) end)
		if okZD then print("[MainServer] ZoneDoorSystem OK") else warn("[MainServer] ZoneDoorSystem failed: " .. tostring(errZD)) end
	end
end
if KnightBaseSystem then
	local ok, err = pcall(function() KnightBaseSystem.Init(PlayerDataManager, BasePlacementSystem, LaserDoorSystem) end)
	if ok then print("[MainServer] KnightBaseSystem OK") else warn("[MainServer] KnightBaseSystem failed: " .. tostring(err)) end
end
if GymBattleSystem then
	local ok, err = pcall(function() GymBattleSystem.Init(PlayerDataManager, BasePlacementSystem) end)
	if ok then print("[MainServer] GymBattleSystem OK") else warn("[MainServer] GymBattleSystem failed: " .. tostring(err)) end
end

-- Cross-link: ArenaSystem ↔ GymBattleSystem for mutual exclusion
-- Arena delays rounds when a gym battle is active; gym blocks when arena is active.
if ArenaSystem and GymBattleSystem then
	pcall(function() ArenaSystem.SetGymBattleSystem(GymBattleSystem) end)
end
-- Badlands: roguelike PvPvE mode (depends on PDM, FCS, MountSystem, CreatureAI)
if BadlandsSystem then
	local ok, err = pcall(function()
		BadlandsSystem.Init(PlayerDataManager, FavoriteCreatureSystem, MountSystem, CreatureAI)
	end)
	if ok then print("[MainServer] BadlandsSystem OK") else warn("[MainServer] BadlandsSystem failed: " .. tostring(err)) end
end
if DecorSystem then
	local ok, err = pcall(function() DecorSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] DecorSystem OK") else warn("[MainServer] DecorSystem failed: " .. tostring(err)) end
end
if EvolutionCombineSystem then
	local ok, err = pcall(function() EvolutionCombineSystem.Init(PlayerDataManager, FavoriteCreatureSystem) end)
	if ok then print("[MainServer] EvolutionCombineSystem OK") else warn("[MainServer] EvolutionCombineSystem failed: " .. tostring(err)) end
end
if CombinerRecyclerSystem then
	local ok, err = pcall(function() CombinerRecyclerSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] CombinerRecyclerSystem OK") else warn("[MainServer] CombinerRecyclerSystem failed: " .. tostring(err)) end
end
local BaseExteriorSystem = nil
pcall(function() BaseExteriorSystem = require(ServerScriptService.BaseExteriorSystem) end)
if BaseExteriorSystem then
	local ok, err = pcall(function() BaseExteriorSystem.Init(PlayerDataManager) end)
	if ok then print("[MainServer] BaseExteriorSystem OK") else warn("[MainServer] BaseExteriorSystem failed: " .. tostring(err)) end
end

local DayNightCycle = nil
pcall(function() DayNightCycle = require(ServerScriptService.DayNightCycle) end)
if DayNightCycle then
	local ok, err = pcall(function() DayNightCycle.Init() end)
	if ok then print("[MainServer] DayNightCycle OK") else warn("[MainServer] DayNightCycle Init failed: " .. tostring(err)) end
end

print("[MainServer] All systems initialized")

local startupMetricsEnabled = GameConfig.StartupMetricLogEnabled == true
local joinClockByUserId = {}
local criticalReadyByUserId = {}
local loadingCriticalReadyEvent = eventsFolder:FindFirstChild("LoadingCriticalReady")

local function logStartupMetric(userId, label)
	if not startupMetricsEnabled then return end
	local joinClock = joinClockByUserId[userId]
	if not joinClock then return end
	print(("[StartupMetric] user=%s %s=%.2fs"):format(tostring(userId), label, os.clock() - joinClock))
end

local function markCriticalReady(plr, reason)
	if not plr or not plr.Parent then return end
	local uid = plr.UserId
	if criticalReadyByUserId[uid] then return end
	criticalReadyByUserId[uid] = true
	logStartupMetric(uid, "join_to_critical_ready")
	if startupMetricsEnabled then
		print(("[StartupMetric] user=%s critical_reason=%s"):format(tostring(uid), tostring(reason or "unknown")))
	end
	if loadingCriticalReadyEvent then
		loadingCriticalReadyEvent:FireClient(plr)
	end
end

-- FIX #27: Underwater drowning damage handler (client fires DrownDamage when breath runs out)
do
	local drownCooldowns = {} -- [userId] = lastDrownTick (rate-limit to prevent spam)
	drownDamage.OnServerEvent:Connect(function(plr, damage)
		if type(damage) ~= "number" then return end
		damage = math.clamp(math.floor(damage), 1, 50) -- sanitize (cap at 50 per tick)
		local now = tick()
		local last = drownCooldowns[plr.UserId] or 0
		if now - last < 2 then return end -- min 2s between drown ticks (anti-exploit)
		drownCooldowns[plr.UserId] = now
		local char = plr.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum:TakeDamage(damage)
		end
	end)
	Players.PlayerRemoving:Connect(function(plr) drownCooldowns[plr.UserId] = nil end)
end

-- ── DOME + SIGN HELPER ──
local function findPlotSignLabel(gui)
	if not gui then return nil end
	local namedTextLabel = gui:FindFirstChild("TextLabel")
	if namedTextLabel and namedTextLabel:IsA("TextLabel") then
		return namedTextLabel
	end
	local namedLabel = gui:FindFirstChild("Label")
	if namedLabel and namedLabel:IsA("TextLabel") then
		return namedLabel
	end
	return gui:FindFirstChildWhichIsA("TextLabel", true)
end

local function setPlotSignState(plotModel, ownerName)
	if not plotModel then return end
	local signPart = plotModel:FindFirstChild("SignPart", true)
	if not signPart then return end

	local hasActiveOwner = type(ownerName) == "string" and ownerName ~= ""
	local signText = hasActiveOwner and (ownerName .. "'s Base") or ""

	for _, guiClassName in ipairs({ "BillboardGui", "SurfaceGui" }) do
		local gui = signPart:FindFirstChildWhichIsA(guiClassName, true)
		if gui then
			gui.Enabled = hasActiveOwner
			local lbl = findPlotSignLabel(gui)
			if lbl then lbl.Text = signText end
		end
	end
end

local function refreshAllPlotSigns()
	local plotsFolder = Workspace:FindFirstChild("BasePlots") or Workspace:WaitForChild("BasePlots", 10)
	if not plotsFolder then return end

	local activeOwnersByPlotId = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerDataManager.GetData(player)
		if data and data.plotId and data.plotId > 0 then
			activeOwnersByPlotId[data.plotId] = player.Name
		end
	end

	for _, plotModel in ipairs(plotsFolder:GetChildren()) do
		local plotId = plotModel.Name:match("^Plot(%d+)$") or plotModel.Name:match("^Part(%d+)$")
		if plotId then
			setPlotSignState(plotModel, activeOwnersByPlotId[tonumber(plotId)])
		end
	end
end

local function setupPlotForPlayer(plr)
	local ok, err = pcall(function()
		local d = PlayerDataManager.GetData(plr)
		if not d or not d.plotId or d.plotId == 0 then return end

		local plotsFolder = workspace:FindFirstChild("BasePlots")
		if not plotsFolder then return end

		local pm = plotsFolder:FindFirstChild("Plot" .. d.plotId) or plotsFolder:FindFirstChild("Part" .. d.plotId)
		if not pm then return end

		-- Set OwnerUserId so client can identify own plot (BaseInteractionClient findOwnPlot)
		pm:SetAttribute("OwnerUserId", plr.UserId)

		-- Create dome only once (check by plotId in activeDomes table)
		if LaserDoorSystem and GameConfig.LaserDoorEnabled then
			local hasDome = LaserDoorSystem.HasDome
			local createForPlot = LaserDoorSystem.CreateForPlot
			if hasDome and createForPlot then
				if not hasDome(pm.Name) then
					createForPlot(pm, plr)
				end
			end
		end

		setPlotSignState(pm, plr.Name)
	end)
	if not ok then warn("[MainServer] setupPlotForPlayer error: " .. tostring(err)) end
end

-- Hide empty-plot sign UIs immediately so map assets do not show their default label text.
refreshAllPlotSigns()


if BaseIncomeSystem then
	BaseIncomeSystem.Init(PlayerDataManager)
	print("[MainServer] BaseIncomeSystem OK")
	-- Egg hatching: run separately (incremental placement, no full base refresh)
	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
			for _, p in ipairs(Players:GetPlayers()) do
				local anyHatched, hatchedSlots = PlayerDataManager.ProcessEggHatches(p)
				if anyHatched and BasePlacementSystem then
					for _, h in ipairs(hatchedSlots) do
						BasePlacementSystem.PlaceCreatureInSlot(p, h.slotType, h.slotIndex, h.newUid)
					end
				end
			end
		end
	end)
else
	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
			for _, p in ipairs(Players:GetPlayers()) do
				local d = PlayerDataManager.GetData(p)
				if d then
					-- Hatch eggs that are ready (placed on base/defense points)
					-- Use incremental PlaceCreatureInSlot per hatched slot instead of full PlaceCreatures
					local anyHatched, hatchedSlots = PlayerDataManager.ProcessEggHatches(p)
					if anyHatched and BasePlacementSystem then
						for _, h in ipairs(hatchedSlots) do
							BasePlacementSystem.PlaceCreatureInSlot(p, h.slotType, h.slotIndex, h.newUid)
						end
					end
					-- Income: only from creatures on income slots (eggs generate nothing)
					local inc = 0
					for _, uid in ipairs(d.baseSlots or {}) do
						if not uid or uid == "" then continue end
						if PlayerDataManager.GetEggByUid(p, uid) then continue end -- skip eggs
						for _, e in ipairs(d.inventory or {}) do
							if e.uid and tostring(e.uid) == tostring(uid) then
								local info = CreatureData.GetById(e.id)
								if info then inc = inc + info.baseIncome end; break
							end
						end
					end
					if inc > 0 then
						PlayerDataManager.AddCoins(p, inc)
						incomeReceived:FireClient(p, inc)
					end
				end
			end
		end
	end)
	print("[MainServer] Inline income running")
end

-- === STEP 4: Helpers ===

local function refreshPlayerBase(plr)
	if BasePlacementSystem then
		task.spawn(function() BasePlacementSystem.PlaceCreatures(plr) end)
	end
	setupPlotForPlayer(plr)
end

local function checkDespawnCompanion(plr)
	if FavoriteCreatureSystem then
		local d = PlayerDataManager.GetData(plr)
		if not d or not d.favoriteUid then
			FavoriteCreatureSystem.DespawnCompanion(plr)
		end
	end
end

-- Teleport player to their base PlotCenter; also teleports companion with them
local function teleportToBase(plr)
	local d = PlayerDataManager.GetData(plr)
	if not d or not d.plotId or d.plotId == 0 then return end
	local plotsFolder = Workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return end
	local pm = plotsFolder:FindFirstChild("Plot" .. d.plotId)
		or plotsFolder:FindFirstChild("Part" .. d.plotId)
	if not pm then return end
	local center = pm:FindFirstChild("PlotCenter")
	if not center or not center:IsA("BasePart") then return end
	local char = plr.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.new(center.Position + Vector3.new(0, 5, 0))
			if FavoriteCreatureSystem then FavoriteCreatureSystem.TeleportCompanionWithPlayer(plr) end
		end
	end
end

-- Global "Heaven Beam" effect for home recall (server-spawned, visible to all players)
local function createHomeRecallEffect(rootPart, channelTime)
	local rootPos = rootPart.Position
	local skyHeight = math.max(100, GameConfig.HomeRecallSkyHeight or 600)
	local skyPos = rootPos + Vector3.new(0, skyHeight, 0)
	local radius = GameConfig.HomeRecallCylinderRadius or 6
	local beamRadius = GameConfig.HomeRecallBeamRadius or 8  -- wide beam, clearly larger than player (~2 studs)
	local groundRadius = GameConfig.HomeRecallGroundRadius or 12
	channelTime = channelTime or (GameConfig.HomeRecallChannelTime or 5)

	local portalOpenTime = 0.5
	local beamDescendEnd = math.min(2, channelTime * 0.4)
	local lockStart = math.min(2.5, channelTime * 0.6)
	local fadeStart = math.max(channelTime - 1.5, lockStart + 0.3)
	local totalDuration = channelTime + 1

	local model = Instance.new("Model")
	model.Name = "HomeRecallEffect"

	local function safeTween(inst, info, props)
		if not inst or not inst.Parent then return nil end
		local tween = TweenService:Create(inst, info, props)
		tween:Play()
		return tween
	end

	local portal = Instance.new("Part")
	portal.Name = "HeavenPortal"
	portal.Anchored = true
	portal.CanCollide = false
	portal.CanQuery = false
	portal.CanTouch = false
	portal.CastShadow = false
	portal.Material = Enum.Material.Neon
	portal.Color = Color3.fromRGB(180, 220, 255)
	portal.Transparency = 1
	portal.Shape = Enum.PartType.Cylinder
	portal.Size = Vector3.new(beamRadius * 2.5, 0.5, beamRadius * 2.5)
	portal.CFrame = CFrame.new(skyPos) * CFrame.Angles(0, 0, math.rad(90))
	portal.Parent = model

	local portalPE = Instance.new("ParticleEmitter")
	portalPE.Name = "PortalGlow"
	portalPE.Texture = "rbxassetid://5860841663"
	portalPE.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255), Color3.fromRGB(140, 190, 255))
	portalPE.Size = NumberSequence.new(0.5, 1.5)
	portalPE.Lifetime = NumberRange.new(0.6, 1.2)
	portalPE.Rate = 40
	portalPE.Speed = NumberRange.new(0.5, 2)
	portalPE.SpreadAngle = Vector2.new(180, 180)
	portalPE.LightEmission = 0.7
	portalPE.Parent = portal

	local beam = Instance.new("Part")
	beam.Name = "HeavenBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(150, 200, 255)
	beam.Transparency = 1
	beam.Shape = Enum.PartType.Cylinder
	local beamHeight = skyHeight
	beam.Size = Vector3.new(beamRadius * 2, beamHeight, beamRadius * 2)
	beam.CFrame = CFrame.new(rootPos + Vector3.new(0, skyHeight * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Parent = model

	local beamLight = Instance.new("PointLight")
	beamLight.Brightness = 4
	beamLight.Range = math.max(40, radius * 4)
	beamLight.Color = Color3.fromRGB(200, 230, 255)
	beamLight.Parent = beam

	-- Large semi-transparent cylinder tube (surrounds player body); thin beam stays at center
	local tubeRadius = groundRadius
	local tube = Instance.new("Part")
	tube.Name = "HeavenTube"
	tube.Anchored = true
	tube.CanCollide = false
	tube.CanQuery = false
	tube.CanTouch = false
	tube.CastShadow = false
	tube.Material = Enum.Material.ForceField
	tube.Color = Color3.fromRGB(180, 220, 255)
	tube.Transparency = 1
	tube.Shape = Enum.PartType.Cylinder
	tube.Size = Vector3.new(beamHeight, tubeRadius * 2, tubeRadius * 2)
	tube.CFrame = CFrame.new(rootPos + Vector3.new(0, skyHeight * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	tube.Parent = model

	local ground = Instance.new("Part")
	ground.Name = "HeavenImpact"
	ground.Anchored = true
	ground.CanCollide = false
	ground.CanQuery = false
	ground.CanTouch = false
	ground.CastShadow = false
	ground.Material = Enum.Material.Neon
	ground.Color = Color3.fromRGB(180, 220, 255)
	ground.Transparency = 1
	ground.Shape = Enum.PartType.Cylinder
	ground.Size = Vector3.new(2, 0.4, 2)
	ground.CFrame = CFrame.new(rootPos) * CFrame.Angles(0, 0, math.rad(90))
	ground.Parent = model

	local groundPE = Instance.new("ParticleEmitter")
	groundPE.Name = "ImpactFountain"
	groundPE.Texture = "rbxassetid://5860841663"
	groundPE.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255), Color3.fromRGB(160, 210, 255))
	groundPE.Size = NumberSequence.new(0.6, 1.4)
	groundPE.Lifetime = NumberRange.new(0.8, 1.6)
	groundPE.Rate = 0
	groundPE.Speed = NumberRange.new(6, 10)
	groundPE.EmissionDirection = Enum.NormalId.Top
	groundPE.SpreadAngle = Vector2.new(40, 40)
	groundPE.LightEmission = 0.8
	groundPE.Parent = ground

	local shockPE = Instance.new("ParticleEmitter")
	shockPE.Name = "GroundShock"
	shockPE.Texture = "rbxassetid://5860841663"
	shockPE.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
	shockPE.Size = NumberSequence.new(1, groundRadius * 0.6)
	shockPE.Lifetime = NumberRange.new(0.4, 0.6)
	shockPE.Rate = 0
	shockPE.Speed = NumberRange.new(0, 0)
	shockPE.EmissionDirection = Enum.NormalId.Top
	shockPE.LightEmission = 0.7
	shockPE.Parent = ground

	local descendSound = Instance.new("Sound")
	descendSound.Name = "HeavenBeamDescend"
	descendSound.SoundId = "rbxassetid://0" -- TODO: set to heaven_beam_descend asset
	descendSound.Volume = 1.2
	descendSound.RollOffMode = Enum.RollOffMode.Inverse
	descendSound.MaxDistance = 500
	descendSound.Parent = beam

	local impactSound = Instance.new("Sound")
	impactSound.Name = "HeavenBeamImpact"
	impactSound.SoundId = "rbxassetid://0" -- TODO: set to impact asset
	impactSound.Volume = 1.6
	impactSound.RollOffMode = Enum.RollOffMode.Inverse
	impactSound.MaxDistance = 500
	impactSound.Parent = ground

	local humLoop = Instance.new("Sound")
	humLoop.Name = "HeavenBeamHum"
	humLoop.SoundId = "rbxassetid://0" -- TODO: set to hum_loop asset
	humLoop.Volume = 0.7
	humLoop.Looped = true
	humLoop.RollOffMode = Enum.RollOffMode.Inverse
	humLoop.MaxDistance = 500
	humLoop.Parent = beam

	model.PrimaryPart = beam
	model.Parent = Workspace

	safeTween(portal, TweenInfo.new(portalOpenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.15,
		Size = Vector3.new(beamRadius * 3, 0.5, beamRadius * 3),
	})

	task.delay(portalOpenTime, function()
		if not model or not model.Parent then return end
		descendSound:Play()
		humLoop:Play()
		beam.Transparency = 0.9
		ground.Transparency = 0.6
		tube.Transparency = 0.65  -- semi-transparent tube around player

		safeTween(beam, TweenInfo.new(beamDescendEnd - portalOpenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			Transparency = 0.1,
			Color = Color3.fromRGB(200, 235, 255),
		})
	end)

	task.delay(lockStart, function()
		if not model or not model.Parent then return end
		impactSound:Play()
		groundPE.Rate = 80
		shockPE:Emit(1)
		safeTween(ground, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(groundRadius * 2, 0.4, groundRadius * 2),
			Transparency = 0.3,
		})
		safeTween(beamLight, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 7,
			Range = math.max(60, radius * 6),
		})
	end)

	task.delay(fadeStart, function()
		if not model or not model.Parent then return end
		groundPE.Rate = 20
		safeTween(beam, TweenInfo.new(totalDuration - fadeStart, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		})
		safeTween(tube, TweenInfo.new(totalDuration - fadeStart, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		})
		safeTween(ground, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		})
		safeTween(portal, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		})
		task.delay(1, function()
			if humLoop.IsPlaying then humLoop:Stop() end
		end)
	end)

	task.delay(totalDuration, function()
		if model and model.Parent then
			model:Destroy()
		end
	end)

	return model
end

-- Home recall: 5s channel, interrupt on damage or leaving bubble, then teleport player + companion
local homeRecallingPlayers = {}
local function cancelRecall(plr, effect, conn, fireCancel)
	homeRecallingPlayers[plr.UserId] = nil
	if effect and effect.Parent then effect:Destroy() end
	if conn then conn:Disconnect() end
	if fireCancel then
		local evt = eventsFolder:FindFirstChild("HomeRecallCancel")
		if evt then evt:FireClient(plr) end
	end
end

local function startHomeRecall(plr)
	if homeRecallingPlayers[plr.UserId] then return end
	local char = plr.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChild("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end
	local d = PlayerDataManager.GetData(plr)
	if not d or not d.plotId or d.plotId == 0 then return end
	local channelTime = GameConfig.HomeRecallChannelTime or 5
	local radius = GameConfig.HomeRecallCylinderRadius or 6
	local bubbleCenter = root.Position
	homeRecallingPlayers[plr.UserId] = { cancelled = false }
	local effect = createHomeRecallEffect(root, channelTime)
	local startHealth = humanoid.Health
	local conn
	conn = humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < startHealth then
			local state = homeRecallingPlayers[plr.UserId]
			if state then state.cancelled = true end
			cancelRecall(plr, effect, conn, true)
		end
		startHealth = newHealth
	end)
	local startEvt = eventsFolder:FindFirstChild("HomeRecallStart")
	if startEvt then startEvt:FireClient(plr, channelTime) end
	task.spawn(function()
		local startTime = tick()
		while tick() - startTime < channelTime do
			local state = homeRecallingPlayers[plr.UserId]
			if not state or state.cancelled then return end
			local c = plr.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if not r then
				state.cancelled = true
				cancelRecall(plr, effect, conn, true)
				return
			end
			local dxz = (r.Position - bubbleCenter) * Vector3.new(1, 0, 1)
			if dxz.Magnitude > radius then
				state.cancelled = true
				cancelRecall(plr, effect, conn, true)
				return
			end
			task.wait(0.1)
		end
		local state = homeRecallingPlayers[plr.UserId]
		if not state or state.cancelled then return end
		if conn then conn:Disconnect() end
		if effect and effect.Parent then effect:Destroy() end
		homeRecallingPlayers[plr.UserId] = nil
		local endEvt = eventsFolder:FindFirstChild("HomeRecallEnd")
		if endEvt then endEvt:FireClient(plr) end
		teleportToBase(plr)
	end)
end

-- Helper: award player XP and fire level-up event if needed
local function awardPlayerXP(plr, amount)
	local newLvl, didLvl = PlayerDataManager.AddPlayerXP(plr, amount)
	if didLvl then
		local lvlEvt = eventsFolder:FindFirstChild("PlayerLevelUp")
		if lvlEvt then lvlEvt:FireClient(plr, newLvl) end
	end
	return newLvl, didLvl
end

-- Auto-assign plot + setup for a player (used on join)
local function autoAssignAndSetup(plr)
	-- Wait for data to be available (PlayerDataManager.OnPlayerJoin may still be loading)
	local d = nil
	for attempt = 1, 10 do
		d = PlayerDataManager.GetData(plr)
		if d then break end
		task.wait(1)
	end
	if not d then
		warn("[MainServer] Data never loaded for " .. plr.Name)
		return
	end
	logStartupMetric(plr.UserId, "join_to_data_ready")

	-- Assign a random unoccupied base every time (spawn at random base each join)
	local plotId = PlayerDataManager.AssignPlot(plr)
	if plotId and plotId > 0 then
		print("[MainServer] Assigned Plot " .. plotId .. " to " .. plr.Name)
	else
		warn("[MainServer] No plots available for " .. plr.Name)
	end

	if BasePlacementSystem and BasePlacementSystem.RefreshAllPlotVisibility then
		BasePlacementSystem.RefreshAllPlotVisibility()
	end
	refreshPlayerBase(plr)

	-- Teleport to base on initial join
	local char = plr.Character or plr.CharacterAdded:Wait()
	task.wait(0.5)
	teleportToBase(plr)
	logStartupMetric(plr.UserId, "join_to_character_spawn")

	-- Debug: double movement speed
	local function applyWalkSpeed(c)
		local speed = GameConfig.DebugDoubleSpeed and 32
		if speed and c then
			local hum = c:FindFirstChild("Humanoid")
			if hum then hum.WalkSpeed = speed end
		end
	end
	applyWalkSpeed(char)

	-- Small area light on right arm so it's not completely dark at night (emanates from right arm)
	local function attachPlayerArmLight(character)
		if not character or not character.Parent then return end
		local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightLowerArm") or character:FindFirstChild("RightHand")
		if not rightArm then return end
		if rightArm:FindFirstChild("PlayerArmLight") then return end
		local light = Instance.new("PointLight")
		light.Name = "PlayerArmLight"
		light.Brightness = 1.2
		light.Range = 14
		light.Color = Color3.fromRGB(255, 235, 200)
		light.Parent = rightArm
	end
	local function ensurePlayerArmLight(character)
		attachPlayerArmLight(character)
		if not character or not character.Parent then return end
		local arm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightLowerArm") or character:FindFirstChild("RightHand")
		if not arm or arm:FindFirstChild("PlayerArmLight") then return end
		task.defer(function()
			task.wait(0.5)
			if character and character.Parent then attachPlayerArmLight(character) end
		end)
	end
	ensurePlayerArmLight(char)

	-- Respawn at base on death (no base refresh - creatures persist)
	plr.CharacterAdded:Connect(function(newChar)
		task.wait(0.5)
		teleportToBase(plr)
		applyWalkSpeed(newChar)
		ensurePlayerArmLight(newChar)
	end)

	-- Player can start playing once core setup is done; world warmup continues in background.
	markCriticalReady(plr, "auto_assign_setup_complete")
end

-- Handle players who join
Players.PlayerAdded:Connect(function(plr)
	joinClockByUserId[plr.UserId] = os.clock()
	task.spawn(function() autoAssignAndSetup(plr) end)
	task.delay(GameConfig.LoadingCriticalMaxWait or 18, function()
		if plr and plr.Parent and not criticalReadyByUserId[plr.UserId] then
			markCriticalReady(plr, "critical_timeout_fallback")
		end
	end)
end)

-- FIX #24: Clean up base plots when players leave (dome removal, sign reset, floor hiding)
-- BasePlacementSystem.PlayerRemoving handles orb cleanup + RefreshAllPlotVisibility.
-- This handler covers MainServer-owned state: dome, sign, companion.
Players.PlayerRemoving:Connect(function(plr)
	-- FIX #35: Return knight base rental BEFORE clearing plot data (needs plotId + PlotCenter)
	if KnightBaseSystem and KnightBaseSystem.IsPlayerRenting and KnightBaseSystem.IsPlayerRenting(plr) then
		pcall(function() KnightBaseSystem.Cleanup(plr) end)
	end

	-- Grab plot info BEFORE PlayerDataManager clears it (PDM also listens to PlayerRemoving)
	local d = PlayerDataManager.GetData(plr)
	local plotId = d and d.plotId
	local plotModel = nil
	if plotId and plotId > 0 then
		local plotsFolder = Workspace:FindFirstChild("BasePlots")
		if plotsFolder then
			plotModel = plotsFolder:FindFirstChild("Plot" .. plotId)
				or plotsFolder:FindFirstChild("Part" .. plotId)
		end
	end

	-- Remove dome shield
	if plotModel and LaserDoorSystem and LaserDoorSystem.RemoveForPlot then
		pcall(function() LaserDoorSystem.RemoveForPlot(plotModel) end)
	end

	-- Hide the plot sign when no active player owns this base.
	if plotModel then
		setPlotSignState(plotModel, nil)
		-- Clear OwnerUserId attribute so client doesn't think this is still owned
		plotModel:SetAttribute("OwnerUserId", nil)
	end

	-- Despawn companion (FavoriteCreatureSystem handles its own cleanup via PlayerRemoving,
	-- but ensure it runs before plot data is gone)
	if FavoriteCreatureSystem and FavoriteCreatureSystem.DespawnCompanion then
		pcall(function() FavoriteCreatureSystem.DespawnCompanion(plr) end)
	end

	-- Cancel home recall if in progress
	if homeRecallingPlayers and homeRecallingPlayers[plr.UserId] then
		homeRecallingPlayers[plr.UserId] = nil
	end
	joinClockByUserId[plr.UserId] = nil
	criticalReadyByUserId[plr.UserId] = nil

	print("[MainServer] Cleaned up plot for " .. plr.Name .. " (Plot " .. tostring(plotId) .. ")")
end)

-- Handle players already in game (Studio test / fast join)
for _, plr in ipairs(Players:GetPlayers()) do
	joinClockByUserId[plr.UserId] = os.clock()
	task.spawn(function() autoAssignAndSetup(plr) end)
	task.delay(GameConfig.LoadingCriticalMaxWait or 18, function()
		if plr and plr.Parent and not criticalReadyByUserId[plr.UserId] then
			markCriticalReady(plr, "critical_timeout_fallback")
		end
	end)
end

-- Start creature spawning independently (wait for any player to exist)
task.spawn(function()
	while #Players:GetPlayers() == 0 do
		task.wait(1)
	end
	task.wait(2) -- Small extra delay for data to load
	if CreatureSpawner and CreatureSpawner.StartSpawning then
		print("[MainServer] Starting creature spawning...")
		CreatureSpawner.StartSpawning()
	else
		warn("[MainServer] Creature spawning NOT started - CreatureSpawner:", CreatureSpawner ~= nil, "StartSpawning:", CreatureSpawner and CreatureSpawner.StartSpawning ~= nil)
	end
end)

-- Loading ready: wait for creature spawn target + min wait, then fire LoadingReady to all players
local loadingReady = false
local loadingReadyEvent = eventsFolder:FindFirstChild("LoadingReady")
if loadingReadyEvent then
	task.spawn(function()
		local spawnTarget = GameConfig.LoadingSpawnTarget or 80
		local minWait = GameConfig.LoadingMinWait or 12
		local maxWait = GameConfig.LoadingMaxWait or 60
		local CREATURE_TAG = "WorldCreature"
		local startTime = tick()
		while tick() - startTime < maxWait do
			local elapsed = tick() - startTime
			local count = #CollectionService:GetTagged(CREATURE_TAG)
			if count >= spawnTarget and elapsed >= minWait then
				break
			end
			task.wait(0.5)
		end
		loadingReady = true
		local finalCount = #CollectionService:GetTagged(CREATURE_TAG)
		print("[MainServer] Loading ready! Creatures:", finalCount .. ", elapsed:", string.format("%.1f", tick() - startTime) .. "s")
		if startupMetricsEnabled then
			print(("[StartupMetric] world_ready_elapsed=%.2fs creatures=%d"):format(tick() - startTime, finalCount))
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			loadingReadyEvent:FireClient(plr)
		end
	end)
	Players.PlayerAdded:Connect(function(plr)
		if loadingReady and loadingReadyEvent then
			loadingReadyEvent:FireClient(plr)
		end
	end)
end

-- === STEP 5: Remote handlers ===

-- GET INVENTORY
getInventory.OnServerInvoke = function(plr)
	local d = PlayerDataManager.GetData(plr)
	if not d then return nil end
	local filledIncome = PlayerDataManager.GetFilledSlotCount and PlayerDataManager.GetFilledSlotCount(plr, "income") or 0
	local filledDefense = PlayerDataManager.GetFilledSlotCount and PlayerDataManager.GetFilledSlotCount(plr, "defense") or 0
	local incomeMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(plr, "income") or (GameConfig.MaxIncomeSlots or 6)
	local defenseMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(plr, "defense") or (GameConfig.MaxDefenseSlots or 6)
	-- Dense slot arrays so client sees every slot (ipairs stops at first nil; sparse tables broke labels/assignment past slot 1)
	local function toDense(slots, maxLen)
		local out = {}
		for i = 1, maxLen do
			local v = slots and (slots[i] or slots[tostring(i)])
			out[i] = (v and v ~= "") and tostring(v) or ""
		end
		return out
	end
	local baseSlotsDense = toDense(d.baseSlots, incomeMax)
	local defenseSlotsDense = toDense(d.defenseSlots, defenseMax)
	-- Explicit UID lists so client Rem button works (Roblox remote serialization can drop/alter keyed tables; simple arrays are reliable)
	local baseSlotUids = {}
	for i = 1, incomeMax do
		local v = d.baseSlots and (d.baseSlots[i] or d.baseSlots[tostring(i)])
		if v and v ~= "" then table.insert(baseSlotUids, tostring(v)) end
	end
	local defenseSlotUids = {}
	for i = 1, defenseMax do
		local v = d.defenseSlots and (d.defenseSlots[i] or d.defenseSlots[tostring(i)])
		if v and v ~= "" then table.insert(defenseSlotUids, tostring(v)) end
	end
	-- Send as comma-separated strings so Rem button works (tables in return can be dropped/mangled by remote serialization)
	local baseSlotUidsStr = table.concat(baseSlotUids, ",")
	local defenseSlotUidsStr = table.concat(defenseSlotUids, ",")
	local bt = d.battleTeam or {}
	-- CRITICAL: Send battle team as an array of { slot, uid }. Roblox remote serialization
	-- can drop entries for tables with sparse numeric keys (e.g. { [1]=a, [3]=b, [4]=c } becomes
	-- just [a] or [a,b,c] with wrong indices), which made slots 3 and 4 "disappear" when slot 1 was filled.
	local battleTeamSlots = {}
	for k, v in pairs(bt) do
		local slot = tonumber(k)
		if slot and slot >= 1 and slot <= (GameConfig.MaxBattleTeamSize or 9) and type(v) == "string" and v ~= "" then
			table.insert(battleTeamSlots, { slot = slot, uid = v })
		end
	end
	-- Also send legacy battleTeam table for any code that still uses it (client will prefer battleTeamSlots)1
	local battleTeamLegacy = {}
	for _, entry in ipairs(battleTeamSlots) do
		battleTeamLegacy[entry.slot] = entry.uid
	end
	local battleMax = GameConfig.MaxBattleTeamCreatures or 5
	local defenseActiveCount, defenseTotalSpawned = 0, 0
	if BasePlacementSystem and BasePlacementSystem.GetDefenseActivityForOwner then
		defenseActiveCount, defenseTotalSpawned = BasePlacementSystem.GetDefenseActivityForOwner(plr.UserId)
	end
	return {
		coins = d.coins, gems = d.gems or 0,
		inventory = d.inventory,
		eggs = d.eggs or {},
		baseSlots = baseSlotsDense, defenseSlots = defenseSlotsDense,
		baseSlotUidsStr = baseSlotUidsStr, defenseSlotUidsStr = defenseSlotUidsStr,
		filledBaseCount = filledIncome, filledDefenseCount = filledDefense,
		incomeMax = incomeMax, defenseMax = defenseMax,
		battleFilled = #battleTeamSlots, battleMax = battleMax,
		defenseActiveCount = defenseActiveCount,
		defenseTotalSpawned = defenseTotalSpawned,
		defenseRaidActive = defenseActiveCount > 0,
		favoriteUid = d.favoriteUid, battleTeam = battleTeamLegacy, battleTeamSlots = battleTeamSlots,
		battleTeamEnabled = d.battleTeamEnabled ~= false,
		plotId = d.plotId or 0, stats = d.stats,
		activeBuffs = PlayerDataManager.GetActiveBuffs(plr),
		cosmetics = PlayerDataManager.GetCosmetics(plr),
		exterior = PlayerDataManager.GetExterior(plr),
		baseColor = PlayerDataManager.GetBaseColor(plr),
		ownedFloors = d.ownedFloors or {1},
		playerLevel = d.playerLevel or 1,
		sigils = d.sigils or {},
		firstZoneDoorOpened = d.firstZoneDoorOpened,
		zoneKeysFromGyms = d.zoneKeysFromGyms or {},
		doorsUnlocked = d.doorsUnlocked or {},
	}
end

setCreatureNickname.OnServerInvoke = function(plr, uid, nickname)
	if type(uid) ~= "string" or uid == "" then return false, "Invalid creature", 0, nil end
	local ok, msg, gemCost, finalNickname = PlayerDataManager.SetCreatureNickname(plr, uid, nickname)
	if ok then
		-- Nickname is visible in world/base tags, so refresh this player's placed creatures.
		if BasePlacementSystem then
			refreshPlayerBase(plr)
		end
		local gemsEvt = eventsFolder:FindFirstChild("GemsUpdate")
		if gemsEvt then gemsEvt:FireClient(plr, PlayerDataManager.GetGems(plr)) end
	end
	return ok, msg, gemCost or 0, finalNickname
end

-- Zone doors: open one door with 4 sigils (client calls from Sigils UI)
local openZoneDoorWithSigils = makeFunc("OpenZoneDoorWithSigils")
openZoneDoorWithSigils.OnServerInvoke = function(plr, zoneId)
	if not plr or not plr.Parent then return false, "Invalid player" end
	if type(zoneId) ~= "string" or zoneId == "" then return false, "Invalid zone" end
	local ok = PlayerDataManager.SpendFourSigilsOpenDoor(plr, zoneId)
	if ok then return true end
	return false, "Cannot open door (need 4 sigils and no door chosen yet, or invalid zone)"
end

-- Zone doors: unlock a door with a gym key (client calls from Sigils UI)
local unlockDoorWithKey = makeFunc("UnlockDoorWithKey")
unlockDoorWithKey.OnServerInvoke = function(plr, zoneId)
	if not plr or not plr.Parent then return false, "Invalid player" end
	if type(zoneId) ~= "string" or zoneId == "" then return false, "Invalid zone" end
	local ok = PlayerDataManager.UnlockDoorWithKey(plr, zoneId)
	if ok then return true end
	return false, "No key for this zone or door already unlocked"
end

-- Base Exterior: get config by id
local function getExteriorConfig(exteriorId)
	for _, item in ipairs(GameConfig.BaseExteriorItems or {}) do
		if item.id == exteriorId then return item end
	end
	return nil
end

local function savePlayerCustomization(plr)
	if not plr or not PlayerDataManager or not PlayerDataManager.SavePlayer then
		return
	end

	task.spawn(function()
		pcall(function()
			PlayerDataManager.SavePlayer(plr)
		end)
	end)
end

buyExterior.OnServerInvoke = function(plr, exteriorId, currency)
	local config = getExteriorConfig(exteriorId)
	if not config then return false, "Invalid exterior" end
	if PlayerDataManager.OwnsExterior(plr, exteriorId) then return false, "Already owned!" end
	local d = PlayerDataManager.GetData(plr)
	if not d then return false, "No data" end
	if currency == "coins" then
		if (config.coinCost or 0) <= 0 then return false, "Not for coins" end
		if d.coins < config.coinCost then return false, "Not enough coins!" end
		PlayerDataManager.SpendCoins(plr, config.coinCost)
	elseif currency == "gems" then
		if (config.gemCost or 0) <= 0 then return false, "Not for gems" end
		if not PlayerDataManager.SpendGems(plr, config.gemCost) then return false, "Not enough gems!" end
	else
		return false, "Invalid currency"
	end
	PlayerDataManager.PurchaseExterior(plr, exteriorId)
	savePlayerCustomization(plr)
	local coinsEvt = eventsFolder:FindFirstChild("CoinsUpdate")
	if coinsEvt then coinsEvt:FireClient(plr, PlayerDataManager.GetCoins(plr)) end
	return true, "Purchased!"
end

equipExterior.OnServerInvoke = function(plr, exteriorId)
	if exteriorId then
		if not PlayerDataManager.OwnsExterior(plr, exteriorId) then return false, "Not owned" end
	end
	-- Link with Colors tab: equipping any exterior clears base color so both UIs stay in sync
	PlayerDataManager.SetEquippedBaseColor(plr, nil)
	PlayerDataManager.SetEquippedExterior(plr, exteriorId)
	savePlayerCustomization(plr)
	-- Skin existing plot (recolor + exterior shell); never delete or move the plot
	if not BaseExteriorSystem or not BaseExteriorSystem.ApplyThemeToPlot then return true, exteriorId and "Theme applied!" or "Unequipped" end
	local plot = BaseExteriorSystem.GetPlotForPlayer(plr)
	if not plot then return true, exteriorId and "Equipped (no plot to theme)" or "Unequipped" end
	BaseExteriorSystem.ApplyThemeToPlot(plot, exteriorId)
	if BaseExteriorSystem.ApplyBaseColorToPlot then
		local bc = PlayerDataManager.GetBaseColor(plr)
		BaseExteriorSystem.ApplyBaseColorToPlot(plot, bc and bc.equipped)
	end
	return true, exteriorId and "Theme applied!" or "Theme removed"
end

-- Base Color: get config by id
local function getBaseColorConfig(colorId)
	for _, item in ipairs(GameConfig.BaseColorItems or {}) do
		if item.id == colorId then return item end
	end
	return nil
end

buyBaseColor.OnServerInvoke = function(plr, colorId, currency)
	local config = getBaseColorConfig(colorId)
	if not config then return false, "Invalid color" end
	if PlayerDataManager.OwnsBaseColor(plr, colorId) then return false, "Already owned!" end
	local d = PlayerDataManager.GetData(plr)
	if not d then return false, "No data" end
	if currency == "coins" then
		if (config.coinCost or 0) <= 0 then return false, "Not for coins" end
		if d.coins < config.coinCost then return false, "Not enough coins!" end
		PlayerDataManager.SpendCoins(plr, config.coinCost)
	elseif currency == "gems" then
		if (config.gemCost or 0) <= 0 then return false, "Not for gems" end
		if not PlayerDataManager.SpendGems(plr, config.gemCost) then return false, "Not enough gems!" end
	else
		return false, "Invalid currency"
	end
	PlayerDataManager.PurchaseBaseColor(plr, colorId)
	savePlayerCustomization(plr)
	local coinsEvt = eventsFolder:FindFirstChild("CoinsUpdate")
	if coinsEvt then coinsEvt:FireClient(plr, PlayerDataManager.GetCoins(plr)) end
	return true, "Purchased!"
end

equipBaseColor.OnServerInvoke = function(plr, colorId)
	if colorId then
		if not PlayerDataManager.OwnsBaseColor(plr, colorId) then return false, "Not owned" end
	end
	-- Link with Base tab: equipping a color clears exterior so both UIs stay in sync
	PlayerDataManager.SetEquippedExterior(plr, nil)
	PlayerDataManager.SetEquippedBaseColor(plr, colorId)
	savePlayerCustomization(plr)
	local plot = BaseExteriorSystem and BaseExteriorSystem.GetPlotForPlayer and BaseExteriorSystem.GetPlotForPlayer(plr)
	if plot and BaseExteriorSystem then
		-- Clear any custom theme (removes shell, resets parts) then apply base color
		if BaseExteriorSystem.ApplyThemeToPlot then
			BaseExteriorSystem.ApplyThemeToPlot(plot, nil)
		end
		if BaseExteriorSystem.ApplyBaseColorToPlot then
			BaseExteriorSystem.ApplyBaseColorToPlot(plot, colorId)
		end
	end
	return true, colorId and "Base color applied!" or "Color removed"
end

-- GET BATTLE TEAM (with synergy info)
getBattleTeam.OnServerInvoke = function(plr)
	local d = PlayerDataManager.GetData(plr)
	if not d then return nil end
	local bt = d.battleTeam or {}
	local teamCreatureIds = {}
	local slots = {}
	for slotIndex, uid in pairs(bt) do
		local sNum = tonumber(slotIndex)
		local su = uid and tostring(uid) or ""
		for _, e in ipairs(d.inventory) do
			if e.uid and tostring(e.uid) == su then
				table.insert(teamCreatureIds, e.id)
				local info = CreatureData.GetById(e.id)
				slots[sNum] = {
					uid = uid, creatureId = e.id,
					displayName = info and info.displayName or "?",
					element = info and info.element or "",
					class = info and info.class or "",
				}
				break
			end
		end
	end
	local synergies, elemCounts, classCounts = {}, {}, {}
	if CreatureData.CalculateSynergies then
		synergies, elemCounts, classCounts = CreatureData.CalculateSynergies(teamCreatureIds)
	end
	local count = 0; for _ in pairs(bt) do count = count + 1 end
	return {
		slots = slots, teamSize = count, maxTeamSize = 5,
		synergies = synergies or {}, elementCounts = elemCounts or {}, classCounts = classCounts or {},
	}
end

-- ASSIGN TO BASE (income). Optional 3rd arg: slot index (1..max = assign), 0 = remove from income (Rem button).s
assignToBase.OnServerEvent:Connect(function(plr, uid, toSlotIndex)
	-- Normalize remove: client sends 0 for Rem; Roblox remotes can sometimes alter 0, so accept 0 or "0"
	local slotArg = (toSlotIndex == 0 or toSlotIndex == "0") and 0 or toSlotIndex
	if type(slotArg) == "number" and slotArg >= 1 and BasePlacementSystem then
		BasePlacementSystem.ClearCreatureAtSlot(plr, "income", slotArg)
	end
	local ok, slotIndex, added = PlayerDataManager.AssignToBase(plr, uid, slotArg)
	if ok then
		checkDespawnCompanion(plr)
		if BasePlacementSystem then
			if added then
				BasePlacementSystem.PlaceCreatureInSlot(plr, "income", slotIndex, uid)
			else
				if BasePlacementSystem.ClearOrbByUid then BasePlacementSystem.ClearOrbByUid(plr, uid, true) end
			end
		else
			refreshPlayerBase(plr)
		end
		if slotAssignComplete then
			local d = PlayerDataManager.GetData(plr)
			local incomeMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(plr, "income") or 6
			local defenseMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(plr, "defense") or 6
			local baseList, defList = {}, {}
			if d and d.baseSlots then for i = 1, incomeMax do local v = d.baseSlots[i] or d.baseSlots[tostring(i)]; if v and v ~= "" then table.insert(baseList, tostring(v)) end end end
			if d and d.defenseSlots then for i = 1, defenseMax do local v = d.defenseSlots[i] or d.defenseSlots[tostring(i)]; if v and v ~= "" then table.insert(defList, tostring(v)) end end end
			slotAssignComplete:FireClient(plr, table.concat(baseList, ","), table.concat(defList, ","))
		end
	end
end)

-- ASSIGN TO DEFENSE. Optional 3rd arg: slot index (1..max = assign), 0 = remove from defense (Rem button).
assignToDefense.OnServerEvent:Connect(function(plr, uid, toSlotIndex)
	local slotArg = (toSlotIndex == 0 or toSlotIndex == "0") and 0 or toSlotIndex
	if type(slotArg) == "number" and slotArg >= 1 and BasePlacementSystem then
		BasePlacementSystem.ClearCreatureAtSlot(plr, "defense", slotArg)
	end
	local ok, slotIndex, added = PlayerDataManager.AssignToDefense(plr, uid, slotArg)
	if ok then
		checkDespawnCompanion(plr)
		if BasePlacementSystem then
			if added then
				BasePlacementSystem.PlaceCreatureInSlot(plr, "defense", slotIndex, uid)
			else
				if BasePlacementSystem.ClearOrbByUid then BasePlacementSystem.ClearOrbByUid(plr, uid, true) end
			end
		else
			refreshPlayerBase(plr)
		end
		if slotAssignComplete then
			local d = PlayerDataManager.GetData(plr)
			local incomeMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(plr, "income") or 6
			local defenseMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(plr, "defense") or 6
			local baseList, defList = {}, {}
			if d and d.baseSlots then for i = 1, incomeMax do local v = d.baseSlots[i] or d.baseSlots[tostring(i)]; if v and v ~= "" then table.insert(baseList, tostring(v)) end end end
			if d and d.defenseSlots then for i = 1, defenseMax do local v = d.defenseSlots[i] or d.defenseSlots[tostring(i)]; if v and v ~= "" then table.insert(defList, tostring(v)) end end end
			slotAssignComplete:FireClient(plr, table.concat(baseList, ","), table.concat(defList, ","))
		end
	end
end)

-- SET FAVORITE (sole handler)
setFavorite.OnServerEvent:Connect(function(plr, uid)
	if plr:GetAttribute("InBadlands") then return end
	local d = PlayerDataManager.GetData(plr)
	if not d then return end
	if MountSystem and MountSystem.IsMounted and MountSystem.IsMounted(plr) then
		MountSystem.Dismount(plr, false)
	end
	if uid == nil or uid == "" then
		PlayerDataManager.ClearFavorite(plr)
		if FavoriteCreatureSystem then FavoriteCreatureSystem.DespawnCompanion(plr) end
	else
		PlayerDataManager.SetFavorite(plr, uid)
		if FavoriteCreatureSystem then
			FavoriteCreatureSystem.DespawnCompanion(plr)
			-- Delay spawn so client summon card animation can play first (card grows from body, then creature appears)
			task.delay(1.05, function()
				if plr and plr.Parent and PlayerDataManager.GetData(plr) and PlayerDataManager.GetFavorite(plr) then
					FavoriteCreatureSystem.SpawnCompanion(plr)
				end
			end)
		end
		-- Remove only this creature's orb from its point (defense/income/battle) - no full respawn
		if BasePlacementSystem and BasePlacementSystem.ClearOrbByUid then
			BasePlacementSystem.ClearOrbByUid(plr, uid)
		end
	end
	-- Notify client of current slot state so UI shows Inc/Def again (SetFavorite removes from slots via removeFromAllSlots)
	if slotAssignComplete then
		local data = PlayerDataManager.GetData(plr)
		local incomeMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(plr, "income") or 6
		local defenseMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(plr, "defense") or 6
		local baseList, defList = {}, {}
		if data and data.baseSlots then for i = 1, incomeMax do local v = data.baseSlots[i] or data.baseSlots[tostring(i)]; if v and v ~= "" then table.insert(baseList, tostring(v)) end end end
		if data and data.defenseSlots then for i = 1, defenseMax do local v = data.defenseSlots[i] or data.defenseSlots[tostring(i)]; if v and v ~= "" then table.insert(defList, tostring(v)) end end end
		slotAssignComplete:FireClient(plr, table.concat(baseList, ","), table.concat(defList, ","))
	end
	setupPlotForPlayer(plr)
end)

-- FIX #17: RECALL COMPANION (Y / ReCard button). Despawn companion model, keep favoriteUid.
-- Client fires this when companion is summoned and user presses Y or clicks the ReCard card button.
-- Unlike setFavorite(""), this does NOT clear favoriteUid — creature stays as favorite, just recalled.
recallCompanion.OnServerEvent:Connect(function(plr)
	if plr:GetAttribute("InBadlands") then return end
	local d = PlayerDataManager.GetData(plr)
	if not d or not d.favoriteUid then return end  -- no favorite, nothing to recall
	if not FavoriteCreatureSystem then return end
	-- Get companion position for card-fly animation before destroying
	local creatureId = nil
	for _, e in ipairs(d.inventory) do
		if tostring(e.uid) == tostring(d.favoriteUid) then creatureId = e.id; break end
	end
	local creaturePos = FavoriteCreatureSystem.GetCompanionPosition(plr)
	-- Fire CompanionRecalled so client plays the card-fly-to-player animation
	local recalledEvt = eventsFolder:FindFirstChild("CompanionRecalled")
	if recalledEvt and creaturePos then
		recalledEvt:FireClient(plr, creaturePos, creatureId)
	end
	-- Despawn the model but do NOT clear favoriteUid
	FavoriteCreatureSystem.DespawnCompanion(plr)
end)

-- FIX #17: SUMMON COMPANION (Y / Summon button). Spawn companion model for existing favorite.
-- Client fires this when creature is favorite but companion is not in the world (recalled/carded).
summonCompanion.OnServerEvent:Connect(function(plr)
	if plr:GetAttribute("InBadlands") then return end
	local d = PlayerDataManager.GetData(plr)
	if not d or not d.favoriteUid then return end  -- no favorite, nothing to summon
	if not FavoriteCreatureSystem then return end
	-- Don't double-spawn if already out
	if FavoriteCreatureSystem.HasCompanion(plr) then return end
	-- Delay spawn so client summon card animation can play first
	task.delay(1.05, function()
		if plr and plr.Parent and PlayerDataManager.GetData(plr) and PlayerDataManager.GetFavorite(plr) then
			FavoriteCreatureSystem.SpawnCompanion(plr)
		end
	end)
end)

-- ASSIGN TO BATTLE (requires Floor 2) - battle team only
-- Battle team is set in the battle menu. Use refreshPlayerBase so base battlepoints display updates.
assignToBattle.OnServerEvent:Connect(function(plr, uid, slotIndex)
	if not PlayerDataManager.OwnsFloor(plr, 2) then
		warn("[MainServer] " .. plr.Name .. " tried battle without Floor 2")
		return
	end
	local success, msg = PlayerDataManager.AssignToBattle(plr, uid, slotIndex)
	if success then
		checkDespawnCompanion(plr)
		refreshPlayerBase(plr)
	else
		warn("[MainServer] AssignToBattle failed: " .. plr.Name .. " - " .. (msg or "?"))
	end
end)

-- TOGGLE BATTLE TEAM (enable/disable without clearing)
toggleBattleTeam.OnServerInvoke = function(plr)
	if not PlayerDataManager.OwnsFloor(plr, 2) then return nil end
	if not PlayerDataManager.ToggleBattleTeamEnabled then
		warn("[MainServer] ToggleBattleTeamEnabled missing - ensure PlayerDataManager.lua has the battle team toggle functions")
		return nil
	end
	local enabled = PlayerDataManager.ToggleBattleTeamEnabled(plr)
	if PlayerDataManager.SavePlayer then
		PlayerDataManager.SavePlayer(plr)  -- Persist immediately so state sticks
	end
	-- Toggle should be backend-only plus BattlePoint color feedback.
	-- Do not full-refresh base models (prevents flicker/disappear-reappear).
	if BasePlacementSystem and BasePlacementSystem.UpdateBattlePointVisualState then
		BasePlacementSystem.UpdateBattlePointVisualState(plr)
	end
	return enabled
end

-- REMOVE FROM BATTLE - battle team only
removeFromBattle.OnServerEvent:Connect(function(plr, uid)
	if PlayerDataManager.RemoveFromBattle(plr, uid) then
		refreshPlayerBase(plr)
	end
end)

-- TOGGLE COMPANION ATTACK MODE
toggleAttackMode.OnServerEvent:Connect(function(plr)
	if FavoriteCreatureSystem then
		local mode = FavoriteCreatureSystem.ToggleAttackMode(plr)
		print("[MainServer] " .. plr.Name .. " attack mode: " .. tostring(mode))
	end
end)

-- Resolve UniqueId (world) or UID (base) to a creature model so we get the rest of the data from there
local function findCreatureModelByUniqueId(targetId)
	if type(targetId) ~= "string" or #targetId == 0 then return nil end
	for _, tag in ipairs({ "WorldCreature", "BaseDefenseCreature", "BaseIncomeCreature" }) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			if model.Parent and (model:GetAttribute("UniqueId") == targetId or model:GetAttribute("UID") == targetId) then
				return model
			end
		end
	end
	return nil
end

-- SET COMPANION TARGET (client sends UniqueId or model; we resolve by id then get data from the model)
setCompanionTarget.OnServerEvent:Connect(function(plr, targetIdOrModel)
	if not FavoriteCreatureSystem then return end
	local creatureModel = type(targetIdOrModel) == "string" and findCreatureModelByUniqueId(targetIdOrModel) or (type(targetIdOrModel) == "userdata" and targetIdOrModel:IsA("Model") and targetIdOrModel or nil)
	FavoriteCreatureSystem.SetTarget(plr, creatureModel)
end)

-- CLEAR COMPANION TARGET
clearCompanionTarget.OnServerEvent:Connect(function(plr)
	if FavoriteCreatureSystem then
		FavoriteCreatureSystem.ClearTarget(plr)
	end
end)

-- SELECT STARTER (new players)
selectStarter.OnServerEvent:Connect(function(plr, starterId)
	local d = PlayerDataManager.GetData(plr)
	if not d then return end
	if #d.inventory > 0 then return end -- already has creatures

	local valid = false
	for _, sid in ipairs(CreatureData.Starters) do
		if sid == starterId then valid = true; break end
	end
	if not valid then return end

	local uid = PlayerDataManager.AddCreature(plr, starterId, nil, nil, nil, nil, { source = "starter" })
	if uid then
		PlayerDataManager.SetFavorite(plr, uid)
		if FavoriteCreatureSystem then
			task.delay(1, function() FavoriteCreatureSystem.SpawnCompanion(plr) end)
		end
		print("[MainServer] " .. plr.Name .. " chose starter: " .. starterId)
	end
end)

-- SELECT PLOT (no-op - plots are now auto-assigned on join)
selectPlot.OnServerInvoke = function(plr, plotId)
	local d = PlayerDataManager.GetData(plr)
	if not d then return false, "No data" end
	-- Plot already auto-assigned, just return current assignment
	return true, "Plot " .. (d.plotId or 0) .. " assigned!"
end

-- ── FRIENDS LIST (laser door access) ──

local addBaseFriend = eventsFolder:FindFirstChild("AddBaseFriend")
local removeBaseFriend = eventsFolder:FindFirstChild("RemoveBaseFriend")
local getFriendsListEvt = eventsFolder:FindFirstChild("GetFriendsList")

if addBaseFriend then
	addBaseFriend.OnServerEvent:Connect(function(plr, friendUserId)
		if typeof(friendUserId) ~= "number" then return end
		local friends = PlayerDataManager.GetFriendsList(plr)
		if #friends >= (GameConfig.LaserDoorMaxFriends or 10) then return end
		PlayerDataManager.AddFriend(plr, friendUserId)
	end)
end

if removeBaseFriend then
	removeBaseFriend.OnServerEvent:Connect(function(plr, friendUserId)
		if typeof(friendUserId) ~= "number" then return end
		PlayerDataManager.RemoveFriend(plr, friendUserId)
	end)
end

if getFriendsListEvt then
	getFriendsListEvt.OnServerInvoke = function(plr)
		return PlayerDataManager.GetFriendsList(plr)
	end
end

-- ── BASE BUILDING: SELL, BUY FLOOR, GO HOME, PROFILE ──

sellCreature.OnServerInvoke = function(plr, uid)
	if not uid or typeof(uid) ~= "string" then return false, 0 end
	local slotIdx, slotType = nil, nil
	for _, st in ipairs({"income", "defense"}) do
		local idx = PlayerDataManager.GetSlotIndexForUid and PlayerDataManager.GetSlotIndexForUid(plr, st, uid)
		if idx then slotIdx, slotType = idx, st break end
	end
	local ok, coins = PlayerDataManager.SellCreature(plr, uid)
	if ok then
		if slotIdx and slotType and BasePlacementSystem and BasePlacementSystem.ClearCreatureAtSlot then
			BasePlacementSystem.ClearCreatureAtSlot(plr, slotType, slotIdx)
		elseif BasePlacementSystem then
			refreshPlayerBase(plr)
		end
		checkDespawnCompanion(plr)
		local coinsEvt = eventsFolder:FindFirstChild("CoinsUpdate")
		if coinsEvt then coinsEvt:FireClient(plr, PlayerDataManager.GetCoins(plr)) end
	end
	return ok, coins
end

inspectEgg.OnServerInvoke = function(plr, uid)
	if typeof(uid) ~= "string" or uid == "" then
		return false, "Invalid egg", nil
	end
	local ok, msg, egg = PlayerDataManager.InspectEgg(plr, uid)
	if ok then
		local gemsEvt = eventsFolder:FindFirstChild("GemsUpdate")
		if gemsEvt then gemsEvt:FireClient(plr, PlayerDataManager.GetGems(plr)) end
		if BasePlacementSystem then
			BasePlacementSystem.PlaceCreatures(plr)
		end
	end
	return ok, msg, egg and egg.creatureId or nil
end

-- ── BASE INTERACTION: Move / Swap creature slots ──
local MOVE_SLOT_DEBUG = false
local function moveSlotLog(plr, ...) if MOVE_SLOT_DEBUG then print("[MoveSlot]", plr and plr.Name or "?", ...) end end

moveCreatureSlot.OnServerInvoke = function(plr, slotType, uid, targetPointIndex)
	moveSlotLog(plr, "invoke: slotType=" .. tostring(slotType), "uid=" .. tostring(uid), "targetPointIndex=" .. tostring(targetPointIndex))
	if not BasePlacementSystem then moveSlotLog(plr, "fail: Base placement not loaded"); return false, "Base placement not loaded" end
	if not slotType or (slotType ~= "income" and slotType ~= "defense") then moveSlotLog(plr, "fail: Invalid slot type"); return false, "Invalid slot type" end
	if not uid or typeof(uid) ~= "string" then moveSlotLog(plr, "fail: Invalid UID type=" .. typeof(uid)); return false, "Invalid UID" end
	if type(targetPointIndex) ~= "number" then moveSlotLog(plr, "fail: Invalid target type=" .. type(targetPointIndex)); return false, "Invalid target" end
	-- Resolve the target point index to a slot array index
	local targetSlotIndex = BasePlacementSystem.GetSlotIndexForPoint(plr, slotType, targetPointIndex)
	if not targetSlotIndex then moveSlotLog(plr, "fail: GetSlotIndexForPoint returned nil for pointIndex=" .. tostring(targetPointIndex)); return false, "Invalid point" end
	-- Get the current slot index for visual clear
	local fromSlotIndex = PlayerDataManager.GetSlotIndexForUid(plr, slotType, uid)
	if not fromSlotIndex then moveSlotLog(plr, "fail: Creature not in slot (GetSlotIndexForUid nil)"); return false, "Creature not in slot" end
	-- Move in data
	local ok, msg = PlayerDataManager.MoveSlotByUid(plr, slotType, uid, targetSlotIndex)
	moveSlotLog(plr, "MoveSlotByUid: ok=" .. tostring(ok), msg and ("msg=" .. tostring(msg)) or "", "fromSlot=" .. tostring(fromSlotIndex), "targetSlot=" .. tostring(targetSlotIndex))
	if ok then
		-- Clear old visual and spawn at new position
		BasePlacementSystem.ClearCreatureAtSlot(plr, slotType, fromSlotIndex)
		-- ClearCreatureAtSlot also calls ClearSlotAt (which sets slot to ""), but we already moved
		-- the data, so the slot is already "" at fromSlotIndex. Re-set the target in case ClearSlotAt
		-- wiped it (it shouldn't since we moved, but be safe):
		local d = PlayerDataManager.GetData(plr)
		if d then
			local slots = (slotType == "income") and d.baseSlots or d.defenseSlots
			if slots then slots[targetSlotIndex] = uid end
		end
		local placeOk = BasePlacementSystem.PlaceCreatureInSlot(plr, slotType, targetSlotIndex, uid)
		moveSlotLog(plr, "PlaceCreatureInSlot result:", placeOk and "ok" or "nil")
	end
	return ok, msg or "Moved"
end

swapCreatureSlots.OnServerInvoke = function(plr, slotType, uidA, uidB)
	if not slotType or (slotType ~= "income" and slotType ~= "defense") then return false, "Invalid slot type" end
	if not uidA or typeof(uidA) ~= "string" then return false, "Invalid UID A" end
	if not uidB or typeof(uidB) ~= "string" then return false, "Invalid UID B" end
	-- Swap in data
	local ok, indexA, indexB = PlayerDataManager.SwapSlotsByUid(plr, slotType, uidA, uidB)
	if ok then
		-- Clear both visuals, then re-place both at swapped positions
		-- Use the internal clearCreatureAtSlot via ClearCreatureAtSlot (which also calls ClearSlotAt).
		-- Since SwapSlotsByUid already set the correct data, we need to preserve it after clear.
		-- Save the data, clear visuals, restore data, re-place.
		local d = PlayerDataManager.GetData(plr)
		local slots = (slotType == "income") and d.baseSlots or d.defenseSlots
		-- ClearCreatureAtSlot will set slots to "", so save & restore
		local savedA, savedB = slots[indexA], slots[indexB]
		BasePlacementSystem.ClearCreatureAtSlot(plr, slotType, indexA)
		BasePlacementSystem.ClearCreatureAtSlot(plr, slotType, indexB)
		slots[indexA] = savedA
		slots[indexB] = savedB
		BasePlacementSystem.PlaceCreatureInSlot(plr, slotType, indexA, savedA)
		BasePlacementSystem.PlaceCreatureInSlot(plr, slotType, indexB, savedB)
	end
	return ok, ok and "Swapped" or "Failed"
end

buyFloor.OnServerInvoke = function(plr, floorNum)
	-- FIX: Accept floor 4 (Siegelord Arena) alongside floors 2 and 3
	if type(floorNum) ~= "number" or (floorNum ~= 2 and floorNum ~= 3 and floorNum ~= 4) then
		return false, "Invalid floor"
	end
	local ok, msg = PlayerDataManager.BuyFloor(plr, floorNum)
	if ok then
		-- FIX: Use incremental ActivateFloor instead of refreshPlayerBase.
		-- This only makes the new floor visible and places creatures on its new
		-- points WITHOUT clearing/respawning models on already-owned floors.
		if BasePlacementSystem and BasePlacementSystem.ActivateFloor then
			task.spawn(function() BasePlacementSystem.ActivateFloor(plr, floorNum) end)
		end
		setupPlotForPlayer(plr)

		-- Recreate dome if LaserDoorSystem exists (so it scales to new floor height)
		local d = PlayerDataManager.GetData(plr)
		local pm = nil
		if d and d.plotId and d.plotId > 0 then
			local plotsFolder = workspace:FindFirstChild("BasePlots")
			if plotsFolder then
				pm = plotsFolder:FindFirstChild("Plot" .. d.plotId)
					or plotsFolder:FindFirstChild("Part" .. d.plotId)
			end
		end
		if pm and LaserDoorSystem and LaserDoorSystem.CreateForPlot then
			LaserDoorSystem.CreateForPlot(pm, plr)
		end

		-- Floor 4: set up gym arena prompt and decor points
		if floorNum == 4 and pm then
			if GymBattleSystem and GymBattleSystem.SetupPlot then
				pcall(function() GymBattleSystem.SetupPlot(pm) end)
			end
			if DecorSystem and DecorSystem.PlaceAllDecor then
				pcall(function() DecorSystem.PlaceAllDecor(plr) end)
			end
		end

		local coinsEvt = eventsFolder:FindFirstChild("CoinsUpdate")
		if coinsEvt then coinsEvt:FireClient(plr, PlayerDataManager.GetCoins(plr)) end
	end
	return ok, msg
end

goHome.OnServerEvent:Connect(function(plr)
	startHomeRecall(plr)
end)

getProfile.OnServerInvoke = function(plr)
	local d = PlayerDataManager.GetData(plr)
	if not d then return nil end
	local lvl, xp, needed = PlayerDataManager.GetPlayerLevel(plr)
	return {
		playerLevel = lvl, playerXP = xp, xpNeeded = needed,
		coins = d.coins, gems = d.gems or 0,
		ownedFloors = d.ownedFloors or {1},
		stats = d.stats, monstersOwned = #d.inventory,
		totalCaptured = d.stats.totalCaptured or 0,
		arenaWins = d.stats.arenaWins or 0,
		arenaMaxStreak = d.stats.arenaMaxStreak or 0,
		totalIncome = d.stats.totalIncome or 0,
		rebirthLevel = PlayerDataManager.GetRebirthLevel(plr),
	}
end

-- Pilot Rebirth: get full info for UI (requirements, progress, what you lose/keep)
getRebirthInfo.OnServerInvoke = function(plr)
	local d = PlayerDataManager.GetData(plr)
	if not d then return nil end
	local rebirthLevel = PlayerDataManager.GetRebirthLevel(plr)
	local nextReq = PlayerDataManager.GetRebirthRequirements(rebirthLevel)
	local canRebirth, errMsg = PlayerDataManager.CanRebirth(plr)
	local counts = PlayerDataManager.CountCreaturesByRarity(plr)
	-- What you keep: favorite creature (if equipped)
	local keepFavorite = nil
	if d.favoriteUid then
		local entry = PlayerDataManager.GetCreatureByUid(plr, d.favoriteUid)
		if entry then
			local info = CreatureData.GetById(entry.id)
			keepFavorite = { uid = d.favoriteUid, name = (info and info.displayName) or entry.id, rarity = (info and info.rarity) or "Common" }
		end
	end
	-- What you lose: all creatures except favorite (base + battle team + rest of inventory)
	local baseCount = 0
	for i = 1, 18 do
		if d.baseSlots and d.baseSlots[i] and d.baseSlots[i] ~= "" then baseCount = baseCount + 1 end
	end
	local defenseCount = 0
	for i = 1, 18 do
		if d.defenseSlots and d.defenseSlots[i] and d.defenseSlots[i] ~= "" then defenseCount = defenseCount + 1 end
	end
	local battleCount = 0
	for _, uid in pairs(d.battleTeam or {}) do if uid and uid ~= "" then battleCount = battleCount + 1 end end
	local totalCreatures = #d.inventory
	local loseCount = totalCreatures - (keepFavorite and 1 or 0)
	local teamProgress = nil
	if nextReq and nextReq.team and type(nextReq.team) == "table" and #nextReq.team > 0 then
		teamProgress = PlayerDataManager.GetRebirthTeamProgress(plr, nextReq.team)
	end
	return {
		rebirthLevel = rebirthLevel,
		nextRequirements = nextReq,
		canRebirth = canRebirth,
		errorMessage = errMsg,
		creatureCountsByRarity = counts,
		teamProgress = teamProgress,
		keepFavorite = keepFavorite,
		loseCreaturesCount = loseCount,
		loseBaseCount = baseCount,
		loseDefenseCount = defenseCount,
		loseBattleCount = battleCount,
		bonuses = PlayerDataManager.GetRebirthBonuses(plr),
		nextBonuses = nextReq and PlayerDataManager.GetRebirthBonusesForLevel and PlayerDataManager.GetRebirthBonusesForLevel(rebirthLevel + 1) or nil,
		coins = d.coins,
	}
end

requestRebirth.OnServerEvent:Connect(function(plr)
	local canRebirth, errMsg = PlayerDataManager.CanRebirth(plr)
	if not canRebirth then
		local evt = eventsFolder:FindFirstChild("RebirthFailed")
		if evt then evt:FireClient(plr, errMsg or "Cannot rebirth") end
		return
	end
	local ok, err = PlayerDataManager.DoRebirth(plr)
	if not ok then
		local evt = eventsFolder:FindFirstChild("RebirthFailed")
		if evt then evt:FireClient(plr, err or "Rebirth failed") end
		return
	end
	-- Refresh base (clear placed creatures from world)
	if BasePlacementSystem then
		task.spawn(function() BasePlacementSystem.PlaceCreatures(plr) end)
	end
	setupPlotForPlayer(plr)
	-- Despawn companion so it can be re-shown with same favorite
	if FavoriteCreatureSystem then
		FavoriteCreatureSystem.DespawnCompanion(plr)
		local d = PlayerDataManager.GetData(plr)
		if d and d.favoriteUid then
			FavoriteCreatureSystem.SpawnCompanion(plr)
		end
	end
	local newLevel = PlayerDataManager.GetRebirthLevel(plr)
	local bonuses = PlayerDataManager.GetRebirthBonuses(plr)
	local evt = eventsFolder:FindFirstChild("RebirthSuccess")
	if evt then evt:FireClient(plr, newLevel, bonuses) end
end)
print("--------------------------------------")
print("   MONSTER SIEGE - Server Ready!")
print("--------------------------------------")
