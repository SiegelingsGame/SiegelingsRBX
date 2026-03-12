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
		local speed = (GameConfig.DebugDoubleSpeed and 32) or 16
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

-- Wait for character to load (timeout prevents infinite hang if character never spawns)
local charTimeout = quickSpawnDebug and 5 or 30
if not player.Character then
	local startWait = tick()
	local charConn
	local charLoaded = false
	charConn = player.CharacterAdded:Connect(function()
		charLoaded = true
		if charConn then charConn:Disconnect() end
	end)
	while not charLoaded and (tick() - startWait) < charTimeout do
		task.wait(0.3)
	end
	if charConn then charConn:Disconnect() end
end
if player.Character then player.Character:WaitForChild("Humanoid", quickSpawnDebug and 3 or 10) end

local loadingDone = false

if quickSpawnDebug then
	-- Quick spawn debug: skip Events + LoadingReady; go straight to play
	statusLbl.Text = "Quick spawn (debug)"
	quoteLbl.Text = "Bypassing loading gate for testing"
	loadingDone = true
	-- #region agent log
	print("[DEBUG-1234af] LoadingGate: QuickSpawnDebugMode — bypassing loading gate")
	-- #endregion
else
	-- Wait for events folder (server creates this first thing)
	statusLbl.Text = pickRandomLoadingMsg()
	quoteLbl.Text = pickRandomQuote()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
	-- #region agent log
	print("[DEBUG-1234af] LoadingGate: Events folder " .. (eventsFolder and "received" or "TIMEOUT"))
	-- #endregion

	-- Rotate loading messages and quotes while waiting for creatures (2-3 seconds each)
	task.spawn(function()
		while not loadingDone do
			statusLbl.Text = pickRandomLoadingMsg()
			quoteLbl.Text = pickRandomQuote()
			task.wait(2 + math.random())  -- 2.0 to 3.0 seconds per message
		end
	end)

	-- Wait for server to signal creatures and models are ready (or timeout)
	local loadingReadyEvt = eventsFolder and eventsFolder:FindFirstChild("LoadingReady")
	local maxWait = (GameConfig.LoadingMaxWait or 60) + 5  -- extra buffer for network
	local ready = false
	if loadingReadyEvt then
		local conn
		conn = loadingReadyEvt.OnClientEvent:Connect(function()
			ready = true
			if conn then conn:Disconnect() end
		end)
		local start = tick()
		while not ready and (tick() - start) < maxWait do
			task.wait(0.3)
		end
		if conn then conn:Disconnect() end
	else
		task.wait(8)  -- fallback if event missing
	end
	loadingDone = true
	-- #region agent log
	print("[DEBUG-1234af] LoadingGate: LoadingReady received or timeout, proceeding")
	-- #endregion
end

-- Done
statusLbl.Text = "Track 'Em Down!"
quoteLbl.Text = ""
statusLbl.TextColor3 = WIND
task.wait(quickSpawnDebug and 0.2 or 0.4)

setFreeze(false)

TweenService:Create(bg, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
TweenService:Create(title, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
TweenService:Create(statusLbl, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
TweenService:Create(quoteLbl, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
task.wait(0.6)
sg:Destroy()
