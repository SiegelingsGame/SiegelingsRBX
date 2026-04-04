# Codex UI (Dual-Mode + 3D Viewer)

Pokédex-style creature panel with **(1) Details** view and **(2) Visual Codex** grid. Click a creature’s icon or name anywhere to open the Codex (Details). Switch to the Visual Codex tab for a scrollable gallery with filters.

## Files changed / added

| File | Change |
|------|--------|
| **GameConfig.lua** | `ENABLE_CODEX_UI`, `ENABLE_CODEX_3D_VIEWER` flags. |
| **CodexModelViewer.lua** | **New** – Reusable 3D viewer (ViewportFrame, orbit drag, wheel zoom, auto-rotate). Place in `ReplicatedStorage.Modules`. |
| **CodexClient.lua** | Dual-mode: Details \| Visual tabs, controller state, Details view with 3D viewer or placeholder, Visual grid with filters (element, rarity, search), lazy viewer pool, Prev/Next, “Visual Codex” button, seen/owned overlays. |
| **InventoryUIManager.lua** | Creature click overlays fire `OpenCodex(creatureId)` when `ENABLE_CODEX_UI` is true. |

## Feature flags

In **GameConfig.lua**:

```lua
GameConfig.ENABLE_CODEX_UI       = true   -- Master switch: Codex panel and creature-click behavior
GameConfig.ENABLE_CODEX_3D_VIEWER = true  -- Use interactive 3D model viewer; if false, placeholder only
```

- **ENABLE_CODEX_UI = false** – Codex and creature-click behavior off (event still exists so no errors).
- **ENABLE_CODEX_3D_VIEWER = false** – Details and Visual grid use colored placeholders only; no ViewportFrame.

## Behavior

- **Details**: One creature – name, element, rarity, description, stats, abilities, 3D preview (or placeholder). Prev/Next, “Visual Codex” button. Drag in viewer to rotate, wheel to zoom.
- **Visual Codex**: Scrollable grid of all (filtered) creatures. Filters: Element (All / Fire / Ice / …), Rarity (All / Common / …), Search by name. Click a cell to open Details for that creature. Scroll position is preserved when switching back. Seen/owned overlay on cells (dimmed “lock” if not seen and not owned).
- **3D viewer**: Reusable **CodexModelViewer** – orbit (drag), zoom (wheel), optional auto-rotate. Used in Details (auto-rotate off) and in gallery cells (pool of 8, auto-rotate on for visible cells). Missing meshes show a placeholder; no runtime errors. **Load by Asset ID**: In Details view, enter a Roblox asset ID (e.g. 257489726) and click "Load Model" to preview any catalog model in the viewer. Switching creatures restores the creature model.

## Adding a new creature

1. **CreatureData.lua**  
   Add an entry to `CreatureData.Creatures` with at least:
   - `id`, `displayName`, `rarity`, `element`, `class`
   - `health`, `attack`, `defense`, `speed`
   - `description` (optional)
   - `primaryColor` (for placeholder)
   - `modelName` (optional; for 3D viewer)

2. **That’s it**  
   Codex uses `CreatureData.GetById` / `GetAll()`. New entries appear in both Details and Visual Codex automatically.

## Why am I only seeing colored circles? (How to activate 3D meshes)

You need **all three** of these in place for 3D models to show instead of placeholders:

1. **Feature flag**  
   In **GameConfig.lua** set:
   ```lua
   GameConfig.ENABLE_CODEX_3D_VIEWER = true
   ```

2. **CodexModelViewer module in the game**  
   The script must live in **ReplicatedStorage** → **Modules** as a **ModuleScript** named exactly **`CodexModelViewer`** (same name as the file without `.lua`).  
   - In Studio: ReplicatedStorage → Modules → right‑click → Insert Object → ModuleScript → rename to `CodexModelViewer`, then paste the contents of `CodexModelViewer.lua`.  
   - If this module is missing or named differently, the Codex falls back to placeholders and does not error.

3. **Creature models in ReplicatedStorage**  
   - In **ReplicatedStorage**, create a **Folder** named exactly **`CreatureModels`** (same folder your spawner uses).  
   - Inside it, add a **Model** (or **MeshPart**) for each creature. The **name** of that instance must match the creature’s **`modelName`** in **CreatureData** (e.g. `Cinders`, `Chillpuff`, `Scaldrat`).  
   - The viewer clones `ReplicatedStorage.CreatureModels[data.modelName]`. If the folder or a matching name is missing, that creature shows the colored circle placeholder.

**Quick check:** If world spawns already use custom models from `ReplicatedStorage.CreatureModels`, the same setup will work for the Codex as long as (1) and (2) above are done.

## Adding meshes so they appear in the 3D viewer

1. In **ReplicatedStorage**, ensure a folder **CreatureModels** exists.
2. Add a **Model** (or **MeshPart**) as a child named exactly **`modelName`** (e.g. `Cinders`, `Chillpuff`). Same name as the creature’s `modelName` in CreatureData.
3. The viewer clones from `ReplicatedStorage.CreatureModels[data.modelName]`, strips scripts, anchors parts, and centers the model. If the model is missing, a colored placeholder (sphere with `primaryColor`) is shown and no error is thrown.

## Opening the Codex from other scripts

```lua
local playerGui = player:WaitForChild("PlayerGui")
local openCodex = playerGui:WaitForChild("OpenCodex")
if openCodex and openCodex:IsA("BindableEvent") then
    openCodex:Fire("cinders")
end
```

All creature clicks should go through `OpenCodex(creatureId)`.

## Architecture (short)

- **Controller state**: `currentCreatureId`, `currentMode` (DETAILS \| VISUAL), `visualScrollPosition`, `seenCreatureIds`, `ownedCreatureIds` (from GetInventory).
- **CodexModelViewer**: Options include `autoRotate`, `zoomEnabled`, `rotateSpeed`, `zoomSpeed`, `minZoom`, `maxZoom`. `SetCreature(creatureId)` mounts model or placeholder; `SetCreature(nil)` clears. `LoadModelByAssetId(assetId)` loads any Roblox catalog model via InsertService for preview. Used in Details (one instance) and in Visual grid (pool of 8, assigned to visible cells on scroll).
