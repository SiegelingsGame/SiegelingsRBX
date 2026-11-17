# Siegelings — Three.js web build

A browser rebuild of the Siegelings Roblox game, made with [three.js](https://threejs.org) and stand-in (procedural) assets.
It reuses the real creature roster and the tuning values from the Roblox scripts. This is the same game logic running in the browser, not a mock-up.

## Run it

```bash
cd web
npm install
npm run dev        # http://localhost:5173
npm run build      # static build in web/dist (open with `npm run preview`)
```

`npm run build:single` also writes `web/dist/siegelings.html`, a single self-contained file (used for the hosted page).
If the browser blocks mouse lock (e.g. inside a sandboxed frame), hold a mouse button and drag to look.

Progress is saved to the browser's `localStorage`. To start over, open Help and choose **Reset save**.

## The game loop

**Runs.** Walk into the Expedition Gate in front of your base, pick a stage (one per biome) and a starting Siegeling from your collection. Wild Siegelings of that biome's elements swarm you. You only move and jump; your team attacks automatically.
- **Team of 6.** Each Siegeling is a weapon with its own attack pattern (15 patterns such as homing bolts, chains, orbiting orbs, ground slams, dashes, beams, mortars, traps and auras). Its element adds an on-hit effect (burn, slow, knockback, poison, life steal...) and uses the TCG weakness chart for bonus damage. Two Siegelings on one team never share a pattern.
- **Chests** appear over time and drop from elites. They open the moment you touch them and offer 1 of 3 Siegelings to recruit.
- **Totems** (6 per arena, purple diamonds on the minimap) need you to stand beside them for 5 seconds. They give better loot: Rare and Epic recruits, or +2 levels on a Siegeling or item, plus a 25 HP heal.
- **Hazards** are themed per biome: static zones (lava, thorns, black ice, quicksand, whirlpools, static fields, shadow pools), telegraphed strikes that land near you and also hurt enemies, and wandering twisters that throw you into the air. Jumping or standing on high ground avoids ground zones.
- **Arenas** are about 2.5 times larger in area than before (radius 182 to 205 studs), with more plateaus, spires and jump pads to match.
- **Level-ups** come from XP gems: upgrade a Siegeling (it evolves along its TCG line at levels 3 and 6) or take one of up to **6 items** (attack speed, damage, movement speed, max HP, regen, armor, pickup range, crit, area, coins, and a damage core per element).
- **Hit feedback.** Every hit shows a damage number (gold for crits, green when the element is strong against the target), a flash, element particles and a small shove. Shots use swept collision so they can't skip through enemies at low frame rates, and attacks don't reach through ledges. After an enemy hits you, you get 0.3 seconds before another contact hit can land.
- **High ground.** Each arena has tiered plateaus (every tier is one jump high), tall spires and jump pads that launch you onto them. Enemies have to climb ledges slowly, so height buys you time, and nearly half of the timed chests appear on top of a structure.
- Survive 5 minutes, then beat the biome's Legendary boss.

**Base.** Between runs you return to your base with the coins you earned. Recruited Siegelings join your collection and can be stationed on income pads or the Battle Team grid, and coins buy new floors.

The code for runs is in `src/run.js`. Sections below about roaming wild creatures, capturing and raids describe the earlier open-world version; that code is still present but no longer used.

## Controls

| Input | Action |
|---|---|
| `W A S D` / `Shift` / `Space` | Move / sprint / jump |
| Mouse | Over-the-shoulder camera (click the game to lock the pointer) |
| Right mouse (hold) | Aim: closer camera, narrower FOV |
| `Q` | Swap shoulder |
| Left mouse / `F` | Energy orb (ranged, light aim assist) / melee swing |
| `E` | Interact: capture a fainted creature, use a base pad, Base Core, teleporter, or hub NPC |
| `Tab` / `I` | Siegelings inventory and assignment |
| `B` | Base Core panel (floor upgrades and slots) |
| `M` / `H` / `?` | World map / teleport home / help |

## Features

**Open world.** The layout matches the Roblox map (`GameConfig.BiomeZone`):
- The Arena Hub sits in the centre.
- Eight base plots ring the hub.
- Four roads (Electric, Cave, Wet, Desert) lead out to the four outer dual-element biomes: Electric Peaks (Lightning + Light), Shadow Caverns (Shadow + Metal), Ocean Shallows (Water + Poison) and Sunscorch Desert (Psychic + Undead).
- Four inner wedge biomes sit between the roads: Earth Forest, Volcanic Wastes, Frozen Tundra and Wind Highlands.

Each biome has SpawnPoints, DungeonPoints (Rare+ creatures) and a BossPoint (Legendary boss). There is also a day/night cycle. At night, Silver and Gold variants can spawn and 2% of creatures are shiny.

**Creature capturing** (`CaptureSystem`):
1. Knock a wild creature to 0 HP so it faints (10s window).
2. Press `E` to throw a capture card. The cost depends on rarity: Common 10, Uncommon 25, Rare 60, Epic 150, Legendary 400 coins.
3. If you move out of range before the card lands, the capture fails and you get a refund.
4. After a capture you can assign the creature straight away.

Creature behaviours are `aggressive`, `pack`, `lone`, `gentle` and `skittish`, as in `CreatureAI`.

**Assigning** (`AssignToBase`, `AssignToDefense`, `SetFavorite`): every creature can go to an income slot, a defense slot, or become your companion.
- **Income creatures** pay their `baseIncome` every 10s. At night only Shadow and Lightning creatures earn, as in `BaseIncomeSystem`.
- **Defense creatures** shoot raiders and gain passive XP.
- **The companion** follows you and fights your target.

You can assign from the inventory, the Base Core, or by walking up to a pad on your base and pressing `E`.

**Battle Team** (`BattleTeamSystem`): a 3x3 grid on Floor 2 holds up to 5 creatures (`MaxBattleTeamCreatures`). It unlocks with Floor 2, and the Base Core shows active element and class synergies (`CreatureData.Synergies`). Arena battles themselves are not built yet.

**Base upgrades** (`BuyFloor`): Floor 2 (500 coins, Lv 5), Floor 3 (5,000, Lv 10) and Floor 4 "Siegelord Arena" (25,000, Lv 25). Each floor adds 6 income and 6 defense pads and appears stacked on your plot. Teleporter pads move you between floors. The next locked floor shows as a hologram with its price. Wild raids (`AIRaidSystem`) attack your base every few minutes and steal coins unless your defenders stop them. Defeated raiders can be captured.

**Central area (Arena Hub)**: a safe zone with:
- a healing fountain that restores your HP and revives your companion
- the Arena ring
- **The Curator**, who sells six rotating Silver or Gold creatures
- **Siege Master**, who sells XP food you can feed to a creature
- **The Broker**, who buys creatures for coins

## Code map

| File | Roblox counterpart |
|---|---|
| `src/data/creatures.json`, `public/art/` | Generated by `tools/sync_tcg_roster.py` (`npm run sync-tcg`): TCG roster + overlay art, merged with `CreatureData.lua` gameplay fields |
| `src/billboard.js` | Card art as camera-facing billboards |
| `src/config.js` | `GameConfigData.lua` values |
| `src/data.js` | `GetEffectiveStats`, XP curves, capture costs, max level by evolution stage |
| `src/state.js` | `PlayerDataManager` (inventory, slots, floors, XP, save) |
| `src/world.js` | Map, biomes, `BiomeZone`, spawn/dungeon/boss points, props |
| `src/creatures.js` | `CreatureSpawner` + `CreatureAI` + AI raids |
| `src/creatureModel.js` | Stand-in models: body shape from class, accessories from element, size from rarity, colour from `primaryColor` |
| `src/player.js` | Player avatar, movement, combat, over-the-shoulder camera |
| `src/companion.js` | `FavoriteCreatureSystem` |
| `src/base.js` | `BasePlacementSystem`, `BaseIncomeSystem` visuals, floors, defense turrets |
| `src/hub.js` | Arena Hub with the Curator, Siege Master and Broker |
| `src/ui.js`, `src/portraits.js` | HUD, minimap and panels; 3D creature portraits |

## Mobile

Phones and tablets get touch controls automatically:
- **Left thumb:** drag anywhere on the left side to move. Push the stick all the way to sprint.
- **Right thumb:** drag to look around.
- **Action buttons:** ⚔️ attack (hold), ⤒ jump, 👊 melee, 🎯 aim toggle.
- **Interact:** tap the on-screen prompt to interact or capture.
- **Menu row:** 🎒 Siegelings, 🏰 Base Core, 🗺️ map, 🏠 home.

On touch devices the attack button locks onto the nearest creature in front of you. Phones also use a lighter render setup: lower resolution, a smaller shadow map and a shorter view distance. In portrait you see a "turn sideways" hint that you can dismiss.

## Roster and art (from the TCG)

The roster follows the **Siegelings TCG** (`SiegelingsGame/SiegelingTCG`): every Siegling card is a creature in the world. Names, elements, rarities, descriptions and evolutions come from the TCG, and so do the starters (the TCG's expedition starters).

Each creature is drawn with its TCG card **overlay art** as an upright billboard that always turns to face the camera. The billboard has:
- a ground shadow
- walk bounce and idle breathing
- mirroring to face the direction it walks
- a fainted pose
- Silver/Gold/Legend tints
- day/night lighting

Gameplay fields the TCG doesn't have (class, behaviour, spawn weights, income, flying...) come from `CreatureData.lua` for creatures both games share. TCG-only creatures get defaults based on rarity, and their colour is sampled from their art.

Refresh from the live TCG at any time:

```bash
pip install pillow
npm run sync-tcg          # or: python3 tools/sync_tcg_roster.py [--input saved.json] [--skip-art]
```

This writes `src/data/creatures.json` and trimmed 512px WebP art to `public/art/`. If an art link fails (an expired Firebase Storage token), the sync keeps the last good copy, or the creature falls back to its procedural stand-in.

Old saves keep working: creatures renamed between the games are mapped to their new ids (e.g. `golor` → `golork`).

## Real Siegelings models

A real 3D model takes priority over the card art. Drop `.glb`/`.gltf` files into `web/public/models/`, named after each creature's `modelName` from `CreatureData.lua` (e.g. `Firsky.glb`). See `web/public/models/README.md` for details.
- Creatures with a file use it everywhere: in the wild, as your companion, on base pads, and in the UI portraits.
- Every other creature keeps its stand-in.
- Sizing follows the Roblox rule in `CreatureModelLoader`: the largest dimension equals `modelDisplaySize` (default 5 studs) × `modelScaleMultiplier`. `modelRotationY` and `modelStandUpAngles` are also applied.
- Clips named `idle` and `walk`/`run` play automatically.

`src/models.js` holds the loader. `buildCreatureModel` in `src/creatureModel.js` swaps the real model in once it has loaded.

## Credits

Particle sprites come from [Pixel Art Atlas 1.4M](https://huggingface.co/datasets/Angais/pixel-art-atlas-1.4m) by Angais, released under CC0 1.0. `tools/build_fx_atlas.py` picks the sprites and writes `src/fxAtlas.js`.
