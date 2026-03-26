--[[
	LivingWorldChatClient.client.lua - StarterPlayer.StarterPlayerScripts
	"Living World" ticker: periodically shows 4-message NPC conversations and
	injects system alerts (Nightfall, 4-hour intervals) in character voices.
	Requires: NotificationManager, LivingWorldData, GameConfig.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
if not Modules then return end

local NotificationManager = require(Modules:WaitForChild("NotificationManager"))
local LivingWorldData = require(Modules:WaitForChild("LivingWorldData"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))

-- NPC chat notifications are intentionally disabled.
if _G.LivingWorldChatClient == nil then
	_G.LivingWorldChatClient = {}
end
_G.LivingWorldChatClient.InjectSystemAlert = function() end
return

-- Config: timing
local CONVERSATION_INTERVAL_MIN = 55   -- seconds between starting each conversation
local CONVERSATION_INTERVAL_MAX = 95
local MESSAGE_DELAY = 7                -- seconds between each of the 4 messages in a conversation
local TIME_CHECK_INTERVAL = 15         -- seconds between time/clock checks for system alerts
local FILLER_INTERVAL = 25             -- seconds between filler messages (keeps ticker continuous when idle)
local NIGHTFALL_WINDOW = 0.15          -- ClockTime window to trigger nightfall (e.g. 17.85–18.15)
local FOUR_HOUR_BLOCKS = { 0, 4, 8, 12, 16, 20 }

local lastConversationTime = 0
local lastNightfallTriggered = false
local lastTimeAlertHour = nil

local function getNpcName(id)
	return LivingWorldData.GetNpcName(id) or "Unknown"
end

-- Push one ticker line. category: "conversation" (blue), nil (gold default)
local function pushTickerLine(name, message, iconType, category)
	local text = string.format("[%s]: %s", name, message)
	NotificationManager.Ticker(text, iconType, category or "conversation")
end

-- Push system alert line (gold, no conversation styling)
local function pushSystemLine(name, message, iconType)
	local text = string.format("[%s]: %s", name, message)
	NotificationManager.Ticker(text, iconType, "arena")  -- gold
end

-- Pick a random conversation and play it (4 messages with delays)
local function playRandomConversation()
	local convos = LivingWorldData.Conversations
	if not convos or #convos == 0 then return end
	local c = convos[math.random(1, #convos)]
	local initName = getNpcName(c.initiatorId)
	local respName = getNpcName(c.responderId)
	-- Message order: Initiator, Responder, Initiator, Responder
	pushTickerLine(initName, c.messages[1], nil)
	task.delay(MESSAGE_DELAY, function()
		pushTickerLine(respName, c.messages[2], nil)
		task.delay(MESSAGE_DELAY, function()
			pushTickerLine(initName, c.messages[3], nil)
			task.delay(MESSAGE_DELAY, function()
				pushTickerLine(respName, c.messages[4], nil)
			end)
		end)
	end)
end

-- Push a single conversation line (for filling when no system alert)
local function pushSingleConversationLine()
	local convos = LivingWorldData.Conversations
	if not convos or #convos == 0 then return end
	local c = convos[math.random(1, #convos)]
	local msgIdx = math.random(1, 4)
	local npcId = (msgIdx == 1 or msgIdx == 3) and c.initiatorId or c.responderId
	local name = getNpcName(npcId)
	local text = c.messages[msgIdx]
	pushTickerLine(name, text, nil, "conversation")
end

-- Inject a system alert (nightfall or time) using a random NPC voice. System alerts are short,
-- so we also add conversation messages to fill the ticker (no timeout).
local function injectSystemAlertWithFill(alertType, data)
	data = data or {}
	local list = LivingWorldData.SystemAlerts and LivingWorldData.SystemAlerts[alertType]
	if not list or #list == 0 then
		pushSingleConversationLine()
		return
	end
	local entry = list[math.random(1, #list)]
	local name = getNpcName(entry.npcId)
	local text = entry.text
	if data.hour then
		text = (text:gsub("{hour}", tostring(data.hour)))
	end
	local iconType = (alertType == "nightfall") and "alert" or nil
	pushSystemLine(name, text, iconType)
	-- Short message: fill with conversation messages despite timeout
	pushSingleConversationLine()
	task.delay(2, pushSingleConversationLine)
	task.delay(4, pushSingleConversationLine)
end

-- Expose for server or other scripts (e.g. RemoteEvent)
if _G.LivingWorldChatClient == nil then
	_G.LivingWorldChatClient = {}
end
-- Public API: InjectSystemAlert now fills with conversations when short
function LivingWorldChatClient_InjectSystemAlert(alertType, data)
	injectSystemAlertWithFill(alertType, data)
end
_G.LivingWorldChatClient.InjectSystemAlert = LivingWorldChatClient_InjectSystemAlert

-- Conversation loop: every CONVERSATION_INTERVAL_MIN–MAX seconds, play a random conversation
task.spawn(function()
	lastConversationTime = tick()
	while true do
		local interval = math.random(CONVERSATION_INTERVAL_MIN, CONVERSATION_INTERVAL_MAX)
		task.wait(interval)
		playRandomConversation()
		lastConversationTime = tick()
	end
end)

-- Time-based system alerts: Nightfall and 4-hour marks (uses Lighting.ClockTime, replicated from server)
local dayNightEnabled = true
local nightStartHour = 18
local nightEndHour = 6

task.spawn(function()
	while true do
		task.wait(TIME_CHECK_INTERVAL)
		local ok, cfg = pcall(function() return GameConfig end)
		if ok and cfg then
			dayNightEnabled = cfg.DayNightCycleEnabled ~= false
			nightStartHour = tonumber(cfg.NightStartHour) or 18
			nightEndHour = tonumber(cfg.NightEndHour) or 6
		end
		local clockTime = Lighting.ClockTime or 0

		local didInject = false

		-- Nightfall: crossing into night (e.g. ClockTime goes past 18)
		if dayNightEnabled then
			if clockTime >= nightStartHour - NIGHTFALL_WINDOW and clockTime <= nightStartHour + NIGHTFALL_WINDOW then
				if not lastNightfallTriggered then
					lastNightfallTriggered = true
					LivingWorldChatClient_InjectSystemAlert("nightfall")
					didInject = true
				end
			else
				if clockTime < nightStartHour - 1 or (clockTime >= nightEndHour and clockTime < nightStartHour - 0.5) then
					lastNightfallTriggered = false
				end
			end
		end

		-- 4-hour interval: trigger once per block (0, 4, 8, 12, 16, 20)
		local hour = math.floor(clockTime) % 24
		local isBlockHour = false
		for _, block in ipairs(FOUR_HOUR_BLOCKS) do
			if hour == block then isBlockHour = true break end
		end
		if isBlockHour then
			if lastTimeAlertHour ~= hour then
				lastTimeAlertHour = hour
				LivingWorldChatClient_InjectSystemAlert("time", { hour = hour })
				didInject = true
			end
		else
			lastTimeAlertHour = nil
		end

		-- If no system message was added, add a conversation message so the ticker stays continuous
		if not didInject then
			pushSingleConversationLine()
		end
	end
end)

-- Filler loop: add conversation lines periodically to keep ticker content long and scroll smooth
-- (avoids short strips that cause frequent loop resets / visible jumps)
task.spawn(function()
	while true do
		task.wait(FILLER_INTERVAL)
		pushSingleConversationLine()
	end
end)
