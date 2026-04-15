-- ═══════════════════════════════════════════════════════════════════════════════
-- LoadingGate.client.lua — StarterPlayer.StarterPlayerScripts (LocalScript)
-- ═══════════════════════════════════════════════════════════════════════════════
-- Name this "!LoadingGate" in Roblox so it runs before other client scripts.
--
-- Full loading gate that freezes the player, shows a themed loading screen,
-- starts music immediately, and waits for ALL of these before releasing:
--   1. Character + Humanoid exist
--   2. Server fires LoadingCriticalReady (base assigned, creatures placed)
--   3. Base plot + creature orbs replicated, and character is near your plot
--      (server may teleport after spawn — do not release while still at default spawn)
--   4. ContentProvider preloads nearby assets so nothing pops in
--
-- Only after all conditions are met does the screen fade out and the player
-- gains control. This prevents the "empty world" flash on join.
--
-- Sets player attribute "LoadingGateActive" = true while the gate is up,
-- so other systems (GameplayMusic) can coordinate.
-- ═══════════════════════════════════════════════════════════════════════════════

local ContentProvider = game:GetService("ContentProvider")
local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService    = game:GetService("SoundService")
local TweenService    = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local player    = Players.LocalPlayer
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Quick-spawn debug bypass
-- ═══════════════════════════════════════════════════════════════════════════════
local quickSpawnDebug = GameConfig.QuickSpawnDebugMode == true

-- ═══════════════════════════════════════════════════════════════════════════════
-- Startup metrics
-- ═══════════════════════════════════════════════════════════════════════════════
local startupClock   = os.clock()
local metricsEnabled = GameConfig.StartupMetricLogEnabled == true
local function logMetric(label)
	if metricsEnabled then
		print(("[StartupMetricClient] %s=%.2fs"):format(label, os.clock() - startupClock))
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Mark loading gate as active (other scripts check this attribute)
-- ═══════════════════════════════════════════════════════════════════════════════
player:SetAttribute("LoadingGateActive", true)

-- ═══════════════════════════════════════════════════════════════════════════════
-- Freeze player movement
-- ═══════════════════════════════════════════════════════════════════════════════
local frozen = true
local function setFreeze(on)
	frozen = on
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	if hum then
		local base = (GameConfig.DebugDoubleSpeed and 32) or (GameConfig.PlayerWalkSpeed or 16)
		local lm = player:GetAttribute("WorldStat_LevelMult")
		if type(lm) ~= "number" or lm <= 0 then
			lm = 1
		end
		local speed = math.floor(base * lm)
		hum.WalkSpeed  = on and 0 or speed
		hum.JumpPower  = on and 0 or 50
	end
end

setFreeze(true)
player.CharacterAdded:Connect(function(char)
	if frozen then
		local hum = char:WaitForChild("Humanoid", 5)
		if hum and frozen then hum.WalkSpeed = 0; hum.JumpPower = 0 end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- UI: Full-screen loading overlay
-- ═══════════════════════════════════════════════════════════════════════════════

-- Elemental palette
local FIRE = Color3.fromRGB(255, 70, 50)
local WIND = Color3.fromRGB(80, 220, 120)
local AIR  = Color3.fromRGB(248, 252, 255)
local ICE  = Color3.fromRGB(100, 180, 255)

local sg = Instance.new("ScreenGui")
sg.Name = "LoadingScreen"
sg.DisplayOrder = 999
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.Parent = playerGui

local bg = Instance.new("Frame")
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = Color3.fromRGB(6, 14, 32)
bg.BorderSizePixel = 0
bg.Parent = sg

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.6, 0, 0, 50)
title.Position = UDim2.new(0.2, 0, 0.30, 0)
title.BackgroundTransparency = 1
title.Text = "Welcome SiegeKnights!"
title.TextColor3 = FIRE
title.Font = Enum.Font.GothamBlack
title.TextSize = 36
title.Parent = bg

-- Status label (loading messages)
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(0.5, 0, 0, 24)
statusLbl.Position = UDim2.new(0.25, 0, 0.43, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Loading..."
statusLbl.TextColor3 = AIR
statusLbl.Font = Enum.Font.GothamMedium
statusLbl.TextSize = 16
statusLbl.Parent = bg

-- Lore quote
local quoteLbl = Instance.new("TextLabel")
quoteLbl.Size = UDim2.new(0.7, 0, 0, 60)
quoteLbl.Position = UDim2.new(0.15, 0, 0.50, 0)
quoteLbl.BackgroundTransparency = 1
quoteLbl.Text = ""
quoteLbl.TextColor3 = Color3.fromRGB(180, 200, 220)
quoteLbl.Font = Enum.Font.Gotham
quoteLbl.TextSize = 13
quoteLbl.TextWrapped = true
quoteLbl.Parent = bg

-- Progress bar (thin, bottom of loading screen)
local progressBarBg = Instance.new("Frame")
progressBarBg.Size = UDim2.new(0.5, 0, 0, 6)
progressBarBg.Position = UDim2.new(0.25, 0, 0.62, 0)
progressBarBg.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
progressBarBg.BorderSizePixel = 0
progressBarBg.Parent = bg

local progressBarCorner = Instance.new("UICorner")
progressBarCorner.CornerRadius = UDim.new(0, 3)
progressBarCorner.Parent = progressBarBg

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = FIRE
progressFill.BorderSizePixel = 0
progressFill.Parent = progressBarBg

local progressFillCorner = Instance.new("UICorner")
progressFillCorner.CornerRadius = UDim.new(0, 3)
progressFillCorner.Parent = progressFill

-- ═══════════════════════════════════════════════════════════════════════════════
-- Loading messages & lore quotes (randomized, rotated while loading)
-- ═══════════════════════════════════════════════════════════════════════════════
local Rand = Random.new()

local LOADING_MESSAGES = {
	"Anointing shields at the Rite of Thirteen...",
	"Forging Capture Cards in Maestro's kiln...",
	"Consulting the Eleminions of the Four Houses...",
	"Summoning Siegelings from the flame-lands...",
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
	"Binding Siegelings to the Valorous pact...",
	"Raising sigils for the Council of Houses...",
	"Channeling the third eye of the Eleminions...",
	"Preparing the battle team formation...",
	"Wiring Monkwatts to the combiner forge...",
	"Fluffing Snowdrifts in the northern wastes...",
	"Shading Shadeblobs in the unlit grottos...",
	"Feeding Appleheads at the harvest plots...",
}

local LORE_QUOTES = {
	'"Through flame, we hold." — Lord Theron Emberward',
	'"Win or lose, you represent your house and the Valorous way." — Lord Theron',
	'"Set one creature as your Favorite—your companion fights by your side in the wilds." — Lord Theron',
	'"The arena teaches. Both victory and defeat." — Lord Theron Emberward',
	'"Cold steel, warm heart." — Lady Elara Frostholm',
	'"Guard your shield. Guard your cards. They are the proof of your bond." — Lady Elara',
	'"Not all who wield Siegelings are Valorous. Defend your base well." — Lady Elara',
	'"Do not force the bond. A Siegeling that refuses the card cannot be bound." — Lady Elara',
	'"Beware raids. Other knights may assault your base to steal your Siegelings." — Lady Elara',
	'"Patience and respect matter more than strength when capturing." — Lord Marcus Cinderthorn',
	'"Three Normals become Silver. Three Silvers become Gold. Three Golds become Legend." — Lord Marcus',
	'"Use the combiner. A stronger team means a stronger defense." — Lord Marcus',
	'"Forge and defend." — Lord Marcus Cinderthorn',
	'"Choose based on each creature\'s strengths—Fire for offense, Ice for control." — Lord Marcus',
	'"Swift as the storm means knowing when to strike and when to hold." — Lord Kael Zephyran',
	'"Everybody is Ser. Only one is Sire." — Lord Kael',
	'"Build a balanced team. Earth for endurance, Air for speed." — Lord Kael',
	'"Assign your Siegelings to Income, Defense, and Battle. Choose wisely." — Lord Kael Zephyran',
	'"A Squire learns: your companion is your first line of defense. Choose well." — Anon. Squire',
	'"Press [E] to target, [F] to strike. Even a hedge knight knows the basics." — Training Yard Proverb',
	'"Raiders lay siege without honor. Stand against them with your defense team." — Siege Knight\'s Creed',
	'"Home Recall channels five seconds. Use it when the wilds grow too fierce." — Squire\'s Handbook',
	'"Unlock Floor 2 for the battle grid. Five Siegelings in formation win duels." — Arena Veteran',
	'"Rarer creatures cost more gold to capture. Save your coins for the right bond." — House Steward',
	'"The Valorous bond by consent. The Unvalorous force. Do not become them." — Council Edict',
}

local function pickRandom(tbl)
	return tbl[Rand:NextInteger(1, #tbl)]
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Progress tracking (0..1) — drives the progress bar
-- ═══════════════════════════════════════════════════════════════════════════════
local progress = 0
local PROGRESS_WEIGHTS = {
	character  = 0.15,   -- character + humanoid exist
	server     = 0.35,   -- LoadingCriticalReady received (base placed server-side)
	baseVisual = 0.25,   -- base plot + creature orbs visible on client
	preload    = 0.25,   -- ContentProvider preloaded nearby assets
}

local progressParts = { character = 0, server = 0, baseVisual = 0, preload = 0 }
local function updateProgress(part, value)
	progressParts[part] = math.clamp(value, 0, 1)
	local total = 0
	for k, v in pairs(progressParts) do
		total = total + v * (PROGRESS_WEIGHTS[k] or 0)
	end
	progress = math.clamp(total, 0, 1)
	-- Animate the bar
	TweenService:Create(progressFill, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {
		Size = UDim2.new(progress, 0, 1, 0)
	}):Play()
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- MUSIC: Start the main theme immediately during loading
-- ═══════════════════════════════════════════════════════════════════════════════
-- We play the main theme directly here so the player hears music from the
-- moment the loading screen appears. GameplayMusic.client.lua will take over
-- seamlessly once the gate drops (it checks for an already-playing track).
local loadingMusic = nil
do
	local mainThemeName = "Siegelings_MainTheme"
	if GameConfig.GameplayMusic and GameConfig.GameplayMusic.MainThemeName then
		mainThemeName = GameConfig.GameplayMusic.MainThemeName
	end
	local snd = SoundService:FindFirstChild(mainThemeName)
	if snd and snd:IsA("Sound") then
		-- Preload the music asset first so there's no silence gap
		pcall(function() ContentProvider:PreloadAsync({ snd }) end)
		loadingMusic = snd
		snd.Looped = true
		snd.Volume = 0
		snd:Play()
		-- Fade in over 2 seconds
		TweenService:Create(snd, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Volume = 0.8
		}):Play()
		print("[LoadingGate] Started loading music: " .. mainThemeName)
	else
		print("[LoadingGate] Main theme '" .. mainThemeName .. "' not found in SoundService — no loading music")
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- GATE CONDITION 1: Character + Humanoid ready
-- ═══════════════════════════════════════════════════════════════════════════════
local characterReady = false
task.spawn(function()
	local charTimeout = quickSpawnDebug and 5 or 30
	local humTimeout  = quickSpawnDebug and 3 or 10
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
		updateProgress("character", 1)
		logMetric("join_to_character_ready")
	else
		-- Timeout fallback — mark ready so we don't hang forever
		characterReady = true
		updateProgress("character", 1)
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- GATE CONDITION 2: Server signals LoadingCriticalReady
-- (fires after plot assigned + PlaceCreatures completes + teleport done)
-- ═══════════════════════════════════════════════════════════════════════════════
local serverReady = false
local loadingStatusReason = "unknown"

if quickSpawnDebug then
	serverReady = true
	loadingStatusReason = "quick_spawn_debug"
	updateProgress("server", 1)
	updateProgress("baseVisual", 1)
	updateProgress("preload", 1)
else
	-- Rotate loading messages while waiting
	task.spawn(function()
		statusLbl.Text = pickRandom(LOADING_MESSAGES)
		quoteLbl.Text  = pickRandom(LORE_QUOTES)
		while not serverReady do
			task.wait(2 + math.random())
			if not serverReady then
				statusLbl.Text = pickRandom(LOADING_MESSAGES)
				quoteLbl.Text  = pickRandom(LORE_QUOTES)
			end
		end
	end)

	-- Listen for server signals
	task.spawn(function()
		local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
		if not eventsFolder then
			serverReady = true
			loadingStatusReason = "events_timeout_fallback"
			updateProgress("server", 1)
			return
		end

		local criticalEvt  = eventsFolder:FindFirstChild("LoadingCriticalReady")
		local worldReadyEvt = eventsFolder:FindFirstChild("LoadingReady")
		local maxCriticalWait = GameConfig.LoadingCriticalMaxWait or 18
		local maxWorldWait    = (GameConfig.LoadingMaxWait or 25) + 5
		local signalReceived  = false
		local criticalConn, worldConn

		if criticalEvt then
			criticalConn = criticalEvt.OnClientEvent:Connect(function()
				signalReceived = true
				loadingStatusReason = "critical_ready_signal"
				serverReady = true
				updateProgress("server", 1)
			end)
		end
		if worldReadyEvt then
			worldConn = worldReadyEvt.OnClientEvent:Connect(function()
				if not serverReady then
					signalReceived = true
					loadingStatusReason = "world_ready_signal"
					serverReady = true
					updateProgress("server", 1)
				end
			end)
		end

		-- Wait for critical signal first
		local started = tick()
		while not signalReceived and (tick() - started) < maxCriticalWait do
			-- Gradually increase progress while waiting
			local elapsed = tick() - started
			updateProgress("server", math.min(0.8, elapsed / maxCriticalWait))
			task.wait(0.1)
		end

		-- If critical didn't fire, wait for world ready
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
			updateProgress("server", 1)
		end
		logMetric("join_to_server_ready")
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- GATE CONDITION 3: Base plot + creature orbs visible on client
-- After the server signals ready, verify the base is actually replicated.
-- ═══════════════════════════════════════════════════════════════════════════════
local baseVisualReady = quickSpawnDebug

--- Find the player's assigned base plot on the client.
--- @return Model|nil — the plot model, or nil if not found yet
local function findMyPlot()
	local plotsFolder = workspace:FindFirstChild("BasePlots") or workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

--- World position of PlotCenter (BasePart or Model with parts), same idea as server teleport target.
local function getPlotCenterWorldPosition(plot)
	local raw = plot:FindFirstChild("PlotCenter", true)
	if not raw then return nil end
	if raw:IsA("BasePart") then
		return raw.Position
	end
	if raw:IsA("Model") then
		if raw.PrimaryPart then
			return raw.PrimaryPart.Position
		end
		local bp = raw:FindFirstChildWhichIsA("BasePart", true)
		return bp and bp.Position or nil
	end
	return nil
end

--- Count base creature orbs on a plot (tagged BaseIncomeCreature / BaseDefenseCreature / BaseBattleCreature)
--- @param plot Model
--- @return number
local function countBaseCreatures(plot)
	local count = 0
	for _, desc in ipairs(plot:GetDescendants()) do
		if CollectionService:HasTag(desc, "BaseIncomeCreature")
			or CollectionService:HasTag(desc, "BaseDefenseCreature")
			or CollectionService:HasTag(desc, "BaseBattleCreature") then
			count = count + 1
		end
	end
	return count
end

if not quickSpawnDebug then
	task.spawn(function()
		-- Wait for server to be ready first (base was placed server-side)
		while not serverReady do task.wait(0.1) end

		statusLbl.Text = "Preparing your base..."

		-- Poll for the plot to appear on the client
		local plot = nil
		local plotWaitStart = tick()
		local PLOT_WAIT_MAX = 10 -- seconds
		while not plot and (tick() - plotWaitStart) < PLOT_WAIT_MAX do
			plot = findMyPlot()
			if not plot then task.wait(0.2) end
		end

		if plot then
			updateProgress("baseVisual", 0.5)
			statusLbl.Text = "Spawning your Siegelings..."

			-- Wait briefly for creature orbs to replicate (they spawn server-side
			-- during PlaceCreatures, but replication to the client takes a moment)
			local creatureWaitStart = tick()
			local CREATURE_WAIT_MAX = 6 -- seconds (base creatures are local, should be fast)
			local lastCount = 0
			local stableFrames = 0
			while (tick() - creatureWaitStart) < CREATURE_WAIT_MAX do
				local count = countBaseCreatures(plot)
				if count > 0 and count == lastCount then
					stableFrames = stableFrames + 1
					-- Stable for 3 consecutive checks = done replicating
					if stableFrames >= 3 then break end
				else
					stableFrames = 0
				end
				lastCount = count
				local elapsed = tick() - creatureWaitStart
				updateProgress("baseVisual", 0.5 + 0.5 * math.min(1, elapsed / CREATURE_WAIT_MAX))
				task.wait(0.3)
			end
			print("[LoadingGate] Base creatures visible: " .. countBaseCreatures(plot) .. " on " .. plot.Name)

			-- Server teleports to plot after assign; replication can lag behind plot/creatures.
			-- Keep the gate up until the character is actually near PlotCenter.
			local centerPos = getPlotCenterWorldPosition(plot)
			if centerPos then
				statusLbl.Text = "Arriving at your base..."
				local ARRIVE_WAIT_MAX = 20
				local AT_BASE_RADIUS = 100 -- studs; teleport is ~5 above PlotCenter
				local arriveStart = tick()
				while (tick() - arriveStart) < ARRIVE_WAIT_MAX do
					local char = player.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if root and (root.Position - centerPos).Magnitude <= AT_BASE_RADIUS then
						break
					end
					task.wait(0.12)
				end
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - centerPos).Magnitude > AT_BASE_RADIUS then
					print("[LoadingGate] Character not at plot after " .. ARRIVE_WAIT_MAX .. "s — releasing anyway (deadline may apply)")
				end
			end
		else
			print("[LoadingGate] Plot not found after " .. PLOT_WAIT_MAX .. "s — releasing anyway")
		end

		baseVisualReady = true
		updateProgress("baseVisual", 1)
		logMetric("join_to_base_visual")
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- GATE CONDITION 4: Preload nearby assets (ContentProvider)
-- After the base is visually present, preload all meshes/textures near the
-- player so nothing pops in when the screen fades away.
-- ═══════════════════════════════════════════════════════════════════════════════
local preloadReady = quickSpawnDebug

if not quickSpawnDebug then
	task.spawn(function()
		-- Wait for base visual to be ready
		while not baseVisualReady do task.wait(0.1) end

		statusLbl.Text = "Loading world visuals..."

		-- Gather nearby instances to preload
		local toPreload = {}
		local PRELOAD_RADIUS = 120 -- studs around the player's base

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local center = root and root.Position or Vector3.new(0, 50, 0)

		-- Also try plot center as fallback reference point
		local plot = findMyPlot()
		if plot then
			local plotCenter = plot:FindFirstChild("PlotCenter")
			if plotCenter and plotCenter:IsA("BasePart") then
				center = plotCenter.Position
			end
		end

		-- Collect meshes, textures, decals, and sounds near the player
		for _, desc in ipairs(workspace:GetDescendants()) do
			if #toPreload >= 200 then break end -- cap to avoid long preload
			if desc:IsA("BasePart") or desc:IsA("MeshPart") or desc:IsA("Decal")
				or desc:IsA("Texture") or desc:IsA("SpecialMesh") then
				local pos = nil
				if desc:IsA("BasePart") then
					pos = desc.Position
				elseif desc.Parent and desc.Parent:IsA("BasePart") then
					pos = desc.Parent.Position
				end
				if pos and (pos - center).Magnitude <= PRELOAD_RADIUS then
					table.insert(toPreload, desc)
				end
			end
		end

		-- Also preload all base creature models on the plot
		if plot then
			for _, desc in ipairs(plot:GetDescendants()) do
				if desc:IsA("MeshPart") or desc:IsA("SpecialMesh") or desc:IsA("Decal") or desc:IsA("Texture") then
					table.insert(toPreload, desc)
				end
			end
		end

		if #toPreload > 0 then
			local loaded = 0
			local total = #toPreload
			-- Preload in batches to allow progress updates
			local BATCH_SIZE = 30
			for i = 1, total, BATCH_SIZE do
				local batch = {}
				for j = i, math.min(i + BATCH_SIZE - 1, total) do
					table.insert(batch, toPreload[j])
				end
				pcall(function()
					ContentProvider:PreloadAsync(batch)
				end)
				loaded = loaded + #batch
				updateProgress("preload", loaded / total)
			end
			print("[LoadingGate] Preloaded " .. total .. " assets within " .. PRELOAD_RADIUS .. " studs")
		else
			print("[LoadingGate] No nearby assets to preload")
		end

		preloadReady = true
		updateProgress("preload", 1)
		logMetric("join_to_preload_done")
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Main gate loop: wait for ALL conditions, then release
-- ═══════════════════════════════════════════════════════════════════════════════
local loadingDone = false

-- Hard deadline: never hold the gate longer than this (prevents infinite hang)
-- Extra headroom for plot/creature polling + "wait until at base" after server teleport replicates
local MAX_GATE_SECONDS = quickSpawnDebug and 2 or (GameConfig.LoadingCriticalMaxWait or 18) + 12 + 25
local releaseDeadline = tick() + MAX_GATE_SECONDS

while tick() < releaseDeadline do
	if characterReady and serverReady and baseVisualReady and preloadReady then
		break
	end
	task.wait(0.05)
end

loadingDone = true

-- Log why we released
if not characterReady then
	loadingStatusReason = "character_timeout_fallback"
end
-- Character wait uses a timeout then marks "ready" anyway; gate can release with no Character.
do
	local charAtRelease = player.Character
	local rootAtRelease = charAtRelease and charAtRelease:FindFirstChild("HumanoidRootPart")
	if not rootAtRelease then
		warn("[LoadingGate] Released without a character/HumanoidRootPart. "
			.. "The 30s character wait may have timed out, or spawn failed (check server scripts / Studio team test). "
			.. "You may see an empty sky until CharacterAdded fires.")
	end
end
logMetric("join_to_control_release")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Release: show "ready" text, unfreeze, fade out the loading screen
-- ═══════════════════════════════════════════════════════════════════════════════

-- Fill progress bar to 100%
TweenService:Create(progressFill, TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 1, 0) }):Play()

statusLbl.Text = "Track 'Em Down!"
quoteLbl.Text = ""
statusLbl.TextColor3 = WIND
progressFill.BackgroundColor3 = WIND
task.wait(quickSpawnDebug and 0.05 or 0.4)

-- Unfreeze player
setFreeze(false)

-- Fade out loading screen
local FADE_TIME = 0.6
TweenService:Create(bg, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 }):Play()
TweenService:Create(title, TweenInfo.new(FADE_TIME * 0.6), { TextTransparency = 1 }):Play()
TweenService:Create(statusLbl, TweenInfo.new(FADE_TIME * 0.6), { TextTransparency = 1 }):Play()
TweenService:Create(quoteLbl, TweenInfo.new(FADE_TIME * 0.6), { TextTransparency = 1 }):Play()
TweenService:Create(progressBarBg, TweenInfo.new(FADE_TIME * 0.6), { BackgroundTransparency = 1 }):Play()
TweenService:Create(progressFill, TweenInfo.new(FADE_TIME * 0.6), { BackgroundTransparency = 1 }):Play()

-- Clear the loading gate attribute so other systems know we're done
task.delay(FADE_TIME, function()
	player:SetAttribute("LoadingGateActive", false)
	if sg and sg.Parent then
		sg:Destroy()
	end
end)

-- NOTE: We do NOT stop loadingMusic here. GameplayMusic.client.lua will detect
-- the already-playing track and take ownership of it seamlessly (it uses the
-- same Sound object in SoundService). This avoids any audio gap.

print("[LoadingGate] Released — reason: " .. tostring(loadingStatusReason)
	.. ", elapsed: " .. string.format("%.1fs", os.clock() - startupClock))
