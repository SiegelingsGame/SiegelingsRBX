# Monster Siege — Game Documentation

A Roblox creature-collection and base-defense game. Players capture creatures in the world, assign them to income/defense/battle slots at their base, fight in arena and PvP battles, raid other players, and evolve/combine creatures. This document describes the game, scripts, function calls, variables, and data structures.

---

## 1. Game Overview

- **Title:** Monster Siege  
- **Genre:** Creature collection, base building, PvE/PvP combat  
- **Flow:** Join → choose starter → get auto-assigned base plot → capture creatures → assign to income/defense/battle → earn coins, level creatures and player → unlock Floor 2/3, arena, PvP, raids, dungeons, AI raids.

**Core systems:**

- **Creatures:** 90 creatures across 6 elements (Fire, Ice, Wind, Earth, Shadow, Lightning), 5 classes (Bruiser, Mage, Guardian, Assassin, Support), rarities Common→Legendary, variants Normal/Silver/Gold/Legend (combine 3→1).
- **Base:** Plot with income slots (coins per tick), defense slots (turrets), battle team (3×3 grid, max 5 for arena/PvP). Up to 3 floors (buy Floor 2/3 with coins + level).
- **Combat:** Arena (periodic king-of-the-hill), PvP 1v1 (challenge nearby player), focus bar and special attacks (burn, earth debuff, wind focus drain).
- **World:** Biomes with SpawnPoints, DungeonPoints, BossPoints; creature AI (pack, lone, gentle, aggressive, skittish); companion (favorite creature) follows and attacks.
- **Economy:** Coins (income, capture cost, sell, shops), Gems (premium); Buff Shop, Cosmetic Shop, Egg Shop (hatch creatures).

---

## 2. Architecture

- **Server entry:** `MainServer.lua` (ServerScriptService) — single entry; creates all remotes, requires server modules, initializes systems, and wires remote handlers.
- **Server modules:** ServerScriptService (e.g. `PlayerDataManager`, `CreatureAI`, `CreatureSpawner`, `CaptureSystem`, `RaidSystem`, `ArenaSystem`, etc.).
- **Shared modules:** ReplicatedStorage/Modules — `GameConfig` (proxy that lazy-loads `GameConfigData`), `GameConfigData` (actual config table), `CreatureData` (and any other shared libs).
- **Remotes:** ReplicatedStorage/Events — created by MainServer; clients use these to call server and receive updates.
- **Client scripts:** StarterPlayerScripts (LocalScripts) — HUD, capture, inventory/UI, combat, shops, friends, leaderboard, etc.

**Initialization order (server):**  
`PlayerDataManager.Init()` → `CreatureAI.Init(LaserDoorSystem)` → `CreatureSpawner.Init(CreatureAI)` → then Capture, Raid, Trade, BasePlacement, FavoriteCreature, Arena, Leaderboard, PvP, AIRaid, Dungeon, WorldCreatureHP, PlayerCombat, BuffShop, Cosmetic, EggShop, LaserDoor, EvolutionCombine, **CombinerRecyclerSystem**; finally `BaseIncomeSystem` (or inline income loop).

---

## 3. Remote Events & Remote Functions

All live under `ReplicatedStorage.Events`. Created with `makeEvent(name)` / `makeFunc(name)` in MainServer.

| Name | Type | Direction | Purpose |
|------|------|-----------|---------|
| **Inventory & base** | | | |
| GetInventory | RemoteFunction | C→S | Returns full player data (coins, gems, inventory, baseSlots, defenseSlots, favoriteUid, battleTeam, plotId, stats, activeBuffs, cosmetics, ownedFloors, playerLevel). |
| AssignToBase | RemoteEvent | C→S | Assign creature (uid) to income slot. |
| AssignToDefense | RemoteEvent | C→S | Assign creature (uid) to defense slot. |
| SetFavorite | RemoteEvent | C→S | Set or clear favorite companion (uid or nil/""). |
| AssignToBattle | RemoteEvent | C→S | Assign creature (uid, slotIndex) to battle team (requires Floor 2). |
| RemoveFromBattle | RemoteEvent | C→S | Remove creature (uid) from battle team. |
| GetBattleTeam | RemoteFunction | C→S | Returns battle team with slots, synergies, element/class counts. |
| OpenCombiner | RemoteEvent | S→C | Open combine UI at MCombiner (plot interact). |
| OpenRecycler | RemoteEvent | S→C | Open recycler UI at MRecycler (plot interact). |
| **Companion** | | | |
| CompanionSpawned | RemoteEvent | S→C | Server tells client companion model (e.g. for grow-from-beneath). |
| ToggleAttackMode | RemoteEvent | C→S | Toggle companion attack/passive. |
| SetCompanionTarget | RemoteEvent | C→S | Set companion target (creatureModel). |
| ClearCompanionTarget | RemoteEvent | C→S | Clear companion target. |
| **Economy** | | | |
| IncomeReceived | RemoteEvent | S→C | Income tick payout (amount). |
| CoinsUpdate | RemoteEvent | S→C | Coins balance update. |
| **Capture** | | | |
| CaptureRequest | RemoteEvent | C→S | Start capture (player, creatureModel). |
| CaptureStart | RemoteEvent | S→C | Capture started. |
| CaptureSuccess | RemoteEvent | S→C | Capture succeeded. |
| CaptureCancel | RemoteEvent | S→C | Capture cancelled. |
| CaptureFail | RemoteEvent | S→C | Capture failed. |
| CaptureOutOfRange | RemoteEvent | S→C | Player moved out of range. |
| AssignCaptured | RemoteEvent | S→C | Assign newly captured creature (e.g. to inventory). |
| **AI Raids** | | | |
| AIRaidStart | RemoteEvent | S→C | AI raid started. |
| AIRaidEnd | RemoteEvent | S→C | AI raid ended. |
| AIRaidAlert | RemoteEvent | S→C | AI raid alert. |
| **Dungeons** | | | |
| DungeonSpawned | RemoteEvent | S→C | Dungeon event spawned. |
| DungeonDespawned | RemoteEvent | S→C | Dungeon despawned. |
| **Raid (PvP base)** | | | |
| RaidRequest | RemoteEvent | C→S | Request raid. |
| RaidStart | RemoteEvent | S→C | Raid started. |
| RaidEnd | RemoteEvent | S→C | Raid ended. |
| CreatureStolen | RemoteEvent | S→C | A creature was stolen. |
| GetRaidTargets | RemoteFunction | C→S | Get raidable targets. |
| **Arena** | | | |
| ArenaAnnounce | RemoteEvent | S→C | Arena announcement. |
| BattleStart | RemoteEvent | S→C | Battle started. |
| BattleEnd | RemoteEvent | S→C | Battle ended. |
| BattleKill | RemoteEvent | S→C | Kill in battle. |
| BattleTeamsPlaced | RemoteEvent | S→C | Teams placed. |
| GetBattleInfo | RemoteFunction | C→S | Battle info. |
| **PvP (1v1)** | | | |
| RequestPvPBattle | RemoteEvent | C→S | Request PvP. |
| PvPBattleStart | RemoteEvent | S→C | PvP battle started. |
| PvPBattleEnd | RemoteEvent | S→C | PvP battle ended. |
| PvPBattleReject | RemoteEvent | S→C | PvP rejected. |
| PvPChallengeNotice | RemoteEvent | S→C | Challenge notice. |
| PvPRevivePrompt | RemoteEvent | S→C | Revive prompt. |
| PvPReviveSuccess | RemoteEvent | S→C | Revive success. |
| PvPReviveWith | RemoteEvent | S→C | Revive with (coins/gems). |
| PvPChallengeInvite | RemoteEvent | S→C | Challenge invite. |
| PvPAcceptChallenge | RemoteEvent | C→S | Accept. |
| PvPDeclineChallenge | RemoteEvent | C→S | Decline. |
| **Player combat** | | | |
| PlayerAttack | RemoteEvent | C→S | Player attack. |
| PlayerAttackFX | RemoteEvent | S→C | Attack FX. |
| **Shops** | | | |
| BuyBuff | RemoteFunction | C→S | Buy buff. |
| BuyCosmetic | RemoteFunction | C→S | Buy cosmetic. |
| EquipCosmetic | RemoteFunction | C→S | Equip cosmetic. |
| BuyEgg | RemoteFunction | C→S | Buy egg. |
| EggResult | RemoteEvent | S→C | Egg hatch result. |
| **Friends / laser door** | | | |
| AddBaseFriend | RemoteEvent | C→S | Add friend (friendUserId). |
| RemoveBaseFriend | RemoteEvent | C→S | Remove friend. |
| GetFriendsList | RemoteFunction | C→S | Get friends list. |
| **Trading** | | | |
| TradeRequest | RemoteEvent | C→S | targetUserId. |
| TradeInvite | RemoteEvent | S→C | { tradeId, fromUserId, fromName }. |
| TradeResponse | RemoteEvent | C→S | tradeId, acceptBool. |
| TradeUpdateOffer | RemoteEvent | C→S | tradeId, offeredUids[]. |
| TradeAccept | RemoteEvent | C→S | tradeId. |
| TradeCancel | RemoteEvent | C→S | tradeId. |
| TradeState | RemoteEvent | S→C | Full trade state. |
| GetPublicProfile | RemoteFunction | C→S | targetUserId → { name, favorite, ... }. |
| **Leaderboard** | | | |
| GetLeaderboardData | RemoteFunction | C→S | Leaderboard data. |
| **Evolution & combine** | | | |
| EvolveCreature | RemoteEvent | C→S | uid. |
| EvolveResult | RemoteEvent | S→C | success, newCreatureId or errorMessage. |
| CombineCreatures | RemoteEvent | C→S | { uid1, uid2, uid3 }. |
| CombineResult | RemoteEvent | S→C | success, newUid or errorMessage. |
| **Base / profile** | | | |
| SellCreature | RemoteFunction | C→S | uid → (ok, coins). |
| BuyFloor | RemoteFunction | C→S | floorNum → (ok, msg). |
| GoHome | RemoteEvent | C→S | Teleport to base. |
| GetProfile | RemoteFunction | C→S | Profile (level, XP, coins, stats, etc.). |
| PlayerLevelUp | RemoteEvent | S→C | Level up (newLevel). |
| PlayerXPGained | RemoteEvent | S→C | XP gained. |
| **Launch** | | | |
| SelectStarter | RemoteEvent | C→S | starterId. |
| SelectPlot | RemoteFunction | C→S | plotId (no-op; plots auto-assigned). |

---

## 4. Data Structures

### 4.1 Player data (server; from PlayerDataManager)

Stored per player (DataStore key `Player_<userId>`). Default shape:

```lua
{
  coins            = number,        -- starting from GameConfig.StartingCoins (or 1000 if DebugCoins1000)
  gems             = number,
  inventory        = { CreatureEntry, ... },  -- see below
  baseSlots        = { uid, ... },             -- income slot UIDs (max from GameConfig / floors)
  defenseSlots     = { uid, ... },             -- defense slot UIDs
  favoriteUid      = string | nil,              -- companion
  battleTeam       = { [slotIndex] = uid },     -- 1–9, number keys; max 5 filled
  stats            = {
    totalCaptured  = number,
    totalRaids     = number,
    arenaWins      = number,
    arenaLosses    = number,
    arenaWinStreak = number,
    arenaMaxStreak = number,
    totalIncome    = number,
  },
  settings         = {},
  plotId           = number,       -- 0 = none
  baseCreaturePositions = {},
  friendsList      = { userId, ... },  -- laser door access
  activeBuffs      = { [buffId] = { expiresAt = number, ... }, ... },
  cosmetics        = { owned = { [id] = true }, equipped = { trail = "", aura = "", nameColor = "" } },
  playerLevel      = number,
  playerXP         = number,
  ownedFloors      = { 1, ... },   -- e.g. {1}, {1,2}, {1,2,3}
}
```

### 4.2 Creature entry (inventory element)

```lua
{
  id     = string,   -- creature id from CreatureData (e.g. "firsky")
  uid    = string,   -- unique instance id (GUID)
  level  = number,   -- 1..GameConfig.MaxCreatureLevel
  xp     = number,
  variant = string,  -- "Normal" | "Silver" | "Gold" | "Legend"
}
```

### 4.3 Creature definition (CreatureData.Creatures / GetById)

```lua
{
  id           = string,   -- e.g. "firsky"
  displayName  = string,
  rarity       = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary",
  element      = "Fire" | "Ice" | "Wind" | "Earth" | "Shadow" | "Lightning",
  class        = "Bruiser" | "Mage" | "Guardian" | "Assassin" | "Support",
  behavior     = "pack" | "lone" | "gentle" | "aggressive" | "skittish" | "raider" | "stationary",
  spawnWeight  = number,
  baseIncome   = number,
  captureTime  = number,
  health       = number,
  attack       = number,
  defense      = number,
  speed        = number,
  description  = string,
  modelName    = string,
  primaryColor = Color3,
  evolvesTo    = string | "Coming Soon" | nil,
  evolvesFrom  = string | nil,
  spawnPointType = nil | "dungeon" | "boss",  -- optional
  packSize     = { min, max },  -- for behavior "pack"
  modelRotationY = number | nil,  -- optional degrees
  evolutionComingSoon = boolean | nil,
}
```

### 4.4 GameConfig (ReplicatedStorage/Modules/GameConfig)

Central config table; key groups:

- **Debug:** `SpawnOnlyCreaturesWithModels`, `DebugCoins1000`, `DebugFloor2Level2`, `DebugDoubleSpeed`
- **Economy:** `StartingCoins`, `IncomeTickSeconds`, `MaxInventorySize`, `EggCost`, `MaxIncomeSlots`, `MaxDefenseSlots`
- **Leveling:** `MaxCreatureLevel` (legacy), `BaseMaxLevel`, `EvolvedMaxLevel`, `FinalMaxLevel` (by evolution stage), `BaseXPRequired`, `XPScaling`, `CaptureXP`, `BattleKillXP`, `ArenaWinXPPoolBase`, `ArenaWinXPPoolPerStreak`, `StatGainPerLevel`
- **Player level:** `PlayerMaxLevel`, `PlayerBaseXP`, `PlayerXPScaling`, `PlayerXP_*` (Capture, ArenaWin, ArenaKill, IncomeTick, RaidWin, DungeonKill, BossKill)
- **Floors:** `Floor2Cost`, `Floor2LevelReq`, `Floor3Cost`, `Floor3LevelReq`
- **Evolution/combine:** `EvolutionMinLevel`, `EvolutionMinLevel2`, `CombineCost`, `VariantStatMultipliers`, `RecyclerDuplicateCount` (min duplicates for recycler → 1 egg 1 tier higher)
- **Debug:** `CombinerRecyclerPromptAllPlots` (E prompts on all plots for testing)
- **Sell:** `SellEnabled`, `SellRange`
- **Spawning:** `MaxWorldCreatures`, `SpawnIntervalMin/Max`, `SpawnsPerCycle`, `SpawnPointFillTarget`, `CreatureDespawnTime`, `SpawnRadius`, `SpawnHeightOffset`, `SpawnPointSpread`, `DungeonPointSpread`, `BossPointSpread`, `DungeonSpawnCount`, `BossRespawnTime`, `DungeonSpawnInterval`, `DungeonDuration`, `DungeonCreatureCount`, `DungeonSpawnRadius`
- **Capture:** `CaptureRange`, `CaptureHoldTime`, `CaptureAnimationTime`, `CaptureGracePeriod`, `CaptureCooldown`, `FaintDuration`
- **Base:** `BasePlotSize`, `MaxBaseCreatures`, `BaseCreatureSpacing`, `MaxPlots`, `PlotSize`, `CreaturesPerRow`, `CreatureSpacing`, `IncomePointsPerFloor`, `DefensePointsPerFloor`
- **Raid:** `RaidCooldown`, `RaidDuration`, `MaxStealPerRaid`, `RaidProtectionTime`, `StealChanceBase`
- **AI Raid:** `AIRaidInterval`, `AIRaidPackSize`, `AIRaidDefenseBreakChance`, `AIRaidIncomeStealChance`, `AIRaidDuration`
- **Arena:** `ArenaRoundInterval`, `MaxBattleTeamSize`, `MinBattleTeamSize`, `BattleTickSpeed`, `GrowthPerWin`, `MaxGrowth`, `ArenaExclusionRadius`, `ArenaPresenceBuff`
- **PvP:** `PvPInteractionRange`, `PvPWinGold`, `PvPLoserGoldLoss`, `PvPBattlePointSpacing`, `PvPBattleTickSpeed`, `PvPReviveCoinCost`, `PvPReviveGemCost`
- **Focus/specials:** `FocusMax`, `FocusGainPerAttack`, `SpecialAttackDuration`, `BurnDamagePerRound`, `BurnDuration`, `EarthDmgReduction`, `EarthDebuffDuration`, `WindFocusDrain`
- **AI:** `AI_TickRate`, `AI_WanderRadius`, `AI_WanderSpeed`, `AI_AggroRange`, `AI_AttackRange`, `AI_AttackCooldown`, `AI_FleeSpeed`, `AI_FleeRange`, `AI_PackCallRange`, `AI_PlayerDamage`, `AI_CreatureDamage`
- **Companion:** `CompanionAttackRange`, `CompanionAttackCD`, `CompanionBaseDamage`, `CompanionFollowDist`, `CompanionFollowSpeed`, `CompanionTargetRange`, `CompanionRespawnCD`
- **Defense:** `DefenseAttackRange`, `DefenseAttackCD`, `DefenseBaseDamage`, `DefensePassiveXP`, `DefenseKillXP`
- **Stealing:** `StealCarrySpeed`, `StealHomeRadius`
- **Player combat:** `PlayerRangedDamage`, `PlayerRangedRange`, `PlayerRangedCooldown`, `PlayerRangedSpeed`, `PlayerMeleeDamage`, `PlayerMeleeRange`, `PlayerMeleeCooldown`, `PlayerMeleeRadius`
- **Codex:** `ENABLE_CODEX_UI`, `ENABLE_CODEX_3D_VIEWER`, `ENABLE_BASE_LAYOUT_OVERVIEW`
- **Targeting:** `TargetScanRange`
- **Laser door:** `LaserDoorEnabled`, `LaserDoorDamage`, `LaserDoorMaxFriends`, `DomeRadius`, `ShieldDuration`
- **Shops:** `BuffShopItems`, `CosmeticItems`, `EggShopItems` (and egg tier percentages)

---

## 5. Server Modules (Agents / Systems)

### 5.1 PlayerDataManager (ServerScriptService)

- **Init():**
  - Hooks `Players.PlayerAdded` / `PlayerRemoving`; loads/saves DataStore; assigns plot on join.
- **Data & economy:**  
  `GetData(player)`, `GetCoins`, `AddCoins`, `SpendCoins`, `GetGems`, `AddGems`, `SpendGems`
- **Creatures:**  
  `GenerateUID()`, `AddCreature(player, creatureId, level, xp, variant)`, `GetCreatureByUid`, `RemoveCreature`, `TransferCreature`, `XPForLevel`, `AddXP`, `GetEffectiveStats(creatureId, level, variant)`
- **Combine/evolve:**  
  `CanCombine(player, uids)`, `CombineCreatures(player, uids)`, `EvolveCreature(player, uid)`
- **Slots:**  
  `AssignToBase`, `AssignToDefense`, `SetFavorite`, `ClearFavorite`, `GetFavorite`, `AssignToBattle`, `RemoveFromBattle`
- **Raid:**  
  `GetStealableCreatures(player)`
- **Profile:**  
  `GetInventoryData`, `AssignPlot`, `OnPlayerJoin`, `OnPlayerLeave`, `SaveAll`, `SavePlayer`
- **Friends:**  
  `GetFriendsList`, `AddFriend`, `RemoveFriend`, `IsFriend`
- **Buffs:**  
  `GetActiveBuffs`, `ActivateBuff`, `HasBuff`
- **Cosmetics:**  
  `GetCosmetics`, `OwnsCosmetic`, `PurchaseCosmetic`, `EquipCosmetic`
- **Player level:**  
  `PlayerXPForLevel`, `AddPlayerXP`, `GetPlayerLevel`, `OwnsFloor`, `BuyFloor`
- **Slots capacity:**  
  `GetMaxSlots(player, slotType)` — slotType `"income"` or `"defense"`
- **Sell:**  
  `SellCreature(player, uid)`
- **Leaderboard:**  
  `GetLeaderboardStats`, `GetAllOnlineData`
- **Init:**  
  `Init()`

### 5.2 CreatureData (ReplicatedStorage/Modules)

Shared; no Init. Defines `Rarities`, `RarityOrder`, `VariantTiers`, `VariantOrder`, `VariantColors`, `Starters`, `ZonePreference`, `ZoneBiomeFolder`, `Zones`, `Elements`, `Classes`, `Synergies`, `Creatures`, and `_byId`.

- **Lookup:**  
  `GetById(id)`, `GetAll()`, `GetBiomeFolderForElement(element)`, `GetElementForBiomeFolder(biomeFolderName)`
- **Capture:**  
  `GetCaptureCost(creatureId)`
- **Variants/evolution:**  
  `GetNextVariant(variant)`, `GetVariantStatMultiplier(variant)`, `CanEvolve(creatureId)`, `CanEvolveInGame(creatureId)`, `GetEvolvesTo(creatureId)`, `GetEvolvesFrom(creatureId)`
- **Models:**  
  `GetModelRotationOffset(creature)`, `CreatureHasModel(creature)`
- **Spawning:**  
  `GetRandomCreatureId(onlyWithModels, preferCommon)`, `GetDungeonCreatureId(element, onlyWithModels)`, `GetBossCreatureId(element, onlyWithModels)`, `GetCreaturesByElement(element)`, `GetCreaturesByRarity(rarity)`
- **Battle:**  
  `CalculateSynergies(creatureIds)` → activeSynergies, elementCounts, classCounts; `GetBoostedStats(creatureId, activeSynergies)`

### 5.3 CreatureAI (ServerScriptService)

- **Init(laserDoorRef)**  
  Sets laser door reference for “inside dome” checks.
- **SetFavoriteSystem(favSys)**  
  Called from MainServer so AI can damage companions.
- **Lifecycle:**  
  `RegisterCreature(model, creatureId, spawnPos, packId)`, `UnregisterCreature(model)`
- **State/HP:**  
  `GetState(model)`, `IsFainted(model)`, `GetHP(model)`
- **Damage/faint:**  
  `DamageCreature(model, damage, attackerModel)`, `FaintCreature(model, killerModel)`
- **Utility:**  
  `GeneratePackId()`

### 5.4 CreatureSpawner (ServerScriptService)

- **Init(creatureAIRef)**
- **Spawning:**  
  `StartSpawning()`, `SpawnCreature()`, `SpawnDungeonCreatures()`, `SpawnBossCreatures()`, `SpawnSpecificCreature(creatureId, position)`
- **Registry:**  
  `RemoveCreature(model)`, `GetCreatureId(model)`, `GetActiveCreatures()`

### 5.5 CaptureSystem (ServerScriptService)

- **Init(playerDataMgr, creatureSpawnerRef, creatureAIRef, basePlacementRef)**
- **Capture:**  
  `TryCapture(player, creatureModel)` — validates faint, range, coins; adds creature; fires success/fail events.

### 5.6 BasePlacementSystem (ServerScriptService)

- **Init(playerDataMgr, creatureAIRef)**  
  Optional: `RegisterCompanionFaintForDefenseXP(favSys)`.
- **Placement:**  
  `PlaceCreatures(player)` — places income/defense/battle creatures on plot.
- **Arena:**  
  `ClearBattleCreatures(player)`, `RespawnBattleCreatures(player)`

### 5.7 FavoriteCreatureSystem (ServerScriptService)

- **Init(playerDataMgr, creatureSpawnerRef, creatureAIRef)**
- **Companion:**  
  `SpawnCompanion(player)`, `DespawnCompanion(player)`, `HasCompanion(player)`, `IsOnCooldown(player)`
- **Combat:**  
  `DamageCompanion(player, damage, attackerModel)`, `FaintCompanion(player, killerModel)`, `GetCompanionForModel(model)`
- **PvP:**  
  `IsPvPFainted(player)`, `SetPvPFainted(player, value)`
- **Behavior:**  
  `ToggleAttackMode(player)`, `SetTarget(player, creatureModel)`, `ClearTarget(player)`

### 5.8 ArenaSystem (ServerScriptService)

- **Init(playerDataMgr, basePlacementSys)**
- **Queries:**  
  `GetPlayerBattleTeam(player)`, `IsBattleInProgress()`, `GetKingName()`, `GetKingStreak()`

### 5.9 BattleTeamSystem (ServerScriptService)

- Manages 3×3 battle grid (slots 1–9), max 5 creatures. Finds `BattlePoint` parts under plot (e.g. Floor2/BattleTeam).  
- MainServer handles `AssignToBattle` / `RemoveFromBattle`; this module can place orbs and sync visuals.

### 5.10 PvPBattleSystem (ServerScriptService)

- **Init(playerDataMgr, favoriteCreatureSys, leaderboardSys)**
- **Query:**  
  `IsBattleActive()`

### 5.11 RaidSystem (ServerScriptService)

- **Init(playerDataMgr)**
- **Raid:**  
  `StartRaid(raider, victim)`, `GetRaidableTargets(raider)`

### 5.12 TradeSystem (ServerScriptService)

- **Init(pdm, remotes)**  
  remotes: TradeRequest, TradeInvite, TradeResponse, TradeUpdateOffer, TradeAccept, TradeCancel, TradeState.
- **Profile:**  
  `GetPublicProfile(requestingPlayer, targetUserId)`

### 5.13 BaseIncomeSystem (ServerScriptService)

- **Init(PlayerDataManager)**  
  Runs income tick loop; pays coins per income slot and fires `IncomeReceived` / `CoinsUpdate`. If module missing, MainServer runs an inline income loop.

### 5.14 AIRaidSystem (ServerScriptService)

- **Init(playerDataMgr, basePlacementRef, creatureSpawnerRef, creatureAIRef)**  
  Periodically spawns AI raiders against player bases; can free defense / steal income.

### 5.15 DungeonSpawner (ServerScriptService)

- **Init(creatureSpawnerRef)**  
  Spawns dungeon events at DungeonPoints on an interval.

### 5.16 WorldCreatureHP (ServerScriptService)

- **Init()**  
  Can mirror or supplement creature HP for UI/feedback.
- **API:**  
  `DamageCreature(model, damage, attackerModel)`, `GetHP(model)`, `Cleanup(model)`

### 5.17 PlayerCombatSystem (ServerScriptService)

- **Init(pdm, cai, favSys)**  
  Handles player melee/ranged attacks vs world creatures and companion.

### 5.18 BuffShopSystem, CosmeticSystem, EggShopSystem (ServerScriptService)

- **BuffShopSystem.Init(pdm)**  
  Handles `BuyBuff` and buff activation.
- **CosmeticSystem.Init(pdm)**  
  Handles `BuyCosmetic`, `EquipCosmetic`.
- **EggShopSystem.Init(pdm)**  
  Handles `BuyEgg`, hatches creature, fires `EggResult`.

### 5.19 LaserDoorSystem (ServerScriptService)

- **Init(pdm)**
- **Dome:**  
  `HasDome(plotId)`, `CreateForPlot(plotModel, player)`, `RemoveForPlot(plotModel)`, `IsInsideActiveShield(position)`

### 5.20 LeaderboardSystem (ServerScriptService)

- **Init(playerDataMgr)**
- **PvP:**  
  `RecordPvPResult(winnerPlayer, loserPlayer)`

### 5.21 EvolutionCombineSystem (ServerScriptService)

- **Init(playerDataManager, favoriteCreatureSys)**  
  Wires `EvolveCreature` / `EvolveResult` and `CombineCreatures` / `CombineResult` remotes to PlayerDataManager and optional favorite checks.

### 5.22 CombinerRecyclerSystem (ServerScriptService)

- **Init(playerDataManager)**  
  Wires combine/recycler plot interact logic; fires `OpenCombiner` / `OpenRecycler` to client when player uses MCombiner/MRecycler.
- **SetupPlotPrompts(plotModel, ownedFloors)**  
  Adds E prompts to Combiner/Recycler on a plot (respects `CombinerRecyclerPromptAllPlots` for all plots vs own only).

---

## 6. Client Scripts (StarterPlayerScripts)

| Script | Purpose |
|--------|---------|
| **HUDClient** | Coin display, inventory count; listens to IncomeReceived, CoinsUpdate, CaptureSuccess, RaidStart/End, CreatureStolen, AIRaidAlert, DungeonSpawned/Despawned, CaptureFail. |
| **CaptureClient** | Click fainted creature to capture; E = target for companion; T = toggle companion attack mode; capture progress UI. |
| **InventoryUIManager** | Inventory, battle formation, raids UI; B or button; uses GetInventory, AssignToBase/Defense/Battle, SetFavorite, sell, evolve, raid remotes. |
| **PlayerCombatClient** | Player melee/ranged; fires PlayerAttack, listens PlayerAttackFX. |
| **HUDButtonBar** | Bottom bar buttons (inventory, passive/attack, etc.). |
| **CodexClient** | Codex UI (creature detail panel); optional 3D viewer. |
| **CodexModelViewer** | ViewportFrame creature viewer. |
| **EggShopClient** | Egg shop UI; BuyEgg, EggResult. |
| **BuffShopClient** | Buff shop UI; BuyBuff. |
| **CosmeticShopClient** | Cosmetic shop; BuyCosmetic, EquipCosmetic. |
| **FriendsListClient** | Friends list; AddBaseFriend, RemoveBaseFriend, GetFriendsList. |
| **LeaderboardClient** | Leaderboard UI; GetLeaderboardData. |
| **PlayerProfileClient** | Profile UI; GetProfile. |
| **PvPBattleClient** | PvP challenge/accept/decline, battle UI, revive. |
| **ArenaRewardUI** | Arena rewards display. |
| **CombinerRecyclerClient** | Combine/recycler UI; listens OpenCombiner, OpenRecycler; interacts with MCombiner/MRecycler at base. |
| **BaseInteractionClient** | Base plot interactions (e.g. prompts, combiner/recycler triggers). |
| **RebirthUIClient** | Rebirth / prestige UI and flow. |
| **CreatureAnimationClient** | Client-side creature animations (idle, combat, etc.). |
| **LaunchScreen** | Starter selection; SelectStarter. |
| **LoadingGate** | Loading gate before game. |
| **NotificationManager** | Shared toast/notifications (required by several clients). |

---

## 7. Base Build Instructions (Custom Bases)

- **BaseBuildInstructions_HauntedHouse.lua** (reference/agent script): Defines the **structure contract** that any custom base (e.g. haunted house theme) must satisfy for `BasePlacementSystem`. Use when building or generating plot models.
- **Contract summary:** Plot must have `Floor1`, `Floor2`, `Floor3`; `DefensePoint1`..`18` and `IncomePoint1`..`18` (per floor); `BattlePoint1`..`9` inside `Floor2/BattleTeam`; `PlotCenter`, optional `SignPart`. Points are BaseParts; discovery uses `GetDescendants` + name match. Glass parts: name contains "Glass" or attribute `IsGlass = true`.
- **Evolution stage → max level:** Base form uses `BaseMaxLevel`, one evolution uses `EvolvedMaxLevel`, final form uses `FinalMaxLevel` (from GameConfigData).

---

## 8. Key Variables & Conventions

- **Creature instance id:** `uid` — string GUID from `PlayerDataManager.GenerateUID()`.
- **Creature type id:** `id` or `creatureId` — string key in CreatureData (e.g. `"firsky"`).
- **Battle team:** `battleTeam` — table with number keys 1..9; value = `uid` or nil; max 5 filled (GameConfig.MaxBattleTeamSize).
- **Plot:** `plotId` — 1..MaxPlots; plot model name `"Plot" .. plotId` or `"Part" .. plotId` under `workspace.BasePlots`.
- **Floors:** `ownedFloors` — array of owned floor numbers; Floor 2 required for battle team and arena.
- **Rarity in eggs:** “Mythic” in config = Epic in CreatureData.

---

## 9. Current To-Do

- **Fix Cosmetic Base** — Resolve bugs or UX issues with the cosmetic base system.
- **Add more cosmetic bases** — Expand cosmetic base options so players have more themes/styles to choose from.

---

## 10. Brainstorm: New Features (Fun + Simplicity)

Ideas that add fun without adding much complexity. Pick what fits the vision; keep implementation small and iterative.

### Quick wins (low effort, high feel-good)

- **Capture celebration** — Short particle burst + sound when a capture succeeds. Reuses existing CaptureSuccess; no new systems.
- **Companion name tag** — Let players name their favorite creature. One string in player data, one label above companion. Builds attachment.
- **"First time" toasts** — First capture, first raid, first arena win: one-time congratulation. Simple flag per milestone in player data.
- **Income tick sparkle** — When income fires, briefly highlight the coin counter or play a small animation. Pure client, no server change.
- **Daily login bonus** — Day 1–7 rewards (coins or one egg). LastLoginDate + DayIndex in player data; one small server check on join.

### One-system additions (medium effort, clear payoff)

- **Creature moods / reactions** — Idle emotes or bubbles based on state (e.g. "happy" at base, "angry" in combat). Reuse existing creature instances; add a small mood/state field and client-only FX.
- **Mini goals / quests** — 3–5 rotating objectives ("Capture 3 Fire creatures", "Win 1 arena match"). Rewards in coins or XP. One Goals table + UI panel; server validates completion.
- **Weather or time-of-day tweaks** — If DayNightCycle exists: light rain or snow in certain biomes, or "golden hour" bonus (e.g. +5% capture rate). Config-driven, no new loops.
- **Base visitor log** — Last 5–10 players who visited (raid or friend). Display in a simple UI. Store recentVisitorIds + timestamps; trim on save.
- **Egg opening animation** — Short "crack and hatch" sequence before showing the creature. Client-only animation + delay before EggResult display.

### Social / retention (keep it simple)

- **Gift a creature** — "Send duplicate to a friend" (same rarity or below). Reuse trade-style flow: one remote, validate ownership and recipient, then transfer one creature.
- **Leaderboard filters** — By stat (e.g. total captured, arena streak). Same leaderboard data; client filters or a single new GetLeaderboardData parameter.
- **Achievement badges** — 10–15 fixed achievements (e.g. "Capture 50", "Win 10 arena"). Icon + name; stored as completedAchievementIds[]. Unlocks cosmetic or title only if you want to avoid new economy.

### Principles

- **One new thing per feature** — Avoid "and also add X and Y." Ship the smallest version that feels good.
- **Reuse remotes and data** — Prefer extending GetInventory, existing events, or player stats over new endpoints.
- **Client-first for feel** — Juicy feedback (SFX, particles, UI tweaks) on the client; server stays the source of truth.
- **Config over code** — New content (e.g. daily rewards, goals) in config/tables so tuning doesn't require code changes.

---

## 11. File Layout Summary

```
ServerScriptService/
  MainServer.lua
  PlayerDataManager.lua
  CreatureAI.lua
  CreatureSpawner.lua
  CaptureSystem.lua
  BasePlacementSystem.lua
  BaseIncomeSystem.lua
  BaseExteriorSystem.lua
  FavoriteCreatureSystem.lua
  ArenaSystem.lua
  BattleTeamSystem.lua
  PvPBattleSystem.lua
  RaidSystem.lua
  TradeSystem.lua
  AIRaidSystem.lua
  DungeonSpawner.lua
  PlayerCombatSystem.lua
  PlayerHealthSystem.lua
  WorldCreatureHP.lua
  BuffShopSystem.lua
  CosmeticSystem.lua
  EggShopSystem.lua
  LaserDoorSystem.lua
  LeaderboardSystem.lua
  EvolutionCombineSystem.lua
  CombinerRecyclerSystem.lua

ReplicatedStorage / Shared (see default.project.json):
  GameConfig.lua, GameConfigData.lua, CreatureData.lua
  CreatureAnimation.lua, CreatureModelLoader.lua, EvolutionEffects.lua
  NotificationManager.lua
  Events/ (created by MainServer), CreatureModels/

StarterPlayer.StarterPlayerScripts/
  HUDClient.lua
  CaptureClient.lua
  InventoryUIManager.lua
  PlayerCombatClient.lua
  HUDButtonBar.lua
  CodexClient.lua
  CodexModelViewer.lua
  CreatureAnimationClient.lua
  EggShopClient.lua
  BuffShopClient.lua
  CosmeticShopClient.lua
  FriendsListClient.lua
  LeaderboardClient.lua
  PlayerProfileClient.lua
  PvPBattleClient.lua
  ArenaRewardUI.lua
  CombinerRecyclerClient.lua
  BaseInteractionClient.lua
  RebirthUIClient.lua
  LaunchScreen.lua
  LoadingGate.lua

Reference / agent (e.g. for base building):
  BaseBuildInstructions_HauntedHouse.lua
  HauntedHouseBaseGenerator.lua
```

Optional / environment: `DayNightCycle.lua` (Lighting or shared).

Workspace: `BasePlots` (Plot1, Plot2, …), biomes (e.g. VolcanicBiome, FrozenBiome) with SpawnPoint, DungeonPoint, BossPoint parts.

---

This README is the central reference for the game’s systems, function calls, variables, and data structures. For adding creatures, elements, or behaviors, see the comments at the top of `CreatureData.lua` and the relevant system modules.
