# Update log / Memory — Last updated: 2026-04-20 17:00

Before committing: refresh this file's top timestamp and add an entry below; add or update `-- Last updated: YYYY-MM-DD HH:MM` at the top of each changed script.

---

## 2026-04-20 17:00
- **FavoriteCreatureSystem.lua** — **`GetCompanionRespawnRemainingSeconds`** exposes faint-respawn cooldown for UI.
- **MainServer.server.lua** — **`GetInventory`** returns **`companionRespawnRemainingSec`** (seconds remaining, or **0**).
- **InventoryUIManager.client.lua** — Favorite card shows **`Fainted — Xs · [name]`** (muted red text) instead of **`ReCard`** while the companion is on faint cooldown; **`CompanionFainted`** + Heartbeat keep the countdown fresh.

## 2026-04-20 16:00
- **TopRightBadgeTray.lua** (new) — Shared **`ScreenGui`** + right-aligned **`UIListLayout`** row; **`Order`** table assigns **`LayoutOrder`** (higher = closer to the right edge; strip grows left toward center).
- **BuffShopClient**, **ArenaBattleSummaryClient**, **BaseSummaryClient**, **HUDClient** (dungeon), **InventoryUIManager** (base raid), **AchievementUnlockBadge**, **MusicMuteBadge**, **ArenaRewardUI** (watch) — crest/buff/utility icons parent into the tray instead of overlapping manual ticker offsets.
- **NotificationManager.lua** — **`ToastContainer`** anchored **top-right** (`AnchorPoint` 1,0), narrower width, vertical list **right-aligned**; **`KillFeed`** shifted down to reduce overlap with the toast column.

## 2026-04-20 14:00
- **BaseSummaryClient.client.lua** — When **`OwnerUserId`** is cleared or no longer matches the local player (leave / new plot), **destroy** the client **`BaseSummary`** billboard and drop **`summaryGuis`** state. Previously the heartbeat loop **`continue`d** on vacant plots without cleanup, leaving owner name + stat text floating over the old slot.
- **MainServer.server.lua** — **`setPlotSignState`** updates **every** **`BillboardGui`** / **`SurfaceGui`** under **`SignPart`** (not only the first of each type), so **`resetPlotWorldState`** / **`refreshAllPlotSigns`** fully clear duplicated sign templates.

## 2026-04-20 13:00
- **PlayerDataManager.lua** — **`OnPlayerLeave`** defers **`claimedPlotIds`** release, **`plotId = 0`**, save, and **`playerCache`** clear so **`PlayerRemoving`** handlers registered later (**BasePlacementSystem**, **`MainServer`** plot reset) still get **`GetData`** / **`plotId`** for **`resetPlotWorldState`** and creature cleanup. **`Players:GetPlayerByUserId`** guard skips deferred teardown if the player reconnected before the deferred step (avoids wiping an active session).

## 2026-04-20 12:00
- **BasePlacementSystem.lua** — **PlayerRemoving** no longer bails when **`GetData`** / **`plotId`** are cleared before this handler (`PlayerDataManager.OnPlayerLeave` order). **`findPlotModelForLeavingPlayer`** resolves plot by **`plotId`** first, then **`OwnerUserId`** on the plot model. **`destroyTaggedBaseCreaturesForOwnerUserId`** removes defense/income/battle tagged models with matching **`OwnerUserId`** (orphans / wrong parent). Prevents Siegelings staying on the **previous** plot after rejoin.

## 2026-04-19 19:45
- **BasePlacementSystem.lua** — **`RefreshAllPlotVisibility`** moved to **after** **`normalizeOwnedFloorsForPlacement`** / **`applyOwnedFloorsVisibility`**. Previously it referenced locals **before** their declarations (Lua treats that as **global** → **nil** → `attempt to call a nil value` at line ~327). That threw during **`MainServer.autoAssignAndSetup`** right after **`AssignPlot`**, aborting **`PlaceCreatures`** and **`teleportToBaseReliable`**. Replaced **`continue`** with nested **`if`** for portability.

## 2026-04-19 19:00
- **MainServer.server.lua** — **`nudgeToAssignedBaseXZ`**: **RunService.Heartbeat** for ~**4s** pulls character back to plot if still far from **PlotCenter** (hub **`SpawnLocation`** often wins first frames). **`buyFloor`** dome path uses **`findBasePlotsFolder`** / **`findPlotModelInFolder`**.
- **PlayerDataManager.lua** — **`BuyFloor`** calls **`SavePlayer`** after purchase so **ownedFloors** (e.g. floor 2) persist before next autosave.
- **BasePlacementSystem.lua** — **`floorIndexFromFloorFolderName`** / **`resolveFloorFolder`**: **`Floor 2`**, **`Floor02`**, etc.; **`setFloorVisibility`**, **`getFloorForPart`**, **`getFloorAncestorNum`**, **`getBattlePointMap`**, **`setBattlePointColors`** use it so stairs/Floor2 content toggles match the map.

## 2026-04-19 18:00
- **MainServer.server.lua** — **`findBasePlotsFolder`** + **`findPlotModelInFolder`** (padded names `Plot02`, nested `World/BasePlots`), defined **before** **`refreshAllPlotSigns`** so startup does not index nil. **`teleportToBaseReliable`**: **100× 0.25s** retries + diagnostic **warn** on failure. **`refreshAllPlotSigns`**, **`findPlotModelForPlayer`**, **`setupPlotForPlayer`**, **`teleportToBase`** use shared resolution.
- **LoadingGate.client.lua** — **`findBasePlotsFolderClient`** matches server so **`OwnerUserId`** plots are found when BasePlots is nested.
- **BasePlacementSystem.lua** — Init resolves **Plots** / nested BasePlots; **`findPlotModel`** matches padded names + scan (same as MainServer).

## 2026-04-19 17:00
- **MainServer.server.lua** — **`teleportToBaseReliable`**: retries base teleport for **~8s** (HRP not ready on first frame). Clears **root** linear/angular velocity on move. **`EnsureBaseSpawn`** remote (rate-limited) for client retry pings. Join, death respawn, and home recall use reliable path; **markCriticalReady** still runs after join teleport finishes.
- **LoadingGate.client.lua** — **"Arriving at your base"** no longer gives up at **20s**; uses **`LoadingGateArriveMaxWait`**, **horizontal (XZ) distance** to plot center, **periodic `EnsureBaseSpawn:FireServer()`** while waiting. **MAX_GATE_SECONDS** uses **`LoadingGateAbsoluteMaxSeconds`**. Preload center uses **`getPlotCenterWorldPosition`** (Model PlotCenter).
- **GameConfigData.lua** — **`LoadingGateArriveMaxWait`** (300), **`LoadingGateAbsoluteMaxSeconds`** (330).

## 2026-04-19 16:30
- **MainServer.server.lua** — **`teleportToBase`** (join + death respawn + home recall) required **`PlotCenter`** to be a **`BasePart`**. Maps where **`PlotCenter`** is a **`Model`** (or nested) silently skipped teleport, so players stayed on the hub **`SpawnLocation`**. Added **`getPlotCenterWorldPosition`** aligned with **`LaserDoorSystem`** / **`LoadingGate`** (model pivot, fallbacks).

## 2026-04-19 15:00
- **BasePlacementSystem.lua** — **Floor 2/3/4 visibility after global plot refresh:** `RefreshAllPlotVisibility` (runs on player join/leave) called `setPlotInhabited`, which hides all upper-floor parts; only the owner’s delayed `PlaceCreatures` restored them — other players who owned Floor 2+ lost visibility until rejoin. After the inhabited pass, re-apply each claimed plot’s **`ownedFloors`** via shared **`applyOwnedFloorsVisibility`**. **PlayerDataManager.lua** — **`GetUserIdForPlot(plotId)`** reads `claimedPlotIds` so placement can resolve the online owner.

## 2026-04-19 14:30
- **LaunchScreen.client.lua** — Starter cards: replaced solid-color element orbs with **circular ViewportFrames** via **CodexModelViewer** (`viewportCornerRadius` full circle, themed lighting, no floor) so each starter shows its **3D model** inside the existing rarity-stroked circle.

## 2026-04-19 13:14
- **EleminionData.lua** — Added Eleminion definitions for **dual-zone elements**: Water (Moisty / `WaterEPoint`), Poison (Slimy / `PoisonEPoint`), Metal (Steamy / `MetalEPoint`), Shadow (Umbry / `ShadowEPoint`), Lightning (Zappy / `ElectricEPoint`), Light (Sunny / `LightEPoint`), Psychic (Thinky / `PsychicEPoint`), Undead (Bony / `UndeadEPoint`). Each includes `pointHints` for Studio marker names, biome labels aligned with **CreatureData** zones, and 10-step affinity quests with matching legend-egg rewards.

## 2026-04-19 12:00
- **CreatureAI.lua** — Water-type world creatures treat **Terrain.Material.Water** like Ocean/WaterBlock: **`IsPositionInTerrainWater`**, **`IsPositionInSwimmableWater`**. **`moveTowards`** skips obstacle **raycasts while swimming** (fixes seafloor pinning). Idle snap, flee, wander vertical jitter, swim animation use **swimmable** volume — **only** **`CreatureData.IsWaterType`** uses this path on land vs water.
- **FavoriteCreatureSystem.lua** — Water companion follow also uses **`CreatureAI.IsPositionInTerrainWater`** (with Ocean / WaterBlock / Humanoid Swimming).

## 2026-04-18 23:59
- **AchievementUnlockBadge.client.lua** — New top-left **achievement badge** (same edge pattern as **MusicMuteBadge**): unlocks queue here; **tap** to show **`Notify.RewardPopup`** (same copy/rewards as before). **`DisplayOrder` 49** so **NotificationGUI** popups draw on top. Queue count bubble when **>1**; dedupe by achievement **id**.
- **PlayerProfileClient.client.lua** — Removed immediate unlock popup; profile still refreshes achievement cache/UI on **`AchievementUnlocked`**.
- **default.project.json** — Register **`AchievementUnlockBadge`** under StarterPlayerScripts.

## 2026-04-18 23:58
- **BasePlacementSystem.lua** — **`BattlePointWall`** parts that are **glass safety barriers** (name contains `glass`, **`IsGlass = true`**, or **`Material = Glass`**) stay **`Material.Glass`**, **`Transparency = 1`**, **`CanCollide = true`**. Team-colored **`ForceField`** **`BattlePoint`** / **`BattlePointWall`** shells unchanged. **`setFloorVisibility`** applies full invisibility to those glass barriers instead of **`GLASS_TRANSPARENCY_VISIBLE`**.

## 2026-04-18 23:55
- **FavoriteCreatureSystem.lua** — Steal delivery at base: **`StealHomeRadius`** is now evaluated on **horizontal distance (XZ)** to match walk-back arrival and avoid false “not home” when **PlotCenter** Y differs from the player. **`getPlotCenterPosition`**: if **`PlotCenter`** is missing, fall back to the plot **Model** pivot. Pickup stores victim **XP**; **`AddCreature`** on deliver passes **variant** + **nickname** via **`buildRaidAddContext`**. Companion carry “home” check uses the same **`getPlotCenterPosition` + horizontal** rule.
- **GameConfigData.lua** — Comment on **`StealHomeRadius`** clarified (horizontal XZ).

## 2026-04-18 23:40
- **FavoriteCreatureSystem.lua** — Steal recovery hits: range check uses victim **HumanoidRootPart** vs thief (matches client), melee uses **`PlayerMeleeRange`** (not AoE **`PlayerMeleeRadius`**), slightly wider tolerance for latency.
- **PlayerCombatClient.client.lua** — **`pvpthief_`** melee gate uses **`PlayerMeleeRange`** so “out of range” matches server.

## 2026-04-18 23:25
- **GameConfigData.lua** — Drip Shop: **White Base** / **Black Base** (`exterior_white`, `exterior_black`) and **White Pads** / **Black Pads** (`base_white`, `base_black`); same coin/gem tiers as existing color options.
- **BaseExteriorSystem.lua** — **`THEME_PALETTES`** entries for **`exterior_white`** and **`exterior_black`** (gym points use brighter blues/reds on black foundations).

## 2026-04-18 23:10
- **BaseExteriorSystem.lua** — On first cosmetic pass, store each part’s **original `Enum.Material` value** on attribute **`BaseCosmeticOriginMaterial`**. Unequipping base exterior or base pad tint **restores** that material (premium themes no longer leave Neon/etc. permanently). **`ClearCosmeticOriginSnapshots`** after plot reset for the next owner.
- **MainServer.server.lua** — **`resetPlotWorldState`**: call **`ClearCosmeticOriginSnapshots`** after resetting themes/colors.

## 2026-04-18 22:50
- **LaserDoorSystem.lua** — Shield generator **ProximityPrompt**: set **`KeyboardKeyCode = E`** and **`Exclusivity = AlwaysShow`** so the **[E]** hint appears (matches Knight Base / base orb prompts).

## 2026-04-18 22:35
- **NpcSpawnMarkers.lua** — **`HideSpawnMarkers`**: **BrokerSpawn**, **CookSpawn**, **SiegeSpawn**, **CuratorSpawn** parts (or Models) set to **Transparency = 1** at server start.
- **MainServer.server.lua** — call **`HideSpawnMarkers`** after hub defer, before hub NPC systems init.

## 2026-04-18 22:15
- **NpcSpawnMarkers.lua** — **`ResolvePlacementRelativeToHubSpawn`**: marker position & facing expressed in **HubArea.SpawnLocation** space so slots track the default hub spawn after layout settles.
- **MainServer.server.lua** — one **`HubNpcPlacementDeferSeconds`** wait (with **`GameConfig.HubNpcPlacementDeferSeconds`**) before hub NPC systems init.
- **BadlandsSystem.lua**, **IngredientSpawnSystem.lua**, **SiegeMasterSystem.lua**, **ArenaTraderSystem.lua** — use resolve when **`SpawnLocation`** exists; **fallback** to raw marker if not.

## 2026-04-18 22:10
- **PlayerProfileClient.client.lua** — Profile tab header: purple **LEVEL** pill sits **immediately to the right of the player name** (horizontal row + centered group), not pinned to the panel’s top-right.

## 2026-04-18 21:35
- **ArenaTraderSystem.lua**, **GameConfigData.lua** — **CuratorSpawn**: Y from marker **top + `ArenaTrader.CuratorSpawnRiseStuds`** (default **8** = two 4-stud blocks), not terrain raycast. Tune in config if you want a different lift.

## 2026-04-18 21:20
- **NpcSpawnMarkers.lua** (ReplicatedStorage) — resolve optional hub spawn **BaseParts** by name.
- **BadlandsSystem.lua** — **The Broker** spawns at **BrokerSpawn** when present (moves existing **BrokerNPC** too).
- **IngredientSpawnSystem.lua** — **Cook** uses **CookSpawn**.
- **SiegeMasterSystem.lua** — **Siege Master** uses **SiegeSpawn**.
- **ArenaTraderSystem.lua** — **The Curator** (trader) uses **CuratorSpawn**.
- **default.project.json** — sync **NpcSpawnMarkers** module path.

## 2026-04-18 21:05
- **BaseExteriorSystem.lua** — **Base Plots** palette: **ramp** parts (name contains `ramp`) tint with the same **income** / **defense** colors as carpets and pads (under **Floor2** → defense; otherwise income). Theme still applies first when clearing the palette.

## 2026-04-18 21:00
- **Shop hub** — New **SCoins** and **Gems** entries; taller hub panel. **SCoins shop** (`ScoinsShopClient`): six tiers (**Handful**→**Bank**) buy **SCoins** with **Diamonds** (gems); config `GameConfig.ScoinsGemPacks`. **Gems shop** (`GemsShopClient`): same tier names, **Robux** only via Developer Products (`GameConfig.GemsRobuxPacks`; `EggShopSystem` **ProcessReceipt** grants gems).
- **PlayerDataManager** — **`scoins`** persisted currency; **GetInventory** returns `scoins`; **PremiumCurrencyShop** module + **`BuyScoinsPack`** remote + **`SCoinsUpdate`**.
- **DiamondNeedHint.lua** — Center **RewardPopup** when diamond gem purchases fail: Achievements, Eleminion quests, Shop → Gems. Wired from **Cosmetic**, **Egg** (gems), **Buff** (gems), **SCoins** shop.

## 2026-04-18 20:20
- **CreatureSpawner.lua**, **CreatureData.lua**, **GameConfigData.lua** — Wild spawns: **fill empty SpawnPoint / SpawnPoint2** parts (weighted by element + rarity), **diversity bias** so species already present in the world are less likely to roll again; tunables `SpawnPointCoverageRadius`, `SpawnPointFillPerCycle`, `SpawnPointBurstFillMax`, `SpawnDiversityStrength`.

## 2026-04-18 19:30
- **GameConfigData.lua** — Hub shops: every **Buff**, **Cosmetic**, **Base exterior**, **Base color**, and **Egg** listing now has both **coin** and **diamond (gem)** prices so players can pay with earned gold or premium currency.
- **EggShopSystem.lua**, **EggShopClient.client.lua** — Egg purchases accept **gems** (`InvokeServer(..., "gems")`); UI shows split **Coins | Diamonds** row plus optional Robux when configured.
- **CosmeticShopClient.client.lua**, **CosmeticSystem.lua**, **MainServer.server.lua** — Drip Shop rows show side-by-side coin and diamond buy buttons where both apply; **GemsUpdate** + clearer “diamonds” copy; exterior/base purchases refresh gem balance after diamond spends.

## 2026-04-18 18:45
- **MainServer.server.lua** — Drip Shop: buying a **base exterior** or **base color** now auto-equips it and applies theme/pad colors to the player’s plot immediately (cosmetic trails/auras/name colors already auto-equipped via `CosmeticSystem`).

## 2026-04-18 18:15
- **BaseExteriorSystem.lua** — Four premium base themes: **JungleHut**, **IceFortress**, **VolcanicCavern**, **FloatingPalace** (full palettes + materials, exterior shell). Registered in `PREMIUM_FULL_THEME_IDS`.
- **GameConfigData.lua** — `BaseExteriorItems` shop entries (500 coins each) with names/descriptions.

## 2026-04-18 17:30
- **BaseExteriorSystem.lua** — Only **HauntedHouse** and **RetroArcade** apply palette materials to plot parts. Default theme, **exterior_*** paint themes, Base Plots pad/carpet tinting, gym BattlePoint tint, and pad grey reset change **Color** only so DiamondPlate (and other Studio materials) stay. Removed Grass/Concrete/SmoothPlastic/Fabric overrides from those paths. **GameConfigData.lua** — comment reflects behavior.

## 2026-04-18 17:00
- **BaseExteriorSystem.lua** — With no Base Plots palette equipped, **Carpet1/Carpet2** parts are no longer recolored to green/red defaults; they keep their Studio starter colors. Shop palette still tints carpets when equipped. **GameConfigData.lua** — comment aligned.

## 2026-04-18 16:30
- **BaseExteriorSystem.lua** — Default (no exterior theme): foundations use grass material/color instead of painting the whole plot grey on spawn/reset. Carpet folders excluded from theme passes; shop tints carpets when a Base Plots palette is equipped (see 17:00 for nil palette behavior).
- **BasePlacementSystem.lua**, **MainServer.server.lua** — Always call `ApplyBaseColorToPlot` (including `nil`) after theme so pads refresh when no Base Plots color is equipped.
- **GameConfigData.lua** — Comment updated for Base Color shop scope.

## 2026-04-18 16:05
- **Steal victim vs thief** – Remotes `StealVictimMarkThief` / `StealVictimClearMark`. Victim sees thief highlighted red + overhead “Target to Free (nickname or species name)”; thief slots into the combat target bar (`pvpthief_<userId>`). Victim hits route through **PlayerCombatSystem** (`HandleStealVictimHit`) with `GameConfig.StealVictimHitDamageCap`; **FavoriteCreatureSystem** restores inventory + income/defense slot + `PlaceCreatureInSlot`. **PlayerDataManager.AddCreature** applies optional nickname from context. **MainServer**, **FavoriteCreatureSystem**, **PlayerCombatSystem**, **PlayerCombatClient**, **CaptureClient**, **PlayerDataManager**, **GameConfigData**.

## 2026-04-18 15:45
- **BiomeSkyboxClient.client.lua** — CaveSky is chosen in the cave baseplate vertical column before hub/roads/inner wedges so cave music/sky is not replaced by spoke wedges (e.g. FireSky). Inner-wedge radius now follows `GameConfig.BiomeZone.InnerWedgeMaxRadius`.
- **GameplayMusic.client.lua** — Same cave-column rule for track selection (beats arena proximity and inner-sky mappings); arena position poll also reacts when entering/leaving the cave column.
- **MusicMuteBadge.client.lua** — New top-right badge toggles mute for the gameplay **Music** `SoundGroup` (all Sieglings theme tracks using that group).

## 2026-04-18 14:00
- **CaptureClient.client.lua** – Clicking an enemy’s fainted base (income/defense) creature now sends `StealInteractRequest` like `[E]` instead of `CaptureRequest` (capture only allows `WorldCreature`, which caused “Invalid target”). Tooltip text for stealables updated. **HUDClient.client.lua** – Removed duplicate `CaptureFail` toast; `CaptureClient` already notifies and resets capture UI.

## 2026-04-18 12:00
- **CreatureModelLoader.lua** – `IntegrateTemplate` no longer calls `IsA` on a `Model` template after `Destroy()`; use a `templateWasModel` flag so rigged model loads do not error inside `pcall` and fall back to placeholder orbs.

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
