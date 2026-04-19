-- Last updated: 2026-03-21 00:34
-- CaptureSystem.lua - ServerScriptService (ModuleScript)
-- Capture fainted creatures for a gold cost based on rarity.
-- After capture, sends slot availability so client can prompt for assignment.
-- Also handles AssignCaptured event for immediate slot assignment.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CaptureCostUtil = require(ReplicatedStorage.Modules.CaptureCostUtil)

local PlayerDataManager
local CreatureSpawner
local CreatureAI
local BasePlacementSystem

local CaptureSystem = {}
local DEBUG_CAPTURE_LOGS = false

local CREATURE_TAG = "WorldCreature"
local captureCooldowns = {}
local capturesInProgress = {}

local badlandsSystemCache = nil

local function getBadlandsSystem()
	if badlandsSystemCache then
		return badlandsSystemCache
	end

	local mod = ServerScriptService:FindFirstChild("BadlandsSystem")
	if not mod then
		return nil
	end

	local ok, result = pcall(require, mod)
	if ok then
		badlandsSystemCache = result
		return result
	end

	warn("[CaptureSystem] Failed to require BadlandsSystem: " .. tostring(result))
	return nil
end

-- Distance from a point to the closest point on the model's bounding box (so tall creatures can be captured from underneath).
local function getDistanceToModel(point, creatureModel)
	local cf, size = creatureModel:GetBoundingBox()
	local half = size * 0.5
	local localP = cf:PointToObjectSpace(point)
	local closestLocal = Vector3.new(
		math.clamp(localP.X, -half.X, half.X),
		math.clamp(localP.Y, -half.Y, half.Y),
		math.clamp(localP.Z, -half.Z, half.Z)
	)
	local closestWorld = cf:PointToWorldSpace(closestLocal)
	return (point - closestWorld).Magnitude
end

local function isInRange(player, creatureModel)
	local character = player.Character
	if not character then return false end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local dist = getDistanceToModel(root.Position, creatureModel)
	return dist <= GameConfig.CaptureRange
end

local function isOnCooldown(player)
	local last = captureCooldowns[player.UserId]
	if not last then return false end
	return (tick() - last) < GameConfig.CaptureCooldown
end

function CaptureSystem.TryCapture(player, creatureModel)
	local existing = capturesInProgress[creatureModel]
	local samePlayer = existing and existing == player
	if DEBUG_CAPTURE_LOGS then
		print(string.format("[DEBUG-CAPTURE] TryCapture player=%s model=%s capturesInProgress=%s samePlayer=%s", player.Name, tostring(creatureModel), tostring(existing and existing.Name or "nil"), tostring(samePlayer)))
	end
	if not creatureModel or not creatureModel.Parent then
		return false, "Creature no longer exists"
	end
	if not CollectionService:HasTag(creatureModel, CREATURE_TAG) then
		return false, "Invalid target"
	end
	if capturesInProgress[creatureModel] then
		if DEBUG_CAPTURE_LOGS then
			print(string.format("[DEBUG-CAPTURE] TryCapture REJECT alreadyCapturing by=%s requester=%s", tostring(existing and existing.Name), player.Name))
		end
		return false, "Someone else is capturing this"
	end
	if isOnCooldown(player) then
		return false, "Capture on cooldown"
	end
	if not isInRange(player, creatureModel) then
		return false, "Too far away"
	end

	local isFainted = creatureModel:GetAttribute("Fainted")
	if not isFainted then
		return false, "Must defeat creature first! Use your companion to faint it."
	end

	-- Any capture while in The Badlands uses the run bag (not main inventory / income UI).
	local isBadlandsCapture = player:GetAttribute("InBadlands") == true

	if isBadlandsCapture and player:GetAttribute("BadlandsLoading") then
		return false, "Still loading into The Badlands..."
	end

	local creatureId = creatureModel:GetAttribute("CreatureId")
	if not creatureId and CreatureSpawner and CreatureSpawner.GetCreatureId then
		creatureId = CreatureSpawner.GetCreatureId(creatureModel)
	end
	if not creatureId then return false, "Unknown creature" end
	local creatureInfo = CreatureData.GetById(creatureId)
	if not creatureInfo then return false, "Invalid creature data" end
	if CreatureData.IsNpcOnly and CreatureData.IsNpcOnly(creatureInfo) then
		return false, "Eleminions cannot be captured."
	end

	local data = nil
	if not isBadlandsCapture then
		data = PlayerDataManager.GetData(player)
		if not data then return false, "Player data not loaded" end
		if #data.inventory >= GameConfig.MaxInventorySize then
			return false, "Inventory full"
		end
	end

	local cost = 0
	if not isBadlandsCapture then
		cost = CreatureData.GetCaptureCost(creatureId)
		local decorBonus = PlayerDataManager.GetDecorStatueBonusMap and PlayerDataManager.GetDecorStatueBonusMap(player) or {}
		cost = CaptureCostUtil.ApplyDecorStatueDiscount(cost, creatureId, decorBonus)
		if PlayerDataManager.HasBuff and PlayerDataManager.HasBuff(player, "lucky") then
			cost = math.floor(cost * 0.75)
		end
		if data.coins < cost then
			return false, "Need " .. cost .. " gold (you have " .. data.coins .. ")"
		end
	end

	capturesInProgress[creatureModel] = player
	captureCooldowns[player.UserId] = tick()

	local holdTime = GameConfig.CaptureAnimationTime or GameConfig.CaptureHoldTime or 2.5
	if not isBadlandsCapture and PlayerDataManager.GetDecorStatueBonusMap then
		local decorBonus = PlayerDataManager.GetDecorStatueBonusMap(player)
		holdTime = CaptureCostUtil.ApplyDecorStatueHoldMultiplier(holdTime, creatureId, decorBonus)
	end
	local events = ReplicatedStorage:FindFirstChild("Events")
	local captureSessionId = HttpService:GenerateGUID(false)

	if holdTime > 0 then
		local startEvent = events and events:FindFirstChild("CaptureStart")
		if startEvent then
			startEvent:FireClient(player, creatureModel, holdTime, captureSessionId)
		end

		task.wait(holdTime)

		if not creatureModel or not creatureModel.Parent then
			capturesInProgress[creatureModel] = nil
			return false, "Creature vanished"
		end

		-- Grace period: if out of range, notify and count down from 3; if they re-enter, continue.
		local gracePeriod = GameConfig.CaptureGracePeriod or 3
		while not isInRange(player, creatureModel) do
			local warnEvent = events and events:FindFirstChild("CaptureOutOfRange")
			if warnEvent then
				-- Pass creatureModel so client can position dome and card
				warnEvent:FireClient(player, gracePeriod, creatureModel)
			end
			task.wait(1)
			gracePeriod = gracePeriod - 1
			if not creatureModel or not creatureModel.Parent then
				capturesInProgress[creatureModel] = nil
				return false, "Creature vanished"
			end
			if gracePeriod <= 0 then
				capturesInProgress[creatureModel] = nil
				return false, "Lost the capture! Return to the creature before the countdown ends."
			end
		end
	end

	if isBadlandsCapture then
		local badlandsSystem = getBadlandsSystem()
		if not badlandsSystem or not badlandsSystem.CaptureCreatureToBag then
			capturesInProgress[creatureModel] = nil
			return false, "Badlands bag system unavailable"
		end

		local ok, msg, bagInfo = badlandsSystem.CaptureCreatureToBag(player, creatureModel)
		capturesInProgress[creatureModel] = nil
		if not ok then
			return false, msg or "Badlands capture failed"
		end

		local successEvent = events and events:FindFirstChild("CaptureSuccess")
		if successEvent then
			local bid = (bagInfo and bagInfo.creatureId) or creatureId
			successEvent:FireClient(player, bid, bagInfo and bagInfo.uid or "", 0, {
				badlands = true,
				badlandsPending = bagInfo and bagInfo.badlandsPending == true,
				bagFull = bagInfo and bagInfo.bagFull == true,
				bagCount = bagInfo and bagInfo.bagCount or 0,
				bagMax = bagInfo and bagInfo.bagMax or 0,
				bag = bagInfo and bagInfo.bag,
				activeSlot = bagInfo and bagInfo.activeIndex or nil,
			}, captureSessionId)
		end

		return true, msg or "Captured!"
	end

	-- Check if this was a leveled creature (freed from a base by AI raid)
	local captureLevel = creatureModel:GetAttribute("CreatureLevel") or 1
	local captureXP = creatureModel:GetAttribute("CreatureXP") or 0
	-- Night spawns can have Silver/Gold variant (set by CreatureSpawner)
	local captureVariant = creatureModel:GetAttribute("Variant")
	if captureVariant ~= "Silver" and captureVariant ~= "Gold" then
		captureVariant = nil  -- Use default "Normal"
	end
	-- Use the world creature's unique id so this instance is preserved in the database
	local worldCreatureUid = creatureModel:GetAttribute("UniqueId")

	PlayerDataManager.SpendCoins(player, cost)

	local uid = PlayerDataManager.AddCreature(player, creatureId, captureLevel, captureXP, captureVariant, worldCreatureUid, {
		source = "capture",
	})
	if not uid then
		capturesInProgress[creatureModel] = nil
		return false, "Failed to add creature"
	end

	data.stats.totalCaptured = (data.stats.totalCaptured or 0) + 1

	-- Inner-zone elemental legendaries: grant SiegeSquire sigil stored under the element name
	-- (per GameConfig comment: "SiegeSquire sigil stored under that element name in player data").
	-- FIX: Previously stored under zoneId, which displayed on the wrong Sigils tab row and forced
	-- the OnPlayerJoin migration to move it each reload (causing sigils to appear to "disappear"
	-- from the Knight row after session). Store under element directly so persistence is stable.
	do
		local elementalElements = GameConfig.ElementalBossElements or { "Fire", "Ice", "Wind", "Earth" }
		for _, element in ipairs(elementalElements) do
			local bossId = CreatureData.GetBossCreatureId and CreatureData.GetBossCreatureId(element, false)
			if bossId and creatureId == bossId then
				local had = PlayerDataManager.HasSigil(player, element)
				PlayerDataManager.AddSigil(player, element)
				-- Persist immediately so an abrupt disconnect before auto-save does not lose the sigil.
				if PlayerDataManager.SavePlayer then
					pcall(function() PlayerDataManager.SavePlayer(player) end)
				end
				local sigilEvt = events and events:FindFirstChild("SigilEarned")
				if sigilEvt and not had then
					sigilEvt:FireClient(player, element)
				end
				break
			end
		end
	end

	-- Award capture XP to companion
	if data.favoriteUid then
		PlayerDataManager.AddXP(player, data.favoriteUid, GameConfig.CaptureXP)
	end

	-- Award player XP for capture
	if PlayerDataManager.AddPlayerXP then
		local newLvl, didLvl = PlayerDataManager.AddPlayerXP(player, GameConfig.PlayerXP_Capture or 15)
		if didLvl then
			local events = game.ReplicatedStorage:FindFirstChild("Events")
			local lvlEvt = events and events:FindFirstChild("PlayerLevelUp")
			if lvlEvt then lvlEvt:FireClient(player, newLvl) end
		end
	end

	CreatureSpawner.RemoveCreature(creatureModel)
	capturesInProgress[creatureModel] = nil

	-- Calculate slot availability for client prompt (dynamic based on owned floors)
	local incomeSlots = PlayerDataManager.GetFilledSlotCount and PlayerDataManager.GetFilledSlotCount(player, "income") or #(data.baseSlots or {})
	local defenseSlots = PlayerDataManager.GetFilledSlotCount and PlayerDataManager.GetFilledSlotCount(player, "defense") or #(data.defenseSlots or {})
	local incomeMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(player, "income") or GameConfig.MaxIncomeSlots
	local defenseMax = PlayerDataManager.GetMaxSlots and PlayerDataManager.GetMaxSlots(player, "defense") or GameConfig.MaxDefenseSlots
	local canIncome = incomeSlots < incomeMax
	local canDefense = defenseSlots < defenseMax

	local successEvent = events and events:FindFirstChild("CaptureSuccess")
	if successEvent then
		successEvent:FireClient(player, creatureId, uid, cost, {
			canIncome = canIncome,
			canDefense = canDefense,
			incomeSlots = incomeSlots,
			incomeMax = incomeMax,
			defenseSlots = defenseSlots,
			defenseMax = defenseMax,
			level = captureLevel,
		}, captureSessionId)
	end

	local coinsEvent = events and events:FindFirstChild("CoinsUpdate")
	if coinsEvent then
		coinsEvent:FireClient(player, PlayerDataManager.GetCoins(player))
	end

	local lvlStr = captureLevel > 1 and (" (Lv." .. captureLevel .. ")") or ""
	return true, "Captured!"
end

function CaptureSystem.Init(playerDataMgr, creatureSpawnerRef, creatureAIRef, basePlacementRef)
	PlayerDataManager = playerDataMgr
	CreatureSpawner = creatureSpawnerRef
	CreatureAI = creatureAIRef
	BasePlacementSystem = basePlacementRef

	local events = ReplicatedStorage:WaitForChild("Events", 30)
	if not events then warn("[CaptureSystem] Events folder not found!"); return end

	local captureRequest = events:WaitForChild("CaptureRequest", 15)

	if captureRequest then
		captureRequest.OnServerEvent:Connect(function(player, creatureModel)
			local success, msg = CaptureSystem.TryCapture(player, creatureModel)
			if not success then
				local existing = capturesInProgress[creatureModel]
				local isSamePlayerDuplicate = existing == player
				-- Don't fire CaptureFail when same player double-clicks: their first request is still in progress.
				-- Firing CaptureFail would destroy the card animation and show a misleading toast.
				if not isSamePlayerDuplicate then
					local failEvent = events:FindFirstChild("CaptureFail")
					if failEvent then failEvent:FireClient(player, msg) end
				end
			end
		end)
	end

	-- Handle post-capture assignment (income/defense)
	local assignCaptured = events:WaitForChild("AssignCaptured", 15)
	if assignCaptured then
		assignCaptured.OnServerEvent:Connect(function(player, uid, slotType)
			uid = tostring(uid or "")
			slotType = (slotType == "base") and "income" or tostring(slotType or "")
			if uid == "" or (slotType ~= "income" and slotType ~= "defense") then return end
			local data = PlayerDataManager.GetData(player)
			if not data then return end

			local success, slotIndex, added = false, nil, false
			if slotType == "income" then
				success, slotIndex, added = PlayerDataManager.AssignToBase(player, uid)
			elseif slotType == "defense" then
				success, slotIndex, added = PlayerDataManager.AssignToDefense(player, uid)
			end

			if success and added and BasePlacementSystem and BasePlacementSystem.PlaceCreatureInSlot and slotIndex then
				task.spawn(function()
					task.wait(0.2)
					BasePlacementSystem.PlaceCreatureInSlot(player, slotType, slotIndex, uid)
				end)
			elseif not success then
				local failEv = events:FindFirstChild("CaptureFail")
				if failEv then failEv:FireClient(player, "Could not assign to " .. slotType .. ". Slots may be full or creature not found.") end
			end
		end)
	else
		warn("[CaptureSystem] AssignCaptured event not found!")
	end

end

return CaptureSystem
