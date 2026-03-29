# Update log / Memory — Last updated: 2026-03-28 19:00

Before committing: refresh this file's top timestamp and add an entry below; add or update `-- Last updated: YYYY-MM-DD HH:MM` at the top of each changed script.

---

## 2026-03-28 19:00
- **MainServer.server.lua**, **IngredientsMenuClient.client.lua** – Cooking mix: new `CraftingMixPlaceAt` RemoteFunction wired server-side; chef slots 1–4 accept **tap after selecting an ingredient** (empty slot places, filled slot replaces/stacks when something is selected, otherwise removes). Non–cook-mode mix list Remove uses real slot indices.

## 2026-03-28 17:30
- **IngredientSpawnSystem.lua** – CookNPC gets a green `Highlight` (`CookNPCHighlight`) so the chef reads clearly in the hub.

## 2026-03-28 17:00
- **IngredientSpawnSystem.lua**, **GameConfigData.lua**, **IngredientsMenuClient.client.lua** – Replaced arena `Campfire` part with hub **CookNPC**: clone `ReplicatedStorage.CookNPC`, place at `Broker + Cooking.CookNPC.OffsetFromBrokerStuds` (raycast Y, `pitch=90` upright, broker-facing), ProximityPrompt “Cook”; retries until Broker exists; client listens for `CookNPC` (+ legacy `ArenaCampfire`) tags.

## 2026-03-28 16:15
- **GameConfigData.lua** – `SiegeMaster.ExtraRotationDegrees` set to `pitch = 90` (same as Curator/Broker) so the Siege Master mesh stands upright instead of lying flat; reset yaw to 0 so facing follows the Broker’s orientation.

## 2026-03-28 15:00
- **SiegeMasterSystem.lua**, **GameConfigData.lua** – Siege Master spawns opposite The Curator: `Broker − ArenaTrader.OffsetFromBrokerStuds` (mirror of Curator’s `Broker + offset`); fallback mirrors spawn-offset when Broker is absent; pre-placed `SiegeMasterNPC` is re-pivoted on init when a spawn frame resolves.

## 2026-03-28 14:30
- **IngredientsMenuClient.client.lua**, **GameConfigData.lua**, **PlayerDataManager.lua**, **IngredientData.lua** – Campfire mix capped at four ingredients: diamond UI shows four slots only; `GameConfig.Cooking.MaxMixIngredients` set to 4 with matching server/normalize defaults and mix header text “3–4 items”.

## 2026-03-28 12:00
- **IngredientsMenuClient.client.lua** – Rebuilt campfire cooking UI: “Master Chef” layout with teal-framed panel, ingredient cards with icon tiles, diamond mix slots (up to five), gold-rimmed rotating “Combine Results” hub, recipe log strip, and responsive larger window in cook mode; ingredient-only (`I`) view keeps the classic bank + mix columns.

## 2026-03-27 14:45
- **CreatureSpawner.lua**, **BadlandsClient.client.lua**, **BadlandsSystem.lua** – Resolved git merge conflicts: kept cave terrain fallback + `CreatureData` outer-biome pairing for dungeon/boss/zone spawns; BadBag HUD uses favorite-card vertical alignment with panel anchored below the button; sacrifice queue rejects both `favoriteUid` and legacy `favoriteCreature`.

## 2026-03-27 12:00
- **BadlandsClient.client.lua** – Moved the BadBag HUD button down by one full control height so it lines up with the favorite card row and stays on-screen; clicking it now opens Sieglinq on the BadBag tab via `HUDToggleMenu` instead of the legacy floating bag panel.

## 2026-03-21 00:59
- **BadlandsSystem.lua** – Restored direct queue-join compatibility after the stricter Broker-only gate likely blocked the existing Badlands teleport path during testing.

## 2026-03-21 00:45
- **BadlandsSystem.lua** – Locked direct `BadlandsQueueJoin` calls behind the Broker contract flow so players now need a validated sacrifice before the server will queue or teleport them.

## 2026-03-21 00:41
- **BadlandsClient.client.lua** – Wired `BadlandsBagUpdate` into the active HUD so the bag button and panel refresh outside extraction, including on run start and when bag state changes.
- **BadlandsSystem.lua** – Added server-side bag serialization/update helpers plus APIs for capturing Badlands creatures directly into the run bag and switching the active bag slot.
- **CaptureSystem.lua** – Routed Badlands captures away from the normal inventory/cost flow and into the Badlands bag pipeline while preserving the regular world capture behavior elsewhere.
- **CaptureClient.client.lua** – Added a Badlands-specific capture success toast so captured creatures no longer open the normal assignment prompt when they are stored in the Badlands bag.

## 2025-03-05 12:05
- **.cursor/rules/update-logging.mdc** – Added Cursor rule: when editing Lua scripts, update UPDATES.md (top timestamp + new entry) and per-file `-- Last updated: YYYY-MM-DD HH:MM` comment.

## 2025-03-05 12:00
- **UPDATES.md** – Created update log (memory file) per Memory File and Update-Tracking Plan. Top timestamp and reverse-chronological entries for codebase integrity.
