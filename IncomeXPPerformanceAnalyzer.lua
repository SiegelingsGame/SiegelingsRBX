--[[
	IncomeXPPerformanceAnalyzer.lua
	ServerScriptService/IncomeXPPerformanceAnalyzer

	Profiles every step that fires during the 10-second income/XP tick to
	pinpoint the operations that freeze the server.

	HOW TO USE
	----------
	1. Drop this script into ServerScriptService in Roblox Studio.
	2. Start a server-side Play Solo (or a local server test).
	3. Wait ~15 seconds; a full report prints to the Output window.
	4. For multi-player stress simulation the script also runs synthetic
	   benchmarks that mimic 1, 5, 10, 25 and 50 concurrent players so you
	   do not need real players to get useful numbers.

	OUTPUT FORMAT
	-------------
	Each line is prefixed [PERF] so you can filter the Output window.

	BOTTLENECK THRESHOLDS (tunable below)
	--------------------------------------
	WARN  > 0.5 ms  per operation instance
	CRIT  > 2.0 ms  per operation instance
]]

-- ────────────────────────────────────────────────────────────────────────────
-- Config
-- ────────────────────────────────────────────────────────────────────────────
local WARN_MS       = 0.5   -- ms — flag as slow
local CRIT_MS       = 2.0   -- ms — flag as critical
local SAMPLE_RUNS   = 20    -- how many times to repeat each synthetic bench
local PLAYER_COUNTS = {1, 5, 10, 25, 50}

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────
local function ms(t)   return t * 1000 end
local function fmt(n)  return string.format("%.4f ms", ms(n)) end

local function tag(level, label, elapsed, extra)
	local prefix = (ms(elapsed) >= CRIT_MS) and "[PERF][CRIT]"
	             or (ms(elapsed) >= WARN_MS) and "[PERF][WARN]"
	             or "[PERF][OK]  "
	print(string.format("%s  %-50s %s %s", prefix, label, fmt(elapsed), extra or ""))
end

local function mean(tbl)
	local s = 0
	for _, v in ipairs(tbl) do s = s + v end
	return s / #tbl
end

local function bench(label, fn, runs)
	runs = runs or SAMPLE_RUNS
	local times = {}
	for i = 1, runs do
		local t0 = os.clock()
		fn()
		times[i] = os.clock() - t0
	end
	local avg = mean(times)
	tag("bench", label, avg, string.format("(avg of %d runs)", runs))
	return avg
end

-- ────────────────────────────────────────────────────────────────────────────
-- Module references (non-fatal if a module is missing)
-- ────────────────────────────────────────────────────────────────────────────
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players            = game:GetService("Players")

local function tryRequire(path)
	local ok, mod = pcall(require, path)
	return ok and mod or nil
end

local CreatureData       = tryRequire(ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("CreatureData"))
local GameConfig         = tryRequire(ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("GameConfig"))
local PlayerDataManager  = tryRequire(ServerScriptService:FindFirstChild("PlayerDataManager"))
local BaseIncomeSystem   = tryRequire(ServerScriptService:FindFirstChild("BaseIncomeSystem"))

-- ────────────────────────────────────────────────────────────────────────────
-- Synthetic data factories
-- ────────────────────────────────────────────────────────────────────────────
local TICK_SECONDS = (GameConfig and GameConfig.IncomeTickSeconds) or 10

-- Build a realistic inventory of `count` creatures
local function makeInventory(count)
	local inv = {}
	for i = 1, count do
		inv[i] = {
			uid   = tostring(i),
			id    = 1,           -- ID 1; CreatureData.GetById may or may not return data
			level = math.random(1, 20),
			xp    = math.random(0, 200),
		}
	end
	return inv
end

-- Build a slot list referencing the first `count` inventory UIDs
local function makeSlots(inventory, count)
	local slots = {}
	for i = 1, math.min(count, #inventory) do
		slots[i] = inventory[i].uid
	end
	return slots
end

-- Minimal player-data table that mirrors what BaseIncomeSystem/doIncomeTick reads
local function makeFakePlayerData(inventorySize, baseSlotCount, defenseSlotCount)
	local inv   = makeInventory(inventorySize)
	return {
		inventory    = inv,
		baseSlots    = makeSlots(inv, baseSlotCount),
		defenseSlots = makeSlots(inv, defenseSlotCount),
		eggs         = {},
		buffs        = {},
		stats        = { totalIncome = 0 },
		coins        = 0,
		playerLevel  = math.random(1, 50),
		playerXP     = 0,
	}
end

-- Typical player: 30 inventory slots, 12 base slots, 6 defense slots
local function typicalData() return makeFakePlayerData(30, 12, 6) end

-- ────────────────────────────────────────────────────────────────────────────
-- Micro-benchmarks — isolated operations
-- ────────────────────────────────────────────────────────────────────────────

print("\n[PERF] ════════════════════════════════════════════════════")
print("[PERF]  INCOME / XP TICK — PERFORMANCE ANALYSIS")
print("[PERF]  Tick interval:", TICK_SECONDS, "seconds")
print("[PERF] ════════════════════════════════════════════════════\n")

-- ── 1. Linear inventory scan (the hottest inner loop) ──────────────────────
print("[PERF] --- MICRO: inventory scan patterns ---")

local INV_SIZES = {10, 30, 50, 100}
for _, sz in ipairs(INV_SIZES) do
	local inv = makeInventory(sz)
	local target = inv[math.ceil(sz / 2)].uid  -- search for middle element (avg case)

	bench(string.format("Linear UID scan — inventory[%d] (avg case)", sz), function()
		for _, e in ipairs(inv) do
			if e.uid == target then break end
		end
	end)
end

-- ── 2. CalculateIncome per player ──────────────────────────────────────────
print("\n[PERF] --- MICRO: CalculateIncome equivalent ---")

-- Inline version of BaseIncomeSystem.CalculateIncome for isolated timing
local function simulateCalculateIncome(data)
	local total = 0
	for _, uid in ipairs(data.baseSlots or {}) do
		if not uid or uid == "" then continue end
		for _, entry in ipairs(data.inventory) do
			if entry.uid and tostring(entry.uid) == tostring(uid) then
				-- CreatureData.GetById call (table lookup or nil)
				if CreatureData then CreatureData.GetById(entry.id) end
				total += 5  -- synthetic baseIncome
				break
			end
		end
	end
	return total
end

local SLOT_COMBOS = { {12, 30}, {18, 50}, {6, 10} }
for _, combo in ipairs(SLOT_COMBOS) do
	local slotCount, invSize = combo[1], combo[2]
	local data = makeFakePlayerData(invSize, slotCount, 0)
	bench(string.format("CalculateIncome — %d baseSlots × %d inventory", slotCount, invSize), function()
		simulateCalculateIncome(data)
	end)
end

-- ── 3. Defense XP scan ────────────────────────────────────────────────────
print("\n[PERF] --- MICRO: DefenseSlot XP inventory scan ---")

local function simulateDefenseXP(data)
	for _, uid in ipairs(data.defenseSlots or {}) do
		if not uid or uid == "" then continue end
		for _, entry in ipairs(data.inventory) do
			if entry.uid and tostring(entry.uid) == tostring(uid) then
				-- AddXP call would go here; we time just the scan
				break
			end
		end
	end
end

for _, combo in ipairs(SLOT_COMBOS) do
	local _, invSize = combo[1], combo[2]
	local data = makeFakePlayerData(invSize, 0, 6)
	bench(string.format("DefenseXP scan — 6 defenseSlots × %d inventory", invSize), function()
		simulateDefenseXP(data)
	end)
end

-- ── 4. XP level-up loop ────────────────────────────────────────────────────
print("\n[PERF] --- MICRO: XP level-up calculation loop ---")

local BASE_XP     = (GameConfig and GameConfig.BaseXPRequired)    or 50
local XP_SCALE    = (GameConfig and GameConfig.XPScaling)          or 1.5
local MAX_LEVEL   = 30

local function xpForLevel(lvl)
	if lvl <= 1 then return 0 end
	return math.floor(BASE_XP * (XP_SCALE ^ (lvl - 2)))
end

-- Simulate adding a small amount of XP (no level-up — common case)
bench("AddXP — no level-up (common case)", function()
	local entry = { level = 10, xp = 0 }
	entry.xp = entry.xp + 3
	while entry.level < MAX_LEVEL do
		local needed = xpForLevel(entry.level + 1)
		if entry.xp >= needed then
			entry.xp = entry.xp - needed
			entry.level = entry.level + 1
		else break end
	end
end)

-- Simulate a level-up burst (rare but expensive)
bench("AddXP — 3-level burst (rare case)", function()
	local entry = { level = 5, xp = xpForLevel(6) + xpForLevel(7) + xpForLevel(8) - 1 }
	entry.xp = entry.xp + 9999
	while entry.level < MAX_LEVEL do
		local needed = xpForLevel(entry.level + 1)
		if entry.xp >= needed then
			entry.xp = entry.xp - needed
			entry.level = entry.level + 1
		else break end
	end
end)

-- ── 5. RemoteEvent FireClient (can't actually fire without a client; measures overhead) ──
print("\n[PERF] --- MICRO: RemoteEvent lookup overhead ---")

local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
bench("FindFirstChild('IncomeReceived') in ReplicatedStorage.Events", function()
	if eventsFolder then eventsFolder:FindFirstChild("IncomeReceived") end
end)

-- ────────────────────────────────────────────────────────────────────────────
-- Full-tick simulation across player counts
-- ────────────────────────────────────────────────────────────────────────────
print("\n[PERF] --- FULL TICK SIMULATION (synthetic players) ---")

-- One complete doIncomeTick iteration for `N` synthetic players
local function simulateFullTick(numPlayers)
	local invSize      = 30
	local baseSlots    = 12
	local defenseSlots = 6

	for _ = 1, numPlayers do
		local data = makeFakePlayerData(invSize, baseSlots, defenseSlots)

		-- Step 1 — CalculateIncome
		simulateCalculateIncome(data)

		-- Step 2 — AddCoins (just an arithmetic write in the cache)
		data.coins = data.coins + 100

		-- Step 3 — AddPlayerXP (no level-up; typical fast path)
		data.playerXP = data.playerXP + 2
		local needed = math.floor(100 * (1.4 ^ (data.playerLevel - 1)))
		if data.playerXP >= needed then
			data.playerXP = data.playerXP - needed
			data.playerLevel = data.playerLevel + 1
		end

		-- Step 4 — Defense XP scan + per-creature AddXP
		for _, uid in ipairs(data.defenseSlots) do
			for _, entry in ipairs(data.inventory) do
				if entry.uid == uid then
					entry.xp = entry.xp + 3
					while entry.level < MAX_LEVEL do
						local nx = xpForLevel(entry.level + 1)
						if entry.xp >= nx then
							entry.xp = entry.xp - nx
							entry.level = entry.level + 1
						else break end
					end
					break
				end
			end
		end

		-- Step 5 — stats update (totalIncome tracking)
		data.stats.totalIncome = data.stats.totalIncome + 100
	end
end

local projections = {}
for _, n in ipairs(PLAYER_COUNTS) do
	local times = {}
	for _ = 1, SAMPLE_RUNS do
		local t0 = os.clock()
		simulateFullTick(n)
		times[#times + 1] = os.clock() - t0
	end
	local avg = mean(times)
	projections[n] = avg
	tag("sim", string.format("Full tick — %2d players (typical)", n), avg,
		string.format("→ %s per player",
			string.format("%.4f ms", ms(avg) / n)))
end

-- ────────────────────────────────────────────────────────────────────────────
-- Worst-case: both income loops running simultaneously
-- ────────────────────────────────────────────────────────────────────────────
print("\n[PERF] --- DUPLICATE-LOOP SCENARIO (BaseIncomeSystem + MainServer fallback) ---")
print("[PERF] If BaseIncomeSystem fails to require() silently, BOTH loops fire every tick.")
print("[PERF] Estimated cost = 2× the numbers above:")

for _, n in ipairs(PLAYER_COUNTS) do
	local doubled = projections[n] * 2
	local badge = (ms(doubled) >= CRIT_MS) and "[CRIT]" or (ms(doubled) >= WARN_MS) and "[WARN]" or "[OK]  "
	print(string.format("[PERF]%s  Dual-loop tick — %2d players → %s total", badge, n, fmt(doubled)))
end

-- ────────────────────────────────────────────────────────────────────────────
-- Live player measurements (if players are present)
-- ────────────────────────────────────────────────────────────────────────────
print("\n[PERF] --- LIVE PLAYER MEASUREMENTS ---")

local livePlayers = Players:GetPlayers()
if #livePlayers == 0 then
	print("[PERF] No live players detected — skipping live measurements.")
	print("[PERF] Join the game and wait for the next tick to get real numbers.")
else
	print("[PERF] Measuring", #livePlayers, "live player(s)…")

	for _, player in ipairs(livePlayers) do
		if not PlayerDataManager then
			print("[PERF] PlayerDataManager not accessible — cannot read live data.")
			break
		end

		-- CalculateIncome
		if BaseIncomeSystem and BaseIncomeSystem.CalculateIncome then
			local t0 = os.clock()
			local income = BaseIncomeSystem.CalculateIncome(player)
			local elapsed = os.clock() - t0
			tag("live", string.format("CalculateIncome(%s) → %d coins", player.Name, income), elapsed)
		end

		-- AddPlayerXP (read-only timing: we add 0 XP)
		if PlayerDataManager.AddPlayerXP then
			local t0 = os.clock()
			PlayerDataManager.AddPlayerXP(player, 0)
			local elapsed = os.clock() - t0
			tag("live", string.format("AddPlayerXP(%s, 0)", player.Name), elapsed)
		end

		-- Defense slot inventory scan
		local data = PlayerDataManager.GetData and PlayerDataManager.GetData(player)
		if data and data.defenseSlots then
			local t0 = os.clock()
			local scanCount = 0
			for _, uid in ipairs(data.defenseSlots) do
				if uid and uid ~= "" then
					for _, entry in ipairs(data.inventory or {}) do
						scanCount += 1
						if entry.uid and tostring(entry.uid) == tostring(uid) then break end
					end
				end
			end
			local elapsed = os.clock() - t0
			tag("live", string.format("DefenseSlot scan(%s) — %d comparisons", player.Name, scanCount), elapsed)
		end
	end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Structural audit — check if both income loops are active
-- ────────────────────────────────────────────────────────────────────────────
print("\n[PERF] --- STRUCTURAL AUDIT ---")

if BaseIncomeSystem then
	print("[PERF][OK]   BaseIncomeSystem loaded — primary loop should be active.")
else
	print("[PERF][CRIT] BaseIncomeSystem FAILED TO LOAD — MainServer fallback loop is running.")
	print("[PERF][CRIT] The fallback loop duplicates work AND lacks day/night awareness.")
end

-- Check for the IncomeReceived event (presence implies at least one loop created it)
local incomeEvt = eventsFolder and eventsFolder:FindFirstChild("IncomeReceived")
if incomeEvt then
	print("[PERF][OK]   IncomeReceived RemoteEvent exists — at least one income loop is live.")
else
	print("[PERF][WARN] IncomeReceived RemoteEvent missing — income loop may not have started yet.")
end

-- ────────────────────────────────────────────────────────────────────────────
-- Identified bottlenecks & recommendations
-- ────────────────────────────────────────────────────────────────────────────
print("\n[PERF] ════════════════════════════════════════════════════")
print("[PERF]  BOTTLENECK SUMMARY & RECOMMENDATIONS")
print("[PERF] ════════════════════════════════════════════════════")

print([[
[PERF] #1 — O(slots × inventory) linear scans  [MOST CRITICAL]
       BaseIncomeSystem.CalculateIncome and the defense-XP loop both scan the
       full inventory array for every slot on every player every tick.
       With 12 base slots + 6 defense slots and a 30-entry inventory that is
       18 × 30 = 540 string comparisons per player per 10 seconds.
       FIX: Build a uid→entry lookup table (hash map) in Init and invalidate
       on AddCreature/RemoveCreature. Each slot lookup becomes O(1).

       -- Example patch inside BaseIncomeSystem.Init:
       -- PlayerDataManager.GetCreatureByUid(player, uid)  ← already exists in PDM
       -- Use it instead of the inline for-loop in CalculateIncome.

[PERF] #2 — Duplicate income loops  [HIGH RISK]
       MainServer.server.lua lines 1056–1109: the else-branch runs a second
       income loop if BaseIncomeSystem fails to require().  If both execute
       (silent pcall failure) every player receives double coins & XP and the
       server does double work per tick.
       FIX: Wrap the BaseIncomeSystem require in a visible assert/warn, not a
       silent fallback, so the failure is obvious.  Remove the duplicate income
       calculation from the fallback; keep only the egg-hatching loop there.

[PERF] #3 — All players processed synchronously in one frame  [HIGH]
       doIncomeTick() iterates every player in a single blocking loop.
       With N players, all 540N string comparisons + N FireClient calls happen
       in the same micro-task, spiking server frame time.
       FIX: Spread players across frames using task.defer or a staggered loop:
         for _, player in ipairs(Players:GetPlayers()) do
             task.defer(function() processOnePlayer(player) end)
         end
       This amortises the spike across multiple heartbeat frames.

[PERF] #4 — ReplicatedStorage.Events:FindFirstChild inside the hot loop  [MEDIUM]
       BaseIncomeSystem.doIncomeTick() calls ReplicatedStorage.Events:FindFirstChild
       ("IncomeReceived") on every tick invocation (line 79).
       FIX: Cache the event reference once at Init time (already done for
       coinsUpdate; do the same for incomeEvent).

[PERF] #5 — Defense-slot night check rescans inventory per creature  [MEDIUM]
       Lines 121–129 of BaseIncomeSystem re-iterate data.inventory inside the
       defense-slot loop to find the creature's element, even when it is not
       night.  That second O(inventory) scan is redundant on day ticks.
       FIX: Hoist the isNight check before the defense loop and only run the
       element lookup branch when isNight is true.

[PERF] #6 — PlayerDataManager.AddXP calls NotifyEleminion per creature  [MEDIUM]
       Every AddXP call (up to 6 per player per tick) fires NotifyEleminion
       which dispatches to all registered Eleminion listeners synchronously.
       FIX: Batch the notifications: collect (uid, newLevel, didLevel) results
       from all AddXP calls and dispatch a single batched notification per tick.

[PERF] #7 — PlaceCreatureInSlot during egg hatch spawns 3-D models  [MEDIUM]
       Egg hatches trigger PlaceCreatureInSlot which instantiates CreatureModel
       assets synchronously.  If multiple eggs hatch on the same tick the
       server creates several models in one frame.
       FIX: Defer model spawning with task.defer or queue hatches and process
       one per heartbeat.
]])

print("[PERF] ════════════════════════════════════════════════════")
print("[PERF]  Analysis complete. Filter Output by '[PERF]' to review.")
print("[PERF] ════════════════════════════════════════════════════\n")
