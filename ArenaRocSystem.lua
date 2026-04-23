-- ArenaRocSystem.lua — ServerScriptService (ModuleScript)
-- Workspace.Arena: **Roc** / **Model_Roc** — single Interact → hub (display team, Trade, PvP, NPC team); hub mutex; faces players (Eleminion-style).
-- Last updated: 2026-04-23 01:00
-- Roc trade accepts N Siegelings → N Cactys in a single submit (no hidden cap). The 10× Cacty →
-- CactyJackedty path is an easter egg; server-side error copy never mentions the 10-stack number.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local FavoriteCreatureSystem = nil
pcall(function()
	FavoriteCreatureSystem = require(ServerScriptService.FavoriteCreatureSystem)
end)

local ArenaRocSystem = {}

local PlayerDataManager

local DS_NAME = "ArenaRocStats_v1"
local rocStore = nil
pcall(function()
	rocStore = DataStoreService:GetDataStore(DS_NAME)
end)

-- npcWins = times Roc's team won; npcLosses = times players defeated Roc
local globalStats = { npcWins = 0, npcLosses = 0 }

local CACTY_ID = "cacty"
local JACK_ID = "cactyjackedty"
local ROC_DIALOG_GREETING = "Hi! I'm Roc — want to trade, PvP, or battle my team?"

-- Siegeling species: Pylook, ids containing "siegling", or displayName contains "Siegeling" (see CreatureData).
local function isSiegelingSpecies(creatureId)
	if type(creatureId) ~= "string" or creatureId == "" then
		return false
	end
	local id = string.lower(creatureId)
	if id == "pylook" then
		return true
	end
	-- "siegeling" vs "siegling" both appear in ids / copy
	if string.find(id, "siegeling", 1, true) ~= nil or string.find(id, "siegling", 1, true) ~= nil then
		return true
	end
	local info = CreatureData.GetById(creatureId)
	if not info then
		return false
	end
	local dn = string.lower(tostring(info.displayName or ""))
	return string.find(dn, "siegeling", 1, true) ~= nil
end

local function countSiegelingsInInventory(d)
	if not d or not d.inventory then
		return 0
	end
	local n = 0
	for _, e in ipairs(d.inventory) do
		if e and e.id and isSiegelingSpecies(e.id) then
			n += 1
		end
	end
	return n
end

-- DataStore / legacy rows may use alternate keys; trading must still list creatures.
local function inventoryCreatureUidId(e)
	if type(e) ~= "table" then
		return nil, nil
	end
	local uid = e.uid or e.Uid or e.UID
	local id = e.id or e.Id
	if uid == nil or id == nil then
		return nil, nil
	end
	local su, sid = tostring(uid), tostring(id)
	if su == "" or sid == "" then
		return nil, nil
	end
	return su, sid
end

local function armRocSiegelingPact(player)
	local d = PlayerDataManager and PlayerDataManager.GetData(player)
	if not d or not d.inventory then
		return
	end
	if countSiegelingsInInventory(d) < 1 then
		return
	end
	for _, e in ipairs(d.inventory) do
		if e.id == CACTY_ID and e.rocSiegelingPact == true and e.rocSiegelingPactActive ~= true then
			e.rocSiegelingPactActive = true
		end
	end
end

local function enforceRocSiegelingPact(player)
	local d = PlayerDataManager and PlayerDataManager.GetData(player)
	if not d or not d.inventory then
		return
	end
	if countSiegelingsInInventory(d) >= 1 then
		return
	end
	local toRemove = {}
	for _, e in ipairs(d.inventory) do
		if e.id == CACTY_ID and e.rocSiegelingPact == true and e.rocSiegelingPactActive == true then
			table.insert(toRemove, tostring(e.uid))
		end
	end
	if #toRemove == 0 then
		return
	end
	for _, uid in ipairs(toRemove) do
		PlayerDataManager.RemoveCreature(player, uid)
	end
	if player.Parent then
		notify(player, "Roc took his Cacty back — keep a Siegeling in your inventory for that trade.", "info")
	end
	if FavoriteCreatureSystem then
		pcall(function()
			FavoriteCreatureSystem.DespawnCompanion(player)
			if player.Parent then
				FavoriteCreatureSystem.SpawnCompanion(player)
			end
		end)
	end
	if PlayerDataManager.SavePlayer then
		pcall(function()
			PlayerDataManager.SavePlayer(player)
		end)
	end
end

local function onInventoryPostChangeForRoc(player)
	armRocSiegelingPact(player)
	enforceRocSiegelingPact(player)
end

local function pushWorkspaceAttributes()
	workspace:SetAttribute("ArenaRocNpcWins", globalStats.npcWins)
	workspace:SetAttribute("ArenaRocNpcLosses", globalStats.npcLosses)
end

local function loadGlobalStats()
	if rocStore then
		local ok, data = pcall(function()
			return rocStore:GetAsync("global")
		end)
		if ok and type(data) == "table" then
			globalStats.npcWins = tonumber(data.npcWins) or tonumber(data.wins) or 0
			globalStats.npcLosses = tonumber(data.npcLosses) or tonumber(data.losses) or 0
		end
	end
	pushWorkspaceAttributes()
end

local function notify(player, message, level)
	local events = ReplicatedStorage:FindFirstChild("Events")
	local ev = events and events:FindFirstChild("ShowNotification")
	if ev and player then
		ev:FireClient(player, message, level or "info")
	end
end

local function findArenaFolder()
	return workspace:FindFirstChild("Arena")
end

-- Static hub + display team: GameConfig.ArenaRoc.DisplayTeam merged with CreatureData.
local function buildRocSpecRows()
	local cfg = GameConfig.ArenaRoc or {}
	local fallbackLvl = tonumber(cfg.OpponentLevel) or 25
	local fromCfg = (type(cfg.DisplayTeam) == "table" and #cfg.DisplayTeam > 0) and cfg.DisplayTeam
		or {
			{ sortOrder = 1, creatureId = CACTY_ID, level = 1, note = "Partner" },
			{ sortOrder = 2, creatureId = JACK_ID, level = fallbackLvl, note = "Favorite ★" },
		}
	local rows = {}
	for i, s in ipairs(fromCfg) do
		if type(s) == "table" then
			local id = s.creatureId or s.id
			if type(id) == "string" and id ~= "" then
				local cInfo = CreatureData.GetById(id)
				local level = tonumber(s.level)
				if not level or level < 1 then
					if id == JACK_ID then
						level = fallbackLvl
					else
						level = 1
					end
				end
				local displayName = s.displayName
				if type(displayName) ~= "string" or displayName == "" then
					displayName = (cInfo and cInfo.displayName) or id
				end
				local baseIncome = s.baseIncome
				if not baseIncome and cInfo and cInfo.baseIncome then
					baseIncome = cInfo.baseIncome
				end
				table.insert(rows, {
					sortOrder = tonumber(s.sortOrder) or i,
					id = id,
					displayName = displayName,
					level = level,
					note = tostring(s.note or ""),
					baseIncome = baseIncome,
				})
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.sortOrder < b.sortOrder
	end)
	if #rows == 0 then
		local c1 = CreatureData.GetById(CACTY_ID)
		local c2 = CreatureData.GetById(JACK_ID)
		table.insert(rows, {
			sortOrder = 1,
			id = CACTY_ID,
			displayName = (c1 and c1.displayName) or "Cacty",
			level = 1,
			note = "Partner",
			baseIncome = c1 and c1.baseIncome,
		})
		table.insert(rows, {
			sortOrder = 2,
			id = JACK_ID,
			displayName = (c2 and c2.displayName) or "CactyJackedty",
			level = fallbackLvl,
			note = "Favorite ★",
			baseIncome = c2 and c2.baseIncome,
		})
	end
	return rows, fallbackLvl
end

local ROC_MODEL_NAMES = { Model_Roc = true, Roc = true }

local function findRocModel()
	local arena = findArenaFolder()
	if not arena then
		return nil
	end
	local m = arena:FindFirstChild("Model_Roc")
	if m and m:IsA("Model") then
		return m
	end
	m = arena:FindFirstChild("Roc")
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

local function getPromptPart(rocModel)
	if not rocModel then
		return nil
	end
	if rocModel:IsA("Model") then
		return rocModel.PrimaryPart
			or rocModel:FindFirstChild("HumanoidRootPart", true)
			or rocModel:FindFirstChildWhichIsA("BasePart", true)
	end
	if rocModel:IsA("BasePart") then
		return rocModel
	end
	return nil
end

-- ====== Roc facing (mirrors EleminionSystem: nearest in AttentionRange, prefer last prompt user) ======
local rocFacingState = nil
local rocFacingLoopStarted = false

local function getRocAttentionRange()
	local cfg = GameConfig.ArenaRoc or {}
	local r = tonumber(cfg.AttentionRange)
	if r and r > 0 then
		return r
	end
	local ele = GameConfig.Eleminion or {}
	return tonumber(ele.AttentionRange) or 50
end

local function getRocFacingInterval()
	local cfg = GameConfig.ArenaRoc or {}
	local t = tonumber(cfg.FacingUpdateInterval)
	if t and t > 0 then
		return t
	end
	local ele = GameConfig.Eleminion or {}
	return tonumber(ele.FacingUpdateInterval) or 0.15
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

local function getRocPreferredTargetRoot(state, origin)
	if not state then
		return nil
	end
	local maxDistance = state.attentionRange or getRocAttentionRange()
	local lastId = state.lastInteractorUserId
	if typeof(lastId) == "number" then
		local preferredPlayer = Players:GetPlayerByUserId(lastId)
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

local function applyRocFacingPivot(model, pivot)
	if not model or not model.Parent or not pivot then
		return
	end
	local currentPivot = model:GetPivot()
	if (currentPivot.Position - pivot.Position).Magnitude <= 1e-3 and currentPivot.LookVector:Dot(pivot.LookVector) > 0.999 then
		return
	end
	model:PivotTo(pivot)
end

local function updateRocFacing()
	if not rocFacingState or not rocFacingState.model or not rocFacingState.model.Parent then
		rocFacingState = nil
		return
	end
	local model = rocFacingState.model
	local currentPivot = model:GetPivot()
	local origin = currentPivot.Position
	local targetRoot = getRocPreferredTargetRoot(rocFacingState, origin)
	if targetRoot then
		local flatDirection = (targetRoot.Position - origin) * Vector3.new(1, 0, 1)
		if flatDirection.Magnitude > 0.05 then
			local desiredPivot = CFrame.lookAt(origin, origin + flatDirection.Unit) * (rocFacingState.rotationOffset or CFrame.new())
			applyRocFacingPivot(model, desiredPivot)
			rocFacingState.currentFacing = "player"
			return
		end
	end
	if rocFacingState.currentFacing ~= "base" and rocFacingState.basePivot then
		applyRocFacingPivot(model, rocFacingState.basePivot)
		rocFacingState.currentFacing = "base"
	end
end

local function noteRocInteractor(player)
	if not rocFacingState or not player then
		return
	end
	rocFacingState.lastInteractorUserId = player.UserId
	updateRocFacing()
end

local function bindRocFacingModel(rocModel)
	if not rocModel or not rocModel:IsA("Model") or not rocModel.Parent then
		return
	end
	if rocFacingState and rocFacingState.model == rocModel then
		return
	end
	rocFacingState = {
		model = rocModel,
		basePivot = rocModel:GetPivot(),
		lastInteractorUserId = nil,
		currentFacing = "base",
		attentionRange = getRocAttentionRange(),
		rotationOffset = CFrame.new(),
	}
	local hum = rocModel:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = false
	end
end

local function ensureRocFacingLoop()
	if rocFacingLoopStarted then
		return
	end
	rocFacingLoopStarted = true
	task.spawn(function()
		while true do
			task.wait(getRocFacingInterval())
			updateRocFacing()
		end
	end)
end

local function wireRocPromptInteractorHooks(part)
	if not part then
		return
	end
	for _, ch in ipairs(part:GetChildren()) do
		if ch:IsA("ProximityPrompt") and string.sub(ch.Name, 1, 3) == "Roc" then
			if not ch:GetAttribute("RocInteractorHooked") then
				ch:SetAttribute("RocInteractorHooked", true)
				ch.Triggered:Connect(function(plr)
					noteRocInteractor(plr)
				end)
			end
		end
	end
end

local rocHubLockUserId = nil
local rocHubLockUntil = 0

local function getRocHubLockSeconds()
	return tonumber((GameConfig.ArenaRoc or {}).HubLockSeconds) or 120
end

local function rocHubLockClearStale()
	if rocHubLockUserId ~= nil and os.clock() >= rocHubLockUntil then
		rocHubLockUserId = nil
		rocHubLockUntil = 0
	end
end

local function holdsRocHubLock(player)
	if not player then
		return false
	end
	rocHubLockClearStale()
	return rocHubLockUserId == player.UserId and os.clock() < rocHubLockUntil
end

local function rocHubRefreshLock(player)
	if player and rocHubLockUserId == player.UserId then
		rocHubLockUntil = os.clock() + getRocHubLockSeconds()
	end
end

local function buildRocHubPayload()
	local cfg = GameConfig.ArenaRoc or {}
	local specRows, _lvl = buildRocSpecRows()
	local outRows = {}
	for _, s in ipairs(specRows) do
		local cInf = s.id and CreatureData.GetById(s.id) or nil
		local lineDetail = nil
		if cInf then
			lineDetail = (cInf.element or "?")
				.. " "
				.. (cInf.class or "")
				.. "  ·  "
				.. tostring(cInf.rarity or "Common")
			if cInf.attack and cInf.defense and cInf.health and cInf.speed then
				lineDetail = lineDetail
					.. "  ·  HP"
					.. tostring(cInf.health)
					.. " / ATK"
					.. tostring(cInf.attack)
					.. " / DEF"
					.. tostring(cInf.defense)
					.. " / SPD"
					.. tostring(cInf.speed)
			end
		end
		table.insert(outRows, {
			sortOrder = s.sortOrder,
			id = s.id,
			displayName = s.displayName,
			level = s.level,
			note = s.note,
			baseIncome = s.baseIncome,
			element = cInf and cInf.element or nil,
			class = cInf and cInf.class or nil,
			rarity = cInf and cInf.rarity or nil,
			lineDetail = lineDetail,
		})
	end
	local stakeWin = tonumber(GameConfig.PvPWinGold) or 10
	local stakeLoss = tonumber(GameConfig.PvPLoserGoldLoss) or 10
	return {
		greeting = (type(cfg.Greeting) == "string" and cfg.Greeting ~= "" and cfg.Greeting) or ROC_DIALOG_GREETING,
		rocInventory = outRows,
		stats = { npcWins = globalStats.npcWins, npcLosses = globalStats.npcLosses },
		pvpStakeWin = stakeWin,
		pvpStakeLoss = stakeLoss,
		pvpRange = tonumber(GameConfig.PvPInteractionRange) or 30,
	}
end

function ArenaRocSystem.Init(pdm)
	PlayerDataManager = pdm
	PlayerDataManager.RegisterInventoryPostChangeListener(onInventoryPostChangeForRoc)
	task.defer(loadGlobalStats)

	local events = ReplicatedStorage:FindFirstChild("Events") or Instance.new("Folder")
	events.Name = "Events"
	events.Parent = ReplicatedStorage

	local function mkEvent(n)
		local e = events:FindFirstChild(n)
		if e then
			return e
		end
		e = Instance.new("RemoteEvent")
		e.Name = n
		e.Parent = events
		return e
	end
	local function mkFunc(n)
		local f = events:FindFirstChild(n)
		if not f then
			f = Instance.new("RemoteFunction")
			f.Name = n
			f.Parent = events
		end
		return f
	end

	local rocOpenHub = mkEvent("RocOpenHub")
	mkEvent("RocHubRelease").OnServerEvent:Connect(function(plr)
		if rocHubLockUserId == plr.UserId then
			rocHubLockUserId = nil
			rocHubLockUntil = 0
		end
	end)
	mkEvent("RocHubRequestBattle").OnServerEvent:Connect(function(plr)
		if not holdsRocHubLock(plr) then
			return
		end
		rocHubRefreshLock(plr)
		local okMod, PvPM = pcall(function()
			return require(ServerScriptService.PvPBattleSystem)
		end)
		if not okMod or not PvPM or not PvPM.ChallengeNearestOpponent then
			notify(plr, "PvP is not available.", "error")
			return
		end
		local ok, errMsg, targetName = PvPM.ChallengeNearestOpponent(plr, GameConfig.PvPInteractionRange or 30)
		if not ok then
			notify(plr, errMsg or "Could not challenge anyone.", "error")
			return
		end
		notify(plr, "Challenged " .. tostring(targetName) .. " — they must accept the PvP invite.", "info")
	end)

	-- Returns only after lock is released server-side; client should close the hub (InvokeServer, then closeAll).
	mkFunc("RequestRocNpcBattle").OnServerInvoke = function(player)
		if not player or not player.Parent then
			return false, "Invalid."
		end
		if not holdsRocHubLock(player) then
			return false, "Session expired. Talk to Roc again."
		end
		local okP, PvPM = pcall(function()
			return require(ServerScriptService:WaitForChild("PvPBattleSystem", 2))
		end)
		if not okP or not PvPM or not PvPM.StartNpcStylePvp then
			return false, "PvP is not available."
		end
		local rocModel = findRocModel()
		local rocPart = rocModel and getPromptPart(rocModel)
		local anchor = rocPart and rocPart.Position
		if not anchor then
			return false, "Roc is not ready. Try again in a moment."
		end
		local ar = GameConfig.ArenaRoc or {}
		local specRows, _f = buildRocSpecRows()
		if #specRows < 1 then
			return false, "No opponent data for Roc."
		end
		local idx = math.clamp(tonumber(ar.NpcPvPChampionIndex) or 2, 1, #specRows)
		local champ = specRows[idx]
		local cInfo = CreatureData.GetById(champ.id)
		local oName = (cInfo and cInfo.displayName) or tostring(champ.id)
		local ok, err = PvPM.StartNpcStylePvp(player, {
			creatureId = champ.id,
			level = champ.level,
			variant = "Normal",
			anchorPosition = anchor,
			opponentName = oName,
			maxRangeFromRoc = tonumber(ar.NpcPvpMaxRange) or 80,
		})
		if not ok then
			return false, err or "Could not start battle."
		end
		rocHubLockUserId = nil
		rocHubLockUntil = 0
		notify(player, "PvP vs " .. oName .. " is starting — good luck!", "info")
		return true, ""
	end

	mkFunc("GetRocTradeInventory").OnServerInvoke = function(player)
		if not holdsRocHubLock(player) then
			return {}
		end
		rocHubRefreshLock(player)
		local d = PlayerDataManager.GetData(player)
		if not d or not d.inventory then
			return {}
		end
		local favUid = tostring(d.favoriteUid or "")
		local out = {}
		for _, e in pairs(d.inventory) do
			local su, sid = inventoryCreatureUidId(e)
			if su then
				local info = CreatureData.GetById(sid)
				table.insert(out, {
					uid = su,
					id = sid,
					level = tonumber(e.level) or 1,
					displayName = (info and info.displayName) or sid,
					isSiegeling = isSiegelingSpecies(sid),
					isFavorite = (su == favUid),
				})
			end
		end
		table.sort(out, function(a, b)
			local na = tostring(a.displayName or a.id or "")
			local nb = tostring(b.displayName or b.id or "")
			if na ~= nb then
				return na < nb
			end
			return tostring(a.uid) < tostring(b.uid)
		end)
		return out
	end

	mkFunc("GetRocGlobalStats").OnServerInvoke = function()
		return {
			npcWins = globalStats.npcWins,
			npcLosses = globalStats.npcLosses,
		}
	end

	mkFunc("SubmitRocTrade").OnServerInvoke = function(player, uids)
		if not holdsRocHubLock(player) then
			return false, "Roc is busy or your session expired. Interact again."
		end
		rocHubRefreshLock(player)
		if type(uids) ~= "table" then
			return false, "Invalid request."
		end
		local n = #uids
		if n < 1 then
			return false, "Offer at least one creature."
		end

		local seen = {}
		local offeredRows = {}
		for _, uid in ipairs(uids) do
			if type(uid) ~= "string" or uid == "" then
				return false, "Invalid creature."
			end
			if seen[uid] then
				return false, "Duplicate in offer."
			end
			seen[uid] = true
			local row = PlayerDataManager.GetCreatureByUid(player, uid)
			if not row or not row.id then
				return false, "Creature not found."
			end
			table.insert(offeredRows, row)
		end

		-- Classify the offer. Only three valid shapes reach the reward branches below:
		--   * Siegelings only (any count N ≥ 1)  → N Cactys
		--   * Cacty only, exactly 1               → fresh Cacty swap
		--   * Cacty only, exactly 10              → CactyJackedty (easter egg — copy stays generic)
		--   * Single non-siegeling, non-Cacty     → 1 Cacty (legacy catch-all trade)
		local allSiegelings = true
		local allCacty = true
		for _, row in ipairs(offeredRows) do
			if not isSiegelingSpecies(row.id) then
				allSiegelings = false
			end
			if row.id ~= CACTY_ID then
				allCacty = false
			end
		end

		local isSiegelingBatch = allSiegelings and n >= 1
		local isCactyJackedtyEasterEgg = allCacty and n == 10
		local isFreshCactySwap = allCacty and n == 1
		local isLegacySingle = (not allSiegelings) and (not allCacty) and n == 1

		if not (isSiegelingBatch or isCactyJackedtyEasterEgg or isFreshCactySwap or isLegacySingle) then
			-- Intentionally vague: never mention the 10-stack count.
			return false, "Roc only accepts Siegelings together, or one other creature at a time."
		end

		-- Compute rewards up front so we can validate inventory space before any removal.
		local rewardsCount
		if isSiegelingBatch then
			rewardsCount = n
		else
			rewardsCount = 1
		end

		local d = PlayerDataManager.GetData(player)
		if not d or not d.inventory then
			return false, "No data."
		end
		local maxInv = GameConfig.MaxInventorySize or 50
		if #d.inventory - n + rewardsCount > maxInv then
			return false, "Not enough inventory space for the reward."
		end

		for _, uid in ipairs(uids) do
			PlayerDataManager.RemoveCreature(player, uid)
		end
		if FavoriteCreatureSystem then
			pcall(function()
				FavoriteCreatureSystem.DespawnCompanion(player)
				if player.Parent then
					FavoriteCreatureSystem.SpawnCompanion(player)
				end
			end)
		end

		if isCactyJackedtyEasterEgg then
			PlayerDataManager.AddCreature(player, JACK_ID, 1, 0, "Normal", nil, { source = "roc_trade" })
			if PlayerDataManager.SavePlayer then
				pcall(function()
					PlayerDataManager.SavePlayer(player)
				end)
			end
			return true, "Roc forged your Cactys into a CactyJackedty!"
		end

		if isSiegelingBatch then
			for _, row in ipairs(offeredRows) do
				PlayerDataManager.AddCreature(player, CACTY_ID, 1, 0, "Normal", nil, {
					source = "roc_trade",
					rocSiegelingPact = true,
					fromSiegelingId = row.id,
				})
			end
			if PlayerDataManager.SavePlayer then
				pcall(function()
					PlayerDataManager.SavePlayer(player)
				end)
			end
			if n == 1 then
				local givenInfo = CreatureData.GetById(offeredRows[1].id)
				local givenName = (givenInfo and givenInfo.displayName) or offeredRows[1].id
				return true, "Roc traded you a Cacty for your " .. givenName .. "."
			end
			return true, string.format("Roc traded you %d Cactys for your Siegelings.", n)
		end

		-- Remaining shapes: isFreshCactySwap (1 Cacty) or isLegacySingle (1 non-siegeling non-Cacty).
		local given = offeredRows[1]
		local siegelingPact = (given.id ~= CACTY_ID) and isSiegelingSpecies(given.id)
		PlayerDataManager.AddCreature(player, CACTY_ID, 1, 0, "Normal", nil, {
			source = "roc_trade",
			rocSiegelingPact = siegelingPact == true,
		})
		if PlayerDataManager.SavePlayer then
			pcall(function()
				PlayerDataManager.SavePlayer(player)
			end)
		end
		if given.id == CACTY_ID then
			return true, "Roc traded you a fresh Cacty."
		end
		local givenInfo = CreatureData.GetById(given.id)
		local givenName = (givenInfo and givenInfo.displayName) or given.id
		return true, "Roc traded you a Cacty for your " .. givenName .. "."
	end

	local function attachPrompts()
		local roc = findRocModel()
		if not roc then
			return false
		end
		local part = getPromptPart(roc)
		if not part then
			warn("[ArenaRoc] Arena.Roc / Model_Roc has no HumanoidRootPart yet (streaming?). Will retry on descendant add.")
			return false
		end
		bindRocFacingModel(roc)
		ensureRocFacingLoop()

		if part:FindFirstChild("RocInteractPrompt") then
			wireRocPromptInteractorHooks(part)
			return true
		end

		for _, ch in ipairs(part:GetChildren()) do
			if ch:IsA("ProximityPrompt") and string.sub(ch.Name, 1, 3) == "Roc" then
				ch:Destroy()
			end
		end

		local interact = Instance.new("ProximityPrompt")
		interact.Name = "RocInteractPrompt"
		interact.ActionText = "Interact"
		interact.ObjectText = "Roc"
		interact.MaxActivationDistance = 14
		interact.HoldDuration = 0
		interact.RequiresLineOfSight = false
		interact.Parent = part
		interact.Triggered:Connect(function(plr)
			-- If this callback errors, Roblox reports "interaction failed" to the player.
			-- Keep it protected so we can surface the real error and avoid breaking the prompt.
			local ok, err = pcall(function()
				noteRocInteractor(plr)
				rocHubLockClearStale()
				if rocHubLockUserId ~= nil and rocHubLockUserId ~= plr.UserId and os.clock() < rocHubLockUntil then
					notify(plr, "Roc is busy with another player. Try again in a moment.", "error")
					return
				end
				rocHubLockUserId = plr.UserId
				rocHubLockUntil = os.clock() + getRocHubLockSeconds()
				rocOpenHub:FireClient(plr, buildRocHubPayload())
			end)
			if not ok then
				warn("[ArenaRoc] RocInteractPrompt Triggered error: " .. tostring(err))
				if plr and plr.Parent then
					notify(plr, "Roc interaction failed (server error). Try again.", "error")
				end
			end
		end)

		wireRocPromptInteractorHooks(part)
		return true
	end

	task.spawn(function()
		findArenaFolder()
		local arena = workspace:FindFirstChild("Arena") or workspace:WaitForChild("Arena", 120)
		if arena then
			local deadline = os.clock() + 180
			while not findRocModel() and os.clock() < deadline do
				task.wait(0.25)
			end
		end
		if not attachPrompts() then
			warn("[ArenaRoc] Roc NPC not ready under Workspace.Arena (expected child Model **Roc** or **Model_Roc**) — prompts attach when the rig streams in.")
		end
	end)

	workspace.DescendantAdded:Connect(function(inst)
		local arena = findArenaFolder()
		if not arena or not inst:IsDescendantOf(arena) then
			return
		end
		local n = inst.Name
		if n == "Model_Roc" or n == "Roc" then
			task.defer(attachPrompts)
			return
		end
		if n == "HumanoidRootPart" then
			local m = inst:FindFirstAncestorWhichIsA("Model")
			if m and m.Parent == arena and ROC_MODEL_NAMES[m.Name] == true then
				task.defer(attachPrompts)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		if rocHubLockUserId == p.UserId then
			rocHubLockUserId = nil
			rocHubLockUntil = 0
		end
	end)

	print("[ArenaRocSystem] Initialized")
end

return ArenaRocSystem
