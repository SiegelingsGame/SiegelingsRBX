# Cursor One-Shot Prompt: Performance, Movement, Collision & Animation Polish
## Siege Monsters — Roblox Game

Paste this entire prompt into Cursor as a single task. Apply all changes across the listed files in one session. Do not stub or skip any section.

---

## Context

This is a Roblox Lua game. Servers run scripts via `RunService.Heartbeat`; clients via `RunService.RenderStepped` / `RunService.Heartbeat`. Creatures are kinematic (position updates, not Humanoid physics). There is NO PathfindingService — movement is direct steering + raycast wall avoidance.

All files are ModuleScripts or Scripts in ServerScriptService / StarterPlayerScripts unless noted.

---

## Problem Areas to Fix

### 1. Creatures freeze and animate in place (do not move)
### 2. Creatures get stuck on walls and parts
### 3. Player collides with objects that should block them (CanCollide issues)
### 4. Choppy / jerky movement and animation transitions
### 5. UI lag — expensive per-frame operations in client scripts

---

## FILE: `CreatureAI.lua`

### Fix 1 — Stuck-detection and wall-sliding

The current `moveTowards()` function casts a single forward raycast for collision avoidance. When a creature hits a wall, it simply stops. Add a proper stuck-detection system and wall-slide escape.

**In the `creatureStates` table entries**, add two new fields when a creature is registered:
```lua
_stuckTimer = 0,      -- accumulated seconds with no position progress
_stuckLastPos = nil,  -- Vector3 last checked position for stuck detection
_stuckEscapeDir = nil -- Vector3 escape direction when stuck
```

**In `moveTowards()` or the per-frame update block that calls it**, after computing the desired position delta but before applying it, add stuck detection:

```lua
-- Stuck detection: if creature hasn't moved more than 0.3 studs in 0.4s, it's stuck
local state = creatureStates[model]
if state then
    if state._stuckLastPos == nil then
        state._stuckLastPos = body.Position
    end
    local moved = (body.Position - state._stuckLastPos).Magnitude
    if moved < 0.3 then
        state._stuckTimer = (state._stuckTimer or 0) + dt
    else
        state._stuckTimer = 0
        state._stuckLastPos = body.Position
        state._stuckEscapeDir = nil
    end

    if state._stuckTimer >= 0.4 then
        -- Generate a random escape direction perpendicular to current heading
        if not state._stuckEscapeDir then
            local angle = math.random() * math.pi * 2
            state._stuckEscapeDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
        end
        -- Override movement direction with escape direction for this frame
        -- (caller should use this to redirect moveStep)
        -- Reset stuckTimer so we get a fresh window after redirect
        state._stuckTimer = 0
        state._stuckLastPos = nil
        return -- skip normal movement this frame; creature will re-evaluate next frame
    end
end
```

**Additionally, add wall-sliding** inside `moveTowards()` where the forward raycast detects a hit:
- When the forward raycast hits a surface, compute the wall normal from the hit.
- Project the desired velocity onto the plane of the wall (slide along it): `slideDir = (desiredDir - desiredDir:Dot(hitNormal) * hitNormal).Unit`
- If `slideDir` is valid (magnitude > 0.01), use it as the movement direction for this frame instead of stopping.
- Cast a secondary raycast in the slide direction to confirm it is clear before committing.

```lua
-- Wall-slide example (add inside moveTowards where forward ray hits):
local hitNormal = rayResult.Normal
local slideDir = (desiredDir - desiredDir:Dot(hitNormal) * hitNormal)
if slideDir.Magnitude > 0.01 then
    slideDir = slideDir.Unit
    -- verify slide path is clear
    local slideRay = workspace:Raycast(
        body.Position + Vector3.new(0, 0.5, 0),
        slideDir * moveStep,
        rayParams
    )
    if not slideRay then
        -- slide is clear — move along wall instead of stopping
        local slidePos = body.Position + slideDir * moveStep
        body.CFrame = CFrame.new(slidePos, slidePos + slideDir) * rotationOffset
        return -- applied slide, done
    end
end
-- If slide is also blocked, don't move (existing behavior)
```

---

### Fix 2 — Freeze/animate-in-place: Wander target re-evaluation

When a creature picks a wander target that ends up inside geometry (e.g., underground or inside a wall), `moveTowards()` returns immediately every frame while the animation plays the Walk loop. The creature never arrives, never re-picks a target. Add a **wander timeout**:

In `creatureStates` entries, add:
```lua
_wanderStarted = 0,   -- tick() when current wander target was set
_wanderTarget = nil,  -- mirrors the current wander Vector3
```

When assigning a new wander target (wherever `state.target` is set for wander behavior), also set:
```lua
state._wanderStarted = tick()
state._wanderTarget = newTarget
```

In the wander update block, add at the top:
```lua
-- Wander timeout: if creature hasn't reached its target in 5s, pick a new one
if state._wanderTarget and tick() - (state._wanderStarted or 0) > 5 then
    state.state = "idle"
    state._wanderTarget = nil
    state._wanderStarted = 0
    return
end
```

Also, when picking a wander target, **validate it is above ground** using a downward raycast from the candidate point before accepting it. Reject and repick if the raycast misses (point is in the air or inside geometry).

---

### Fix 3 — LOD system: ensure animation stops at low-LOD

At LOD level 2 (>120 studs, 2 Hz tick), creatures still run animations client-side. Server should send a `"pause"` animation signal at low LOD and `"resume"` when the creature re-enters high LOD range. For now, at minimum ensure that when `dt` is large (> 0.2s, meaning the creature was skipped for many frames), the position update uses the CLAMPED dt (already done via `math.min(dt, 1/15)`) — verify this clamp is applied to ALL movement math, not just part of it.

Also cap `moveStep` to the creature's physical size to prevent tunneling through thin walls:
```lua
local bodySize = body.Size.Magnitude * 0.5  -- approximate radius
moveStep = math.min(moveStep, bodySize * 0.8)
```

---

### Fix 4 — Per-frame raycast: cache raycast params

`RaycastParams` is currently recreated or reused. Confirm that `rayParams.FilterDescendantsInstances` is set once using `getCachedExcludeList()` and is NOT reassigned every frame. If it is being reassigned, cache it:

```lua
-- At top of per-frame loop, set params once:
local excludeList = getCachedExcludeList()
rayParams.FilterDescendantsInstances = excludeList  -- only if list changed
```

Better: compare list length to last frame's length — only update `FilterDescendantsInstances` if a creature was added or removed.

---

## FILE: `FavoriteCreatureSystem.lua`

### Fix 5 — Cache body lookup (hot path, every frame)

Line ~1256: `CreatureModelLoader.GetBodyPart(comp.model) or comp.model:FindFirstChild("Body")` is called every Heartbeat. Cache it on the companion table at spawn time:

```lua
-- When companion is created / model is assigned:
comp._cachedBody = CreatureModelLoader.GetBodyPart(comp.model) or comp.model:FindFirstChild("Body")
```

Then in the hot loop, replace the FindFirstChild call with:
```lua
local body = comp._cachedBody
if not body or not body.Parent then
    -- model was destroyed, clean up companion
    break
end
```

---

### Fix 6 — Cache terrain water detection (expensive every frame)

The `IsPositionInSwimmableWater()` / `IsPositionInTerrainWater()` calls read terrain voxels every frame. Throttle this check to run at most 10 Hz (every 0.1s):

```lua
-- On companion table:
comp._waterCheckTimer = 0
comp._isInWater = false  -- cached result

-- In hot loop:
comp._waterCheckTimer = (comp._waterCheckTimer or 0) + dt
local isInWater = comp._isInWater
if comp._waterCheckTimer >= 0.1 then
    comp._waterCheckTimer = 0
    isInWater = IsPositionInSwimmableWater(body.Position)
    comp._isInWater = isInWater
end
```

---

### Fix 7 — Cache attack target scan (CollectionService every frame)

When attack mode is enabled, `CollectionService:GetTagged()` is called every Heartbeat. Throttle to 5 Hz (every 0.2s):

```lua
comp._targetScanTimer = 0
comp._nearbyTargets = {}

-- In attack loop:
comp._targetScanTimer = (comp._targetScanTimer or 0) + dt
if comp._targetScanTimer >= 0.2 then
    comp._targetScanTimer = 0
    comp._nearbyTargets = CollectionService:GetTagged(WORLD_CREATURE_TAG)
    -- also merge in BASE_DEFENSE_TAG targets as needed
end
local targets = comp._nearbyTargets
```

---

### Fix 8 — Smooth companion follow speed (reduce choppiness)

When the companion is far from the player, it snaps speed up to catch-up immediately. Apply a tighter lerp to prevent the jolt:

```lua
-- Current (abrupt):
comp._followSpeed = lerp(comp._followSpeed, targetSpeed, CompanionFollowSpeedSmooth * dt)

-- Change: clamp the lerp alpha to prevent over-correction on large dt
local alpha = math.min(CompanionFollowSpeedSmooth * dt, 0.3)
comp._followSpeed = lerp(comp._followSpeed, targetSpeed, alpha)
```

Also ensure that when the companion teleports (e.g., spawns, player teleports), `comp._followSpeed` is reset to 0 rather than inheriting the last frame's value, which can cause the companion to shoot off at full speed the next frame.

---

## FILE: `BasePlacementSystem.lua`

### Fix 9 — Creature CanCollide setup for world collision

When creature models are placed on income/defense points, their parts have mixed CanCollide values. Ensure the following rules are enforced at spawn time and reviewed:

```lua
-- For ALL parts in a placed creature orb/model:
for _, part in ipairs(model:GetDescendants()) do
    if part:IsA("BasePart") then
        if part.Name == "Body" or part.Name == "HitBox" then
            part.CanCollide = false  -- kinematic creatures should NOT block player movement
            part.CanQuery = true     -- still raycasted for HP/targeting
        else
            part.CanCollide = false
            part.CanQuery = false
        end
    end
end
```

**Rationale**: Placed (stationary) base creatures blocking player movement causes the player to get caught on them and feel laggy. They should be walkthrough (CanCollide = false), detectable by raycast (CanQuery = true) for HP bars.

---

### Fix 10 — World creature CanCollide (walking creatures)

In `CreatureAI.lua` RegisterCreature or wherever creature models are set up, apply the same CanCollide=false, CanQuery=true treatment to all creature parts:

```lua
local function setCreatureCollision(model)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false   -- don't block player or other creatures
            part.CanQuery = true      -- allow raycast targeting and HP
            part.Massless = true      -- prevent physics mass interference
        end
    end
end
```

Call `setCreatureCollision(model)` in `RegisterCreature()` after the model is validated.

---

## FILE: `WorldMapClient.client.lua` (and all UI client scripts)

### Fix 11 — Move per-frame player-position update off RenderStepped

The `RenderStepped` connection updates the player's dot on the world map every render frame (~60 fps). This is unnecessary. Move it to a throttled `task.spawn` loop at 10 Hz:

```lua
-- REMOVE:
-- RunService.RenderStepped:Connect(function() updatePlayerDot() end)

-- ADD:
task.spawn(function()
    while true do
        task.wait(0.1)  -- 10 Hz
        if not mapOpen then continue end  -- only update when map is visible
        updatePlayerDot()
    end
end)
```

Apply the same pattern to **any other UI client script** that has `RenderStepped` or `Heartbeat` connections that update labels, positions, or values. If the UI element does not need sub-frame accuracy, move it to a `task.wait(0.1)` loop and guard it with an `if not uiVisible then continue end` check.

---

### Fix 12 — Debounce UI button callbacks

Any `MouseButton1Click` or `Activated` callbacks on shop/menu buttons that open frames should have a `debounce` flag to prevent double-fires (which can cause the UI to open and immediately close, appearing as a lag flash):

```lua
local _uiDebounce = false
button.Activated:Connect(function()
    if _uiDebounce then return end
    _uiDebounce = true
    -- ... open/close logic
    task.delay(0.3, function() _uiDebounce = false end)
end)
```

---

## FILE: All Client Scripts (general animation smoothness)

### Fix 13 — TweenService for UI transitions instead of instant show/hide

For any UI frame that is shown/hidden by setting `Visible = true/false` directly, replace with a short fade tween (0.15s transparency) to eliminate visual pop. Example:

```lua
local TweenService = game:GetService("TweenService")
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function showFrame(frame)
    frame.Visible = true
    frame.BackgroundTransparency = 1
    TweenService:Create(frame, TWEEN_INFO, {BackgroundTransparency = 0}):Play()
    -- also tween child labels if needed
end

local function hideFrame(frame)
    local t = TweenService:Create(frame, TWEEN_INFO, {BackgroundTransparency = 1})
    t:Play()
    t.Completed:Connect(function() frame.Visible = false end)
end
```

Only apply this to the main container frames (shop panels, menus), NOT to HUD elements that must update instantly.

---

## FILE: World Parts / Map Geometry (Workspace setup — script to run in Studio)

### Fix 14 — Ensure player-collidable parts are correctly set

Run this as a one-time Studio Script (or call at server start from `MainServer.server.lua`) to audit and fix CanCollide on workspace parts:

```lua
-- In MainServer.server.lua, add after workspace loads:
local function enforceWorldCollision()
    -- All parts in workspace that are NOT creatures, NOT players, NOT UI anchors:
    -- should have CanCollide = true so players cannot walk through walls/floors.
    -- Creature models are excluded (handled by setCreatureCollision above).
    local creatureTags = {"WorldCreature","BaseDefenseCreature","BaseIncomeCreature","FavoriteCreature"}
    local creatureModels = {}
    for _, tag in ipairs(creatureTags) do
        for _, m in ipairs(CollectionService:GetTagged(tag)) do
            creatureModels[m] = true
        end
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            -- Skip creature parts
            local isCreaturePart = false
            local parent = obj.Parent
            while parent and parent ~= workspace do
                if creatureModels[parent] then isCreaturePart = true; break end
                parent = parent.Parent
            end
            if isCreaturePart then continue end

            -- Skip player characters
            local char = obj:FindFirstAncestorOfClass("Model")
            if char and Players:GetPlayerFromCharacter(char) then continue end

            -- Enforce: non-transparent architectural parts must be collidable
            if obj.Transparency < 0.9 and not obj.Anchored == false then
                obj.CanCollide = true
            end
        end
    end
end

-- Call once after a short delay for all instances to load:
task.delay(3, enforceWorldCollision)
```

**Note**: Review the output of this after running — some intentionally passthrough parts (triggers, sensors) may need to be excluded by Name or CollectionService tag.

---

## Summary of Changes by File

| File | Changes |
|------|---------|
| `CreatureAI.lua` | Stuck detection + escape, wall-slide in moveTowards, wander timeout + target validation, moveStep cap, cache raycast params, CanCollide=false/CanQuery=true for all creature parts |
| `FavoriteCreatureSystem.lua` | Cache body lookup, throttle water detection to 10Hz, throttle target scan to 5Hz, smooth follow speed lerp, reset speed on spawn |
| `BasePlacementSystem.lua` | CanCollide=false/CanQuery=true for all placed orbs |
| `WorldMapClient.client.lua` | Move map dot update from RenderStepped to 10Hz task loop guarded by map visibility |
| All UI client scripts | Debounce button callbacks, TweenService fade for panel show/hide |
| `MainServer.server.lua` | `enforceWorldCollision()` called once at startup after 3s delay |

## Rules
- Do NOT change DataStore, PlayerDataManager, or economy logic.
- Do NOT change animation asset IDs or CreatureData entries.
- Do NOT change the floor gating, plot assignment, or battle/defense systems.
- All timing values (0.1s water check, 0.2s target scan, 0.4s stuck timeout) should be defined as named local constants at the top of each file, not hardcoded inline.
- Add `-- PERF:` comments on every line changed for performance reasons so they are easy to audit.
- Add `-- FIX #20:` comments on every line changed for stuck/collision/animation reasons (continue the existing numbering convention; the last fix in the file is #19).
- Keep all existing `-- FIX #N:` comments intact.
