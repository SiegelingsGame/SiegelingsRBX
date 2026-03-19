-- LoadingGate.client.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Name this "!LoadingGate" in Roblox so it runs first.
-- Shows loading screen, freezes player, waits for character + events, done.sdfsf

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local playerGui = player:WaitForChild("PlayerGui")

local sg = Instance.new("ScreenGui")
sg.Name = "LoadingScreen"; sg.DisplayOrder = 999
sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.Parent = playerGui

-- Elemental theme: Fire (Red), Wind (Green), Air (White), Ice (Blue)
local FIRE = Color3.fromRGB(255, 70, 50)
local WIND = Color3.fromRGB(80, 220, 120)
local AIR  = Color3.fromRGB(248, 252, 255)
local ICE  = Color3.fromRGB(100, 180, 255)

local bg = Instance.new("Frame")
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = Color3.fromRGB(6, 14, 32)
bg.BorderSizePixel = 0; bg.Parent = sg

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.6, 0, 0, 50); title.Position = UDim2.new(0.2, 0, 0.35, 0)
title.BackgroundTransparency = 1; title.Text = "Welcome SiegeKnights!"
title.TextColor3 = FIRE
title.Font = Enum.Font.GothamBlack; title.TextSize = 36; title.Parent = bg

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(0.5, 0, 0, 24); statusLbl.Position = UDim2.new(0.25, 0, 0.48, 0)
statusLbl.BackgroundTransparency = 1; statusLbl.Text = "Loading..."
statusLbl.TextColor3 = AIR
statusLbl.Font = Enum.Font.GothamMedium; statusLbl.TextSize = 16; statusLbl.Parent = bg

local quoteLbl = Instance.new("TextLabel")
quoteLbl.Size = UDim2.new(0.7, 0, 0, 60); quoteLbl.Position = UDim2.new(0.15, 0, 0.54, 0)
quoteLbl.BackgroundTransparency = 1; quoteLbl.Text = ""
quoteLbl.TextColor3 = Color3.fromRGB(180, 200, 220)
quoteLbl.Font = Enum.Font.Gotham; quoteLbl.TextSize = 13; quoteLbl.TextWrapped = true
quoteLbl.Parent = bg

local Random = Random.new()

-- Lore-infused loading messages (unique, randomized).
local LOADING_MESSAGES = {
	"Anointing shields at the Rite of Thirteen...",
	"Forging Capture Cards in Maestro's kiln...",
	"Consulting the Eleminions of the Four Houses...",
	"Summoning Sieglings from the flame-lands...",
	"Building bases upon the frontier...",
	"Herding Cloudhares through the Zephyr winds...",
	"Taming Emberpups in House Emberward...",
	"Chilling Frostflies in House Frostholm...",
	"Polishing Glaciuses at the ice forges...",
	"Warming Firskies for the dawn muster...",
	"Growing Squire Buds in the training yards...",
	"Hexing Hexweavers in the shadow courts...",
	"Storming Thunderlords across the arena...",
	"Voiding Voidmaws beyond the safe paths...",
	"Grooming Cinderstags in House Cinderthorn...",
	"Buffing Pylords for the defense grid...",
	"Binding Sieglings to the Valorous pact...",
	"Raising sigils for the Council of Houses...",
	"Channeling the third eye of the Eleminions...",
	"Preparing the battle team formation...",
	"Wiring Monkwatts to the combiner forge...",
	"Fluffing Snowdrifts in the northern wastes...",
	"Shading Shadeblobs in the unlit grottos...",
	"Feeding Appleheads at the harvest plots...",
}

-- Quotes from Great Sieg Knights, Squires, and Lords (lessons + game tips in lore jargon)
local LORE_QUOTES = {
	-- Lord Theron Emberward (Fire)
	'"Through flame, we hold." — Lord Theron Emberward',
	'"Win or lose, you represent your house and the Valorous way." — Lord Theron',
	'"Set one creature as your Favorite—your companion fights by your side in the wilds." — Lord Theron',
	'"The arena teaches. Both victory and defeat." — Lord Theron Emberward',
	-- Lady Elara Frostholm (Ice)
	'"Cold steel, warm heart." — Lady Elara Frostholm',
	'"Guard your shield. Guard your cards. They are the proof of your bond." — Lady Elara',
	'"Not all who wield Sieglings are Valorous. Defend your base well." — Lady Elara',
	'"Do not force the bond. A Siegling that refuses the card cannot be bound." — Lady Elara',
	'"Beware raids. Other knights may assault your base to steal your Sieglings." — Lady Elara',
	-- Lord Marcus Cinderthorn (Earth)
	'"Patience and respect matter more than strength when capturing." — Lord Marcus Cinderthorn',
	'"Three Normals become Silver. Three Silvers become Gold. Three Golds become Legend." — Lord Marcus',
	'"Use the combiner. A stronger team means a stronger defense." — Lord Marcus',
	'"Forge and defend." — Lord Marcus Cinderthorn',
	'"Choose based on each creature\'s strengths—Fire for offense, Ice for control." — Lord Marcus',
	-- Lord Kael Zephyran (Air)
	'"Swift as the storm means knowing when to strike and when to hold." — Lord Kael Zephyran',
	'"Everybody is Ser. Only one is Sire." — Lord Kael',
	'"Build a balanced team. Earth for endurance, Air for speed." — Lord Kael',
	'"Assign your Sieglings to Income, Defense, and Battle. Choose wisely." — Lord Kael Zephyran',
	-- Squires & Hedge Knights
	'"A Squire learns: your companion is your first line of defense. Choose well." — Anon. Squire',
	'"Press [E] to target, [F] to strike. Even a hedge knight knows the basics." — Training Yard Proverb',
	'"Raiders lay siege without honor. Stand against them with your defense team." — Siege Knight\'s Creed',
	'"Home Recall channels five seconds. Use it when the wilds grow too fierce." — Squire\'s Handbook',
	'"Unlock Floor 2 for the battle grid. Five Sieglings in formation win duels." — Arena Veteran',
	'"Rarer creatures cost more gold to capture. Save your coins for the right bond." — House Steward',
	'"The Valorous bond by consent. The Unvalorous force. Do not become them." — Council Edict',
}

local function pickRandomLoadingMsg()
	return LOADING_MESSAGES[Random:NextInteger(1, #LOADING_MESSAGES)]
end

local function pickRandomQuote()
	return LORE_QUOTES[Random:NextInteger(1, #LORE_QUOTES)]
end

-- Freeze player
local frozen = true
local function setFreeze(on)
	frozen = on
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	if hum then
		local speed = (GameConfig.DebugDoubleSpeed and 32) or (GameConfig.PlayerWalkSpeed or 16)
		hum.WalkSpeed = on and 0 or speed
		hum.JumpPower = on and 0 or 50
	end
end

setFreeze(true)
player.CharacterAdded:Connect(function(char)
	if frozen then
		local hum = char:WaitForChild("Humanoid", 5)
		if hum and frozen then hum.WalkSpeed = 0; hum.JumpPower = 0 end
	end
end)

local quickSpawnDebug = GameConfig.QuickSpawnDebugMode == true
local startupClock = os.clock()
local metricsEnabled = GameConfig.StartupMetricLogEnabled == true
local function logMetric(label)
	if metricsEnabled then
		print(("[StartupMetricClient] %s=%.2fs"):format(label, os.clock() - startupClock))
	end
end

local loadingDone = false
local characterReady = false
local serverReady = false
local loadingStatusReason = "unknown"

task.spawn(function()
	-- Wait for character/humanoid in parallel with server readiness.
	local charTimeout = quickSpawnDebug and 5 or 30
	local humTimeout = quickSpawnDebug and 3 or 10
	local char = player.Character
	if not char then
		local charLoaded = false
		local charConn
		charConn = player.CharacterAdded:Connect(function(newChar)
			char = newChar
			charLoaded = true
			if charConn then charConn:Disconnect() end
		end)
		local startWait = tick()
		while not charLoaded and (tick() - startWait) < charTimeout do
			task.wait(0.1)
		end
		if charConn then charConn:Disconnect() end
	end
	if char then
		char:WaitForChild("Humanoid", humTimeout)
		characterReady = true
		logMetric("join_to_character_ready")
	end
end)

if quickSpawnDebug then
	statusLbl.Text = "Quick spawn (debug)"
	quoteLbl.Text = "Bypassing loading gate for testing"
	serverReady = true
	loadingStatusReason = "quick_spawn_debug"
	-- #region agent log
	print("[DEBUG-1234af] LoadingGate: QuickSpawnDebugMode — bypassing loading gate")
	-- #endregion
else
	statusLbl.Text = pickRandomLoadingMsg()
	quoteLbl.Text = pickRandomQuote()

	task.spawn(function()
		while not loadingDone do
			statusLbl.Text = pickRandomLoadingMsg()
			quoteLbl.Text = pickRandomQuote()
			task.wait(2 + math.random())
		end
	end)

	task.spawn(function()
		local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
		-- #region agent log
		print("[DEBUG-1234af] LoadingGate: Events folder " .. (eventsFolder and "received" or "TIMEOUT"))
		-- #endregion
		if not eventsFolder then
			serverReady = true
			loadingStatusReason = "events_timeout_fallback"
			return
		end

		local criticalEvt = eventsFolder:FindFirstChild("LoadingCriticalReady")
		local worldReadyEvt = eventsFolder:FindFirstChild("LoadingReady")
		local maxCriticalWait = GameConfig.LoadingCriticalMaxWait or 18
		local maxWorldWait = (GameConfig.LoadingMaxWait or 25) + 5
		local signalReceived = false
		local criticalConn, worldConn

		if criticalEvt then
			criticalConn = criticalEvt.OnClientEvent:Connect(function()
				signalReceived = true
				loadingStatusReason = "critical_ready_signal"
				serverReady = true
			end)
		end
		if worldReadyEvt then
			worldConn = worldReadyEvt.OnClientEvent:Connect(function()
				if not serverReady then
					signalReceived = true
					loadingStatusReason = "world_ready_signal"
					serverReady = true
				end
			end)
		end

		local started = tick()
		while not signalReceived and (tick() - started) < maxCriticalWait do
			task.wait(0.1)
		end

		if not signalReceived then
			local worldStart = tick()
			while not signalReceived and (tick() - worldStart) < maxWorldWait do
				task.wait(0.15)
			end
		end

		if criticalConn then criticalConn:Disconnect() end
		if worldConn then worldConn:Disconnect() end

		if not serverReady then
			serverReady = true
			loadingStatusReason = "signal_timeout_fallback"
		end
		logMetric("join_to_server_ready")
	end)
end

local releaseDeadline = tick() + ((GameConfig.LoadingCriticalMaxWait or 18) + 2)
while tick() < releaseDeadline do
	if characterReady and serverReady then
		break
	end
	task.wait(0.05)
end
loadingDone = true
if not characterReady then
	loadingStatusReason = "character_timeout_fallback"
end
logMetric("join_to_control_release")
print("[DEBUG-1234af] LoadingGate: proceeding reason=" .. tostring(loadingStatusReason))

-- Done
statusLbl.Text = "Track 'Em Down!"
quoteLbl.Text = ""
statusLbl.TextColor3 = WIND
task.wait(quickSpawnDebug and 0.05 or 0.1)

setFreeze(false)

TweenService:Create(bg, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
TweenService:Create(title, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
TweenService:Create(statusLbl, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
TweenService:Create(quoteLbl, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
task.delay(0.35, function()
	if sg and sg.Parent then
		sg:Destroy()
	end
end)
