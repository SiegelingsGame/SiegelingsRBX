# Siegelings — Performance & Multiplayer Desync Plan

**Date:** 2026-04-23  
**Author:** perf review via Roblox Studio MCP + static analysis  
**Live place inspected:** Siegelings (active Studio instance)  
**Status snapshot:** edit mode

---

> **Correction v2 (2026-04-23):** v1 of this doc said "delete both `RBX_ANIMSAVES` trees." That would have broken runtime playback. The ModuleScript at `ReplicatedStorage.Modules.CreatureAnimation` uses a **hybrid loader** — `Animation` objects with a cloud `AnimationId` play from the asset id, but animations without an id fall back to their sibling `KeyframeSequence` inside `RBX_ANIMSAVES`. v2 (§ 2.1 and § 7.1 below) replaces the wholesale delete with a surgical strip that only removes `KeyframeSequence` subtrees of already-uploaded animations and keeps the un-uploaded fallbacks intact.

---

## 0) Executive summary

Studio reports **2,274,827 DataModel instances** in the place file (Workspace `150,319`, ReplicatedStorage `866,141`, ServerStorage `843,394`). A healthy live Roblox place at this production stage usually sits at `<500k`. Multiplayer lag, high join times, memory pressure, and client-side desync are all downstream effects of this.

Three root causes dominate; everything else is secondary:

1. `**RBX_ANIMSAVES` backup trees are shipped in the place** (both in `ReplicatedStorage` and `ServerStorage`) — **~1.7 million** `Pose`/`Keyframe`/`KeyframeSequence` instances. 536 of the 595 `Animation` objects in there already have cloud `AnimationId`s, so their `KeyframeSequence` siblings are dead weight. Surgically stripping those recovers roughly 65–75% of the DataModel immediately; the last ~10% comes out after uploading the 59-animation backlog (see § 2.1 / § 7.1).
2. `**Workspace.Biomes.OceanBiome.POI.Folder` contains ~1,056 duplicated "Constant" scripts + 1,056 `TextureConfiguration` ModuleScripts** ("Made by Zeimi — Advanced Texture Management System"). This is a free-model script infection attached to every part that was imported. ~25 MB of duplicated source compiled and replicated per session.
3. `**Workspace.Biomes` physics & render pressure:** 88,745 `BaseParts` (84,792 with `CanTouch=true`), 3,267 **unanchored** parts, 6,206 `UnionOperations`, 27,277 `Weld`/`ManualWeld`, **1,789 dynamic lights** (Point/Spot/Surface), 338 `ParticleEmitter`, 217 `Fire`, 182 `Beam`. OceanBiome alone has 1,161 lights.

The multiplayer **desync** on top of lag is caused by: creature server-owned physics without explicit `SetNetworkOwner`, reliable-only `RemoteEvent` usage for high-frequency cosmetic traffic, and every physics update from the 3,267 unanchored decor parts being replicated to all clients over a saturated link.

---

## 1) Evidence from Studio (MCP)


| Area                                   | Metric                                                   | Value                                             |
| -------------------------------------- | -------------------------------------------------------- | ------------------------------------------------- |
| DataModel                              | Total instances                                          | **2,274,827**                                     |
| Workspace                              | Descendants                                              | 150,319                                           |
| Workspace                              | Parts / MeshParts / Unions / Welds / WedgeParts          | 57,145 / 16,095 / 6,364 / 27,279 / 7,356          |
| Workspace                              | Moving primitives (edit) / Primitives                    | 0 / 90,613                                        |
| Workspace                              | `StreamingEnabled`                                       | `true` (good — but masked by in-repstorage bloat) |
| ReplicatedStorage                      | Descendants                                              | **866,141**                                       |
| ReplicatedStorage                      | `RBX_ANIMSAVES` pose-like instances                      | **857,564**                                       |
| ServerStorage                          | Descendants                                              | **843,394**                                       |
| ServerStorage                          | `RBX_ANIMSAVES` pose-like instances                      | **843,237**                                       |
| Workspace.Biomes                       | Parts w/ `CanTouch=true`                                 | 84,792 / 88,745                                   |
| Workspace.Biomes                       | Unanchored BaseParts                                     | **3,267**                                         |
| Workspace.Biomes                       | Scripts / ModuleScripts                                  | **1,620 / 1,444**                                 |
| Workspace.Biomes.OceanBiome.POI.Folder | Scripts / ModuleScripts                                  | **1,056 / 1,056**                                 |
| Workspace                              | PointLights + SpotLights + SurfaceLights                 | **1,304 + 380 + 105**                             |
| Workspace                              | Fire / Smoke / ParticleEmitter / Beam                    | 217 / 126 / 338 / 182                             |
| Workspace                              | Decals / Textures                                        | 668 / 1,686                                       |
| ReplicatedStorage                      | RemoteEvents / RemoteFunctions                           | 15 / 2 (not the problem)                          |
| ReplicatedStorage                      | `UnreliableRemoteEvent` usage                            | **0**                                             |
| Code                                   | `:SetNetworkOwner(` calls                                | **0**                                             |
| Code                                   | `FireClient` call sites                                  | ~280 across 40 files (heavy but bounded)          |
| Code                                   | `while true do task.wait(…)` polling loops               | 30+                                               |
| Code                                   | `RunService.Heartbeat:Connect` / `RenderStepped:Connect` | 28 distinct                                       |


---

## 2) Tier-1 fixes (do these first — ~80% of the win)

### 2.1 Strip uploaded `KeyframeSequence` subtrees; keep `Animation` objects

- **Context (important — this corrects v1 of the plan):** `CreatureAnimation.lua` at `ReplicatedStorage.Modules.CreatureAnimation` uses a **hybrid loader**. Its own header:
  > "Supports two types of animation objects in the anim folder: 1. Animation (published) — Has rbxassetid:// ID. Used directly. 2. KeyframeSequence (local) — Raw keyframe data saved by the Animation Editor."
  > So we cannot wipe `RBX_ANIMSAVES` as v1 suggested. We can surgically remove the `KeyframeSequence` subtree for every `Animation` that already has a cloud id, and leave the 59 stragglers intact until their assets are uploaded.
- **Scan results (from live place via MCP):**
  - 536 `Animation` objects inside `RBX_ANIMSAVES` with a real `rbxassetid://...` — their sibling `KeyframeSequence` (with nested `Keyframe` / `Pose` / `NumberPose`) is dead weight and carries the bulk of the 857,564 pose-like instances.
  - 59 `Animation` objects inside `RBX_ANIMSAVES` with an empty `AnimationId` — runtime falls back to their sibling `KeyframeSequence`. **Keep these intact** until uploaded.
  - 59 `Animation` objects outside `RBX_ANIMSAVES` (the Roc defaults under `Workspace.Arena.Roc.Animate`) all have cloud ids and are unrelated to this cleanup.
- **Rule:** for every `Animation` whose `AnimationId` is non-empty, destroy the `KeyframeSequence` that lives in the **same parent folder**. Leave the `Animation` in place. Do not touch subtrees of empty-id animations.
- **ServerStorage mirror:** `ServerStorage.RBX_ANIMSAVES` is declared as the **fallback** by `CreatureAnimation.lua`. Treat it as deletable only *after* the audit confirms every id that exists in the ServerStorage copy also exists (with the same id) in the ReplicatedStorage copy. Defer that deletion to the end of Tier-1.
- **Action (staged):**
  1. Snapshot the place file (backup `.rbxl`).
  2. Run the **audit** (§ 7.1) — it prints each animation path, its `AnimationId`, and whether a sibling `KeyframeSequence` exists. Verify the 59 empty-id rows match the expected "not uploaded yet" list.
  3. Run the **safe cleanup** (§ 7.1 part 2). It destroys only the sibling `KeyframeSequence` of animations with a non-empty `AnimationId`, and prints `UPLOAD ME:` for the rest — that's your upload backlog.
  4. Play test (Idle / Move / Attack / Special / Income / Faint across Breezee, Cacty, Pylme, CactyJackedty, including at least one empty-id creature).
  5. After the backlog is emptied (or per-animation, whenever you upload and paste in the new `AnimationId`), re-run the cleanup to finish those entries.
  6. Once the `ReplicatedStorage.RBX_ANIMSAVES` copy is fully `KeyframeSequence`-free for empty-id cases too, delete `ServerStorage.RBX_ANIMSAVES` outright.
- **Estimated impact:** immediate removal of roughly **1.5M** `Pose` / `Keyframe` / `KeyframeSequence` instances (the 536/595 already-uploaded slice across both copies). Remaining **~0.2M** come out as the 59-animation upload backlog is completed. Net: DataModel drops from ~2.27M toward ~0.7M after Tier 1; join time and client memory drop sharply.

### 2.2 Purge the "Made by Zeimi" / TextureConfiguration script swarm

- **Where:** `Workspace.Biomes.OceanBiome.POI.Folder` — 1,056 × `Script Constant` (13,814 chars each) + 1,056 × `ModuleScript TextureConfiguration` (9,820 chars each).
- **Why:** Free-model infection. Every `Part` under that folder carries the same compiled script. The client must compile and memory-hold all of them. Per-script instancing also fires runtime side effects across parts.
- **Action:**
  1. `CollectionService`-free sweep script: iterate `Workspace.Biomes:GetDescendants()`, `Destroy()` any `Script` named `Constant` whose source starts with `"-- Made by Zeimi"`.
  2. Same sweep for `ModuleScript` named `TextureConfiguration`.
  3. Verify no legitimate system names collide (they do not — `script_grep "Made by Zeimi"` confirmed no runtime code refers to them).
- **Estimated impact:** removes ~25 MB of compiled Luau from every client; eliminates per-part ambient scripts; drops server start CPU.

### 2.3 Reset dynamic-light budget in `Workspace.Biomes`

- **Where:** OceanBiome `1,161` lights, ElectricBiome `441` lights + `182` Beams + `112` Smoke, VolcanicBiome `69` lights + `128` emitters + `16` Fire + `12` Smoke, FrozenBiome `27` lights + `151` emitters, HighlandsBiome `40` lights + `104` Fire, CaveBiome `15` lights + `63` Fire, DesertBiome `27` lights + `24` Fire.
- **Why:** Roblox caches and renders a limited number of dynamic lights per frame. Overflow is silently dropped but every light is still evaluated on the client and replicated.
- **Action:**
  1. Target ≤100 active dynamic lights per biome.
  2. For decorative lights (torches, lanterns, neon emitters): set `Enabled = false` by default and flick them on only when a player is inside the biome's streaming radius, or batch by distance using a single Heartbeat throttle.
  3. Replace point-light "glow" with neon material + Bloom where visually equivalent.
  4. Demote `Fire`/`Smoke`/`ParticleEmitter` duplicates (run a dedup pass per biome — 151 emitters in FrozenBiome is 10× reasonable).

### 2.4 Collapse `CanTouch` on static decor

- **Where:** 84,792 of 88,745 biome parts have `CanTouch = true`.
- **Why:** Touch events propagate through engine dispatch even when nothing listens. Static decor (foliage, rocks, benches) should have `CanTouch = false` and `CanQuery = false` wherever raycast-targetable pickability isn't required.
- **Action:** Batch write pass:
  ```lua
  for _, d in ipairs(workspace.Biomes:GetDescendants()) do
      if d:IsA("BasePart") and d.Anchored then
          d.CanTouch = false
          if not d:GetAttribute("Queryable") then d.CanQuery = false end
      end
  end
  ```
  Run once (editor-only) and commit the asset.

### 2.5 Anchor audit on biome decor

- **Where:** 3,267 unanchored parts in `Workspace.Biomes`.
- **Why:** Each unanchored part is a physics body broadcasting transforms to every client every step. Most are certainly decor that shouldn't simulate.
- **Action:** List the unanchored parts per biome; anchor everything that isn't explicitly moving (water surface, flags, boss FX, mount pieces).

---

## 3) Tier-2 fixes (server tick, AI, replication shape)

### 3.1 Creature AI scheduling (`CreatureAI.lua`)

- **Current:** Single `RunService.Heartbeat` iterates every registered creature every frame and calls `updateCreature(...)` (raycast + anim logic).  
- **Change:**
  - Introduce **LOD buckets** keyed by distance to nearest player:
    - `<40 studs`: full rate (every frame).
    - `40–120 studs`: 10 Hz.
    - `>120 studs`: 2 Hz (or suspend entirely if outside all stream radii).
  - Use a rolling index so that at most `N/4` creatures update per frame (fixed work budget per tick). The existing optimization notes already took step 1 (exclude-list caching, anim throttling) — this is the next step.
- **Also:** `GameConfigData.lua` currently has `MaxWorldCreatures = 1000` (line 270) despite the 2025-03 note reducing it to 150. That regressed — cap back to 150 (200 at night with bonus) until AI LOD lands.

### 3.2 Network ownership for AI creatures (desync root-cause)

- **Problem:** `SetNetworkOwner` is **never called** anywhere in the codebase. Roblox auto-assigns physics ownership to whichever player is closest to each unanchored BasePart (including AI rigs). When a creature's `HumanoidRootPart` is physics-owned by Client A and the server `CFrame`-writes it every Heartbeat from `CreatureAI`, Client B sees the creature rubber-banding (Client A's physics and the server's CFrame fight each other).
- **Fix:** After spawning a creature in `CreatureSpawner`, for the rig's root part call:
  ```lua
  root:SetNetworkOwner(nil)   -- pin to server so all clients see identical interpolation
  ```
  Do the same for any server-driven moving decor.
- **Expected result:** creatures stop jittering across clients.

### 3.3 High-frequency cosmetic events → `UnreliableRemoteEvent`

- **Problem:** 0 unreliable remotes in the game. Cosmetic packets (damage-number pops, player-attack FX, creature-hit FX, raid pulses) fight for bandwidth with gameplay-critical packets on the reliable channel, inflating end-to-end latency.
- **Fix:** Convert the following to `UnreliableRemoteEvent`:
  - `Events.PlayerAttackFX`
  - Any "show floating number / particle burst" broadcast
  - Raid kill-feed ticker events
  - Eleminion / Roc facing updates (if replicated)
- **Keep reliable:** Capture, Raid, AssignToBase, IncomeReceived, PvP state — anything the client must observe exactly once in order.

### 3.4 De-fan the per-player loops

- 35 `FireClient` calls in `PvPBattleSystem`, 28 in `MainServer`, 21 in `ArenaSystem`, 24 `GetPlayers()` loops in `FavoriteCreatureSystem`. Audit the hot ones (battle loops, arena round pushes) to ensure they don't broadcast every tick. Use `:FireAllClients` where every client needs the payload; use server-side caching for "only send delta" patterns.
- Consolidate **polling loops** that run at similar rates:
  - `LaserDoorSystem` 0.4s, `ArenaShieldSystem` 0.4s, `ArenaRocSystem.updateRocFacing` 0.15s, `EleminionSystem` 0.15s + 10s. Merge the "NPC facing" loops into a single dispatcher that walks a list of facing jobs; target one `Heartbeat` connection per system-type, not one per NPC.

### 3.5 SavePlayer throttling

- `PlayerDataManager.SavePlayer(player)` is called inside many `pcall` blocks right after inventory mutations (Roc trade, Broker, Capture, …). DataStore writes are expensive and queued. Replace immediate saves with a **dirty flag + 15–30 s coalesced save** (or rely on the existing auto-save loop). Keep an immediate save on `BindToClose`.

---

## 4) Tier-3 fixes (client hygiene)

### 4.1 Merge or throttle per-frame client connections

Identified `RenderStepped`/`Heartbeat` connections that should drop to `Heartbeat`-throttled (≤15 Hz) unless tied to the camera:


| File                                  | Line      | Current                                  | Proposed           |
| ------------------------------------- | --------- | ---------------------------------------- | ------------------ |
| `BuffShopClient.client.lua`           | 323       | `RenderStepped` pulse                    | `Heartbeat`, 10 Hz |
| `InventoryUIManager.client.lua`       | 227, 714  | `RenderStepped` pulse + `Heartbeat` tick | consolidate, 10 Hz |
| `NotificationManager.lua`             | 564       | `RenderStepped` ticker                   | `Heartbeat`, 15 Hz |
| `ArenaRewardUI.client.lua`            | 134       | `RenderStepped` pulse                    | `Heartbeat`, 10 Hz |
| `ArenaBattleSummaryClient.client.lua` | 922, 1441 | two per-frame                            | merge, 10 Hz       |
| `BaseSummaryClient.client.lua`        | 422, 607  | two per-frame                            | merge, 10 Hz       |
| `HUDClient.client.lua`                | 277       | `RenderStepped`                          | only when visible  |
| `NpcHighlightClient.client.lua`       | 164       | `RenderStepped`                          | 15 Hz Heartbeat    |
| `BaseInteractionClient.client.lua`    | 1143      | `RenderStepped`                          | 15 Hz Heartbeat    |
| `ZoneDoorBoardClient.client.lua`      | 437       | per-frame anchor update                  | 10 Hz              |


Follow the pattern already used in `PvPBattleClient` (post-optimization: 0.066 s throttle) and `PlayerCombatClient` (30 Hz).

### 4.2 Avoid `GetDescendants()` in hot paths

Verified hot ones:

- `BasePlacementSystem.lua` — 13 calls across plot rescans. Cache once per plot, refresh on `ChildAdded/Removed`.
- `MainServer.server.lua` lines 863/978/1167 — already inside guarded paths, OK.
- `ElectricBiomeHazardSystem.lua` lines 110/117/617/758 — these iterate biome descendants on spawn. Do it once at init and subscribe to changes instead.
- `LoadingGate.client.lua` 593/611 — one-shot OK.
- `GameplayMusic.client.lua` 367 — `game:GetDescendants()` scan — **replace** with explicit path lookups.

### 4.3 Streaming tuning

`Workspace.StreamingEnabled = true` is already set. With biome cleanup (2.3/2.4) and AI LOD (3.1), reduce `StreamingTargetRadius` to e.g. 384 and `StreamingMinRadius` to 64 so clients load less geometry.

---

## 5) Desync checklist (multiplayer)

Root causes observed:

1. **No server network ownership on AI creatures** → § 3.2.
2. **Physics churn from 3,267 unanchored decor parts** → § 2.5.
3. **Reliable channel saturation** from cosmetic events → § 3.3.
4. **Free-model script swarm injecting side effects per-part** → § 2.2.
5. **Animation replication storm on join** — uploaded-but-still-local `KeyframeSequence` subtrees in `RBX_ANIMSAVES` → § 2.1.
6. `**MaxWorldCreatures = 1000`** causes per-Heartbeat creature-count spikes; multiplied by N clients' replication, it desyncs far-away creatures → § 3.1.

After the fixes, revalidate with:

```lua
-- Run in-game on the server once players are loaded
local Stats = game:GetService("Stats")
print("HB", Stats.HeartbeatTimeMs, "Phys", Stats.PhysicsStepTimeMs,
      "Send", Stats.DataSendKbps, "Recv", Stats.DataReceiveKbps,
      "Instances", Stats.InstanceCount,
      "Moving", Stats.MovingPrimitivesCount, "Prims", Stats.PrimitivesCount)
```

Target after Tier 1+2: `InstanceCount < 500_000`, `HeartbeatTimeMs < 4` on a 6-player server, `DataSendKbps < 150` per client at steady state.

---

## 6) Execution order (recommended)

1. **Backup** — export the current `.rbxl`.
2. **Tier 1** (editing sessions, no runtime code changes):
  1. § 2.1 animation cleanup, **staged**:
    1. Run the audit (§ 7.1 Step A).
    2. Run the safe cleanup on `ReplicatedStorage.RBX_ANIMSAVES` (§ 7.1 Step B). Collect the `UPLOAD ME:` list.
    3. Playtest Idle / Move / Attack / Special / Income / Faint on Breezee, Cacty, Pylme, CactyJackedty (include at least one species from the `UPLOAD ME:` list to confirm the fallback still plays).
    4. Work the `UPLOAD ME:` backlog over time in the Animation Editor; after each batch of uploads, re-run Step B to strip the now-uploadable entries.
    5. When the `UPLOAD ME:` list is empty, run § 7.1 Step C to delete `ServerStorage.RBX_ANIMSAVES`.
  2. Run the Zeimi/TextureConfiguration purge (§ 2.2).
  3. Run the `CanTouch`/anchor/light sweeps (§ 2.3–2.5).
  4. Save & playtest 2-player.
3. **Tier 2** (code PRs):
  1. `CreatureSpawner.lua`: call `rootPart:SetNetworkOwner(nil)` after spawn (§ 3.2).
  2. `GameConfigData.lua`: `MaxWorldCreatures = 150`.
  3. `CreatureAI.lua`: LOD buckets (§ 3.1).
  4. Convert cosmetic remotes to `UnreliableRemoteEvent` (§ 3.3).
  5. De-fan facing and polling loops (§ 3.4).
  6. Throttle `SavePlayer` (§ 3.5).
4. **Tier 3** (client hygiene PR): merge/throttle per-frame connections (§ 4.1), cache hot `GetDescendants` (§ 4.2), streaming tuning (§ 4.3).
5. **Revalidate** with § 5 probe and compare before/after.

---

## 7) Quick, one-shot probe scripts (run in Studio Command Bar)

### 7.1 Animation audit + surgical `KeyframeSequence` cleanup

**Step A — Audit.** Prints every `Animation` under the two `RBX_ANIMSAVES` trees with its id and whether a sibling `KeyframeSequence` exists. Counters at the end tell you how many are safe to strip vs. how many need uploading first.

```lua
local function hasSiblingKFS(anim)
    local parent = anim.Parent
    if not parent then return false end
    for _, sib in ipairs(parent:GetChildren()) do
        if sib:IsA("KeyframeSequence") then return true end
    end
    return false
end

local function audit(root, label)
    if not root then print(("[%s] missing"):format(label)); return end
    local withId, withoutId, strippable = 0, 0, 0
    for _, a in ipairs(root:GetDescendants()) do
        if a:IsA("Animation") then
            local id = tostring(a.AnimationId or "")
            local has = hasSiblingKFS(a)
            if id == "" or id == "rbxassetid://0" then
                withoutId += 1
                print(("[%s] NEEDS UPLOAD  %s  kfs=%s"):format(label, a:GetFullName(), tostring(has)))
            else
                withId += 1
                if has then strippable += 1 end
                print(("[%s] ok            %s  id=%s  kfs=%s"):format(label, a:GetFullName(), id, tostring(has)))
            end
        end
    end
    print(("[%s] totals: withId=%d  withoutId=%d  strippable=%d"):format(label, withId, withoutId, strippable))
end

audit(game.ReplicatedStorage:FindFirstChild("RBX_ANIMSAVES"), "ReplicatedStorage")
audit(game.ServerStorage:FindFirstChild("RBX_ANIMSAVES"),     "ServerStorage")
```

**Step B — Safe cleanup.** Destroys *only* the sibling `KeyframeSequence` of animations with a non-empty `AnimationId`. Leaves empty-id animations (and their keyframe subtrees) untouched so the hybrid loader in `CreatureAnimation.lua` keeps working. Prints an `UPLOAD ME:` list that is your remaining work.

```lua
local function clean(root, label)
    if not root then print(("[%s] missing"):format(label)); return end
    local kfsDestroyed, poseLike, skipped = 0, 0, {}
    for _, a in ipairs(root:GetDescendants()) do
        if a:IsA("Animation") then
            local id = tostring(a.AnimationId or "")
            if id ~= "" and id ~= "rbxassetid://0" then
                local parent = a.Parent
                if parent then
                    for _, sib in ipairs(parent:GetChildren()) do
                        if sib:IsA("KeyframeSequence") then
                            poseLike += #sib:GetDescendants() + 1
                            sib:Destroy()
                            kfsDestroyed += 1
                        end
                    end
                end
            else
                table.insert(skipped, a:GetFullName())
            end
        end
    end
    print(("[%s] destroyed %d KeyframeSequences (~%d instances). %d animations need upload:")
        :format(label, kfsDestroyed, poseLike, #skipped))
    for _, s in ipairs(skipped) do print("  UPLOAD ME:", s) end
end

clean(game.ReplicatedStorage:FindFirstChild("RBX_ANIMSAVES"), "ReplicatedStorage")
-- Only run on ServerStorage after you have confirmed the ReplicatedStorage copy is authoritative:
-- clean(game.ServerStorage:FindFirstChild("RBX_ANIMSAVES"), "ServerStorage")
```

**Step C — Retire the ServerStorage mirror.** Once Step B has been re-run after every `UPLOAD ME:` is cleared (or you have verified the ReplicatedStorage copy alone satisfies `CreatureAnimation.lua` at runtime), delete the ServerStorage mirror entirely:

```lua
local mirror = game.ServerStorage:FindFirstChild("RBX_ANIMSAVES")
if mirror then mirror:Destroy() end
```

### 7.2 Zeimi / TextureConfiguration purge

```lua
local destroyed = 0
for _, d in ipairs(workspace.Biomes:GetDescendants()) do
    if d:IsA("Script") and d.Name == "Constant"
       and string.sub(d.Source, 1, 40):find("Made by Zeimi") then
        d:Destroy(); destroyed += 1
    elseif d:IsA("ModuleScript") and d.Name == "TextureConfiguration" then
        d:Destroy(); destroyed += 1
    end
end
print("Purged", destroyed)
```

### 7.3 CanTouch / CanQuery off for anchored decor

```lua
local changed = 0
for _, d in ipairs(workspace.Biomes:GetDescendants()) do
    if d:IsA("BasePart") and d.Anchored then
        if d.CanTouch then d.CanTouch = false; changed += 1 end
        if d.CanQuery and not d:GetAttribute("Queryable") then
            d.CanQuery = false; changed += 1
        end
    end
end
print("Toggled", changed)
```

### 7.4 Find the biggest unanchored offenders

```lua
local Workspace = game:GetService("Workspace")
local sizes = {}
for _, d in ipairs(Workspace.Biomes:GetDescendants()) do
    if d:IsA("BasePart") and not d.Anchored then
        table.insert(sizes, d:GetFullName())
    end
end
print("Unanchored:", #sizes)
for i = 1, math.min(20, #sizes) do print(sizes[i]) end
```

---

## 8) What not to touch yet

- The 15 `RemoteEvent`s / 2 `RemoteFunction`s are fine in count; the problem is *channel choice* and *call frequency*, not the number of endpoints.
- `StreamingEnabled` is already on — keep it on.
- The existing `PERFORMANCE_OPTIMIZATION_NOTES.md` items (CreatureAI exclude cache, anim throttling, DayNight 10 Hz, Favorite Heartbeat merge) are good and should be preserved.

---

## 9) Estimated impact (rough)


| Step                                           | Instance delta                                                                                | Client join time    | Server Heartbeat         | Bandwidth                  |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------- | ------------------- | ------------------------ | -------------------------- |
| § 2.1 Strip uploaded KeyframeSequence subtrees | **~−1.5 M immediate**, remaining **~−0.2 M** after the 59-animation upload backlog is cleared | −60–75%             | —                        | −huge on join              |
| § 2.2 Zeimi purge                              | −2.1 k                                                                                        | −moderate (compile) | small drop               | small drop                 |
| § 2.3–2.5 decor sweep                          | −light / physics                                                                              | small               | **−30–50% physics step** | **−30–60%**                |
| § 3.1 AI LOD + cap to 150                      | —                                                                                             | —                   | **−40–60% Heartbeat**    | −moderate                  |
| § 3.2 SetNetworkOwner(nil)                     | —                                                                                             | —                   | —                        | **removes rubber-banding** |
| § 3.3 Unreliable channel                       | —                                                                                             | —                   | —                        | −latency tail              |
| § 3.4/3.5 loop & save dedupe                   | —                                                                                             | —                   | smooth tail              | small                      |


Net: a realistic target of **<700 k instances immediately after Tier 1 (drops toward <500 k once the upload backlog is cleared)**, **<4 ms server Heartbeat at 6 players**, and **no visible creature desync between clients** after all three tiers ship.