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

Progress is saved to the browser's `localStorage`. To start over, open Help and choose **Reset save**.

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
| `src/data/creatures.json` | Generated from `CreatureData.lua` by `tools/export_creatures_web.py` (`npm run export-data`), including the `AllocateBaseStats` port |
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

## Swapping in real assets

All creature visuals go through `buildCreatureModel(def, opts)` in `src/creatureModel.js`. To use real models, load a glTF keyed by `def.modelName` there and return the same `{ root, inner, legs, wings, height, radius, hover, animate }` shape. Nothing else needs to change.
