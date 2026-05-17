--[[
	GameConfigData.lua
	ReplicatedStorage/Modules/GameConfigData
	Actual config data. Required lazily by GameConfig to avoid recursive require.
]]
-- Last updated: 2026-04-24 22:26
-- lol

local GameConfig = {}

-- Day / Night Cycle (Lighting.ClockTime)
GameConfig.DayNightCycleEnabled = true   -- true = enable cycle; false = use default Roblox lighting
GameConfig.DayNightCycleSeconds = 500    -- real seconds per full day (24 in-game hours); changeable
GameConfig.DayNightCycleStartHour = 5.5  -- initial server start time (5.5 ~= crack of dawn / sunrise)
GameConfig.NightStartHour = 22          -- ClockTime >= this = night (6 PM)
GameConfig.NightEndHour = 5              -- ClockTime < this = night (until 6 AM)
GameConfig.NightDarknessReductionPercent = 0.10 -- lighten night by 10% (applied as extra Lighting.Brightness)
GameConfig.NightDarknessTransitionHours = 0.75 -- smooth night brightness fade in/out (in-game hours)
-- Night spawn variants: Common/Uncommon → Silver chance; Rare+ → Gold chance (0–1)
GameConfig.NightSpawnSilverChance = 0.10  -- chance for Common/Uncommon at night
GameConfig.NightSpawnGoldChance = 0.05    -- chance for Rare+ at night
GameConfig.ShinySpawnChance = 0.02        -- chance any spawned world creature becomes shiny (Neon mesh material)
-- World creatures with evolutions: at night randomly evolve (base→evolved), at dawn devolve
GameConfig.NightWorldEvolutionChance   = 0.20  -- per creature per check (base form with evolvesTo)
GameConfig.NightWorldEvolutionInterval = 30     -- seconds .between evolution checks
GameConfig.NightSpawnBonus             = 0    -- keep world cap flat at MaxWorldCreatures (no night population spike)

-- Debug / Dev toggles (set true for testing)ff
GameConfig.SpawnOnlyCreaturesWithModels = true  -- true = only spawn creatures that have models in CreatureModels
GameConfig.DebugCoins1000 = false               -- true = new players start with 1000 coins
GameConfig.DebugFloor2Level2 = false            -- true = Floor 2 srequires player level 2 (instead of 5)
GameConfig.DebugDoubleSpeed = false             -- true = player WalkSpeed is 32 (2x default)
GameConfig.QuickSpawnDebugMode = false         -- true = bypass loading gate (skip Events/LoadingReady wait) for fast testing
GameConfig.CombinerRecyclerPromptAllPlots = true -- true = add E prompts to Combiner/Recycler on ALL plots (for testing; set false for release)
GameConfig.DebugBrokerGoldOnly = false             -- true = The Broker only asks for 100 gold coins instead of a creature sacrifice (for testing)
GameConfig.DebugBrokerCacty = false                -- true = The Broker always asks for a Lv1 Common Earth Cacty (for testing)
GameConfig.ZoneDoorsDisabled = true

-- Logging: false = quiet production (no duplicate startup warn/print); true = verbose diagnostics
GameConfig.DebugServerLogging = false
-- Client: false = do not warn on transient InvokeServer failures during loading/retries
GameConfig.DebugClientInvokeWarnings = false

-- Performance telemetry ([PerformanceMetrics.lua]): keep false in published games (extra Heartbeat + GetTagged cost when true).
GameConfig.PerfMetricsEnabled = false

-- Economy
GameConfig.StartingCoins       = 100
GameConfig.IncomeTickSeconds   = 10
-- Server: spread each player's income/defense-XP work across frames (0 = legacy: all players same frame)
GameConfig.IncomeTickStaggerSeconds = 0.018
GameConfig.MaxInventorySize    = 50
GameConfig.EggCost             = 50
GameConfig.MaxIncomeSlots      = 6   -- matches IncomePoints on plot.
GameConfig.MaxDefenseSlots     = 4   -- active defense slots per floor when premium points disabled; Init may set from plot count

-- Leveling (creature levels; max level depends on evolution stage)
GameConfig.MaxCreatureLevel    = 10   -- legacy/fallbackd
GameConfig.BaseMaxLevel        = 10   -- base form (no evolvesFrom)
GameConfig.EvolvedMaxLevel     = 25   -- after 1st evolution (has evolvesTo).
GameConfig.FinalMaxLevel       = 50   -- after 2nd evolution / final form (no evolvesTo)
GameConfig.BaseXPRequired      = 50   -- XP to reach level 2
GameConfig.XPScaling           = 1.5  -- each level needs 1.5x more XP
GameConfig.CaptureXP           = 10   -- XP gained for capturing a creature
GameConfig.BattleKillXP        = 25   -- XP per arena battle kill (per creature that gets a kill)
-- Arena win XP: entire winning team splits a pool; pool scales with win streak; smaller teams get more XP per creature
GameConfig.ArenaWinXPPoolBase      = 400   -- base XP pool for winning (total before split)
GameConfig.ArenaWinXPPoolPerStreak = 60    -- extra pool XP per current win streak (e.g. streak 5 = 400 + 300 = 700)
GameConfig.StatGainPerLevel    = 0.08 -- base % gain per level (then scaled by stat rank)f
-- Rank-based level scaling: highest base stat grows fastest, then next, down to lowest (rank 1 = biggest stat)
GameConfig.StatGainByRank      = { 1.5, 1.25, 1.0, 0.75 }  -- multipliers for rank 1..4 (1=fastest growth)
-- Rarity amplifies effective stats (higher rarity = stronger when leveled)
GameConfig.RarityStatMultipliers = { Common = 1.0, Uncommon = 1.05, Rare = 1.1, Epic = 1.15, Legendary = 1.25 }
-- Creature nicknames: first naming is free, later renames cost premium currency ("diamonds"/gems)
GameConfig.CreatureNicknameMaxLength = 20
GameConfig.CreatureRenameGemCost = 5

-- Player Leveling (separate from creature levels — gates features & floors)
GameConfig.PlayerMaxLevel         = 100
GameConfig.PlayerBaseXP           = 100    -- XP for player level 2
GameConfig.PlayerXPScaling        = 1.4    -- each level needs 1.4x more
GameConfig.PlayerXP_Capture       = 10     -- XP for capturing a creature
GameConfig.PlayerXP_ArenaWin      = 50     -- XP for winning arena battle
GameConfig.PlayerXP_ArenaKill     = 10     -- XP per arena kill
GameConfig.PlayerXP_IncomeTick    = 1      -- XP per income tick (if income > 0).
GameConfig.PlayerXP_RaidWin       = 30     -- XP for successful raid
GameConfig.PlayerXP_DungeonKill   = 20     -- XP for killing a dungeon creature
GameConfig.PlayerXP_BossKill      = 100    -- XP for killing a boss creature

-- Player rank titles (used for Roblox `leaderstats` + UI).
-- The first entry whose `minLevel <= playerLevel` and is the highest minLevel wins.
-- Edit these strings freely to match your game's lore.
GameConfig.PlayerRankTitles = {
	{ minLevel = 1,  title = "Siegling" },
	{ minLevel = 5,  title = "Siegesquire" },
	{ minLevel = 10, title = "Siegeknight" },
	{ minLevel = 25, title = "Siegemaster" },
	{ minLevel = 50, title = "Siegelord" },
}

-- Achievement tier rewards (chain tier I–V; single-step achievements use tier 1)
GameConfig.AchievementGemsByTier = { 5, 12, 24, 45, 80 }
GameConfig.AchievementXPByTier = { 35, 75, 140, 230, 350 }
-- Coin (gold) reward scaling by abchievement tier (I..V). Previously missing,
-- so achievements never paidc out gold even though notifications implied they should.
GameConfig.AchievementCoinsByTier = { 150, 400, 900, 1800, 3500 }

-- Base Floors
GameConfig.Floor2Cost             = 500   -- coins to buy Floor 2
GameConfig.Floor2LevelReq         = 5      -- player level required
GameConfig.Floor3Cost             = 5000  -- coins to buy Floor 3
GameConfig.Floor3LevelReq         = 10     -- player level required
GameConfig.Floor4Cost             = 25 -- coins to buy Floor 4 (Siegelord Arena)
GameConfig.Floor4LevelReq         = 10    -- player level required for Floor 4...

-- Evolution & Combine (monster duplication / variant tiers)
GameConfig.EvolutionMinLevel      = 10      -- level required for 1st evolution (base form).
GameConfig.EvolutionMinLevel2     = 25      -- level required for 2nd evolution (evolved form)
GameConfig.CombineCost            = 100      -- gold cost to combine 3 into next variant (0 = free)
GameConfig.RecyclerDuplicateCount = 3      -- min same-creature duplicates to trade for 1 egg (1 rarity tier higher)
-- Egg hatch time (minutes) by creature level inside the egg: level 1→20min, 2→30, 3→60, 4→120, 5→600, 6+→300
GameConfig.EggHatchMinutesByLevel = { 20, 30, 60, 120, 600, 300 }
-- Mystery egg inspect cost (diamonds/gems) for revealing what's inside before hatch
GameConfig.EggInspectGemCost = 5
GameConfig.VariantStatMultipliers = { Normal = 1.0, Silver = 1.15, Gold = 1.35, Legend = 1.6 }

-- Selling
GameConfig.SellEnabled            = true
GameConfig.SellRange              = 12     -- studs to walk-up sell from base creature

-- Base Interaction (walk-up creature management: pick up, move, swap, sell from base).
GameConfig.BaseInteractionRange   = 12     -- studs; ProximityPrompt activation distance
GameConfig.BasePlacementPromptRange = 18   -- studs; [E] Place Here / Swap on points while holding (slightly larger so standing on defense platform can reach adjacent empty points)
GameConfig.BaseInteractionEnabled = true   -- master toggle for pick-up/move/swap features
GameConfig.HoldInteractionDuration = 0.6   -- seconds to hold [E] for ProximityPrompt interactions (0 = press)

-- Per-floor slot limits (total across all owned floors)
GameConfig.IncomePointsPerFloor   = 6
GameConfig.DefensePointsPerFloor  = 4 -- active defense slots per owned floor (6 income + 4 defense = 10 siegelings/floor when premium off)

-- Optional extra DefensePoint parts in the world (same names on each floor tier). When disabled they stay in the map but are
-- invisible, non-interactive, and excluded from slot counts/placements. Toggle on to treat them as normal defense slots again.
GameConfig.DefensePremiumPointsEnabled = false
GameConfig.DefensePremiumPointNames = {
	"DefensePoint2",
	"DefensePoint6",
	"DefensePoint8",
	"DefensePoint11",
	"DefensePoint14",
	"DefensePoint17",
}

-- Loading screen: critical-first startup + background world warmup
GameConfig.LoadingCriticalMaxWait = 18 -- max seconds client waits for critical gameplay readiness
GameConfig.LoadingSpawnTarget  = 15   -- initial random spawns before SpawnPoint burst (keep low for server perf)
GameConfig.LoadingMinWait      = 2    -- minimum world warmup signal delay (non-blocking for control release)
GameConfig.LoadingMaxWait      = 25   -- max seconds for world warmup signal before fallback
-- Loading gate: stay up until character reaches assigned plot (server teleport can lag behind HRP creation)
GameConfig.LoadingGateArriveMaxWait = 300 -- max seconds at "Arriving at your base..." before forced release (avoids infinite hang)
GameConfig.LoadingGateAbsoluteMaxSeconds = 330 -- whole-gate hard cap (must be >= arrive + preload headroom)
GameConfig.StartupMetricLogEnabled = false -- true = prints startup timing milestones (join->critical/control/world-ready)

-- Gameplay music (client-side loop under SoundService)
GameConfig.GameplayMusic = {
    Enabled = true,  -- multi-track biome music system

    -- Sound object names in SoundService (must match Roblox Studio names exactly)
    MainThemeName   = "Sieglings_MainTheme",      -- hub / default / fallback
    BattleThemeName = "Sieglings_BattleTheme",    -- arena, gym, PvP, badlands

    -- Sky → biome track mapping (skybox name from BiomeSkyboxClient → Sound name in SoundService)
    -- If a Sound doesn't exist yet in SoundService, Main Theme is used as fallback.
    -- To add a new biome: place the Sound in SoundService and add the entry here.
    SkyToTrack = {
        -- Inner biomes (wedges between roads)
        FireSky     = "Sieglings_FireBiome",
        IceSky      = "Sieglings_SnowBiome",
        WindSky     = "Sieglings_WindBiome",
        EarthSky    = "Sieglings_EarthBiome",
        -- Outer biomes (baseplates)
        DesertSky   = "Sieglings_DesertBiome",
        ElectricSky = "Sieglings_ElectricBiome",
        WaterSky    = "Sieglings_OceanBiome",
        CaveSky     = "Sieglings_CaveBiome", -- fourth outer baseplate (Terrain.CaveBaseplate); same priority as other outer biomes
        -- ForestSky = "Sieglings_ForestBiome",  -- uncomment when track is added
    },

    -- Main arena (workspace.Arena → BlueTeam/RedTeam BattlePoint*, optional ArenaCenter): battle theme within this radius (studs)
    -- Use ~half the arena width if music only triggers at the edges (default 80).
    ArenaBattleMusicRadius = 50,

    -- Sky names from BiomeSkyboxClient outer baseplates. While CurrentSkyName matches one of these,
    -- that biome's music wins over ArenaBattleMusicRadius (so outer maps don't bleed arena BGM).
    OuterBiomeSkies = { "DesertSky", "ElectricSky", "WaterSky", "CaveSky" },

    -- Volume & pacing
    Volume        = 0.80,   -- target volume for the active track
    PlaybackSpeed = 1,
    FadeInTime    = 2.5,    -- initial fade-in on game start
    CrossfadeTime = 1.5,    -- crossfade duration when switching biome/combat tracks

    -- Unknown background music blocker (stops stray sounds from overlapping)
    BlockUnknownBackgroundMusic = true,

    -- Startup gates (wait for loading screens before playing)
    StartDelay      = 0.4,
    MaxScreenWait   = 45,
    ScreenSettleTime = 0.75,
    WaitForScreens  = { "LoadingScreen", "LaunchScreen" },
    SoundGroupName  = "Music",
}

-- Biome regions for ingredient spawns (mirrors BiomeSkyboxClient zone order; server-side)df
GameConfig.BiomeZone = {
	InnerWedgeMaxRadius = 1000,
	OuterZones = {
		{ path = { "Terrain", "DesertBaseplate" }, sky = "DesertSky" },
		{ path = { "Terrain", "ElectricBaseplate" }, sky = "ElectricSky" },
		{ path = { "Terrain", "OceanBaseplate" }, sky = "WaterSky" },
		{ path = { "Terrain", "CaveBaseplate" }, sky = "CaveSky" },
	},
	HubParts = {
		{ "HubArea", "HubGround" },
	},
	RoadNames = { "CaveRoad", "ElectricRoad", "DesertRoad", "WetRoad" },
	InnerWedges = {
		{ from = "ElectricRoad", to = "CaveRoad", sky = "EarthSky" },
		{ from = "CaveRoad", to = "WetRoad", sky = "FireSky" },
		{ from = "WetRoad", to = "DesertRoad", sky = "IceSky" },
		{ from = "DesertRoad", to = "ElectricRoad", sky = "WindSky" },
	},
}

-- World map (client UI): upload your map imaage to Roblox,f paste rbxassetid here, tune bounds if the pin feels off.
GameConfig.WorldMap = {
	Enabled = true,
	-- After uploading the PNG to Roblox (Asset Manager or Create Decal/Image), set e.g. "rbxassetid://1234567890"
	ImageAssetId = "76681495282321",
	UseAutoBounds = true,
	-- When UseAutoBounds is false, or auto-resolve finds no parts, these world XZ extents define the full image edges:
	MinWorldXZ = Vector2.new(-2200, -2200),
	MaxWorldXZ = Vector2.new(2200, 2200),
	-- Padding added outside the union of hub + outer baseplates when UseAutoBounds is true (0–0.25)
	AutoBoundsPadFraction = 0.08,
	-- If true, world +Z maps toward the bottom of the image (common for north-up art vs Roblox UI Y-down)
	FlipWorldZOnMap = true,
	-- Rotation (degrees). Use 0/90/180/270 to align the art with your world orientation.
	-- If the pin appears in the wrong biome but with roughly correct distance from the center,
	-- try 90 (clockwise), then 180, then 270.
	RotationDegrees = 0,
	-- Calibration mode (recommended): solve a worldXZ -> mapUV transform from 3 anchors.
	-- Enable, open the map, press [C], then:
	-- - Stand on a landmark in-world
	-- - Click that same landmark on the map image
	-- Do this for A, B, C. The output prints a ready-to-paste Calibration block.
	CalibrationEnabled = true,
	-- Temporary base-point debugging: when true, opening the map prints the player's world position
	-- plus the resolved owned PlotCenter so base/map anchor points can be collected from Studio output.
	DebugPrintPlayerPositionOnOpen = true,
	-- PlotCenter orientation can differ from the hand-drawn map. Snap owned base markers to these measured
	-- world XZ anchor points so each base lands on its true drawn hub pad.
	UseBasePointAnchors = true,
	BasePointAnchorSnapDistance = 90,
	BasePointAnchors = {
		{ id = "Red", world = Vector2.new(82.911, -93.859) },
		{ id = "Blue", world = Vector2.new(177.128, -0.531) },
		{ id = "Green", world = Vector2.new(175.310, 115.909) },
		{ id = "Yellow", world = Vector2.new(84.891, 221.530) },
		{ id = "Orange", world = Vector2.new(-36.782, 216.679) },
		{ id = "Purple", world = Vector2.new(-134.612, 121.513) },
		{ id = "Pink", world = Vector2.new(-130.212, -0.641) },
		{ id = "White", world = Vector2.new(-37.752, -89.189), mapUV = Vector2.new(0.620000, 0.335000) },
	},
	Calibration = nil,
	-- Auto-calibration (recommended): solve calibration from the 4 exterior zone doors (Ocean/Desert/Electric/Cave).
	-- You only need to click each door once on the map (UV capture); the world positions are resolved automatically.
	AutoFromZoneDoors = true,
	-- Filled via the in-game capture mode (press [Z] on the map): values are UVs (0..1) on the image.
	ZoneDoorMapUV = {
		Ocean = Vector2.new(0.281880, 0.615916),
		Desert = Vector2.new(0.478516, 0.345646),
		Electric = Vector2.new(0.688260, 0.615916),
		Cave = Vector2.new(0.481793, 0.902402),
	},
	-- Durable calibration: each point pairs a real world XZ position with its UV on the uploaded map image.
	-- Keep literal world coordinates for critical anchors so missing/streamed door parts cannot force bounds fallback.
	AnchorCalibration = {
		Enabled = true,
		Mode = "nearest3",
		MinResolvedPoints = 3,
		WarnErrorUV = 0.025,
		Points = {
			{ id = "OceanDoor", zoneId = "Ocean", uv = Vector2.new(0.281880, 0.615916) },
			{ id = "DesertDoor", zoneId = "Desert", uv = Vector2.new(0.478516, 0.345646) },
			{ id = "ElectricDoor", zoneId = "Electric", world = Vector2.new(-1004.753, 62.229), uv = Vector2.new(0.688260, 0.615916) },
			{ id = "CaveDoor", zoneId = "Cave", world = Vector2.new(30.186, -983.326), uv = Vector2.new(0.481793, 0.902402) },
			{ id = "CloudtopiaWind", world = Vector2.new(-586.587, 309.098), uv = Vector2.new(0.355000, 0.145000) },
			{ id = "EvergreenEarth", world = Vector2.new(-536.305, -375.834), uv = Vector2.new(0.610000, 0.535000) },
			{ id = "EvergreenForestReference", world = Vector2.new(-772.743, -764.626), uv = Vector2.new(0.680000, 0.680000) },
			{ id = "VolcanicFire", world = Vector2.new(737.707, -876.628), uv = Vector2.new(0.345000, 0.690000) },
			{ id = "FrozenIce", world = Vector2.new(650.820, 841.113), uv = Vector2.new(0.390000, 0.400000) },
		},
	},
	-- Panel width as fraction of the shorter viewport side
	PanelFill = 0.88,
	-- Map image width ÷ height (your art aspect); used for the map frame only
	MapAspectRatio = 1.65,
}

-- Campfire crafting / ingredient pickups
GameConfig.Cooking = {
	Enabled = true,
	SpawnIntervalSeconds = 5,
	MaxPickupsPerRegion = 10,
	PickupLifetimeSeconds = 180,
	PickupCollectRange = 22,
	CampfireProximity = 22,
	-- CookNPC: ReplicatedStorage template name; spawned near Broker/Curator/Siege Master hub (see CookNPC table).
	CookNPC = {
		TemplateName = "CookNPC",
		InstanceName = "CookNPC",
		-- World XZ offset from The Broker (studs). Curator/Siege use ±X; this uses +Z to sit with the hub group..
		OffsetFromBrokerStuds = Vector3.new(0, 0, 22),
		FallbackOffsetFromSpawnStuds = Vector3.new(0, 0, 22),
		OffsetFromArenaCenterStuds = Vector3.new(0, 0, 8),
		-- Studs added above the downward raycast hit when placing the model (hub ground snap).
		GroundOffsetStuds = 4.5,
		ExtraRotationDegrees = { pitch = 90, yaw = 0, roll = 0 },
		PromptObjectText = "Campfire Chef",
		-- Shown on BillboardGui above the NPC (matches other hub NPCs like The Broker).
		OverheadSubtitle = "Cooking & recipes",
	},
	MaxStackPerIngredientId = 999,
	MaxTotalIngredientCount = 2500,
	MinMixIngredients = 3,
	MaxMixIngredients = 4,
	DiversityBonusRaritySteps = 0.25,
	CraftCooldownSeconds = 2,
	BuffDurationByRarity = {
		Common = 60,
		Uncommon = 75,
		Rare = 95,
		Epic = 115,
		Legendary = 140,
	},
	PlayerAttackMultByRarity = { Common = 1.10, Uncommon = 1.16, Rare = 1.24, Epic = 1.32, Legendary = 1.40 },
	PlayerSpeedMultByRarity = { Common = 1.08, Uncommon = 1.14, Rare = 1.22, Epic = 1.30, Legendary = 1.38 },
	PlayerHealthBonusByRarity = { Common = 0.12, Uncommon = 0.18, Rare = 0.25, Epic = 0.32, Legendary = 0.40 },
	SiegelingStatMultByRarity = { Common = 1.08, Uncommon = 1.12, Rare = 1.18, Epic = 1.24, Legendary = 1.30 },

	-- Campfire recipe minigame settings
	Minigame = {
		Enabled = true,
		PatternTimeLimit = 12, -- seconds
		Attempts = 1,
		RequirePerfectMatch = false, -- false = partial match still crafts with lower quality
		QualityThresholds = {
			Perfect = 0.90,
			Great = 0.75,
			Good = 0.55,
		},
		PatternSessionTimeout = 30, -- seconds to submit after receiving recipe pattern
	},
	QualityPotencyMult = {
		Poor = 0.90,
		Good = 1.00,
		Great = 1.12,
		Perfect = 1.25,
	},
	QualityDurationMult = {
		Poor = 0.90,
		Good = 1.00,
		Great = 1.15,
		Perfect = 1.30,
	},
}

-- Spawning (SpawnPoints: one creature per point unless pack; cap 100 world creatures)
-- Lower = less CreatureAI + spawner load on published servers (tradeoff: fewer roaming spawns).
GameConfig.MaxWorldCreatures   = 100
GameConfig.SpawnIntervalMin    = 1.0
GameConfig.SpawnIntervalMax    = 2.5
GameConfig.SpawnsPerCycle      = 2     -- extra random spawns per cycle when under capacity
GameConfig.SpawnPointFillTarget = 0.5  -- run dungeon spawns when creature count above this fraction (lower = more dungeon spawns)
GameConfig.CreatureDespawnTime = 86400 -- unused when CreatureWorldAutoDespawnEnabled is false
GameConfig.CreatureWorldAutoDespawnEnabled = false -- stay until killed/captured/faint cleanup (no age despawn churn)
GameConfig.SpawnRadius         = 200
GameConfig.SpawnHeightOffset   = 1
GameConfig.FlyingHoverHeight   = 10   -- studs above ground for flying creatures (player model height)
GameConfig.SpawnPointSpread    = 0      -- 0 = spawn exactly on SpawnPoint part (non-pack); packs still use small offsets
-- Cover empty SpawnPoints: horizontal (XZ) radius to treat a point as "occupied" (keep small when Spread is 0)
GameConfig.SpawnPointCoverageRadius = 10
GameConfig.SpawnPointFillPerCycle   = 6
GameConfig.SpawnPointBurstFillMax   = 16 -- initial burst: fewer fill passes (server perf)
-- Weight divisor for species already in the world: w /= (1 + strength * count). 0 = off.
GameConfig.SpawnDiversityStrength   = 0.55
GameConfig.DungeonPointSpread  = 15     -- studs radius around a DungeonPoint (tighter for dungeon encounters)
GameConfig.BossPointSpread     = 10     -- studs radius around a BossPoint (tight cluster for boss arena).
GameConfig.DungeonSpawnCount   = {1, 1} -- one spawn per DungeonPoint per cycle (pack types may still spawn multiples)
GameConfig.BossRespawnTime     = 300    -- seconds before a boss can respawn at the same BossPoint..

-- Capture (creatures must be fainted first)
GameConfig.CaptureRange        = 30
GameConfig.CaptureHoldTime     = 0
GameConfig.CaptureAnimationTime = 2.5   -- card throw + warp animation duration
GameConfig.CaptureGracePeriod   = 10     -- seconds to return when out of range before capture fails
GameConfig.CaptureCooldown     = 0.5
-- Client CaptureClient: full-workspace descendant scan when no tagged targets in range (very expensive on large maps).
-- 0 = never run fallback (recommended published); >0 = max instances visited per fallback pass (yields every 400 steps).
GameConfig.CaptureWorkspaceFallbackMaxSteps = 0
-- Client: if workspace descendant count exceeds this at startup, warn once (cheap early-exit scan). 0 = off.
GameConfig.WorkspaceDescendantWarnThreshold = 100000
GameConfig.FaintDuration       = 10   -- seconds a fainted world creature stays before despawning (unclaimed = disappears so others can spawn)

-- Base
GameConfig.BasePlotSize        = 60
GameConfig.MaxBaseCreatures    = 20
GameConfig.BaseCreatureSpacing = 8

-- Base billboard distance (controls when individual creature tags hide and summary appears)
GameConfig.BaseBillboardMaxDistance = 80    -- studs; individual creature billboards hide beyond this
GameConfig.BaseSummaryShowDistance  = 100    -- studs; summary GUI fades in right when individual labels disappear
GameConfig.BaseSummaryMaxDistance   = 1500   -- studs; summary GUI hides beyond this

-- Base plots
GameConfig.MaxPlots            = 8
GameConfig.PlotSize            = 50
GameConfig.CreaturesPerRow     = 5
GameConfig.CreatureSpacing     = 8

-- Raiding
GameConfig.RaidCooldown        = 120
GameConfig.RaidDuration        = 30
GameConfig.MaxStealPerRaid     = 1
GameConfig.RaidProtectionTime  = 60
GameConfig.StealChanceBase     = 0.3
GameConfig.DefensePerCreature  = 0.03  -- steal chance reduction per defense creature (e.g. 6 defense = -18% chance)

-- AI Raids (wild creatures attack bases)
GameConfig.AIRaidEnabled       = false  -- set true to enable periodic wild-creature base raids
GameConfig.AIRaidInterval      = 90   -- seconds between AI raids
GameConfig.AIRaidPackSize      = {1, 2}  -- min/max raiders
GameConfig.AIRaidDefenseBreakChance = 0.15  -- 15% chance to free a defense creature per attack (when they defeat one)
GameConfig.AIRaidIncomeStealChance  = 0.08  -- 8% chance to steal income creature after defenses down
GameConfig.AIRaidDuration      = 18   -- seconds the raid lasts
GameConfig.AIRaidAttackInsideRadius = 55    -- raiders must be within this many studs of plot center to attack (stops outranging from outside base)
GameConfig.AIRaidDoorReachRadius     = 10   -- studs; raiders path to door (Ramp/PlotCenter) first; within this = "at door"
GameConfig.AIRaidCenterReachRadius   = 14   -- studs; after door, raiders path to plot center (up ramp); within this = "at center", then may engage targets

-- ═══════════════════════════════════════════════════════════════════════════════
-- Knight Base Rental (deploy base to outer biome outposts)
-- ═══════════════════════════════════════════════════════════════════════════════
GameConfig.KnightBaseRentalCost       = 1000           -- coins to rent a knight base slot
GameConfig.KnightBaseRentalDuration   = 300            -- seconds (5 minutes)
GameConfig.KnightBaseWarningTimes     = {30, 10}       -- seconds remaining when countdown warnings fire
GameConfig.KnightBaseBiomes           = {"DesertBiome", "OceanBiome", "ElectricBiome", "CaveBiome"}
GameConfig.KnightBaseSlotsPerBiome    = 2              -- PlotCenter1, PlotCenter2 per biome
GameConfig.KnightBaseMinPlayerLevel   = 5              -- player level required to rent

-- Dungeon events (legendary dungeon landmark + DungeonPoint spawners)
GameConfig.LegendaryDungeonsEnabled = false  -- set true to enable legendary dungeon spawns
GameConfig.DungeonSpawnInterval = 90   -- seconds between legendary dungeon spawns (more frequent)
GameConfig.DungeonDuration      = 120  -- seconds before dungeon despawns (longer so overlap possible)
GameConfig.DungeonCreatureCount = {2, 4} -- min/max legendary creatures per legendary dungeon
GameConfig.DungeonSpawnRadius   = 250  -- distance from center to spawn dungeons

-- Arena presence buff
GameConfig.ArenaPresenceBuff    = 0.10 -- +10% stats when owner stands on arena

-- Arena / Battle
GameConfig.ArenaRoundInterval  = 120
GameConfig.MaxBattleTeamSize   = 9      -- total grid slots (3x3 layout)
GameConfig.MaxBattleTeamCreatures = 5   -- max creatures allowed on team (enforced by AssignToBattle)
GameConfig.MinBattleTeamSize   = 1
GameConfig.BattleTickSpeed     = 1.2
GameConfig.GrowthPerWin        = 0.05
GameConfig.MaxGrowth           = 3.0
GameConfig.ArenaExclusionRadius = 80  -- studs around arena center where creatures cannot spawn/be targeted

-- Arena UI (client)
-- Show the condensed arena battle summary when the player is far enough that
-- individual arena fighter HP bars would be noisy. HP bars only show when close.
GameConfig.ArenaSummaryShowDistance    = 30   -- studs; summary fades in at/after this distance (outside arena dome)
GameConfig.ArenaSummaryMaxDistance     = 900  -- studs; summary hides beyond this distance
GameConfig.ArenaHealthBarShowDistance  = 10   -- studs; arena fighter HP bars only visible within this distance

-- Client: full-screen / mobile menus (MobileWindowLayout — inventory hub, shops, codex, profile, etc.)
-- UIMenuSpawnOffsetYPx: added to menu Y after coin bar / hub layout (positive = menus open lower on screen).
-- UIMenuWindowHeightScale: multiplies computed menu height (1 = default; 0.9 = shorter, 1.1 = taller).
-- UIMenuDesktopPanelScaleMultiplier: multiplies centered desktop/tablet panel scale (Inventory main window when not using mobile bounds).
GameConfig.UIMenuSpawnOffsetYPx = -100
GameConfig.UIMenuWindowHeightScale = 1.5
GameConfig.UIMenuDesktopPanelScaleMultiplier = 1
-- Close/dismiss buttons: Unicode U+2715 ("✕") often renders blank in Gotham on some devices; use ASCII everywhere.
GameConfig.UICloseGlyph = "X"

-- Mobile menus: stretch panel bounds to the device safe area (GuiService insets only, plus optional edge padding).
-- When true, menus use the full width/height between safe top and bottom instead of aligning to the HUD coin strip.
-- Height still stops above the bottom HUD hub bar when MobileMenuReserveBottomHubGap is true so hub buttons stay visible.
GameConfig.MobileMenuFillDeviceSafeArea = true
GameConfig.MobileMenuEdgeInsetPx = 0
GameConfig.MobileMenuUseHUDCoinBarTop = false
GameConfig.MobileMenuReserveBottomHubGap = true
-- When filling the safe area, ignore UIMenuSpawnOffsetYPx / UIMenuWindowHeightScale so the rectangle stays maximal.
GameConfig.MobileMenuIgnoreLegacyMenuHeightTweaksWhenFilling = true

-- WaterGym (OceanBiome): touch ArenaBase for [E] Summon Gym; requires battle team; pay entry fee; fight 5 high-level Water/Ice/Fire.

GameConfig.WaterGymEntryFee       = 500   -- coins to challenge the gym leader
GameConfig.WaterGymCreatureLevel  = 20    -- level of gym leader's squdad (high level)
GameConfig.WaterGymPromptRange    = 30    -- studs; ProximityPrompt on ArenaBase
GameConfig.WaterGymWinReward      = 5000   -- coins if player wins
GameConfig.WaterGymWinXP          = 75200    -- player XP on gym win
GameConfig.WaterGymCooldown       = 120   -- seconds; per-player cooldown between gym challengess.

-- CaveGym (CaveBiome): Shadow (+ Earth) element squad
GameConfig.CaveGymEntryFee       = 500
GameConfig.CaveGymCreatureLevel   = 20
GameConfig.CaveGymPromptRange    = 30
GameConfig.CaveGymWinReward      = 5000
GameConfig.CaveGymWinXP           = 200
GameConfig.CaveGymCooldown        = 120

-- DesertGym (DesertBiome): Fire + Earth element squad.
GameConfig.DesertGymEntryFee      = 500
GameConfig.DesertGymCreatureLevel = 20
GameConfig.DesertGymPromptRange   = 30
GameConfig.DesertGymWinReward     = 5000
GameConfig.DesertGymWinXP         = 200
GameConfig.DesertGymCooldown      = 120

-- ElectricGym (ElectricBiome): Lightning element squad
GameConfig.ElectricGymEntryFee       = 500
GameConfig.ElectricGymCreatureLevel = 20
GameConfig.ElectricGymPromptRange   = 30
GameConfig.ElectricGymWinReward     = 5000
GameConfig.ElectricGymWinXP         = 200
GameConfig.ElectricGymCooldown      = 120

-- Arena.Roc or Arena.Model_Roc: Cacty trade + PvP-style 1v1 (PvPBattleSystem) vs a DisplayTeam pick
GameConfig.ArenaRoc = {
	OpponentLevel = 25,
	WinCoins = 200,
	WinXP = 50,
	CooldownSeconds = 120,
	-- Shown in hub (not from player DataStore).
	Greeting = "Hi! I'm Roc — trade, challenge another player in PvP, or take on my team here!",
	GymName = "Roc's Challenge",
	-- Static data for the hub; **Vs Roc** uses PvP 1v1 — see NpcPvPChampionIndex.
	DisplayTeam = {
		{ sortOrder = 1, creatureId = "cacty", level = 1, note = "Partner" },
		{ sortOrder = 2, creatureId = "cactyjackedty", level = 25, note = "Favorite ★" },
	},
	-- Which **DisplayTeam** entry is the PvP opponent (1 = first row, 2 = second, etc.).
	NpcPvPChampionIndex = 2,
	NpcPvpMaxRange = 80,
	-- Hub: only one player may hold Roc UI session until timeout (seconds).
	HubLockSeconds = 120,
	-- NPC yaw: flat XZ look-at toward nearest player in range, or last Talk/Trade/Battle user (Eleminion-style).
	AttentionRange = 50,
	FacingUpdateInterval = 0.15,
}

-- Eleminion affinity “battle pass” milestones.
-- As you gain affinity with ANY Eleminion element, you earn these one-time rewards per element.
-- Thresholds are expressed as a fraction (0..1) of that element’s max affinity.
-- Eleminion NPC respawn check interval (ensure missing NPCs respawn)
GameConfig.EleminionEnsureNpcIntervalSeconds = 10

GameConfig.EleminionAffinityPass = {
	{ id = "25", pct = 0.25, rewards = { coins = 1000 }, label = "25% — 1,000 Gold" },
	{ id = "50", pct = 0.50, rewards = { egg = "Rare" }, label = "50% — Rare Egg" },
	{ id = "75", pct = 0.75, rewards = { gems = 250 }, label = "75% — 250 Diamonds" },
	{ id = "100", pct = 1.00, rewards = { egg = "Legendary" }, label = "100% — Legendary Egg" },
}

-- Zone doors (Ocean, Desert, Electric, Cave): spend 4 inner boss Legendaries at the door to pass; gym keys / sigils still supported in data.
-- When true: no pfrompts / unlock UI / remotes; gate parts are made non-collidafble so biomes stay walk-through.

GameConfig.ZoneDoorZoneIds        = { "Ocean", "Desert", "Electric", "Cave" }
GameConfig.ZoneDoorBiomeFolders   = { Ocean = "OceanBiome", Desert = "DesertBiome", Electric = "ElectricBiome", Cave = "CaveBiome" }
-- First match under workspace.Biomes wins. Include common alternates so gates work if the folder isn't the canonical name.df
GameConfig.ZoneDoorBiomeAliases   = {
	Ocean = { "AquaticBiome", "WaterBiome" },
	Desert = {},
	Electric = { "PeaksBiome", "ElectriBiome" },
	Cave = { "Cave", "CryptBiome", "CavernBiome", "CaveBiome_" },
}
-- Instance names for the interactable (wide openings: use an invisible part named ZoneDoorTrigger spanning the mouth).
GameConfig.ZoneDoorPartNames      = { "ZoneDoor", "ZoneDoorTrigger", "GateTrigger", "BiomeGate" }
-- Studs; increase if the prompt feels too hard to trigger at a wide cave mouth.
GameConfig.ZoneDoorPromptRange    = 28
-- Extra screen-space offset for the prompt UI (pixels). Use if the anchor is still slightly high/low.
GameConfig.ZoneDoorPromptUIOffset = Vector2.new(0, 12)
-- Client: each frame, move the prompt anchor to the door surface point closest to the local player (best for wide colliders).
GameConfig.ZoneDoorPromptTrackClosestToPlayer = true
-- Zone door modal (ZoneDoorBoardClient): leave empty for a minimal, gameplay-first UI (sigil tutorial lives in Profile / Codex).s
GameConfig.ZoneDoorModalSigilsHint = ""
GameConfig.ZoneDoorModalGateLines = {}
GameConfig.ZoneDoorProgressionBlurb = ""
-- After the first exterior gate is open, other gates use an Arena Pass from the Gym in the furthest-open zone (see ZoneDoorZoneIds order)..
GameConfig.ZoneDoorArenaPassFlavor = "Further exterior gates need an Arena Pass from your latest unlocked biome — win at that zone's Gym to earn one. Passes are spent when you open the next gate."
-- Per-gate copy for zone-door modal (tagline + features + gym). Keep features to plain zone mechanics.
GameConfig.ZoneDoorZonePitch = {
	Ocean = {
		tagline = "Swimming · underwater exploration",
		intro = "Ocean exterior: open water and underwater routes.",
		features = "Swim on the surface and dive underwater. Manage breath, follow currents, and use depth to reach hidden paths and pickups.",
		knightBase = "",
		gym = "Ocean Gym — defeat the Gym Leader to earn a Biome Pass toward other exterior zones.",
		closing = "",
	},
	Desert = {
		tagline = "Sandstorms · hidden secrets",
		intro = "Desert exterior: open dunes and landmarks.",
		features = "Cross open sand, push through sandstorms that change visibility and paths, and explore ruins and points of interest for loot.",
		knightBase = "",
		gym = "Desert Gym — win here for a Biome Pass and to unlock progress toward other gates.",
		closing = "",
	},
	Electric = {
		tagline = "Electro hazards · downtown streets",
		intro = "City exterior: streets, hazards, and vertical space.",
		features = "Move through city blocks, avoid electro hazards, and use streets and rooftops to navigate fights and objectives.",
		knightBase = "",
		gym = "City Gym — clear it for a Biome Pass and the League's urban trial.",
		closing = "",
	},
	Cave = {
		tagline = "Dark caves · deep exploration",
		intro = "Cave exterior: branching tunnels and dark passages.",
		features = "Explore winding tunnels and side chambers with limited light. Learn the layout, watch for ambushes, and push deeper for rewards.",
		knightBase = "",
		gym = "Cave Gym — beat the leader in tight arenas to earn your Biome Pass.",
		closing = "",
	},
}
-- Header gradient (top, bottom) per exterior zone — thematic flared.
GameConfig.ZoneDoorGateAccent = {
	Ocean = { top = Color3.fromRGB(55, 145, 255), bottom = Color3.fromRGB(18, 55, 120) },
	Desert = { top = Color3.fromRGB(255, 150, 70), bottom = Color3.fromRGB(140, 55, 25) },
	Electric = { top = Color3.fromRGB(255, 230, 90), bottom = Color3.fromRGB(90, 70, 180) },
	Cave = { top = Color3.fromRGB(160, 120, 255), bottom = Color3.fromRGB(40, 25, 70) },
}
-- Zone door UI: client-only small world tag (BaseSummary-style) + ScreenGui modal on ProximityPrompt (see ZoneDoorBoardClient)
GameConfig.ZoneDoorInfoBoard = {
	ZoneTitles = { Ocean = "Ocean", Desert = "Desert", Electric = "City", Cave = "Cave" },
	Lines = {}, -- superseded by ZoneDoorModalSigilsHint + ZoneDoorModalGateLines on client
}
GameConfig.ZoneDoorTag = {
	Enabled = true,
	WidthPx = 500,
	HeightPx = 100,
	-- Large / rotated doors: local StudsOffset Y is NOT always world-up/down. Default anchors tag to
	-- the part's bottom in world space, then raises by HeightAboveDoorBottomStuds (player-height-ish)..
	UseBottomWorldAnchor = true,
	HeightAboveDoorBottomStuds = 15,
	-- If UseBottomWorldAnchor = false: offset from part center; set StudsOffsetWorldSpace = true for pure world Y1
	StudsOffsetWorldSpace = false,
	StudsOffset = Vector3.new(0, -20, 0),
	MaxDistance = 160,
	TitleTemplate = "%s — Zone gate",
	Subtitle = "Interact to open gate",
}
-- Gym names shown on zone-door boards (match *GymSystem / WaterGymBattleSystem configs).
GameConfig.ZoneDoorGymNames = {
	Ocean = "Water Gym",
	Desert = "Desert Gym",
	Electric = "City Gym",
	Cave = "Cave Gym",
}
-- Element whose boss grants each zone's sigil (CreatureData.GetBossCreatureId(element))
GameConfig.ZoneDoorElementByZone  = { Ocean = "Water", Desert = "Fire", Electric = "Lightning", Cave = "Shadow" }

-- Sigil backboard UI: two sections
-- 1) Elemental inner bosses (Fire, Ice, Wind, Earth) — defeat legendary in inner zone → SiegeSquire sigil stored under that element name in player data
GameConfig.ElementalBossElements   = { "Fire", "Ice", "Wind", "Earth" }
-- 2) SiegeKnight Sigils (display names; order matches ZoneDoorZoneIds) — earned by winning that zone's Gym, stored as zone id (Ocean, Desert, Electric, Cave)
GameConfig.SiegeKnightSigilLabels  = { "Desert", "Cave", "Ocean", "Cyber" }
GameConfig.SiegeKnightSigilZoneIds = { "Desert", "Cave", "Ocean", "Electric" }  -- backend zone ids (Electric = Cyber)
-- SiegeLord: stored in player.sigils under this id (Profile Sigils tab + achievements). Earned on first successful Badlands extraction.
GameConfig.SiegeLordSigilZoneId   = "Badlands"
GameConfig.SiegeLordSigilSubtext    = "Successful extraction"

-- PvP (player vs player) 1v1 battle
GameConfig.PvPInteractionRange   = 30   -- studs; must be this close to challenge (server checks HumanoidRoot distance)
GameConfig.PvPWinGold            = 10   -- gold to winner
GameConfig.PvPLoserGoldLoss      = 10   -- gold lost by loser (minimum 0)
GameConfig.PvPBattlePointSpacing = 16   -- studs between red and blue battle points
GameConfig.PvPBattleTickSpeed    = 1.2  -- seconds between combat ticks (same as arena)
GameConfig.PvPReviveCoinCost     = 25   -- coins to instant-revive fainted creature after PvP loss
GameConfig.PvPReviveGemCost      = 2    -- gems (Robux) to instant-revive after PvP loss

-- Focus Bar & Special Attacks
GameConfig.FocusMax            = 100   -- focus needed to use special
GameConfig.FocusGainPerAttack  = 25    -- focus gained when dealing a normal attack
GameConfig.SpecialAttackDuration = 2.5 -- seconds to pause battle for special attack animation
GameConfig.BurnDamagePerRound  = 0.08  -- 8% max HP burn damage per round (applied start of turn)
GameConfig.BurnDuration        = 3     -- rounds burn lasts
GameConfig.EarthDmgReduction   = 0.25  -- 25% damage reduction from Earth special
GameConfig.EarthDebuffDuration = 3     -- rounds Earth debuff lasts
GameConfig.WindFocusDrain      = 50    -- focus drained from target by Wind special
GameConfig.WaterHealPercent    = 0.20  -- Water special: attacker heals 20% of max HP

-- Elemental weaknesses: Fire→Ice→Earth→Wind→Fire; Quad 1 Water/Lightning/Metal/Poison; Quad 2 4-cycle Light→Shadow→Psychic→Undead→Light
GameConfig.ElementalAdvantageMultiplier   = 1.5   -- damage when attacker element beats defender
GameConfig.ElementalDisadvantageMultiplier = 0.5   -- damage when defender element beats attacker

-- World Creature AI
GameConfig.AI_StationaryUntilEngaged = true -- wild creatures idle at spawn; move only for chase/attack/flee (not wander)
GameConfig.AI_FrameBuckets     = 10    -- time-slice distant creatures across more frames (lower server spikes; higher = smoother)
-- Hard-anchored stationary (not skittish / not pack-fear): how often to raycast Y + snap XZ (every frame is expensive).
GameConfig.AI_StationaryGroundSnapInterval = 0.25
GameConfig.AI_TickRate         = 0.5    -- seconds between AI updates
GameConfig.AI_WanderRadius     = 60     -- legacy; unused for wild creatures when AI_StationaryUntilEngaged
GameConfig.AI_WanderSpeed      = 5      -- studs/sec for raiders / engaged movement
GameConfig.AI_AggroRange       = 40     -- distance to detect targets
GameConfig.AI_AttackRange      = 40      -- distance to start attacking
GameConfig.AI_AttackCooldown   = 2.0    -- seconds between attacks
GameConfig.AI_FleeSpeed        = 12     -- studs/sec for fleeing
GameConfig.AI_FleeRange        = 35     -- distance skittish creatures flee to
GameConfig.AI_PackCallRange    = 60     -- distance pack members alert each other
GameConfig.AI_PlayerDamage     = 5      -- damage creatures deal to player companion
GameConfig.AI_CreatureDamage   = 8      -- damage creatures deal to other creatures
GameConfig.AI_CreatureProjectileSpeed = 80  -- projectile studs/sec when creatures attack

-- Stealing (player E-interact, carry to base; creature walks back to owner if carrier dies).
GameConfig.StealCarrySpeed      = 0.5     -- movement speed multiplier while carrying
GameConfig.StealHomeRadius      = 30      -- horizontal studs from PlotCenter (XZ); matches walk-back arrival
GameConfig.StealInteractRange   = 12     -- range for E to interact and pick up fainted base creature
GameConfig.StealWalkBackSpeed   = 14     -- studs/sec when dropped creature walks back to owner's base
GameConfig.StealVictimHitDamageCap = 12  -- max HP lost per hit when the victim attacks the thief to recover a steal

-- Home Recall (channel 5s, interrupt on damage)
GameConfig.HomeRecallChannelTime = 5   -- seconds to channel before teleporting to base
GameConfig.HomeRecallCylinderRadius  = 10  -- studs radius of stay-in-bubble (interrupt zone)
GameConfig.HomeRecallCylinderHeight  = 600  -- studs height of cylinder (legacy)
GameConfig.HomeRecallSkyHeight       = 600 -- studs: Heaven Beam extends this high
GameConfig.HomeRecallBeamRadius      = 18  -- studs: beam width (UFO levitation ray style, fits player comfortably)
GameConfig.HomeRecallGroundRadius    = 22  -- studs: impact circle radius

-- Companion (favorite creature)
GameConfig.CompanionAttackRange = 40
GameConfig.CompanionAttackCD    = 2.0
GameConfig.CompanionBaseDamage  = 1.1    -- multiplied by creature attack stat / 10
GameConfig.CompanionFollowDist  = 10
GameConfig.CompanionFollowSpeed = 28   -- used as catch-up speed when companion is far; normal follow matches player WalkSpeed
GameConfig.CompanionFollowCatchUpDist = 12  -- when distance to follow point exceeds this (studs), companion starts speeding up
GameConfig.CompanionFollowSpeedSmooth  = 10  -- how fast applied speed lerps toward target (higher = snappier, lower = smoother); avoids choppy speed jumps
GameConfig.WaterCompanionMaxSurfaceOffset = 1.5  -- water favorite max Y above player root when swimming; keeps companion at wading depth, never breaks surface until player touches ground
GameConfig.WaterBlockTag = "WaterBlock"  -- tag on Part(s) that define swim water; if player position is inside any tagged part, non-water favorite is carded
-- Aquatic creatures (spawned from OceanBiome / in WaterBlock): surface to "breathe" for this many seconds
GameConfig.WaterBreathSurfaceDuration = 10
GameConfig.WaterBreathUnderwaterBaseSeconds = 30   -- base time underwater before needing to surface (Common); higher rarity = longer
GameConfig.WaterBreathRarityMultiplier = { Common = 1.2, Uncommon = 1.5, Rare = 2.0, Epic = 3.0, Legendary = 6.0 }
GameConfig.WaterBlockSeekRange = 80     -- max studs from spawn to consider "seek out" nearest WaterBlock (OceanBiome water creatures)
GameConfig.CompanionTargetRange = 40    -- range for manual target selection
GameConfig.CompanionRespawnCD   = 30    -- seconds before companion respawns after fainting
GameConfig.CompanionAutoRecallDistance = 150  -- if companion gets this far from player (studs), auto-card and force resummon

-- ═══════════════════════════════════════════════════════════════════════════════
-- Mounting System (ride your favorite creature as a mount)
-- ═══════════════════════════════════════════════════════════════════════════════
GameConfig.MountEnabled              = true
GameConfig.MountMinPlayerLevel       = 10   -- player level required to unlock mounting

-- Speed formula: BaseSpeed + (creatureSpeed / 10) * MountSpeedMultiplier + mountSpeedBonus
-- Example: speed=10 creature → 16 + (10/10)*20 + 0 = 36 studs/sec
GameConfig.MountSpeedMultiplier      = 20   -- how much creature speed stat contributes
GameConfig.MountSprintMultiplier     = 1.4  -- sprint = mountSpeed * this (close to 26/16 ratio)
GameConfig.MountMaxSpeed             = 60   -- hard cap on ground mount speed (studs/sec)

-- Flying mount
GameConfig.MountFlySpeed             = 40   -- base flying mount speed (overrides ground formula)
GameConfig.MountFlyVerticalSpeed     = 25   -- studs/sec vertical (Space=up, Ctrl=down)
GameConfig.MountFlyMaxAltitude       = 200  -- max studs above ground

-- Swimming mount
GameConfig.MountSwimSpeed            = 30   -- base swimming mount speed
GameConfig.MountSwimVerticalSpeed    = 15   -- vertical swim speed

-- Mount / Dismount
GameConfig.MountCooldown             = 3    -- seconds between dismount and next mount

-- Mount Shield (absorbs damage while mounted; recharges when depleted)
GameConfig.MountShieldMultiplier     = 5    -- shield HP = creature defense * this multiplier
GameConfig.MountShieldRechargeTime   = 30   -- seconds to fully recharge shield from 0 to max
GameConfig.MountShieldRechargeDelay  = 3    -- seconds after shield breaks before recharge begins

-- Visual
GameConfig.MountModelScale           = 2.0  -- default scale for mount models (overridden per-creature)

-- ElectricBiome hazards (ElectroBall AOE) — only near world spawn markers, not full grid
GameConfig.ElectroBallCount          = 12   -- max orbs per activation cycle (capped near spawn points)
GameConfig.ElectroBallOnlyNearSpawnPoints = true -- no random grid fill; hazards only within ElectroBallNearSpawnStuds of SpawnPoint/Dungeon/Boss parts
GameConfig.ElectroBallNearSpawnStuds = 40   -- ~10 classic 4-stud blocks radius around each spawn-type part
GameConfig.ElectroBallSpawnInterval  = 30   -- seconds between activations
GameConfig.ElectroBallRadius         = 20   -- studs (10 foot) AOE radius
GameConfig.ElectroBallChargeSeconds  = 3    -- seconds for red fill (FF14-style)
GameConfig.ElectroBallStunSeconds    = 1    -- stun duration after impact
GameConfig.ElectroBallDamagePercent  = 0.25 -- 25% max health damage

-- Base creature placement (Meshy AI / rigged models)
GameConfig.RiggedModelFloorBuffer = 2.5  -- extra studs lift for Humanoid/rigged models; compensates for mesh extent beyond bbox
GameConfig.PointHeightOffset = 0  -- baseline extra studs when placing on Defense or Income points (all creatures)

-- Defense turrets (base defense creatures)
GameConfig.DefenseAttackRange   = 20    -- studs - attack range (within plot area)
GameConfig.DefenseAttackCD      = 2.5   -- seconds between shots
GameConfig.DefenseBaseDamage    = 12    -- multiplied by creature attack stat / 10
GameConfig.DefensePassiveXP     = 3     -- XP per creature in defense slot per income tick (while stationed)
GameConfig.DefenseKillXP        = 15    -- XP to the defense creature when it gets a kill (world creature or enemy companion)
-- Defense AI loop ([BasePlacementSystem.lua]): max defense models processed per 0.5s tick (lower = spread CPU).
GameConfig.DefenseTurretBatchSize = 12

-- Placeholder Visuals
GameConfig.PlaceholderSize     = Vector3.new(4, 4, 4)
GameConfig.CreatureBobHeight   = 1
GameConfig.CreatureBobSpeed    = 2

-- Player Health
GameConfig.PlayerMaxHealth           = 100   -- starting/max HP hhffd
-- Pilot defense (world): incoming damage is reduced similar to arena (dmg - defense/3, min 1)
GameConfig.PlayerBaseDefense         = 9
GameConfig.PlayerHealthOutOfCombatDelay = 5   -- seconds without any health decrease before regen runs (includes drowning etc.)
GameConfig.PlayerHealthRegenPerSecond  = 100  -- HP/sec only after the delay above; no regen while health is still dropping

-- Underwater Breath Mechanic (client-side)
GameConfig.BreathMaxTime             = 10    -- seconds of breath before drowning starts
GameConfig.BreathDrownDamage         = 20    -- HP lost per tick when drowning (+10%)
GameConfig.BreathDrownTickInterval   = 5     -- seconds between drown damage ticks
GameConfig.BreathWaterCreatureBonus  = 2     -- extra seconds of breath per water creature level (equipped favorite)
GameConfig.BreathWaterCreatureMaxBonus = 60  -- cap on bonus breath from water creature level
-- Seconds fully submerged before O2 meter appears + starts draining
GameConfig.BreathSubmergeGraceSeconds = 5

-- Player movement
GameConfig.PlayerWalkSpeed      = 16    -- normal walk speed (studs/sec)
GameConfig.PlayerSprintSpeed    = 26    -- sprint speed when holding Shift or toggling Sprint button

-- Player Combat (outside arena)
GameConfig.PlayerRangedDamage   = 4
GameConfig.PlayerRangedRange    = 35
GameConfig.PlayerRangedCooldown = 0.8   -- seconds
GameConfig.PlayerRangedSpeed    = 120   -- projectile studs/sec
GameConfig.PlayerMeleeDamage    = 6
GameConfig.PlayerMeleeRange     = 10
GameConfig.PlayerMeleeCooldown  = 1.2
GameConfig.PlayerMeleeRadius    = 8     -- AOE radius for melee swing

-- Pilot Rebirth Systemk
-- Each level: gold cost + a specific TEAM of 5 creatures (by id). Player must own each creature
-- at MAX LEVEL (base=10, evolved=25, final=50). Team list is updatable here; order is slot 1..5.
-- Rewards scale: passive gold per tick, world damage multiplier, max health bonus (cumulative).
GameConfig.RebirthPassiveGoldPerLevel   = 2   -- extra gold per income tick per rebirth level
GameConfig.RebirthDamageMultPerLevel    = 0.05 -- +5% world damage per level (1 + level * this)
GameConfig.RebirthHealthBonusPerLevel  = 15   -- flat +HP to PlayerMaxHealth per rebirth level
GameConfig.RebirthMaxLevel             = 10   -- max rebirth level (config length can extend this)
-- RebirthLevels: { gold = number, team = { creatureId1, creatureId2, creatureId3, creatureId4, creatureId5 } }
-- Each creature must be owned and at max level for that form. Update team arrays to change requirements.
GameConfig.RebirthLevels = {
	-- Level 1: 5k gold, team of 5 commons (starters) max leveled
	{ gold = 5000,  team = { "cacty", "breezee", "fawny", "sundile"} },
	-- Level 2: 15k gold, 5 commons (Fire)
	{ gold = 15000, team = { "firsky", "pylook", "sundile", "draco"} },
	-- Level 3: 40k gold, mix common + uncommon
	{ gold = 40000, team = { "emberpup", "raydile", "emberfin", "sootfang", "fawny" } },
	-- Level 4: 100k gold
	{ gold = 100000, team = { "frostfly", "icewee", "snowdrift", "falcoat", "chilldoe" } },
	-- Level 5: 250k gold
	{ gold = 250000, team = { "ragguette", "blinky", "zephyrpup", "cloudhare", "cloudwisp" } },
	-- Level 6: 500k gold
	{ gold = 500000, team = { "applehead", "papap", "squirebud", "jackedty", "bonoblade" } },
	-- Level 7: 1M gold
	{ gold = 1000000, team = { "gloomrat", "duskmoth", "shadeblob", "nightfang", "hexweaver" } },
	-- Level 8: 2.5M gold
	{ gold = 2500000, team = { "monkwatt", "boltant", "voltpecker", "sparkwisp", "thundermole" } },
	-- Level 9: 5M gold
	{ gold = 5000000, team = { "dracoil", "cinderstag", "glacius", "lumina", "hurricrane" } },
	-- Level 10: 10M gold
	{ gold = 10000000, team = { "pyleer", "solgator", "frostag", "ceesteed", "skydon" } },
}

-- Codex UI (creature detail panel when clicking creature icon/name)
GameConfig.ENABLE_CODEX_UI      = true  -- set false to disable Codex and creature-click-to-open behavior
GameConfig.ENABLE_CODEX_3D_VIEWER = true -- set false to use placeholder only (no ViewportFrame model viewer)
GameConfig.ENABLE_BASE_LAYOUT_OVERVIEW = false -- legacy flag; base slot grid was removed from inventory (Bag tab now)

-- Siegelings cinematic inventory cells: trait text under creature name (element + class/role).
-- false = full words, e.g. "Wind Support", "Earth Bruiser", "Psychic Support"
-- true  = compact codes, e.g. "WI SU", "EA BR", "PS SU"
GameConfig.CinematicInventoryTraitsAbbreviated = false

-- Targeting (E key)
GameConfig.TargetScanRange      = 50    -- max range to scan for targetable creatures

-- Laser Door (base protection)
GameConfig.LaserDoorEnabled     = true
GameConfig.LaserDoorDamage      = 20    -- damage to non-friends entering dome
GameConfig.LaserDoorMaxFriends  = 10
GameConfig.ShieldLaserDoorTransparency = 1 -- 1 = invisible (100%), 0 = opaque
GameConfig.BaseShieldDomeEnabled = true -- toggle dome visual created by base shield button (protection logic still runs)
GameConfig.DomeRadius           = 50    -- studs, horizontal (XZ) radius at base; dome is ellipsoid
GameConfig.DomeHeightMultiplier = 1.5   -- vertical (Y) radius = DomeRadius * sdthis (taller ellipse, same footprint)
GameConfig.ShieldDuration       = 50    -- seconds before shield expires and must be reactivated

-- Shop hub — SCoins packs (pay Diamonds/gems → SCoins currency). Tier names match GemsRobuxPacks.
GameConfig.ScoinsGemPacks = {
	{ id = "handful", name = "Handful", gemCost = 100,  scoins = 5000 },
	{ id = "bag",     name = "Bag",     gemCost = 200,  scoins = 15000 },
	{ id = "sack",    name = "Sack",    gemCost = 350,  scoins = 50000 },
	{ id = "chest",   name = "Chest",   gemCost = 600,  scoins = 175000 },
	{ id = "safe",    name = "Safe",    gemCost = 1000, scoins = 600000 },
	{ id = "bank",    name = "Bank",    gemCost = 1700, scoins = 2000000 },
}

-- Same six tier names — Diamonds only via Robux (Developer Product). Set productId in Creator Studio / GameConfig.
GameConfig.GemsRobuxPacks = {
	{ id = "handful", name = "Handful", gems = 80,   robuxListPrice = 49,  productId = 0 },
	{ id = "bag",     name = "Bag",     gems = 200,  robuxListPrice = 99,  productId = 0 },
	{ id = "sack",    name = "Sack",    gems = 450,  robuxListPrice = 199, productId = 0 },
	{ id = "chest",   name = "Chest",   gems = 1000, robuxListPrice = 399, productId = 0 },
	{ id = "safe",    name = "Safe",    gems = 2200, robuxListPrice = 799, productId = 0 },
	{ id = "bank",    name = "Bank",    gems = 5000, robuxListPrice = 1699, productId = 0 },
}

-- Buff Shop
GameConfig.BuffShopItems = {
	{id = "shield",     name = "Energy Shield",     desc = "-50% damage for 60s",      duration = 60,  coinCost = 150, gemCost = 12},
	{id = "highjump",   name = "Super Jump",        desc = "Moon-like jump for 45s",   duration = 45,  coinCost = 100, gemCost = 8},
	{id = "speed",      name = "Super Speed",       desc = "2x walk speed for 60s",    duration = 60,  coinCost = 120, gemCost = 10},
	{id = "invuln",     name = "Invulnerability",   desc = "Immune to damage for 15s", duration = 15,  coinCost = 450, gemCost = 5},
	{id = "invis",      name = "Invisibility",      desc = "Hidden from creatures 30s", duration = 30,  coinCost = 270, gemCost = 3},
	{id = "swap",       name = "Swap Places",       desc = "Teleport to random player", duration = 0,  coinCost = 200, gemCost = 16},
	{id = "lowgrav",    name = "Low Gravity",       desc = "Moon-like float for 40s",   duration = 40,  coinCost = 90,  gemCost = 8},
	{id = "regen",      name = "Health Regen",      desc = "Regen 2 HP/s for 45s",      duration = 45,  coinCost = 130, gemCost = 11},
	{id = "doublejump", name = "Double Jump",       desc = "Jump again in mid-air 40s", duration = 40,  coinCost = 110, gemCost = 9},
	{id = "glide",      name = "Feather Fall",      desc = "Slow fall for 50s",         duration = 50,  coinCost = 95,  gemCost = 8},
	{id = "xpboost",    name = "XP Boost",          desc = "2x XP gain for 120s",       duration = 120, coinCost = 180, gemCost = 2},
	{id = "coinboost",  name = "Coin Magnet",       desc = "2x income for 90s",         duration = 90,  coinCost = 160, gemCost = 1},
	{id = "haste",      name = "Haste",             desc = "1.5x walk speed for 50s",   duration = 50,  coinCost = 80,  gemCost = 7},
	{id = "giant",      name = "Giant",             desc = "2x size for 30s",           duration = 30,  coinCost = 140, gemCost = 11},
	{id = "glow",       name = "Radiant",           desc = "Glow aura for 60s",         duration = 60,  coinCost = 360, gemCost = 4},
	{id = "antifall",   name = "Featherfeet",       desc = "No fall damage for 45s",    duration = 45,  coinCost = 100, gemCost = 8},
	{id = "swimspeed",  name = "Dolphin",           desc = "3x swim speed for 45s",     duration = 45,  coinCost = 85,  gemCost = 7},
	{id = "lucky",      name = "Lucky Charm",       desc = "Better capture odds 90s",   duration = 90,  coinCost = 540, gemCost = 6},
	-- Siege Master stock (Arena-only provisioning)
	{id = "siegelingxpboost", name = "Siegeling XP Draft", desc = "2x Siegeling XP for 180s", duration = 180, coinCost = 260, gemCost = 2, shop = "siege_master"},
	{id = "food_powerstew", name = "Power Stew", desc = "+35% player attack for 120s", duration = 120, coinCost = 220, gemCost = 2, shop = "siege_master"},
	{id = "food_ironbroth", name = "Iron Broth", desc = "+25% max health for 120s", duration = 120, coinCost = 220, gemCost = 2, shop = "siege_master"},
	{id = "food_swiftsnack", name = "Swift Snack", desc = "+40% movement speed for 90s", duration = 90, coinCost = 180, gemCost = 1, shop = "siege_master"},
	{id = "food_fire_siegeling", name = "Ember Feed", desc = "Fire Siegelings: +30% attack for 180s", duration = 180, coinCost = 260, gemCost = 2, shop = "siege_master"},
	{id = "food_earth_siegeling", name = "Stone Feed", desc = "Earth Siegelings: +30% defense for 180s", duration = 180, coinCost = 260, gemCost = 2, shop = "siege_master"},
	{id = "food_wind_siegeling", name = "Gale Feed", desc = "Wind Siegelings: +30% speed for 180s", duration = 180, coinCost = 260, gemCost = 2, shop = "siege_master"},
	{id = "food_water_siegeling", name = "Tide Feed", desc = "Water Siegelings: +30% health for 180s", duration = 180, coinCost = 260, gemCost = 2, shop = "siege_master"},
}

-- Cosmetic Shop
GameConfig.CosmeticItems = {
	-- Trails (each item: coin price and diamond/gem price — player picks one)
	{id = "trail_fire",     slot = "trail", name = "Fire Trail",      coinCost = 300,  gemCost = 50},
	{id = "trail_ice",      slot = "trail", name = "Ice Trail",       coinCost = 300,  gemCost = 50},
	{id = "trail_rainbow",  slot = "trail", name = "Rainbow Trail",   coinCost = 400,  gemCost = 50},
	{id = "trail_shadow",   slot = "trail", name = "Shadow Trail",    coinCost = 400,  gemCost = 50},
	{id = "trail_nature",   slot = "trail", name = "Nature Trail",    coinCost = 350,  gemCost = 50},
	{id = "trail_poison",   slot = "trail", name = "Poison Trail",    coinCost = 400,  gemCost = 50},
	{id = "trail_void",     slot = "trail", name = "Void Trail",      coinCost = 400,  gemCost = 50},
	{id = "trail_sunset",   slot = "trail", name = "Sunset Trail",    coinCost = 350,  gemCost = 50},
	{id = "trail_candy",    slot = "trail", name = "Candy Trail",     coinCost = 400,  gemCost = 50},
	{id = "trail_galaxy",   slot = "trail", name = "Galaxy Trail",     coinCost = 400,  gemCost = 50},
	-- Auras
	{id = "aura_flame",     slot = "aura",  name = "Flame Aura",      coinCost = 500,  gemCost = 42},
	{id = "aura_electric",  slot = "aura",  name = "⚡ Electric Aura", coinCost = 500,  gemCost = 42},
	{id = "aura_divine",    slot = "aura",  name = "✨ Divine Aura",   coinCost = 600,  gemCost = 100},
	{id = "aura_nature",    slot = "aura",  name = "Nature Aura",      coinCost = 500,  gemCost = 42},
	{id = "aura_void",      slot = "aura",  name = "Void Aura",       coinCost = 600,  gemCost = 100},
	{id = "aura_ice",       slot = "aura",  name = "Ice Aura",        coinCost = 500,  gemCost = 42},
	{id = "aura_poison",    slot = "aura",  name = "Poison Aura",     coinCost = 120,  gemCost = 10},
	{id = "aura_sakura",    slot = "aura",  name = "Sakura Aura",     coinCost = 144,  gemCost = 12},
	{id = "aura_star",      slot = "aura",  name = "Star Aura",       coinCost = 156,  gemCost = 13},
	-- Name Colors
	{id = "name_gold",      slot = "nameColor", name = "Gold Name",    coinCost = 200,  gemCost = 17},
	{id = "name_red",       slot = "nameColor", name = "Red Name",     coinCost = 200,  gemCost = 17},
	{id = "name_rainbow",   slot = "nameColor", name = "Rainbow Name", coinCost = 240,  gemCost = 12},
	{id = "name_blue",      slot = "nameColor", name = "Blue Name",    coinCost = 200,  gemCost = 17},
	{id = "name_green",     slot = "nameColor", name = "Green Name",   coinCost = 200,  gemCost = 17},
	{id = "name_purple",    slot = "nameColor", name = "Purple Name",  coinCost = 200,  gemCost = 17},
	{id = "name_cyan",      slot = "nameColor", name = "Cyan Name",    coinCost = 200,  gemCost = 17},
	{id = "name_pink",      slot = "nameColor", name = "Pink Name",    coinCost = 200,  gemCost = 17},
	{id = "name_orange",    slot = "nameColor", name = "Orange Name",  coinCost = 200,  gemCost = 17},
	{id = "name_white",     slot = "nameColor", name = "White Name",   coinCost = 120,  gemCost = 6},
	{id = "name_lime",      slot = "nameColor", name = "Lime Name",    coinCost = 200,  gemCost = 17},
	{id = "name_coral",     slot = "nameColor", name = "Coral Name",   coinCost = 200,  gemCost = 17},
}

-- Base Exterior Shop (purchase theme; equipping applies theme or foundation color styling)
-- Full / premium themes: palette can override materials. Exterior_* + default + Base Plots pads: tint Color only (keeps DiamondPlate etc.).
GameConfig.BaseExteriorItems = {
	-- Premium full themes (500 coins each) — materials + colors via BaseExteriorSystem.THEME_PALETTES
	{id = "HauntedHouse", name = "Haunted House", desc = "Spooky base with walls, stairs & lanterns", coinCost = 500, gemCost = 40},
	{id = "RetroArcade",   name = "Retro Arcade", desc = "Neon lights & arcade vibes on all walls & stairs", coinCost = 500, gemCost = 40},
	{id = "JungleHut",       name = "Jungle Hut",       desc = "Thatch & bamboo greens — humid jungle hideaway", coinCost = 500, gemCost = 40},
	{id = "IceFortress",     name = "Ice Fortress",     desc = "Frosted stone & glacier blues — frozen stronghold", coinCost = 500, gemCost = 40},
	{id = "VolcanicCavern",  name = "Volcanic Cavern",  desc = "Basalt & glowing magma veins — deep volcanic hall", coinCost = 500, gemCost = 40},
	{id = "FloatingPalace", name = "Floating Palace", desc = "Marble, pearl & soft gold — skyborne courts", coinCost = 500, gemCost = 40},
	-- Color themes (500 coins each) - base foundations only
	{id = "exterior_red",    name = "Red Base",    desc = "Base foundations in red",    coinCost = 500, gemCost = 40, color = Color3.fromRGB(200, 60, 60)},
	{id = "exterior_blue",   name = "Blue Base",   desc = "Base foundations in blue",   coinCost = 500, gemCost = 40, color = Color3.fromRGB(60, 100, 200)},
	{id = "exterior_green",  name = "Green Base",  desc = "Base foundations in green",  coinCost = 500, gemCost = 40, color = Color3.fromRGB(60, 180, 80)},
	{id = "exterior_yellow", name = "Yellow Base", desc = "Base foundations in yellow", coinCost = 500, gemCost = 40, color = Color3.fromRGB(220, 200, 60)},
	{id = "exterior_purple", name = "Purple Base", desc = "Base foundations in purple", coinCost = 500, gemCost = 40, color = Color3.fromRGB(140, 80, 200)},
	{id = "exterior_orange", name = "Orange Base", desc = "Base foundations in orange", coinCost = 500, gemCost = 40, color = Color3.fromRGB(230, 140, 50)},
	{id = "exterior_white", name = "White Base", desc = "Base foundations in white", coinCost = 500, gemCost = 40, color = Color3.fromRGB(248, 248, 250)},
	{id = "exterior_black", name = "Black Base", desc = "Base foundations in black", coinCost = 500, gemCost = 40, color = Color3.fromRGB(28, 28, 32)},
}

-- Base Color Shop (Drip Shop → Base Plots) — tints IncomePoint* / DefensePoint* pads; when equipped, also Floor1/Carpet1 (income) + Floor2/Carpet2 (defense). Carpets keep Studio colors until a palette is equipped.
-- Optional defensePointColor: if omitted, a slightly darker variant of color is used for defense pads.
GameConfig.BaseColorItems = {
	{id = "base_red",    name = "Red Pads",    color = Color3.fromRGB(200, 60, 60),   defensePointColor = Color3.fromRGB(160, 45, 50),   coinCost = 300, gemCost = 28},
	{id = "base_blue",   name = "Blue Pads",   color = Color3.fromRGB(60, 100, 200),  defensePointColor = Color3.fromRGB(45, 75, 170),  coinCost = 300, gemCost = 28},
	{id = "base_green",  name = "Green Pads",  color = Color3.fromRGB(60, 180, 80),   defensePointColor = Color3.fromRGB(45, 140, 60),   coinCost = 300, gemCost = 28},
	{id = "base_yellow", name = "Yellow Pads", color = Color3.fromRGB(220, 200, 60),  defensePointColor = Color3.fromRGB(180, 155, 45), coinCost = 300, gemCost = 28},
	{id = "base_purple", name = "Purple Pads", color = Color3.fromRGB(140, 80, 200),  defensePointColor = Color3.fromRGB(110, 55, 165), coinCost = 300, gemCost = 28},
	{id = "base_orange", name = "Orange Pads", color = Color3.fromRGB(230, 140, 50),  defensePointColor = Color3.fromRGB(195, 105, 40), coinCost = 300, gemCost = 28},
	{id = "base_white",  name = "White Pads",  color = Color3.fromRGB(238, 238, 242),  defensePointColor = Color3.fromRGB(175, 175, 182), coinCost = 300, gemCost = 28},
	{id = "base_black",  name = "Black Pads",  color = Color3.fromRGB(52, 52, 58),   defensePointColor = Color3.fromRGB(30, 30, 36),   coinCost = 300, gemCost = 28},
}


-- Base decor / furnishing — creature statue placement costs (gold sink, scales by rarity)
GameConfig.DecorPointsPerFloor4  = 6       -- legacy hint; see DecorMaxSlotIndexPerFloor
GameConfig.DecorMaxSlotIndexPerFloor = 12 -- max DecorPoint index per floor (server validates)
GameConfig.DecorCostByRarity = {
	Common    = 500,
	Uncommon  = 1000,
	Rare      = 2500,
	Epic      = 5000,
	Legendary = 10000,
}
-- Open-world capture: statue of species X on base reduces cost to capture X (non-Badlands)
GameConfig.DecorStatueCaptureCostMultiplier = 0.85 -- applied before Lucky buff
GameConfig.DecorStatueCaptureHoldMultiplier   = 1  -- 1 = off; e.g. 0.9 = shorter channel

-- Gym Battle System — Floor 4 personal arena (visitors battle owner's battle team)
GameConfig.GymBattleTickSpeed    = 1.2    -- seconds between combat ticks (matches arena)0
GameConfig.GymBattleWinGold      = 200    -- flat gold reward for winning a gym battle
GameConfig.GymBattleCooldown     = 60     -- seconds before same challenger can re-challenge
GameConfig.GymBountyBase         = 100    -- starting bounty on a fresh gym (coins)
GameConfig.GymBountyGrowth       = 50     -- bounty increases by this much per owner defense win
GameConfig.GymBountyMax          = 5000   -- bounty cap so it doesn't grow infinitely.
GameConfig.GymOwnerDefenseIncome = 75     -- owner earns this many coins per successful defense
GameConfig.GymChallengerLosePay  = 25     -- consolation coins for a challenger who loses
GameConfig.GymJumbotronEnabled   = false  -- toggle live jumbotron viewports on gym leaderboard screens (OFF = disabled, reduces client load)

-- ═══════════════════════════════════════════════════════════════════════════════
-- Section 12: BADLANDS (Roguelike PvPvE Mode)
-- ═══════════════════════════════════════════════════════════════════════════════.
GameConfig.BadlandsEnabled              = true
GameConfig.BadlandsMaxPlayers           = 8     -- max players per run
GameConfig.BadlandsMinPlayers           = 1     -- min to start a run
GameConfig.BadlandsQueueTimeout         = 60    -- seconds before starting with < max players
GameConfig.BadlandsRunDuration          = 600   -- 10 minutes (hard timer — expelled with only favorite)
GameConfig.BadlandsHardDeadline         = 600   -- 10 minutes (hard collapse — same as run duration).
GameConfig.BadlandsExtractionActivateAt = 420   -- 7 minutes (extraction points go live)
GameConfig.BadlandsSpawnShieldDuration  = 30    -- seconds of PvP immunity on entry

-- Broker NPC (Arena Hub): optional extra rotation (degrees) applied after spawn placement.
-- Use if the mesh still appears flipped after fixing PrimaryPart in Studio (e.g. pitch = -90).
GameConfig.BrokerNPCExtraRotationDegrees = { pitch = 90, yaw = 0, roll = 0 }
-- Studs added above downward raycast ground Y before PivotTo (0 = pivot at hit surface).
GameConfig.BrokerNPCGroundOffsetStuds = 0

-- Hub NPC spawn markers (BrokerSpawn, etc.): wait once so HubArea.SpawnLocation has its final CFrame before resolving marker offsets against it.
GameConfig.HubNpcPlacementDeferSeconds = 0.12

-- Arena Hub: Curator Trader — sells six rotating Siegelings (2 Common, 1 Uncommon, 1 Rare, 1 Epic, 1 Legendary).
-- Priced above egg tiers; each slot can be bought with coins or diamonds (gems).
GameConfig.ArenaTraderEnabled = true
GameConfig.ArenaTrader = {
	StockRefreshSeconds = 6 * 3600, -- full rotation (seconds)c
	-- Horizontal offset from The Broker (studs); Y is resolved with a downward raycast.
	OffsetFromBrokerStuds = Vector3.new(-26, 0, 0),
	-- Studs added above the raycast hit when placing TraderNPC (matches Cook / Siege Master tuning).
	GroundOffsetStuds = 1.6,
	-- When workspace CuratorSpawn exists: studs above that part’s top face (ignores terrain raycast). Two classic 4-stud blocks = 8
	CuratorSpawnRiseStuds = 3,
	-- If BrokerNPC is missing, place using HubArea.SpawnLocation + this offset instead.
	FallbackOffsetFromSpawnStuds = Vector3.new(-26, 0, 16),
	-- Optional extra rotation for TraderNPC after placement (degrees).
	-- Keep this at pitch=90 to stand the current Trader model upright.
	ExtraRotationDegrees = { pitch = 90, yaw = 0, roll = 0 },
	-- Per-rarity prices (direct known creature — much higher than mystery eggs).
	CoinPrice = { Common = 1500, Uncommon = 7500, Rare = 45000, Epic = 75000, Legendary = 110000 },
	GemPrice = { Common = 500, Uncommon = 1000, Rare = 2500, Epic = 5000, Legendary = 10000 },
	-- Curator stock variants are restricted to Silver/Gold only.
	VariantWeights = { Silver = 50, Gold = 50 },
}

-- Arena Hub: Siege Master vendor (food + XP provisioning)
-- Placement: opposite side of The Broker from The Curator — position = Broker − ArenaTrader.OffsetFromBrokerStuds
-- (Curator is Broker + that offset). If Broker is missing: SpawnLocation − ArenaTrader.FallbackOffsetFromSpawnStuds.
-- Only if both are missing: OffsetFromArenaCenterStuds from Arena.ArenaCenter (legacy).
GameConfig.SiegeMasterEnabled = true
GameConfig.SiegeMaster = {
	OffsetFromArenaCenterStuds = Vector3.new(-22, 0, -8),
	-- Studs added above the raycast hit when placing SiegeMasterNPC.
	GroundOffsetStuds = 4.2,
	-- Same pitch=90 pattern as Curator / Broker NPC mesh upright (model imports lying flat).
	ExtraRotationDegrees = { pitch = 90, yaw = 0, roll = 0 },
	PromptRange = 12,
	PurchaseRange = 22, -- must be this close to buy siege-only items.
}

-- Badlands: Bag
GameConfig.BadlandsBagSlots             = 10    -- bag capacity
GameConfig.BadlandsLootBagDespawnTime   = 60    -- seconds before dropped bag despawns
GameConfig.BadlandsLootBagBeaconRange   = 200   -- visible distance (studs)

-- Badlands: Creature Spawning
-- ALL Badlands creatures are Gold/Legend variant, 1.5–2x scale, stat-boosted.09
-- Every rarity can spawn (Common through Legendary) but they are ALL elite versions.
GameConfig.BadlandsStarterCreatureCount = 5     -- placed on first spawn points when a run starts (easy finds)
GameConfig.BadlandsRoamingHighLevelCount = 10 -- additional Epic/Legend-heavy spawns (fixed pool = 15 with cap below)
GameConfig.BadlandsInitialSpawnCount    = 5     -- legacy compat: starters only; full wave uses Starter + Roaming counts
GameConfig.BadlandsSpawnInterval        = 90    -- only used if BadlandsPeriodicRefillEnabled
GameConfig.BadlandsMaxCreatures         = 15    -- hard cap: 5 starters + 10 high-tier to find in the run
GameConfig.BadlandsPeriodicRefillEnabled = false -- no drip spawns; creatures persist until killed/captured
GameConfig.BadlandsCreatureScaleMin     = 1.5   -- minimum model scale multiplier (1.5x normal)
GameConfig.BadlandsCreatureScaleMax     = 2.0   -- maximum model scale multiplier (2x normal)
GameConfig.BadlandsCreatureStatMult     = 2.0   -- stat multiplier (HP, ATK, DEF, SPD all 2x)
GameConfig.BadlandsCreatureMinLevel     = 20    -- minimum creature level
GameConfig.BadlandsCreatureMaxLevel     = 50    -- maximum creature level
-- Rarity weights: ALL rarities spawn, weighted toward higher tiers
GameConfig.BadlandsRarityWeights        = { Common = 15, Uncommon = 20, Rare = 25, Epic = 25, Legendary = 15 }
-- Variant weights: Gold and Legend ONLY (no Normal, no Silver — every creature is elite)
GameConfig.BadlandsVariantWeights       = { Gold = 50, Legend = 50 }

-- Badlands: Capture
GameConfig.BadlandsCaptureTime          = 0.3   -- faster than normal (0.5)..
GameConfig.BadlandsCaptureCost          = 0     -- free captures inside Badlands
GameConfig.BadlandsLoadingDuration      = 5     -- seconds; no point/activity interactions during load-in
GameConfig.BadlandsSacrificeStatBoost   = 5     -- flat bonus per sacrificed creature (Health/Attack/Defense/MovementSpeed)
GameConfig.BadlandsBonusBuffAmount     = 10    -- flat boost to ALL stats when offering the Broker's bonus creature

-- Badlands: Zone Collapse
GameConfig.BadlandsOuterCollapseTime    = 480   -- 8 min: outer ring collapses
GameConfig.BadlandsMidCollapseTime      = 540   -- 9 min: mid ring collapses
GameConfig.BadlandsInnerCollapseTime    = 720   -- 12 min: inner ring collapses
GameConfig.BadlandsCollapseDPS          = 5     -- HP/sec in collapsed zonesf
GameConfig.BadlandsCollapseTransition   = 30    -- seconds for ring to fully collapse

-- Badlands: Extraction
GameConfig.BadlandsExtractionTime       = 5     -- seconds to channel
GameConfig.BadlandsExtractionMinTime    = 5     -- hard floor with run power reduction
GameConfig.BadlandsExtractionBeaconRange= 200   -- visible to all (studs)
GameConfig.BadlandsExtractionPointCount = 12     -- number of extraction points

-- Badlands: Run Power (temporary progression per run)
GameConfig.BadlandsMaxRunLevel          = 10
GameConfig.BadlandsXPPerCapture         = 15    -- per creature level
GameConfig.BadlandsXPPerFaint           = 5     -- per creature level (no capture)
GameConfig.BadlandsXPPerPlayerKill      = 100
GameConfig.BadlandsXPPerMinuteSurvived  = 10
GameConfig.BadlandsXPPerLoot            = 25    -- per creature looted from bag

-- Badlands: Economy
GameConfig.BadlandsFreeRunsPerDay       = 1     -- free entries per 24h
GameConfig.BadlandsExtraRunGemCost      = 50    -- gems for additional runs beyond free

-- Badlands: Supply Drops (mid-run events)
GameConfig.BadlandsSupplyDropCount      = 2     -- drops per run
GameConfig.BadlandsSupplyDropTimes      = {240, 360}  -- seconds into run
GameConfig.BadlandsSupplyDropDespawn    = 45    -- seconds
GameConfig.BadlandsSupplyDropMinRarity  = "Rare"
GameConfig.BadlandsSupplyDropMaxRarity  = "Epic"

-- Egg Shop: 5 tiers. All eggs purchasable with Coins or Robux (higher tiers very expensive).
-- Percentages per tier (must sum to 100). Used to build each egg's pool.

-- Common Egg pool: Common, Uncommon, Rare
GameConfig.EggCommon_CommonPct   = 60
GameConfig.EggCommon_UncommonPct = 30
GameConfig.EggCommon_RarePct     = 10

-- Rare Egg pool: Uncommon, Rare
GameConfig.EggRare_UncommonPct   = 50
GameConfig.EggRare_RarePct       = 50

-- Mythic Egg pool: Rare, Mythic (Mythic = Epic creatures in CreatureData)
GameConfig.EggMythic_RarePct    = 50
GameConfig.EggMythic_MythicPct   = 50

-- Legendary Egg pool: Rare, Mythic, Legendary
GameConfig.EggLegendary_RarePct     = 30
GameConfig.EggLegendary_MythicPct  = 40
GameConfig.EggLegendary_LegendaryPct = 30

-- God Egg pool: Mythic, Legendary
GameConfig.EggGod_MythicPct     = 40
GameConfig.EggGod_LegendaryPct  = 60

GameConfig.EggShopItems = {
	{
		id = "egg_common",
		name = "Common Egg",
		icon = "egg_white",
		desc = "Common, Uncommon, or Rare",
		coinCost = 1000,
		gemCost = 85,
		robuxCost = 25,
		productId = 0, -- set to Developer Product ID for Robux; 0 = not configured
		pool = {
			{ rarity = "Common",   weight = GameConfig.EggCommon_CommonPct   },
			{ rarity = "Uncommon", weight = GameConfig.EggCommon_UncommonPct },
			{ rarity = "Rare",     weight = GameConfig.EggCommon_RarePct     },
		},
	},
	{
		id = "egg_rare",
		name = "Rare Egg",
		icon = "egg_blue",
		desc = "Uncommon or Rare",
		coinCost = 10000,
		gemCost = 720,
		robuxCost = 75,
		productId = 0,
		pool = {
			{ rarity = "Uncommon", weight = GameConfig.EggRare_UncommonPct },
			{ rarity = "Rare",     weight = GameConfig.EggRare_RarePct     },
		},
	},
	{
		id = "egg_mythic",
		name = "Mythic Egg",
		icon = "egg_purple",
		desc = "Rare or Mythic",
		coinCost = 25000,
		gemCost = 1750,
		robuxCost = 199,
		productId = 0,
		pool = {
			{ rarity = "Rare",   weight = GameConfig.EggMythic_RarePct   },
			{ rarity = "Mythic", weight = GameConfig.EggMythic_MythicPct },
		},
	},
	{
		id = "egg_legendary",
		name = "Legendary Egg",
		icon = "egg_gold",
		desc = "Rare, Mythic, or Legendary",
		coinCost = 50000,
		gemCost = 3400,
		robuxCost = 499,
		productId = 0,
		pool = {
			{ rarity = "Rare",      weight = GameConfig.EggLegendary_RarePct     },
			{ rarity = "Mythic",    weight = GameConfig.EggLegendary_MythicPct    },
			{ rarity = "Legendary", weight = GameConfig.EggLegendary_LegendaryPct },
		},
	},
	{
		id = "egg_god",
		name = "God Egg",
		icon = "egg_rainbow",
		desc = "Mythic or Legendary only",
		coinCost = 100000,
		gemCost = 6200,
		robuxCost = 999,
		productId = 0,
		pool = {
			{ rarity = "Mythic",    weight = GameConfig.EggGod_MythicPct    },
			{ rarity = "Legendary", weight = GameConfig.EggGod_LegendaryPct },
		},
	},
}

return GameConfig



