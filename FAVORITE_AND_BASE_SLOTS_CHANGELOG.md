# Favorite & Base Assignment Systems – What Changed Since “2 Summons” Bug

This doc summarizes everything that was changed to fix the broken favorite companion system and base (income/defense) assignment, and what could still be missing if it’s “still not working.”

---

## 1. What You Reported (and when “2 summons” broke things)

- **Favorite:** Can’t set a favorite from inventory; Fav button doesn’t work; favorite doesn’t show as gold; Y button behavior changed.
- **Base assignment:** Only the first income point and first defense point are used; extra creatures don’t go to points 2, 3, …; no green/red tints or INCOME/DEFENSE tags in the inventory UI.
- **Inventory UI:** Buttons (Fav, Inc, Def) not triggering or not updating the list; colors/tags not changing.

So the breakage showed up when you had multiple creatures/summons (e.g. “2 summons”) and tried to assign them to income/defense or set a favorite.

---

## 2. Root Causes That Were Fixed

### A. UID type mismatch (string vs number)

- Creature UIDs are strings (`HttpService:GenerateGUID`). After DataStore or client↔server round-trips, the same UID can be string in one place and number in another.
- Code using strict `==` then failed:
  - **SetFavorite** couldn’t find the creature in inventory → favorite never set.
  - **AssignToBase / AssignToDefense** could fail lookups.
  - **Client** couldn’t match `data.baseSlots[i]` / `data.favoriteUid` to `entry.uid` → no green/red/gold tints or badges.

**Fixes:** All UID comparisons were normalized with `tostring()` on both sides in:

- **PlayerDataManager:** SetFavorite, GetFavorite, removeFromAllSlots, GetCreatureByUid, RemoveCreature, TransferCreature, getValidUidSet, countValidFilledSlotsAndSanitize, AssignToBattle, SellCreature, rebirth keep-favorite, GetSlotIndexForUid, MoveCreatureToSlot, MoveCreatureSlot, GetStealableCreatures; and when storing: `d.favoriteUid = tostring(uid)`, `d.baseSlots[slot] = tostring(uid)`, `d.defenseSlots[slot] = tostring(uid)`.
- **InventoryUIManager.client.lua:** mkCard (isBase, isDef, isFav, battle) and income-sum loop use `tostring(u) == tostring(entry.uid)` (and equivalent).
- **BasePlacementSystem.lua:** RefreshOrbByUid and the placement loops that match `data.baseSlots[i]` / `data.defenseSlots[i]` to inventory entries use `tostring(entry.uid) == tostring(uid)`; **PlaceCreatureInSlot** now uses `tostring(entry.uid) == tostring(uid)` when finding the inventory entry so the orb always spawns.

### B. Sparse slot arrays and `ipairs()` (only first slot used)

- **Before:** `normalizeSlotArray` (on DataStore load) built the slot table from `pairs(slots)` and only wrote keys that existed; it also dropped non-string values. So you could get:
  - Sparse tables, e.g. `{[1]="uid1", [3]="uid3"}` with no `[2]`.
  - In Lua, **`ipairs()` stops at the first nil**. So placement and UI only ever saw index 1 → only IncomePoint1 and DefensePoint1 were used.
- **After:**
  - **normalizeSlotArray** now always builds a **dense** array for indices `1 .. MAX_SLOTS` (18): for each `i` it sets `fixed[i]` from `slots[i]` or `slots[tostring(i)]`, defaulting to `""`, and normalizes values with `tostring(v)`. So after load, `baseSlots` and `defenseSlots` are always dense and all slots are visible to `ipairs()` and numeric `for i = 1, maxSlots`.
  - **ensureSlotsDense(slots, maxSlots)** was added and is called at the start of **AssignToBase** and **AssignToDefense**. So in-memory slot tables are always dense (indices 1..maxSlots exist, `""` if empty) even before the first save/load. That way GetInventory, placement, and UI all see every slot.

### C. Stale-UID sanitize on load

- After load, “clear stale slot UIDs” used `validUids[data.baseSlots[i]]` and `validUids[e.uid]` without normalizing type, so valid slots could be cleared when types differed.
- **Fix:** Valid set and lookups use `validUids[tostring(...)]` and `tostring(data.baseSlots[i])` / `tostring(data.defenseSlots[i])`.

### D. Inventory UI: buttons not receiving clicks

- A large transparent Codex button (ZIndex 2) could sit on top of the card and steal clicks.
- **Fix:** Action buttons (Sell, Fav, Inc, Def, Evolve) and the card frame were given explicit ZIndex so buttons (ZIndex 10) are above overlays and always receive clicks.

### E. Y button label

- Per your request, the Y button label was switched to **“Card [CreatureName]”** (and “Card [lastName]” when re-equipping, “No favorite” when none).

### F. Variant used before definition (earlier fix, later reverted then fixed again)

- In mkCard, `variant` was used for the orb stroke before it was defined, so variant strokes could be wrong. The definition was moved so variant is set before the orb block (and the duplicate definition removed).

---

## 3. Files Touched (summary)

| File | Changes |
|------|--------|
| **PlayerDataManager.lua** | UID comparisons → tostring everywhere; normalizeSlotArray → dense 1..MAX_SLOTS; ensureSlotsDense() and call it in AssignToBase/AssignToDefense; store favoriteUid and slot UIDs as tostring(uid); validUids and load sanitize use tostring. |
| **InventoryUIManager.client.lua** | UID comparisons in mkCard and income sum → tostring; Fav/Inc/Def button ZIndex = 10, card ZIndex = 2; Y label “Card [name]”; variant order; refresh delay 0.35s after Inc/Def. |
| **BasePlacementSystem.lua** | RefreshOrbByUid and placement loops: slot UID vs inventory entry with tostring; **PlaceCreatureInSlot** inventory lookup: `tostring(entry.uid) == tostring(uid)`. |
| **MainServer.server.lua** | No logic change; still calls PlayerDataManager.AssignToBase/AssignToDefense and BasePlacementSystem.PlaceCreatureInSlot. |

---

### Full script audit (UID / slot fixes)

Every script that touches baseSlots, defenseSlots, favoriteUid, or UID comparisons was checked and updated so **all** UID comparisons and slot lookups use tostring: PlayerDataManager (AddXP, GetEggByUid, RemoveEgg); MainServer (income tick, GetBattleInfo); BaseIncomeSystem (CalculateIncome, defense XP); HUDClient (computeIncomePerMin); EvolutionCombineSystem (favoriteUid); BasePlacementSystem (RefreshOrbByUid, PlaceCreatures, RespawnBattleCreatures, ClearOrbByUid); InventoryUIManager (assigned set); ArenaSystem (getPlayerIncome, getPlayerBattleTeam); TradeSystem (invHasUid, getOfferDetails, GetPublicProfile); BattleTeamSystem (PlaceTeam, AssignToSlot, RemoveFromTeam, GetTeamData, getTeamCreatureIds).

---

## 4. What Could Still Be Missing (if it’s “still not working”)

1. **PlaceCreatureInSlot inventory lookup**  
   If the orb still doesn’t appear when assigning to income/defense, the last place it could fail was the strict `entry.uid == uid` in **PlaceCreatureInSlot**. That is now `tostring(entry.uid) == tostring(uid)` so the correct creature is found and the orb is spawned.

2. **In-memory slots not dense before first save**  
   New players (or first session) never run normalizeSlotArray until they load from DataStore. So in memory you could have `baseSlots = {[1]=a, [2]=b}` with no `[3]..[6]`. That’s still dense for 1–2, but any code assuming “all indices 1..maxSlots exist” could misbehave. **ensureSlotsDense** at the start of AssignToBase/AssignToDefense fixes that so even the first few assignments see a full 1..maxSlots table.

3. **GetInventory return value**  
   MainServer returns `d.baseSlots` and `d.defenseSlots` directly. After the above changes they are either:
   - Dense from normalizeSlotArray (after load), or  
   - Dense from ensureSlotsDense (after each assign).  
   So the client should always get a table that ipairs and numeric loops can use for all slots.

4. **Remotes / Events**  
   If “AssignToBase” or “AssignToDefense” or “SetFavorite” are missing under ReplicatedStorage.Events, or the client fails to get them (e.g. safeGet returns nil), buttons would do nothing. Worth confirming in Studio that those RemoteEvents exist and that the client is not early-returning due to nil.

5. **Base layout / points**  
   If the plot has only one IncomePoint and one DefensePoint (e.g. only IncomePoint1 and DefensePoint1), then only one income and one defense creature will ever be placed. The code uses `getPointsForOwnedFloors` / `getPointsByPrefix`; if the scene only has one point per type, behavior will look like “only first point used” even though the slot array has multiple entries. So: verify in the Explorer that you have the expected number of points (e.g. IncomePoint1..6, DefensePoint1..6) under the correct folders for the owned floors.

6. **Refresh timing**  
   Client waits 0.35s after Inc/Def and 0.4s after Fav before calling refreshInventory(). If the server or replication is slow, the list could occasionally refresh before the new state is visible. If that’s suspected, try a slightly longer delay or a second refresh after another short delay.

---

## 6. Quick verification checklist

- [ ] ReplicatedStorage.Events has AssignToBase, AssignToDefense, SetFavorite, GetInventory.
- [ ] Plot has multiple IncomePoints and DefensePoints (e.g. 1..6 for Floor1) under the correct floor/folders.
- [ ] After assigning two different creatures to Income, both appear on different green platforms and both show INCOME in the inventory.
- [ ] After assigning two different creatures to Defense, both appear on different red platforms and both show DEFENSE in the inventory.
- [ ] After setting a favorite, that creature’s card shows gold tint and FAVORITE badge and the Y button shows “Card [name]”.
- [ ] Save/load (or rejoin): assignments and favorite persist and still show correctly.

If it’s still only using the first income and first defense point after these changes, the next place to look is the **scene**: confirm that the plot model actually has multiple IncomePoint and DefensePoint parts and that `getPointsForOwnedFloors` / `getPointsByPrefix` returns more than one point per type for the player’s owned floors.
