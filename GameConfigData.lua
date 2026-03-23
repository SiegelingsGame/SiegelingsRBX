--[[
	GameConfigData.lua
	ReplicatedStorage/Modules/GameConfigData
	Actual config data. Required lazily by GameConfig to avoid recursive require.
]]
-- lol

local GameConfig = {}

-- Day / Night Cycle (Lighting.ClockTime)
GameConfig.DayNightCycleEnabled = true   -- true = enable cycle; false = use default Roblox lighting
GameConfig.DayNightCycleSeconds = 500    -- real seconds per full day (24 in-game hours); changeable
GameConfig.NightStartHour = 22          -- ClockTime >= this = night (6 PM)
GameConfig.NightEndHour = 5              -- ClockTime < this = night (until 6 AM)
-- Night spawn variants: Common/Uncommon → Silver chance; Rare+ → Gold chance (0–1)
GameConfig.NightSpawnSilverChance = 0.10  -- chance for Common/Uncommon at night
GameConfig.NightSpawnGoldChance = 0.05    -- chance for Rare+ at night
-- World creatures with evolutions: at night randomly evolve (base→evolved), at dawn devolve
GameConfig.NightWorldEvolutionChance   = 0.20  -- per creature per check (base form with evolvesTo)
GameConfig.NightWorldEvolutionInterval = 30     -- seconds .between evolution checks
GameConfig.NightSpawnBonus             = 100   -- extra max world creatures at night (for rare/night spawns)

-- Debug / Dev toggles (set true for testing)ff
GameConfig.SpawnOnlyCreaturesWithModels = true  -- true = only spawn creatures that have models in CreatureModels
GameConfig.DebugCoins1000 = false               -- true = new players start with 1000 coins
GameConfig.DebugFloor2Level2 = false            -- true = Floor 2 srequires player level 2 (instead of 5)
GameConfig.DebugDoubleSpeed = false             -- true = player WalkSpeed is 32 (2x default)
GameConfig.QuickSpawnDebugMode = false         -- true = bypass loading gate (skip Events/LoadingReady wait) for fast testing
GameConfig.CombinerRecyclerPromptAllPlots = true -- true = add E prompts to Combiner/Recycler on ALL plots (for testing; set false for release)
GameConfig.DebugBrokerGoldOnly = false             -- true = The Broker only asks for 100 gold coins instead of a creature sacrifice (for testing)
GameConfig.DebugBrokerCacty = false                -- true = The Broker always asks for a Lv1 Common Earth Cacty (for testing)

-- Economy
GameConfig.StartingCoins       = 1000
GameConfig.IncomeTickSeconds   = 10
GameConfig.MaxInventorySize    = 50
GameConfig.EggCost             = 50
GameConfig.MaxIncomeSlots      = 6   -- matches IncomePoints on plot
GameConfig.MaxDefenseSlots     = 6   -- matches DefensePoints on plot (auto-detected too)

-- Leveling (creature levels; max level depends on evolution stage)
GameConfig.MaxCreatureLevel    = 10   -- legacy/fallbackd
GameConfig.BaseMaxLevel        = 10   -- base form (no evolvesFrom)
GameConfig.EvolvedMaxLevel     = 25   -- after 1st evolution (has evolvesTo)
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
GameConfig.PlayerXP_Capture       = 15     -- XP for capturing a creature
GameConfig.PlayerXP_ArenaWin      = 50     -- XP for winning arena battle
GameConfig.PlayerXP_ArenaKill     = 10     -- XP per arena kill
GameConfig.PlayerXP_IncomeTick    = 2      -- XP per income tick (if income > 0)
GameConfig.PlayerXP_RaidWin       = 30     -- XP for successful raid
GameConfig.PlayerXP_DungeonKill   = 20     -- XP for killing a dungeon creature
GameConfig.PlayerXP_BossKill      = 100    -- XP for killing a boss creature

-- Base Floors
GameConfig.Floor2Cost             = 500   -- coins to buy Floor 2
GameConfig.Floor2LevelReq         = 2      -- player level required
GameConfig.Floor3Cost             = 5000  -- coins to buy Floor 3
GameConfig.Floor3LevelReq         = 10     -- player level required
GameConfig.Floor4Cost             = 25000 -- coins to buy Floor 4 (Siegelord Arena)
GameConfig.Floor4LevelReq         = 15     -- player level required for Floor 4

-- Evolution & Combine (monster duplication / variant tiers)
GameConfig.EvolutionMinLevel      = 10      -- level required for 1st evolution (base form)
GameConfig.EvolutionMinLevel2     = 25      -- level required for 2nd evolution (evolved form)
GameConfig.CombineCost            = 0      -- gold cost to combine 3 into next variant (0 = free)
GameConfig.RecyclerDuplicateCount = 3      -- min same-creature duplicates to trade for 1 egg (1 rarity tier higher)
-- Egg hatch time (minutes) by creature level inside the egg: level 1→20min, 2→30, 3→60, 4→120, 5→600, 6+→300
GameConfig.EggHatchMinutesByLevel = { 20, 30, 60, 120, 600, 300 }
-- Mystery egg inspect cost (diamonds/gems) for revealing what's inside before hatch
GameConfig.EggInspectGemCost = 5
GameConfig.VariantStatMultipliers = { Normal = 1.0, Silver = 1.15, Gold = 1.35, Legend = 1.6 }

-- Selling
GameConfig.SellEnabled            = true
GameConfig.SellRange              = 12     -- studs to walk-up sell from base creature

-- Base Interaction (walk-up creature management: pick up, move, swap, sell from base)
GameConfig.BaseInteractionRange   = 12     -- studs; ProximityPrompt activation distance
GameConfig.BasePlacementPromptRange = 18   -- studs; [E] Place Here / Swap on points while holding (slightly larger so standing on defense platform can reach adjacent empty points)
GameConfig.BaseInteractionEnabled = true   -- master toggle for pick-up/move/swap features

-- Per-floor slot limits (total across all owned floors)
GameConfig.IncomePointsPerFloor   = 6
GameConfig.DefensePointsPerFloor  = 6

-- Loading screen: critical-first startup + background world warmup
GameConfig.LoadingCriticalMaxWait = 18 -- max seconds client waits for critical gameplay readiness
GameConfig.LoadingSpawnTarget  = 30   -- world creatures target for non-critical "world ready" signal
GameConfig.LoadingMinWait      = 2    -- minimum world warmup signal delay (non-blocking for control release)
GameConfig.LoadingMaxWait      = 25   -- max seconds for world warmup signal before fallback
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
        -- ForestSky = "Sieglings_ForestBiome",  -- uncomment when track is added
    },

    -- Cave biome: positional override (not skybox-based).
    -- Plays when the player is above CaveBaseplate within CaveVerticalRange studs.
    -- Path: workspace.Terrain.CaveBaseplate
    CaveBiome = {
        TrackName      = "Sieglings_CaveBiome",
        BaseplateParent = "Terrain",
        BaseplateName   = "CaveBaseplate",
        VerticalRange   = 700,  -- studs above the baseplate top surface
    },

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

-- Spawning (SpawnPoints should stay full; common creatures prioritized)
-- Reduced from 200 to 150 for performance (night bonus +100 still applies)
GameConfig.MaxWorldCreatures   = 400
GameConfig.SpawnIntervalMin    = 0.5   -- faster spawns so SpawnPoints stay full
GameConfig.SpawnIntervalMax    = 1.5
GameConfig.SpawnsPerCycle      = 4     -- spawn this many per cycle when under 50% capacity (else 1-2)
GameConfig.SpawnPointFillTarget = 0.5  -- run dungeon spawns when creature count above this fraction (lower = more dungeon spawns)
GameConfig.CreatureDespawnTime = 180
GameConfig.SpawnRadius         = 200
GameConfig.SpawnHeightOffset   = 1
GameConfig.FlyingHoverHeight   = 10   -- studs above ground for flying creatures (player model height)
GameConfig.SpawnPointSpread    = 25     -- studs radius around a biome SpawnPoint
GameConfig.DungeonPointSpread  = 15     -- studs radius around a DungeonPoint (tighter for dungeon encounters)
GameConfig.BossPointSpread     = 10     -- studs radius around a BossPoint (tight cluster for boss arena)
GameConfig.DungeonSpawnCount   = {2, 4} -- min/max creatures per DungeonPoint per cycle (guarantee at least 1 rare+ always)
GameConfig.BossRespawnTime     = 300    -- seconds before a boss can respawn at the same BossPoint

-- Capture (creatures must be fainted first)
GameConfig.CaptureRange        = 30
GameConfig.CaptureHoldTime     = 0
GameConfig.CaptureAnimationTime = 2.5   -- card throw + warp animation duration
GameConfig.CaptureGracePeriod   = 10     -- seconds to return when out of range before capture fails
GameConfig.CaptureCooldown     = 0.5
GameConfig.FaintDuration       = 10   -- seconds a fainted world creature stays before despawning (unclaimed = disappears so others can spawn)

-- Base
GameConfig.BasePlotSize        = 60
GameConfig.MaxBaseCreatures    = 20
GameConfig.BaseCreatureSpacing = 8

-- Base billboard distance (controls when individual creature tags hide and summary appears)
GameConfig.BaseBillboardMaxDistance = 80    -- studs; individual creature billboards hide beyond this
GameConfig.BaseSummaryShowDistance  = 100    -- studs; summary GUI fades in right when individual labels disappear
GameConfig.BaseSummaryMaxDistance   = 900   -- studs; summary GUI hides beyond this

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
GameConfig.DungeonSpawnInterval = 90   -- seconds between legendary dungeon spawns (more frequent)
GameConfig.DungeonDuration      = 120  -- seconds before dungeon despawns (longer so overlap possible)
GameConfig.DungeonCreatureCount = {2, 4} -- min/max legendary creatures per legendary dungeon
GameConfig.DungeonSpawnRadius   = 250  -- distance from center to spawn dungeons

-- Arena presence buff
GameConfig.ArenaPresenceBuff    = 0.10 -- +10% stats when owner stands on arena

-- Arena / Battle
GameConfig.ArenaRoundInterval  = 60
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

-- WaterGym (OceanBiome): touch ArenaBase for [E] Summon Gym; requires battle team; pay entry fee; fight 5 high-level Water/Ice/Fire
GameConfig.WaterGymEntryFee       = 100   -- coins to challenge the gym leader
GameConfig.WaterGymCreatureLevel  = 45    -- level of gym leader's squdad (high level)
GameConfig.WaterGymPromptRange    = 10    -- studs; ProximityPrompt on ArenaBase
GameConfig.WaterGymWinReward      = 5000   -- coins if player wins
GameConfig.WaterGymWinXP          = 75200    -- player XP on gym win
GameConfig.WaterGymCooldown       = 120   -- seconds; per-player cooldown between gym challenges

-- CaveGym (CaveBiome): Shadow (+ Earth) element squad
GameConfig.CaveGymEntryFee       = 100
GameConfig.CaveGymCreatureLevel   = 45
GameConfig.CaveGymPromptRange    = 10
GameConfig.CaveGymWinReward      = 5000
GameConfig.CaveGymWinXP           = 200
GameConfig.CaveGymCooldown        = 120

-- DesertGym (DesertBiome): Fire + Earth element squad
GameConfig.DesertGymEntryFee      = 100
GameConfig.DesertGymCreatureLevel = 45
GameConfig.DesertGymPromptRange   = 10
GameConfig.DesertGymWinReward     = 5000
GameConfig.DesertGymWinXP         = 200
GameConfig.DesertGymCooldown      = 120

-- ElectricGym (ElectricBiome): Lightning element squad
GameConfig.ElectricGymEntryFee       = 100
GameConfig.ElectricGymCreatureLevel = 45
GameConfig.ElectricGymPromptRange   = 10
GameConfig.ElectricGymWinReward     = 5000
GameConfig.ElectricGymWinXP         = 200
GameConfig.ElectricGymCooldown      = 120

-- Zone doors (Ocean, Desert, Electric, Cave): 4 sigils from boss defeats open one door; gym win grants key for another
GameConfig.ZoneDoorZoneIds        = { "Ocean", "Desert", "Electric", "Cave" }
GameConfig.ZoneDoorBiomeFolders   = { Ocean = "OceanBiome", Desert = "DesertBiome", Electric = "ElectricBiome", Cave = "CaveBiome" }
-- Ocean allows alias AquaticBiome; Desert may use VolcanicBiome until DesertBiome exists
GameConfig.ZoneDoorBiomeAliases   = { Ocean = { "AquaticBiome", "WaterBiome" } }
-- Element whose boss grants each zone's sigil (CreatureData.GetBossCreatureId(element))
GameConfig.ZoneDoorElementByZone  = { Ocean = "Water", Desert = "Fire", Electric = "Lightning", Cave = "Shadow" }

-- Sigil backboard UI: two sections
-- 1) Elemental Bosses (Fire, Ice, Wind, Earth) — defeat in world to earn corresponding SiegeKnight Sigil
GameConfig.ElementalBossElements   = { "Fire", "Ice", "Wind", "Earth" }
-- Which zone sigil is earned when this elemental boss is defeated (zone id used in player data)
GameConfig.ElementalBossToZoneId   = { Fire = "Desert", Ice = "Cave", Wind = "Ocean", Earth = "Electric" }
-- 2) SiegeKnight Sigils (display names; order matches ZoneDoorZoneIds for door-unlock UI)
GameConfig.SiegeKnightSigilLabels  = { "Desert", "Cave", "Ocean", "Cyber" }
GameConfig.SiegeKnightSigilZoneIds = { "Desert", "Cave", "Ocean", "Electric" }  -- backend zone ids (Electric = Cyber)

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
GameConfig.AI_TickRate         = 0.5    -- seconds between AI updates
GameConfig.AI_WanderRadius     = 60     -- max wander distance from spawn
GameConfig.AI_WanderSpeed      = 10      -- studs/sec for wandering
GameConfig.AI_AggroRange       = 40     -- distance to detect targets
GameConfig.AI_AttackRange      = 40      -- distance to start attacking
GameConfig.AI_AttackCooldown   = 2.0    -- seconds between attacks
GameConfig.AI_FleeSpeed        = 12     -- studs/sec for fleeing
GameConfig.AI_FleeRange        = 35     -- distance skittish creatures flee to
GameConfig.AI_PackCallRange    = 60     -- distance pack members alert each other
GameConfig.AI_PlayerDamage     = 5      -- damage creatures deal to player companion
GameConfig.AI_CreatureDamage   = 8      -- damage creatures deal to other creatures
GameConfig.AI_CreatureProjectileSpeed = 80  -- projectile studs/sec when creatures attack

-- Stealing (player E-interact, carry to base; creature walks back to owner if carrier dies)
GameConfig.StealCarrySpeed      = 0.8     -- movement speed multiplier while carrying
GameConfig.StealHomeRadius      = 30      -- how close to your plot center to "deliver"
GameConfig.StealInteractRange   = 12     -- range for E to interact and pick up fainted base creature
GameConfig.StealWalkBackSpeed   = 14     -- studs/sec when dropped creature walks back to owner's base

-- Home Recall (channel 5s, interrupt on damage)
GameConfig.HomeRecallChannelTime = 5   -- seconds to channel before teleporting to base
GameConfig.HomeRecallCylinderRadius  = 10  -- studs radius of stay-in-bubble (interrupt zone)
GameConfig.HomeRecallCylinderHeight  = 12  -- studs height of cylinder (legacy)
GameConfig.HomeRecallSkyHeight       = 600 -- studs: Heaven Beam extends this high
GameConfig.HomeRecallBeamRadius      = 18  -- studs: beam width (UFO levitation ray style, fits player comfortably)
GameConfig.HomeRecallGroundRadius    = 22  -- studs: impact circle radius

-- Companion (favorite creature)
GameConfig.CompanionAttackRange = 40
GameConfig.CompanionAttackCD    = 2.0
GameConfig.CompanionBaseDamage  = 1.1    -- multiplied by creature attack stat / 10
GameConfig.CompanionFollowDist  = 6
GameConfig.CompanionFollowSpeed = 28   -- used as catch-up speed when companion is far; normal follow matches player WalkSpeed
GameConfig.CompanionFollowCatchUpDist = 12  -- when distance to follow point exceeds this (studs), companion starts speeding up
GameConfig.CompanionFollowSpeedSmooth  = 10  -- how fast applied speed lerps toward target (higher = snappier, lower = smoother); avoids choppy speed jumps
GameConfig.WaterCompanionMaxSurfaceOffset = 1.5  -- water favorite max Y above player root when swimming; keeps companion at wading depth, never breaks surface until player touches ground
GameConfig.WaterBlockTag = "WaterBlock"  -- tag on Part(s) that define swim water; if player position is inside any tagged part, non-water favorite is carded
-- Aquatic creatures (spawned from OceanBiome / in WaterBlock): surface to "breathe" for this many seconds
GameConfig.WaterBreathSurfaceDuration = 10
GameConfig.WaterBreathUnderwaterBaseSeconds = 30   -- base time underwater before needing to surface (Common); higher rarity = longer
GameConfig.WaterBreathRarityMultiplier = { Common = 1, Uncommon = 1.25, Rare = 1.5, Epic = 2, Legendary = 2.5 }
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

-- ElectricBiome hazards (ElectroBall AOE)
GameConfig.ElectroBallCount          = 50   -- total placed (grid + 1 per SpawnPoint/DungeonPoint/BossPoint)
GameConfig.ElectroBallSpawnInterval  = 10   -- seconds between activations
GameConfig.ElectroBallRadius         = 10   -- studs (10 foot) AOE radius
GameConfig.ElectroBallChargeSeconds  = 3    -- seconds for red fill (FF14-style)
GameConfig.ElectroBallStunSeconds    = 1    -- stun duration after impact
GameConfig.ElectroBallDamagePercent  = 0.25 -- 25% max health damage

-- Base creature placement (Meshy AI / rigged models)
GameConfig.RiggedModelFloorBuffer = 2.5  -- extra studs lift for Humanoid/rigged models; compensates for mesh extent beyond bbox
GameConfig.PointHeightOffset = 0  -- baseline extra studs when placing on Defense or Income points (all creatures)

-- Defense turrets (base defense creatures)
GameConfig.DefenseAttackRange   = 40    -- studs - attack range (within plot area)
GameConfig.DefenseAttackCD      = 2.5   -- seconds between shots
GameConfig.DefenseBaseDamage    = 12    -- multiplied by creature attack stat / 10
GameConfig.DefensePassiveXP     = 3     -- XP per creature in defense slot per income tick (while stationed)
GameConfig.DefenseKillXP        = 15    -- XP to the defense creature when it gets a kill (world creature or enemy companion)

-- Placeholder Visuals
GameConfig.PlaceholderSize     = Vector3.new(4, 4, 4)
GameConfig.CreatureBobHeight   = 1
GameConfig.CreatureBobSpeed    = 2

-- Player Health
GameConfig.PlayerMaxHealth           = 100   -- starting/max HP
GameConfig.PlayerHealthOutOfCombatDelay = 5   -- seconds without damage before regen starts
GameConfig.PlayerHealthRegenPerSecond  = 100  -- HP/sec when regen is active (rapid heal to full)

-- Underwater Breath Mechanic (client-side)
GameConfig.BreathMaxTime             = 10    -- seconds of breath before drowning starts
GameConfig.BreathDrownDamage         = 10    -- HP lost per tick when drowning
GameConfig.BreathDrownTickInterval   = 5     -- seconds between drown damage ticks
GameConfig.BreathWaterCreatureBonus  = 2     -- extra seconds of breath per water creature level (equipped favorite)
GameConfig.BreathWaterCreatureMaxBonus = 60  -- cap on bonus breath from water creature level

-- Player movement
GameConfig.PlayerWalkSpeed      = 16    -- normal walk speed (studs/sec)
GameConfig.PlayerSprintSpeed    = 26    -- sprint speed when holding Shift or toggling Sprint button

-- Player Combat (outside arena)
GameConfig.PlayerRangedDamage   = 4
GameConfig.PlayerRangedRange    = 25
GameConfig.PlayerRangedCooldown = 0.8   -- seconds
GameConfig.PlayerRangedSpeed    = 120   -- projectile studs/sec
GameConfig.PlayerMeleeDamage    = 10
GameConfig.PlayerMeleeRange     = 10
GameConfig.PlayerMeleeCooldown  = 1.2
GameConfig.PlayerMeleeRadius    = 8     -- AOE radius for melee swing

-- Pilot Rebirth System
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
	{ gold = 5000,  team = { "cacty", "breezee", "pylme", "sundile", "ceeponee" } },
	-- Level 2: 15k gold, 5 commons (Fire)
	{ gold = 15000, team = { "firsky", "pylook", "sundile", "draco", "smoldervine" } },
	-- Level 3: 40k gold, mix common + uncommon
	{ gold = 40000, team = { "emberpup", "raydile", "hotty", "sootfang", "fawny" } },
	-- Level 4: 100k gold
	{ gold = 100000, team = { "frostfly", "icewee", "snowdrift", "frosty", "chilldoe" } },
	-- Level 5: 250k gold
	{ gold = 250000, team = { "ragguette", "blinky", "zephyrpup", "cloudhare", "lofty" } },
	-- Level 6: 500k gold
	{ gold = 500000, team = { "applehead", "papap", "squirebud", "jackedty", "mossy" } },
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
GameConfig.ENABLE_BASE_LAYOUT_OVERVIEW = true -- Raid tab: show Income/Defense slot tracks + defense HP (set false to hide)

-- Targeting (E key)
GameConfig.TargetScanRange      = 50    -- max range to scan for targetable creatures

-- Laser Door (base protection)
GameConfig.LaserDoorEnabled     = true
GameConfig.LaserDoorDamage      = 20    -- damage to non-friends entering dome
GameConfig.LaserDoorMaxFriends  = 10
GameConfig.DomeRadius           = 50    -- studs, horizontal (XZ) radius at base; dome is ellipsoid
GameConfig.DomeHeightMultiplier = 1.5   -- vertical (Y) radius = DomeRadius * sdthis (taller ellipse, same footprint)
GameConfig.ShieldDuration       = 50    -- seconds before shield expires and must be reactivated

-- Buff Shop
GameConfig.BuffShopItems = {
	{id = "shield",     name = "Energy Shield",     desc = "-50% damage for 60s",      duration = 60,  coinCost = 150, gemCost = 0},
	{id = "highjump",   name = "Super Jump",        desc = "Moon-like jump for 45s",   duration = 45,  coinCost = 100, gemCost = 0},
	{id = "speed",      name = "Super Speed",       desc = "2x walk speed for 60s",    duration = 60,  coinCost = 120, gemCost = 0},
	{id = "invuln",     name = "Invulnerability",   desc = "Immune to damage for 15s", duration = 15,  coinCost = 0,   gemCost = 5},
	{id = "invis",      name = "Invisibility",      desc = "Hidden from creatures 30s", duration = 30,  coinCost = 0,   gemCost = 3},
	{id = "swap",       name = "Swap Places",       desc = "Teleport to random player", duration = 0,  coinCost = 200, gemCost = 0},
	{id = "lowgrav",    name = "Low Gravity",       desc = "Moon-like float for 40s",   duration = 40,  coinCost = 90,  gemCost = 0},
	{id = "regen",      name = "Health Regen",      desc = "Regen 2 HP/s for 45s",      duration = 45,  coinCost = 130, gemCost = 0},
	{id = "doublejump", name = "Double Jump",       desc = "Jump again in mid-air 40s", duration = 40,  coinCost = 110, gemCost = 0},
	{id = "glide",      name = "Feather Fall",      desc = "Slow fall for 50s",         duration = 50,  coinCost = 95,  gemCost = 0},
	{id = "xpboost",    name = "XP Boost",          desc = "2x XP gain for 120s",       duration = 120, coinCost = 180, gemCost = 2},
	{id = "coinboost",  name = "Coin Magnet",       desc = "2x income for 90s",         duration = 90,  coinCost = 160, gemCost = 1},
	{id = "haste",      name = "Haste",             desc = "1.5x walk speed for 50s",   duration = 50,  coinCost = 80,  gemCost = 0},
	{id = "giant",      name = "Giant",             desc = "2x size for 30s",           duration = 30,  coinCost = 140, gemCost = 0},
	{id = "glow",       name = "Radiant",           desc = "Glow aura for 60s",         duration = 60,  coinCost = 0,   gemCost = 4},
	{id = "antifall",   name = "Featherfeet",       desc = "No fall damage for 45s",    duration = 45,  coinCost = 100, gemCost = 0},
	{id = "swimspeed",  name = "Dolphin",           desc = "3x swim speed for 45s",     duration = 45,  coinCost = 85,  gemCost = 0},
	{id = "lucky",      name = "Lucky Charm",       desc = "Better capture odds 90s",   duration = 90,  coinCost = 0,   gemCost = 6},
}

-- Cosmetic Shop
GameConfig.CosmeticItems = {
	-- Trails
	{id = "trail_fire",     slot = "trail", name = "Fire Trail",      coinCost = 300,  gemCost = 0},
	{id = "trail_ice",      slot = "trail", name = "Ice Trail",       coinCost = 300,  gemCost = 0},
	{id = "trail_rainbow",  slot = "trail", name = "Rainbow Trail",   coinCost = 0,    gemCost = 10},
	{id = "trail_shadow",   slot = "trail", name = "Shadow Trail",    coinCost = 0,    gemCost = 8},
	{id = "trail_nature",   slot = "trail", name = "Nature Trail",    coinCost = 350,  gemCost = 0},
	{id = "trail_poison",   slot = "trail", name = "Poison Trail",    coinCost = 0,    gemCost = 9},
	{id = "trail_void",     slot = "trail", name = "Void Trail",      coinCost = 0,    gemCost = 11},
	{id = "trail_sunset",   slot = "trail", name = "Sunset Trail",    coinCost = 350,  gemCost = 0},
	{id = "trail_candy",    slot = "trail", name = "Candy Trail",     coinCost = 0,    gemCost = 8},
	{id = "trail_galaxy",   slot = "trail", name = "Galaxy Trail",     coinCost = 0,    gemCost = 12},
	-- Auras
	{id = "aura_flame",     slot = "aura",  name = "Flame Aura",      coinCost = 500,  gemCost = 0},
	{id = "aura_electric",  slot = "aura",  name = "⚡ Electric Aura", coinCost = 500,  gemCost = 0},
	{id = "aura_divine",    slot = "aura",  name = "✨ Divine Aura",   coinCost = 0,    gemCost = 15},
	{id = "aura_nature",    slot = "aura",  name = "Nature Aura",      coinCost = 500,  gemCost = 0},
	{id = "aura_void",      slot = "aura",  name = "Void Aura",       coinCost = 0,    gemCost = 14},
	{id = "aura_ice",       slot = "aura",  name = "Ice Aura",        coinCost = 500,  gemCost = 0},
	{id = "aura_poison",    slot = "aura",  name = "Poison Aura",     coinCost = 0,    gemCost = 10},
	{id = "aura_sakura",    slot = "aura",  name = "Sakura Aura",     coinCost = 0,    gemCost = 12},
	{id = "aura_star",      slot = "aura",  name = "Star Aura",       coinCost = 0,    gemCost = 13},
	-- Name Colors
	{id = "name_gold",      slot = "nameColor", name = "Gold Name",    coinCost = 200,  gemCost = 0},
	{id = "name_red",       slot = "nameColor", name = "Red Name",     coinCost = 200,  gemCost = 0},
	{id = "name_rainbow",   slot = "nameColor", name = "Rainbow Name", coinCost = 0,    gemCost = 12},
	{id = "name_blue",      slot = "nameColor", name = "Blue Name",    coinCost = 200,  gemCost = 0},
	{id = "name_green",     slot = "nameColor", name = "Green Name",   coinCost = 200,  gemCost = 0},
	{id = "name_purple",    slot = "nameColor", name = "Purple Name",  coinCost = 200,  gemCost = 0},
	{id = "name_cyan",      slot = "nameColor", name = "Cyan Name",    coinCost = 200,  gemCost = 0},
	{id = "name_pink",      slot = "nameColor", name = "Pink Name",    coinCost = 200,  gemCost = 0},
	{id = "name_orange",    slot = "nameColor", name = "Orange Name",  coinCost = 200,  gemCost = 0},
	{id = "name_white",     slot = "nameColor", name = "White Name",   coinCost = 0,    gemCost = 6},
	{id = "name_lime",      slot = "nameColor", name = "Lime Name",    coinCost = 200,  gemCost = 0},
	{id = "name_coral",     slot = "nameColor", name = "Coral Name",   coinCost = 200,  gemCost = 0},
}

-- Base Exterior Shop (purchase theme; equipping applies theme to walls, stairs, etc.)
-- Full themes: Haunted House, Retro Arcade
-- Color themes: single-color for backwall, front left/right walls, stairs (all floors)
GameConfig.BaseExteriorItems = {
	-- Full themes (500 coins each)
	{id = "HauntedHouse", name = "Haunted House", desc = "Spooky base with walls, stairs & lanterns", coinCost = 500, gemCost = 0},
	{id = "RetroArcade",   name = "Retro Arcade",   desc = "Neon lights & arcade vibes on all walls & stairs", coinCost = 500, gemCost = 0},
	-- Color themes (500 coins each) - entire base: backwall, front left/right walls, stairs
	{id = "exterior_red",    name = "Red Base",    desc = "Backwall, walls & stairs in red",   coinCost = 500, gemCost = 0, color = Color3.fromRGB(200, 60, 60)},
	{id = "exterior_blue",   name = "Blue Base",   desc = "Backwall, walls & stairs in blue",  coinCost = 500, gemCost = 0, color = Color3.fromRGB(60, 100, 200)},
	{id = "exterior_green",  name = "Green Base",  desc = "Backwall, walls & stairs in green", coinCost = 500, gemCost = 0, color = Color3.fromRGB(60, 180, 80)},
	{id = "exterior_yellow", name = "Yellow Base", desc = "Backwall, walls & stairs in yellow",coinCost = 500, gemCost = 0, color = Color3.fromRGB(220, 200, 60)},
	{id = "exterior_purple", name = "Purple Base", desc = "Backwall, walls & stairs in purple",coinCost = 500, gemCost = 0, color = Color3.fromRGB(140, 80, 200)},
	{id = "exterior_orange", name = "Orange Base", desc = "Backwall, walls & stairs in orange",coinCost = 500, gemCost = 0, color = Color3.fromRGB(230, 140, 50)},
}

-- Base Color Shop (walls, stairs, points, combiner, recycler - not glass)
-- Each item: id, name, color (Color3), coinCost, gemCost
GameConfig.BaseColorItems = {
	{id = "base_red",    name = "Red",    color = Color3.fromRGB(200, 60, 60),   coinCost = 300, gemCost = 0},
	{id = "base_blue",   name = "Blue",   color = Color3.fromRGB(60, 100, 200),  coinCost = 300, gemCost = 0},
	{id = "base_green",  name = "Green",  color = Color3.fromRGB(60, 180, 80),   coinCost = 300, gemCost = 0},
	{id = "base_yellow", name = "Yellow", color = Color3.fromRGB(220, 200, 60),  coinCost = 300, gemCost = 0},
	{id = "base_purple", name = "Purple", color = Color3.fromRGB(140, 80, 200),  coinCost = 300, gemCost = 0},
	{id = "base_orange", name = "Orange", color = Color3.fromRGB(230, 140, 50),  coinCost = 300, gemCost = 0},
}

-- Floor 4 Decor System — creature statue placement costs (gold sink, scales by rarity)
GameConfig.DecorPointsPerFloor4  = 6       -- customization points on Floor 4
GameConfig.DecorCostByRarity = {
	Common    = 500,
	Uncommon  = 1000,
	Rare      = 2500,
	Epic      = 5000,
	Legendary = 10000,
}

-- Gym Battle System — Floor 4 personal arena (visitors battle owner's battle team)
GameConfig.GymBattleTickSpeed    = 1.2    -- seconds between combat ticks (matches arena)
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
GameConfig.BadlandsMinPlayers           = 4     -- min to start a run
GameConfig.BadlandsQueueTimeout         = 60    -- seconds before starting with < max players
GameConfig.BadlandsRunDuration          = 600   -- 10 minutes (hard timer — expelled with only favorite)
GameConfig.BadlandsHardDeadline         = 600   -- 10 minutes (hard collapse — same as run duration).
GameConfig.BadlandsExtractionActivateAt = 420   -- 7 minutes (extraction points go live)
GameConfig.BadlandsSpawnShieldDuration  = 30    -- seconds of PvP immunity on entry

-- Broker NPC (Arena Hub): optional extra rotation (degrees) applied after spawn placement.
-- Use if the mesh still appears flipped after fixing PrimaryPart in Studio (e.g. pitch = -90).
GameConfig.BrokerNPCExtraRotationDegrees = { pitch = 90, yaw = 0, roll = 0 }

-- Badlands: Bag
GameConfig.BadlandsBagSlots             = 10    -- bag capacity
GameConfig.BadlandsLootBagDespawnTime   = 60    -- seconds before dropped bag despawns
GameConfig.BadlandsLootBagBeaconRange   = 200   -- visible distance (studs)

-- Badlands: Creature Spawning
-- ALL Badlands creatures are Gold/Legend variant, 1.5–2x scale, stat-boosted.
-- Every rarity can spawn (Common through Legendary) but they are ALL elite versions.
GameConfig.BadlandsInitialSpawnCount    = 20    -- creatures spawned on run start
GameConfig.BadlandsSpawnInterval        = 8     -- seconds between new spawns
GameConfig.BadlandsMaxCreatures         = 40    -- creature cap in zone
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

-- Badlands: Zone Collapse
GameConfig.BadlandsOuterCollapseTime    = 480   -- 8 min: outer ring collapses
GameConfig.BadlandsMidCollapseTime      = 540   -- 9 min: mid ring collapses
GameConfig.BadlandsInnerCollapseTime    = 720   -- 12 min: inner ring collapses
GameConfig.BadlandsCollapseDPS          = 5     -- HP/sec in collapsed zones
GameConfig.BadlandsCollapseTransition   = 30    -- seconds for ring to fully collapse

-- Badlands: Extraction
GameConfig.BadlandsExtractionTime       = 15    -- seconds to channel
GameConfig.BadlandsExtractionMinTime    = 8     -- hard floor with run power reduction
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
		coinCost = 150,
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
		coinCost = 800,
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
		coinCost = 3500,
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
		coinCost = 12000,
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
		coinCost = 50000,
		robuxCost = 999,
		productId = 0,
		pool = {
			{ rarity = "Mythic",    weight = GameConfig.EggGod_MythicPct    },
			{ rarity = "Legendary", weight = GameConfig.EggGod_LegendaryPct },
		},
	},
}

return GameConfig



