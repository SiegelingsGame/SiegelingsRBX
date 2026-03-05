# Performance Optimization Progress Notes

**Started:** 2025-03-02  
**Plan reference:** roblox_game_performance_optimization_fddcc152.plan.md

---

## Completed Changes

### 1. CreatureAI – Exclude list caching ✓
- **File:** CreatureAI.lua
- **Change:** `getCreatureExcludeList()` rebuilt every creature/raycast. Now `getCachedExcludeList()` builds the list once per frame (keyed by `tick()`). Reuses shared `RaycastParams`.
- **Impact:** Reduces O(N²) iterations to O(N) per frame for ~200+ creatures.

### 2. CreatureAI – Animation throttling ✓
- **File:** CreatureAI.lua
- **Change:** Only call `CreatureAnimation.PlayAnimation()` when `animType` differs from `state._lastAnimType`. Preserves crawling orientation fix using `prevAnimType`.
- **Impact:** Skips hundreds of redundant animation calls per frame.

### 3. GameConfigData – MaxWorldCreatures ✓
- **File:** GameConfigData.lua
- **Change:** `MaxWorldCreatures` reduced from 200 to 150. Night bonus (+100) still applies.
- **Impact:** Fewer active creatures and less AI work per frame.

### 4. DayNightCycle – task.wait loop ✓
- **File:** DayNightCycle.lua
- **Change:** Switched from `RunService.Heartbeat` to `task.spawn` + `task.wait(0.1)` loop (~10 Hz).
- **Impact:** Lighting updates 10×/sec instead of ~60×/sec.

### 5. FavoriteCreatureSystem – Merge Heartbeats ✓
- **File:** FavoriteCreatureSystem.lua
- **Change:** Combined companion respawn (water exit) and player carry visual/deliver/drop into one Heartbeat connection.
- **Impact:** One fewer Heartbeat connection; same logic, less overhead.

### 6. PvPBattleClient – Throttle updatePrompt ✓
- **File:** PvPBattleClient.lua
- **Change:** Throttled `updatePrompt()` to ~15 Hz (0.066 s interval) instead of every frame.
- **Impact:** Lower per-frame cost when near other players.

### 7. PlayerCombatClient – Throttle crosshair ✓
- **File:** PlayerCombatClient.lua
- **Change:** Switched from `RenderStepped` to `Heartbeat`; crosshair position updates throttled to ~30 Hz.
- **Impact:** Fewer per-frame updates when aiming.

### 8. wait() → task.wait() ✓
- **Status:** Project already uses `task.wait()`; no deprecated `wait()` calls found.

---

## Skipped (optional / deferred)

- **InventoryUIManager pooling:** Object pooling for cards deferred; do when inventory UI lag is confirmed.

---

## Testing Notes

- CreatureAI: Verify ground raycasts still work (creatures on terrain, no fly-up). Verify crawling creatures reset orientation correctly when stopping.
- DayNightCycle: Confirm day/night transition is smooth; 10 Hz should be imperceptible.
- FavoriteCreatureSystem: Test companion respawn after exiting water; test steal carry visual/deliver/drop.
- PvP/Combat: Test PvP prompt near players; test crosshair when aiming.
- GameConfigData: World should cap at 150 creatures during day; night can reach ~250 with bonus.
