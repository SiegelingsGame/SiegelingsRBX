-- AchievementsSystem.lua - ServerScriptService (ModuleScript)
-- Scalable achievement tracking, metric storage, and live unlock dispatch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AchievementsConfig = require(ReplicatedStorage.Modules.AchievementsConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)

local AchievementsSystem = {}

local Events = ReplicatedStorage:WaitForChild("Events")
local getAchievementsRF = Events:WaitForChild("GetAchievements")
local achievementProgressRE = Events:WaitForChild("AchievementProgress")
local achievementUnlockedRE = Events:WaitForChild("AchievementUnlocked")

local PlayerDataManager = nil

local OUTER_ZONE_DEFS = {
	{ id = "Desert", path = { "Terrain", "DesertBaseplate" } },
	{ id = "Electric", path = { "Terrain", "ElectricBaseplate" } },
	{ id = "Ocean", path = { "Terrain", "OceanBaseplate" } },
}

local INNER_WEDGES = {
	{ id = "Earth", from = "ElectricRoad", to = "CaveRoad" },
	{ id = "Fire", from = "CaveRoad", to = "WetRoad" },
	{ id = "Ice", from = "WetRoad", to = "DesertRoad" },
	{ id = "Wind", from = "DesertRoad", to = "ElectricRoad" },
}

local ZONE_CHECK_INTERVAL = 2.5
local VERTICAL_BUFFER = 900
local GROUND_VERTICAL_BUFFER = 100
local INNER_WEDGE_MAX_RADIUS = 1000

local zoneGeometry = {
	ready = false,
	outer = {},
	hubParts = {},
	roadParts = {},
	roadAngles = {},
	hubCenter = Vector3.new(0, 0, 0),
}

local classNormalizeMap = {}
for className in pairs(CreatureData.Classes or {}) do
	classNormalizeMap[string.lower(className)] = className
end

function AchievementsSystem.BindPlayerDataManager(pdm)
	PlayerDataManager = pdm
end

local function getOrInitAchievementState(data)
	if type(data.achievements) ~= "table" then
		data.achievements = {}
	end
	return data.achievements
end

local function getOrInitMetrics(data)
	if type(data.achievementMetrics) ~= "table" then
		data.achievementMetrics = {}
	end
	local metrics = data.achievementMetrics
	if type(metrics.counters) ~= "table" then metrics.counters = {} end
	if type(metrics.best) ~= "table" then metrics.best = {} end
	if type(metrics.sets) ~= "table" then metrics.sets = {} end
	return metrics
end

local function countSetMembers(setTable)
	local count = 0
	for _, value in pairs(setTable or {}) do
		if value == true then
			count += 1
		end
	end
	return count
end

local function getOrInitSet(metrics, key)
	if type(metrics.sets[key]) ~= "table" then
		metrics.sets[key] = {}
	end
	return metrics.sets[key]
end

local function incrementCounter(metrics, key, amount)
	amount = tonumber(amount) or 0
	if amount == 0 then
		return false
	end
	local before = tonumber(metrics.counters[key]) or 0
	local after = before + amount
	if after < 0 then after = 0 end
	metrics.counters[key] = after
	return after ~= before
end

local function setBest(metrics, key, value)
	value = tonumber(value) or 0
	local before = tonumber(metrics.best[key]) or 0
	if value > before then
		metrics.best[key] = value
		return true
	end
	return false
end

local function markSetMember(metrics, key, member)
	member = tostring(member or "")
	if member == "" then
		return false
	end
	local setTable = getOrInitSet(metrics, key)
	if setTable[member] == true then
		return false
	end
	setTable[member] = true
	return true
end

local function readPath(root, path)
	local current = root
	for _, key in ipairs(path or {}) do
		if type(current) ~= "table" then
			return 0
		end
		current = current[key]
	end
	if type(current) == "number" then
		return current
	end
	return tonumber(current) or 0
end

local function normalizeClassName(className)
	local key = string.lower(tostring(className or ""))
	return classNormalizeMap[key] or className
end

local function getFamilyOwnedCount(data, familyId)
	local family = AchievementsConfig.TrackedFamiliesById[familyId]
	if not family then
		return 0
	end
	local metrics = getOrInitMetrics(data)
	local speciesSet = metrics.sets["collection.speciesOwned"] or {}
	local count = 0
	for _, speciesId in ipairs(family.species or {}) do
		if speciesSet[speciesId] == true then
			count += 1
		end
	end
	return count
end

local function backfillMetricsFromCurrentData(data)
	local metrics = getOrInitMetrics(data)
	local inventoryCount = 0

	for _, entry in ipairs(data.inventory or {}) do
		inventoryCount += 1
		if entry and entry.id then
			local creature = CreatureData.GetById(entry.id)
			markSetMember(metrics, "collection.speciesOwned", entry.id)
			if creature and creature.element then
				markSetMember(metrics, "collection.elementsOwned", creature.element)
			end
			if creature and creature.rarity then
				markSetMember(metrics, "collection.raritiesOwned", creature.rarity)
			end
		end
	end

	setBest(metrics, "collection.peakOwned", inventoryCount)

	for _, uid in ipairs(data.baseSlots or {}) do
		if uid and uid ~= "" then
			markSetMember(metrics, "base.incomeAssigned", tostring(uid))
		end
	end

	for _, uid in ipairs(data.defenseSlots or {}) do
		if uid and uid ~= "" then
			markSetMember(metrics, "base.defendersAssigned", tostring(uid))
		end
	end

	for zoneId, unlocked in pairs(data.doorsUnlocked or {}) do
		if unlocked == true or unlocked == "true" then
			markSetMember(metrics, "exploration.doorsUnlocked", zoneId)
		end
	end

	for zoneId, keyOwned in pairs(data.zoneKeysFromGyms or {}) do
		if keyOwned == true or keyOwned == "true" then
			markSetMember(metrics, "exploration.gymKeys", zoneId)
		end
	end

	for zoneId, sigilOwned in pairs(data.sigils or {}) do
		if sigilOwned == true or sigilOwned == "true" then
			markSetMember(metrics, "exploration.sigilsEarned", zoneId)
		end
	end

	local inferredGymWins = countSetMembers(metrics.sets["exploration.gymKeys"])
	if inferredGymWins > (tonumber(metrics.counters["battle.gymWins"]) or 0) then
		metrics.counters["battle.gymWins"] = inferredGymWins
	end
end

local function getCompletedFamiliesCount(data)
	local total = 0
	for _, family in ipairs(AchievementsConfig.TrackedFamilies or {}) do
		if getFamilyOwnedCount(data, family.id) >= #(family.species or {}) then
			total += 1
		end
	end
	return total
end

local function computeMetricValue(metric, data)
	if type(metric) ~= "table" then
		return 0
	end

	local metrics = getOrInitMetrics(data)
	local kind = metric.kind

	if kind == "counter" then
		return tonumber(metrics.counters[metric.key]) or 0
	end

	if kind == "best" then
		return tonumber(metrics.best[metric.key]) or 0
	end

	if kind == "set_count" then
		return countSetMembers(metrics.sets[metric.key])
	end

	if kind == "set_member" then
		local setTable = metrics.sets[metric.key] or {}
		return setTable[tostring(metric.member or "")] and 1 or 0
	end

	if kind == "data_path" then
		return readPath(data, metric.path)
	end

	if kind == "list_count" then
		local list = data
		for _, key in ipairs(metric.path or {}) do
			if type(list) ~= "table" then
				return 0
			end
			list = list[key]
		end
		return type(list) == "table" and #list or 0
	end

	if kind == "sum" then
		local total = 0
		for _, item in ipairs(metric.items or {}) do
			total += computeMetricValue(item, data)
		end
		return total
	end

	if kind == "family_owned_count" then
		return getFamilyOwnedCount(data, metric.familyId)
	end

	if kind == "completed_families_count" then
		return getCompletedFamiliesCount(data)
	end

	return 0
end

local function toClientEntry(def, stateEntry, progress)
	local required = tonumber(def.requiredProgress) or 0
	local current = math.max(0, math.floor(tonumber(progress) or 0))
	local unlocked = (stateEntry and stateEntry.unlocked == true) or (required > 0 and current >= required)

	return {
		id = def.id,
		category = def.category or "Capture",
		subcategory = def.subcategory or "General",
		chainName = def.chainName or def.name or "Achievement",
		name = def.name or "Achievement",
		titleEarned = def.titleEarned or "",
		description = def.description or "",
		icon = def.icon or "",
		badgeKey = def.badgeKey or "",
		badgeGlyph = def.badgeGlyph or "",
		badgeAccent = def.badgeAccent,
		currentProgress = current,
		requiredProgress = required,
		unlocked = unlocked,
		unlockedAt = stateEntry and stateEntry.unlockedAt or nil,
		tier = def.tier or 1,
		tierChainId = def.tierChainId or def.id,
		chainTierCount = def.chainTierCount or 1,
		rewardData = def.rewardData,
		sortOrder = def.sortOrder or 0,
	}
end

local function evaluatePlayerAchievements(player)
	if not PlayerDataManager then
		return nil, {}, {}
	end

	local data = PlayerDataManager.GetData(player)
	if not data then
		return nil, {}, {}
	end

	local state = getOrInitAchievementState(data)
	getOrInitMetrics(data)
	backfillMetricsFromCurrentData(data)

	local changed = {}
	local unlockedNow = {}

	for _, def in ipairs(AchievementsConfig.Definitions or {}) do
		local st = state[def.id]
		if type(st) ~= "table" then
			st = { progress = 0, unlocked = false }
			state[def.id] = st
		end

		local progress = math.max(0, math.floor(computeMetricValue(def.metric, data)))
		local previousProgress = tonumber(st.progress) or 0
		local wasUnlocked = st.unlocked == true

		if previousProgress ~= progress then
			st.progress = progress
			changed[def.id] = true
		end

		local required = tonumber(def.requiredProgress) or 0
		if not wasUnlocked and required > 0 and progress >= required then
			st.unlocked = true
			st.unlockedAt = os.time()
			changed[def.id] = true
			unlockedNow[def.id] = true
		end
	end

	return data, changed, unlockedNow
end

function AchievementsSystem.RecomputeAndUnlock(player, reason)
	local data, changed, unlockedNow = evaluatePlayerAchievements(player)
	if not data then
		return
	end

	local state = getOrInitAchievementState(data)
	for id in pairs(changed) do
		local def = AchievementsConfig.ById[id]
		if def then
			local entry = toClientEntry(def, state[id], state[id].progress)
			achievementProgressRE:FireClient(player, entry, reason or "recompute")
		end
	end

	for id in pairs(unlockedNow) do
		local def = AchievementsConfig.ById[id]
		if def then
			achievementUnlockedRE:FireClient(player, {
				id = def.id,
				name = def.name,
				chainName = def.chainName or def.name,
				titleEarned = def.titleEarned or "",
				description = def.description or "",
				category = def.category or "Capture",
				subcategory = def.subcategory or "General",
				icon = def.icon or "",
				badgeKey = def.badgeKey or "",
				badgeGlyph = def.badgeGlyph or "",
				badgeAccent = def.badgeAccent,
				tier = def.tier or 1,
				tierChainId = def.tierChainId or def.id,
			})
		end
	end
end

local function recordAcquisition(player, creatureId, context)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	local metrics = getOrInitMetrics(data)
	local creature = creatureId and CreatureData.GetById(creatureId) or nil

	if creature then
		markSetMember(metrics, "collection.speciesOwned", creatureId)
		if creature.element then
			markSetMember(metrics, "collection.elementsOwned", creature.element)
		end
		if creature.rarity then
			markSetMember(metrics, "collection.raritiesOwned", creature.rarity)
		end
	end

	local inventoryCount = type(data.inventory) == "table" and #data.inventory or 0
	setBest(metrics, "collection.peakOwned", inventoryCount)

	local source = context and context.source
	if source then
		markSetMember(metrics, "economy.acquisitionSources", source)
	end
end

function AchievementsSystem.OnAcquireCreature(player, creatureId, context)
	recordAcquisition(player, creatureId, context)
	AchievementsSystem.RecomputeAndUnlock(player, "acquire")
end

function AchievementsSystem.OnCapture(player, creatureId, context)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	local metrics = getOrInitMetrics(data)
	local creature = creatureId and CreatureData.GetById(creatureId) or nil

	recordAcquisition(player, creatureId, context)
	incrementCounter(metrics, "capture.total", 1)
	incrementCounter(metrics, "capture.creature." .. tostring(creatureId), 1)

	if creature then
		if creature.element then
			incrementCounter(metrics, "capture.element." .. tostring(creature.element), 1)
		end
		if creature.rarity then
			incrementCounter(metrics, "capture.rarity." .. tostring(creature.rarity), 1)
		end
		local className = normalizeClassName(creature.class)
		if className then
			incrementCounter(metrics, "capture.class." .. tostring(className), 1)
		end
	end

	AchievementsSystem.RecomputeAndUnlock(player, "capture")
end

function AchievementsSystem.OnEvolution(player, fromCreatureId, toCreatureId)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	local metrics = getOrInitMetrics(data)
	local creature = toCreatureId and CreatureData.GetById(toCreatureId) or CreatureData.GetById(fromCreatureId)

	incrementCounter(metrics, "evolution.total", 1)
	if creature and creature.element then
		incrementCounter(metrics, "evolution.element." .. tostring(creature.element), 1)
	end

	if toCreatureId then
		recordAcquisition(player, toCreatureId, { source = "evolution" })
	end

	AchievementsSystem.RecomputeAndUnlock(player, "evolution")
end

function AchievementsSystem.OnTradeCompleted(player)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	incrementCounter(getOrInitMetrics(data), "economy.tradesCompleted", 1)
	AchievementsSystem.RecomputeAndUnlock(player, "trade")
end

function AchievementsSystem.OnSale(player)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	incrementCounter(getOrInitMetrics(data), "economy.salesCompleted", 1)
	AchievementsSystem.RecomputeAndUnlock(player, "sale")
end

function AchievementsSystem.OnSlotAssigned(player, slotType, uid)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	local key = nil
	if slotType == "defense" then
		key = "base.defendersAssigned"
	elseif slotType == "income" or slotType == "base" then
		key = "base.incomeAssigned"
	end

	if not key then return end

	markSetMember(getOrInitMetrics(data), key, tostring(uid or ""))
	AchievementsSystem.RecomputeAndUnlock(player, "slot")
end

function AchievementsSystem.OnArenaWin(player)
	AchievementsSystem.RecomputeAndUnlock(player, "arena")
end

function AchievementsSystem.OnGymWin(player, zoneKey)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	local metrics = getOrInitMetrics(data)
	incrementCounter(metrics, "battle.gymWins", 1)
	if zoneKey then
		markSetMember(metrics, "exploration.gymKeys", zoneKey)
	end
	AchievementsSystem.RecomputeAndUnlock(player, "gym")
end

function AchievementsSystem.OnDefenseKill(player, killKind)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	local metrics = getOrInitMetrics(data)
	if killKind == "raider" then
		incrementCounter(metrics, "base.defenseKills.raider", 1)
	elseif killKind == "monster" then
		incrementCounter(metrics, "base.defenseKills.monster", 1)
	end

	AchievementsSystem.RecomputeAndUnlock(player, "defense_kill")
end

function AchievementsSystem.OnDefenseSuccess(player)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	incrementCounter(getOrInitMetrics(data), "base.defenseSuccesses", 1)
	AchievementsSystem.RecomputeAndUnlock(player, "defense_success")
end

function AchievementsSystem.OnZoneVisited(player, zoneId)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	if markSetMember(getOrInitMetrics(data), "exploration.zonesVisited", zoneId) then
		AchievementsSystem.RecomputeAndUnlock(player, "zone")
	end
end

function AchievementsSystem.OnDoorUnlocked(player, zoneId)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	if markSetMember(getOrInitMetrics(data), "exploration.doorsUnlocked", zoneId) then
		AchievementsSystem.RecomputeAndUnlock(player, "door")
	end
end

function AchievementsSystem.OnFloorUnlocked(player)
	AchievementsSystem.RecomputeAndUnlock(player, "floor")
end

function AchievementsSystem.OnPlayerLevelChanged(player)
	AchievementsSystem.RecomputeAndUnlock(player, "level")
end

function AchievementsSystem.OnSigilEarned(player, zoneId)
	if not PlayerDataManager then return end
	local data = PlayerDataManager.GetData(player)
	if not data then return end

	markSetMember(getOrInitMetrics(data), "exploration.sigilsEarned", zoneId)
	AchievementsSystem.RecomputeAndUnlock(player, "sigil")
end

local function isOverPart(position, part, verticalBuffer)
	if not part or not part:IsA("BasePart") then
		return false
	end

	verticalBuffer = verticalBuffer or GROUND_VERTICAL_BUFFER
	local localPos = part.CFrame:PointToObjectSpace(position)
	local halfX = part.Size.X * 0.5
	local halfY = part.Size.Y * 0.5
	local halfZ = part.Size.Z * 0.5

	if math.abs(localPos.X) > halfX then return false end
	if math.abs(localPos.Z) > halfZ then return false end
	if localPos.Y < -halfY then return false end
	if localPos.Y > halfY + verticalBuffer then return false end

	return true
end

local function normalizeAngle(value)
	value = value % (2 * math.pi)
	if value > math.pi then
		value -= 2 * math.pi
	end
	return value
end

local function isAngleBetween(angle, fromAngle, toAngle)
	local sweep = normalizeAngle(toAngle - fromAngle)
	local test = normalizeAngle(angle - fromAngle)
	if sweep > 0 then
		return test >= 0 and test <= sweep
	end
	return test >= 0 or test <= sweep
end

local function resolveWorkspacePart(path)
	local current = workspace
	for _, name in ipairs(path) do
		current = current:FindFirstChild(name)
		if not current then
			return nil
		end
	end
	return current
end

local function refreshZoneGeometry()
	local outer = {}
	for _, def in ipairs(OUTER_ZONE_DEFS) do
		local part = resolveWorkspacePart(def.path)
		if part then
			table.insert(outer, { id = def.id, part = part })
		end
	end

	local hubGround = resolveWorkspacePart({ "HubArea", "HubGround" })
	local roadsFolder = workspace:FindFirstChild("Roads")
	if not hubGround or not roadsFolder then
		zoneGeometry.ready = false
		zoneGeometry.outer = outer
		return
	end

	local roadParts = {}
	local roadAngles = {}
	for _, roadName in ipairs({ "CaveRoad", "ElectricRoad", "DesertRoad", "WetRoad" }) do
		local road = roadsFolder:FindFirstChild(roadName)
		if road and road:IsA("BasePart") then
			roadParts[roadName] = road
		end
	end

	local hubCenter = hubGround.Position
	for roadName, road in pairs(roadParts) do
		local delta = road.Position - hubCenter
		roadAngles[roadName] = math.atan2(delta.Z, delta.X)
	end

	zoneGeometry.ready = true
	zoneGeometry.outer = outer
	zoneGeometry.hubParts = { hubGround }
	zoneGeometry.roadParts = roadParts
	zoneGeometry.roadAngles = roadAngles
	zoneGeometry.hubCenter = hubCenter
end

local function getZoneIdForPosition(position)
	if not zoneGeometry.ready then
		refreshZoneGeometry()
	end

	for _, zone in ipairs(zoneGeometry.outer or {}) do
		if isOverPart(position, zone.part, VERTICAL_BUFFER) then
			return zone.id
		end
	end

	for _, part in ipairs(zoneGeometry.hubParts or {}) do
		if isOverPart(position, part, GROUND_VERTICAL_BUFFER) then
			return nil
		end
	end

	for _, part in pairs(zoneGeometry.roadParts or {}) do
		if isOverPart(position, part, GROUND_VERTICAL_BUFFER) then
			return nil
		end
	end

	local hubCenter = zoneGeometry.hubCenter
	if not hubCenter then
		return nil
	end

	local dx = position.X - hubCenter.X
	local dz = position.Z - hubCenter.Z
	local distance = math.sqrt((dx * dx) + (dz * dz))
	if distance > INNER_WEDGE_MAX_RADIUS then
		return nil
	end

	local angle = math.atan2(dz, dx)
	for _, wedge in ipairs(INNER_WEDGES) do
		local fromAngle = zoneGeometry.roadAngles[wedge.from]
		local toAngle = zoneGeometry.roadAngles[wedge.to]
		if fromAngle and toAngle and isAngleBetween(angle, fromAngle, toAngle) then
			return wedge.id
		end
	end

	return nil
end

local function zoneWatcherLoop()
	while true do
		task.wait(ZONE_CHECK_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local zoneId = getZoneIdForPosition(root.Position)
				if zoneId then
					AchievementsSystem.OnZoneVisited(player, zoneId)
				end
			end
		end
	end
end

getAchievementsRF.OnServerInvoke = function(player)
	if not PlayerDataManager then
		return {}
	end

	local data = PlayerDataManager.GetData(player)
	if not data then
		return {}
	end

	evaluatePlayerAchievements(player)

	local state = getOrInitAchievementState(data)
	local result = {}
	for _, def in ipairs(AchievementsConfig.Definitions or {}) do
		local st = state[def.id] or { progress = 0, unlocked = false }
		table.insert(result, toClientEntry(def, st, st.progress))
	end
	return result
end

Players.PlayerAdded:Connect(function(player)
	task.delay(3, function()
		AchievementsSystem.RecomputeAndUnlock(player, "join")
	end)
end)

task.spawn(zoneWatcherLoop)

return AchievementsSystem
