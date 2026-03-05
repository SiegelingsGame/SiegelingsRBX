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

	for _, uid in ipairs(data.baseSlots or {}) do
		if not uid or uid == "" then continue end
		-- Find the creature entry by UID
		for _, entry in ipairs(data.inventory) do
			if entry.uid == uid then
				local creatureInfo = CreatureData.GetById(entry.id)
				if creatureInfo then
					if isNight and not isNightActiveElement(creatureInfo.element) then
						-- Creature sleeps; no income
					else
						totalIncome += creatureInfo.baseIncome
					end
				end
				break
			end
		end
	end

	-- Rebirth: passive gold per tick (no creatures required)
	local bonuses = PlayerDataManager.GetRebirthBonuses and PlayerDataManager.GetRebirthBonuses(player)
	if bonuses and (bonuses.passiveGold or 0) > 0 then
		totalIncome = totalIncome + bonuses.passiveGold
	end

	return totalIncome
end

-- -- Income tick --

local function doIncomeTick()
	local incomeEvent = ReplicatedStorage.Events:FindFirstChild("IncomeReceived")

	for _, player in ipairs(Players:GetPlayers()) do
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
				if pDidLvl then
					local events = ReplicatedStorage:FindFirstChild("Events")
					local lvlEvt = events and events:FindFirstChild("PlayerLevelUp")
					if lvlEvt then lvlEvt:FireClient(player, pLvl) end
				end
			end

			-- Notify client for UI feedback
			if incomeEvent then
				incomeEvent:FireClient(player, income, newBalance)
			end

			-- Fire signal for other systems
			BaseIncomeSystem.OnIncomeReceived:Fire(player, income)
		end

		-- Passive XP for creatures in defense slots (while stationed) — skip during night except Shadow/Lightning
		local data = PlayerDataManager.GetData(player)
		local isNight = DayNightCycle and DayNightCycle.IsNight and DayNightCycle.IsNight()
		if data and data.defenseSlots and PlayerDataManager.GetFilledSlotCount(player, "defense") > 0 then
			local baseXP = GameConfig.DefensePassiveXP or 3
			for _, uid in ipairs(data.defenseSlots) do
				if not uid or uid == "" then continue end
				local xpToAdd = baseXP
				if isNight then
					for _, entry in ipairs(data.inventory or {}) do
						if entry.uid == uid then
							local info = CreatureData.GetById(entry.id)
							if not info or not isNightActiveElement(info.element) then
								xpToAdd = 0  -- Creature sleeps; no XP
							end
							break
						end
					end
				end
				if xpToAdd > 0 then
					local newLvl, didLevel = PlayerDataManager.AddXP(player, uid, xpToAdd)
					if didLevel then
						local events = ReplicatedStorage:FindFirstChild("Events")
						local lvlEvt = events and events:FindFirstChild("CreatureLevelUp")
						if lvlEvt then lvlEvt:FireClient(player, uid, newLvl) end
					end
				end
			end
		end
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
		local incomeEvent = Instance.new("RemoteEvent")
		incomeEvent.Name = "IncomeReceived"
		incomeEvent.Parent = eventsFolder
	end

	-- Create coins update event if it doesn't exist
	if not eventsFolder:FindFirstChild("CoinsUpdate") then
		local coinsUpdate = Instance.new("RemoteEvent")
		coinsUpdate.Name = "CoinsUpdate"
		coinsUpdate.Parent = eventsFolder
	end

	-- Start income loop
	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
			doIncomeTick()
		end
	end)

end � income every " .. GameConfig.IncomeTickSeconds .. "s")
end

-- Add signal for income notifications
BaseIncomeSystem.OnIncomeReceived = Instance.new("BindableEvent")

return BaseIncomeSystem