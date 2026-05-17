--[[
	BaseIncomeSystem.lua
	ServerScriptService/BaseIncomeSystem

	Handles passive coin income from creatures stationed at the player's base.
	Only generates income while the player is ONLINE (active session only).

	Every income tick:
		- Iterates over all online players
		- Sums baseIncome from all creatures in their baseSlots
		- Adds coins to their balance
		- Fires a UI event so the client can show a floating "+X coins" indicator
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerScriptService = game:GetService("ServerScriptService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local DayNightCycle = nil
pcall(function() DayNightCycle = require(ServerScriptService.DayNightCycle) end)

local PlayerDataManager -- set during Init
local BaseIncomeSystem = {}

-- RemoteEvent references cached at Init (avoids FindFirstChild in the hot loop).
local incomeEvent
local playerLevelUpEvent
local creatureLevelUpEvent

-- -- Calculate total income for a player --

-- Shadow and Lightning (Electric) creatures stay active at night; others sleep.
local function isNightActiveElement(element)
	return element == "Shadow" or element == "Lightning"
end

function BaseIncomeSystem.CalculateIncome(player: Player): number
	local data = PlayerDataManager.GetData(player)
	if not data then return 0 end

	-- During night, defense and income monsters sleep — no income except Shadow/Lightning
	local isNight = DayNightCycle and DayNightCycle.IsNight and DayNightCycle.IsNight()

	local totalIncome = 0
	local getByUid = PlayerDataManager.GetCreatureByUid

	for _, uid in ipairs(data.baseSlots or {}) do
		if not uid or uid == "" then continue end
		local entry = getByUid(player, uid)
		if entry then
			local creatureInfo = CreatureData.GetById(entry.id)
			if creatureInfo then
				if isNight and not isNightActiveElement(creatureInfo.element) then
					-- Creature sleeps; no income
				else
					totalIncome += creatureInfo.baseIncome
				end
			end
		end
	end

	-- Rebirth: passive gold per tick (no creatures required)
	local bonuses = PlayerDataManager.GetRebirthBonuses and PlayerDataManager.GetRebirthBonuses(player)
	if bonuses and (bonuses.passiveGold or 0) > 0 then
		totalIncome = totalIncome + bonuses.passiveGold
	end

	-- Coin boost buff: 2x income
	if PlayerDataManager.HasBuff and PlayerDataManager.HasBuff(player, "coinboost") then
		totalIncome = totalIncome * 2
	end

	return totalIncome
end

-- -- Per-player tick handler (runs in its own task so one slow player can't stall others) --

local function processPlayerTick(player)
	if not player or not player.Parent then return end

	local income = BaseIncomeSystem.CalculateIncome(player)

	if income > 0 then
		local newBalance = PlayerDataManager.AddCoins(player, income)

		-- Track cumulative income for leaderboard
		local data = PlayerDataManager.GetData(player)
		if data and data.stats then
			data.stats.totalIncome = (data.stats.totalIncome or 0) + income
		end

		-- Award player XP for generating income
		if PlayerDataManager.AddPlayerXP then
			local pLvl, pDidLvl = PlayerDataManager.AddPlayerXP(player, GameConfig.PlayerXP_IncomeTick or 2)
			if pDidLvl and playerLevelUpEvent then
				playerLevelUpEvent:FireClient(player, pLvl)
			end
		end

		-- Notify client for UI feedback
		if incomeEvent then
			incomeEvent:FireClient(player, income, newBalance)
		end

		-- Fire signal for other systems
		BaseIncomeSystem.OnIncomeReceived:Fire(player, income)
	end

	-- Passive XP for creatures in defense slots (while stationed)
	local data = PlayerDataManager.GetData(player)
	if not (data and data.defenseSlots and PlayerDataManager.GetFilledSlotCount(player, "defense") > 0) then
		return
	end

	local isNight = DayNightCycle and DayNightCycle.IsNight and DayNightCycle.IsNight()
	local baseXP = GameConfig.DefensePassiveXP or 3
	local addXP = PlayerDataManager.AddXPNoNotify or PlayerDataManager.AddXP

	-- Collect level changes so we can fire one batched Eleminion event instead of
	-- six individual deferred tasks per player per tick.
	local levelChanges = {}

	for _, uid in ipairs(data.defenseSlots) do
		if not uid or uid == "" then continue end
		local xpToAdd = baseXP

		-- Only re-check the creature's element when it's actually night; on day ticks
		-- this branch is skipped entirely (saves an inventory lookup per defense slot).
		if isNight then
			local entry = PlayerDataManager.GetCreatureByUid(player, uid)
			local info = entry and CreatureData.GetById(entry.id)
			if not info or not isNightActiveElement(info.element) then
				xpToAdd = 0
			end
		end

		if xpToAdd > 0 then
			local newLvl, didLevel, creatureId = addXP(player, uid, xpToAdd)
			if didLevel and creatureLevelUpEvent then
				creatureLevelUpEvent:FireClient(player, uid, newLvl)
			end
			if creatureId then
				levelChanges[#levelChanges + 1] = {
					creatureId = creatureId,
					uid = uid,
					newLevel = newLvl,
					amount = xpToAdd,
					leveled = didLevel == true,
				}
			end
		end
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

-- -- Initialize --

function BaseIncomeSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr

	-- Get or create events folder
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	-- Create income event if it doesn't exist
	if not eventsFolder:FindFirstChild("IncomeReceived") then
		local incomeEvt = Instance.new("RemoteEvent")
		incomeEvt.Name = "IncomeReceived"
		incomeEvt.Parent = eventsFolder
	end

	-- Create coins update event if it doesn't exist
	if not eventsFolder:FindFirstChild("CoinsUpdate") then
		local coinsUpdate = Instance.new("RemoteEvent")
		coinsUpdate.Name = "CoinsUpdate"
		coinsUpdate.Parent = eventsFolder
	end

	-- Cache RemoteEvent references once instead of FindFirstChild every tick.
	incomeEvent = eventsFolder:FindFirstChild("IncomeReceived")
	playerLevelUpEvent = eventsFolder:FindFirstChild("PlayerLevelUp")
	creatureLevelUpEvent = eventsFolder:FindFirstChild("CreatureLevelUp")

	-- Start income loop
	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
			doIncomeTick()
		end
	end)

end

-- Add signal for income notifications
BaseIncomeSystem.OnIncomeReceived = Instance.new("BindableEvent")

return BaseIncomeSystem
