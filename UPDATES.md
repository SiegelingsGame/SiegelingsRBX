# Update log / Memory — Last updated: 2026-03-27 14:45

Before committing: refresh this file's top timestamp and add an entry below; add or update `-- Last updated: YYYY-MM-DD HH:MM` at the top of each changed script.

---

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
