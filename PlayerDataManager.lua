-- PlayerDataManager.lua - ServerScriptService (ModuleScript)
-- Manages all persistent player data.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local GameConfig = require(game.ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(game.ReplicatedStorage.Modules.CreatureData)

local PlayerDataManager = {}

local DATA_STORE_NAME = "MonsterSiege_PlayerData_v1"
local AUTO_SAVE_INTERVAL = 120
local MAX_RETRIES = 3
local MAX_BATTLE_TEAM = GameConfig.MaxBattleTeamSize or 9
local GRID_SLOTS = 9

local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)
local playerCache = {}
-- plotId -> userId: atomic source of truth to prevent two players claiming same base
local claimedPlotIds = {}

local function getDefaultData()
	local startingCoins = (GameConfig.DebugCoins1000 and 1000) or GameConfig.StartingCoins
	return {
		coins        = startingCoins,
		gems         = 0,  -- premium currency
		inventory    = {},
		baseSlots    = {},
		defenseSlots = {},
		favoriteUid  = nil,
		battleTeam   = {},  -- { [1]=uid, [3]=uid, ... } number keys only, max 5 of 9
		battleTeamEnabled = true,  -- when false, team is not active for arena/raids (toggle without clearing)
		stats        = { totalCaptured = 0, totalRaids = 0, arenaWins = 0, arenaLosses = 0, arenaWinStreak = 0, arenaMaxStreak = 0, totalIncome = 0 },
		settings     = {},
		plotId       = 0,
		baseCreaturePositions = {},
		friendsList  = {},  -- {userId1, userId2, ...} allowed through laser door
		activeBuffs  = {},  -- {buffId = {expiresAt = tick, ...}, ...}
		cosmetics    = {},  -- {owned = {id1=true, ...}, equipped = {trail="", aura=""}}
		exterior     = {},  -- {owned = {id1=true, ...}, equipped = "HauntedHouse" or nil}
		baseColor    = {},  -- {owned = {id1=true, ...}, equipped = "base_red" or nil}
		playerLevel  = 1,
		playerXP     = 0,
		ownedFloors  = {1},  -- array of floor numbers owned; starts with Floor 1
		eggs         = {},   -- { { uid, creatureId, level, rarity, hatchMinutes, createdAt }, ... }; place on base/defense to hatch
		rebirthLevel = 0,    -- pilot rebirth level (0 = never rebirthed); bonuses apply to passive gold, damage, health
	}
end

-- DataStore converts number keys to strings. This fixes them back.
local function normalizeBattleTeam(bt)
	if type(bt) ~= "table" then return {} end
	local fixed = {}
	for k, v in pairs(bt) do
		local n = tonumber(k)
		if n and n >= 1 and n <= GRID_SLOTS and type(v) == "string" and v ~= "" then
			fixed[n] = v
		end
	end
	return fixed
end

-- DataStore can serialize array keys as strings; normalize baseSlots/defenseSlots to dense 1..MAX_SLOTS array.
-- ipairs() stops at first nil, so we must return a dense array or only slot 1 is ever used by placement/UI.
local MAX_SLOTS = 18  -- 3 floors * 6
local function normalizeSlotArray(slots)
	if type(slots) ~= "table" then
		local empty = {}
		for i = 1, MAX_SLOTS do empty[i] = "" end
		return empty
	end
	local fixed = {}
	for i = 1, MAX_SLOTS do
		local v = slots[i] or slots[tostring(i)]
		fixed[i] = (v and v ~= "") and tostring(v) or ""
	end
	return fixed
end

-- Count how many slots are filled in battleTeam (uses pairs so string keys from serialization are counted)
local function countBattleTeam(bt)
	local c = 0
	for _, uid in pairs(bt or {}) do
		if uid and uid ~= "" then c = c + 1 end
	end
	return c
end

function PlayerDataManager.GenerateUID()
	return HttpService:GenerateGUID(false)
end

local function loadFromStore(userId)
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function() return dataStore:GetAsync("Player_" .. userId) end)
		if ok then return true, result end
		if attempt < MAX_RETRIES then task.wait(1 * attempt) end
	end
	return false, nil
end

local function saveToStore(userId, data)
	for attempt = 1, MAX_RETRIES do
		local ok = pcall(function() dataStore:SetAsync("Player_" .. userId, data) end)
		if ok then return true end
		if attempt < MAX_RETRIES then task.wait(1 * attempt) end
	end
	return false
end

-- ====== Public API ======

function PlayerDataManager.GetData(player)
	return playerCache[player.UserId]
end

function PlayerDataManager.GetCoins(player)
	local d = playerCache[player.UserId]
	return d and d.coins or 0
end

function PlayerDataManager.AddCoins(player, amount)
	local d = playerCache[player.UserId]
	if d then d.coins = math.max(0, d.coins + amount); return d.coins end
	return 0
end

function PlayerDataManager.SpendCoins(player, amount)
	local d = playerCache[player.UserId]
	if d and d.coins >= amount then d.coins = d.coins - amount; return true end
	return false
end

function PlayerDataManager.AddCreature(player, creatureId, level, xp, variant, existingUid)
	local d = playerCache[player.UserId]
	if not d or #d.inventory >= GameConfig.MaxInventorySize then return nil end
	-- Use existing unique id when provided (e.g. from captured world creature) so creature data is maintained
	local uid = (type(existingUid) == "string" and #existingUid > 0) and existingUid or PlayerDataManager.GenerateUID()
	variant = variant or "Normal"
	table.insert(d.inventory, { id = creatureId, uid = uid, level = level or 1, xp = xp or 0, variant = variant })
	d.stats.totalCaptured = d.stats.totalCaptured + 1
	return uid
end

-- XP needed for a given level
function PlayerDataManager.XPForLevel(level)
	if level <= 1 then return 0 end
	return math.floor(GameConfig.BaseXPRequired * (GameConfig.XPScaling ^ (level - 2)))
end

-- Add XP to a creature by uid, auto-level if threshold met. Returns newLevel, didLevelUp
function PlayerDataManager.AddXP(player, uid, amount)
	local d = playerCache[player.UserId]
	if not d then return 0, false end
	local su = tostring(uid or "")
	if su == "" then return 0, false end
	for _, e in ipairs(d.inventory) do
		if e.uid and tostring(e.uid) == su then
			e.level = e.level or 1; e.xp = e.xp or 0
			local maxLvl = CreatureData.GetMaxCreatureLevel(e.id)
			if e.level >= maxLvl then return e.level, false end
			e.xp = e.xp + amount
			local leveled = false
			while e.level < maxLvl do
				local needed = PlayerDataManager.XPForLevel(e.level + 1)
				if e.xp >= needed then
					e.xp = e.xp - needed; e.level = e.level + 1; leveled = true
				else break end
			end
			return e.level, leveled
		end
	end
	return 0, false
end

-- Get creature entry by uid
function PlayerDataManager.GetCreatureByUid(player, uid)
	local d = playerCache[player.UserId]
	if not d then return nil end
	local su = tostring(uid or "")
	if su == "" then return nil end
	for _, e in ipairs(d.inventory) do
		if tostring(e.uid) == su then return e end
	end
	return nil
end

-- Get effective stats for a creature: rank-based level scaling (biggest base stat grows fastest),
-- then amplified by tier (Silver/Gold/Legend) and rarity.
function PlayerDataManager.GetEffectiveStats(creatureId, level, variant)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end
	level = level or 1
	variant = variant or "Normal"
	local rarity = info.rarity or "Common"

	-- Base stats and stat names for ranking
	local statKeys = { "health", "attack", "defense", "speed" }
	local baseStats = {
		health = info.health or 1,
		attack = info.attack or 1,
		defense = info.defense or 1,
		speed = info.speed or 1,
	}

	-- Sort stat names by base value descending (biggest first); tiebreak by fixed order so ranking is deterministic
	local orderTiebreak = { health = 1, attack = 2, defense = 3, speed = 4 }
	table.sort(statKeys, function(a, b)
		local va, vb = baseStats[a], baseStats[b]
		if va ~= vb then return va > vb end
		return (orderTiebreak[a] or 0) < (orderTiebreak[b] or 0)
	end)

	-- Rank 1 = highest base stat (fastest growth), rank 4 = lowest
	local gainByRank = GameConfig.StatGainByRank or { 1.5, 1.25, 1.0, 0.75 }
	local baseGain = GameConfig.StatGainPerLevel or 0.08
	local rankOf = {}
	for rank, key in ipairs(statKeys) do
		rankOf[key] = rank
	end

	-- Per-stat level multiplier: 1 + (level - 1) * baseGain * gainByRank[rank]
	local levelMult = {}
	for _, key in ipairs(statKeys) do
		local r = rankOf[key]
		local rankMult = gainByRank[r] or 1
		levelMult[key] = 1 + (level - 1) * baseGain * rankMult
	end

	-- Tier (variant) and rarity amplifiers
	local variantMult = CreatureData.GetVariantStatMultiplier and CreatureData.GetVariantStatMultiplier(variant) or 1
	local rarityMults = GameConfig.RarityStatMultipliers or {}
	local rarityMult = rarityMults[rarity] or 1

	local mult = variantMult * rarityMult
	return {
		health = math.floor(baseStats.health * levelMult.health * mult),
		attack = math.floor(baseStats.attack * levelMult.attack * mult),
		defense = math.floor(baseStats.defense * levelMult.defense * mult),
		speed = math.floor(baseStats.speed * levelMult.speed * mult),
		level = level,
		variant = variant,
	}
end

-- Remove uid from ALL slot types (all occurrences, not just first). Uses slot clear (set to "") to avoid shifting.
-- Clears duplicates so a creature cannot appear in multiple income/defense slots.
local function removeFromAllSlots(data, uid)
	local su = tostring(uid or "")
	if su == "" then return end
	for i = 1, MAX_SLOTS do
		if data.baseSlots and tostring(data.baseSlots[i] or "") == su then data.baseSlots[i] = "" end
	end
	for i = 1, MAX_SLOTS do
		if data.defenseSlots and tostring(data.defenseSlots[i] or "") == su then data.defenseSlots[i] = "" end
	end
	if data.favoriteUid and tostring(data.favoriteUid) == su then data.favoriteUid = nil end
	-- FIX #10: Use pairs() instead of integer loop for battleTeam.
	-- DataStore serializes number keys as strings. Even though normalizeBattleTeam
	-- converts them back on load, pairs() is more robust than for i=1,N.
	if data.battleTeam then
		for key, val in pairs(data.battleTeam) do
			if val and tostring(val) == su then data.battleTeam[key] = nil break end
		end
	end
end

function PlayerDataManager.RemoveCreature(player, uid)
	local d = playerCache[player.UserId]
	if not d then return nil end
	for i, entry in ipairs(d.inventory) do
		if tostring(entry.uid) == tostring(uid) then
			local removed = table.remove(d.inventory, i)
			removeFromAllSlots(d, uid)
			return removed
		end
	end
	return nil
end

function PlayerDataManager.TransferCreature(fromPlayer, toPlayer, uid)
	local fd = playerCache[fromPlayer.UserId]
	local td = playerCache[toPlayer.UserId]
	if not fd or not td or #td.inventory >= GameConfig.MaxInventorySize then return false end

	local entry, idx = nil, nil
	for i, e in ipairs(fd.inventory) do
		if tostring(e.uid) == tostring(uid) then entry = e; idx = i; break end
	end
	if not entry then return false end

	table.remove(fd.inventory, idx)
	removeFromAllSlots(fd, uid)
	-- Preserve level/xp/variant on transfers (used by trading/raids)
	table.insert(td.inventory, {
		id = entry.id,
		uid = PlayerDataManager.GenerateUID(),
		level = entry.level or 1,
		xp = entry.xp or 0,
		variant = entry.variant or "Normal",
	})
	return true
end

-- ====== COMBINE (3 same creature + same variant → 1 of next variant) ======
-- uids: array of exactly 3 UIDs. Must be same creatureId, same variant; variant must not be Legend.
-- Returns: newUid or nil, errorMessage

function PlayerDataManager.CanCombine(player, uids)
	if not uids or #uids ~= 3 then return false, "Need exactly 3 creatures" end
	local d = playerCache[player.UserId]
	if not d or not d.inventory then return false, "No data" end
	if #d.inventory - 3 + 1 > GameConfig.MaxInventorySize then return false, "Inventory would be over capacity" end

	local entries = {}
	for _, uid in ipairs(uids) do
		local e = PlayerDataManager.GetCreatureByUid(player, uid)
		if not e then return false, "One or more creatures not found" end
		table.insert(entries, e)
	end

	local creatureId = entries[1].id
	local variant = entries[1].variant or "Normal"
	for i = 2, 3 do
		if entries[i].id ~= creatureId then return false, "All 3 must be the same creature" end
		if (entries[i].variant or "Normal") ~= variant then return false, "All 3 must be the same variant (e.g. all Silver)" end
	end

	if variant == "Legend" then return false, "Legend tier cannot combine further" end
	local nextVariant = CreatureData.GetNextVariant(variant)
	if not nextVariant then return false, "Cannot combine this variant" end

	return true, nil
end

function PlayerDataManager.CombineCreatures(player, uids)
	local ok, err = PlayerDataManager.CanCombine(player, uids)
	if not ok then return nil, err end

	local d = playerCache[player.UserId]
	local entries = {}
	for _, uid in ipairs(uids) do
		local e = PlayerDataManager.GetCreatureByUid(player, uid)
		table.insert(entries, e)
	end

	local creatureId = entries[1].id
	local variant = entries[1].variant or "Normal"
	local nextVariant = CreatureData.GetNextVariant(variant)
	-- Use highest level/xp of the three for the result
	local bestLevel, bestXp = 1, 0
	for _, e in ipairs(entries) do
		local l, x = e.level or 1, e.xp or 0
		if l > bestLevel or (l == bestLevel and x > bestXp) then bestLevel = l; bestXp = x end
	end

	for _, uid in ipairs(uids) do
		PlayerDataManager.RemoveCreature(player, uid)
	end

	local newUid = PlayerDataManager.AddCreature(player, creatureId, bestLevel, bestXp, nextVariant)
	return newUid
end

-- ====== EVOLUTION (same creature, next stage in evolution chain) ======
-- Changes entry.id to evolvesTo; keeps level, xp, variant. Returns true or false, errorMessage.

function PlayerDataManager.EvolveCreature(player, uid)
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	local entry = PlayerDataManager.GetCreatureByUid(player, uid)
	if not entry then return false, "Creature not found" end

	local nextId = CreatureData.GetEvolvesTo(entry.id)
	if not nextId then return false, "This creature cannot evolve" end
	-- Block if evolution isn't available in-game (no model yet or marked coming soon)
	if not CreatureData.CanEvolveInGame(entry.id) then
		return false, "Evolution not available yet"
	end
	-- Level requirement: base form needs EvolutionMinLevel (10), evolved form needs EvolutionMinLevel2 (25)
	local minLvl = CreatureData.GetEvolvesFrom(entry.id) and (GameConfig.EvolutionMinLevel2 or 25) or (GameConfig.EvolutionMinLevel or 10)
	local lvl = entry.level or 1
	if lvl < minLvl then
		return false, "Reach level " .. tostring(minLvl) .. " to evolve"
	end

	entry.id = nextId
	return true
end

-- ====== EGGS (from Recycler: 1 higher rarity; place on base/defense point to hatch) ======
-- Hatch time in minutes by level: level 1→20, 2→30, 3→60, 4→120, 5→600, 6+→300
function PlayerDataManager.GetHatchMinutesForLevel(level)
	local tbl = GameConfig.EggHatchMinutesByLevel or { 20, 30, 60, 120, 600, 300 }
	local idx = math.clamp(tonumber(level) or 1, 1, #tbl)
	return tbl[idx] or tbl[#tbl] or 60
end

function PlayerDataManager.GetEggByUid(player, uid)
	local d = playerCache[player.UserId]
	if not d or not d.eggs then return nil end
	local su = tostring(uid or "")
	if su == "" then return nil end
	for _, egg in ipairs(d.eggs) do
		if egg.uid and tostring(egg.uid) == su then return egg end
	end
	return nil
end

function PlayerDataManager.AddEgg(player, creatureId, level, rarity)
	local d = playerCache[player.UserId]
	if not d then return nil end
	if not d.eggs then d.eggs = {} end
	local lvl = math.max(1, tonumber(level) or 1)
	local hatchMinutes = PlayerDataManager.GetHatchMinutesForLevel(lvl)
	local uid = PlayerDataManager.GenerateUID()
	table.insert(d.eggs, {
		uid = uid,
		creatureId = creatureId,
		level = lvl,
		rarity = rarity or "Common",
		hatchMinutes = hatchMinutes,
		createdAt = os.time(),
	})
	return uid
end

function PlayerDataManager.RemoveEgg(player, uid)
	local d = playerCache[player.UserId]
	if not d or not d.eggs then return nil end
	local su = tostring(uid or "")
	for i, egg in ipairs(d.eggs) do
		if egg.uid and tostring(egg.uid) == su then
			table.remove(d.eggs, i)
			return egg
		end
	end
	return nil
end

-- Process eggs placed in baseSlots/defenseSlots; hatch any that are ready.
-- Returns: anyHatched (boolean), hatchedSlots (array of {slotType, slotIndex, newUid} for incremental placement)
function PlayerDataManager.ProcessEggHatches(player)
	local d = playerCache[player.UserId]
	if not d then return false, {} end
	local now = os.time()
	local anyHatched = false
	local hatchedSlots = {}
	for dataKey, slotList in pairs({ baseSlots = d.baseSlots, defenseSlots = d.defenseSlots }) do
		if not slotList then continue end
		local slotType = (dataKey == "baseSlots") and "income" or "defense"
		for i = #slotList, 1, -1 do
			local uid = slotList[i]
			local egg = PlayerDataManager.GetEggByUid(player, uid)
			if not egg then continue end
			local hatchAt = egg.createdAt + egg.hatchMinutes * 60
			if now >= hatchAt then
				-- Hatch: add creature to inventory, remove egg from slots and eggs list
				local newUid = PlayerDataManager.AddCreature(player, egg.creatureId, egg.level, 0)
				removeFromAllSlots(d, uid)
				PlayerDataManager.RemoveEgg(player, uid)
				slotList[i] = newUid  -- same slot, new creature uid
				anyHatched = true
				table.insert(hatchedSlots, { slotType = slotType, slotIndex = i, newUid = newUid })
			end
		end
	end
	return anyHatched, hatchedSlots
end

-- ====== RECYCLER (trade N duplicates for 1 EGG of 1 rarity tier higher; place egg on point to hatch) ======
-- uids: array of UIDs, all must be same creatureId; count must be >= GameConfig.RecyclerDuplicateCount (e.g. 3).
-- Returns: eggUid or nil, errorMessage
function PlayerDataManager.RecycleDuplicates(player, uids)
	local d = playerCache[player.UserId]
	if not d or not d.inventory then return nil, "No data" end
	local minCount = GameConfig.RecyclerDuplicateCount or 3
	if not uids or type(uids) ~= "table" or #uids < minCount then
		return nil, "Select at least " .. tostring(minCount) .. " of the same creature"
	end
	-- Eggs don't fill inventory; no need to check MaxInventorySize for adding one egg
	local creatureId = nil
	local entries = {}
	for _, uid in ipairs(uids) do
		local e = PlayerDataManager.GetCreatureByUid(player, uid)
		if not e then return nil, "One or more creatures not found" end
		if creatureId and e.id ~= creatureId then return nil, "All must be the same creature" end
		creatureId = e.id
		table.insert(entries, e)
	end

	local info = CreatureData.GetById(creatureId)
	if not info then return nil, "Invalid creature" end
	local nextRarity = CreatureData.GetNextRarity(info.rarity)
	if not nextRarity then return nil, "Legendary cannot be recycled for higher" end

	local newCreatureId = CreatureData.GetRandomCreatureIdByRarity(nextRarity)
	if not newCreatureId then return nil, "No " .. nextRarity .. " creature available" end

	for _, uid in ipairs(uids) do
		PlayerDataManager.RemoveCreature(player, uid)
	end

	-- Give an egg (place on base/defense point to hatch); creature inside is level 1
	local eggUid = PlayerDataManager.AddEgg(player, newCreatureId, 1, nextRarity)
	return eggUid
end

-- ====== SLOT ASSIGNMENT (mutually exclusive) ======

local function isCreatureOrEggUid(d, uid)
	local su = tostring(uid or "")
	if su == "" then return false end
	for _, e in ipairs(d.inventory or {}) do if tostring(e.uid or "") == su then return true end end
	for _, egg in ipairs(d.eggs or {}) do if tostring(egg.uid or "") == su then return true end end
	return false
end

-- Count filled slots (excludes nil and "")
local function countFilledSlots(slots, maxSlots)
	if not slots then return 0 end
	local c = 0
	for i = 1, maxSlots do
		local v = slots[i]
		if v and v ~= "" then c = c + 1 end
	end
	return c
end

-- Build set of UIDs that actually exist (inventory + eggs). Used to avoid counting stale slot refs.
-- Key by string so slot UIDs (which may be string or number after serialization) match.
local function getValidUidSet(d)
	local valid = {}
	if not d then return valid end
	for _, e in ipairs(d.inventory or {}) do if e and e.uid then valid[tostring(e.uid)] = true end end
	for _, egg in ipairs(d.eggs or {}) do if egg and egg.uid then valid[tostring(egg.uid)] = true end end
	return valid
end

-- Count filled slots that reference a UID still in inventory or eggs. Clears stale refs and duplicates.
-- Duplicates (same UID in multiple slots) cause income creatures to spawn twice; keep first occurrence only.
local function countValidFilledSlotsAndSanitize(d, slots, maxSlots)
	if not slots or not d then return 0 end
	local valid = getValidUidSet(d)
	local seen = {}
	local c = 0
	for i = 1, maxSlots do
		local v = slots[i]
		if v and v ~= "" then
			local sv = tostring(v)
			if valid[sv] then
				if seen[sv] then
					-- Duplicate UID: clear so we only have one creature per slot type
					slots[i] = ""
				else
					seen[sv] = true
					c = c + 1
				end
			else
				-- Stale UID: clear so display and next save are correct
				slots[i] = ""
			end
		end
	end
	return c
end

-- First empty slot (1..max). "" or nil = empty. Returns index or nil.
local function firstEmptySlot(slots, maxSlots)
	for i = 1, maxSlots do
		local v = slots[i]
		if not v or v == "" then return i end
	end
	return nil
end

-- Ensure slots table is dense (1..maxSlots all exist) so ipairs()s and placement see every slot.
local function ensureSlotsDense(slots, maxSlots)
	if not slots or maxSlots < 1 then return end
	for i = 1, maxSlots do
		if slots[i] == nil then slots[i] = "" end
	end
end

-- Assign uid to aincome slot. optionalSlotIndex: if given, place at that slot (replacing any creature there; server clears sthat slot first).
-- optionalSlotIndex == 0 means explicit "remove from base" (client Rem button)... Returns success, slotIndex, added (true=we juast placed in this call; false=removed or already in base—server must not place again).
function PlayerDataManager.AssignToBase(player, uid, optionalSlotIndex)
	local d = playerCache[player.UserId]
	if not d then return false, nil, nil end
	if not d.baseSlots then d.baseSlots = {} end
	local maxSlots = PlayerDataManager.GetMaxSlots(player, "income")
	ensureSlotsDense(d.baseSlots, maxSlots)
	countValidFilledSlotsAndSanitize(d, d.baseSlots, maxSlots)
	local su = tostring(uid or "")
	-- Explicit remove: client sends 0 for "Rem" button. Clear ALL slots with this uid (fixes duplicate reappearing).
	if optionalSlotIndex == 0 or optionalSlotIndex == "0" then
		local cleared = false
		for i = 1, maxSlots do
			local v = d.baseSlots[i] or d.baseSlots[tostring(i)]
			if tostring(v or "") == su then
				d.baseSlots[i] = ""
				d.baseSlots[tostring(i)] = ""
				cleared = true
			end
		end
		return cleared, 0, false
	end
	-- Already in base? Idempotent: treat as success but do NOT place again (prevents duplicate models on double-fire).
	for i = 1, maxSlots do
		if tostring(d.baseSlots[i] or "") == su then
			if type(optionalSlotIndex) == "number" and optionalSlotIndex >= 1 and optionalSlotIndex <= maxSlots and optionalSlotIndex ~= i then
				-- Moving to a different slot: remove from current, will place below
				d.baseSlots[i] = ""
				break
			else
				return true, i, false
			end
		end
	end
	-- Assign to specific slot (caller must ClearCreatureAtSlot first for that index)
	if type(optionalSlotIndex) == "number" and optionalSlotIndex >= 1 and optionalSlotIndex <= maxSlots then
		if not isCreatureOrEggUid(d, uid) then return false, nil, nil end
		removeFromAllSlots(d, uid)
		d.baseSlots[optionalSlotIndex] = tostring(uid)
		return true, optionalSlotIndex, true
	end
	-- First empty slot
	if countFilledSlots(d.baseSlots, maxSlots) >= maxSlots then return false, nil, nil end
	if not isCreatureOrEggUid(d, uid) then return false, nil, nil end
	removeFromAllSlots(d, uid)
	local slot = firstEmptySlot(d.baseSlots, maxSlots)
	d.baseSlots[slot] = tostring(uid)
	return true, slot, true
end

-- Assign uid to defense slot. optionalSlotIndex: if given, place at that slot (replacing any creature there; server clears that slot first).
-- optionalSlotIndex == 0 means explicit "remove from defense" (client Rem button). Returns success, slotIndex, added (true=we just placed in this call; false=removed or already in defense—server must not place again).
function PlayerDataManager.AssignToDefense(player, uid, optionalSlotIndex)
	local d = playerCache[player.UserId]
	if not d then return false, nil, nil end
	if not d.defenseSlots then d.defenseSlots = {} end
	local maxSlots = PlayerDataManager.GetMaxSlots(player, "defense")
	ensureSlotsDense(d.defenseSlots, maxSlots)
	countValidFilledSlotsAndSanitize(d, d.defenseSlots, maxSlots)
	local su = tostring(uid or "")
	-- Explicit remove: client sends 0 for "Rem" button. Clear ALL slots with this uid (fixes duplicate reappearing).
	if optionalSlotIndex == 0 or optionalSlotIndex == "0" then
		local cleared = false
		for i = 1, maxSlots do
			local v = d.defenseSlots[i] or d.defenseSlots[tostring(i)]
			if tostring(v or "") == su then
				d.defenseSlots[i] = ""
				d.defenseSlots[tostring(i)] = ""
				cleared = true
			end
		end
		return cleared, 0, false
	end
	-- Already in defense? Idempotent: treat as success but do NOT place again (prevents duplicate models on double-fire).
	for i = 1, maxSlots do
		if tostring(d.defenseSlots[i] or "") == su then
			if type(optionalSlotIndex) == "number" and optionalSlotIndex >= 1 and optionalSlotIndex <= maxSlots and optionalSlotIndex ~= i then
				d.defenseSlots[i] = ""
				break
			else
				return true, i, false
			end
		end
	end
	if type(optionalSlotIndex) == "number" and optionalSlotIndex >= 1 and optionalSlotIndex <= maxSlots then
		if not isCreatureOrEggUid(d, uid) then return false, nil, nil end
		removeFromAllSlots(d, uid)
		d.defenseSlots[optionalSlotIndex] = tostring(uid)
		return true, optionalSlotIndex, true
	end
	if countFilledSlots(d.defenseSlots, maxSlots) >= maxSlots then return false, nil, nil end
	if not isCreatureOrEggUid(d, uid) then return false, nil, nil end
	removeFromAllSlots(d, uid)
	local slot = firstEmptySlot(d.defenseSlots, maxSlots)
	d.defenseSlots[slot] = tostring(uid)
	return true, slot, true
end

-- Clear slot at index (e.g. when creature dies). Slot becomes available.
function PlayerDataManager.ClearSlotAt(player, slotType, index)
	local d = playerCache[player.UserId]
	if not d then return end
	local slots = (slotType == "income" or slotType == "base") and d.baseSlots or d.defenseSlots
	if slots and slots[index] then slots[index] = "" end
end

-- Count filled slots that reference creatures/eggs still in inventory. Clears stale slot UIDs so counts match reality.
function PlayerDataManager.GetFilledSlotCount(player, slotType)
	local d = playerCache[player.UserId]
	if not d then return 0 end
	local isBase = (slotType == "income" or slotType == "base")
	local slots = isBase and d.baseSlots or d.defenseSlots
	if not slots then return 0 end
	local maxSlots = PlayerDataManager.GetMaxSlots(player, isBase and "income" or "defense")
	return countValidFilledSlotsAndSanitize(d, slots, maxSlots)
end

-- Get slot index for uid (1-based), or nil if not found
function PlayerDataManager.GetSlotIndexForUid(player, slotType, uid)
	local d = playerCache[player.UserId]
	if not d then return nil end
	local isBase = (slotType == "income" or slotType == "base")
	local slots = isBase and d.baseSlots or d.defenseSlots
	if not slots then return nil end
	local maxSlots = PlayerDataManager.GetMaxSlots(player, isBase and "income" or "defense")
	local su = tostring(uid or "")
	for i = 1, maxSlots do
		local v = slots[i]
		if v and tostring(v) == su then return i end
	end
	return nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- BASE INTERACTION: Move / Swap creatures within same slot type
-- Used by walk-up base management (BaseInteractionClient + MainServer handlers).
-- ══════════════════════════════════════════════════════════════════════════════

--- Move a creature from its current slot to a different slot index within the same type.
-- @param player Player
-- @param slotType string "income" or "defense"
-- @param uid string creature UID to move
-- @param targetIndex number destination slot index (1-based)
-- @return ok boolean, message string
function PlayerDataManager.MoveSlotByUid(player, slotType, uid, targetIndex)
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	local isBase = (slotType == "income" or slotType == "base")
	local slots = isBase and d.baseSlots or d.defenseSlots
	if not slots then return false, "No slots" end
	local maxSlots = PlayerDataManager.GetMaxSlots(player, isBase and "income" or "defense")
	if type(targetIndex) ~= "number" or targetIndex < 1 or targetIndex > maxSlots then
		return false, "Invalid target slot"
	end
	-- Find current slot
	local fromIndex = nil
	local su = tostring(uid or "")
	for i = 1, maxSlots do
		local v = slots[i]
		if v and tostring(v) == su then fromIndex = i; break end
	end
	if not fromIndex then return false, "Creature not in slot" end
	if fromIndex == targetIndex then return false, "Already in that slot" end
	-- Target must be empty
	if slots[targetIndex] and slots[targetIndex] ~= "" then
		return false, "Target slot occupied"
	end
	-- Move
	slots[fromIndex] = ""
	slots[targetIndex] = uid
	return true, "Moved"
end

--- Swap two creatures' slot positions within the same type.
-- Both slots must contain creatures (non-empty).testt
-- @param player Player
-- @param slotType string "income" or "defense"
-- @param uidA string first creature UID
-- @param uidB string second creature UID
-- @return ok boolean, indexA number, indexB number t
function PlayerDataManager.SwapSlotsByUid(player, slotType, uidA, uidB)
	local d = playerCache[player.UserId]
	if not d then return false, 0, 0 end
	local isBase = (slotType == "income" or slotType == "base")
	local slots = isBase and d.baseSlots or d.defenseSlots
	if not slots then return false, 0, 0 end
	local maxSlots = PlayerDataManager.GetMaxSlots(player, isBase and "income" or "defense")
	local indexA, indexB = nil, nil
	local sA, sB = tostring(uidA or ""), tostring(uidB or "")
	for i = 1, maxSlots do
		local v = slots[i]
		if v and tostring(v) == sA then indexA = i end
		if v and tostring(v) == sB then indexB = i end
	end
	if not indexA then return false, 0, 0 end
	if not indexB then return false, 0, 0 end
	-- Swap
	slots[indexA] = uidB
	slots[indexB] = uidA
	return true, indexA, indexB
end

function PlayerDataManager.SetFavorite(player, uid)
	local d = playerCache[player.UserId]
	if not d then return false end
	-- Idempotent set: repeated SetFavorite(uid) calls should not clear favorite.
	-- Unfavorite is handled explicitly via ClearFavorite / empty uid event.
	if d.favoriteUid and tostring(d.favoriteUid) == tostring(uid) then return true end
	local found = false
	for _, e in ipairs(d.inventory) do if tostring(e.uid) == tostring(uid) then found = true break end end
	if not found then return false end
	removeFromAllSlots(d, uid)
	d.favoriteUid = tostring(uid)
	return true
end

function PlayerDataManager.ClearFavorite(player)
	local d = playerCache[player.UserId]
	if d then d.favoriteUid = nil end
end

function PlayerDataManager.GetFavorite(player)
	local d = playerCache[player.UserId]
	if not d or not d.favoriteUid then return nil end
	local su = tostring(d.favoriteUid)
	for _, e in ipairs(d.inventory) do
		if tostring(e.uid) == su then return e end
	end
	return nil
end

-- ====== BATTLE TEAM ======

function PlayerDataManager.AssignToBattle(player, uid, slotIndex)
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end

	slotIndex = tonumber(slotIndex)
	if not slotIndex or slotIndex < 1 or slotIndex > GRID_SLOTS then
		return false, "Invalid slot: " .. tostring(slotIndex)
	end

	if not d.battleTeam then d.battleTeam = {} end

	-- Clear slot request
	if not uid or uid == "" then
		d.battleTeam[slotIndex] = nil
		return true, "Cleared"
	end

	-- Verify creature exists
	local found = false
	for _, e in ipairs(d.inventory) do if tostring(e.uid) == tostring(uid) then found = true break end end
	if not found then return false, "Not in inventory" end

	-- Is this creature already on the battle team? (use pairs so string keys from serialization are found)
	local existingSlot = nil
	local su = tostring(uid)
	for key, val in pairs(d.battleTeam) do
		if val and tostring(val) == su then
			existingSlot = tonumber(key) or key
			break
		end
	end

	-- Count current team size (not counting this creature's current slot if moving)
	local teamCount = 0
	for key, val in pairs(d.battleTeam) do
		if val and val ~= "" then
			local k = tonumber(key) or key
			if not (existingSlot and k == existingSlot and val == uid) then
				teamCount = teamCount + 1
			end
		end
	end

	-- New creature joining team?
	if not existingSlot and teamCount >= MAX_BATTLE_TEAM then
		return false, "Team full (" .. teamCount .. "/" .. MAX_BATTLE_TEAM .. ")"
	end

	-- Who's currently in the target slot? (check both number and string key for serialization quirks)
	local targetOccupant = d.battleTeam[slotIndex] or d.battleTeam[tostring(slotIndex)]

	-- Remove creature from ALL other assignments (income/defense/favorite/battle)
	removeFromAllSlots(d, uid)

	-- Swap: if target was occupied AND creature was already on team
	if targetOccupant and existingSlot and targetOccupant ~= uid then
		d.battleTeam[existingSlot] = targetOccupant
	end

	-- Place creature (always use number key)
	d.battleTeam[slotIndex] = uid
	-- Keep only number keys so client/serialization never see mixed or string keys
	d.battleTeam = normalizeBattleTeam(d.battleTeam)
	return true, "Assigned"
end

function PlayerDataManager.GetBattleTeamEnabled(player)
	local d = playerCache[player.UserId]
	if not d then return true end
	return d.battleTeamEnabled ~= false  -- default true for nil/legacy
end

function PlayerDataManager.SetBattleTeamEnabled(player, enabled)
	local d = playerCache[player.UserId]
	if not d then return false end
	d.battleTeamEnabled = enabled
	return true
end

function PlayerDataManager.ToggleBattleTeamEnabled(player)
	local d = playerCache[player.UserId]
	if not d then return false end
	d.battleTeamEnabled = not (d.battleTeamEnabled ~= false)
	return d.battleTeamEnabled
end

function PlayerDataManager.RemoveFromBattle(player, uid)
	local d = playerCache[player.UserId]
	if not d or not d.battleTeam then return false end
	local su = tostring(uid or "")
	for key, val in pairs(d.battleTeam) do
		if val and tostring(val) == su then
			d.battleTeam[key] = nil
			return true
		end
	end
	return false
end

function PlayerDataManager.GetStealableCreatures(player)
	local d = playerCache[player.UserId]
	if not d then return {} end
	local protected = {}
	for _, u in ipairs(d.defenseSlots or {}) do if u and u ~= "" then protected[tostring(u)] = true end end
	if d.favoriteUid then protected[tostring(d.favoriteUid)] = true end
	local stealable = {}
	for _, e in ipairs(d.inventory) do
		if not protected[tostring(e.uid)] then table.insert(stealable, e) end
	end
	return stealable
end

function PlayerDataManager.GetInventoryData(player)
	return playerCache[player.UserId]
end

-- ====== REBIRTH (Pilot Rebirth System) ======

function PlayerDataManager.GetRebirthLevel(player)
	local d = playerCache[player.UserId]
	return (d and d.rebirthLevel) or 0
end

-- Count owned creatures by rarity (inventory only; eggs not counted for rebirth requirements)
function PlayerDataManager.CountCreaturesByRarity(player)
	local d = playerCache[player.UserId]
	if not d or not d.inventory then return {} end
	local counts = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0 }
	for _, e in ipairs(d.inventory) do
		local info = CreatureData.GetById(e.id)
		if info and info.rarity and counts[info.rarity] ~= nil then
			counts[info.rarity] = counts[info.rarity] + 1
		end
	end
	return counts
end

-- True if player has at least one of this creature at max level (for rebirth team requirement).
function PlayerDataManager.HasCreatureAtMaxLevel(player, creatureId)
	local d = playerCache[player.UserId]
	if not d or not d.inventory then return false end
	local maxLvl = CreatureData.GetMaxCreatureLevel(creatureId)
	for _, e in ipairs(d.inventory) do
		if e.id == creatureId and (e.level or 1) >= maxLvl then
			return true
		end
	end
	return false
end

-- Returns array of { creatureId, displayName, haveAtMaxLevel } for UI. teamArray = req.team from config.
function PlayerDataManager.GetRebirthTeamProgress(player, teamArray)
	if not teamArray or type(teamArray) ~= "table" then return {} end
	local out = {}
	for _, creatureId in ipairs(teamArray) do
		local info = CreatureData.GetById(creatureId)
		out[#out + 1] = {
			creatureId = creatureId,
			displayName = (info and info.displayName) or creatureId,
			haveAtMaxLevel = PlayerDataManager.HasCreatureAtMaxLevel(player, creatureId),
		}
	end
	return out
end

-- Get requirements for next rebirth (level = current rebirth + 1). Returns nil if max level.
function PlayerDataManager.GetRebirthRequirements(level)
	local cfg = GameConfig.RebirthLevels
	if not cfg or type(cfg) ~= "table" then return nil end
	local idx = level and (level + 1) or 1
	if idx < 1 or idx > #cfg then return nil end
	return cfg[idx]
end

-- Check if player can perform next rebirth (gold + team of 5 at max level, or legacy rarity counts).
function PlayerDataManager.CanRebirth(player)
	local lvl = PlayerDataManager.GetRebirthLevel(player)
	local req = PlayerDataManager.GetRebirthRequirements(lvl)
	if not req then return false, "Max rebirth level reached" end
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	if (d.coins or 0) < (req.gold or 0) then
		return false, "Need " .. tostring(req.gold) .. " gold (you have " .. tostring(d.coins or 0) .. ")"
	end
	-- Team-based: require each creature in team to be owned at max level
	if req.team and type(req.team) == "table" and #req.team > 0 then
		for i, creatureId in ipairs(req.team) do
			if not PlayerDataManager.HasCreatureAtMaxLevel(player, creatureId) then
				local info = CreatureData.GetById(creatureId)
				local name = (info and info.displayName) or creatureId
				return false, "Need " .. tostring(name) .. " at max level (slot " .. tostring(i) .. ")"
			end
		end
		return true
	end
	-- Legacy: rarity counts
	local counts = PlayerDataManager.CountCreaturesByRarity(player)
	for rarity, need in pairs(req.creatures or {}) do
		local have = counts[rarity] or 0
		if have < need then
			return false, "Need " .. tostring(need) .. " " .. rarity .. " creatures (you have " .. tostring(have) .. ")"
		end
	end
	return true
end

-- Perform rebirth: spend gold, clear base + battle team (and remove all creatures except favorite from inventory).
-- Favorite creature (if equipped) is kept in inventory. Returns success, errorMessage.
function PlayerDataManager.DoRebirth(player)
	local ok, err = PlayerDataManager.CanRebirth(player)
	if not ok then return false, err end
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	local req = PlayerDataManager.GetRebirthRequirements(PlayerDataManager.GetRebirthLevel(player))
	if not req then return false, "Invalid rebirth level" end
	-- Spend gold
	if not PlayerDataManager.SpendCoins(player, req.gold) then
		return false, "Not enough gold"
	end
	local keepUid = d.favoriteUid  -- keep favorite in inventory; it stays equipped
	local keepStr = tostring(keepUid or "")
	-- Build list of UIDs to remove: everything in inventory except favorite
	local toRemove = {}
	for _, e in ipairs(d.inventory) do
		if tostring(e.uid) ~= keepStr then toRemove[#toRemove + 1] = e.uid end
	end
	-- Remove each creature (this clears base/defense/battle slots via removeFromAllSlots)
	for _, uid in ipairs(toRemove) do
		PlayerDataManager.RemoveCreature(player, uid)
	end
	-- Clear base and battle slots explicitly (in case any slot referenced the kept favorite — we keep favorite but clear its slot assignments so they start fresh)
	for i = 1, MAX_SLOTS do
		if d.baseSlots then d.baseSlots[i] = "" end
		if d.defenseSlots then d.defenseSlots[i] = "" end
	end
	if d.battleTeam then
		for k in pairs(d.battleTeam) do d.battleTeam[k] = nil end
	end
	-- If we kept the favorite, it's still in inventory and still favoriteUid; it's just no longer on base/battle. Optionally re-add to inventory if it was removed from slots only (it wasn't removed — we only removed others). So inventory now = at most [favorite]. Good.
	d.rebirthLevel = (d.rebirthLevel or 0) + 1
	return true
end

-- Bonuses for a given rebirth level (for income, health, damage). Pass level or use player's current.
function PlayerDataManager.GetRebirthBonuses(player)
	local level = player and PlayerDataManager.GetRebirthLevel(player) or 0
	return PlayerDataManager.GetRebirthBonusesForLevel(level)
end

function PlayerDataManager.GetRebirthBonusesForLevel(level)
	level = level or 0
	if level <= 0 then
		return { passiveGold = 0, damageMultiplier = 1, healthBonus = 0 }
	end
	local passiveGold = (GameConfig.RebirthPassiveGoldPerLevel or 0) * level
	local mult = (GameConfig.RebirthDamageMultPerLevel or 0) * level
	local damageMultiplier = 1 + mult
	local healthBonus = (GameConfig.RebirthHealthBonusPerLevel or 0) * level
	return { passiveGold = passiveGold, damageMultiplier = damageMultiplier, healthBonus = healthBonus }
end

-- ====== Plot Assignment ======
-- Each join: assign a random unoccupied base (no reclaim; spawn at random base every time).

function PlayerDataManager.AssignPlot(player)
	local d = playerCache[player.UserId]
	if not d then return 0 end

	-- Release any previously claimed plot so it can be chosen by others
	if d.plotId and d.plotId > 0 and claimedPlotIds[d.plotId] == player.UserId then
		claimedPlotIds[d.plotId] = nil
	end
	d.plotId = 0

	-- Build list of unoccupied plots and pick one at random
	local available = {}
	for i = 1, GameConfig.MaxPlots do
		if not claimedPlotIds[i] then
			table.insert(available, i)
		end
	end
	if #available == 0 then return 0 end
	local pick = available[math.random(1, #available)]
	claimedPlotIds[pick] = player.UserId
	d.plotId = pick
	return pick
end

-- Returns set of plotIds currently claimed by an online player (for plot visibility).
function PlayerDataManager.GetClaimedPlotIds()
	local out = {}
	for plotId, _ in pairs(claimedPlotIds) do
		out[plotId] = true
	end
	return out
end

-- ====== Lifecycle ======

function PlayerDataManager.OnPlayerJoin(player)
	local success, data = loadFromStore(player.UserId)
	if success and data then
		local template = getDefaultData()
		for key, val in pairs(template) do
			if data[key] == nil then data[key] = val end
		end
		-- Backfill new stats fields for existing players
		local templateStats = getDefaultData().stats
		for statKey, defaultVal in pairs(templateStats) do
			if data.stats[statKey] == nil then data.stats[statKey] = defaultVal end
		end
		-- Backfill player level/floor fields for existing players
		if data.playerLevel == nil then data.playerLevel = 1 end
		if data.playerXP == nil then data.playerXP = 0 end
		if data.ownedFloors == nil then data.ownedFloors = {1} end
		if data.eggs == nil then data.eggs = {} end
		if data.rebirthLevel == nil then data.rebirthLevel = 0 end
		-- CRITICAL: normalize battleTeam keys from strings to numbers ONCE on load
		data.battleTeam = normalizeBattleTeam(data.battleTeam)
		if data.battleTeamEnabled == nil then data.battleTeamEnabled = true end  -- backfill for existing players
		-- CRITICAL: normalize baseSlots/defenseSlots keys (DataStore serializes number keys as strings)
		data.baseSlots = normalizeSlotArray(data.baseSlots)
		data.defenseSlots = normalizeSlotArray(data.defenseSlots)
		-- Normalize old inventory entries to include level/xp/variant
		for _, e in ipairs(data.inventory) do
			if e.level == nil then e.level = 1 end
			if e.xp == nil then e.xp = 0 end
			if e.variant == nil then e.variant = "Normal" end
		end
		-- Clear stale and duplicate slot UIDs. Stale = creature no longer in inventory. Duplicate = same UID in multiple slots (causes income creatures to spawn twice).
		do
			local validUids = {}
			for _, e in ipairs(data.inventory or {}) do if e and e.uid then validUids[tostring(e.uid)] = true end end
			for _, egg in ipairs(data.eggs or {}) do if egg and egg.uid then validUids[tostring(egg.uid)] = true end end
			local seenBase, seenDef = {}, {}
			for i = 1, MAX_SLOTS do
				local b = data.baseSlots and data.baseSlots[i]
				if b and b ~= "" then
					local sb = tostring(b)
					if not validUids[sb] then data.baseSlots[i] = ""
					elseif seenBase[sb] then data.baseSlots[i] = ""  -- duplicate
					else seenBase[sb] = true end
				end
				local d = data.defenseSlots and data.defenseSlots[i]
				if d and d ~= "" then
					local sd = tostring(d)
					if not validUids[sd] then data.defenseSlots[i] = ""
					elseif seenDef[sd] then data.defenseSlots[i] = ""  -- duplicate
					else seenDef[sd] = true end
				end
			end
			for key, uid in pairs(data.battleTeam or {}) do
				if uid and uid ~= "" and not validUids[uid] then
					data.battleTeam[key] = nil
				end
			end
			data.battleTeam = normalizeBattleTeam(data.battleTeam)
		end
		-- Clear removed themes (OceanBreeze, InvisibleBase) so plots return to visible
		if data.exterior then
			if data.exterior.owned then
				data.exterior.owned["OceanBreeze"] = nil
				data.exterior.owned["InvisibleBase"] = nil
			end
			if data.exterior.equipped == "OceanBreeze" or data.exterior.equipped == "InvisibleBase" then
				data.exterior.equipped = nil
			end
		end
		playerCache[player.UserId] = data
	else
		playerCache[player.UserId] = getDefaultData()
	end
	PlayerDataManager.AssignPlot(player)
	PlayerDataManager.SavePlayer(player)

	-- Push initial coins to client immediately
	task.spawn(function()
		task.wait(1)
		local d = playerCache[player.UserId]
		if d then
			local events = game.ReplicatedStorage:FindFirstChild("Events")
			local coinsEvt = events and events:FindFirstChild("CoinsUpdate")
			if coinsEvt then
				coinsEvt:FireClient(player, d.coins)
			end
		end
	end)
end

function PlayerDataManager.OnPlayerLeave(player)
	local d = playerCache[player.UserId]
	if d then
		-- Release plot so another player can claim it
		if d.plotId and d.plotId > 0 and claimedPlotIds[d.plotId] == player.UserId then
			claimedPlotIds[d.plotId] = nil
		end
		saveToStore(player.UserId, d)
		playerCache[player.UserId] = nil
	end
end

function PlayerDataManager.SaveAll()
	for userId, d in pairs(playerCache) do saveToStore(userId, d) end
end

function PlayerDataManager.SavePlayer(player)
	local d = playerCache[player.UserId]
	if d then saveToStore(player.UserId, d) end
end

-- -- GEMS (premium currency) --

function PlayerDataManager.GetGems(player)
	local d = playerCache[player.UserId]; return d and d.gems or 0
end

function PlayerDataManager.AddGems(player, amount)
	local d = playerCache[player.UserId]; if not d then return false end
	d.gems = (d.gems or 0) + amount; return true
end

function PlayerDataManager.SpendGems(player, amount)
	local d = playerCache[player.UserId]; if not d then return false end
	if (d.gems or 0) < amount then return false end
	d.gems = d.gems - amount; return true
end

-- -- FRIENDS LIST (laser door access) --

function PlayerDataManager.GetFriendsList(player)
	local d = playerCache[player.UserId]; if not d then return {} end
	return d.friendsList or {}
end

function PlayerDataManager.AddFriend(player, friendUserId)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.friendsList then d.friendsList = {} end
	for _, fid in ipairs(d.friendsList) do if fid == friendUserId then return false end end
	table.insert(d.friendsList, friendUserId); return true
end

function PlayerDataManager.RemoveFriend(player, friendUserId)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.friendsList then return false end
	for i, fid in ipairs(d.friendsList) do
		if fid == friendUserId then table.remove(d.friendsList, i); return true end
	end
	return false
end

function PlayerDataManager.IsFriend(player, otherUserId)
	local d = playerCache[player.UserId]; if not d or not d.friendsList then return false end
	for _, fid in ipairs(d.friendsList) do if fid == otherUserId then return true end end
	return false
end

-- -- ACTIVE BUFFS --

function PlayerDataManager.GetActiveBuffs(player)
	local d = playerCache[player.UserId]; if not d then return {} end
	if not d.activeBuffs then d.activeBuffs = {} end
	-- Clean expired
	local now = tick()
	for buffId, info in pairs(d.activeBuffs) do
		if info.expiresAt and info.expiresAt <= now then d.activeBuffs[buffId] = nil end
	end
	return d.activeBuffs
end

function PlayerDataManager.ActivateBuff(player, buffId, duration)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.activeBuffs then d.activeBuffs = {} end
	d.activeBuffs[buffId] = { expiresAt = tick() + duration, activatedAt = tick() }
	return true
end

function PlayerDataManager.HasBuff(player, buffId)
	local d = playerCache[player.UserId]; if not d or not d.activeBuffs then return false end
	local info = d.activeBuffs[buffId]
	if not info then return false end
	if info.expiresAt and info.expiresAt <= tick() then d.activeBuffs[buffId] = nil; return false end
	return true
end

-- -- COSMETICS --

function PlayerDataManager.GetCosmetics(player)
	local d = playerCache[player.UserId]; if not d then return {} end
	if not d.cosmetics then d.cosmetics = {owned = {}, equipped = {}} end
	return d.cosmetics
end

function PlayerDataManager.OwnsCosmetic(player, cosmeticId)
	local d = playerCache[player.UserId]; if not d or not d.cosmetics then return false end
	return d.cosmetics.owned and d.cosmetics.owned[cosmeticId] == true
end

function PlayerDataManager.PurchaseCosmetic(player, cosmeticId)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.cosmetics then d.cosmetics = {owned = {}, equipped = {}} end
	if not d.cosmetics.owned then d.cosmetics.owned = {} end
	d.cosmetics.owned[cosmeticId] = true; return true
end

function PlayerDataManager.EquipCosmetic(player, slot, cosmeticId)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.cosmetics then d.cosmetics = {owned = {}, equipped = {}} end
	if not d.cosmetics.equipped then d.cosmetics.equipped = {} end
	if cosmeticId and not d.cosmetics.owned[cosmeticId] then return false end
	d.cosmetics.equipped[slot] = cosmeticId; return true
end

-- -- BASE EXTERIOR (theme for base plot) --
function PlayerDataManager.GetExterior(player)
	local d = playerCache[player.UserId]; if not d then return {owned = {}, equipped = nil} end
	if not d.exterior then d.exterior = {owned = {}, equipped = nil} end
	return d.exterior
end

function PlayerDataManager.OwnsExterior(player, exteriorId)
	local d = playerCache[player.UserId]; if not d or not d.exterior then return false end
	return d.exterior.owned and d.exterior.owned[exteriorId] == true
end

function PlayerDataManager.PurchaseExterior(player, exteriorId)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.exterior then d.exterior = {owned = {}, equipped = nil} end
	if not d.exterior.owned then d.exterior.owned = {} end
	d.exterior.owned[exteriorId] = true
	return true
end

function PlayerDataManager.SetEquippedExterior(player, exteriorId)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.exterior then d.exterior = {owned = {}, equipped = nil} end
	if exteriorId and not (d.exterior.owned and d.exterior.owned[exteriorId]) then return false end
	d.exterior.equipped = exteriorId
	return true
end

-- -- BASE COLOR (walls, stairs, points, combiner, recycler) --
function PlayerDataManager.GetBaseColor(player)
	local d = playerCache[player.UserId]; if not d then return {owned = {}, equipped = nil} end
	if not d.baseColor then d.baseColor = {owned = {}, equipped = nil} end
	return d.baseColor
end

function PlayerDataManager.OwnsBaseColor(player, colorId)
	local d = playerCache[player.UserId]; if not d or not d.baseColor then return false end
	return d.baseColor.owned and d.baseColor.owned[colorId] == true
end

function PlayerDataManager.PurchaseBaseColor(player, colorId)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.baseColor then d.baseColor = {owned = {}, equipped = nil} end
	if not d.baseColor.owned then d.baseColor.owned = {} end
	d.baseColor.owned[colorId] = true
	return true
end

function PlayerDataManager.SetEquippedBaseColor(player, colorId)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.baseColor then d.baseColor = {owned = {}, equipped = nil} end
	if colorId and not (d.baseColor.owned and d.baseColor.owned[colorId]) then return false end
	d.baseColor.equipped = colorId
	return true
end

-- -- PLAYER LEVEL / XP --

-- XP needed for a given player level
function PlayerDataManager.PlayerXPForLevel(level)
	if level <= 1 then return 0 end
	return math.floor(GameConfig.PlayerBaseXP * (GameConfig.PlayerXPScaling ^ (level - 2)))
end

-- Add XP to the player, auto-level if threshold met. Returns newLevel, didLevelUp
function PlayerDataManager.AddPlayerXP(player, amount)
	local d = playerCache[player.UserId]
	if not d then return 0, false end
	-- XP boost buff: 2x XP
	if PlayerDataManager.HasBuff(player, "xpboost") then
		amount = amount * 2
	end
	d.playerLevel = d.playerLevel or 1
	d.playerXP = d.playerXP or 0
	if d.playerLevel >= GameConfig.PlayerMaxLevel then return d.playerLevel, false end
	d.playerXP = d.playerXP + amount
	local leveled = false
	while d.playerLevel < GameConfig.PlayerMaxLevel do
		local needed = PlayerDataManager.PlayerXPForLevel(d.playerLevel + 1)
		if d.playerXP >= needed then
			d.playerXP = d.playerXP - needed
			d.playerLevel = d.playerLevel + 1
			leveled = true
		else break end
	end
	return d.playerLevel, leveled
end

-- Get player level info: level, currentXP, xpNeededForNext
function PlayerDataManager.GetPlayerLevel(player)
	local d = playerCache[player.UserId]
	if not d then return 1, 0, 100 end
	local lvl = d.playerLevel or 1
	local xp = d.playerXP or 0
	local needed = PlayerDataManager.PlayerXPForLevel(lvl + 1)
	return lvl, xp, needed
end

-- -- FLOOR OWNERSHIP --

function PlayerDataManager.OwnsFloor(player, floorNum)
	local d = playerCache[player.UserId]
	if not d or not d.ownedFloors then return floorNum == 1 end
	for _, f in ipairs(d.ownedFloors) do
		if f == floorNum then return true end
	end
	return false
end

function PlayerDataManager.BuyFloor(player, floorNum)
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	if PlayerDataManager.OwnsFloor(player, floorNum) then return false, "Already owned" end
	local floor2Req = (GameConfig.DebugFloor2Level2 and 2) or GameConfig.Floor2LevelReq
	local reqLevel = floorNum == 2 and floor2Req or GameConfig.Floor3LevelReq
	if (d.playerLevel or 1) < reqLevel then return false, "Requires level " .. reqLevel end
	if floorNum == 3 and not PlayerDataManager.OwnsFloor(player, 2) then return false, "Buy Floor 2 first" end
	local cost = floorNum == 2 and GameConfig.Floor2Cost or GameConfig.Floor3Cost
	if d.coins < cost then return false, "Not enough coins" end
	d.coins = d.coins - cost
	table.insert(d.ownedFloors, floorNum)
	return true, "Floor " .. floorNum .. " unlocked!"
end

-- Dynamic slot limit based on number of owned floors
function PlayerDataManager.GetMaxSlots(player, slotType)
	local d = playerCache[player.UserId]
	if not d then return 6 end
	local floors = d.ownedFloors or {1}
	local perFloor = slotType == "defense" and GameConfig.DefensePointsPerFloor or GameConfig.IncomePointsPerFloor
	return #floors * perFloor
end

-- -- SELL CREATURE --

function PlayerDataManager.SellCreature(player, uid)
	local d = playerCache[player.UserId]
	if not d then return false, 0 end
	local entry = nil
	local su = tostring(uid or "")
	for _, e in ipairs(d.inventory) do
		if tostring(e.uid) == su then entry = e; break end
	end
	if not entry then return false, 0 end
	local CreatureData = require(game.ReplicatedStorage.Modules.CreatureData)
	local info = CreatureData.GetById(entry.id)
	if not info then return false, 0 end
	-- Sell price = captureCost (from rarity) * creature level
	local rarityInfo = CreatureData.Rarities and CreatureData.Rarities[info.rarity]
	local baseCost = (rarityInfo and rarityInfo.captureCost) or (info.baseIncome and info.baseIncome * 5) or 50
	local sellPrice = math.floor(baseCost * (entry.level or 1))
	removeFromAllSlots(d, uid)
	for i, e in ipairs(d.inventory) do
		if tostring(e.uid) == su then table.remove(d.inventory, i); break end
	end
	d.coins = d.coins + sellPrice
	return true, sellPrice
end

-- -- LEADERBOARD HELPERS --

function PlayerDataManager.GetLeaderboardStats(player)
	local d = playerCache[player.UserId]
	if not d then return nil end
	return {
		totalIncome = d.stats.totalIncome or 0,
		arenaWins = d.stats.arenaWins or 0,
		arenaMaxStreak = d.stats.arenaMaxStreak or 0,
		monstersOwned = #d.inventory,
		playerName = player.Name,
		userId = player.UserId,
	}
end

function PlayerDataManager.GetAllOnlineData()
	local result = {}
	for userId, data in pairs(playerCache) do
		result[userId] = data
	end
	return result
end

function PlayerDataManager.Init()
	Players.PlayerAdded:Connect(function(p) PlayerDataManager.OnPlayerJoin(p) end)
	Players.PlayerRemoving:Connect(function(p) PlayerDataManager.OnPlayerLeave(p) end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function() PlayerDataManager.OnPlayerJoin(p) end)
	end
	task.spawn(function() while true do task.wait(AUTO_SAVE_INTERVAL); PlayerDataManager.SaveAll() end end)
	game:BindToClose(function() PlayerDataManager.SaveAll() end)
end

return PlayerDataManager