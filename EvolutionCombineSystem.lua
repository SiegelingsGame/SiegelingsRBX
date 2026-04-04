-- EvolutionCombineSystem.lua - ServerScriptService (ModuleScript)
-- Handles monster evolution (creature → next stage in chain) and combining (3 same variant → 1 next variant).
-- Evolution: one creature advances to its evolvesTo form (e.g. Firsky → Emberpup).
-- Combine: 3 of same creature + same variant tier become 1 of next tier (3 Normal → 1 Silver, 3 Silver → 1 Gold, 3 Gold → 1 Legend).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local EvolutionCombineSystem = {}

local EvolutionEffects = nil
pcall(function() EvolutionEffects = require(ServerScriptService.EvolutionEffects) end)
local BasePlacementSystem = nil
pcall(function() BasePlacementSystem = require(ServerScriptService.BasePlacementSystem) end)

local PlayerDataManager = nil
local FavoriteCreatureSystem = nil
local eventsFolder = nil

-- Remotes: EvolveCreature (client sends uid), CombineCreatures (client sends {uid1, uid2, uid3})
-- Server fires: EvolveResult(success, payload) where payload = newCreatureId or errorMessage
--               CombineResult(success, payload) where payload = newUid or errorMessage

local function getEvent(name)
	return eventsFolder and eventsFolder:FindFirstChild(name)
end

local function bindHandlers()
	local evolveEvent = getEvent("EvolveCreature")
	local combineEvent = getEvent("CombineCreatures")
	local evolveResult = getEvent("EvolveResult")
	local combineResult = getEvent("CombineResult")

	if evolveEvent and evolveResult then
		evolveEvent.OnServerEvent:Connect(function(player, uid)
			if not player or not PlayerDataManager.GetData(player) then return end
			if type(uid) ~= "string" or uid == "" then
				evolveResult:FireClient(player, false, "Invalid creature")
				return
			end
			local ok, err = PlayerDataManager.EvolveCreature(player, uid)
			if ok then
				-- Play evolution effect at companion or player position
				local pos = nil
				if FavoriteCreatureSystem then
					local d = PlayerDataManager.GetData(player)
					if d and d.favoriteUid and tostring(d.favoriteUid) == tostring(uid) and FavoriteCreatureSystem.HasCompanion(player) then
						pos = FavoriteCreatureSystem.GetCompanionPosition(player)
					end
				end
				if not pos and player.Character then
					local root = player.Character:FindFirstChild("HumanoidRootPart")
					if root then pos = root.Position end
				end
				if pos and EvolutionEffects and EvolutionEffects.PlayEvolutionEffect then
					EvolutionEffects.PlayEvolutionEffect(pos)
				end
				local entry = PlayerDataManager.GetCreatureByUid(player, uid)
				evolveResult:FireClient(player, true, entry and entry.id or nil)
				-- If the evolved creature was the player's favorite, refresh companion so the model updates
				local d = PlayerDataManager.GetData(player)
				if d and d.favoriteUid and tostring(d.favoriteUid) == tostring(uid) and FavoriteCreatureSystem then
					FavoriteCreatureSystem.DespawnCompanion(player)
					FavoriteCreatureSystem.SpawnCompanion(player)
				end
				-- If the evolved creature is on defense/income/battle, refresh the orb model
				if BasePlacementSystem and BasePlacementSystem.RefreshOrbByUid then
					BasePlacementSystem.RefreshOrbByUid(player, uid)
				end
			else
				evolveResult:FireClient(player, false, err or "Evolution failed")
			end
		end)
	end

	if combineEvent and combineResult then
		combineEvent.OnServerEvent:Connect(function(player, uids)
			if not player or not PlayerDataManager.GetData(player) then
				warn("[EvolutionCombine] CombineCreatures: no player or no data")
				return
			end
			if type(uids) ~= "table" then
				combineResult:FireClient(player, false, "Invalid selection")
				return
			end
			local newUid, err = PlayerDataManager.CombineCreatures(player, uids)
			if newUid then
				combineResult:FireClient(player, true, newUid)
			else
				combineResult:FireClient(player, false, err or "Combine failed")
			end
		end)
	end
end

function EvolutionCombineSystem.Init(playerDataManager, favoriteCreatureSys)
	PlayerDataManager = playerDataManager
	FavoriteCreatureSystem = favoriteCreatureSys
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then return end
	bindHandlers()
end

return EvolutionCombineSystem
