# Companion Rotation – Full Review & Plan

## Current State (Broken)

1. **Facing backwards**: Cacty, Breezee, and most companions face away from the player instead of toward them.
2. **Crawling introduced complexity**: FIX #15 added branching for Sundile/Abysscrawler that complicated the rotation flow.
3. **Multiple code paths**: Different creatures now use different defaults (COMPANION_ROTATION_DEFAULT, COMPANION_UPRIGHT_DEFAULT, COMPANION_STAND_UP_ANGLES, CreatureData), and the 180° Y facing correction was removed from the new paths.

---

## Root Cause Analysis

### How orientation works

- **Behavior loop**: `rotCf = CFrame.lookAt(newPos, targetFlat) * rotOffset`
- **lookAt**: Creates a CFrame where `-Z` points at the target (player/attack target).
- **rotOffset**: Multiplied on the right → applied in local space after lookAt.

### Facing convention

- Most Blender/FBX models use **+Z as forward**.
- After `lookAt`, `-Z` points at the player → model faces away.
- **180° Y** flips `+Z` and `-Z`, making the model face the player.
- The original `COMPANION_ROTATION_DEFAULT` included `CFrame.Angles(0, math.rad(180), 0)` for this reason.

### What changed today

1. **COMPANION_UPRIGHT_DEFAULT**: Switched from `CFrame.Angles(0, 180, 0)` to `CFrame.identity` → removed facing fix.
2. **COMPANION_STAND_UP_ANGLES**: Removed `* CFrame.Angles(0, 180, 0)` from the return → Cacty lost facing fix.
3. **Crawling path** still uses `COMPANION_ROTATION_DEFAULT` (includes 180° Y), but non‑crawling creatures no longer get it.

---

## Plan

### 1. Centralize facing correction

Introduce a single constant used by all companion rotation paths:

```lua
-- Most models export +Z forward; lookAt uses -Z at target. 180° Y corrects facing.
local COMPANION_FACING_CORRECTION = CFrame.Angles(0, math.rad(180), 0)
```

### 2. Fix all rotation paths

Apply `COMPANION_FACING_CORRECTION` at the end of `getCompanionRotationOffset` for all paths:

| Path | Current | Fix |
|------|---------|-----|
| COMPANION_STAND_UP_ANGLES (Cacty) | `standUp` only | `return standUp * COMPANION_FACING_CORRECTION` |
| COMPANION_UPRIGHT_DEFAULT (Breezee, etc.) | `CFrame.identity` | `return COMPANION_FACING_CORRECTION` |
| fromData (CreatureData) | Use as-is | `return fromData * COMPANION_FACING_CORRECTION` |
| Crawling (Sundile) | COMPANION_ROTATION_DEFAULT (has 180° Y) | Keep as-is (already correct) |
| Fallback | COMPANION_ROTATION_DEFAULT | Keep as-is |

### 3. Simplify crawling interaction

- Crawling creatures use `COMPANION_ROTATION_DEFAULT` (with/without correction).
- That default already contains 180° Y, so no extra facing correction for them.
- Keep the existing crawl logic; only ensure non‑crawling creatures get the facing fix.

### 4. Implementation summary

- Add `COMPANION_FACING_CORRECTION`.
- Apply it to: `COMPANION_STAND_UP_ANGLES`, `COMPANION_UPRIGHT_DEFAULT`, and `fromData`.
- Do not apply it to the crawling path or fallback (they already include it via `COMPANION_ROTATION_DEFAULT`).
