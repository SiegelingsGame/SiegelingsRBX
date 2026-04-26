-- EleminionSystem.lua - ServerScriptService (ModuleScript)
-- Spawns Eleminion NPCs at biome EPoints / EleminionPoints and handles affinity quest progress.
-- Last updated: 2026-04-25 00:22

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)
local EleminionData = require(ReplicatedStorage.Modules.EleminionData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local EleminionSystem = {}

local PlayerDataManager
local eventsFolder
local statusUpdateEvent
local openUiEvent
local showNotificationEvent
local coinsUpdateEvent
local gemsUpdateEvent
local playerXpEvent
local playerLevelEvent

local eleminionNpcs = {}
local eleminionNpcStates = {}
local promptConnections = {}
local warnedMissingPoints = {}

-- ══════════════════════════════════════════════════════════════════════════
-- MULTI-ELEMINION BIOME ASSIGNMENT
-- Some biomes host TWO Eleminions (see CreatureData.OuterBiomePrimarySecondary):
--   OceanBiome    = Water (primary) + Poison (secondary)
--   CaveBiome     = Shadow (primary) + Metal (secondary)
--   ElectricBiome = Lightning (primary) + Light (secondary)
--   DesertBiome   = Psychic (primary) + Undead (secondary)
-- Without coordination, both defs would score the same EPoint highest and
-- both NPCs would overlap at the same part — looking like only one spawned.
-- Two mechanisms keep them distinct:
--   1. Claim system (npcSpawnPoints): once a def picks a point, other defs
--      skip that exact point so each NPC gets its own location.
--   2. Primary/secondary suffix bias: secondary elements prefer points whose
--      names end in "2" (EPoint2, EleminionPoint2) matching the same
--      SpawnPoint / SpawnPoint2 convention used by outer dual biomes.
-- ══════════════════════════════════════════════════════════════════════════
local npcSpawnPoints = {}  -- [element] = BasePart currently hosting that Eleminion NPC

warn("[EleminionSystem] Module loaded")

local function normalizeName(value)
	return string.lower((tostring(value or "")):gsub("[%s%p_]+", ""))
end

local function scoreNameKey(nameKey, def)
	if not nameKey or nameKey == "" then
		return 0
	end

	local score = 0
	local elementKey = normalizeName(def.element)
	local npcKey = normalizeName(def.npcCreatureId)

	for _, hint in ipairs(def.pointHints or {}) do
		local hintKey = normalizeName(hint)
		if nameKey == hintKey then
			score += 140
		elseif nameKey:find(hintKey, 1, true) then
			score += 80
		end
	end

	if nameKey == "epoint" or nameKey == "eleminionpoint" then
		score += 60
	end
	if nameKey:find("eleminionpoint", 1, true) or nameKey:find("epoint", 1, true) then
		score += 40
	end
	if nameKey:find("eleminion", 1, true) then
		score += 28
	end
	if nameKey:find(elementKey, 1, true) then
		score += 18
	end
	if nameKey:find(npcKey, 1, true) then
		score += 24
	end

	return score
end

-- Returns "primary", "secondary", or nil for def.element based on
-- CreatureData.OuterBiomePrimarySecondary. Only dual-biome elements get a role.
local function getElementRoleInOuterBiome(element)
	local tbl = CreatureData.OuterBiomePrimarySecondary
	if type(tbl) ~= "table" then
		return nil
	end
	for _, pair in pairs(tbl) do
		if type(pair) == "table" then
			if pair[1] == element then
				return "primary"
			elseif pair[2] == element then
				return "secondary"
			end
		end
	end
	return nil
end

-- Point names matching the SpawnPoint2 convention (trailing "2", or an
-- explicit "secondary" marker) are reserved for the secondary Eleminion in a
-- dual-element biome.
local function hasSecondaryPointSuffix(nameKey)
	if not nameKey or nameKey == "" then
		return false
	end
	if nameKey:sub(-1) == "2" then
		return true
	end
	if nameKey:find("secondary", 1, true) then
		return true
	end
	return false
end

-- Biases the score of a point based on the def's role in an outer dual biome:
--   secondary def + "2"-suffix point      → strongly preferred
--   primary def   + "2"-suffix point      → strongly avoided
--   secondary def + plain (non-"2") point → mildly avoided so plain points go to primary
--   primary def   + plain point           → neutral
-- Non-dual-biome defs (Fire, Ice, Wind, Earth, ...) get no bias.
local function scoreSecondaryBias(nameKey, def)
	local role = getElementRoleInOuterBiome(def.element)
	if not role then
		return 0
	end
	local isSecondaryPoint = hasSecondaryPointSuffix(nameKey)
	if role == "secondary" then
		if isSecondaryPoint then
			return 55
		else
			return -20
		end
	else -- primary
		if isSecondaryPoint then
			return -55
		else
			return 0
		end
	end
end

local function scoreAttributes(instance, def)
	if not instance then
		return 0
	end

	local score = 0
	local elementKey = normalizeName(def.element)
	local npcKey = normalizeName(def.npcCreatureId)

	local attrElementNames = { "EleminionElement", "Element", "BiomeElement", "SpawnElement" }
	for _, attrName in ipairs(attrElementNames) do
		local attrValue = instance:GetAttribute(attrName)
		if type(attrValue) == "string" and normalizeName(attrValue) == elementKey then
			score += 200
			break
		end
	end

	local attrIdNames = { "EleminionId", "NpcCreatureId", "CreatureId", "NpcId" }
	for _, attrName in ipairs(attrIdNames) do
		local attrValue = instance:GetAttribute(attrName)
		if type(attrValue) == "string" and normalizeName(attrValue) == npcKey then
			score += 220
			break
		end
	end

	local pointTypeNames = { "PointType", "SpawnType", "MarkerType" }
	for _, attrName in ipairs(pointTypeNames) do
		local attrValue = instance:GetAttribute(attrName)
		if type(attrValue) == "string" then
			local key = normalizeName(attrValue)
			if key == "eleminion" or key == "epoint" or key == "eleminionpoint" then
				score += 90
				break
			end
		end
	end

	return score
end

local function getElementColor(element)
	local def = CreatureData.Elements[element]
	return (def and def.color) or Color3.fromRGB(220, 220, 220)
end

local function isEnabled()
	return GameConfig.EleminionsEnabled ~= false
end

local function getPromptRange()
	local cfg = GameConfig.Eleminion
	return (type(cfg) == "table" and tonumber(cfg.PromptRange)) or 14
end

local function getNpcGroundOffset()
	local cfg = GameConfig.Eleminion
	return (type(cfg) == "table" and tonumber(cfg.GroundOffsetStuds)) or 0.2
end

local function getAttentionRange()
	local cfg = GameConfig.Eleminion
	return (type(cfg) == "table" and tonumber(cfg.AttentionRange)) or 50
end

local function getFacingUpdateInterval()
	local cfg = GameConfig.Eleminion
	return (type(cfg) == "table" and tonumber(cfg.FacingUpdateInterval)) or 0.15
end

local function notify(player, message, level)
	if showNotificationEvent and player and message and message ~= "" then
		showNotificationEvent:FireClient(player, message, level or "info")
	end
end

local function disconnectPromptForModel(model)
	if not model then
		return
	end
	for prompt, connection in pairs(promptConnections) do
		if prompt == nil or prompt.Parent == nil or prompt:IsDescendantOf(model) then
			if connection then
				connection:Disconnect()
			end
			promptConnections[prompt] = nil
		end
	end
end

local function getCharacterRoot(player)
	if not player then
		return nil
	end
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function getNearestPlayerRoot(origin, maxDistance)
	local nearestRoot
	local nearestDistance = maxDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local root = getCharacterRoot(player)
		if root then
			local flat = (root.Position - origin) * Vector3.new(1, 0, 1)
			local distance = flat.Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestRoot = root
			end
		end
	end
	return nearestRoot, nearestDistance
end

local function getPreferredTargetRoot(npcState, origin)
	if not npcState then
		return nil
	end

	local maxDistance = npcState.attentionRange or getAttentionRange()
	local lastInteractorUserId = npcState.lastInteractorUserId
	if typeof(lastInteractorUserId) == "number" then
		local preferredPlayer = Players:GetPlayerByUserId(lastInteractorUserId)
		local preferredRoot = getCharacterRoot(preferredPlayer)
		if preferredRoot then
			local flat = (preferredRoot.Position - origin) * Vector3.new(1, 0, 1)
			if flat.Magnitude <= maxDistance then
				return preferredRoot
			end
		end
	end

	return getNearestPlayerRoot(origin, maxDistance)
end

local function applyFacingPivot(npcState, pivot)
	if not npcState or not npcState.model or not npcState.model.Parent or not pivot then
		return
	end

	local currentPivot = npcState.model:GetPivot()
	if (currentPivot.Position - pivot.Position).Magnitude <= 1e-3
		and currentPivot.LookVector:Dot(pivot.LookVector) > 0.999 then
		return
	end

	npcState.model:PivotTo(pivot)
end

local function updateNpcFacing(npcState)
	if not npcState or not npcState.model or not npcState.model.Parent then
		return
	end

	local currentPivot = npcState.model:GetPivot()
	local origin = currentPivot.Position
	local targetRoot = getPreferredTargetRoot(npcState, origin)
	if targetRoot then
		local flatDirection = (targetRoot.Position - origin) * Vector3.new(1, 0, 1)
		if flatDirection.Magnitude > 0.05 then
			local desiredPivot = CFrame.lookAt(origin, origin + flatDirection.Unit) * npcState.rotationOffset
			applyFacingPivot(npcState, desiredPivot)
			npcState.currentFacing = "player"
			return
		end
	end

	if npcState.currentFacing ~= "base" and npcState.basePivot then
		applyFacingPivot(npcState, npcState.basePivot)
		npcState.currentFacing = "base"
	end
end

local function updateAllNpcFacing()
	for element, npcState in pairs(eleminionNpcStates) do
		if not npcState or not npcState.model or not npcState.model.Parent then
			eleminionNpcStates[element] = nil
			eleminionNpcs[element] = nil
		else
			updateNpcFacing(npcState)
		end
	end
end

local function getOrCreateElementState(player, element)
	local data = PlayerDataManager and PlayerDataManager.GetData and PlayerDataManager.GetData(player)
	if not data then
		return nil, nil
	end
	if type(data.eleminions) ~= "table" then
		data.eleminions = {}
	end
	local state = data.eleminions[element]
	if type(state) ~= "table" then
		state = {
			affinity = 0,
			quests = {},
		}
		data.eleminions[element] = state
	end
	if type(state.affinity) ~= "number" then
		state.affinity = math.max(0, tonumber(state.affinity) or 0)
	end
	if type(state.quests) ~= "table" then
		state.quests = {}
	end
	if type(state.affinityPassClaims) ~= "table" then
		state.affinityPassClaims = {} -- [milestoneId] = true
	end
	return data, state
end

local function getOrCreateQuestState(state, questIndex)
	local questState = state.quests[questIndex]
	if type(questState) ~= "table" then
		questState = {
			claimed = false,
			completed = false,
			completedAt = nil,
			claimedAt = nil,
			objectives = {},
		}
		state.quests[questIndex] = questState
	end
	if type(questState.objectives) ~= "table" then
		questState.objectives = {}
	end
	return questState
end

local function getCurrentQuestIndex(def, state)
	for index = 1, #(def.quests or {}) do
		local questState = state and state.quests and state.quests[index]
		if not (questState and questState.claimed == true) then
			return index
		end
	end
	return nil
end

local function countOwnedCreatures(data, creatureId)
	local count = 0
	for _, entry in ipairs(data.inventory or {}) do
		if entry.id == creatureId then
			count += 1
		end
	end
	return count
end

local function getHighestOwnedLevel(data, creatureId)
	local best = 0
	for _, entry in ipairs(data.inventory or {}) do
		if entry.id == creatureId then
			best = math.max(best, tonumber(entry.level) or 1)
		end
	end
	return best
end

local function isObjectiveComplete(objective, progressValue)
	progressValue = tonumber(progressValue) or 0
	if objective.type == "capture" then
		return progressValue >= (tonumber(objective.amount) or 1)
	end
	if objective.type == "level" then
		return progressValue >= (tonumber(objective.targetLevel) or 1)
	end
	return false
end

local function finalizeQuestState(questDef, questState)
	local wasCompleted = questState.completed == true
	local completed = true
	for objectiveIndex, objective in ipairs(questDef.objectives or {}) do
		if not isObjectiveComplete(objective, questState.objectives[objectiveIndex]) then
			completed = false
			break
		end
	end
	questState.completed = completed
	if completed and not wasCompleted then
		questState.completedAt = os.time()
	end
	return wasCompleted, completed
end

local function syncActiveQuestProgress(player, element)
	local def = EleminionData.GetByElement(element)
	if not def then
		return nil
	end
	local data, state = getOrCreateElementState(player, element)
	if not data or not state then
		return nil
	end
	local questIndex = getCurrentQuestIndex(def, state)
	if not questIndex then
		return {
			data = data,
			state = state,
			def = def,
			questIndex = nil,
			questDef = nil,
			questState = nil,
			justCompleted = false,
		}
	end

	local questDef = def.quests[questIndex]
	local questState = getOrCreateQuestState(state, questIndex)
	for objectiveIndex, objective in ipairs(questDef.objectives or {}) do
		local saved = tonumber(questState.objectives[objectiveIndex]) or 0
		if objective.type == "capture" then
			local ownedCount = countOwnedCreatures(data, objective.creatureId)
			questState.objectives[objectiveIndex] = math.max(saved, math.min(tonumber(objective.amount) or 1, ownedCount))
		elseif objective.type == "level" then
			local bestLevel = getHighestOwnedLevel(data, objective.creatureId)
			questState.objectives[objectiveIndex] = math.max(saved, bestLevel)
		end
	end

	local wasCompleted, completed = finalizeQuestState(questDef, questState)
	return {
		data = data,
		state = state,
		def = def,
		questIndex = questIndex,
		questDef = questDef,
		questState = questState,
		justCompleted = (not wasCompleted) and completed,
	}
end

local function buildRewardsText(questDef)
	local parts = {}
	local rewards = questDef.rewards or {}
	if tonumber(rewards.coins) and rewards.coins > 0 then
		table.insert(parts, tostring(math.floor(rewards.coins)) .. " coins")
	end
	if tonumber(rewards.gems) and rewards.gems > 0 then
		table.insert(parts, tostring(math.floor(rewards.gems)) .. " gems")
	end
	if tonumber(rewards.playerXP) and rewards.playerXP > 0 then
		table.insert(parts, tostring(math.floor(rewards.playerXP)) .. " player XP")
	end
	if rewards.legendaryEggElement then
		table.insert(parts, tostring(rewards.legendaryEggElement) .. " Legendary Egg")
	end
	table.insert(parts, "+" .. tostring(math.floor(tonumber(questDef.affinityReward) or 0)) .. " affinity")
	return table.concat(parts, "  |  ")
end

local function buildQuestPayload(def, questIndex, questDef, questState, unlocked)
	local objectives = {}
	for objectiveIndex, objective in ipairs(questDef.objectives or {}) do
		local progressValue = tonumber(questState and questState.objectives and questState.objectives[objectiveIndex]) or 0
		local targetValue = (objective.type == "level") and (tonumber(objective.targetLevel) or 1) or (tonumber(objective.amount) or 1)
		local progressText
		if objective.type == "level" then
			progressText = "Lv." .. tostring(math.min(progressValue, targetValue)) .. " / Lv." .. tostring(targetValue)
		else
			progressText = tostring(math.min(progressValue, targetValue)) .. " / " .. tostring(targetValue)
		end
		table.insert(objectives, {
			index = objectiveIndex,
			type = objective.type,
			creatureId = objective.creatureId,
			label = objective.label,
			progress = math.min(progressValue, targetValue),
			target = targetValue,
			progressText = progressText,
			complete = isObjectiveComplete(objective, progressValue),
		})
	end

	local status = "locked"
	if questState and questState.claimed == true then
		status = "claimed"
	elseif questState and questState.completed == true then
		status = "complete"
	elseif unlocked then
		status = "active"
	end

	return {
		index = questIndex,
		title = questDef.title,
		description = questDef.description,
		status = status,
		claimable = questState and questState.completed == true and questState.claimed ~= true or false,
		rewardsText = buildRewardsText(questDef),
		objectives = objectives,
	}
end

function EleminionSystem.GetStatusPayload(player, element)
	local def = EleminionData.GetByElement(element)
	if not def then
		return nil
	end
	local npcInfo = EleminionData.GetNpcProfile(def)

	local sync = syncActiveQuestProgress(player, element)
	if not sync then
		return nil
	end

	local state = sync.state
	local affinity = math.max(0, tonumber(state.affinity) or 0)
	local maxAffinity = EleminionData.GetMaxAffinity(element)
	local currentQuestIndex = getCurrentQuestIndex(def, state)
	local allClaimed = currentQuestIndex == nil

	local quests = {}
	local unlocked = true
	for questIndex, questDef in ipairs(def.quests or {}) do
		local questState = getOrCreateQuestState(state, questIndex)
		local payload = buildQuestPayload(def, questIndex, questDef, questState, unlocked)
		table.insert(quests, payload)
		unlocked = questState.claimed == true
	end

	local pass = {}
	local cfgPass = GameConfig.EleminionAffinityPass
	if type(cfgPass) == "table" then
		for _, m in ipairs(cfgPass) do
			if type(m) == "table" then
				local id = tostring(m.id or "")
				local pct = math.clamp(tonumber(m.pct) or 0, 0, 1)
				if id ~= "" and pct > 0 then
					table.insert(pass, {
						id = id,
						pct = pct,
						requiredAffinity = math.floor(maxAffinity * pct + 0.5),
						label = m.label,
						claimed = state.affinityPassClaims and state.affinityPassClaims[id] == true or false,
					})
				end
			end
		end
	end
	table.sort(pass, function(a, b)
		return (a.pct or 0) < (b.pct or 0)
	end)

	return {
		element = def.element,
		title = def.title,
		subtitle = def.subtitle,
		biomeLabel = def.biomeLabel,
		npcCreatureId = def.npcCreatureId,
		npcDisplayName = npcInfo and npcInfo.displayName or nil,
		npcModelName = npcInfo and npcInfo.modelName or nil,
		affinity = affinity,
		maxAffinity = maxAffinity,
		affinityPercent = (maxAffinity > 0) and math.clamp(affinity / maxAffinity, 0, 1) or 0,
		affinityPass = pass,
		currentQuestIndex = currentQuestIndex or #(def.quests or {}),
		totalQuests = #(def.quests or {}),
		allClaimed = allClaimed,
		canClaimCurrent = sync.questState and sync.questState.completed == true and sync.questState.claimed ~= true or false,
		currentQuest = (currentQuestIndex and quests[currentQuestIndex]) or quests[#quests],
		quests = quests,
		finalRewardLabel = def.element .. " Legendary Egg",
	}
end

local function fireStatusUpdate(player, element)
	if statusUpdateEvent then
		local payload = EleminionSystem.GetStatusPayload(player, element)
		if payload then
			statusUpdateEvent:FireClient(player, element, payload)
		end
	end
end

local function awardPlayerXp(player, amount)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount <= 0 or not PlayerDataManager.AddPlayerXP then
		return
	end
	local newLevel, didLevel = PlayerDataManager.AddPlayerXP(player, amount)
	if playerXpEvent then
		playerXpEvent:FireClient(player, amount)
	end
	if didLevel and playerLevelEvent then
		playerLevelEvent:FireClient(player, newLevel)
	end
end

local function awardLegendaryEgg(player, element)
	local data = PlayerDataManager.GetData(player)
	if not data then
		return false, "No data"
	end
	if #(data.eggs or {}) >= (GameConfig.MaxInventorySize or 50) then
		return false, "Too many eggs. Hatch or clear space first."
	end

	local creatureId = EleminionData.RollLegendaryEggCreatureId(element, true)
	if not creatureId then
		creatureId = EleminionData.RollLegendaryEggCreatureId(element, false)
	end
	if not creatureId then
		return false, "No eligible egg reward creature for " .. tostring(element)
	end

	local eggUid = PlayerDataManager.AddEgg(player, creatureId, 1, "Legendary", true)
	if not eggUid then
		return false, "Failed to create reward egg"
	end

	return true, eggUid, creatureId
end

local function rollRandomCreatureIdByRarity(rarity)
	local pool = {}
	for _, c in ipairs(CreatureData.Creatures or {}) do
		if c
			and c.id
			and c.rarity == rarity
			and c.npcOnly ~= true
			and c.modelName ~= "Egg" then
			table.insert(pool, c.id)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

local function awardRareEgg(player)
	local data = PlayerDataManager.GetData(player)
	if not data then
		return false, "No data"
	end
	if #(data.eggs or {}) >= (GameConfig.MaxInventorySize or 50) then
		return false, "Too many eggs. Hatch or clear space first."
	end

	-- Rare Egg pool: Uncommon or Rare (matches GameConfig egg_rare defaults).
	local rarity = (math.random() < 0.50) and "Uncommon" or "Rare"
	local creatureId = rollRandomCreatureIdByRarity(rarity) or rollRandomCreatureIdByRarity("Common")
	if not creatureId then
		return false, "No creatures available for rare egg reward."
	end

	local eggUid = PlayerDataManager.AddEgg(player, creatureId, 1, rarity, true)
	if not eggUid then
		return false, "Failed to create reward egg"
	end
	return true, eggUid, creatureId, rarity
end

local function tryGrantAffinityPassMilestones(player, element, previousAffinity, newAffinity, grantedEggThisClaim)
	local def = EleminionData.GetByElement(element)
	if not def then
		return
	end
	local data, state = getOrCreateElementState(player, element)
	if not data or not state then
		return
	end

	local maxAffinity = EleminionData.GetMaxAffinity(element)
	if maxAffinity <= 0 then
		return
	end

	local passCfg = GameConfig.EleminionAffinityPass
	if type(passCfg) ~= "table" then
		return
	end

	local claims = state.affinityPassClaims
	if type(claims) ~= "table" then
		claims = {}
		state.affinityPassClaims = claims
	end

	local function markClaimed(id)
		claims[tostring(id)] = true
	end

	for _, m in ipairs(passCfg) do
		if type(m) == "table" then
			local id = tostring(m.id or "")
			local pct = math.clamp(tonumber(m.pct) or 0, 0, 1)
			if id ~= "" and pct > 0 and claims[id] ~= true then
				local requiredAffinity = math.floor(maxAffinity * pct + 0.5)
				if (tonumber(newAffinity) or 0) >= requiredAffinity then
					local rewards = m.rewards or {}

					-- 100% legendary egg: if the current quest claim already granted the legendary egg,
					-- do not grant a duplicate — just mark the pass milestone claimed.
					local wantsEgg = rewards.egg
					if wantsEgg == "Legendary" and grantedEggThisClaim == true then
						markClaimed(id)
					else
						local didAnything = false
						if tonumber(rewards.coins) and rewards.coins > 0 then
							PlayerDataManager.AddCoins(player, math.floor(rewards.coins))
							if coinsUpdateEvent then
								coinsUpdateEvent:FireClient(player, PlayerDataManager.GetCoins(player))
							end
							didAnything = true
						end
						if tonumber(rewards.gems) and rewards.gems > 0 then
							PlayerDataManager.AddGems(player, math.floor(rewards.gems))
							if gemsUpdateEvent then
								gemsUpdateEvent:FireClient(player, PlayerDataManager.GetGems(player))
							end
							didAnything = true
						end
						if wantsEgg == "Rare" then
							local ok = awardRareEgg(player)
							if ok then
								didAnything = true
							end
						elseif wantsEgg == "Legendary" then
							local ok = awardLegendaryEgg(player, element)
							if ok then
								didAnything = true
							end
						end

						if didAnything then
							markClaimed(id)
							notify(player, (def.title or (element .. " Eleminion")) .. " affinity milestone reached: " .. tostring(m.label or (tostring(math.floor(pct * 100)) .. "%")), "info")
						else
							-- Still mark claimed to prevent repeated attempts if the reward cannot be granted (e.g., egg full).
							-- Player will still have the quest reward path; this avoids spam loops.
							markClaimed(id)
						end
					end
				end
			end
		end
	end
end

function EleminionSystem.ClaimQuestReward(player, element)
	local def = EleminionData.GetByElement(element)
	if not def then
		return false, "Unknown Eleminion", nil
	end

	local sync = syncActiveQuestProgress(player, element)
	if not sync or not sync.state then
		return false, "Data not ready", nil
	end
	if not sync.questIndex or not sync.questDef or not sync.questState then
		return false, "This affinity path is already complete.", EleminionSystem.GetStatusPayload(player, element)
	end
	if sync.questState.claimed == true then
		return false, "That reward has already been claimed.", EleminionSystem.GetStatusPayload(player, element)
	end
	if sync.questState.completed ~= true then
		return false, "Finish the current quest first.", EleminionSystem.GetStatusPayload(player, element)
	end

	local rewards = sync.questDef.rewards or {}
	local previousAffinity = math.max(0, tonumber(sync.state.affinity) or 0)
	local grantedEggThisClaim = false
	if rewards.legendaryEggElement then
		local ok, err = awardLegendaryEgg(player, rewards.legendaryEggElement)
		if not ok then
			return false, err or "Reward egg unavailable.", EleminionSystem.GetStatusPayload(player, element)
		end
		grantedEggThisClaim = true
	end

	if tonumber(rewards.coins) and rewards.coins > 0 then
		PlayerDataManager.AddCoins(player, math.floor(rewards.coins))
		if coinsUpdateEvent then
			coinsUpdateEvent:FireClient(player, PlayerDataManager.GetCoins(player))
		end
	end
	if tonumber(rewards.gems) and rewards.gems > 0 then
		PlayerDataManager.AddGems(player, math.floor(rewards.gems))
		if gemsUpdateEvent then
			gemsUpdateEvent:FireClient(player, PlayerDataManager.GetGems(player))
		end
	end
	if tonumber(rewards.playerXP) and rewards.playerXP > 0 then
		awardPlayerXp(player, rewards.playerXP)
	end

	sync.questState.claimed = true
	sync.questState.claimedAt = os.time()
	sync.state.affinity = math.min(EleminionData.GetMaxAffinity(element), math.max(0, tonumber(sync.state.affinity) or 0) + (tonumber(sync.questDef.affinityReward) or 0))
	local newAffinity = math.max(0, tonumber(sync.state.affinity) or 0)

	local message = def.title .. " rewarded your progress."
	if rewards.legendaryEggElement then
		message = message .. " A " .. rewards.legendaryEggElement .. " Legendary Egg was added to your eggs."
	end
	notify(player, message, "info")

	-- Achievements: quest completion/claim.
	if PlayerDataManager and PlayerDataManager.NotifyAchievement then
		PlayerDataManager.NotifyAchievement("OnEleminionQuestClaimed", player, element, sync.questIndex)
	end

	-- Affinity pass milestones (one-time per element).
	tryGrantAffinityPassMilestones(player, element, previousAffinity, newAffinity, grantedEggThisClaim)
	fireStatusUpdate(player, element)

	return true, "Reward claimed!", EleminionSystem.GetStatusPayload(player, element)
end

function EleminionSystem.OnCreatureCaptured(_, player, creatureId, creatureLevel)
	for _, def in ipairs(EleminionData.GetAll()) do
		local sync = syncActiveQuestProgress(player, def.element)
		if sync and sync.questDef and sync.questState and sync.questState.claimed ~= true then
			local changed = false
			for objectiveIndex, objective in ipairs(sync.questDef.objectives or {}) do
				if objective.creatureId == creatureId then
					local currentValue = tonumber(sync.questState.objectives[objectiveIndex]) or 0
					if objective.type == "capture" then
						local ownedCount = countOwnedCreatures(sync.data, objective.creatureId)
						local nextValue = math.min(tonumber(objective.amount) or 1, ownedCount)
						if nextValue ~= currentValue then
							sync.questState.objectives[objectiveIndex] = nextValue
							changed = true
						end
					elseif objective.type == "level" then
						local nextValue = math.max(currentValue, tonumber(creatureLevel) or 1)
						if nextValue ~= currentValue then
							sync.questState.objectives[objectiveIndex] = nextValue
							changed = true
						end
					end
				end
			end
			if changed then
				local wasCompleted, completed = finalizeQuestState(sync.questDef, sync.questState)
				fireStatusUpdate(player, def.element)
				if not wasCompleted and completed then
					notify(player, def.title .. " quest complete. Return and claim your reward.", "info")
				end
			end
		end
	end
end

function EleminionSystem.OnCreatureLevelChanged(_, player, creatureId, _, newLevel)
	for _, def in ipairs(EleminionData.GetAll()) do
		local sync = syncActiveQuestProgress(player, def.element)
		if sync and sync.questDef and sync.questState and sync.questState.claimed ~= true then
			local changed = false
			for objectiveIndex, objective in ipairs(sync.questDef.objectives or {}) do
				if objective.type == "level" and objective.creatureId == creatureId then
					local currentValue = tonumber(sync.questState.objectives[objectiveIndex]) or 0
					local nextValue = math.max(currentValue, tonumber(newLevel) or 1)
					if nextValue ~= currentValue then
						sync.questState.objectives[objectiveIndex] = nextValue
						changed = true
					end
				end
			end
			if changed then
				local wasCompleted, completed = finalizeQuestState(sync.questDef, sync.questState)
				fireStatusUpdate(player, def.element)
				if not wasCompleted and completed then
					notify(player, def.title .. " quest complete. Return and claim your reward.", "info")
				end
			end
		end
	end
end

local function getModelBottomY(model)
	local minY = math.huge
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local bottom = desc.Position.Y - desc.Size.Y * 0.5
			if bottom < minY then
				minY = bottom
			end
		end
	end
	return minY ~= math.huge and minY or nil
end

local function getPointScore(point, def)
	if not point or not point:IsA("BasePart") then
		return -1
	end

	local score = 0

	local current = point
	local depth = 0
	while current and current ~= Workspace and depth < 8 do
		local depthBias = math.max(0, 8 - depth)
		score += scoreNameKey(normalizeName(current.Name), def) * depthBias
		score += scoreAttributes(current, def) * depthBias
		current = current.Parent
		depth += 1
	end

	return score
end

local function findSpawnPoint(def)
	local bestPoint
	local bestScore = -1

	local function scanContainer(container)
		if not container then
			return
		end
		if container:IsA("BasePart") then
			local score = getPointScore(container, def)
			if score > 0 and score > bestScore then
				bestPoint = container
				bestScore = score
			end
		end
		for _, desc in ipairs(container:GetDescendants()) do
			if desc:IsA("BasePart") then
				local score = getPointScore(desc, def)
				if score > 0 and score > bestScore then
					bestPoint = desc
					bestScore = score
				end
			end
		end
	end

	local biomesFolder = Workspace:FindFirstChild("Biomes")
	if biomesFolder then
		local folderNames = CreatureData.GetBiomeFolderNamesForElement(def.element)
		for _, folderName in ipairs(folderNames or {}) do
			scanContainer(biomesFolder:FindFirstChild(folderName))
		end
	end

	if not bestPoint then
		scanContainer(Workspace)
	end

	return bestPoint
end

local function createFallbackNpc(def, info)
	local model = Instance.new("Model")
	model.Name = info.displayName .. "EleminionNPC"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(4.5, 4.5, 4.5)
	body.Anchored = true
	body.CanCollide = false
	body.Material = Enum.Material.Neon
	body.Color = getElementColor(def.element)
	body.Parent = model

	model.PrimaryPart = body
	return model, body
end

local function spawnNpc(def, point)
	local info = EleminionData.GetNpcProfile(def)
	if not info then
		warn("[EleminionSystem] Missing NPC profile for " .. tostring(def.element))
		return nil
	end

	local existing = eleminionNpcs[def.element]
	if existing and existing.Parent then
		disconnectPromptForModel(existing)
		existing:Destroy()
	end
	eleminionNpcStates[def.element] = nil

	local model = Instance.new("Model")
	model.Name = info.displayName .. "EleminionNPC"
	model:SetAttribute("EleminionElement", def.element)
	model:SetAttribute("EleminionId", info.id or def.npcCreatureId)

	local body = nil
	local templateOptions = { targetSize = info.targetSize or 6 }
	local hasTemplate = CreatureModelLoader.HasTemplate(info.modelName, info.displayName)
	if not hasTemplate then
		warn(string.format(
			"[EleminionSystem] No CreatureModels template found for %s (modelName=%s, displayName=%s)",
			tostring(def.element),
			tostring(info.modelName),
			tostring(info.displayName)
		))
	end
	body = select(1, CreatureModelLoader.LoadAndIntegrate(model, info.modelName, info.displayName, point.Position + Vector3.new(0, 4, 0), templateOptions))
	if not body then
		warn(string.format(
			"[EleminionSystem] Falling back to placeholder NPC for %s (modelName=%s, displayName=%s)",
			tostring(def.element),
			tostring(info.modelName),
			tostring(info.displayName)
		))
		model:Destroy()
		model, body = createFallbackNpc(def, info)
		model:SetAttribute("EleminionUsingFallback", true)
	else
		model:SetAttribute("EleminionUsingFallback", false)
		print(string.format(
			"[EleminionSystem] Loaded NPC model for %s using template %s",
			tostring(def.element),
			tostring(model:GetAttribute("TemplateName") or info.modelName)
		))
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
	if not model.PrimaryPart and body then
		model.PrimaryPart = body
	end

	local rotationOffset = CreatureData.GetModelRotationOffset(info, "world", false)
	local placementOffset = CreatureData.GetModelPlacementOffset(info)
	-- World-space top of the pad: Position.Y + Size.Y/2 is wrong when the part is rotated
	-- (Size is in local axes). Use local +Y half-extent in world space.
	local topOfPad = point.CFrame * Vector3.new(0, point.Size.Y * 0.5, 0)
	local baseY = topOfPad.Y + getNpcGroundOffset()
	local pos = Vector3.new(
		topOfPad.X + placementOffset.X,
		baseY + placementOffset.Y,
		topOfPad.Z + placementOffset.Z
	)
	-- Stand upright: applying the pad's full tilt breaks foot alignment because getModelBottomY
	-- + vertical lift assume world-up. Flat EPoints behave the same; tilted pads (e.g. ocean sand) do not.
	local flatLook = point.CFrame.LookVector * Vector3.new(1, 0, 1)
	if flatLook.Magnitude < 0.05 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end
	local pivot = CFrame.lookAt(pos, pos + flatLook) * rotationOffset
	model:PivotTo(pivot)

	local bottomY = getModelBottomY(model)
	if bottomY then
		local lift = (baseY - bottomY) + CreatureData.GetModelPlacementYOffset(info)
		if lift ~= 0 then
			model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
		end
	end

	local promptParent = model.PrimaryPart or body
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EleminionTag"
	billboard.Adornee = promptParent
	billboard.Size = UDim2.new(0, 240, 0, 64)
	billboard.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, promptParent), 0)
	billboard.MaxDistance = getAttentionRange()
	billboard.Parent = model

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
	titleLabel.Text = info.displayName
	titleLabel.Parent = billboard

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.new(1, 0, 0.42, 0)
	subtitleLabel.Position = UDim2.new(0, 0, 0.54, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.GothamMedium
	subtitleLabel.TextScaled = true
	subtitleLabel.TextColor3 = getElementColor(def.element)
	subtitleLabel.Text = def.element .. " Eleminion"
	subtitleLabel.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EleminionPrompt"
	prompt.ObjectText = info.displayName
	prompt.ActionText = "Talk"
	prompt.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = getPromptRange()
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = promptParent

	local highlight = Instance.new("Highlight")
	highlight.Name = "EleminionHighlight"
	highlight.Enabled = false
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = getElementColor(def.element)
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0.2
	highlight:SetAttribute("NpcHighlightDistance", getAttentionRange())
	highlight.Parent = model

	model:SetAttribute("NpcHighlightDistance", getAttentionRange())
	model.Parent = Workspace
	eleminionNpcs[def.element] = model
	eleminionNpcStates[def.element] = {
		element = def.element,
		model = model,
		basePivot = model:GetPivot(),
		rotationOffset = rotationOffset,
		attentionRange = getAttentionRange(),
		lastInteractorUserId = nil,
		currentFacing = "base",
	}

	if not promptConnections[prompt] then
		promptConnections[prompt] = prompt.Triggered:Connect(function(player)
			local npcState = eleminionNpcStates[def.element]
			if npcState then
				npcState.lastInteractorUserId = player.UserId
				updateNpcFacing(npcState)
			end
			if openUiEvent then
				openUiEvent:FireClient(player, def.element)
			end
			if PlayerDataManager and PlayerDataManager.NotifyAchievement then
				PlayerDataManager.NotifyAchievement("OnEleminionMet", player, def.element)
			end
			fireStatusUpdate(player, def.element)
		end)
	end

	return model
end

local function ensureNpcForDefinition(def)
	local point = findSpawnPoint(def)
	if not point then
		if not warnedMissingPoints[def.element] then
			warn("[EleminionSystem] No EPoint / EleminionPoint found for " .. tostring(def.element))
			warnedMissingPoints[def.element] = true
		end
		return nil
	end

	warnedMissingPoints[def.element] = nil
	local npc = eleminionNpcs[def.element]
	if npc and npc.Parent then
		return npc
	end
	print(string.format("[EleminionSystem] Spawning %s at %s", tostring(def.npcCreatureId), point:GetFullName()))
	return spawnNpc(def, point)
end

local function ensureAllNpcs()
	for _, def in ipairs(EleminionData.GetAll()) do
		ensureNpcForDefinition(def)
	end
end

function EleminionSystem.Init(playerDataManager)
	warn("[EleminionSystem] Init called")
	PlayerDataManager = playerDataManager
	if PlayerDataManager and PlayerDataManager.BindEleminionObserver then
		PlayerDataManager.BindEleminionObserver(EleminionSystem)
		warn("[EleminionSystem] Bound to PlayerDataManager observer")
	end

	if not isEnabled() then
		print("[EleminionSystem] Disabled via GameConfig.EleminionsEnabled")
		warn("[EleminionSystem] Disabled via GameConfig.EleminionsEnabled")
		return
	end

	eventsFolder = ReplicatedStorage:WaitForChild("Events", 30)
	if not eventsFolder then
		warn("[EleminionSystem] Events folder not found")
		return
	end
	warn("[EleminionSystem] Events folder found")

	openUiEvent = eventsFolder:FindFirstChild("OpenEleminionUI")
	statusUpdateEvent = eventsFolder:FindFirstChild("EleminionStatusUpdated")
	showNotificationEvent = eventsFolder:FindFirstChild("ShowNotification")
	coinsUpdateEvent = eventsFolder:FindFirstChild("CoinsUpdate")
	gemsUpdateEvent = eventsFolder:FindFirstChild("GemsUpdate")
	playerXpEvent = eventsFolder:FindFirstChild("PlayerXPGained")
	playerLevelEvent = eventsFolder:FindFirstChild("PlayerLevelUp")

	local getStatusFunction = eventsFolder:FindFirstChild("GetEleminionStatus")
	if getStatusFunction and getStatusFunction:IsA("RemoteFunction") then
		getStatusFunction.OnServerInvoke = function(player, element)
			if type(element) ~= "string" or element == "" then
				return nil
			end
			return EleminionSystem.GetStatusPayload(player, element)
		end
	end

	local claimRewardFunction = eventsFolder:FindFirstChild("ClaimEleminionQuestReward")
	if claimRewardFunction and claimRewardFunction:IsA("RemoteFunction") then
		claimRewardFunction.OnServerInvoke = function(player, element)
			if type(element) ~= "string" or element == "" then
				return false, "Invalid Eleminion", nil
			end
			return EleminionSystem.ClaimQuestReward(player, element)
		end
	end

	ensureAllNpcs()
	task.spawn(function()
		while true do
			task.wait(10)
			ensureAllNpcs()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(getFacingUpdateInterval())
			updateAllNpcFacing()
		end
	end)

	print("[EleminionSystem] Initialized")
	warn("[EleminionSystem] Initialized")
end

return EleminionSystem
