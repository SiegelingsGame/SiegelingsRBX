--[[
	BaseIncomeSystem.lua
	ServerScriptService/BaseIncomeSystem

	Handles passive coin income from creatures stationed at the player's base.
	Only generates income while the player is ONLINE (active session only).

	Performance model:
		- Each player has an independent payout loop, offset by IncomeTickStaggerSeconds.
		- Slot economics are cached as day/night income and eligible defense UIDs.
		- The cache rebuilds only when inventory or slot state changes.
		- Hot-path XP and creature lookups use PlayerDataManager UID indexes
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local DayNightCycle = nil
pcall(function()
	DayNightCycle = require(ServerScriptService.DayNightCycle)
end)

local PlayerDataManager -- set during Init
local BaseIncomeSystem = {}

local playerStates = {}
local initialized = false
local incomeEvent = nil
local creatureLevelUpEvent = nil
local playerLevelUpEvent = nil

-- Shadow and Lightning (Electric) creatures stay active at night; others sleep.
local function isNightActiveElement(element)
	return element == "Shadow" or element == "Lightning"
end

local function isNightNow()
	return DayNightCycle and DayNightCycle.IsNight and DayNightCycle.IsNight() or false
end

local function getTickSeconds()
	return math.max(1, tonumber(GameConfig.IncomeTickSeconds) or 10)
end

local function getStaggerSeconds()
	local stagger = tonumber(GameConfig.IncomeTickStaggerSeconds)
	if stagger == nil then
		return 0.018
	end
	return math.max(0, stagger)
end

local function getMaxSlots(player, slotType)
	if PlayerDataManager and PlayerDataManager.GetMaxSlots then
		return PlayerDataManager.GetMaxSlots(player, slotType)
	end
	return slotType == "defense" and (GameConfig.MaxDefenseSlots or 4) or (GameConfig.MaxIncomeSlots or 6)
end

local function getSlotUid(slots, index)
	if not slots then
		return ""
	end
	local uid = slots[index] or slots[tostring(index)]
	return uid and tostring(uid) or ""
end

local function buildSlotSignature(slots, maxSlots)
	if not slots or maxSlots <= 0 then
		return ""
	end
	local parts = {}
	for i = 1, maxSlots do
		local uid = getSlotUid(slots, i)
		if uid ~= "" then
			parts[#parts + 1] = tostring(i) .. ":" .. uid
		end
	end
	return table.concat(parts, "|")
end

local function getInventoryVersion(player)
	if PlayerDataManager and PlayerDataManager.GetInventoryVersion then
		return PlayerDataManager.GetInventoryVersion(player)
	end
	return 0
end

local function getSlotVersion(player)
	if PlayerDataManager and PlayerDataManager.GetSlotVersion then
		return PlayerDataManager.GetSlotVersion(player)
	end
	return 0
end

local function getCreatureByUid(player, data, uid)
	if not uid or uid == "" then
		return nil
	end
	if PlayerDataManager and PlayerDataManager.GetCreatureByUid then
		return PlayerDataManager.GetCreatureByUid(player, uid)
	end
	for _, entry in ipairs(data.inventory or {}) do
		if entry and tostring(entry.uid or "") == tostring(uid) then
			return entry
		end
	end
	return nil
end

local function getPlayerState(player)
	local userId = player.UserId
	local state = playerStates[userId]
	if not state then
		state = {
			dirty = true,
			cache = {
				dayIncome = 0,
				nightIncome = 0,
				dayDefenseUids = {},
				nightDefenseUids = {},
			},
		}
		playerStates[userId] = state
	end
	return state
end

local function rebuildIncomeCache(player, data, state, revisions)
	local dayIncome = 0
	local nightIncome = 0
	local dayDefenseUids = {}
	local nightDefenseUids = {}

	for i = 1, revisions.maxIncomeSlots do
		local slotUid = getSlotUid(data.baseSlots, i)
		if slotUid ~= "" then
			local entry = getCreatureByUid(player, data, slotUid)
			local info = entry and CreatureData.GetById(entry.id)
			local baseIncome = info and (tonumber(info.baseIncome) or 0) or 0
			if baseIncome > 0 then
				dayIncome += baseIncome
				if isNightActiveElement(info.element) then
					nightIncome += baseIncome
				end
			end
		end
	end

	for i = 1, revisions.maxDefenseSlots do
		local uid = getSlotUid(data.defenseSlots, i)
		if uid ~= "" then
			local entry = getCreatureByUid(player, data, uid)
			local info = entry and CreatureData.GetById(entry.id)
			if info then
				dayDefenseUids[#dayDefenseUids + 1] = uid
				if isNightActiveElement(info.element) then
					nightDefenseUids[#nightDefenseUids + 1] = uid
				end
			end
		end
	end

	state.cache = {
		dayIncome = dayIncome,
		nightIncome = nightIncome,
		dayDefenseUids = dayDefenseUids,
		nightDefenseUids = nightDefenseUids,
	}
	state.inventoryVersion = revisions.inventoryVersion
	state.slotVersion = revisions.slotVersion
	state.baseSignature = revisions.baseSignature
	state.defenseSignature = revisions.defenseSignature
	state.maxIncomeSlots = revisions.maxIncomeSlots
	state.maxDefenseSlots = revisions.maxDefenseSlots
	state.dirty = false

	return state.cache
end

local function ensureIncomeCache(player, data)
	local state = getPlayerState(player)
	local revisions = {
		inventoryVersion = getInventoryVersion(player),
		slotVersion = getSlotVersion(player),
		maxIncomeSlots = getMaxSlots(player, "income"),
		maxDefenseSlots = getMaxSlots(player, "defense"),
	}
	revisions.baseSignature = buildSlotSignature(data.baseSlots, revisions.maxIncomeSlots)
	revisions.defenseSignature = buildSlotSignature(data.defenseSlots, revisions.maxDefenseSlots)

	local shouldRebuild = state.dirty
		or state.inventoryVersion ~= revisions.inventoryVersion
		or state.slotVersion ~= revisions.slotVersion
		or state.baseSignature ~= revisions.baseSignature
		or state.defenseSignature ~= revisions.defenseSignature
		or state.maxIncomeSlots ~= revisions.maxIncomeSlots
		or state.maxDefenseSlots ~= revisions.maxDefenseSlots

	if shouldRebuild then
		return rebuildIncomeCache(player, data, state, revisions)
	end

	return state.cache
end

local function applyDynamicIncomeBonuses(player, baseIncome)
	local totalIncome = baseIncome

	local bonuses = PlayerDataManager.GetRebirthBonuses and PlayerDataManager.GetRebirthBonuses(player)
	if bonuses and (bonuses.passiveGold or 0) > 0 then
		totalIncome += bonuses.passiveGold
	end

	if PlayerDataManager.HasBuff and PlayerDataManager.HasBuff(player, "coinboost") then
		totalIncome *= 2
	end

	return totalIncome
end

-- Income amount for one player (requires player for rebirth / buffs).
function BaseIncomeSystem.CalculateIncome(player: Player): number
	if not PlayerDataManager then
		return 0
	end
	local data = PlayerDataManager.GetData(player)
	if not data then
		return 0
	end
	local cache = ensureIncomeCache(player, data)
	local baseIncome = isNightNow() and cache.nightIncome or cache.dayIncome
	return applyDynamicIncomeBonuses(player, baseIncome)
end

local function processDefensePassiveXP(player, cache, nightNow)
	local defenseUids = nightNow and cache.nightDefenseUids or cache.dayDefenseUids
	if #defenseUids == 0 then
		return
	end

	-- One buff lookup per tick (not per defending creature)
	local xpBoost = PlayerDataManager.HasBuff(player, "siegelingxpboost")
	local baseXP = (GameConfig.DefensePassiveXP or 3) * (xpBoost and 2 or 1)
	local xpOpts = {
		skipBuffCheck = true,
		eleminionNotifyLevelUpOnly = true,
	}
	for _, uid in ipairs(defenseUids) do
		local newLvl, didLevel = PlayerDataManager.AddXP(player, uid, baseXP, xpOpts)
		if didLevel and creatureLevelUpEvent then
			creatureLevelUpEvent:FireClient(player, uid, newLvl)
		end
	end
end

local function processOnePlayerIncome(player)
	if not player.Parent then
		return
	end

	local data = PlayerDataManager.GetData(player)
	if not data then
		return
	end

	local cache = ensureIncomeCache(player, data)
	local nightNow = isNightNow()
	local baseIncome = nightNow and cache.nightIncome or cache.dayIncome
	local income = applyDynamicIncomeBonuses(player, baseIncome)

	-- Coins + networking first; defer XP (player + defense) so this frame isn’t dominated by
	-- HasBuff / AddXP / Eleminion scheduling every IncomeTickSeconds.
	if income > 0 then
		local newBalance = PlayerDataManager.AddCoins(player, income)

		if data.stats then
			data.stats.totalIncome = (data.stats.totalIncome or 0) + income
		end

		if incomeEvent then
			incomeEvent:FireClient(player, income, newBalance)
		end

		BaseIncomeSystem.OnIncomeReceived:Fire(player, income)
	end

	local incomeForXp = income
	task.defer(function()
		if not player.Parent then
			return
		end
		local d = PlayerDataManager.GetData(player)
		if not d then
			return
		end
		local c = ensureIncomeCache(player, d)
		local night = isNightNow()
		if incomeForXp > 0 and PlayerDataManager.AddPlayerXP then
			local pLvl, pDidLvl = PlayerDataManager.AddPlayerXP(player, GameConfig.PlayerXP_IncomeTick or 2)
			if pDidLvl and playerLevelUpEvent then
				playerLevelUpEvent:FireClient(player, pLvl)
			end
		end
		processDefensePassiveXP(player, c, night)
	end)
end

local function runPlayerIncomeSafely(player)
	local ok, err = pcall(processOnePlayerIncome, player)
	if not ok then
		warn("[BaseIncomeSystem] processOnePlayerIncome failed:", player.Name, err)
	end

	if #levelChanges > 0 and PlayerDataManager.NotifyEleminion then
		PlayerDataManager.NotifyEleminion("OnCreatureLevelChangedBatch", player, levelChanges)
	end
end

-- -- Income tick --

local function doIncomeTick()
	-- Spread player processing across frames via task.defer so a single tick
	-- doesn't block the heartbeat with N players' worth of work in one micro-task.
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(processPlayerTick, player)
	end
end

function BaseIncomeSystem.InvalidatePlayer(player)
	if not player then
		return
	end
	local state = playerStates[player.UserId]
	if state then
		state.dirty = true
	end
end

local function stopPlayerLoop(player)
	local state = playerStates[player.UserId]
	if state then
		state.loopToken = nil
		state.running = false
	end
	playerStates[player.UserId] = nil
end

local function startPlayerLoop(player, playerIndex)
	local state = getPlayerState(player)
	if state.running then
		return
	end

	state.running = true
	state.loopToken = {}
	local token = state.loopToken
	local initialDelay = math.max(0, ((playerIndex or 1) - 1) * getStaggerSeconds())

	task.spawn(function()
		if initialDelay > 0 then
			task.wait(initialDelay)
		end

		while player.Parent and playerStates[player.UserId] == state and state.loopToken == token do
			task.wait(getTickSeconds())
			if not player.Parent or playerStates[player.UserId] ~= state or state.loopToken ~= token then
				break
			end
			runPlayerIncomeSafely(player)
		end
	end)
end

local function ensureEvents()
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	incomeEvent = eventsFolder:FindFirstChild("IncomeReceived")
	if not incomeEvent then
		incomeEvent = Instance.new("RemoteEvent")
		incomeEvent.Name = "IncomeReceived"
		incomeEvent.Parent = eventsFolder
	end

	if not eventsFolder:FindFirstChild("CoinsUpdate") then
		local coinsUpdate = Instance.new("RemoteEvent")
		coinsUpdate.Name = "CoinsUpdate"
		coinsUpdate.Parent = eventsFolder
	end

	creatureLevelUpEvent = eventsFolder:FindFirstChild("CreatureLevelUp")
	playerLevelUpEvent = eventsFolder:FindFirstChild("PlayerLevelUp")
end

-- -- Initialize --

function BaseIncomeSystem.Init(playerDataMgr)
	if initialized then
		return
	end
	initialized = true

	PlayerDataManager = playerDataMgr
	ensureEvents()

	if PlayerDataManager.RegisterInventoryPostChangeListener then
		PlayerDataManager.RegisterInventoryPostChangeListener(function(player)
			BaseIncomeSystem.InvalidatePlayer(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		local currentPlayers = Players:GetPlayers()
		startPlayerLoop(player, #currentPlayers)
	end)

	Players.PlayerRemoving:Connect(function(player)
		stopPlayerLoop(player)
	end)

	for i, player in ipairs(Players:GetPlayers()) do
		startPlayerLoop(player, i)
	end
end

BaseIncomeSystem.OnIncomeReceived = Instance.new("BindableEvent")

return BaseIncomeSystem
