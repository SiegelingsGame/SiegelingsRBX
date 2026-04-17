-- PlayerDataManager.lua - ServerScriptService (ModuleScript)
-- Manages all persistent player data.
-- Last updated: 2026-03-28 14:30

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local GameConfig = require(game.ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(game.ReplicatedStorage.Modules.CreatureData)
local IngredientData = require(game.ReplicatedStorage.Modules.IngredientData)
local PlayerWorldStats = require(game.ReplicatedStorage.Modules:WaitForChild("PlayerWorldStats"))

local PlayerDataManager = {}

local DATA_STORE_NAME = "MonsterSiege_PlayerData_v1"
local AUTO_SAVE_INTERVAL = 120
local MAX_RETRIES = 3
-- FIX #22: MaxBattleTeamSize is the GRID size (9 slots in 3x3 layout).
-- MaxBattleTeamCreatures is the actual creature limit (default 5).
-- Previously used grid size as creature limit, allowing 9 creatures on a 5-creature team.
local MAX_BATTLE_TEAM = GameConfig.MaxBattleTeamCreatures or 5
local GRID_SLOTS = 9

local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)
local playerCache = {}
local AchievementObserver = nil
local EleminionObserver = nil
-- plotId -> userId: atomic source of truth to prevent two players claiming same base
local claimedPlotIds = {}

function PlayerDataManager.BindAchievementObserver(observer)
	AchievementObserver = observer
end

function PlayerDataManager.BindEleminionObserver(observer)
	EleminionObserver = observer
end

function PlayerDataManager.NotifyAchievement(eventName, ...)
	local observer = AchievementObserver
	local handler = observer and observer[eventName]
	if type(handler) ~= "function" then
		return
	end

	local args = table.pack(...)
	task.defer(function()
		local ok, err = pcall(function()
			handler(observer, table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn("[PlayerDataManager] Achievement event failed:", tostring(eventName), tostring(err))
		end
	end)
end

function PlayerDataManager.NotifyEleminion(eventName, ...)
	local observer = EleminionObserver
	local handler = observer and observer[eventName]
	if type(handler) ~= "function" then
		return
	end

	local args = table.pack(...)
	task.defer(function()
		local ok, err = pcall(function()
			handler(observer, table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn("[PlayerDataManager] Eleminion event failed:", tostring(eventName), tostring(err))
		end
	end)
end

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
		stats        = { totalCaptured = 0, totalRaids = 0, defenseKills = 0, arenaWins = 0, arenaLosses = 0, arenaWinStreak = 0, arenaMaxStreak = 0, totalIncome = 0 },
		settings     = {},
		plotId       = 0,
		baseCreaturePositions = {},
		friendsList  = {},  -- {userId1, userId2, ...} allowed through laser door
		activeBuffs  = {},  -- {buffId = {expiresAt = tick, ...}, ...}
		cosmetics    = {owned = {}, equipped = {}},  -- {owned = {id1=true, ...}, equipped = {trail="", aura=""}}
		exterior     = {owned = {}, equipped = nil}, -- nil equipped = standard gray base
		baseColor    = {owned = {}, equipped = nil}, -- foundation colors: floors, ramp, stairs, plot center
		playerLevel  = 1,
		playerXP     = 0,
		ownedFloors  = {1},  -- array of floor numbers owned; starts with Floor 1
		decorSlots   = {},   -- { ["floor_slot"] = { kind="statue"|"furniture", creatureId?, furnitureId? } }
		eggs         = {},   -- { { uid, creatureId, level, rarity, hatchMinutes, createdAt }, ... }; place on base/defense to hatch
		rebirthLevel = 0,    -- pilot rebirth level (0 = never rebirthed); bonuses apply to passive gold, damage, health
		-- Zone doors / sigils: inner legendaries + gym wins store SiegeKnight entries by zone id (Ocean, Desert, Electric, Cave); four unlock one Biome Pass
		sigils             = {},  -- { Ocean = true, Desert = true, ... }
		firstZoneDoorOpened = nil, -- zoneId opened with "4 sigils" choice, or nil
		zoneKeysFromGyms   = {},  -- { Ocean = true, ... } key earned by winning that zone's gym
		doorsUnlocked      = {},  -- { Ocean = true, ... } which ZoneDoors are open

		-- Achievements: { [achievementId] = { progress = number, unlocked = boolean, unlockedAt = unixTime? }, ... }
		-- Some achievements are derived from existing stats/inventory; others are driven by systems via AchievementsSystem.
		achievements = {},
		achievementMetrics = { counters = {}, best = {}, sets = {} },
		ingredientBank = {}, -- { [ingredientId] = count }
		eleminions = {}, -- { [element] = { affinity = number, quests = { [questIndex] = { claimed, completed, objectives = { [objectiveIndex] = number } } } } }
	}
end

-- Per-player campfire mix (server-only; not persisted)
local craftingMixByUserId = {}

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

-- DataStore / JSON can yield {}, missing 1, or string keys. Empty {} is truthy so `or {1}` never runs elsewhere.
local function normalizeOwnedFloors(raw)
	if type(raw) ~= "table" then
		return {1}
	end
	local seen = {}
	local out = {}
	for k, v in pairs(raw) do
		local n = tonumber(v) or tonumber(k)
		if n and n >= 1 and n <= 6 then
			if not seen[n] then
				seen[n] = true
				table.insert(out, n)
			end
		end
	end
	table.sort(out)
	if #out == 0 then
		return {1}
	end
	if not seen[1] then
		table.insert(out, 1)
		table.sort(out)
	end
	return out
end

local function normalizeOwnedLookup(raw)
	local fixed = {}
	if type(raw) ~= "table" then
		return fixed
	end

	for key, value in pairs(raw) do
		if type(key) == "string" and key ~= "" and (value == true or value == "true" or value == 1) then
			fixed[key] = true
		elseif type(value) == "string" and value ~= "" then
			fixed[value] = true
		end
	end

	return fixed
end

local function normalizeCosmeticsData(cosmetics)
	local fixed = { owned = {}, equipped = {} }
	if type(cosmetics) ~= "table" then
		return fixed
	end

	fixed.owned = normalizeOwnedLookup(cosmetics.owned or cosmetics)
	if type(cosmetics.equipped) == "table" then
		for slot, cosmeticId in pairs(cosmetics.equipped) do
			if type(slot) == "string" and type(cosmeticId) == "string" and cosmeticId ~= "" then
				fixed.equipped[slot] = cosmeticId
				fixed.owned[cosmeticId] = true
			end
		end
	end

	return fixed
end

local function normalizeSingleUnlockData(data)
	local fixed = { owned = {}, equipped = nil }
	if type(data) ~= "table" then
		return fixed
	end

	fixed.owned = normalizeOwnedLookup(data.owned or data)
	local equipped = data.equipped
	if type(equipped) == "string" and equipped ~= "" then
		fixed.equipped = equipped
		fixed.owned[equipped] = true
	end

	return fixed
end

-- Accepts id->count maps, id->{id,qty} entries (serialization quirks), and array-shaped banks from DataStore/JSON.
local function normalizeIngredientBank(raw)
	local fixed = {}
	if type(raw) ~= "table" then
		return fixed
	end
	for k, v in pairs(raw) do
		if type(v) == "table" and v.id then
			local id = tostring(v.id)
			local n = math.floor(tonumber(v.qty or v.count or v.n) or 0)
			if id ~= "" and n > 0 then
				fixed[id] = (fixed[id] or 0) + n
			end
		else
			local id = tostring(k)
			local n = math.floor(tonumber(v) or 0)
			if id ~= "" and n > 0 then
				fixed[id] = (fixed[id] or 0) + n
			end
		end
	end
	if next(fixed) == nil then
		for _, e in ipairs(raw) do
			if type(e) == "table" and e.id then
				local id = tostring(e.id)
				local n = math.floor(tonumber(e.qty or e.count or e.n) or 0)
				if id ~= "" and n > 0 then
					fixed[id] = (fixed[id] or 0) + n
				end
			end
		end
	end
	return fixed
end

local function normalizeEleminionData(raw)
	local fixed = {}
	if type(raw) ~= "table" then
		return fixed
	end

	for element, state in pairs(raw) do
		if type(element) == "string" and type(state) == "table" then
			local quests = {}
			for questKey, questState in pairs(state.quests or {}) do
				local questIndex = tonumber(questKey)
				if questIndex then
					local objectives = {}
					for objectiveKey, value in pairs((type(questState) == "table" and questState.objectives) or {}) do
						local objectiveIndex = tonumber(objectiveKey)
						local numericValue = tonumber(value)
						if not numericValue and value == true then
							numericValue = 1
						end
						if objectiveIndex and numericValue and numericValue > 0 then
							objectives[objectiveIndex] = math.floor(numericValue)
						end
					end
					quests[questIndex] = {
						claimed = type(questState) == "table" and questState.claimed == true or false,
						completed = type(questState) == "table" and questState.completed == true or false,
						completedAt = type(questState) == "table" and tonumber(questState.completedAt) or nil,
						claimedAt = type(questState) == "table" and tonumber(questState.claimedAt) or nil,
						objectives = objectives,
					}
				end
			end

			fixed[element] = {
				affinity = math.max(0, math.floor(tonumber(state.affinity) or 0)),
				quests = quests,
			}
		end
	end

	return fixed
end

local function getMaxMixIngredients()
	local cook = GameConfig.Cooking or {}
	return tonumber(cook.MaxMixIngredients) or 4
end

--- mix[1..max] = { id, qty } or false (empty slot). Indices are preserved (sparse layouts like slots 2–4 only stay valid).
local function ensureFixedMixSlots(mix, maxMix)
	maxMix = maxMix or getMaxMixIngredients()
	for i = 1, maxMix do
		local e = mix[i]
		if e == false or e == nil then
			mix[i] = false
		elseif type(e) == "table" then
			local id = tostring(e.id or "")
			local q = math.floor(tonumber(e.qty) or 0)
			if id == "" or q <= 0 then
				mix[i] = false
			else
				mix[i] = { id = id, qty = q }
			end
		else
			mix[i] = false
		end
	end
	for k in pairs(mix) do
		if type(k) == "number" then
			if k < 1 or k > maxMix or k % 1 ~= 0 then
				mix[k] = nil
			end
		else
			mix[k] = nil
		end
	end
end

local function mixTotalQty(mix)
	local t = 0
	for _, e in pairs(mix) do
		if type(e) == "table" and (tonumber(e.qty) or 0) > 0 then
			t = t + e.qty
		end
	end
	return t
end

local function mixCountForId(mix, id)
	local t = 0
	for _, e in pairs(mix) do
		if type(e) == "table" and e.id == id then
			t = t + (tonumber(e.qty) or 0)
		end
	end
	return t
end

-- Count how many slots are filled in battleTeam (uses pairs so string keys from serialization are counted)
local function countBattleTeam(bt)
	local c = 0
	for _, uid in pairs(bt or {}) do
		if uid and uid ~= "" then c = c + 1 end
	end
	return c
end

local function trimString(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Nickname safety filter:
-- - common curse words
-- - common sexual terms
-- - common racist slur stems
-- Uses both raw lowercase text and a compacted/leet-normalized form to catch simple bypasses.
local BANNED_NICKNAME_TERMS = {
	-- Curse words
	"fuck", "shit", "bitch", "asshole", "bastard", "dick", "pussy", "cunt",
	"motherfucker", "mf", "wtf", "fuk", "fck", "sh1t", "biatch",
	-- Sexual content
	"sex", "sexy", "porn", "porno", "nude", "naked", "boobs", "tits", "penis",
	"vagina", "blowjob", "handjob", "cum", "orgasm", "fetish", "bdsm", "onlyfans",
	-- Racist slur stems (stems used to catch inflections/plurals)
	"nigg", "fagg", "chink", "gook", "kike", "spic", "wetback", "paki", "coon",
}

local function normalizeNicknameForFilter(s)
	local t = string.lower(tostring(s or ""))
	-- Basic leetspeak substitutions.
	t = t:gsub("0", "o")
		:gsub("1", "i")
		:gsub("3", "e")
		:gsub("4", "a")
		:gsub("5", "s")
		:gsub("7", "t")
		:gsub("@", "a")
		:gsub("%$", "s")
	-- Keep alphanumeric only for compact matching.
	t = t:gsub("[^%a%d]", "")
	return t
end

local function nicknameHasBannedContent(name)
	local raw = string.lower(tostring(name or ""))
	local compact = normalizeNicknameForFilter(name)
	for _, term in ipairs(BANNED_NICKNAME_TERMS) do
		if string.find(raw, term, 1, true) or string.find(compact, term, 1, true) then
			return true
		end
	end
	return false
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

-- -------- Sigils / Zone doors --------
local ZONE_IDS = GameConfig.ZoneDoorZoneIds or { "Ocean", "Desert", "Electric", "Cave" }

function PlayerDataManager.AddSigil(player, zoneId)
	local d = playerCache[player.UserId]
	if not d then return end
	if not d.sigils then d.sigils = {} end
	d.sigils[zoneId] = true
	PlayerDataManager.NotifyAchievement("OnSigilEarned", player, zoneId)
end

function PlayerDataManager.HasSigil(player, zoneId)
	local d = playerCache[player.UserId]
	return d and d.sigils and (d.sigils[zoneId] == true or d.sigils[zoneId] == "true")
end

function PlayerDataManager.GetSigilCount(player)
	local d = playerCache[player.UserId]
	if not d or not d.sigils then return 0 end
	local n = 0
	for _, zid in ipairs(ZONE_IDS) do
		if d.sigils[zid] == true or d.sigils[zid] == "true" then n = n + 1 end
	end
	return n
end

function PlayerDataManager.CanSpendFourSigils(player)
	local d = playerCache[player.UserId]
	return d and (d.firstZoneDoorOpened == nil or d.firstZoneDoorOpened == "") and PlayerDataManager.GetSigilCount(player) >= 4
end

function PlayerDataManager.SpendFourSigilsOpenDoor(player, zoneId)
	if not PlayerDataManager.CanSpendFourSigils(player) then return false end
	local valid = false
	for _, zid in ipairs(ZONE_IDS) do
		if zid == zoneId then valid = true; break end
	end
	if not valid then return false end
	local d = playerCache[player.UserId]
	d.firstZoneDoorOpened = zoneId
	if not d.doorsUnlocked then d.doorsUnlocked = {} end
	d.doorsUnlocked[zoneId] = true
	PlayerDataManager.NotifyAchievement("OnDoorUnlocked", player, zoneId, "sigils")
	return true
end

function PlayerDataManager.AddZoneKeyFromGym(player, zoneId)
	local d = playerCache[player.UserId]
	if not d then return end
	if not d.zoneKeysFromGyms then d.zoneKeysFromGyms = {} end
	d.zoneKeysFromGyms[zoneId] = true
	PlayerDataManager.NotifyAchievement("OnGymWin", player, zoneId)
end

function PlayerDataManager.HasZoneKey(player, zoneId)
	local d = playerCache[player.UserId]
	return d and d.zoneKeysFromGyms and (d.zoneKeysFromGyms[zoneId] == true or d.zoneKeysFromGyms[zoneId] == "true")
end

-- Furthest exterior zone along GameConfig.ZoneDoorZoneIds that this player has already opened (used for Arena Pass source).
function PlayerDataManager.GetLastUnlockedExteriorZone(player)
	local d = playerCache[player.UserId]
	if not d or not d.doorsUnlocked then
		return nil
	end
	local last = nil
	for _, zid in ipairs(ZONE_IDS) do
		if d.doorsUnlocked[zid] == true or d.doorsUnlocked[zid] == "true" then
			last = zid
		end
	end
	return last
end

function PlayerDataManager.HasAnyExteriorDoorUnlocked(player)
	local d = playerCache[player.UserId]
	if not d or not d.doorsUnlocked then
		return false
	end
	for _, zid in ipairs(ZONE_IDS) do
		if d.doorsUnlocked[zid] == true or d.doorsUnlocked[zid] == "true" then
			return true
		end
	end
	return false
end

-- Open an exterior gate using one Arena Pass (gym key) from the latest unlocked exterior biome. Consumes that pass.
function PlayerDataManager.UnlockDoorWithKey(player, targetZoneId)
	local d = playerCache[player.UserId]
	if not d then
		return false, "No data"
	end
	if PlayerDataManager.IsDoorUnlocked(player, targetZoneId) then
		return true
	end
	local validTarget = false
	for _, zid in ipairs(ZONE_IDS) do
		if zid == targetZoneId then
			validTarget = true
			break
		end
	end
	if not validTarget then
		return false, "Invalid zone"
	end
	local passZone = PlayerDataManager.GetLastUnlockedExteriorZone(player)
	if not passZone then
		return false, "Open your first exterior gate before using Arena Passes"
	end
	if not PlayerDataManager.HasZoneKey(player, passZone) then
		return false, "Need an Arena Pass from your latest exterior biome (win at that zone's Gym)"
	end
	if not d.doorsUnlocked then
		d.doorsUnlocked = {}
	end
	d.doorsUnlocked[targetZoneId] = true
	if not d.zoneKeysFromGyms then
		d.zoneKeysFromGyms = {}
	end
	d.zoneKeysFromGyms[passZone] = nil
	PlayerDataManager.NotifyAchievement("OnDoorUnlocked", player, targetZoneId, "arenaPass")
	PlayerDataManager.SavePlayer(player)
	return true
end

function PlayerDataManager.IsDoorUnlocked(player, zoneId)
	local d = playerCache[player.UserId]
	return d and d.doorsUnlocked and (d.doorsUnlocked[zoneId] == true or d.doorsUnlocked[zoneId] == "true")
end

-- Spend exactly one of each inner-zone boss Legendary (Fire/Ice/Wind/Earth) to open this exterior gate for this player.
function PlayerDataManager.SpendFourBossLegendariesOpenDoor(player, zoneId, uids)
	if not player or not player.Parent then return false, "Invalid player" end
	if type(zoneId) ~= "string" or zoneId == "" then return false, "Invalid zone" end
	local validZone = false
	for _, zid in ipairs(ZONE_IDS) do
		if zid == zoneId then
			validZone = true
			break
		end
	end
	if not validZone then return false, "Invalid zone" end
	if PlayerDataManager.IsDoorUnlocked(player, zoneId) then
		return false, "This gate is already open for you"
	end
	if PlayerDataManager.HasAnyExteriorDoorUnlocked(player) then
		return false, "Further gates require an Arena Pass from the Gym in your latest unlocked exterior biome"
	end
	if type(uids) ~= "table" or #uids ~= 4 then
		return false, "Select exactly four creatures"
	end
	local seen = {}
	for _, u in ipairs(uids) do
		if type(u) ~= "string" or u == "" then return false, "Invalid creature" end
		if seen[u] then return false, "Duplicate creature in selection" end
		seen[u] = true
	end

	local elements = GameConfig.ElementalBossElements or { "Fire", "Ice", "Wind", "Earth" }
	local requiredIds = {}
	for _, el in ipairs(elements) do
		local bid = CreatureData.GetBossCreatureId(el, false)
		if not bid then return false, "Boss creature data missing" end
		table.insert(requiredIds, bid)
	end
	table.sort(requiredIds)

	local d = playerCache[player.UserId]
	if not d or not d.inventory then return false, "No data" end

	local collected = {}
	for _, uid in ipairs(uids) do
		local entry = nil
		for _, e in ipairs(d.inventory) do
			if e and tostring(e.uid) == tostring(uid) then
				entry = e
				break
			end
		end
		if not entry then return false, "Creature not in inventory" end
		table.insert(collected, entry.id)
	end
	table.sort(collected)

	if #requiredIds ~= #collected then return false, "Wrong creatures" end
	for i = 1, #requiredIds do
		if collected[i] ~= requiredIds[i] then
			return false, "Place one of each inner Legendary boss (Fire, Ice, Wind, Earth)"
		end
	end

	for _, uid in ipairs(uids) do
		PlayerDataManager.RemoveCreature(player, uid)
	end

	if not d.doorsUnlocked then d.doorsUnlocked = {} end
	d.doorsUnlocked[zoneId] = true
	if d.firstZoneDoorOpened == nil or d.firstZoneDoorOpened == "" then
		d.firstZoneDoorOpened = zoneId
	end
	PlayerDataManager.NotifyAchievement("OnDoorUnlocked", player, zoneId, "legendaries")
	PlayerDataManager.SavePlayer(player)
	return true
end

function PlayerDataManager.AddCreature(player, creatureId, level, xp, variant, existingUid, context)
	local d = playerCache[player.UserId]
	if not d or #d.inventory >= GameConfig.MaxInventorySize then return nil end
	-- Use existing unique id when provided (e.g. from captured world creature) so creature data is maintained
	local uid = (type(existingUid) == "string" and #existingUid > 0) and existingUid or PlayerDataManager.GenerateUID()
	variant = variant or "Normal"
	table.insert(d.inventory, { id = creatureId, uid = uid, level = level or 1, xp = xp or 0, variant = variant })
	local source = context and context.source
	if source == "capture" then
		PlayerDataManager.NotifyAchievement("OnCapture", player, creatureId, context)
		PlayerDataManager.NotifyEleminion("OnCreatureCaptured", player, creatureId, level or 1, context)
	else
		PlayerDataManager.NotifyAchievement("OnAcquireCreature", player, creatureId, context)
	end
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
	if PlayerDataManager.HasBuff(player, "siegelingxpboost") then
		amount = amount * 2
	end
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
			PlayerDataManager.NotifyEleminion("OnCreatureLevelChanged", player, e.id, e.uid, e.level, e.xp, amount, leveled)
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
function PlayerDataManager.GetEffectiveStats(creatureId, level, variant, player)
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
	local extraHealthMult = 1
	local extraAttackMult = 1
	local extraDefenseMult = 1
	local extraSpeedMult = 1
	if player then
		local element = info.element or ""
		local class = info.class or ""
		if element == "Water" and PlayerDataManager.HasBuff(player, "food_water_siegeling") then
			extraHealthMult = extraHealthMult * 1.3
		end
		if element == "Fire" and PlayerDataManager.HasBuff(player, "food_fire_siegeling") then
			extraAttackMult = extraAttackMult * 1.3
		end
		if element == "Earth" and PlayerDataManager.HasBuff(player, "food_earth_siegeling") then
			extraDefenseMult = extraDefenseMult * 1.3
		end
		if element == "Wind" and PlayerDataManager.HasBuff(player, "food_wind_siegeling") then
			extraSpeedMult = extraSpeedMult * 1.3
		end

		local cook = GameConfig.Cooking or {}
		local sMultTbl = cook.SiegelingStatMultByRarity or {}
		local function applyCraft(statName, m)
			if statName == "health" then
				extraHealthMult = extraHealthMult * m
			elseif statName == "attack" then
				extraAttackMult = extraAttackMult * m
			elseif statName == "defense" then
				extraDefenseMult = extraDefenseMult * m
			elseif statName == "speed" then
				extraSpeedMult = extraSpeedMult * m
			end
		end
		local elemFocus = {
			Fire = "attack",
			Ice = "defense",
			Wind = "speed",
			Earth = "defense",
			Water = "health",
			Shadow = "attack",
			Light = "defense",
			Lightning = "speed",
			Psychic = "attack",
			Metal = "defense",
			Poison = "health",
			Undead = "attack",
		}
		local classFocus = {
			Bruiser = "health",
			Mage = "attack",
			Guardian = "defense",
			Assassin = "speed",
			Support = "health",
		}
		local elemCraft = PlayerDataManager.GetBuffInfo(player, "craft_siegeling_element")
		if elemCraft and elemCraft.meta and elemCraft.meta.element == element then
			local r = elemCraft.meta.craftRarity or "Common"
			local q = tonumber(elemCraft.meta.qualityPotencyMult) or 1
			local m = (tonumber(sMultTbl[r]) or 1.12) * q
			local st = elemFocus[element]
			if st then
				applyCraft(st, m)
			end
		end
		local clsCraft = PlayerDataManager.GetBuffInfo(player, "craft_siegeling_class")
		if clsCraft and clsCraft.meta and clsCraft.meta.class == class then
			local r = clsCraft.meta.craftRarity or "Common"
			local q = tonumber(clsCraft.meta.qualityPotencyMult) or 1
			local m = (tonumber(sMultTbl[r]) or 1.12) * q
			local st = classFocus[class]
			if st then
				applyCraft(st, m)
			end
		end
	end
	return {
		health = math.floor(baseStats.health * levelMult.health * mult * extraHealthMult),
		attack = math.floor(baseStats.attack * levelMult.attack * mult * extraAttackMult),
		defense = math.floor(baseStats.defense * levelMult.defense * mult * extraDefenseMult),
		speed = math.floor(baseStats.speed * levelMult.speed * mult * extraSpeedMult),
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

function PlayerDataManager.TransferCreature(fromPlayer, toPlayer, uid, context)
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
		nickname = entry.nickname,
		nicknameEverSet = entry.nicknameEverSet == true,
	})
	PlayerDataManager.NotifyAchievement("OnAcquireCreature", toPlayer, entry.id, context)
	return true
end

-- Set or rename a creature nickname.
-- First naming is free; later changes cost gems ("diamonds").
-- Returns: success, message, gemCostApplied, finalNickname
function PlayerDataManager.SetCreatureNickname(player, uid, nickname)
	local d = playerCache[player.UserId]
	if not d then return false, "No data", 0, nil end
	local entry = PlayerDataManager.GetCreatureByUid(player, uid)
	if not entry then return false, "Creature not found", 0, nil end
	if type(nickname) ~= "string" then return false, "Invalid name", 0, nil end
	local cleaned = trimString(nickname)
	local maxLen = tonumber(GameConfig.CreatureNicknameMaxLength) or 20
	if cleaned == "" then return false, "Name cannot be empty", 0, nil end
	if #cleaned > maxLen then
		return false, ("Name too long (max %d)"):format(maxLen), 0, nil
	end
	if nicknameHasBannedContent(cleaned) then
		return false, "Name not allowed by content filter", 0, nil
	end

	local oldName = trimString(entry.nickname or "")
	if oldName ~= "" and oldName == cleaned then
		return true, "Name unchanged", 0, cleaned
	end

	local gemCost = 0
	if entry.nicknameEverSet == true then
		gemCost = tonumber(GameConfig.CreatureRenameGemCost) or 5
		if gemCost > 0 and not PlayerDataManager.SpendGems(player, gemCost) then
			return false, ("Need %d diamonds to rename"):format(gemCost), 0, nil
		end
	end

	entry.nickname = cleaned
	entry.nicknameEverSet = true
	return true, (gemCost > 0 and "Renamed!" or "Nickname set!"), gemCost, cleaned
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

	local previousId = entry.id
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
	PlayerDataManager.NotifyAchievement("OnEvolution", player, previousId, nextId)
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

function PlayerDataManager.AddEgg(player, creatureId, level, rarity, isMystery)
	local d = playerCache[player.UserId]
	if not d then return nil end
	if not d.eggs then d.eggs = {} end
	local lvl = math.max(1, tonumber(level) or 1)
	local hatchMinutes = PlayerDataManager.GetHatchMinutesForLevel(lvl)
	local uid = PlayerDataManager.GenerateUID()
	local mystery = isMystery == true
	table.insert(d.eggs, {
		uid = uid,
		creatureId = creatureId,
		level = lvl,
		rarity = rarity or "Common",
		hatchMinutes = hatchMinutes,
		createdAt = os.time(),
		mystery = mystery,
		inspected = mystery and false or true,
	})
	return uid
end

-- Reveal a mystery egg's creature by spending gems ("diamonds").
-- Returns: success, message, eggTableOrNil
function PlayerDataManager.InspectEgg(player, uid)
	local d = playerCache[player.UserId]
	if not d or not d.eggs then return false, "No data", nil end
	local egg = PlayerDataManager.GetEggByUid(player, uid)
	if not egg then return false, "Egg not found", nil end
	local su = tostring(uid)
	local placed = false
	for _, slotUid in ipairs(d.baseSlots or {}) do
		if tostring(slotUid or "") == su then placed = true break end
	end
	if not placed then
		for _, slotUid in ipairs(d.defenseSlots or {}) do
			if tostring(slotUid or "") == su then placed = true break end
		end
	end
	if not placed then
		return false, "Place the egg at your base first", nil
	end
	if egg.mystery ~= true then
		egg.inspected = true
		return true, "This egg is already known", egg
	end
	if egg.inspected == true then
		return true, "Already inspected", egg
	end
	local cost = tonumber(GameConfig.EggInspectGemCost) or 5
	if cost > 0 and not PlayerDataManager.SpendGems(player, cost) then
		return false, ("Need %d diamonds to inspect"):format(cost), nil
	end
	egg.inspected = true
	return true, "Inspected!", egg
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
				local newUid = PlayerDataManager.AddCreature(player, egg.creatureId, egg.level, 0, nil, nil, { source = "egg_hatch" })
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
		PlayerDataManager.NotifyAchievement("OnSlotAssigned", player, "income", uid)
		return true, optionalSlotIndex, true
	end
	-- First empty slot
	if countFilledSlots(d.baseSlots, maxSlots) >= maxSlots then return false, nil, nil end
	if not isCreatureOrEggUid(d, uid) then return false, nil, nil end
	removeFromAllSlots(d, uid)
	local slot = firstEmptySlot(d.baseSlots, maxSlots)
	d.baseSlots[slot] = tostring(uid)
	PlayerDataManager.NotifyAchievement("OnSlotAssigned", player, "income", uid)
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
		PlayerDataManager.NotifyAchievement("OnSlotAssigned", player, "defense", uid)
		return true, optionalSlotIndex, true
	end
	if countFilledSlots(d.defenseSlots, maxSlots) >= maxSlots then return false, nil, nil end
	if not isCreatureOrEggUid(d, uid) then return false, nil, nil end
	removeFromAllSlots(d, uid)
	local slot = firstEmptySlot(d.defenseSlots, maxSlots)
	d.defenseSlots[slot] = tostring(uid)
	PlayerDataManager.NotifyAchievement("OnSlotAssigned", player, "defense", uid)
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
	task.defer(function()
		if player.Parent then
			PlayerDataManager.ApplyWorldStatsToCharacter(player)
		end
	end)
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
		data.ownedFloors = normalizeOwnedFloors(data.ownedFloors)
		if data.eggs == nil then data.eggs = {} end
		if data.rebirthLevel == nil then data.rebirthLevel = 0 end
		if type(data.achievementMetrics) ~= "table" then data.achievementMetrics = {} end
		if type(data.achievementMetrics.counters) ~= "table" then data.achievementMetrics.counters = {} end
		if type(data.achievementMetrics.best) ~= "table" then data.achievementMetrics.best = {} end
		if type(data.achievementMetrics.sets) ~= "table" then data.achievementMetrics.sets = {} end
		data.eleminions = normalizeEleminionData(data.eleminions)
		data.cosmetics = normalizeCosmeticsData(data.cosmetics)
		data.exterior = normalizeSingleUnlockData(data.exterior)
		data.baseColor = normalizeSingleUnlockData(data.baseColor)
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
		-- Normalize egg inspect fields:
		-- legacy eggs (no mystery flag) are treated as known and already inspected.
		for _, egg in ipairs(data.eggs) do
			if egg.mystery == nil then egg.mystery = false end
			if egg.inspected == nil then egg.inspected = (egg.mystery ~= true) end
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
		data.ingredientBank = normalizeIngredientBank(data.ingredientBank)
		PlayerDataManager.NormalizeDecorSlotsIfNeeded(data)
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
		-- Sigils: Squire keys = element names; Knight keys = zone ids. Legacy: inner legendaries wrongly stored a zone id (see oldInnerBossZoneByElement).
		do
			local zoneIds = GameConfig.ZoneDoorZoneIds or { "Ocean", "Desert", "Electric", "Cave" }
			local oldInnerBossZoneByElement = { Fire = "Desert", Ice = "Cave", Wind = "Ocean", Earth = "Electric" }
			if not data.sigils then data.sigils = {} end
			if data.zoneKeysFromGyms then
				for _, zid in ipairs(zoneIds) do
					local v = data.zoneKeysFromGyms[zid]
					if v == true or v == "true" then
						data.sigils[zid] = true
					end
				end
			end
			for element, zid in pairs(oldInnerBossZoneByElement) do
				local hasKey = data.zoneKeysFromGyms and (data.zoneKeysFromGyms[zid] == true or data.zoneKeysFromGyms[zid] == "true")
				local hasZoneSigil = data.sigils[zid] == true or data.sigils[zid] == "true"
				if hasZoneSigil and not hasKey then
					data.sigils[element] = true
					data.sigils[zid] = nil
				end
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
			local ingEvt = events and events:FindFirstChild("IngredientBankChanged")
			if ingEvt and d.ingredientBank then
				local snap = {}
				for id, n in pairs(d.ingredientBank) do
					snap[id] = n
				end
				ingEvt:FireClient(player, snap)
			end
		end
	end)
	task.defer(function()
		PlayerDataManager.ApplyWorldStatsToCharacter(player)
	end)
end

function PlayerDataManager.OnPlayerLeave(player)
	local uid = player.UserId
	craftingMixByUserId[uid] = nil
	local d = playerCache[uid]
	if d then
		-- Release plot so another player can claim it
		if d.plotId and d.plotId > 0 and claimedPlotIds[d.plotId] == player.UserId then
			claimedPlotIds[d.plotId] = nil
		end
		-- Plot assignment is session-only. Clearing it here prevents stale ownership
		-- from being persisted and keeps rejoin/setup logic deterministic.
		d.plotId = 0
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

-- -- INGREDIENT BANK & CAMPFIRE MIX --

function PlayerDataManager.GetIngredientBank(player)
	local d = playerCache[player.UserId]
	if not d then return {} end
	if not d.ingredientBank then d.ingredientBank = {} end
	return d.ingredientBank
end

function PlayerDataManager.GetIngredientBankSnapshot(player)
	local bank = PlayerDataManager.GetIngredientBank(player)
	local copy = {}
	for id, n in pairs(bank) do
		local nid = tostring(id)
		if nid ~= "" then
			local num = n
			if type(n) == "table" and n.id then
				num = tonumber(n.qty or n.count or n.n) or 0
			else
				num = tonumber(n) or 0
			end
			num = math.floor(num)
			if num > 0 then
				copy[nid] = (copy[nid] or 0) + num
			end
		end
	end
	return copy
end

function PlayerDataManager.GetTotalIngredientCount(player)
	local bank = PlayerDataManager.GetIngredientBank(player)
	local t = 0
	for _, n in pairs(bank) do
		t = t + (tonumber(n) or 0)
	end
	return t
end

function PlayerDataManager.AddIngredient(player, ingredientId, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false, "Bad amount" end
	if not IngredientData.GetById(ingredientId) then return false, "Unknown ingredient" end
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	if not d.ingredientBank then d.ingredientBank = {} end
	local cook = GameConfig.Cooking or {}
	local maxPer = tonumber(cook.MaxStackPerIngredientId) or 999
	local maxTot = tonumber(cook.MaxTotalIngredientCount) or 2500
	local cur = d.ingredientBank[ingredientId] or 0
	if cur + amount > maxPer then return false, "Stack limit for this ingredient" end
	local tot = PlayerDataManager.GetTotalIngredientCount(player) + amount
	if tot > maxTot then return false, "Ingredient bank full" end
	d.ingredientBank[ingredientId] = cur + amount
	return true
end

function PlayerDataManager.DestroyIngredient(player, ingredientId, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false, "Bad amount" end
	local d = playerCache[player.UserId]
	if not d or not d.ingredientBank then return false, "No data" end
	local cur = d.ingredientBank[ingredientId] or 0
	if cur < amount then return false, "Not enough" end
	local left = cur - amount
	if left <= 0 then d.ingredientBank[ingredientId] = nil else d.ingredientBank[ingredientId] = left end
	return true
end

--- mixList: { { id = string, qty = number }, ... } (merged ids optional)
function PlayerDataManager.TryConsumeIngredients(player, mixList)
	if type(mixList) ~= "table" then return false end
	local need = {}
	for _, e in ipairs(mixList) do
		local id = tostring(e.id or "")
		local q = math.floor(tonumber(e.qty) or 0)
		if id ~= "" and q > 0 then
			need[id] = (need[id] or 0) + q
		end
	end
	local d = playerCache[player.UserId]
	if not d or not d.ingredientBank then return false end
	for id, q in pairs(need) do
		if (d.ingredientBank[id] or 0) < q then return false end
	end
	for id, q in pairs(need) do
		local left = (d.ingredientBank[id] or 0) - q
		if left <= 0 then d.ingredientBank[id] = nil else d.ingredientBank[id] = left end
	end
	return true
end

local function getOrInitMix(uid)
	local m = craftingMixByUserId[uid]
	if not m then
		m = {}
		craftingMixByUserId[uid] = m
	end
	return m
end

function PlayerDataManager.GetCraftingMix(player)
	local maxMix = getMaxMixIngredients()
	local mix = getOrInitMix(player.UserId)
	if next(mix) == nil then
		for i = 1, maxMix do
			mix[i] = false
		end
	else
		ensureFixedMixSlots(mix, maxMix)
	end
	local out = {}
	for i = 1, maxMix do
		local e = mix[i]
		if type(e) == "table" and e.id and tostring(e.id) ~= "" and (tonumber(e.qty) or 0) > 0 then
			out[i] = { id = e.id, qty = e.qty }
		else
			out[i] = { id = "", qty = 0 }
		end
	end
	return out
end

function PlayerDataManager.CraftingMixClear(player)
	local maxMix = getMaxMixIngredients()
	local mix = {}
	for i = 1, maxMix do
		mix[i] = false
	end
	craftingMixByUserId[player.UserId] = mix
	return PlayerDataManager.GetCraftingMix(player)
end

--- Place qty of ingredientId into a fixed slot (1..max). Replaces occupied slot; stacks if same id.
--- On success returns true plus fresh mix snapshot for the client (avoids a follow-up GetCraftingMix desync).
function PlayerDataManager.CraftingMixPlaceAt(player, slotIndex, ingredientId, qty)
	ingredientId = tostring(ingredientId or "")
	qty = math.floor(tonumber(qty) or 0)
	if ingredientId == "" or qty <= 0 then
		return false, "Bad ingredient or qty"
	end
	local def = IngredientData.GetById(ingredientId)
	if not def then
		return false, "Unknown ingredient"
	end
	local maxMix = getMaxMixIngredients()
	slotIndex = math.floor(tonumber(slotIndex) or 0)
	if slotIndex < 1 or slotIndex > maxMix then
		return false, "Bad slot"
	end
	local mix = getOrInitMix(player.UserId)
	ensureFixedMixSlots(mix, maxMix)

	local old = mix[slotIndex]
	if type(old) ~= "table" or not old.id or (tonumber(old.qty) or 0) <= 0 then
		old = nil
	end

	local newQtyAtSlot = qty
	if old and old.id == ingredientId then
		newQtyAtSlot = old.qty + qty
	end

	local totalAfter = mixTotalQty(mix) - (old and old.qty or 0) + newQtyAtSlot
	if totalAfter > maxMix then
		return false, "Mix is full (max " .. tostring(maxMix) .. " items)"
	end

	local inMixOtherSlots = 0
	for i = 1, maxMix do
		if i ~= slotIndex then
			local e = mix[i]
			if type(e) == "table" and e.id == ingredientId then
				inMixOtherSlots = inMixOtherSlots + (tonumber(e.qty) or 0)
			end
		end
	end

	local d = playerCache[player.UserId]
	if not d or not d.ingredientBank then
		return false, "No data"
	end
	local have = d.ingredientBank[ingredientId] or 0
	if inMixOtherSlots + newQtyAtSlot > have then
		return false, "Not enough in bank"
	end

	mix[slotIndex] = { id = ingredientId, qty = newQtyAtSlot }
	return true, PlayerDataManager.GetCraftingMix(player)
end

function PlayerDataManager.CraftingMixAdd(player, ingredientId, qty)
	qty = math.floor(tonumber(qty) or 0)
	if qty <= 0 then
		return false, "Bad qty"
	end
	local def = IngredientData.GetById(ingredientId)
	if not def then
		return false, "Unknown ingredient"
	end
	local maxMix = getMaxMixIngredients()
	local mix = getOrInitMix(player.UserId)
	ensureFixedMixSlots(mix, maxMix)
	local function slotEmpty(mi, idx)
		local e = mi[idx]
		if e == false or e == nil then
			return true
		end
		if type(e) ~= "table" then
			return true
		end
		return (not e.id or tostring(e.id) == "") or (tonumber(e.qty) or 0) <= 0
	end
	for i = 1, maxMix do
		if slotEmpty(mix, i) then
			return PlayerDataManager.CraftingMixPlaceAt(player, i, ingredientId, qty)
		end
	end
	return false, "Mix is full (max " .. tostring(maxMix) .. " items)"
end

--- Clear one fixed slot (1-based).
function PlayerDataManager.CraftingMixRemoveSlot(player, index)
	local mix = craftingMixByUserId[player.UserId]
	if not mix then
		return false
	end
	index = math.floor(tonumber(index) or 0)
	local maxMix = getMaxMixIngredients()
	ensureFixedMixSlots(mix, maxMix)
	if index < 1 or index > maxMix then
		return false
	end
	if mix[index] == false or type(mix[index]) ~= "table" then
		return false
	end
	mix[index] = false
	return true, PlayerDataManager.GetCraftingMix(player)
end

function PlayerDataManager.CraftingMixTrimQty(player, index, newQty)
	local mix = craftingMixByUserId[player.UserId]
	if not mix then
		return false
	end
	index = math.floor(tonumber(index) or 0)
	newQty = math.floor(tonumber(newQty) or 0)
	local maxMix = getMaxMixIngredients()
	ensureFixedMixSlots(mix, maxMix)
	if index < 1 or index > maxMix then
		return false
	end
	local e = mix[index]
	if type(e) ~= "table" or not e.id then
		return false
	end
	if newQty <= 0 then
		mix[index] = false
		return true, PlayerDataManager.GetCraftingMix(player)
	end
	local other = mixTotalQty(mix) - e.qty
	if other + newQty > maxMix then
		return false, "Would exceed mix size"
	end
	local d = playerCache[player.UserId]
	local have = d and d.ingredientBank and (d.ingredientBank[e.id] or 0) or 0
	if mixCountForId(mix, e.id) - e.qty + newQty > have then
		return false, "Not enough in bank"
	end
	e.qty = newQty
	return true, PlayerDataManager.GetCraftingMix(player)
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

function PlayerDataManager.ActivateBuff(player, buffId, duration, meta)
	local d = playerCache[player.UserId]; if not d then return false end
	if not d.activeBuffs then d.activeBuffs = {} end
	local entry = { expiresAt = tick() + duration, activatedAt = tick() }
	if type(meta) == "table" then
		entry.meta = meta
	end
	d.activeBuffs[buffId] = entry
	return true
end

--- Returns buff entry { expiresAt, activatedAt, meta? } or nil if missing/expired.
function PlayerDataManager.GetBuffInfo(player, buffId)
	local d = playerCache[player.UserId]; if not d or not d.activeBuffs then return nil end
	local info = d.activeBuffs[buffId]
	if not info then return nil end
	if info.expiresAt and info.expiresAt <= tick() then
		d.activeBuffs[buffId] = nil
		return nil
	end
	return info
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
	if leveled then
		PlayerDataManager.NotifyAchievement("OnPlayerLevelChanged", player, d.playerLevel)
		task.defer(function()
			if player.Parent then
				PlayerDataManager.ApplyWorldStatsToCharacter(player)
			end
		end)
	end
	return d.playerLevel, leveled
end

-- Sync pilot combat attributes (level scaling + rebirth). Safe when data not loaded.
function PlayerDataManager.SyncPlayerWorldStats(player)
	if not player then
		return nil
	end
	local d = playerCache[player.UserId]
	if not d then
		return nil
	end
	local lvl = d.playerLevel or 1
	local bonuses = PlayerDataManager.GetRebirthBonuses(player)
	local s = PlayerWorldStats.ComputeForPlayer(lvl, bonuses)
	player:SetAttribute("WorldStat_LevelMult", s.levelMult)
	player:SetAttribute("WorldStat_Attack", s.attack)
	player:SetAttribute("WorldStat_Defense", s.defense)
	player:SetAttribute("WorldStat_MaxHealth", s.maxHealth)
	player:SetAttribute("WorldStat_WalkSpeed", s.walkSpeed)
	player:SetAttribute("WorldStat_SprintSpeed", s.sprintSpeed)
	return s
end

--- Apply synced max health to the humanoid (includes Badlands flat Health boost when active).
function PlayerDataManager.ApplyWorldStatsToCharacter(player, humanoidOpt)
	PlayerDataManager.SyncPlayerWorldStats(player)
	local hum = humanoidOpt or (player.Character and player.Character:FindFirstChildOfClass("Humanoid"))
	if not hum then
		return
	end
	local baseMax = player:GetAttribute("WorldStat_MaxHealth")
	if type(baseMax) ~= "number" or baseMax < 1 then
		return
	end
	local blHP = 0
	if player:GetAttribute("InBadlands") == true then
		local bh = player:GetAttribute("BadlandsStat_Health")
		if type(bh) == "number" and bh > 0 then
			blHP = bh
		end
	end
	local maxHP = math.max(1, math.floor(baseMax + blHP))
	local prevMax = hum.MaxHealth
	local ratio = prevMax > 0 and (hum.Health / prevMax) or 1
	hum.MaxHealth = maxHP
	hum.Health = math.min(maxHP, math.max(1, math.floor(ratio * maxHP + 0.5)))
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

-- Floor purchase config lookup tables (generalized for any number of floors)
-- Maps floorNum → { cost, levelReq, prerequisiteFloor }
local FLOOR_CONFIG = {
	[2] = {
		cost = function() return GameConfig.Floor2Cost or 500 end,
		levelReq = function() return (GameConfig.DebugFloor2Level2 and 2) or GameConfig.Floor2LevelReq or 2 end,
		prereq = nil, -- Floor 2 has no prerequisite floor
	},
	[3] = {
		cost = function() return GameConfig.Floor3Cost or 5000 end,
		levelReq = function() return GameConfig.Floor3LevelReq or 10 end,
		prereq = 2,   -- Must own Floor 2
	},
	[4] = {
		cost = function() return GameConfig.Floor4Cost or 25000 end,
		levelReq = function() return GameConfig.Floor4LevelReq or 20 end,
		prereq = 3,   -- Must own Floor 3 (Siegelord Arena)
	},
}

function PlayerDataManager.BuyFloor(player, floorNum)
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	if PlayerDataManager.OwnsFloor(player, floorNum) then return false, "Already owned" end

	local cfg = FLOOR_CONFIG[floorNum]
	if not cfg then return false, "Invalid floor" end

	-- Check level requirement
	local reqLevel = cfg.levelReq()
	if (d.playerLevel or 1) < reqLevel then return false, "Requires level " .. reqLevel end

	-- Check prerequisite floor
	if cfg.prereq and not PlayerDataManager.OwnsFloor(player, cfg.prereq) then
		return false, "Buy Floor " .. cfg.prereq .. " first"
	end

	-- Check coins
	local cost = cfg.cost()
	if d.coins < cost then return false, "Not enough coins" end

	d.coins = d.coins - cost
	table.insert(d.ownedFloors, floorNum)
	PlayerDataManager.NotifyAchievement("OnFloorUnlocked", player, floorNum)
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

-- -- DECOR / FURNISH (multi-floor DecorPoints) --

local function parseDecorSlotKey(slotKey)
	if type(slotKey) ~= "string" then return nil, nil end
	local floorStr, idxStr = slotKey:match("^(%d+)_(%d+)$")
	if not floorStr then return nil, nil end
	return tonumber(floorStr), tonumber(idxStr)
end

--- Migrate legacy numeric keys to "4_n" and normalize slot payloads.
function PlayerDataManager.NormalizeDecorSlotsIfNeeded(d)
	if not d then return end
	if type(d.decorSlots) ~= "table" then
		d.decorSlots = {}
		return
	end
	local newSlots = {}
	for k, v in pairs(d.decorSlots) do
		if type(v) ~= "table" then continue end
		local keyStr = tostring(k)
		local outKey = keyStr
		if type(k) == "number" or keyStr:match("^%d+$") then
			outKey = "4_" .. keyStr
		end
		if v.kind == "furniture" and v.furnitureId then
			newSlots[outKey] = { kind = "furniture", furnitureId = v.furnitureId }
		elseif v.creatureId then
			newSlots[outKey] = { kind = "statue", creatureId = v.creatureId }
		end
	end
	d.decorSlots = newSlots
end

function PlayerDataManager.GetDecorStatueBonusMap(player)
	local d = playerCache[player.UserId]
	if not d then return {} end
	PlayerDataManager.NormalizeDecorSlotsIfNeeded(d)
	local map = {}
	for _, slot in pairs(d.decorSlots or {}) do
		if slot.kind == "statue" and slot.creatureId then
			map[slot.creatureId] = true
		end
	end
	return map
end

--- @return boolean success, string message
function PlayerDataManager.PlaceFurnish(player, slotKey, kind, id)
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	PlayerDataManager.NormalizeDecorSlotsIfNeeded(d)

	local floorNum, slotIdx = parseDecorSlotKey(slotKey)
	if not floorNum or not slotIdx then return false, "Invalid slot" end
	if not PlayerDataManager.OwnsFloor(player, floorNum) then return false, "Floor " .. floorNum .. " required" end

	local maxIdx = GameConfig.DecorMaxSlotIndexPerFloor or GameConfig.DecorPointsPerFloor4 or 12
	if slotIdx < 1 or slotIdx > maxIdx then return false, "Invalid slot index" end

	local cost = 0
	local entry = nil

	if kind == "statue" then
		if type(id) ~= "string" then return false, "Invalid creature" end
		local CreatureData = require(game.ReplicatedStorage.Modules.CreatureData)
		local info = CreatureData.GetById(id)
		if not info then return false, "Unknown creature" end
		local costTable = GameConfig.DecorCostByRarity or {}
		cost = costTable[info.rarity] or 1000
	elseif kind == "furniture" then
		if type(id) ~= "string" then return false, "Invalid item" end
		local FurnitureCatalog = require(game.ReplicatedStorage.Modules.FurnitureCatalog)
		entry = FurnitureCatalog.GetById(id)
		if not entry then return false, "Unknown furniture" end
		cost = entry.coinCost or 0
		local modelsFolder = game.ReplicatedStorage:FindFirstChild("FurnitureModels")
		local template = modelsFolder and modelsFolder:FindFirstChild(entry.modelName)
		if not template then return false, "Furniture model missing" end
	else
		return false, "Invalid kind"
	end

	if d.coins < cost then return false, "Need " .. cost .. " coins" end

	d.coins = d.coins - cost
	d.decorSlots[slotKey] = kind == "statue" and { kind = "statue", creatureId = id }
		or { kind = "furniture", furnitureId = id }

	return true, "Placed!"
end

function PlayerDataManager.RemoveFurnish(player, slotKey)
	local d = playerCache[player.UserId]
	if not d then return false, "No data" end
	PlayerDataManager.NormalizeDecorSlotsIfNeeded(d)
	if type(slotKey) ~= "string" or not d.decorSlots or not d.decorSlots[slotKey] then
		return false, "Slot empty"
	end
	d.decorSlots[slotKey] = nil
	return true, "Removed"
end

--- Legacy: numeric slot = Floor 4 slot index.
function PlayerDataManager.PlaceDecor(player, slotIndex, creatureId)
	if type(slotIndex) == "number" then
		return PlayerDataManager.PlaceFurnish(player, "4_" .. tostring(math.floor(slotIndex)), "statue", creatureId)
	end
	return false, "Invalid slot"
end

function PlayerDataManager.RemoveDecor(player, slotIndex)
	if type(slotIndex) == "number" then
		return PlayerDataManager.RemoveFurnish(player, "4_" .. tostring(math.floor(slotIndex)))
	end
	return false, "Invalid slot"
end

function PlayerDataManager.GetDecorSlots(player)
	local d = playerCache[player.UserId]
	if not d then return {} end
	PlayerDataManager.NormalizeDecorSlotsIfNeeded(d)
	return d.decorSlots or {}
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
	PlayerDataManager.NotifyAchievement("OnSale", player, entry.id, sellPrice)
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
