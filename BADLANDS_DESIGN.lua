--[[
═══════════════════════════════════════════════════════════════════════════════════
THE BADLANDS — Full Gameplay Design & Implementation Plan
═══════════════════════════════════════════════════════════════════════════════════
Version: 1.0
Date: 2026-03-20
Status: Production Design — Ready for Implementation
Game: Siege Monsters (Siegelings)

One-line pitch:
"The Badlands is a roguelike PvPvE arena where players enter with nothing,
build power through risk, and only keep what they survive with."

═══════════════════════════════════════════════════════════════════════════════════
TABLE OF CONTENTS
═══════════════════════════════════════════════════════════════════════════════════
  1.  MODE OVERVIEW
  2.  FULL GAMEPLAY LOOP
  3.  ENTRY CONTRACT SYSTEM
  4.  MATCH / INSTANCE STRUCTURE
  5.  BADLANDS BAG SYSTEM
  6.  CREATURE SPAWNING & ENCOUNTER DESIGN
  7.  TEMPORARY PROGRESSION (RUN POWER)
  8.  PVP COMBAT & DEATH / LOOT RULES
  9.  EXTRACTION SYSTEM
  10. RISK / REWARD BALANCING
  11. MAP FLOW & ENCOUNTER PACING
  12. DAILY VARIATION & REPLAYABILITY
  13. FUTURE EXPANSION HOOKS
  14. MODULAR IMPLEMENTATION STRUCTURE
  15. GAMECONFIG VALUES
  16. REMOTE EVENTS & DATA SCHEMA
  17. FILE MANIFEST

═══════════════════════════════════════════════════════════════════════════════════
1. MODE OVERVIEW
═══════════════════════════════════════════════════════════════════════════════════

The Badlands is a daily-rotating, instanced PvPvE roguelike mode. It is the
endgame proving ground for Siegelings — a lawless arena where skill, timing,
greed management, and survival instinct determine who walks out with loot.

KEY PILLARS:
  • Enter with nothing — no carried stats, creatures, or advantages
  • Build from scratch — capture wild Badlands creatures to grow during the run
  • PvPvE tension — other players are threats, not teammates
  • Extract or lose everything — death drops your entire bag
  • Daily rotation — entry requirements and modifiers change every 24 hours

PLAYER CAPACITY: 8 players per instance
RUN DURATION: 12 minutes (soft timer) + 3-minute extraction countdown (hard)
ENTRY: Daily Contract NPC — sacrifice a qualifying Siegeling to enter

═══════════════════════════════════════════════════════════════════════════════════
2. FULL GAMEPLAY LOOP
═══════════════════════════════════════════════════════════════════════════════════

PHASE 1: CONTRACT (Pre-Run)
────────────────────────────
  1. Player visits the Badlands Contract NPC in the Arena Hub
  2. NPC shows today's entry requirement (e.g., "Offer a Lv5+ Rare Fire Siegeling")
  3. Player selects a qualifying creature from inventory
  4. Creature is CONSUMED (permanently sacrificed)
  5. Player enters the Badlands matchmaking queue
  6. When 4-8 players are queued (or 60s timeout), the run begins

PHASE 2: DROP-IN (0:00 – 0:30)
────────────────────────────────
  1. All players teleported to a random spawn point in the Badlands zone
  2. Spawn points are spread out — no two players spawn adjacent
  3. Each player starts with:
     • Empty Badlands Bag (10 slots)
     • Badlands Power Level 1
     • No active Siegeling (naked — can't fight until first capture)
     • 30-second spawn shield (PvP immunity, shown as fading blue aura)
  4. Wild Tier 1 creatures roam near spawn points — easy first captures

PHASE 3: SCALING (0:30 – 8:00)
────────────────────────────────
  1. Players explore the Badlands, capturing creatures to fill their bag
  2. First capture auto-equips as active companion (can attack PvE + PvP)
  3. Stronger creatures spawn deeper in the map / in dangerous zones
  4. Players gain Badlands XP from captures and kills → level up run power
  5. Mid-run events trigger (supply drops, elite spawns, zone collapses)
  6. Other players are always a threat — PvP enabled after spawn shield fades

PHASE 4: PRESSURE (8:00 – 12:00)
──────────────────────────────────
  1. Zone starts shrinking (outer areas become "Corrupted" — DoT damage)
  2. Players forced toward center where extraction points are
  3. Creature spawns become rarer but more powerful
  4. Extraction points activate at 10:00 (announced globally)
  5. Tension peaks — players deciding stay vs. extract

PHASE 5: EXTRACTION (10:00 – 15:00)
─────────────────────────────────────
  1. 3 extraction points glow on minimap
  2. Player walks to extraction point, holds interact for 15 seconds
  3. During channel: player is VISIBLE to all (beacon above head), CANNOT move
  4. If interrupted (damaged or knocked), extraction resets
  5. Successful extraction: all bag contents → permanent main inventory
  6. At 15:00 hard timer: Badlands collapses. Anyone still inside DIES (full drop)

PHASE 6: POST-RUN
───────────────────
  1. Extracted players shown a results screen:
     • Creatures extracted (with rarity/level)
     • Players eliminated
     • Badlands Power Level reached
     • Total run value (coin equivalent)
  2. Player returns to main game with extracted creatures in inventory
  3. Daily cooldown: 1 free run per day, additional runs cost gems

═══════════════════════════════════════════════════════════════════════════════════
3. ENTRY CONTRACT SYSTEM
═══════════════════════════════════════════════════════════════════════════════════

PURPOSE:
  Make entry feel exclusive and valuable. Encourage broad creature collection
  in the main game. Create a daily reason to engage with The Badlands.

DAILY CONTRACT FORMAT:
  Each day at midnight UTC, a new contract is generated from a pool of templates.

CONTRACT TEMPLATES:
  ┌──────────────────────────────────────────────────────────────────────────┐
  │ Template           │ Example                                           │
  ├──────────────────────────────────────────────────────────────────────────┤
  │ Species + Level    │ "Offer a Sundile at Lv3 or higher"                │
  │ Rarity + Element   │ "Offer any Rare Ice Siegeling"                     │
  │ Rarity + Level     │ "Offer any Epic Siegeling at Lv10+"                │
  │ Element only       │ "Offer any Fire Siegeling"                         │
  │ Specific creature  │ "Offer a Pyleer"                                  │
  │ Variant required   │ "Offer any Silver or Gold variant"                │
  │ Class + Rarity     │ "Offer a Rare+ Guardian"                         │
  │ Wildcard (easy day)│ "Offer any Siegeling Lv5+"                         │
  └──────────────────────────────────────────────────────────────────────────┘

CONTRACT DATA STRUCTURE:
  {
    contractId = "2026-03-20",         -- date string, rotates daily
    templateType = "rarity_element",   -- template key
    displayText = "Offer any Rare Ice Siegeling",
    requirements = {
      rarity = "Rare",                 -- nil = any
      element = "Ice",                 -- nil = any
      minLevel = nil,                  -- nil = any
      species = nil,                   -- nil = any (specific id if set)
      variant = nil,                   -- nil = any ("Silver", "Gold", etc.)
      class = nil,                     -- nil = any ("Guardian", "Striker", etc.)
    },
    seed = 12345,                      -- deterministic daily seed
  }

CONTRACT GENERATION LOGIC:
  1. Compute seed from date: seed = os.time() / 86400 (day number)
  2. Use seed to pick template type (weighted — easier templates more common early)
  3. Use seed to fill template slots (pick random element, rarity, creature, etc.)
  4. Validate: ensure at least 3+ creatures in the game satisfy the requirement
  5. Cache for the day — all players see the same contract

CREATURE SACRIFICE:
  • The offered creature is PERMANENTLY REMOVED from inventory
  • This creates real stakes before the run even starts
  • Higher-value sacrifices could grant a small starting bonus (future hook)
  • Sacrifice is logged in stats: totalBadlandsSacrifices

NPC DESIGN:
  • Name: "The Broker" — shady figure near the Arena
  • Flavor: speaks in riddles, implies forbidden knowledge about The Badlands
  • ProximityPrompt: "Inspect Today's Contract"
  • UI shows: contract text, qualifying creatures from inventory, sacrifice button

═══════════════════════════════════════════════════════════════════════════════════
4. MATCH / INSTANCE STRUCTURE
═══════════════════════════════════════════════════════════════════════════════════

ZONE PLACEMENT:
  The Badlands zone exists as a physical area in workspace: workspace.Badlands
  It is placed far from the main map (e.g., Y=-500 or X=5000) to prevent
  interference with normal gameplay.

WORKSPACE STRUCTURE:
  workspace.Badlands/
    BadlandsCenter (Part — center reference for zone collapse)
    SpawnPoints/ (Folder)
      SpawnPoint1..SpawnPoint8 (Parts — player teleport destinations)
    CreatureSpawns/ (Folder)
      Tier1Spawns/ (Folder — easy creatures near edges)
        SpawnPoint1..N (Parts)
      Tier2Spawns/ (Folder — medium creatures mid-ring)
        SpawnPoint1..N (Parts)
      Tier3Spawns/ (Folder — hard creatures near center)
        SpawnPoint1..N (Parts)
      EliteSpawns/ (Folder — rare powerful creatures)
        SpawnPoint1..N (Parts)
    ExtractionPoints/ (Folder)
      ExtractPoint1..ExtractPoint3 (Parts — glow when active)
    Zones/ (Folder — visual/collision boundaries)
      OuterRing (Part — first zone to collapse)
      MidRing (Part)
      InnerRing (Part)
      Center (Part — final safe zone)
    SupplyDropPoints/ (Folder — mid-run event locations)
      DropPoint1..DropPoint5 (Parts)

INSTANCE MANAGEMENT:
  • NOT a separate Place/Universe — runs in the same server
  • Players are teleported to a SpawnPoint inside workspace.Badlands
  • During a Badlands run, normal gameplay systems are suppressed for
    participants (no income ticks, no arena calls, companion despawned)
  • Multiple runs can overlap if server supports it (future: one at a time V1)

PLAYER TELEPORTATION:
  1. Save player's pre-Badlands position (for return)
  2. Despawn companion, dismount if mounted
  3. Set player attribute "InBadlands" = true
  4. Teleport character to assigned SpawnPoint
  5. Apply spawn shield (30s PvP immunity)
  6. On extraction/death/timeout: teleport back to saved position

MATCHMAKING (V1 — Simple):
  • Queue is a server-side list of player references
  • When queue hits 4+ players OR 60s timeout passes, start the run
  • Max 8 players per run
  • If fewer than 4 after 90s, refund sacrifice and cancel

═══════════════════════════════════════════════════════════════════════════════════
5. BADLANDS BAG SYSTEM
═══════════════════════════════════════════════════════════════════════════════════

PURPOSE:
  Replaces the normal inventory during a Badlands run. Creates scarcity,
  forces decisions, and defines what can be extracted.

BAG PROPERTIES:
  • 10 slots (fixed — no upgrades in V1)
  • Stores captured Badlands creatures only
  • Run-scoped: created on entry, destroyed on death/extraction/timeout
  • NOT saved to DataStore until successful extraction

BAG DATA STRUCTURE (per player, server-side):
  badlandsBag = {
    slots = {
      [1] = { id = "sundile", level = 3, xp = 0, variant = "Normal",
              uid = "bl_unique_1", capturedAt = os.clock() },
      [2] = { ... },
      -- up to [10]
    },
    activeIndex = 1,  -- which slot is the "equipped" companion (first capture)
    capacity = 10,
  }

FIRST CAPTURE RULE:
  When the bag is empty and the player captures their first creature:
  1. Creature is placed in slot 1
  2. activeIndex = 1 (auto-equips as companion)
  3. Companion spawns immediately — player can now fight

BAG FULL BEHAVIOR:
  When all 10 slots are occupied and player captures a new creature:
  1. UI prompt: "Bag Full — Replace a Siegeling?"
  2. Shows all 10 slots with creature info (name, rarity, level)
  3. Player taps a slot to REPLACE it (old creature released/destroyed)
  4. Or taps "Cancel" to abandon the new capture
  5. If the replaced creature was the active companion, the new one auto-equips

ACTIVE COMPANION SWITCHING:
  During the run, players can switch their active companion:
  • Open bag UI (keybind or button)
  • Tap any occupied slot to make it the active companion
  • Previous companion despawns, new one spawns
  • This allows strategic swapping (e.g., Ice companion vs Fire enemy)

BAG DROP ON DEATH:
  When a player dies:
  1. A "Loot Bag" model spawns at their death location
  2. Loot Bag contains ALL creatures from their bag (up to 10)
  3. Loot Bag is visible to all players (glowing beacon, special color)
  4. Any player can interact with the Loot Bag (ProximityPrompt)
  5. Looting transfers creatures into the looter's bag (up to their free slots)
  6. If looter bag is full, they choose which to take/replace (same UI as capture)
  7. Loot Bags despawn after 60 seconds if not fully looted
  8. Multiple players can loot the same bag (first come first served per slot)

═══════════════════════════════════════════════════════════════════════════════════
6. CREATURE SPAWNING & ENCOUNTER DESIGN
═══════════════════════════════════════════════════════════════════════════════════

BADLANDS CREATURE POOL:
  The Badlands uses the same CreatureData registry but with modified spawn rules.
  Creatures spawn at Badlands-specific levels, not world levels.

TIER SYSTEM:
  ┌─────────┬─────────────┬────────────┬───────────────────────────────────────┐
  │ Tier    │ Zone        │ Rarity Pool│ Creature Level Range                  │
  ├─────────┼─────────────┼────────────┼───────────────────────────────────────┤
  │ Tier 1  │ Outer Ring  │ Common 70% │ Lv 1–3                                │
  │         │             │ Uncommon 30│                                       │
  │ Tier 2  │ Mid Ring    │ Common 30% │ Lv 3–8                                │
  │         │             │ Uncommon 40│                                       │
  │         │             │ Rare 30%   │                                       │
  │ Tier 3  │ Inner Ring  │ Uncommon 20│ Lv 8–15                               │
  │         │             │ Rare 40%   │                                       │
  │         │             │ Epic 40%   │                                       │
  │ Elite   │ Center/Event│ Epic 40%   │ Lv 15–25                              │
  │         │             │ Legendary  │                                       │
  │         │             │ 60%        │                                       │
  └─────────┴─────────────┴────────────┴───────────────────────────────────────┘

SPAWN MECHANICS:
  • Creatures spawn at tier spawn points inside workspace.Badlands
  • Initial wave: 20-30 Tier 1 + 10-15 Tier 2 creatures on run start
  • Continuous spawning: new creatures appear every 5-8 seconds
  • Tier 3 and Elite creatures only spawn after 3:00 into the run
  • Total creature cap: 60 creatures alive at once in the Badlands
  • When zone collapses, creatures in collapsed zones are destroyed

BADLANDS-EXCLUSIVE CREATURES (Future Hook):
  • Special creatures only found in The Badlands (not in main world)
  • Identified by a "Badlands" tag or special visual (red aura, corrupted look)
  • These would be highly desirable extraction targets

CAPTURE MECHANICS (Modified for Badlands):
  • Same core capture system (approach fainted creature, hold to capture)
  • Capture cost: FREE in The Badlands (no coin cost)
  • Capture time: Faster (0.3s base vs 0.5s normal) — survival pressure
  • Faint requirement: must damage creature to 0 HP first
  • Players attack with their active companion (same combat as PvE world)
  • No companion = cannot attack = must find Tier 1 creatures with low enough HP

CREATURE BEHAVIOR IN BADLANDS:
  • More aggressive — creatures attack players on sight within range
  • Higher-tier creatures have larger aggro radius
  • Elite creatures actively hunt nearby players (not just idle patrol)
  • Pack creatures move in groups and coordinate attacks

═══════════════════════════════════════════════════════════════════════════════════
7. TEMPORARY PROGRESSION (RUN POWER)
═══════════════════════════════════════════════════════════════════════════════════

PURPOSE:
  Create within-run scaling so successful play builds momentum. Early captures
  matter, mid-game decisions compound, and late-game players feel powerful.

BADLANDS POWER LEVEL:
  Separate from main game player level. Exists only during the run.
  Range: Level 1 → Level 10 (max)

  ┌───────┬─────────┬───────────────────────────────────────────────────────┐
  │ Level │ XP Req  │ Bonus Effect                                         │
  ├───────┼─────────┼───────────────────────────────────────────────────────┤
  │  1    │ 0       │ Base stats (no bonus)                                │
  │  2    │ 50      │ +10% companion damage                                │
  │  3    │ 120     │ +15% companion HP                                    │
  │  4    │ 220     │ +5% movement speed                                   │
  │  5    │ 360     │ +20% companion damage, +10% capture speed            │
  │  6    │ 550     │ +25% companion HP, +1 bag slot (11 total)            │
  │  7    │ 800     │ +10% movement speed, extraction time -3s (12s)       │
  │  8    │ 1100    │ +35% companion damage, +30% companion HP             │
  │  9    │ 1500    │ +15% movement speed, extraction time -5s (10s)       │
  │  10   │ 2000    │ +50% companion damage, +50% HP, +2 bag slots (13)   │
  └───────┴─────────┴───────────────────────────────────────────────────────┘

XP SOURCES:
  • Capture a creature: 15 XP × creature level
  • Faint a wild creature (without capture): 5 XP × creature level
  • Kill another player: 100 XP + 50% of their Badlands XP
  • Loot a player's bag: 25 XP per creature looted
  • Survive each minute: 10 XP (passive)

RUN POWER DATA STRUCTURE:
  badlandsRunPower = {
    level = 1,
    xp = 0,
    bonuses = {
      damageMult = 1.0,
      healthMult = 1.0,
      speedMult = 1.0,
      captureSpeedMult = 1.0,
      extractionTimeReduction = 0,
      bonusBagSlots = 0,
    },
  }

LEVEL-UP VISUAL:
  • Screen flash (gold border pulse)
  • "POWER LEVEL 5" text with level-specific icon
  • Audio cue (ascending chime)
  • Visible to other players: brief gold aura around the character

═══════════════════════════════════════════════════════════════════════════════════
8. PVP COMBAT & DEATH / LOOT RULES
═══════════════════════════════════════════════════════════════════════════════════

PVP OVERVIEW:
  The Badlands is full PvP after spawn shields expire. Players can attack each
  other at any time. Combat uses the existing companion attack system.

ATTACK MECHANICS:
  • Players attack via their active companion (same as world PvE)
  • Companion auto-targets the nearest enemy companion or player
  • Player characters themselves take damage from companion attacks
  • Player HP: uses PlayerHealthSystem (100 HP base, modified by run power)
  • Companion HP: uses creature stats (modified by run power bonuses)

TARGETING PRIORITY:
  1. If enemy companion is alive → attack companion first
  2. If enemy companion fainted → attack player character directly
  3. Player can manually target (click on enemy) to override auto-target

DAMAGE FORMULA (Same as existing PvP):
  dmg = max(1, companion.attack - target.defense / 3)
  dmg *= elementalMultiplier
  dmg *= (0.85 + random() * 0.3)
  dmg *= runPowerDamageMult  -- NEW: Badlands run power bonus
  dmg = floor(max(1, dmg))

DEATH RULES:
  When a player's character HP reaches 0:
  1. Player character ragdolls (death animation)
  2. Active companion despawns
  3. ALL bag contents drop as a Loot Bag at the death location
  4. Player is ELIMINATED from the run
  5. Player teleported back to main game (saved position)
  6. Results screen shown: "ELIMINATED" — creatures lost, run stats

  CRITICAL: Death is PERMANENT for the run. No respawns. No revives.

LOOT BAG RULES:
  • Loot Bag is a glowing model (pulsing red/gold) at death location
  • ProximityPrompt: "Loot Fallen Player's Bag" (0.5s hold)
  • Shows loot UI: list of all creatures in the bag
  • Player selects which creatures to take (limited by their own free bag slots)
  • If their bag is full, they can swap (replace a slot with a looted creature)
  • Multiple players can loot simultaneously (race condition: first grab wins each slot)
  • Loot Bag despawns after 60 seconds
  • Loot Bags show on all players' screens (minimap blip, world beacon)

COMPANION FAINT (Not Player Death):
  If the active companion faints but the player survives:
  1. Player loses their active fighter (can't attack)
  2. Player must switch to another creature in their bag (if available)
  3. If bag has other creatures → auto-switch to next slot
  4. If bag is empty → player is defenseless until they capture something

SPAWN SHIELD:
  • 30 seconds of PvP immunity on entry
  • Shown as fading blue shield aura
  • Attacking another player cancels your own shield early
  • Shield does NOT protect against PvE creatures

═══════════════════════════════════════════════════════════════════════════════════
9. EXTRACTION SYSTEM
═══════════════════════════════════════════════════════════════════════════════════

PURPOSE:
  The climax of every run. Extraction is what makes The Badlands meaningful.
  Everything earned is worthless until you successfully extract.

EXTRACTION POINTS:
  • 3 fixed extraction points in the Badlands zone
  • Located in the mid-to-inner ring (not at the edges, not dead center)
  • Activated at 10:00 into the run (announced: "EXTRACTION POINTS ONLINE")
  • Visually: glowing gold pillars with upward beam of light
  • Minimap: shown as gold diamond icons when active

EXTRACTION FLOW:
  1. Player approaches an extraction point (within 5 studs)
  2. ProximityPrompt appears: "BEGIN EXTRACTION" (0s hold — instant start)
  3. Extraction channel begins (15 seconds base, reduced by run power)
  4. During channel:
     • Player is FROZEN in place (cannot move or attack)
     • A BEACON appears above the player (visible to all, 200 stud range)
     • Channel progress bar shown on screen
     • Channel sound effect (ascending whine)
  5. If player takes ANY damage during channel:
     • Channel interrupted — progress resets to 0
     • Player can move again
     • Must restart the channel from scratch
  6. On successful completion:
     • Flash of light — player disappears
     • All bag contents transferred to main game inventory
     • Player teleported back to main game
     • "EXTRACTION SUCCESSFUL" results screen

EXTRACTION TIMER:
  Base: 15 seconds
  Run Power Level 7: -3 seconds (12 seconds)
  Run Power Level 9: -5 seconds (10 seconds)
  Minimum: 8 seconds (hard floor)

HARD DEADLINE:
  At 15:00 (3 minutes after extraction activates):
  • "BADLANDS COLLAPSING" warning at 14:00
  • "60 SECONDS REMAINING" at 14:00
  • "30 SECONDS" / "10 SECONDS" / countdown
  • At 15:00: ALL remaining players instantly die
  • Bag contents are LOST (no loot bags — everything destroyed)
  • This prevents indefinite camping

EXTRACTION STRATEGY DYNAMICS:
  • Early extraction (10:00-11:00): safest, least competition, smaller bags
  • Mid extraction (11:00-13:00): riskier, players may camp extract points
  • Late extraction (13:00-15:00): maximum bag value but extreme danger
  • Camping extraction points is viable but risky (you're in a known location)

═══════════════════════════════════════════════════════════════════════════════════
10. RISK / REWARD BALANCING
═══════════════════════════════════════════════════════════════════════════════════

RISK SPECTRUM:
  ┌──────────────────────────────────────────────────────────────────────────────┐
  │ Strategy         │ Risk   │ Reward │ Notes                                  │
  ├──────────────────────────────────────────────────────────────────────────────┤
  │ Quick Extract    │ Low    │ Low    │ Grab 2-3 Tier 1 creatures, extract at  │
  │ (the tourist)    │        │        │ 10:00. Safe but minimal value.          │
  │                  │        │        │                                         │
  │ PvE Farmer       │ Medium │ Medium │ Focus on creature captures, avoid PvP. │
  │ (the survivalist)│        │        │ Fill bag, extract mid-window.           │
  │                  │        │        │                                         │
  │ PvP Hunter       │ High   │ High   │ Hunt other players, steal their bags.  │
  │ (the predator)   │        │        │ Highest upside but combat risk.        │
  │                  │        │        │                                         │
  │ Deep Diver       │ V.High │ V.High │ Push to Tier 3/Elite zones for rare    │
  │ (the gambler)    │        │        │ creatures. Greedy but rewarding.       │
  │                  │        │        │                                         │
  │ Extract Camper   │ High   │ Varies │ Wait at extraction points, ambush      │
  │ (the gatekeeper) │        │        │ extractors, steal loaded bags.         │
  └──────────────────────────────────────────────────────────────────────────────┘

ECONOMIC BALANCE:
  Entry cost: 1 creature (Rare = ~60 coin capture value, Epic = ~150)
  Average extraction value:
    • Tourist run: 2-3 Commons = 20-30 coin equivalent
    • Farmer run: 6-8 mixed = 200-400 coin equivalent
    • Hunter run: 5-10 mixed (including stolen) = 300-800 coin equivalent
    • Deep dive: 4-6 high-rarity = 500-2000+ coin equivalent

  The entry cost should feel meaningful but recoverable. A successful mid-tier
  run should return 3-5x the entry cost. An excellent run should return 10x+.

ANTI-FRUSTRATION MEASURES:
  • Tier 1 creatures near every spawn → no player is truly helpless
  • Spawn shield prevents instant spawn-camping
  • 3 extraction points → hard to camp all of them
  • Zone collapse forces engagement (no hiding in corners forever)
  • 60s loot bag timer → you can sometimes recover your own bag (unlikely)

═══════════════════════════════════════════════════════════════════════════════════
11. MAP FLOW & ENCOUNTER PACING
═══════════════════════════════════════════════════════════════════════════════════

MAP LAYOUT (Concentric Rings):
  ┌─────────────────────────────────────────────────────────────────────┐
  │                                                                     │
  │   ╔═══════════════════════════════════════════════════════════╗     │
  │   ║  OUTER RING — Tier 1 spawns, player spawn points        ║     │
  │   ║                                                           ║     │
  │   ║   ╔═══════════════════════════════════════════════╗       ║     │
  │   ║   ║  MID RING — Tier 2 spawns, supply drops      ║       ║     │
  │   ║   ║                                               ║       ║     │
  │   ║   ║   ╔═══════════════════════════════════╗       ║       ║     │
  │   ║   ║   ║  INNER RING — Tier 3, extract pts ║       ║       ║     │
  │   ║   ║   ║                                   ║       ║       ║     │
  │   ║   ║   ║   ╔═══════════════════╗           ║       ║       ║     │
  │   ║   ║   ║   ║  CENTER — Elites  ║           ║       ║       ║     │
  │   ║   ║   ║   ╚═══════════════════╝           ║       ║       ║     │
  │   ║   ║   ╚═══════════════════════════════════╝       ║       ║     │
  │   ║   ╚═══════════════════════════════════════════════╝       ║     │
  │   ╚═══════════════════════════════════════════════════════════╝     │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘

PACING TIMELINE:
  0:00  — Players spawn in Outer Ring with 30s shield
  0:30  — Shields expire, PvP enabled
  1:00  — Tier 2 creatures begin spawning in Mid Ring
  3:00  — Tier 3 creatures begin spawning in Inner Ring
  4:00  — First supply drop event (random Mid Ring location)
  5:00  — Elite creatures begin spawning in Center
  6:00  — Second supply drop event
  8:00  — Outer Ring begins collapsing (DoT in outer zone)
  9:00  — Mid Ring begins collapsing
  10:00 — EXTRACTION POINTS ACTIVATE (announced globally)
  12:00 — Inner Ring begins collapsing (only Center + extract pts safe)
  14:00 — "60 SECONDS REMAINING" — final warning
  15:00 — COLLAPSE — all remaining players eliminated

ZONE COLLAPSE MECHANICS:
  • Collapsed zones deal 5 HP/second damage (PlayerHealthSystem)
  • Visual: red fog/corruption particles fill collapsed areas
  • Creatures in collapsed zones are instantly destroyed
  • Collapse is gradual (30-second transition per ring)

SUPPLY DROP EVENTS:
  • Announced globally: "SUPPLY DROP INCOMING — [location]"
  • A crate spawns at a random SupplyDropPoint
  • Crate contains 1-2 pre-captured creatures (Rare-Epic, Lv 5-15)
  • Player interacts with crate (1s hold) to add contents to bag
  • Crate is contestable — multiple players may fight over it
  • Crate despawns after 45 seconds if not looted

═══════════════════════════════════════════════════════════════════════════════════
12. DAILY VARIATION & REPLAYABILITY
═══════════════════════════════════════════════════════════════════════════════════

DAILY ROTATION ELEMENTS:
  1. Entry Contract — different creature requirement each day
  2. Creature Pool Modifier — each day emphasizes certain elements
  3. Weather Modifier (Future) — visual + gameplay effect
  4. Map Variant (Future) — layout shifts or different Badlands biome

ELEMENT OF THE DAY:
  One element is "boosted" each day:
  • Boosted element creatures spawn 50% more frequently
  • Boosted element creatures have +20% stats
  • Creates daily meta shifts (e.g., "Today is Fire day — bring Ice companions")

DAILY MODIFIERS (V2+):
  ┌────────────────────────────────────────────────────────────────────────────┐
  │ Modifier          │ Effect                                                │
  ├────────────────────────────────────────────────────────────────────────────┤
  │ Dense Fog         │ Reduced visibility, creatures harder to spot          │
  │ Blood Moon        │ All creatures +30% aggressive, +50% XP               │
  │ Famine            │ 50% fewer creature spawns, higher rarity when found  │
  │ Sanctuary         │ PvP disabled first 5 minutes (pure PvE start)        │
  │ Bounty Day        │ Killing players drops 2x loot bag duration           │
  │ Speed Run         │ Run is 8 min instead of 12, extraction at 6 min      │
  │ Giant Siege       │ All creatures are 2x size, 2x stats, 2x XP          │
  │ Elemental Storm   │ Random element DoT zones appear and move             │
  └────────────────────────────────────────────────────────────────────────────┘

REPLAYABILITY HOOKS:
  • Daily leaderboard: most valuable extraction, most kills, fastest extract
  • Weekly challenge: "Extract 3 Legendary creatures this week"
  • Streak bonus: consecutive daily entries grant +1 bag slot or +XP
  • Badlands-exclusive evolution materials (future)
  • SiegeLord Sigil: earned after N successful extractions

═══════════════════════════════════════════════════════════════════════════════════
13. FUTURE EXPANSION HOOKS
═══════════════════════════════════════════════════════════════════════════════════

The system is designed with these expansion points built in:

  BADLANDS-EXCLUSIVE EVOLUTIONS
    • Certain creatures can only evolve inside The Badlands
    • Requires finding a "Corruption Shard" item during a run
    • Extracting an evolution-ready creature + shard triggers the evolution

  MUTATIONS
    • Rare chance for Badlands creatures to spawn "Mutated"
    • Mutated creatures have altered stats, visual effects, and unique moves
    • Highly valuable extraction targets

  MID-RUN BOSS EVENTS
    • At random intervals, a Badlands Boss spawns in the center
    • Requires multiple players to take down (temporary cooperation)
    • Boss drops guaranteed Legendary creature + materials

  RANKED BADLANDS
    • Seasonal ranked queue with ELO-based matchmaking
    • Higher ranks face harder modifiers but better creature pools
    • Season rewards: exclusive cosmetics, creatures, titles

  TEAM VARIANTS
    • Duos mode: 2-player teams (4 teams of 2)
    • Squad mode: future expansion with larger maps

  SPECIAL CONTRACTS
    • Weekly "Legendary Contracts" with harder entry requirements
    • Guarantee at least one Legendary spawn per run
    • Higher stakes, higher rewards

═══════════════════════════════════════════════════════════════════════════════════
14. MODULAR IMPLEMENTATION STRUCTURE
═══════════════════════════════════════════════════════════════════════════════════

The Badlands is built as a set of independent modules that communicate through
well-defined interfaces. Each module can be developed and tested independently.

FILE ARCHITECTURE:
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │ File                           │ Location            │ Role                │
  ├─────────────────────────────────────────────────────────────────────────────┤
  │ BadlandsSystem.lua             │ ServerScriptService  │ Master coordinator  │
  │ BadlandsContractSystem.lua     │ ServerScriptService  │ Daily NPC + queue   │
  │ BadlandsBagSystem.lua          │ ServerScriptService  │ Bag CRUD + loot     │
  │ BadlandsSpawner.lua            │ ServerScriptService  │ Creature spawning   │
  │ BadlandsCombatSystem.lua       │ ServerScriptService  │ PvP + PvE combat    │
  │ BadlandsExtractionSystem.lua   │ ServerScriptService  │ Extract channels    │
  │ BadlandsZoneSystem.lua         │ ServerScriptService  │ Zone collapse logic │
  │ BadlandsRunPower.lua           │ ServerScriptService  │ Temp progression    │
  │ BadlandsClient.client.lua      │ StarterPlayerScripts │ Master client UI    │
  │ BadlandsBagClient.client.lua   │ StarterPlayerScripts │ Bag UI              │
  │ BadlandsHUDClient.client.lua   │ StarterPlayerScripts │ Timer/zone/minimap  │
  │ BadlandsContractClient.client.lua │ StarterPlayerScripts│ NPC interaction UI│
  └─────────────────────────────────────────────────────────────────────────────┘

MODULE DEPENDENCY GRAPH:
  MainServer.lua
    └── BadlandsSystem.Init(PlayerDataManager, CreatureSpawner, CreatureAI,
                            FavoriteCreatureSystem, MountSystem)
          ├── BadlandsContractSystem.Init(PlayerDataManager)
          ├── BadlandsBagSystem.Init(PlayerDataManager)
          ├── BadlandsSpawner.Init(CreatureAI)
          ├── BadlandsCombatSystem.Init(PlayerDataManager, CreatureAI)
          ├── BadlandsExtractionSystem.Init(PlayerDataManager, BadlandsBagSystem)
          ├── BadlandsZoneSystem.Init()
          └── BadlandsRunPower.Init()

IMPLEMENTATION ORDER (Recommended):
  Phase 1 (Core Loop):
    1. BadlandsSystem.lua — teleportation, run lifecycle, state machine
    2. BadlandsBagSystem.lua — bag creation, slot management, drop/loot
    3. BadlandsSpawner.lua — tier-based creature spawning
    4. BadlandsClient.client.lua — basic HUD, bag UI, extraction UI

  Phase 2 (Combat + Extraction):
    5. BadlandsCombatSystem.lua — PvP rules, death handling, loot bags
    6. BadlandsExtractionSystem.lua — channel mechanic, beacon, transfer
    7. BadlandsHUDClient.client.lua — timer, zone indicators, minimap

  Phase 3 (Progression + Polish):
    8. BadlandsRunPower.lua — XP, leveling, bonus application
    9. BadlandsZoneSystem.lua — zone collapse, DoT, visual effects
    10. BadlandsContractSystem.lua — daily rotation, NPC, queue
    11. BadlandsContractClient.client.lua — contract UI, sacrifice flow

  Phase 4 (Balance + Events):
    12. Supply drops, elite spawns, mid-run events
    13. Daily modifiers
    14. Leaderboard integration
    15. SiegeLord Sigil unlock condition

═══════════════════════════════════════════════════════════════════════════════════
15. GAMECONFIG VALUES
═══════════════════════════════════════════════════════════════════════════════════

All Badlands tuning values live in GameConfigData.lua:

-- ═══ Badlands: Core ═══
GameConfig.BadlandsEnabled              = true
GameConfig.BadlandsMaxPlayers           = 8
GameConfig.BadlandsMinPlayers           = 4
GameConfig.BadlandsQueueTimeout         = 60    -- seconds before starting with < max
GameConfig.BadlandsRunDuration          = 720   -- 12 minutes (seconds)
GameConfig.BadlandsHardDeadline         = 900   -- 15 minutes (seconds)
GameConfig.BadlandsExtractionActivateAt = 600   -- 10 minutes (seconds)
GameConfig.BadlandsSpawnShieldDuration  = 30    -- seconds of PvP immunity

-- ═══ Badlands: Bag ═══
GameConfig.BadlandsBagSlots             = 10
GameConfig.BadlandsLootBagDespawnTime   = 60    -- seconds
GameConfig.BadlandsLootBagBeaconRange   = 200   -- studs (visible distance)

-- ═══ Badlands: Spawning ═══
GameConfig.BadlandsInitialTier1Count    = 25
GameConfig.BadlandsInitialTier2Count    = 12
GameConfig.BadlandsSpawnInterval        = 6     -- seconds between new spawns
GameConfig.BadlandsMaxCreatures         = 60
GameConfig.BadlandsTier3ActivateTime    = 180   -- 3 minutes
GameConfig.BadlandsEliteActivateTime    = 300   -- 5 minutes

-- ═══ Badlands: Capture ═══
GameConfig.BadlandsCaptureTime          = 0.3   -- seconds (faster than normal 0.5)
GameConfig.BadlandsCaptureCost          = 0     -- free captures

-- ═══ Badlands: Zone Collapse ═══
GameConfig.BadlandsOuterCollapseTime    = 480   -- 8 minutes
GameConfig.BadlandsMidCollapseTime      = 540   -- 9 minutes
GameConfig.BadlandsInnerCollapseTime    = 720   -- 12 minutes
GameConfig.BadlandsCollapseDPS          = 5     -- HP/second in collapsed zones
GameConfig.BadlandsCollapseTransition   = 30    -- seconds for ring to fully collapse

-- ═══ Badlands: Extraction ═══
GameConfig.BadlandsExtractionTime       = 15    -- seconds to channel
GameConfig.BadlandsExtractionMinTime    = 8     -- hard floor with run power reduction
GameConfig.BadlandsExtractionBeaconRange= 200   -- studs (visible to all)
GameConfig.BadlandsExtractionPointCount = 3

-- ═══ Badlands: Run Power ═══
GameConfig.BadlandsMaxRunLevel          = 10
GameConfig.BadlandsXPPerCapture         = 15    -- per creature level
GameConfig.BadlandsXPPerFaint           = 5     -- per creature level
GameConfig.BadlandsXPPerPlayerKill      = 100
GameConfig.BadlandsXPPerMinuteSurvived  = 10
GameConfig.BadlandsXPPerLoot            = 25    -- per creature looted from bag

-- ═══ Badlands: Economy ═══
GameConfig.BadlandsFreeRunsPerDay       = 1
GameConfig.BadlandsExtraRunGemCost      = 50    -- gems for additional runs
GameConfig.BadlandsDailyCooldownReset   = 0     -- midnight UTC

-- ═══ Badlands: Supply Drops ═══
GameConfig.BadlandsSupplyDropCount      = 2     -- drops per run
GameConfig.BadlandsSupplyDropTimes      = {240, 360} -- seconds into run
GameConfig.BadlandsSupplyDropDespawn    = 45    -- seconds
GameConfig.BadlandsSupplyDropMinRarity  = "Rare"
GameConfig.BadlandsSupplyDropMaxRarity  = "Epic"

═══════════════════════════════════════════════════════════════════════════════════
16. REMOTE EVENTS & DATA SCHEMA
═══════════════════════════════════════════════════════════════════════════════════

REMOTE EVENTS (created in MainServer.lua):
  -- Contract
  makeEvent("BadlandsContractData")     -- server → client: today's contract
  makeEvent("BadlandsOfferCreature")    -- client → server: sacrifice creature
  makeEvent("BadlandsQueueJoin")        -- client → server: enter queue
  makeEvent("BadlandsQueueLeave")       -- client → server: leave queue
  makeEvent("BadlandsQueueUpdate")      -- server → client: queue count
  makeEvent("BadlandsQueueReject")      -- server → client: can't join (reason)

  -- Run lifecycle
  makeEvent("BadlandsRunStart")         -- server → clients: run beginning
  makeEvent("BadlandsRunEnd")           -- server → client: run over (results)
  makeEvent("BadlandsEliminated")       -- server → client: you died (results)
  makeEvent("BadlandsExtracted")        -- server → client: extraction success

  -- Bag
  makeEvent("BadlandsBagUpdate")        -- server → client: bag state changed
  makeEvent("BadlandsBagSwitch")        -- client → server: switch active slot
  makeEvent("BadlandsBagReplace")       -- client → server: replace slot with capture
  makeEvent("BadlandsLootBagSpawned")   -- server → clients: loot bag appeared
  makeEvent("BadlandsLootBagLoot")      -- client → server: take from loot bag
  makeEvent("BadlandsLootBagUpdate")    -- server → client: loot bag contents changed

  -- Combat
  makeEvent("BadlandsPvPDamage")        -- server → client: damage notification
  makeEvent("BadlandsPlayerKill")       -- server → clients: kill feed

  -- Extraction
  makeEvent("BadlandsExtractStart")     -- client → server: begin extraction channel
  makeEvent("BadlandsExtractCancel")    -- server → client: interrupted
  makeEvent("BadlandsExtractProgress")  -- server → client: channel % update
  makeEvent("BadlandsExtractActivate")  -- server → clients: points now active

  -- Zone
  makeEvent("BadlandsZoneCollapse")     -- server → clients: ring collapsing
  makeEvent("BadlandsTimerSync")        -- server → clients: time remaining

  -- Run Power
  makeEvent("BadlandsXPGain")           -- server → client: XP awarded
  makeEvent("BadlandsLevelUp")          -- server → clients: player leveled up

  -- Events
  makeEvent("BadlandsSupplyDrop")       -- server → clients: supply drop spawned

PLAYER STATE ATTRIBUTES (set on Player object):
  InBadlands           = true/false    -- is player in a Badlands run
  BadlandsRunId        = string/nil    -- current run identifier
  BadlandsSpawnShield  = true/false    -- has PvP immunity
  BadlandsPowerLevel   = number        -- current run power level

WORKSPACE ATTRIBUTES (set on Badlands folder):
  BadlandsRunActive    = true/false    -- is a run currently happening
  BadlandsRunStartTime = number        -- os.clock() when run started
  BadlandsRunId        = string        -- unique run identifier
  BadlandsPlayerCount  = number        -- current players alive in run

PER-RUN SERVER STATE:
  badlandsRun = {
    runId = "bl_2026-03-20_001",
    startTime = os.clock(),
    players = {
      [userId] = {
        player = Player,
        bag = badlandsBag,           -- reference to bag data
        runPower = badlandsRunPower,  -- reference to run power
        alive = true,
        savedPosition = CFrame,      -- where to teleport back
        spawnShieldExpiry = number,
        kills = 0,
        captures = 0,
      },
    },
    creatures = {},                   -- tracked spawned creatures
    lootBags = {},                    -- dropped bags from dead players
    zoneState = {                     -- which rings have collapsed
      outer = false,
      mid = false,
      inner = false,
    },
    extractionActive = false,
    phase = "waiting"|"active"|"extraction"|"collapsing"|"ended",
  }

═══════════════════════════════════════════════════════════════════════════════════
17. FILE MANIFEST
═══════════════════════════════════════════════════════════════════════════════════

Files to create:
  SERVER:
    BadlandsSystem.lua              — Master coordinator, lifecycle, teleport
    BadlandsContractSystem.lua      — Daily contract generation, NPC, queue
    BadlandsBagSystem.lua           — Bag CRUD, loot bags, extraction transfer
    BadlandsSpawner.lua             — Tier-based creature spawning in Badlands zone
    BadlandsCombatSystem.lua        — PvP damage, death, elimination
    BadlandsExtractionSystem.lua    — Channel mechanic, beacon, inventory transfer
    BadlandsZoneSystem.lua          — Ring collapse, DoT, visual zones
    BadlandsRunPower.lua            — XP tracking, level ups, bonus application

  CLIENT:
    BadlandsClient.client.lua       — Master client (lifecycle, state sync)
    BadlandsBagClient.client.lua    — Bag UI (slots, switch, replace, loot)
    BadlandsHUDClient.client.lua    — Timer, zone minimap, kill feed, power level
    BadlandsContractClient.client.lua — Contract NPC UI, sacrifice flow, queue

  CONFIG:
    GameConfigData.lua              — Add all BadlandsXxx config values

  PROJECT:
    default.project.json            — Add all new files to tree

Files to modify:
    MainServer.server.lua           — Require + Init BadlandsSystem
    GameConfigData.lua              — Add Badlands config section
    default.project.json            — Register new files
    PlayerDataManager.lua           — Add badlandsStats to player data
    FavoriteCreatureSystem.lua      — Suppress companion during Badlands
    MountSystem.lua                 — Auto-dismount on Badlands entry
    ArenaSystem.lua                 — Skip Badlands players for arena rounds
    BossBackboardClient.client.lua  — Update "Coming Soon" to real status
    PlayerProfileClient.client.lua  — Update Badlands sigil display

═══════════════════════════════════════════════════════════════════════════════════
END OF DESIGN DOCUMENT
═══════════════════════════════════════════════════════════════════════════════════
--]]
return nil
