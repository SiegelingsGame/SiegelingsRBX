# Base Exterior Shop – Testing Haunted House

## What Was Added

- **Cosmetic Shop → "Base Exteriors" tab**  
  Same UI as trails/auras/names; lists purchasable base themes (e.g. Haunted House).

- **Config** (`GameConfigData.lua`):  
  `GameConfig.BaseExteriorItems` – e.g. `{ id = "HauntedHouse", name = "Haunted House", desc = "...", coinCost = 500, gemCost = 0 }`.

- **Player data**:  
  `exterior.owned` and `exterior.equipped`.  
  **Buy** = add to owned and spend coins/gems.  
  **Equip** = set equipped theme and **rebuild the player’s current plot** with that theme’s generator (e.g. `HauntedHouseBaseGenerator`).

- **Remotes**:  
  `BuyExterior` (exteriorId, currency), `EquipExterior` (exteriorId or nil to unequip).

---

## How to Test Haunted House

### 1. Prerequisites in Roblox Studio

- **ServerScriptService** (or same location as your scripts):
  - `BaseExteriorSystem` (ModuleScript)
  - `HauntedHouseBaseGenerator` (ModuleScript)
  - `BaseBuildInstructions_HauntedHouse` (ModuleScript) – optional, used by BaseExteriorSystem for instructions.
- **ReplicatedStorage.Modules**:
  - `GameConfig` / `GameConfigData` (so `GameConfig.BaseExteriorItems` exists).
- **MainServer** (or your main server script) creates `BuyExterior` and `EquipExterior` remotes and runs the handlers that call `PlayerDataManager` and `BaseExteriorSystem.BuildPlot`.

### 2. Give yourself coins (if needed)

- Ensure the player has at least **500 coins** (default Haunted House cost), or change `coinCost` in `GameConfig.BaseExteriorItems` for testing.

### 3. Have a plot assigned

- Player must have a **plotId** (e.g. join and let the server auto-assign a plot, or use Select Plot flow).
- `Workspace.BasePlots` should exist; the plot may be created by your existing base placement system or be missing until first “Equip”.

### 4. Open the Cosmetic Shop

- Press **C** (or use the HUD button that opens **CosmeticShopGUI**).

### 5. Open the “Base Exteriors” tab

- Click the **Base Exteriors** tab in the cosmetic shop.

### 6. Purchase “Haunted House”

- Click the **500** (coins) button on the Haunted House row.
- You should see “Purchased Haunted House!” and the row should show **Equip**.

### 7. Equip Haunted House (rebuild base)

- Click **Equip**.
- Server will:
  - Set `exterior.equipped = "HauntedHouse"`.
  - Find your current plot in `Workspace.BasePlots` (e.g. `Plot1`).
  - Store its position, destroy the old plot model, then call `BaseExteriorSystem.BuildPlot(plotId, position)`.
- **HauntedHouseBaseGenerator** builds the full Haunted House layout (3 floors, walls, stairs, defense/income/battle points, lanterns) at that position.
- You should see “Equipped Haunted House (base rebuilt)” and your base should now be the Haunted House structure.

### 8. Unequip (optional)

- In Base Exteriors tab, click **Unequip** on the Haunted House row.
- This only clears `exterior.equipped`; it does **not** delete or change the plot model again. The plot stays as the last built theme until you equip another exterior (which would rebuild again).

### 9. If the plot didn’t exist before Equip

- If the player had a `plotId` but no plot model in `BasePlots` yet, the equip handler still runs and calls `BuildPlot(plotId, position)` with `position = (0,0,0)`. So the Haunted House will appear at the origin. You may want to ensure a plot is created (e.g. by your placement system) before testing Equip, or adjust the server logic to use a default position when no existing plot is found.

---

## Quick Checklist

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open Cosmetic Shop (C) | Panel opens |
| 2 | Click “Base Exteriors” tab | List shows “Haunted House” (500 coins) |
| 3 | Click 500 (buy) | “Purchased!”; button becomes “Equip” |
| 4 | Click “Equip” | “Base rebuilt!”; plot in world becomes Haunted House |
| 5 | Go to base / teleport home | See 3 floors, walls, stairs, points, lanterns |

---

## Adding More Exteriors

1. In **GameConfigData.lua**, add another entry to `GameConfig.BaseExteriorItems`:
   - `id` = theme key (e.g. `"Castle"`).
   - `name`, `desc`, `coinCost`, `gemCost`.
2. On the server, when handling **Equip** for that `id`, call the matching generator (e.g. a future `CastleBaseGenerator.BuildPlot(plotId, position)`). Right now only **HauntedHouse** is wired via `BaseExteriorSystem.BuildPlot` (which uses `HauntedHouseBaseGenerator`). You can extend the equip handler to switch by `exteriorId` and call different generators.

---

## Files Touched

- **GameConfigData.lua** – `BaseExteriorItems`.
- **PlayerDataManager.lua** – `exterior` in default data; `GetExterior`, `OwnsExterior`, `PurchaseExterior`, `SetEquippedExterior`.
- **CosmeticShopClient.lua** – “Base Exteriors” tab; `playerExterior`; buy/equip/unequip with `BuyExterior` / `EquipExterior`.
- **MainServer.lua** – `BuyExterior` / `EquipExterior` remotes and handlers; `getInventory` now returns `exterior`.
- **BaseExteriorSystem.lua** – unchanged; already has `BuildPlot` that calls `HauntedHouseBaseGenerator.BuildPlot`.
- **HauntedHouseBaseGenerator.lua** – unchanged; builds the full plot.

Use this flow to verify the cosmetic shop section for purchasing base exteriors and that equipping Haunted House runs the generator and replaces the plot correctly.
