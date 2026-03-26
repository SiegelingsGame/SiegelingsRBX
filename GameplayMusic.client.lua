-- ═══════════════════════════════════════════════════════════════════════════════
-- Last updated: 2026-03-21
-- GameplayMusic.client.lua
-- ═══════════════════════════════════════════════════════════════════════════════
-- Multi-track biome music system with battle theme override.
--
-- All Sound objects live in SoundService (placed in Roblox Studio).
-- Naming convention: "Sieglings_[TrackName]"
--
-- Track routing (priority order):
--   1. COMBAT → Sieglings_BattleTheme  (arena, gym, PvP, badlands)
--   2. BIOME  → mapped from current skybox name:
--        FireSky     → Sieglings_FireBiome
--        IceSky      → Sieglings_SnowBiome
--        WindSky     → Sieglings_WindBiome
--        EarthSky    → Sieglings_EarthBiome
--        ForestSky   → Sieglings_ForestBiome   (if it exists, else Main Theme)
--        DesertSky   → Sieglings_DesertBiome   (if it exists, else Main Theme)
--        ElectricSky → Sieglings_ElectricBiome (if it exists, else Main Theme)
--        WaterSky    → Sieglings_WaterBiome    (if it exists, else Main Theme)
--        ArenaSky    → Sieglings_ Main Theme   (hub / default)
--   3. FALLBACK → Sieglings_ Main Theme
--
-- BiomeSkyboxClient sets player attribute "CurrentSkyName" whenever the
-- skybox changes. This script listens for that attribute.
--
-- Combat / battle music (instance-based — only participants hear it):
--   • player attribute "InBattleMusic"            == true  (set by server on arena/gym participants)
--   • player attribute "InBadlands"               == true
--   • PvPBattleStart / PvPBattleEnd RemoteEvents
--   • within ArenaBattleMusicRadius studs of any workspace.Arena BlueTeam/RedTeam BattlePoint
--
-- Crossfade: smooth transition between tracks. Outgoing fades to silence,
-- incoming fades to target volume. Tracks keep playing silently so resuming
-- continues from where it left off (seamless thematic continuity).
--
-- Adding new biome tracks: just place a Sound named "Sieglings_[BiomeName]"
-- in SoundService and add the sky→track mapping to SKY_TO_TRACK below.
-- ═══════════════════════════════════════════════════════════════════════════════

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Configuration
-- ═══════════════════════════════════════════════════════════════════════════════sd
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local config = GameConfig.GameplayMusic or {}

-- Master kill-switchf
if config.Enabled == false then
	return
end

-- Volume & timing
local TARGET_VOLUME   = math.max(0, tonumber(config.Volume) or 0.80)
local FADE_IN_TIME    = math.max(0, tonumber(config.FadeInTime) or 2.5)
local CROSSFADE_TIME  = math.max(0.2, tonumber(config.CrossfadeTime) or 1.5)
local BLOCK_UNKNOWN_BGM = config.BlockUnknownBackgroundMusic ~= false

-- Sound object names in SoundService
local MAIN_THEME_NAME   = config.MainThemeName   or "Sieglings_MainTheme"
local BATTLE_THEME_NAME = config.BattleThemeName  or "Sieglings_BattleTheme"

-- ═══════════════════════════════════════════════════════════════════════════════
-- Sky → Track mapping
-- Maps skybox names (from BiomeSkyboxClient) to Sound object names in SoundService.
-- If a biome track doesn't exist in SoundService, the Main Theme is used as fallback.
-- To add a new biome track: place the Sound in SoundService and add a line here.
-- ═══════════════════════════════════════════════════════════════════════════════
local SKY_TO_TRACK = config.SkyToTrack or {
	FireSky     = "Sieglings_FireBiome",
	IceSky      = "Sieglings_SnowBiome",
	WindSky     = "Sieglings_WindBiome",
	EarthSky    = "Sieglings_EarthBiome",
	DesertSky   = "Sieglings_DesertBiome",
	ElectricSky = "Sieglings_ElectricBiome",
	WaterSky    = "Sieglings_OceanBiome",
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- Cave biome: positional override (not skybox-based)
-- The cave is underground — no skybox change happens there. Instead we detect
-- the player standing above the CaveBaseplate within a vertical range.
-- ═══════════════════════════════════════════════════════════════════════════════
local caveConfig = config.CaveBiome or {}
local CAVE_TRACK_NAME     = caveConfig.TrackName      or "Sieglings_CaveBiome"
local CAVE_BASEPLATE_PATH = { caveConfig.BaseplateParent or "Terrain", caveConfig.BaseplateName or "CaveBaseplate" }
local CAVE_VERTICAL_RANGE = tonumber(caveConfig.VerticalRange) or 700
local CAVE_CHECK_INTERVAL = 0.2  -- seconds between position checks

-- Resolve the CaveBaseplate part at startup
local caveBaseplate = nil
do
	local current = workspace
	for _, name in ipairs(CAVE_BASEPLATE_PATH) do
		current = current:FindFirstChild(name)
		if not current then break end
	end
	if current and current:IsA("BasePart") then
		caveBaseplate = current
	else
		print("[GameplayMusic] CaveBaseplate not found — cave music disabled")
	end
end

-- Cave state (updated by position polling loop)
local inCaveBiome = false

-- Main Siegelord arena: battle theme when near team BattlePoints (see GameConfig.GameplayMusic.ArenaBattleMusicRadius).
local ARENA_BATTLE_MUSIC_RADIUS = math.max(5, tonumber(config.ArenaBattleMusicRadius) or 80)
local mainArenaBattlePointParts = {} -- BasePart[]
local mainArenaCenterPart = nil
local nearMainArenaBattleMusicZone = false

local function findMainArenaModel()
	local direct = workspace:FindFirstChild("Arena")
	if direct and (direct:FindFirstChild("BlueTeam") or direct:FindFirstChild("RedTeam")) then
		return direct
	end
	-- Streaming / alternate layout: any Arena folder/model with both teams
	for _, inst in workspace:GetChildren() do
		if inst.Name == "Arena" and (inst:IsA("Folder") or inst:IsA("Model")) then
			if inst:FindFirstChild("BlueTeam") and inst:FindFirstChild("RedTeam") then
				return inst
			end
		end
	end
	return nil
end

local function refreshMainArenaBattlePointParts()
	table.clear(mainArenaBattlePointParts)
	mainArenaCenterPart = nil
	local arena = findMainArenaModel()
	if not arena then return end
	local ac = arena:FindFirstChild("ArenaCenter")
	if ac and ac:IsA("BasePart") then
		mainArenaCenterPart = ac
	end
	for _, teamName in ipairs({ "BlueTeam", "RedTeam" }) do
		local team = arena:FindFirstChild(teamName)
		if team then
			for _, d in ipairs(team:GetDescendants()) do
				if d:IsA("BasePart") and d.Name:match("^BattlePoint%d+$") then
					table.insert(mainArenaBattlePointParts, d)
				end
			end
		end
	end
end

--- True if player is within `radius` studs of any BattlePoint or optional ArenaCenter.
local function isNearArenaBattleAnchors(rootPos, radius)
	local r2 = radius * radius
	for _, pt in ipairs(mainArenaBattlePointParts) do
		if pt.Parent then
			local d = rootPos - pt.Position
			if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
				return true
			end
		end
	end
	if mainArenaCenterPart and mainArenaCenterPart.Parent then
		local d = rootPos - mainArenaCenterPart.Position
		if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
			return true
		end
	end
	return false
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Discover all Sound objects in SoundService
-- ═══════════════════════════════════════════════════════════════════════════════

--- @param name string  — Sound object name in SoundService (any depth; Studio often nests Sounds in folders)
--- @return Sound|nil
local function findSound(name)
	if not name or name == "" then return nil end
	local snd = SoundService:FindFirstChild(name, true)
	if snd and snd:IsA("Sound") then
		return snd
	end
	return nil
end

-- Build the set of ALL known track names (main + battle + all biome + cave tracks)
local knownTrackNames = {
	[MAIN_THEME_NAME]   = true,
	[BATTLE_THEME_NAME] = true,
	[CAVE_TRACK_NAME]   = true,
}
for _, trackName in pairs(SKY_TO_TRACK) do
	knownTrackNames[trackName] = true
end

-- Clean up leftover sounds from the old single-track system (top-level only; nested assets stay)
do
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("Sound") and not knownTrackNames[child.Name] then
			if child.IsPlaying then child:Stop() end
			child:Destroy()
			print("[GameplayMusic] Removed leftover Sound: '" .. child.Name .. "'")
		end
	end
end

-- Resolve references to all tracks
local mainTheme   = findSound(MAIN_THEME_NAME)
local battleTheme = findSound(BATTLE_THEME_NAME)

-- Biome tracks: sky name → Sound reference (nil if not yet in SoundService)
local biomeTracks = {}  -- skyName → Sound|nil
for skyName, trackName in pairs(SKY_TO_TRACK) do
	biomeTracks[skyName] = findSound(trackName)
end

-- Cave track (positional, not skybox-based)
local caveTrack = findSound(CAVE_TRACK_NAME)

-- Log what we found
local foundCount = 0
local missingList = {}
if mainTheme then foundCount += 1 else table.insert(missingList, MAIN_THEME_NAME) end
if battleTheme then foundCount += 1 else table.insert(missingList, BATTLE_THEME_NAME) end
for skyName, trackName in pairs(SKY_TO_TRACK) do
	if trackName ~= MAIN_THEME_NAME then -- don't double-count
		if findSound(trackName) then
			foundCount += 1
		else
			table.insert(missingList, trackName)
		end
	end
end
if caveTrack then foundCount += 1 else table.insert(missingList, CAVE_TRACK_NAME) end

if foundCount == 0 then
	warn("[GameplayMusic] No music tracks found in SoundService — music system disabled.")
	return
end

if #missingList > 0 then
	print("[GameplayMusic] Missing tracks (will use Main Theme as fallback): " .. table.concat(missingList, ", "))
end
if not battleTheme then
	warn("[GameplayMusic] Battle theme not found in SoundService as '" .. BATTLE_THEME_NAME
		.. "' (search is recursive). Combat / arena music will use Main Theme until you add it.")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Sound Group (shared volume control)
-- ═══════════════════════════════════════════════════════════════════════════════
local function getOrCreateSoundGroup(name)
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local sg = Instance.new("SoundGroup")
	sg.Name = name
	sg.Parent = SoundService
	return sg
end

local musicGroup = getOrCreateSoundGroup(config.SoundGroupName or "Music")

-- Set of all known Sound refs (for the unknown-BGM blocker)
local knownSoundRefs = {}

-- Configure a track: looped, start silent, assign to music group
local function prepareTrack(snd)
	if not snd then return end
	snd.Looped = true
	snd.Volume = 0
	snd.SoundGroup = musicGroup
	snd.PlaybackSpeed = tonumber(config.PlaybackSpeed) or 1
	knownSoundRefs[snd] = true
end

-- Prepare all discovered tracks
prepareTrack(mainTheme)
prepareTrack(battleTheme)
prepareTrack(caveTrack)
for _, snd in pairs(biomeTracks) do
	prepareTrack(snd)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Unknown background music blocker (prevents stray sounds from playing)
-- ═══════════════════════════════════════════════════════════════════════════════
local function shouldStopAsUnknownBackground(soundObj)
	if not BLOCK_UNKNOWN_BGM then return false end
	if not soundObj or not soundObj:IsA("Sound") then return false end
	if knownSoundRefs[soundObj] then return false end

	local nameLower = string.lower(soundObj.Name or "")
	local groupedAsMusic = soundObj.SoundGroup == musicGroup
	local nameLooksLikeMusic =
		nameLower:find("music", 1, true)
		or nameLower:find("theme", 1, true)
		or nameLower:find("song", 1, true)
		or nameLower:find("bgm", 1, true)
	if groupedAsMusic or (soundObj.Looped and nameLooksLikeMusic) then
		return true
	end
	return false
end

local function stopUnknownBackground(soundObj)
	if not shouldStopAsUnknownBackground(soundObj) then return end
	if soundObj.IsPlaying then soundObj:Stop() end
	soundObj.Volume = 0
end

local function stopUnknownBackgroundNow()
	for _, desc in ipairs(game:GetDescendants()) do
		if desc:IsA("Sound") then
			stopUnknownBackground(desc)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Startup gates (wait for loading screens to clear before starting music)
-- ═══════════════════════════════════════════════════════════════════════════════
local function screensAreBlocking()
	local waitForScreens = config.WaitForScreens
	if type(waitForScreens) ~= "table" then return false end
	for _, screenName in ipairs(waitForScreens) do
		local sg2 = playerGui:FindFirstChild(screenName)
		if sg2 and (not sg2:IsA("ScreenGui") or sg2.Enabled ~= false) then
			return true
		end
	end
	return false
end

local function waitForGameplayWindow()
	local initialDelay = tonumber(config.StartDelay) or 0.4
	if initialDelay > 0 then task.wait(initialDelay) end

	local deadline = os.clock() + math.max(5, tonumber(config.MaxScreenWait) or 45)
	local settleWindow = math.max(0.25, tonumber(config.ScreenSettleTime) or 0.75)
	local clearSince = nil

	while os.clock() < deadline do
		if screensAreBlocking() then
			clearSince = nil
		else
			clearSince = clearSince or os.clock()
			if os.clock() - clearSince >= settleWindow then return end
		end
		task.wait(0.1)
	end
end

--- Wait for the loading gate to finish before taking over music control.
--- LoadingGate.client.lua starts the main theme during loading and sets
--- player attribute "LoadingGateActive" while the gate is up. We wait for
--- that attribute to become false (or absent) so there's no audio conflict.
--- Falls back to the old LoadingCriticalReady signal if the attribute isn't set.
local function waitForStartupReady()
	-- FIX: Coordinate with LoadingGate. The gate starts music and sets
	-- LoadingGateActive=true. We wait for the gate to drop before taking over.
	if player:GetAttribute("LoadingGateActive") == true then
		-- Gate is active — wait for it to finish
		local gateStart = tick()
		local MAX_GATE_WAIT = 45 -- absolute max (should never be hit; gate has its own deadline)
		while player:GetAttribute("LoadingGateActive") == true and (tick() - gateStart) < MAX_GATE_WAIT do
			task.wait(0.2)
		end
		return
	end

	-- Fallback: if LoadingGateActive was never set (old flow or race), use the event
	local events = ReplicatedStorage:FindFirstChild("Events")
		or ReplicatedStorage:WaitForChild("Events", 15)
	if not events then return end

	local criticalReady = events:FindFirstChild("LoadingCriticalReady")
	local worldReady    = events:FindFirstChild("LoadingReady")
	if criticalReady then
		criticalReady.OnClientEvent:Wait()
	elseif worldReady then
		worldReady.OnClientEvent:Wait()
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Combat state detection
-- ═══════════════════════════════════════════════════════════════════════════════
local inPvP = false

--- @return boolean — true if any combat scenario is active for THIS player
local function isInCombat()
	-- Instance-based: server sets InBattleMusic on only the participating players
	if player:GetAttribute("InBattleMusic") == true then return true end
	if player:GetAttribute("InBadlands") == true then return true end
	if inPvP then return true end
	return false
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Crossfade engine
-- ═══════════════════════════════════════════════════════════════════════════════
local activeTrack = nil
local activeTween = nil
local inactiveTween = nil

--- Crossfade from the current track to `targetTrack`.
--- If targetTrack is already active, does nothing.
--- @param targetTrack Sound
local function crossfadeTo(targetTrack)
	if not targetTrack then return end
	if targetTrack == activeTrack then return end

	local outgoing = activeTrack
	activeTrack = targetTrack

	-- Cancel any in-progress tweens
	if activeTween then activeTween:Cancel() end
	if inactiveTween then inactiveTween:Cancel() end

	-- Start the target playing (if not already) so the fade-in has audio
	if not targetTrack.IsPlaying then
		if not targetTrack.IsLoaded then
			pcall(function() ContentProvider:PreloadAsync({ targetTrack }) end)
		end
		targetTrack.Volume = 0
		targetTrack:Play()
	end

	-- Fade IN the target track
	activeTween = TweenService:Create(
		targetTrack,
		TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Volume = TARGET_VOLUME }
	)
	activeTween:Play()

	-- Fade OUT the outgoing track (if any)
	if outgoing and outgoing ~= targetTrack then
		inactiveTween = TweenService:Create(
			outgoing,
			TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Volume = 0 }
		)
		inactiveTween:Play()
		-- Don't :Stop() — let it keep TimePosition for seamless resume later
	end

	-- Silence ALL other managed tracks that aren't the target.
	-- Prevents leftover volume from rapid biome transitions or cancelled tweens
	-- (e.g. biome music still audible when battle music starts).
	local allTracks = { mainTheme, battleTheme, caveTrack }
	for _, snd in pairs(biomeTracks) do
		table.insert(allTracks, snd)
	end
	for _, snd in ipairs(allTracks) do
		if snd and snd ~= targetTrack and snd ~= outgoing and snd.Volume > 0 then
			TweenService:Create(
				snd,
				TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
				{ Volume = 0 }
			):Play()
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Track selection: combat overrides biome, biome overrides default
-- ═══════════════════════════════════════════════════════════════════════════════

--- Determine the correct track to play right now.
--- Priority: Combat > Cave (positional) > Biome (skybox) > Main Theme
--- @return Sound — the Sound object to crossfade to
local function getDesiredTrack()
	-- Priority 1: Combat / main-arena battle-point radius → battle theme
	if isInCombat() or nearMainArenaBattleMusicZone then
		return battleTheme or mainTheme
	end

	-- Priority 2: Cave biome (positional override — underground, no skybox change)
	if inCaveBiome and caveTrack then
		return caveTrack
	end

	-- Priority 3: Biome-specific track based on current skybox
	local skyName = player:GetAttribute("CurrentSkyName")
	if skyName and biomeTracks[skyName] then
		return biomeTracks[skyName]
	end

	-- Priority 4: Fallback → main theme
	return mainTheme or battleTheme
end

--- Evaluate what should be playing and crossfade if needed.
local function evaluateMusic()
	local target = getDesiredTrack()
	if target then
		crossfadeTo(target)
	end
end

-- Hard reset: stop all managed tracks and restart main theme from the beginning.
local function resetAllMusicToMainTheme()
	if activeTween then activeTween:Cancel() end
	if inactiveTween then inactiveTween:Cancel() end

	-- Clear transient combat/cave / arena-proximity state so death always returns to default music.
	inPvP = false
	inCaveBiome = false
	nearMainArenaBattleMusicZone = false

	local uniqueTracks = {}
	local allTracks = { mainTheme, battleTheme, caveTrack }
	for _, snd in pairs(biomeTracks) do
		table.insert(allTracks, snd)
	end

	for _, snd in ipairs(allTracks) do
		if snd and not uniqueTracks[snd] then
			uniqueTracks[snd] = true
			if snd.IsPlaying then snd:Stop() end
			snd.Volume = 0
			snd.TimePosition = 0
		end
	end

	local target = mainTheme or battleTheme
	activeTrack = target
	if target then
		target.Volume = TARGET_VOLUME
		target:Play()
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Boot sequence
-- ═══════════════════════════════════════════════════════════════════════════════
task.spawn(function()
	waitForStartupReady()
	waitForGameplayWindow()
	stopUnknownBackgroundNow()

	-- Block any future unknown background sounds
	if BLOCK_UNKNOWN_BGM then
		game.DescendantAdded:Connect(function(desc)
			if desc:IsA("Sound") then
				stopUnknownBackground(desc)
				desc:GetPropertyChangedSignal("IsPlaying"):Connect(function()
					stopUnknownBackground(desc)
				end)
			end
		end)
	end

	-- Preload all tracks
	local toPreload = {}
	if mainTheme   and not mainTheme.IsLoaded   then table.insert(toPreload, mainTheme) end
	if battleTheme and not battleTheme.IsLoaded then table.insert(toPreload, battleTheme) end
	if caveTrack   and not caveTrack.IsLoaded  then table.insert(toPreload, caveTrack) end
	for _, snd in pairs(biomeTracks) do
		if snd and not snd.IsLoaded then table.insert(toPreload, snd) end
	end
	if #toPreload > 0 then
		pcall(function() ContentProvider:PreloadAsync(toPreload) end)
	end

	-- Start the correct track.
	-- FIX: LoadingGate may have already started the main theme during loading.
	-- If the desired track is already playing (same Sound object), adopt it
	-- instead of restarting from Volume 0. This prevents an audio gap.
	local startTrack = getDesiredTrack()
	if startTrack then
		if startTrack.IsPlaying and startTrack.Volume > 0.1 then
			-- LoadingGate already started this track — adopt it seamlessly
			activeTrack = startTrack
			print("[GameplayMusic] Adopted already-playing track: " .. startTrack.Name)
		else
			startTrack.Volume = 0
			startTrack:Play()
			activeTrack = startTrack

			if FADE_IN_TIME > 0 then
				TweenService:Create(
					startTrack,
					TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{ Volume = TARGET_VOLUME }
				):Play()
			else
				startTrack.Volume = TARGET_VOLUME
			end
		end
	end

	-- ═══════════════════════════════════════════════════════════════════════════
	-- Bind state change listeners (all trigger evaluateMusic)
	-- ═══════════════════════════════════════════════════════════════════════════

	-- Combat triggers (instance-based: only this player's attribute matters)
	player:GetAttributeChangedSignal("InBattleMusic"):Connect(evaluateMusic)
	player:GetAttributeChangedSignal("InBadlands"):Connect(evaluateMusic)

	-- Biome trigger (skybox change published by BiomeSkyboxClient)
	player:GetAttributeChangedSignal("CurrentSkyName"):Connect(evaluateMusic)

	-- Player death: hard reset all tracks back to main theme.
	local function attachDeathReset(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		humanoid.Died:Connect(resetAllMusicToMainTheme)
	end
	if player.Character then
		attachDeathReset(player.Character)
	end
	player.CharacterAdded:Connect(attachDeathReset)

	-- PvP battles (RemoteEvents)
	local events = ReplicatedStorage:FindFirstChild("Events")
	if events then
		local pvpStart = events:FindFirstChild("PvPBattleStart")
		local pvpEnd   = events:FindFirstChild("PvPBattleEnd")

		if pvpStart then
			pvpStart.OnClientEvent:Connect(function()
				inPvP = true
				evaluateMusic()
			end)
		end
		if pvpEnd then
			pvpEnd.OnClientEvent:Connect(function()
				inPvP = false
				evaluateMusic()
			end)
		end
	end

	-- ═══════════════════════════════════════════════════════════════════════════
	-- Cave biome position polling
	-- The cave is underground (no skybox change). We poll the player's position
	-- to detect when they're above the CaveBaseplate within the vertical range.
	-- ═══════════════════════════════════════════════════════════════════════════
	if caveBaseplate and caveTrack then
		task.spawn(function()
			while true do
				task.wait(CAVE_CHECK_INTERVAL)
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and caveBaseplate.Parent then
					local pos = root.Position
					local bp = caveBaseplate
					-- Check XZ bounds (within the baseplate's footprint)
					local bpPos = bp.Position
					local bpSize = bp.Size
					local halfX = bpSize.X / 2
					local halfZ = bpSize.Z / 2
					local inXZ = (pos.X >= bpPos.X - halfX and pos.X <= bpPos.X + halfX)
						and (pos.Z >= bpPos.Z - halfZ and pos.Z <= bpPos.Z + halfZ)
					-- Check Y: above baseplate top surface, within vertical range
					local bpTop = bpPos.Y + bpSize.Y / 2
					local inY = pos.Y >= bpTop and pos.Y <= bpTop + CAVE_VERTICAL_RANGE

					local wasInCave = inCaveBiome
					inCaveBiome = inXZ and inY
					if inCaveBiome ~= wasInCave then
						evaluateMusic()
					end
				else
					if inCaveBiome then
						inCaveBiome = false
						evaluateMusic()
					end
				end
			end
		end)
	end

	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Arena" then
			refreshMainArenaBattlePointParts()
		end
	end)

	-- Main arena: battle music near BlueTeam/RedTeam BattlePoints (streaming-safe refresh)
	task.spawn(function()
		local arenaRescanTicks = 0
		while true do
			task.wait(CAVE_CHECK_INTERVAL)
			arenaRescanTicks += 1
			if arenaRescanTicks >= 25 or #mainArenaBattlePointParts == 0 then
				arenaRescanTicks = 0
				refreshMainArenaBattlePointParts()
			end

			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local near = false
			if root and (mainArenaCenterPart or #mainArenaBattlePointParts > 0) then
				near = isNearArenaBattleAnchors(root.Position, ARENA_BATTLE_MUSIC_RADIUS)
			end

			if near ~= nearMainArenaBattleMusicZone then
				nearMainArenaBattleMusicZone = near
				evaluateMusic()
			end
		end
	end)

	-- Log summary
	local trackList = {}
	if mainTheme then table.insert(trackList, "Main") end
	if battleTheme then table.insert(trackList, "Battle") end
	if caveTrack then table.insert(trackList, "Cave") end
	for skyName, snd in pairs(biomeTracks) do
		if snd then table.insert(trackList, skyName) end
	end
	print("[GameplayMusic] Initialized — " .. #trackList .. " tracks: " .. table.concat(trackList, ", ")
		.. " | Volume: " .. TARGET_VOLUME .. " | Crossfade: " .. CROSSFADE_TIME .. "s"
		.. (caveBaseplate and " | Cave: enabled" or " | Cave: no baseplate"))
end)
