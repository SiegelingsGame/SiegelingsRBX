--[[
	GameConfigData.lua
	ReplicatedStorage/Modules/GameConfigData
	Actual config data. Required lazily by GameConfig to avoid recursive require.
]]

local GameConfig = {}

-- Day / Night Cycle (Lighting.ClockTime)
GameConfig.DayNightCycleEnabled = true   -- true = enable cycle; false = use default Roblox lighting
GameConfig.DayNightCycleSeconds = 180    -- real seconds per full day (24 in-game hours); changeable
GameConfig.NightStartHour = 18          -- ClockTime >= this = night (6 PM)
GameConfig.NightEndHour = 6              -- ClockTime < this = night (until 6 AM)
-- Night spawn variants: Common/Uncommon → Silver chance; Rare+ → Gold chance (0–1)
GameConfig.NightSpawnSilverChance = 0.35  -- chance for Common/Uncommon at night
GameConfig.NightSpawnGoldChance = 0.25    -- chance for Rare+ at night
-- World creatures with evolutions: at night randomly evolve (base→evolved), at dawn devolve
GameConfig.NightWorldEvolutionChance   = 0.35  -- per creature per check (base form with evolvesTo)
GameConfig.NightWorldEvolutionInterval = 8     -- seconds between evolution checks
GameConfig.NightSpawnBonus             = 100   -- extra max world creatures at night (for rare/night spawns)

-- Debug / Dev toggles (set true for testing)
GameConfig.SpawnOnlyCreaturesWithModels = true  -- true = only spawn creatures that have models in CreatureModels
GameConfig.DebugCoins1000 = false               -- true = new players start with 1000 coins
GameConfig.DebugFloor2Level2 = false            -- true = Floor 2 requires player level 2 (instead of 5)
GameConfig.DebugDoubleSpeed = false             -- true = player WalkSpeed is 32 (2x default)
GameConfig.CombinerRecyclerPromptAllPlots = true -- true = add E prompts to Combiner/Recycler on ALL plots (for testing; set false for release)

-- Economy
GameConfig.StartingCoins       = 1000
GameConfig.IncomeTickSeconds   = 10
GameConfig.MaxInventorySize    = 50
GameConfig.EggCost             = 50
GameConfig.MaxIncomeSlots      = 6   -- matches IncomePoints on plot
GameConfig.MaxDefenseSlots     = 6   -- matches DefensePoints on plot (auto-detected too)

-- Leveling (creature levels; max level depends on evolution stage)
GameConfig.MaxCreatureLevel    = 10   -- legacy/fallback
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
GameConfig.StatGainPerLevel    = 0.08 -- base % gain per level (then scaled by stat rank)
-- Rank-based level scaling: highest base stat grows fastest, then next, down to lowest (rank 1 = biggest stat)
GameConfig.StatGainByRank      = { 1.5, 1.25, 1.0, 0.75 }  -- multipliers for rank 1..4 (1=fastest growth)
-- Rarity amplifies effective stats (higher rarity = stronger when leveled)
GameConfig.RarityStatMultipliers = { Common = 1.0, Uncommon = 1.05, Rare = 1.1, Epic = 1.15, Legendary = 1.25 }

-- Player Leveling (separate from creature levels — gates features & floors)
GameConfig.PlayerMaxLevel         = 50
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
GameConfig.Floor3LevelReq         = 5     -- player level required

-- Evolution & Combine (monster duplication / variant tiers)
GameConfig.EvolutionMinLevel      = 1      -- level required for 1st evolution (base form)
GameConfig.EvolutionMinLevel2     = 1      -- level required for 2nd evolution (evolved form)
GameConfig.CombineCost            = 0      -- gold cost to combine 3 into next variant (0 = free)
GameConfig.RecyclerDuplicateCount = 3      -- min same-creature duplicates to trade for 1 egg (1 rarity tier higher)
-- Egg hatch time (minutes) by creature level inside the egg: level 1→20min, 2→30, 3→60, 4→120, 5→600, 6+→300
GameConfig.EggHatchMinutesByLevel = { 20, 30, 60, 120, 600, 300 }
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

-- Loading screen: wait for creatures + models before allowing play
GameConfig.LoadingSpawnTarget  = 80   -- creatures to spawn before "ready" (initial burst is 50; this ensures good fill)
GameConfig.LoadingMinWait      = 12   -- minimum seconds loading screen shows (allows model replication)
GameConfig.LoadingMaxWait      = 60   -- max seconds before allowing play anyway (safety timeout)

-- Spawning (SpawnPoints should stay full; common creatures prioritized)
-- Reduced from 200 to 150 for performance (night bonus +100 still applies)
GameConfig.MaxWorldCreatures   = 150
GameConfig.SpawnIntervalMin    = 0.5   -- faster spawns so SpawnPoints stay full
GameConfig.SpawnIntervalMax    = 1.5
GameConfig.SpawnsPerCycle      = 4     -- spawn this many per cycle when under 50% capacity (else 1-2)
GameConfig.SpawnPointFillTarget = 0.8  -- run dungeon spawns only when creature count is above this fraction of max
GameConfig.CreatureDespawnTime = 180
GameConfig.SpawnRadius         = 200
GameConfig.SpawnHeightOffset   = 3
GameConfig.FlyingHoverHeight   = 10   -- studs above ground for flying creatures (player model height)
GameConfig.SpawnPointSpread    = 25     -- studs radius around a biome SpawnPoint
GameConfig.DungeonPointSpread  = 15     -- studs radius around a DungeonPoint (tighter for dungeon encounters)
GameConfig.BossPointSpread     = 10     -- studs radius around a BossPoint (tight cluster for boss arena)
GameConfig.DungeonSpawnCount   = {1, 2} -- min/max creatures per DungeonPoint per cycle
GameConfig.BossRespawnTime     = 300    -- seconds before a boss can respawn at the same BossPoint

-- Capture (creatures must be fainted first)
GameConfig.CaptureRange        = 30
GameConfig.CaptureHoldTime     = 0
GameConfig.CaptureAnimationTime = 2.5   -- card throw + warp animation duration
GameConfig.CaptureGracePeriod   = 3     -- seconds to return when out of range before capture fails
GameConfig.CaptureCooldown     = 0.5
GameConfig.FaintDuration       = 5   -- seconds a fainted world creature stays before despawning (unclaimed = disappears so others can spawn)

-- Base
GameConfig.BasePlotSize        = 60
GameConfig.MaxBaseCreatures    = 20
GameConfig.BaseCreatureSpacing = 8

-- Base plots
GameConfig.MaxPlots            = 4
GameConfig.PlotSize            = 50
GameConfig.CreaturesPerRow     = 5
GameConfig.CreatureSpacing     = 8

-- Raiding
GameConfig.RaidCooldown        = 120
GameConfig.RaidDuration        = 30
GameConfig.MaxStealPerRaid     = 1
GameConfig.RaidProtectionTime  = 60
GameConfig.StealChanceBase     = 0.3

-- AI Raids (wild creatures attack bases)
GameConfig.AIRaidInterval      = 90   -- seconds between AI raids
GameConfig.AIRaidPackSize      = {1, 2}  -- min/max raiders
GameConfig.AIRaidDefenseBreakChance = 0.15  -- 15% chance to free a defense creature per attack (when they defeat one)
GameConfig.AIRaidIncomeStealChance  = 0.08  -- 8% chance to steal income creature after defenses down
GameConfig.AIRaidDuration      = 18   -- seconds the raid lasts
GameConfig.AIRaidAttackInsideRadius = 55    -- raiders must be within this many studs of plot center to attack (stops outranging from outside base)
GameConfig.AIRaidDoorReachRadius     = 10   -- studs; raiders path to door (Ramp/PlotCenter) first; within this = "at door"
GameConfig.AIRaidCenterReachRadius   = 14   -- studs; after door, raiders path to plot center (up ramp); within this = "at center", then may engage targets

-- Dungeon events
GameConfig.DungeonSpawnInterval = 120  -- seconds between dungeon spawns
GameConfig.DungeonDuration      = 90   -- seconds before dungeon despawns
GameConfig.DungeonCreatureCount = {2, 4} -- min/max legendary creatures
GameConfig.DungeonSpawnRadius   = 250  -- distance from center to spawn dungeons

-- Arena presence buff
GameConfig.ArenaPresenceBuff    = 0.10 -- +10% stats when owner stands on arena

-- Arena / Battle
GameConfig.ArenaRoundInterval  = 60
GameConfig.MaxBattleTeamSize   = 9
GameConfig.MinBattleTeamSize   = 1
GameConfig.BattleTickSpeed     = 1.2
GameConfig.GrowthPerWin        = 0.05
GameConfig.MaxGrowth           = 3.0
GameConfig.ArenaExclusionRadius = 80  -- studs around arena center where creatures cannot spawn/be targeted

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

-- Elemental weaknesses (Fire→Ice→Earth→Wind→Fire cycle; Shadow/Lightning neutral)
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
GameConfig.CompanionBaseDamage  = 15    -- multiplied by creature attack stat / 10
GameConfig.CompanionFollowDist  = 6
GameConfig.CompanionFollowSpeed = 28   -- used as catch-up speed when companion is far; normal follow matches player WalkSpeed
GameConfig.CompanionFollowCatchUpDist = 12  -- when distance to follow point exceeds this (studs), companion starts speeding up
GameConfig.CompanionFollowSpeedSmooth  = 10  -- how fast applied speed lerps toward target (higher = snappier, lower = smoother); avoids choppy speed jumps
GameConfig.CompanionTargetRange = 40    -- range for manual target selection
GameConfig.CompanionRespawnCD   = 30    -- seconds before companion respawns after fainting

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
-- Each level: gold cost, creature requirements by rarity (Common, Uncommon, Rare, Epic, Legendary).
-- Rewards scale: passive gold per tick, world damage multiplier, max health bonus (cumulative).
GameConfig.RebirthPassiveGoldPerLevel   = 2   -- extra gold per income tick per rebirth level
GameConfig.RebirthDamageMultPerLevel    = 0.05 -- +5% world damage per level (1 + level * this)
GameConfig.RebirthHealthBonusPerLevel  = 15   -- flat +HP to PlayerMaxHealth per rebirth level
GameConfig.RebirthMaxLevel             = 10   -- max rebirth level (config length can extend this)
GameConfig.RebirthLevels = {
	-- Level 1: 5k gold, 3 Common
	{ gold = 5000,  creatures = { Common = 3 } },
	-- Level 2: 15k gold, 5 Common, 2 Uncommon
	{ gold = 15000, creatures = { Common = 5, Uncommon = 2 } },
	-- Level 3: 40k gold, 8 Common, 4 Uncommon, 1 Rare
	{ gold = 40000, creatures = { Common = 8, Uncommon = 4, Rare = 1 } },
	-- Level 4: 100k gold, 12 Common, 6 Uncommon, 3 Rare
	{ gold = 100000, creatures = { Common = 12, Uncommon = 6, Rare = 3 } },
	-- Level 5: 250k gold, 15 Common, 10 Uncommon, 5 Rare, 1 Epic
	{ gold = 250000, creatures = { Common = 15, Uncommon = 10, Rare = 5, Epic = 1 } },
	-- Level 6: 500k gold, 20 Common, 12 Uncommon, 8 Rare, 3 Epic
	{ gold = 500000, creatures = { Common = 20, Uncommon = 12, Rare = 8, Epic = 3 } },
	-- Level 7: 1M gold, 25 Common, 15 Uncommon, 10 Rare, 5 Epic, 1 Legendary
	{ gold = 1000000, creatures = { Common = 25, Uncommon = 15, Rare = 10, Epic = 5, Legendary = 1 } },
	-- Level 8: 2.5M gold, 30 Common, 18 Uncommon, 12 Rare, 7 Epic, 2 Legendary
	{ gold = 2500000, creatures = { Common = 30, Uncommon = 18, Rare = 12, Epic = 7, Legendary = 2 } },
	-- Level 9: 5M gold, 35 Common, 22 Uncommon, 15 Rare, 10 Epic, 3 Legendary
	{ gold = 5000000, creatures = { Common = 35, Uncommon = 22, Rare = 15, Epic = 10, Legendary = 3 } },
	-- Level 10: 10M gold, 40 Common, 25 Uncommon, 18 Rare, 12 Epic, 5 Legendary
	{ gold = 10000000, creatures = { Common = 40, Uncommon = 25, Rare = 18, Epic = 12, Legendary = 5 } },
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
GameConfig.DomeHeightMultiplier = 1.5   -- vertical (Y) radius = DomeRadius * this (taller ellipse, same footprint)
GameConfig.ShieldDuration       = 50    -- seconds before shield expires and must be reactivated

-- Buff Shop
GameConfig.BuffShopItems = {
	{id = "shield",     name = "Energy Shield",   desc = "-50% damage for 60s",     duration = 60,  coinCost = 150, gemCost = 0},
	{id = "highjump",   name = "Super Jump",       desc = "3x jump power for 45s",   duration = 45,  coinCost = 100, gemCost = 0},
	{id = "speed",      name = "? Super Speed",       desc = "2x walk speed for 60s",   duration = 60,  coinCost = 120, gemCost = 0},
	{id = "invuln",     name = "Invulnerability",   desc = "Immune to damage for 15s",duration = 15,  coinCost = 0,   gemCost = 5},
	{id = "invis",      name = "Invisibility",      desc = "Hidden from creatures 30s",duration = 30, coinCost = 0,   gemCost = 3},
	{id = "swap",       name = "Swap Places",       desc = "Teleport to random player",duration = 0,  coinCost = 200, gemCost = 0},
}

-- Cosmetic Shop
GameConfig.CosmeticItems = {
	-- Trails
	{id = "trail_fire",     slot = "trail", name = "Fire Trail",      coinCost = 300,  gemCost = 0},
	{id = "trail_ice",      slot = "trail", name = "Ice Trail",       coinCost = 300,  gemCost = 0},
	{id = "trail_rainbow",  slot = "trail", name = "Rainbow Trail",   coinCost = 0,    gemCost = 10},
	{id = "trail_shadow",   slot = "trail", name = "Shadow Trail",    coinCost = 0,    gemCost = 8},
	-- Auras
	{id = "aura_flame",     slot = "aura",  name = "Flame Aura",     coinCost = 500,  gemCost = 0},
	{id = "aura_electric",  slot = "aura",  name = "? Electric Aura",   coinCost = 500,  gemCost = 0},
	{id = "aura_divine",    slot = "aura",  name = "? Divine Aura",     coinCost = 0,    gemCost = 15},
	-- Name Colors
	{id = "name_gold",      slot = "nameColor", name = "Gold Name",   coinCost = 200,  gemCost = 0},
	{id = "name_red",       slot = "nameColor", name = "Red Name",    coinCost = 200,  gemCost = 0},
	{id = "name_rainbow",   slot = "nameColor", name = "Rainbow Name",coinCost = 0,    gemCost = 12},
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
